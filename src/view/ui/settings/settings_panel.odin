package uisettings

import uilayout "../layout"
import native "../../native"
import core "../../../core"
import contentdata "../../../core/content"
import particlemodel "../../../particles/model"
import geometry "../../../core/geometry"
import view_font "../../font"
import setting_model "../../../settings"
import fmt "core:fmt"
import log "core:log"
import viewmessages "../../messages"
import viewtext "../text"
import projection "../../world/projection"
import input "../../input"
import uiwidgets "../widgets"
import theme "../theme"
import worldmodel "../../world/model"
import uisemantics "../semantics"
import viewpreferences "../../preferences"

SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID :: 6101

//   Shared dependencies for controls in one settings panel frame.
Settings_View_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
}

//   Row y-positions for the settings view's controls.
Settings_View_Rows :: struct {
    slider_label_y : f32,
    stats_y : f32,
    fps_y : f32,
    limit_y : f32,
    sound_y : f32,
    simd_y : f32,
    gpu_dust_y : f32,
    reduce_motion_y: f32,
}

//   Fixed prepared interaction results for all settings controls.
Settings_View_Preparation :: struct {
    rows: Settings_View_Rows,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    max_particles: uiwidgets.Integer_Slider_Result,
    fps: uiwidgets.Checkbox_Result,
    limit: uiwidgets.Checkbox_Result,
    sound: uiwidgets.Checkbox_Result,
    simd: uiwidgets.Checkbox_Result,
    gpu_dust: uiwidgets.Checkbox_Result,
    reduce_motion: uiwidgets.Checkbox_Result,
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
    order: u16,
}

//   Prepared controls paired with platform feature availability.
Settings_Control_Update :: struct {
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool,
}

// draw_encoded_checkbox_geometry encodes one checkbox without its deferred label.
draw_encoded_checkbox_geometry :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle, checked: bool) {
    _ = native.draw_encoder_rectangle_outline(
        encoder, geometry.Rectangle(rectangle), 1, theme.UI_BORDER_COLOR)
    if !checked {
        return
    }
    first := geometry.Vector2{rectangle.x + 3,
        rectangle.y + rectangle.height * 0.55}
    second := geometry.Vector2{rectangle.x + 6,
        rectangle.y + rectangle.height - 3}
    third := geometry.Vector2{rectangle.x + rectangle.width - 3, rectangle.y + 3}
    _ = native.draw_encoder_line(encoder, first, second, 1.6, theme.UI_TEXT_COLOR)
    _ = native.draw_encoder_line(encoder, second, third, 1.6, theme.UI_TEXT_COLOR)
}

// draw_encoded_slider_geometry encodes one slider track, fill, and knob.
draw_encoded_slider_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: uiwidgets.Integer_Slider_Result) {
    knob_center_x := prepared.knob.x + prepared.knob.width * 0.5
    _ = native.draw_encoder_rectangle(
        encoder, prepared.track, worldmodel.BACKGROUND_COLOR)
    fill := geometry.Rectangle{prepared.track.x, prepared.track.y,
        max(0, knob_center_x - prepared.track.x), prepared.track.height}
    _ = native.draw_encoder_rectangle(
        encoder, fill, theme.UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle(
        encoder, prepared.knob, theme.UI_TEXT_COLOR)
}

// Draw every checkbox in one prepared Settings layout.
draw_encoded_settings_checkboxes :: proc(
    encoder: ^native.Draw_Encoder, prepared: Settings_View_Preparation) {
    checks := [6]uiwidgets.Checkbox_Result{
        prepared.fps, prepared.limit, prepared.sound,
        prepared.simd, prepared.gpu_dust, prepared.reduce_motion,
    }
    for check in checks {
        draw_encoded_checkbox_geometry(
            encoder, check.box_rect, check.checked_out)
    }
}

// draw_encoded_settings_geometry encodes settings controls without text.
draw_encoded_settings_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: Settings_View_Preparation) {
    draw_encoded_slider_geometry(encoder, prepared.max_particles)
    draw_encoded_settings_checkboxes(encoder, prepared)
    uiwidgets.draw_encoded_scrollbar(encoder, prepared.scroll.scrollbar)
}

// Draw labels attached to the prepared settings checkboxes.
draw_encoded_settings_check_labels :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    x: f32, rows: Settings_View_Rows, prepared: Settings_View_Preparation) {
    labels := [6]struct{label: string, y: f32}{
        {viewmessages.shell_message(state, .Settings_Display_Fps), rows.fps_y},
        {viewmessages.shell_message(state, .Settings_Limit_Fps), rows.limit_y},
        {viewmessages.shell_message(state, .Settings_Drawing_Sound), rows.sound_y},
        {settings_simd_label(state, prepared.simd_available), rows.simd_y},
        {settings_gpu_dust_label(state, prepared.gpu_available), rows.gpu_dust_y},
        {viewmessages.shell_message(
            state, .Settings_Reduce_Motion), rows.reduce_motion_y},
    }
    for item in labels {
        viewtext.draw_encoded_label(&state^.font_cache, encoder, item.label,
            x + theme.SETTINGS_CHECKBOX_SIZE + theme.SETTINGS_CHECKBOX_LABEL_GAP,
            item.y - theme.SETTINGS_CHECKBOX_TEXT_OFFSET_Y)
    }
    if state^.ui_runtime.platform_reduce_motion {
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            viewmessages.shell_message(state, .Settings_System_Reduce_Motion),
            x, rows.reduce_motion_y + theme.SETTINGS_TOGGLE_ROW_GAP)
    }
}

// draw_encoded_settings_text emits current labels, values, and counters.
draw_encoded_settings_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Settings_View_Preparation) {
    panel := prepared.scroll.view_rect
    rows := prepared.rows
    x := panel.x + theme.SETTINGS_PANEL_INSET
    value := fmt.tprintf("%d", state^.particle_system^.use_max_dust_particles)
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    value_width, measured := viewtext.ui_text_measure_monospace(
        value, face, theme.TREE_FONT_SIZE, 0)
    if !measured {
        value_width = 40
    }
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Settings_Maximum_Dust), x, rows.slider_label_y)
    viewtext.draw_encoded_label(&state^.font_cache, encoder, value,
        settings_right_aligned_x(panel, value_width), rows.slider_label_y)
    animation_entries_added := 0
    if state^.julia_interface != nil {
        animation_entries_added = state^.julia_interface^.animation_count
    }
    draw_settings_particle_stats(
        {state = state, panel = panel, font = face,
            font_resolver = view_font.cache_terminal_resolver(&state^.font_cache)},
        rows.stats_y, encoder, animation_entries_added)
    draw_encoded_settings_check_labels(state, encoder, x, rows, prepared)
    status_y := rows.reduce_motion_y + theme.SETTINGS_TOGGLE_ROW_GAP
    if state^.ui_runtime.platform_reduce_motion {
        status_y += theme.SETTINGS_TOGGLE_ROW_GAP
    }
    draw_encoded_settings_save_status(state, encoder, x, status_y)
}

// Resolve and draw the localized persistence state beneath the setting controls.
draw_encoded_settings_save_status :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    x, y: f32) {
    message := contentdata.Content_Message_Id.Settings_Save_Saved
    switch state^.ui_runtime.settings_save_status {
    case .Saved: message = .Settings_Save_Saved
    case .Pending: message = .Settings_Save_Pending
    case .Saving: message = .Settings_Save_Saving
    case .Unavailable: message = .Settings_Save_Unavailable
    case .Failed: message = .Settings_Save_Failed
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
    panel: geometry.Rectangle, text_width: f32) -> f32 {
    return panel.x + panel.width - theme.SETTINGS_PANEL_INSET - max(text_width, 0)
}

//   Build one settings checkbox parameter record from shared row context.
settings_checkbox_params :: proc(
    ctx: Settings_View_Context,
    descriptor: Settings_Checkbox_Descriptor) -> uiwidgets.Checkbox_Params {
    return {
        id = descriptor.id,
        rect = geometry.Rectangle{
            ctx.panel.x + theme.SETTINGS_PANEL_INSET, descriptor.row_y,
            theme.SETTINGS_CHECKBOX_SIZE, theme.SETTINGS_CHECKBOX_SIZE,},
        checked = descriptor.checked,
        enabled = descriptor.enabled,
        mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = true,
        label = descriptor.label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = theme.TREE_FONT_SIZE,
        label_offset_x = theme.SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -theme.SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
        semantic_focus = ctx.state.ui_runtime.semantic_focus,
        semantic_domain = .Settings_Control,
        semantic_order = descriptor.order,
        semantic_clip = ctx.panel,
    }
}

//   Build the maximum-particle slider parameters shared by update and draw.
settings_max_particles_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        ui_runtime = &ctx.state.ui_runtime,
        press_id = SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        label = viewmessages.shell_message(ctx.state, .Settings_Maximum_Dust),
        value = ctx.state.particle_system.use_max_dust_particles,
        min_value = 0,
        max_value = particlemodel.MAX_LOW_PARTICLES,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 0,
    }
}

//   Render particle render-count statistics and Julia animation-entry counts in settings view.
draw_settings_particle_stats :: proc(
    ctx: Settings_View_Context, stats_y: f32,
    encoder: ^native.Draw_Encoder, animation_entries_added: int) {

    ps := ctx.state.particle_system
    statistics := [4]struct{id: contentdata.Content_Message_Id, count: int}{
        {.Settings_Stats_Dust, ps.last_render_low},
        {.Settings_Stats_Trail, ps.last_render_mid},
        {.Settings_Stats_Flicker, ps.last_render_high},
        {.Settings_Stats_Animation_Entries, animation_entries_added},
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for statistic, row in statistics {
        label := viewmessages.shell_format(ctx.state, statistic.id,
            []contentdata.Content_Format_Argument{{"count", i64(statistic.count)}},
            storage[:])
        viewtext.ui_text_shaped({
            encoder = encoder,
            resolver = ctx.font_resolver,
            key = .Regular,
            text = label,
            position = {
                ctx.panel.x + theme.SETTINGS_PANEL_INSET,
                stats_y + f32(row)*theme.SETTINGS_STATS_ROW_GAP,
            },
            color = theme.UI_TEXT_COLOR,
            font = viewtext.ui_text_font(ctx.font),
        })
    }
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
    stack_rect: geometry.Rectangle) -> Settings_View_Rows {
    stack_cursor := uilayout.stack_panel_cursor_zero()
    stack_cursor.offset =
        theme.SETTINGS_SLIDER_LABEL_TOP_OFFSET - theme.SETTINGS_HEADER_TOP_OFFSET

    slider_label_row := settings_stack_row(stack_rect,
        theme.SETTINGS_TRACK_TOP_OFFSET + theme.SETTINGS_STATS_TOP_OFFSET, stack_cursor)
    stats_row := settings_stack_row(stack_rect,
        theme.SETTINGS_TOGGLE_TOP_OFFSET - theme.SETTINGS_STATS_TOP_OFFSET,
        slider_label_row.cursor_out)
    fps_row := settings_stack_row(stack_rect, theme.SETTINGS_TOGGLE_ROW_GAP,
        stats_row.cursor_out)
    limit_row := settings_stack_row(stack_rect, theme.SETTINGS_TOGGLE_ROW_GAP,
        fps_row.cursor_out)
    sound_row := settings_stack_row(stack_rect, theme.SETTINGS_TOGGLE_ROW_GAP,
        limit_row.cursor_out)
    simd_row := settings_stack_row(stack_rect, theme.SETTINGS_TOGGLE_ROW_GAP,
        sound_row.cursor_out)
    gpu_dust_row := settings_stack_row(stack_rect, theme.SETTINGS_TOGGLE_ROW_GAP,
        simd_row.cursor_out)
    reduce_motion_row := settings_stack_row(stack_rect, 0, gpu_dust_row.cursor_out)

    return Settings_View_Rows{
        slider_label_y = slider_label_row.segment_rect.y,
        stats_y = stats_row.segment_rect.y,
        fps_y = fps_row.segment_rect.y,
        limit_y = limit_row.segment_rect.y,
        sound_y = sound_row.segment_rect.y,
        simd_y = simd_row.segment_rect.y,
        gpu_dust_y = gpu_dust_row.segment_rect.y,
        reduce_motion_y = reduce_motion_row.segment_rect.y,
    }
}

//   Update every settings control and report optional feature availability.
update_settings_controls :: proc(
    ctx: Settings_View_Context,
    rows: Settings_View_Rows, interactive := true) -> Settings_Control_Update {
    result := Settings_View_Preparation{rows = rows}
    result.max_particles = uiwidgets.prepare_integer_slider(
        settings_max_particles_params(ctx, rows.slider_label_y), interactive)
    result.fps = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.fps_y,
        4001, viewmessages.shell_message(ctx.state, .Settings_Display_Fps),
        ctx.state.ui_runtime.settings_preferences.interface.display_fps, true, 1}),
        &ctx.state.ui_runtime.ui_press_owner, interactive)
    result.limit = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.limit_y,
        4002, viewmessages.shell_message(ctx.state, .Settings_Limit_Fps),
        ctx.state.ui_runtime.settings_preferences.rendering.limit_fps, true, 2}),
        &ctx.state.ui_runtime.ui_press_owner, interactive)
    result.sound = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.sound_y,
        4004, viewmessages.shell_message(ctx.state, .Settings_Drawing_Sound),
        ctx.state.ui_runtime.settings_preferences.drawing.sound_enabled, true, 3}),
        &ctx.state.ui_runtime.ui_press_owner, interactive)
    prepare_settings_optional_controls(ctx, rows, interactive, &result)
    return {result, result.simd_available, result.gpu_available}
}

// Prepare capability-gated toggles and motion policy without committing preference edits.
prepare_settings_optional_controls :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows,
    interactive: bool, result: ^Settings_View_Preparation) {
    simd_available := projection.simd_batch_projection_available()
    simd_label := settings_simd_label(ctx.state, simd_available)
    result.simd = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.simd_y,
        4003, simd_label,
        ctx.state.ui_runtime.settings_preferences.rendering.simd,
        simd_available, 4}), &ctx.state.ui_runtime.ui_press_owner, interactive)
    gpu_available := ctx.state.ui_runtime.gpu_dust_instancing_available
    gpu_label := settings_gpu_dust_label(ctx.state, gpu_available)
    result.gpu_dust = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {rows.gpu_dust_y,
            4005, gpu_label,
            ctx.state.ui_runtime.settings_preferences.rendering.gpu_dust_instancing,
            gpu_available, 5}),
        &ctx.state.ui_runtime.ui_press_owner, interactive)
    result.simd_available = simd_available
    result.gpu_available = gpu_available
    result.reduce_motion = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {
        rows.reduce_motion_y, 4006,
        viewmessages.shell_message(ctx.state, .Settings_Reduce_Motion),
        ctx.state.ui_runtime.settings_preferences.interface.reduce_motion, true, 6}),
        &ctx.state.ui_runtime.ui_press_owner, interactive)
}

// settings_scroll_content_height reserves controls, the platform notice, and save status.
settings_scroll_content_height :: proc(system_notice: bool) -> f32 {
    height := f32(
        theme.SETTINGS_SLIDER_LABEL_TOP_OFFSET + theme.SETTINGS_TRACK_TOP_OFFSET +
        theme.SETTINGS_TOGGLE_TOP_OFFSET + 6 * theme.SETTINGS_TOGGLE_ROW_GAP +
        theme.TREE_FONT_SIZE + theme.SETTINGS_PANEL_INSET)
    if system_notice {
        height += theme.SETTINGS_TOGGLE_ROW_GAP
    }
    return height
}

// register_settings_scroll_semantics admits keyboard page navigation in short viewports.
register_settings_scroll_semantics :: proc(
    state: ^core.Euclid_General_State, scroll: uiwidgets.Scroll_Container_Update_Result) {
    if !scroll.scrollbar.has_scrollbar {
        return
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = uisemantics.semantic_control_id(.Settings_Control, 6102), role = .Panel,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll, .Set_Value}, region = .Accordion_Content,
        traversal_order = 7, bounds = geometry.Rectangle(scroll.view_rect),
        clip_bounds = geometry.Rectangle(scroll.view_rect),
        numeric_range = {0, f64(scroll.maximum), f64(scroll.scroll_y_out),
            f64(scroll.step), .Vertical, true},
        label = viewmessages.shell_message(state, .Navigation_Settings),
    })
}

// prepare_settings_scroll retains bounded short-viewport scrolling across panel switches.
prepare_settings_scroll :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame,
    interactive: bool) -> uiwidgets.Scroll_Container_Update_Result {
    runtime := &state^.ui_runtime
    height := settings_scroll_content_height(runtime^.platform_reduce_motion)
    scroll := uiwidgets.scroll_container_visual(
        panel, height, runtime^.settings_scroll_y, theme.SETTINGS_TOGGLE_ROW_GAP)
    if interactive {
        scroll = uiwidgets.scroll_container_update({id = 6102, rect = panel,
            scroll_y_in = runtime^.settings_scroll_y, content_height = height,
            mouse_input = frame, interaction_space_rect = panel,
            wheel_step = theme.SETTINGS_TOGGLE_ROW_GAP * theme.WHEEL_SCROLL_MULTIPLIER,
            press_owner = &runtime^.ui_press_owner,
            state_in = {runtime^.settings_scroll_dragging,
                runtime^.settings_scroll_drag_off},
            semantic_focus = runtime^.semantic_focus,
            semantic_id = uisemantics.semantic_control_id(.Settings_Control, 6102)})
        runtime^.settings_scroll_y = scroll.scroll_y_out
        runtime^.settings_scroll_dragging = scroll.state_out.is_dragging_thumb
        runtime^.settings_scroll_drag_off = scroll.state_out.drag_offset_y
    }
    if scroll.scrollbar.has_scrollbar {
        scroll.view_rect.width =
            max(f32(0), scroll.view_rect.width - theme.SCROLLBAR_WIDTH)
    }
    return scroll
}

//   Resolve settings controls and commit their values before rendering.
prepare_settings_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame, interactive := true) -> Settings_View_Preparation {
    if state == nil || state.particle_system == nil {
        return {}
    }
    scroll := prepare_settings_scroll(state, panel, mouse_input, interactive)
    content_panel := scroll.view_rect
    stack_rect := geometry.Rectangle{content_panel.x + theme.SETTINGS_PANEL_INSET,
        content_panel.y + theme.SETTINGS_HEADER_TOP_OFFSET - scroll.scroll_y_out,
        content_panel.width - theme.SETTINGS_PANEL_INSET * 2,
        content_panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack_rect)
    ctx := Settings_View_Context{state, content_panel, mouse_input,
        view_font.cache_borrow(&state.font_cache, .Regular),
        view_font.cache_terminal_resolver(&state.font_cache)}
    update := update_settings_controls(ctx, rows, interactive)
    update.prepared.scroll = scroll
    if interactive {
        register_settings_scroll_semantics(state, scroll)
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
    if prepared.max_particles.changed {
        state.particle_system.use_max_dust_particles = prepared.max_particles.value
        settings_record_preference_edit(
            state, .Drawing_Dust_Limit,
            setting_model.integer_value(prepared.max_particles.value))
    }
    if prepared.fps.toggled {
        state.ui_runtime.display_fps = prepared.fps.checked_out
        settings_record_preference_edit(
            state, .Interface_Display_Fps,
            setting_model.boolean_value(prepared.fps.checked_out))
    }
    if prepared.limit.toggled {
        state.ui_runtime.limit_fps = prepared.limit.checked_out
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
    if prepared.reduce_motion.toggled {
        settings_record_preference_edit(state, .Interface_Reduce_Motion,
            setting_model.boolean_value(prepared.reduce_motion.checked_out))
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
    state.ui_runtime.use_simd_batch_projection =
        simd_available && state.ui_runtime.settings_preferences.rendering.simd
    state.ui_runtime.use_gpu_dust_instancing =
        gpu_available &&
        state.ui_runtime.settings_preferences.rendering.gpu_dust_instancing
}

// Coalesce one typed user edit for the next worker-owned persistence batch.
settings_record_preference_edit :: proc(
    state: ^core.Euclid_General_State,
    id: setting_model.Setting_Id,
    value: setting_model.Setting_Value) {
    runtime := &state^.ui_runtime
    preferences := runtime^.settings_preferences
    pending := state^.preferences_runtime.settings_pending
    if !setting_model.apply_setting_value(&preferences, id, value, .Override) ||
        !setting_model.change_set_set(&pending, id, value) {
        log.errorf("settings_edit_rejected setting=%d", int(id))
        return
    }
    runtime^.settings_preferences = preferences
    state^.preferences_runtime.settings_pending = pending
    viewpreferences.settings_save_note_edit(state)
}

// Resolve optional control availability without replacing the retained user preference.
settings_control_available :: proc(
    id: setting_model.Setting_Id, simd_available, gpu_available: bool) -> bool {
    #partial switch id {
    case .Rendering_Simd: return simd_available
    case .Rendering_Gpu_Dust_Instancing: return gpu_available
    }
    return true
}

// Apply a typed edit to an existing control, preserving hardware availability gates.
settings_apply_control_edit :: proc(
    state: ^core.Euclid_General_State, id: setting_model.Setting_Id,
    value: setting_model.Setting_Value) -> bool {
    if state == nil || state^.particle_system == nil ||
        !setting_model.valid_setting_value(id, value) {
        return false
    }
    simd_available := projection.simd_batch_projection_available()
    gpu_available := state^.ui_runtime.gpu_dust_instancing_available
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
    case .Interface_Display_Fps:
        prepared.fps = {toggled = true, checked_out = value.boolean}
    case .Interface_Reduce_Motion:
        prepared.reduce_motion = {toggled = true, checked_out = value.boolean}
    case .Rendering_Limit_Fps:
        prepared.limit = {toggled = true, checked_out = value.boolean}
    case .Drawing_Sound_Enabled:
        prepared.sound = {toggled = true, checked_out = value.boolean}
    case .Rendering_Simd:
        prepared.simd = {toggled = true, checked_out = value.boolean}
    case .Rendering_Gpu_Dust_Instancing:
        prepared.gpu_dust = {toggled = true, checked_out = value.boolean}
    case:
        return {}, false
    }
    return prepared, true
}
