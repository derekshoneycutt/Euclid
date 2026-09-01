package dynview

import "../core"
import "../grid"

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

//   Tight pixel-space visual bounds for one inline shape.
Inline_Shape_Geometry :: struct {
    draw_width, draw_height: f32,
    center_offset_x, center_offset_y: f32,
    stroke: f32,
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
    overflows_horizontally: bool,
}

//   Canonical column reservation for one measured outer math block.
Math_Block_Columns :: struct {
    span: int,
    overflows_horizontally: bool,
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

//   Aggregated row requirements for one sparse document line.
Line_Grid_Extents :: struct {
    baseline_rows_above: int,
    baseline_rows_below: int,
    nonbaseline_rows: int,
    has_baseline: bool,
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

//   Return style-independent canonical column capacity in the active panel.
layout_max_cols :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache) -> int {

    content_width := cache^.last_panel_width - TEXT_PADDING * 2
    max_cols := chars_per_text_row(content_width, cache^.last_cell_width)
    return max(1, max_cols)
}

//   Construct canonical cell geometry from tracked dimensions and base text metrics.
layout_cell_metrics :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    base_ascent, base_descent: f32) -> grid.Cell_Metrics {

    text_height := base_ascent + base_descent
    top_inset := max(0.0, (cache^.last_cell_height - text_height) * 0.5)
    return {
        cell_width = cache^.last_cell_width,
        cell_height = cache^.last_cell_height,
        baseline_from_top = top_inset + base_ascent,
    }
}

//   Report whether one item participates in the shared text and math baseline.
layout_item_has_baseline :: #force_inline proc(
    item: core.Dynview_Layout_Item) -> bool {

    return item.kind == .Text_Run || item.kind == .Math_Glyph_Run ||
        item.kind == .Math_Block || item.kind == .Script_Attach ||
        item.kind == .Frac || item.kind == .Stretch_Delimiter ||
        item.kind == .Matrix || item.kind == .Large_Op ||
        item.kind == .Accent_Bar || item.kind == .Radical_Bar
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

    status := core.bounded_element_builder_append(
        &cache^.layout_item_builder, []core.Dynview_Layout_Item{item})
    if status != .Ok {
        return compiled_builder_status(status)
    }
    cache^.layout_items = cache^.layout_item_builder.storage[
        :cache^.layout_item_builder.count]
    item_slot := &cache^.layout_items[cache^.layout_item_builder.count - 1]
    item_slot^.block_id = state^.active_block_id
    item_slot^.line_index = state^.line_index
    item_slot^.col_start = state^.col

    cache^.layout_item_count = cache^.layout_item_builder.count
    state^.col += max(1, item.col_span)
    acc^.item_count += 1
    acc^.max_ascent = max(acc^.max_ascent, item.ascent)
    acc^.max_descent = max(acc^.max_descent, item.descent)
    return DYNVIEW_STATUS_OK
}

//   Quantize one item's existing intrinsic bounds onto the canonical grid.
layout_place_item_on_grid :: #force_inline proc(
    item: ^core.Dynview_Layout_Item,
    cells: grid.Cell_Metrics) -> (grid.Embedded_Grid_Placement, bool) {

    has_baseline := layout_item_has_baseline(item^)
    content_height := max(1.0, item^.draw_height)
    content_width := max(1.0, item^.draw_width)
    if has_baseline {
        content_width = max(1.0, f32(max(1, item^.col_span)) * cells.cell_width)
    }
    baseline_from_top := f32(0)
    if has_baseline {
        content_height = max(1.0, item^.ascent + item^.descent)
        baseline_from_top = item^.ascent
    }
    if item^.kind == .Math_Block {
        content_width = max(1.0, item^.draw_width)
        content_height = max(1.0, item^.visual_padding_top + item^.ascent +
            item^.descent + item^.visual_padding_bottom)
        baseline_from_top = item^.visual_padding_top + item^.ascent
    }
    placement, ok := grid.place_embedded_content(cells, {
        width = content_width,
        height = content_height,
        has_baseline = has_baseline,
        baseline_from_top = baseline_from_top,
    })
    if !ok {
        return {}, false
    }
    placement.column_span = max(1, item^.col_span)
    placement.allocated_width = f32(placement.column_span) * cells.cell_width
    placement.content_offset_x = (placement.allocated_width - content_width) * 0.5
    return placement, true
}

//   Quantize item heights and collect rows required around a common baseline.
layout_measure_item_rows :: proc(
    cache: ^core.Dynview_Compile_Cache,
    start_index, item_count: int,
    cells: grid.Cell_Metrics) -> (Line_Grid_Extents, bool) {

    extents := Line_Grid_Extents{}
    item_end := start_index + item_count
    for item_index in start_index..<item_end {
        item := &cache^.layout_items[item_index]
        has_baseline := layout_item_has_baseline(item^)
        placement, ok := layout_place_item_on_grid(item, cells)
        if !ok {
            return {}, false
        }
        item^.row_span = placement.row_span
        item^.baseline_row = placement.baseline_row
        item^.content_offset_x = placement.content_offset_x
        item^.content_offset_y = placement.content_offset_y
        if has_baseline {
            extents.has_baseline = true
            extents.baseline_rows_above = max(
                extents.baseline_rows_above, placement.baseline_row)
            extents.baseline_rows_below = max(extents.baseline_rows_below,
                placement.row_span - placement.baseline_row - 1)
        } else {
            extents.nonbaseline_rows = max(
                extents.nonbaseline_rows, placement.row_span)
        }
    }
    return extents, true
}

//   Resolve final line rows while centering any extra rows around the baseline band.
layout_resolve_line_rows :: #force_inline proc(
    extents: Line_Grid_Extents) -> (row_span, baseline_row: int) {

    baseline_span := 0
    if extents.has_baseline {
        baseline_span = extents.baseline_rows_above + 1 +
            extents.baseline_rows_below
    }
    row_span = max(1, max(baseline_span, extents.nonbaseline_rows))
    if extents.has_baseline {
        baseline_row = extents.baseline_rows_above + (row_span - baseline_span) / 2
    }
    return
}

//   Derive item row offsets and transitional pixel origins from final line rows.
layout_apply_item_grid_offsets :: proc(
    cache: ^core.Dynview_Compile_Cache,
    line: ^core.Dynview_Layout_Line,
    cells: grid.Cell_Metrics) {

    item_end := line^.item_start + line^.item_count
    for item_index in line^.item_start..<item_end {
        item := &cache^.layout_items[item_index]
        if layout_item_has_baseline(item^) {
            item^.row_offset = line^.baseline_row - item^.baseline_row
        } else {
            item^.row_offset = (line^.row_span - item^.row_span) / 2
        }
    }
}

//   Advance state after one line finalization.
layout_advance_after_line :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    row_span: int,
    base: Line_Base_Metrics) {

    cache^.layout_line_count += 1
    state^.line_index += 1
    state^.col = 0
    state^.row += row_span
    layout_seed_line_accumulator(
        acc, cache^.layout_item_count, base.ascent, base.descent)
}

//   Finalize one line as an integral grid band with a shared canonical baseline.
layout_finalize_line :: proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    base_ascent, base_descent: f32) -> i32 {

    cells := layout_cell_metrics(cache, base_ascent, base_descent)
    extents, ok := layout_measure_item_rows(
        cache, acc^.item_start, acc^.item_count, cells)
    if !ok {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    row_span, baseline_row := layout_resolve_line_rows(extents)
    line_record := core.Dynview_Layout_Line{
        item_start = acc^.item_start,
        item_count = acc^.item_count,
        row_start = state^.row,
        row_span = row_span,
        baseline_row = baseline_row,
        max_ascent = acc^.max_ascent,
        max_descent = acc^.max_descent,
    }
    status := core.bounded_element_builder_append(
        &cache^.layout_line_builder, []core.Dynview_Layout_Line{line_record})
    if status != .Ok {
        return compiled_builder_status(status)
    }
    cache^.layout_lines = cache^.layout_line_builder.storage[
        :cache^.layout_line_builder.count]
    line := &cache^.layout_lines[cache^.layout_line_builder.count - 1]

    layout_apply_item_grid_offsets(cache, line, cells)
    layout_advance_after_line(cache, state, acc, row_span, {
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

    max_cols := layout_max_cols(ctx^.cache)
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
        italic_correction = layout.program^.italic_correction,
        top_accent_attachment = layout.program^.top_accent_attachment,
        overflows_horizontally = layout.overflows_horizontally,
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
math_block_columns :: #force_inline proc(
    draw_width, cell_width: f32,
    max_cols: int) -> Math_Block_Columns {

    required_cols := max(1, int(math.ceil(f64(draw_width) / f64(cell_width))))
    return {
        span = min(max_cols, required_cols),
        overflows_horizontally = required_cols > max_cols,
    }
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

    max_cols := layout_max_cols(ctx^.cache)
    columns := math_block_columns(
        program^.draw_width, ctx^.cache^.last_cell_width, max_cols)
    text_ascent, text_descent := style_ascent_descent(style, ctx^.font_size)
    return Math_Block_Layout{
        program = program,
        max_cols = max_cols,
        cols = columns.span,
        text_ascent = text_ascent,
        text_descent = text_descent,
        overflows_horizontally = columns.overflows_horizontally,
    }, DYNVIEW_STATUS_OK
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

    max_cols := layout_max_cols(ctx^.cache)
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

    return inline_shape_cols(cmd, cache^.last_cell_width, max_cols)
}

//   Measure box-like inline items through the common column-measurer contract.
inline_box_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, cache^.last_cell_width, max_cols)
}

//   Measure circle-like inline items through the common column-measurer contract.
inline_circle_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, cache^.last_cell_width, max_cols)
}

//   Measure pie-section inline items through the common column-measurer contract.
inline_pie_section_column_measure :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, cache^.last_cell_width, max_cols)
}

//   Build a line inline item from the shared inline layout context.
inline_line_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    geometry := inline_shape_geometry(
        item_ctx.cmd, item_ctx.cache^.last_cell_width)
    return core.Dynview_Layout_Item{
        kind = .Inline_Line,
        style_id = item_ctx.cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = item_ctx.cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        has_brush_color = item_ctx.cmd.has_brush_color,
        brush_color = item_ctx.cmd.brush_color,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
    }
}

//   Build a box inline item anchored around the text baseline zone.
inline_box_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Box,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        inline_box_height = cmd.inline_box_height * item_ctx.cache^.last_cell_width,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        shape_edge_color_4 = cmd.shape_edge_color_4,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
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

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Circle,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
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

//   Compute tight stroke-inclusive draw bounds and center offsets for one pie section.
pie_section_geometry :: #force_inline proc(
    radius, stroke, start_angle, end_angle: f32) -> Pie_Section_Geometry {

    bounds := pie_section_bounds(radius, start_angle, end_angle)
    half_stroke := stroke * 0.5
    return Pie_Section_Geometry{
        draw_width = max(1.0, bounds.x_max - bounds.x_min + stroke),
        draw_height = max(1.0, bounds.y_max - bounds.y_min + stroke),
        center_offset_x = -bounds.x_min + half_stroke,
        center_offset_y = -bounds.y_min + half_stroke,
    }
}

//   Return the stroke extent contributing to one shape's tight visual bounds.
inline_shape_visual_stroke :: #force_inline proc(
    cmd: core.Dynview_Command) -> f32 {

    #partial switch cmd.kind {
    case .Inline_Filled_Box, .Inline_Filled_Circle:
        return max(0.0, cmd.inline_outline_stroke)
    case .Inline_Pie_Section:
        if cmd.pie_is_filled {
            return max(0.0, cmd.inline_outline_stroke)
        }
        return max(1.0, cmd.inline_outline_stroke)
    case .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
        return max(1.0, cmd.inline_atom_stroke)
    case:
        return 0
    }
}

//   Measure one inline shape's complete stroke-inclusive intrinsic bounds.
inline_shape_geometry :: proc(
    cmd: core.Dynview_Command,
    cell_width: f32) -> Inline_Shape_Geometry {

    stroke := inline_shape_visual_stroke(cmd)
    width := max(0.001, cmd.inline_atom_dimension * cell_width)
    height := max(0.001, cmd.inline_box_height * cell_width)
    #partial switch cmd.kind {
    case .Inline_Line:
        return {width + stroke, stroke, 0, 0, stroke}
    case .Inline_Box, .Inline_Filled_Box, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
        return {width + stroke, height + stroke, 0, 0, stroke}
    case .Inline_Circle, .Inline_Filled_Circle:
        diameter := width * 2
        return {diameter + stroke, diameter + stroke, 0, 0, stroke}
    case .Inline_Pie_Section:
        pie := pie_section_geometry(width, stroke,
            cmd.pie_start_angle_degrees, cmd.pie_end_angle_degrees)
        return {pie.draw_width, pie.draw_height,
            pie.center_offset_x, pie.center_offset_y, stroke}
    case:
        return {1, 1, 0, 0, 0}
    }
}

//   Reserve canonical columns for intrinsic shape width without scaling content.
inline_shape_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
    cell_width: f32,
    max_cols: int) -> int {

    if max_cols <= 0 || cell_width <= 0 {
        return 1
    }
    geometry := inline_shape_geometry(cmd, cell_width)
    required := max(1,
        int(math.ceil(f64(geometry.draw_width) / f64(cell_width))))
    return min(max_cols, required)
}

//   Build one pie-section item using circle-equivalent geometry.
inline_pie_section_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Pie_Section,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = max(0.0, cmd.inline_outline_stroke),
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        pie_is_filled = cmd.pie_is_filled,
        has_outline_color = cmd.has_outline_color,
        outline_color = cmd.outline_color,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
        pie_center_offset_x = geometry.center_offset_x,
        pie_center_offset_y = geometry.center_offset_y,
    }
}

//   Build one perpendicular item using box-equivalent geometry.
inline_perpendicular_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Perpendicular,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        inline_box_height = cmd.inline_box_height * item_ctx.cache^.last_cell_width,
        has_brush_color = true,
        brush_color = cmd.brush_color,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
    }
}

//   Build one triangle item using box-equivalent geometry.
inline_triangle_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Triangle,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        inline_box_height = cmd.inline_box_height * item_ctx.cache^.last_cell_width,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        shape_is_filled = cmd.shape_is_filled,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
    }
}

//   Build one inline-pentagon layout item from command metrics and style defaults.
inline_pentagon_item :: #force_inline proc(
    item_ctx: Inline_Item_Context) -> core.Dynview_Layout_Item {

    cmd := item_ctx.cmd
    geometry := inline_shape_geometry(cmd, item_ctx.cache^.last_cell_width)

    return core.Dynview_Layout_Item{
        kind = .Inline_Pentagon,
        style_id = cmd.style_id,
        col_span = item_ctx.metrics.cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = geometry.stroke,
        inline_box_height = cmd.inline_box_height * item_ctx.cache^.last_cell_width,
        shape_is_filled = cmd.shape_is_filled,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        shape_edge_color_1 = cmd.shape_edge_color_1,
        shape_edge_color_2 = cmd.shape_edge_color_2,
        shape_edge_color_3 = cmd.shape_edge_color_3,
        shape_edge_color_4 = cmd.shape_edge_color_4,
        shape_edge_color_5 = cmd.shape_edge_color_5,
        overflows_horizontally = geometry.draw_width >
            f32(item_ctx.metrics.max_cols) * item_ctx.cache^.last_cell_width,
        draw_width = geometry.draw_width,
        draw_height = geometry.draw_height,
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
layout_set_empty_default :: proc(cache: ^core.Dynview_Compile_Cache) -> i32 {
    base_ascent := max(1.0, cache^.last_font_size * 0.8)
    base_descent := max(1.0, cache^.last_font_size * 0.2)
    cells := layout_cell_metrics(cache, base_ascent, base_descent)
    line := core.Dynview_Layout_Line{
        row_span = 1,
        max_ascent = base_ascent,
        max_descent = base_descent,
    }
    status := core.bounded_element_builder_append(
        &cache^.layout_line_builder, []core.Dynview_Layout_Line{line})
    if status != .Ok {
        return compiled_builder_status(status)
    }
    cache^.layout_lines = cache^.layout_line_builder.storage[:1]
    cache^.layout_line_count = 1
    cache^.layout_total_height = cells.cell_height
    cache^.layout_average_line_height = cells.cell_height
    return DYNVIEW_STATUS_OK
}

//   Seed layout context from cached panel/font metrics.
layout_build_context :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator) -> Dynview_Layout_Build_Context {

    base_style := style_by_id(DYNVIEW_STYLE_OUTPUT)
    base_ascent, base_descent := style_ascent_descent(base_style, cache^.last_font_size)
    cells := layout_cell_metrics(cache, base_ascent, base_descent)
    state^ = Dynview_Layout_State{
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
        grid_metrics = cells,
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

    spacing_rows := int(math.ceil(f64(spacing) / f64(ctx^.grid_metrics.cell_height)))
    ctx^.state^.row += max(1, spacing_rows)
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

    total_line_rows := 0
    for line_index in 0..<ctx^.cache^.layout_line_count {
        total_line_rows += ctx^.cache^.layout_lines[line_index].row_span
    }
    ctx^.cache^.layout_total_height =
        f32(ctx^.state^.row) * ctx^.grid_metrics.cell_height
    ctx^.cache^.layout_average_line_height =
        f32(total_line_rows) * ctx^.grid_metrics.cell_height /
        f32(ctx^.cache^.layout_line_count)
    return DYNVIEW_STATUS_OK
}

//   Initialize bounded line and item storage for one layout rebuild.
layout_builders_init :: proc(
    cache: ^core.Dynview_Compile_Cache,
    cache_arena: ^core.Arena_Owner) -> i32 {
    line_status := core.bounded_element_builder_init(
        &cache^.layout_line_builder, core.DYNVIEW_MAX_LAYOUT_LINES, cache_arena)
    if line_status != .Ok {
        return compiled_builder_status(line_status)
    }
    item_status := core.bounded_element_builder_init(
        &cache^.layout_item_builder, core.DYNVIEW_MAX_LAYOUT_ITEMS, cache_arena)
    return compiled_builder_status(item_status)
}

//   Seal and publish one complete line/item layout transaction.
layout_builders_seal :: proc(cache: ^core.Dynview_Compile_Cache) -> i32 {
    lines, line_status := core.bounded_element_builder_seal(
        &cache^.layout_line_builder)
    if line_status != .Ok {
        return compiled_builder_status(line_status)
    }
    items, item_status := core.bounded_element_builder_seal(
        &cache^.layout_item_builder)
    if item_status != .Ok {
        return compiled_builder_status(item_status)
    }
    cache^.layout_lines = lines
    cache^.layout_items = items
    cache^.layout_is_valid = true
    return DYNVIEW_STATUS_OK
}

//   Build deterministic line/item layout cache from current validated command stream.
rebuild_layout_cache :: proc(
    runtime: ^core.Dynview_System,
    cache_arena: ^core.Arena_Owner) -> i32 {
    if runtime == nil {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    commands := command_buffer_commands(buffer)
    layout_reset_cache(cache)
    init_status := layout_builders_init(cache, cache_arena)
    if init_status != DYNVIEW_STATUS_OK {
        return init_status
    }

    if len(commands) <= 0 {
        status := layout_set_empty_default(cache)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
        return layout_builders_seal(cache)
    }

    state := Dynview_Layout_State{}
    acc := Dynview_Layout_Line_Accumulator{}
    ctx := layout_build_context(cache, buffer, &state, &acc)

    for cmd in commands {
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

    metrics_status := layout_finalize_metrics(&ctx)
    if metrics_status != DYNVIEW_STATUS_OK {
        return metrics_status
    }
    return layout_builders_seal(cache)
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
    text_bytes := command_buffer_text(buffer)
    if text_offset + text_len > len(text_bytes) {
        return ""
    }
    return string(text_bytes[text_offset:text_offset + text_len])
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
    text_bytes := command_buffer_text(buffer)
    if cmd.text_offset + cmd.text_len > len(text_bytes) {
        return ""
    }
    return string(text_bytes[cmd.text_offset:cmd.text_offset + cmd.text_len])
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

    _ = style
    return inline_shape_cols(cmd, wrap_advance, max_cols)
}

//   Measure inline-box command from intrinsic visual width in canonical columns.
inline_box_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, wrap_advance, max_cols)
}

//   Measure inline-circle command from intrinsic visual width in canonical columns.
inline_circle_cols :: #force_inline proc(
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, wrap_advance, max_cols)
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
    wrap_advance: f32,
    max_cols: int) -> int {

    _ = style
    return inline_shape_cols(cmd, wrap_advance, max_cols)
}
