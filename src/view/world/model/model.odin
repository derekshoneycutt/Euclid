package worldmodel

import portable_color "../../../core/color"
import geometry "../../../core/geometry"

TOOL_LENGTH :: 0.35

MAX_TOOL_BRUSH_OCCLUDERS :: 2

VIEW_WIDTH :: 900
VIEW_HEIGHT :: 500

// Iso_Scale owns display projection and screen-shake state.
Iso_Scale :: struct {
    scale: f32,
    x_offset: f32,
    y_offset: f32,
    half_scale: f32,
    quarter_scale: f32,
    main_light_dir: geometry.Vector3,
    use_directional_shadow: bool,
    screenshake_trauma: f32,
    screenshake_elapsed: f32,
    screenshake_offset_x: f32,
    screenshake_offset_y: f32,
    screenshake_phase: f32,
}

// Euclid_Drawing_Surface defines the display-owned world drawing plane.
Euclid_Drawing_Surface :: struct {
    zeros: geometry.Vector3,
    right_up: geometry.Vector3,
    left_down: geometry.Vector3,
    right_down: geometry.Vector3,
    color: portable_color.Color_RGBA8,
    edge_color: portable_color.Color_RGBA8,
    edge_size: f32,
}

ISO_SCALE_VALUE :: 800

ISO_X_OFFSET :: 450

ISO_Y_OFFSET :: 450

BACKGROUND_COLOR :: portable_color.Color_RGBA8{36, 5, 16, 255}

TOOL_COLOR :: portable_color.Color_RGBA8{160, 135, 135, 255}

SURFACE_COLOR :: portable_color.Color_RGBA8{25, 25, 25, 255}

SURFACE_EDGE_SIZE :: 0.05

SURFACE_EDGE_COLOR :: portable_color.Color_RGBA8{96, 65, 76, 255}
