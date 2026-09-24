package native

import color "../../core/color"

import sdl "vendor:sdl3"

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