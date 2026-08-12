package dynview

import "../core"

import "core:math"

import rl "vendor:raylib"

//   Uniform handler shape for one inline-shape layout command.
Layout_Inline_Shape_Handler :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int)

//   Dispatch table mapping each inline-shape command kind to its layout handler.
//   Non-inline-shape kinds map to nil and are rejected by the caller.
LAYOUT_INLINE_SHAPE_HANDLERS ::
    [core.Dynview_Command_Kind]Layout_Inline_Shape_Handler{
    .BeginBlock = nil, .EndBlock = nil, .TextRun = nil, .MathGlyphRun = nil,
    .MathBlock = nil, .ScriptAttachRecursive = nil, .FracRecursive = nil,
    .StretchDelimiterRecursive = nil, .MatrixRecursive = nil,
    .LargeOpRecursive = nil, .AccentBarRecursive = nil, .RadicalBarRecursive = nil,
    .CopyableTextRun = nil, .LineBreak = nil, .Divider = nil,
    .InlineLine = layout_consume_inline_line,
    .InlineBox = layout_consume_inline_box,
    .InlineCircle = layout_consume_inline_circle,
    .InlineFilledBox = layout_consume_inline_filled_box,
    .InlineFilledCircle = layout_consume_inline_filled_circle,
    .InlinePieSection = layout_consume_inline_pie_section,
    .InlinePerpendicular = layout_consume_inline_perpendicular,
    .InlineTriangle = layout_consume_inline_triangle,
    .InlinePentagon = layout_consume_inline_pentagon,
}

Inline_Line_Metrics :: struct {
    ascent:      f32,
    descent:     f32,
    draw_height: f32,
}

Layout_Item_Line_Span :: struct {
    first_line:        int,
    last_line:         int,
    has_visible_items: bool,
}

Pie_Section_Bounds :: struct {
    x_min: f32,
    x_max: f32,
    y_min: f32,
    y_max: f32,
}

//   Per-segment wrapped line metrics: byte span within the source text, column
//   span on the layout grid, and the line box vertical extents.
Wrapped_Line_Metrics :: struct {
    byte_start: int,
    byte_len:   int,
    col_span:   int,
    ascent:     f32,
    descent:    f32,
}

//   Shared environment for wrapping one text run into layout lines. Groups the
//   cache/state/accumulator targets with the source command, text, style, and
//   typography metrics so the wrap helpers pass one coherent value.
Text_Wrap_Context :: struct {
    cache:    ^core.Dynview_Compile_Cache,
    state:    ^Dynview_Layout_State,
    acc:      ^Dynview_Layout_Line_Accumulator,
    cmd:      core.Dynview_Command,
    text:     string,
    style:    Dynview_Text_Style,
    max_cols: int,
    ascent:   f32,
    descent:  f32,
}

// Accumulate information based on a layout seed
layout_seed_line_accumulator :: #force_inline proc(
    acc: ^Dynview_Layout_Line_Accumulator,
    item_start: int,
    base_ascent, base_descent: f32) {

    acc^.item_start = item_start
    acc^.item_count = 0
    acc^.max_ascent = base_ascent
    acc^.max_descent = base_descent
}

//   Return wrapped column capacity for one style in active panel.
layout_max_cols :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    style: Dynview_Text_Style) -> int {

    max_cols := chars_per_row_for_style(
        cache^.last_panel_width,
        TEXT_PADDING,
        cache^.last_wrap_advance,
        style)
    return max(1, max_cols)
}

//   Enforce style-level line-start behavior before placing content.
layout_prepare_style_placement :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    style: Dynview_Text_Style,
    font_size: f32) -> i32 {

    if style.force_line_start && state^.col > 0 {
        ascent, descent := style_ascent_descent(style, font_size)
        status := layout_finalize_line(cache, state, acc, ascent, descent)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    if state^.col == 0 && style.indent_cols > 0 {
        state^.col = style.indent_cols
    }

    return DYNVIEW_STATUS_OK
}

//   Reserve a new layout item slot and append a prepared item.
layout_push_item :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    item: core.Dynview_Layout_Item) -> i32 {

    if cache^.layout_item_count >= len(cache^.layout_items) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    item_slot := &cache^.layout_items[cache^.layout_item_count]
    item_slot^ = item
    item_slot^.block_id = state^.active_block_id
    item_slot^.line_index = state^.line_index
    item_slot^.col_start = state^.col
    item_slot^.x_offset = f32(state^.col) * effective_advance(
        style_by_id(item.style_id),
        cache^.last_wrap_advance)

    cache^.layout_item_count += 1
    state^.col += max(1, item.col_span)
    acc^.item_count += 1
    acc^.max_ascent = max(acc^.max_ascent, item.ascent)
    acc^.max_descent = max(acc^.max_descent, item.descent)
    return DYNVIEW_STATUS_OK
}

//   Apply per-item vertical offsets from finalized baseline metrics.
layout_apply_item_offsets :: proc(
    cache: ^core.Dynview_Compile_Cache,
    start_index, item_count: int,
    line_height: f32) {

    item_end := start_index + item_count
    for item_index in start_index..<item_end {
        item := &cache^.layout_items[item_index]
        item^.y_offset = (line_height - item^.draw_height) * 0.5
    }
}

//   Advance state after one line finalization.
layout_advance_after_line :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    line_height, base_ascent, base_descent: f32) {

    cache^.layout_line_count += 1
    state^.line_index += 1
    state^.col = 0
    state^.y_offset += line_height + state^.line_gap
    layout_seed_line_accumulator(acc, cache^.layout_item_count, base_ascent, base_descent)
}

//   Finalize one layout line and compute y-offsets from per-item ascent/descent.
layout_finalize_line :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    base_ascent, base_descent: f32) -> i32 {

    if state^.line_index >= len(cache^.layout_lines) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    line_height := max(1.0, acc^.max_ascent + acc^.max_descent)
    line := &cache^.layout_lines[state^.line_index]
    line^.item_start = acc^.item_start
    line^.item_count = acc^.item_count
    line^.y_offset = state^.y_offset
    line^.line_height = line_height
    line^.baseline = acc^.max_ascent
    line^.max_ascent = acc^.max_ascent
    line^.max_descent = acc^.max_descent

    layout_apply_item_offsets(
        cache, line^.item_start, line^.item_count, line^.line_height)
    layout_advance_after_line(cache, state, acc, line_height, base_ascent, base_descent)
    return DYNVIEW_STATUS_OK
}

//   Finalize current line when wrapping a multi-line item is required.
layout_finalize_for_wrap :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    ascent, descent: f32) -> i32 {

    if state^.col < 0 {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    return layout_finalize_line(cache, state, acc, ascent, descent)
}

//   Build a text-run layout item for one wrapped line segment.
text_run_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    line_start, line_byte_len, line_col_span: int,
    ascent, descent: f32) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .TextRun,
        style_id = cmd.style_id,
        col_span = line_col_span,
        text_offset = cmd.text_offset + line_start,
        text_len = line_byte_len,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
}

//   Consume one wrapped text segment and optionally force a line break.
layout_push_wrapped_text_segment :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    metrics: Wrapped_Line_Metrics,
    should_break: bool) -> i32 {

    item := text_run_item(
        cmd,
        style,
        cache^.last_wrap_advance,
        metrics.byte_start,
        metrics.byte_len,
        metrics.col_span,
        metrics.ascent,
        metrics.descent)

    status := layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if should_break {
        return layout_finalize_for_wrap(cache, state, acc, metrics.ascent,
            metrics.descent)
    }

    return DYNVIEW_STATUS_OK
}

//   Lay out one wrapped text command and return the last line touched.
layout_consume_text_run :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    text: string,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    if len(text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    ascent, descent := style_ascent_descent(style, font_size)
    return layout_wrap_text_run(Text_Wrap_Context{
        cache = cache,
        state = state,
        acc = acc,
        cmd = cmd,
        text = text,
        style = style,
        max_cols = max_cols,
        ascent = ascent,
        descent = descent,
    })
}

//   Wrap one text segment at `start`, finalizing full rows, and return the next
//   start index. A returned next_start <= start signals the loop should stop.
layout_wrap_one_segment :: proc(
    ctx: Text_Wrap_Context,
    start: int) -> (int, i32) {

    if ctx.state^.col >= ctx.max_cols {
        status := layout_finalize_for_wrap(ctx.cache, ctx.state, ctx.acc,
            ctx.ascent, ctx.descent)
        if status != DYNVIEW_STATUS_OK {
            return start, status
        }
    }

    available := ctx.max_cols - ctx.state^.col
    if available <= 0 {
        status := layout_finalize_for_wrap(ctx.cache, ctx.state, ctx.acc,
            ctx.ascent, ctx.descent)
        if status != DYNVIEW_STATUS_OK {
            return start, status
        }
        return start, DYNVIEW_STATUS_OK
    }

    span := next_wrapped_text_span(ctx.text, start, available)
    line_col_span := text_codepoint_count_span(ctx.text, span.line_start, span.line_end)
    line_byte_len := span.line_end - span.line_start
    if line_col_span <= 0 || line_byte_len <= 0 {
        return start, DYNVIEW_STATUS_OK
    }

    status := layout_push_wrapped_text_segment(
        ctx.cache, ctx.state, ctx.acc, ctx.cmd, ctx.style,
        Wrapped_Line_Metrics{
            byte_start = span.line_start,
            byte_len = line_byte_len,
            col_span = line_col_span,
            ascent = ctx.ascent,
            descent = ctx.descent,
        },
        span.next_start < len(ctx.text))
    if status != DYNVIEW_STATUS_OK {
        return start, status
    }
    return span.next_start, DYNVIEW_STATUS_OK
}

//   Wrap one text run into layout lines, finalizing a row whenever the line is full.
layout_wrap_text_run :: proc(ctx: Text_Wrap_Context) -> (i32, int) {

    state := ctx.state
    text := ctx.text
    last_line := -1
    start := 0
    for start < len(text) {
        next_start, status := layout_wrap_one_segment(ctx, start)
        if status != DYNVIEW_STATUS_OK {
            return status, last_line
        }
        if next_start <= start {
            break
        }

        last_line = state^.line_index
        start = next_start
        if next_start < len(text) {
            last_line = state^.line_index - 1
        }
    }

    return DYNVIEW_STATUS_OK, last_line
}

//   Lay out one premeasured recursive math block as an atomic non-wrapping inline item.
layout_consume_math_block :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    program, ok := math_program_from_command(cache, cmd)
    if !ok {
        return DYNVIEW_STATUS_INVALID_ARGUMENT, -1
    }
    if !measure_math_program(cache, buffer, program, font_size) {
        return DYNVIEW_STATUS_INVALID_ARGUMENT, -1
    }

    max_cols := layout_max_cols(cache, style)
    text_ascent, text_descent := style_ascent_descent(style, font_size)
    cols := 1
    base_advance := effective_advance(style, cache^.last_wrap_advance)
    if base_advance > 0 {
        cols = max(cols, int(program^.draw_width / base_advance))
        if f32(cols) * base_advance < program^.draw_width {
            cols += 1
        }
    }
    cols = min(max_cols, max(1, cols))

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := core.Dynview_Layout_Item{
        kind = .MathBlock,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        col_span = cols,
        draw_width = program^.draw_width,
        draw_height = program^.ascent + program^.descent,
        ascent = program^.ascent,
        descent = program^.descent,
        visual_padding_top = program^.visual_padding_top,
        visual_padding_bottom = program^.visual_padding_bottom,
    }

    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Compute line-style inline stroke metrics centered on baseline zone.
inline_line_metrics :: #force_inline proc(
    thickness, text_ascent, text_descent: f32) -> Inline_Line_Metrics {

    center := (text_descent - text_ascent) * 0.5
    top := center - thickness * 0.5
    bottom := center + thickness * 0.5
    ascent := max(0.0, -top)
    descent := max(0.0, bottom)
    return Inline_Line_Metrics{ascent, descent, thickness}
}

//   Finalize line before placing one inline item if current row overflows.
layout_wrap_before_inline :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols, cols: int,
    text_ascent, text_descent: f32) -> i32 {

    if state^.col <= 0 || state^.col + cols <= max_cols {
        return DYNVIEW_STATUS_OK
    }

    return layout_finalize_line(cache, state, acc, text_ascent, text_descent)
}

//   Finalize line after placing one inline item when row reaches capacity.
layout_finalize_after_inline_if_full :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols: int,
    text_ascent, text_descent: f32) -> (i32, int) {

    if state^.col < max_cols {
        return DYNVIEW_STATUS_OK, state^.line_index
    }

    status := layout_finalize_line(cache, state, acc, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, state^.line_index - 1
    }

    return DYNVIEW_STATUS_OK, state^.line_index - 1
}

//   Lay out one inline-line command and return the line touched.
layout_consume_inline_line :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_line_cols(cmd, style, cache^.last_wrap_advance, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    thickness := max(1.0, cmd.inline_atom_stroke)
    metrics := inline_line_metrics(thickness, text_ascent, text_descent)
    item := core.Dynview_Layout_Item{
        kind = .InlineLine,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = thickness,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        draw_width = f32(cols) * effective_advance(style, cache^.last_wrap_advance),
        draw_height = metrics.draw_height,
        ascent = max(metrics.ascent, text_ascent * 0.08),
        descent = max(metrics.descent, text_descent * 0.08),
    }

    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a box inline item anchored around the text baseline zone.
inline_box_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    box_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlineBox,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = box_height,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        draw_width = f32(cols) * effective_advance,
        draw_height = box_height,
        ascent = max(0.0, -(center - box_height * 0.5)),
        descent = max(0.0, center + box_height * 0.5),
    }
}

//   Lay out one inline-box command and return the line touched.
layout_consume_inline_box :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a circle inline item centered in the text baseline zone.
inline_circle_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    atom_width := f32(cols) * effective_advance
    radius := max(2.0, min(atom_width * 0.5, (text_ascent + text_descent) * 0.5))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlineCircle,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        draw_width = atom_width,
        draw_height = radius * 2,
        ascent = max(0.0, -(center - radius)),
        descent = max(0.0, center + radius),
    }
}

//   Lay out one inline-circle command and return the line touched.
layout_consume_inline_circle :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a filled-box inline item using the same geometry as outline boxes.
inline_filled_box_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    item := inline_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    item.kind = .InlineFilledBox
    return item
}

//   Lay out one inline-filled-box command and return the line touched.
layout_consume_inline_filled_box :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_filled_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a filled-circle inline item using the same geometry as outline circles.
inline_filled_circle_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    item := inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    item.kind = .InlineFilledCircle
    return item
}

//   Lay out one inline-filled-circle command and return the line touched.
layout_consume_inline_filled_circle :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_filled_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build one pie-section item using circle-equivalent geometry.
inline_pie_section_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    reserved_width := f32(cols) * effective_advance

    // Inline pie radius is authored in wrap-column units.
    // Use requested radius directly so larger radius grows the marker itself,
    // not only its surrounding horizontal span.
    requested_radius := max(2.0, cmd.inline_atom_dimension * effective_advance)

    bounds := pie_section_bounds(
        requested_radius,
        cmd.pie_start_angle_degrees,
        cmd.pie_end_angle_degrees)
    draw_width := max(1.0, bounds.x_max - bounds.x_min)
    draw_height := max(1.0, bounds.y_max - bounds.y_min)
    center_offset_x := -bounds.x_min
    center_offset_y := -bounds.y_min

    // Keep draw width inside the reserved layout span in edge-rounding cases.
    if draw_width > reserved_width {
        draw_width = reserved_width
    }

    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlinePieSection,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = max(0.0, cmd.inline_outline_stroke),
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        pie_is_filled = cmd.pie_is_filled,
        has_outline_color = cmd.has_outline_color,
        outline_color = cmd.outline_color,
        draw_width = draw_width,
        draw_height = draw_height,
        pie_center_offset_x = center_offset_x,
        pie_center_offset_y = center_offset_y,
        ascent = max(0.0, -(center - center_offset_y)),
        descent = max(0.0, center + (draw_height - center_offset_y)),
    }
}

//   Build one perpendicular item using box-equivalent geometry.
inline_perpendicular_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    line_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlinePerpendicular,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = line_height,
        has_brush_color = true,
        brush_color = cmd.brush_color,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        draw_width = f32(cols) * effective_advance,
        draw_height = line_height,
        ascent = max(0.0, -(center - line_height * 0.5)),
        descent = max(0.0, center + line_height * 0.5),
    }
}

//   Build one triangle item using box-equivalent geometry.
inline_triangle_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    tri_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlineTriangle,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = tri_height,
        has_brush_color = cmd.shape_is_filled,
        brush_color = cmd.brush_color,
        shape_is_filled = cmd.shape_is_filled,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        draw_width = f32(cols) * effective_advance,
        draw_height = tri_height,
        ascent = max(0.0, -(center - tri_height * 0.5)),
        descent = max(0.0, center + tri_height * 0.5),
    }
}

//   Build one inline-pentagon layout item from command metrics and style defaults.
inline_pentagon_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Dynview_Layout_Item {

    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    pent_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .InlinePentagon,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = pent_height,
        shape_is_filled = cmd.shape_is_filled,
        has_brush_color = cmd.shape_is_filled,
        brush_color = cmd.brush_color,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        shape_edge_color_4 = cmd.shape_edge_color_4,
        shape_edge_color_5 = cmd.shape_edge_color_5,
        draw_width = f32(cols) * effective_advance,
        draw_height = pent_height,
        ascent = max(0.0, -(center - pent_height * 0.5)),
        descent = max(0.0, center + pent_height * 0.5),
    }
}

//   Lay out one inline pie-section command and return the line touched.
layout_consume_inline_pie_section :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_pie_section_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_pie_section_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Lay out one inline-perpendicular command and return the line touched.
layout_consume_inline_perpendicular :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status :=
        layout_prepare_style_placement(cache, state, acc, style, font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache, state, acc, max_cols, cols, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_perpendicular_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache, state, acc, max_cols, text_ascent, text_descent)
}

//   Lay out one inline-triangle command and return the line touched.
layout_consume_inline_triangle :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache, state, acc, style, font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache, state, acc, max_cols, cols, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_triangle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache, state, acc, max_cols, text_ascent, text_descent)
}

//   Lay out one inline-pentagon command and return the line touched.
layout_consume_inline_pentagon :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        cache, state, acc, style, font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(cache, style)
    cols := inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, font_size)

    status := layout_wrap_before_inline(
        cache, state, acc, max_cols, cols, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := inline_pentagon_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        cache, state, acc, max_cols, text_ascent, text_descent)
}

//   Fill a one-line layout cache for an empty command stream.
layout_set_empty_default :: proc(cache: ^core.Dynview_Compile_Cache) {
    cache^.layout_is_valid = true
    cache^.layout_line_count = 1
    cache^.layout_lines[0] = core.Dynview_Layout_Line{
        y_offset = 0,
        line_height = max(1.0, cache^.last_font_size),
        baseline = max(1.0, cache^.last_font_size * 0.8),
        max_ascent = max(1.0, cache^.last_font_size * 0.8),
        max_descent = max(1.0, cache^.last_font_size * 0.2),
    }
    cache^.layout_total_height = cache^.layout_lines[0].line_height
    cache^.layout_average_line_height = cache^.layout_lines[0].line_height
}

//   Seed layout context from cached panel/font metrics.
layout_build_context :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator) -> Dynview_Layout_Build_Context {

    base_style := style_by_id(DYNVIEW_STYLE_OUTPUT)
    base_ascent, base_descent := style_ascent_descent(base_style, cache^.last_font_size)
    state^ = Dynview_Layout_State{
        line_gap = max(1.0, (base_ascent + base_descent) * 0.16),
        active_block_id = -1,
        active_block_kind = -1,
        active_block_format = block_format_for_kind(-1),
    }
    layout_seed_line_accumulator(acc, 0, base_ascent, base_descent)

    return Dynview_Layout_Build_Context{
        cache = cache,
        buffer = buffer,
        state = state,
        acc = acc,
        font_size = cache^.last_font_size,
        base_ascent = base_ascent,
        base_descent = base_descent,
    }
}

//   Apply before/after paragraph spacing at block boundaries.
layout_apply_block_spacing :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    spacing: f32) -> i32 {

    if spacing <= 0 {
        return DYNVIEW_STATUS_OK
    }

    if ctx^.acc^.item_count > 0 {
        status := layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    ctx^.state^.y_offset += spacing
    return DYNVIEW_STATUS_OK
}

//   Update copy-span tracking for block lifecycle commands.
layout_handle_block_markers :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command) -> i32 {

    if cmd.kind == .BeginBlock {
        new_format := block_format_for_kind(cmd.style_id)
        spacing_status :=
            layout_apply_block_spacing(ctx, new_format.paragraph_spacing_before)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = cmd.block_id
        ctx^.state^.active_block_kind = cmd.style_id
        ctx^.state^.active_block_format = new_format
        return DYNVIEW_STATUS_OK
    }

    if cmd.kind == .EndBlock {
        spacing_status := layout_apply_block_spacing(
            ctx,
            ctx^.state^.active_block_format.paragraph_spacing_after)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = -1
        ctx^.state^.active_block_kind = -1
        ctx^.state^.active_block_format = block_format_for_kind(-1)
        return DYNVIEW_STATUS_OK
    }

    return DYNVIEW_STATUS_OK
}

//   Consume one visible text-like command using normal wrapped text flow.
layout_consume_text_like_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    text := text_for_command(ctx^.buffer, cmd)
    status, _ := layout_consume_text_run(
        ctx^.cache, ctx^.state, ctx^.acc, cmd, text, style, ctx^.font_size)
    return status
}

//   Consume one visible math-structure command using the matching layout helper.
//   Only top-level MathBlock is handled here; nested math-structure kinds are
//   consumed through their own recursion and are rejected at this layer.
layout_consume_structured_math_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    if cmd.kind != .MathBlock {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    status, _ := layout_consume_math_block(
        ctx^.cache, ctx^.buffer, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
    return status
}

//   Consume one visible inline-shape command using the matching layout helper.
layout_consume_inline_shape_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    handlers := LAYOUT_INLINE_SHAPE_HANDLERS
    handler := handlers[cmd.kind]
    if handler == nil {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    status, _ := handler(ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
    return status
}

//   Consume one visible dynview command and update copy-row span.
layout_consume_visible_command :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    effective_style := style_with_block_format(style, ctx^.state^.active_block_format)
    switch cmd.kind {
    case .TextRun, .MathGlyphRun:
        return layout_consume_text_like_command(ctx, cmd, effective_style)
    case .MathBlock, .ScriptAttachRecursive, .FracRecursive,
        .LargeOpRecursive, .AccentBarRecursive,
        .StretchDelimiterRecursive, .MatrixRecursive,
        .RadicalBarRecursive:
        return layout_consume_structured_math_command(ctx, cmd, effective_style)
    case .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox,
        .InlineFilledCircle, .InlinePieSection, .InlinePerpendicular,
        .InlineTriangle, .InlinePentagon:
        return layout_consume_inline_shape_command(ctx, cmd, effective_style)
    case .LineBreak, .Divider:
        return layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
    case .BeginBlock, .EndBlock, .CopyableTextRun:
    }

    return DYNVIEW_STATUS_OK
}

//   Resolve inline draw color using per-item brush override with style fallback.
inline_draw_color :: #force_inline proc(
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item) -> rl.Color {

    if item.has_brush_color {
        return item.brush_color
    }
    return style.color
}

//   Finalize total layout metrics after all commands are consumed.
layout_finalize_metrics :: proc(ctx: ^Dynview_Layout_Build_Context) -> i32 {
    status := layout_finalize_line(
        ctx^.cache,
        ctx^.state,
        ctx^.acc,
        ctx^.base_ascent,
        ctx^.base_descent)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if ctx^.cache^.layout_line_count <= 0 {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    last_line := ctx^.cache^.layout_lines[ctx^.cache^.layout_line_count - 1]
    ctx^.cache^.layout_total_height = last_line.y_offset + last_line.line_height
    ctx^.cache^.layout_average_line_height =
        ctx^.cache^.layout_total_height / f32(ctx^.cache^.layout_line_count)
    ctx^.cache^.layout_is_valid = true
    return DYNVIEW_STATUS_OK
}

//   Build deterministic line/item layout cache from current validated command stream.
rebuild_layout_cache :: proc(runtime: ^core.Dynview_System) -> i32 {
    if runtime == nil {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    layout_reset_cache(cache)

    if buffer^.command_count <= 0 {
        layout_set_empty_default(cache)
        return DYNVIEW_STATUS_OK
    }

    state := Dynview_Layout_State{}
    acc := Dynview_Layout_Line_Accumulator{}
    ctx := layout_build_context(cache, buffer, &state, &acc)

    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        marker_status := layout_handle_block_markers(&ctx, cmd)
        if marker_status != DYNVIEW_STATUS_OK {
            return marker_status
        }

        style := style_by_id(cmd.style_id)
        status := layout_consume_visible_command(&ctx, cmd, style)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return layout_finalize_metrics(&ctx)
}

//   Return the first/last layout line indices that contain visible items for block_id.
layout_item_line_span_for_block :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    block_id: i32) -> Layout_Item_Line_Span {

    first_line := -1
    last_line := -1
    for i in 0..<cache^.layout_item_count {
        item := cache^.layout_items[i]
        if item.block_id != block_id {
            continue
        }

        if first_line < 0 || item.line_index < first_line {
            first_line = item.line_index
        }
        if item.line_index > last_line {
            last_line = item.line_index
        }
    }

    if first_line < 0 || last_line < first_line {
        return Layout_Item_Line_Span{0, 0, false}
    }

    return Layout_Item_Line_Span{first_line, last_line, true}
}

//   Extract a text span from the shared dynview byte buffer using explicit offset/length.
text_span_from_buffer :: #force_inline proc(
    buffer: ^core.Dynview_Command_Buffer,
    text_offset, text_len: int) -> string {

    if text_offset < 0 || text_len < 0 {
        return ""
    }
    if text_offset + text_len > buffer^.text_bytes_len {
        return ""
    }
    return string(buffer^.text_bytes[text_offset:text_offset + text_len])
}

//   Build display-style large-operator plain-text fallback using canonical command name.
large_op_visible_text :: #force_inline proc(
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command) -> string {

    switch cmd.large_op_kind {
    case 1:
        return "\\sum"
    case 2:
        return "\\prod"
    case 3:
        return "\\int"
    case 4:
        return "\\lim"
    }
    return text_for_command(buffer, cmd)
}

//   Extract text slice from one text run command.
text_for_command :: #force_inline proc(
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command) -> string {

    if cmd.text_offset < 0 || cmd.text_len < 0 {
        return ""
    }
    if cmd.text_offset + cmd.text_len > buffer^.text_bytes_len {
        return ""
    }
    return string(buffer^.text_bytes[cmd.text_offset:cmd.text_offset + cmd.text_len])
}

//   Return max wrapped chars for a style using style-aware wrap scale.
chars_per_row_for_style :: #force_inline proc(
    panel_width, text_padding, wrap_advance: f32,
    style: Dynview_Text_Style) -> int {

    effective_advance := max(1.0, wrap_advance * max(0.5, style.wrap_scale))
    return chars_per_text_row(panel_width - text_padding * 2, effective_advance)
}


//   Measure inline-line command in columns with bounded minimum/maximum spans.
inline_line_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
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
inline_box_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
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
inline_circle_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
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

//   Normalize one degree angle into the [0, 360) range.
pie_normalize_angle_degrees :: #force_inline proc(angle: f32) -> f32 {
    normalized := angle
    for normalized < 0 {
        normalized += 360
    }
    for normalized >= 360 {
        normalized -= 360
    }
    return normalized
}

//   Compute positive sweep degrees from start to end with wraparound.
pie_positive_sweep_degrees :: #force_inline proc(start_degrees, end_degrees: f32) -> f32 {
    start_n := pie_normalize_angle_degrees(start_degrees)
    end_n := pie_normalize_angle_degrees(end_degrees)
    sweep := end_n - start_n
    if sweep < 0 {
        sweep += 360
    }
    return sweep
}

//   Return true when angle lies inside the inclusive start->end positive sweep.
pie_angle_in_sweep :: #force_inline proc(
    angle_degrees,
    start_degrees,
    sweep_degrees: f32) -> bool {

    delta := pie_normalize_angle_degrees(angle_degrees - start_degrees)
    return delta <= sweep_degrees + 0.0001
}

//   Compute tight wedge bounds including center and cardinal sweep crossings.
pie_section_bounds :: #force_inline proc(
    radius,
    start_degrees,
    end_degrees: f32) -> Pie_Section_Bounds {

    start_n := pie_normalize_angle_degrees(start_degrees)
    end_n := pie_normalize_angle_degrees(end_degrees)
    sweep := pie_positive_sweep_degrees(start_n, end_n)

    x_min: f32 = 0
    x_max: f32 = 0
    y_min: f32 = 0
    y_max: f32 = 0

    include_angle :: #force_inline proc(
        angle_degrees: f32, radius: f32, x_min, x_max, y_min, y_max: ^f32) {
        radians := angle_degrees * math.PI / 180.0
        x := radius * f32(math.cos(f64(radians)))
        y := -radius * f32(math.sin(f64(radians)))
        x_min^ = min(x_min^, x)
        x_max^ = max(x_max^, x)
        y_min^ = min(y_min^, y)
        y_max^ = max(y_max^, y)
    }

    include_angle(start_n, radius, &x_min, &x_max, &y_min, &y_max)
    include_angle(end_n, radius, &x_min, &x_max, &y_min, &y_max)

    cardinals := [?]f32{0, 90, 180, 270}
    for i in 0..<len(cardinals) {
        angle := cardinals[i]
        if pie_angle_in_sweep(angle, start_n, sweep) {
            include_angle(angle, radius, &x_min, &x_max, &y_min, &y_max)
        }
    }

    return Pie_Section_Bounds{x_min, x_max, y_min, y_max}
}

//   Measure inline pie-section command using tight wedge horizontal bounds.
inline_pie_section_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    if max_cols <= 0 {
        return 1
    }

    radius_in_cols := cmd.inline_atom_dimension
    if radius_in_cols <= 0 {
        radius_in_cols = 1
    }
    radius_scaled := radius_in_cols * max(0.5, style.wrap_scale)

    bounds := pie_section_bounds(
        radius_scaled,
        cmd.pie_start_angle_degrees,
        cmd.pie_end_angle_degrees)
    width_in_cols := max(1.0, bounds.x_max - bounds.x_min)

    cols := int(math.ceil(f64(width_in_cols)))
    if cols < 1 {
        cols = 1
    }
    if cols > max_cols {
        cols = max_cols
    }
    return cols
}
