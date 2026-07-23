package ui

import "../../core"
import "core:math"

import rl "vendor:raylib"

DYNVIEW_INVALIDATE_CONTENT :: u32(1 << 0)
DYNVIEW_INVALIDATE_PANEL :: u32(1 << 1)
DYNVIEW_INVALIDATE_FONT :: u32(1 << 2)
DYNVIEW_INVALIDATE_STYLE :: u32(1 << 3)

DYNVIEW_STYLE_REVISION_PLAIN_TEXT :: u64(2)

DYNVIEW_STYLE_DEFAULT :: i32(0)
DYNVIEW_STYLE_PROMPT :: i32(1)
DYNVIEW_STYLE_OUTPUT :: i32(2)
DYNVIEW_STYLE_ERROR :: i32(3)
DYNVIEW_STYLE_BOLD :: i32(10)
DYNVIEW_STYLE_ITALIC :: i32(11)
DYNVIEW_STYLE_CENTER :: i32(12)
DYNVIEW_STYLE_INLINE_ATOM :: i32(20)

DYNVIEW_ENABLED_DEFAULT :: true

DYNVIEW_STATUS_OK :: i32(0)
DYNVIEW_STATUS_INVALID_ARGUMENT :: i32(2)
DYNVIEW_STATUS_OUT_OF_CAPACITY :: i32(5)
DYNVIEW_STATUS_ILLEGAL_STATE :: i32(6)

Dynview_Text_Style :: struct {
    color: rl.Color,
    centered: bool,
    bold: bool,
    italic: bool,
    wrap_scale: f32,
}

Dynview_Compile_State :: struct {
    open_block: bool,
    block_id: i32,
    block_kind: i32,
    block_row_start: int,
    block_row_end: int,
    block_payload_start: int,
    block_has_copy_payload: bool,
    current_row: int,
}

Dynview_Flow_State :: struct {
    row: int,
    col: int,
    had_visible: bool,
}

Dynview_Draw_Context :: struct {
    enabled: bool,
    panel: rl.Rectangle,
    scroll_y: f32,
    text_padding: f32,
    text_row_height: f32,
    wrap_advance: f32,
    font_size: f32,
    font: rl.Font,
}

//   Return style-adjusted horizontal advance for one column unit.
dynview_effective_advance :: #force_inline proc(style: Dynview_Text_Style, wrap_advance: f32) -> f32 {
    return max(1.0, wrap_advance * max(0.5, style.wrap_scale))
}

//   Advance flow cursor to the next row when no columns remain in current row.
dynview_wrap_if_full :: #force_inline proc(flow: ^Dynview_Flow_State, max_cols: int) {
    if max_cols <= 0 {
        return
    }

    if flow^.col >= max_cols {
        flow^.row += 1
        flow^.col = 0
    }
}

//   Measure inline-line command in columns with bounded minimum/maximum spans.
dynview_inline_line_cols :: #force_inline proc(
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    max_cols: int) -> int {

    if max_cols <= 0 {
        return 1
    }

    length_in_cols := cmd.inline_atom_dimension
    if length_in_cols <= 0 {
        length_in_cols = 1
    }

    // length is expressed in wrap-column units and scaled by style metrics.
    scaled := f64(length_in_cols * max(0.5, style.wrap_scale))
    cols := int(math.ceil(scaled))
    if cols < 1 {
        cols = 1
    }
    if cols > max_cols {
        cols = max_cols
    }
    return cols
}

//   Measure inline-box command in columns with bounded minimum/maximum spans.
dynview_inline_box_cols :: #force_inline proc(
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    if max_cols <= 0 {
        return 1
    }

    width_in_cols := cmd.inline_atom_dimension
    if width_in_cols <= 0 {
        width_in_cols = 1
    }

    scaled := f64(width_in_cols * max(0.5, style.wrap_scale))
    cols := int(math.ceil(scaled))
    if cols < 1 {
        cols = 1
    }
    if cols > max_cols {
        cols = max_cols
    }
    return cols
}

//   Measure inline-circle command in columns with bounded minimum/maximum spans.
dynview_inline_circle_cols :: #force_inline proc(
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    if max_cols <= 0 {
        return 1
    }

    diameter_in_cols := cmd.inline_atom_dimension * 2
    if diameter_in_cols <= 0 {
        diameter_in_cols = 1
    }

    scaled := f64(diameter_in_cols * max(0.5, style.wrap_scale))
    cols := int(math.ceil(scaled))
    if cols < 1 {
        cols = 1
    }
    if cols > max_cols {
        cols = max_cols
    }
    return cols
}

//   Consume one text run in flow layout, optionally drawing each wrapped segment.
dynview_flow_consume_text_run :: proc(
    flow: ^Dynview_Flow_State,
    text: string,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    if len(text) <= 0 {
        return
    }

    max_cols := dynview_chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)

    if max_cols <= 0 {
        max_cols = 1
    }

    start := 0
    for start < len(text) {
        dynview_wrap_if_full(flow, max_cols)

        available := max_cols - flow^.col
        if available <= 0 {
            flow^.row += 1
            flow^.col = 0
            continue
        }

        line_start, line_end, next_start := next_wrapped_text_span(text, start, available)
        line_text := text[line_start:line_end]
        line_len := len(line_text)
        if line_len <= 0 {
            break
        }

        if draw_ctx^.enabled {
            row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
                f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
            if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
                row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

                line_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                    f32(flow^.col) * dynview_effective_advance(style, draw_ctx^.wrap_advance)
                if style.centered && flow^.col == 0 {
                    line_w := f32(line_len) * dynview_effective_advance(style, draw_ctx^.wrap_advance)
                    line_x = draw_ctx^.panel.x + (draw_ctx^.panel.width - line_w) * 0.5
                }

                if style.bold {
                    ui_text(line_text,
                        int(line_x + 1),
                        int(row_y),
                        style.color,
                        draw_ctx^.font,
                        draw_ctx^.font_size)
                }

                if style.italic {
                    line_x += 1
                }

                ui_text(line_text,
                    int(line_x),
                    int(row_y),
                    style.color,
                    draw_ctx^.font,
                    draw_ctx^.font_size)
            }
        }

        flow^.had_visible = true
        flow^.col += line_len

        if next_start < len(text) {
            flow^.row += 1
            flow^.col = 0
        }

        if next_start <= start {
            break
        }
        start = next_start
    }
}

//   Consume one inline-line atom in flow layout, optionally drawing it.
dynview_flow_consume_inline_line :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview_chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview_inline_line_cols(cmd, style, draw_ctx^.wrap_advance, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview_effective_advance(style, draw_ctx^.wrap_advance)
            line_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            line_w := f32(cols) * effective_advance
            baseline_y := row_y + draw_ctx^.text_row_height * 0.62
            thickness := max(1.0, cmd.inline_atom_stroke)
            start_pos := rl.Vector2{line_x, baseline_y}
            end_pos := rl.Vector2{line_x + line_w, baseline_y}
            rl.DrawLineEx(start_pos, end_pos, thickness, style.color)
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    dynview_wrap_if_full(flow, max_cols)
}

//   Consume one inline-box atom in flow layout, optionally drawing it.
dynview_flow_consume_inline_box :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview_chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview_inline_box_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview_effective_advance(style, draw_ctx^.wrap_advance)
            box_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            box_w := f32(cols) * effective_advance
            raw_h := cmd.inline_box_height * effective_advance
            box_h := max(4.0, min(draw_ctx^.text_row_height - 3, raw_h))
            box_y := row_y + (draw_ctx^.text_row_height - box_h) * 0.5
            stroke := max(1.0, cmd.inline_atom_stroke)
            rl.DrawRectangleLinesEx(rl.Rectangle{box_x, box_y, box_w, box_h}, stroke, style.color)
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    dynview_wrap_if_full(flow, max_cols)
}

//   Consume one inline-circle atom in flow layout, optionally drawing it.
dynview_flow_consume_inline_circle :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview_chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview_inline_circle_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview_effective_advance(style, draw_ctx^.wrap_advance)
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y + draw_ctx^.text_row_height * 0.58}
            stroke := max(1.0, cmd.inline_atom_stroke)
            rl.DrawCircleLines(i32(center.x), i32(center.y), radius, style.color)
            if stroke > 1 {
                rl.DrawCircleLines(i32(center.x), i32(center.y), max(1.0, radius - 1), style.color)
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    dynview_wrap_if_full(flow, max_cols)
}

//   Resolve a style id using a fixed host-owned table.
dynview_style_by_id :: #force_inline proc(style_id: i32) -> Dynview_Text_Style {
    switch style_id {
    case DYNVIEW_STYLE_PROMPT:
        return Dynview_Text_Style{
            color = rl.Color{186, 198, 228, 255},
            wrap_scale = 1.02,
        }
    case DYNVIEW_STYLE_OUTPUT:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            wrap_scale = 1.0,
        }
    case DYNVIEW_STYLE_ERROR:
        return Dynview_Text_Style{
            color = rl.Color{220, 95, 95, 255},
            wrap_scale = 1.03,
        }
    case DYNVIEW_STYLE_BOLD:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            bold = true,
            wrap_scale = 1.12,
        }
    case DYNVIEW_STYLE_ITALIC:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            italic = true,
            wrap_scale = 1.07,
        }
    case DYNVIEW_STYLE_CENTER:
        return Dynview_Text_Style{
            color = UI_TEXT_COLOR,
            centered = true,
            wrap_scale = 1.0,
        }
    case DYNVIEW_STYLE_INLINE_ATOM:
        return Dynview_Text_Style{
            color = rl.Color{170, 190, 218, 255},
            wrap_scale = 1.0,
        }
    }

    return Dynview_Text_Style{
        color = UI_TEXT_COLOR,
        wrap_scale = 1.0,
    }
}

//   Return max wrapped chars for a style using style-aware wrap scale.
dynview_chars_per_row_for_style :: #force_inline proc(
    panel_width, text_padding, wrap_advance: f32,
    style: Dynview_Text_Style) -> int {

    effective_advance := max(1.0, wrap_advance * max(0.5, style.wrap_scale))
    return chars_per_text_row(panel_width - text_padding * 2, effective_advance)
}

//   Compute style-aware row count for one text command payload.
dynview_count_rows_for_run :: #force_inline proc(
    text: string,
    panel_width, text_padding, wrap_advance: f32,
    style: Dynview_Text_Style) -> int {

    max_chars := dynview_chars_per_row_for_style(panel_width, text_padding, wrap_advance, style)
    return count_wrapped_text_rows(text, max_chars)
}

//   Extract text slice from one text run command.
dynview_text_for_command :: #force_inline proc(
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command) -> string {

    if cmd.text_offset < 0 || cmd.text_len < 0 {
        return ""
    }
    if cmd.text_offset + cmd.text_len > buffer^.text_bytes_len {
        return ""
    }
    return string(buffer^.text_bytes[cmd.text_offset:cmd.text_offset + cmd.text_len])
}

//   Build style-aware row spans for copy-enabled blocks using current panel metrics.
dynview_update_copy_block_row_spans :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel_width, text_padding, wrap_advance: f32) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    if cache^.copy_block_count <= 0 {
        return
    }

    flow := Dynview_Flow_State{}
    draw_ctx := Dynview_Draw_Context{
        panel = {0, 0, panel_width, 0},
        text_padding = text_padding,
        text_row_height = 1,
        wrap_advance = wrap_advance,
    }
    active_copy_index := -1
    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        switch cmd.kind {
        case .BeginBlock:
            active_copy_index = -1
            for j in 0..<cache^.copy_block_count {
                if cache^.copy_blocks[j].block_id == cmd.block_id {
                    active_copy_index = j
                    cache^.copy_blocks[j].row_start = flow.row
                    cache^.copy_blocks[j].row_end = flow.row
                    break
                }
            }
        case .TextRun:
            text := dynview_text_for_command(buffer, cmd)
            dynview_flow_consume_text_run(&flow, text, dynview_style_by_id(cmd.style_id), &draw_ctx)

            if active_copy_index >= 0 {
                cache^.copy_blocks[active_copy_index].row_end = flow.row
            }
        case .InlineLine:
            dynview_flow_consume_inline_line(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
            if active_copy_index >= 0 {
                cache^.copy_blocks[active_copy_index].row_end = flow.row
            }
        case .InlineBox:
            dynview_flow_consume_inline_box(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
            if active_copy_index >= 0 {
                cache^.copy_blocks[active_copy_index].row_end = flow.row
            }
        case .InlineCircle:
            dynview_flow_consume_inline_circle(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
            if active_copy_index >= 0 {
                cache^.copy_blocks[active_copy_index].row_end = flow.row
            }
        case .LineBreak, .Divider:
            if active_copy_index >= 0 {
                // Keep span bound to the last content row; do not include the newly advanced row.
                if cache^.copy_blocks[active_copy_index].row_end < flow.row {
                    cache^.copy_blocks[active_copy_index].row_end = flow.row
                }
            }
            flow.row += 1
            flow.col = 0
        case .EndBlock:
            active_copy_index = -1
        case .CopyableTextRun:
            // Copy payload does not affect visible row placement directly.
        }
    }
}

//   Draw one styled wrapped text line run with bounded visual traits.
dynview_draw_styled_line :: #force_inline proc(
    text: string,
    panel: rl.Rectangle,
    row_y, text_padding, wrap_advance, font_size: f32,
    font: rl.Font,
    style: Dynview_Text_Style) {

    line_x := panel.x + text_padding
    if style.centered {
        line_w := f32(len(text)) * wrap_advance * max(0.5, style.wrap_scale)
        line_x = panel.x + (panel.width - line_w) * 0.5
    }

    if style.bold {
        ui_text(text, int(line_x + 1), int(row_y), style.color, font, font_size)
    }
    if style.italic {
        line_x += 1
    }
    ui_text(text, int(line_x), int(row_y), style.color, font, font_size)
}

//   Count total style-aware rows from validated dynview command stream.
dynview_count_styled_rows :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel_width, text_padding, wrap_advance: f32) -> int {

    if runtime == nil {
        return 1
    }

    buffer := &runtime^.command_buffer
    if buffer^.command_count <= 0 {
        return 1
    }

    flow := Dynview_Flow_State{}
    draw_ctx := Dynview_Draw_Context{
        panel = {0, 0, panel_width, 0},
        text_padding = text_padding,
        text_row_height = 1,
        wrap_advance = wrap_advance,
    }
    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        switch cmd.kind {
        case .TextRun:
            text := dynview_text_for_command(buffer, cmd)
            dynview_flow_consume_text_run(&flow, text, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineLine:
            dynview_flow_consume_inline_line(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineBox:
            dynview_flow_consume_inline_box(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineCircle:
            dynview_flow_consume_inline_circle(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .LineBreak, .Divider:
            flow.row += 1
            flow.col = 0
        case .BeginBlock, .EndBlock, .CopyableTextRun:
        }
    }

    if !flow.had_visible && flow.row == 0 {
        return 1
    }
    return flow.row + 1
}

//   Draw style-aware wrapped dynview text content clipped by caller scissor.
dynview_draw_styled_content :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    scroll_y, text_padding, text_row_height, wrap_advance, font_size: f32,
    font: rl.Font) {

    if runtime == nil {
        return
    }

    buffer := &runtime^.command_buffer
    flow := Dynview_Flow_State{}
    draw_ctx := Dynview_Draw_Context{
        enabled = true,
        panel = panel,
        scroll_y = scroll_y,
        text_padding = text_padding,
        text_row_height = text_row_height,
        wrap_advance = wrap_advance,
        font_size = font_size,
        font = font,
    }
    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        switch cmd.kind {
        case .TextRun:
            text := dynview_text_for_command(buffer, cmd)
            dynview_flow_consume_text_run(&flow, text, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineLine:
            dynview_flow_consume_inline_line(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineBox:
            dynview_flow_consume_inline_box(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .InlineCircle:
            dynview_flow_consume_inline_circle(&flow, cmd, dynview_style_by_id(cmd.style_id), &draw_ctx)
        case .LineBreak, .Divider:
            flow.row += 1
            flow.col = 0
        case .BeginBlock, .EndBlock, .CopyableTextRun:
        }
    }
}

//   Toggle dynview runtime and mark all compile inputs dirty on mode change.
dynview_set_enabled :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State, enabled: bool) {
    if ui_runtime == nil {
        return
    }

    runtime := &ui_runtime^.dynview_runtime
    if runtime^.enabled == enabled {
        return
    }

    runtime^.enabled = enabled
    dynview_invalidate(runtime,
        DYNVIEW_INVALIDATE_CONTENT |
        DYNVIEW_INVALIDATE_PANEL |
        DYNVIEW_INVALIDATE_FONT |
        DYNVIEW_INVALIDATE_STYLE)
}

//   Mark compile cache invalid and accumulate invalidation reasons.
dynview_invalidate :: proc(runtime: ^core.Ui_Dynview_Runtime, mask: u32) {
    if runtime == nil {
        return
    }

    runtime^.pending_invalidation_mask |= mask
    runtime^.compile_cache.is_valid = false
}

//   Reset per-frame command storage while advancing stream revision.
dynview_reset_command_buffer :: proc(runtime: ^core.Ui_Dynview_Runtime) {
    if runtime == nil {
        return
    }

    runtime^.command_buffer.command_count = 0
    runtime^.command_buffer.text_bytes_len = 0
    runtime^.command_buffer.has_stream_error = false
    runtime^.command_buffer.stream_open_block = false
    runtime^.command_buffer.stream_open_block_id = -1
    runtime^.compile_cache.copy_hit_target_count = 0
    runtime^.command_buffer.revision += 1
}

//   Mark stream invalid and preserve first error code for diagnostics/fallback.
dynview_mark_stream_error :: proc(runtime: ^core.Ui_Dynview_Runtime, code: i32) {
    if runtime == nil {
        return
    }

    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == DYNVIEW_STATUS_OK {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
}

//   Compute a stable FNV-1a hash used for content-change tracking.
dynview_hash_text :: proc(text: string) -> u64 {
    hash: u64 = 1469598103934665603
    for b in text {
        hash = (hash ~ u64(b)) * 1099511628211
    }
    return hash
}

//   Track text content keys and invalidate when text identity changes.
dynview_track_content :: proc(runtime: ^core.Ui_Dynview_Runtime, text: string) {
    if runtime == nil {
        return
    }

    content_hash := dynview_hash_text(text)
    content_len := len(text)
    cache := &runtime^.compile_cache
    if content_hash == cache^.last_content_hash && content_len == cache^.last_content_len {
        return
    }

    cache^.last_content_hash = content_hash
    cache^.last_content_len = content_len
    dynview_invalidate(runtime, DYNVIEW_INVALIDATE_CONTENT)
}

//   Track panel dimensions and invalidate when layout bounds change.
dynview_track_panel :: proc(runtime: ^core.Ui_Dynview_Runtime, panel: rl.Rectangle) {
    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if panel.width == cache^.last_panel_width && panel.height == cache^.last_panel_height {
        return
    }

    cache^.last_panel_width = panel.width
    cache^.last_panel_height = panel.height
    dynview_invalidate(runtime, DYNVIEW_INVALIDATE_PANEL)
}

//   Track font/wrap metrics and invalidate when text layout metrics shift.
dynview_track_font :: proc(runtime: ^core.Ui_Dynview_Runtime, font_size, wrap_advance: f32) {
    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if font_size == cache^.last_font_size && wrap_advance == cache^.last_wrap_advance {
        return
    }

    cache^.last_font_size = font_size
    cache^.last_wrap_advance = wrap_advance
    dynview_invalidate(runtime, DYNVIEW_INVALIDATE_FONT)
}

//   Track style schema version and invalidate when style mapping changes.
dynview_track_style :: proc(runtime: ^core.Ui_Dynview_Runtime, style_revision: u64) {
    if runtime == nil {
        return
    }

    if runtime^.compile_cache.last_style_revision == style_revision {
        return
    }

    runtime^.compile_cache.last_style_revision = style_revision
    dynview_invalidate(runtime, DYNVIEW_INVALIDATE_STYLE)
}

//   Append one byte to compiled plain-text cache and report capacity errors.
dynview_append_compiled_byte :: proc(cache: ^core.Ui_Dynview_Compile_Cache, b: u8) -> i32 {
    if cache^.compiled_plain_text_len >= len(cache^.compiled_plain_text) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    cache^.compiled_plain_text[cache^.compiled_plain_text_len] = b
    cache^.compiled_plain_text_len += 1
    return DYNVIEW_STATUS_OK
}

//   Copy one command text slice into compiled plain-text cache with bounds checks.
dynview_append_compiled_text_slice :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    if offset + count > buffer^.text_bytes_len {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    for i in 0..<count {
        status := dynview_append_compiled_byte(cache, buffer^.text_bytes[offset + i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return DYNVIEW_STATUS_OK
}

//   Append one byte to compiled copy payload cache and report capacity errors.
dynview_append_copy_payload_byte :: proc(cache: ^core.Ui_Dynview_Compile_Cache, b: u8) -> i32 {
    if cache^.compiled_copy_payload_len >= len(cache^.compiled_copy_payload) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    cache^.compiled_copy_payload[cache^.compiled_copy_payload_len] = b
    cache^.compiled_copy_payload_len += 1
    return DYNVIEW_STATUS_OK
}

//   Copy one command copy-text slice into compiled copy payload cache.
dynview_append_copy_payload_slice :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    if offset + count > buffer^.text_bytes_len {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    for i in 0..<count {
        status := dynview_append_copy_payload_byte(cache, buffer^.text_bytes[offset + i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return DYNVIEW_STATUS_OK
}

//   Require an open block before consuming block-scoped content commands.
dynview_require_open_block :: #force_inline proc(open_block: bool) -> i32 {
    if open_block {
        return DYNVIEW_STATUS_OK
    }
    return DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Apply begin-block ordering rule.
dynview_compile_begin_block :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    if state^.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    state^.open_block = true
    state^.block_id = cmd.block_id
    state^.block_kind = cmd.style_id
    state^.block_row_start = state^.current_row
    state^.block_row_end = state^.current_row
    state^.block_payload_start = cache^.compiled_copy_payload_len
    state^.block_has_copy_payload = false
    return DYNVIEW_STATUS_OK
}

//   Apply end-block ordering rule.
dynview_compile_end_block :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    if !state^.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    if state^.block_has_copy_payload {
        if cache^.copy_block_count >= len(cache^.copy_blocks) {
            return DYNVIEW_STATUS_OUT_OF_CAPACITY
        }

        payload_len := cache^.compiled_copy_payload_len - state^.block_payload_start
        cache^.copy_blocks[cache^.copy_block_count] = core.Ui_Dynview_Copy_Block{
            block_id = state^.block_id,
            block_kind = state^.block_kind,
            row_start = state^.block_row_start,
            row_end = state^.block_row_end,
            payload_offset = state^.block_payload_start,
            payload_len = payload_len,
        }
        cache^.copy_block_count += 1
    }

    state^.open_block = false
    return DYNVIEW_STATUS_OK
}

//   Apply text-run compilation rule.
dynview_compile_text_run :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    state^.block_row_end = state^.current_row
    return dynview_append_compiled_text_slice(cache, buffer, cmd.text_offset, cmd.text_len)
}

//   Apply copyable-run compilation rule.
dynview_compile_copyable_text_run :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = dynview_append_copy_payload_slice(cache, buffer, cmd.copy_text_offset, cmd.copy_text_len)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.copy_text_len > 0 {
        state^.block_has_copy_payload = true
    }
    return DYNVIEW_STATUS_OK
}

//   Apply inline-line compilation rule.
dynview_compile_inline_line :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-box compilation rule.
dynview_compile_inline_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-circle compilation rule.
dynview_compile_inline_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply newline-like command rule shared by line-break and divider.
dynview_compile_newline_command :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    status := dynview_require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = dynview_append_compiled_byte(cache, '\n')
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if state^.block_has_copy_payload {
        status = dynview_append_copy_payload_byte(cache, '\n')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    state^.current_row += 1
    return DYNVIEW_STATUS_OK
}

//   Compile one command into cache and enforce the ordering contract.
dynview_compile_command :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Ui_Dynview_Command) -> i32 {

    switch cmd.kind {
    case .BeginBlock:
        return dynview_compile_begin_block(cache, state, cmd)
    case .EndBlock:
        return dynview_compile_end_block(cache, state)
    case .TextRun:
        return dynview_compile_text_run(cache, buffer, state, cmd)
    case .CopyableTextRun:
        return dynview_compile_copyable_text_run(cache, buffer, state, cmd)
    case .LineBreak:
        return dynview_compile_newline_command(cache, state)
    case .Divider:
        return dynview_compile_newline_command(cache, state)
    case .InlineLine:
        return dynview_compile_inline_line(state, cmd)
    case .InlineBox:
        return dynview_compile_inline_box(state, cmd)
    case .InlineCircle:
        return dynview_compile_inline_circle(state, cmd)
    }

    return DYNVIEW_STATUS_INVALID_ARGUMENT
}

//   Validate ordering contract and materialize stream text for host rendering.
dynview_rebuild_compiled_plain_text :: proc(runtime: ^core.Ui_Dynview_Runtime) -> i32 {
    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    cache^.compiled_plain_text_len = 0
    cache^.compiled_copy_payload_len = 0
    cache^.copy_block_count = 0
    cache^.copy_hit_target_count = 0

    compile_state := Dynview_Compile_State{}
    for i in 0..<buffer^.command_count {
        status := dynview_compile_command(cache, buffer, &compile_state, buffer^.commands[i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    if compile_state.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }
    return DYNVIEW_STATUS_OK
}

//   Rebuild scratchpad copy icon hit targets from compiled copy blocks.
dynview_rebuild_copy_hit_targets :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    scroll_y, text_padding, row_height, icon_size, icon_x_pad: f32) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    cache^.copy_hit_target_count = 0
    if !cache^.is_valid {
        return
    }

    dynview_update_copy_block_row_spans(runtime, panel.width, text_padding, cache^.last_wrap_advance)

    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    for i in 0..<cache^.copy_block_count {
        block := cache^.copy_blocks[i]
        row_top := panel.y + text_padding + f32(block.row_start) * row_height - scroll_y
        row_bottom := panel.y + text_padding + f32(block.row_end + 1) * row_height - scroll_y
        if row_bottom < panel_top || row_top > panel_bottom {
            continue
        }
        if cache^.copy_hit_target_count >= len(cache^.copy_hit_targets) {
            break
        }

        visible_top := max(row_top, panel_top)
        visible_bottom := min(row_bottom, panel_bottom)
        hover_rect := rl.Rectangle{
            panel.x + text_padding,
            visible_top,
            max(0.0, panel.width - text_padding * 2),
            max(0.0, visible_bottom - visible_top),
        }
        if hover_rect.height <= 0 || hover_rect.width <= 0 {
            continue
        }

        icon_x := panel.x + panel.width - text_padding - icon_size - icon_x_pad
        icon_y := max(panel_top + 1, min(row_top + 2, panel_bottom - icon_size - 1))
        cache^.copy_hit_targets[cache^.copy_hit_target_count] = core.Ui_Dynview_Copy_Hit_Target{
            block_id = block.block_id,
            payload_offset = block.payload_offset,
            payload_len = block.payload_len,
            rect = {icon_x, icon_y, icon_size, icon_size},
            hover_rect = hover_rect,
        }
        cache^.copy_hit_target_count += 1
    }
}

//   Return compiled copy payload string for one hit target index.
dynview_copy_target_payload :: proc(runtime: ^core.Ui_Dynview_Runtime, target_index: int) -> string {
    if runtime == nil {
        return ""
    }

    cache := &runtime^.compile_cache
    if target_index < 0 || target_index >= cache^.copy_hit_target_count {
        return ""
    }

    target := cache^.copy_hit_targets[target_index]
    if target.payload_offset < 0 || target.payload_len <= 0 {
        return ""
    }
    if target.payload_offset + target.payload_len > cache^.compiled_copy_payload_len {
        return ""
    }

    return string(cache^.compiled_copy_payload[target.payload_offset:target.payload_offset + target.payload_len])
}

//   Compile command buffer metadata plus plain-text stream projection when needed.
dynview_compile_if_needed :: proc(runtime: ^core.Ui_Dynview_Runtime) {
    if runtime == nil || !runtime^.enabled {
        return
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    should_compile := !cache^.is_valid || runtime^.pending_invalidation_mask != 0
    should_compile = should_compile || cache^.compiled_revision != buffer^.revision
    if !should_compile {
        return
    }

    cache^.last_error_code = DYNVIEW_STATUS_OK
    status := dynview_rebuild_compiled_plain_text(runtime)
    cache^.compiled_revision = buffer^.revision
    cache^.compiled_command_count = buffer^.command_count
    cache^.compiled_text_bytes_len = buffer^.text_bytes_len
    cache^.last_invalidation_mask = runtime^.pending_invalidation_mask
    runtime^.pending_invalidation_mask = 0

    if status != DYNVIEW_STATUS_OK {
        dynview_mark_stream_error(runtime, status)
        cache^.copy_hit_target_count = 0
        return
    }

    buffer^.has_stream_error = false
    cache^.is_valid = true
}

//   Compile scratchpad stream and return compiled text when validation succeeds.
dynview_compiled_scratchpad_text_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    font_size, wrap_advance: f32,
    style_revision: u64,
    fallback_text: string) -> string {

    if ui_runtime == nil {
        return fallback_text
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled {
        return fallback_text
    }

    dynview_track_panel(runtime, panel)
    dynview_track_font(runtime, font_size, wrap_advance)
    dynview_track_style(runtime, style_revision)
    dynview_compile_if_needed(runtime)

    if !runtime^.compile_cache.is_valid || runtime^.command_buffer.has_stream_error {
        return fallback_text
    }

    text_len := runtime^.compile_cache.compiled_plain_text_len
    return string(runtime^.compile_cache.compiled_plain_text[:text_len])
}

//   Recompute copy hit-target cache for the current scratchpad panel and scroll.
dynview_refresh_scratchpad_copy_targets :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    scroll_y, text_padding, row_height, icon_size, icon_x_pad: f32) {

    if ui_runtime == nil {
        return
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled {
        runtime^.compile_cache.copy_hit_target_count = 0
        return
    }

    dynview_rebuild_copy_hit_targets(runtime,
        panel, scroll_y, text_padding, row_height, icon_size, icon_x_pad)
}

//   Return style-aware row count when dynview compiled stream is valid.
dynview_scratchpad_styled_rows_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    text_padding, wrap_advance: f32,
    fallback_text: string) -> int {

    if ui_runtime == nil {
        return count_wrapped_text_rows(fallback_text,
            chars_per_text_row(panel.width - text_padding * 2, wrap_advance))
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled || !runtime^.compile_cache.is_valid || runtime^.command_buffer.has_stream_error {
        return count_wrapped_text_rows(fallback_text,
            chars_per_text_row(panel.width - text_padding * 2, wrap_advance))
    }
    if runtime^.command_buffer.command_count <= 0 {
        return count_wrapped_text_rows(fallback_text,
            chars_per_text_row(panel.width - text_padding * 2, wrap_advance))
    }

    return dynview_count_styled_rows(runtime, panel.width, text_padding, wrap_advance)
}

//   Draw style-aware dynview content, falling back to plain wrapped text when unavailable.
dynview_draw_scratchpad_styled_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    fallback_text: string,
    panel: rl.Rectangle,
    scroll_y: f32,
    font: rl.Font,
    text_padding, text_row_height, wrap_advance, font_size: f32,
    fallback_text_color: rl.Color) {

    if ui_runtime == nil {
        draw_wrapped_text_content(fallback_text,
            panel,
            scroll_y,
            font,
            text_padding,
            text_row_height,
            fallback_text_color,
            wrap_advance,
            font_size)
        return
    }

    runtime := &ui_runtime^.dynview_runtime
    if runtime^.enabled && runtime^.compile_cache.is_valid &&
        !runtime^.command_buffer.has_stream_error && runtime^.command_buffer.command_count > 0 {
        dynview_draw_styled_content(runtime,
            panel,
            scroll_y,
            text_padding,
            text_row_height,
            wrap_advance,
            font_size,
            font)
        return
    }

    draw_wrapped_text_content(fallback_text,
        panel,
        scroll_y,
        font,
        text_padding,
        text_row_height,
        fallback_text_color,
        wrap_advance,
        font_size)
}

//   Phase 1 dynview tick: reset stream, track invalidation keys, and compile metadata.
dynview_tick_phase1 :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    source_text: string,
    panel: rl.Rectangle,
    font_size, wrap_advance: f32,
    style_revision: u64) {

    if ui_runtime == nil {
        return
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled {
        return
    }

    dynview_reset_command_buffer(runtime)
    dynview_track_content(runtime, source_text)
    dynview_track_panel(runtime, panel)
    dynview_track_font(runtime, font_size, wrap_advance)
    dynview_track_style(runtime, style_revision)
    dynview_compile_if_needed(runtime)
}
