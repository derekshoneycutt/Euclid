package ui

import native "../native"

import "../../core"
import audiomodel "../../audio/model"
import particlemodel "../../particles/model"
import geometry "../../core/geometry"
import view_core "../core"
import view_font "../font"

import "core:fmt"

//   Shared dependencies for controls in one settings panel frame.
Settings_View_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: Input_Frame,
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
}

//   Fixed prepared interaction results for all settings controls.
Settings_View_Preparation :: struct {
    rows: Settings_View_Rows,
    max_particles: Integer_Slider_Result,
    fps: Checkbox_Result,
    limit: Checkbox_Result,
    sound: Checkbox_Result,
    simd: Checkbox_Result,
    gpu_dust: Checkbox_Result,
}

//   Values unique to one checkbox row in the settings panel.
Settings_Checkbox_Descriptor :: struct {
    row_y: f32,
    id: int,
    label: string,
    checked: bool,
    enabled: bool,
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
        encoder, geometry.Rectangle(rectangle), 1, UI_BORDER_COLOR)
    if !checked {return}
    first := geometry.Vector2{rectangle.x + 3,
        rectangle.y + rectangle.height * 0.55}
    second := geometry.Vector2{rectangle.x + 6,
        rectangle.y + rectangle.height - 3}
    third := geometry.Vector2{rectangle.x + rectangle.width - 3, rectangle.y + 3}
    _ = native.draw_encoder_line(encoder, first, second, 1.6, UI_TEXT_COLOR)
    _ = native.draw_encoder_line(encoder, second, third, 1.6, UI_TEXT_COLOR)
}

// draw_encoded_slider_geometry encodes one slider track, fill, and knob.
draw_encoded_slider_geometry :: proc(
    encoder: ^native.Draw_Encoder, panel: geometry.Rectangle, row_y: f32,
    value, min_value, max_value: int) {
    track := slider_track_rect(geometry.Rectangle(panel), row_y)
    denominator := max(1, max_value - min_value)
    ratio := f32(clamp(value, min_value, max_value) - min_value) /
        f32(denominator)
    knob_center_x, knob := build_slider_knob(track, ratio)
    _ = native.draw_encoder_rectangle(
        encoder, track, BACKGROUND_COLOR)
    fill := geometry.Rectangle{track.x, track.y,
        max(0, knob_center_x - track.x), track.height}
    _ = native.draw_encoder_rectangle(
        encoder, fill, UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle(
        encoder, knob, UI_TEXT_COLOR)
}

// draw_encoded_settings_geometry encodes settings controls without text.
draw_encoded_settings_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    if state == nil || state^.particle_system == nil {return}
    stack_rect := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack_rect)
    draw_encoded_slider_geometry(encoder, panel, rows.slider_label_y,
        state^.particle_system^.use_max_dust_particles,
        0, particlemodel.MAX_LOW_PARTICLES)
    checks := [4]struct{rectangle: geometry.Rectangle, checked: bool}{
        {{
            panel.x + SETTINGS_PANEL_INSET, rows.fps_y,
            SETTINGS_CHECKBOX_SIZE, SETTINGS_CHECKBOX_SIZE
        }, state^.ui_runtime.display_fps},
        {{
            panel.x + SETTINGS_PANEL_INSET, rows.limit_y,
            SETTINGS_CHECKBOX_SIZE, SETTINGS_CHECKBOX_SIZE
        }, state^.ui_runtime.limit_fps},
        {{
            panel.x + SETTINGS_PANEL_INSET, rows.simd_y,
            SETTINGS_CHECKBOX_SIZE, SETTINGS_CHECKBOX_SIZE
        }, state^.ui_runtime.use_simd_batch_projection},
        {{
            panel.x + SETTINGS_PANEL_INSET, rows.gpu_dust_y,
            SETTINGS_CHECKBOX_SIZE, SETTINGS_CHECKBOX_SIZE
        }, state^.ui_runtime.use_gpu_dust_instancing},
    }
    for check in checks {
        draw_encoded_checkbox_geometry(encoder, check.rectangle, check.checked)
    }
}

// draw_encoded_settings_text emits current labels, values, and counters.
draw_encoded_settings_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    stack := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack)
    x := panel.x + SETTINGS_PANEL_INSET
    value := fmt.tprintf("%d", state^.particle_system^.use_max_dust_particles)
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    value_width, measured := view_core.ui_text_measure_monospace(
        value, face, TREE_FONT_SIZE, 0)
    if !measured {value_width = 40}
    draw_encoded_label(state, encoder, "Maximum Dust particles", x, rows.slider_label_y)
    draw_encoded_label(state, encoder, value,
        settings_right_aligned_x(panel, value_width), rows.slider_label_y)
    animation_entries_added := 0
    if state^.julia_interface != nil {
        animation_entries_added = state^.julia_interface^.animation_count
    }
    draw_settings_particle_stats(
        {state = state, panel = panel, font = face,
            font_resolver = view_font.cache_terminal_resolver(&state^.font_cache)},
        rows.stats_y, encoder, animation_entries_added)
    labels := [4]struct{label: string, y: f32}{
        {"Display FPS", rows.fps_y}, {"Limit FPS", rows.limit_y},
        {"Use SIMD Projection", rows.simd_y},
        {"GPU Dust Instancing", rows.gpu_dust_y},
    }
    for item in labels {
        draw_encoded_label(state, encoder, item.label,
            x + SETTINGS_CHECKBOX_SIZE + SETTINGS_CHECKBOX_LABEL_GAP,
            item.y - SETTINGS_CHECKBOX_TEXT_OFFSET_Y)
    }
}

// settings_right_aligned_x keeps one measured value inside the panel inset.
settings_right_aligned_x :: #force_inline proc(
    panel: geometry.Rectangle, text_width: f32) -> f32 {
    return panel.x + panel.width - SETTINGS_PANEL_INSET - max(text_width, 0)
}

//   Build one settings checkbox parameter record from shared row context.
settings_checkbox_params :: proc(
    ctx: Settings_View_Context,
    descriptor: Settings_Checkbox_Descriptor) -> Checkbox_Params {
    return {
        id = descriptor.id,
        rect = geometry.Rectangle{ctx.panel.x + SETTINGS_PANEL_INSET, descriptor.row_y,
            SETTINGS_CHECKBOX_SIZE, SETTINGS_CHECKBOX_SIZE},
        checked = descriptor.checked,
        enabled = descriptor.enabled,
        mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = true,
        label = descriptor.label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }
}

//   Build the maximum-particle slider parameters shared by update and draw.
settings_max_particles_params :: proc(
    ctx: Settings_View_Context,
    row_y: f32) -> Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel),
        row_y = row_y,
        mouse_input = ctx.mouse_input,
        ui_runtime = &ctx.state.ui_runtime,
        press_id = SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        label = "Maximum Dust particles",
        value = &ctx.state.particle_system.use_max_dust_particles,
        min_value = 0,
        max_value = particlemodel.MAX_LOW_PARTICLES,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
    }
}

//   Render particle render-count statistics and Julia animation-entry counts in settings view.
draw_settings_particle_stats :: proc(
    ctx: Settings_View_Context, stats_y: f32,
    encoder: ^native.Draw_Encoder, animation_entries_added: int) {

    ps := ctx.state.particle_system
    labels := [4]string{
        fmt.tprintf("Dust particles Rendered: %d", ps.last_render_low),
        fmt.tprintf("Trail particles Rendered: %d", ps.last_render_mid),
        fmt.tprintf("Flicker particles Rendered: %d", ps.last_render_high),
        fmt.tprintf("Julia animation entries added: %d", animation_entries_added),
    }
    for label, row in labels {
        view_core.ui_text_shaped({
            encoder = encoder,
            resolver = ctx.font_resolver,
            key = .Regular,
            text = label,
            position = {
                ctx.panel.x + SETTINGS_PANEL_INSET,
                stats_y + f32(row)*SETTINGS_STATS_ROW_GAP,
            },
            color = UI_TEXT_COLOR,
            font = view_core.ui_text_font(ctx.font),
        })
    }
}

//   Place one fixed-size settings row and return it with the advanced cursor.
settings_stack_row :: #force_inline proc(
    rect: geometry.Rectangle, segment_size: f32,
    cursor: Stack_Panel_Cursor) -> Stack_Panel_Result {

    return stack_panel_place_segment(Stack_Panel_Params{
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
    stack_cursor := stack_panel_cursor_zero()
    stack_cursor.offset = SETTINGS_SLIDER_LABEL_TOP_OFFSET - SETTINGS_HEADER_TOP_OFFSET

    slider_label_row := settings_stack_row(stack_rect,
        SETTINGS_TRACK_TOP_OFFSET + SETTINGS_STATS_TOP_OFFSET, stack_cursor)
    stats_row := settings_stack_row(stack_rect,
        SETTINGS_TOGGLE_TOP_OFFSET - SETTINGS_STATS_TOP_OFFSET,
        slider_label_row.cursor_out)
    fps_row := settings_stack_row(stack_rect, SETTINGS_TOGGLE_ROW_GAP,
        stats_row.cursor_out)
    limit_row := settings_stack_row(stack_rect, SETTINGS_TOGGLE_ROW_GAP,
        fps_row.cursor_out)
    sound_row := limit_row
    when audiomodel.EXPERIMENTAL_AUDIO_ENABLED {
        sound_row = settings_stack_row(stack_rect, SETTINGS_TOGGLE_ROW_GAP,
            limit_row.cursor_out)
    }
    simd_row := settings_stack_row(stack_rect, SETTINGS_TOGGLE_ROW_GAP,
        sound_row.cursor_out)
    gpu_dust_row := settings_stack_row(stack_rect, 0, simd_row.cursor_out)

    return Settings_View_Rows{
        slider_label_y = slider_label_row.segment_rect.y,
        stats_y = stats_row.segment_rect.y,
        fps_y = fps_row.segment_rect.y,
        limit_y = limit_row.segment_rect.y,
        sound_y = sound_row.segment_rect.y,
        simd_y = simd_row.segment_rect.y,
        gpu_dust_y = gpu_dust_row.segment_rect.y,
    }
}

//   Update every settings control and report optional feature availability.
update_settings_controls :: proc(
    ctx: Settings_View_Context,
    rows: Settings_View_Rows) -> Settings_Control_Update {
    result := Settings_View_Preparation{rows = rows}
    result.max_particles = update_settings_integer_slider(
        settings_max_particles_params(ctx, rows.slider_label_y))
    result.fps = update_checkbox(settings_checkbox_params(ctx, {rows.fps_y,
        4001, "Display FPS", ctx.state.ui_runtime.display_fps, true}),
        &ctx.state.ui_runtime.ui_press_owner)
    result.limit = update_checkbox(settings_checkbox_params(ctx, {rows.limit_y,
        4002, "Limit FPS", ctx.state.ui_runtime.limit_fps, true}),
        &ctx.state.ui_runtime.ui_press_owner)
    when audiomodel.EXPERIMENTAL_AUDIO_ENABLED {
        result.sound = update_checkbox(settings_checkbox_params(ctx, {rows.sound_y,
            4004, "Enable Drawing Sound", ctx.state.user_drawing_sound_enabled, true}),
            &ctx.state.ui_runtime.ui_press_owner)
    }
    simd_available := view_core.simd_batch_projection_available()
    simd_label := "Use SIMD Projection"
    if !simd_available { simd_label = "Use SIMD Projection (Unavailable)" }
    result.simd = update_checkbox(settings_checkbox_params(ctx, {rows.simd_y,
        4003, simd_label, ctx.state.ui_runtime.use_simd_batch_projection,
        simd_available}), &ctx.state.ui_runtime.ui_press_owner)
    gpu_available := ctx.state.ui_runtime.gpu_dust_instancing_available
    gpu_label := "GPU Dust Instancing"
    if !gpu_available { gpu_label = "GPU Dust Instancing (Unavailable)" }
    result.gpu_dust = update_checkbox(settings_checkbox_params(ctx, {rows.gpu_dust_y,
        4005, gpu_label, ctx.state.ui_runtime.use_gpu_dust_instancing,
        gpu_available}), &ctx.state.ui_runtime.ui_press_owner)
    return {result, simd_available, gpu_available}
}

//   Resolve settings controls and commit their values before rendering.
prepare_settings_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: Input_Frame) -> Settings_View_Preparation {
    if state == nil || state.particle_system == nil { return {} }
    stack_rect := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    rows := settings_view_layout_rows(stack_rect)
    ctx := Settings_View_Context{state, panel, mouse_input,
        view_font.cache_borrow(&state.font_cache, .Regular),
        view_font.cache_terminal_resolver(&state.font_cache)}
    update := update_settings_controls(ctx, rows)
    apply_settings_preparation(state, update.prepared,
        update.simd_available, update.gpu_available)
    return update.prepared
}

//   Commit prepared settings toggle results and related display policy.
apply_settings_preparation :: proc(
    state: ^core.Euclid_General_State,
    prepared: Settings_View_Preparation,
    simd_available: bool,
    gpu_available: bool) {
    if prepared.fps.toggled { state.ui_runtime.display_fps = prepared.fps.checked_out }
    if prepared.limit.toggled {
        state.ui_runtime.limit_fps = prepared.limit.checked_out
    }
    when audiomodel.EXPERIMENTAL_AUDIO_ENABLED {
        if prepared.sound.toggled {
            state.user_drawing_sound_enabled = prepared.sound.checked_out
        }
    }
    state.ui_runtime.use_simd_batch_projection =
        simd_available && prepared.simd.checked_out
    state.ui_runtime.use_gpu_dust_instancing =
        gpu_available && prepared.gpu_dust.checked_out
}


