package ui

import "../../core"
import view_core "../core"
import view_font "../font"
import "core:strings"

import rl "vendor:raylib"

Checkbox_Params :: struct {
    id: int,
    rect: rl.Rectangle,
    checked: bool,
    enabled: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
    label: string,
    font: rl.Font,
    label_font_size: f32,
    label_offset_x: f32,
    label_offset_y: f32,
    font_resolver: view_font.Font_Resolver,
}

Checkbox_Result :: struct {
    box_drawn_rect: rl.Rectangle,
    label_drawn_rect: rl.Rectangle,
    toggled: bool,
    checked_out: bool,
    hovered: bool,
    pressed: bool,
}

//   Resolve checkbox label color from enabled state.
checkbox_label_color :: #force_inline proc(enabled: bool) -> rl.Color {
    if enabled {
        return UI_TEXT_COLOR
    }
    return rl.Color{110, 110, 110, 255}
}

//   Measure and place the optional checkbox label, returning its rect and merged hit rect.
checkbox_label_layout :: proc(
    params: Checkbox_Params,
    box_rect: rl.Rectangle,
    hit_rect: rl.Rectangle) -> (rl.Rectangle, rl.Rectangle) {

    if len(params.label) <= 0 {
        return rl.Rectangle{}, hit_rect
    }

    label_x := box_rect.x + box_rect.width + params.label_offset_x
    label_y := box_rect.y + params.label_offset_y
    label_cstr := strings.clone_to_cstring(params.label, context.temp_allocator)
    measured := rl.MeasureTextEx(params.font, label_cstr, params.label_font_size, 0)
    label_rect := rl.Rectangle{label_x, label_y,
        max(0.0, measured.x), max(0.0, measured.y)}
    return label_rect, checkbox_union_rect(hit_rect, label_rect)
}

//   Resolve whether this checkbox currently owns the shared press state.
checkbox_owns_press :: #force_inline proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Checkbox &&
        press_owner^.id == id
}

//   Capture shared press ownership for a checkbox when it is newly pressed.
checkbox_try_capture_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    params: Checkbox_Params,
    hovered: bool,
    can_interact: bool,
    owns_press: ^bool) {

    if !can_interact || press_owner^.active || !params.mouse.left_pressed || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Checkbox
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership and resolve checkbox toggle output.
checkbox_release_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    params: Checkbox_Params,
    can_interact: bool,
    hovered_item: bool,
    owns_press: ^bool) -> (bool, bool) {

    if !owns_press^ || !params.mouse.left_released {
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

//   Resolve checkbox border and checkmark colors from enabled state.
checkbox_mark_colors :: #force_inline proc(enabled: bool) -> (rl.Color, rl.Color) {
    if enabled {
        return UI_BORDER_COLOR, UI_TEXT_COLOR
    }
    return rl.Color{78, 78, 78, 255}, rl.Color{110, 110, 110, 255}
}

//   Return the smallest rectangle that contains both a and b.
checkbox_union_rect :: #force_inline proc(a, b: rl.Rectangle) -> rl.Rectangle {
    ax2 := a.x + a.width
    ay2 := a.y + a.height
    bx2 := b.x + b.width
    by2 := b.y + b.height

    min_x := min(a.x, b.x)
    min_y := min(a.y, b.y)
    max_x := max(ax2, bx2)
    max_y := max(ay2, by2)
    return rl.Rectangle{min_x, min_y, max(0.0, max_x - min_x), max(0.0, max_y - min_y)}
}

//   Convert screen-space mouse position into local interaction space.
checkbox_local_mouse :: #force_inline proc(
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.position.x - scroll_offset.x,
        mouse_input.position.y - scroll_offset.y,
    }
}

//   Build square checkbox box centered inside caller-provided rect.
checkbox_box_drawn_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    drawn_rect := clamp_non_negative_rect(rect)
    side := min(drawn_rect.width, drawn_rect.height)

    center_x := drawn_rect.x + drawn_rect.width * 0.5
    center_y := drawn_rect.y + drawn_rect.height * 0.5
    return rl.Rectangle{
        center_x - side * 0.5,
        center_y - side * 0.5,
        side,
        side,
    }
}

//   Draw the check mark and pressed-state outline for the box.
checkbox_draw_box_marks :: proc(
    box_rect: rl.Rectangle, checked_out, pressed: bool, border, mark: rl.Color) {

    rl.DrawRectangleLinesEx(box_rect, 1, border)
    if checked_out {
        p0 := rl.Vector2{box_rect.x + 3, box_rect.y + box_rect.height * 0.55}
        p1 := rl.Vector2{box_rect.x + 6, box_rect.y + box_rect.height - 3}
        p2 := rl.Vector2{box_rect.x + box_rect.width - 3, box_rect.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, mark)
        rl.DrawLineEx(p1, p2, 1.6, mark)
    }

    if pressed {
        rl.DrawRectangleLinesEx(box_rect, 2, border)
    }
}

//   Resolve hover capture and release for one checkbox, writing toggle state.
checkbox_resolve_interaction :: proc(
    params: Checkbox_Params,
    press_owner: ^core.Ui_Press_Owner_State,
    local_mouse: rl.Vector2,
    hit_rect: rl.Rectangle,
    out: ^Checkbox_Result) {

    hovered_item := rl.CheckCollisionPointRec(local_mouse, hit_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
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
    out.pressed = owns_press && params.mouse.left_down
}

//   Draw one checkbox and resolve release-confirmed toggle interaction.
draw_checkbox :: proc(
    params: Checkbox_Params,
    press_owner: ^core.Ui_Press_Owner_State) -> Checkbox_Result {

    drawn_rect := clamp_non_negative_rect(params.rect)
    box_rect := checkbox_box_drawn_rect(drawn_rect)
    local_mouse := checkbox_local_mouse(params.mouse, params.scroll_offset)

    hit_rect := drawn_rect
    label_rect := rl.Rectangle{}
    label_rect, hit_rect = checkbox_label_layout(params, box_rect, hit_rect)
    label_color := checkbox_label_color(params.enabled)

    result := Checkbox_Result{
        box_drawn_rect = box_rect,
        label_drawn_rect = label_rect,
    }
    checkbox_resolve_interaction(params, press_owner, local_mouse, hit_rect, &result)

    border, mark := checkbox_mark_colors(params.enabled)
    checkbox_draw_box_marks(box_rect, result.checked_out, result.pressed, border, mark)

    if len(params.label) > 0 {
        text_font := view_core.Ui_Text_Font{params.font, params.label_font_size}
        view_core.ui_text_shaped({
            resolver = params.font_resolver,
            key = .Regular,
            text = params.label,
            position = {label_rect.x, label_rect.y},
            color = label_color,
            font = text_font,
        })
    }

    return result
}