package ui

// Shared UI constants and basic drawing helpers for panel modules.

import view_core "../core"
import "../../dynview"
import dyncompile "../../dynview/compile"
import dyncore "../../dynview/core"
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
DYNVIEW_COPY_ICON_SIZE :: 14
DYNVIEW_COPY_ICON_X_PAD :: 6
TREE_TOOLBAR_HEIGHT :: 28
TREE_TOOLBAR_BUTTON_SIZE :: 20
TREE_TOOLBAR_GAP :: 6
TREE_TOOLBAR_EDGE_PAD :: 4
TREE_TOOLBAR_BUTTON_GAP :: 4
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
SETTINGS_SLIDER_LABEL_TOP_OFFSET :: 32
SETTINGS_TRACK_TOP_OFFSET :: 22
SETTINGS_TRACK_HIT_PAD_Y :: 6
SETTINGS_KNOB_PAD_Y :: 4
SETTINGS_VALUE_TOP_OFFSET :: 16
SETTINGS_STATS_TOP_OFFSET :: 26
SETTINGS_STATS_ROW_GAP :: 22
SETTINGS_TOGGLE_TOP_OFFSET :: 118
SETTINGS_CHECKBOX_SIZE :: 14
SETTINGS_CHECKBOX_LABEL_GAP :: 8
SETTINGS_CHECKBOX_HIT_PAD_Y :: 4
SETTINGS_CHECKBOX_TEXT_OFFSET_Y :: 1
SETTINGS_TOGGLE_ROW_GAP :: 22
SETTINGS_GIF_TOP_OFFSET :: 185
SETTINGS_GIF_SLIDER_ROW_GAP :: 36
SETTINGS_GIF_BUTTON_TOP_OFFSET :: 132
SETTINGS_GIF_BUTTON_HEIGHT :: 24
SETTINGS_GIF_STATUS_TOP_OFFSET :: 162
SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE :: SETTINGS_GIF_SLIDER_ROW_GAP
SETTINGS_GIF_FRAME_TO_BUTTON_SEGMENT_SIZE ::
    SETTINGS_GIF_BUTTON_TOP_OFFSET - SETTINGS_GIF_SLIDER_ROW_GAP * 2
SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE ::
    SETTINGS_GIF_STATUS_TOP_OFFSET - SETTINGS_GIF_BUTTON_TOP_OFFSET
SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET :: 18
SETTINGS_GIF_STATUS_PATH_ROW_OFFSET :: 36
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

DYNVIEW_STYLE_OUTPUT :: dyncore.DYNVIEW_STYLE_OUTPUT
DYNVIEW_STYLE_CUSTOM_FONT :: dyncore.DYNVIEW_STYLE_CUSTOM_FONT
DYNVIEW_STYLE_CUSTOM_FONT_MASK :: dyncore.DYNVIEW_STYLE_CUSTOM_FONT_MASK

Mouse_Input_State :: view_core.Mouse_Input_State

//   Clamp a rectangle so width and height are never negative.
clamp_non_negative_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
}

//   Prepare frame geometry and report whether Dynview cache construction is required.
prepare_ui_frame :: proc(state: ^core.Euclid_General_State) -> bool {
    regions := compute_ui_regions(state^.ui_runtime.current_layout_mode)
    if !validate_ui_regions(regions) {
        fmt.println("[ui] Warning: invalid regions; using baseline fallback")
        regions = compute_ui_regions(.Baseline)
    }
    state^.ui_runtime.ui_regions = regions

    text_panel := view_text_content_panel(regions.text_rect)
    dynview.track_panel(&state^.dynview, text_panel)
    dynview.track_font(
        &state^.dynview, TREE_FONT_SIZE, TEXT_WRAP_ADVANCE, TEXT_ROW_HEIGHT)
    dynview.track_style(&state^.dynview, dyncore.DYNVIEW_STYLE_REVISION_PLAIN_TEXT)
    return dyncompile.compile_is_needed(&state^.dynview)
}

//   Render all UI panels in baseline layout.
draw_ui_panels :: proc(state: ^core.Euclid_General_State) {
    regions := state^.ui_runtime.ui_regions
    mouse_input := view_core.capture_mouse_input_state()

    bottom_bar := rl.Rectangle{
        regions.world_rect.x,
        regions.world_rect.y + regions.world_rect.height,
        regions.world_rect.width,
        WINDOW_HEIGHT - regions.world_rect.height,
    }
    rl.DrawRectangleRec(bottom_bar, UI_BACK_COLOR)
    draw_view_text_panel(state, regions.text_rect, mouse_input)

    right_bar := rl.Rectangle{
        regions.world_rect.x + regions.world_rect.width,
        0,
        WINDOW_WIDTH - regions.world_rect.width,
        WINDOW_HEIGHT,
    }
    rl.DrawRectangleRec(right_bar, UI_BACK_COLOR)
    draw_tree_view(state, regions.tree_rect, mouse_input)
}
