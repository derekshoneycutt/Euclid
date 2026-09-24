package ui

import viewmodel "../model"

import view_core "../core"
import view_font "../font"
import geometry "../../core/geometry"

Checkbox_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    checked: bool,
    enabled: bool,
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    interaction_enabled: bool,
    label: string,
    font: view_font.Font_Face,
    label_font_size: f32,
    label_offset_x: f32,
    label_offset_y: f32,
    font_resolver: view_font.Font_Resolver,
}

Checkbox_Result :: struct {
    toggled: bool,
    checked_out: bool,
    hovered: bool,
    pressed: bool,
}

//   Measure and place the optional checkbox label, returning its rect and merged hit rect.
checkbox_label_layout :: proc(
    params: Checkbox_Params,
    box_rect: geometry.Rectangle,
    hit_rect: geometry.Rectangle) -> (geometry.Rectangle, geometry.Rectangle) {

    if len(params.label) <= 0 {
        return geometry.Rectangle{}, hit_rect
    }

    label_x := box_rect.x + box_rect.width + params.label_offset_x
    label_y := box_rect.y + params.label_offset_y
    measured_width, _ := view_core.ui_text_measure_monospace(
        params.label, params.font, params.label_font_size, 0)
    measured := geometry.Vector2{measured_width, params.label_font_size}
    label_rect := geometry.Rectangle{label_x, label_y,
        max(0.0, measured.x), max(0.0, measured.y)}
    return label_rect, checkbox_union_rect(hit_rect, label_rect)
}

//   Resolve whether this checkbox currently owns the shared press state.
checkbox_owns_press :: #force_inline proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Checkbox &&
        press_owner^.id == id
}

//   Capture shared press ownership for a checkbox when it is newly pressed.
checkbox_try_capture_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    params: Checkbox_Params,
    hovered: bool,
    can_interact: bool,
    owns_press: ^bool) {

    if !can_interact || press_owner^.active ||
        !input_frame_left_pressed(params.mouse) || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Checkbox
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership and resolve checkbox toggle output.
checkbox_release_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    params: Checkbox_Params,
    can_interact: bool,
    hovered_item: bool,
    owns_press: ^bool) -> (bool, bool) {

    if !owns_press^ || !input_frame_left_released(params.mouse) {
        return false, params.checked
    }

    toggled := can_interact && hovered_item
    checked_out := params.checked
    if toggled {
        checked_out = !params.checked
    }

    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
    return toggled, checked_out
}

//   Return the smallest rectangle that contains both a and b.
checkbox_union_rect :: #force_inline proc(
    a, b: geometry.Rectangle) -> geometry.Rectangle {
    ax2 := a.x + a.width
    ay2 := a.y + a.height
    bx2 := b.x + b.width
    by2 := b.y + b.height

    min_x := min(a.x, b.x)
    min_y := min(a.y, b.y)
    max_x := max(ax2, bx2)
    max_y := max(ay2, by2)
    return geometry.Rectangle{
        min_x, min_y, max(0.0, max_x - min_x), max(0.0, max_y - min_y)}
}

//   Convert screen-space mouse position into local interaction space.
checkbox_local_mouse :: #force_inline proc(
    mouse_input: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{
        mouse_input.mouse_position.x - scroll_offset.x,
        mouse_input.mouse_position.y - scroll_offset.y,
    }
}

//   Build square checkbox box centered inside caller-provided rect.
checkbox_box_drawn_rect :: #force_inline proc(
    rect: geometry.Rectangle) -> geometry.Rectangle {
    drawn_rect := rect
    drawn_rect.width = max(f32(0), drawn_rect.width)
    drawn_rect.height = max(f32(0), drawn_rect.height)
    side := min(drawn_rect.width, drawn_rect.height)

    center_x := drawn_rect.x + drawn_rect.width * 0.5
    center_y := drawn_rect.y + drawn_rect.height * 0.5
    return geometry.Rectangle{
        center_x - side * 0.5,
        center_y - side * 0.5,
        side,
        side,
    }
}

//   Resolve hover capture and release for one checkbox, writing toggle state.
checkbox_resolve_interaction :: proc(
    params: Checkbox_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    local_mouse: geometry.Vector2,
    hit_rect: geometry.Rectangle,
    out: ^Checkbox_Result) {

    hovered_item := geometry.rectangle_contains(hit_rect, local_mouse)
    hovered_space := geometry.rectangle_contains(
        params.interaction_space_rect, local_mouse)
    hovered := hovered_item && hovered_space

    owns_press := checkbox_owns_press(press_owner, params.id)
    can_interact := params.enabled && params.interaction_enabled
    checkbox_try_capture_press(press_owner, params, hovered, can_interact, &owns_press)

    toggled, checked_out := checkbox_release_press(
        press_owner,
        params,
        can_interact,
        hovered_item,
        &owns_press)

    out.toggled = toggled
    out.checked_out = checked_out
    out.hovered = hovered
    out.pressed = owns_press && input_frame_left_down(params.mouse)
}

//   Resolve one checkbox interaction without issuing drawing commands.
update_checkbox :: proc(
    params: Checkbox_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State) -> Checkbox_Result {

    drawn_rect := params.rect
    drawn_rect.width = max(f32(0), drawn_rect.width)
    drawn_rect.height = max(f32(0), drawn_rect.height)
    box_rect := checkbox_box_drawn_rect(drawn_rect)
    local_mouse := checkbox_local_mouse(params.mouse, params.scroll_offset)

    hit_rect := drawn_rect
    label_rect := geometry.Rectangle{}
    label_rect, hit_rect = checkbox_label_layout(params, box_rect, hit_rect)

    result := Checkbox_Result{}
    checkbox_resolve_interaction(params, press_owner, local_mouse, hit_rect, &result)
    return result
}
