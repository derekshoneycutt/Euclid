#+test
package viewgraphics

import termattachment "../../terminal/attachment"
import "../../evidence/trace"

import "core:testing"
import "core:mem"

// Mutable upload fixture for transactional playback publication tests.
Playback_Test_Upload :: struct {
    accept: bool,
    call_count: int,
    first_byte: u8,
}

// Record one attempted canvas upload and return the configured outcome.
playback_test_upload :: proc(
    user_data: rawptr, id: termattachment.Attachment_Id,
    pixels: []u8) -> bool {
    fixture := cast(^Playback_Test_Upload)user_data
    if fixture == nil || id.generation == 0 || len(pixels) == 0 { return false }
    fixture.call_count += 1
    fixture.first_byte = pixels[0]
    return fixture.accept
}

// Return one deterministic two-frame animation timeline for playback tests.
playback_test_animation :: proc(
    infinite: bool = false, repeat_count: u32 = 0) -> termattachment.Animation_View {
    @(static) frames := [2]termattachment.Animation_Frame{
        {pixels = {offset = 0, count = 4}, duration_ns = 20},
        {pixels = {offset = 4, count = 4}, duration_ns = 30},
    }
    return {
        frames = frames[:],
        timeline = {
            frame_count = 2,
            cycle_duration_ns = 50,
            repeat_count = repeat_count,
            infinite = infinite,
        },
    }
}

// Reserve and publish one two-frame store-owned animation for service tests.
playback_test_publish_store_animation :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    infinite: bool = false) -> termattachment.Attachment_Id {
    id, outcome := termattachment.animation_reserve(store, {
        metadata = {
            kind = .Raster,
            origin = .Iterm2,
            metrics = {width = 1, height = 1},
        },
        frame_count = 2,
        payload_byte_count = 8,
        temporary_decode_byte_count = 8,
        infinite = infinite,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    preparation, found := termattachment.animation_preparation_buffer(store, id)
    testing.expect(t, found)
    preparation.pixels[4] = 77
    preparation.frames[0] = {
        pixels = {offset = 0, count = 4},
        duration_ns = 20_000_000,
    }
    preparation.frames[1] = {
        pixels = {offset = 4, count = 4},
        duration_ns = 30_000_000,
    }
    testing.expect_value(t,
        termattachment.animation_preparation_publish(store, id),
        termattachment.Handle_Outcome.Found)
    return id
}

// Verify elapsed playback does not allocate and deletion releases payload ownership.
@(test)
playback_test_resource_baseline :: proc(t: ^testing.T) {
    table_tracker, payload_tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(
        &table_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&table_tracker)
    mem.tracking_allocator_init(
        &payload_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&payload_tracker)
    store: termattachment.Store
    testing.expect(t, termattachment.store_init_with_allocators(
        &store, service_test_limits(), mem.tracking_allocator(&table_tracker),
        mem.tracking_allocator(&payload_tracker)))
    id := playback_test_publish_store_animation(t, &store, true)
    payload_baseline := payload_tracker.current_memory_allocated
    animation, found := termattachment.animation_view(&store, id)
    testing.expect(t, found)
    entry, valid := playback_begin(id, animation, 0)
    testing.expect(t, valid)
    service := Service{store = &store}
    upload := Playback_Test_Upload{accept = true}

    for update in 1..=1_000 {
        playback_update_entry(&service, &entry, u64(update) * 50_000_000,
            playback_test_upload, &upload)
    }

    testing.expect_value(t,
        payload_tracker.current_memory_allocated, payload_baseline)
    testing.expect_value(t,
        termattachment.attachment_remove(&store, id),
        termattachment.Handle_Outcome.Found)
    testing.expect_value(t, store.animated_attachment_count, 0)
    testing.expect_value(t, store.cpu_byte_count, 0)
    testing.expect_value(t, payload_tracker.current_memory_allocated, i64(0))
    termattachment.store_destroy(&store)
    testing.expect_value(t, table_tracker.current_memory_allocated, i64(0))
}

// Verify exact boundaries, overdue transitions, finite loops, and final retention.
@(test)
playback_test_timeline_boundaries :: proc(t: ^testing.T) {
    animation := playback_test_animation(repeat_count = 1)
    id := termattachment.Attachment_Id{slot = 1, generation = 2}
    entry, valid := playback_begin(id, animation, 100)
    testing.expect(t, valid)
    testing.expect_value(t, entry.deadline_ns, u64(120))
    before := playback_plan(entry, animation, 119)
    testing.expect_value(t, before.candidate.frame_index, 0)
    first := playback_plan(entry, animation, 120)
    testing.expect_value(t, first.candidate.frame_index, 1)
    testing.expect(t, first.frame_changed)
    looped := playback_plan(first.candidate, animation, 150)
    testing.expect_value(t, looped.candidate.frame_index, 0)
    testing.expect_value(t, looped.candidate.completed_cycles, u64(1))
    overdue := playback_plan(looped.candidate, animation, 200)
    testing.expect_value(t, overdue.candidate.frame_index, 1)
    testing.expect(t, overdue.candidate.completed)
    testing.expect_value(t, overdue.candidate.completed_cycles, u64(1))
}

// Verify pause and resume preserve remaining duration without catch-up.
@(test)
playback_test_pause_resume :: proc(t: ^testing.T) {
    animation := playback_test_animation(infinite = true)
    entry, valid := playback_begin({slot = 0, generation = 1}, animation, 100)
    testing.expect(t, valid)
    playback_pause(&entry, 110)
    testing.expect(t, entry.paused)
    testing.expect_value(t, entry.remaining_ns, u64(10))
    playback_resume(&entry, 1_000)
    testing.expect(t, !entry.paused)
    testing.expect_value(t, entry.deadline_ns, u64(1_010))
    testing.expect_value(t,
        playback_plan(entry, animation, 1_009).candidate.frame_index, 0)
    testing.expect_value(t,
        playback_plan(entry, animation, 1_010).candidate.frame_index, 1)
}

    // Verify draw epochs freeze unseen playback and resume without hidden catch-up.
    @(test)
    playback_test_visibility_epoch :: proc(t: ^testing.T) {
        animation := playback_test_animation(infinite = true)
        entry, valid := playback_begin({slot = 0, generation = 1}, animation, 100)
        testing.expect(t, valid)

        playback_visibility_commit(&entry, 1, 110)
        testing.expect(t, entry.paused)
        testing.expect_value(t, entry.remaining_ns, u64(10))
        entry.visible_epoch = 2
        playback_visibility_commit(&entry, 2, 1_000)

        testing.expect(t, !entry.paused)
        testing.expect_value(t, entry.deadline_ns, u64(1_010))
        testing.expect_value(t,
        playback_plan(entry, animation, 1_009).candidate.frame_index, 0)
    }

// Verify service epochs share visibility by exact generation across placements.
@(test)
playback_test_service_visibility_epochs :: proc(t: ^testing.T) {
    id := termattachment.Attachment_Id{slot = 0, generation = 2}
    animation := playback_test_animation(infinite = true)
    entry, valid := playback_begin(id, animation, 100)
    testing.expect(t, valid)
    service := Service{playbacks = {0 = entry}}

    playback_visibility_begin_frame(&service, 100)
    playback_visibility_record(&service, {slot = 0, generation = 1})
    playback_visibility_record(&service, id)
    playback_visibility_begin_frame(&service, 110)
    testing.expect(t, !service.playbacks[0].paused)
    playback_visibility_begin_frame(&service, 120)

    testing.expect(t, service.playbacks[0].paused)
    testing.expect_value(t, service.playbacks[0].remaining_ns, u64(0))
}

// Verify epoch wrap clears stale marks before opening the replacement epoch.
@(test)
playback_test_visibility_epoch_wrap :: proc(t: ^testing.T) {
    service := Service{visibility_epoch = max(u64)}
    service.playbacks[0] = {
        attachment_id = {slot = 0, generation = 1},
        visible_epoch = max(u64),
        active = true,
    }

    playback_visibility_begin_frame(&service, 100)

    testing.expect_value(t, service.visibility_epoch, u64(1))
    testing.expect_value(t, service.playbacks[0].visible_epoch, u64(0))
}

// Verify only partial or complete viewport intersections qualify as visible.
@(test)
playback_test_raster_visibility_intersection :: proc(t: ^testing.T) {
    clip := termattachment.Render_Rectangle{x = 10, y = 10, width = 20, height = 20}
    testing.expect(t, raster_rectangles_intersect(
        {x = 0, y = 0, width = 11, height = 11}, clip))
    testing.expect(t, !raster_rectangles_intersect(
        {x = -20, y = 10, width = 20, height = 20}, clip))
    testing.expect(t, !raster_rectangles_intersect(
        {x = 30, y = 10, width = 20, height = 20}, clip))
}

// Verify transition work remains bounded under an extreme overdue timestamp.
@(test)
playback_test_transition_bound :: proc(t: ^testing.T) {
    animation := playback_test_animation(infinite = true)
    entry, valid := playback_begin({slot = 0, generation = 1}, animation, 0)
    testing.expect(t, valid)

    planned := playback_plan(entry, animation, max(u64))

    testing.expect(t, planned.valid)
    testing.expect(t, planned.candidate.deadline_ns < max(u64))
    testing.expect_value(t, planned.transition_count, PLAYBACK_TRANSITION_LIMIT)
    testing.expect_value(t, planned.candidate.completed_cycles, u64(32))
}

// Verify a rejected upload preserves the exact committed playback state for retry.
playback_test_expect_failed_upload :: proc(
    t: ^testing.T, service: ^Service, entry: ^Playback_Entry,
    upload: ^Playback_Test_Upload) {
    playback_update_entry(
        service, entry, 20_000_100, playback_test_upload, upload)
    testing.expect_value(t, upload.call_count, 1)
    testing.expect_value(t, entry.frame_index, 0)
    testing.expect_value(t, entry.deadline_ns, u64(20_000_100))
    testing.expect_value(t, service.playback_upload_failure_count, u64(1))
    testing.expect_value(t, service.playback_transition_count, u64(0))
}

// Verify retry publishes the next frame and commits its new deadline once.
playback_test_expect_successful_retry :: proc(
    t: ^testing.T, service: ^Service, entry: ^Playback_Entry,
    upload: ^Playback_Test_Upload) {
    upload.accept = true
    playback_update_entry(
        service, entry, 20_000_100, playback_test_upload, upload)
    testing.expect_value(t, upload.call_count, 2)
    testing.expect_value(t, upload.first_byte, u8(77))
    testing.expect_value(t, entry.frame_index, 1)
    testing.expect_value(t, entry.deadline_ns, u64(50_000_100))
    testing.expect_value(t, service.playback_transition_count, u64(1))
}

// Verify upload failure holds the committed frame and deadline for exact retry.
@(test)
playback_test_upload_failure_holds_state :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    id := playback_test_publish_store_animation(t, &store)
    animation, visible := termattachment.animation_view(&store, id)
    testing.expect(t, visible)
    entry, valid := playback_begin(id, animation, 100)
    testing.expect(t, valid)
    ring: trace.Ring
    trace.ring_init(&ring, .Display)
    service := Service{store = &store, trace_ring = &ring}
    upload: Playback_Test_Upload

    playback_test_expect_failed_upload(t, &service, &entry, &upload)
    playback_test_expect_successful_retry(t, &service, &entry, &upload)
    playback_update_entry(
        &service, &entry, 50_000_100, playback_test_upload, &upload)
    testing.expect(t, entry.completed)
    testing.expect_value(t, entry.frame_index, 1)
    testing.expect_value(t, service.playback_completion_count, u64(1))
    events: [2]trace.Event
    testing.expect_value(t, trace.ring_drain(&ring, events[:]), 2)
    testing.expect_value(t, events[0].kind, trace.Kind.Animation_Frame_Presented)
    testing.expect_value(t, events[0].payload.counts.first, u32(2))
    testing.expect_value(t, events[1].kind, trace.Kind.Animation_Playback_Completed)
}

// Verify lazy texture publication selects the committed frame after generation reuse.
@(test)
playback_test_lazy_payload_uses_current_generation :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    id := playback_test_publish_store_animation(t, &store)
    service := Service{store = &store, monotonic_ns = 100}
    service.playbacks[id.slot] = {
        attachment_id = {slot = id.slot, generation = id.generation + 1},
        frame_index = 1,
        active = true,
    }

    testing.expect(t, texture_activate_playback(&service, id))

    playback := &service.playbacks[id.slot]
    testing.expect_value(t, playback.attachment_id, id)
    testing.expect_value(t, playback.frame_index, 0)
    playback.frame_index = 1
    payload, found := texture_animation_payload(&service, id)
    testing.expect(t, found)
    testing.expect_value(t, len(payload.bytes), 4)
    testing.expect_value(t, payload.bytes[0], u8(77))
}

// Verify stale attachment generations clear their fixed playback slot.
@(test)
playback_test_stale_generation_clears_entry :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    service := Service{store = &store}
    entry := Playback_Entry{
        attachment_id = {slot = 0, generation = 99},
        active = true,
    }

    playback_update_entry(
        &service, &entry, 10, playback_test_upload, nil)

    testing.expect(t, !entry.active)
    testing.expect_value(t, service.playback_stale_count, u64(1))
}

// Verify Kitty controls select canvases and commit run and stop state exactly once.
@(test)
playback_test_kitty_control_states :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    id := playback_test_publish_store_animation(t, &store)
    service := Service{store = &store}
    upload := Playback_Test_Upload{accept = true}

    playback_apply_command(&service, {
        attachment_id = id,
        kind = .Control,
        current_frame = 2,
        animation_state = 3,
    }, 100, playback_test_upload, &upload)

    entry := &service.playbacks[id.slot]
    testing.expect_value(t, upload.first_byte, u8(77))
    testing.expect_value(t, entry.frame_index, 1)
    testing.expect(t, !entry.stopped && !entry.loading)
    playback_apply_command(&service, {
        attachment_id = id,
        kind = .Control,
        current_frame = 1,
        animation_state = 1,
    }, 200, playback_test_upload, &upload)
    testing.expect_value(t, entry.frame_index, 0)
    testing.expect(t, entry.stopped)
    testing.expect_value(t, entry.completed_cycles, u64(0))
}

// Verify rejected selected-canvas upload preserves all committed playback state.
@(test)
playback_test_kitty_control_upload_failure_rolls_back :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    id := playback_test_publish_store_animation(t, &store)
    animation, found := termattachment.animation_view(&store, id)
    testing.expect(t, found)
    entry, valid := playback_begin(id, animation, 100)
    testing.expect(t, valid)
    service := Service{store = &store}
    service.playbacks[id.slot] = entry
    upload: Playback_Test_Upload

    playback_apply_command(&service, {
        attachment_id = id,
        kind = .Control,
        current_frame = 2,
        animation_state = 3,
    }, 200, playback_test_upload, &upload)

    testing.expect_value(t, service.playbacks[id.slot], entry)
    testing.expect_value(t, service.playback_upload_failure_count, u64(1))
}

// Verify loading mode holds the current final frame until a later refresh arrives.
@(test)
playback_test_loading_holds_final_frame :: proc(t: ^testing.T) {
    animation := playback_test_animation(infinite = true)
    entry, valid := playback_begin(
        {slot = 0, generation = 1}, animation, 100)
    testing.expect(t, valid)
    entry.frame_index = 1
    entry.deadline_ns = 130
    entry.loading = true

    planned := playback_plan(entry, animation, 130)

    testing.expect(t, planned.valid)
    testing.expect_value(t, planned.candidate.frame_index, 1)
    testing.expect_value(t, planned.transition_count, 0)
}