package ui

import viewmodel "../model"

// Shared UI constants and basic drawing helpers for panel modules.

import view_core "../core"
import view_font "../font"
import "../input"
import "../../dynview"
import dyncompile "../../dynview/compile"
import dyncore "../../dynview/core"
import "../../core"
import "core:fmt"

import rl "vendor:raylib"

TREE_PANEL_PADDING :: 10
WORLD_MIN_WIDTH :: 320
WORLD_MIN_HEIGHT :: 240
RIGHT_PANEL_MIN_WIDTH :: 240
BOTTOM_PANEL_MIN_HEIGHT :: 140
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
ACCORDION_HEADER_HEIGHT :: f32(34)
ACCORDION_PANEL_INSET :: f32(6)
ACCORDION_HEADER_PADDING :: f32(10)
ACCORDION_DISCLOSURE_SIZE :: f32(14)
ACCORDION_HEADER_LABEL_GAP :: f32(8)
ACCORDION_HEADER_TEXT_OFFSET_Y :: f32(7)
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

Input_Frame :: input.Input_Frame

// Geometry-stage result carried into static routing and later frame preparation.
Ui_Geometry_Preparation :: struct {
    pointer_capture: viewmodel.Ui_Press_Owner_State,
    compile_dynview: bool,
}

// Fixed frame-local control results prepared before services and rendering.
Ui_Control_Preparation :: struct {
    animation_controls: Animation_Control_Preparation,
    accordion: Accordion_Preparation,
    settings: Settings_View_Preparation,
    gif: Gif_View_Preparation,
    tree: Tree_List_Preparation,
}

// Post-layout interaction results prepared after Dynview compilation completes.
Ui_Layout_Interaction_Preparation :: struct {
    presentation: Presentation_Preparation,
}

// Convert one portable screen position for immediate use by Raylib UI APIs.
input_frame_mouse_position :: #force_inline proc(frame: Input_Frame) -> rl.Vector2 {
    return {frame.mouse_position.x, frame.mouse_position.y}
}

// Report whether the primary pointer button was pressed this frame.
input_frame_left_pressed :: #force_inline proc(frame: Input_Frame) -> bool {
    return .Left in frame.mouse_pressed
}

// Report whether the primary pointer button remains down this frame.
input_frame_left_down :: #force_inline proc(frame: Input_Frame) -> bool {
    return .Left in frame.mouse_down
}

// Report whether the primary pointer button was released this frame.
input_frame_left_released :: #force_inline proc(frame: Input_Frame) -> bool {
    return .Left in frame.mouse_released
}

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

// Prepare panel geometry while preserving capture identity from frame start.
prepare_ui_geometry :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: Input_Frame) -> Ui_Geometry_Preparation {
    ui_runtime := &state^.ui_runtime
    capture_for_frame := ui_runtime^.ui_press_owner
    frame_dt := min(f32(0.05), max(f32(0), rl.GetFrameTime()))
    update_splitters(ui_runtime, mouse_input, frame_dt)
    regions := compute_ui_regions(ui_runtime.current_layout_mode,
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    if !validate_ui_regions(regions) {
        fmt.println("[ui] Warning: invalid regions; using baseline fallback")
        regions = compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT)
    }
    state^.ui_runtime.ui_regions = regions
    view_core.fit_iso_scale_to_viewport(
        state^.iso_scale, regions.world_rect.width, regions.world_rect.height)

    text_panel := view_text_content_panel(regions.text_rect)
    dynview.track_panel(&state^.dynview, text_panel)
    dynview.track_font(
        &state^.dynview, TREE_FONT_SIZE, TEXT_WRAP_ADVANCE, TEXT_ROW_HEIGHT)
    dynview.track_style(&state^.dynview, dyncore.DYNVIEW_STYLE_REVISION_PLAIN_TEXT)
    return {capture_for_frame, dyncompile.compile_is_needed(&state^.dynview)}
}

// Resolve static UI targets after authoritative panel geometry is available.
prepare_ui_static_interaction :: proc(
    state: ^core.Euclid_General_State,
    frame: Input_Frame,
    capture: viewmodel.Ui_Press_Owner_State) {
    _ = ui_route_interaction_frame(&state^.ui_runtime, {
        frame = frame,
        terminal_present = is_terminal_selected(state),
        capture = capture,
    })
}

// Return a frame copy containing only pointer fields routed to the accordion.
ui_accordion_input_frame :: proc(
    frame: Input_Frame,
    routed: viewmodel.Ui_Surface_Interaction) -> Input_Frame {
    if routed.pointer && routed.wheel {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels, .Wheel})
    }
    if routed.pointer {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels})
    }
    if routed.wheel {
        return input.input_frame_filter_pointer(frame, {.Screen_Position, .Wheel})
    }
    return input.input_frame_filter_pointer(frame, {.Screen_Position})
}

// Return pointer input only when the animation overlay owns this frame.
ui_animation_control_input_frame :: proc(
    frame: Input_Frame,
    routed: viewmodel.Ui_Interaction_Frame) -> Input_Frame {
    target := routed.pointer_target
    if target.kind == .Control && animation_control_id(target.id) {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels})
    }
    return input.input_frame_filter_pointer(frame, {.Screen_Position})
}

// Resolve geometry-known controls and commit their actions before services run.
prepare_ui_controls :: proc(
    state: ^core.Euclid_General_State,
    frame: Input_Frame) -> Ui_Control_Preparation {
    animation_frame := ui_animation_control_input_frame(
        frame, state^.ui_runtime.interaction_frame)
    routed_frame := ui_accordion_input_frame(
        frame, state^.ui_runtime.interaction_frame.accordion)
    result := Ui_Control_Preparation{}
    result.animation_controls = prepare_animation_controls(state, animation_frame)
    accordion_panel := state^.ui_runtime.ui_regions.accordion_rect
    result.accordion = prepare_accordion_view(
        state, accordion_panel, routed_frame)
    content_panel := result.accordion.layout.content
    switch state^.ui_runtime.active_accordion_section {
    case .Library:
        result.tree = prepare_tree_list_panel({
            ji = state^.julia_interface,
            ui_runtime = &state^.ui_runtime,
            list_panel = content_panel,
            mouse_input = routed_frame,
            scroll_y = &state^.ui_runtime.tree_scroll_y,
            font = view_font.cache_borrow(&state^.font_cache, .Regular),
            font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        })
    case .Save_Gif:
        result.gif = prepare_gif_view(state, content_panel, routed_frame)
    case .Settings:
        result.settings = prepare_settings_view(state, content_panel, routed_frame)
    }
    return result
}

// Resolve layout-dependent presentation interaction before drawing begins.
prepare_ui_layout_interaction :: proc(
    state: ^core.Euclid_General_State,
    frame: Input_Frame) -> Ui_Layout_Interaction_Preparation {
    routed := state^.ui_runtime.interaction_frame.presentation
    presentation_frame := input.input_frame_filter_pointer(frame,
        routed.pointer ? input.Input_Pointer_Fields{
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels,
            .Wheel} : input.Input_Pointer_Fields{.Screen_Position})
    if !routed.wheel { presentation_frame.mouse_wheel_delta = 0 }
    return {presentation = prepare_presentation_interaction(state,
        state^.ui_runtime.ui_regions.text_rect, presentation_frame,
        routed.keyboard)}
}

//   Render all UI panels in baseline layout.
draw_ui_panels :: proc(
    state: ^core.Euclid_General_State,
    input_frame: Input_Frame,
    terminal_frame: Terminal_Prepared_Frame,
    controls: Ui_Control_Preparation,
    layout_interaction: Ui_Layout_Interaction_Preparation) {
    regions := state^.ui_runtime.ui_regions

    draw_animation_controls(
        state, input_frame, controls.animation_controls)

    bottom_bar := rl.Rectangle{
        regions.world_rect.x,
        regions.world_rect.y + regions.world_rect.height,
        regions.world_rect.width,
        WINDOW_HEIGHT - regions.world_rect.height,
    }
    rl.DrawRectangleRec(bottom_bar, UI_BACK_COLOR)
    draw_view_text_panel(state, regions.text_rect, terminal_frame,
        layout_interaction.presentation)

    right_bar := rl.Rectangle{
        regions.world_rect.x + regions.world_rect.width,
        0,
        WINDOW_WIDTH - regions.world_rect.width,
        WINDOW_HEIGHT,
    }
    rl.DrawRectangleRec(right_bar, UI_BACK_COLOR)
    draw_accordion_view(state, regions.accordion_rect, input_frame, controls)
    draw_splitters(&state^.ui_runtime, input_frame_mouse_position(input_frame))
}
