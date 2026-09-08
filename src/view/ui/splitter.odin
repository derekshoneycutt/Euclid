package ui

import "../../core"

import rl "vendor:raylib"

SPLITTER_VISIBLE_WIDTH :: 3.0
SPLITTER_HIT_WIDTH :: 8.0
SPLITTER_FADE_SECONDS :: 0.15
SPLITTER_VERTICAL_PRESS_ID :: 6201
SPLITTER_HORIZONTAL_PRESS_ID :: 6202
SPLITTER_COLOR :: rl.Color{70, 130, 180, 255}

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
    axis: Splitter_Axis, split_x, split_y: f32) -> Splitter_Geometry {

    if axis == .Vertical {
        return {
            visible_rect = {split_x - SPLITTER_VISIBLE_WIDTH * 0.5, 0,
                SPLITTER_VISIBLE_WIDTH, WINDOW_HEIGHT},
            hit_rect = {split_x - SPLITTER_HIT_WIDTH * 0.5, 0,
                SPLITTER_HIT_WIDTH, WINDOW_HEIGHT},
        }
    }
    return {
        visible_rect = {0, split_y - SPLITTER_VISIBLE_WIDTH * 0.5,
            split_x, SPLITTER_VISIBLE_WIDTH},
        hit_rect = {0, split_y - SPLITTER_HIT_WIDTH * 0.5,
            split_x, SPLITTER_HIT_WIDTH},
    }
}

//   Select the nearest hovered splitter, preferring vertical on an exact tie.
splitter_hovered_axis :: proc(
    mouse: rl.Vector2, split_x, split_y: f32) -> (Splitter_Axis, bool) {

    vertical := splitter_geometry(.Vertical, split_x, split_y)
    horizontal := splitter_geometry(.Horizontal, split_x, split_y)
    over_vertical := rl.CheckCollisionPointRec(mouse, vertical.hit_rect)
    over_horizontal := rl.CheckCollisionPointRec(mouse, horizontal.hit_rect)
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
splitters_locked_for_gif :: #force_inline proc(phase: core.Gif_Capture_Phase) -> bool {
    return phase == .Armed || phase == .Recording || phase == .Finalizing
}

//   Report whether one splitter owns the shared UI press capture.
splitter_owns_press :: #force_inline proc(
    owner: core.Ui_Press_Owner_State, press_id: int) -> bool {

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
splitter_release_capture :: proc(ui_runtime: ^core.Euclid_Ui_Runtime_State) {
    if ui_runtime.ui_press_owner.kind != .Splitter {
        return
    }
    ui_runtime.ui_press_owner = {}
    ui_runtime.splitter_drag_offset = 0
}

//   Capture the hovered splitter when no other control owns the pointer press.
splitter_try_capture :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    mouse_input: Mouse_Input_State,
    hovered_axis: Splitter_Axis,
    hovered: bool) {

    if !hovered || !mouse_input.left_pressed || ui_runtime.ui_press_owner.active {
        return
    }
    press_id := SPLITTER_VERTICAL_PRESS_ID
    split_position := ui_runtime.vertical_split_x
    mouse_position := mouse_input.position.x
    if hovered_axis == .Horizontal {
        press_id = SPLITTER_HORIZONTAL_PRESS_ID
        split_position = ui_runtime.horizontal_split_y
        mouse_position = mouse_input.position.y
    }
    ui_runtime.ui_press_owner = {active = true, kind = .Splitter, id = press_id}
    ui_runtime.splitter_drag_offset = split_position - mouse_position
}

//   Apply the active splitter drag while preserving all pane minimums.
splitter_apply_drag :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    mouse_input: Mouse_Input_State) {

    if !mouse_input.left_down {
        splitter_release_capture(ui_runtime)
        return
    }
    if splitter_owns_press(ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID) {
        ui_runtime.vertical_split_x = clamp(
            mouse_input.position.x + ui_runtime.splitter_drag_offset,
            f32(WORLD_MIN_WIDTH), f32(WINDOW_WIDTH - RIGHT_PANEL_MIN_WIDTH))
    } else if splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_HORIZONTAL_PRESS_ID) {
        ui_runtime.horizontal_split_y = clamp(
            mouse_input.position.y + ui_runtime.splitter_drag_offset,
            f32(WORLD_MIN_HEIGHT), f32(WINDOW_HEIGHT - BOTTOM_PANEL_MIN_HEIGHT))
    }
}

//   Update splitter capture, positions, and hover fades before layout is prepared.
update_splitters :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    mouse_input: Mouse_Input_State,
    dt: f32) {

    locked := splitters_locked_for_gif(ui_runtime.gif_capture_phase)
    axis, hovered := splitter_hovered_axis(mouse_input.position,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
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
    ui_runtime.vertical_split_hover = splitter_update_fade(
        ui_runtime.vertical_split_hover, vertical_target, dt)
    ui_runtime.horizontal_split_hover = splitter_update_fade(
        ui_runtime.horizontal_split_hover, horizontal_target, dt)
}

//   Draw splitter feedback and apply the active resize cursor.
draw_splitters :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    mouse_position: rl.Vector2) {

    axis, hovered := splitter_hovered_axis(mouse_position,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    vertical_owned := splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID)
    horizontal_owned := splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_HORIZONTAL_PRESS_ID)
    if splitters_locked_for_gif(ui_runtime.gif_capture_phase) {
        hovered = false
    }
    if vertical_owned || (hovered && axis == .Vertical) {
        rl.SetMouseCursor(.RESIZE_EW)
    } else if horizontal_owned || (hovered && axis == .Horizontal) {
        rl.SetMouseCursor(.RESIZE_NS)
    } else {
        rl.SetMouseCursor(.DEFAULT)
    }

    vertical := splitter_geometry(.Vertical,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    horizontal := splitter_geometry(.Horizontal,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    if ui_runtime.vertical_split_hover > 0 {
        rl.DrawRectangleRec(vertical.visible_rect,
            rl.Fade(SPLITTER_COLOR, ui_runtime.vertical_split_hover))
    }
    if ui_runtime.horizontal_split_hover > 0 {
        rl.DrawRectangleRec(horizontal.visible_rect,
            rl.Fade(SPLITTER_COLOR, ui_runtime.horizontal_split_hover))
    }
}