package dynview

import "../../../core"
import view_core "../../core"

import rl "vendor:raylib"

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
DYNVIEW_STYLE_INLINE_ATOM :: 20

DYNVIEW_STYLE_CUSTOM_FONT :: (1 << 24)
DYNVIEW_STYLE_CUSTOM_FONT_MASK :: 0xFF

Dynview_Text_Alignment :: enum {
    Left,
    Center,
}

Dynview_Text_Style :: struct {
    color: rl.Color,
    alignment: Dynview_Text_Alignment,
    bold: bool,
    italic: bool,
    font_flags: core.Font_Variant_Flags,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
    force_line_start: bool,
    wrap_scale: f32,
}

//   Resolve a style id using custom font flags encoded in the style id bits.
style_from_custom_font_flags :: #force_inline proc(style_id: i32) -> (Dynview_Text_Style, bool) {
    bits := u32(style_id)
    if (bits & u32(DYNVIEW_STYLE_CUSTOM_FONT)) == 0 {
        return Dynview_Text_Style{}, false
    }

    flags_bits := bits & u32(DYNVIEW_STYLE_CUSTOM_FONT_MASK)
    flags := core.Font_Variant_Flags(flags_bits)
    if flags == .None {
        flags = .Regular
    }

    weight := view_core.font_resolve_weight_from_flags(flags)
    italic := view_core.font_has_flag(flags, .Italic)

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

    switch style_id {
    case DYNVIEW_STYLE_PROMPT:
        return Dynview_Text_Style{
            color = rl.Color{186, 198, 228, 255},
            font_flags = .Regular,
            indent_cols = 1,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_OUTPUT:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            font_flags = .Regular,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_ERROR:
        return Dynview_Text_Style{
            color = rl.Color{220, 95, 95, 255},
            font_flags = .Regular,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_BOLD:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            bold = true,
            font_flags = .Bold,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_ITALIC:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            italic = true,
            font_flags = core.Font_Variant_Flags(
                u32(core.Font_Variant_Flags.Regular) |
                u32(core.Font_Variant_Flags.Italic)),
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_CENTER:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            alignment = .Center,
            font_flags = .Regular,
            force_line_start = true,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_MEDIUM:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            font_flags = .Medium,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_SEMIBOLD:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            font_flags = .SemiBold,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_EXTRABOLD:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            font_flags = .ExtraBold,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_BLACK:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            font_flags = .Black,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    case DYNVIEW_STYLE_INLINE_ATOM:
        return Dynview_Text_Style{
            color = rl.Color{170, 190, 218, 255},
            font_flags = .Regular,
            wrap_scale = 1.0,
            line_height_multiplier = 1.0,
        }
    }

    return Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        font_flags = .Regular,
        wrap_scale = 1.0,
        line_height_multiplier = 1.0,
    }
}
