package dynview

import "../core"

import "core:math"

import rl "vendor:raylib"

//   Uniform handler shape for one inline-shape layout command.
Layout_Inline_Shape_Handler :: #type proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int)

Inline_Item_Builder :: #type proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item

Inline_Column_Measurer :: #type proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int

//   Dispatch table mapping each inline-shape command kind to its layout handler.
//   Non-inline-shape kinds map to nil and are rejected by the caller.
LAYOUT_INLINE_SHAPE_HANDLERS ::
    [core.Dynview_Command_Kind]Layout_Inline_Shape_Handler{
    .Begin_Block = nil, .End_Block = nil, .Text_Run = nil, .Math_Glyph_Run = nil,
    .Math_Block = nil, .Script_Attach = nil, .Frac = nil,
    .Stretch_Delimiter = nil, .Matrix = nil,
    .Large_Op = nil, .Accent_Bar = nil, .Radical_Bar = nil,
    .Copyable_Text_Run = nil, .Line_Break = nil, .Divider = nil,
    .Inline_Line = layout_consume_inline_line,
    .Inline_Box = layout_consume_inline_box,
    .Inline_Circle = layout_consume_inline_circle,
    .Inline_Filled_Box = layout_consume_inline_filled_box,
    .Inline_Filled_Circle = layout_consume_inline_filled_circle,
    .Inline_Pie_Section = layout_consume_inline_pie_section,
    .Inline_Perpendicular = layout_consume_inline_perpendicular,
    .Inline_Triangle = layout_consume_inline_triangle,
    .Inline_Pentagon = layout_consume_inline_pentagon,
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

Pie_Section_Geometry :: struct {
    draw_width, draw_height: f32,
    center_offset_x, center_offset_y: f32,
}

Inline_Layout_Metrics :: struct {
    max_cols: int,
    cols: int,
    text_ascent: f32,
    text_descent: f32,
}

Inline_Item_Context :: struct {
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    metrics: Inline_Layout_Metrics,
}

Math_Block_Layout :: struct {
    program: ^core.Dynview_Math_Program,
    max_cols, cols: int,
    text_ascent, text_descent: f32,
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

Line_Base_Metrics :: struct {
    ascent, descent: f32,
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
    line_height: f32,
    base: Line_Base_Metrics) {

    cache^.layout_line_count += 1
    state^.line_index += 1
    state^.col = 0
    state^.y_offset += line_height + state^.line_gap
    layout_seed_line_accumulator(
        acc, cache^.layout_item_count, base.ascent, base.descent)
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
    layout_advance_after_line(cache, state, acc, line_height, {
        base_ascent, base_descent,
    })
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
    metrics: Wrapped_Line_Metrics) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Text_Run,
        style_id = cmd.style_id,
        col_span = metrics.col_span,
        text_offset = cmd.text_offset + metrics.byte_start,
        text_len = metrics.byte_len,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent,
        descent = metrics.descent,
    }
}

//   Consume one wrapped text segment and optionally force a line break.
layout_push_wrapped_text_segment :: proc(
    ctx: Text_Wrap_Context,
    metrics: Wrapped_Line_Metrics,
    should_break: bool) -> i32 {

    item := text_run_item(ctx.cmd, ctx.style, metrics)

    status := layout_push_item(ctx.cache, ctx.state, ctx.acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if should_break {
        return layout_finalize_for_wrap(ctx.cache, ctx.state, ctx.acc, metrics.ascent,
            metrics.descent)
    }

    return DYNVIEW_STATUS_OK
}

//   Lay out one wrapped text command and return the last line touched.
layout_consume_text_run :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    text: string,
    style: Dynview_Text_Style) -> (i32, int) {

    if len(text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    placement_status := layout_prepare_style_placement(
        ctx^.cache,
        ctx^.state,
        ctx^.acc,
        style,
        ctx^.font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := layout_max_cols(ctx^.cache, style)
    ascent, descent := style_ascent_descent(style, ctx^.font_size)
    return layout_wrap_text_run(Text_Wrap_Context{
        cache = ctx^.cache,
        state = ctx^.state,
        acc = ctx^.acc,
        cmd = cmd,
        text = text,
        style = style,
        max_cols = max_cols,
        ascent = ascent,
        descent = descent,
    })
}

//   Finalize the current wrapped line only when it is already at capacity.
layout_finalize_if_wrap_full :: #force_inline proc(
    ctx: Text_Wrap_Context) -> i32 {

    if ctx.state^.col < ctx.max_cols {
        return DYNVIEW_STATUS_OK
    }
    return layout_finalize_for_wrap(
        ctx.cache, ctx.state, ctx.acc, ctx.ascent, ctx.descent)
}

//   Wrap one text segment at `start`, finalizing full rows, and return the next
//   start index. A returned next_start <= start signals the loop should stop.
layout_wrap_one_segment :: proc(
    ctx: Text_Wrap_Context,
    start: int) -> (int, i32) {

    status := layout_finalize_if_wrap_full(ctx)
    if status != DYNVIEW_STATUS_OK {
        return start, status
    }

    available := ctx.max_cols - ctx.state^.col
    if available <= 0 {
        status = layout_finalize_for_wrap(ctx.cache, ctx.state, ctx.acc,
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

    status = layout_push_wrapped_text_segment(
        ctx,
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

//   Build the finalized layout item for one measured math program.
math_block_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    layout: Math_Block_Layout) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Math_Block,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        col_span = layout.cols,
        draw_width = layout.program^.draw_width,
        draw_height = layout.program^.ascent + layout.program^.descent,
        ascent = layout.program^.ascent,
        descent = layout.program^.descent,
        visual_padding_top = layout.program^.visual_padding_top,
        visual_padding_bottom = layout.program^.visual_padding_bottom,
    }
}

//   Convert measured math block metrics into the shared inline placement shape.
math_block_inline_metrics :: #force_inline proc(
    layout: Math_Block_Layout) -> Inline_Layout_Metrics {

    return Inline_Layout_Metrics{
        max_cols = layout.max_cols,
        cols = layout.cols,
        text_ascent = layout.text_ascent,
        text_descent = layout.text_descent,
    }
}

//   Lay out one premeasured recursive math block as an atomic non-wrapping inline item.
layout_consume_math_block :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        ctx^.cache,
        ctx^.state,
        ctx^.acc,
        style,
        ctx^.font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    layout, measure_status := math_block_layout_metrics(ctx, cmd, style)
    if measure_status != DYNVIEW_STATUS_OK {
        return measure_status, -1
    }

    metrics := math_block_inline_metrics(layout)
    status := layout_wrap_before_inline(ctx^.cache, ctx^.state, ctx^.acc, metrics)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := math_block_item(cmd, layout)

    status = layout_push_item(ctx^.cache, ctx^.state, ctx^.acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        ctx^.cache, ctx^.state, ctx^.acc, metrics)
}

//   Measure one math block and derive its line placement metrics.
math_block_layout_metrics :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (Math_Block_Layout, i32) {

    program, ok := math_program_from_command(ctx^.cache, cmd)
    if !ok || !measure_math_program(ctx^.cache, ctx^.buffer, program, ctx^.font_size) {
        return {}, DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    max_cols := layout_max_cols(ctx^.cache, style)
    cols := 1
    base_advance := effective_advance(style, ctx^.cache^.last_wrap_advance)
    if base_advance > 0 {
        cols = max(cols, int(program^.draw_width / base_advance))
        if f32(cols) * base_advance < program^.draw_width {
            cols += 1
        }
    }
    text_ascent, text_descent := style_ascent_descent(style, ctx^.font_size)
    return Math_Block_Layout{
        program = program,
        max_cols = max_cols,
        cols = min(max_cols, max(1, cols)),
        text_ascent = text_ascent,
        text_descent = text_descent,
    }, DYNVIEW_STATUS_OK
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
    metrics: Inline_Layout_Metrics) -> i32 {

    if state^.col <= 0 || state^.col + metrics.cols <= metrics.max_cols {
        return DYNVIEW_STATUS_OK
    }

    return layout_finalize_line(
        cache, state, acc, metrics.text_ascent, metrics.text_descent)
}

//   Finalize line after placing one inline item when row reaches capacity.
layout_finalize_after_inline_if_full :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    metrics: Inline_Layout_Metrics) -> (i32, int) {

    if state^.col < metrics.max_cols {
        return DYNVIEW_STATUS_OK, state^.line_index
    }

    status := layout_finalize_line(
        cache, state, acc, metrics.text_ascent, metrics.text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, state^.line_index - 1
    }

    return DYNVIEW_STATUS_OK, state^.line_index - 1
}

//   Compute the wrapping and baseline metrics shared by inline layout items.
inline_layout_metrics :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    measure_columns: Inline_Column_Measurer) -> Inline_Layout_Metrics {

    max_cols := layout_max_cols(ctx^.cache, style)
    text_ascent, text_descent := style_ascent_descent(style, ctx^.font_size)
    return Inline_Layout_Metrics{
        max_cols = max_cols,
        cols = measure_columns(ctx^.cache, cmd, style, max_cols),
        text_ascent = text_ascent,
        text_descent = text_descent,
    }
}

//   Place one inline item using shared style, wrapping, and line-finalization rules.
layout_consume_inline_item :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    measure_columns: Inline_Column_Measurer,
    build_item: Inline_Item_Builder) -> (i32, int) {

    placement_status := layout_prepare_style_placement(
        ctx^.cache, ctx^.state, ctx^.acc, style, ctx^.font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    metrics := inline_layout_metrics(ctx, cmd, style, measure_columns)
    status := layout_wrap_before_inline(
        ctx^.cache, ctx^.state, ctx^.acc, metrics)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := build_item(Inline_Item_Context{
        cache = ctx^.cache,
        cmd = cmd,
        style = style,
        metrics = metrics,
    })
    status = layout_push_item(ctx^.cache, ctx^.state, ctx^.acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return layout_finalize_after_inline_if_full(
        ctx^.cache, ctx^.state, ctx^.acc, metrics)
}

//   Lay out one inline-line command and return the line touched.
layout_consume_inline_line :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_line_column_measure, inline_line_item)
}

//   Measure line inline items using the cached wrap advance.
inline_line_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    return inline_line_cols(cmd, style, cache^.last_wrap_advance, max_cols)
}

//   Measure box-like inline items through the common column-measurer contract.
inline_box_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = cache
    return inline_box_cols(cmd, style, max_cols)
}

//   Measure circle-like inline items through the common column-measurer contract.
inline_circle_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = cache
    return inline_circle_cols(cmd, style, max_cols)
}

//   Measure pie-section inline items through the common column-measurer contract.
inline_pie_section_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = cache
    return inline_pie_section_cols(cmd, style, max_cols)
}

//   Build a line inline item from the shared inline layout context.
inline_line_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    thickness := max(1.0, item_ctx.cmd.inline_atom_stroke)
    metrics := inline_line_metrics(
        thickness, item_ctx.metrics.text_ascent, item_ctx.metrics.text_descent)
    return core.Dynview_Layout_Item{
        kind = .Inline_Line,
        style_id = item_ctx.cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = item_ctx.cmd.inline_atom_dimension,
        inline_atom_stroke = thickness,
        has_brush_color = item_ctx.cmd.has_brush_color,
        brush_color = item_ctx.cmd.brush_color,
        draw_width = f32(item_ctx.metrics.cols) * effective_advance(
            item_ctx.style, item_ctx.cache^.last_wrap_advance),
        draw_height = metrics.draw_height,
        ascent = max(metrics.ascent, item_ctx.metrics.text_ascent * 0.08),
        descent = max(metrics.descent, item_ctx.metrics.text_descent * 0.08),
    }
}

//   Build a box inline item anchored around the text baseline zone.
inline_box_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    box_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Box,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = box_height,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        shape_edge_color_4 = cmd.shape_edge_color_4,
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
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_box_column_measure, inline_box_item)
}

//   Build a circle inline item centered in the text baseline zone.
inline_circle_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    atom_width := f32(cols) * effective_advance
    radius := max(2.0, min(atom_width * 0.5, (text_ascent + text_descent) * 0.5))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Circle,
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
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_circle_column_measure, inline_circle_item)
}

//   Build a filled-box inline item using the same geometry as outline boxes.
inline_filled_box_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    item := inline_box_item(item_ctx)
    item.kind = .Inline_Filled_Box
    return item
}

//   Lay out one inline-filled-box command and return the line touched.
layout_consume_inline_filled_box :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_box_column_measure, inline_filled_box_item)
}

//   Build a filled-circle inline item using the same geometry as outline circles.
inline_filled_circle_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    item := inline_circle_item(item_ctx)
    item.kind = .Inline_Filled_Circle
    return item
}

//   Lay out one inline-filled-circle command and return the line touched.
layout_consume_inline_filled_circle :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_circle_column_measure, inline_filled_circle_item)
}

//   Compute the clipped draw bounds and center offsets for one pie section.
pie_section_geometry :: #force_inline proc(
    radius, reserved_width, start_angle, end_angle: f32) -> Pie_Section_Geometry {

    bounds := pie_section_bounds(radius, start_angle, end_angle)
    draw_width := min(reserved_width, max(1.0, bounds.x_max - bounds.x_min))
    return Pie_Section_Geometry{
        draw_width = draw_width,
        draw_height = max(1.0, bounds.y_max - bounds.y_min),
        center_offset_x = -bounds.x_min,
        center_offset_y = -bounds.y_min,
    }
}

//   Build one pie-section item using circle-equivalent geometry.
inline_pie_section_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    reserved_width := f32(cols) * effective_advance

    requested_radius := max(2.0, cmd.inline_atom_dimension * effective_advance)
    geometry := pie_section_geometry(
        requested_radius, reserved_width, cmd.pie_start_angle_degrees,
        cmd.pie_end_angle_degrees)

    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Pie_Section,
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
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
        pie_center_offset_x = geometry.center_offset_x,
        pie_center_offset_y = geometry.center_offset_y,
        ascent = max(0.0, -(center - geometry.center_offset_y)),
        descent = max(0.0, center + (geometry.draw_height - geometry.center_offset_y)),
    }
}

//   Build one perpendicular item using box-equivalent geometry.
inline_perpendicular_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    line_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Perpendicular,
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
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    tri_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Triangle,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = tri_height,
        has_brush_color = cmd.has_brush_color,
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
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cache := item_ctx.cache
    cmd := item_ctx.cmd
    style := item_ctx.style
    cols := item_ctx.metrics.cols
    text_ascent := item_ctx.metrics.text_ascent
    text_descent := item_ctx.metrics.text_descent
    effective_advance := effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    pent_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Dynview_Layout_Item{
        kind = .Inline_Pentagon,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = pent_height,
        shape_is_filled = cmd.shape_is_filled,
        has_brush_color = cmd.has_brush_color,
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
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_pie_section_column_measure, inline_pie_section_item)
}

//   Lay out one inline-perpendicular command and return the line touched.
layout_consume_inline_perpendicular :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_box_column_measure, inline_perpendicular_item)
}

//   Lay out one inline-triangle command and return the line touched.
layout_consume_inline_triangle :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_box_column_measure, inline_triangle_item)
}

//   Lay out one inline-pentagon command and return the line touched.
layout_consume_inline_pentagon :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> (i32, int) {

    return layout_consume_inline_item(
        ctx, cmd, style, inline_box_column_measure, inline_pentagon_item)
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

    if cmd.kind == .Begin_Block {
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

    if cmd.kind == .End_Block {
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
        ctx, cmd, text, style)
    return status
}

//   Consume one visible math-structure command using the matching layout helper.
//   Only top-level Math_Block is handled here; nested math-structure kinds are
//   consumed through their own recursion and are rejected at this layer.
layout_consume_structured_math_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    if cmd.kind != .Math_Block {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    status, _ := layout_consume_math_block(
        ctx, cmd, style)
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
    status, _ := handler(ctx, cmd, style)
    return status
}

//   Consume one visible dynview command and update copy-row span.
layout_consume_visible_command :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    effective_style := style_with_block_format(style, ctx^.state^.active_block_format)
    switch cmd.kind {
    case .Text_Run, .Math_Glyph_Run:
        return layout_consume_text_like_command(ctx, cmd, effective_style)
    case .Math_Block, .Script_Attach, .Frac,
        .Large_Op, .Accent_Bar,
        .Stretch_Delimiter, .Matrix,
        .Radical_Bar:
        return layout_consume_structured_math_command(ctx, cmd, effective_style)
    case .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Filled_Box,
        .Inline_Filled_Circle, .Inline_Pie_Section, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
        return layout_consume_inline_shape_command(ctx, cmd, effective_style)
    case .Line_Break, .Divider:
        return layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
    case .Begin_Block, .End_Block, .Copyable_Text_Run:
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

//   Expand one pie-section bounds record to include a point on its arc.
pie_include_angle :: #force_inline proc(
    bounds: ^Pie_Section_Bounds,
    angle_degrees, radius: f32) {

    radians := angle_degrees * math.PI / 180.0
    x := radius * f32(math.cos(f64(radians)))
    y := -radius * f32(math.sin(f64(radians)))
    bounds^.x_min = min(bounds^.x_min, x)
    bounds^.x_max = max(bounds^.x_max, x)
    bounds^.y_min = min(bounds^.y_min, y)
    bounds^.y_max = max(bounds^.y_max, y)
}

//   Compute tight wedge bounds including center and cardinal sweep crossings.
pie_section_bounds :: #force_inline proc(
    radius,
    start_degrees,
    end_degrees: f32) -> Pie_Section_Bounds {

    start_n := pie_normalize_angle_degrees(start_degrees)
    end_n := pie_normalize_angle_degrees(end_degrees)
    sweep := pie_positive_sweep_degrees(start_n, end_n)

    bounds := Pie_Section_Bounds{}
    pie_include_angle(&bounds, start_n, radius)
    pie_include_angle(&bounds, end_n, radius)

    cardinals := [?]f32{0, 90, 180, 270}
    for i in 0..<len(cardinals) {
        angle := cardinals[i]
        if pie_angle_in_sweep(angle, start_n, sweep) {
            pie_include_angle(&bounds, angle, radius)
        }
    }

    return bounds
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
