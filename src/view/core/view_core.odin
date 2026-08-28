package view_core

import "../../core"

import rl "vendor:raylib"

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

BACKGROUND_COLOR :: rl.Color{36, 5, 16, 255}
TOOL_COLOR :: rl.Color{175, 150, 150, 255}

UI_BACK_COLOR :: rl.Color{66, 35, 46, 255}
UI_BORDER_COLOR :: rl.Color{86, 55, 66, 255}
UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

UI_COMPONENT_BACKGROUND_COLOR :: rl.Color{25, 25, 25, 255}

SURFACE_COLOR :: rl.Color{25, 25, 25, 255}
SURFACE_EDGE_SIZE :: 0.05
SURFACE_EDGE_COLOR :: rl.Color{96, 65, 76, 255}


TREE_FONT_SIZE :: 16

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Shapes_Point_Type :: core.Shapes_Point_Type
Shapes_Point :: core.Shapes_Point
Shapes_Constraint :: core.Shapes_Constraint
Shapes_Point_System :: core.Shapes_Point_System
Particle :: core.Particle
Particle_System :: core.Particle_System
Euclid_Drawing_Surface :: core.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings
