package view_core

import viewmodel "../model"

import "../../core"
import color "../../core/color"
import geometry "../../core/geometry"
import particlemodel "../../particles/model"

ISO_SCALE_VALUE :: 800
ISO_X_OFFSET :: 450
ISO_Y_OFFSET :: 450

LIMIT_FPS :: 60
FIXED_DT :: 1.0 / LIMIT_FPS
MAX_FRAME_DT :: 0.25
MAX_STEPS_PER_FRAME :: 6
FPS_AVERAGE_BUCKET_COUNT :: 60

ALLOWED_CONSTRAINT_ERROR :: 0.0001

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280

VIEW_HEIGHT :: 500
BOTTOM_BAR_HEIGHT :: WINDOW_HEIGHT - VIEW_HEIGHT
VIEW_WIDTH :: 900
RIGHT_BAR_WIDTH :: WINDOW_WIDTH - VIEW_WIDTH

WINDOW_TITLE :: "Euclid's Elements"

JULIA_MONO_FONT_LOAD_SIZE :: 64

BACKGROUND_COLOR :: color.Color_RGBA8{36, 5, 16, 255}
TOOL_COLOR :: color.Color_RGBA8{160, 135, 135, 255}

UI_BACK_COLOR :: color.Color_RGBA8{66, 35, 46, 255}
UI_BORDER_COLOR :: color.Color_RGBA8{86, 55, 66, 255}
UI_TEXT_COLOR :: color.Color_RGBA8{175, 150, 150, 255}

UI_COMPONENT_BACKGROUND_COLOR :: color.Color_RGBA8{25, 25, 25, 255}

SURFACE_COLOR :: color.Color_RGBA8{25, 25, 25, 255}
SURFACE_EDGE_SIZE :: 0.05
SURFACE_EDGE_COLOR :: color.Color_RGBA8{96, 65, 76, 255}


TREE_FONT_SIZE :: 16

TOOL_LENGTH :: viewmodel.TOOL_LENGTH

Vector2 :: geometry.Vector2
Vector3 :: geometry.Vector3
Iso_Scale :: viewmodel.Iso_Scale
Particle :: particlemodel.Particle
Particle_System :: particlemodel.Particle_System
Euclid_Drawing_Surface :: viewmodel.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings
