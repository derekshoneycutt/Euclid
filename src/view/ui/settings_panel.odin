package ui

import "../../core"
import view_core "../core"

import "core:fmt"

import rl "vendor:raylib"

//   Render particle render-count statistics and Julia animation-entry counts in settings view.
draw_settings_particle_stats :: proc(
    panel: rl.Rectangle,
    stats_y: f32,
    ps: ^core.Particle_System,
    animation_entries_added: int,
    font: rl.Font) {

    ui_text(fmt.tprintf("Dust particles Rendered: %d", ps.last_render_low),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y), UI_TEXT_COLOR, font)
    ui_text(fmt.tprintf("Trail particles Rendered: %d", ps.last_render_mid),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y + SETTINGS_STATS_ROW_GAP),
        UI_TEXT_COLOR, font)
    ui_text(fmt.tprintf("Flicker particles Rendered: %d", ps.last_render_high),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y + SETTINGS_STATS_ROW_GAP * 2),
        UI_TEXT_COLOR, font)
    ui_text(fmt.tprintf("Julia animation entries added: %d", animation_entries_added),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y + SETTINGS_STATS_ROW_GAP * 3),
        UI_TEXT_COLOR, font)
}

//   Render and handle the Display FPS toggle control.
draw_settings_fps_checkbox :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse_input: Mouse_Input_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label := "Display FPS"

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4001,
        rect = box,
        checked = ui_runtime.display_fps,
        enabled = true,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        label = label,
        font = font,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ui_runtime.display_fps = checkbox_result.checked_out
    }
}

//   Render and handle the Limit FPS toggle control.
draw_settings_limit_fps_checkbox :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse_input: Mouse_Input_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label := "Limit FPS"

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4002,
        rect = box,
        checked = ui_runtime.limit_fps,
        enabled = true,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        label = label,
        font = font,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ui_runtime.limit_fps = checkbox_result.checked_out
        if checkbox_result.checked_out {
            rl.SetTargetFPS(LIMIT_FPS)
        } else {
            rl.SetTargetFPS(0)
        }
    }
}

//   Render and handle the SIMD batch projection toggle control.
draw_settings_simd_projection_checkbox :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse_input: Mouse_Input_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    is_available := view_core.simd_batch_projection_available()
    label := "Use SIMD Projection"
    if !is_available {
        label = "Use SIMD Projection (Unavailable)"
    }

    checkbox_result := draw_checkbox(Checkbox_Params{
        id = 4003,
        rect = box,
        checked = ui_runtime.use_simd_batch_projection,
        enabled = is_available,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        label = label,
        font = font,
        label_font_size = TREE_FONT_SIZE,
        label_offset_x = SETTINGS_CHECKBOX_LABEL_GAP,
        label_offset_y = -SETTINGS_CHECKBOX_TEXT_OFFSET_Y,
    }, &ui_runtime.ui_press_owner)
    if checkbox_result.toggled {
        ui_runtime.use_simd_batch_projection = checkbox_result.checked_out
    }
    if !is_available {
        ui_runtime.use_simd_batch_projection = false
    }
}

//   Render full settings panel and wire all settings controls.
draw_settings_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    if state == nil || state.particle_system == nil {
        return
    }

    ps := state.particle_system
    ui_runtime := &state.ui_runtime
    font := state.font

    _ = draw_container(panel, .Grey)

    header_y := int(panel.y + SETTINGS_HEADER_TOP_OFFSET)
    ui_text("Settings", int(panel.x + SETTINGS_PANEL_INSET), header_y, UI_TEXT_COLOR, font)

    stack_rect := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET,
    }
    stack_cursor := stack_panel_cursor_zero()
    stack_cursor.offset = SETTINGS_SLIDER_LABEL_TOP_OFFSET - SETTINGS_HEADER_TOP_OFFSET

    slider_label_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_TRACK_TOP_OFFSET + SETTINGS_STATS_TOP_OFFSET,
        cursor_in = stack_cursor,
    })
    stack_cursor = slider_label_row.cursor_out

    stats_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_TOGGLE_TOP_OFFSET - SETTINGS_STATS_TOP_OFFSET,
        cursor_in = stack_cursor,
    })
    stack_cursor = stats_row.cursor_out

    fps_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_TOGGLE_ROW_GAP,
        cursor_in = stack_cursor,
    })
    stack_cursor = fps_row.cursor_out

    limit_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_TOGGLE_ROW_GAP,
        cursor_in = stack_cursor,
    })
    stack_cursor = limit_row.cursor_out

    simd_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = 0,
        cursor_in = stack_cursor,
    })

    max_particles := core.MAX_LOW_PARTICLES
    animation_entries_added := 0
    if state.julia_interface != nil {
        animation_entries_added = state.julia_interface.next_animation_index
    }
    draw_settings_integer_slider(
        panel,
        slider_label_row.segment_rect.y,
        mouse_input,
        ui_runtime,
        SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID,
        "Maximum Dust particles",
        &ps.use_max_dust_particles,
        0,
        max_particles,
        font)
    draw_settings_particle_stats(panel, stats_row.segment_rect.y, ps, animation_entries_added, font)
    draw_settings_fps_checkbox(panel, fps_row.segment_rect.y, mouse_input, ui_runtime, font)
    draw_settings_limit_fps_checkbox(panel, limit_row.segment_rect.y, mouse_input, ui_runtime, font)
    draw_settings_simd_projection_checkbox(panel, simd_row.segment_rect.y, mouse_input, ui_runtime, font)
}

