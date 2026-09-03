package dynview_core

import app_core "../../core"

import rl "vendor:raylib"

UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

TEXT_PADDING :: 8

// Style schema revision used for cache invalidation when style mapping changes.
DYNVIEW_STYLE_REVISION_PLAIN_TEXT :: 3

DYNVIEW_STYLE_DEFAULT :: 0
DYNVIEW_STYLE_PROMPT :: 1
DYNVIEW_STYLE_OUTPUT :: 2
DYNVIEW_STYLE_ERROR :: 3
DYNVIEW_STYLE_BOLD :: 10
DYNVIEW_STYLE_ITALIC :: 11
DYNVIEW_STYLE_CENTER :: 12
DYNVIEW_STYLE_MEDIUM :: 13
DYNVIEW_STYLE_SEMIBOLD :: 14
DYNVIEW_STYLE_EXTRABOLD :: 15
DYNVIEW_STYLE_BLACK :: 16
DYNVIEW_STYLE_UNDERLINE :: 17
DYNVIEW_STYLE_INLINE_ATOM :: 20

DYNVIEW_STYLE_CUSTOM_FONT :: (1 << 24)
DYNVIEW_STYLE_CUSTOM_FONT_MASK :: 0xFF

Dynview_Text_Alignment :: app_core.Dynview_Text_Alignment
Dynview_Text_Style :: app_core.Dynview_Text_Style

//   One fixed style entry: a style id and its resolved text style.
Style_Entry :: struct {
    id:    i32,
    style: Dynview_Text_Style,
}

//   The shared default style used for unrecognized non-custom style ids.
STYLE_DEFAULT :: Dynview_Text_Style{
    color = UI_TEXT_COLOR,
    font_flags = .Regular,
    wrap_scale = 1.0,
    line_height_multiplier = 1.0,
}

//   Fixed host-owned styles keyed by style id.
STYLE_TABLE :: []Style_Entry{
    {DYNVIEW_STYLE_PROMPT, Dynview_Text_Style{
        color = rl.Color{186, 198, 228, 255},
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_OUTPUT, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_ERROR, Dynview_Text_Style{
        color = rl.Color{220, 95, 95, 255},
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_BOLD, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        bold = true,
        font_flags = .Bold,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_ITALIC, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        italic = true,
        font_flags = app_core.Font_Variant_Flags(
            u32(app_core.Font_Variant_Flags.Regular) |
            u32(app_core.Font_Variant_Flags.Italic)),
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_CENTER, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        alignment = .Center,
        font_flags = .Regular,
        force_line_start = true,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_MEDIUM, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Medium,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_SEMIBOLD, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Semibold,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_EXTRABOLD, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Extrabold,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_BLACK, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Black,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_UNDERLINE, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        underline = true,
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_INLINE_ATOM, Dynview_Text_Style{
        color = rl.Color{170, 190, 218, 255},
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
}

//   Resolve a style id using custom font flags encoded in the style id bits.
style_from_custom_font_flags :: #force_inline proc(
    style_id: i32) -> (Dynview_Text_Style, bool) {
    bits := u32(style_id)
    if (bits & u32(DYNVIEW_STYLE_CUSTOM_FONT)) == 0 {
        return Dynview_Text_Style{}, false
    }

    flags_bits := bits & u32(DYNVIEW_STYLE_CUSTOM_FONT_MASK)
    flags := app_core.Font_Variant_Flags(flags_bits)
    if flags == .None {
        flags = .Regular
    }

    weight := app_core.font_resolve_weight_from_flags(flags)
    italic := app_core.font_has_flag(flags, .Italic)

    _ = weight
    wrap_scale: f32 = 1.0
    line_height: f32 = 1.0

    return Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        italic = italic,
        font_flags = flags,
        wrap_scale = wrap_scale,
        line_height_multiplier = line_height,
    }, true
}

//   Resolve one style id using the fixed host-owned style table.
style_by_id :: #force_inline proc(style_id: i32) -> Dynview_Text_Style {
    custom_style, is_custom := style_from_custom_font_flags(style_id)
    if is_custom {
        return custom_style
    }

    table := STYLE_TABLE
    for entry in table {
        if entry.id == style_id {
            return entry.style
        }
    }
    return STYLE_DEFAULT
}

//   Return style-adjusted horizontal advance for one column unit.
effective_advance :: #force_inline proc(
    style: Dynview_Text_Style, wrap_advance: f32) -> f32 {
    return max(1.0, wrap_advance * max(0.5, style.wrap_scale))
}

//   Return style-aware ascent/descent estimates from active font size.
style_ascent_descent :: #force_inline proc(
    style: Dynview_Text_Style, font_size: f32) -> (f32, f32) {
    scale := max(0.8, style.wrap_scale)
    ascent := max(1.0, font_size * (0.74 + 0.06 * scale))
    descent := max(1.0, font_size * (0.22 + 0.02 * scale))
    if style.bold {
        ascent += font_size * 0.06
    }
    if style.italic {
        descent += font_size * 0.03
    }
    line_height_mult := max(0.6, style.line_height_multiplier)
    return ascent * line_height_mult, descent * line_height_mult
}
