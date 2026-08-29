package ui

import "../../core"
import view_core "../core"
import view_font "../font"

import "core:fmt"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

//   Shared context for one settings toggle checkbox row.
Settings_Toggle_Context :: struct {
    panel : rl.Rectangle,
    row_y : f32,
    mouse_input : Mouse_Input_State,
    ui_runtime : ^core.Euclid_Ui_Runtime_State,
    font : rl.Font,
    font_resolver : view_font.Font_Resolver,
}

//   Shared dependencies for controls in one settings panel frame.
Settings_View_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    font: rl.Font,
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

//   Render particle render-count statistics and Julia animation-entry counts in settings view.
draw_settings_particle_stats :: proc(
    ctx: Settings_View_Context, stats_y: f32,
    animation_entries_added: int) {

    ps := ctx.state.particle_system
    labels := [4]string{
        fmt.tprintf("Dust particles Rendered: %d", ps.last_render_low),
        fmt.tprintf("Trail particles Rendered: %d", ps.last_render_mid),
        fmt.tprintf("Flicker particles Rendered: %d", ps.last_render_high),
        fmt.tprintf("Julia animation entries added: %d", animation_entries_added),
    }
    for label, row in labels {
        view_core.ui_text_shaped({
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

//   Render and handle the Display FPS toggle control.
draw_settings_fps_checkbox :: proc(
    ctx: Settings_View_Context, row_y: f32) {

    box := rl.Rectangle{
        ctx.panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label := "Display FPS"

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4001,
        rect = box,
        checked = ctx.state.ui_runtime.display_fps,
        enabled = true,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        label = label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ctx.state.ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ctx.state.ui_runtime.display_fps = checkbox_result.checked_out
    }
}

//   Render and handle the Limit FPS toggle control.
draw_settings_limit_fps_checkbox :: proc(
    ctx: Settings_View_Context, row_y: f32) {

    box := rl.Rectangle{
        ctx.panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label := "Limit FPS"

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4002,
        rect = box,
        checked = ctx.state.ui_runtime.limit_fps,
        enabled = true,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        label = label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ctx.state.ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ctx.state.ui_runtime.limit_fps = checkbox_result.checked_out
        if checkbox_result.checked_out {
            rl.SetTargetFPS(LIMIT_FPS)
        } else {
            rl.SetTargetFPS(0)
        }
    }
}

//   Draw one settings toggle checkbox, honoring availability and writing the flag.
draw_settings_toggle_checkbox :: proc(
    ctx: Settings_Toggle_Context,
    id: int,
    label: string,
    is_available: bool,
    value: ^bool) {

    panel := ctx.panel
    ui_runtime := ctx.ui_runtime
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        ctx.row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = id,
        rect = box,
        checked = value^,
        enabled = is_available,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        label = label,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        value^ = checkbox_result.checked_out
    }
    if !is_available {
        value^ = false
    }
}

//   Render and handle the SIMD batch projection toggle control.
draw_settings_simd_projection_checkbox :: proc(
    ctx: Settings_View_Context, row_y: f32) {

    is_available := view_core.simd_batch_projection_available()
    label := "Use SIMD Projection"
    if !is_available {
        label = "Use SIMD Projection (Unavailable)"
    }
    draw_settings_toggle_checkbox(
        Settings_Toggle_Context{
            ctx.panel, row_y, ctx.mouse_input, &ctx.state.ui_runtime,
            ctx.font, ctx.font_resolver},
        4003, label, is_available, &ctx.state.ui_runtime.use_simd_batch_projection)
}

//   Render and handle the GPU dust instancing toggle control.
draw_settings_gpu_dust_checkbox :: proc(
    ctx: Settings_View_Context, row_y: f32) {

    is_available := rlgl.GetVersion() >= .OPENGL_33
    label := "GPU Dust Instancing"
    if !is_available {
        label = "GPU Dust Instancing (Unavailable)"
    }
    draw_settings_toggle_checkbox(
        Settings_Toggle_Context{
            ctx.panel, row_y, ctx.mouse_input, &ctx.state.ui_runtime,
            ctx.font, ctx.font_resolver},
        4005, label, is_available, &ctx.state.ui_runtime.use_gpu_dust_instancing)
}

//   Render and handle the drawing sound toggle control.
draw_settings_sound_checkbox :: proc(
    ctx: Settings_View_Context, row_y: f32) {

    box := rl.Rectangle{
        ctx.panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4004,
        rect = box,
        checked = ctx.state.user_drawing_sound_enabled,
        enabled = true,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        label = "Enable Drawing Sound",
        font = ctx.font,
        font_resolver = ctx.font_resolver,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ctx.state.ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ctx.state.user_drawing_sound_enabled = checkbox_result.checked_out
    }
}

//   Place one fixed-size settings row and return it with the advanced cursor.
settings_stack_row :: #force_inline proc(
    rect: rl.Rectangle, segment_size: f32,
    cursor: Stack_Panel_Cursor) -> Stack_Panel_Result {

    return stack_panel_place_segment(Stack_Panel_Params{
        origin_x = rect.x,
        origin_y = rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = segment_size,
        cursor_in = cursor,
    })
}

//   Lay out the settings view rows and return their y-positions.
settings_view_layout_rows :: proc(stack_rect: rl.Rectangle) -> Settings_View_Rows {
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
    sound_row := settings_stack_row(stack_rect, SETTINGS_TOGGLE_ROW_GAP,
        limit_row.cursor_out)
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

//   Draw all settings controls against the laid-out rows.
draw_settings_controls :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    rows: Settings_View_Rows) {

    ps := state.particle_system
    ui_runtime := &state.ui_runtime
    regular_font := view_font.cache_borrow(&state.font_cache, .Regular)
    resolver := view_font.cache_terminal_resolver(&state.font_cache)
    ctx := Settings_View_Context{
        state, panel, mouse_input, regular_font, resolver}

    animation_entries_added := 0
    if state.julia_interface != nil {
        animation_entries_added = state.julia_interface.animation_count
    }
    draw_settings_integer_slider(Integer_Slider_Params{
        panel = panel,
        row_y = rows.slider_label_y,
        mouse_input = mouse_input,
        ui_runtime = ui_runtime,
        press_id = SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        label = "Maximum Dust particles",
        value = &ps.use_max_dust_particles,
        min_value = 0,
        max_value = core.MAX_LOW_PARTICLES,
        font = regular_font,
        font_resolver = resolver,
    })
    draw_settings_particle_stats(ctx, rows.stats_y, animation_entries_added)
    draw_settings_fps_checkbox(ctx, rows.fps_y)
    draw_settings_limit_fps_checkbox(ctx, rows.limit_y)
    draw_settings_sound_checkbox(ctx, rows.sound_y)
    draw_settings_simd_projection_checkbox(ctx, rows.simd_y)
    draw_settings_gpu_dust_checkbox(ctx, rows.gpu_dust_y)
}

//   Render full settings panel and wire all settings controls.
draw_settings_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    if state == nil || state.particle_system == nil {
        return
    }

    _ = draw_container(panel, .Grey)

    header_y := int(panel.y + SETTINGS_HEADER_TOP_OFFSET)
    regular_font := view_font.cache_borrow(&state.font_cache, .Regular)
    resolver := view_font.cache_terminal_resolver(&state.font_cache)
    view_core.ui_text_shaped({
        resolver = resolver,
        key = .Regular,
        text = "Settings",
        position = {panel.x + SETTINGS_PANEL_INSET, f32(header_y)},
        color = UI_TEXT_COLOR,
        font = view_core.ui_text_font(regular_font),
    })

    stack_rect := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET,
    }
    rows := settings_view_layout_rows(stack_rect)
    draw_settings_controls(state, panel, mouse_input, rows)
}

