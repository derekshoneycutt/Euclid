#+test
package termattachment

import "core:mem"
import "core:testing"

// Return one two-frame full-canvas animation reservation for attachment tests.
attachment_test_animation_reservation :: proc(
    retained: bool = false) -> Animation_Reservation {
    return {
        metadata = attachment_test_metadata(.Iterm2),
        frame_count = 2,
        payload_byte_count = 32,
        temporary_decode_byte_count = 32,
        repeat_count = 2,
        protocol_retained = retained,
    }
}

// Fill one reserved animation with deterministic full-canvas ranges and durations.
attachment_test_fill_animation :: proc(preparation: Animation_Preparation) {
    for index in 0..<len(preparation.pixels) {
        preparation.pixels[index] = u8(index)
    }
    preparation.frames[0] = {
        pixels = {offset = 0, count = 16},
        duration_ns = 20_000_000,
    }
    preparation.frames[1] = {
        pixels = {offset = 16, count = 16},
        duration_ns = 30_000_000,
    }
}

// Verify animation bytes remain unreadable until exact-generation atomic publication.
@(test)
attachment_test_animation_reserve_publish :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 128), context.allocator))
    defer store_destroy(&store)
    id, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())
    expected_cpu_bytes := 32 + 2 * int(size_of(Animation_Frame))
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, store.cpu_byte_count, expected_cpu_bytes)
    testing.expect_value(t, store.animated_attachment_count, 1)
    testing.expect_value(t, store.animation_decode_byte_count, 32)
    _, visible_before := animation_view(&store, id)
    testing.expect(t, !visible_before)
    _, static_visible := attachment_payload(&store, id)
    testing.expect(t, !static_visible)
    preparation, writable := animation_preparation_buffer(&store, id)
    testing.expect(t, writable)
    attachment_test_fill_animation(preparation)

    testing.expect_value(t,
        animation_preparation_publish(&store, id), Handle_Outcome.Found)

    animation, visible := animation_view(&store, id)
    testing.expect(t, visible)
    testing.expect_value(t, animation.timeline.frame_count, 2)
    testing.expect_value(t, animation.timeline.cycle_duration_ns, u64(50_000_000))
    testing.expect_value(t, animation.timeline.repeat_count, u32(2))
    testing.expect(t, !animation.timeline.infinite)
    testing.expect_value(t, animation.frames[1].pixels.offset, 16)
    testing.expect_value(t, animation.pixels[31], u8(31))
    testing.expect_value(t, store.attachments[id.slot].pin_count, 0)
    testing.expect_value(t, store.animation_decode_byte_count, 0)
}

// Verify malformed frame publication rolls back through the pending release path.
@(test)
attachment_test_animation_invalid_publish_release :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 128), context.allocator))
    defer store_destroy(&store)
    id, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    preparation, writable := animation_preparation_buffer(&store, id)
    testing.expect(t, writable)
    attachment_test_fill_animation(preparation)
    preparation.frames[1].pixels.offset = 15

    testing.expect_value(t,
        animation_preparation_publish(&store, id), Handle_Outcome.Stale)
    _, visible := animation_view(&store, id)
    testing.expect(t, !visible)
    testing.expect_value(t,
        attachment_preparation_release(&store, id), Handle_Outcome.Found)
    testing.expect_value(t, store.animation_decode_byte_count, 0)
    testing.expect_value(t, attachment_remove(&store, id), Handle_Outcome.Found)
    testing.expect_value(t, store.cpu_byte_count, 0)
    testing.expect_value(t, store.animated_attachment_count, 0)
}

// Verify temporary decode reservations are bounded across pending generations.
@(test)
attachment_test_animation_aggregate_decode_limit :: proc(t: ^testing.T) {
    limits := attachment_test_limits(
        attachment_capacity = 2, cpu_byte_limit = 128)
    limits.animated_attachment_limit = 2
    limits.animation_decode_byte_limit = 48
    store: Store
    testing.expect(t, store_init(&store, limits, context.allocator))
    defer store_destroy(&store)
    reservation := attachment_test_animation_reservation()
    first, first_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, first_outcome, Admission_Outcome.Admitted)

    _, blocked_outcome := animation_reserve(&store, reservation)

    testing.expect_value(t, blocked_outcome, Admission_Outcome.Byte_Limit_Exceeded)
    testing.expect_value(t, store.animation_decode_byte_count, 32)
    preparation, writable := animation_preparation_buffer(&store, first)
    testing.expect(t, writable)
    attachment_test_fill_animation(preparation)
    testing.expect_value(t,
        animation_preparation_publish(&store, first), Handle_Outcome.Found)
    testing.expect_value(t, store.animation_decode_byte_count, 0)
    _, admitted_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, admitted_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, store.animation_decode_byte_count, 32)
}

// Verify animation admission enforces occupancy, frame, decode, byte, and duration limits.
@(test)
attachment_test_animation_limits :: proc(t: ^testing.T) {
    limits := attachment_test_limits(
        attachment_capacity = 2, cpu_byte_limit = 128)
    limits.animated_attachment_limit = 1
    store: Store
    testing.expect(t, store_init(&store, limits, context.allocator))
    defer store_destroy(&store)
    reservation := attachment_test_animation_reservation(true)
    first, first_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, first_outcome, Admission_Outcome.Admitted)
    _, second_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, second_outcome, Admission_Outcome.Capacity_Exceeded)
    testing.expect_value(t, store.diagnostics.animation_admission_count, u64(1))
    testing.expect_value(t, store.diagnostics.animation_rejection_count, u64(1))

    testing.expect_value(t,
        attachment_preparation_release(&store, first), Handle_Outcome.Found)
    testing.expect_value(t,
        attachment_set_protocol_retained(&store, first, false), Handle_Outcome.Found)
    testing.expect_value(t, attachment_remove(&store, first), Handle_Outcome.Found)
    reservation.frame_count = 5
    _, frame_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, frame_outcome, Admission_Outcome.Invalid)
    reservation = attachment_test_animation_reservation()
    reservation.temporary_decode_byte_count = 65
    _, decode_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, decode_outcome, Admission_Outcome.Invalid)
    reservation = attachment_test_animation_reservation()
    reservation.payload_byte_count = 31
    _, byte_outcome := animation_reserve(&store, reservation)
    testing.expect_value(t, byte_outcome, Admission_Outcome.Invalid)
}

// Verify source timing converts exactly, clamps short delays, and rejects long frames.
@(test)
attachment_test_animation_duration_normalization :: proc(t: ^testing.T) {
    limits := attachment_test_limits()
    exact, exact_valid := animation_duration_from_units(3, 100, limits)
    testing.expect(t, exact_valid)
    testing.expect_value(t, exact, u64(30_000_000))
    clamped, clamped_valid := animation_duration_from_units(0, 100, limits)
    testing.expect(t, clamped_valid)
    testing.expect_value(t, clamped, limits.animation_min_frame_duration_ns)
    _, long_valid := animation_duration_from_units(11, 100, limits)
    testing.expect(t, !long_valid)
    _, invalid_rate := animation_duration_from_units(1, 0, limits)
    testing.expect(t, !invalid_rate)
}

// Verify LRU eviction releases all animated payload and descriptor accounting.
@(test)
attachment_test_animation_eviction_accounting :: proc(t: ^testing.T) {
    expected_cpu_bytes := 32 + 2 * int(size_of(Animation_Frame))
    store: Store
    testing.expect(t, store_init(&store, attachment_test_limits(
        attachment_capacity = 2, cpu_byte_limit = expected_cpu_bytes),
        context.allocator))
    defer store_destroy(&store)
    id, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    preparation, writable := animation_preparation_buffer(&store, id)
    testing.expect(t, writable)
    attachment_test_fill_animation(preparation)
    testing.expect_value(t,
        animation_preparation_publish(&store, id), Handle_Outcome.Found)

    _, static_outcome := attachment_test_admit(&store, false)

    testing.expect_value(t, static_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, store.animated_attachment_count, 0)
    testing.expect_value(t,
        store.diagnostics.cpu_evicted_bytes, u64(expected_cpu_bytes))
    _, stale := animation_view(&store, id)
    testing.expect(t, !stale)
}

// Verify duration overflow cannot partially publish a pending animation generation.
@(test)
attachment_test_animation_duration_limit :: proc(t: ^testing.T) {
    limits := attachment_test_limits(cpu_byte_limit = 128)
    limits.animation_duration_ns_limit = 49_000_000
    store: Store
    testing.expect(t, store_init(&store, limits, context.allocator))
    defer store_destroy(&store)
    id, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    preparation, writable := animation_preparation_buffer(&store, id)
    testing.expect(t, writable)
    attachment_test_fill_animation(preparation)

    testing.expect_value(t,
        animation_preparation_publish(&store, id), Handle_Outcome.Stale)
    testing.expect_value(t,
        attachment_preparation_release(&store, id), Handle_Outcome.Found)
}

// Verify removal frees animation pixels and descriptors from the payload allocator.
@(test)
attachment_test_animation_allocator_lifetime :: proc(t: ^testing.T) {
    table_tracker, payload_tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(
        &table_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&table_tracker)
    mem.tracking_allocator_init(
        &payload_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&payload_tracker)
    store: Store
    testing.expect(t, store_init_with_allocators(
        &store, attachment_test_limits(cpu_byte_limit = 128),
        mem.tracking_allocator(&table_tracker),
        mem.tracking_allocator(&payload_tracker)))
    id, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    testing.expect(t, payload_tracker.current_memory_allocated > 32)
    testing.expect_value(t,
        attachment_preparation_release(&store, id), Handle_Outcome.Found)
    testing.expect_value(t, attachment_remove(&store, id), Handle_Outcome.Found)
    testing.expect_value(t, payload_tracker.current_memory_allocated, i64(0))

    store_destroy(&store)
    testing.expect_value(t, table_tracker.current_memory_allocated, i64(0))
    testing.expect_value(t, len(table_tracker.bad_free_array), 0)
    testing.expect_value(t, len(payload_tracker.bad_free_array), 0)
}

// Verify descriptor allocation failure releases pixels and leaves no partial entry.
@(test)
attachment_test_animation_allocation_failure_is_atomic :: proc(t: ^testing.T) {
    failure_storage: [40]byte
    failure_arena: mem.Arena
    mem.arena_init(&failure_arena, failure_storage[:])
    store: Store
    testing.expect(t, store_init_with_allocators(
        &store, attachment_test_limits(cpu_byte_limit = 128),
        context.allocator, mem.arena_allocator(&failure_arena)))
    defer store_destroy(&store)

    _, outcome := animation_reserve(
        &store, attachment_test_animation_reservation())

    testing.expect_value(t, outcome, Admission_Outcome.Allocation_Failed)
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.animated_attachment_count, 0)
    testing.expect_value(t, store.cpu_byte_count, 0)
    testing.expect_value(t, store.diagnostics.animation_admission_count, u64(0))
    testing.expect_value(t, store.diagnostics.animation_rejection_count, u64(1))
}