package ui

import viewmodel "../model"

import native "../native"
import color "../../core/color"
import geometry "../../core/geometry"

SPLITTER_VISIBLE_WIDTH :: 3.0
SPLITTER_HIT_WIDTH :: 8.0
SPLITTER_FADE_SECONDS :: 0.15
SPLITTER_VERTICAL_PRESS_ID :: 6201
SPLITTER_HORIZONTAL_PRESS_ID :: 6202
SPLITTER_ACTIVE_COLOR :: color.Color_RGBA8{70, 130, 180, 255}

Splitter_Axis :: enum {
    Vertical,
    Horizontal,
}

//   Visible and interactive rectangles for one pane splitter.
Splitter_Geometry :: struct {
    visible_rect: geometry.Rectangle,
    hit_rect: geometry.Rectangle,
}

// Prepared geometry and visibility for one splitter axis.
Splitter_Axis_Preparation :: struct {
    control_geometry: viewmodel.Ui_Control_Geometry,
    visible_rect: geometry.Rectangle,
    value: f32,
    minimum: f32,
    maximum: f32,
    step: f32,
    changed: bool,
    sources: viewmodel.Ui_Control_Action_Source,
    orientation: viewmodel.Ui_Range_Orientation,
    opacity: f32,
    present: bool,
}

// Frame-local splitter geometry consumed by routing and observational drawing.
Splitter_Preparation :: struct {
    vertical: Splitter_Axis_Preparation,
    horizontal: Splitter_Axis_Preparation,
    locked: bool,
}

// Splitter_Value_Result carries converged axis values and their input provenance.
Splitter_Value_Result :: struct {
    vertical: f32,
    horizontal: f32,
    sources: viewmodel.Ui_Control_Action_Source,
}

// splitter_semantic_id returns the stable application-level axis identity.
splitter_semantic_id :: #force_inline proc(axis: Splitter_Axis) ->
    viewmodel.Ui_Node_Id {
    if axis == .Vertical {
        return semantic_control_id(.Application, SPLITTER_VERTICAL_PRESS_ID)
    }
    return semantic_control_id(.Application, SPLITTER_HORIZONTAL_PRESS_ID)
}

// splitter_axis_preparation builds one axis's prepared range and geometry.
splitter_axis_preparation :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, axis: Splitter_Axis,
    shape: Splitter_Geometry, value: f32,
    sources: viewmodel.Ui_Control_Action_Source) -> Splitter_Axis_Preparation {
    vertical := axis == .Vertical
    minimum := f32(WORLD_MIN_HEIGHT)
    maximum := max(WORLD_MIN_HEIGHT,
        f32(ui_runtime.window.height) - BOTTOM_PANEL_MIN_HEIGHT)
    original := ui_runtime.horizontal_split_y
    orientation := viewmodel.Ui_Range_Orientation.Vertical
    present := true
    if vertical {
        minimum = f32(WORLD_MIN_WIDTH)
        maximum = max(WORLD_MIN_WIDTH,
            f32(ui_runtime.window.width) - RIGHT_PANEL_MIN_WIDTH)
        original = ui_runtime.vertical_split_x
        orientation = .Horizontal
        present = ui_runtime.current_layout_mode == .Landscape
    }
    window_rect := viewmodel.Rectangle{
        0, 0, f32(ui_runtime.window.width), f32(ui_runtime.window.height)}
    return {{viewmodel.Rectangle(shape.hit_rect), window_rect},
        shape.visible_rect, value, minimum, maximum, 8, value != original,
        sources, orientation, vertical ? ui_runtime.vertical_split_hover :
            ui_runtime.horizontal_split_hover, present}
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
    mouse: geometry.Vector2, mode: viewmodel.Ui_Layout_Mode,
    split_x, split_y: f32,
    window: viewmodel.Ui_Window_Metrics) -> (Splitter_Axis, bool) {

    horizontal := splitter_geometry(.Horizontal, mode, split_x, split_y, window)
    if mode == .Portrait {
        return .Horizontal, geometry.rectangle_contains(horizontal.hit_rect, mouse)
    }
    vertical := splitter_geometry(.Vertical, mode, split_x, split_y, window)
    over_vertical := geometry.rectangle_contains(vertical.hit_rect, mouse)
    over_horizontal := geometry.rectangle_contains(horizontal.hit_rect, mouse)
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
    vertical_value := ui_runtime^.vertical_split_x
    if ui_runtime^.current_layout_mode == .Landscape {
        vertical_value = splitter_clamp_vertical(
            vertical, ui_runtime^.window.width)
    }
    horizontal_value := splitter_clamp_horizontal(
        horizontal, ui_runtime^.window.height)
    prepared := splitter_preparation(ui_runtime, false,
        vertical_value, horizontal_value, {.Scenario})
    apply_splitter_preparation(ui_runtime, prepared)
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
    mouse_input: Input_Frame,
    vertical, horizontal: ^f32) {

    if !input_frame_left_down(mouse_input) {
        splitter_release_capture(ui_runtime)
        return
    }
    if splitter_owns_press(ui_runtime.ui_press_owner, SPLITTER_VERTICAL_PRESS_ID) {
        vertical^ = splitter_clamp_vertical(
            mouse_input.mouse_position.x + ui_runtime.splitter_drag_offset,
            ui_runtime^.window.width)
    } else if splitter_owns_press(
        ui_runtime.ui_press_owner, SPLITTER_HORIZONTAL_PRESS_ID) {
        horizontal^ = splitter_clamp_horizontal(
            mouse_input.mouse_position.y + ui_runtime.splitter_drag_offset,
            ui_runtime^.window.height)
    }
}

// Resolve one portable cursor from current splitter hover and capture targets.
splitter_cursor :: proc(
    vertical_target, horizontal_target: f32) -> viewmodel.Ui_Cursor_Kind {
    if vertical_target > 0 {return .Resize_Ew}
    if horizontal_target > 0 {return .Resize_Ns}
    return .Default
}

// splitter_apply_semantic_axis resolves bounded keyboard changes for one axis.
splitter_apply_semantic_axis :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, axis: Splitter_Axis,
    value, minimum, maximum: f32) -> f32 {
    if ui_runtime.semantic_focus == nil {return value}
    id := splitter_semantic_id(axis)
    spec, valid := range_float_spec(minimum, maximum, 8,
        max(f32(8), (maximum - minimum) / 10))
    if !valid {return value}
    result := value
    if semantic_command_requested(ui_runtime.semantic_focus, id, .Increment) {
        result = range_float_step(result, 1, spec)
    }
    if semantic_command_requested(ui_runtime.semantic_focus, id, .Decrement) {
        result = range_float_step(result, -1, spec)
    }
    if semantic_command_requested(ui_runtime.semantic_focus, id, .Set_Minimum) {
        result = spec.minimum
    }
    if semantic_command_requested(ui_runtime.semantic_focus, id, .Set_Maximum) {
        result = spec.maximum
    }
    for command in ui_runtime.semantic_focus.commands[
        :ui_runtime.semantic_focus.command_count] {
        if command.target == id && command.kind == .Set_Value {
            result = f32(command.numeric_value)
        }
        if command.target == id && command.kind == .Page_Step {
            result = range_float_step(result, f32(command.amount), spec, true)
        }
    }
    return result
}

// Prepare final splitter hit, clip, and visible geometry after interaction.
splitter_preparation :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    locked: bool, vertical_value, horizontal_value: f32,
    sources: viewmodel.Ui_Control_Action_Source) -> Splitter_Preparation {
    vertical := splitter_geometry(.Vertical, ui_runtime^.current_layout_mode,
        vertical_value, horizontal_value,
        ui_runtime^.window)
    horizontal := splitter_geometry(.Horizontal, ui_runtime^.current_layout_mode,
        vertical_value, horizontal_value,
        ui_runtime^.window)
    return {
        vertical = splitter_axis_preparation(
            ui_runtime, .Vertical, vertical, vertical_value, sources),
        horizontal = splitter_axis_preparation(
            ui_runtime, .Horizontal, horizontal, horizontal_value, sources),
        locked = locked,
    }
}

// splitter_resolve_values converges pointer and semantic axis changes.
splitter_resolve_values :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, mouse_input: Input_Frame,
    axis: Splitter_Axis, hovered, locked: bool) -> Splitter_Value_Result {
    result := Splitter_Value_Result{
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y, {}}
    if locked {
        splitter_release_capture(ui_runtime)
        return result
    }
    splitter_try_capture(ui_runtime, mouse_input, axis, hovered)
    if ui_runtime.ui_press_owner.kind == .Splitter {
        splitter_apply_drag(ui_runtime, mouse_input,
            &result.vertical, &result.horizontal)
    }
    pointer_changed := result.vertical != ui_runtime.vertical_split_x ||
        result.horizontal != ui_runtime.horizontal_split_y
    result.sources += range_action_source(pointer_changed, .Pointer)
    before := result
    if ui_runtime.current_layout_mode == .Landscape {
        result.vertical = splitter_apply_semantic_axis(ui_runtime, .Vertical,
            result.vertical, WORLD_MIN_WIDTH, max(WORLD_MIN_WIDTH,
                f32(ui_runtime.window.width) - RIGHT_PANEL_MIN_WIDTH))
    }
    result.horizontal = splitter_apply_semantic_axis(ui_runtime, .Horizontal,
        result.horizontal, WORLD_MIN_HEIGHT, max(WORLD_MIN_HEIGHT,
            f32(ui_runtime.window.height) - BOTTOM_PANEL_MIN_HEIGHT))
    semantic_changed := result.vertical != before.vertical ||
        result.horizontal != before.horizontal
    result.sources += range_action_source(semantic_changed, .Semantic)
    return result
}

// splitter_update_feedback advances cursor and hover fades for both axes.
splitter_update_feedback :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, axis: Splitter_Axis,
    hovered, locked: bool, dt: f32) {
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

//   Update splitter capture, positions, and hover fades before layout is prepared.
update_splitters :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame,
    dt: f32) -> Splitter_Preparation {

    locked := splitters_locked_for_gif(ui_runtime.gif_capture_phase)
    axis, hovered := splitter_hovered_axis(input_frame_mouse_position(mouse_input),
        ui_runtime^.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y,
        ui_runtime^.window)
    values := splitter_resolve_values(
        ui_runtime, mouse_input, axis, hovered, locked)
    splitter_update_feedback(ui_runtime, axis, hovered, locked, dt)
    return splitter_preparation(ui_runtime, locked, values.vertical,
        values.horizontal, values.sources)
}

// apply_splitter_preparation commits prepared pane positions and ratio intent once.
apply_splitter_preparation :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    prepared: Splitter_Preparation) {
    if !prepared.vertical.changed && !prepared.horizontal.changed {return}
    ui_runtime.vertical_split_x = prepared.vertical.value
    ui_runtime.horizontal_split_y = prepared.horizontal.value
    splitter_store_ratios(ui_runtime)
}

// register_splitter_semantics publishes unlocked axis controls from prepared facts.
register_splitter_semantics :: proc(
    focus: ^viewmodel.Ui_Semantic_Focus_State,
    prepared: Splitter_Preparation) {
    if prepared.locked {return}
    axes := [2]struct {
        axis: Splitter_Axis,
        prepared: Splitter_Axis_Preparation,
        label: string,
    }{
        {.Vertical, prepared.vertical, "Resize left and right panes"},
        {.Horizontal, prepared.horizontal, "Resize upper and lower panes"},
    }
    for entry, order in axes {
        if !entry.prepared.present {continue}
        _ = semantic_register_control(focus, {
            id = splitter_semantic_id(entry.axis), role = .Slider,
            states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
            actions = {.Focus, .Increment, .Decrement, .Set_To_Bound, .Set_Value},
            region = .Pane_Layout,
            traversal_order = u16(order),
            bounds = entry.prepared.control_geometry.bounds,
            clip_bounds = entry.prepared.control_geometry.clip_bounds,
            numeric_range = {f64(entry.prepared.minimum),
                f64(entry.prepared.maximum), f64(entry.prepared.value),
                f64(entry.prepared.step), entry.prepared.orientation, true},
            label = entry.label,
        })
    }
}

// draw_encoded_splitters encodes current splitter feedback without changing policy.
draw_encoded_splitters :: proc(
    encoder: ^native.Draw_Encoder,
    prepared: Splitter_Preparation) {
    if prepared.vertical.present && prepared.vertical.opacity > 0 {
        draw_color := SPLITTER_ACTIVE_COLOR
        draw_color.a = u8(255 * clamp(prepared.vertical.opacity, f32(0), f32(1)))
        _ = native.draw_encoder_rectangle(
            encoder, prepared.vertical.visible_rect, draw_color)
    }
    if prepared.horizontal.present && prepared.horizontal.opacity > 0 {
        draw_color := SPLITTER_ACTIVE_COLOR
        draw_color.a = u8(255 * clamp(prepared.horizontal.opacity, f32(0), f32(1)))
        _ = native.draw_encoder_rectangle(
            encoder, prepared.horizontal.visible_rect, draw_color)
    }
}