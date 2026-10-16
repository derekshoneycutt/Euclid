package theme

import color "../../../core/color"
import geometry "../../../core/geometry"

// Ui_Elevation names the shared UI surface hierarchy.
Ui_Elevation :: enum {
    Low,
    Medium,
    High,
}

// Ui_Shadow_Preset stores logical-pixel geometry and opacity for one elevation.
Ui_Shadow_Preset :: struct {
    contact_offset: geometry.Vector2,
    cast_offset: geometry.Vector2,
    feather: f32,
    contact_opacity: f32,
    cast_opacity: f32,
    tint: color.Color_RGBA8,
}

UI_SHADOW_TINT :: color.Color_RGBA8{22, 14, 16, 255}

UI_ELEVATION_LOW :: Ui_Shadow_Preset{
    contact_offset = {0.75, 0.75},
    cast_offset = {1.5, 2.5},
    feather = 3.5,
    contact_opacity = 0.26,
    cast_opacity = 0.20,
    tint = UI_SHADOW_TINT,
}

UI_ELEVATION_MEDIUM :: Ui_Shadow_Preset{
    contact_offset = {0.75, 0.75},
    cast_offset = {2.5, 4.5},
    feather = 5.5,
    contact_opacity = 0.26,
    cast_opacity = 0.20,
    tint = UI_SHADOW_TINT,
}

UI_ELEVATION_HIGH :: Ui_Shadow_Preset{
    contact_offset = {0.75, 0.75},
    cast_offset = {3.5, 6},
    feather = 8.5,
    contact_opacity = 0.26,
    cast_opacity = 0.20,
    tint = UI_SHADOW_TINT,
}
