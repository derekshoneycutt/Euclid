package ui

import "../../core"

import rl "vendor:raylib"

Dynview_Layout_Line_Accumulator :: struct {
    item_start: int,
    item_count: int,
    max_ascent: f32,
    max_descent: f32,
}

Dynview_Block_Format :: struct {
    alignment: Dynview_Text_Alignment,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
}

Dynview_Layout_State :: struct {
    line_index: int,
    col: int,
    y_offset: f32,
    line_gap: f32,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

Dynview_Layout_Build_Context :: struct {
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
}

//   Return style-aware ascent/descent estimates from active font size.
dynview_style_ascent_descent :: #force_inline proc(style: Dynview_Text_Style, font_size: f32) -> (f32, f32) {
    scale := max(0.8, style.wrap_scale)
    ascent := max(1.0, font_size * (0.74 + 0.06 * scale))
    descent := max(1.0, font_size * (0.22 + 0.02 * scale))

    if style.bold {
        ascent += font_size * 0.06
    }

    if style.italic {
        descent += font_size * 0.03
    }

    line_height_mult := max(0.6, style.line_height_multiplier)
    return ascent * line_height_mult, descent * line_height_mult
}

//   Return default block format values keyed by block kind.
dynview_block_format_for_kind :: #force_inline proc(block_kind: i32) -> Dynview_Block_Format {
    switch block_kind {
    case 1: // BRIDGE_DYNVIEW_BLOCK_INPUT
        return Dynview_Block_Format{
            indent_cols = 2,
            paragraph_spacing_before = 2,
            paragraph_spacing_after = 2,
            line_height_multiplier = 1.0,
        }
    case 2: // BRIDGE_DYNVIEW_BLOCK_OUTPUT
        return Dynview_Block_Format{
            paragraph_spacing_after = 1,
            line_height_multiplier = 1.0,
        }
    }

    return Dynview_Block_Format{
        line_height_multiplier = 1.0,
    }
}

//   Merge per-style values with active block format controls.
dynview_style_with_block_format :: #force_inline proc(
    style: Dynview_Text_Style,
    block_format: Dynview_Block_Format) -> Dynview_Text_Style {

    merged := style
    if merged.alignment == .Left && block_format.alignment != .Left {
        merged.alignment = block_format.alignment
    }

    merged.indent_cols = max(merged.indent_cols, block_format.indent_cols)
    merged.paragraph_spacing_before = max(merged.paragraph_spacing_before, block_format.paragraph_spacing_before)
    merged.paragraph_spacing_after = max(merged.paragraph_spacing_after, block_format.paragraph_spacing_after)
    merged.line_height_multiplier = max(merged.line_height_multiplier, block_format.line_height_multiplier)
    return merged
}

//   Reset canonical layout cache fields before rebuild.
dynview_layout_reset_cache :: proc(cache: ^core.Ui_Dynview_Compile_Cache) {
    cache^.layout_line_count = 0
    cache^.layout_item_count = 0
    cache^.layout_total_height = 0
    cache^.layout_average_line_height = 0
    cache^.layout_is_valid = false
}

//   Start a new line accumulator seeded from base text metrics.
dynview_layout_seed_line_accumulator :: #force_inline proc(
    acc: ^Dynview_Layout_Line_Accumulator,
    item_start: int,
    base_ascent, base_descent: f32) {

    acc^.item_start = item_start
    acc^.item_count = 0
    acc^.max_ascent = base_ascent
    acc^.max_descent = base_descent
}

//   Return wrapped column capacity for one style in active panel.
dynview_layout_max_cols :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    style: Dynview_Text_Style) -> int {

    max_cols := dynview_chars_per_row_for_style(
        cache^.last_panel_width,
        TEXT_PADDING,
        cache^.last_wrap_advance,
        style)
    return max(1, max_cols)
}

//   Enforce style-level line-start behavior before placing content.
dynview_layout_prepare_style_placement :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    style: Dynview_Text_Style,
    font_size: f32) -> i32 {

    if style.force_line_start && state^.col > 0 {
        ascent, descent := dynview_style_ascent_descent(style, font_size)
        status := dynview_layout_finalize_line(cache, state, acc, ascent, descent)
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
dynview_layout_push_item :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    item: core.Ui_Dynview_Layout_Item) -> i32 {

    if cache^.layout_item_count >= len(cache^.layout_items) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    item_slot := &cache^.layout_items[cache^.layout_item_count]
    item_slot^ = item
    item_slot^.block_id = state^.active_block_id
    item_slot^.line_index = state^.line_index
    item_slot^.col_start = state^.col
    item_slot^.x_offset = f32(state^.col) * dynview_effective_advance(
        dynview_style_by_id(item.style_id),
        cache^.last_wrap_advance)

    cache^.layout_item_count += 1
    state^.col += max(1, item.col_span)
    acc^.item_count += 1
    acc^.max_ascent = max(acc^.max_ascent, item.ascent)
    acc^.max_descent = max(acc^.max_descent, item.descent)
    return DYNVIEW_STATUS_OK
}

//   Apply per-item vertical offsets from finalized baseline metrics.
dynview_layout_apply_item_offsets :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    start_index, item_count: int,
    baseline: f32) {

    item_end := start_index + item_count
    for item_index in start_index..<item_end {
        item := &cache^.layout_items[item_index]
        item^.y_offset = baseline - item^.ascent
    }
}

//   Advance state after one line finalization.
dynview_layout_advance_after_line :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    line_height, base_ascent, base_descent: f32) {

    cache^.layout_line_count += 1
    state^.line_index += 1
    state^.col = 0
    state^.y_offset += line_height + state^.line_gap
    dynview_layout_seed_line_accumulator(acc, cache^.layout_item_count, base_ascent, base_descent)
}

//   Finalize one layout line and compute y-offsets from per-item ascent/descent.
dynview_layout_finalize_line :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
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

    dynview_layout_apply_item_offsets(cache, line^.item_start, line^.item_count, line^.baseline)
    dynview_layout_advance_after_line(cache, state, acc, line_height, base_ascent, base_descent)
    return DYNVIEW_STATUS_OK
}

//   Finalize current line when wrapping a multi-line item is required.
dynview_layout_finalize_for_wrap :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    ascent, descent: f32) -> i32 {

    if state^.col < 0 {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    return dynview_layout_finalize_line(cache, state, acc, ascent, descent)
}

//   Build a text-run layout item for one wrapped line segment.
dynview_text_run_item :: #force_inline proc(
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    line_start, line_len: int,
    ascent, descent: f32) -> core.Ui_Dynview_Layout_Item {

    return core.Ui_Dynview_Layout_Item{
        kind = .TextRun,
        style_id = cmd.style_id,
        col_span = line_len,
        text_offset = cmd.text_offset + line_start,
        text_len = line_len,
        draw_width = f32(line_len) * dynview_effective_advance(style, wrap_advance),
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
}

//   Consume one wrapped text segment and optionally force a line break.
dynview_layout_push_wrapped_text_segment :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    line_start, line_len: int,
    should_break: bool,
    ascent, descent: f32) -> i32 {

    item := dynview_text_run_item(
        cmd,
        style,
        cache^.last_wrap_advance,
        line_start,
        line_len,
        ascent,
        descent)

    status := dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if should_break {
        return dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
    }

    return DYNVIEW_STATUS_OK
}

//   Lay out one wrapped text command and return the last line touched.
dynview_layout_consume_text_run :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    text: string,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    if len(text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    ascent, descent := dynview_style_ascent_descent(style, font_size)
    last_line := -1
    start := 0
    for start < len(text) {
        if state^.col >= max_cols {
            status := dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
            if status != DYNVIEW_STATUS_OK {
                return status, last_line
            }
        }

        available := max_cols - state^.col
        if available <= 0 {
            status := dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
            if status != DYNVIEW_STATUS_OK {
                return status, last_line
            }
            continue
        }

        line_start, line_end, next_start := next_wrapped_text_span(text, start, available)
        line_len := line_end - line_start
        if line_len <= 0 {
            break
        }

        status := dynview_layout_push_wrapped_text_segment(
            cache,
            state,
            acc,
            cmd,
            style,
            line_start,
            line_len,
            next_start < len(text),
            ascent,
            descent)
        if status != DYNVIEW_STATUS_OK {
            return status, last_line
        }

        last_line = state^.line_index
        if next_start <= start {
            break
        }

        start = next_start
        if next_start < len(text) {
            last_line = state^.line_index - 1
        }
    }

    return DYNVIEW_STATUS_OK, last_line
}

//   Compute line-style inline stroke metrics centered on baseline zone.
dynview_inline_line_metrics :: #force_inline proc(
    thickness, text_ascent, text_descent: f32) -> (f32, f32, f32) {

    center := (text_descent - text_ascent) * 0.5
    top := center - thickness * 0.5
    bottom := center + thickness * 0.5
    ascent := max(0.0, -top)
    descent := max(0.0, bottom)
    return ascent, descent, thickness
}

//   Finalize line before placing one inline item if current row overflows.
dynview_layout_wrap_before_inline :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols, cols: int,
    text_ascent, text_descent: f32) -> i32 {

    if state^.col <= 0 || state^.col + cols <= max_cols {
        return DYNVIEW_STATUS_OK
    }

    return dynview_layout_finalize_line(cache, state, acc, text_ascent, text_descent)
}

//   Finalize line after placing one inline item when row reaches capacity.
dynview_layout_finalize_after_inline_if_full :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols: int,
    text_ascent, text_descent: f32) -> (i32, int) {

    if state^.col < max_cols {
        return DYNVIEW_STATUS_OK, state^.line_index
    }

    status := dynview_layout_finalize_line(cache, state, acc, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, state^.line_index - 1
    }

    return DYNVIEW_STATUS_OK, state^.line_index - 1
}

//   Lay out one inline-line command and return the line touched.
dynview_layout_consume_inline_line :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_line_cols(cmd, style, cache^.last_wrap_advance, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
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
    ascent, descent, draw_height := dynview_inline_line_metrics(thickness, text_ascent, text_descent)
    item := core.Ui_Dynview_Layout_Item{
        kind = .InlineLine,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = thickness,
        draw_width = f32(cols) * dynview_effective_advance(style, cache^.last_wrap_advance),
        draw_height = draw_height,
        ascent = max(ascent, text_ascent * 0.08),
        descent = max(descent, text_descent * 0.08),
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a box inline item anchored around the text baseline zone.
dynview_inline_box_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    effective_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    box_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Ui_Dynview_Layout_Item{
        kind = .InlineBox,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = box_height,
        draw_width = f32(cols) * effective_advance,
        draw_height = box_height,
        ascent = max(0.0, -(center - box_height * 0.5)),
        descent = max(0.0, center + box_height * 0.5),
    }
}

//   Lay out one inline-box command and return the line touched.
dynview_layout_consume_inline_box :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
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

    item := dynview_inline_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a circle inline item centered in the text baseline zone.
dynview_inline_circle_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    effective_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    atom_width := f32(cols) * effective_advance
    radius := max(2.0, min(atom_width * 0.5, (text_ascent + text_descent) * 0.5))
    center := (text_descent - text_ascent) * 0.5

    return core.Ui_Dynview_Layout_Item{
        kind = .InlineCircle,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        draw_width = atom_width,
        draw_height = radius * 2,
        ascent = max(0.0, -(center - radius)),
        descent = max(0.0, center + radius),
    }
}

//   Lay out one inline-circle command and return the line touched.
dynview_layout_consume_inline_circle :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
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

    item := dynview_inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Fill a one-line layout cache for an empty command stream.
dynview_layout_set_empty_default :: proc(cache: ^core.Ui_Dynview_Compile_Cache) {
    cache^.layout_is_valid = true
    cache^.layout_line_count = 1
    cache^.layout_lines[0] = core.Ui_Dynview_Layout_Line{
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
dynview_layout_build_context :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator) -> Dynview_Layout_Build_Context {

    base_style := dynview_style_by_id(DYNVIEW_STYLE_OUTPUT)
    base_ascent, base_descent := dynview_style_ascent_descent(base_style, cache^.last_font_size)
    state^ = Dynview_Layout_State{
        line_gap = max(1.0, (base_ascent + base_descent) * 0.16),
        active_block_id = -1,
        active_block_kind = -1,
        active_block_format = dynview_block_format_for_kind(-1),
    }
    dynview_layout_seed_line_accumulator(acc, 0, base_ascent, base_descent)

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
dynview_layout_apply_block_spacing :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    spacing: f32) -> i32 {

    if spacing <= 0 {
        return DYNVIEW_STATUS_OK
    }

    if ctx^.acc^.item_count > 0 {
        status := dynview_layout_finalize_line(
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
dynview_layout_handle_block_markers :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command) -> i32 {

    if cmd.kind == .BeginBlock {
        new_format := dynview_block_format_for_kind(cmd.style_id)
        spacing_status := dynview_layout_apply_block_spacing(ctx, new_format.paragraph_spacing_before)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = cmd.block_id
        ctx^.state^.active_block_kind = cmd.style_id
        ctx^.state^.active_block_format = new_format
        return DYNVIEW_STATUS_OK
    }

    if cmd.kind == .EndBlock {
        spacing_status := dynview_layout_apply_block_spacing(
            ctx,
            ctx^.state^.active_block_format.paragraph_spacing_after)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = -1
        ctx^.state^.active_block_kind = -1
        ctx^.state^.active_block_format = dynview_block_format_for_kind(-1)
        return DYNVIEW_STATUS_OK
    }

    return DYNVIEW_STATUS_OK
}

//   Consume one visible dynview command and update copy-row span.
dynview_layout_consume_visible_command :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    effective_style := dynview_style_with_block_format(style, ctx^.state^.active_block_format)
    status: i32 = DYNVIEW_STATUS_OK
    switch cmd.kind {
    case .TextRun:
        text := dynview_text_for_command(ctx^.buffer, cmd)
        status, _ = dynview_layout_consume_text_run(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, text, effective_style, ctx^.font_size)
    case .InlineLine:
        status, _ = dynview_layout_consume_inline_line(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, effective_style, ctx^.font_size)
    case .InlineBox:
        status, _ = dynview_layout_consume_inline_box(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, effective_style, ctx^.font_size)
    case .InlineCircle:
        status, _ = dynview_layout_consume_inline_circle(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, effective_style, ctx^.font_size)
    case .LineBreak, .Divider:
        status = dynview_layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
    case .BeginBlock, .EndBlock, .CopyableTextRun:
    }

    return status
}

//   Finalize total layout metrics after all commands are consumed.
dynview_layout_finalize_metrics :: proc(ctx: ^Dynview_Layout_Build_Context) -> i32 {
    status := dynview_layout_finalize_line(
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
dynview_rebuild_layout_cache :: proc(runtime: ^core.Ui_Dynview_Runtime) -> i32 {
    if runtime == nil {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    dynview_layout_reset_cache(cache)

    if buffer^.command_count <= 0 {
        dynview_layout_set_empty_default(cache)
        return DYNVIEW_STATUS_OK
    }

    state := Dynview_Layout_State{}
    acc := Dynview_Layout_Line_Accumulator{}
    ctx := dynview_layout_build_context(cache, buffer, &state, &acc)

    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        marker_status := dynview_layout_handle_block_markers(&ctx, cmd)
        if marker_status != DYNVIEW_STATUS_OK {
            return marker_status
        }

        style := dynview_style_by_id(cmd.style_id)
        status := dynview_layout_consume_visible_command(&ctx, cmd, style)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return dynview_layout_finalize_metrics(&ctx)
}

//   Return true when one layout line is outside the visible panel bounds.
dynview_layout_line_outside_panel :: #force_inline proc(
    line_top, line_bottom, panel_top, panel_bottom: f32) -> bool {

    return line_bottom < panel_top || line_top > panel_bottom
}

//   Draw one cached text item.
dynview_draw_cached_text_item :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

    text_end := item.text_offset + item.text_len
    if item.text_offset < 0 || item.text_len < 0 {
        return
    }
    if text_end > runtime^.command_buffer.text_bytes_len {
        return
    }

    text := string(runtime^.command_buffer.text_bytes[item.text_offset:text_end])
    draw_x := item_x
    if style.alignment == .Center && item.col_start == 0 {
        draw_x = panel.x + (panel.width - item.draw_width) * 0.5
    }

    if style.bold {
        ui_text(text, int(draw_x + 1), int(item_y), style.color, font, font_size)
    }

    if style.italic {
        draw_x += 1
    }

    ui_text(text, int(draw_x), int(item_y), style.color, font, font_size)
}

//   Draw one cached inline shape item.
dynview_draw_cached_inline_item :: proc(
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

    switch item.kind {
    case .InlineLine:
        center_y := item_y + item.draw_height * 0.5
        rl.DrawLineEx(
            rl.Vector2{item_x, center_y},
            rl.Vector2{item_x + item.draw_width, center_y},
            max(1.0, item.inline_atom_stroke),
            style.color)
    case .InlineBox:
        rl.DrawRectangleLinesEx(
            rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height},
            max(1.0, item.inline_atom_stroke),
            style.color)
    case .InlineCircle:
        center := rl.Vector2{item_x + item.draw_width * 0.5, item_y + item.draw_height * 0.5}
        rl.DrawCircleLines(i32(center.x), i32(center.y), item.draw_height * 0.5, style.color)
        if item.inline_atom_stroke > 1 {
            rl.DrawCircleLines(
                i32(center.x),
                i32(center.y),
                max(1.0, item.draw_height * 0.5 - 1),
                style.color)
        }
    case .TextRun:
    }
}

//   Draw one cached layout line and all its items.
dynview_draw_cached_line :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    line: core.Ui_Dynview_Layout_Line,
    line_top, text_padding, font_size: f32,
    font: rl.Font) {

    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := runtime^.compile_cache.layout_items[item_index]
        style := dynview_style_by_id(item.style_id)
        item_x := panel.x + text_padding + item.x_offset
        item_y := line_top + item.y_offset

        if item.kind == .TextRun {
            dynview_draw_cached_text_item(runtime, panel, font, font_size, style, item, item_x, item_y)
            continue
        }

        dynview_draw_cached_inline_item(style, item, item_x, item_y)
    }
}

//   Draw the canonical layout cache using explicit per-line baselines and offsets.
dynview_draw_cached_layout :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    scroll_y, text_padding, font_size: f32,
    font: rl.Font) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if !cache^.layout_is_valid {
        return
    }

    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    for line_index in 0..<cache^.layout_line_count {
        line := cache^.layout_lines[line_index]
        line_top := panel.y + text_padding + line.y_offset - scroll_y
        line_bottom := line_top + line.line_height
        if dynview_layout_line_outside_panel(line_top, line_bottom, panel_top, panel_bottom) {
            continue
        }

        dynview_draw_cached_line(runtime, panel, line, line_top, text_padding, font_size, font)
    }
}

//   Return fallback wrapped row count for plain-text rendering.
dynview_fallback_row_count :: #force_inline proc(
    panel: rl.Rectangle,
    wrap_advance: f32,
    fallback_text: string) -> int {

    max_cols := chars_per_text_row(panel.width - TEXT_PADDING * 2, wrap_advance)
    return count_wrapped_text_rows(fallback_text, max_cols)
}

//   Return total content height using cached line metrics, else fallback row math.
dynview_scratchpad_content_height_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    text_padding, wrap_advance, fallback_row_height: f32,
    fallback_text: string) -> f32 {

    fallback_rows := dynview_fallback_row_count(panel, wrap_advance, fallback_text)
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
dynview_scratchpad_scroll_step_or_fallback :: proc(
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
