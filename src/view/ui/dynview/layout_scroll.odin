package dynview

import "../../../core"
import view_core "../../core"

import rl "vendor:raylib"

//   Return fallback wrapped row count for plain-text rendering.
fallback_row_count :: #force_inline proc(
    panel: rl.Rectangle,
    wrap_advance: f32,
    fallback_text: string) -> int {

    max_cols := view_core.chars_per_text_row(panel.width - TEXT_PADDING * 2, wrap_advance)
    return view_core.count_wrapped_text_rows(fallback_text, max_cols)
}

//   Return total content height using cached line metrics, else fallback row math.
scratchpad_content_height_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    text_padding, wrap_advance, fallback_row_height: f32,
    fallback_text: string) -> f32 {

    fallback_rows := fallback_row_count(panel, wrap_advance, fallback_text)
    fallback_height := text_padding * 2 + f32(fallback_rows) * fallback_row_height
    if ui_runtime == nil {
        return fallback_height
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        runtime^.command_buffer.command_count <= 0 {
        return fallback_height
    }

    return text_padding * 2 + runtime^.compile_cache.layout_total_height
}

//   Return scroll step derived from cached line metrics, else fallback to fixed row height.
scratchpad_scroll_step_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    fallback_row_height: f32) -> f32 {

    if ui_runtime == nil {
        return fallback_row_height
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        runtime^.command_buffer.command_count <= 0 {
        return fallback_row_height
    }

    return max(1.0, runtime^.compile_cache.layout_average_line_height)
}
