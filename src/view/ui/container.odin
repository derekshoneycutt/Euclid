package ui

import geometry "../../core/geometry"

Container_Draw_Result :: struct {
    drawn_rect: geometry.Rectangle,
    inner_rect: geometry.Rectangle,
}

//   Return clamped outer and inner geometry without drawing the container.
container_geometry :: proc(
    rect: geometry.Rectangle, border_thickness: f32) -> Container_Draw_Result {
    drawn_rect := rect
    drawn_rect.width = max(f32(0), drawn_rect.width)
    drawn_rect.height = max(f32(0), drawn_rect.height)
    border := max(0.0, border_thickness)

    inner_rect := geometry.Rectangle{
        drawn_rect.x + border,
        drawn_rect.y + border,
        drawn_rect.width - border * 2,
        drawn_rect.height - border * 2,
    }
    inner_rect.width = max(f32(0), inner_rect.width)
    inner_rect.height = max(f32(0), inner_rect.height)
    return Container_Draw_Result{
        drawn_rect = drawn_rect,
        inner_rect = inner_rect,
    }
}
