#+test
package termattachment

import "core:testing"

// Admit one retained two-pixel Kitty root for mutation tests.
kitty_animation_test_root :: proc(t: ^testing.T, store: ^Store) -> Attachment_Id {
    pixels := [8]u8{255, 0, 0, 255, 0, 0, 255, 255}
    id, outcome := attachment_admit(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 2, height = 1},
        },
        payload = pixels[:],
        payload_format = .Rgba8,
        payload_stride = 8,
        protocol_retained = true,
    })
    testing.expect_value(t, outcome, Admission_Outcome.Admitted)
    return id
}

// Verify append and edit atomically convert a static root into full canvases.
@(test)
kitty_animation_test_append_and_edit :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 256), context.allocator))
    defer store_destroy(&store)
    id := kitty_animation_test_root(t, &store)
    green := [4]u8{0, 255, 0, 255}

    outcome := kitty_animation_mutate_frame(&store, id, {
        pixels = green[:], format = .Rgba8, width = 1, height = 1,
        destination_x = 1, base_frame = 1, gap_ms = 25,
        gap_specified = true, overwrite = true,
    })

    testing.expect_value(t, outcome, Animation_Mutation_Outcome.Found)
    animation, found := animation_view(&store, id)
    testing.expect(t, found)
    testing.expect_value(t, animation.timeline.frame_count, 2)
    testing.expect_value(t, animation.frames[0].duration_ns, u64(40_000_000))
    testing.expect_value(t, animation.frames[1].duration_ns, u64(25_000_000))
    testing.expect_value(t, animation.pixels[8], u8(255))
    testing.expect_value(t, animation.pixels[12], u8(0))
    testing.expect_value(t, animation.pixels[13], u8(255))

    transparent_blue := [4]u8{0, 0, 255, 128}
    testing.expect_value(t, kitty_animation_mutate_frame(&store, id, {
        pixels = transparent_blue[:], format = .Rgba8, width = 1, height = 1,
        edit_frame = 2,
    }), Animation_Mutation_Outcome.Found)
    edited, edited_found := animation_view(&store, id)
    testing.expect(t, edited_found)
    testing.expect_value(t, edited.frames[1].duration_ns, u64(25_000_000))
    testing.expect_value(t, edited.pixels[8], u8(127))
    testing.expect_value(t, edited.pixels[10], u8(128))
}

// Verify quota rejection leaves the exact static root and accounting untouched.
@(test)
kitty_animation_test_quota_rollback :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 32), context.allocator))
    defer store_destroy(&store)
    id := kitty_animation_test_root(t, &store)
    original_bytes := store.cpu_byte_count
    patch := [4]u8{1, 2, 3, 4}

    outcome := kitty_animation_mutate_frame(&store, id, {
        pixels = patch[:], format = .Rgba8, width = 1, height = 1,
    })

    testing.expect_value(t, outcome, Animation_Mutation_Outcome.Capacity_Exceeded)
    testing.expect_value(t, store.cpu_byte_count, original_bytes)
    payload, found := attachment_payload(&store, id)
    testing.expect(t, found)
    testing.expect_value(t, payload.bytes[0], u8(255))
    testing.expect_value(t, store.animated_attachment_count, 0)
}

// Compose the two retained frames and verify the resulting second-frame pixel.
kitty_animation_test_expect_composition :: proc(
    t: ^testing.T, store: ^Store, id: Attachment_Id) {
    testing.expect_value(t, kitty_animation_compose(store, id, {
        source_frame = 1, destination_frame = 2,
        source_x = 0, destination_x = 1, width = 1, height = 1,
        overwrite = true,
    }), Animation_Mutation_Outcome.Found)
    testing.expect_value(t, kitty_animation_compose(store, id, {
        source_frame = 1, destination_frame = 1,
        source_x = 0, destination_x = 0, width = 1, height = 1,
        overwrite = true,
    }), Animation_Mutation_Outcome.Found)
    composed, found := animation_view(store, id)
    testing.expect(t, found)
    testing.expect_value(t, composed.pixels[12], u8(255))
    testing.expect_value(t, composed.pixels[13], u8(0))
}

// Apply animation timing controls and verify the normalized timeline.
kitty_animation_test_expect_control :: proc(
    t: ^testing.T, store: ^Store, id: Attachment_Id) {
    testing.expect_value(t, kitty_animation_control(store, id, {
        frame_number = 1, gap_ms = -1,
        gap_specified = true, loop_count = 3,
    }), Animation_Mutation_Outcome.Found)
    controlled, found := animation_view(store, id)
    testing.expect(t, found)
    testing.expect_value(t, controlled.frames[0].duration_ns, u64(0))
    testing.expect_value(t, controlled.timeline.repeat_count, u32(2))
    testing.expect(t, !controlled.timeline.infinite)
}

// Verify composition, negative gaps, loop encoding, and deletion share one identity.
@(test)
kitty_animation_test_compose_control_and_delete :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 256), context.allocator))
    defer store_destroy(&store)
    id := kitty_animation_test_root(t, &store)
    green := [4]u8{0, 255, 0, 255}
    testing.expect_value(t, kitty_animation_mutate_frame(&store, id, {
        pixels = green[:], format = .Rgba8, width = 1, height = 1,
        destination_x = 1, base_frame = 1, gap_ms = 30,
        gap_specified = true, overwrite = true,
    }), Animation_Mutation_Outcome.Found)

    kitty_animation_test_expect_composition(t, &store, id)
    kitty_animation_test_expect_control(t, &store, id)
    testing.expect_value(t, kitty_animation_delete_frames(
        &store, id, 2, false), Animation_Mutation_Outcome.Found)
    reduced, reduced_found := animation_view(&store, id)
    testing.expect(t, reduced_found)
    testing.expect_value(t, reduced.timeline.frame_count, 1)
    testing.expect_value(t, reduced.timeline.cycle_duration_ns, u64(0))
}

// Verify rejected frame and control durations leave pixels and timing unchanged.
@(test)
kitty_animation_test_duration_limit_rollback :: proc(t: ^testing.T) {
    limits := attachment_test_limits(cpu_byte_limit = 256)
    limits.animation_max_frame_duration_ns = 50_000_000
    limits.animation_duration_ns_limit = 60_000_000
    store: Store
    testing.expect(t, store_init(&store, limits, context.allocator))
    defer store_destroy(&store)
    id := kitty_animation_test_root(t, &store)
    patch := [4]u8{0, 255, 0, 255}

    testing.expect_value(t, kitty_animation_mutate_frame(&store, id, {
        pixels = patch[:], format = .Rgba8, width = 1, height = 1,
        gap_ms = 30, gap_specified = true,
    }), Animation_Mutation_Outcome.Invalid)
    payload, static_found := attachment_payload(&store, id)
    testing.expect(t, static_found)
    testing.expect_value(t, payload.bytes[0], u8(255))
    testing.expect_value(t, kitty_animation_mutate_frame(&store, id, {
        pixels = patch[:], format = .Rgba8, width = 1, height = 1,
        gap_ms = 20, gap_specified = true,
    }), Animation_Mutation_Outcome.Found)
    before, found := animation_view(&store, id)
    testing.expect(t, found)
    testing.expect_value(t, kitty_animation_control(
        &store, id, {
            frame_number = 2, gap_ms = 50, gap_specified = true,
        }), Animation_Mutation_Outcome.Invalid)
    after, after_found := animation_view(&store, id)
    testing.expect(t, after_found)
    testing.expect_value(t,
        after.timeline.cycle_duration_ns, before.timeline.cycle_duration_ns)
    testing.expect_value(t,
        after.frames[1].duration_ns, before.frames[1].duration_ns)
}

// Verify one valid frame selector cannot mask another invalid one-based selector.
@(test)
kitty_animation_test_frame_index_validation_is_cumulative :: proc(t: ^testing.T) {
    store: Store
    testing.expect(t, store_init(
        &store, attachment_test_limits(cpu_byte_limit = 256), context.allocator))
    defer store_destroy(&store)
    id := kitty_animation_test_root(t, &store)
    patch := [4]u8{0, 255, 0, 255}

    outcome := kitty_animation_mutate_frame(&store, id, {
        pixels = patch[:], format = .Rgba8, width = 1, height = 1,
        edit_frame = 2, base_frame = 1,
    })

    testing.expect_value(t, outcome, Animation_Mutation_Outcome.Invalid)
    _, animated := animation_view(&store, id)
    testing.expect(t, !animated)
}