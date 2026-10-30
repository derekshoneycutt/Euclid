package theme



TREE_PANEL_PADDING :: 10

WORLD_MIN_WIDTH :: 320

WORLD_MIN_HEIGHT :: 240

RIGHT_PANEL_MIN_WIDTH :: 240

BOTTOM_PANEL_MIN_HEIGHT :: 140

TREE_ROW_HEIGHT :: 22

TREE_INDENT :: 16

TREE_FONT_SIZE :: 16

TEXT_SIZE_DEFAULT_PERCENT :: 100
TEXT_SIZE_MIN_PERCENT :: 100
TEXT_SIZE_STEP_PERCENT :: 25
TEXT_SIZE_MAX_PERCENT :: 175

CONTROL_SIZE_DEFAULT_PERCENT :: 100
CONTROL_SIZE_MIN_PERCENT :: 100
CONTROL_SIZE_STEP_PERCENT :: 25
CONTROL_SIZE_MAX_PERCENT :: 200

TEXT_ROW_HEIGHT :: 22

TEXT_PADDING :: 8

TEXT_WRAP_ADVANCE :: 8.0

SCROLLBAR_WIDTH :: 8

SCROLLBAR_THUMB_MIN_HEIGHT :: 24

ACCORDION_HEADER_HEIGHT :: f32(32)

ACCORDION_PANEL_INSET :: f32(6)

ACCORDION_HEADER_PADDING :: f32(10)

ACCORDION_DISCLOSURE_SIZE :: f32(14)

ACCORDION_HEADER_LABEL_GAP :: f32(8)

ACCORDION_HEADER_TEXT_OFFSET_Y :: f32(6)

ANIMATION_CONTROL_BUTTON_SIZE :: f32(30)

ANIMATION_CONTROL_BUTTON_GAP :: f32(4)

ANIMATION_CONTROL_PADDING :: f32(6)

ANIMATION_CONTROL_EDGE_INSET :: f32(12)

ANIMATION_CONTROL_ICON_SCALE :: f32(0.74)

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

SETTINGS_TOGGLE_TOP_OFFSET :: 162

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

SETTINGS_GIF_FRAME_TO_TIMING_SEGMENT_SIZE :: SETTINGS_GIF_SLIDER_ROW_GAP

SETTINGS_GIF_TIMING_TO_BUTTON_SEGMENT_SIZE :: 48

SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE ::
    SETTINGS_GIF_STATUS_TOP_OFFSET - SETTINGS_GIF_BUTTON_TOP_OFFSET

SETTINGS_GIF_TIMING_BUTTON_TOP_OFFSET :: 18

SETTINGS_GIF_TIMING_BUTTON_GAP :: 4

SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET :: 18

SETTINGS_GIF_STATUS_PATH_ROW_OFFSET :: 36

// Keep panel action buttons padded consistently at every supported UI scale.
ui_panel_button_height :: #force_inline proc(
    text_percent: int,
    control_percent := CONTROL_SIZE_DEFAULT_PERCENT) -> f32 {
    scale := ui_effective_control_scale(text_percent, control_percent)
    return max(ui_control_scaled_metric(
            SETTINGS_GIF_BUTTON_HEIGHT, text_percent, control_percent),
        ui_font_size(text_percent) + 8 * scale)
}

// ui_text_scale_factor converts a validated text-size preference to a safe multiplier.
ui_text_scale_factor :: #force_inline proc(percent: int) -> f32 {
    return f32(clamp(percent, TEXT_SIZE_MIN_PERCENT, TEXT_SIZE_MAX_PERCENT)) / 100
}

// ui_effective_control_scale preserves text-driven geometry while allowing larger controls.
ui_effective_control_scale :: #force_inline proc(
    text_percent, control_percent: int) -> f32 {
    text_scale := ui_text_scale_factor(text_percent)
    control_scale := f32(clamp(control_percent,
        CONTROL_SIZE_MIN_PERCENT, CONTROL_SIZE_MAX_PERCENT)) / 100
    return max(text_scale, control_scale)
}

// ui_control_size_scale applies only the independent non-font control preference.
ui_control_size_scale :: #force_inline proc(control_percent: int) -> f32 {
    return f32(clamp(control_percent,
        CONTROL_SIZE_MIN_PERCENT, CONTROL_SIZE_MAX_PERCENT)) / 100
}

// ui_control_scaled_metric composes control and text geometry without altering fonts.
ui_control_scaled_metric :: #force_inline proc(
    value: f32, text_percent, control_percent: int) -> f32 {
    return value * ui_effective_control_scale(text_percent, control_percent)
}

// ui_control_size_metric scales a target-only metric without text-size side effects.
ui_control_size_metric :: #force_inline proc(
    value: f32, control_percent: int) -> f32 {
    return value * ui_control_size_scale(control_percent)
}

// ui_font_size resolves a logical UI font size under the active text-size preference.
ui_font_size :: #force_inline proc(percent: int) -> f32 {
    return TREE_FONT_SIZE * ui_text_scale_factor(percent)
}

// ui_scaled_metric scales layout distances that are coupled to interface text.
ui_scaled_metric :: #force_inline proc(value: f32, percent: int) -> f32 {
    return value * ui_text_scale_factor(percent)
}

// ui_tree_row_height keeps Library row hit targets matched to larger labels.
ui_tree_row_height :: #force_inline proc(
    text_percent: int, control_percent := CONTROL_SIZE_DEFAULT_PERCENT) -> f32 {
    return ui_control_scaled_metric(
        f32(TREE_ROW_HEIGHT), text_percent, control_percent)
}
