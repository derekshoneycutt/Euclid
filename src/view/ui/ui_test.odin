package ui

import viewmodel "../model"

import bridgemodel "../../bridge/model"

import dynviewmodel "../../dynview/model"

import "core:testing"

import app_core "../../core"
import app_dynview "../../dynview"
import geometry "../../core/geometry"
import "../input"

//   Build one default-size landscape UI runtime for interaction tests.
make_baseline_ui_runtime :: proc() -> viewmodel.Euclid_Ui_Runtime_State {
    return {
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        presentation_visible = true,
        ui_regions = compute_ui_regions(
            .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT),
    }
}

//   Verify the baseline UI regions are valid and mutually consistent.
@(test)
ui_regions_baseline_is_valid_and_consistent :: proc(t: ^testing.T) {
    // Verifies baseline UI region construction is internally consistent and matches fixed panel sizing contracts.
    regions := compute_ui_regions(
        .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT)

    testing.expect(t, validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, VIEW_WIDTH)
    testing.expect_value(t, regions.world_rect.height, VIEW_HEIGHT)
    testing.expect_value(
        t, regions.accordion_rect.x, VIEW_WIDTH + TREE_PANEL_PADDING)
    testing.expect_value(
        t, regions.text_rect.y, VIEW_HEIGHT + TREE_PANEL_PADDING)
    testing.expect(t, regions.terminal_rect.width >= 0)
    testing.expect(t, regions.terminal_rect.height >= 0)
}

//   Verify split coordinates preserve minimum sizes for all four panes.
@(test)
ui_regions_clamp_all_pane_minimums :: proc(t: ^testing.T) {
    minimums := compute_ui_regions(.Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, 0, 0)
    testing.expect_value(t, minimums.world_rect.width, f32(WORLD_MIN_WIDTH))
    testing.expect_value(t, minimums.world_rect.height, f32(WORLD_MIN_HEIGHT))

    maximums := compute_ui_regions(.Landscape, WINDOW_WIDTH, WINDOW_HEIGHT,
        WINDOW_WIDTH, WINDOW_HEIGHT)
    testing.expect_value(t, maximums.world_rect.width,
        f32(WINDOW_WIDTH - RIGHT_PANEL_MIN_WIDTH))
    testing.expect_value(t, maximums.world_rect.height,
        f32(WINDOW_HEIGHT - BOTTOM_PANEL_MIN_HEIGHT))
    testing.expect(t, maximums.accordion_rect.width >= 0)
    testing.expect(t, maximums.text_rect.height >= 0)
}

//   Verify compact live extents degrade without inverted clamps or rectangles.
@(test)
ui_regions_compact_extent_remains_non_negative :: proc(t: ^testing.T) {
    regions := compute_ui_regions(.Landscape, 320, 240, 225, 167)

    testing.expect(t, validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, f32(225))
    testing.expect_value(t, regions.world_rect.height, f32(167))
    testing.expect(t, regions.accordion_rect.width >= 0)
    testing.expect(t, regions.text_rect.height >= 0)
    testing.expect(t, regions.world_rect.width <= 320)
    testing.expect(t, regions.world_rect.height <= 240)
}

// Verify a full-capacity dust value remains inside the settings panel inset.
@(test)
settings_dust_value_is_right_aligned_inside_panel :: proc(t: ^testing.T) {
    panel := geometry.Rectangle{100, 0, 180, 240}
    text_width: f32 = 40
    x := settings_right_aligned_x(geometry.Rectangle(panel), text_width)

    testing.expect_value(t, x, panel.x + panel.width - SETTINGS_PANEL_INSET - 40)
    testing.expect(t, x >= panel.x + SETTINGS_PANEL_INSET)
    testing.expect(t, x + text_width <=
        panel.x + panel.width - SETTINGS_PANEL_INSET)
}

//   Verify forced modes and automatic hysteresis resolve deterministically.
@(test)
layout_mode_resolution_honors_preference_and_hysteresis :: proc(t: ^testing.T) {
    testing.expect_value(t, resolve_initial_layout_mode(.Auto, 1280, 720),
        viewmodel.Ui_Layout_Mode.Landscape)
    testing.expect_value(t, resolve_initial_layout_mode(.Auto, 640, 720),
        viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, resolve_layout_mode(.Portrait, .Landscape, 1600, 700),
        viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, resolve_layout_mode(.Landscape, .Portrait, 600, 900),
        viewmodel.Ui_Layout_Mode.Landscape)
    testing.expect_value(t, resolve_layout_mode(.Auto, .Landscape, 89, 100),
        viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, resolve_layout_mode(.Auto, .Portrait, 111, 100),
        viewmodel.Ui_Layout_Mode.Landscape)
    testing.expect_value(t, resolve_layout_mode(.Auto, .Landscape, 100, 100),
        viewmodel.Ui_Layout_Mode.Landscape)
    testing.expect_value(t, resolve_layout_mode(.Auto, .Portrait, 100, 100),
        viewmodel.Ui_Layout_Mode.Portrait)
}

//   Verify portrait uses one full-width world above a nonnegative accordion.
@(test)
ui_regions_portrait_is_full_width_and_compact_safe :: proc(t: ^testing.T) {
    regions := compute_ui_regions(.Portrait, 640, 720, 0, 360)
    testing.expect_value(t, regions.world_rect.width, f32(640))
    testing.expect_value(t, regions.world_rect.height, f32(360))
    testing.expect_value(t, regions.accordion_rect.x, f32(TREE_PANEL_PADDING))
    testing.expect_value(t, regions.accordion_rect.width, f32(620))
    view_layout := accordion_layout(
        geometry.Rectangle(regions.accordion_rect),
        accordion_portrait_sections("Animation"), .View)
    testing.expect_value(
        t, regions.text_rect, viewmodel.Rectangle(view_layout.content))
    testing.expect(t, regions.terminal_rect.width >= 0)
    testing.expect(t, validate_ui_regions(regions))

    compact := compute_ui_regions(.Portrait, 200, 180, 0, 90)
    testing.expect(t, validate_ui_regions(compact))
    testing.expect(t, compact.world_rect.height <= 180)
    testing.expect(t, compact.accordion_rect.height >= 0)
}

// Verify animation controls remain inset from the world's moving bottom-left edge.
@(test)
animation_controls_follow_world_splitters :: proc(t: ^testing.T) {
    world := geometry.Rectangle{0, 0, 640, 480}
    slots := animation_control_layout_slots(geometry.Rectangle(world))
    testing.expect_value(t, slots.panel.x, ANIMATION_CONTROL_EDGE_INSET)
    testing.expect_value(t, slots.panel.y + slots.panel.height,
        world.height - ANIMATION_CONTROL_EDGE_INSET)
    testing.expect_value(t, slots.refresh.width, ANIMATION_CONTROL_BUTTON_SIZE)
    testing.expect_value(t, slots.pause.x - slots.refresh.x,
        ANIMATION_CONTROL_BUTTON_SIZE + ANIMATION_CONTROL_BUTTON_GAP)

    resized := animation_control_layout_slots({0, 0, 480, 320})
    testing.expect_value(t, resized.panel.x, slots.panel.x)
    testing.expect_value(t, resized.panel.y - slots.panel.y, f32(-160))
}

// Verify relocated controls preserve reset, unpause, and pause-toggle semantics.
@(test)
animation_controls_apply_existing_actions :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    ji := bridgemodel.Euclid_Julia_Interface{}
    state^.julia_interface = &ji
    state^.ui_runtime.simulation_paused = true

    apply_animation_control_hit(state, {refresh_requested = true})
    testing.expect(t, !state^.ui_runtime.simulation_paused)
    testing.expect(t, ji.pending_animation_reset)

    apply_animation_control_hit(state, {toggle_pause_requested = true})
    testing.expect(t, state^.ui_runtime.simulation_paused)
}

// Verify Terminal entry focuses once while window activation only changes effective focus.
@(test)
ui_focus_terminal_entry_and_window_activation :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        presentation_visible = true,
        ui_regions = compute_ui_regions(
            .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT),
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
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        presentation_visible = true,
        ui_regions = compute_ui_regions(
            .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT),
    }
    _ = ui_reconcile_focus(&runtime, {window_focused = true}, true)

    tree := runtime.ui_regions.accordion_rect
    moved := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {tree.x + 1, tree.y + 1},
        mouse_pressed = {.Left},
    }, true)
    testing.expect_value(t, moved.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Accordion)
    testing.expect_value(t, moved.effective_focus.kind,
        viewmodel.Ui_Focus_Kind.Accordion)
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
    runtime := make_baseline_ui_runtime()
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
    testing.expect(t, !routed.accordion.wheel)

    controls := animation_control_layout_slots(
        geometry.Rectangle(runtime.ui_regions.world_rect))
    animation := ui_route_interaction_frame(&runtime, {
        frame = {mouse_position = {
            controls.pause.x + 1, controls.pause.y + 1}},
    })
    testing.expect_value(t, animation.hover.kind,
        viewmodel.Ui_Interaction_Target_Kind.Control)
    testing.expect_value(t, animation.hover.id, ANIMATION_PAUSE_BUTTON_ID)
    testing.expect_value(t, animation.hover.focus.kind,
        viewmodel.Ui_Focus_Kind.None)
}

// Verify capture from frame start outranks new hover and suppresses wheel routing.
@(test)
ui_router_retains_captured_target_through_release :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        presentation_visible = true,
        ui_regions = compute_ui_regions(
            .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT),
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
        viewmodel.Ui_Focus_Kind.Accordion)
    testing.expect_value(t, routed.pointer_target.focus.kind,
        viewmodel.Ui_Focus_Kind.Accordion)
    testing.expect_value(t, routed.wheel_target.kind,
        viewmodel.Ui_Interaction_Target_Kind.None)
    testing.expect(t, routed.accordion.pointer)
    testing.expect(t, !routed.terminal.pointer)
}

// Verify prepared Terminal track geometry refines panel routing before consumption.
@(test)
ui_router_refines_terminal_scrollbar_target :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
        presentation_visible = true,
        ui_regions = compute_ui_regions(
            .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT),
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
ui_accordion_input_frame_filters_independent_pointer_classes :: proc(t: ^testing.T) {
    frame := Input_Frame{mouse_position = {12, 18}, mouse_pressed = {.Left},
        mouse_down = {.Left}, mouse_wheel_delta = -2}
    wheel_only := ui_accordion_input_frame(frame, {wheel = true})
    testing.expect(t, card(wheel_only.mouse_pressed) == 0)
    testing.expect(t, card(wheel_only.mouse_down) == 0)
    testing.expect_value(t, wheel_only.mouse_wheel_delta, f32(-2))

    pointer_only := ui_accordion_input_frame(frame, {pointer = true})
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
    window := viewmodel.Ui_Window_Metrics{WINDOW_WIDTH, WINDOW_HEIGHT}
    vertical := splitter_geometry(
        .Vertical, .Landscape, VIEW_WIDTH, VIEW_HEIGHT, window)
    horizontal := splitter_geometry(
        .Horizontal, .Landscape, VIEW_WIDTH, VIEW_HEIGHT, window)

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
    baseline := compute_ui_regions(
        .Landscape, WINDOW_WIDTH, WINDOW_HEIGHT, VIEW_WIDTH, VIEW_HEIGHT)
    resized := compute_ui_regions(.Landscape, WINDOW_WIDTH, WINDOW_HEIGHT,
        VIEW_WIDTH - 100, VIEW_HEIGHT)

    app_dynview.track_panel(
        runtime, viewmodel.Rectangle(
            view_text_content_panel(geometry.Rectangle(baseline.text_rect))))
    runtime^.pending_invalidation_mask = 0
    runtime^.compile_cache.is_valid = true
    app_dynview.track_panel(
        runtime, viewmodel.Rectangle(
            view_text_content_panel(geometry.Rectangle(resized.text_rect))))

    testing.expect(t, runtime^.pending_invalidation_mask &
        app_dynview.DYNVIEW_INVALIDATE_PANEL != 0)
    testing.expect(t, !runtime^.compile_cache.is_valid)
}

//   Verify overlapping splitter targets select the nearest visible line.
@(test)
splitter_intersection_selects_nearest_axis :: proc(t: ^testing.T) {
    axis, hovered := splitter_hovered_axis({VIEW_WIDTH - 1, VIEW_HEIGHT - 3},
        .Landscape, VIEW_WIDTH, VIEW_HEIGHT, {WINDOW_WIDTH, WINDOW_HEIGHT})
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Vertical)

    axis, hovered = splitter_hovered_axis({VIEW_WIDTH - 3, VIEW_HEIGHT - 1},
        .Landscape, VIEW_WIDTH, VIEW_HEIGHT, {WINDOW_WIDTH, WINDOW_HEIGHT})
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Horizontal)

    axis, hovered = splitter_hovered_axis({VIEW_WIDTH - 2, VIEW_HEIGHT - 2},
        .Landscape, VIEW_WIDTH, VIEW_HEIGHT, {WINDOW_WIDTH, WINDOW_HEIGHT})
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Vertical)
}

//   Verify portrait exposes only one full-width horizontal splitter target.
@(test)
portrait_splitter_is_horizontal_and_full_width :: proc(t: ^testing.T) {
    window := viewmodel.Ui_Window_Metrics{640, 720}
    horizontal := splitter_geometry(.Horizontal, .Portrait, 640, 360, window)
    testing.expect_value(t, horizontal.hit_rect.width, f32(640))

    axis, hovered := splitter_hovered_axis(
        {639, 360}, .Portrait, 640, 360, window)
    testing.expect(t, hovered)
    testing.expect_value(t, axis, Splitter_Axis.Horizontal)
    axis, hovered = splitter_hovered_axis(
        {640, 100}, .Portrait, 640, 360, window)
    testing.expect(t, !hovered)
}

//   Verify hidden portrait presentation surfaces cannot win pointer routing.
@(test)
portrait_routes_origin_to_world_not_hidden_presentation :: proc(t: ^testing.T) {
    runtime := make_baseline_ui_runtime()
    runtime.current_layout_mode = .Portrait
    runtime.ui_regions = compute_ui_regions(.Portrait, 640, 720, 0, 360)
    frame := Input_Frame{mouse_position = {0, 0}}

    target := ui_hover_target(&runtime, frame, true)
    testing.expect_value(t, target.kind,
        viewmodel.Ui_Interaction_Target_Kind.World)
}

//   Verify portrait routes only expanded View content to Presentation or Terminal.
@(test)
portrait_routes_expanded_view_content :: proc(t: ^testing.T) {
    runtime := make_baseline_ui_runtime()
    runtime.current_layout_mode = .Portrait
    runtime.active_accordion_section = .View
    runtime.ui_regions = compute_ui_regions(.Portrait, 640, 720, 0, 360)
    _ = ui_publish_presentation_visibility(&runtime)
    point := input.Input_Position{
        runtime.ui_regions.terminal_rect.x + 1,
        runtime.ui_regions.terminal_rect.y + 1,
    }
    terminal := ui_hover_target(&runtime, {mouse_position = point}, true)
    testing.expect_value(t, terminal.focus.kind, viewmodel.Ui_Focus_Kind.Terminal)
    presentation := ui_hover_target(&runtime, {mouse_position = point}, false)
    testing.expect_value(t, presentation.focus.kind,
        viewmodel.Ui_Focus_Kind.Presentation)

    runtime.active_accordion_section = .Library
    _ = ui_publish_presentation_visibility(&runtime)
    hidden := ui_hover_target(&runtime, {mouse_position = point}, true)
    testing.expect_value(t, hidden.focus.kind,
        viewmodel.Ui_Focus_Kind.Accordion)
}

// Verify hiding View releases UI transactions without discarding selection or refocusing.
@(test)
portrait_view_hide_and_reopen_preserves_content_state :: proc(t: ^testing.T) {
    runtime := make_baseline_ui_runtime()
    runtime.current_layout_mode = .Portrait
    runtime.active_accordion_section = .View
    runtime.ui_regions = compute_ui_regions(.Portrait, 640, 720, 0, 360)
    runtime.dynview_selection = {
        mode = .Wrapped_Text, revision = 7, anchor = {2}, head = {5},
        active = true, dragging = true,
    }
    runtime.ui_press_owner = {active = true, kind = .Dynview_Selection}
    _ = ui_publish_presentation_visibility(&runtime)
    _ = ui_reconcile_focus(&runtime, {window_focused = true}, true)

    runtime.active_accordion_section = .Library
    testing.expect(t, ui_publish_presentation_visibility(&runtime))
    testing.expect(t, !runtime.ui_press_owner.active)
    testing.expect(t, !runtime.dynview_selection.dragging)
    testing.expect(t, runtime.dynview_selection.active)
    testing.expect_value(t, runtime.dynview_selection.revision, u64(7))
    testing.expect(t, runtime.interaction_frame.terminal_focus_changed)

    runtime.active_accordion_section = .View
    testing.expect(t, ui_publish_presentation_visibility(&runtime))
    testing.expect_value(t, runtime.interaction.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.None)
    terminal := runtime.ui_regions.terminal_rect
    focused := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {terminal.x + 1, terminal.y + 1},
        mouse_pressed = {.Left},
    }, true)
    testing.expect_value(t, focused.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Terminal)
}

//   Verify splitter capture persists off-target, clamps, and releases on mouse-up.
@(test)
splitter_drag_owns_press_until_release :: proc(t: ^testing.T) {
    ui_runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        landscape = {
            vertical_ratio = f32(VIEW_WIDTH) / f32(WINDOW_WIDTH),
            horizontal_ratio = f32(VIEW_HEIGHT) / f32(WINDOW_HEIGHT),
        },
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
            window = {WINDOW_WIDTH, WINDOW_HEIGHT},
            landscape = {
                vertical_ratio = f32(VIEW_WIDTH) / f32(WINDOW_WIDTH),
                horizontal_ratio = f32(VIEW_HEIGHT) / f32(WINDOW_HEIGHT),
            },
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
        window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        landscape = {
            vertical_ratio = f32(VIEW_WIDTH) / f32(WINDOW_WIDTH),
            horizontal_ratio = f32(VIEW_HEIGHT) / f32(WINDOW_HEIGHT),
        },
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

//   Verify resize derives split pixels from intent and releases stale UI capture.
@(test)
window_resize_preserves_split_ratios_and_releases_capture :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {1280, 720},
        landscape = {
            vertical_ratio = 0.703125,
            horizontal_ratio = f32(500) / f32(720),
        },
        vertical_split_x = 900,
        horizontal_split_y = 500,
        ui_press_owner = {active = true, kind = .Splitter,
            id = SPLITTER_VERTICAL_PRESS_ID},
        tree_scroll_dragging = true,
        dynview_selection = {dragging = true},
    }

    testing.expect(t, ui_apply_window_metrics(&runtime, {1024, 768}))
    testing.expect_value(t, runtime.vertical_split_x, f32(720))
    testing.expect(t, abs(runtime.horizontal_split_y - f32(533.3333)) < 0.001)
    testing.expect(t, !runtime.ui_press_owner.active)
    testing.expect(t, !runtime.tree_scroll_dragging)
    testing.expect(t, !runtime.dynview_selection.dragging)
}

//   Verify entering portrait restores its split and accordion intent.
@(test)
layout_transition_restores_portrait_state :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {1280, 720},
        layout_preference = .Auto,
        landscape = {
            vertical_ratio = 0.7,
            horizontal_ratio = 0.6,
            active_section = .Settings,
        },
        portrait = {
            world_height_ratio = 0.45,
            active_section = .Save_Gif,
            entered = true,
        },
        current_layout_mode = .Landscape,
        active_accordion_section = .Settings,
        ui_press_owner = {active = true, kind = .Splitter,
            id = SPLITTER_VERTICAL_PRESS_ID},
    }

    testing.expect(t, ui_apply_window_metrics(&runtime, {640, 720}))
    testing.expect_value(t, runtime.current_layout_mode,
        viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, runtime.horizontal_split_y, f32(324))
    testing.expect_value(t, runtime.active_accordion_section,
        viewmodel.Ui_Accordion_Section.Save_Gif)
    testing.expect(t, runtime.portrait.entered)
    testing.expect(t, !runtime.ui_press_owner.active)
}

//   Verify first portrait entry selects View regardless of unentered memory.
@(test)
layout_first_portrait_entry_selects_view :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {1280, 720},
        layout_preference = .Auto,
        landscape = {active_section = .Library},
        portrait = {world_height_ratio = 0.5, active_section = .Settings},
        current_layout_mode = .Landscape,
        active_accordion_section = .Library,
    }
    testing.expect(t, ui_apply_window_metrics(&runtime, {640, 720}))
    testing.expect_value(t, runtime.active_accordion_section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect_value(t, runtime.portrait.active_section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect(t, runtime.portrait.entered)
}

//   Verify returning to landscape preserves portrait edits and restores landscape.
@(test)
layout_transition_restores_landscape_state :: proc(t: ^testing.T) {
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = {640, 720},
        layout_preference = .Auto,
        landscape = {
            vertical_ratio = 0.7,
            horizontal_ratio = 0.6,
            active_section = .Settings,
        },
        portrait = {
            world_height_ratio = 0.5,
            active_section = .Library,
            entered = true,
        },
        current_layout_mode = .Portrait,
        active_accordion_section = .Library,
        horizontal_split_y = 360,
    }
    testing.expect(t, ui_apply_window_metrics(&runtime, {1280, 720}))
    testing.expect_value(t, runtime.current_layout_mode,
        viewmodel.Ui_Layout_Mode.Landscape)
    testing.expect_value(t, runtime.vertical_split_x, f32(896))
    testing.expect(t, abs(runtime.horizontal_split_y - f32(432)) < 0.001)
    testing.expect_value(t, runtime.active_accordion_section,
        viewmodel.Ui_Accordion_Section.Settings)
    testing.expect_value(t, runtime.portrait.world_height_ratio, f32(0.5))
    testing.expect_value(t, runtime.portrait.active_section,
        viewmodel.Ui_Accordion_Section.Library)
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
    state^.ui_runtime.presentation_visible = true
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
    regions.world_rect = viewmodel.Rectangle{0, 0, -1, 10}

    testing.expect(t, !validate_ui_regions(regions))

    regions.world_rect = viewmodel.Rectangle{0, 0, 1, 10}
    regions.accordion_rect = viewmodel.Rectangle{0, 0, 10, -1}
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

    panel := geometry.Rectangle{10, 20, 200, 120}
    scrollbar := build_vertical_scrollbar(
        Vertical_Scrollbar_Input{geometry.Rectangle(panel), 480, 60, 360}, 8, 24)
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
    bounds := geometry.Rectangle{10, 20, 100, 80}
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
    bounds := geometry.Rectangle{10, 20, 100, 80}
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
    bounds := geometry.Rectangle{10, 20, 100, 80}
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

// Verify accordion headers retain order while the active child consumes free height.
@(test)
accordion_layout_places_active_content_after_selected_header :: proc(t: ^testing.T) {
    panel := geometry.Rectangle{10, 20, 300, 500}
    sections := accordion_landscape_sections()
    layout := accordion_layout(geometry.Rectangle(panel), sections, .Save_Gif)
    testing.expect_value(t, layout.headers[0].y, f32(26))
    testing.expect_value(t, layout.headers[1].y,
        layout.headers[0].y + ACCORDION_HEADER_HEIGHT)
    testing.expect_value(t, layout.content.y,
        layout.headers[1].y + ACCORDION_HEADER_HEIGHT)
    testing.expect_value(t, layout.headers[2].y,
        layout.content.y + layout.content.height)
    testing.expect_value(t, layout.content.height,
        panel.height - ACCORDION_PANEL_INSET * 2 -
            ACCORDION_HEADER_HEIGHT * f32(sections.count))
}

// Verify portrait descriptors lead with the borrowed title and preserve utility order.
@(test)
accordion_portrait_descriptors_include_selected_title :: proc(t: ^testing.T) {
    sections := accordion_portrait_sections("Euclid's Elements")
    testing.expect_value(t, sections.count, 4)
    testing.expect_value(t, sections.items[0].section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect_value(t, sections.items[0].label, "Euclid's Elements")
    testing.expect_value(t, sections.items[1].section,
        viewmodel.Ui_Accordion_Section.Library)
    testing.expect_value(t, sections.items[3].section,
        viewmodel.Ui_Accordion_Section.Settings)
    testing.expect_value(t,
        accordion_portrait_sections("").items[0].label, "Animation")
}

// Verify landscape retains three utility headers without a View descriptor.
@(test)
accordion_landscape_descriptors_remain_unchanged :: proc(t: ^testing.T) {
    sections := accordion_landscape_sections()
    testing.expect_value(t, sections.count, 3)
    testing.expect_value(t, sections.items[0].section,
        viewmodel.Ui_Accordion_Section.Library)
    testing.expect_value(t, sections.items[1].section,
        viewmodel.Ui_Accordion_Section.Save_Gif)
    testing.expect_value(t, sections.items[2].section,
        viewmodel.Ui_Accordion_Section.Settings)
}

// Verify portrait places View content after its first header and keeps four headers.
@(test)
accordion_portrait_layout_places_view_first :: proc(t: ^testing.T) {
    panel := geometry.Rectangle{10, 20, 300, 500}
    sections := accordion_portrait_sections("Proposition I")
    layout := accordion_layout(geometry.Rectangle(panel), sections, .View)
    testing.expect_value(t, layout.content.y,
        layout.headers[0].y + ACCORDION_HEADER_HEIGHT)
    testing.expect_value(t, layout.headers[1].y,
        layout.content.y + layout.content.height)
    testing.expect_value(t, layout.content.height,
        panel.height - ACCORDION_PANEL_INSET * 2 -
            ACCORDION_HEADER_HEIGHT * f32(sections.count))
}

// Verify the selected catalogue title is borrowed with an Animation fallback.
@(test)
selected_animation_title_tracks_current_selection :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    ji := bridgemodel.Euclid_Julia_Interface{}
    animation := bridgemodel.Euclid_Julia_Animation_Interface{
        name = "Proclus's Commentary"}
    state^.julia_interface = &ji
    testing.expect_value(t, selected_animation_title(state), "Animation")
    ji.selected_animation = &animation
    testing.expect_value(t, selected_animation_title(state),
        "Proclus's Commentary")
    animation.name = ""
    testing.expect_value(t, selected_animation_title(state), "Animation")
}

// Verify a header click selects exactly one section and moves expanded content.
@(test)
accordion_header_click_selects_one_section :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    active := viewmodel.Ui_Accordion_Section.Library
    panel := geometry.Rectangle{10, 20, 300, 500}
    sections := accordion_landscape_sections()
    settings_index := accordion_section_index(sections, .Settings)
    settings := accordion_layout(
        geometry.Rectangle(panel), sections, .Library).headers[settings_index]
    mouse_position := input.Input_Position{settings.x + 2, settings.y + 2}
    pressed_context := Accordion_Context{panel = geometry.Rectangle(panel),
        mouse_input = {mouse_position = mouse_position,
            mouse_pressed = {.Left}, mouse_down = {.Left}},
        press_owner = &owner, active = active}
    _ = prepare_accordion(pressed_context, sections, &active)
    testing.expect_value(t, active, viewmodel.Ui_Accordion_Section.Library)

    released_context := pressed_context
    released_context.mouse_input = {
        mouse_position = mouse_position, mouse_released = {.Left}}
    prepared := prepare_accordion(released_context, sections, &active)
    testing.expect_value(t, active, viewmodel.Ui_Accordion_Section.Settings)
    testing.expect_value(t, prepared.layout.content.y,
        prepared.layout.headers[settings_index].y + ACCORDION_HEADER_HEIGHT)
    testing.expect(t, !owner.active)
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

