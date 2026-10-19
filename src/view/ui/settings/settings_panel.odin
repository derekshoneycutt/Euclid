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
import viewmodel "../model"

SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID :: 6101

// Settings_View_Labels snapshots localized strings before leaf control preparation.
Settings_View_Labels :: struct {
    maximum_dust: string,
    display_fps: string,
    limit_fps: string,
    drawing_sound: string,
    simd: string,
    gpu_dust: string,
    reduce_motion: string,
}

// Shared component and input dependencies for one settings panel preparation.
Settings_View_Context :: struct {
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    settings_panel: ^viewmodel.Ui_Settings_Panel_State,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    preferences: setting_model.Preferences,
    particle_system: ^particlemodel.Particle_System,
    gpu_dust_available: bool,
    platform_reduce_motion: bool,
    simd_available: bool,
    labels: Settings_View_Labels,
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
    order: u32,
}

//   Prepared controls paired with platform feature availability.
Settings_Control_Update :: struct {
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool,
}

// Settings_Particle_Stats_Context groups display facts for the settings statistics.
Settings_Particle_Stats_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
    stats_y: f32,
    encoder: ^native.Draw_Encoder,
    animation_entries_added: int,
}

// settings_cancel_geometry_capture releases transient panel drags after layout changes.
settings_cancel_geometry_capture :: proc(
    panel: ^viewmodel.Ui_Settings_Panel_State) {
    panel^.scroll_dragging = false
    panel^.scroll_drag_off = 0
    panel^.slider_dragging = false
    panel^.slider_drag_offset_x = 0
}

// settings_view_context snapshots the application facts needed by leaf preparation.
settings_view_context :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame) -> Settings_View_Context {
    preferences := state^.ui_runtime.preferences.values
    simd_available := projection.simd_batch_projection_available()
    gpu_available := state^.ui_runtime.rendering.gpu_dust_instancing_available
    labels := Settings_View_Labels{
        maximum_dust = viewmessages.shell_message(state, .Settings_Maximum_Dust),
        display_fps = viewmessages.shell_message(state, .Settings_Display_Fps),
        limit_fps = viewmessages.shell_message(state, .Settings_Limit_Fps),
        drawing_sound = viewmessages.shell_message(state, .Settings_Drawing_Sound),
        simd = settings_simd_label(state, simd_available),
        gpu_dust = settings_gpu_dust_label(state, gpu_available),
        reduce_motion = viewmessages.shell_message(state, .Settings_Reduce_Motion),
    }
    return Settings_View_Context{
        panel = panel, mouse_input = mouse_input,
        settings_panel = &state^.ui_runtime.settings_panel,
        press_owner = &state^.ui_runtime.input.press_owner,
        semantic_focus = state^.ui_runtime.semantic_focus,
        preferences = preferences, particle_system = &state^.particle_system,
        gpu_dust_available = gpu_available,
        platform_reduce_motion = state^.ui_runtime.platform_reduce_motion,
        simd_available = simd_available, labels = labels,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
    }
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
    value := fmt.tprintf("%d", state^.particle_system.use_max_dust_particles)
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
    draw_settings_particle_stats(Settings_Particle_Stats_Context{
        state = state, panel = panel, font = face,
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        stats_y = rows.stats_y, encoder = encoder,
        animation_entries_added = animation_entries_added,
    })
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
    switch state^.ui_runtime.preferences.save_status {
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
        semantic_focus = ctx.semantic_focus,
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
        press_owner = ctx.press_owner,
        semantic_focus = ctx.semantic_focus,
        press_id = SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        label = ctx.labels.maximum_dust,
        value = ctx.particle_system^.use_max_dust_particles,
        min_value = 0,
        max_value = particlemodel.MAX_LOW_PARTICLES,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        semantic_domain = .Settings_Control,
        semantic_order = 0,
    }
}

// Draw completed particle interval peaks separately from the live animation-entry count.
draw_settings_particle_stats :: proc(ctx: Settings_Particle_Stats_Context) {
    state := ctx.state
    counts := state^.telemetry.particle_counts.published
    statistics := [4]struct{id: contentdata.Content_Message_Id, count: int}{
        {.Settings_Stats_Dust, counts.dust},
        {.Settings_Stats_Trail, counts.trail},
        {.Settings_Stats_Ui_Dust, counts.ui_dust},
        {.Settings_Stats_Animation_Entries, ctx.animation_entries_added},
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for statistic, row in statistics {
        label := viewmessages.shell_format(state, statistic.id,
            []contentdata.Content_Format_Argument{{"count", i64(statistic.count)}},
            storage[:])
        display_row := row
        if statistic.id == .Settings_Stats_Animation_Entries {
            display_row += 1
        }
        draw_settings_stat_row(ctx, label, display_row)
    }
    draw_settings_stat_row(ctx,
        viewmessages.shell_message(state, .Settings_Stats_Interval), 3)
}

// Draw one statistic or explanation at its shared Settings row spacing.
draw_settings_stat_row :: proc(
    ctx: Settings_Particle_Stats_Context, label: string, row: int) {
    viewtext.ui_text_shaped({
        encoder = ctx.encoder,
        resolver = ctx.font_resolver,
        key = .Regular,
        text = label,
        position = {
            ctx.panel.x + theme.SETTINGS_PANEL_INSET,
            ctx.stats_y + f32(row)*theme.SETTINGS_STATS_ROW_GAP,
        },
        color = theme.UI_TEXT_COLOR,
        font = viewtext.ui_text_font(ctx.font),
    })
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
        4001, ctx.labels.display_fps,
        ctx.preferences.interface.display_fps, true, 1}),
        ctx.press_owner, interactive)
    result.limit = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.limit_y,
        4002, ctx.labels.limit_fps,
        ctx.preferences.rendering.limit_fps, true, 2}),
        ctx.press_owner, interactive)
    result.sound = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.sound_y,
        4004, ctx.labels.drawing_sound,
        ctx.preferences.drawing.sound_enabled, true, 3}),
        ctx.press_owner, interactive)
    prepare_settings_optional_controls(ctx, rows, interactive, &result)
    return {result, result.simd_available, result.gpu_available}
}

// Prepare capability-gated toggles and motion policy without committing preference edits.
prepare_settings_optional_controls :: proc(
    ctx: Settings_View_Context, rows: Settings_View_Rows,
    interactive: bool, result: ^Settings_View_Preparation) {
    simd_available := ctx.simd_available
    result.simd = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {rows.simd_y,
        4003, ctx.labels.simd,
        ctx.preferences.rendering.simd,
        simd_available, 4}), ctx.press_owner, interactive)
    gpu_available := ctx.gpu_dust_available
    result.gpu_dust = uiwidgets.prepare_checkbox(
        settings_checkbox_params(ctx, {rows.gpu_dust_y,
            4005, ctx.labels.gpu_dust,
            ctx.preferences.rendering.gpu_dust_instancing,
            gpu_available, 5}),
        ctx.press_owner, interactive)
    result.simd_available = simd_available
    result.gpu_available = gpu_available
    result.reduce_motion = uiwidgets.prepare_checkbox(settings_checkbox_params(ctx, {
        rows.reduce_motion_y, 4006,
        ctx.labels.reduce_motion,
        ctx.preferences.interface.reduce_motion, true, 6}),
        ctx.press_owner, interactive)
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
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    label: string,
    scroll: uiwidgets.Scroll_Container_Update_Result) {
    if !scroll.scrollbar.has_scrollbar {
        return
    }
    _ = uisemantics.semantic_register_control(semantic_focus, {
        id = uisemantics.semantic_control_id(.Settings_Control, 6102), role = .Panel,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll, .Set_Value}, region = .Accordion_Content,
        traversal_order = 7, bounds = geometry.Rectangle(scroll.view_rect),
        clip_bounds = geometry.Rectangle(scroll.view_rect),
        numeric_range = {0, f64(scroll.maximum), f64(scroll.scroll_y_out),
            f64(scroll.step), .Vertical, true},
        label = label,
    })
}

// prepare_settings_scroll retains bounded short-viewport scrolling across panel switches.
prepare_settings_scroll :: proc(
    ctx: Settings_View_Context,
    interactive: bool) -> uiwidgets.Scroll_Container_Update_Result {
    panel_state := ctx.settings_panel
    height := settings_scroll_content_height(ctx.platform_reduce_motion)
    scroll := uiwidgets.scroll_container_visual(
        ctx.panel, height, panel_state^.scroll_y, theme.SETTINGS_TOGGLE_ROW_GAP)
    if interactive {
        scroll = uiwidgets.scroll_container_update({id = 6102, rect = ctx.panel,
            scroll_y_in = panel_state^.scroll_y, content_height = height,
            mouse_input = ctx.mouse_input, interaction_space_rect = ctx.panel,
            wheel_step = theme.SETTINGS_TOGGLE_ROW_GAP * theme.WHEEL_SCROLL_MULTIPLIER,
            press_owner = ctx.press_owner,
            state_in = {panel_state^.scroll_dragging, panel_state^.scroll_drag_off},
            semantic_focus = ctx.semantic_focus,
            semantic_id = uisemantics.semantic_control_id(.Settings_Control, 6102)})
        panel_state^.scroll_y = scroll.scroll_y_out
        panel_state^.scroll_dragging = scroll.state_out.is_dragging_thumb
        panel_state^.scroll_drag_off = scroll.state_out.drag_offset_y
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
    if state == nil {
        return {}
    }
    ctx := settings_view_context(state, panel, mouse_input)
    scroll := prepare_settings_scroll(ctx, interactive)
    content_panel := scroll.view_rect
    stack_rect := geometry.Rectangle{content_panel.x + theme.SETTINGS_PANEL_INSET,
        content_panel.y + theme.SETTINGS_HEADER_TOP_OFFSET - scroll.scroll_y_out,
        content_panel.width - theme.SETTINGS_PANEL_INSET * 2,
        content_panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack_rect)
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
    case .Rendering_Simd: return simd_available
    case .Rendering_Gpu_Dust_Instancing: return gpu_available
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
