package ui_dynview

import "../../../core"
import "../../../dynview"
import view_core "../../core"

import "core:math"

import rl "vendor:raylib"

//   Uniform handler shape for one flow command; the style is resolved by the caller.
//   Handlers that do not need the command buffer receive nil for it.
Flow_Command_Handler :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context)

//   Dispatch table mapping each dynview command kind to its flow handler.
//   Kinds with no flow behavior (blocks, copyable text, line-break) map to nil.
FLOW_COMMAND_HANDLERS :: [core.Dynview_Command_Kind]Flow_Command_Handler{
    .Begin_Block = nil,
    .End_Block = nil,
    .Copyable_Text_Run = nil,
    .Line_Break = nil,
    .Divider = nil,
    .Text_Run = consume_text_based_command,
    .Math_Glyph_Run = consume_text_based_command,
    .Math_Block = consume_text_based_command,
    .Script_Attach = consume_text_based_command,
    .Frac = consume_text_based_command,
    .Stretch_Delimiter = consume_text_based_command,
    .Matrix = consume_text_based_command,
    .Large_Op = consume_large_op_command,
    .Accent_Bar = consume_text_based_command,
    .Radical_Bar = consume_text_based_command,
    .Inline_Line = flow_handle_inline_line,
    .Inline_Box = flow_handle_inline_box,
    .Inline_Circle = flow_handle_inline_circle,
    .Inline_Filled_Box = flow_handle_inline_filled_box,
    .Inline_Filled_Circle = flow_handle_inline_filled_circle,
    .Inline_Pie_Section = flow_handle_inline_pie_section,
    .Inline_Perpendicular = flow_handle_inline_perpendicular,
    .Inline_Triangle = flow_handle_inline_triangle,
    .Inline_Pentagon = flow_handle_inline_pentagon,
}

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

Perpendicular_Colors :: struct {
    top: rl.Color,
    stem: rl.Color,
}

Triangle_Colors :: struct {
    fill: rl.Color,
    edge1: rl.Color,
    edge2: rl.Color,
    edge3: rl.Color,
}

Pentagon_Colors :: struct {
    fill: rl.Color,
    edge1: rl.Color,
    edge2: rl.Color,
    edge3: rl.Color,
    edge4: rl.Color,
    edge5: rl.Color,
}

Inline_Shape_Frame :: struct {
    rect: rl.Rectangle,
    cols: int,
    max_cols: int,
    visible: bool,
}

Pie_Section_Bounds :: struct {
    x_min: f32,
    x_max: f32,
    y_min: f32,
    y_max: f32,
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

shape_edge_color_or :: #force_inline proc(edge_color, fallback: rl.Color) -> rl.Color {
    if edge_color.r == 0 && edge_color.g == 0 && edge_color.b == 0 && edge_color.a == 0 {
        return fallback
    }
    return edge_color
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
pie_point :: #force_inline proc(
    center: rl.Vector2, radius, angle_degrees: f32) -> rl.Vector2 {
    radians := angle_degrees * math.PI / 180.0
    return rl.Vector2{
        center.x + radius * f32(math.cos(f64(radians))),
        center.y - radius * f32(math.sin(f64(radians))),
    }
}

//   Return true when angle lies inside the inclusive start->end positive sweep.
pie_angle_in_sweep :: #force_inline proc(
    angle_degrees,
    start_degrees,
    sweep_degrees: f32) -> bool {

    delta := normalize_angle_degrees(angle_degrees - start_degrees)
    return delta <= sweep_degrees + 0.0001
}

//   Compute tight wedge bounds including center and cardinal sweep crossings.
pie_section_bounds :: #force_inline proc(
    radius,
    start_degrees,
    end_degrees: f32) -> Pie_Section_Bounds {

    start_n := normalize_angle_degrees(start_degrees)
    end_n := normalize_angle_degrees(end_degrees)
    sweep := positive_sweep_degrees(start_n, end_n)

    x_min: f32 = 0
    x_max: f32 = 0
    y_min: f32 = 0
    y_max: f32 = 0

    include_bound_angle :: #force_inline proc(
        angle_degrees: f32, radius: f32, x_min, x_max, y_min, y_max: ^f32) {
        radians := angle_degrees * math.PI / 180.0
        x := radius * f32(math.cos(f64(radians)))
        y := -radius * f32(math.sin(f64(radians)))
        x_min^ = min(x_min^, x)
        x_max^ = max(x_max^, x)
        y_min^ = min(y_min^, y)
        y_max^ = max(y_max^, y)
    }

    include_bound_angle(start_n, radius, &x_min, &x_max, &y_min, &y_max)
    include_bound_angle(end_n, radius, &x_min, &x_max, &y_min, &y_max)

    cardinals := [?]f32{0, 90, 180, 270}
    for i in 0..<len(cardinals) {
        angle := cardinals[i]
        if pie_angle_in_sweep(angle, start_n, sweep) {
            include_bound_angle(angle, radius, &x_min, &x_max, &y_min, &y_max)
        }
    }

    return Pie_Section_Bounds{x_min, x_max, y_min, y_max}
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

//   Draw one pie-section outline with arc and radial edges.
draw_pie_section_outline :: proc(
    center: rl.Vector2,
    radius: f32,
    start_degrees, end_degrees: f32,
    stroke: f32,
    color: rl.Color) {

    sweep := positive_sweep_degrees(start_degrees, end_degrees)
    if sweep <= 0 {
        return
    }

    segments := max(1, int(math.ceil(f64(sweep / 8.0))))
    prev := pie_point(center, radius, start_degrees)
    for i in 0..<segments {
        t := f32(i + 1) / f32(segments)
        angle := normalize_angle_degrees(start_degrees + sweep * t)
        next_point := pie_point(center, radius, angle)
        rl.DrawLineEx(prev, next_point, stroke, color)
        prev = next_point
    }

    start_point := pie_point(center, radius, start_degrees)
    end_point := pie_point(center, radius, end_degrees)
    rl.DrawLineEx(center, start_point, stroke, color)
    rl.DrawLineEx(center, end_point, stroke, color)
}

//   Draw one perpendicular shape with the primary line on the bottom edge.
draw_perpendicular_shape :: proc(
    rect: rl.Rectangle,
    stroke: f32,
    colors: Perpendicular_Colors) {

    bottom_y := rect.y + rect.height
    bottom_left := rl.Vector2{rect.x, bottom_y}
    bottom_right := rl.Vector2{rect.x + rect.width, bottom_y}
    stem_x := rect.x + rect.width * 0.5
    rl.DrawLineEx(bottom_left, bottom_right, stroke, colors.top)
    rl.DrawLineEx(rl.Vector2{stem_x, rect.y},
        rl.Vector2{stem_x, bottom_y}, stroke, colors.stem)
}

//   Draw one triangle shape with optional fill and per-edge colors.
draw_triangle_shape :: proc(
    rect: rl.Rectangle,
    filled: bool,
    colors: Triangle_Colors,
    stroke: f32) {

    apex := rl.Vector2{rect.x + rect.width * 0.5, rect.y}
    base_left := rl.Vector2{rect.x, rect.y + rect.height}
    base_right := rl.Vector2{rect.x + rect.width, rect.y + rect.height}
    if filled {
        rl.DrawTriangle(apex, base_left, base_right, colors.fill)
    }
    if stroke <= 0 {
        return
    }
    rl.DrawLineEx(apex, base_left, stroke, colors.edge1)
    rl.DrawLineEx(base_left, base_right, stroke, colors.edge2)
    rl.DrawLineEx(base_right, apex, stroke, colors.edge3)
}

//   Draw one pentagon shape with optional fill and per-edge colors.
draw_pentagon_shape :: proc(
    rect: rl.Rectangle,
    filled: bool,
    colors: Pentagon_Colors,
    stroke: f32) {

    center_x := rect.x + rect.width * 0.5
    center_y := rect.y + rect.height * 0.5
    radius := max(1.0, min(rect.width, rect.height) * 0.5)
    start_angle: f32 = -90.0

    points: [5]rl.Vector2
    for i in 0..<5 {
        angle := start_angle + f32(i) * 72.0
        radians := angle * f32(math.PI) / 180.0
        points[i] = rl.Vector2{
            center_x + radius * math.cos_f32(radians),
            center_y + radius * math.sin_f32(radians),
        }
    }

    if filled {
        for i in 1..<4 {
            rl.DrawTriangle(points[i], points[0], points[i + 1], colors.fill)
        }
    }

    if stroke <= 0 {
        return
    }

    rl.DrawLineEx(points[0], points[1], stroke, colors.edge1)
    rl.DrawLineEx(points[1], points[2], stroke, colors.edge2)
    rl.DrawLineEx(points[2], points[3], stroke, colors.edge3)
    rl.DrawLineEx(points[3], points[4], stroke, colors.edge4)
    rl.DrawLineEx(points[4], points[0], stroke, colors.edge5)
}

//   Prepare one inline-shape frame using the current flow cursor and row height.
flow_inline_shape_frame :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context,
    y_start_scale, y_end_scale: f32) -> Inline_Shape_Frame {

    max_cols := dynview.chars_per_row_for_style(
        draw_ctx^.panel.width, draw_ctx^.text_padding, draw_ctx^.wrap_advance, style)
    if max_cols <= 0 {
        max_cols = 1
    }

    cols := dynview.inline_box_cols(cmd, style, max_cols)
    if flow^.col > 0 && flow^.col + cols > max_cols {
        flow^.row += 1
        flow^.col = 0
    }

    if draw_ctx^.enabled {
        row_y := draw_ctx^.panel.y + draw_ctx^.text_padding + f32(flow^.row) *
            draw_ctx^.text_row_height - draw_ctx^.scroll_y
        if row_y + draw_ctx^.text_row_height >= draw_ctx^.panel.y &&
            row_y <= draw_ctx^.panel.y + draw_ctx^.panel.height {

            effective_advance := dynview.effective_advance(style, draw_ctx^.wrap_advance)
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            top_y := row_y + draw_ctx^.text_row_height * y_start_scale
            bottom_y := row_y + draw_ctx^.text_row_height * y_end_scale
            return Inline_Shape_Frame{rl.Rectangle{
                atom_x, top_y, atom_w, max(1.0, bottom_y - top_y)}, cols, max_cols, true}
        }
    }

    return Inline_Shape_Frame{{}, cols, max_cols, false}
}

//   Consume one text run in flow layout, optionally drawing each wrapped segment.
flow_consume_text_run :: proc(
    flow: ^Dynview_Flow_State,
    text: string,
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

    start := 0
    for start < len(text) {
        wrap_if_full(flow, max_cols)

        available := max_cols - flow^.col
        if available <= 0 {
            flow^.row += 1
            flow^.col = 0
            continue
        }

        span := dynview.next_wrapped_text_span(text, start, available)
        line_text := text[span.line_start:span.line_end]
        line_len := dynview.text_codepoint_count_span(line_text, 0, len(line_text))
        if line_len <= 0 {
            break
        }

        flow_draw_text_line(flow, line_text, line_len, style, draw_ctx)

        flow^.had_visible = true
        flow^.col += line_len

        if span.next_start < len(text) {
            flow^.row += 1
            flow^.col = 0
        }

        if span.next_start <= start {
            break
        }
        start = span.next_start
    }
}

//   Draw one wrapped text line at the current flow position when it is visible.
flow_draw_text_line :: proc(
    flow: ^Dynview_Flow_State,
    line_text: string,
    line_len: int,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    if !draw_ctx^.enabled {
        return
    }
    row_y := draw_ctx^.panel.y + draw_ctx^.text_padding +
        f32(flow^.row) * draw_ctx^.text_row_height - draw_ctx^.scroll_y
    if row_y + draw_ctx^.text_row_height < draw_ctx^.panel.y ||
        row_y > draw_ctx^.panel.y + draw_ctx^.panel.height {
        return
    }

    line_x := draw_ctx^.panel.x + draw_ctx^.text_padding + f32(flow^.col) *
        dynview.effective_advance(style, draw_ctx^.wrap_advance)
    if style.alignment == .Center && flow^.col == 0 {
        line_w := f32(line_len) * dynview.effective_advance(
            style, draw_ctx^.wrap_advance)
        line_x = draw_ctx^.panel.x + (draw_ctx^.panel.width - line_w) * 0.5
    }

    view_core.ui_text(line_text, int(line_x), int(row_y), style.color,
        style_font(draw_ctx, style), draw_ctx^.font_size)
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
            line_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
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
            box_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
            box_w := f32(cols) * effective_advance
            raw_h := cmd.inline_box_height * effective_advance
            box_h := max(4.0, min(draw_ctx^.text_row_height - 3, raw_h))
            box_y := row_y + (draw_ctx^.text_row_height - box_h) * 0.5
            stroke := max(1.0, cmd.inline_atom_stroke)
            top_left := rl.Vector2{box_x, box_y}
            top_right := rl.Vector2{box_x + box_w, box_y}
            bottom_left := rl.Vector2{box_x, box_y + box_h}
            bottom_right := rl.Vector2{box_x + box_w, box_y + box_h}
            base_color := command_draw_color(cmd, style)
            edge1 := shape_edge_color_or(cmd.shape_edge_color_1, base_color)
            edge2 := shape_edge_color_or(cmd.shape_edge_color_2, base_color)
            edge3 := shape_edge_color_or(cmd.shape_edge_color_3, base_color)
            edge4 := shape_edge_color_or(cmd.shape_edge_color_4, base_color)
            rl.DrawLineEx(top_left, top_right, stroke, edge1)
            rl.DrawLineEx(top_right, bottom_right, stroke, edge2)
            rl.DrawLineEx(bottom_right, bottom_left, stroke, edge3)
            rl.DrawLineEx(bottom_left, top_left, stroke, edge4)
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

    cols := dynview.inline_pie_section_cols(cmd, style, max_cols)
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
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y +
                draw_ctx^.text_row_height * 0.58}
            stroke := max(1.0, cmd.inline_atom_stroke)
            color := command_draw_color(cmd, style)
            rl.DrawCircleLines(i32(center.x), i32(center.y), radius, color)
            if stroke > 1 {
                rl.DrawCircleLines(i32(center.x), i32(center.y),
                    max(1.0, radius - 1), color)
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
            box_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
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
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
            atom_w := f32(cols) * effective_advance
            radius := max(2.0, min(atom_w * 0.5, draw_ctx^.text_row_height * 0.45))
            center := rl.Vector2{atom_x + atom_w * 0.5, row_y +
                    draw_ctx^.text_row_height * 0.58}
            color := command_draw_color(cmd, style)
            rl.DrawCircleV(center, radius, color)

            if cmd.inline_outline_stroke > 0 {
                stroke := max(1.0, cmd.inline_outline_stroke)
                rl.DrawCircleLines(i32(center.x), i32(center.y), radius, style.color)
                if stroke > 1 {
                    rl.DrawCircleLines(i32(center.x), i32(center.y),
                        max(1.0, radius - 1), style.color)
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
            atom_x := draw_ctx^.panel.x + draw_ctx^.text_padding +
                f32(flow^.col) * effective_advance
            radius := max(2.0, cmd.inline_atom_dimension * effective_advance)
            bounds := pie_section_bounds(
                radius,
                cmd.pie_start_angle_degrees,
                cmd.pie_end_angle_degrees)
            wedge_height := max(1.0, bounds.y_max - bounds.y_min)
            center := rl.Vector2{
                atom_x + (-bounds.x_min),
                row_y + draw_ctx^.text_row_height * 0.58 -
                    wedge_height * 0.5 + (-bounds.y_min),
            }
            fill_color := command_draw_color(cmd, style)
            outline_color := cmd.has_outline_color ? cmd.outline_color : style.color
            stroke := max(1.0, cmd.inline_outline_stroke)
            if cmd.pie_is_filled {
                draw_filled_pie_section(
                    center,
                    radius,
                    cmd.pie_start_angle_degrees,
                    cmd.pie_end_angle_degrees,
                    fill_color)
                if cmd.inline_outline_stroke > 0 {
                    draw_pie_section_outline(
                        center,
                        radius,
                        cmd.pie_start_angle_degrees,
                        cmd.pie_end_angle_degrees,
                        stroke,
                        outline_color)
                }
            } else {
                draw_pie_section_outline(
                    center,
                    radius,
                    cmd.pie_start_angle_degrees,
                    cmd.pie_end_angle_degrees,
                    stroke,
                    outline_color)
            }
        }
    }

    flow^.had_visible = true
    flow^.col += cols
    wrap_if_full(flow, max_cols)
}

//   Consume one inline-perpendicular atom in flow layout, optionally drawing it.
flow_consume_inline_perpendicular :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    frame := flow_inline_shape_frame(flow, cmd, style, draw_ctx, 0.34, 0.74)
    if frame.visible {
        draw_perpendicular_shape(frame.rect, max(1.0, cmd.inline_atom_stroke),
            Perpendicular_Colors{command_draw_color(cmd, style), cmd.shape_edge_color_1})
    }

    flow^.had_visible = true
    flow^.col += frame.cols
    wrap_if_full(flow, frame.max_cols)
}

//   Consume one inline-triangle atom in flow layout, optionally drawing it.
flow_consume_inline_triangle :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    frame := flow_inline_shape_frame(flow, cmd, style, draw_ctx, 0.30, 0.78)
    if frame.visible {
        base_color := command_draw_color(cmd, style)
        draw_triangle_shape(frame.rect, cmd.shape_is_filled, Triangle_Colors{
            base_color,
            shape_edge_color_or(cmd.shape_edge_color_1, base_color),
            shape_edge_color_or(cmd.shape_edge_color_2, base_color),
            shape_edge_color_or(cmd.shape_edge_color_3, base_color),
        }, max(1.0, cmd.inline_atom_stroke))
    }

    flow^.had_visible = true
    flow^.col += frame.cols
    wrap_if_full(flow, frame.max_cols)
}

//   Consume one inline-pentagon atom in flow layout, optionally drawing it.
flow_consume_inline_pentagon :: proc(
    flow: ^Dynview_Flow_State,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {

    frame := flow_inline_shape_frame(flow, cmd, style, draw_ctx, 0.30, 0.78)
    if frame.visible {
        base_color := command_draw_color(cmd, style)
        draw_pentagon_shape(frame.rect, cmd.shape_is_filled, Pentagon_Colors{
            base_color,
            shape_edge_color_or(cmd.shape_edge_color_1, base_color),
            shape_edge_color_or(cmd.shape_edge_color_2, base_color),
            shape_edge_color_or(cmd.shape_edge_color_3, base_color),
            shape_edge_color_or(cmd.shape_edge_color_4, base_color),
            shape_edge_color_or(cmd.shape_edge_color_5, base_color),
        }, max(1.0, cmd.inline_atom_stroke))
    }

    flow^.had_visible = true
    flow^.col += frame.cols
    wrap_if_full(flow, frame.max_cols)
}

//   Compute style-aware row count for one text command payload.
count_rows_for_run :: #force_inline proc(
    text: string,
    panel_width, text_padding, wrap_advance: f32,
    style: Dynview_Text_Style) -> int {

    max_chars := dynview.chars_per_row_for_style(
        panel_width, text_padding, wrap_advance, style)
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

//   Adapt flow_consume_inline_line to the uniform table handler shape.
flow_handle_inline_line :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_line(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_box to the uniform table handler shape.
flow_handle_inline_box :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_box(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_circle to the uniform table handler shape.
flow_handle_inline_circle :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_circle(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_filled_box to the uniform table handler shape.
flow_handle_inline_filled_box :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_filled_box(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_filled_circle to the uniform table handler shape.
flow_handle_inline_filled_circle :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_filled_circle(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_pie_section to the uniform table handler shape.
flow_handle_inline_pie_section :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_pie_section(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_perpendicular to the uniform table handler shape.
flow_handle_inline_perpendicular :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_perpendicular(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_triangle to the uniform table handler shape.
flow_handle_inline_triangle :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_triangle(flow, cmd, style, draw_ctx)
}

//   Adapt flow_consume_inline_pentagon to the uniform table handler shape.
flow_handle_inline_pentagon :: proc(
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    style: Dynview_Text_Style,
    draw_ctx: ^Dynview_Draw_Context) {
    flow_consume_inline_pentagon(flow, cmd, style, draw_ctx)
}

//   Consume a single command in the current run of the given flow.
//   Handlers are dispatched from a static table indexed by command kind.
consume_flow_command :: proc(
    runtime: ^core.Dynview_System,
    cmd: core.Dynview_Command,
    buffer: ^core.Dynview_Command_Buffer,
    flow: ^Dynview_Flow_State,
    draw_ctx: ^Dynview_Draw_Context) {

    kind := cmd.kind
    if kind == .Line_Break || kind == .Divider {
        consume_linebreak(flow)
        return
    }

    style := dynview.style_by_id(cmd.style_id)
    handlers := FLOW_COMMAND_HANDLERS
    handler := handlers[kind]
    if handler != nil {
        handler(cmd, buffer, flow, style, draw_ctx)
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

//   Draw environment for styled wrapped dynview content: the target panel,
//   scroll offset, typography metrics, and fallback font, grouped so the entry
//   point passes one coherent value.
Styled_Content_Params :: struct {
    panel:           rl.Rectangle,
    scroll_y:        f32,
    text_padding:    f32,
    text_row_height: f32,
    wrap_advance:    f32,
    font_size:       f32,
    font:            rl.Font,
}

//   Draw style-aware wrapped dynview text content clipped by caller scissor.
draw_styled_content :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    params: Styled_Content_Params) {

    if runtime == nil {
        return
    }

    buffer := &runtime^.command_buffer
    flow := Dynview_Flow_State{}
    draw_ctx := Dynview_Draw_Context{
        enabled = true,
        state = state,
        panel = params.panel,
        scroll_y = params.scroll_y,
        text_padding = params.text_padding,
        text_row_height = params.text_row_height,
        wrap_advance = params.wrap_advance,
        font_size = params.font_size,
        fallback_font = params.font,
    }
    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        consume_flow_command(runtime, cmd, buffer, &flow, &draw_ctx)
    }
}
