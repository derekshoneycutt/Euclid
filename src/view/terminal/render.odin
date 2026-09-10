package terminalview

import "../../core"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"
import termattachment "../../terminal/attachment"
import termhist "../../terminal/history"
import termmodel "../../terminal/model"
import termpalette "../../terminal/palette"
import termshellintegration "../../terminal/shell_integration"
import "../input"
import "../font"

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

import rl "vendor:raylib"

//   Append streamed ANSI output through the bounded terminal interpreter.
//
// Notes:
//   - Supports reset, bold, italic, underline, normal/bright foreground
//     colors, and default foreground restoration.
//   - Consumes unsupported ANSI SGR parameters without exposing escape bytes.
//   - A bare `\r` (not part of `\r\n`) discards the runs written so far on
//     the current logical line, simulating progress-bar/spinner overwrite;
//     the current SGR style carries over across the reset.
//   - The active SGR style and any escape sequence left unterminated at the
//     end of `text` both persist on `term` across calls, since a streamed
//     evaluation delivers `text` in arbitrarily-cut chunks that can split a
//     sequence or leave a color open mid-chunk.
//
// Parameters:
//   - term: Terminal state owning the bounded output interpreter and grid.
//   - text: Arbitrarily chunked terminal byte stream to interpret.
//
// Side effects:
//   - Marks output started and mutates interpreter, grid, scrollback, title, and parser
//     diagnostics according to the received terminal stream.
terminal_append_ansi_output :: proc(
    term: ^core.Terminal_State, text: string,
    producer: termmodel.Terminal_Producer = {}) {
    if term == nil || term.history == nil {
        return
    }
    termemulator.interpreter_write(&term.output_interpreter, text, producer)
    if producer.kind != .None {
        term.output_producer = producer
    }
    term.output_started = true
}

//   Append one line of plain text to the terminal's scrollback, splitting it on any
//   embedded newlines so each becomes its own logical line.
//
// Notes:
//   - Output-run grouping only splits on a run's own trailing newline, not
//     embedded ones, so a multi-line result must be appended one line at a
//     time to render and select correctly.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - text: The text to append; may contain `\n` for multiple lines.
//
// Side effects:
//   - Appends one white output run per line via termhist.
terminal_append_output_line :: proc(term: ^core.Terminal_State, text: string) {
    if term == nil || term.history == nil {
        return
    }

    term.output_started = true
    termemulator.interpreter_write(&term.output_interpreter, text)
    termemulator.interpreter_write(&term.output_interpreter, "\n")
}

// Compute the initial vertical offset, following newly grown content to the bottom.
//
// Parameters:
//   - term: Terminal state carrying the prior frame's scroll metrics.
//   - padded_bounds: Visible scroll viewport after terminal padding.
//   - content_height: Current total terminal content height in pixels.
//
// Returns:
//   - Prior offset unless content height increased beyond the previous frame.
terminal_initial_scroll_offset :: proc(
    term: ^core.Terminal_State, padded_bounds: rl.Rectangle,
    content_height: f32) -> f32 {
    offset_y := term.scroll_offset_y
    if content_height > term.scroll_content_height {
        offset_y = content_height - padded_bounds.height
    }
    return offset_y
}

// Resolve the active or synchronized grid row containing an output cursor.
terminal_output_cursor_cells :: proc(
    term: ^core.Terminal_State, cursor: termgrid.Cursor) -> ([]termgrid.Cell, bool) {
    if term.synchronized_output.active {
        return termgrid.display_checkpoint_grid_row(
            &term.synchronized_output.checkpoint, cursor.row)
    }
    if cursor.row < 0 || cursor.row >= len(term.output_grid.rows) {
        return nil, false
    }
    return term.output_grid.rows[cursor.row].cells, true
}

//   Resolve the active grid cursor into combined scrollback/output coordinates.
//
// Parameters:
//   - term: Terminal state carrying interpreter visibility and active-grid cursor state.
//   - window_focused: Whether the cursor should use its focused filled presentation.
//
// Returns:
//   - A visible cursor presentation with combined line, column, width, and style, or
//     an empty presentation when output cursor rendering is not applicable.
terminal_output_cursor_presentation :: proc(
    term: ^core.Terminal_State,
    window_focused: bool = true) -> Terminal_Output_Cursor_Presentation {
    if term == nil || terminal_prompt_visible(term) {
        return {}
    }
    output_started := term.output_started
    cursor := term.output_grid.cursor
    cursor_visible := term.output_interpreter.cursor_visible
    if term.synchronized_output.active {
        output_started = term.synchronized_output.captured_output_started
        cursor = term.synchronized_output.checkpoint.grid_cursor
        cursor_visible = term.synchronized_output.captured_cursor_visible
    }
    if !output_started || !cursor_visible {
        return {}
    }
    cells, ok := terminal_output_cursor_cells(term, cursor)
    if !ok || cursor.column < 0 || cursor.column >= len(cells) {
        return {}
    }
    width := 1
    cell := &cells[cursor.column]
    if !cell.continuation && cell.grapheme_len > 0 {
        width = max(int(cell.width), 1)
    }
    return {
        visible = true,
        style = .Filled if window_focused else .Outline,
        line = terminal_visible_scrollback_count(term) + cursor.row,
        column = cursor.column,
        width = width,
    }
}

//   Resolve terminal geometry, font, and ordered selection for one frame.
//
// Parameters:
//   - term: Terminal state supplying geometry, content, cursor, and selection state.
//   - font_resolver: Borrowing capability for the regular terminal font.
//   - bounds: Full terminal panel bounds before semantic padding and geometry limits.
//
// Returns:
//   - Frame-local layout metrics and ordered selection used by terminal drawing.
terminal_draw_layout :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    bounds: rl.Rectangle,
    theme: Terminal_Draw_Theme) -> Terminal_Draw_Layout {
    padded_bounds := terminal_accepted_padded_bounds(term, bounds)
    line_height := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    regular := terminal_font_resolve(font_resolver, .Regular)
    line_count := terminal_line_count(term)
    prompt_visible := terminal_prompt_visible(term)
    prompt_line_count := 0
    if prompt_visible {
        prompt_line_count = terminal_live_input_line_count(term)
    }
    content_line_count := line_count + prompt_line_count
    output_cursor := terminal_output_cursor_presentation(term)
    if output_cursor.visible {
        content_line_count = max(content_line_count, output_cursor.line + 1)
    }
    content_height := f32(content_line_count) * line_height
    content_height = max(content_height, terminal_raster_content_height(
        term, terminal_column_width(regular), line_height))
    selection_start, selection_end := terminal_selection_ordered(
        term.view_selection_anchor, term.view_selection_head)
    return {
        padded_bounds = padded_bounds,
        line_height = line_height,
        line_count = line_count,
        prompt_visible = prompt_visible,
        content_height = content_height,
        selection = {selection_start, selection_end,
            padded_bounds.x + padded_bounds.width},
        regular = regular,
        theme = theme,
    }
}

// Draw the grapheme inverted inside one filled output cursor.
terminal_draw_output_cursor_glyph :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    presentation: Terminal_Output_Cursor_Presentation, position: rl.Vector2,
    theme: Terminal_Draw_Theme) {
    cells, ok := terminal_output_row(term, presentation.line)
    if !ok || presentation.column >= len(cells) { return }
    cell := &cells[presentation.column]
    if cell.continuation || cell.grapheme_len == 0 { return }
    text: [termgrid.CELL_GRAPHEME_CAPACITY + 1]u8
    copy(text[:], cell.grapheme[:cell.grapheme_len])
    resolved := terminal_font_resolve(
        font_resolver, terminal_font_key_for_cell(cell.style))
    rl.DrawTextEx(resolved, cast(cstring)&text[0], position,
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, theme.cursor_foreground)
}

//   Draw the active ANSI output-grid cursor after its row and selection overlays.
//
// Parameters:
//   - term: Terminal state supplying the active cursor cell for filled rendering.
//   - font_resolver: Borrowing capability for regular and styled cursor-cell fonts.
//   - presentation: Resolved visibility, style, combined position, and semantic width.
//   - origin: Top-left draw origin of the combined terminal content.
//   - line_height: Pixel pitch between terminal rows.
//
// Side effects:
//   - Issues Raylib rectangle and optional inverted cursor-glyph draw commands.
terminal_draw_output_cursor :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    presentation: Terminal_Output_Cursor_Presentation,
    layout: Terminal_Draw_Layout, origin: rl.Vector2) {
    if !presentation.visible {
        return
    }
    regular := terminal_font_resolve(font_resolver, .Regular)
    column_width := terminal_column_width(regular)
    position := rl.Vector2{
        origin.x + f32(presentation.column) * column_width,
        origin.y + f32(presentation.line) * layout.line_height,
    }
    cursor_color := terminal_packed_color(
        termpalette.terminal_palette_cursor_rgba(
            &term.output_interpreter.title_state.palette))
    if presentation.style == .Outline {
        rl.DrawRectangleLinesEx(rl.Rectangle{
            position.x, position.y,
            f32(presentation.width) * column_width, TERMINAL_FONT_SIZE,
        }, 1, cursor_color)
        return
    }
    rl.DrawRectangleV(position, rl.Vector2{
        f32(presentation.width) * column_width, TERMINAL_FONT_SIZE},
        cursor_color)
    terminal_draw_output_cursor_glyph(
        term, font_resolver, presentation, position, layout.theme)
}

//   Draw every materialized output row and its selection overlay.
//
// Parameters:
//   - term: Terminal state supplying rows and active selection state.
//   - font_resolver: Borrowing capability for semantic output fonts.
//   - layout: Frame-local line, spacing, selection, and regular-font metrics.
//   - origin: Top-left draw origin of the combined terminal content.
//
// Side effects:
//   - Issues row glyph and active-selection draw commands in display order.
terminal_draw_output_rows :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    layout: Terminal_Draw_Layout, origin: rl.Vector2,
    hover: Terminal_Link_Hit) {

    for index in 0..<layout.line_count {
        line_position := rl.Vector2{
            origin.x, origin.y + f32(index) * layout.line_height}
        if cells, ok := terminal_output_row(term, index); ok {
            shaping_allowed := true
            if term.view_selection_active {
                line_text := terminal_line_text(term, index)
                span := terminal_selection_span_for_line(
                    layout.selection.start, layout.selection.end,
                    index, len(line_text))
                shaping_allowed = !span.has_selection
            }
            row := Terminal_Shaped_Output_Context{
                font_resolver, cells, line_position,
                &term.output_interpreter.title_state.palette,
                terminal_column_width(layout.regular), layout.theme}
            terminal_draw_output_row(row, shaping_allowed)
            if hover.kind != .None && hover.line == index {
                terminal_draw_link_hover(row, hover)
            }
        }
        terminal_draw_line_selection(
            term, index, layout, line_position)
    }
}

// Resolve a command completion status to one restrained gutter-mark color.
terminal_command_status_color :: proc(status: i32) -> rl.Color {
    return rl.Color{0x38, 0x98, 0x26, 0xFF} if status == 0 else
        rl.Color{0xCB, 0x3C, 0x33, 0xFF}
}

// Draw retained command completion outcomes without inserting terminal text.
terminal_draw_command_statuses :: proc(
    term: ^core.Terminal_State, layout: Terminal_Draw_Layout,
    origin: rl.Vector2) {
    count := termshellintegration.shell_command_block_count(term.shell_integration)
    for index in 0..<count {
        block, present := termshellintegration.shell_command_block(
            term.shell_integration, index)
        if !present || .Finished not_in block.present || !block.status_present {
            continue
        }
        position, found := terminal_semantic_view_position(term, block.finished)
        if !found { continue }
        rl.DrawRectangleRec(rl.Rectangle{
            origin.x, origin.y + f32(position.line) * layout.line_height + 3,
            2, TERMINAL_FONT_SIZE - 6,
        }, terminal_command_status_color(block.status))
    }
}

// Draw the active local command-search query as a compact bottom status strip.
terminal_draw_command_search :: proc(
    term: ^core.Terminal_State, font: rl.Font,
    bounds: rl.Rectangle, theme: Terminal_Draw_Theme) {
    shell := term.shell_integration
    if shell == nil || !shell.search_editing { return }
    query := string(shell.search_query[:shell.search_query_byte_count])
    height := TERMINAL_FONT_SIZE + 6
    position := rl.Vector2{bounds.x + 4, bounds.y + bounds.height - height + 3}
    background := theme.cursor_foreground
    rl.DrawRectangleRec(rl.Rectangle{
        bounds.x, bounds.y + bounds.height - height, bounds.width, height,
    }, background)
    rl.DrawTextEx(font, fmt.ctprintf("find: %s", query), position,
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, theme.default_foreground)
}

//   Find the combined presented line for one stable logical-row identity.
//
// Returns:
//   - Zero-based line and true, or zero and false when the row is not presented.
terminal_raster_line :: proc(
    term: ^core.Terminal_State, logical_row: i64) -> (int, bool) {
    if term == nil { return 0, false }
    line_count := terminal_visible_scrollback_count(term)
    line_count += len(term.synchronized_output.checkpoint.grid_rows) if
        term.synchronized_output.active else len(term.output_grid.rows)
    for line in 0..<line_count {
        candidate, found := terminal_output_logical_row(term, line)
        if found && candidate == logical_row { return line, true }
    }
    return 0, false
}

//   Resolve and validate one placement's source rectangle against intrinsic metrics.
terminal_raster_source :: proc(
    geometry: termattachment.Placement_Geometry,
    metrics: termattachment.Intrinsic_Metrics) ->
    (termattachment.Pixel_Rectangle, bool) {
    source := geometry.source
    if source.width == 0 && source.height == 0 {
        source = {width = metrics.width, height = metrics.height}
    }
    valid := source.x >= 0 && source.y >= 0 &&
        source.width > 0 && source.height > 0 &&
        source.x + source.width <= metrics.width &&
        source.y + source.height <= metrics.height
    return source, valid
}

//   Resolve one placement's positive pixel allocation from pixel, cell, or source size.
terminal_raster_allocation :: proc(
    geometry: termattachment.Placement_Geometry,
    source: termattachment.Pixel_Rectangle,
    column_width, line_height: f32) -> rl.Vector2 {
    width := f32(geometry.pixel_width)
    height := f32(geometry.pixel_height)
    if width <= 0 && geometry.column_span > 0 {
        width = f32(geometry.column_span) * column_width
    }
    if height <= 0 && geometry.row_span > 0 {
        height = f32(geometry.row_span) * line_height
    }
    if width <= 0 { width = f32(source.width) }
    if height <= 0 { height = f32(source.height) }
    return {width, height}
}

// Apply fit, centered, or fill sizing to mutable raster source and destination.
terminal_raster_apply_sizing :: proc(
    sizing: termattachment.Sizing_Mode, source: ^termattachment.Pixel_Rectangle,
    destination: ^termattachment.Render_Rectangle, allocation: rl.Vector2) {
    source_ratio := f32(source.width) / f32(source.height)
    allocation_ratio := allocation.x / allocation.y
    if sizing == .Fit || sizing == .Intrinsic_Centered {
        scale := min(allocation.x / f32(source.width),
            allocation.y / f32(source.height))
        if sizing == .Intrinsic_Centered { scale = min(scale, 1) }
        destination.width = f32(source.width) * scale
        destination.height = f32(source.height) * scale
        destination.x += (allocation.x - destination.width) / 2
        destination.y += (allocation.y - destination.height) / 2
    } else if sizing == .Fill && source_ratio != allocation_ratio {
        if source_ratio > allocation_ratio {
            width := max(1, int(f32(source.height) * allocation_ratio))
            source.x += (source.width - width) / 2
            source.width = width
        } else {
            height := max(1, int(f32(source.width) / allocation_ratio))
            source.y += (source.height - height) / 2
            source.height = height
        }
    }
}

//   Resolve source crop and destination extent for one placement allocation.
//
// Returns:
//   - Complete positive geometry only when source and sizing policy are valid.
terminal_raster_geometry :: proc(
    placement: termattachment.Placement_Metadata,
    metrics: termattachment.Intrinsic_Metrics,
    anchor: rl.Vector2, column_width, line_height: f32) -> Terminal_Raster_Geometry {
    geometry := placement.geometry
    source, source_valid := terminal_raster_source(geometry, metrics)
    if !source_valid { return {} }
    allocation := terminal_raster_allocation(
        geometry, source, column_width, line_height)
    destination := termattachment.Render_Rectangle{
        x = anchor.x + f32(geometry.content_offset_x),
        y = anchor.y + f32(geometry.content_offset_y),
        width = allocation.x,
        height = allocation.y,
    }
    terminal_raster_apply_sizing(
        geometry.sizing, &source, &destination, allocation)
    return {source = source, destination = destination, valid = true}
}

//   Report whether a placement belongs to one terminal raster layer.
terminal_raster_in_layer :: proc(z_index: i32, layer: Terminal_Raster_Layer) -> bool {
    return z_index < 0 if layer == .Behind_Text else z_index >= 0
}

// Collect the active live or synchronized placement snapshot for drawing.
terminal_collect_raster_placements :: proc(
    term: ^core.Terminal_State,
    placements: []termattachment.Placement_Metadata) -> int {
    screen := termattachment.Screen_Identity.Alternate if
        term.output_interpreter.alternate_screen_active else .Primary
    if term.synchronized_output.active {
        screen = .Alternate if
            term.synchronized_output.captured_alternate_screen_active else .Primary
        return termattachment.placement_checkpoint_collect(
            &term.synchronized_output.checkpoint.placements, screen, placements)
    }
    return termattachment.placements_collect(
        term.synchronized_output.attachments, screen, placements)
}

// Draw one placement when its layer, row, metrics, and geometry resolve.
terminal_draw_raster :: proc(
    term: ^core.Terminal_State, renderer: termattachment.Raster_Renderer,
    placement: termattachment.Placement_Metadata,
    draw: Terminal_Raster_Draw_Context) {
    if !terminal_raster_in_layer(placement.geometry.z_index, draw.layer) { return }
    line, found := terminal_raster_line(term, placement.geometry.logical_row)
    metrics, metrics_found := termattachment.attachment_metrics(
        term.synchronized_output.attachments, placement.attachment_id)
    if !found || !metrics_found { return }
    anchor := rl.Vector2{
        draw.origin.x + f32(placement.geometry.column) * draw.column_width,
        draw.origin.y + f32(line) * draw.layout.line_height,
    }
    geometry := terminal_raster_geometry(
        placement, metrics, anchor, draw.column_width, draw.layout.line_height)
    if !geometry.valid { return }
    renderer.draw(renderer.user_data, {
        attachment_id = placement.attachment_id, source = geometry.source,
        destination = geometry.destination,
        clip = {x = draw.layout.padded_bounds.x, y = draw.layout.padded_bounds.y,
            width = draw.layout.padded_bounds.width,
            height = draw.layout.padded_bounds.height},
        z_index = placement.geometry.z_index,
    })
}

// Return the lowest drawable raster edge in terminal content coordinates.
terminal_raster_content_height :: proc(
    term: ^core.Terminal_State, column_width, line_height: f32) -> f32 {
    if term == nil { return 0 }
    placements:
        [termattachment.DEFAULT_PLACEMENT_CAPACITY]termattachment.Placement_Metadata
    count := terminal_collect_raster_placements(term, placements[:])
    content_height: f32
    for placement in placements[:count] {
        line, found := terminal_raster_line(term, placement.geometry.logical_row)
        metrics, metrics_found := termattachment.attachment_metrics(
            term.synchronized_output.attachments, placement.attachment_id)
        if !found || !metrics_found { continue }
        geometry := terminal_raster_geometry(placement, metrics,
            {0, f32(line) * line_height}, column_width, line_height)
        if geometry.valid {
            content_height = max(content_height,
                geometry.destination.y + geometry.destination.height)
        }
    }
    return content_height
}

//   Draw one z-index partition of captured or live placements through a
//   display-owned renderer capability.
terminal_draw_rasters :: proc(
    term: ^core.Terminal_State, renderer: termattachment.Raster_Renderer,
    layout: Terminal_Draw_Layout, origin: rl.Vector2,
    layer: Terminal_Raster_Layer) {
    if renderer.draw == nil { return }
    placements:
        [termattachment.DEFAULT_PLACEMENT_CAPACITY]termattachment.Placement_Metadata
    count := terminal_collect_raster_placements(term, placements[:])
    column_width := terminal_column_width(layout.regular)
    draw := Terminal_Raster_Draw_Context{layout, origin, layer, column_width}
    for placement in placements[:count] {
        terminal_draw_raster(term, renderer, placement, draw)
    }
}

// Retain UI-owned scrolling results in terminal presentation state.
terminal_commit_scroll :: proc(
    term: ^core.Terminal_State, offset_y, content_height: f32) {
    term.scroll_offset_y = offset_y
    term.scroll_content_height = content_height
}

// Draw terminal foreground overlays after output rows and rasters.
terminal_draw_foreground :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    layout: Terminal_Draw_Layout, origin: rl.Vector2,
    frame: input.Input_Frame) {
    terminal_draw_output_cursor(
        term, font_resolver,
        terminal_output_cursor_presentation(term, frame.window_focused),
        layout, origin)
    if layout.prompt_visible {
        terminal_draw_prompt(
            term, font_resolver, layout,
            rl.Vector2{origin.x,
                origin.y + f32(layout.line_count) * layout.line_height})
    }
    if term.view_selection_active {
        terminal_draw_virtual_selection_rows(
            layout, origin)
    }
}

// Draw terminal content at an origin established by the owning UI container.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - font_resolver: The borrowing capability for semantic font variants.
//   - raster_renderer: Display-owned raster rendering capability.
//   - draw: Prepared layout, UI-owned origin, bounds, and input frame.
//
// Side effects:
//   - Issues terminal raster, text, cursor, prompt, and search draw commands.
terminal_draw_content :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    raster_renderer: termattachment.Raster_Renderer,
    draw: Terminal_Draw_Content_Context) {
    hover := terminal_hyperlink_hover_hit(term, draw.frame, draw.bounds)
    terminal_draw_rasters(
        term, raster_renderer, draw.layout, draw.origin, .Behind_Text)
    terminal_draw_output_rows(
        term, font_resolver, draw.layout, draw.origin, hover)
    terminal_draw_command_statuses(term, draw.layout, draw.origin)
    terminal_draw_rasters(
        term, raster_renderer, draw.layout, draw.origin, .In_Front_Of_Text)
    terminal_draw_foreground(
        term, font_resolver, draw.layout, draw.origin, draw.frame)
}

// Draw terminal overlays after the owning UI container closes its scissor region.
terminal_draw_overlays :: proc(
    term: ^core.Terminal_State, layout: Terminal_Draw_Layout) {
    terminal_draw_command_search(
        term, layout.regular, layout.padded_bounds, layout.theme)
}

//   Return wheel input reserved for local scrolling under current mouse modes.
//
// Parameters:
//   - term: Terminal state supplying negotiated mouse reporting mode.
//   - frame: Polled input frame containing wheel delta and mouse modifiers.
//
// Returns:
//   - Zero while the foreground session owns unshifted mouse reporting; otherwise the
//     frame's wheel delta for local scroll handling.
terminal_local_wheel_delta :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame) -> f32 {
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    if mode.mouse_tracking != .None && mode.mouse_sgr_encoding &&
        .Shift not_in frame.mouse_modifiers {
        return 0
    }
    return frame.mouse_wheel_delta
}

//   Shrink a rectangle by the terminal's edge padding on all sides.
//
// Parameters:
//   - bounds: The full rectangle the terminal is drawn within.
//
// Returns:
//   - The padded rectangle content is laid out and hit-tested within.
terminal_padded_bounds :: proc(bounds: rl.Rectangle) -> rl.Rectangle {
    return rl.Rectangle{
        bounds.x + TERMINAL_PADDING, bounds.y + TERMINAL_PADDING,
        bounds.width - TERMINAL_PADDING * 2, bounds.height - TERMINAL_PADDING * 2,
    }
}

//   Resolve the semantic cell rectangle within the padded terminal panel.
//
// Parameters:
//   - term: Terminal state carrying accepted cell dimensions and measured pitch.
//   - bounds: Full terminal panel bounds before padding and semantic clamping.
//
// Returns:
//   - Padded bounds clamped to accepted grid dimensions when geometry is measurable.
terminal_accepted_padded_bounds :: proc(
    term: ^core.Terminal_State, bounds: rl.Rectangle) -> rl.Rectangle {
    padded := terminal_padded_bounds(bounds)
    if term.geometry.column_width <= 0 || term.geometry.line_height <= 0 {
        return padded
    }
    padded.width = min(padded.width,
        f32(term.geometry.dimensions.columns) * term.geometry.column_width)
    padded.height = min(padded.height,
        f32(term.geometry.dimensions.rows) * term.geometry.line_height)
    return padded
}

//   Resolve screen space into one-based coordinates of the live visible grid.
//
// Parameters:
//   - term: Terminal state carrying accepted dimensions and measured cell pitch.
//   - frame: Polled input frame whose screen-space pointer fields are preserved.
//   - bounds: Full terminal panel bounds used to resolve the semantic grid rectangle.
//
// Returns:
//   - A copy of the frame enriched with clamped one-based terminal coordinates,
//     inside-state, validity, and Shift-based foreground ownership.
terminal_resolve_mouse_frame :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame,
    bounds: rl.Rectangle) -> input.Input_Frame {
    result := frame
    if term == nil || term.geometry.column_width <= 0 ||
        term.geometry.line_height <= 0 ||
        term.geometry.dimensions.columns == 0 ||
        term.geometry.dimensions.rows == 0 {
        return result
    }
    padded := terminal_accepted_padded_bounds(term, bounds)
    mouse := rl.Vector2{result.mouse_position.x, result.mouse_position.y}
    result.terminal_mouse_inside = rl.CheckCollisionPointRec(mouse, padded)
    relative_x := math.clamp(mouse.x - padded.x, f32(0),
        math.max(padded.width - 1, f32(0)))
    relative_y := math.clamp(mouse.y - padded.y, f32(0),
        math.max(padded.height - 1, f32(0)))
    result.terminal_mouse_position = {
        column = int(relative_x / term.geometry.column_width) + 1,
        row = int(relative_y / term.geometry.line_height) + 1,
    }
    result.terminal_mouse_pixel_position = {
        column = int(relative_x) + 1,
        row = int(relative_y) + 1,
    }
    result.terminal_mouse_position_valid = true
    result.terminal_mouse_owned = .Shift not_in result.mouse_modifiers
    return result
}

//   Draw one scrollback line's selection highlight, if the selection covers it.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - font: The monospace font used for terminal text.
//   - line: The scrollback run's combined line index.
//   - selection: The selection's ordered start/end positions.
//   - line_position: The top-left screen position of the line.
//
// Side effects:
//   - May issue Raylib highlight and inverted-text commands for the selected span.
terminal_draw_line_selection :: proc(
    term: ^core.Terminal_State, line: int,
    layout: Terminal_Draw_Layout, line_position: rl.Vector2) {
    if !term.view_selection_active {
        return
    }

    line_text := terminal_line_text(term, line)
    span := terminal_selection_span_for_line(
        layout.selection.start, layout.selection.end, line, len(line_text))
    if span.has_selection {
        terminal_draw_inverted_span({
            font = layout.regular,
            text = line_text,
            position = line_position,
            theme = layout.theme,
        }, span, layout.selection.right_edge_x)
    }
}

//   Draw selection highlight for any virtual blank rows the active selection
//   reaches below the live prompt line.
//
// Notes:
//   - Reuses the same per-line span computation and rendering as real lines
//     with an empty line text, so a partial start/end column within a blank
//     row (rather than always the row's full width) renders correctly.
//   - Callers must only invoke this while the view selection is active.
//
// Parameters:
//   - font: The monospace font used for measuring virtual columns.
//   - line_count: The prompt line's combined line index; the last real line.
//   - selection: The selection's ordered start/end positions and right edge.
//   - origin: The scrollback viewport's drawing origin.
//   - line_height: The pixel height of one terminal row.
//
// Side effects:
//   - Issues Raylib highlight commands for selected blank rows below real content.
terminal_draw_virtual_selection_rows :: proc(
    layout: Terminal_Draw_Layout, origin: rl.Vector2) {
    if layout.selection.end.line <= layout.line_count {
        return
    }

    for line := layout.line_count + 1;
        line <= layout.selection.end.line; line += 1 {
        span := terminal_selection_span_for_line(
            layout.selection.start, layout.selection.end, line, 0)
        if !span.has_selection {
            continue
        }

        row_position := rl.Vector2{
            origin.x, origin.y + f32(line) * layout.line_height}
        terminal_draw_inverted_span({
            font = layout.regular,
            text = "",
            position = row_position,
            theme = layout.theme,
        }, span, layout.selection.right_edge_x)
    }
}

//   Resolve the active selection span for one single-line prompt.
//
// Parameters:
//   - term: Terminal state indicating whether view selection is active.
//   - selection: Ordered combined-content selection bounds and viewport edge.
//   - line_count: Combined line index occupied by the single-line prompt.
//   - prompt_length: Prompt-prefixed line length in bytes.
//
// Returns:
//   - Prompt-local selection bounds, or an empty span when selection is inactive.
terminal_prompt_selection :: proc(
    term: ^core.Terminal_State, selection: Terminal_Selection_Bounds,
    line_count, prompt_length: int) -> Terminal_Line_Selection {

    if !term.view_selection_active {
        return {}
    }
    result := terminal_selection_span_for_line(
        selection.start, selection.end, line_count, prompt_length)
    result.right_edge_x = selection.right_edge_x
    return result
}

//   Convert prompt overlay byte ranges into current-text-local shaping exclusions.
//
// Parameters:
//   - current_text: Editable text without its prompt prefix.
//   - prompt_prefix: Prefix prepended to the editable text for display.
//   - cursor_position: Cursor byte offset in prompt-prefixed coordinates.
//   - selection: Selection span in prompt-prefixed coordinates.
//
// Returns:
//   - Cursor and selection ranges clamped to the editable text byte interval.
terminal_prompt_shape_exclusions :: proc(
    current_text, prompt_prefix: string, cursor_position: int,
    selection: Terminal_Line_Selection) -> Terminal_Prompt_Shape_Exclusions {

    cursor_start := cursor_position - len(prompt_prefix)
    return {
        cursor_start = cursor_start,
        cursor_end = terminal_codepoint_end(current_text, cursor_start),
        selection_start = math.clamp(
            selection.start - len(prompt_prefix), 0, len(current_text)),
        selection_end = math.clamp(
            selection.end - len(prompt_prefix), 0, len(current_text)),
    }
}

//   Draw the live prompt line, including its selection highlight and cursor.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - font_resolver: The borrowing capability for semantic font variants.
//   - line_count: The prompt line's combined line index.
//   - selection: The selection's ordered start/end positions.
//   - prompt_position: The top-left screen position of the prompt line.
//
// Side effects:
//   - Issues Raylib commands for prompt text, completion preview, selection, and cursor.
terminal_draw_prompt :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    layout: Terminal_Draw_Layout, prompt_position: rl.Vector2) {

    regular := terminal_font_resolve(font_resolver, .Regular)
    current_text := termhist.termhist_current_text(term.history)
    prompt_prefix := terminal_prompt_prefix(term)
    prompt_color := terminal_prompt_draw_color(term.input_mode)
    prompt_text := fmt.tprintf("%s%s", prompt_prefix, current_text)

    if strings.index_byte(current_text, '\n') >= 0 {
        terminal_draw_prompt_lines(
            term, font_resolver, prompt_position, layout.theme)
        terminal_draw_multiline_prompt_cursor(
            term, regular, prompt_position, layout.theme)
        return
    }

    prompt_selection := terminal_prompt_selection(
        term, layout.selection, layout.line_count, len(prompt_text))
    cursor_position := termhist.termhist_cursor(term.history) + len(prompt_prefix)
    terminal_draw_prompt_base({
        resolver = font_resolver,
        current_text = current_text,
        prompt_prefix = prompt_prefix,
        prompt_color = prompt_color,
        position = prompt_position,
        exclusions = terminal_prompt_shape_exclusions(
            current_text, prompt_prefix, cursor_position, prompt_selection),
        theme = layout.theme,
    })
    terminal_draw_completion_preview(
        term, regular, prompt_position, layout.theme)
    terminal_draw_prompt_overlay({
        font = regular,
        text = prompt_text,
        position = prompt_position,
        theme = layout.theme,
    }, cursor_position, prompt_selection)
}

//   Draw one physical multiline prompt row and return the next source byte offset.
//
// Parameters:
//   - request: Terminal, source, row, cursor, style, resolver, and draw-position inputs.
//
// Returns:
//   - The global source byte offset immediately after this row's newline delimiter.
//
// Side effects:
//   - Draws the row prefix and text with cursor and selection shaping exclusions.
terminal_draw_prompt_line :: proc(
    request: Terminal_Multiline_Prompt_Row_Draw) -> int {

    line_text := terminal_live_input_line_text(request.text, request.line)
    line_end := request.line_start + len(line_text)
    prefix := TERMINAL_CONTINUATION_PROMPT
    if request.line == 0 {
        prefix = terminal_primary_prompt_prefix(request.term)
    }
    cursor_start, cursor_end := -1, -1
    if request.cursor >= request.line_start && request.cursor <= line_end {
        cursor_start = request.cursor - request.line_start
        cursor_end = terminal_codepoint_end(line_text, cursor_start)
    }
    selection_start, selection_end := -1, -1
    if request.term.view_selection_active {
        selection_start = 0
        selection_end = len(line_text)
    }
    terminal_draw_prompt_base({
        resolver = request.resolver,
        current_text = line_text,
        prompt_prefix = prefix,
        prompt_color = request.prompt_color,
        position = request.position,
        exclusions = {
            cursor_start = cursor_start,
            cursor_end = cursor_end,
            selection_start = selection_start,
            selection_end = selection_end,
        },
        theme = request.theme,
    })
    return line_end + 1
}

//   Draw every physical row of the editable multiline prompt.
//
// Parameters:
//   - term: Terminal state supplying live cursor and selection state.
//   - font_resolver: Borrowing capability for prompt fonts.
//   - text: Complete editable source containing one or more physical rows.
//   - prompt_color: Draw color for mode-specific row prefixes.
//   - position: Top-left screen position of the first physical row.
//
// Side effects:
//   - Draws the mode-specific primary prefix on row zero and aligned continuation
//     prefixes on subsequent rows without mutating terminal state.
terminal_draw_prompt_lines :: proc(
    term: ^core.Terminal_State, font_resolver: font.Font_Resolver,
    position: rl.Vector2, theme: Terminal_Draw_Theme) {
    text := termhist.termhist_current_text(term.history)
    prompt_color := terminal_prompt_draw_color(term.input_mode)
    line_height := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    cursor := termhist.termhist_cursor(term.history)
    line_start := 0
    for line := 0; line < terminal_live_input_line_count(term); line += 1 {
        line_position := rl.Vector2{position.x, position.y + f32(line) * line_height}
        line_start = terminal_draw_prompt_line({
            term = term,
            resolver = font_resolver,
            text = text,
            prompt_color = prompt_color,
            position = line_position,
            line = line,
            line_start = line_start,
            cursor = cursor,
            theme = theme,
        })
    }
}

//   Draw the cursor on the physical row containing the current editor cursor.
//
// Notes:
//   - Converts the editor's global UTF-8 byte offset into row-local prompt coordinates.
//
// Parameters:
//   - term: Terminal state supplying editable text, cursor, and prompt mode.
//   - font: Monospace font used to measure and draw the cursor cell.
//   - position: Top-left screen position of the multiline prompt.
//
// Side effects:
//   - Issues Raylib commands for the block cursor and inverted cursor glyph.
terminal_draw_multiline_prompt_cursor :: proc(
    term: ^core.Terminal_State, font: rl.Font, position: rl.Vector2,
    theme: Terminal_Draw_Theme) {
    text := termhist.termhist_current_text(term.history)
    cursor := termhist.termhist_cursor(term.history)
    line := 0
    line_start := 0
    for byte, index in text[:cursor] {
        if byte == '\n' {
            line += 1
            line_start = index + 1
        }
    }
    line_text := terminal_live_input_line_text(text, line)
    prefix := TERMINAL_CONTINUATION_PROMPT
    if line == 0 {
        prefix = terminal_primary_prompt_prefix(term)
    }
    prompt_text := fmt.tprintf("%s%s", prefix, line_text)
    cursor_position := cursor - line_start + len(prefix)
    line_height := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    cursor_position_y := position
    cursor_position_y.y += f32(line) * line_height
    terminal_draw_cursor({
        font = font,
        text = prompt_text,
        position = cursor_position_y,
        theme = theme,
    }, cursor_position, false)
}

//   Draw a muted completion insertion without mutating the live input text.
//
// Notes:
//   - Clears the source replacement range first, so Unicode replacements such
//     as `\alpha` preview as `α` rather than appearing beside their source.
//
// Parameters:
//   - term: Terminal state supplying correlated preview and input snapshot state.
//   - font: Monospace font used to measure and draw preview text.
//   - current_text: Current editable input without its prompt prefix.
//   - prompt_prefix: Prefix prepended to current input for display.
//   - position: Top-left screen position of the prompt line.
//
// Side effects:
//   - Issues Raylib replacement-mask and muted preview-text draw commands when current.
terminal_draw_completion_preview :: proc(
    term: ^core.Terminal_State, font: rl.Font,
    position: rl.Vector2, theme: Terminal_Draw_Theme) {
    current_text := termhist.termhist_current_text(term.history)
    prompt_prefix := terminal_prompt_prefix(term)
    if len(term.completion_preview_insertion) == 0 ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return
    }

    start := math.clamp(term.completion_preview_start, 0, len(current_text))
    end := math.clamp(term.completion_preview_end, start, len(current_text))
    prefix_width := terminal_measure_prefix_width(font, prompt_prefix)
    start_x := position.x + prefix_width + terminal_position_x(font, current_text, start)
    end_x := position.x + prefix_width + terminal_position_x(font, current_text, end)
    preview_position := rl.Vector2{start_x, position.y}

    if end > start {
        rl.DrawRectangleV(
            preview_position, rl.Vector2{end_x - start_x, TERMINAL_FONT_SIZE},
            theme.cursor_foreground)
    }
    rl.DrawTextEx(
        font, fmt.ctprintf("%s", term.completion_preview_insertion), preview_position,
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, TERMINAL_COMPLETION_PREVIEW_COLOR)
}

//   Draw the live input line's base text: a bold prompt (green for `julia>`,
//   yellow for `help?>`) followed by the plain white typed text.
//
// Parameters:
//   - request: Prompt prefix, editable text, colors, shaping exclusions, resolver, and
//     screen position required to draw one prompt row.
//
// Side effects:
//   - Issues Raylib commands for the bold mode prefix and shaped or fallback input text.
terminal_draw_prompt_base :: proc(request: Terminal_Prompt_Draw) {
    bold := terminal_font_resolve(request.resolver, .Bold)
    regular := terminal_font_resolve(request.resolver, .Regular)
    if terminal_text_has_visible_bytes(request.prompt_prefix) {
        rl.DrawTextEx(bold, fmt.ctprintf("%s", request.prompt_prefix), request.position,
            TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, request.prompt_color)
    }

    prompt_width := terminal_measure_prefix_width(bold, request.prompt_prefix)
    terminal_draw_prompt_text({
        resolver = request.resolver,
        current_text = request.current_text,
        regular = regular,
        position = {
            request.position.x + prompt_width, request.position.y},
        exclusions = request.exclusions,
        color = request.theme.default_foreground,
    })
}

// Return whether terminal text contains a byte with visible ink potential.
terminal_text_has_visible_bytes :: proc(text: string) -> bool {
    for byte in transmute([]u8)text {
        if byte > ' ' { return true }
    }
    return false
}

//   Report whether one prompt byte may join an ASCII contextual-alternate run.
//
// Parameters:
//   - text: Editable prompt text whose byte is classified.
//   - offset: Byte offset to test.
//   - exclusions: Cursor and selection ranges that must remain independently drawable.
//
// Returns:
//   - True for visible printable ASCII outside cursor and selection overlays.
terminal_prompt_byte_shapeable :: proc(
    text: string, offset: int,
    exclusions: Terminal_Prompt_Shape_Exclusions) -> bool {

    if offset < 0 || offset >= len(text) || text[offset] <= ' ' ||
        text[offset] > '~' {
        return false
    }
    cursor_excluded := offset >= exclusions.cursor_start &&
        offset < exclusions.cursor_end
    selection_excluded := offset >= exclusions.selection_start &&
        offset < exclusions.selection_end
    return !cursor_excluded && !selection_excluded
}

//   Draw prompt text in shaped ASCII fragments split at cursor and selection overlays.
//
// Parameters:
//   - request: Prompt text, regular font, resolver, exclusions, and screen position.
//
// Side effects:
//   - Issues shaped glyph commands where valid and Raylib text fallback commands for
//     excluded, non-ASCII, single-byte, or rejected fragments.
terminal_draw_prompt_text :: proc(request: Terminal_Prompt_Text_Draw) {

    segment_start := 0
    for segment_start < len(request.current_text) {
        shapeable := terminal_prompt_byte_shapeable(
            request.current_text, segment_start, request.exclusions)
        segment_end := segment_start + 1
        for segment_end < len(request.current_text) &&
            terminal_prompt_byte_shapeable(
                request.current_text, segment_end,
                request.exclusions) == shapeable {
            segment_end += 1
        }
        segment := request.current_text[segment_start:segment_end]
        segment_position := rl.Vector2{
            request.position.x + terminal_measure_prefix_width(
                request.regular, request.current_text[:segment_start]),
            request.position.y,
        }
        shaped := shapeable && len(segment) > 1 &&
            terminal_draw_shaped_ascii(
                request.resolver, .Regular, segment, segment_position,
                request.color)
        if !shaped {
            rl.DrawTextEx(
                request.regular, fmt.ctprintf("%s", segment), segment_position,
                TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, request.color)
        }
        segment_start = segment_end
    }
}

//   Draw one output cell through the resolved semantic font variant.
//
// Parameters:
//   - font_resolver: Borrowing capability for the cell's semantic font variant.
//   - cell: Leading semantic grid cell to draw.
//   - glyph_position: Authoritative top-left screen position of the cell.
//   - column_width: Measured monospace pixel pitch.
//   - palette: Display-owned palette snapshot used to resolve cell colors.
//
// Side effects:
//   - Issues the fallback cell draw at its authoritative grid-column position.
terminal_draw_output_cell :: proc(
    draw: Terminal_Shaped_Output_Context, cell: ^termgrid.Cell,
    glyph_position: rl.Vector2) {
    key := terminal_font_key_for_cell(cell.style)
    resolved_font := terminal_font_resolve(draw.resolver, key)
    terminal_draw_cell(draw, resolved_font, cell, glyph_position)
}

// Try one contextual shaping chunk and return its next source column.
terminal_draw_output_shaped_chunk :: proc(
    ctx: Terminal_Shaped_Output_Context,
    column: int) -> (int, bool) {
    cell := &ctx.cells[column]
    run_end := terminal_shape_run_end(ctx.cells, column)
    chunk_end := terminal_shape_chunk_end(column, run_end)
    key := terminal_font_key_for_cell(cell.style)
    color := terminal_resolve_foreground(
        ctx.palette, cell.style.foreground, ctx.theme.default_foreground)
    if chunk_end - column <= 1 { return column, false }
    drawn := terminal_draw_shaped_output_run({
        resolver = ctx.resolver,
        cells = ctx.cells[column:chunk_end],
        start_column = column,
        position = ctx.position,
        column_width = ctx.column_width,
        key = key,
        color = color,
    })
    return chunk_end, drawn
}

//   Draw one logical scrollback line's run segments left-to-right, each in its
//   own style's font and color.
//
// Parameters:
//   - font_resolver: The borrowing capability for semantic font variants.
//   - cells: The exact semantic cells in one output row.
//   - position: The top-left screen position of the line.
//   - palette: Display-owned palette snapshot used to resolve retained references.
//   - shaping_allowed: Whether eligible same-style runs may use contextual shaping.
//
// Side effects:
//   - Issues background, shaped-run, fallback-cell, and decoration draw commands in
//     authoritative grid-column order; may record bounded shaping fallback diagnostics.
terminal_draw_output_row :: proc(
    draw: Terminal_Shaped_Output_Context,
    shaping_allowed := true) {
    terminal_draw_output_backgrounds(
        draw.cells, draw.position, draw.column_width, draw.palette)
    column := 0
    for column < len(draw.cells) {
        cell := &draw.cells[column]
        if cell.continuation || cell.grapheme_len == 0 {
            column += 1
            continue
        }
        if shaping_allowed && terminal_cell_shape_eligible(cell) {
            next_column, drawn := terminal_draw_output_shaped_chunk(
                draw, column)
            if drawn {
                column = next_column
                continue
            }
        }
        terminal_draw_output_cell(draw, cell, rl.Vector2{
            draw.position.x + f32(column) * draw.column_width,
            draw.position.y,
        })
        column += max(int(cell.width), 1)
    }
}

// Draw one transient link underline split where resolved foreground color changes.
terminal_draw_link_hover :: proc(
    draw: Terminal_Shaped_Output_Context, hit: Terminal_Link_Hit) {
    column := clamp(hit.column_start, 0, len(draw.cells))
    limit := clamp(hit.column_end, column, len(draw.cells))
    underline_y := draw.position.y + TERMINAL_FONT_SIZE - 1
    for column < limit {
        cell := &draw.cells[column]
        if cell.continuation {
            column += 1
            continue
        }
        color := terminal_resolve_foreground(
            draw.palette, cell.style.foreground,
            draw.theme.default_foreground)
        run_start := column
        column += max(int(cell.width), 1)
        for column < limit {
            next := &draw.cells[column]
            if next.continuation { column += 1; continue }
            next_color := terminal_resolve_foreground(
                draw.palette, next.style.foreground,
                draw.theme.default_foreground)
            if next_color != color { break }
            column += max(int(next.width), 1)
        }
        rl.DrawLineEx(
            rl.Vector2{draw.position.x +
                f32(run_start) * draw.column_width, underline_y},
            rl.Vector2{draw.position.x +
                f32(min(column, limit)) * draw.column_width,
                underline_y},
            1, color)
    }
}

//   Paint explicit cell backgrounds before glyph shaping and decoration.
//
// Parameters:
//   - cells: Semantic cells whose non-default backgrounds are painted.
//   - position: Top-left screen position of the output row.
//   - column_width: Measured monospace pixel pitch.
//   - palette: Display-owned palette snapshot used to resolve backgrounds.
//
// Side effects:
//   - Issues Raylib rectangle commands for leading cells with explicit backgrounds.
terminal_draw_output_backgrounds :: proc(
    cells: []termgrid.Cell, position: rl.Vector2, column_width: f32,
    palette: ^termpalette.Terminal_Palette_State) {
    for &cell, column in cells {
        background := termpalette.terminal_color_resolve_background(
            palette, cell.style.background)
        if cell.continuation ||
            background == termpalette.TERMINAL_DEFAULT_BACKGROUND_RGBA {
            continue
        }
        width := column_width * f32(max(int(cell.width), 1))
        cell_position := rl.Vector2{
            position.x + f32(column) * column_width,
            position.y,
        }
        rl.DrawRectangleV(cell_position,
            rl.Vector2{width, TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING},
            terminal_packed_color(background))
    }
}

//   Report whether one leading cell may participate in a shaped output run.
//
// Parameters:
//   - cell: Semantic grid cell to classify; nil is ineligible.
//
// Returns:
//   - True for a nonempty, single-column, non-continuation cell without underline.
terminal_cell_shape_eligible :: proc(cell: ^termgrid.Cell) -> bool {
    return cell != nil && !cell.continuation && cell.width == 1 &&
        cell.grapheme_len > 0 && !cell.style.underline
}

//   Find the exclusive end of one contiguous same-style shapeable run.
//
// Parameters:
//   - cells: Semantic row cells containing the run.
//   - start: Index of the first eligible leading cell.
//
// Returns:
//   - Exclusive index after contiguous eligible cells sharing the starting style.
terminal_shape_run_end :: proc(cells: []termgrid.Cell, start: int) -> int {
    style := cells[start].style
    result := start
    for result < len(cells) && terminal_cell_shape_eligible(&cells[result]) &&
        cells[result].style == style {
        result += 1
    }
    return result
}

//   Bound one shapeable run segment to the fixed stack workspace capacity.
//
// Parameters:
//   - start: Inclusive starting cell index of this chunk.
//   - run_end: Exclusive end of the full same-style run.
//
// Returns:
//   - The lesser of the run end and one fixed-capacity chunk past start.
terminal_shape_chunk_end :: proc(start, run_end: int) -> int {
    return min(start + TERMINAL_SHAPING_RUN_COLUMNS, run_end)
}

//   Flatten one semantic-cell run and retain each cell's starting UTF-8 byte offset.
//
// Parameters:
//   - cells: Eligible semantic cells to flatten in source order.
//   - storage: Caller-owned byte workspace receiving concatenated graphemes.
//   - cell_offsets: Caller-owned workspace receiving each cell boundary.
//
// Returns:
//   - A borrowed view into populated byte storage and true, or empty and false when
//     either workspace is too small or the resulting run has no bytes.
//
// Side effects:
//   - Writes concatenated grapheme bytes and source-cell boundaries into the workspaces.
terminal_shape_run_text :: proc(
    cells: []termgrid.Cell, storage: []u8,
    cell_offsets: []int) -> (string, bool) {

    if len(cell_offsets) < len(cells) + 1 {
        return "", false
    }
    byte_count := 0
    for &cell, index in cells {
        grapheme_length := int(cell.grapheme_len)
        if byte_count + grapheme_length > len(storage) {
            return "", false
        }
        cell_offsets[index] = byte_count
        copy(storage[byte_count:], cell.grapheme[:grapheme_length])
        byte_count += grapheme_length
    }
    cell_offsets[len(cells)] = byte_count
    return string(storage[:byte_count]), byte_count > 0
}

//   Resolve a HarfBuzz byte cluster to its authoritative source-cell column.
//
// Parameters:
//   - cluster: HarfBuzz byte cluster offset in the flattened run text.
//   - cell_offsets: Ordered source-cell byte boundaries including the final sentinel.
//
// Returns:
//   - The zero-based source-cell column and true, or zero and false when invalid.
terminal_shape_cluster_column :: proc(
    cluster: u32, cell_offsets: []int) -> (int, bool) {

    if len(cell_offsets) < 2 || int(cluster) >= cell_offsets[len(cell_offsets) - 1] {
        return 0, false
    }
    for index in 0..<len(cell_offsets) - 1 {
        if int(cluster) >= cell_offsets[index] &&
            int(cluster) < cell_offsets[index + 1] {
            return index, true
        }
    }
    return 0, false
}

//   Validate horizontal monospace output against the semantic source-cell span.
//
// Parameters:
//   - glyphs: Caller-owned shaped-glyph workspace containing the candidate prefix.
//   - cell_count: Number of authoritative semantic source cells in the run.
//   - glyph_count: Number of shaped glyphs reported by the shaping callback.
//   - atlas: Resolved Raylib font atlas used to validate glyph identifiers.
//
// Returns:
//   - True when glyph IDs, advances, direction, and total monospace span are valid.
terminal_shaped_run_is_valid :: proc(
    glyphs: []font.Shaped_Glyph, cell_count, glyph_count: int,
    atlas: rl.Font) -> bool {

    if glyph_count <= 0 || glyph_count > len(glyphs) || cell_count <= 0 {
        return false
    }
    total_advance := i64(0)
    for glyph in glyphs[:glyph_count] {
        if glyph.glyph_id >= u32(atlas.glyphCount) || glyph.y_advance != 0 ||
            glyph.x_advance <= 0 {
            return false
        }
        total_advance += i64(glyph.x_advance)
    }
    return total_advance == i64(glyphs[0].x_advance)*i64(cell_count)
}

//   Draw one shaped glyph directly from its complete glyph-ID atlas rectangle.
//
// Parameters:
//   - atlas: Font atlas containing the shaped glyph ID and metrics.
//   - glyph: Shaped glyph ID plus HarfBuzz positioning offsets.
//   - cell_position: Authoritative top-left source-cell position.
//   - color: Foreground tint applied to the atlas texture.
//
// Side effects:
//   - Issues one Raylib textured-quad draw command.
terminal_draw_shaped_glyph :: proc(
    atlas: rl.Font, glyph: font.Shaped_Glyph,
    cell_position: rl.Vector2, color: rl.Color) {

    source := atlas.recs[glyph.glyph_id]
    if !terminal_shaped_source_has_ink(source) {
        return
    }
    metric := atlas.glyphs[glyph.glyph_id]
    scale := TERMINAL_FONT_SIZE/f32(atlas.baseSize)
    offset_scale := scale/64
    destination := rl.Rectangle{
        x = cell_position.x + f32(metric.offsetX)*scale +
            f32(glyph.x_offset)*offset_scale,
        y = cell_position.y + f32(metric.offsetY)*scale +
            f32(glyph.y_offset)*offset_scale,
        width = source.width*scale,
        height = source.height*scale,
    }
    rl.DrawTexturePro(
        atlas.texture, source, destination, {}, 0, color)
}

// Return whether one shaped glyph atlas rectangle contains drawable ink.
terminal_shaped_source_has_ink :: proc(source: rl.Rectangle) -> bool {
    return source.width > 0 && source.height > 0
}

//   Record one bounded shaped-run fallback through an available resolver callback.
//
// Parameters:
//   - resolver: Font capability optionally exposing fallback diagnostics.
//   - reason: Stable reason the shaped path could not be used.
//
// Side effects:
//   - Invokes the resolver's diagnostic callback when available.
terminal_record_shape_fallback :: proc(
    resolver: font.Font_Resolver, reason: font.Shape_Fallback_Reason) {

    if resolver.record_shape_fallback != nil {
        resolver.record_shape_fallback(resolver.user_data, reason)
    }
}

//   Resolve every shaped byte cluster to an authoritative source-cell column.
//
// Parameters:
//   - resolver: Font capability used to record invalid-cluster diagnostics.
//   - workspace: Shaping workspace supplying glyph clusters and receiving columns.
//   - cell_count: Number of source cells represented by workspace offsets.
//   - glyph_count: Number of shaped glyphs whose clusters must be mapped.
//
// Returns:
//   - True after populating the shaped-glyph prefix of `source_columns`.
//   - False after recording the first invalid cluster.
terminal_map_shape_clusters :: proc(
    resolver: font.Font_Resolver, workspace: ^Terminal_Shaped_Run_Workspace,
    cell_count, glyph_count: int) -> bool {

    for glyph, index in workspace.shaped_glyphs[:glyph_count] {
        source_column, cluster_valid := terminal_shape_cluster_column(
            glyph.cluster, workspace.cell_offsets[:cell_count + 1])
        if !cluster_valid {
            terminal_record_shape_fallback(resolver, .Invalid_Cluster)
            return false
        }
        workspace.source_columns[index] = source_column
    }
    return true
}

//   Prepare and validate one eligible run without issuing partial draw commands.
//
// Parameters:
//   - request: Eligible cells, font capability, style, placement, and draw color.
//   - workspace: Stack workspace receiving flattened text, offsets, glyphs, and atlas.
//
// Returns:
//   - True when the entire run is shaped, validated, and mapped for drawing.
//
// Side effects:
//   - Populates the workspace and may record one bounded fallback reason; issues no
//     draw commands, preserving all-or-fallback rendering.
terminal_prepare_shaped_run :: proc(
    request: Terminal_Shaped_Run_Draw,
    workspace: ^Terminal_Shaped_Run_Workspace) -> bool {
    if request.resolver.shape == nil ||
        len(request.cells) > TERMINAL_SHAPING_RUN_COLUMNS {
        terminal_record_shape_fallback(
            request.resolver, .Workspace_Overflow)
        return false
    }
    text, built := terminal_shape_run_text(
        request.cells, workspace.text_storage[:],
        workspace.cell_offsets[:len(request.cells) + 1])
    if !built {
        return false
    }
    glyph_count, shaped := request.resolver.shape(
        request.resolver.user_data, request.key, text,
        workspace.shaped_glyphs[:])
    workspace.atlas = terminal_font_resolve(request.resolver, request.key)
    if !shaped || !terminal_shaped_run_is_valid(
        workspace.shaped_glyphs[:], len(request.cells),
        glyph_count, workspace.atlas) {
        terminal_record_shape_fallback(request.resolver, .Invalid_Result)
        return false
    }
    if !terminal_map_shape_clusters(
        request.resolver, workspace, len(request.cells), glyph_count) {
        return false
    }
    workspace.glyph_count = glyph_count
    return true
}

//   Shape and draw one eligible output run without mutating semantic cells.
//
// Parameters:
//   - request: Semantic cells, font capability, style, placement, and draw color.
//
// Returns:
//   - True after the complete run is validated and drawn; false before any run glyph is
//     drawn when shaping cannot preserve authoritative cell semantics.
//
// Side effects:
//   - May record fallback diagnostics and issues one textured glyph command per valid
//     shaped glyph.
terminal_draw_shaped_output_run :: proc(
    request: Terminal_Shaped_Run_Draw) -> bool {

    workspace: Terminal_Shaped_Run_Workspace
    if !terminal_prepare_shaped_run(request, &workspace) {
        return false
    }
    for glyph, index in workspace.shaped_glyphs[:workspace.glyph_count] {
        source_column := workspace.source_columns[index]
        if terminal_cell_is_ascii_space(&request.cells[source_column]) {
            continue
        }
        cell_position := rl.Vector2{
            request.position.x + f32(
                request.start_column + source_column)*
                request.column_width,
            request.position.y,
        }
        terminal_draw_shaped_glyph(
            workspace.atlas, glyph, cell_position, request.color)
    }
    return true
}

//   Shape one bounded printable-ASCII prompt fragment as single-width cells.
//
// Parameters:
//   - resolver: Font capability supplying shaping, atlas, and fallback diagnostics.
//   - key: Semantic font variant used for shaping and drawing.
//   - text: Candidate printable-ASCII fragment.
//   - position: Top-left screen position of the fragment.
//   - color: Foreground draw color.
//
// Returns:
//   - True after a bounded multi-byte ASCII fragment is shaped and drawn; false when
//     ineligible or when validated shaping fails before drawing.
//
// Side effects:
//   - May record fallback diagnostics and issue shaped glyph draw commands.
terminal_draw_shaped_ascii :: proc(
    resolver: font.Font_Resolver, key: font.Font_Key,
    text: string, position: rl.Vector2, color: rl.Color) -> bool {

    if len(text) < 2 || len(text) > TERMINAL_SHAPING_RUN_COLUMNS {
        return false
    }
    cells: [TERMINAL_SHAPING_RUN_COLUMNS]termgrid.Cell
    for byte, index in transmute([]u8)text {
        if byte <= ' ' || byte > '~' {
            return false
        }
        cells[index].grapheme[0] = byte
        cells[index].grapheme_len = 1
        cells[index].width = 1
    }
    atlas := terminal_font_resolve(resolver, key)
    return terminal_draw_shaped_output_run({
        resolver = resolver,
        cells = cells[:len(text)],
        position = position,
        column_width = terminal_column_width(atlas),
        key = key,
        color = color,
    })
}

//   Draw one semantic grid cell using stack-backed null-terminated grapheme text.
//
// Parameters:
//   - font: Resolved semantic font for the cell style.
//   - cell: Leading semantic grid cell supplying grapheme, style, and width.
//   - position: Authoritative top-left screen position of the cell.
//   - column_width: Measured monospace pixel pitch used for underline width.
//   - palette: Display-owned palette snapshot used to resolve the foreground.
//
// Side effects:
//   - Draws the grapheme in captured foreground/style font and, when requested, an
//     underline spanning at least one column or the cell's semantic width.
terminal_draw_cell :: proc(
    draw: Terminal_Shaped_Output_Context, font: rl.Font,
    cell: ^termgrid.Cell, position: rl.Vector2) {

    if terminal_cell_is_ascii_space(cell) {
        return
    }
    text: [termgrid.CELL_GRAPHEME_CAPACITY + 1]u8
    copy(text[:], cell.grapheme[:cell.grapheme_len])
    color := terminal_resolve_foreground(
        draw.palette, cell.style.foreground,
        draw.theme.default_foreground)
    rl.DrawTextEx(font, cast(cstring)&text[0], position,
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, color)
    if cell.style.underline {
        width := draw.column_width * f32(max(int(cell.width), 1))
        underline_y := position.y + TERMINAL_FONT_SIZE - 1
        rl.DrawLineEx(
            rl.Vector2{position.x, underline_y},
            rl.Vector2{position.x + width, underline_y}, 1, color)
    }
}

// Return whether one semantic cell is an ordinary spacing column with no ink.
terminal_cell_is_ascii_space :: proc(cell: ^termgrid.Cell) -> bool {
    return cell != nil && !cell.continuation && cell.grapheme_len == 1 &&
        cell.grapheme[0] == ' '
}

//   Select a semantic font variant for one grid cell style.
//
// Parameters:
//   - style: Grid-cell style carrying weight, legacy bold, and italic attributes.
//
// Returns:
//   - Weight/italic variant, with legacy bold promoting Regular weight to Bold.
terminal_font_key_for_cell :: proc(style: termgrid.Cell_Style) -> font.Font_Key {
    italic := style.italic
    weight := style.font_weight
    if style.bold && weight == .Regular {
        weight = .Bold
    }
    switch weight {
    case .Light:
        return .Light_Italic if italic else .Light
    case .Medium:
        return .Medium_Italic if italic else .Medium
    case .Semi_Bold:
        return .Semi_Bold_Italic if italic else .Semi_Bold
    case .Bold:
        return .Bold_Italic if italic else .Bold
    case .Extra_Bold:
        return .Extra_Bold_Italic if italic else .Extra_Bold
    case .Black:
        return .Black_Italic if italic else .Black
    case .Regular:
        return .Regular_Italic if italic else .Regular
    }
    return .Regular
}

//   Unpack big-endian RGBA8888 channels into a raylib color.
//
// Parameters:
//   - packed: Big-endian RGBA8888 color value.
//
// Returns:
//   - Color with red in bits 31-24 through alpha in bits 7-0.
terminal_packed_color :: proc(packed: u32) -> rl.Color {
    return rl.Color{
        u8(packed >> 24 & 0xff),
        u8(packed >> 16 & 0xff),
        u8(packed >> 8 & 0xff),
        u8(packed & 0xff),
    }
}

// Resolve a cell foreground while preserving explicit ANSI palette references.
terminal_resolve_foreground :: proc(
    palette: ^termpalette.Terminal_Palette_State,
    color: termmodel.Terminal_Color_Reference,
    default_foreground: rl.Color) -> rl.Color {
    if termpalette.terminal_color_kind(color) == .Default {
        return default_foreground
    }
    return terminal_packed_color(
        termpalette.terminal_color_resolve_foreground(palette, color))
}

//   Draw the live input line's selection highlight and block cursor, over
//   already-drawn base text.
//
// Parameters:
//   - font: The monospace font used for the highlight and cursor overlay.
//   - prompt_text: The "> "-prefixed live line text.
//   - cursor_position: The cursor's byte offset into prompt_text.
//   - selection: The line's selected byte sub-range and highlight-extension
//     edge, in prompt_text coordinates.
//   - position: The top-left screen position for the prompt line.
//
// Side effects:
//   - Issues Raylib commands for the optional selection overlay and block cursor.
terminal_draw_prompt_overlay :: proc(
    draw: Terminal_Text_Overlay_Draw, cursor_position: int,
    selection: Terminal_Line_Selection) {
    if selection.has_selection {
        terminal_draw_inverted_span(
            draw, selection, selection.right_edge_x)
    }

    cursor_on_selection := selection.has_selection &&
        cursor_position >= selection.start && cursor_position < selection.end
    terminal_draw_cursor(
        draw, cursor_position, cursor_on_selection)
}

//   Draw a solid rect plus inverted glyphs over one line's selected byte
//   sub-range, extending into virtual blank columns past the line's real text
//   (or all the way to the viewport's right edge when the selection reaches
//   the line's true end and continues onward), so consecutive full lines and
//   blank space form one contiguous block.
//
// Parameters:
//   - font: The monospace font used for terminal text.
//   - line_text: The full line text the sub-range indexes into.
//   - span: The line's selected byte sub-range and whether it reaches the
//     line's end; start/end may exceed len(line_text).
//   - position: The top-left screen position of the line.
//   - right_edge_x: The viewport's right edge, for full-line highlight extension.
//
// Side effects:
//   - Issues Raylib commands for the selection rectangle and inverted selected glyphs.
terminal_draw_inverted_span :: proc(
    draw: Terminal_Text_Overlay_Draw, span: Terminal_Line_Selection,
    right_edge_x: f32) {
    span_position := rl.Vector2{
        draw.position.x + terminal_position_x(draw.font, draw.text, span.start),
        draw.position.y,
    }
    span_end_x := draw.position.x +
        terminal_position_x(draw.font, draw.text, span.end)

    text_start := math.clamp(span.start, 0, len(draw.text))
    text_end := math.clamp(span.end, text_start, len(draw.text))
    span_text := draw.text[text_start:text_end]

    rect_width := span_end_x - span_position.x
    if span.covers_trailing_gap {
        rect_width = math.max(rect_width, right_edge_x - span_position.x)
    }

    rect_height := TERMINAL_FONT_SIZE
    if span.covers_trailing_gap {
        rect_height += TERMINAL_LINE_SPACING
    }

    rl.DrawRectangleV(span_position, rl.Vector2{rect_width, rect_height},
        draw.theme.selection_background)
    if text_start < text_end {
        rl.DrawTextEx(draw.font, fmt.ctprintf("%s", span_text), span_position,
            TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING,
            draw.theme.selection_foreground)
    }
}

//   Draw the block cursor over its codepoint, inverted from whatever sits
//   beneath it so it stays visible whether or not a selection covers it.
//
// Parameters:
//   - font: The monospace font used for terminal text.
//   - line_text: The full line text the cursor indexes into.
//   - cursor_position: The cursor's byte offset into line_text.
//   - on_selection: true when the cursor's cell falls inside an active
//     selection highlight, so its colors are inverted a second time.
//   - position: The top-left screen position of the line.
//
// Side effects:
//   - Issues Raylib commands for the cursor rectangle and inverted codepoint glyph.
terminal_draw_cursor :: proc(
    draw: Terminal_Text_Overlay_Draw, cursor_position: int,
    on_selection: bool) {
    cursor_end := terminal_codepoint_end(draw.text, cursor_position)

    prefix_width := terminal_measure_prefix_width(
        draw.font, draw.text[:cursor_position])
    cursor_screen_position := rl.Vector2{
        draw.position.x + prefix_width, draw.position.y}

    glyph_text :=
        cursor_position < cursor_end ? draw.text[cursor_position:cursor_end] : " "
    glyph_size := rl.MeasureTextEx(draw.font, fmt.ctprintf("%s", glyph_text),
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING)

    rect_color := draw.theme.selection_foreground if
        on_selection else draw.theme.default_foreground
    glyph_color := draw.theme.selection_background if
        on_selection else draw.theme.cursor_foreground

    rl.DrawRectangleV(cursor_screen_position,
        rl.Vector2{glyph_size.x, TERMINAL_FONT_SIZE}, rect_color)
    rl.DrawTextEx(draw.font, fmt.ctprintf("%s", glyph_text), cursor_screen_position,
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING, glyph_color)
}

//   Return the byte offset just past the UTF-8 codepoint at offset, if any.
//
// Parameters:
//   - text: The line text the offset indexes into.
//   - offset: The starting byte offset.
//
// Returns:
//   - offset plus that codepoint's width, or offset unchanged at line end.
terminal_codepoint_end :: proc(text: string, offset: int) -> int {
    if offset >= len(text) {
        return offset
    }

    _, width := utf8.decode_rune(text[offset:])
    return offset + width
}

//   Measure a line prefix's true rendered pixel width.
//
// Notes:
//   - MeasureTextEx omits spacing after a string's final character, but a
//     continuous multi-segment render effectively includes it before the
//     next segment. Adding it back here keeps split-segment positioning
//     (colored runs, the bold "> " prompt, selection/cursor overlays) aligned
//     with plain single-call lines.
//
// Parameters:
//   - font: The monospace font used for measuring.
//   - prefix: The line's leading text before the position being computed.
//
// Returns:
//   - The prefix's true rendered width in pixels.
terminal_measure_prefix_width :: proc(font: rl.Font, prefix: string) -> f32 {
    if len(prefix) == 0 {
        return 0
    }

    width := rl.MeasureTextEx(font, fmt.ctprintf("%s", prefix),
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING).x
    return width + TERMINAL_TEXT_SPACING
}

//   Measure one monospace character cell's pixel pitch, including spacing.
//
// Parameters:
//   - font: The monospace font used for measuring.
//
// Returns:
//   - The pixel width of one virtual blank column.
terminal_column_width :: proc(font: rl.Font) -> f32 {
    advance := rl.MeasureTextEx(font, fmt.ctprintf("%s", " "),
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING).x
    return advance + TERMINAL_TEXT_SPACING
}

//   Resolve the pixel x-offset for a byte offset that may exceed a line's
//   real text, extrapolating into virtual blank columns past its end.
//
// Parameters:
//   - font: The monospace font used for measuring.
//   - line_text: The line's real text.
//   - offset: A real byte offset into line_text, or a value past
//     len(line_text) representing virtual blank columns beyond it.
//
// Returns:
//   - The pixel x-offset from the line's left edge.
terminal_position_x :: proc(font: rl.Font, line_text: string, offset: int) -> f32 {
    if offset <= len(line_text) {
        return terminal_measure_prefix_width(font, line_text[:math.max(offset, 0)])
    }

    real_width := terminal_measure_prefix_width(font, line_text)
    virtual_columns := offset - len(line_text)
    return real_width + f32(virtual_columns) * terminal_column_width(font)
}
