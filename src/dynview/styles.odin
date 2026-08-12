package dynview

import "../core"

import rl "vendor:raylib"

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
        font_flags = core.Font_Variant_Flags(
            u32(core.Font_Variant_Flags.Regular) |
            u32(core.Font_Variant_Flags.Italic)),
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
        font_flags = .SemiBold,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }},
    {DYNVIEW_STYLE_EXTRABOLD, Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .ExtraBold,
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
    flags := core.Font_Variant_Flags(flags_bits)
    if flags == .None {
        flags = .Regular
    }

    weight := core.font_resolve_weight_from_flags(flags)
    italic := core.font_has_flag(flags, .Italic)

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
