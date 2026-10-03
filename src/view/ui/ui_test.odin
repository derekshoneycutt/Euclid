#+test
package ui

import viewmodel "../model"

import bridgemodel "../../bridge/model"

import dynviewmodel "../../dynview/model"

import "core:testing"

import app_core "../../core"
import contentdata "../../core/content"
import app_dynview "../../dynview"
import geometry "../../core/geometry"
import termhist "../../terminal/history"
import "../input"
import view_core "../core"

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

// Verify GIF button labels and enabled states describe every capture phase.
@(test)
gif_button_presentation_matches_capture_phase :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    phases := [6]viewmodel.Gif_Capture_Phase{
        .Idle, .Armed, .Recording, .Finalizing, .Saved, .Error}
    labels := [6]string{
        "Save GIF", "Cancel GIF", "Recording...", "Saving...", "Save GIF", "Save GIF"}
    enabled := [6]bool{true, true, false, false, true, true}
    for phase, index in phases {
        testing.expect_value(t, gif_capture_button_label(state, phase), labels[index])
        testing.expect_value(t, gif_capture_button_enabled(phase), enabled[index])
    }
}

// Verify GIF status labels include phase state and prepared recording progress.
@(test)
gif_status_labels_cover_capture_phases :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    testing.expect_value(t, gif_capture_status_label(state, .Idle, 0, storage[:]), "Status: Idle")
    testing.expect_value(t, gif_capture_status_label(state, .Armed, 0, storage[:]), "Status: Armed")
    testing.expect_value(t, gif_capture_status_label(state, .Recording, 12, storage[:]),
        "Status: Recording (12 frames)")
    testing.expect_value(t, gif_capture_status_label(state, .Finalizing, 12, storage[:]),
        "Status: Saving")
    testing.expect_value(t, gif_capture_status_label(
        state, .Saved, 12, storage[:]), "Status: Saved")
    testing.expect_value(t, gif_capture_status_label(
        state, .Error, 0, storage[:]), "Status: Error")
    phases := [6]viewmodel.Gif_Capture_Phase{
        .Idle, .Armed, .Recording, .Finalizing, .Saved, .Error}
    milestones := [6]string{"GIF capture idle", "GIF capture armed",
        "GIF capture recording", "GIF capture saving", "GIF capture saved",
        "GIF capture error"}
    for phase, index in phases {
        testing.expect_value(t,
            gif_accessibility_status_label(state, phase), milestones[index])
    }
}

// Verify GIF slider values use export-oriented labels instead of raw factors.
@(test)
gif_control_value_labels_are_human_readable :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    testing.expect_value(t, gif_output_scale_label(state, 1), "100%")
    testing.expect_value(t, gif_output_scale_label(state, 2), "50%")
    testing.expect_value(t, gif_output_scale_label(state, 3), "33%")
    testing.expect_value(t, gif_output_scale_label(state, 4), "25%")
    testing.expect_value(t, gif_output_scale_label(state, 0), "100%")
    testing.expect_value(t, gif_output_scale_label(state, 5), "25%")
    cadence := [4]string{"frame", "2 frames", "3 frames", "4 frames"}
    for expected, index in cadence {
        testing.expect_value(t,
            gif_capture_cadence_label(state, index + 1, storage[:]), expected)
    }
    testing.expect_value(t, gif_capture_cadence_label(state, 0, storage[:]), "frame")
    testing.expect_value(t, gif_capture_cadence_label(state, 5, storage[:]), "4 frames")
}

// Verify GIF timing segments remain inside the minimum panel width.
@(test)
gif_timing_segments_fit_compact_panel :: proc(t: ^testing.T) {
    panel := geometry.Rectangle{10, 20, 240, 300}
    animation, recorded := gif_timing_button_rects(panel, 100)
    testing.expect(t, animation.width > 0)
    testing.expect_value(t, animation.width, recorded.width)
    testing.expect(t, animation.x >= panel.x + SETTINGS_PANEL_INSET)
    testing.expect(t, recorded.x + recorded.width <=
        panel.x + panel.width - SETTINGS_PANEL_INSET)
}

// Verify optional settings labels expose unavailable controls without audio changes.
@(test)
settings_capability_labels_match_prepared_availability :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    testing.expect_value(t, settings_simd_label(state, true), "Use SIMD Projection")
    testing.expect_value(t, settings_simd_label(state, false),
        "Use SIMD Projection (Unavailable)")
    testing.expect_value(t, settings_gpu_dust_label(state, true), "GPU Dust Instancing")
    testing.expect_value(t, settings_gpu_dust_label(state, false),
        "GPU Dust Instancing (Unavailable)")
}

// Verify the settings statistics use complete production templates and named counts.
@(test)
settings_statistic_messages_preserve_rendered_counts :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    statistics := [4]struct{id: contentdata.Content_Message_Id, expected: string}{
        {.Settings_Stats_Dust, "Dust particles Rendered: 12"},
        {.Settings_Stats_Trail, "Trail particles Rendered: 12"},
        {.Settings_Stats_Flicker, "Flicker particles Rendered: 12"},
        {.Settings_Stats_Animation_Entries, "Julia animation entries added: 12"},
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for statistic in statistics {
        label := view_core.shell_format(state, statistic.id,
            []contentdata.Content_Format_Argument{{"count", i64(12)}}, storage[:])
        testing.expect_value(t, label, statistic.expected)
    }
}

// Verify GIF and settings visible and semantic static labels retain authored output.
@(test)
gif_and_settings_static_messages_preserve_labels :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    labels := []struct{id: contentdata.Content_Message_Id, expected: string}{
        {.Settings_Display_Fps, "Display FPS"},
        {.Settings_Limit_Fps, "Limit FPS"},
        {.Settings_Drawing_Sound, "Enable Drawing Sound"},
        {.Settings_Maximum_Dust, "Maximum Dust particles"},
        {.Gif_Output_Scale, "Output scale"},
        {.Gif_Capture_Every, "Capture every"},
        {.Gif_Playback_Timing, "Playback timing"},
        {.Gif_Timing_Animation, "Animation"},
        {.Gif_Timing_Recorded, "Recorded"},
        {.Gif_Timing_Animation_Description, "Use animation timing"},
        {.Gif_Timing_Recorded_Description, "Use recorded timing"},
        {.Gif_Downsample_Accessible, "Downsample"},
        {.Gif_Saved_Path_Label, "Path"},
        {.Gif_Saved_Path_Accessible, "Saved GIF path"},
    }
    for label in labels {
        testing.expect_value(t, view_core.shell_message(state, label.id), label.expected)
    }
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

// Verify drawing sound is a normal default-off Settings row and sole user gate.
@(test)
settings_drawing_sound_row_is_unconditional_and_user_owned :: proc(t: ^testing.T) {
    rows := settings_view_layout_rows({0, 0, 320, 480})
    testing.expect(t, rows.sound_y > rows.limit_y)
    testing.expect(t, rows.simd_y > rows.sound_y)

    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, !state^.user_drawing_sound_enabled)
    apply_settings_preparation(state, {
        sound = {toggled = true, checked_out = true},
    }, false, false)
    testing.expect(t, state^.user_drawing_sound_enabled)
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

// Verify the visible GIF path takes exclusive keyboard focus from Terminal by ID.
@(test)
ui_focus_routes_visible_gif_path_input :: proc(t: ^testing.T) {
    runtime := make_baseline_ui_runtime()
    runtime.active_accordion_section = .Save_Gif
    runtime.gif_capture_phase = .Saved
    runtime.last_gif_path_len = 4
    field := gif_path_input_rect(&runtime)
    routed := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {field.x + 1, field.y + 1},
        mouse_pressed = {.Left},
    }, true)
    testing.expect_value(t, routed.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Input_Box)
    testing.expect_value(t, routed.logical_focus.id, GIF_PATH_INPUT_BOX_ID)
    testing.expect(t, !routed.terminal_focused)
    testing.expect(t, routed.accordion.pointer)

    runtime.active_accordion_section = .Library
    hidden := ui_reconcile_focus(&runtime, {window_focused = true}, true)
    testing.expect_value(t, hidden.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.None)
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

// Verify checkbox preparation preserves distinct visual, hit, and clip geometry.
@(test)
checkbox_result_publishes_authoritative_geometry :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    result := update_checkbox({
        id = 42, rect = {10, 20, 30, 18}, checked = false, enabled = true,
        interaction_space_rect = {0, 0, 100, 100}, interaction_enabled = true,
        semantic_clip = {5, 6, 70, 80},
    }, &owner)
    testing.expect_value(t, result.box_rect,
        geometry.Rectangle{16, 20, 18, 18})
    testing.expect_value(t, result.control_geometry.bounds,
        viewmodel.Rectangle{10, 20, 30, 18})
    testing.expect_value(t, result.control_geometry.clip_bounds,
        viewmodel.Rectangle{5, 6, 70, 80})
}

// Verify button preparation converges semantic activation and publishes geometry.
@(test)
text_button_converges_semantic_action_and_geometry :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    id := semantic_control_id(.Gif_Control, 77)
    testing.expect(t, semantic_begin(semantic))
    testing.expect(t, semantic_append_command(semantic, {
        target = id, kind = .Activate}))
    result := update_text_button({
        id = 77, rect = {10, 20, 80, 24}, label = "Save", enabled = true,
        interaction_space_rect = {0, 0, 200, 200}, interaction_enabled = true,
        semantics = {
            publish = true, focus = semantic, id = id, role = .Button,
            states = button_semantic_states(true), region = .Accordion_Content,
            clip_bounds = {0, 0, 100, 100}, label = "Save",
        },
    }, &owner)
    testing.expect(t, result.action.activated)
    testing.expect(t, .Semantic in result.action.sources)
    testing.expect_value(t, result.control_geometry.bounds,
        viewmodel.Rectangle{10, 20, 80, 24})
    testing.expect_value(t, result.control_geometry.clip_bounds,
        viewmodel.Rectangle{0, 0, 100, 100})
}

// Verify disabled button semantics publish without admitting activation.
@(test)
disabled_text_button_rejects_semantic_activation :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    id := semantic_control_id(.Gif_Control, 78)
    testing.expect(t, semantic_begin(semantic))
    testing.expect(t, semantic_append_command(semantic, {
        target = id, kind = .Activate}))
    result := update_text_button({
        id = 78, rect = {10, 20, 80, 24}, label = "Saving", enabled = false,
        interaction_space_rect = {0, 0, 200, 200}, interaction_enabled = true,
        semantics = {
            publish = true, focus = semantic, id = id, role = .Button,
            states = button_semantic_states(false), region = .Accordion_Content,
            clip_bounds = {0, 0, 100, 100}, label = "Saving",
        },
    }, &owner)
    testing.expect(t, !result.action.activated)
    testing.expect(t, card(result.action.sources) == 0)
}

// Verify simultaneous pointer and semantic routes still produce one activation.
@(test)
button_action_coalesces_duplicate_sources :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    id := semantic_control_id(.Animation_Control, 79)
    testing.expect(t, semantic_begin(semantic))
    testing.expect(t, semantic_append_command(semantic, {
        target = id, kind = .Activate}))
    result := button_resolve_action({
        semantics = {focus = semantic, id = id, role = .Button,
            states = button_semantic_states(true)},
        bounds = {10, 20, 80, 24}, press_owner = &owner,
        press_kind = .Icon_Button, press_id = 79, pointer_activated = true,
    })
    testing.expect(t, result.activated)
    testing.expect(t, .Pointer in result.sources)
    testing.expect(t, .Semantic in result.sources)
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

    runtime := viewmodel.Euclid_Ui_Runtime_State{
        window = window, vertical_split_x = VIEW_WIDTH,
        horizontal_split_y = VIEW_HEIGHT,
    }
    prepared := splitter_preparation(
        &runtime, false, VIEW_WIDTH, VIEW_HEIGHT, {})
    testing.expect_value(t, prepared.vertical.control_geometry.bounds,
        viewmodel.Rectangle(vertical.hit_rect))
    testing.expect_value(t, prepared.vertical.control_geometry.clip_bounds,
        viewmodel.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT})
    testing.expect_value(t, prepared.vertical.visible_rect,
        vertical.visible_rect)
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
    _ = update_splitters(&ui_runtime, {
        mouse_position = {VIEW_WIDTH, 20},
        mouse_pressed = {.Left}, mouse_down = {.Left}}, 0.05)
    testing.expect(t, splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID))

    dragged := update_splitters(&ui_runtime, {
        mouse_position = {0, 20}, mouse_down = {.Left}}, 0.05)
    testing.expect_value(t, ui_runtime.vertical_split_x, f32(VIEW_WIDTH))
    testing.expect(t, dragged.vertical.changed)
    testing.expect(t, .Pointer in dragged.vertical.sources)
    apply_splitter_preparation(&ui_runtime, dragged)
    testing.expect_value(t, ui_runtime.vertical_split_x, f32(WORLD_MIN_WIDTH))
    testing.expect(t, ui_runtime.ui_press_owner.active)

    _ = update_splitters(&ui_runtime, {mouse_position = {0, 20}}, 0.05)
    testing.expect(t, !ui_runtime.ui_press_owner.active)
}

// Verify splitter keyboard commands prepare a bounded value before owner commit.
@(test)
splitter_semantic_step_precedes_owner_commit :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        semantic_focus = semantic, window = {WINDOW_WIDTH, WINDOW_HEIGHT},
        vertical_split_x = VIEW_WIDTH, horizontal_split_y = VIEW_HEIGHT,
    }
    testing.expect(t, semantic_append_command(semantic, {
        target = splitter_semantic_id(.Vertical), kind = .Increment}))
    prepared := update_splitters(&runtime, {}, 0)
    testing.expect_value(t, runtime.vertical_split_x, f32(VIEW_WIDTH))
    testing.expect_value(t, prepared.vertical.value, f32(VIEW_WIDTH + 8))
    testing.expect(t, prepared.vertical.changed)
    testing.expect(t, .Semantic in prepared.vertical.sources)
    apply_splitter_preparation(&runtime, prepared)
    testing.expect_value(t, runtime.vertical_split_x, f32(VIEW_WIDTH + 8))
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
    testing.expect(t, result.changed)
    testing.expect(t, .Pointer in result.sources)
    testing.expect_value(t, result.minimum, f32(0))
    testing.expect_value(t, result.maximum, f32(160))
    testing.expect_value(t, result.orientation,
        viewmodel.Ui_Range_Orientation.Vertical)
    testing.expect_value(t, result.control_geometry.bounds,
        viewmodel.Rectangle{10, 20, 100, 80})
    testing.expect_value(t, result.control_geometry.clip_bounds,
        viewmodel.Rectangle{10, 20, 100, 80})
}

// Verify one scroll result coalesces pointer and composite semantic input.
@(test)
scroll_container_update_coalesces_input_sources :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    id := semantic_control_id(.Presentation, 7)
    testing.expect(t, semantic_begin(semantic))
    testing.expect(t, semantic_append_command(semantic, {
        target = id, kind = .Scroll_Page, amount = 1}))
    result := scroll_container_update({
        id = 1002, rect = {10, 20, 100, 80}, content_height = 240,
        mouse_input = {mouse_position = {20, 30}, mouse_wheel_delta = -1},
        interaction_space_rect = {10, 20, 100, 80}, wheel_step = 20,
        press_owner = &owner, semantic_focus = semantic, semantic_id = id,
    })
    testing.expect_value(t, result.scroll_y_out, f32(80))
    testing.expect(t, .Pointer in result.sources)
    testing.expect(t, .Semantic in result.sources)
}

// Verify reusable integer range operations normalize, round, and clamp values.
@(test)
integer_range_operations_are_bounded :: proc(t: ^testing.T) {
    spec := range_integer_spec(10, 0, -2, -5)
    testing.expect_value(t, spec, Integer_Range_Spec{0, 10, 2, 5})
    testing.expect_value(t, range_integer_step(9, 1, spec), 10)
    testing.expect_value(t, range_integer_step(2, -1, spec, true), 0)
    testing.expect_value(t, range_integer_from_normalized(0.55, spec), 6)
    testing.expect_value(t, range_integer_normalized(5, spec), f32(0.5))
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

// Verify search topology retains ancestors and derives expansion without mutation.
@(test)
tree_search_policy_retains_ancestors_without_changing_expansion :: proc(t: ^testing.T) {
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]
    nodes[0].stable_id[0] = 1
    nodes[1].stable_id[0] = 2
    nodes[2].stable_id[0] = 3
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, false)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)
    search := viewmodel.Library_Search_State{active = true, visible_id_count = 2}
    search.visible_ids[0] = nodes[0].stable_id
    search.visible_ids[1] = nodes[2].stable_id
    policy := Tree_Visibility_Policy{search = &search}

    testing.expect_value(t, count_visible_tree_rows_all_roots(&ji, policy), 2)
    testing.expect(t, tree_node_is_effectively_expanded(policy, &nodes[0]))
    testing.expect(t, !nodes[0].is_expanded)
    row, found := tree_visible_row(&ji, &nodes[2], policy)
    testing.expect(t, found)
    testing.expect_value(t, row, 1)
}

// Verify Library search layout reserves correction rows only when populated.
@(test)
library_search_layout_reserves_only_visible_rows :: proc(t: ^testing.T) {
    plain := library_search_layout({10, 20, 240, 180}, false)
    testing.expect_value(t, plain.input.height, LIBRARY_SEARCH_INPUT_HEIGHT)
    testing.expect_value(t, plain.suggestion_prompt.height, f32(0))
    testing.expect_value(t, plain.suggestion.height, f32(0))
    testing.expect_value(t, plain.tree.y, plain.input.y + plain.input.height)
    suggested := library_search_layout({10, 20, 240, 180}, true)
    testing.expect_value(t, suggested.suggestion_prompt.height,
        LIBRARY_SEARCH_PROMPT_HEIGHT)
    testing.expect_value(t, suggested.suggestion.height,
        LIBRARY_SEARCH_SUGGESTION_HEIGHT)
    testing.expect(t, suggested.suggestion.x > suggested.suggestion_prompt.x)
    testing.expect_value(t, suggested.tree.y,
        suggested.suggestion.y + suggested.suggestion.height)
    testing.expect(t, suggested.tree.height >= 0)
}

// Verify Library Search status remains bounded to meaningful milestones.
@(test)
library_search_status_reports_results_and_empty_queries :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    storage: [64]u8
    search: viewmodel.Library_Search_State
    testing.expect_value(t, library_search_status_text(state, &search, storage[:]), "")
    search.query[0] = 'x'
    search.query_length = 1
    testing.expect_value(t, library_search_status_text(state, &search, storage[:]),
        "Searching animations")
    search.active = true
    testing.expect_value(t, library_search_status_text(state, &search, storage[:]),
        "No matching animations")
    search.total_match_count = 42
    search.more_available = true
    testing.expect_value(t, library_search_status_text(state, &search, storage[:]),
        "Matching animations: 42 or more")
}

// Verify the spoken suggestion action identifies its proposed correction.
@(test)
library_search_suggestion_label_names_target :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    storage: [64]u8
    testing.expect_value(t,
        library_search_suggestion_label(state, "Elements", storage[:]),
        "Use suggested search: Elements")
}

// Verify edits debounce, Enter bypasses debounce, and clear restores ordinary state.
@(test)
library_search_input_policy_handles_edit_submit_and_clear :: proc(t: ^testing.T) {
    search := viewmodel.Library_Search_State{query_length = 4, active = true,
        visible_id_count = 2, suggestion_length = 3}
    library_search_apply_input(&search, {changed = true})
    testing.expect_value(t, search.generation, u64(1))
    testing.expect(t, search.query_dirty && !search.active)
    testing.expect_value(t, search.debounce_remaining_seconds,
        LIBRARY_SEARCH_DEBOUNCE_SECONDS)
    library_search_apply_input(&search, {submit_requested = true})
    testing.expect(t, search.submit_requested)
    testing.expect_value(t, search.debounce_remaining_seconds, f32(0))
    library_search_clear_query(&search)
    testing.expect_value(t, search.query_length, 0)
    testing.expect(t, !search.query_dirty && !search.active)
    testing.expect_value(t, search.visible_id_count, 0)
}

// Verify keyboard suggestion activation replaces the full bounded query.
@(test)
library_search_suggestion_replaces_query_and_submits :: proc(t: ^testing.T) {
    search := viewmodel.Library_Search_State{query_length = 3,
        suggestion_length = len("perpendicular")}
    copy(search.query[:], "bad")
    copy(search.suggestion[:], "perpendicular")
    library_search_apply_suggestion(&search)
    testing.expect_value(t, string(search.query[:search.query_length]),
        "perpendicular")
    testing.expect(t, search.query_dirty && search.submit_requested)
    testing.expect_value(t, search.input.cursor_byte, search.query_length)
}

// Verify Search accepts Right only at a collapsed end caret and never uses Tab.
@(test)
library_search_suggestion_key_requires_collapsed_end_caret :: proc(t: ^testing.T) {
    search := viewmodel.Library_Search_State{
        query_length = 3, suggestion_length = 4,
        input = {cursor_byte = 3, anchor_byte = 3},
    }
    right := [1]input.Input_Event{{kind = .Press, key = .Right}}
    testing.expect(t, library_search_accept_suggestion_key(
        &search, {events = right[:]}))
    search.input.anchor_byte = 1
    testing.expect(t, !library_search_accept_suggestion_key(
        &search, {events = right[:]}))
    search.input.anchor_byte = 3
    tab := [1]input.Input_Event{{kind = .Press, key = .Tab}}
    testing.expect(t, !library_search_accept_suggestion_key(
        &search, {events = tab[:]}))
}

// Verify integer sliders apply addressed keyboard commands through normal clamping.
@(test)
integer_slider_applies_semantic_keyboard_step :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    value := 2
    id := semantic_control_id(.Gif_Control, 6201)
    testing.expect(t, semantic_begin(semantic))
    testing.expect(t, semantic_append_command(semantic, {
        target = id, kind = .Increment}))
    result := update_settings_integer_slider({
        panel = {0, 0, 200, 100}, row_y = 0,
        ui_runtime = &runtime, press_id = 6201, label = "Output scale",
        value = value, min_value = 1, max_value = 4,
        semantic_domain = .Gif_Control,
    })
    testing.expect_value(t, result.value, 3)
    testing.expect_value(t, value, 2)
    testing.expect(t, result.changed)
    testing.expect(t, .Semantic in result.sources)
    testing.expect(t, .Pointer not_in result.sources)
    testing.expect_value(t, result.minimum, 1)
    testing.expect_value(t, result.maximum, 4)
    testing.expect_value(t, result.track,
        geometry.Rectangle{8, 22, 184, 8})
    testing.expect_value(t, result.control_geometry.bounds,
        viewmodel.Rectangle{8, 16, 184, 20})
    testing.expect_value(t, result.control_geometry.clip_bounds,
        viewmodel.Rectangle{0, 0, 200, 100})
    testing.expect(t, result.knob.width > result.track.height)
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

// Verify the Library tree publishes one Tab stop with UUID-backed descendants.
@(test)
tree_semantics_publish_composite_hierarchy :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    ji.selected_animation = &nodes[0]
    nodes[0].next_in_registry = &nodes[1]
    nodes[0].stable_id[0] = 1
    nodes[1].stable_id[0] = 2
    nodes[0].name = "Book I"
    nodes[1].name = "Proposition I"
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, nil, false)
    scroll_y: f32

    testing.expect(t, semantic_begin(semantic))
    _ = prepare_tree_list_panel({ji = &ji, ui_runtime = &runtime,
        list_panel = {0, 0, 200, 100}, scroll_y = &scroll_y})
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    snapshot := semantic_snapshot(semantic)
    testing.expect_value(t, snapshot^.node_count, 3)
    tree_index := semantic_node_index(snapshot, tree_semantic_id())
    testing.expect(t, tree_index >= 0)
    tree := snapshot^.nodes[tree_index]
    testing.expect(t, .Tab_Stop in tree.states)
    testing.expect_value(t, tree.active_descendant, tree_item_semantic_id(&nodes[0]))
    child_index := semantic_node_index(snapshot, tree_item_semantic_id(&nodes[1]))
    testing.expect(t, child_index >= 0)
    child := snapshot^.nodes[child_index]
    testing.expect_value(t, child.parent, tree_item_semantic_id(&nodes[0]))
    testing.expect_value(t, child.level, u16(2))
    testing.expect_value(t, child.position_in_set, u16(1))
    testing.expect_value(t, child.set_size, u16(1))
    testing.expect(t, .Tab_Stop not_in child.states)
}

// Build the semantic tree fixture used by the command-routing test.
tree_semantic_commands_fixture :: proc(
    semantic: ^viewmodel.Ui_Semantic_Focus_State,
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface,
    scroll_y: ^f32) -> Tree_List_Params {
    runtime^.semantic_focus = semantic
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes)
    ji^.selected_animation = &nodes[0]
    for index in 0..<len(nodes) {
        nodes[index].stable_id[0] = byte(index + 1)
        if index + 1 < len(nodes) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }
    }
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)
    return Tree_List_Params{ji = ji, ui_runtime = runtime,
        list_panel = {0, 0, 200, TREE_ROW_HEIGHT}, scroll_y = scroll_y}
}

// Verify routed tree commands move, reveal, and select through existing state.
@(test)
tree_semantic_commands_roam_and_select :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    scroll_y: f32
    params := tree_semantic_commands_fixture(
        semantic, &runtime, &ji, nodes[:], &scroll_y)
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_tree_list_panel(params)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    semantic^.logical_focus = tree_semantic_id()

    _ = semantic_route_keyboard(semantic,
        {events = {{kind = .Press, key = .End}}})
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_tree_list_panel(params)
    testing.expect_value(t, semantic^.active_tree_item, nodes[2].stable_id)
    testing.expect_value(t, scroll_y, TREE_ROW_HEIGHT * 2)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)

    _ = semantic_route_keyboard(semantic,
        {events = {{kind = .Press, key = .Enter}}})
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_tree_list_panel(params)
    testing.expect_value(t, ji.selected_animation, &nodes[2])
    testing.expect(t, nodes[2].is_selected)
}

// Verify item-addressed native commands mutate their stable branch, not the roving item.
@(test)
tree_semantic_commands_target_addressed_branch :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji := bridgemodel.Euclid_Julia_Interface{}
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    for index in 0..<len(nodes) {
        nodes[index].stable_id[0] = byte(index + 1)
        if index + 1 < len(nodes) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }
    }
    seed_tree_node(&nodes[0], nil, nil, &nodes[1], false)
    seed_tree_node(&nodes[1], nil, &nodes[2], nil, true)
    seed_tree_node(&nodes[2], &nodes[1], nil, nil, false)
    semantic^.active_tree_item = nodes[0].stable_id
    semantic^.commands[0] = {
        target = tree_item_semantic_id(&nodes[1]), kind = .Toggle}
    semantic^.command_count = 1
    scroll_y: f32
    params := Tree_List_Params{ji = &ji, ui_runtime = &runtime,
        list_panel = {0, 0, 200, TREE_ROW_HEIGHT}, scroll_y = &scroll_y}

    active := tree_apply_semantic_commands(params)

    testing.expect(t, !nodes[1].is_expanded)
    testing.expect_value(t, active, &nodes[1])
    testing.expect_value(t, semantic^.active_tree_item, nodes[1].stable_id)
}

// Verify the roving tree descendant is identified only for keyboard-visible focus.
@(test)
tree_keyboard_active_descendant_is_visible :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    node := bridgemodel.Euclid_Julia_Animation_Interface{}
    node.stable_id[0] = 1
    semantic^.window_focused = true
    semantic^.focus_origin = .Keyboard
    semantic^.logical_focus = tree_semantic_id()
    semantic^.active_tree_item = node.stable_id

    testing.expect(t, tree_item_is_keyboard_active(&runtime, &node))
    semantic^.focus_origin = .Pointer
    testing.expect(t, !tree_item_is_keyboard_active(&runtime, &node))
    semantic^.focus_origin = .Keyboard
    semantic^.window_focused = false
    testing.expect(t, !tree_item_is_keyboard_active(&runtime, &node))
}

// Verify document replacement preserves keyboard focus on the document surface.
@(test)
presentation_semantics_reconcile_compilation_generation :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    state^.ui_runtime.interaction.logical_focus = {kind = .Presentation}
    state^.dynview.compile_cache.compiled_revision = 12

    testing.expect(t, semantic_begin(semantic))
    register_presentation_semantics(state, {0, 0, 200, 100}, {})
    parent := presentation_semantic_id(state)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    semantic^.logical_focus = parent
    semantic^.focus_origin = .Keyboard

    state^.dynview.compile_cache.compiled_revision = 13
    testing.expect(t, semantic_begin(semantic))
    register_presentation_semantics(state, {0, 0, 200, 100}, {})
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic^.logical_focus, presentation_semantic_id(state))
    testing.expect_value(t, semantic^.focus_origin, viewmodel.Ui_Focus_Origin.Keyboard)
}

// Verify Terminal's editable descriptor excludes completion and output policy state.
@(test)
terminal_editable_descriptor_exposes_only_committed_input :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    bytes: [16]u8
    copy(bytes[:], "x=α")
    history := termhist.Termhist_State{
        text = bytes[:], text_len = len("x=α"), cursor = len("x=α"),
        content_revision = 9,
    }
    state^.terminal.history = &history
    state^.terminal.completion_preview_insertion = " + preview"
    scroll := Scroll_Container_Update_Result{
        view_rect = {10, 20, 200, 100},
        control_geometry = {{10, 20, 200, 100}, {5, 6, 220, 130}},
        scroll_y_out = 12,
    }
    descriptor, text_geometry := terminal_editable_text_adapter(state, {
        padded_bounds = {14, 24, 192, 92}, line_height = 18, line_count = 3,
    }, scroll)
    testing.expect_value(t, descriptor.text, "x=α")
    testing.expect_value(t, descriptor.cursor_byte, len("x=α"))
    testing.expect_value(t, descriptor.anchor_byte, len("x=α"))
    testing.expect_value(t, descriptor.content_revision, u64(9))
    testing.expect(t, descriptor.text != state^.terminal.completion_preview_insertion)
    testing.expect_value(t, text_geometry.cursor_column, 3)
    testing.expect_value(t, text_geometry.selection.width, f32(0))
    testing.expect_value(t, text_geometry.control, scroll.control_geometry)
}

// Verify Terminal registration publishes one generation-scoped global stop.
@(test)
terminal_semantics_publish_single_surface :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    state^.terminal.animation_generation = 9
    testing.expect(t, semantic_begin(semantic))
    register_terminal_semantics(state, {5, 6, 200, 120}, {})
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    snapshot := semantic_snapshot(semantic)
    index := semantic_node_index(snapshot, terminal_semantic_id(state))
    testing.expect(t, index >= 0)
    testing.expect_value(t, snapshot^.nodes[index].role,
        viewmodel.Ui_Node_Role.Terminal)
    testing.expect(t, .Tab_Stop in snapshot^.nodes[index].states)
    testing.expect(t, semantic_focus_matches_name(semantic, "terminal"))
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
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    sections := accordion_portrait_sections("Euclid's Elements", state)
    testing.expect_value(t, sections.count, 4)
    testing.expect_value(t, sections.items[0].section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect_value(t, sections.items[0].label, "Euclid's Elements")
    testing.expect_value(t, sections.items[1].section,
        viewmodel.Ui_Accordion_Section.Library)
    testing.expect_value(t, sections.items[3].section,
        viewmodel.Ui_Accordion_Section.Settings)
    testing.expect_value(t,
        accordion_portrait_sections("", state).items[0].label, "Animation")
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
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
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
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
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
        press_owner = &owner, semantic_focus = semantic, active = active}
    testing.expect(t, semantic_begin(semantic))
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

// Verify a focused accordion header consumes the routed activation command.
@(test)
accordion_header_keyboard_activation_selects_section :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    active := viewmodel.Ui_Accordion_Section.Library
    sections := accordion_landscape_sections()
    ctx := Accordion_Context{
        panel = {10, 20, 300, 500},
        press_owner = &owner,
        semantic_focus = semantic,
        active = active,
    }
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_accordion(ctx, sections, &active)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    semantic^.logical_focus = accordion_semantic_id(.Settings)
    _ = semantic_route_keyboard(semantic, {
        events = {{kind = .Press, key = .Space}},
    })
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_accordion(ctx, sections, &active)
    testing.expect_value(t, active, viewmodel.Ui_Accordion_Section.Settings)
}

// Verify a native Expand command selects the same accordion section owner.
@(test)
accordion_header_external_expand_selects_section :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    active := viewmodel.Ui_Accordion_Section.Library
    sections := accordion_landscape_sections()
    ctx := Accordion_Context{
        panel = {10, 20, 300, 500},
        press_owner = &owner,
        semantic_focus = semantic,
        active = active,
    }
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_accordion(ctx, sections, &active)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    target := accordion_semantic_id(.Settings)
    testing.expect(t, semantic_apply_external_action(
        semantic, target, .Expand))
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_accordion(ctx, sections, &active)
    testing.expect_value(t, active, viewmodel.Ui_Accordion_Section.Settings)
}

// Verify the active header controls one panel that owns accordion content.
@(test)
accordion_publishes_controlled_content_panel :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    active := viewmodel.Ui_Accordion_Section.Settings
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_accordion({
        panel = {10, 20, 300, 500}, press_owner = &owner,
        semantic_focus = semantic, active = active,
    }, accordion_landscape_sections(), &active)
    child_id := semantic_control_id(.Settings_Control, 99)
    _ = semantic_register_control(semantic, {
        id = child_id, role = .Button, states = {.Visible, .Enabled},
        region = .Accordion_Content, bounds = {20, 80, 100, 24},
        clip_bounds = {10, 20, 300, 500}, label = "Child",
    })
    staging := semantic_staging_snapshot(semantic)
    header_index := semantic_node_index(
        staging, accordion_semantic_id(.Settings))
    panel_id := accordion_panel_semantic_id(.Settings)
    panel_index := semantic_node_index(staging, panel_id)
    child_index := semantic_node_index(staging, child_id)
    testing.expect(t, header_index >= 0 && panel_index >= 0 && child_index >= 0)
    if header_index >= 0 && child_index >= 0 {
        testing.expect_value(t,
            staging^.nodes[header_index].controls, panel_id)
        testing.expect_value(t, staging^.nodes[child_index].parent, panel_id)
    }
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
