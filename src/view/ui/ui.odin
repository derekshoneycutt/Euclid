package ui

// Shared UI constants and basic drawing helpers for panel modules.

import view_core "../core"
import "../../core"
import "core:fmt"

import rl "vendor:raylib"

TREE_PANEL_PADDING :: 10
TREE_ROW_HEIGHT :: 22
TREE_INDENT :: 16
TREE_FONT_SIZE :: 16
TEXT_ROW_HEIGHT :: 22
TEXT_PADDING :: 8
TEXT_WRAP_ADVANCE :: 8.0
SCROLLBAR_WIDTH :: 8
SCROLLBAR_THUMB_MIN_HEIGHT :: 24
TREE_TOOLBAR_HEIGHT :: 28
TREE_TOOLBAR_BUTTON_SIZE :: 20
TREE_TOOLBAR_GAP :: 6
SETTINGS_TRACK_HEIGHT :: 8
SETTINGS_KNOB_WIDTH :: 10
WHEEL_SCROLL_MULTIPLIER :: 2
SCROLLBAR_DRAG_EPSILON :: 0.001
TREE_ROW_ICON_OFFSET_X :: 2
TREE_ROW_ICON_OFFSET_Y :: 3
TREE_ROW_ICON_SIZE :: 16
TREE_ROW_LABEL_OFFSET_X :: 22
TREE_ROW_LABEL_OFFSET_Y :: 2

SETTINGS_PANEL_INSET :: 8
SETTINGS_HEADER_TOP_OFFSET :: 8
SETTINGS_SLIDER_LABEL_TOP_OFFSET :: 36
SETTINGS_TRACK_TOP_OFFSET :: 22
SETTINGS_TRACK_HIT_PAD_Y :: 6
SETTINGS_KNOB_PAD_Y :: 4
SETTINGS_VALUE_TOP_OFFSET :: 16
SETTINGS_STATS_TOP_OFFSET :: 46
SETTINGS_STATS_ROW_GAP :: 22
SETTINGS_TOGGLE_TOP_OFFSET :: 118
SETTINGS_CHECKBOX_SIZE :: 14
SETTINGS_CHECKBOX_LABEL_GAP :: 8
SETTINGS_GIF_TOP_OFFSET :: 185
SETTINGS_GIF_SLIDER_ROW_GAP :: 36
SETTINGS_GIF_BUTTON_TOP_OFFSET :: 132
SETTINGS_GIF_BUTTON_HEIGHT :: 24
SETTINGS_GIF_STATUS_TOP_OFFSET :: 162
SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS :: 0.53

ISO_SCALE_VALUE :: view_core.ISO_SCALE_VALUE
ISO_X_OFFSET :: view_core.ISO_X_OFFSET
ISO_Y_OFFSET :: view_core.ISO_Y_OFFSET

LIMIT_FPS :: view_core.LIMIT_FPS
FIXED_DT :: view_core.FIXED_DT
MAX_FRAME_DT :: view_core.MAX_FRAME_DT
MAX_STEPS_PER_FRAME :: view_core.MAX_STEPS_PER_FRAME
FPS_AVERAGE_BUCKET_COUNT :: view_core.FPS_AVERAGE_BUCKET_COUNT

ALLOWED_CONSTRAINT_ERROR :: view_core.ALLOWED_CONSTRAINT_ERROR

WINDOW_HEIGHT :: view_core.WINDOW_HEIGHT
WINDOW_WIDTH :: view_core.WINDOW_WIDTH

VIEW_HEIGHT :: view_core.VIEW_HEIGHT
BOTTOM_BAR_HEIGHT :: view_core.BOTTOM_BAR_HEIGHT
VIEW_WIDTH :: view_core.VIEW_WIDTH
RIGHT_BAR_WIDTH :: view_core.RIGHT_BAR_WIDTH

WINDOW_TITLE :: view_core.WINDOW_TITLE

BACKGROUND_COLOR :: view_core.BACKGROUND_COLOR
TOOL_COLOR :: view_core.TOOL_COLOR

UI_BACK_COLOR :: view_core.UI_BACK_COLOR
UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR

UI_COMPONENT_BACKGROUND_COLOR :: view_core.UI_COMPONENT_BACKGROUND_COLOR

SURFACE_COLOR :: view_core.SURFACE_COLOR
SURFACE_EDGE_SIZE :: view_core.SURFACE_EDGE_SIZE
SURFACE_EDGE_COLOR :: view_core.SURFACE_EDGE_COLOR


//   Render all UI panels in baseline layout.
draw_ui_panels :: proc(state: ^core.Euclid_General_State) {
    regions := compute_ui_regions(state^.ui_runtime.current_layout_mode)
    if !validate_ui_regions(regions) {
        fmt.println("[ui] Warning: invalid regions; using baseline fallback")
        regions = compute_ui_regions(.Baseline)
    }
    state^.ui_runtime.ui_regions = regions

    bottom_bar := rl.Rectangle{
        regions.world_rect.x,
        regions.world_rect.y + regions.world_rect.height,
        regions.world_rect.width,
        WINDOW_HEIGHT - regions.world_rect.height,
    }
    rl.DrawRectangleRec(bottom_bar, UI_BACK_COLOR)
    draw_view_text_panel(state, regions.text_rect)

    right_bar := rl.Rectangle{
        regions.world_rect.x + regions.world_rect.width,
        0,
        WINDOW_WIDTH - regions.world_rect.width,
        WINDOW_HEIGHT,
    }
    rl.DrawRectangleRec(right_bar, UI_BACK_COLOR)
    draw_tree_view(state, regions.tree_rect)
}
