package ui_dynview

import "../../../core"
import "../../../dynview"
import view_core "../../core"

import "core:math"

import rl "vendor:raylib"

Dynview_Flow_State :: struct {
    row: int,
    col: int,
    had_visible: bool,
}

Dynview_Draw_Context :: struct {
    enabled: bool,
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    scroll_y: f32,
    text_padding: f32,
    text_row_height: f32,
    wrap_advance: f32,
    font_size: f32,
    fallback_font: rl.Font,
}

style_font :: #force_inline proc(
    draw_ctx: ^Dynview_Draw_Context, style: Dynview_Text_Style) -> rl.Font {
    if draw_ctx == nil || draw_ctx^.state == nil {
        return draw_ctx^.fallback_font
    }

    flags := style.font_flags
    if flags == .None {
        flags = view_core.font_flags_from_bold_italic(style.bold, style.italic)
    }
    return view_core.font_runtime_resolve(
        draw_ctx^.state,
        flags,
        view_core.JULIA_MONO_FONT_LOAD_SIZE)
}

//   Advance flow cursor to the next row when no columns remain in current row.
wrap_if_full :: #force_inline proc(flow: ^Dynview_Flow_State, max_cols: int) {
    if max_cols <= 0 {
        return
    }

    if flow^.col >= max_cols {
        flow^.row += 1
        flow^.col = 0
    }
}

//   Resolve draw color using command brush override with style fallback.
command_draw_color :: #force_inline proc(
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style) -> rl.Color {

    if cmd.has_brush_color {
        return cmd.brush_color
    }
    return style.color
}

//   Normalize one degree angle into the [0, 360) range.
normalize_angle_degrees :: #force_inline proc(angle: f32) -> f32 {
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
positive_sweep_degrees :: #force_inline proc(start_degrees, end_degrees: f32) -> f32 {
    start_n := normalize_angle_degrees(start_degrees)
    end_n := normalize_angle_degrees(end_degrees)
    sweep := end_n - start_n
    if sweep < 0 {
        sweep += 360
    }
    return sweep
}

//   Compute one point on a circle from center/radius and degree angle.
pie_point :: #force_inline proc(center: rl.Vector2, radius, angle_degrees: f32) -> rl.Vector2 {
    radians := angle_degrees * math.PI / 180.0
    return rl.Vector2{
        center.x + radius * f32(math.cos(f64(radians))),
        center.y - radius * f32(math.sin(f64(radians))),
    }
}

//   Draw a filled pie section using a deterministic triangle fan.
draw_filled_pie_section :: proc(
    center: rl.Vector2,
    radius: f32,
    start_degrees, end_degrees: f32,
    color: rl.Color) {

    sweep := positive_sweep_degrees(start_degrees, end_degrees)
    if sweep <= 0 {
        return
    }

    segments := max(1, int(math.ceil(f64(sweep / 8.0))))
    for i in 0..<segments {
        t0 := f32(i) / f32(segments)
        t1 := f32(i + 1) / f32(segments)
        a0 := normalize_angle_degrees(start_degrees + sweep * t0)
        a1 := normalize_angle_degrees(start_degrees + sweep * t1)
        p0 := pie_point(center, radius, a0)
        p1 := pie_point(center, radius, a1)
        rl.DrawTriangle(center, p0, p1, color)
    }
}

//   Consume one text run in flow layout, optionally drawing each wrapped segment.
flow_consume_text_run :: proc(
    flow: ^Dynview_Flow_State,
    text: string,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    if len(text) <= 0 {
        return
    }

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)

    if max_cols <= 0 {
        max_cols = 1
    }

    start := 0
    for start < len(text) {
        wrap_if_full(flow, max_cols)

        available := max_cols - flow^.col
        if available <= 0 {
            flow^.row += 1
            flow^.col = 0
            continue
        }

        line_start, line_end, next_start := dynview.next_wrapped_text_span(text, start, available)
        line_text := text[line_start:line_end]
        line_len := dynview.text_codepoint_count_span(line_text, 0, len(line_text))
        if line_len <= 0 {
            break
        }

        if draw_ctx^.enabled {
            row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
                f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
            if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
                row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

                line_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                    f32(flow^.col) * dynview.effective_advance(style, draw_ctx^.wrap_advance)
                if style.alignment == .Center && flow^.col == 0 {
                    line_w := f32(line_len) * dynview.effective_advance(style, draw_ctx^.wrap_advance)
                    line_x = draw_ctx^.panel.x + (draw_ctx^.panel.width - line_w) * 0.5
                }

                view_core.ui_text(line_text,
                    int(line_x),
                    int(row_y),
                    style.color,
                    style_font(draw_ctx, style),
                    draw_ctx^.font_size)
                if style.underline {
                    underline_y := row_y + draw_ctx^.font_size + 1
                    underline_width := f32(line_len) *
                        dynview.effective_advance(style, draw_ctx^.wrap_advance)
                    rl.DrawLineEx(
                        rl.Vector2{line_x, underline_y},
                        rl.Vector2{line_x + underline_width, underline_y},
                        1,
                        style.color)
                }
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
flow_consume_inline_line :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_line_cols(cmd, style, draw_ctx^.wrap_advance, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            line_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            line_w := f32(cols) * effective_advance
            baseline_y := row_y + draw_ctx^.text_row_height * 0.62
            thickness := max(1.0, cmd.inline_atom_stroke)
            start_pos := rl.Vector2{line_x, baseline_y}
            end_pos := rl.Vector2{line_x + line_w, baseline_y}
            rl.DrawLineEx(start_pos, end_pos, thickness, command_draw_color(cmd, style))
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one inline-box atom in flow layout, optionally drawing it.
flow_consume_inline_box :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_box_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            box_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            box_w := f32(cols) * effective_advance
            raw_h := cmd.inline_box_height * effective_advance
            box_h := max(4.0, min(draw_ctx^.text_row_height - 3, raw_h))
            box_y := row_y + (draw_ctx^.text_row_height - box_h) * 0.5
            stroke := max(1.0, cmd.inline_atom_stroke)
            rl.DrawRectangleLinesEx(
                rl.Rectangle{box_x, box_y, box_w, box_h},
                stroke,
                command_draw_color(cmd, style))
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one inline-circle atom in flow layout, optionally drawing it.
flow_consume_inline_circle :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_circle_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y + draw_ctx^.text_row_height * 0.58}
            stroke := max(1.0, cmd.inline_atom_stroke)
            color := command_draw_color(cmd, style)
            rl.DrawCircleLines(i32(center.x), i32(center.y), radius, color)
            if stroke > 1 {
                rl.DrawCircleLines(i32(center.x), i32(center.y), max(1.0, radius - 1), color)
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one filled inline-box atom in flow layout, optionally drawing it.
flow_consume_inline_filled_box :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_box_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            box_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            box_w := f32(cols) * effective_advance
            raw_h := cmd.inline_box_height * effective_advance
            box_h := max(4.0, min(draw_ctx^.text_row_height - 3, raw_h))
            box_y := row_y + (draw_ctx^.text_row_height - box_h) * 0.5
            color := command_draw_color(cmd, style)
            rl.DrawRectangleRec(rl.Rectangle{box_x, box_y, box_w, box_h}, color)

            if cmd.inline_outline_stroke > 0 {
                rl.DrawRectangleLinesEx(
                    rl.Rectangle{box_x, box_y, box_w, box_h},
                    max(1.0, cmd.inline_outline_stroke),
                    style.color)
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one filled inline-circle atom in flow layout, optionally drawing it.
flow_consume_inline_filled_circle :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_circle_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y + draw_ctx^.text_row_height * 0.58}
            color := command_draw_color(cmd, style)
            rl.DrawCircleV(center, radius, color)

            if cmd.inline_outline_stroke > 0 {
                stroke := max(1.0, cmd.inline_outline_stroke)
                rl.DrawCircleLines(i32(center.x), i32(center.y), radius, style.color)
                if stroke > 1 {
                    rl.DrawCircleLines(i32(center.x), i32(center.y), max(1.0, radius - 1), style.color)
                }
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one inline pie-section atom in flow layout, optionally drawing it.
flow_consume_inline_pie_section :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width,
        draw_ctx^.text_padding,
        draw_ctx^.wrap_advance,
        style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_circle_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
            f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y + draw_ctx^.text_row_height * 0.58}
            color := command_draw_color(cmd, style)
            draw_filled_pie_section(
                center,
                radius,
                cmd.pie_start_angle_degrees,
                cmd.pie_end_angle_degrees,
                color)

            if cmd.inline_outline_stroke > 0 {
                stroke := max(1.0, cmd.inline_outline_stroke)
                start_point := pie_point(center, radius, cmd.pie_start_angle_degrees)
                end_point := pie_point(center, radius, cmd.pie_end_angle_degrees)
                rl.DrawLineEx(center, start_point, stroke, style.color)
                rl.DrawLineEx(center, end_point, stroke, style.color)
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Compute style-aware row count for one text command payload.
count_rows_for_run :: #force_inline proc(
    text: string,
    panel_width, text_padding, wrap_advance: f32,
    style: Dynview_Text_Style) -> int {

    max_chars := dynview.chars_per_row_for_style(panel_width, text_padding, wrap_advance, style)
    return dynview.count_wrapped_text_rows(text, max_chars)
}

//   Draw one styled wrapped text line run with bounded visual traits.
draw_styled_line :: #force_inline proc(
    text: string,
    panel: rl.Rectangle,
    row_y, text_padding, wrap_advance, font_size: f32,
    font: rl.Font,
    style: Dynview_Text_Style) {

    line_x := panel.x + text_padding
    if style.alignment == .Center {
        line_w := f32(dynview.text_codepoint_count_span(text, 0, len(text))) *
            wrap_advance * max(0.5, style.wrap_scale)
        line_x = panel.x + (panel.width - line_w) * 0.5
    }

    view_core.ui_text(text, int(line_x), int(row_y), style.color, font, font_size)
}

//  Consume a text based command for the given flow
consume_text_based_command :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    text := dynview.text_for_command(buffer, cmd)
    text_style := style
    if cmd.has_brush_color {
        text_style.color = cmd.brush_color
    }
    flow_consume_text_run(flow, text, text_style, draw_ctx)
}

//  Consume a large op command for the given flow
consume_large_op_command :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    text := dynview.large_op_visible_text(buffer, cmd)
    flow_consume_text_run(flow, text, style, draw_ctx)
}

//  Consume a line break for the given flow
consume_linebreak :: proc(
    flow: ^Dynview_Flow_State) {

    flow.row += 1
    flow.col = 0
}

//  Consume a single command in the current run of the given flow
consume_flow_command :: proc(
    runtime: ^core.Dynview_System,
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    draw_ctx: ^Dynview_Draw_Context) {

    // #lizard forgives(cyclomatic_complexity)
    style := dynview.style_by_id(cmd.style_id)
    switch cmd.kind {
    case .TextRun:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .MathGlyphRun:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .MathBlock:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .ScriptAttachRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .FracRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .StretchDelimiterRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .MatrixRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .LargeOpRecursive:
        consume_large_op_command(cmd, buffer, flow, style, draw_ctx)
    case .AccentBarRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .RadicalBarRecursive:
        consume_text_based_command(cmd, buffer, flow, style, draw_ctx)
    case .InlineLine:
        flow_consume_inline_line(flow, cmd, style, draw_ctx)
    case .InlineBox:
        flow_consume_inline_box(flow, cmd, style, draw_ctx)
    case .InlineCircle:
        flow_consume_inline_circle(flow, cmd, style, draw_ctx)
    case .InlineFilledBox:
        flow_consume_inline_filled_box(flow, cmd, style, draw_ctx)
    case .InlineFilledCircle:
        flow_consume_inline_filled_circle(flow, cmd, style, draw_ctx)
    case .InlinePieSection:
        flow_consume_inline_pie_section(flow, cmd, style, draw_ctx)
    case .LineBreak, .Divider:
        consume_linebreak(flow)
    case .BeginBlock, .EndBlock, .CopyableTextRun:
    }
}

//   Count total style-aware rows from validated dynview command stream.
count_styled_rows :: proc(
    runtime: ^core.Dynview_System,
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
        consume_flow_command(runtime, cmd, buffer, &flow, &draw_ctx)
    }

    if !flow.had_visible && flow.row == 0 {
        return 1
    }
    return flow.row + 1
}

//   Draw style-aware wrapped dynview text content clipped by caller scissor.
draw_styled_content :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
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
        state = state,
        panel = panel,
        scroll_y = scroll_y,
        text_padding = text_padding,
        text_row_height = text_row_height,
        wrap_advance = wrap_advance,
        font_size = font_size,
        fallback_font = font,
    }
    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        consume_flow_command(runtime, cmd, buffer, &flow, &draw_ctx)
    }
}
