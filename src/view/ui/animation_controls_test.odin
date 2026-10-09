#+test
package ui

import viewmodel "model"
import bridgemodel "../../bridge/model"
import collections "../../collections"
import userdata "../../userdata"
import geometry "../../core/geometry"
import app_core "../../core"
import testing "core:testing"
import uianimation "animation"
import uisemantics "semantics"
import theme "theme"
import uuid "core:encoding/uuid"
import native "../native"

// Build one selected animation with a live collection store for control tests.
animation_controls_test_state :: proc(
    t: ^testing.T,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) ->
    (state: ^app_core.Euclid_General_State, store: ^userdata.Store) {
    state = make_shell_test_state(t)
    store = new(userdata.Store, context.allocator)
    collections.initialize(&state^.preferences_runtime.collections_state)
    state^.preferences_runtime.settings_store = store
    animation^.stable_id[0] = 71
    animation^.node_kind = .Animation
    ji^.selected_animation = animation
    state^.julia_interface = ji
    state^.ui_runtime.ui_regions.world_rect = {0, 0, 640, 480}
    return
}

// Click and release the prepared Favorites slot through ordinary pointer input.
animation_controls_test_click_favorite :: proc(
    state: ^app_core.Euclid_General_State) {
    slots := uianimation.animation_control_layout_slots(
        geometry.Rectangle(state^.ui_runtime.ui_regions.world_rect), true)
    _ = uianimation.prepare_animation_controls(state, {
        mouse_position = {slots.favorite.x + slots.favorite.width * 0.5,
            slots.favorite.y + slots.favorite.height * 0.5},
        mouse_pressed = {.Left}, mouse_down = {.Left},
    })
    _ = uianimation.prepare_animation_controls(state, {
        mouse_position = {slots.favorite.x + slots.favorite.width * 0.5,
            slots.favorite.y + slots.favorite.height * 0.5},
        mouse_released = {.Left},
    })
}

// Repeated star activation removes and re-appends with a fresh ordered placement.
@(test)
animation_controls_favorites_toggle_and_reappend :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    first, second: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &first)
    defer {
        free(store, context.allocator)
        destroy_shell_test_state(state)
    }
    state^.ui_runtime.simulation_paused = true
    selected_key: uuid.Identifier
    selected_key[0] = 99
    state^.ui_runtime.selected_tree_item_id = selected_key
    animation_controls_test_click_favorite(state)
    first_entry_id := state^.preferences_runtime.collections_state.entries[0].id
    ji.selected_animation = &second
    second.stable_id[0] = 72
    second.node_kind = .Animation
    animation_controls_test_click_favorite(state)
    ji.selected_animation = &first
    animation_controls_test_click_favorite(state)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entry_count, 1)
    animation_controls_test_click_favorite(state)
    set := &state^.preferences_runtime.collections_state
    testing.expect_value(t, set^.entries[0].animation_id, second.stable_id)
    testing.expect_value(t, set^.entries[1].animation_id, first.stable_id)
    testing.expect(t, set^.entries[1].id != first_entry_id)
    testing.expect_value(t, state^.preferences_runtime.collection_mutation_count, 4)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(4))
    testing.expect_value(t, ji.selected_animation, &first)
    testing.expect(t, state^.ui_runtime.simulation_paused)
    testing.expect(t, !ji.pending_animation_reset)
    testing.expect_value(t, state^.ui_runtime.selected_tree_item_id, selected_key)
}

// Keyboard activation uses the semantic button action and exposes checked focus state.
@(test)
animation_controls_favorite_semantics_and_keyboard_activation :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer {
        free(store, context.allocator)
        destroy_shell_test_state(state)
    }
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    state^.ui_runtime.semantic_focus = focus
    _, accepted := uianimation.toggle_animation_favorite(state, &animation)
    testing.expect(t, accepted)
    testing.expect(t, uisemantics.semantic_begin(focus))
    _ = uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t, uisemantics.semantic_publish(focus),
        viewmodel.Ui_Semantic_Status.Ok)
    id := uisemantics.semantic_control_id(
        .Animation_Control, uianimation.ANIMATION_FAVORITE_BUTTON_ID)
    snapshot := uisemantics.semantic_snapshot(focus)
    index := uisemantics.semantic_node_index(snapshot, id)
    node := snapshot^.nodes[index]
    testing.expect(t, .Checked in node.states && .Tab_Stop in node.states)
    testing.expect_value(t, node.traversal_order, u16(2))
    testing.expect(t, .Activate in node.actions)
    testing.expect(t, uisemantics.semantic_append_command(focus, {
        target = id, kind = .Activate,
    }))
    testing.expect(t, uisemantics.semantic_begin(focus))
    _ = uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entry_count, 0)
    testing.expect_value(t, ji.selected_animation, &animation)
    testing.expect_value(t, ji.pending_animation_reset, false)
}

// Terminal and missing selections do not create or route a Favorites control.
@(test)
animation_controls_exclude_ineligible_favorite_targets :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer {
        free(store, context.allocator)
        destroy_shell_test_state(state)
    }
    animation.node_kind = .Terminal
    prepared := uianimation.prepare_animation_controls(state, {})
    testing.expect(t, !prepared.favorite_visible)
    slots := uianimation.animation_control_layout_slots(
        geometry.Rectangle(state^.ui_runtime.ui_regions.world_rect), false)
    id, hit := uianimation.animation_control_hit_test(
        geometry.Rectangle(state^.ui_runtime.ui_regions.world_rect),
        state^.gif_capture_status.gif_capture_phase, false,
        {slots.favorite.x + 1, slots.favorite.y + 1})
    testing.expect(t, !hit)
    testing.expect_value(t, id, 0)
    ji.selected_animation = nil
    testing.expect(t, !uianimation.animation_favorite_eligible(&ji))
}

// Favorites publishes bounds and clipping from its right-side box rather than transport.
@(test)
animation_controls_favorite_semantics_use_separate_panel :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer {
        free(store, context.allocator)
        destroy_shell_test_state(state)
    }
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    state^.ui_runtime.semantic_focus = focus
    testing.expect(t, uisemantics.semantic_begin(focus))
    prepared := uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t, uisemantics.semantic_publish(focus),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(focus)
    id := uisemantics.semantic_control_id(
        .Animation_Control, uianimation.ANIMATION_FAVORITE_BUTTON_ID)
    index := uisemantics.semantic_node_index(snapshot, id)
    testing.expect(t, index >= 0)
    node := snapshot^.nodes[index]
    testing.expect_value(t, node.bounds, prepared.slots.favorite)
    testing.expect_value(t, node.clip_bounds, prepared.slots.favorite_panel)
}

// Offset and resized worlds keep matching control boxes apart and equally inset.
@(test)
animation_controls_separate_panels_follow_world_bounds :: proc(t: ^testing.T) {
    worlds := [3]geometry.Rectangle{
        {40, 70, 640, 480}, {20, 30, 360, 640}, {5, 10, 320, 240},
    }
    for world in worlds {
        slots := uianimation.animation_control_layout_slots(world, true)
        hidden := uianimation.animation_control_layout_slots(world, false)
        testing.expect_value(t, slots.panel, hidden.panel)
        testing.expect_value(t, hidden.favorite_panel, geometry.Rectangle{})
        testing.expect_value(t, hidden.favorite, geometry.Rectangle{})
        testing.expect_value(t, slots.panel.x,
            world.x + theme.ANIMATION_CONTROL_EDGE_INSET)
        testing.expect_value(t, slots.favorite_panel.x + slots.favorite_panel.width,
            world.x + world.width - theme.ANIMATION_CONTROL_EDGE_INSET)
        testing.expect_value(t, slots.favorite_panel.y + slots.favorite_panel.height,
            world.y + world.height - theme.ANIMATION_CONTROL_EDGE_INSET)
        testing.expect(t, slots.panel.x + slots.panel.width < slots.favorite_panel.x)
        testing.expect_value(t, slots.favorite_panel.height, slots.panel.height)
        testing.expect_value(t, slots.favorite.x - slots.favorite_panel.x,
            slots.refresh.x - slots.panel.x)
        id, hit := uianimation.animation_control_hit_test(world, .Idle, true,
            {slots.panel.x + slots.panel.width + 10, slots.favorite.y + 1})
        testing.expect(t, !hit)
        testing.expect_value(t, id, 0)
    }
}

// Both control groups encode the same panel chrome; ineligible selections omit Favorites.
@(test)
animation_controls_draw_separate_matching_panels :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer {
        free(store, context.allocator)
        destroy_shell_test_state(state)
    }
    vertices: [1024]native.Draw_Vertex
    indices: [2048]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    eligibility := [2]bool{true, false}
    for eligible in eligibility {
        animation.node_kind = .Animation if eligible else .Terminal
        prepared := uianimation.prepare_animation_controls(state, {})
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {640, 480}, {640, 480}))
        uianimation.draw_encoded_animation_controls(state, &encoder, prepared)
        panels := 0
        for vertex in vertices[:encoder.vertex_count] {
            if vertex.color == theme.UI_COMPONENT_BACKGROUND_COLOR {
                panels += 1
            }
        }
        testing.expect_value(t, panels, 8 if eligible else 4)
        testing.expect_value(t, vertices[0].position,
            geometry.Vector2{prepared.slots.panel.x, prepared.slots.panel.y})
    }
}

// Rounded hover backing stays inside the existing control hit rectangle.
@(test)
animation_controls_hover_geometry_preserves_hit_bounds :: proc(t: ^testing.T) {
    slots := uianimation.animation_control_layout_slots({0, 0, 640, 480}, true)
    rectangles := [3]geometry.Rectangle{
        slots.refresh, slots.pause, slots.favorite,
    }
    for rectangle, index in rectangles {
        shape := uianimation.animation_control_hover_geometry(rectangle)
        testing.expect(t, shape.radius > 0)
        for point in shape.boundary {
            testing.expect(t, point.x >= rectangle.x)
            testing.expect(t, point.x <= rectangle.x + rectangle.width)
            testing.expect(t, point.y >= rectangle.y)
            testing.expect(t, point.y <= rectangle.y + rectangle.height)
        }
        id, hit := uianimation.animation_control_hit_test(
            {0, 0, 640, 480}, .Idle, true,
            {rectangle.x + rectangle.width * 0.5,
                rectangle.y + rectangle.height * 0.5})
        testing.expect(t, hit)
        expected_id := uianimation.ANIMATION_REFRESH_BUTTON_ID
        if index == 1 {
            expected_id = uianimation.ANIMATION_PAUSE_BUTTON_ID
        } else if index == 2 {
            expected_id = uianimation.ANIMATION_FAVORITE_BUTTON_ID
        }
        testing.expect_value(t, id, expected_id)
    }
}

// Hover draws a uniform low-alpha rounded fill without overlapping triangles.
@(test)
animation_controls_hover_draws_rounded_light_highlight :: proc(t: ^testing.T) {
    vertices: [uianimation.ANIMATION_CONTROL_HOVER_POINTS + 1]native.Draw_Vertex
    indices: [uianimation.ANIMATION_CONTROL_HOVER_POINTS * 3]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {640, 480}, {640, 480}))
    rectangle := geometry.Rectangle{10, 20, 30, 30}
    draw_color := uianimation.draw_encoded_animation_control_backing(
        &encoder, rectangle, true, false, false)
    highlight := theme.UI_TEXT_COLOR
    highlight.a = 24
    testing.expect_value(t, encoder.vertex_count, len(vertices))
    testing.expect_value(t, encoder.index_count, len(indices))
    testing.expect_value(t, encoder.batch_count, 1)
    testing.expect_value(t, vertices[0].position,
        geometry.Vector2{rectangle.x + rectangle.width * 0.5,
            rectangle.y + rectangle.height * 0.5})
    for vertex in vertices {
        testing.expect_value(t, vertex.color, highlight)
    }
    animation_controls_expect_uniform_coverage(t, vertices[:], indices[:], rectangle)
    testing.expect_value(t, draw_color, theme.UI_TEXT_COLOR)
}

// Return the oriented edge area used to test encoded triangle coverage.
animation_controls_triangle_edge :: proc(
    first, second, point: geometry.Vector2) -> f32 {
    return (second.x - first.x) * (point.y - first.y) -
        (second.y - first.y) * (point.x - first.x)
}

// Sample encoded triangles to reject alpha overdraw, missing interiors, and square corners.
animation_controls_expect_uniform_coverage :: proc(
    t: ^testing.T, vertices: []native.Draw_Vertex, indices: []u32,
    rectangle: geometry.Rectangle) {
    for y in 0..<30 {
        for x in 0..<30 {
            point := geometry.Vector2{rectangle.x + f32(x) + 0.37,
                rectangle.y + f32(y) + 0.61}
            coverage := 0
            for index := 0; index < len(indices); index += 3 {
                first := vertices[indices[index]].position
                second := vertices[indices[index + 1]].position
                third := vertices[indices[index + 2]].position
                if animation_controls_triangle_edge(first, second, point) > 0 &&
                    animation_controls_triangle_edge(second, third, point) > 0 &&
                    animation_controls_triangle_edge(third, first, point) > 0 {
                    coverage += 1
                }
            }
            testing.expect(t, coverage <= 1)
            if x >= 7 && x < 23 || y >= 7 && y < 23 {
                testing.expect_value(t, coverage, 1)
            }
            if (x == 0 || x == 29) && (y == 0 || y == 29) {
                testing.expect_value(t, coverage, 0)
            }
        }
    }
}
