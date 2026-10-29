package ink

import "core:math"

import color "../../core/color"

Authored_Palette_Entry :: struct {
    rgb: [3]u8,
    normal_gray: u8,
    increased_gray: u8,
}

@(rodata)
authored_palette := [?]Authored_Palette_Entry{
    {{70, 130, 180}, 185, 212},
    {{255, 130, 171}, 230, 246},
    {{205, 198, 115}, 210, 230},
    {{153, 153, 153}, 165, 200},
    {{255, 187, 255}, 245, 255},
    {{144, 238, 144}, 220, 240},
    {{178, 34, 34}, 190, 220},
}

// resolve_content_ink maps original authored RGBA once for animation or Dynview.
resolve_content_ink :: proc(
    original: color.Color_RGBA8,
    monochrome: bool,
    effective_contrast: bool) -> color.Color_RGBA8 {
    if !monochrome {
        return original
    }

    for entry in authored_palette {
        if original[0] == entry.rgb[0] &&
            original[1] == entry.rgb[1] &&
            original[2] == entry.rgb[2] {
            gray := entry.normal_gray
            if effective_contrast {
                gray = entry.increased_gray
            }
            return {gray, gray, gray, original[3]}
        }
    }

    gray := authored_luminance_gray(original, effective_contrast)
    return {gray, gray, gray, original[3]}
}

// authored_luminance_gray maps linear Rec. 709 luminance into the selected range.
authored_luminance_gray :: proc(
    original: color.Color_RGBA8,
    effective_contrast: bool) -> u8 {
    red := srgb_to_linear(f64(original[0]) / 255)
    green := srgb_to_linear(f64(original[1]) / 255)
    blue := srgb_to_linear(f64(original[2]) / 255)
    luminance := red * 0.2126 + green * 0.7152 + blue * 0.0722
    minimum, maximum := f64(0.30), f64(0.82)
    if effective_contrast {
        minimum, maximum = 0.55, 1.0
    }
    mapped := minimum + luminance * (maximum - minimum)
    encoded := linear_to_srgb(mapped)
    return u8(clamp(int(math.floor(encoded*255+0.5)), 0, 255))
}

// srgb_to_linear decodes one normalized sRGB channel.
srgb_to_linear :: proc(encoded: f64) -> f64 {
    return encoded / 12.92 if encoded <= 0.04045 else
        math.pow((encoded + 0.055) / 1.055, 2.4)
}

// linear_to_srgb encodes one normalized linear-light channel.
linear_to_srgb :: proc(linear: f64) -> f64 {
    return 12.92 * linear if linear <= 0.0031308 else
        1.055 * math.pow(linear, 1.0/2.4) - 0.055
}
