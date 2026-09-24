package native

import color "../../core/color"

import rl "vendor:raylib"
import sdl "vendor:sdl3"

// Convert one portable RGBA8 value at a native rendering boundary.
to_raylib_color :: #force_inline proc(value: color.Color_RGBA8) -> rl.Color {
    return rl.Color(value)
}

// from_raylib_color converts one temporary Raylib UI color to portable RGBA8.
from_raylib_color :: #force_inline proc(value: rl.Color) -> color.Color_RGBA8 {
    return color.Color_RGBA8(value)
}

// Convert one portable RGBA8 value to a normalized SDL GPU clear color.
to_sdl_color :: #force_inline proc(value: color.Color_RGBA8) -> sdl.FColor {
    scale := f32(1.0 / 255.0)
    return {
        f32(value[0]) * scale,
        f32(value[1]) * scale,
        f32(value[2]) * scale,
        f32(value[3]) * scale,
    }
}