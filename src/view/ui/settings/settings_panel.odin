package uisettings

import uilayout "../layout"
import native "../../native"
import core "../../../core"
import contentdata "../../../core/content"
import particlemodel "../../../particles/model"
import geometry "../../../core/geometry"
import historyruntime "../../../terminal/history/runtime"
import view_font "../../font"
import setting_model "../../../settings"
import fmt "core:fmt"
import log "core:log"
import math "core:math"
import viewmessages "../../messages"
import viewtext "../text"
import projection "../../world/projection"
import input "../../input"
import uiwidgets "../widgets"
import theme "../theme"
import terminalview "../../terminal"
import worldmodel "../../world/model"
import uisemantics "../semantics"
import uioverlay "../overlay"
import viewpreferences "../../preferences"
import viewmodel "../model"

SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID :: 6101
SETTINGS_ANIMATION_SCALE_SLIDER_ID :: 6106
SETTINGS_HISTORY_DELETE_BUTTON_ID :: 6104
SETTINGS_HISTORY_DELETE_STATUS_ID :: 6105
SETTINGS_HOVER_FOCUS_CHECKBOX_ID :: 4010
SETTINGS_CONTROL_SIZE_SLIDER_ID :: 6107
SETTINGS_SHOW_MAGNIFIER_CHECKBOX_ID :: 4011
SETTINGS_MAGNIFIER_INPUT_LOCK_CHECKBOX_ID :: 4012
SETTINGS_HISTORY_DELETE_TIMEOUT_SECONDS :: 5
SETTINGS_HISTORY_DELETE_SHAKE_SECONDS :: 0.3

// Settings_View_Labels snapshots localized strings before leaf control preparation.
Settings_View_Labels :: struct {
    maximum_dust: string,
    display_fps: string,
    limit_fps: string,
    drawing_sound: string,
    simd: string,
    gpu_dust: string,
    reduce_motion: string,
    enable_particle_effects: string,
    open_completed: string,
    particle_effects_help: string,
    open_completed_help: string,
    increased_contrast: string,
    hover_focus: string,
    hover_focus_tooltip: string,
    show_magnifier: string,
    show_magnifier_tooltip: string,
    magnifier_input_lock: string,
    magnifier_input_lock_tooltip: string,
    control_size: string,
    control_size_tooltip: string,
    text_size: string,
    animation_scale: string,
    animation_scale_tooltip: string,
    monochrome: string,
    persist_history: string,
    delete_history: string,
    confirm_delete_history: string,
    confirm_delete_history_value: string,
    history_delete_pending: string,
    history_delete_succeeded: string,
    history_delete_failed: string,
}

// Shared component and input dependencies for one settings panel preparation.
Settings_View_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    settings_panel: ^viewmodel.Ui_Settings_Panel_State,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    preferences: setting_model.Preferences,
    particle_system: ^particlemodel.Particle_System,
    gpu_dust_available: bool,
    platform_reduce_motion: bool,
    platform_increased_contrast: bool,
    simd_available: bool,
    labels: Settings_View_Labels,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
}

//   Row y-positions for the settings view's controls.
Settings_View_Rows :: struct {
    particles_header_y: f32,
    slider_label_y: f32,
    stats_y: f32,
    other_header_y: f32,
    animation_entries_y: f32,
    fps_y: f32,
    limit_y: f32,
    sound_y: f32,
    simd_y: f32,
    gpu_dust_y: f32,
    accessibility_header_y: f32,
    history_header_y: f32,
    persist_history_y: f32,
    delete_history_y: f32,
    history_delete_status_y: f32,
    reduce_motion_y: f32,
    enable_particle_effects_y: f32,
    open_completed_y: f32,
    increased_contrast_y: f32,
    hover_focus_y: f32,
    show_magnifier_y: f32,
    magnifier_input_lock_y: f32,
    monochrome_y: f32,
    system_motion_y: f32,
    system_contrast_y: f32,
    control_size_y: f32,
    animation_scale_y: f32,
    text_size_y: f32,
    save_status_y: f32,
}

// Settings_View_Layout_State carries the section cursor and scale metrics during layout.
Settings_View_Layout_State :: struct {
    stack_rect: geometry.Rectangle,
    cursor: uilayout.Stack_Panel_Cursor,
    rows: Settings_View_Rows,
    row_gap: f32,
    heading_height: f32,
    slider_height: f32,
    action_height: f32,
    action_status_gap: f32,
    system_motion_notice: bool,
    system_contrast_notice: bool,
}

//   Fixed prepared interaction results for all settings controls.
Settings_View_Preparation :: struct {
    rows: Settings_View_Rows,
    text_size_percent: int,
    control_size_percent: int,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    max_particles: uiwidgets.Integer_Slider_Result,
    animation_scale: uiwidgets.Integer_Slider_Result,
    control_size: uiwidgets.Integer_Slider_Result,
    text_size: uiwidgets.Integer_Slider_Result,
    fps: uiwidgets.Checkbox_Result,
    limit: uiwidgets.Checkbox_Result,
    sound: uiwidgets.Checkbox_Result,
    simd: uiwidgets.Checkbox_Result,
    gpu_dust: uiwidgets.Checkbox_Result,
    reduce_motion: uiwidgets.Checkbox_Result,
    enable_particle_effects: uiwidgets.Checkbox_Result,
    open_completed: uiwidgets.Checkbox_Result,
    increased_contrast: uiwidgets.Checkbox_Result,
    hover_focus: uiwidgets.Checkbox_Result,
    show_magnifier: uiwidgets.Checkbox_Result,
    magnifier_input_lock: uiwidgets.Checkbox_Result,
    persist_history: uiwidgets.Checkbox_Result,
    monochrome: uiwidgets.Checkbox_Result,
    delete_history: uiwidgets.Text_Button_Result,
    history_delete_status: viewmodel.Ui_History_Delete_Status,
    history_delete_armed: bool,
    simd_available: bool,
    gpu_available: bool,
}

//   Values unique to one checkbox row in the settings panel.
Settings_Checkbox_Descriptor :: struct {
    row_y: f32,
    id: int,
    label: string,
    checked: bool,
    enabled: bool,
    order: u32,
}

//   Prepared controls paired with platform feature availability.
Settings_Control_Update :: struct {
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool,
}

// Settings_Text_Context shares display and font facts across Settings labels.
Settings_Text_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
    stats_y: f32,
    encoder: ^native.Draw_Encoder,
    text_size_percent: int,
    control_size_percent: int,
}

// Offer the control-size explanation through the shared accessible tooltip path.
settings_offer_control_size_tooltip :: proc(
    ctx: Settings_View_Context,
    prepared: uiwidgets.Integer_Slider_Result, interactive: bool) {
    if !interactive {
        return
    }
    owner := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_CONTROL_SIZE_SLIDER_ID)
    source := uioverlay.tooltip_control_source(
        &ctx.state^.ui_runtime.input, ctx.semantic_focus,
        owner, SETTINGS_CONTROL_SIZE_SLIDER_ID)
    mouse: geometry.Vector2 = {
        ctx.mouse_input.mouse_position.x,
        ctx.mouse_input.mouse_position.y,
    }
    press_active := ctx.press_owner != nil && ctx.press_owner^.active
    if source == .None && !press_active &&
        geometry.rectangle_contains(ctx.panel, mouse) &&
        geometry.rectangle_contains(prepared.control_geometry.bounds, mouse) {
        source = .Pointer
    }
    uioverlay.tooltip_offer(&ctx.state^.ui_runtime.tooltip, {
        owner = owner,
        source = source,
        anchor = prepared.control_geometry.bounds,
        prefer_above = true,
        text = ctx.labels.control_size_tooltip,
    })
}

// Offer pointer-magnifier help through the shared accessible tooltip path.
settings_offer_magnifier_tooltip :: proc(
    ctx: Settings_View_Context,
    prepared: uiwidgets.Checkbox_Result,
    interactive: bool) {
    if !interactive {
        return
    }
    owner := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_SHOW_MAGNIFIER_CHECKBOX_ID)
    source := uioverlay.tooltip_control_source(
        &ctx.state^.ui_runtime.input, ctx.semantic_focus,
        owner, SETTINGS_SHOW_MAGNIFIER_CHECKBOX_ID)
    mouse: geometry.Vector2 = {
        ctx.mouse_input.mouse_position.x,
        ctx.mouse_input.mouse_position.y,
    }
    press_active := ctx.press_owner != nil && ctx.press_owner^.active
    if source == .None && !press_active &&
        geometry.rectangle_contains(ctx.panel, mouse) &&
        geometry.rectangle_contains(prepared.control_geometry.bounds, mouse) {
        source = .Pointer
    }
    if prepared.toggled {
        uioverlay.tooltip_dismiss(&ctx.state^.ui_runtime.tooltip, owner)
    }
    uioverlay.tooltip_offer(&ctx.state^.ui_runtime.tooltip, {
        owner = owner,
        source = source,
        anchor = prepared.control_geometry.bounds,
        prefer_above = true,
        text = ctx.labels.show_magnifier_tooltip,
    })
}

// Offer caret-lock help through the shared accessible tooltip path.
settings_offer_magnifier_input_lock_tooltip :: proc(
    ctx: Settings_View_Context,
    prepared: uiwidgets.Checkbox_Result,
    interactive: bool) {
    if !interactive {
        return
    }
    owner := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_MAGNIFIER_INPUT_LOCK_CHECKBOX_ID)
    source := uioverlay.tooltip_control_source(
        &ctx.state^.ui_runtime.input, ctx.semantic_focus,
        owner, SETTINGS_MAGNIFIER_INPUT_LOCK_CHECKBOX_ID)
    mouse: geometry.Vector2 = {
        ctx.mouse_input.mouse_position.x,
        ctx.mouse_input.mouse_position.y,
    }
    press_active := ctx.press_owner != nil && ctx.press_owner^.active
    if source == .None && !press_active &&
        geometry.rectangle_contains(ctx.panel, mouse) &&
        geometry.rectangle_contains(prepared.control_geometry.bounds, mouse) {
        source = .Pointer
    }
    if prepared.toggled {
        uioverlay.tooltip_dismiss(&ctx.state^.ui_runtime.tooltip, owner)
    }
    uioverlay.tooltip_offer(&ctx.state^.ui_runtime.tooltip, {
        owner = owner,
        source = source,
        anchor = prepared.control_geometry.bounds,
        prefer_above = true,
        text = ctx.labels.magnifier_input_lock_tooltip,
    })
}

// settings_cancel_geometry_capture releases transient panel drags after layout changes.
settings_cancel_geometry_capture :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State) {
    panel^.scroll_dragging = false
    panel^.scroll_drag_off = 0
    panel^.slider_dragging = false
    panel^.slider_drag_offset_x = 0
}

// Cancel destructive intent when the Settings surface stops being current.
settings_cancel_history_confirmation :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State) {
    if panel == nil || panel^.history_delete_status != .Armed {
        return
    }
    panel^.history_delete_status = .Idle
    panel^.history_delete_armed_at_seconds = 0
}

// settings_view_context snapshots the application facts needed by leaf preparation.
settings_view_context :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame) -> Settings_View_Context {
    preferences := state^.ui_runtime.preferences.values
    simd_available := projection.simd_batch_projection_available()
    gpu_available := state^.ui_runtime.rendering.gpu_dust_instancing_available
    labels := settings_view_labels(state, simd_available, gpu_available)
    return Settings_View_Context{
        state = state,
        panel = panel,
        mouse_input = mouse_input,
        settings_panel = &state^.ui_runtime.settings_panel,
        press_owner = &state^.ui_runtime.input.press_owner,
        semantic_focus = state^.ui_runtime.semantic_focus,
        preferences = preferences,
        particle_system = &state^.particle_system,
        gpu_dust_available = gpu_available,
        platform_reduce_motion = state^.ui_runtime.platform_reduce_motion,
        platform_increased_contrast = state^.ui_runtime.platform_increased_contrast,
        simd_available = simd_available,
        labels = labels,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
    }
}

// Snapshot history labels into the shared Settings label record.
settings_history_labels :: proc(
    state: ^core.Euclid_General_State, labels: ^Settings_View_Labels) {
    labels^.persist_history =
        viewmessages.shell_message(state, .Settings_Persist_Terminal_History)
    labels^.delete_history =
        viewmessages.shell_message(state, .Settings_Delete_Terminal_History)
    labels^.confirm_delete_history =
        viewmessages.shell_message(state, .Settings_Confirm_Delete_Terminal_History)
    labels^.confirm_delete_history_value =
        viewmessages.shell_message(state, .Settings_History_Delete_Confirm_Value)
    labels^.history_delete_pending =
        viewmessages.shell_message(state, .Settings_History_Delete_Pending)
    labels^.history_delete_succeeded =
        viewmessages.shell_message(state, .Settings_History_Delete_Succeeded)
    labels^.history_delete_failed =
        viewmessages.shell_message(state, .Settings_History_Delete_Failed)
}

// Snapshot localized Settings labels before leaf-control preparation.
settings_view_labels :: proc(
    state: ^core.Euclid_General_State,
    simd_available, gpu_available: bool) -> Settings_View_Labels {
    labels: Settings_View_Labels
    settings_history_labels(state, &labels)
    labels.maximum_dust = viewmessages.shell_message(state, .Settings_Maximum_Dust)
    labels.display_fps = viewmessages.shell_message(state, .Settings_Display_Fps)
    labels.limit_fps = viewmessages.shell_message(state, .Settings_Limit_Fps)
    labels.drawing_sound = viewmessages.shell_message(state, .Settings_Drawing_Sound)
    labels.simd = settings_simd_label(state, simd_available)
    labels.gpu_dust = settings_gpu_dust_label(state, gpu_available)
    settings_accessibility_labels(state, &labels)
    labels.control_size = viewmessages.shell_message(state, .Settings_Control_Size)
    labels.control_size_tooltip =
        viewmessages.shell_message(state, .Settings_Control_Size_Tooltip)
    labels.text_size = viewmessages.shell_message(state, .Settings_Text_Size)
    labels.animation_scale =
        viewmessages.shell_message(state, .Settings_Animation_Scale)
    labels.animation_scale_tooltip =
        viewmessages.shell_message(state, .Settings_Animation_Scale_Tooltip)
    labels.monochrome = viewmessages.shell_message(state, .Settings_Monochrome)
    return labels
}

// Snapshot localized motion, contrast, and pointer accessibility labels and help.
settings_accessibility_labels :: proc(
    state: ^core.Euclid_General_State, labels: ^Settings_View_Labels) {
    labels.reduce_motion = viewmessages.shell_message(state, .Settings_Reduce_Motion)
    labels.enable_particle_effects =
        viewmessages.shell_message(state, .Settings_Enable_Particle_Effects)
    labels.open_completed = viewmessages.shell_message(state, .Settings_Open_Completed)
    labels.particle_effects_help =
        viewmessages.shell_message(state, .Settings_Particle_Effects_Help)
    labels.open_completed_help =
        viewmessages.shell_message(state, .Settings_Open_Completed_Help)
    labels.increased_contrast =
        viewmessages.shell_message(state, .Settings_Increased_Contrast)
    labels.hover_focus = viewmessages.shell_message(state, .Settings_Hover_Focus)
    labels.hover_focus_tooltip =
        viewmessages.shell_message(state, .Settings_Hover_Focus_Tooltip)
    labels.show_magnifier =
        viewmessages.shell_message(state, .Settings_Show_Magnifier)
    labels.show_magnifier_tooltip =
        viewmessages.shell_message(state, .Settings_Show_Magnifier_Tooltip)
    labels.magnifier_input_lock =
        viewmessages.shell_message(state, .Settings_Magnifier_Input_Lock)
    labels.magnifier_input_lock_tooltip =
        viewmessages.shell_message(state, .Settings_Magnifier_Input_Lock_Tooltip)
}

// Center the destructive label inside the prepared panel button, including its shake.
draw_encoded_settings_history_button_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Settings_View_Preparation) {
    rectangle := prepared.delete_history.control_geometry.bounds
    label := viewmessages.shell_message(state, .Settings_Delete_Terminal_History)
    tint := theme.draw_color(encoder, .Text)
    if prepared.history_delete_armed {
        label = viewmessages.shell_message(
            state, .Settings_Confirm_Delete_Terminal_History)
        tint = theme.draw_color(encoder, .Error_Text)
    }
    if prepared.history_delete_status == .Pending {
        tint = theme.draw_color(encoder, .Disabled_Text)
    }
    font_size := theme.ui_font_size(encoder^.ui_text_size_percent)
    width, measured := viewtext.ui_text_measure_monospace(
        label, view_font.cache_borrow(&state^.font_cache, .Regular), font_size, 0)
    if !measured {
        width = 0
    }
    viewtext.draw_encoded_colored_label(&state^.font_cache, encoder, label,
        {rectangle.x + max(f32(0), (rectangle.width - width) * 0.5),
         rectangle.y + (rectangle.height - font_size) * 0.5}, tint)
}

// Draw the confirmation label and truthful asynchronous status beneath its button.
draw_encoded_settings_history_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Settings_View_Preparation) {
    rectangle := prepared.delete_history.control_geometry.bounds
    draw_encoded_settings_history_button_text(state, encoder, prepared)
    message := settings_history_delete_status_message(
        prepared.history_delete_status)
    if message != .Invalid {
        color := theme.draw_color(encoder, .Text)
        if prepared.history_delete_status == .Failed {
            color = theme.draw_color(encoder, .Error_Text)
        }
        viewtext.draw_encoded_colored_label(&state^.font_cache, encoder,
            viewmessages.shell_message(state, message),
            {rectangle.x,
             prepared.rows.history_delete_status_y}, color)
    }
}

// draw_encoded_checkbox_geometry encodes one checkbox without its deferred label.
draw_encoded_checkbox_geometry :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle, checked: bool,
    scale := f32(1)) {
    uiwidgets.draw_encoded_checkbox_geometry(encoder, rectangle, checked, scale)
}

// draw_encoded_slider_geometry encodes one slider track, fill, and knob.
draw_encoded_slider_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: uiwidgets.Integer_Slider_Result) {
    scale := prepared.track.height / theme.SETTINGS_TRACK_HEIGHT
    knob_center_x := prepared.knob.x + prepared.knob.width * 0.5
    _ = native.draw_encoder_rectangle(
        encoder, prepared.track, worldmodel.BACKGROUND_COLOR)
    fill: geometry.Rectangle = {prepared.track.x, prepared.track.y,
        max(0, knob_center_x - prepared.track.x), prepared.track.height}
    _ = native.draw_encoder_rectangle(
        encoder, fill, theme.draw_color(encoder, .Control_Border))
    _ = native.draw_encoder_rectangle(
        encoder, prepared.knob, theme.draw_color(encoder, .Text))
    _ = native.draw_encoder_rectangle_outline(
        encoder, prepared.track, scale, theme.draw_color(encoder, .Control_Border))
    _ = native.draw_encoder_rectangle_outline(
        encoder, prepared.knob, scale, theme.UI_SELECTION_TEXT_COLOR)
}

// Draw every checkbox in one prepared Settings layout.
draw_encoded_settings_checkboxes :: proc(
    encoder: ^native.Draw_Encoder, prepared: Settings_View_Preparation) {
    checks: [14]uiwidgets.Checkbox_Result = {
        prepared.enable_particle_effects, prepared.open_completed,
        prepared.reduce_motion, prepared.increased_contrast, prepared.hover_focus,
        prepared.show_magnifier, prepared.magnifier_input_lock,
        prepared.monochrome, prepared.gpu_dust,
        prepared.fps, prepared.limit, prepared.sound, prepared.simd,
        prepared.persist_history,
    }
    for check in checks {
        draw_encoded_checkbox_geometry(
            encoder, check.box_rect, check.checked_out,
            theme.ui_effective_control_scale(
                prepared.text_size_percent, prepared.control_size_percent))
    }
}

// Keep the full destructive button visible before and during confirmation.
draw_encoded_settings_history_button_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: Settings_View_Preparation) {
    button := prepared.delete_history.control_geometry.bounds
    border := theme.draw_color(encoder, .Control_Border)
    if prepared.history_delete_armed {
        border = theme.draw_color(encoder, .Error_Text)
    }
    _ = native.draw_encoder_rectangle(
        encoder, button, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, button,
        theme.ui_control_size_scale(prepared.control_size_percent), border)
}

// draw_encoded_settings_geometry encodes settings controls without text.
draw_encoded_settings_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: Settings_View_Preparation) {
    draw_encoded_slider_geometry(encoder, prepared.max_particles)
    draw_encoded_slider_geometry(encoder, prepared.control_size)
    draw_encoded_slider_geometry(encoder, prepared.animation_scale)
    draw_encoded_slider_geometry(encoder, prepared.text_size)
    draw_encoded_settings_checkboxes(encoder, prepared)
    draw_encoded_settings_history_button_geometry(encoder, prepared)
    uiwidgets.draw_encoded_scrollbar(encoder, prepared.scroll.scrollbar)
}

// Draw labels attached to the prepared settings checkboxes.
draw_encoded_settings_check_labels :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    x: f32, rows: Settings_View_Rows, prepared: Settings_View_Preparation) {
    labels: [14]struct{label: string, y: f32} = {
        {viewmessages.shell_message(state, .Settings_Enable_Particle_Effects),
            rows.enable_particle_effects_y},
        {viewmessages.shell_message(state, .Settings_Open_Completed),
            rows.open_completed_y},
        {viewmessages.shell_message(state, .Settings_Reduce_Motion),
            rows.reduce_motion_y},
        {viewmessages.shell_message(state, .Settings_Increased_Contrast),
            rows.increased_contrast_y},
        {viewmessages.shell_message(state, .Settings_Hover_Focus),
            rows.hover_focus_y},
        {viewmessages.shell_message(state, .Settings_Show_Magnifier),
            rows.show_magnifier_y},
        {viewmessages.shell_message(state, .Settings_Magnifier_Input_Lock),
            rows.magnifier_input_lock_y},
        {viewmessages.shell_message(state, .Settings_Monochrome),
            rows.monochrome_y},
        {viewmessages.shell_message(state, .Settings_Persist_Terminal_History),
            rows.persist_history_y},
        {settings_gpu_dust_label(state, prepared.gpu_available),
            rows.gpu_dust_y},
        {viewmessages.shell_message(state, .Settings_Display_Fps), rows.fps_y},
        {viewmessages.shell_message(state, .Settings_Limit_Fps), rows.limit_y},
        {viewmessages.shell_message(state, .Settings_Drawing_Sound), rows.sound_y},
        {settings_simd_label(state, prepared.simd_available), rows.simd_y},
    }
    for item in labels {
        viewtext.draw_encoded_label(&state^.font_cache, encoder, item.label,
            x + theme.SETTINGS_CHECKBOX_SIZE + theme.SETTINGS_CHECKBOX_LABEL_GAP,
            item.y - theme.SETTINGS_CHECKBOX_TEXT_OFFSET_Y)
    }
    if state^.ui_runtime.platform_reduce_motion {
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            viewmessages.shell_message(state, .Settings_System_Reduce_Motion),
            x, rows.system_motion_y)
    }
    if state^.ui_runtime.platform_increased_contrast {
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            viewmessages.shell_message(state, .Settings_System_Increased_Contrast),
            x, rows.system_contrast_y)
    }
}

// Draw all current Settings labels, values, and counters.
draw_encoded_settings_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Settings_View_Preparation) {
    panel := prepared.scroll.view_rect
    rows := prepared.rows
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    control_percent := state^.ui_runtime.preferences.values.interface.control_size_percent
    x := panel.x + theme.ui_control_size_metric(
        theme.SETTINGS_PANEL_INSET, control_percent)
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    text_ctx: Settings_Text_Context = {
        state = state,
        panel = panel,
        font = face,
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        stats_y = rows.stats_y,
        encoder = encoder,
        text_size_percent = text_percent,
        control_size_percent = control_percent,
    }
    draw_encoded_settings_slider_labels(text_ctx, rows)
    draw_encoded_settings_section_headings(state, encoder, x, rows)
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Settings_Control_Size),
        x, rows.control_size_y)
    draw_encoded_settings_control_size_value(text_ctx, rows.control_size_y)
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Settings_Text_Size),
        x, rows.text_size_y)
    draw_encoded_settings_size_value(text_ctx, rows.text_size_y)
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Settings_Animation_Scale),
        x, rows.animation_scale_y)
    draw_encoded_settings_animation_scale_value(text_ctx, rows.animation_scale_y)
    draw_settings_particle_stats(text_ctx)
    draw_settings_animation_count(text_ctx, rows.animation_entries_y)
    draw_encoded_settings_check_labels(state, encoder, x, rows, prepared)
    draw_encoded_settings_history_controls(state, encoder, prepared)
    draw_encoded_settings_save_status(state, encoder, x, rows.save_status_y)
}

// Draw the four section headings using the prepared Settings row positions.
draw_encoded_settings_section_headings :: proc(
    state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder,
    x: f32,
    rows: Settings_View_Rows) {
    draw_encoded_settings_section_heading(state, encoder,
        .Settings_Section_Accessibility, x, rows.accessibility_header_y)
    draw_encoded_settings_section_heading(state, encoder,
        .Settings_Section_History, x, rows.history_header_y)
    draw_encoded_settings_section_heading(state, encoder,
        .Settings_Section_Particles, x, rows.particles_header_y)
    draw_encoded_settings_section_heading(state, encoder,
        .Settings_Section_Other, x, rows.other_header_y)
}

// Show the chosen control-size scale without implying a font-size change.
draw_encoded_settings_control_size_value :: proc(
    ctx: Settings_Text_Context, row_y: f32) {
    value := fmt.tprintf("%d%%",
        ctx.state^.ui_runtime.preferences.values.interface.control_size_percent)
    value_width, measured := viewtext.ui_text_measure_monospace(
        value, ctx.font, theme.ui_font_size(ctx.text_size_percent), 0)
    if !measured {
        value_width = 48
    }
    viewtext.draw_encoded_label(&ctx.state^.font_cache, ctx.encoder, value,
        settings_right_aligned_x(
            ctx.panel, value_width, ctx.control_size_percent), row_y)
}

// Show the selected animation multiplier, identifying its unmodified default.
draw_encoded_settings_animation_scale_value :: proc(
    ctx: Settings_Text_Context, row_y: f32) {
    scale_percent := ctx.state^.ui_runtime.preferences.values.animation.scale_percent
    value := fmt.tprintf("%d%%", scale_percent)
    if scale_percent == 100 {
        value = viewmessages.shell_message(
            ctx.state, .Settings_Animation_Scale_Default)
    }
    value_width, measured := viewtext.ui_text_measure_monospace(
        value, ctx.font, theme.ui_font_size(ctx.text_size_percent), 0)
    if !measured {
        value_width = 80
    }
    viewtext.draw_encoded_label(&ctx.state^.font_cache, ctx.encoder, value,
        settings_right_aligned_x(
            ctx.panel, value_width, ctx.control_size_percent), row_y)
}

// Draw the labels and right-aligned values associated with both Settings sliders.
draw_encoded_settings_slider_labels :: proc(
    ctx: Settings_Text_Context, rows: Settings_View_Rows) {
    state := ctx.state
    font_size := theme.ui_font_size(ctx.text_size_percent)
    dust_value := fmt.tprintf("%d", state^.particle_system.use_max_dust_particles)
    dust_width, dust_measured := viewtext.ui_text_measure_monospace(
        dust_value, ctx.font, font_size, 0)
    if !dust_measured {
        dust_width = 40
    }
    viewtext.draw_encoded_label(&state^.font_cache, ctx.encoder,
        viewmessages.shell_message(state, .Settings_Maximum_Dust),
        ctx.panel.x + theme.ui_control_size_metric(
            theme.SETTINGS_PANEL_INSET, ctx.control_size_percent),
        rows.slider_label_y)
    viewtext.draw_encoded_label(&state^.font_cache, ctx.encoder, dust_value,
        settings_right_aligned_x(
            ctx.panel, dust_width, ctx.control_size_percent), rows.slider_label_y)
}

// Draw the selected percentage beside the text-size slider label.
draw_encoded_settings_size_value :: proc(
    ctx: Settings_Text_Context, row_y: f32) {
    value := fmt.tprintf("%d%%", ctx.text_size_percent)
    value_width, measured := viewtext.ui_text_measure_monospace(
        value, ctx.font, theme.ui_font_size(ctx.text_size_percent), 0)
    if !measured {
        value_width = 40
    }
    viewtext.draw_encoded_label(&ctx.state^.font_cache, ctx.encoder, value,
        settings_right_aligned_x(
            ctx.panel, value_width, ctx.control_size_percent), row_y)
}

// Draw the current Julia animation count as the first Other Settings row.
draw_settings_animation_count :: proc(
    ctx: Settings_Text_Context, row_y: f32) {
    count := 0
    if ctx.state^.julia_interface != nil {
        count = ctx.state^.julia_interface^.animation_count
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    label := viewmessages.shell_format(ctx.state,
        .Settings_Stats_Animation_Entries,
        []contentdata.Content_Format_Argument{{"count", i64(count)}},
        storage[:])
    stats_context := ctx
    stats_context.stats_y = row_y
    draw_settings_stat_row(stats_context, label, 0)
}

// Draw one localized Settings section heading.
draw_encoded_settings_section_heading :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    id: contentdata.Content_Message_Id, x, y: f32) {
    face := view_font.cache_borrow(&state^.font_cache, .Bold)
    _ = viewtext.ui_text_shaped({
        encoder = encoder,
        resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        key = .Bold,
        text = viewmessages.shell_message(state, id),
        position = {x, y},
        color = theme.draw_color(encoder, .Text),
        font = viewtext.ui_text_font(
            face, encoder^.ui_text_size_percent),
    })
}

// Resolve and draw the localized persistence state beneath the setting controls.
draw_encoded_settings_save_status :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    x, y: f32) {
    message := contentdata.Content_Message_Id.Settings_Save_Saved
    switch state^.ui_runtime.preferences.save_status {
    case .Saved:
        message = .Settings_Save_Saved
    case .Pending:
        message = .Settings_Save_Pending
    case .Saving:
        message = .Settings_Save_Saving
    case .Unavailable:
        message = .Settings_Save_Unavailable
    case .Failed:
        message = .Settings_Save_Failed
    }
    viewtext.draw_encoded_label(
        &state^.font_cache, encoder, viewmessages.shell_message(state, message), x, y)
}

// settings_simd_label describes whether SIMD projection can be selected.
settings_simd_label :: proc(
    state: ^core.Euclid_General_State, available: bool) -> string {
    if available {
        return viewmessages.shell_message(state, .Settings_Simd_Available)
    }
    return viewmessages.shell_message(state, .Settings_Simd_Unavailable)
}

// settings_gpu_dust_label describes whether GPU dust can be selected.
settings_gpu_dust_label :: proc(
    state: ^core.Euclid_General_State, available: bool) -> string {
    if available {
        return viewmessages.shell_message(state, .Settings_Gpu_Dust_Available)
    }
    return viewmessages.shell_message(state, .Settings_Gpu_Dust_Unavailable)
}

// settings_right_aligned_x keeps one measured value inside the panel inset.
settings_right_aligned_x :: #force_inline proc(
    panel: geometry.Rectangle, text_width: f32,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> f32 {
    inset := theme.ui_control_size_metric(
        theme.SETTINGS_PANEL_INSET, control_size_percent)
    return panel.x + panel.width - inset - max(text_width, 0)
}

//   Build one settings checkbox parameter record from shared row context.
settings_checkbox_params :: proc(
    ctx: Settings_View_Context,
    descriptor: Settings_Checkbox_Descriptor) -> uiwidgets.Checkbox_Params {
    scale := theme.ui_effective_control_scale(
        ctx.preferences.interface.text_size_percent,
        ctx.preferences.interface.control_size_percent)
    box_side := theme.SETTINGS_CHECKBOX_SIZE * scale
    row_rect: geometry.Rectangle = {
        ctx.panel.x,
        descriptor.row_y,
        ctx.panel.width,
        max(box_side, theme.ui_font_size(
            ctx.preferences.interface.text_size_percent)),
    }
    semantic_domain := viewmodel.Ui_Node_Domain.None
    if geometry.rectangles_intersect(row_rect, geometry.Rectangle(ctx.panel)) {
        semantic_domain = .Settings_Control
    }
    return {
        id = descriptor.id,
        rect = geometry.Rectangle{
            ctx.panel.x + theme.ui_control_size_metric(
                theme.SETTINGS_PANEL_INSET,
                ctx.preferences.interface.control_size_percent), descriptor.row_y,
            box_side,
            box_side,},
        checked = descriptor.checked,
        enabled = descriptor.enabled,
        mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = true,
        label = descriptor.label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = theme.ui_font_size(
            ctx.preferences.interface.text_size_percent),
        label_offset_x = theme.ui_control_scaled_metric(
            theme.SETTINGS_CHECKBOX_LABEL_GAP,
            ctx.preferences.interface.text_size_percent,
            ctx.preferences.interface.control_size_percent),
        label_offset_y = -theme.ui_control_scaled_metric(
            theme.SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
            ctx.preferences.interface.text_size_percent,
            ctx.preferences.interface.control_size_percent),
        semantic_focus = ctx.semantic_focus,
        semantic_domain = semantic_domain,
        semantic_order = descriptor.order,
        semantic_clip = ctx.panel,
    }
}

// Prepare a Settings slider only while its hit area intersects the visible panel.
settings_prepare_integer_slider :: proc(
    ctx: Settings_View_Context,
    params: uiwidgets.Integer_Slider_Params,
    interactive: bool) -> uiwidgets.Integer_Slider_Result {
    slider_params := params
    track := uiwidgets.slider_track_rect(
        slider_params.panel, slider_params.row_y,
        slider_params.text_size_percent, slider_params.control_size_percent)
    scale := theme.ui_control_size_scale(slider_params.control_size_percent)
    hit := uiwidgets.slider_hit_rect(track, scale)
    visible := geometry.rectangles_intersect(hit, geometry.Rectangle(ctx.panel))
    if !visible {
        owner := ctx.press_owner
        if owner^.active && owner^.kind == .Slider &&
            owner^.id == slider_params.press_id {
            owner^.active = false
            owner^.kind = .None
            owner^.id = -1
        }
        slider_params.semantic_domain = .None
        return uiwidgets.prepare_integer_slider(slider_params, false)
    }
    owns_press := ctx.press_owner^.active &&
        ctx.press_owner^.kind == .Slider &&
        ctx.press_owner^.id == slider_params.press_id
    if !owns_press && !geometry.rectangle_contains(
        ctx.panel, {slider_params.mouse_input.mouse_position.x,
            slider_params.mouse_input.mouse_position.y}) {
        slider_params.mouse_input.mouse_position = {-1, -1}
    }
    return uiwidgets.prepare_integer_slider(slider_params, interactive)
}

// Build the focusable deletion action with explicit armed state and bounded motion.
settings_history_delete_button_rect :: proc(
    ctx: Settings_View_Context,
    rows: Settings_View_Rows,
    armed: bool) -> geometry.Rectangle {
    panel_state := ctx.settings_panel
    rectangle: geometry.Rectangle = {
        ctx.panel.x + theme.ui_control_size_metric(
            theme.SETTINGS_PANEL_INSET,
            ctx.preferences.interface.control_size_percent),
        rows.delete_history_y,
        max(f32(0), ctx.panel.width -
            2*theme.ui_control_size_metric(
                theme.SETTINGS_PANEL_INSET,
                ctx.preferences.interface.control_size_percent)),
        theme.ui_panel_button_height(
            ctx.preferences.interface.text_size_percent,
            ctx.preferences.interface.control_size_percent),
    }
    if armed {
        rectangle.x += settings_history_delete_shake_offset(
            panel_state, ctx.mouse_input.sample_time_seconds,
            ctx.preferences.interface.reduce_motion ||
                ctx.platform_reduce_motion)
    }
    return rectangle
}

// Build the focusable deletion action with explicit armed state and bounded motion.
settings_history_delete_button_params :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows) ->
        uiwidgets.Text_Button_Params {
    panel_state := ctx.settings_panel
    armed := panel_state^.history_delete_status == .Armed
    pending := panel_state^.history_delete_status == .Pending
    label := ctx.labels.delete_history
    value := ""
    states := uiwidgets.button_semantic_states(!pending)
    if armed {
        label = ctx.labels.confirm_delete_history
        value = ctx.labels.confirm_delete_history_value
        states += {.Selected}
    }
    if pending {
        states += {.Busy}
    }
    rectangle := settings_history_delete_button_rect(ctx, rows, armed)
    semantic_id := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_HISTORY_DELETE_BUTTON_ID)
    return {
        id = SETTINGS_HISTORY_DELETE_BUTTON_ID,
        rect = rectangle,
        label = label,
        enabled = !pending,
        mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = !panel_state^.scroll_dragging,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantics = {
            publish = true,
            focus = ctx.semantic_focus,
            id = semantic_id,
            role = .Button,
            states = states,
            region = .Accordion_Content,
            traversal_order = 10,
            clip_bounds = geometry.Rectangle(ctx.panel),
            label = label,
            value = value,
        },
    }
}

// Shake an armed delete action briefly unless the user requested reduced motion.
settings_history_delete_shake_offset :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State, now: f64,
    reduce_motion: bool) -> f32 {
    elapsed := now - panel^.history_delete_armed_at_seconds
    if reduce_motion || elapsed < 0 ||
       elapsed >= SETTINGS_HISTORY_DELETE_SHAKE_SECONDS {
        return 0
    }
    progress := elapsed / SETTINGS_HISTORY_DELETE_SHAKE_SECONDS
    return f32(math.sin(progress * 6 * math.PI) * 5 * (1 - progress))
}

// Publish deletion status as a non-focusable live semantic node.
settings_publish_history_delete_status :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows) {
    message := settings_history_delete_status_message(
        ctx.settings_panel^.history_delete_status)
    if message == .Invalid {
        return
    }
    states: viewmodel.Ui_Node_State = {.Visible}
    if ctx.settings_panel^.history_delete_status == .Pending {
        states += {.Busy}
    }
    font_size := theme.ui_font_size(
        ctx.preferences.interface.text_size_percent)
    _ = uisemantics.semantic_register_control(ctx.semantic_focus, {
        id = uisemantics.semantic_control_id(
            .Settings_Control, SETTINGS_HISTORY_DELETE_STATUS_ID),
        role = .Status,
        states = states,
        region = .Accordion_Content,
        traversal_order = 11,
        bounds = {
            ctx.panel.x + theme.SETTINGS_PANEL_INSET,
            rows.history_delete_status_y,
            max(f32(0), ctx.panel.width - 2*theme.SETTINGS_PANEL_INSET),
            font_size,
        },
        clip_bounds = geometry.Rectangle(ctx.panel),
        label = viewmessages.shell_message(ctx.state, message),
    })
}

// Resolve one localized status for the deletion lifecycle.
settings_history_delete_status_message :: proc(
    status: viewmodel.Ui_History_Delete_Status) -> contentdata.Content_Message_Id {
    switch status {
    case .Pending:
        return .Settings_History_Delete_Pending
    case .Cleared:
        return .Settings_History_Delete_Succeeded
    case .Failed:
        return .Settings_History_Delete_Failed
    case .Idle, .Armed:
        return .Invalid
    }
    return .Invalid
}

// Arm the first activation or enqueue the confirmed transaction on the history owner.
settings_history_delete_activate :: proc(
    state: ^core.Euclid_General_State, now: f64) {
    if state == nil {
        return
    }
    panel := &state^.ui_runtime.settings_panel
    elapsed := now - panel^.history_delete_armed_at_seconds
    if panel^.history_delete_status != .Armed || elapsed < 0 ||
       elapsed >= SETTINGS_HISTORY_DELETE_TIMEOUT_SECONDS {
        panel^.history_delete_status = .Armed
        panel^.history_delete_armed_at_seconds = now
        return
    }
    panel^.history_delete_status = .Idle
    panel^.history_delete_armed_at_seconds = 0
    enqueue_result: historyruntime.History_Runtime_Enqueue_Result =
        terminalview.history_runtime_enqueue_clear(
            &state^.terminal_history_runtime)
    if enqueue_result == .Queued {
        panel^.history_delete_status = .Pending
        panel^.history_delete_completion_serial =
            state^.terminal_history_runtime.clear_completion_serial
        return
    }
    panel^.history_delete_status = .Failed
    log.warnf("terminal_history_clear_rejected reason=%d", int(enqueue_result))
}

// Expire confirmation when its clock moves backward or its bounded window elapses.
settings_history_delete_expire :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State, now: f64) {
    if panel == nil || panel^.history_delete_status != .Armed {
        return
    }
    elapsed := now - panel^.history_delete_armed_at_seconds
    if elapsed < 0 || elapsed >= SETTINGS_HISTORY_DELETE_TIMEOUT_SECONDS {
        settings_cancel_history_confirmation(panel)
    }
}

// Publish only a completed clear result newer than the pending request.
settings_history_delete_observe_completion :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State,
    completion_serial: u64, cleared: bool) -> bool {
    if panel == nil || panel^.history_delete_status != .Pending ||
       completion_serial == panel^.history_delete_completion_serial {
        return false
    }
    panel^.history_delete_completion_serial = completion_serial
    panel^.history_delete_status =
        viewmodel.Ui_History_Delete_Status.Cleared if cleared else .Failed
    return cleared
}

//   Build the maximum-particle slider parameters shared by update and draw.
settings_max_particles_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        press_owner = ctx.press_owner,
        semantic_focus = ctx.semantic_focus,
        press_id = SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        label = ctx.labels.maximum_dust,
        value = ctx.particle_system^.use_max_dust_particles,
        min_value = 0,
        max_value = particlemodel.MAX_LOW_PARTICLES,
        text_size_percent = ctx.preferences.interface.text_size_percent,
        control_size_percent = ctx.preferences.interface.control_size_percent,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 11,
    }
}

// Build the saved animation-scale slider parameters.
settings_animation_scale_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        press_owner = ctx.press_owner,
        semantic_focus = ctx.semantic_focus,
        press_id = SETTINGS_ANIMATION_SCALE_SLIDER_ID,
        label = ctx.labels.animation_scale,
        value = ctx.preferences.animation.scale_percent,
        min_value = 50,
        max_value = 200,
        step = 5,
        value_suffix = "%",
        text_size_percent = ctx.preferences.interface.text_size_percent,
        control_size_percent = ctx.preferences.interface.control_size_percent,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 9,
    }
}

// Build the bounded interface control-size slider parameters.
settings_control_size_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        press_owner = ctx.press_owner,
        semantic_focus = ctx.semantic_focus,
        press_id = SETTINGS_CONTROL_SIZE_SLIDER_ID,
        label = ctx.labels.control_size,
        value = ctx.preferences.interface.control_size_percent,
        min_value = theme.CONTROL_SIZE_MIN_PERCENT,
        max_value = theme.CONTROL_SIZE_MAX_PERCENT,
        step = theme.CONTROL_SIZE_STEP_PERCENT,
        value_suffix = "%",
        text_size_percent = ctx.preferences.interface.text_size_percent,
        control_size_percent = ctx.preferences.interface.control_size_percent,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 7,
    }
}

// Build the app-owned discrete text-size slider parameters.
settings_text_size_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        press_owner = ctx.press_owner,
        semantic_focus = ctx.semantic_focus,
        press_id = 6103,
        label = ctx.labels.text_size,
        value = ctx.preferences.interface.text_size_percent,
        min_value = theme.TEXT_SIZE_MIN_PERCENT,
        max_value = theme.TEXT_SIZE_MAX_PERCENT,
        step = theme.TEXT_SIZE_STEP_PERCENT,
        value_suffix = "%",
        text_size_percent = ctx.preferences.interface.text_size_percent,
        control_size_percent = ctx.preferences.interface.control_size_percent,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 8,
    }
}

// Draw particle counters and interval text within the Particles section.
draw_settings_particle_stats :: proc(ctx: Settings_Text_Context) {
    state := ctx.state
    counts := state^.telemetry.particle_counts.published
    statistics: [3]struct{id: contentdata.Content_Message_Id, count: int} = {
        {.Settings_Stats_Dust, counts.dust},
        {.Settings_Stats_Trail, counts.trail},
        {.Settings_Stats_Ui_Dust, counts.ui_dust},
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for statistic, row in statistics {
        label := viewmessages.shell_format(state, statistic.id,
            []contentdata.Content_Format_Argument{{"count", i64(statistic.count)}},
            storage[:])
        draw_settings_stat_row(ctx, label, row)
    }
    draw_settings_stat_row(ctx,
        viewmessages.shell_message(state, .Settings_Stats_Interval), 3)
}

// Draw one statistic or explanation at its shared Settings row spacing.
draw_settings_stat_row :: proc(
    ctx: Settings_Text_Context, label: string, row: int) {
    viewtext.ui_text_shaped({
        encoder = ctx.encoder,
        resolver = ctx.font_resolver,
        key = .Regular,
        text = label,
        position = {
            ctx.panel.x + theme.ui_control_size_metric(
                theme.SETTINGS_PANEL_INSET, ctx.control_size_percent),
            ctx.stats_y + f32(row)*settings_scaled_row_gap(
                ctx.text_size_percent, ctx.control_size_percent),
        },
        color = theme.draw_color(ctx.encoder, .Text),
        font = viewtext.ui_text_font(ctx.font, ctx.text_size_percent),
    })
}

// settings_scaled_row_gap keeps text rows separated at every supported size.
settings_scaled_row_gap :: #force_inline proc(
    text_size_percent: int,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> f32 {
    control_scale := theme.ui_control_size_scale(control_size_percent)
    text_required := max(max(theme.SETTINGS_TOGGLE_ROW_GAP,
        theme.SETTINGS_STATS_ROW_GAP),
        theme.ui_font_size(text_size_percent) + 6)
    return max(text_required, theme.SETTINGS_TOGGLE_ROW_GAP * control_scale)
}

//   Place one fixed-size settings row and return it with the advanced cursor.
settings_stack_row :: #force_inline proc(
    rect: geometry.Rectangle, segment_size: f32,
    cursor: uilayout.Stack_Panel_Cursor) -> uilayout.Stack_Panel_Result {

    return uilayout.stack_panel_place_segment(uilayout.Stack_Panel_Params{
        origin_x = rect.x,
        origin_y = rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = geometry.Rectangle(rect),
        can_expand = false,
        segment_size_is_set = true,
        segment_size = segment_size,
        cursor_in = cursor,
    })
}

//   Lay out the settings view rows and return their y-positions.
settings_view_layout_rows :: proc(
    stack_rect: geometry.Rectangle,
    text_size_percent := theme.TEXT_SIZE_DEFAULT_PERCENT,
    system_motion_notice := false,
    system_contrast_notice := false,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> Settings_View_Rows {
    font_size := theme.ui_font_size(text_size_percent)
    control_scale := theme.ui_control_size_scale(control_size_percent)
    layout: Settings_View_Layout_State = {
        stack_rect = stack_rect,
        cursor = uilayout.stack_panel_cursor_zero(),
        row_gap = settings_scaled_row_gap(text_size_percent, control_size_percent),
        heading_height = font_size + 10,
        action_height = theme.ui_panel_button_height(
            text_size_percent, control_size_percent),
        action_status_gap = theme.ui_control_size_metric(
            theme.SETTINGS_PANEL_INSET * 0.75, control_size_percent),
        slider_height = max(font_size + 6,
            uiwidgets.slider_track_top_offset(text_size_percent,
                control_size_percent) +
            (theme.SETTINGS_TRACK_HEIGHT +
                theme.SETTINGS_TRACK_HIT_PAD_Y * 2) * control_scale + 6),
        system_motion_notice = system_motion_notice,
        system_contrast_notice = system_contrast_notice,
    }
    settings_layout_accessibility_section(&layout)
    settings_layout_history_section(&layout)
    settings_layout_particles_section(&layout)
    settings_layout_other_section(&layout)
    return layout.rows
}

// Reserve the Accessibility heading, controls, notices, and preference sliders.
settings_layout_accessibility_section :: proc(layout: ^Settings_View_Layout_State) {
    rect := layout^.stack_rect
    rows := &layout^.rows
    placement := settings_stack_row(
        rect, layout^.heading_height, layout^.cursor)
    rows^.accessibility_header_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
    rows^.reduce_motion_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.enable_particle_effects_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.open_completed_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.increased_contrast_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.hover_focus_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    settings_layout_magnifier_accessibility_rows(layout)
    settings_layout_accessibility_notices(layout)
    rows^.control_size_y = rect.y + layout^.cursor.offset
    placement = settings_stack_row(rect, layout^.slider_height, layout^.cursor)
    layout^.cursor = placement.cursor_out
    rows^.text_size_y = rect.y + layout^.cursor.offset
    placement = settings_stack_row(rect, layout^.slider_height, layout^.cursor)
    layout^.cursor = placement.cursor_out
    rows^.animation_scale_y = rect.y + layout^.cursor.offset
    placement = settings_stack_row(rect, layout^.slider_height, layout^.cursor)
    layout^.cursor = placement.cursor_out
}

// Reserve only active platform-policy notices while retaining absent-row sentinels.
settings_layout_accessibility_notices :: proc(layout: ^Settings_View_Layout_State) {
    rows := &layout^.rows
    rows^.system_motion_y = -1
    rows^.system_contrast_y = -1
    if layout^.system_motion_notice {
        rows^.system_motion_y = layout^.stack_rect.y + layout^.cursor.offset
        layout^.cursor.offset += layout^.row_gap
    }
    if layout^.system_contrast_notice {
        rows^.system_contrast_y = layout^.stack_rect.y + layout^.cursor.offset
        layout^.cursor.offset += layout^.row_gap
    }
}

// Keep the lens modes and monochrome checkbox in one ordered Accessibility group.
settings_layout_magnifier_accessibility_rows :: proc(
    layout: ^Settings_View_Layout_State) {
    rows := &layout^.rows
    rect := layout^.stack_rect
    rows^.show_magnifier_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.magnifier_input_lock_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.monochrome_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
}

// Reserve the History heading, persistence checkbox, deletion action, and status.
settings_layout_history_section :: proc(layout: ^Settings_View_Layout_State) {
    rect := layout^.stack_rect
    rows := &layout^.rows
    placement := settings_stack_row(
        rect, layout^.heading_height, layout^.cursor)
    rows^.history_header_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
    rows^.persist_history_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.delete_history_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.action_height + layout^.action_status_gap
    rows^.history_delete_status_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
}

// Reserve the Particles heading, limit controls, GPU toggle, and particle counters.
settings_layout_particles_section :: proc(layout: ^Settings_View_Layout_State) {
    rect := layout^.stack_rect
    rows := &layout^.rows
    placement := settings_stack_row(
        rect, layout^.heading_height, layout^.cursor)
    rows^.particles_header_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
    placement = settings_stack_row(rect, layout^.slider_height, layout^.cursor)
    rows^.slider_label_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
    rows^.gpu_dust_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    placement = settings_stack_row(
        rect, layout^.row_gap * 4, layout^.cursor)
    rows^.stats_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
}

// Reserve the Other Settings heading, Julia count, preference rows, and save status.
settings_layout_other_section :: proc(layout: ^Settings_View_Layout_State) {
    rect := layout^.stack_rect
    rows := &layout^.rows
    placement := settings_stack_row(
        rect, layout^.heading_height, layout^.cursor)
    rows^.other_header_y = placement.segment_rect.y
    layout^.cursor = placement.cursor_out
    rows^.animation_entries_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.fps_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.limit_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.sound_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.simd_y = rect.y + layout^.cursor.offset
    layout^.cursor.offset += layout^.row_gap
    rows^.save_status_y = rect.y + layout^.cursor.offset
}

//   Update every settings control and report optional feature availability.
update_settings_controls :: proc(
    ctx: Settings_View_Context,
    rows: Settings_View_Rows, interactive := true) -> Settings_Control_Update {
    result: Settings_View_Preparation = {
        rows = rows,
        text_size_percent = ctx.preferences.interface.text_size_percent,
        control_size_percent = ctx.preferences.interface.control_size_percent,
    }
    settings_prepare_sliders(ctx, rows, interactive, &result)
    result.fps = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.fps_y,
        4001, ctx.labels.display_fps,
        ctx.preferences.interface.display_fps, true, 13}),
        ctx.press_owner, interactive)
    result.limit = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.limit_y,
        4002, ctx.labels.limit_fps,
        ctx.preferences.rendering.limit_fps, true, 14}),
        ctx.press_owner, interactive)
    result.sound = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.sound_y,
        4004, ctx.labels.drawing_sound,
        ctx.preferences.drawing.sound_enabled, true, 15}),
        ctx.press_owner, interactive)
    prepare_settings_optional_controls(ctx, rows, interactive, &result)
    settings_offer_checkbox_help(ctx, result.hover_focus, interactive,
        SETTINGS_HOVER_FOCUS_CHECKBOX_ID, ctx.labels.hover_focus_tooltip)
    settings_offer_checkbox_help(ctx, result.enable_particle_effects, interactive,
        4013, ctx.labels.particle_effects_help)
    settings_offer_checkbox_help(ctx, result.open_completed, interactive,
        4014, ctx.labels.open_completed_help)
    settings_offer_magnifier_tooltip(ctx, result.show_magnifier, interactive)
    settings_offer_magnifier_input_lock_tooltip(
        ctx, result.magnifier_input_lock, interactive)
    settings_offer_control_size_tooltip(ctx, result.control_size, interactive)
    result.delete_history = uiwidgets.prepare_text_button(
        settings_history_delete_button_params(ctx, rows),
        ctx.press_owner, interactive)
    if result.delete_history.action.activated {
        settings_history_delete_activate(
            ctx.state, ctx.mouse_input.sample_time_seconds)
    }
    result.history_delete_status = ctx.settings_panel^.history_delete_status
    result.history_delete_armed =
        result.history_delete_status == .Armed
    if interactive {
        settings_publish_history_delete_status(ctx, rows)
    }
    return {result, result.simd_available, result.gpu_available}
}

// Prepare Settings sliders and offer the animation-scale tooltip when eligible.
settings_prepare_sliders :: proc(
    ctx: Settings_View_Context,
    rows: Settings_View_Rows,
    interactive: bool,
    result: ^Settings_View_Preparation) {
    result^.max_particles = settings_prepare_integer_slider(
        ctx, settings_max_particles_params(ctx, rows.slider_label_y), interactive)
    result^.control_size = settings_prepare_integer_slider(
        ctx, settings_control_size_params(ctx, rows.control_size_y), interactive)
    result^.text_size = settings_prepare_integer_slider(
        ctx, settings_text_size_params(ctx, rows.text_size_y), interactive)
    result^.animation_scale = settings_prepare_integer_slider(
        ctx, settings_animation_scale_params(ctx, rows.animation_scale_y), interactive)
    if interactive && geometry.rectangles_intersect(
        result^.animation_scale.control_geometry.bounds,
        geometry.Rectangle(ctx.panel)) {
        settings_offer_animation_scale_tooltip(ctx, result^.animation_scale)
    }
}

// Prepare capability-gated toggles and interface policy without committing preference edits.
prepare_settings_optional_controls :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows,
    interactive: bool, result: ^Settings_View_Preparation) {
    prepare_settings_rendering_capabilities(ctx, rows, interactive, result)
    prepare_settings_accessibility_controls(ctx, rows, interactive, result)
}

// Prepare hardware-gated rendering toggles without overwriting saved capability intent.
prepare_settings_rendering_capabilities :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows,
    interactive: bool, result: ^Settings_View_Preparation) {
    simd_available := ctx.simd_available
    result.simd = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.simd_y,
        4003, ctx.labels.simd,
        ctx.preferences.rendering.simd,
        simd_available, 16}), ctx.press_owner, interactive)
    gpu_available := ctx.gpu_dust_available
    result.gpu_dust = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {rows.gpu_dust_y,
            4005, ctx.labels.gpu_dust,
            ctx.preferences.rendering.gpu_dust_instancing,
            gpu_available, 12}),
        ctx.press_owner, interactive)
    result.simd_available = simd_available
    result.gpu_available = gpu_available
}

// Prepare independent accessibility policies in their visual and semantic focus order.
prepare_settings_accessibility_controls :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows,
    interactive: bool, result: ^Settings_View_Preparation) {
    result.reduce_motion = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {
        rows.reduce_motion_y, 4006,
        ctx.labels.reduce_motion,
        ctx.preferences.interface.reduce_motion, true, 1}),
        ctx.press_owner, interactive)
    result.increased_contrast = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.increased_contrast_y, 4007,
            ctx.labels.increased_contrast,
            ctx.preferences.interface.increased_contrast, true, 4,
        }), ctx.press_owner, interactive)
    result.enable_particle_effects = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.enable_particle_effects_y, 4013, ctx.labels.enable_particle_effects,
            ctx.preferences.interface.enable_particle_effects, true, 2,
        }), ctx.press_owner, interactive)
    result.open_completed = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.open_completed_y, 4014, ctx.labels.open_completed,
            ctx.preferences.animation.open_completed, true, 3,
        }), ctx.press_owner, interactive)
    result.hover_focus = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {
        rows.hover_focus_y, SETTINGS_HOVER_FOCUS_CHECKBOX_ID,
        ctx.labels.hover_focus,
        ctx.preferences.interface.hover_focus, true, 5,
    }), ctx.press_owner, interactive)
    result.show_magnifier = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.show_magnifier_y, SETTINGS_SHOW_MAGNIFIER_CHECKBOX_ID,
            ctx.labels.show_magnifier,
            ctx.preferences.interface.show_magnifier, true, 6,
        }), ctx.press_owner, interactive)
    result.magnifier_input_lock = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.magnifier_input_lock_y,
            SETTINGS_MAGNIFIER_INPUT_LOCK_CHECKBOX_ID,
            ctx.labels.magnifier_input_lock,
            ctx.preferences.interface.magnifier_input_lock,
            ctx.preferences.interface.show_magnifier, 7,
        }), ctx.press_owner, interactive)
    result.persist_history = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.persist_history_y, 4008,
            ctx.labels.persist_history,
            ctx.preferences.terminal.persist_history, true, 9,
        }), ctx.press_owner, interactive)
    result.monochrome = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {
            rows.monochrome_y, 4009,
            ctx.labels.monochrome,
            ctx.preferences.animation.monochrome, true, 8,
        }), ctx.press_owner, interactive)
}

// Offer checkbox help through the shared keyboard and pointer tooltip path.
settings_offer_checkbox_help :: proc(
    ctx: Settings_View_Context,
    prepared: uiwidgets.Checkbox_Result, interactive: bool,
    control_id: int, text: string) {
    if !interactive {
        return
    }
    owner := uisemantics.semantic_control_id(
        .Settings_Control, control_id)
    source := uioverlay.tooltip_control_source(
        &ctx.state^.ui_runtime.input, ctx.semantic_focus,
        owner, control_id)
    mouse: geometry.Vector2 = {
        ctx.mouse_input.mouse_position.x,
        ctx.mouse_input.mouse_position.y,
    }
    press_active := ctx.press_owner != nil && ctx.press_owner^.active
    if source == .None && !press_active &&
        geometry.rectangle_contains(ctx.panel, mouse) &&
        geometry.rectangle_contains(prepared.control_geometry.bounds, mouse) {
        source = .Pointer
    }
    if prepared.toggled {
        uioverlay.tooltip_dismiss(&ctx.state^.ui_runtime.tooltip, owner)
    }
    uioverlay.tooltip_offer(&ctx.state^.ui_runtime.tooltip, {
        owner = owner,
        source = source,
        anchor = prepared.control_geometry.bounds,
        prefer_above = true,
        text = text,
    })
}

// Offer the animation-scale explanation through the shared accessible tooltip path.
settings_offer_animation_scale_tooltip :: proc(
    ctx: Settings_View_Context, prepared: uiwidgets.Integer_Slider_Result) {
    owner := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_ANIMATION_SCALE_SLIDER_ID)
    source := uioverlay.tooltip_control_source(
        &ctx.state^.ui_runtime.input, ctx.semantic_focus,
        owner, SETTINGS_ANIMATION_SCALE_SLIDER_ID)
    mouse: geometry.Vector2 = {
        ctx.mouse_input.mouse_position.x,
        ctx.mouse_input.mouse_position.y,
    }
    owns_press := ctx.press_owner^.active &&
        ctx.press_owner^.kind == .Slider &&
        ctx.press_owner^.id == SETTINGS_ANIMATION_SCALE_SLIDER_ID
    if source == .None && (!ctx.press_owner^.active || owns_press) &&
        geometry.rectangle_contains(ctx.panel, mouse) &&
        geometry.rectangle_contains(prepared.control_geometry.bounds, mouse) {
        source = .Pointer
    }
    if prepared.changed {
        uioverlay.tooltip_dismiss(&ctx.state^.ui_runtime.tooltip, owner)
    }
    uioverlay.tooltip_offer(&ctx.state^.ui_runtime.tooltip, {
        owner = owner,
        source = source,
        anchor = prepared.control_geometry.bounds,
        prefer_above = true,
        text = ctx.labels.animation_scale_tooltip,
    })
}

// settings_scroll_content_height reserves every scaled Settings section and status.
settings_scroll_content_height :: proc(
    system_motion_notice: bool, system_contrast_notice := false,
    text_size_percent := theme.TEXT_SIZE_DEFAULT_PERCENT,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> f32 {
    rows := settings_view_layout_rows({}, text_size_percent,
        system_motion_notice, system_contrast_notice, control_size_percent)
    return theme.SETTINGS_HEADER_TOP_OFFSET + rows.save_status_y +
        theme.ui_font_size(text_size_percent) + theme.SETTINGS_PANEL_INSET
}

// register_settings_scroll_semantics admits keyboard page navigation in short viewports.
register_settings_scroll_semantics :: proc(
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    label: string,
    scroll: uiwidgets.Scroll_Container_Update_Result) {
    if !scroll.scrollbar.has_scrollbar {
        return
    }
    _ = uisemantics.semantic_register_control(semantic_focus, {
        id = uisemantics.semantic_control_id(.Settings_Control, 6102),
        role = .Panel,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll, .Set_Value},
        region = .Accordion_Content,
        traversal_order = 17,
        bounds = geometry.Rectangle(scroll.view_rect),
        clip_bounds = geometry.Rectangle(scroll.view_rect),
        numeric_range = {
            0,
            f64(scroll.maximum),
            f64(scroll.scroll_y_out),
            f64(scroll.step),
            .Vertical,
            true},
        label = label,
    })
}

// prepare_settings_scroll retains bounded short-viewport scrolling across panel switches.
prepare_settings_scroll :: proc(
    ctx: Settings_View_Context,
    interactive: bool) -> uiwidgets.Scroll_Container_Update_Result {
    panel_state := ctx.settings_panel
    height := settings_scroll_content_height(
        ctx.platform_reduce_motion, ctx.platform_increased_contrast,
        ctx.preferences.interface.text_size_percent,
        ctx.preferences.interface.control_size_percent)
    row_gap := settings_scaled_row_gap(
        ctx.preferences.interface.text_size_percent,
        ctx.preferences.interface.control_size_percent)
    scroll := uiwidgets.scroll_container_visual(
        ctx.panel, height, panel_state^.scroll_y, row_gap,
        ctx.preferences.interface.control_size_percent)
    if interactive {
        scroll = uiwidgets.scroll_container_update({
            id = 6102,
            rect = ctx.panel,
            scroll_y_in = panel_state^.scroll_y,
            content_height = height,
            mouse_input = ctx.mouse_input,
            interaction_space_rect = ctx.panel,
            wheel_step = row_gap * theme.WHEEL_SCROLL_MULTIPLIER,
            press_owner = ctx.press_owner,
            state_in = {panel_state^.scroll_dragging, panel_state^.scroll_drag_off},
            semantic_focus = ctx.semantic_focus,
            semantic_id = uisemantics.semantic_control_id(.Settings_Control, 6102),
            control_size_percent = ctx.preferences.interface.control_size_percent,
        })
        panel_state^.scroll_y = scroll.scroll_y_out
        panel_state^.scroll_dragging = scroll.state_out.is_dragging_thumb
        panel_state^.scroll_drag_off = scroll.state_out.drag_offset_y
    }
    if scroll.scrollbar.has_scrollbar {
        scroll.view_rect.width =
            max(f32(0), scroll.view_rect.width -
                theme.ui_control_size_metric(theme.SCROLLBAR_WIDTH,
                    ctx.preferences.interface.control_size_percent))
    }
    return scroll
}

//   Resolve settings controls and commit their values before rendering.
prepare_settings_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame, interactive := true) -> Settings_View_Preparation {
    if state == nil {
        return {}
    }
    ctx := settings_view_context(state, panel, mouse_input)
    if interactive {
        settings_history_delete_expire(
            ctx.settings_panel, mouse_input.sample_time_seconds)
    }
    scroll := prepare_settings_scroll(ctx, interactive)
    content_panel := scroll.view_rect
    panel_inset := theme.ui_control_size_metric(
        theme.SETTINGS_PANEL_INSET, ctx.preferences.interface.control_size_percent)
    stack_rect: geometry.Rectangle = {content_panel.x + panel_inset,
        content_panel.y + theme.SETTINGS_HEADER_TOP_OFFSET - scroll.scroll_y_out,
        content_panel.width - panel_inset * 2,
        content_panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack_rect,
        ctx.preferences.interface.text_size_percent,
        ctx.platform_reduce_motion, ctx.platform_increased_contrast,
        ctx.preferences.interface.control_size_percent)
    ctx.panel = content_panel
    update := update_settings_controls(ctx, rows, interactive)
    update.prepared.scroll = scroll
    if interactive {
        register_settings_scroll_semantics(
            ctx.semantic_focus,
            viewmessages.shell_message(state, .Navigation_Settings), scroll)
        apply_settings_preparation(state, update.prepared,
            update.simd_available, update.gpu_available)
    }
    return update.prepared
}

//   Commit prepared settings toggle results and related display policy.
apply_settings_preparation :: proc(
    state: ^core.Euclid_General_State,
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool) {
    apply_settings_primary_preparation(state, prepared)
    apply_settings_optional_preparation(
        state, prepared, simd_available, gpu_available)
}

// Commit dust, display, and drawing controls from the prepared frame.
apply_settings_primary_preparation :: proc(
    state: ^core.Euclid_General_State, prepared: Settings_View_Preparation) {
    apply_settings_accessibility_preparation(state, prepared)
    if prepared.max_particles.changed {
        state.particle_system.use_max_dust_particles = prepared.max_particles.value
        settings_record_preference_edit(
            state, .Drawing_Dust_Limit,
            setting_model.integer_value(prepared.max_particles.value))
    }
    if prepared.fps.toggled {
        state.ui_runtime.rendering.display_fps = prepared.fps.checked_out
        settings_record_preference_edit(
            state, .Interface_Display_Fps,
            setting_model.boolean_value(prepared.fps.checked_out))
    }
    if prepared.limit.toggled {
        state.ui_runtime.rendering.limit_fps = prepared.limit.checked_out
        settings_record_preference_edit(
            state, .Rendering_Limit_Fps,
            setting_model.boolean_value(prepared.limit.checked_out))
    }
    if prepared.sound.toggled {
        state.user_drawing_sound_enabled = prepared.sound.checked_out
        settings_record_preference_edit(
            state, .Drawing_Sound_Enabled,
            setting_model.boolean_value(prepared.sound.checked_out))
    }
}

// Persist accessibility preferences changed by the prepared Settings frame.
apply_settings_accessibility_preparation :: proc(
    state: ^core.Euclid_General_State, prepared: Settings_View_Preparation) {
    if prepared.enable_particle_effects.toggled {
        settings_record_preference_edit(state, .Interface_Enable_Particle_Effects,
            setting_model.boolean_value(prepared.enable_particle_effects.checked_out))
    }
    if prepared.open_completed.toggled {
        settings_record_preference_edit(state, .Animation_Open_Completed,
            setting_model.boolean_value(prepared.open_completed.checked_out))
    }
    apply_settings_accessibility_sizes(state, prepared)
    if prepared.reduce_motion.toggled {
        settings_record_preference_edit(state, .Interface_Reduce_Motion,
            setting_model.boolean_value(prepared.reduce_motion.checked_out))
    }
    if prepared.increased_contrast.toggled {
        settings_record_preference_edit(state, .Interface_Increased_Contrast,
            setting_model.boolean_value(prepared.increased_contrast.checked_out))
    }
    apply_settings_pointer_accessibility_preparation(state, prepared)
    if prepared.persist_history.toggled {
        settings_record_preference_edit(state, .Persist_Terminal_History,
            setting_model.boolean_value(prepared.persist_history.checked_out))
    }
    if prepared.monochrome.toggled {
        settings_record_preference_edit(state, .Animation_Monochrome,
            setting_model.boolean_value(prepared.monochrome.checked_out))
    }
}

// Persist the three independently prepared accessibility scale sliders.
apply_settings_accessibility_sizes :: proc(
    state: ^core.Euclid_General_State, prepared: Settings_View_Preparation) {
    if prepared.animation_scale.changed {
        settings_record_preference_edit(state, .Animation_Scale_Percent,
            setting_model.integer_value(prepared.animation_scale.value))
    }
    if prepared.control_size.changed {
        settings_record_preference_edit(state, .Interface_Control_Size,
            setting_model.integer_value(prepared.control_size.value))
    }
    if prepared.text_size.changed {
        settings_record_preference_edit(state, .Interface_Text_Size,
            setting_model.integer_value(prepared.text_size.value))
    }
}

// Persist pointer-only accessibility toggles from the prepared Settings frame.
apply_settings_pointer_accessibility_preparation :: proc(
    state: ^core.Euclid_General_State, prepared: Settings_View_Preparation) {
    if prepared.hover_focus.toggled {
        settings_record_preference_edit(state, .Interface_Hover_Focus,
            setting_model.boolean_value(prepared.hover_focus.checked_out))
    }
    if prepared.show_magnifier.toggled {
        settings_record_preference_edit(state, .Interface_Show_Magnifier,
            setting_model.boolean_value(prepared.show_magnifier.checked_out))
    }
    if prepared.magnifier_input_lock.toggled {
        settings_record_preference_edit(state, .Interface_Magnifier_Input_Lock,
            setting_model.boolean_value(prepared.magnifier_input_lock.checked_out))
    }
}

// Preserve optional-feature intent while deriving hardware-gated runtime state.
apply_settings_optional_preparation :: proc(
    state: ^core.Euclid_General_State,
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool) {
    if prepared.simd.toggled {
        settings_record_preference_edit(
            state, .Rendering_Simd,
            setting_model.boolean_value(prepared.simd.checked_out))
    }
    if prepared.gpu_dust.toggled {
        settings_record_preference_edit(
            state, .Rendering_Gpu_Dust_Instancing,
            setting_model.boolean_value(prepared.gpu_dust.checked_out))
    }
    state.ui_runtime.rendering.use_simd_batch_projection =
        simd_available && state.ui_runtime.preferences.values.rendering.simd
    state.ui_runtime.rendering.use_gpu_dust_instancing =
        gpu_available &&
        state.ui_runtime.preferences.values.rendering.gpu_dust_instancing
}

// Coalesce one typed user edit for the next worker-owned persistence batch.
settings_record_preference_edit :: proc(
    state: ^core.Euclid_General_State,
    id: setting_model.Setting_Id,
    value: setting_model.Setting_Value) {
    runtime := &state^.ui_runtime
    preferences := runtime^.preferences.values
    pending := state^.preferences_runtime.settings_pending
    if !setting_model.apply_setting_value(&preferences, id, value, .Override) ||
        !setting_model.change_set_set(&pending, id, value) {
        log.errorf("settings_edit_rejected setting=%d", int(id))
        return
    }
    runtime^.preferences.values = preferences
    state^.preferences_runtime.settings_pending = pending
    viewpreferences.settings_save_note_edit(state)
}

// Resolve optional control availability without replacing the retained user preference.
settings_control_available :: proc(
    id: setting_model.Setting_Id, simd_available, gpu_available: bool) -> bool {
    #partial switch id {
    case .Rendering_Simd:
        return simd_available
    case .Rendering_Gpu_Dust_Instancing:
        return gpu_available
    }
    return true
}

// Apply a typed edit to an existing control, preserving hardware availability gates.
settings_apply_control_edit :: proc(
    state: ^core.Euclid_General_State, id: setting_model.Setting_Id,
    value: setting_model.Setting_Value) -> bool {
    if state == nil ||
        !setting_model.valid_setting_value(id, value) {
        return false
    }
    simd_available := projection.simd_batch_projection_available()
    gpu_available := state^.ui_runtime.rendering.gpu_dust_instancing_available
    if !settings_control_available(id, simd_available, gpu_available) {
        return false
    }
    prepared, supported := settings_control_edit_preparation(id, value)
    if !supported {
        return false
    }
    apply_settings_preparation(state, prepared, simd_available, gpu_available)
    return true
}

// Translate an admitted control identity into the same typed results as ordinary input.
settings_control_edit_preparation :: proc(
    id: setting_model.Setting_Id, value: setting_model.Setting_Value) ->
    (Settings_View_Preparation, bool) {
    prepared: Settings_View_Preparation
    #partial switch id {
    case .Drawing_Dust_Limit:
        prepared.max_particles.changed = true
        prepared.max_particles.value = value.integer
    case .Animation_Scale_Percent:
        prepared.animation_scale.changed = true
        prepared.animation_scale.value = int(value.integer)
    case .Interface_Text_Size:
        prepared.text_size.changed = true
        prepared.text_size.value = int(value.integer)
    case .Interface_Control_Size:
        prepared.control_size.changed = true
        prepared.control_size.value = int(value.integer)
    case .Interface_Display_Fps, .Interface_Reduce_Motion,
        .Interface_Increased_Contrast, .Rendering_Limit_Fps,
        .Drawing_Sound_Enabled, .Rendering_Simd,
        .Rendering_Gpu_Dust_Instancing, .Persist_Terminal_History,
        .Animation_Monochrome, .Interface_Hover_Focus,
        .Interface_Show_Magnifier, .Interface_Magnifier_Input_Lock,
        .Interface_Enable_Particle_Effects, .Animation_Open_Completed:
        return settings_boolean_control_edit_preparation(id, value)
    case:
        return {}, false
    }
    return prepared, true
}

// Translate one boolean preference identity into its prepared checkbox result.
settings_boolean_control_edit_preparation :: proc(
    id: setting_model.Setting_Id, value: setting_model.Setting_Value) ->
    (Settings_View_Preparation, bool) {
    prepared: Settings_View_Preparation
    #partial switch id {
    case .Interface_Enable_Particle_Effects:
        prepared.enable_particle_effects = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Animation_Open_Completed:
        prepared.open_completed = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Display_Fps:
        prepared.fps = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Reduce_Motion:
        prepared.reduce_motion = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Increased_Contrast:
        prepared.increased_contrast = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Hover_Focus:
        prepared.hover_focus = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Show_Magnifier:
        prepared.show_magnifier = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Interface_Magnifier_Input_Lock:
        prepared.magnifier_input_lock = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Persist_Terminal_History:
        prepared.persist_history = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Animation_Monochrome:
        prepared.monochrome = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Rendering_Limit_Fps:
        prepared.limit = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Drawing_Sound_Enabled:
        prepared.sound = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Rendering_Simd:
        prepared.simd = {
            toggled = true,
            checked_out = value.boolean,
        }
    case .Rendering_Gpu_Dust_Instancing:
        prepared.gpu_dust = {
            toggled = true,
            checked_out = value.boolean,
        }
    case:
        return {}, false
    }
    return prepared, true
}
