package native

import color "../../core/color"

import rl "vendor:raylib"

// Convert one portable RGBA8 value at a native rendering boundary.
to_raylib_color :: #force_inline proc(value: color.Color_RGBA8) -> rl.Color {
    return rl.Color(value)
}