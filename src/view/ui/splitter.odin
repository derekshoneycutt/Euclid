package ui

import viewmodel "../model"

import native "../native"
import color "../../core/color"
import geometry "../../core/geometry"

import rl "vendor:raylib"

SPLITTER_VISIBLE_WIDTH :: 3.0
SPLITTER_HIT_WIDTH :: 8.0
SPLITTER_FADE_SECONDS :: 0.15
SPLITTER_VERTICAL_PRESS_ID :: 6201
SPLITTER_HORIZONTAL_PRESS_ID :: 6202
SPLITTER_COLOR :: rl.Color{70, 130, 180, 255}
SPLITTER_ACTIVE_COLOR :: color.Color_RGBA8{70, 130, 180, 255}

Splitter_Axis :: enum {
    Vertical,
    Horizontal,
}

//   Visible and interactive rectangles for one pane splitter.
Splitter_Geometry :: struct {
    visible_rect: rl.Rectangle,
    hit_rect: rl.Rectangle,
}

//   Build centered visible and hit rectangles for one splitter axis.
splitter_geometry :: proc(
    axis: Splitter_Axis, mode: viewmodel.Ui_Layout_Mode,
    split_x, split_y: f32,
    window: viewmodel.Ui_Window_Metrics) -> Splitter_Geometry {

    if axis == .Vertical {
        return {
            visible_rect = {split_x - SPLITTER_VISIBLE_WIDTH * 0.5, 0,
                SPLITTER_VISIBLE_WIDTH, f32(window.height)},
            hit_rect = {split_x - SPLITTER_HIT_WIDTH * 0.5, 0,
                SPLITTER_HIT_WIDTH, f32(window.height)},
        }
    }
    horizontal_width := split_x
    if mode == .Portrait { horizontal_width = f32(window.width) }
    return {
        visible_rect = {0, split_y - SPLITTER_VISIBLE_WIDTH * 0.5,
            horizontal_width, SPLITTER_VISIBLE_WIDTH},
        hit_rect = {0, split_y - SPLITTER_HIT_WIDTH * 0.5,
            horizontal_width, SPLITTER_HIT_WIDTH},
    }
}

//   Select the nearest hovered splitter, preferring vertical on an exact tie.
splitter_hovered_axis :: proc(
    mouse: rl.Vector2, mode: viewmodel.Ui_Layout_Mode,
    split_x, split_y: f32,
    window: viewmodel.Ui_Window_Metrics) -> (Splitter_Axis, bool) {

    horizontal := splitter_geometry(.Horizontal, mode, split_x, split_y, window)
    if mode == .Portrait {
        return .Horizontal, geometry.rectangle_contains(
            geometry.Rectangle(horizontal.hit_rect), geometry.Vector2(mouse))
    }
    vertical := splitter_geometry(.Vertical, mode, split_x, split_y, window)
    over_vertical := geometry.rectangle_contains(
        geometry.Rectangle(vertical.hit_rect), geometry.Vector2(mouse))
    over_horizontal := geometry.rectangle_contains(
        geometry.Rectangle(horizontal.hit_rect), geometry.Vector2(mouse))
    if over_vertical && over_horizontal {
        if abs(mouse.y - split_y) < abs(mouse.x - split_x) {
            return .Horizontal, true
        }
        return .Vertical, true
    }
    if over_vertical {
        return .Vertical, true
    }
    return .Horizontal, over_horizontal
}

//   Report whether GIF capture currently requires stable pane geometry.
splitters_locked_for_gif :: #force_inline proc(
    phase: viewmodel.Gif_Capture_Phase) -> bool {
    return phase == .Armed || phase == .Recording || phase == .Finalizing
}

//   Report whether scenario-driven splitter geometry may change now.
splitter_positions_are_mutable :: #force_inline proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {

    return ui_runtime != nil && !ui_runtime^.save_gif_requested &&
        !splitters_locked_for_gif(ui_runtime^.gif_capture_phase)
}

//   Clamp one requested vertical split while preserving both horizontal pane minimums.
splitter_clamp_vertical :: #force_inline proc(
    value: f32, window_width: int) -> f32 {
    return layout_clamp_split(value, f32(window_width),
        WORLD_MIN_WIDTH, RIGHT_PANEL_MIN_WIDTH)
}

//   Clamp one requested horizontal split while preserving both vertical pane minimums.
splitter_clamp_horizontal :: #force_inline proc(
    value: f32, window_height: int) -> f32 {
    return layout_clamp_split(value, f32(window_height),
        WORLD_MIN_HEIGHT, BOTTOM_PANEL_MIN_HEIGHT)
}

//   Update normalized landscape split intent from current clamped pixels.
splitter_store_ratios :: proc(ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if ui_runtime^.current_layout_mode == .Portrait {
        if ui_runtime^.window.height > 0 {
            ui_runtime^.portrait.world_height_ratio =
                ui_runtime^.horizontal_split_y / f32(ui_runtime^.window.height)
        }
        return
    }
    if ui_runtime^.window.width > 0 {
        ui_runtime^.landscape.vertical_ratio = ui_runtime^.vertical_split_x /
            f32(ui_runtime^.window.width)
    }
    if ui_runtime^.window.height > 0 {
        ui_runtime^.landscape.horizontal_ratio = ui_runtime^.horizontal_split_y /
            f32(ui_runtime^.window.height)
    }
}

//   Report whether one splitter owns the shared UI press capture.
splitter_owns_press :: #force_inline proc(
    owner: viewmodel.Ui_Press_Owner_State, press_id: int) -> bool {

    return owner.active && owner.kind == .Splitter && owner.id == press_id
}

//   Move one hover fade toward its target without overshoot.
splitter_update_fade :: #force_inline proc(value, target, dt: f32) -> f32 {
    step := clamp(dt / SPLITTER_FADE_SECONDS, f32(0), f32(1))
    if value < target {
        return min(target, value + step)
    }
    return max(target, value - step)
}

//   Release splitter capture when geometry locks or the pointer is released.
splitter_release_capture :: proc(ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if ui_runtime.ui_press_owner.kind != .Splitter {
        return
    }
    ui_runtime.ui_press_owner = {}
    ui_runtime.splitter_drag_offset = 0
}

//   Atomically apply scenario-requested splitter positions through ordinary UI policy.
set_splitter_positions :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    vertical, horizontal: f32) -> bool {

    if !splitter_positions_are_mutable(ui_runtime) {
        return false
    }
    splitter_release_capture(ui_runtime)
    if ui_runtime^.current_layout_mode == .Landscape {
        ui_runtime^.vertical_split_x = splitter_clamp_vertical(
            vertical, ui_runtime^.window.width)
    }
    ui_runtime^.horizontal_split_y = splitter_clamp_horizontal(
        horizontal, ui_runtime^.window.height)
    splitter_store_ratios(ui_runtime)
    ui_runtime^.vertical_split_hover = 0
    ui_runtime^.horizontal_split_hover = 0
    return true
}

//   Capture the hovered splitter when no other control owns the pointer press.
splitter_try_capture :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame,
    hovered_axis: Splitter_Axis,
    hovered: bool) {

    if !hovered || !input_frame_left_pressed(mouse_input) ||
        ui_runtime.ui_press_owner.active {
        return
    }
    press_id := SPLITTER_VERTICAL_PRESS_ID
    split_position := ui_runtime.vertical_split_x
    mouse_position := mouse_input.mouse_position.x
    if hovered_axis == .Horizontal ||
        ui_runtime^.current_layout_mode == .Portrait {
        press_id = SPLITTER_HORIZONTAL_PRESS_ID
        split_position = ui_runtime.horizontal_split_y
        mouse_position = mouse_input.mouse_position.y
    }
    ui_runtime.ui_press_owner = {active = true, kind = .Splitter, id = press_id}
    ui_runtime.splitter_drag_offset = split_position - mouse_position
}

//   Apply the active splitter drag while preserving all pane minimums.
splitter_apply_drag :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame) {

    if !input_frame_left_down(mouse_input) {
        splitter_release_capture(ui_runtime)
        return
    }
    if splitter_owns_press(ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID) {
        ui_runtime.vertical_split_x = splitter_clamp_vertical(
            mouse_input.mouse_position.x + ui_runtime.splitter_drag_offset,
            ui_runtime^.window.width)
    } else if splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_HORIZONTAL_PRESS_ID) {
        ui_runtime.horizontal_split_y = splitter_clamp_horizontal(
            mouse_input.mouse_position.y + ui_runtime.splitter_drag_offset,
            ui_runtime^.window.height)
    }
    splitter_store_ratios(ui_runtime)
}

// Resolve one portable cursor from current splitter hover and capture targets.
splitter_cursor :: proc(
    vertical_target, horizontal_target: f32) -> viewmodel.Ui_Cursor_Kind {
    if vertical_target > 0 {return .Resize_Ew}
    if horizontal_target > 0 {return .Resize_Ns}
    return .Default
}

//   Update splitter capture, positions, and hover fades before layout is prepared.
update_splitters :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame,
    dt: f32) {

    locked := splitters_locked_for_gif(ui_runtime.gif_capture_phase)
    axis, hovered := splitter_hovered_axis(input_frame_mouse_position(mouse_input),
        ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    if locked {
        splitter_release_capture(ui_runtime)
        hovered = false
    } else {
        splitter_try_capture(ui_runtime, mouse_input, axis, hovered)
        if ui_runtime.ui_press_owner.kind == .Splitter {
            splitter_apply_drag(ui_runtime, mouse_input)
        }
    }

    vertical_target: f32
    horizontal_target: f32
    if !locked && ((hovered && axis == .Vertical) || splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID)) {
        vertical_target = 1
    }
    if !locked && ((hovered && axis == .Horizontal) || splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_HORIZONTAL_PRESS_ID)) {
        horizontal_target = 1
    }
    ui_runtime^.cursor = splitter_cursor(vertical_target, horizontal_target)
    ui_runtime.vertical_split_hover = splitter_update_fade(
        ui_runtime.vertical_split_hover, vertical_target, dt)
    ui_runtime.horizontal_split_hover = splitter_update_fade(
        ui_runtime.horizontal_split_hover, horizontal_target, dt)
}

//   Draw splitter feedback for the active layout.
draw_splitters :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_position: rl.Vector2) {

    _, hovered := splitter_hovered_axis(mouse_position,
        ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    if splitters_locked_for_gif(ui_runtime.gif_capture_phase) {
        hovered = false
    }

    vertical := splitter_geometry(.Vertical, ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    horizontal := splitter_geometry(.Horizontal, ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    if ui_runtime^.current_layout_mode == .Landscape &&
        ui_runtime.vertical_split_hover > 0 {
        rl.DrawRectangleRec(vertical.visible_rect,
            rl.Fade(SPLITTER_COLOR, ui_runtime.vertical_split_hover))
    }
    if ui_runtime.horizontal_split_hover > 0 {
        rl.DrawRectangleRec(horizontal.visible_rect,
            rl.Fade(SPLITTER_COLOR, ui_runtime.horizontal_split_hover))
    }
}

// draw_encoded_splitters encodes current splitter feedback without changing policy.
draw_encoded_splitters :: proc(
    encoder: ^native.Draw_Encoder,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_position: rl.Vector2) {
    _, hovered := splitter_hovered_axis(mouse_position,
        ui_runtime^.current_layout_mode, ui_runtime.vertical_split_x,
        ui_runtime.horizontal_split_y, ui_runtime^.window)
    if splitters_locked_for_gif(ui_runtime.gif_capture_phase) {hovered = false}
    vertical := splitter_geometry(.Vertical, ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    horizontal := splitter_geometry(.Horizontal, ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    if ui_runtime^.current_layout_mode == .Landscape &&
        ui_runtime.vertical_split_hover > 0 {
        draw_color := SPLITTER_ACTIVE_COLOR
        draw_color.a = u8(255 * clamp(ui_runtime.vertical_split_hover, f32(0), f32(1)))
        _ = native.draw_encoder_rectangle(
            encoder, geometry.Rectangle(vertical.visible_rect), draw_color)
    }
    if ui_runtime.horizontal_split_hover > 0 {
        draw_color := SPLITTER_ACTIVE_COLOR
        draw_color.a = u8(255 * clamp(ui_runtime.horizontal_split_hover, f32(0), f32(1)))
        _ = native.draw_encoder_rectangle(
            encoder, geometry.Rectangle(horizontal.visible_rect), draw_color)
    }
}