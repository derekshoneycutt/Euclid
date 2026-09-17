package render_raylib

import colormodel "../../../color/model"
import geometrymodel "../../../geometry/model"
import rl "vendor:raylib"

// color converts one application color at the Raylib submission boundary.
color :: #force_inline proc(value: colormodel.Color_RGBA8) -> rl.Color {
    return {value.red, value.green, value.blue, value.alpha}
}

// application_color converts temporary Raylib values into application storage.
application_color :: #force_inline proc(value: rl.Color) -> colormodel.Color_RGBA8 {
    return {value.r, value.g, value.b, value.a}
}

// rectangle converts application bounds at the Raylib submission boundary.
rectangle :: #force_inline proc(value: geometrymodel.Rectangle) -> rl.Rectangle {
    return {value.x, value.y, value.width, value.height}
}

// application_rectangle converts Raylib-produced bounds into application storage.
application_rectangle :: #force_inline proc(
    value: rl.Rectangle) -> geometrymodel.Rectangle {
    return {value.x, value.y, value.width, value.height}
}