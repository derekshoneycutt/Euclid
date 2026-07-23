package ui

import "core:math"

import rl "vendor:raylib"

//   Draw the circular refresh glyph used in the tree toolbar.
draw_refresh_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5
    radius := min(rect.width, rect.height) * 0.34
    thickness: f32 = 1.6
    arrow_size := radius * 0.55

    start1: f32 = math.PI * (2.0 / 9.0)
    end1: f32 = math.PI * (10.0 / 9.0)
    start2: f32 = math.PI * (11.0 / 9.0)
    end2: f32 = math.PI * (19.0 / 9.0)

    draw_arc_polyline(cx, cy, radius, start1, end1, thickness, color)
    draw_arc_arrowhead(cx, cy, radius, end1, arrow_size, thickness, color)

    draw_arc_polyline(cx, cy, radius, start2, end2, thickness, color)
    draw_arc_arrowhead(cx, cy, radius, end2, arrow_size, thickness, color)
}

//   Draw pause glyph with two vertical bars.
draw_pause_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    bar_w := max(2.0, rect.width * 0.18)
    gap := max(2.0, rect.width * 0.14)
    total_w := bar_w * 2 + gap
    left_x := rect.x + (rect.width - total_w) * 0.5
    top := rect.y + rect.height * 0.24
    bottom := rect.y + rect.height * 0.76

    rl.DrawRectangleRec(rl.Rectangle{left_x, top, bar_w, bottom - top}, color)
    rl.DrawRectangleRec(rl.Rectangle{left_x + bar_w + gap, top, bar_w, bottom - top}, color)
}

//   Draw play glyph with a right-pointing triangle.
draw_play_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    left := rect.x + rect.width * 0.34
    right := rect.x + rect.width * 0.72
    top := rect.y + rect.height * 0.24
    bottom := rect.y + rect.height * 0.76
    mid_y := rect.y + rect.height * 0.5

    rl.DrawTriangle(
        rl.Vector2{left, top}, rl.Vector2{left, bottom}, rl.Vector2{right, mid_y},
        color)
}

//   Draw an approximated arc segment using connected line segments.
draw_arc_polyline :: proc(
    cx, cy, radius: f32,
    start_angle, end_angle: f32,
    thickness: f32,
    color: rl.Color) {

    segments := 10

    prev_angle := start_angle
    prev := rl.Vector2{
        cx + radius * f32(math.cos(f64(prev_angle))),
        cy + radius * f32(math.sin(f64(prev_angle))),
    }

    for i in 1..<(segments + 1) {
        t := f32(i) / f32(segments)
        angle := start_angle + (end_angle - start_angle) * t
        current := rl.Vector2{
            cx + radius * f32(math.cos(f64(angle))),
            cy + radius * f32(math.sin(f64(angle))),
        }

        rl.DrawLineEx(prev, current, thickness, color)
        prev = current
    }
}

//   Draw an arrowhead tangent to an arc at the provided angle.
draw_arc_arrowhead :: proc(
    cx, cy, radius: f32,
    angle: f32,
    size: f32,
    thickness: f32,
    color: rl.Color) {

    tip := rl.Vector2{
        cx + radius * f32(math.cos(f64(angle))),
        cy + radius * f32(math.sin(f64(angle))),
    }

    tangent := rl.Vector2{-f32(math.sin(f64(angle))), f32(math.cos(f64(angle)))}
    back := rl.Vector2{tip.x - tangent.x * size, tip.y - tangent.y * size}
    perp := rl.Vector2{-tangent.y, tangent.x}

    wing_scale := size * 0.55
    left := rl.Vector2{back.x + perp.x * wing_scale, back.y + perp.y * wing_scale}
    right := rl.Vector2{back.x - perp.x * wing_scale, back.y - perp.y * wing_scale}

    rl.DrawLineEx(left, tip, thickness, color)
    rl.DrawLineEx(right, tip, thickness, color)
}

//   Draw expand/collapse chevron icon for tree nodes.
draw_tree_disclosure_icon :: proc(rect: rl.Rectangle, expanded: bool, color: rl.Color) {
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5

    left_top_x: f32 = -4.0
    left_top_y: f32 = -4.0
    left_bottom_x: f32 = -4.0
    left_bottom_y: f32 = 4.0
    tip_x: f32 = 2.0
    tip_y: f32 = 0.0

    if expanded {
        lt_x := -left_top_y
        lt_y := left_top_x
        lb_x := -left_bottom_y
        lb_y := left_bottom_x
        tp_x := -tip_y
        tp_y := tip_x

        left_top_x = lt_x
        left_top_y = lt_y
        left_bottom_x = lb_x
        left_bottom_y = lb_y
        tip_x = tp_x
        tip_y = tp_y
    }

    p0 := rl.Vector2{cx + left_top_x, cy + left_top_y}
    p1 := rl.Vector2{cx + tip_x, cy + tip_y}
    p2 := rl.Vector2{cx + left_bottom_x, cy + left_bottom_y}

    rl.DrawLineEx(p0, p1, 1.6, color)
    rl.DrawLineEx(p1, p2, 1.6, color)
}

//   Draw the settings/controls glyph for the toolbar toggle.
draw_gear_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    left := rect.x + 4
    right := rect.x + rect.width - 4
    y1 := rect.y + 5
    y2 := rect.y + rect.height * 0.5
    y3 := rect.y + rect.height - 5

    thickness: f32 = 1.5
    knob_r: f32 = 2.2

    rl.DrawLineEx(rl.Vector2{left, y1}, rl.Vector2{right, y1}, thickness, color)
    rl.DrawLineEx(rl.Vector2{left, y2}, rl.Vector2{right, y2}, thickness, color)
    rl.DrawLineEx(rl.Vector2{left, y3}, rl.Vector2{right, y3}, thickness, color)

    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.36, y1}, knob_r, color)
    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.64, y2}, knob_r, color)
    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.46, y3}, knob_r, color)
}

//   Draw a simple camera icon for the GIF export toolbar toggle.
draw_gif_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    body := rl.Rectangle{
        rect.x + 3,
        rect.y + 6,
        rect.width - 6,
        rect.height - 10,
    }
    bump := rl.Rectangle{
        body.x + body.width * 0.15,
        body.y - 2,
        body.width * 0.28,
        2,
    }

    rl.DrawRectangleLinesEx(body, 1, color)
    rl.DrawRectangleRec(bump, color)

    lens_center := rl.Vector2{body.x + body.width * 0.5, body.y + body.height * 0.5}
    lens_r := max(2.0, min(body.width, body.height) * 0.22)
    rl.DrawCircleLines(i32(lens_center.x), i32(lens_center.y), lens_r, color)

    flash_dot := rl.Vector2{body.x + body.width * 0.78, body.y + body.height * 0.3}
    rl.DrawCircleV(flash_dot, 1.0, color)
}

//   Draw a simple two-sheet copy glyph used for scratchpad block copy actions.
draw_copy_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    back := rl.Rectangle{
        rect.x + rect.width * 0.32,
        rect.y + rect.height * 0.18,
        rect.width * 0.5,
        rect.height * 0.62,
    }

    front := rl.Rectangle{
        rect.x + rect.width * 0.16,
        rect.y + rect.height * 0.3,
        rect.width * 0.5,
        rect.height * 0.62,
    }

    rl.DrawRectangleLinesEx(back, 1, color)
    rl.DrawRectangleLinesEx(front, 1, color)
}
