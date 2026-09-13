package dynview_core

import fontmodel "../../view/font/model"


import "core:testing"

//   Verify custom font style flags decode to the expected weight and italic.
@(test)
custom_font_style_flags_decode_correctly :: proc(t: ^testing.T) {
    custom_flags := fontmodel.Font_Variant_Flags(
        u32(fontmodel.Font_Variant_Flags.Light) |
        u32(fontmodel.Font_Variant_Flags.Bold) |
        u32(fontmodel.Font_Variant_Flags.Italic))
    style_id := DYNVIEW_STYLE_CUSTOM_FONT | i32(u32(custom_flags) &
        u32(DYNVIEW_STYLE_CUSTOM_FONT_MASK))

    style, ok := style_from_custom_font_flags(style_id)

    testing.expect(t, ok)
    testing.expect(t, style.italic)
    testing.expect_value(t, style.font_flags, custom_flags)
    testing.expect_value(t, style.wrap_scale, f32(1.0))
    testing.expect_value(t, style.line_height_multiplier, f32(1.0))
    _, normal_ok := style_from_custom_font_flags(DYNVIEW_STYLE_OUTPUT)
    testing.expect(t, !normal_ok)
}