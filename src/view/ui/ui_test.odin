package ui

import viewmodel "../model"

import bridgemodel "../../bridge/model"

import dynviewmodel "../../dynview/model"

import "core:testing"

import app_core "../../core"
import app_dynview "../../dynview"
import "../input"

import rl "vendor:raylib"

//   Verify the baseline UI regions are valid and mutually consistent.
@(test)
ui_regions_baseline_is_valid_and_consistent :: proc(t: ^testing.T) {
    // Verifies baseline UI region construction is internally consistent and matches fixed panel sizing contracts.
    regions := compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT)

    testing.expect(t, validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, VIEW_WIDTH)
    testing.expect_value(t, regions.world_rect.height, VIEW_HEIGHT)
    testing.expect_value(
        t, regions.tree_rect.x, VIEW_WIDTH + TREE_PANEL_PADDING)
    testing.expect_value(
        t, regions.text_rect.y, VIEW_HEIGHT + TREE_PANEL_PADDING)
    testing.expect_value(t, regions.settings_rect.width, regions.gif_rect.width)
    testing.expect_value(t, regions.settings_rect.height, regions.gif_rect.height)
    testing.expect(t, regions.terminal_rect.width >= 0)
    testing.expect(t, regions.terminal_rect.height >= 0)
}

//   Verify split coordinates preserve minimum sizes for all four panes.
@(test)
ui_regions_clamp_all_pane_minimums :: proc(t: ^testing.T) {
    minimums := compute_ui_regions(.Baseline, 0, 0)
    testing.expect_value(t, minimums.world_rect.width, f32(WORLD_MIN_WIDTH))
    testing.expect_value(t, minimums.world_rect.height, f32(WORLD_MIN_HEIGHT))

    maximums := compute_ui_regions(.Baseline, WINDOW_WIDTH, WINDOW_HEIGHT)
    testing.expect_value(t, maximums.world_rect.width,
        f32(WINDOW_WIDTH - RIGHT_PANEL_MIN_WIDTH))
    testing.expect_value(t, maximums.world_rect.height,
        f32(WINDOW_HEIGHT - BOTTOM_PANEL_MIN_HEIGHT))
    testing.expect(t, maximums.tree_rect.width >= 0)
    testing.expect(t, maximums.text_rect.height >= 0)
}

// Verify Terminal entry focuses once while window activation only changes effective focus.
@(test)
ui_focus_terminal_entry_and_window_activation :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        ui_regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT),
    }
    focused := ui_reconcile_focus(&runtime, {window_focused = true}, true)
    testing.expect_value(t, focused.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
    testing.expect(t, focused.terminal_focused)
    testing.expect(t, focused.terminal_focus_changed)

    unfocused := ui_reconcile_focus(&runtime, {window_focused = false}, true)
    testing.expect_value(t, unfocused.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
    testing.expect(t, !unfocused.terminal_focused)
    testing.expect(t, unfocused.terminal_focus_changed)

    restored := ui_reconcile_focus(&runtime, {window_focused = true}, true)
    testing.expect(t, restored.terminal_focused)
    testing.expect(t, restored.terminal_focus_changed)
    stable := ui_reconcile_focus(&runtime, {window_focused = true}, true)
    testing.expect(t, !stable.terminal_focus_changed)
}

// Verify primary presses retarget focus and Terminal exit invalidates its target.
@(test)
ui_focus_press_targets_and_terminal_exit :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        ui_regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT),
    }
    _ = ui_reconcile_focus(&runtime, {window_focused = true}, true)

    tree := runtime.ui_regions.tree_rect
    moved := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {tree.x + 1, tree.y + 1},
        mouse_pressed = {.Left},
    }, true)
    testing.expect_value(t, moved.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Tree)
    testing.expect_value(t, moved.effective_focus.kind,
        viewmodel.Ui_Focus_Kind.Tree)
    testing.expect(t, !moved.terminal_focused)
    testing.expect(t, moved.terminal_focus_changed)

    terminal := runtime.ui_regions.terminal_rect
    restored := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {terminal.x + 1, terminal.y + 1},
        mouse_pressed = {.Left},
    }, true)
    testing.expect_value(t, restored.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
    testing.expect(t, restored.terminal_focused)

    exited := ui_reconcile_focus(&runtime, {window_focused = true}, false)
    testing.expect_value(t, exited.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.None)
    testing.expect(t, !exited.terminal_focused)
    testing.expect(t, exited.terminal_focus_changed)
}

// Verify static routing declares splitter and panel priority independently of drawing.
@(test)
ui_router_declares_static_target_priority :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        ui_regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT),
    }
    splitter := ui_route_interaction_frame(&runtime, {
        frame = {mouse_position = {VIEW_WIDTH, 20}},
        terminal_present = true,
    })
    testing.expect_value(t, splitter.hover.kind,
        viewmodel.Ui_Interaction_Target_Kind.Splitter)

    terminal := runtime.ui_regions.terminal_rect
    routed := ui_route_interaction_frame(&runtime, {
        frame = {
            mouse_position = {terminal.x + 1, terminal.y + 1},
            mouse_wheel_delta = -1,
        },
        terminal_present = true,
    })
    testing.expect_value(t, routed.hover.focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
    testing.expect(t, routed.terminal.pointer)
    testing.expect(t, routed.terminal.wheel)
    testing.expect(t, !routed.presentation.pointer)
    testing.expect(t, !routed.tree.wheel)
}

// Verify capture from frame start outranks new hover and suppresses wheel routing.
@(test)
ui_router_retains_captured_target_through_release :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        ui_regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT),
    }
    terminal := runtime.ui_regions.terminal_rect
    routed := ui_route_interaction_frame(&runtime, {
        frame = {
            mouse_position = {terminal.x + 1, terminal.y + 1},
            mouse_released = {.Left},
            mouse_wheel_delta = -1,
        },
        terminal_present = true,
        capture = {active = true, kind = .Scrollbar,
            id = UI_TREE_SCROLLBAR_ID},
    })
    testing.expect_value(t, routed.hover.focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
    testing.expect_value(t, routed.pointer_capture.focus.kind,
        viewmodel.Ui_Focus_Kind.Tree)
    testing.expect_value(t, routed.pointer_target.focus.kind,
        viewmodel.Ui_Focus_Kind.Tree)
    testing.expect_value(t, routed.wheel_target.kind,
        viewmodel.Ui_Interaction_Target_Kind.None)
    testing.expect(t, routed.tree.pointer)
    testing.expect(t, !routed.terminal.pointer)
}

// Verify prepared Terminal track geometry refines panel routing before consumption.
@(test)
ui_router_refines_terminal_scrollbar_target :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        ui_regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT),
    }
    terminal := runtime.ui_regions.terminal_rect
    _ = ui_route_interaction_frame(&runtime, {
        frame = {
            mouse_position = {terminal.x + 1, terminal.y + 1},
            mouse_wheel_delta = -1,
        },
        terminal_present = true,
    })
    ui_refine_terminal_scroll_route(&runtime, true, true, true)

    routed := runtime.interaction_frame
    testing.expect_value(t, routed.hover.kind,
        viewmodel.Ui_Interaction_Target_Kind.Scrollbar)
    testing.expect_value(t, routed.pointer_target.id,
        UI_TERMINAL_SCROLLBAR_ID)
    testing.expect_value(t, routed.wheel_target.id,
        UI_TERMINAL_SCROLLBAR_ID)
    testing.expect(t, routed.terminal.pointer)
    testing.expect(t, routed.terminal.wheel)
}

// Verify tree routing independently filters pointer edges and wheel input.
@(test)
ui_tree_input_frame_filters_independent_pointer_classes :: proc(t: ^testing.T) {
    frame := Input_Frame{mouse_position = {12, 18}, mouse_pressed = {.Left},
        mouse_down = {.Left}, mouse_wheel_delta = -2}
    wheel_only := ui_tree_input_frame(frame, {wheel = true})
    testing.expect(t, card(wheel_only.mouse_pressed) == 0)
    testing.expect(t, card(wheel_only.mouse_down) == 0)
    testing.expect_value(t, wheel_only.mouse_wheel_delta, f32(-2))

    pointer_only := ui_tree_input_frame(frame, {pointer = true})
    testing.expect(t, .Left in pointer_only.mouse_pressed)
    testing.expect(t, .Left in pointer_only.mouse_down)
    testing.expect_value(t, pointer_only.mouse_wheel_delta, f32(0))
}

// Verify update-only checkbox interaction captures and toggles on matching release.
@(test)
checkbox_update_commits_without_drawing :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    params := Checkbox_Params{id = 41, rect = {10, 10, 20, 20}, checked = false,
        enabled = true, mouse = {mouse_position = {15, 15},
            mouse_pressed = {.Left}, mouse_down = {.Left}},
        interaction_space_rect = {0, 0, 100, 100}, interaction_enabled = true}
    pressed := update_checkbox(params, &owner)
    testing.expect(t, pressed.pressed && owner.active)

    params.mouse = {mouse_position = {15, 15}, mouse_released = {.Left}}
    released := update_checkbox(params, &owner)
    testing.expect(t, released.toggled && released.checked_out)
    testing.expect(t, !owner.active)
}

// Verify a copy-icon capture remains classified as Presentation interaction.
@(test)
ui_router_classifies_copy_capture_as_presentation :: proc(t: ^testing.T) {
    target := ui_capture_target({active = true, kind = .Copy_Icon, id = 17})
    testing.expect_value(t, target.kind,
        viewmodel.Ui_Interaction_Target_Kind.Control)
    testing.expect_value(t, target.focus.kind,
        viewmodel.Ui_Focus_Kind.Presentation)
    testing.expect_value(t, target.id, 17)
}

//   Verify splitter geometry uses an eight-pixel hit target and three-pixel line.
@(test)
splitter_geometry_uses_distinct_hit_and_visible_widths :: proc(t: ^testing.T) {
    vertical := splitter_geometry(.Vertical, VIEW_WIDTH, VIEW_HEIGHT)
    horizontal := splitter_geometry(.Horizontal, VIEW_WIDTH, VIEW_HEIGHT)

    testing.expect_value(t, vertical.hit_rect.width, f32(8))
    testing.expect_value(t, vertical.visible_rect.width, f32(3))
    testing.expect_value(t, horizontal.hit_rect.height, f32(8))
    testing.expect_value(t, horizontal.visible_rect.height, f32(3))
    testing.expect_value(t, horizontal.hit_rect.width, f32(VIEW_WIDTH))
}

//   Verify a changed split width invalidates Dynview panel layout for reflow.
@(test)
split_width_change_invalidates_dynview_panel_layout :: proc(t: ^testing.T) {
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime)
    baseline := compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT)
    resized := compute_ui_regions(.Baseline, VIEW_WIDTH - 100, VIEW_HEIGHT)

    app_dynview.track_panel(runtime, view_text_content_panel(baseline.text_rect))
    runtime^.pending_invalidation_mask = 0
    runtime^.compile_cache.is_valid = true
    app_dynview.track_panel(runtime, view_text_content_panel(resized.text_rect))

    testing.expect(t, runtime^.pending_invalidation_mask &
        app_dynview.DYNVIEW_INVALIDATE_PANEL != 0)
    testing.expect(t, !runtime^.compile_cache.is_valid)
}

//   Verify overlapping splitter targets select the nearest visible line.
@(test)
splitter_intersection_selects_nearest_axis :: proc(t: ^testing.T) {
    axis, hovered := splitter_hovered_axis({VIEW_WIDTH - 1, VIEW_HEIGHT - 3},
        VIEW_WIDTH, VIEW_HEIGHT)
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Vertical)

    axis, hovered = splitter_hovered_axis({VIEW_WIDTH - 3, VIEW_HEIGHT - 1},
        VIEW_WIDTH, VIEW_HEIGHT)
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Horizontal)

    axis, hovered = splitter_hovered_axis({VIEW_WIDTH - 2, VIEW_HEIGHT - 2},
        VIEW_WIDTH, VIEW_HEIGHT)
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Vertical)
}

//   Verify splitter capture persists off-target, clamps, and releases on mouse-up.
@(test)
splitter_drag_owns_press_until_release :: proc(t: ^testing.T) {
    ui_runtime := viewmodel.Euclid_Ui_Runtime_State{
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
    }
    update_splitters(&ui_runtime, {
        mouse_position = {VIEW_WIDTH, 20},
        mouse_pressed = {.Left}, mouse_down = {.Left}}, 0.05)
    testing.expect(t, splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID))

    update_splitters(&ui_runtime, {
        mouse_position = {0, 20}, mouse_down = {.Left}}, 0.05)
    testing.expect_value(t, ui_runtime.vertical_split_x, f32(WORLD_MIN_WIDTH))
    testing.expect(t, ui_runtime.ui_press_owner.active)

    update_splitters(&ui_runtime, {mouse_position = {0, 20}}, 0.05)
    testing.expect(t, !ui_runtime.ui_press_owner.active)
}

//   Verify active GIF phases lock and release splitter interaction.
@(test)
gif_capture_phases_lock_splitters :: proc(t: ^testing.T) {
    phases := [3]viewmodel.Gif_Capture_Phase{.Armed, .Recording, .Finalizing}
    for phase in phases {
        ui_runtime := viewmodel.Euclid_Ui_Runtime_State{
            vertical_split_x = VIEW_WIDTH,
            horizontal_split_y = VIEW_HEIGHT,
            gif_capture_phase = phase,
            ui_press_owner = {active = true, kind = .Splitter,
                id = SPLITTER_VERTICAL_PRESS_ID},
        }
        update_splitters(&ui_runtime, {
            mouse_position = {VIEW_WIDTH, 20},
            mouse_pressed = {.Left}, mouse_down = {.Left}}, 0.05)
        testing.expect(t, !ui_runtime.ui_press_owner.active)
        testing.expect_value(t, ui_runtime.vertical_split_x, f32(VIEW_WIDTH))
    }
}

//   Verify programmatic splitter placement is atomic, clamped, and capture-safe.
@(test)
scenario_splitter_positions_follow_ui_policy :: proc(t: ^testing.T) {
    ui_runtime := viewmodel.Euclid_Ui_Runtime_State{
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        ui_press_owner = {active = true, kind = .Splitter,
            id = SPLITTER_VERTICAL_PRESS_ID},
        vertical_split_hover = 1,
        horizontal_split_hover = 1,
    }

    testing.expect(t, set_splitter_positions(&ui_runtime, 0, WINDOW_HEIGHT))
    testing.expect_value(t, ui_runtime.vertical_split_x, f32(WORLD_MIN_WIDTH))
    testing.expect_value(t, ui_runtime.horizontal_split_y,
        f32(WINDOW_HEIGHT - BOTTOM_PANEL_MIN_HEIGHT))
    testing.expect(t, !ui_runtime.ui_press_owner.active)
    testing.expect_value(t, ui_runtime.vertical_split_hover, f32(0))
    testing.expect_value(t, ui_runtime.horizontal_split_hover, f32(0))

    ui_runtime.gif_capture_phase = .Recording
    testing.expect(t, !set_splitter_positions(&ui_runtime, VIEW_WIDTH, VIEW_HEIGHT))
    testing.expect_value(t, ui_runtime.vertical_split_x, f32(WORLD_MIN_WIDTH))
}

//   Verify programmatic presentation scrolling clears capture and rejects Terminal.
@(test)
scenario_presentation_scroll_follows_ui_policy :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := new(bridgemodel.Euclid_Julia_Animation_Interface, context.allocator)
    defer free(animation)
    state^.julia_interface^.selected_animation = animation
    state^.ui_runtime.ui_press_owner = {active = true, kind = .Scrollbar,
        id = UI_PRESENTATION_SCROLLBAR_ID}
    state^.ui_runtime.text_scroll_dragging = true
    state^.ui_runtime.text_scroll_drag_off = 12

    testing.expect(t, set_presentation_scroll_position(state, -40))
    testing.expect_value(t, state^.ui_runtime.view_text_scroll_y, f32(0))
    testing.expect(t, !state^.ui_runtime.ui_press_owner.active)
    testing.expect(t, !state^.ui_runtime.text_scroll_dragging)

    animation^.node_kind = .Terminal
    testing.expect(t, !set_presentation_scroll_position(state, 40))
    testing.expect_value(t, state^.ui_runtime.view_text_scroll_y, f32(0))
}

//   Verify UI region validation rejects negative dimensions.
@(test)
validate_ui_regions_rejects_negative_dimensions :: proc(t: ^testing.T) {
    // Ensures region validation fails when any panel rectangle has negative width or height.
    regions := viewmodel.Ui_Regions{}
    regions.world_rect = rl.Rectangle{0, 0, -1, 10}

    testing.expect(t, !validate_ui_regions(regions))

    regions.world_rect = rl.Rectangle{0, 0, 1, 10}
    regions.tree_rect = rl.Rectangle{0, 0, 10, -1}
    testing.expect(t, !validate_ui_regions(regions))
}

//   Verify the scrollbar thumb math clamps and positions correctly.
@(test)
scrollbar_thumb_math_clamps_and_positions_correctly :: proc(t: ^testing.T) {
    // Checks scrollbar thumb sizing and placement clamp correctly across top, bottom, and constructed panel geometry.
    thumb_h := scrollbar_thumb_height(100, 1000, 24)
    testing.expect(t, thumb_h >= 24)
    testing.expect(t, thumb_h <= 100)

    y_top := scrollbar_thumb_y(50, 100, thumb_h, 0, 300)
    y_bottom := scrollbar_thumb_y(50, 100, thumb_h, 300, 300)
    testing.expect_value(t, y_top, f32(50))
    testing.expect_value(t, y_bottom, f32(150) - thumb_h)

    panel := rl.Rectangle{10, 20, 200, 120}
    scrollbar := build_vertical_scrollbar(
        Vertical_Scrollbar_Input{panel, 480, 60, 360}, 8, 24)
    testing.expect(t, scrollbar.has_scrollbar)
    testing.expect_value(t, scrollbar.track_rect.x, panel.x + panel.width - 8)
    testing.expect_value(t, scrollbar.thumb_height, scrollbar.thumb_rect.height)
}

// Verify prepared scrolling owns the full track and applies wheel exactly once.
@(test)
scroll_container_update_reserves_track_and_wheel :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    result := scroll_container_update({
        id = 1002,
        rect = {10, 20, 100, 80},
        content_height = 240,
        mouse_input = {mouse_position = {106, 30}, mouse_wheel_delta = -1},
        interaction_space_rect = {10, 20, 100, 80},
        wheel_step = 20,
        press_owner = &owner,
    })
    testing.expect(t, result.scrollbar.has_scrollbar)
    testing.expect(t, result.pointer_reserved)
    testing.expect(t, result.wheel_consumed)
    testing.expect_value(t, result.scroll_y_out, f32(20))
}

// Verify thumb capture survives pointer exit and clears on physical release.
scroll_container_drag_test_update :: proc(
    owner: ^viewmodel.Ui_Press_Owner_State,
    state: Scroll_Container_State,
    mouse_input: Input_Frame,
    scroll_y: f32 = 0) -> Scroll_Container_Update_Result {
    return scroll_container_update({
        id = 1002, rect = {10, 20, 100, 80}, scroll_y_in = scroll_y,
        content_height = 240, mouse_input = mouse_input,
        interaction_space_rect = {10, 20, 100, 80}, wheel_step = 20,
        press_owner = owner, state_in = state,
    })
}

// Verify thumb capture survives pointer exit and clears on physical release.
@(test)
scroll_container_update_retains_drag_outside_track :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    pressed := scroll_container_drag_test_update(&owner, {}, {
        mouse_position = {106, 21}, mouse_pressed = {.Left},
        mouse_down = {.Left},
    })
    testing.expect(t, pressed.state_out.is_dragging_thumb)
    testing.expect(t, pressed.pointer_reserved)

    dragged := scroll_container_drag_test_update(&owner, pressed.state_out,
        {mouse_position = {200, 95}, mouse_down = {.Left}})
    testing.expect(t, dragged.state_out.is_dragging_thumb)
    testing.expect(t, dragged.pointer_reserved)
    testing.expect_value(t, dragged.scroll_y_out, f32(160))

    released := scroll_container_drag_test_update(&owner, dragged.state_out,
        {mouse_position = {200, 95}, mouse_released = {.Left}},
        dragged.scroll_y_out)
    testing.expect(t, !released.state_out.is_dragging_thumb)
    testing.expect(t, !owner.active)
}

// Verify Terminal wheel policy gives track and Shift override priority over the child.
@(test)
terminal_scroll_wheel_routes_to_one_owner :: proc(t: ^testing.T) {
    frame := Input_Frame{mouse_wheel_delta = -2}
    testing.expect_value(t,
        terminal_scroll_wheel_delta(frame, false, false), f32(-2))
    testing.expect_value(t,
        terminal_scroll_wheel_delta(frame, false, true), f32(0))
    testing.expect_value(t,
        terminal_scroll_wheel_delta(frame, true, true), f32(-2))

    frame.mouse_modifiers = {.Shift}
    testing.expect_value(t,
        terminal_scroll_wheel_delta(frame, false, true), f32(-2))
}

// Verify scrollbar routing blocks all uncaptured Terminal pointer input.
@(test)
terminal_scrollbar_filter_blocks_uncaptured_pointer :: proc(t: ^testing.T) {
    bounds := rl.Rectangle{10, 20, 100, 80}
    filtered := terminal_filter_content_pointer({
        mouse_position = {106, 30},
        mouse_moved = true,
        mouse_pressed = {.Left},
        mouse_released = {.Left},
        mouse_down = {.Left},
        mouse_wheel_delta = -1,
        terminal_mouse_inside = true,
        terminal_mouse_owned = true,
        terminal_mouse_position_valid = true,
        terminal_mouse_position = {column = 12, row = 3},
    }, bounds, false, false)
    testing.expect(t, !filtered.mouse_moved)
    testing.expect(t, card(filtered.mouse_pressed) == 0)
    testing.expect(t, card(filtered.mouse_released) == 0)
    testing.expect(t, card(filtered.mouse_down) == 0)
    testing.expect_value(t, filtered.mouse_wheel_delta, f32(0))
    testing.expect(t, !filtered.terminal_mouse_inside)
    testing.expect(t, !filtered.terminal_mouse_owned)
    testing.expect(t, !filtered.terminal_mouse_position_valid)
    testing.expect_value(t, filtered.mouse_position,
        input.Input_Position{bounds.x - 1, bounds.y - 1})
}

// Verify local capture retains its real release point but cannot start another press.
@(test)
terminal_scrollbar_filter_preserves_local_release :: proc(t: ^testing.T) {
    bounds := rl.Rectangle{10, 20, 100, 80}
    frame := Input_Frame{
        mouse_position = {106, 30},
        mouse_pressed = {.Left},
        mouse_released = {.Left},
        mouse_wheel_delta = -1,
    }
    filtered := terminal_filter_content_pointer(frame, bounds, true, false)
    testing.expect_value(t, filtered.mouse_position, frame.mouse_position)
    testing.expect(t, card(filtered.mouse_pressed) == 0)
    testing.expect(t, .Left in filtered.mouse_released)
    testing.expect_value(t, filtered.mouse_wheel_delta, f32(0))
}

// Verify child capture retains routed drag and release data outside content.
@(test)
terminal_scrollbar_filter_preserves_child_capture :: proc(t: ^testing.T) {
    bounds := rl.Rectangle{10, 20, 100, 80}
    filtered := terminal_filter_content_pointer({
        mouse_position = {106, 30},
        mouse_moved = true,
        mouse_pressed = {.Middle},
        mouse_released = {.Left},
        mouse_down = {.Left},
        mouse_wheel_delta = -1,
        terminal_mouse_owned = true,
        terminal_mouse_position_valid = true,
        terminal_mouse_position = {column = 12, row = 3},
    }, bounds, false, true)
    testing.expect(t, filtered.mouse_moved)
    testing.expect(t, card(filtered.mouse_pressed) == 0)
    testing.expect(t, .Left in filtered.mouse_released)
    testing.expect(t, .Left in filtered.mouse_down)
    testing.expect_value(t, filtered.mouse_wheel_delta, f32(0))
    testing.expect(t, filtered.terminal_mouse_owned)
    testing.expect(t, filtered.terminal_mouse_position_valid)
    testing.expect_value(t, filtered.terminal_mouse_position.column, 12)
}

//   Seed one tree node with a name and optional children for testing.
seed_tree_node :: proc(
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    parent: ^bridgemodel.Euclid_Julia_Animation_Interface,
    first_child: ^bridgemodel.Euclid_Julia_Animation_Interface,
    next_sibling: ^bridgemodel.Euclid_Julia_Animation_Interface,
    expanded: bool) {

    node^.parent = parent
    node^.first_child = first_child
    node^.next_sibling = next_sibling
    node^.is_expanded = expanded
}

//   Verify the tree row count respects each node's expansion state.
@(test)
tree_row_count_respects_expansion_state :: proc(t: ^testing.T) {
    // Verifies visible tree row counting respects node expansion state and first-child expansion helper behavior.
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[2]
    ji.animation_count = 3

    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]

    // root(0) -> child(1) -> sibling(2)
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)

    count_expanded := count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_expanded, 3)

    nodes[0].is_expanded = false
    count_collapsed := count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_collapsed, 1)

    testing.expect_value(t, expanded_first_child(&nodes[1]), nil)
    nodes[0].is_expanded = true
    testing.expect_value(t, expanded_first_child(&nodes[0]), &nodes[1])
}

//   Verify tree row lookup follows visible depth-first order across roots.
@(test)
tree_visible_row_follows_draw_order :: proc(t: ^testing.T) {
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [4]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    for index in 0..<len(nodes) - 1 {
        nodes[index].next_in_registry = &nodes[index + 1]
    }
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)
    seed_tree_node(&nodes[3], nil, nil, nil, false)

    row, found := tree_visible_row(&ji, &nodes[2])
    testing.expect(t, found)
    testing.expect_value(t, row, 2)
    row, found = tree_visible_row(&ji, &nodes[3])
    testing.expect(t, found)
    testing.expect_value(t, row, 3)

    nodes[0].is_expanded = false
    _, found = tree_visible_row(&ji, &nodes[2])
    testing.expect(t, !found)
}

//   Verify tree reveal scrolling moves only enough to expose the target row.
@(test)
tree_reveal_scroll_is_minimal_and_clamped :: proc(t: ^testing.T) {
    testing.expect_value(t, tree_reveal_scroll(44, 3, 66, 220), f32(44))
    testing.expect_value(t, tree_reveal_scroll(88, 2, 66, 220), f32(44))
    testing.expect_value(t, tree_reveal_scroll(0, 5, 66, 220), f32(66))
    testing.expect_value(t, tree_reveal_scroll(200, 0, 66, 220), f32(0))
    testing.expect_value(t, tree_reveal_scroll(30, 1, 100, 44), f32(0))
}

//   Verify a stable reveal request scrolls, cancels dragging, and is consumed.
@(test)
pending_tree_reveal_applies_display_state :: proc(t: ^testing.T) {
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    nodes[0].next_in_registry = &nodes[1]
    nodes[0].stable_id[0] = 1
    nodes[1].stable_id[0] = 2
    ui_runtime := viewmodel.Euclid_Ui_Runtime_State{
        tree_reveal_pending = true,
        tree_reveal_stable_id = nodes[1].stable_id,
        tree_scroll_dragging = true,
        tree_scroll_drag_off = 5,
        ui_press_owner = {active = true, kind = .Scrollbar, id = 1003},
    }
    scroll_y: f32
    apply_pending_tree_reveal(Tree_List_Params{
        ji = &ji,
        ui_runtime = &ui_runtime,
        list_panel = {height = TREE_ROW_HEIGHT},
        scroll_y = &scroll_y,
    }, TREE_ROW_HEIGHT * 2)

    testing.expect_value(t, scroll_y, TREE_ROW_HEIGHT)
    testing.expect(t, !ui_runtime.tree_reveal_pending)
    testing.expect(t, !ui_runtime.tree_scroll_dragging)
    testing.expect(t, !ui_runtime.ui_press_owner.active)

    ui_runtime.tree_reveal_pending = true
    ui_runtime.tree_reveal_stable_id[0] = 3
    apply_pending_tree_reveal(Tree_List_Params{
        ji = &ji,
        ui_runtime = &ui_runtime,
        list_panel = {height = TREE_ROW_HEIGHT},
        scroll_y = &scroll_y,
    }, TREE_ROW_HEIGHT * 2)
    testing.expect(t, ui_runtime.tree_reveal_pending)
}

//   Verify build_tree_view_panels clamps small panels to non-negative rects.
@(test)
build_tree_view_panels_clamps_small_panels :: proc(t: ^testing.T) {
    // Confirms tiny tree panels still produce a fixed-height toolbar and non-negative list viewport dimensions.
    panel := rl.Rectangle{0, 0, 8, 8}
    toolbar, list := build_tree_view_panels(panel)

    testing.expect(t, toolbar.height == TREE_TOOLBAR_HEIGHT)
    testing.expect(t, list.width >= 0)
    testing.expect(t, list.height >= 0)
}

//   Verify the tree row-count guard stops recursive walks.
@(test)
tree_row_count_guard_stops_recursive_walks :: proc(t: ^testing.T) {
    // Verifies row counting guard limits recursive traversal depth to prevent runaway tree walks.
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[1]
    ji.animation_count = 2

    nodes[0].next_in_registry = &nodes[1]

    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, nil, true)

    testing.expect_value(t, count_visible_tree_rows_limited(&ji, &nodes[0], 1), 1)
}

