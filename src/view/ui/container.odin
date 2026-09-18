package ui

import rl "vendor:raylib"

Container_Fill_Variant :: enum {
    Dark_Red,
    Grey,
}

Container_Draw_Result :: struct {
    drawn_rect: rl.Rectangle,
    inner_rect: rl.Rectangle,
}

//   Resolve container fill color from the selected visual family variant.
container_fill_color :: #force_inline proc(
    fill_variant: Container_Fill_Variant) -> rl.Color {
    switch fill_variant {
    case .Dark_Red:
        return BACKGROUND_COLOR
    case .Grey:
        return UI_COMPONENT_BACKGROUND_COLOR
    }

    return BACKGROUND_COLOR
}

//   Return clamped outer and inner geometry without drawing the container.
container_geometry :: proc(
    rect: rl.Rectangle, border_thickness: f32) -> Container_Draw_Result {
    drawn_rect := clamp_non_negative_rect(rect)
    border := max(0.0, border_thickness)

    inner_rect := rl.Rectangle{
        drawn_rect.x + border,
        drawn_rect.y + border,
        drawn_rect.width - border * 2,
        drawn_rect.height - border * 2,
    }
    inner_rect = clamp_non_negative_rect(inner_rect)
    return Container_Draw_Result{
        drawn_rect = drawn_rect,
        inner_rect = inner_rect,
    }
}

//   Draw a container fill+border and return clamped outer/inner geometry.
draw_container_with_border :: proc(
    rect: rl.Rectangle,
    fill_variant: Container_Fill_Variant,
    border_thickness: f32) -> Container_Draw_Result {

    geometry := container_geometry(rect, border_thickness)
    drawn_rect := geometry.drawn_rect
    border := max(0.0, border_thickness)

    rl.DrawRectangleRec(drawn_rect, container_fill_color(fill_variant))
    if border > 0 {
        rl.DrawRectangleLinesEx(drawn_rect, border, UI_BORDER_COLOR)
    }

    return geometry
}

//   Draw a container using the standard 1px border thickness.
draw_container :: proc(
    rect: rl.Rectangle,
    fill_variant: Container_Fill_Variant) -> Container_Draw_Result {

    return draw_container_with_border(rect, fill_variant, 1)
}