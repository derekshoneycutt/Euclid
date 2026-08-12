package ui_dynview

import "../../../core"
import "../../../dynview"
import view_core "../../core"

import rl "vendor:raylib"


Mouse_Input_State :: view_core.Mouse_Input_State

UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR


Dynview_Text_Alignment :: core.Dynview_Text_Alignment
Dynview_Text_Style :: core.Dynview_Text_Style


//   Fallback wrapped-text layout metrics, grouped so the styled-or-fallback
//   entry point passes typography settings as one coherent value.
Wrapped_Text_Metrics :: struct {
    padding:      f32,
    row_height:   f32,
    wrap_advance: f32,
    font_size:    f32,
}


//   Draw style-aware dynview content, falling back to plain wrapped text when unavailable.
draw_scratchpad_styled_or_fallback :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    fallback_text: string,
    panel: rl.Rectangle,
    scroll_y: f32,
    font: rl.Font,
    metrics: Wrapped_Text_Metrics,
    fallback_text_color: rl.Color) {

    if ui_runtime == nil {
        view_core.draw_wrapped_text_content(fallback_text,
            view_core.Wrapped_Text_Content_Params{
                panel = panel,
                scroll_y = scroll_y,
                font = font,
                text_padding = metrics.padding,
                text_row_height = metrics.row_height,
                text_color = fallback_text_color,
                wrap_advance = metrics.wrap_advance,
                font_size = metrics.font_size,
            })
        return
    }

    runtime := &state^.dynview
    if runtime^.enabled && runtime^.compile_cache.is_valid &&
        !runtime^.command_buffer.has_stream_error &&
        runtime^.command_buffer.command_count > 0 {
        if runtime^.compile_cache.layout_is_valid {
            draw_cached_layout(state,
                runtime,
                panel,
                scroll_y,
                metrics.padding,
                metrics.font_size,
                font)
            return
        }
    }

    view_core.draw_wrapped_text_content(fallback_text,
        view_core.Wrapped_Text_Content_Params{
            panel = panel,
            scroll_y = scroll_y,
            font = font,
            text_padding = metrics.padding,
            text_row_height = metrics.row_height,
            text_color = fallback_text_color,
            wrap_advance = metrics.wrap_advance,
            font_size = metrics.font_size,
        })
}

//   Draw one measured child math program with a shared baseline.
draw_math_program_at :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    program: core.Dynview_Math_Program,
    draw_x, baseline_y: f32) {

    child_x := draw_x
    command_end := program.command_start + program.command_count
    ctx := Layout_Draw_Context{
        state = state,
        runtime = runtime,
        panel = panel,
        font = font,
        font_size = font_size,
    }
    for command_index in program.command_start..<command_end {
        cmd := runtime^.compile_cache.math_commands[command_index]
        child_item, ok := dynview.math_program_item(
            &runtime^.compile_cache,
            &runtime^.command_buffer,
            cmd,
            font_size)
        if !ok {
            continue
        }

        child_y := baseline_y - child_item.ascent
        child_style := dynview.style_by_id(child_item.style_id)
        draw_cached_text_item(ctx, child_style, child_item, child_x, child_y)
        child_x += child_item.draw_width
    }
}
