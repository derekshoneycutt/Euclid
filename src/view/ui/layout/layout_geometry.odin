package uilayout

import geometry "../../../core/geometry"

//   Clamp a rectangle so width and height are never negative.
clamp_non_negative_rect :: #force_inline proc(
    rect: geometry.Rectangle) -> geometry.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
}
