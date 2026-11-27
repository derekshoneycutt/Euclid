package builderui

import buildermodel "../../../animation/builder"
import core "../../../core"
import corecolor "../../../core/color"
import geometry "../../../core/geometry"
import input "../../input"
import native "../../native"
import projection "../../world/projection"
import viewmodel "../model"
import testing "core:testing"

// Create the minimum display state needed to exercise Builder board gestures.
builder_surface_test_state_create :: proc() -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state^.ui_runtime.layout.ui_regions.world_rect = {0, 0, 900, 500}
    projection.fit_iso_scale_to_viewport(&state^.iso_scale, 900, 500)
    state^.builder.tool = .Point
    state^.builder.color = {10, 20, 30, 255}
    state^.builder.brush_size = 7
    state^.ui_runtime.preferences.values.interface.enable_particle_effects = true
    return state
}

// Release the test-owned state with the same allocator used by its fixture.
builder_surface_test_state_destroy :: proc(state: ^core.Euclid_General_State) {
    free(state, context.allocator)
}

// Construct a focused pointer sample for one Builder gesture phase.
builder_surface_test_frame :: proc(
    position: geometry.Vector2,
    pressed, down, released: input.Input_Mouse_Buttons) -> input.Input_Frame {
    return {
        window_focused = true,
        mouse_position = {position.x, position.y},
        mouse_pressed = pressed,
        mouse_down = down,
        mouse_released = released,
    }
}

// Project one board coordinate through the configured display projection.
builder_surface_test_screen :: proc(
    state: ^core.Euclid_General_State,
    position: geometry.Vector3) -> geometry.Vector2 {
    return projection.iso_to_cartesian(position, state^.iso_scale)
}

// Add one completed visible point to the fixed Builder test fixture.
builder_surface_test_point :: proc(
    state: ^core.Euclid_General_State) -> buildermodel.Point_Identity {
    point: buildermodel.Point_Identity = {1, 1}
    state^.builder.generation = 1
    state^.builder.point_count = 1
    state^.builder.points[0] = {
        identity = point,
        position = {0.25, 0.35, 0},
        state = .Ready,
        visible = true,
        brush_size = 5,
    }
    return point
}

// Select a point with a gesture that moves but must not initiate dragging.
builder_surface_test_select_first :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    point: buildermodel.Point_Identity, press, moved: geometry.Vector2) {
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(press, {.Left}, {.Left}, {}), &result)
    testing.expect_value(t, state^.builder.selected_point, point)
    testing.expect(t, !state^.builder.drag_active)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(moved, {}, {.Left}, {}), &result)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(moved, {}, {}, {.Left}), &result)
    testing.expect_value(t, result.command.kind, Builder_Command_Kind.None)
}

// Selection consumes the first gesture; a later drag preserves the grab offset.
@(test)
builder_drag_requires_selection_and_tracks_offset :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    point := builder_surface_test_point(state)
    origin := state^.builder.points[0].position
    screen := builder_surface_test_screen(state, origin)
    press := screen + geometry.Vector2{3, 0}
    moved := press + geometry.Vector2{60, 20}
    builder_surface_test_select_first(t, state, point, press, moved)
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(press, {.Left}, {.Left}, {}), &result)
    testing.expect(t, state^.builder.drag_active)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(press + {2, 0}, {}, {.Left}, {}), &result)
    testing.expect(t, !state^.builder.points[0].preview_active)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(moved, {}, {.Left}, {}), &result)
    testing.expect(t, state^.builder.points[0].preview_active)
    preview := state^.builder.points[0].preview_position
    expected_screen := screen + (moved - press)
    actual_screen := builder_surface_test_screen(state, preview)
    delta := actual_screen - expected_screen
    testing.expect(t, delta.x * delta.x + delta.y * delta.y < 0.001)
    testing.expect_value(t, state^.builder.points[0].position, origin)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(moved, {}, {}, {.Left}), &result)
    testing.expect_value(t, result.command.kind, Builder_Command_Kind.Move_Point)
    testing.expect_value(t, result.command.position, preview)
    testing.expect(t, !state^.builder.drag_active)
}

// Cancellation restores a previous pending preview and never submits a move.
@(test)
builder_drag_cancellation_restores_pending_preview :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    point := builder_surface_test_point(state)
    state^.builder.selected_point = point
    record := &state^.builder.points[0]
    record^.preview_active = true
    record^.preview_position = {0.4, 0.4, 0}
    record^.preview_command = {1, 4}
    original := record^.preview_position
    press := builder_surface_test_screen(state, original)
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(press, {.Left}, {.Left}, {}), &result)
    builder_prepare_board_gesture(
        state, builder_surface_test_frame(press + {40, 10}, {}, {.Left}, {}), &result)
    testing.expect(t, record^.preview_position != original)
    escape := builder_surface_test_frame(press, {}, {.Left}, {})
    events := [?]input.Input_Event{{
        kind = .Press,
        key = .Escape,
    }}
    escape.events = events[:]
    builder_prepare_board_gesture(state, escape, &result)
    testing.expect(t, !state^.builder.drag_active)
    testing.expect(t, record^.preview_active)
    testing.expect_value(t, record^.preview_position, original)
    testing.expect_value(t, result.command.kind, Builder_Command_Kind.None)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// Queue backpressure restores the prior admitted position rather than the rejected drag.
@(test)
builder_rejected_move_restores_prior_preview :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    point := builder_surface_test_point(state)
    record := &state^.builder.points[0]
    record^.preview_active = true
    record^.preview_command = {1, 4}
    state^.builder.drag_original = {0.4, 0.4, 0}
    request: Builder_Command_Request = {
        kind = .Move_Point,
        point = point,
        position = {0.6, 0.6, 0},
    }
    builder_move_command_result(&state^.builder, request, {}, false)
    testing.expect(t, record^.preview_active)
    testing.expect_value(t, record^.preview_position, state^.builder.drag_original)
    record^.preview_command = {}
    builder_move_command_result(&state^.builder, request, {}, false)
    testing.expect(t, !record^.preview_active)
}

// Lost capture, focus, layout, and outside release discard uncommitted previews.
@(test)
builder_drag_cancels_on_interaction_loss :: proc(t: ^testing.T) {
    for mode in 0..<4 {
        state := builder_surface_test_state_create()
        point := builder_surface_test_point(state)
        state^.builder.selected_point = point
        press := builder_surface_test_screen(state, state^.builder.points[0].position)
        result: Builder_Surface_Preparation
        builder_prepare_board_gesture(
            state, builder_surface_test_frame(press, {.Left}, {.Left}, {}), &result)
        builder_prepare_board_gesture(
            state, builder_surface_test_frame(press + {30, 0}, {}, {.Left}, {}), &result)
        testing.expect(t, state^.builder.points[0].preview_active)
        switch mode {
        case 0:
            frame := builder_surface_test_frame(press, {}, {.Left}, {})
            frame.window_focused = false
            builder_prepare_board_gesture(state, frame, &result)
        case 1:
            state^.ui_runtime.input.press_owner = {}
            builder_prepare_board_gesture(
                state, builder_surface_test_frame(press, {}, {.Left}, {}), &result)
        case 2:
            builder_release_surface_capture(state)
        case 3:
            builder_prepare_board_gesture(state,
                builder_surface_test_frame({-10, -10}, {}, {}, {.Left}), &result)
        }
        testing.expect(t, !state^.builder.drag_active)
        testing.expect(t, !state^.builder.points[0].preview_active)
        testing.expect_value(t, result.command.kind, Builder_Command_Kind.None)
        builder_surface_test_state_destroy(state)
    }
}

// Keep the initial empty workspace limited to its fixed Point control.
@(test)
builder_empty_workspace_hides_contextual_options :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.tool = .None
    testing.expect(t, !builder_contextual_options_visible(&state^.builder))
}

// Show style controls for an armed tool, placement, or selected point.
@(test)
builder_contextual_options_follow_builder_state :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    testing.expect(t, builder_contextual_options_visible(&state^.builder))

    state^.builder.tool = .None
    state^.builder.placement_phase = .Hover
    testing.expect(t, builder_contextual_options_visible(&state^.builder))

    state^.builder.placement_phase = .Idle
    state^.builder.selected_point = {
        generation = 1,
        id = 1,
    }
    testing.expect(t, builder_contextual_options_visible(&state^.builder))
}

// Mark only the color currently used by the point or selected-point draft.
@(test)
builder_palette_selection_matches_active_color :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.color = builder_palette_color(0)
    testing.expect(t, builder_palette_is_selected(&state^.builder, 0))
    testing.expect(t, !builder_palette_is_selected(&state^.builder, 1))

    state^.builder.selected_point = {
        generation = 1,
        id = 1,
    }
    state^.builder.style_draft_color = builder_palette_color(2)
    testing.expect(t, builder_palette_is_selected(&state^.builder, 2))
    testing.expect(t, !builder_palette_is_selected(&state^.builder, 0))
}

// Keep the neutral and Point toolbar controls square and left-aligned.
@(test)
builder_toolbar_controls_are_square_and_left_aligned :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    layout := builder_surface_layout(state, {0, 0, 400, 180}, {0, 0, 400, 180})
    testing.expect_value(t, layout.select_tool.width, layout.select_tool.height)
    testing.expect_value(t, layout.tool.width, layout.tool.height)
    testing.expect(t, layout.select_tool.x < layout.tool.x)
    testing.expect(t, layout.select_tool.x < layout.options_section.x +
        layout.options_section.width * 0.5)
}

// Clear selection and disarm Point while retaining the next-point style.
@(test)
builder_select_button_returns_to_neutral_mode :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.selected_point = {
        generation = 1,
        id = 2,
    }
    state^.builder.style_draft_point = state^.builder.selected_point
    state^.builder.placement_phase = .Hover
    state^.builder.placement_status = .Point_Queued
    color_before := state^.builder.color
    brush_before := state^.builder.brush_size
    builder_clear_selection(&state^.builder)
    testing.expect_value(t, state^.builder.tool, buildermodel.Tool_Mode.None)
    testing.expect_value(t, state^.builder.selected_point,
        buildermodel.Point_Identity{})
    testing.expect_value(t, state^.builder.placement_phase,
        buildermodel.Placement_Phase.Idle)
    testing.expect_value(t, state^.builder.placement_status,
        buildermodel.Placement_Status.Ready)
    testing.expect_value(t, state^.builder.color, color_before)
    testing.expect_value(t, state^.builder.brush_size, brush_before)

    state^.builder.placement_phase = .Waiting
    state^.builder.placement_status = .Point_Queued
    builder_clear_selection(&state^.builder)
    testing.expect_value(t, state^.builder.placement_phase,
        buildermodel.Placement_Phase.Waiting)
    testing.expect_value(t, state^.builder.placement_status,
        buildermodel.Placement_Status.Point_Queued)
}

// Admit dirty inspector edits before the Select button clears its point.
@(test)
builder_select_button_waits_for_dirty_style_admission :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.generation = 1
    point: buildermodel.Point_Identity = {
        generation = 1,
        id = 3,
    }
    state^.builder.selected_point = point
    state^.builder.style_draft_point = point
    state^.builder.style_draft_color_dirty = true
    state^.builder.style_draft_color = builder_palette_color(1)
    result: Builder_Surface_Preparation
    builder_apply_select_button_activation(state, &result)
    testing.expect_value(t, result.command.kind, Builder_Command_Kind.Edit_Style)
    testing.expect_value(t, state^.builder.selected_point, point)
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.Clear_Selection)

    builder_style_command_result(&state^.builder, result.command, true)
    builder_prepare_pending_action(state, &result.command)
    testing.expect_value(t, state^.builder.selected_point,
        buildermodel.Point_Identity{})
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.None)
}

// A captured gesture emits the release coordinate with its press-time style.
@(test)
builder_gesture_uses_release_position_and_captured_style :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    start := builder_surface_test_screen(state, {0.1, 0.2, 0})
    pressed := builder_surface_test_frame(start, {.Left}, {.Left}, {})
    builder_prepare_board_gesture(state, pressed, nil)
    testing.expect(t, state^.builder.gesture_active)

    state^.builder.color = {90, 80, 70, 255}
    state^.builder.brush_size = 12
    moved := builder_surface_test_screen(state, {0.25, 0.35, 0})
    moving := builder_surface_test_frame(moved, {}, {.Left}, {})
    builder_prepare_board_gesture(state, moving, nil)
    expected_preview, preview_valid := projection.cartesian_to_iso_board(
        moved, state^.iso_scale, false)
    testing.expect(t, preview_valid)
    testing.expect_value(t, state^.builder.placement_position, expected_preview)
    released := builder_surface_test_screen(state, {0.3, 0.4, 0})
    frame := builder_surface_test_frame(released, {}, {}, {.Left})
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(state, frame, &result)
    expected, valid := projection.cartesian_to_iso_board(
        released, state^.iso_scale, false)
    testing.expect(t, valid)
    testing.expect(t, result.placement.active)
    testing.expect_value(t, result.placement.position, expected)
    testing.expect_value(t,
        result.placement.color, corecolor.Color_RGBA8{10, 20, 30, 255})
    testing.expect_value(t, result.placement.brush_size, f32(7))
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// Escape cancellation releases capture and cannot emit a placement on release.
@(test)
builder_gesture_escape_cancels_release :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    position := builder_surface_test_screen(state, {0.2, 0.3, 0})
    pressed := builder_surface_test_frame(position, {.Left}, {.Left}, {})
    builder_prepare_board_gesture(state, pressed, nil)
    events: [1]input.Input_Event
    events[0] = {
        kind = .Press,
        key = .Escape,
    }
    frame := builder_surface_test_frame(position, {}, {}, {.Left})
    frame.events = events[:]
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(state, frame, &result)
    testing.expect(t, !result.placement.active)
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// An outside-board release cancels rather than placing at a clamped position.
@(test)
builder_gesture_outside_release_is_cancelled :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    position := builder_surface_test_screen(state, {0.2, 0.3, 0})
    pressed := builder_surface_test_frame(position, {.Left}, {.Left}, {})
    builder_prepare_board_gesture(state, pressed, nil)
    outside := builder_surface_test_frame({-10, -10}, {}, {}, {.Left})
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(state, outside, &result)
    testing.expect(t, !result.placement.active)
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// A release without Builder's press capture cannot create a point.
@(test)
builder_unowned_release_does_not_place :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    position := builder_surface_test_screen(state, {0.2, 0.3, 0})
    released := builder_surface_test_frame(position, {}, {}, {.Left})
    result: Builder_Surface_Preparation
    builder_prepare_board_gesture(state, released, &result)
    testing.expect(t, !result.placement.active)
    testing.expect(t, !state^.builder.gesture_active)
}

// Builder cannot replace a press owner already admitted by another UI control.
@(test)
builder_gesture_respects_existing_press_owner :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.ui_runtime.input.press_owner = {
        active = true,
        kind = .Text_Button,
        id = 12,
    }
    position := builder_surface_test_screen(state, {0.2, 0.3, 0})
    pressed := builder_surface_test_frame(position, {.Left}, {.Left}, {})
    builder_prepare_board_gesture(state, pressed, nil)
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect_value(t, state^.ui_runtime.input.press_owner.kind,
        viewmodel.Ui_Press_Owner_Kind.Text_Button)
    testing.expect_value(t, state^.ui_runtime.input.press_owner.id, 12)
}

// Account for presentation shake when aligning the board preview to the pointer.
@(test)
builder_preview_tracks_screen_shake :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.iso_scale.screenshake_trauma = 0.8
    state^.iso_scale.screenshake_phase = 0.5
    projection.screenshake_set_offsets_from_trauma(&state^.iso_scale)
    expected: geometry.Vector3 = {0.25, 0.35, 0}
    screen := builder_surface_test_screen(state, expected)
    screen.x += state^.iso_scale.screenshake_offset_x
    screen.y += state^.iso_scale.screenshake_offset_y
    frame := builder_surface_test_frame(screen, {}, {}, {})
    builder_prepare_board_gesture(state, frame, nil)
    testing.expect_value(t, state^.builder.placement_phase,
        buildermodel.Placement_Phase.Hover)
    delta := state^.builder.placement_position - expected
    testing.expect(t, delta.x * delta.x + delta.y * delta.y < 1.0e-10)
}

// Completing an admitted placement cannot overwrite a newer point selection.
@(test)
builder_waiting_point_completion_preserves_newer_selection :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    first: buildermodel.Point_Identity = {
        generation = 1,
        id = 1,
    }
    newer: buildermodel.Point_Identity = {
        generation = 1,
        id = 2,
    }
    state^.builder.generation = 1
    state^.builder.placement_phase = .Waiting
    state^.builder.point_count = 1
    state^.builder.points[0] = {
        identity = first,
        state = .Ready,
        visible = true,
    }
    builder_placement_result(&state^.builder, first, .Point_Queued)
    state^.builder.selected_point = newer
    builder_reconcile_waiting_point(&state^.builder)
    testing.expect_value(t, state^.builder.selected_point, newer)
    testing.expect(t, state^.builder.waiting_point.generation == 0)
    testing.expect_value(t, state^.builder.placement_phase,
        buildermodel.Placement_Phase.Idle)
}

// Keep the pending construction marker separate from the preview and ready-point passes.
@(test)
builder_waiting_marker_has_a_separate_draw_pass :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.generation = 1
    state^.ui_runtime.preferences.values.animation.scale_percent = 100
    state^.builder.waiting_point = {
        generation = 1,
        id = 1,
    }
    state^.builder.point_count = 1
    state^.builder.points[0] = {
        identity = state^.builder.waiting_point,
        state = .Pending,
        position = {0.25, 0.35, 0},
        color = {70, 130, 180, 255},
        brush_size = 5,
    }
    vertices: [256]native.Draw_Vertex
    indices: [768]u32
    batches: [4]native.Draw_Batch
    commands: [4]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {900, 500}, {900, 500}))
    builder_draw_placement_markers(state, &encoder, &state^.builder)
    testing.expect_value(t, encoder.vertex_count, 0)
    builder_draw_waiting_marker(state, &encoder, &state^.builder)
    testing.expect_value(t, encoder.vertex_count, 97)
    testing.expect_value(t, encoder.index_count, 288)
    state^.builder.points[0].state = .Ready
    builder_draw_waiting_marker(state, &encoder, &state^.builder)
    testing.expect_value(t, encoder.vertex_count, 97)
    state^.builder.points[0].state = .Failed
    builder_draw_waiting_marker(state, &encoder, &state^.builder)
    testing.expect_value(t, encoder.vertex_count, 97)
}

// Expand the selected point in its own color, then return to base size.
@(test)
builder_selection_breathing_scales_radius_and_respects_reduced_motion :: proc(
    t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    before := state^.builder
    start := builder_selection_breathing_scale(0, false)
    expanded := builder_selection_breathing_scale(
        BUILDER_SELECTION_BREATH_PERIOD_SECONDS * 0.5, false)
    returned := builder_selection_breathing_scale(
        BUILDER_SELECTION_BREATH_PERIOD_SECONDS, false)
    reduced := builder_selection_breathing_scale(0.5, true)
    testing.expect_value(t, start, f32(1))
    testing.expect_value(t, expanded, f32(1) + BUILDER_SELECTION_BREATH_MAX_EXPANSION)
    testing.expect_value(t, returned, f32(1))
    testing.expect_value(t, reduced, f32(1))
    testing.expect_value(t, state^.builder, before)
}

// Resolve overlapping points deterministically against the shaken screen projection.
@(test)
builder_hit_test_uses_stable_overlap_and_screen_shake :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.iso_scale.screenshake_trauma = 0.8
    state^.iso_scale.screenshake_phase = 0.5
    projection.screenshake_set_offsets_from_trauma(&state^.iso_scale)
    location: geometry.Vector3 = {0.25, 0.35, 0}
    state^.builder.generation = 4
    state^.builder.point_count = 2
    state^.builder.points[0] = {
        identity = {
            generation = 4,
            id = 1,
        },
        position = location,
        brush_size = 5,
        visible = true,
        state = .Ready,
    }
    state^.builder.points[1] = {
        identity = {
            generation = 4,
            id = 2,
        },
        position = location,
        brush_size = 5,
        visible = true,
        state = .Ready,
    }
    scale := state^.iso_scale
    _ = projection.screenshake_apply_origin(&scale, true)
    mouse := projection.iso_to_cartesian(location, scale)
    testing.expect_value(t, builder_hit_test(state, mouse),
        buildermodel.Point_Identity{4, 2})
}

// Hidden selection remains editable and showable until another selection is made.
@(test)
builder_hidden_selection_retains_inspector_identity :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    hidden: buildermodel.Point_Identity = {
        generation = 5,
        id = 1,
    }
    other: buildermodel.Point_Identity = {
        generation = 5,
        id = 2,
    }
    state^.builder.generation = 5
    state^.builder.point_count = 2
    state^.builder.points[0] = {
        identity = hidden,
        position = {0.2, 0.3, 0},
        color = {70, 130, 180, 255},
        brush_size = 5,
        visible = false,
        state = .Ready,
    }
    state^.builder.points[1] = {
        identity = other,
        position = {0.7, 0.8, 0},
        visible = true,
        state = .Ready,
    }
    builder_select_point(&state^.builder, hidden)
    testing.expect_value(t, state^.builder.selected_point, hidden)
    testing.expect_value(t, builder_hit_test(state, {0, 0}),
        buildermodel.Point_Identity{})
    command: Builder_Command_Request
    builder_apply_palette_choice(&state^.builder, 1, &command)
    testing.expect_value(t, command.point, hidden)
    testing.expect(t, command.style.color_set)
    state^.builder.style_draft_color_dirty = false
    builder_prepare_visibility_request(
        state, &state^.builder, true, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.Show_Point)
    testing.expect_value(t, command.point, hidden)
    builder_select_point(&state^.builder, other)
    testing.expect_value(t, state^.builder.selected_point, other)
}

// Flush a selected-point style draft before applying a deferred selection change.
@(test)
builder_pending_selection_waits_for_style_admission :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    first: buildermodel.Point_Identity = {
        generation = 2,
        id = 1,
    }
    second: buildermodel.Point_Identity = {
        generation = 2,
        id = 2,
    }
    state^.builder.generation = 2
    state^.builder.selected_point = first
    state^.builder.style_draft_point = first
    state^.builder.style_draft_color_dirty = true
    state^.builder.style_draft_color = {20, 30, 40, 255}
    state^.builder.point_count = 2
    state^.builder.points[0] = {
        identity = first,
        state = .Ready,
        visible = true,
    }
    state^.builder.points[1] = {
        identity = second,
        state = .Ready,
        visible = true,
    }
    builder_defer_action(state, .Select_Point, second)
    command: Builder_Command_Request
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.Edit_Style)
    testing.expect_value(t, command.point, first)
    testing.expect_value(t, state^.builder.selected_point, first)
    state^.builder.style_draft_color = {90, 80, 70, 255}
    builder_style_command_result(&state^.builder, command, true)
    testing.expect(t, state^.builder.style_draft_color_dirty)
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, command.style.color, state^.builder.style_draft_color)
    builder_style_command_result(&state^.builder, command, true)
    testing.expect(t, !state^.builder.style_draft_color_dirty)
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, state^.builder.selected_point, second)
    testing.expect_value(t, state^.builder.style_draft_color,
        state^.builder.points[1].color)
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.None)
}

// Keep a visibility intent attached to its selected point until FIFO admission.
@(test)
builder_pending_visibility_waits_for_style_admission :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    point: buildermodel.Point_Identity = {
        generation = 3,
        id = 7,
    }
    state^.builder.generation = 3
    state^.builder.selected_point = point
    state^.builder.style_draft_point = point
    state^.builder.style_draft_brush_dirty = true
    state^.builder.style_draft_brush_size = 9
    command: Builder_Command_Request
    builder_prepare_visibility_request(state, &state^.builder, false, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.Edit_Style)
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.Hide_Point)
    state^.builder.style_draft_brush_dirty = false
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.Hide_Point)
    testing.expect_value(t, command.point, point)
    builder_command_result(state, command, false)
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.Hide_Point)
    builder_command_result(state, command, true)
    testing.expect_value(t, state^.ui_runtime.builder.pending_action,
        viewmodel.Ui_Builder_Pending_Action.None)
}

// Coalesce pointer brush changes into one command on release.
@(test)
builder_brush_drag_emits_one_release_command :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    point: buildermodel.Point_Identity = {
        generation = 1,
        id = 4,
    }
    state^.builder.generation = 1
    state^.builder.selected_point = point
    state^.builder.style_draft_point = point
    state^.builder.style_draft_brush_size = 8
    state^.builder.style_draft_brush_dirty = true
    state^.ui_runtime.input.press_owner = {
        active = true,
        id = BUILDER_BRUSH_SLIDER_ID,
    }
    state^.ui_runtime.builder.pending_action =
        viewmodel.Ui_Builder_Pending_Action.Hide_Point
    state^.ui_runtime.builder.pending_point_generation = 1
    state^.ui_runtime.builder.pending_point_id = point.id
    command: Builder_Command_Request
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.None)
    state^.ui_runtime.input.press_owner = {}
    builder_prepare_pending_action(state, &command)
    testing.expect_value(t, command.kind, Builder_Command_Kind.Edit_Style)

    held_frame := builder_surface_test_frame({}, {}, {.Left}, {})
    held_result: Builder_Surface_Preparation = {
        brush = {
            changed = true,
            value = 8,
            sources = {.Pointer},
        },
    }
    builder_apply_brush_slider_change(state, held_frame, true, &held_result)
    testing.expect_value(t, held_result.command.kind, Builder_Command_Kind.None)
    release_frame := builder_surface_test_frame({}, {}, {}, {.Left})
    release_result: Builder_Surface_Preparation = {
        brush = {
            changed = true,
            value = 9,
            sources = {.Pointer},
        },
    }
    builder_apply_brush_slider_change(state, release_frame, true, &release_result)
    testing.expect_value(t, release_result.command.kind, Builder_Command_Kind.Edit_Style)
    testing.expect_value(t, release_result.command.point, point)
    testing.expect(t, release_result.command.style.brush_set)
    testing.expect_value(t, release_result.command.style.brush_size, f32(9))
}

// Keep the virtual Builder inspector scrollable and clipped to its fixed viewport.
@(test)
builder_inspector_scroll_moves_controls_inside_clip :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    result: Builder_Surface_Preparation = {
        layout = {
            panel = {0, 0, 200, 100},
            clip = {0, 0, 200, 100},
            tool = {10, 20, 160, 24},
            brush_row_y = 80,
            hide = {10, 110, 70, 24},
            show = {90, 110, 70, 24},
            status_y = 140,
            text_size = 16,
            scale = 1,
            content_height = 220,
        },
    }
    result.layout.palette[0] = {10, 80, 40, 24}
    frame := builder_surface_test_frame({100, 50}, {}, {}, {})
    frame.mouse_wheel_delta = -2
    builder_prepare_scroll(state, frame, true, &result)
    testing.expect(t, result.scroll.scroll_y_out > 0)
    testing.expect(t, result.scroll.scrollbar.has_scrollbar)
    testing.expect_value(t, result.layout.tool.y, f32(20))
    testing.expect_value(t, result.layout.palette[0].y,
        f32(80) - result.scroll.scroll_y_out)
    testing.expect_value(t, result.layout.panel, geometry.Rectangle{0, 0, 200, 100})
    testing.expect_value(t, result.layout.clip, geometry.Rectangle{0, 0, 200, 100})
}

// Release placement and scrollbar captures when the surface geometry changes.
@(test)
builder_layout_change_invalidates_capture :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.gesture_active = true
    state^.builder.placement_phase = .Held
    state^.ui_runtime.input.press_owner = {
        active = true,
        kind = .Builder_Placement,
        id = BUILDER_PLACEMENT_PRESS_ID,
    }
    builder_reconcile_capture_layout(state, {0, 0, 200, 200},
        {0, 0, 200, 200}, {0, 0, 900, 500})
    builder_reconcile_capture_layout(state, {0, 0, 200, 150},
        {0, 0, 200, 150}, {0, 0, 900, 500})
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// Modal overlays and focus loss release Builder-owned pointer captures.
@(test)
builder_surface_modal_overlay_releases_capture :: proc(t: ^testing.T) {
    state := builder_surface_test_state_create()
    defer builder_surface_test_state_destroy(state)
    state^.builder.gesture_active = true
    state^.ui_runtime.input.press_owner = {
        active = true,
        kind = .Builder_Placement,
        id = BUILDER_PLACEMENT_PRESS_ID,
    }
    state^.ui_runtime.context_menu.active = true
    testing.expect(t, !builder_reconcile_surface_interaction(state, true, true))
    testing.expect(t, !state^.builder.gesture_active)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)

    state^.ui_runtime.context_menu.active = false
    state^.ui_runtime.membership.active = true
    state^.ui_runtime.input.press_owner = {
        active = true,
        kind = .Builder_Placement,
        id = BUILDER_PLACEMENT_PRESS_ID,
    }
    testing.expect(t, !builder_reconcile_surface_interaction(state, true, true))
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}
