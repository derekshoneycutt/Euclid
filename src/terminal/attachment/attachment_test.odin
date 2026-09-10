#+test
package termattachment

import "core:mem"
import "core:testing"

// Return a compact resource policy suitable for deterministic unit fixtures.
attachment_test_limits :: proc(
    attachment_capacity: int = 2, placement_capacity: int = 2,
    transfer_capacity: int = 1, cpu_byte_limit: int = 32,
    gpu_byte_limit: int = 16) -> Limits {
    return {
        attachment_capacity = attachment_capacity,
        placement_capacity = placement_capacity,
        transfer_capacity = transfer_capacity,
        transfer_byte_limit = 8,
        dimension_limit = 4,
        image_pixel_limit = 16,
        cpu_byte_limit = cpu_byte_limit,
        gpu_byte_limit = gpu_byte_limit,
        animated_attachment_limit = 2,
        animation_frame_limit = 4,
        animation_decode_byte_limit = 64,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }
}

// Return valid metadata for one two-by-two raster attachment.
attachment_test_metadata :: proc(origin: Protocol_Origin = .Kitty) ->
    Attachment_Metadata {
    return {
        kind = .Raster,
        origin = origin,
        metrics = {width = 2, height = 2},
    }
}

// Admit one four-byte indexed raster fixture.
attachment_test_admit :: proc(
    store: ^Store, retained: bool = true,
    origin: Protocol_Origin = .Kitty) -> (Attachment_Id, Admission_Outcome) {
    payload := [4]u8{1, 2, 3, 4}
    return attachment_admit(store, {
        metadata = attachment_test_metadata(origin),
        payload = payload[:],
        payload_format = .Indexed8,
        payload_stride = 2,
        protocol_retained = retained,
    })
}

// Return one valid placement fixture for an attachment.
attachment_test_placement :: proc(id: Attachment_Id) -> Placement_Metadata {
    return {
        attachment_id = id,
        geometry = {
            screen = .Primary,
            logical_row = 17,
            column = 3,
            column_span = 2,
            row_span = 1,
            source = {width = 2, height = 2},
            sizing = .Fit,
            cursor = .Advance,
        },
        lifecycle = .Addressable,
    }
}

// Record display-owned residency evictions for one test admission.
attachment_test_evict :: proc(
    user_data: rawptr, attachment_id: Attachment_Id) -> bool {
    evicted := (^struct {
        ids: [4]Attachment_Id,
        count: int,
    })(user_data)
    evicted.ids[evicted.count] = attachment_id
    evicted.count += 1
    return true
}

// Confirm the renderer capability receives immutable measured draw data.
attachment_test_draw :: proc(
    user_data: rawptr, request: Raster_Draw_Request) -> bool {
    observed := (^Raster_Draw_Request)(user_data)
    observed^ = request
    return true
}

// Move retained primary placements and evict anchors outside the replacement model.
attachment_test_relocate :: proc(
    user_data: rawptr, geometry: Placement_Geometry) ->
    (Placement_Geometry, bool) {
    evicted_row := (^i64)(user_data)^
    if geometry.logical_row == evicted_row { return {}, false }
    result := geometry
    result.logical_row += 10
    result.column += 2
    return result, true
}

// Verify fixed tables and removable payloads retain distinct allocator domains.
@(test)
attachment_test_split_allocator_ownership :: proc(t: ^testing.T) {
    table_tracker, payload_tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(
        &table_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&table_tracker)
    mem.tracking_allocator_init(
        &payload_tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&payload_tracker)
    table_allocator := mem.tracking_allocator(&table_tracker)
    payload_allocator := mem.tracking_allocator(&payload_tracker)
    store: Store

    testing.expect(t, store_init_with_allocators(
        &store, attachment_test_limits(),
        table_allocator, payload_allocator))
    testing.expect(t, table_tracker.current_memory_allocated > 0)
    testing.expect_value(t, payload_tracker.current_memory_allocated, i64(0))
    _, outcome := attachment_test_admit(&store, false)
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, payload_tracker.current_memory_allocated, i64(4))

    store_destroy(&store)
    testing.expect_value(t, table_tracker.current_memory_allocated, i64(0))
    testing.expect_value(t, payload_tracker.current_memory_allocated, i64(0))
    testing.expect_value(t, len(table_tracker.bad_free_array), 0)
    testing.expect_value(t, len(payload_tracker.bad_free_array), 0)
}

// Verify default policy exposes the approved Phase 1 resource limits.
@(test)
attachment_test_default_limits :: proc(t: ^testing.T) {
    limits := limits_default()

    testing.expect_value(t, limits.attachment_capacity, 256)
    testing.expect_value(t, limits.placement_capacity, 1024)
    testing.expect_value(t, limits.transfer_capacity, 4)
    testing.expect_value(t, limits.transfer_byte_limit, 32 * 1024 * 1024)
    testing.expect_value(t, limits.dimension_limit, 8192)
    testing.expect_value(t, limits.image_pixel_limit, 16_777_216)
    testing.expect_value(t, limits.cpu_byte_limit, 256 * 1024 * 1024)
    testing.expect_value(t, limits.gpu_byte_limit, 256 * 1024 * 1024)
    testing.expect_value(t, limits.animated_attachment_limit, 64)
    testing.expect_value(t, limits.animation_frame_limit, 1024)
    testing.expect_value(t, limits.animation_decode_byte_limit, 256 * 1024 * 1024)
    testing.expect_value(t, limits.animation_min_frame_duration_ns, u64(10_000_000))
    testing.expect_value(t, limits.animation_max_frame_duration_ns, u64(60_000_000_000))
    testing.expect_value(t, limits.animation_duration_ns_limit, u64(86_400_000_000_000))
}

// Verify destroyed and reused attachment slots reject stale generations.
@(test)
attachment_test_generation_reuse :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(attachment_capacity = 1),
        context.allocator))
    defer store_destroy(&store)
    first, first_outcome := attachment_test_admit(&store, false)
    testing.expect_value(t, first_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, attachment_remove(&store, first), Handle_Outcome.Found)

    second, second_outcome := attachment_test_admit(&store, false)

    testing.expect_value(t, second_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, second.slot, first.slot)
    testing.expect(t, second.generation != first.generation)
    _, first_found := attachment_payload(&store, first)
    testing.expect(t, !first_found)
    _, second_found := attachment_payload(&store, second)
    testing.expect(t, second_found)
}

// Verify bounded prepared enumeration excludes invalid, pending, and removed slots.
@(test)
attachment_test_prepared_id_at :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(), context.allocator))
    defer store_destroy(&store)
    prepared, prepared_outcome := attachment_test_admit(&store, true)
    testing.expect_value(t, prepared_outcome, Admission_Outcome.Admitted)
    pending, pending_outcome := attachment_reserve(&store, {
        metadata = {
            kind = .Raster,
            origin = .Sixel,
            metrics = {width = 1, height = 1},
        },
        payload_byte_count = 4,
        payload_format = .Rgba8,
        payload_stride = 4,
    })
    testing.expect_value(t, pending_outcome, Admission_Outcome.Admitted)

    found, available := attachment_prepared_id_at(&store, prepared.slot)
    testing.expect(t, available)
    testing.expect_value(t, found, prepared)
    _, pending_available := attachment_prepared_id_at(&store, pending.slot)
    testing.expect(t, !pending_available)
    _, invalid_available := attachment_prepared_id_at(&store, -1)
    testing.expect(t, !invalid_available)
    testing.expect_value(t,
        attachment_set_protocol_retained(&store, prepared, false),
        Handle_Outcome.Found)
    testing.expect_value(t,
        attachment_remove(&store, prepared), Handle_Outcome.Found)
    _, removed_available := attachment_prepared_id_at(&store, prepared.slot)
    testing.expect(t, !removed_available)
}

// Verify pending storage remains unreadable until exact-generation publication.
@(test)
attachment_test_preparation_reserve_publish :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(), context.allocator))
    defer store_destroy(&store)
    id, outcome := attachment_reserve(&store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 2, height = 1},
        },
        payload_byte_count = 8,
        payload_format = .Rgba8,
        payload_stride = 8,
    })
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    _, readable := attachment_payload(&store, id)
    testing.expect(t, !readable)
    output, writable := attachment_preparation_buffer(&store, id)
    testing.expect(t, writable)
    copy(output, []u8{1, 2, 3, 4, 5, 6, 7, 8})

    testing.expect_value(t,
        attachment_preparation_publish(&store, id), Handle_Outcome.Found)

    payload, readable_after := attachment_payload(&store, id)
    testing.expect(t, readable_after)
    testing.expect_value(t, payload.bytes[0], u8(1))
    testing.expect_value(t, payload.bytes[7], u8(8))
    testing.expect_value(t, store.attachments[id.slot].pin_count, 0)
}

// Verify logical removal prevents a joined pending generation from publishing.
@(test)
attachment_test_preparation_removal_rejects_publish :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(), context.allocator))
    defer store_destroy(&store)
    id, outcome := attachment_reserve(&store, {
        metadata = {
            kind = .Raster,
            origin = .Sixel,
            metrics = {width = 1, height = 1},
        },
        payload_byte_count = 4,
        payload_format = .Rgba8,
        payload_stride = 4,
    })
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, attachment_remove(&store, id), Handle_Outcome.Stale)
    testing.expect_value(t,
        attachment_preparation_publish(&store, id), Handle_Outcome.Stale)
    testing.expect_value(t,
        attachment_preparation_release(&store, id), Handle_Outcome.Found)
    testing.expect_value(t, attachment_remove(&store, id), Handle_Outcome.Found)
    _, readable := attachment_payload(&store, id)
    testing.expect(t, !readable)
}

// Verify placement references block eviction until their exact generation is removed.
@(test)
attachment_test_placement_retention :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(attachment_capacity = 1),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store, false)
    placement, placement_outcome := placement_admit(
        &store, attachment_test_placement(first))
    testing.expect_value(t, placement_outcome, Admission_Outcome.Admitted)

    _, blocked := attachment_test_admit(&store, false)
    testing.expect_value(t, blocked, Admission_Outcome.No_Evictable_Entry)
    testing.expect_value(t, placement_remove(&store, placement), Handle_Outcome.Found)
    second, admitted := attachment_test_admit(&store, false)

    testing.expect_value(t, admitted, Admission_Outcome.Admitted)
    testing.expect_value(t, second.slot, first.slot)
    testing.expect(t, second.generation != first.generation)
    testing.expect_value(t, placement_remove(&store, placement), Handle_Outcome.Stale)
}

// Verify restored placements retain their exact attachment references and pins.
attachment_test_expect_checkpoint_restore :: proc(
    t: ^testing.T, store: ^Store, first, second: Attachment_Id) {
    testing.expect_value(t, store.placement_count, 2)
    first_entry, first_found := attachment_entry(store, first)
    second_entry, second_found := attachment_entry(store, second)
    testing.expect_value(t, first_found, Handle_Outcome.Found)
    testing.expect_value(t, second_found, Handle_Outcome.Found)
    testing.expect_value(t, first_entry.placement_reference_count, 1)
    testing.expect_value(t, second_entry.placement_reference_count, 1)
    testing.expect_value(t, first_entry.pin_count, 1)
    testing.expect_value(t, second_entry.pin_count, 1)
}

// Verify row cleanup, screen cleanup, and checkpoint restore preserve references.
@(test)
attachment_test_placement_lifecycle_checkpoint :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(
            attachment_capacity = 2, placement_capacity = 4),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store, false)
    second, _ := attachment_test_admit(&store, false)
    first_metadata := attachment_test_placement(first)
    second_metadata := attachment_test_placement(second)
    second_metadata.geometry.screen = .Alternate
    second_metadata.geometry.logical_row = 23
    _, first_outcome := placement_admit(&store, first_metadata)
    _, second_outcome := placement_admit(&store, second_metadata)
    testing.expect_value(t, first_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, second_outcome, Admission_Outcome.Admitted)

    checkpoint: Placement_Checkpoint
    testing.expect(t, placement_checkpoint_init(
        &checkpoint, &store, context.allocator))
    defer placement_checkpoint_destroy(&checkpoint)
    testing.expect(t, placement_checkpoint_capture(&checkpoint, &store))
    testing.expect_value(t, checkpoint.pin_count, 2)
    testing.expect_value(t,
        placements_remove_row(&store, .Primary, 17), 1)
    testing.expect_value(t,
        placements_remove_screen(&store, .Alternate), 1)
    testing.expect_value(t, store.placement_count, 0)

    testing.expect(t, placement_checkpoint_restore(&checkpoint, &store))
    attachment_test_expect_checkpoint_restore(t, &store, first, second)
}

// Verify prepared placement relocation leaves the live table unchanged until restore.
@(test)
attachment_test_checkpoint_relocation_is_transactional :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(
            attachment_capacity = 2, placement_capacity = 4),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store, false)
    second, _ := attachment_test_admit(&store, false)
    first_metadata := attachment_test_placement(first)
    second_metadata := attachment_test_placement(second)
    second_metadata.geometry.logical_row = 23
    first_id, _ := placement_admit(&store, first_metadata)
    _, _ = placement_admit(&store, second_metadata)
    checkpoint: Placement_Checkpoint
    testing.expect(t, placement_checkpoint_init(
        &checkpoint, &store, context.allocator))
    defer placement_checkpoint_destroy(&checkpoint)
    testing.expect(t, placement_checkpoint_capture(&checkpoint, &store))
    evicted_row := i64(23)
    testing.expect(t, placement_checkpoint_relocate(
        &checkpoint, .Primary, &evicted_row, attachment_test_relocate))
    live, live_found := placement_metadata(&store, first_id)
    testing.expect(t, live_found)
    testing.expect_value(t, live.geometry.logical_row, i64(17))
    testing.expect(t, placement_checkpoint_restore(&checkpoint, &store))
    relocated, relocated_found := placement_metadata(&store, first_id)
    testing.expect(t, relocated_found)
    testing.expect_value(t, relocated.geometry.logical_row, i64(27))
    testing.expect_value(t, relocated.geometry.column, 5)
    testing.expect_value(t, store.placement_count, 1)
}

// Verify checkpoint-style pins and protocol identity independently retain payloads.
@(test)
attachment_test_pin_and_protocol_retention :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(attachment_capacity = 1),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store)
    testing.expect_value(t, attachment_pin(&store, first), Handle_Outcome.Found)
    testing.expect_value(t,
        attachment_set_protocol_retained(&store, first, false),
        Handle_Outcome.Found)

    _, pinned := attachment_test_admit(&store, false)
    testing.expect_value(t, pinned, Admission_Outcome.No_Evictable_Entry)
    testing.expect_value(t, attachment_unpin(&store, first), Handle_Outcome.Found)
    _, admitted := attachment_test_admit(&store, false)

    testing.expect_value(t, admitted, Admission_Outcome.Admitted)
    testing.expect_value(t, store.diagnostics.attachment_eviction_count, 1)
}

// Verify CPU pressure evicts the least recently used eligible payload.
@(test)
attachment_test_cpu_lru_eviction :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(
            attachment_capacity = 3, cpu_byte_limit = 8),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store, false, .Kitty)
    second, _ := attachment_test_admit(&store, false, .Sixel)
    _, first_found := attachment_payload(&store, first)
    testing.expect(t, first_found)

    third, outcome := attachment_test_admit(&store, false, .Iterm2)

    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    _, second_found := attachment_payload(&store, second)
    testing.expect(t, !second_found)
    _, third_found := attachment_payload(&store, third)
    testing.expect(t, third_found)
    testing.expect_value(t, store.cpu_byte_count, 8)
    testing.expect_value(t, store.diagnostics.cpu_evicted_bytes, 4)
}

// Verify malformed dimensions and short raster storage are rejected before copying.
@(test)
attachment_test_payload_validation :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(&store, attachment_test_limits(), context.allocator))
    defer store_destroy(&store)
    payload := [4]u8{1, 2, 3, 4}
    oversized := attachment_test_metadata()
    oversized.metrics.width = 5

    _, oversized_outcome := attachment_admit(&store, {
        metadata = oversized,
        payload = payload[:],
        payload_format = .Indexed8,
        payload_stride = 2,
    })
    _, short_outcome := attachment_admit(&store, {
        metadata = attachment_test_metadata(),
        payload = payload[:],
        payload_format = .Rgba8,
        payload_stride = 8,
    })

    testing.expect_value(t, oversized_outcome, Admission_Outcome.Pixel_Limit_Exceeded)
    testing.expect_value(t, short_outcome, Admission_Outcome.Invalid)
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.cpu_byte_count, 0)
}

// Verify transfers use exact reservations, enforce limits, and reject stale reuse.
@(test)
attachment_test_transfer_lifecycle :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(&store, attachment_test_limits(), context.allocator))
    defer store_destroy(&store)
    first, first_outcome := transfer_begin(&store, .Iterm2, 4)
    testing.expect_value(t, first_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t,
        transfer_append(&store, first, []u8{1, 2, 3}),
        Admission_Outcome.Admitted)
    testing.expect_value(t,
        transfer_append(&store, first, []u8{4, 5}),
        Admission_Outcome.Byte_Limit_Exceeded)
    bytes, found := transfer_bytes(&store, first)
    testing.expect(t, found)
    testing.expect_value(t, len(bytes), 3)
    testing.expect_value(t, transfer_remove(&store, first), Handle_Outcome.Found)

    second, second_outcome := transfer_begin(&store, .Kitty, 8)

    testing.expect_value(t, second_outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, second.slot, first.slot)
    testing.expect(t, second.generation != first.generation)
    _, first_found := transfer_bytes(&store, first)
    testing.expect(t, !first_found)
}

// Verify GPU quota pressure coordinates every oldest-first native eviction.
@(test)
attachment_test_gpu_lru_eviction :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(
            attachment_capacity = 3, cpu_byte_limit = 16,
            gpu_byte_limit = 16), context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store)
    second, _ := attachment_test_admit(&store)
    third, _ := attachment_test_admit(&store)
    testing.expect_value(t, residency_admit(&store, first, 6).outcome,
        Admission_Outcome.Admitted)
    testing.expect_value(t, residency_admit(&store, second, 6).outcome,
        Admission_Outcome.Admitted)
    evicted: struct {
        ids: [4]Attachment_Id,
        count: int,
    }

    admission := residency_admit(
        &store, third, 12, attachment_test_evict, &evicted)

    testing.expect_value(t, admission.outcome, Admission_Outcome.Admitted)
    testing.expect_value(t, admission.eviction_count, 2)
    testing.expect_value(t, evicted.count, 2)
    testing.expect(t, evicted.ids[0] == first)
    testing.expect(t, evicted.ids[1] == second)
    testing.expect_value(t, store.gpu_byte_count, 12)
    testing.expect_value(t, store.diagnostics.gpu_evicted_bytes, 12)
}

// Verify visible or pinned attachments cannot be selected for GPU eviction.
@(test)
attachment_test_gpu_retention :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(
            attachment_capacity = 2, gpu_byte_limit = 8),
        context.allocator))
    defer store_destroy(&store)
    first, _ := attachment_test_admit(&store)
    second, _ := attachment_test_admit(&store)
    placement, _ := placement_admit(&store, attachment_test_placement(first))
    testing.expect_value(t, residency_admit(&store, first, 8).outcome,
        Admission_Outcome.Admitted)

    blocked := residency_admit(
        &store, second, 8, attachment_test_evict, nil)

    testing.expect_value(t, blocked.outcome, Admission_Outcome.No_Evictable_Entry)
    testing.expect_value(t, placement_remove(&store, placement), Handle_Outcome.Found)
}

// Verify native residency defers attachment deletion until display-owner teardown.
@(test)
attachment_test_residency_defers_removal :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(gpu_byte_limit = 8), context.allocator))
    defer store_destroy(&store)
    attachment, _ := attachment_test_admit(&store)
    testing.expect_value(t, residency_admit(&store, attachment, 4).outcome,
        Admission_Outcome.Admitted)
    testing.expect_value(t,
        attachment_set_protocol_retained(&store, attachment, false),
        Handle_Outcome.Found)

    testing.expect_value(t, attachment_remove(&store, attachment), Handle_Outcome.Stale)
    testing.expect(t, attachment_removal_requested(&store, attachment))
    payload, found := attachment_payload(&store, attachment)
    testing.expect(t, found)
    testing.expect_value(t, len(payload.bytes), 4)

    testing.expect_value(t, residency_remove(&store, attachment), Handle_Outcome.Found)
    testing.expect_value(t, attachment_remove(&store, attachment), Handle_Outcome.Found)
}

// Verify the renderer boundary transports no Raylib or mutable terminal state.
@(test)
attachment_test_renderer_capability :: proc(t: ^testing.T) {
    observed: Raster_Draw_Request
    renderer := Raster_Renderer{
        user_data = &observed,
        draw = attachment_test_draw,
    }
    request := Raster_Draw_Request{
        attachment_id = {slot = 3, generation = 7},
        source = {x = 1, y = 2, width = 4, height = 5},
        destination = {x = 10, y = 20, width = 30, height = 40},
        clip = {width = 80, height = 60},
        z_index = -2,
    }

    testing.expect(t, renderer.draw(renderer.user_data, request))

    testing.expect(t, observed.attachment_id == request.attachment_id)
    testing.expect_value(t, observed.destination.width, f32(30))
    testing.expect_value(t, observed.z_index, -2)
}

// Verify snapshots filter screens and sort equal-z placements by stable slot order.
@(test)
attachment_test_collects_render_order :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(placement_capacity = 4), context.allocator))
    defer store_destroy(&store)
    attachment, _ := attachment_test_admit(&store)
    first := attachment_test_placement(attachment)
    first.geometry.z_index = 3
    second := first
    second.geometry.column = 4
    second.geometry.z_index = -1
    third := first
    third.geometry.column = 5
    third.geometry.z_index = -1
    alternate := first
    alternate.geometry.screen = .Alternate
    placement_admit(&store, first)
    placement_admit(&store, second)
    placement_admit(&store, third)
    placement_admit(&store, alternate)

    output: [4]Placement_Metadata
    count := placements_collect(&store, .Primary, output[:])

    testing.expect_value(t, count, 3)
    testing.expect_value(t, output[0].geometry.column, 4)
    testing.expect_value(t, output[1].geometry.column, 5)
    testing.expect_value(t, output[2].geometry.column, 3)
}

// Verify Sixel publication retires only an older resident at the same position.
@(test)
attachment_test_replaces_resident_sixel_position :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(&store, attachment_test_limits(
        attachment_capacity = 4, placement_capacity = 4,
        cpu_byte_limit = 32, gpu_byte_limit = 16), context.allocator))
    defer store_destroy(&store)
    old_sixel, _ := attachment_test_admit(&store, false, .Sixel)
    current_sixel, _ := attachment_test_admit(&store, false, .Sixel)
    pending_sixel, _ := attachment_test_admit(&store, false, .Sixel)
    iterm2, _ := attachment_test_admit(&store, origin = .Iterm2)
    placement_admit(&store, attachment_test_placement(old_sixel))
    placement_admit(&store, attachment_test_placement(current_sixel))
    placement_admit(&store, attachment_test_placement(pending_sixel))
    placement_admit(&store, attachment_test_placement(iterm2))
    testing.expect_value(t,
        residency_admit(&store, old_sixel, 4).outcome, Admission_Outcome.Admitted)
    testing.expect_value(t,
        residency_admit(&store, current_sixel, 4).outcome, Admission_Outcome.Admitted)
    testing.expect_value(t,
        residency_admit(&store, iterm2, 4).outcome, Admission_Outcome.Admitted)

    removed := placements_remove_resident_position_origin_except(
        &store, attachment_test_placement(current_sixel).geometry,
        .Sixel, current_sixel)

    testing.expect_value(t, removed, 1)
    testing.expect_value(t, store.placement_count, 3)
    testing.expect(t, attachment_removal_requested(&store, old_sixel))
    testing.expect(t, !attachment_removal_requested(&store, pending_sixel))
    output: [4]Placement_Metadata
    count := placements_collect(&store, .Primary, output[:])
    testing.expect_value(t, count, 3)
    testing.expect_value(t, output[0].attachment_id, current_sixel)
    testing.expect_value(t, output[1].attachment_id, pending_sixel)
    testing.expect_value(t, output[2].attachment_id, iterm2)
}