package view_core

import "../../core"

import "core:mem"
import "core:testing"

import rl "vendor:raylib"

//   Verify hover and press ownership retain the selected arena-backed target identity.
@(test)
copy_interaction_tracks_hovered_and_pressed_target :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena, 64*uint(mem.Kilobyte)))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    runtime := new(core.Dynview_System, allocator)
    cache := &runtime^.compile_cache
    testing.expect_value(t, core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, core.DYNVIEW_MAX_COMMANDS, &arena),
        core.Bounded_Builder_Status.Ok)
    target := core.Dynview_Copy_Hit_Target{
        block_id = 12,
        rect = {x = 10, y = 20, width = 16, height = 16},
    }
    testing.expect_value(t, core.bounded_element_builder_append(
        &cache^.copy_hit_target_builder, []core.Dynview_Copy_Hit_Target{target}),
        core.Bounded_Builder_Status.Ok)
    cache^.copy_hit_targets, _ = core.bounded_element_builder_view(
        &cache^.copy_hit_target_builder)
    cache^.copy_hit_target_count = 1

    hovered := copy_icon_find_hovered_index(cache, rl.Vector2{12, 22})
    copy_icon_update_hover_state(runtime, cache, hovered)
    copy_icon_begin_press_if_hovered(runtime, cache, hovered, {
        left_pressed = true,
    })

    testing.expect_value(t, hovered, 0)
    testing.expect(t, runtime^.copy_icon_hover_active)
    testing.expect_value(t, runtime^.copy_icon_hover_block_id, i32(12))
    testing.expect(t, runtime^.copy_icon_press_active)
    testing.expect_value(t, runtime^.copy_icon_press_block_id, i32(12))
}

//   Verify copying resolves the exact payload span owned by a hit target.
@(test)
copy_interaction_resolves_target_payload_span :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena, 64*uint(mem.Kilobyte)))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    runtime := new(core.Dynview_System, allocator)
    payload := []u8{'a', 'b', 'c', 'd', 'e', 'f'}
    runtime^.compile_cache.compiled_copy_payload = payload
    runtime^.compile_cache.compiled_copy_payload_len = 6
    runtime^.compile_cache.copy_hit_targets = []core.Dynview_Copy_Hit_Target{{
        payload_offset = 2,
        payload_len = 3,
    }}
    runtime^.compile_cache.copy_hit_target_count = 1

    testing.expect_value(t, copy_target_payload(runtime, 0), "cde")
    testing.expect_value(t, copy_target_payload(runtime, 1), "")
}