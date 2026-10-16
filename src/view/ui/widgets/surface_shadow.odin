package uiwidgets

import native "../../native"
import geometry "../../../core/geometry"
import theme "../theme"

// surface_shadow_draw maps UI elevation policy to the native colored mesh.
surface_shadow_draw :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle,
    elevation: theme.Ui_Elevation) -> bool {
    preset: theme.Ui_Shadow_Preset
    switch elevation {
    case .Low:
        preset = theme.UI_ELEVATION_LOW
    case .Medium:
        preset = theme.UI_ELEVATION_MEDIUM
    case .High:
        preset = theme.UI_ELEVATION_HIGH
    }
    return native.draw_encoder_shadow(encoder, bounds, {
        contact_offset = preset.contact_offset,
        cast_offset = preset.cast_offset,
        feather = preset.feather,
        contact_opacity = preset.contact_opacity,
        cast_opacity = preset.cast_opacity,
        tint = preset.tint,
    })
}
