package font

import "../../core"
import "../../taskpool"

import vmem "core:mem/virtual"

// Display-owned lifecycle of the single optional-font preparation slot.
//
// Retry owns an unsubmitted payload; Queued identifies pool-owned execution/polling;
// Idle guarantees no worker can access task or arena storage.
Font_Prepare_Operation_State :: core.Font_Prepare_Operation_State
Font_Prepare_Task :: core.Font_Prepare_Task
Font_Prepare_Operation :: core.Font_Prepare_Operation

//   Prepare one task-owned font result without touching display resources.
//
// Parameters:
//   - payload: Non-nil `^Font_Prepare_Task` exclusively owned for task execution.
//
// Returns:
//   - `.Succeeded` when a complete arena-backed CPU font was produced; otherwise `.Failed`.
//
// Side effects:
//   - Writes only `task.prepared`; does not call raylib or mutate the cache.
prepare_task_execute :: proc(payload: rawptr) -> taskpool.Task_Result {
    task := cast(^Font_Prepare_Task)payload
    request := Font_Prepare_Request{
        key = task.key,
        generation = task.generation,
        path = string(task.path_storage[:task.path_length]),
        pixel_size = task.pixel_size,
        codepoints = task.codepoints[:task.codepoint_count],
        complete_face = true,
    }
    if prepare(request, &task.prepared, task.allocator, .Arena) {
        return .Succeeded
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
        return
    }
    entry := &cache.entries[int(key)]
    if !cache_preparation_arena_init(cache) {
        entry.state = .Failed
        cache.preparation.failure_count += 1
        return
    }
    entry.state = .Preparing
    cache.preparation.state = .Retry
    cache.preparation.task = {
        key = key,
        generation = entry.requested_generation,
        pixel_size = JULIA_MONO_FONT_SIZE,
        allocator = vmem.arena_allocator(&cache.preparation_arena),
    }
    path := cache_source_path(cache, key)
    if !prepare_task_set_path(&cache.preparation.task, path) {
        entry.state = .Failed
        cache.preparation.state = .Idle
        cache.preparation.failure_count += 1
        return
    }
    codepoints := codepoint_set()
    copy(cache.preparation.task.codepoints[:], codepoints.values[:codepoints.count])
    cache.preparation.task.codepoint_count = codepoints.count
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
    source_monitor_service(cache, source_monitor_now_ns())
    cache_begin_next_request(cache)
    if cache.preparation.state == .Idle {
        return
    }
    if cache.preparation.state == .Retry {
        cache_submit_preparation(cache, pool)
        return
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
    result, joined := taskpool.task_pool_wait(pool, cache.preparation.handle)
    if joined == .Joined && result == .Succeeded &&
        cache_publish(cache, &cache.preparation.task.prepared) {
        cache.preparation.publication_count += 1
    } else if cache.preparation.task.generation !=
        cache.entries[int(cache.preparation.task.key)].requested_generation {
        cache.preparation.stale_completion_count += 1
    } else {
        cache.preparation.failure_count += 1
        cache_fail_preparation(cache)
    }
    cache_finish_preparation(cache)
}

//   Attempt one bounded submission while retaining ownership on queue pressure.
//
// Side effects:
//   - Transitions Retry to Queued on acceptance, remains Retry when full, or fails and
//     releases the operation when the pool is stopped.
cache_submit_preparation :: proc(
    cache: ^Font_Cache, pool: ^taskpool.Task_Pool) {

    handle, outcome := taskpool.task_pool_submit(
        pool, prepare_task_execute, &cache.preparation.task)
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
    prepare_destroy(&cache.preparation.task.prepared)
    cache.preparation.task = {}
    cache.preparation.handle = {}
    cache.preparation.state = .Idle
    cache_preparation_arena_reset(cache)
}

//   Mark the active optional generation failed while preserving any resident font.
//
// Side effects:
//   - Marks Failed only if the completing task still matches desired generation;
//     superseded work leaves the newer Requested state intact.
cache_fail_preparation :: proc(cache: ^Font_Cache) {
    key := cache.preparation.task.key
    entry := &cache.entries[int(key)]
    if cache.preparation.task.generation == entry.requested_generation {
        entry.state = .Failed
    }
}
