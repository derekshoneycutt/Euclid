package font

import "../../taskpool"
import fontmodel "model"

import "core:log"
import vmem "core:mem/virtual"

// Display-owned lifecycle of the single optional-font preparation slot.
//
// Retry owns an unsubmitted payload; Queued identifies pool-owned execution/polling;
// Idle guarantees no worker can access task or arena storage.
Font_Prepare_Operation_State :: fontmodel.Font_Prepare_Operation_State
Font_Prepare_Operation_Kind :: fontmodel.Font_Prepare_Operation_Kind
Font_Prepare_Task :: fontmodel.Font_Prepare_Task
Font_Prepare_Operation :: fontmodel.Font_Prepare_Operation

//   Prepare one task-owned font result without touching display resources.
//
// Parameters:
//   - payload: Non-nil `^Font_Prepare_Task` exclusively owned for task execution.
//
// Returns:
//   - `.Succeeded` when a complete arena-backed CPU font was produced; otherwise `.Failed`.
//
// Side effects:
//   - Writes only `task.prepared`; does not call native GPU APIs or mutate the cache.
prepare_task_cancel_requested :: proc(user_data: rawptr) -> bool {
    token := cast(^taskpool.Task_Cancellation_Token)user_data
    return token != nil && taskpool.task_cancellation_requested(token^)
}

// Select the oldest optional raster with bounded pending glyph work.
cache_next_optional_raster_slot :: proc(
    cache: ^Font_Cache) -> fontmodel.Font_Raster_Slot_Selection {
    if cache == nil {
        return {}
    }
    selected_key := Font_Key.Regular
    selected_index := i32(-1)
    selected_tick := max(u64)
    for raster, slot_index in cache.optional_rasters {
        if (raster.state != .Preparing && raster.state != .Resident) ||
            raster.pending_glyph_count <= 0 ||
            raster.page_count >= fontmodel.FONT_GLYPH_PAGE_CAPACITY {
            continue
        }
        if raster.first_pending_demand_tick < selected_tick {
            selected_key = raster.identity.key
            selected_index = i32(slot_index)
            selected_tick = raster.first_pending_demand_tick
        }
    }
    return {key = selected_key, slot_index = selected_index,
        found = selected_index >= 0}
}

//   Prepare one task-owned font result without touching display resources.
prepare_task_execute :: proc(
    payload: rawptr,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    task := cast(^Font_Prepare_Task)payload
    cancellation_token := token
    cancellation := Font_Prepare_Cancellation{
        user_data = &cancellation_token,
        requested = prepare_task_cancel_requested,
    }
    switch task.kind {
    case .Seed:
        if prepare({
            key = task.key,
            generation = task.generation,
            path = string(task.path_storage[:task.path_length]),
            pixel_size = task.pixel_size,
            codepoints = task.codepoints[:task.codepoint_count],
            cancellation = cancellation,
        }, &task.prepared, task.allocator, .Arena) {
            return .Succeeded
        }
    case .Glyph_Page:
        if prepare_glyph_page({
            key = task.key,
            generation = task.generation,
            path = string(task.path_storage[:task.path_length]),
            pixel_size = task.pixel_size,
            glyph_ids = task.glyph_ids[:task.glyph_id_count],
            cancellation = cancellation,
        }, &task.prepared, task.allocator, .Arena) {
            return .Succeeded
        }
    }
    return .Failed
}

//   Copy one source path into task-owned storage for safe asynchronous use.
prepare_task_set_path :: proc(task: ^Font_Prepare_Task, path: string) -> bool {
    if task == nil || len(path) == 0 || len(path) > len(task.path_storage) {
        return false
    }
    copy(task.path_storage[:], transmute([]u8)path)
    task.path_length = len(path)
    return true
}

//   Record optional demand once and activate it when the preparation slot is idle.
//
// Returns:
//   - True for a newly requested optional key; false for Regular, shutdown, nil, or
//     already requested/preparing/ready/failed state.
//
// Side effects:
//   - Advances desired generation and cumulative request telemetry on first demand.
cache_request :: proc(cache: ^Font_Cache, key: Font_Key) -> bool {
    if cache == nil || key == .Regular || cache.shutting_down {
        return false
    }
    entry := &cache.entries[int(key)]
    if entry.state != .Unrequested {
        entry.coalesced_request_count += 1
        return false
    }
    entry.state = .Requested
    entry.request_count += 1
    entry.requested_generation += 1
    cache_begin_next_request(cache)
    return true
}

//   Record a replacement generation while preserving the current resident font.
//
// Returns:
//   - True after scheduling relevant demand; false during shutdown or for a variant
//     that is neither resident nor previously requested.
//
// Side effects:
//   - Advances desired generation, marks requested, and may supersede queued work.
cache_reload :: proc(cache: ^Font_Cache, key: Font_Key) -> bool {
    if cache == nil || cache.shutting_down {
        return false
    }
    entry := &cache.entries[int(key)]
    if !entry.resident && entry.request_count == 0 {
        return false
    }
    entry.requested_generation += 1
    entry.request_count += 1
    entry.state = .Requested
    cache_begin_next_request(cache)
    return true
}

//   Move the oldest recorded optional demand into the single preparation slot.
//
// Notes:
//   - Selection follows `Font_Key` order, not original request timestamp.
//
// Side effects:
//   - Lazily initializes the arena and transitions one entry to Preparing and the
//     operation to Retry; arena failure marks that entry Failed.
cache_next_requested_key :: proc(cache: ^Font_Cache) -> (Font_Key, bool) {
    for entry_index in 0..<FONT_KEY_COUNT {
        if cache.entries[entry_index].state == .Requested {
            return Font_Key(entry_index), true
        }
    }
    return .Regular, false
}

//   Select the first resident generation with unresolved glyph demand.
//
// Returns:
//   - Font key and true when a bounded page can be prepared.
cache_next_page_key :: proc(cache: ^Font_Cache) -> (Font_Key, bool) {
    for entry_index in 0..<FONT_KEY_COUNT {
        entry := &cache.entries[entry_index]
        if entry.resident && entry.state == .Ready &&
            entry.generation == entry.requested_generation &&
            entry.canonical_raster.pending_glyph_count > 0 &&
            entry.canonical_raster.page_count <
                fontmodel.FONT_GLYPH_PAGE_CAPACITY {
            return Font_Key(entry_index), true
        }
    }
    return .Regular, false
}

//   Queue pending demand first and report whether the task owns any demand.
cache_page_task_queue_pending :: proc(
    raster: ^Font_Raster_Instance, task: ^Font_Prepare_Task) -> bool {

    for &glyph, glyph_id in raster.glyphs {
        if glyph.state != .Pending {
            continue
        }
        task.glyph_ids[task.glyph_id_count] = u32(glyph_id)
        task.glyph_id_count += 1
        task.demanded_glyph_count += 1
        glyph.state = .Queued
        if task.glyph_id_count == FONT_GLYPH_PAGE_REQUEST_CAPACITY {
            break
        }
    }
    return task.demanded_glyph_count > 0
}

//   Fill unused page slots with missing face glyphs in glyph-ID order.
cache_page_task_fill_missing :: proc(
    raster: ^Font_Raster_Instance, task: ^Font_Prepare_Task) {

    for &glyph, glyph_id in raster.glyphs {
        if task.glyph_id_count == FONT_GLYPH_PAGE_REQUEST_CAPACITY {
            break
        }
        if glyph.state != .Missing {
            continue
        }
        task.glyph_ids[task.glyph_id_count] = u32(glyph_id)
        task.glyph_id_count += 1
        glyph.state = .Queued
    }
}

// Resolve the canonical or currently preparable optional raster for a page task.
cache_page_task_raster :: proc(
    cache: ^Font_Cache, key: Font_Key,
    raster_slot_index: i32) -> ^Font_Raster_Instance {

    if raster_slot_index < 0 {
        return &cache.entries[int(key)].canonical_raster
    }
    if raster_slot_index >= len(cache.optional_rasters) {
        return nil
    }
    raster := &cache.optional_rasters[raster_slot_index]
    if raster.state != .Preparing && raster.state != .Resident {
        return nil
    }
    return raster
}

//   Copy pending IDs first, then fill the page with deterministic missing IDs.
//
// Returns:
//   - True when at least one glyph ID was transferred to the task.
cache_prepare_page_task :: proc(
    cache: ^Font_Cache, key: Font_Key,
    task: ^Font_Prepare_Task, raster_slot_index := i32(-1)) -> bool {

    entry := &cache.entries[int(key)]
    raster := cache_page_task_raster(cache, key, raster_slot_index)
    if raster == nil {
        return false
    }
    reservation_bytes := u64(fontmodel.FONT_RASTER_PAGE_RESERVATION_RGBA_BYTES)
    if !cache_raster_budget_reserve_with_retirement(
        cache, reservation_bytes, raster_slot_index) {
        return false
    }
    task^ = {
        kind = .Glyph_Page,
        key = key,
        generation = entry.generation,
        raster_slot_index = raster_slot_index,
        raster_slot_incarnation = raster.identity.slot_incarnation,
        rgba_reservation_bytes = reservation_bytes,
        pixel_size = i32(raster.identity.pixel_height),
        allocator = vmem.arena_allocator(&cache.preparation_arena),
    }
    if !prepare_task_set_path(task, cache_source_path(cache, key)) {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, task.rgba_reservation_bytes, false)
        return false
    }
    if !cache_page_task_queue_pending(raster, task) {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, task.rgba_reservation_bytes, false)
        return false
    }
    raster.queued_demand_count = task.demanded_glyph_count
    cache_page_task_fill_missing(raster, task)
    return true
}

//   Start one glyph-page operation in the serialized preparation slot.
cache_begin_page_request :: proc(
    cache: ^Font_Cache, key: Font_Key, raster_slot_index := i32(-1)) {
    if !cache_preparation_arena_init(cache) {
        return
    }
    cache.preparation.state = .Retry
    if !cache_prepare_page_task(
        cache, key, &cache.preparation.task, raster_slot_index) {
        cache.preparation.state = .Idle
        cache.preparation.failure_count += 1
    }
}

// Copy the key's required startup coverage into the seed preparation task.
cache_seed_task_set_codepoints :: proc(task: ^Font_Prepare_Task, key: Font_Key) {
    codepoints := required_seed_codepoints(key)
    copy(task.codepoints[:], codepoints.values[:codepoints.count])
    task.codepoint_count = codepoints.count
}

//   Start one seed-generation operation in the serialized preparation slot.
cache_begin_seed_request :: proc(cache: ^Font_Cache, key: Font_Key) {
    entry := &cache.entries[int(key)]
    reservation_bytes := u64(fontmodel.FONT_RASTER_PAGE_RESERVATION_RGBA_BYTES)
    if !cache_raster_budget_reserve_with_retirement(
        cache, reservation_bytes) {
        return
    }
    if !cache_preparation_arena_init(cache) {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, reservation_bytes, false)
        entry.state = .Failed
        cache.preparation.failure_count += 1
        return
    }
    entry.state = .Preparing
    cache.preparation.state = .Retry
    cache.preparation.task = {
        kind = .Seed,
        key = key,
        generation = entry.requested_generation,
        raster_slot_index = -1,
        rgba_reservation_bytes = reservation_bytes,
        pixel_size = JULIA_MONO_FONT_SIZE,
        allocator = vmem.arena_allocator(&cache.preparation_arena),
    }
    if !prepare_task_set_path(
        &cache.preparation.task, cache_source_path(cache, key)) {
        entry.state = .Failed
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, reservation_bytes, false)
        cache.preparation.state = .Idle
        cache.preparation.failure_count += 1
        return
    }
    cache_seed_task_set_codepoints(&cache.preparation.task, key)
}

//   Move the oldest recorded optional demand into the single preparation slot.
//
// Notes:
//   - Selection follows `Font_Key` order, not original request timestamp.
//
// Side effects:
//   - Lazily initializes the arena and transitions one entry to Preparing and the
//     operation to Retry; arena failure marks that entry Failed.
cache_begin_next_request :: proc(cache: ^Font_Cache) {
    if cache == nil || cache.shutting_down ||
        cache.preparation.state != .Idle {
        return
    }
    key, found := cache_next_requested_key(cache)
    if !found {
        optional_slot := cache_next_optional_raster_slot(cache)
        if optional_slot.found {
            raster := &cache.optional_rasters[optional_slot.slot_index]
            age := cache.raster_request_clock - raster.first_pending_demand_tick
            if age >= fontmodel.FONT_RASTER_DEMAND_AGE_TICKS {
                cache_begin_page_request(
                    cache, optional_slot.key, optional_slot.slot_index)
                return
            }
        }
        page_key, page_found := cache_next_page_key(cache)
        if page_found {
            cache_begin_page_request(cache, page_key)
            return
        }
        fallback_slot := cache_next_optional_raster_slot(cache)
        if fallback_slot.found {
            cache_begin_page_request(
                cache, fallback_slot.key, fallback_slot.slot_index)
        }
        return
    }
    cache_begin_seed_request(cache, key)
}

//   Report whether the active result still targets its owning generation.
//
// Returns:
//   - True for a current seed request or a current published page generation.
cache_preparation_is_current :: proc(cache: ^Font_Cache) -> bool {
    task := &cache.preparation.task
    entry := &cache.entries[int(task.key)]
    switch task.kind {
    case .Seed:
        return task.generation == entry.requested_generation
    case .Glyph_Page:
        return cache_preparation_raster(cache, task) != nil &&
            task.generation == entry.generation &&
            entry.generation == entry.requested_generation &&
            entry.state == .Ready
    }
    return false
}

//   Request cancellation for one accepted font preparation exactly once.
//
// Returns:
//   - True when the live task already has or newly receives a cancellation request.
//
// Side effects:
//   - Increments request telemetry only for the first successful request.
cache_request_preparation_cancellation :: proc(
    cache: ^Font_Cache, pool: ^taskpool.Task_Pool) -> bool {
    if cache == nil || pool == nil || cache.preparation.state != .Queued {
        return false
    }
    outcome := taskpool.task_pool_cancel(pool, cache.preparation.handle)
    if outcome == .Requested {
        cache.preparation.cancellation_request_count += 1
    }
    return outcome == .Requested || outcome == .Already_Requested
}

// cache_commit_uploaded_preparation publishes one successfully submitted atlas.
cache_commit_uploaded_preparation :: proc(cache: ^Font_Cache) -> bool {
    task := &cache.preparation.task
    texture := cache.preparation.pending_texture
    published := false
    switch task.kind {
    case .Seed:
        published = cache_publish_texture(
            cache, &task.prepared, texture, task.rgba_reservation_bytes)
    case .Glyph_Page:
        published = cache_publish_glyph_page_texture(
            cache, &task.prepared, task, texture)
    }
    return published
}

// cache_texture_upload_completed commits or rolls back one exact pending atlas.
cache_texture_upload_completed :: proc(
    user_data: rawptr, identity, generation: u64, succeeded: bool) {
    cache := cast(^Font_Cache)user_data
    if cache == nil || cache.preparation.state != .Uploading {
       return
    }
    task := &cache.preparation.task
     if identity != task.upload_identity || generation != task.generation {
       return
    }
    texture := cache.preparation.pending_texture
    published := succeeded && cache_preparation_is_current(cache) &&
        cache_commit_uploaded_preparation(cache)
    if published {
        cache.preparation.publication_count += 1
        if task.kind == .Seed {
            log.infof("font_generation_published key=%d generation=%d",
                int(task.key), task.generation)
        }
    } else {
        if succeeded && texture.handle != nil {
            cache.texture_operations.release(
                cache.texture_operations.user_data, texture)
        }
        cache.preparation.failure_count += 1
        cache_fail_preparation(cache)
    }
    cache.preparation.pending_texture = {}
    cache_finish_preparation(cache)
}

// Queue one atlas upload while retaining its CPU storage until completion.
cache_begin_preparation_upload :: proc(cache: ^Font_Cache) -> bool {
    task := &cache.preparation.task
    if task.kind == .Glyph_Page {
        entry := &cache.entries[int(task.key)]
        raster := cache_preparation_raster(cache, task)
        if !cache_glyph_page_matches_task(&task.prepared, task) ||
            !cache_glyph_page_can_publish(entry, raster, &task.prepared) {
            return false
        }
    }
    actual_bytes := u64(task.prepared.atlas_width) *
        u64(task.prepared.atlas_height) * 4
    if !font_raster_budget_shrink_candidate(
        &cache.raster_budget, task.rgba_reservation_bytes, actual_bytes) {
        return false
    }
    task.rgba_reservation_bytes = actual_bytes
    cache.next_upload_identity += 1
    if cache.next_upload_identity == 0 {
        cache.next_upload_identity = 1
    }
    task.upload_identity = cache.next_upload_identity
    texture, queued := finalize_texture(
        &task.prepared, cache.texture_operations, {
            identity = task.upload_identity,
            generation = task.generation,
            completion = cache_texture_upload_completed,
            completion_data = cache,
        })
    if !queued {
       return false
    }
    cache.preparation.pending_texture = texture
    cache.preparation.state = .Uploading
    return true
}

//   Restore demanded and prefetched page IDs after failure or supersession.
cache_restore_page_demand :: proc(cache: ^Font_Cache) {
    task := &cache.preparation.task
    if task.rgba_reservation_bytes > 0 {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, task.rgba_reservation_bytes, false)
    }
    if task.kind != .Glyph_Page {
        return
    }
    entry := &cache.entries[int(task.key)]
    raster := &entry.canonical_raster
    if task.raster_slot_index >= 0 &&
        task.raster_slot_index < len(cache.optional_rasters) {
        candidate := &cache.optional_rasters[task.raster_slot_index]
        if candidate.identity.slot_incarnation != task.raster_slot_incarnation {
            return
        }
        raster = candidate
    }
    if task.generation != entry.generation {
        return
    }
    for glyph_id, index in task.glyph_ids[:task.glyph_id_count] {
        if glyph_id < u32(len(raster.glyphs)) &&
            raster.glyphs[glyph_id].state == .Queued {
            raster.glyphs[glyph_id].state =
                .Pending if i32(index) < task.demanded_glyph_count else .Missing
        }
    }
    raster.queued_demand_count = 0
}

//   Lazily reserve one fixed virtual arena shared by serialized preparations.
//
// Returns:
//   - True when already initialized or after successful reserve/initial commit.
cache_preparation_arena_init :: proc(cache: ^Font_Cache) -> bool {
    if cache == nil {
        return false
    }
    if cache.preparation_arena_initialized {
        return true
    }
    arena_error := vmem.arena_init_static(
        &cache.preparation_arena,
        FONT_PREPARATION_ARENA_RESERVE_SIZE,
        FONT_PREPARATION_ARENA_INITIAL_COMMIT_SIZE)
    if arena_error != nil {
        cache.preparation_arena = {}
        return false
    }
    cache.preparation_arena_initialized = true
    return true
}

//   Reset logical usage while retaining committed pages for the next preparation.
//
// Side effects:
//   - Bulk-invalidates every arena allocation; requires no queued worker access.
cache_preparation_arena_reset :: proc(cache: ^Font_Cache) {
    if cache == nil || !cache.preparation_arena_initialized {
        return
    }
    assert(cache.preparation.state != .Queued)
    vmem.arena_free_all(&cache.preparation_arena)
}

//   Release the preparation arena's reservation and every committed page.
//
// Side effects:
//   - Destroys virtual storage only while the operation slot is idle.
cache_preparation_arena_destroy :: proc(cache: ^Font_Cache) {
    if cache == nil || !cache.preparation_arena_initialized {
        return
    }
    assert(cache.preparation.state == .Idle)
    vmem.arena_destroy(&cache.preparation_arena)
    cache.preparation_arena_initialized = false
}

//   Join and classify one terminal worker result, then release the operation.
cache_complete_preparation :: proc(
    cache: ^Font_Cache, pool: ^taskpool.Task_Pool) {

    task := &cache.preparation.task
    result, joined := taskpool.task_pool_wait(pool, cache.preparation.handle)
    if joined == .Joined && result == .Cancelled {
        cache.preparation.cancellation_completion_count += 1
        cache_fail_preparation(cache)
    } else if joined == .Joined && result == .Succeeded &&
        cache_preparation_is_current(cache) &&
        cache_begin_preparation_upload(cache) {
        return
    } else if !cache_preparation_is_current(cache) {
        cache.preparation.stale_completion_count += 1
        cache_restore_page_demand(cache)
    } else {
        cache.preparation.failure_count += 1
        if task.kind == .Seed {
            log.warnf("font_generation_failed key=%d generation=%d",
                int(task.key), task.generation)
        }
        cache_fail_preparation(cache)
    }
    cache_finish_preparation(cache)
}

//   Submit, poll, join, and publish optional preparation without frame waits.
//
// Parameters:
//   - cache: Display-owned cache serviced once per frame.
//   - pool: Live task pool whose accepted work is joined before shutdown.
//
// Side effects:
//   - Services hot reload, advances one operation, publishes only current generations,
//     classifies stale/failure outcomes, and starts subsequent requested work.
cache_service :: proc(cache: ^Font_Cache, pool: ^taskpool.Task_Pool) {
    if cache == nil || pool == nil {
        return
    }
    if cache.raster_request_clock < max(u64) {
        cache.raster_request_clock += 1
    }
    source_monitor_service(cache, source_monitor_now_ns())
    cache_begin_next_request(cache)
    if cache.preparation.state == .Idle {
        return
    }
    if cache.preparation.state == .Uploading {
       return
    }
    if cache.preparation.state == .Retry {
        cache_submit_preparation(cache, pool)
        return
    }
    if !cache_preparation_is_current(cache) {
        _ = cache_request_preparation_cancellation(cache, pool)
    }

    poll := taskpool.task_pool_poll(pool, cache.preparation.handle)
    if poll == .Pending {
        cache.preparation.pending_poll_count += 1
        return
    }
    if poll == .Stale_Handle {
        cache.preparation.failure_count += 1
        cache_fail_preparation(cache)
        cache_finish_preparation(cache)
        return
    }
    cache_complete_preparation(cache, pool)
}

//   Submit worker-only CPU preparation, retaining ownership on queue pressure.
//
// Side effects:
//   - Transitions Retry to Queued on acceptance, remains Retry when full, or fails and
//     releases the operation when the pool is stopped.
cache_submit_preparation :: proc(
    cache: ^Font_Cache, pool: ^taskpool.Task_Pool) {

    handle, outcome := taskpool.task_pool_submit(
        pool, prepare_task_execute, &cache.preparation.task, .Worker_Only)
    switch outcome {
    case .Queued:
        cache.preparation.handle = handle
        cache.preparation.state = .Queued
    case .Queue_Full:
        cache.preparation.queue_full_count += 1
    case .Pool_Stopped:
        cache.preparation.failure_count += 1
        cache_fail_preparation(cache)
        cache_finish_preparation(cache)
    }
}

//   Drain accepted font work before the general pool releases task storage.
//
// Parameters:
//   - cache: Display-owned cache entering permanent shutdown.
//   - pool: Pool still valid for shutdown and joining accepted work.
//
// Side effects:
//   - Rejects new requests, fails unsubmitted demand, shuts down the pool when work is
//     active, services its terminal result, and leaves the preparation slot idle.
//   - Accepted preparation remains worker-only while the display owner waits for drain.
cache_shutdown_service :: proc(
    cache: ^Font_Cache, pool: ^taskpool.Task_Pool) {

    if cache == nil || pool == nil {
        return
    }
    cache.shutting_down = true
    for entry_index in 0..<FONT_KEY_COUNT {
        entry := &cache.entries[entry_index]
        if entry.state == .Requested {
            entry.state = .Failed
        }
    }
    if cache.preparation.state == .Idle {
        return
    }
    _ = cache_request_preparation_cancellation(cache, pool)
    taskpool.task_pool_shutdown(pool)
    cache_service(cache, pool)
    assert(cache.preparation.state == .Idle)
}

//   Report whether no optional preparation request remains owner-visible.
//
// Returns:
//   - True for nil cache or an Idle operation slot.
cache_preparation_idle :: proc(cache: ^Font_Cache) -> bool {
    return cache == nil || cache.preparation.state == .Idle
}

//   Release a terminal operation result and return its owner state to idle.
//
// Side effects:
//   - Clears prepared/task/handle state, transitions to Idle, and bulk-resets arena use.
cache_finish_preparation :: proc(cache: ^Font_Cache) {
    task := cache.preparation.task
    prepare_destroy(&cache.preparation.task.prepared)
    cache.preparation.task = {}
    cache.preparation.handle = {}
    cache.preparation.state = .Idle
    cache_preparation_arena_reset(cache)
    if task.kind == .Glyph_Page {
        entry := &cache.entries[int(task.key)]
        cache_destroy_stale_optional_rasters(cache, task.key, entry.generation)
    }
}

//   Mark the active optional generation failed while preserving any resident font.
//
// Side effects:
//   - Marks Failed only if the completing task still matches desired generation;
//     superseded work leaves the newer Requested state intact.
cache_fail_preparation :: proc(cache: ^Font_Cache) {
    key := cache.preparation.task.key
    entry := &cache.entries[int(key)]
    if cache.preparation.task.kind == .Glyph_Page {
        cache_restore_page_demand(cache)
    } else {
        cache_restore_page_demand(cache)
        if cache.preparation.task.generation == entry.requested_generation {
            entry.state = .Failed
        }
    }
}
