package view_core

import viewmodel "../model"

import dynviewmodel "../../dynview/model"

import geometry "../../core/geometry"
import storage "../../core/storage"


import "core:mem"
import "core:testing"

//   Verify hover and press ownership retain the selected arena-backed target identity.
@(test)
copy_interaction_tracks_hovered_and_pressed_target :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    testing.expect(t, storage.arena_owner_init(&arena, 64*uint(mem.Kilobyte)))
    defer storage.arena_owner_destroy(&arena)
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    cache := &runtime^.compile_cache
    testing.expect_value(t, storage.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, dynviewmodel.DYNVIEW_MAX_COMMANDS, &arena),
        storage.Bounded_Builder_Status.Ok)
    target := dynviewmodel.Dynview_Copy_Hit_Target{
        block_id = 12,
        rect = {x = 10, y = 20, width = 16, height = 16},
    }
    testing.expect_value(t, storage.bounded_element_builder_append(
        &cache^.copy_hit_target_builder, []dynviewmodel.Dynview_Copy_Hit_Target{target}),
        storage.Bounded_Builder_Status.Ok)
    cache^.copy_hit_targets, _ = storage.bounded_element_builder_view(
        &cache^.copy_hit_target_builder)
    cache^.copy_hit_target_count = 1

    hovered := copy_icon_find_hovered_index(cache, geometry.Vector2{12, 22})
    copy_icon_update_hover_state(runtime, cache, hovered)
    owner: viewmodel.Ui_Press_Owner_State
    copy_icon_begin_press_if_hovered(runtime, cache, hovered, {
        mouse_pressed = {.Left},
    }, &owner)

    testing.expect_value(t, hovered, 0)
    testing.expect(t, runtime^.copy_icon_hover_active)
    testing.expect_value(t, runtime^.copy_icon_hover_block_id, i32(12))
    testing.expect(t, runtime^.copy_icon_press_active)
    testing.expect_value(t, runtime^.copy_icon_press_block_id, i32(12))
    testing.expect_value(t, owner.kind, viewmodel.Ui_Press_Owner_Kind.Copy_Icon)
}

//   Verify copying resolves the exact payload span owned by a hit target.
@(test)
copy_interaction_resolves_target_payload_span :: proc(t: ^testing.T) {
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    payload := []u8{'a', 'b', 'c', 'd', 'e', 'f'}
    runtime^.compile_cache.compiled_copy_payload = payload
    runtime^.compile_cache.compiled_copy_payload_len = 6
    runtime^.compile_cache.copy_hit_targets = []dynviewmodel.Dynview_Copy_Hit_Target{{
        payload_offset = 2,
        payload_len = 3,
    }}
    runtime^.compile_cache.copy_hit_target_count = 1

    testing.expect_value(t, copy_target_payload(runtime, 0), "cde")
    testing.expect_value(t, copy_target_payload(runtime, 1), "")
}