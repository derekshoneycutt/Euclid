package view

import "../core"
import "../julia"

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:strings"

TREE_PANEL_PADDING :: 10
TREE_ROW_HEIGHT :: 22
TREE_INDENT :: 16
TREE_FONT_SIZE :: 18
TEXT_ROW_HEIGHT :: 22
TEXT_PADDING :: 8
TEXT_WRAP_ADVANCE :: 9
SCROLLBAR_WIDTH :: 8
SCROLLBAR_THUMB_MIN_HEIGHT :: 24
TREE_TOOLBAR_HEIGHT :: 28
TREE_TOOLBAR_BUTTON_SIZE :: 20
TREE_TOOLBAR_GAP :: 6
SETTINGS_TRACK_HEIGHT :: 8
SETTINGS_KNOB_WIDTH :: 10
WHEEL_SCROLL_MULTIPLIER :: 2
SCROLLBAR_DRAG_EPSILON :: 0.001
TREE_ROW_ICON_OFFSET_X :: 2
TREE_ROW_ICON_OFFSET_Y :: 3
TREE_ROW_ICON_SIZE :: 16
TREE_ROW_LABEL_OFFSET_X :: 22
TREE_ROW_LABEL_OFFSET_Y :: 2

SETTINGS_PANEL_INSET :: 8
SETTINGS_HEADER_TOP_OFFSET :: 8
SETTINGS_SLIDER_LABEL_TOP_OFFSET :: 36
SETTINGS_TRACK_TOP_OFFSET :: 22
SETTINGS_TRACK_HIT_PAD_Y :: 6
SETTINGS_KNOB_PAD_Y :: 4
SETTINGS_VALUE_TOP_OFFSET :: 16
SETTINGS_STATS_TOP_OFFSET :: 46
SETTINGS_STATS_ROW_GAP :: 22
SETTINGS_TOGGLE_TOP_OFFSET :: 118
SETTINGS_CHECKBOX_SIZE :: 14
SETTINGS_CHECKBOX_LABEL_GAP :: 8

TreeHit :: struct {
    SelectedID: int,
    ToggledID:  int,
}

TreeToolbarHit :: struct {
    RefreshRequested: bool,
    ToggleSettingsRequested: bool,
}

ui_text :: #force_inline proc(text: string, x, y: int, color: rl.Color) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawText(cloned, i32(x), i32(y), TREE_FONT_SIZE, color)
}

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

draw_arc_polyline :: proc(
    cx, cy, radius: f32,
    start_angle, end_angle: f32,
    thickness: f32,
    color: rl.Color,
) {
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

draw_arc_arrowhead :: proc(
    cx, cy, radius: f32,
    angle: f32,
    size: f32,
    thickness: f32,
    color: rl.Color,
) {
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

draw_toolbar_icon_button :: proc(
    rect: rl.Rectangle,
    mouse: rl.Vector2,
    active: bool,
    draw_icon: proc(rect: rl.Rectangle, color: rl.Color),
) -> bool {
    hovered := rl.CheckCollisionPointRec(mouse, rect)
    pressed := hovered && rl.IsMouseButtonDown(.LEFT)

    icon_rect := rect
    icon_color := TextColor

    if active || pressed {
        rl.DrawRectangleRec(rect, BorderColor)
        icon_color = BackgroundColor
    }

    if pressed {
        icon_rect.x += 0.5
        icon_rect.y += 0.5
    }

    draw_icon(icon_rect, icon_color)
    return rl.IsMouseButtonPressed(.LEFT) && hovered
}

draw_tree_toolbar :: proc(
    panel: rl.Rectangle, mouse: rl.Vector2, show_settings: bool
) -> TreeToolbarHit {
    hit := TreeToolbarHit{}

    rl.DrawRectangleRec(panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(panel, 1, BorderColor)

    refresh_rect := rl.Rectangle{
        panel.x + 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    settings_rect := rl.Rectangle{
        panel.x + panel.width - TREE_TOOLBAR_BUTTON_SIZE - 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    hit.RefreshRequested =
        draw_toolbar_icon_button(refresh_rect, mouse, false, draw_refresh_icon)
    hit.ToggleSettingsRequested =
        draw_toolbar_icon_button(settings_rect, mouse, show_settings, draw_gear_icon)
    return hit
}

build_settings_slider_layout :: proc(panel: rl.Rectangle) -> (f32, rl.Rectangle, rl.Rectangle) {
    slider_label_y := panel.y + SETTINGS_SLIDER_LABEL_TOP_OFFSET

    slider_track := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        slider_label_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }

    slider_hit := rl.Rectangle{
        slider_track.x,
        slider_track.y - SETTINGS_TRACK_HIT_PAD_Y,
        slider_track.width,
        slider_track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }

    return slider_label_y, slider_track, slider_hit
}

slider_value_ratio :: proc(value, max_value: int) -> f32 {
    if max_value <= 0 {
        return 0
    }
    return f32(value) / f32(max_value)
}

build_slider_knob :: proc(slider_track: rl.Rectangle, ratio: f32) -> (f32, rl.Rectangle) {
    knob_center_x := slider_track.x + ratio * slider_track.width
    knob := rl.Rectangle{
        knob_center_x - SETTINGS_KNOB_WIDTH * 0.5,
        slider_track.y - SETTINGS_KNOB_PAD_Y,
        SETTINGS_KNOB_WIDTH,
        slider_track.height + SETTINGS_KNOB_PAD_Y * 2,
    }
    return knob_center_x, knob
}

update_use_max_particles_slider :: proc(
    ps: ^core.ParticleSystem,
    ui_runtime: ^core.EuclidUIRuntimeState,
    mouse: rl.Vector2,
    max_particles: int,
    slider_track: rl.Rectangle,
    slider_hit: rl.Rectangle,
    knob: rl.Rectangle,
    knob_center_x: f32,
) {
    if !rl.IsMouseButtonDown(.LEFT) {
        ui_runtime.SettingsSliderDragging = false
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, knob) {
        ui_runtime.SettingsSliderDragging = true
        ui_runtime.SettingsSliderDragOffsetX = mouse.x - knob_center_x
    }

    slider_hovered := rl.CheckCollisionPointRec(mouse, slider_hit)
    if slider_hovered {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            step := max(1, max_particles / 64)
            delta := int(math.round(f64(wheel * f32(step))))
            if delta == 0 {
                if wheel > 0 {
                    delta = step
                } else {
                    delta = -step
                }
            }

            next_value := ps.UseMaxDustParticles + delta
            ps.UseMaxDustParticles = clamp(next_value, 0, max_particles)
        }
    }

    if slider_track.width > 0 && ui_runtime.SettingsSliderDragging &&
        rl.IsMouseButtonDown(.LEFT) {

        knob_target_x := mouse.x - ui_runtime.SettingsSliderDragOffsetX
        t_drag := clamp((knob_target_x - slider_track.x) / slider_track.width, 0, 1)
        next_value := int(t_drag * f32(max_particles) + 0.5)
        ps.UseMaxDustParticles = clamp(next_value, 0, max_particles)
    }
}

draw_use_max_particles_slider :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    knob_center_x: f32,
    knob: rl.Rectangle,
    current_value: int,
    max_particles: int,
) {
    rl.DrawRectangleRec(slider_track, BackgroundColor)
    rl.DrawRectangleRec(
        rl.Rectangle{
            slider_track.x,
            slider_track.y,
            max(0.0, knob_center_x - slider_track.x),
            slider_track.height,
        },
        BorderColor,
    )
    rl.DrawRectangleRec(knob, TextColor)

    use_max_text := fmt.tprintf("%d / %d", current_value, max_particles)
    ui_text(
        use_max_text,
        int(panel.x + SETTINGS_PANEL_INSET),
        int(slider_track.y + SETTINGS_VALUE_TOP_OFFSET),
        TextColor,
    )
}

draw_settings_particle_stats :: proc(panel: rl.Rectangle, slider_track: rl.Rectangle, ps: ^core.ParticleSystem) {
    stats_y := slider_track.y + SETTINGS_STATS_TOP_OFFSET
    ui_text(
        fmt.tprintf("Dust Particles Rendered: %d", ps.LastRenderLow),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y),
        TextColor,
    )
    ui_text(
        fmt.tprintf("Trail Particles Rendered: %d", ps.LastRenderMid),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y + SETTINGS_STATS_ROW_GAP),
        TextColor,
    )
    ui_text(
        fmt.tprintf("Flicker Particles Rendered: %d", ps.LastRenderHigh),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y + SETTINGS_STATS_ROW_GAP * 2),
        TextColor,
    )
}

draw_settings_fps_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.EuclidUIRuntimeState,
) {
    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    label := "Display FPS"

    // Keep hit target larger than the box so this is easy to click.
    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.DisplayFPS = !ui_runtime.DisplayFPS
    }

    rl.DrawRectangleLinesEx(box, 1, BorderColor)
    if ui_runtime.DisplayFPS {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, TextColor)
        rl.DrawLineEx(p1, p2, 1.6, TextColor)
    }

    ui_text(label, int(label_x), int(row_y - 1), TextColor)
}

draw_settings_view :: proc(
    state: ^core.EuclidGeneralState, panel: rl.Rectangle, mouse: rl.Vector2) {

    if state == nil || state.ParticleSystem == nil {
        return
    }

    ps := state.ParticleSystem
    ui_runtime := &state.UIRuntime

    rl.DrawRectangleRec(panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(panel, 1, BorderColor)

    header_y := int(panel.y + SETTINGS_HEADER_TOP_OFFSET)
    ui_text("Settings", int(panel.x + SETTINGS_PANEL_INSET), header_y, TextColor)

    slider_label_y, slider_track, slider_hit := build_settings_slider_layout(panel)
    ui_text("Maximum Dust Particles", int(panel.x + SETTINGS_PANEL_INSET), int(slider_label_y), TextColor)

    max_particles := core.MAX_LOW_PARTICLES
    ps.UseMaxDustParticles = clamp(ps.UseMaxDustParticles, 0, max_particles)

    ratio := slider_value_ratio(ps.UseMaxDustParticles, max_particles)
    knob_center_x, knob := build_slider_knob(slider_track, ratio)

    update_use_max_particles_slider(
        ps,
        ui_runtime,
        mouse,
        max_particles,
        slider_track,
        slider_hit,
        knob,
        knob_center_x,
    )

    ratio = slider_value_ratio(ps.UseMaxDustParticles, max_particles)
    knob_center_x, knob = build_slider_knob(slider_track, ratio)

    draw_use_max_particles_slider(
        panel,
        slider_track,
        knob_center_x,
        knob,
        ps.UseMaxDustParticles,
        max_particles,
    )
    draw_settings_particle_stats(panel, slider_track, ps)
    draw_settings_fps_checkbox(panel, slider_track, mouse, ui_runtime)
}

chars_per_text_row :: #force_inline proc(width: f32) -> int {
    count := int(width / TEXT_WRAP_ADVANCE)
    if count < 1 {
        return 1
    }
    return count
}

next_wrapped_text_span :: proc(
    text: string, start: int, max_chars: int
) -> (int, int, int) {
    if start >= len(text) {
        return start, start, start
    }

    line_end := start
    chars_used := 0
    last_space := -1

    for line_end < len(text) && text[line_end] != '\n' {
        if text[line_end] == ' ' || text[line_end] == '\t' {
            last_space = line_end
        }

        chars_used += 1
        if chars_used > max_chars {
            if last_space >= start {
                line_end = last_space
            } else if line_end > start {
                line_end -= 1
            }
            break
        }

        line_end += 1
    }

    if line_end == start && line_end < len(text) && text[line_end] != '\n' {
        line_end += 1
    }

    next_start := line_end
    if next_start < len(text) && text[next_start] == '\n' {
        next_start += 1
    } else {
        for next_start < len(text) && (text[next_start] == ' ' || text[next_start] == '\t') {
            next_start += 1
        }
    }

    return start, line_end, next_start
}

count_wrapped_text_rows :: proc(text: string, max_chars: int) -> int {
    if len(text) == 0 {
        return 1
    }

    rows := 0
    start := 0
    for start < len(text) {
        _, _, next_start := next_wrapped_text_span(text, start, max_chars)
        rows += 1
        if next_start <= start {
            break
        }
        start = next_start
    }

    return rows
}

draw_wrapped_text_content :: proc(text: string, panel: rl.Rectangle, scroll_y: f32) {
    max_chars := chars_per_text_row(panel.width - TEXT_PADDING * 2)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + TEXT_PADDING), int(panel.y + TEXT_PADDING), TextColor)
        return
    }

    for start < len(text) {
        line_start, line_end, next_start := next_wrapped_text_span(text, start, max_chars)
        row_y := panel.y + TEXT_PADDING + f32(row) * TEXT_ROW_HEIGHT - scroll_y

        if row_y + TEXT_ROW_HEIGHT >= panel.y && row_y <= panel.y + panel.height {
            ui_text(text[line_start:line_end], int(panel.x + TEXT_PADDING), int(row_y), TextColor)
        }

        row += 1
        if next_start <= start {
            break
        }
        start = next_start
    }
}

set_selected_animation :: proc(ji: ^core.EuclidJuliaInterface, selected_id: int) {
    if selected_id < 0 || selected_id >= ji.NextAnimationIndex {
        return
    }

    for i in 0..<ji.NextAnimationIndex {
        ji.Animations[i].IsSelected = (i == selected_id)
    }
    ji.SelectedAnimationIndex = selected_id
}

count_visible_tree_rows_all_roots :: proc(ji: ^core.EuclidJuliaInterface) -> int {
    count := 0
    for i in 0..<ji.NextAnimationIndex {
        if ji.Animations[i].ParentId < 0 {
            count += count_visible_tree_rows_limited(ji, i, ji.NextAnimationIndex)
        }
    }
    return count
}

merge_tree_hit :: #force_inline proc(dst: ^TreeHit, src: TreeHit) {
    if src.SelectedID >= 0 {
        dst.SelectedID = src.SelectedID
    }
    if src.ToggledID >= 0 {
        dst.ToggledID = src.ToggledID
    }
}

clamp_scroll_position :: proc(scroll_y: ^f32, max_scroll: f32) {
    if scroll_y^ < 0 {
        scroll_y^ = 0
    }
    if scroll_y^ > max_scroll {
        scroll_y^ = max_scroll
    }
}

apply_wheel_scroll :: proc(
    mouse: rl.Vector2, panel: rl.Rectangle, row_height: f32,
    scroll_y: ^f32, max_scroll: f32) {

    if !rl.CheckCollisionPointRec(mouse, panel) {
        return
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 {
        scroll_y^ -= wheel * (row_height * WHEEL_SCROLL_MULTIPLIER)
        clamp_scroll_position(scroll_y, max_scroll)
    }
}

build_vertical_scrollbar :: proc(
    panel: rl.Rectangle, content_h: f32, scroll_y: f32, max_scroll: f32
) -> (rl.Rectangle, rl.Rectangle, f32, bool) {
    if max_scroll <= 0 {
        return rl.Rectangle{}, rl.Rectangle{}, 0, false
    }

    track := rl.Rectangle{
        panel.x + panel.width - SCROLLBAR_WIDTH,
        panel.y,
        SCROLLBAR_WIDTH,
        panel.height,
    }

    thumb_h := scrollbar_thumb_height(panel.height, content_h)
    thumb_y := scrollbar_thumb_y(panel.y, panel.height, thumb_h, scroll_y, max_scroll)
    thumb := rl.Rectangle{track.x, thumb_y, SCROLLBAR_WIDTH, thumb_h}
    return track, thumb, thumb_h, true
}

apply_tree_hit :: proc(ji: ^core.EuclidJuliaInterface, hit: TreeHit) {
    if hit.ToggledID >= 0 && hit.ToggledID < ji.NextAnimationIndex {
        ji.Animations[hit.ToggledID].IsExpanded = !ji.Animations[hit.ToggledID].IsExpanded
    }
    if hit.SelectedID >= 0 {
        set_selected_animation(ji, hit.SelectedID)
    }
}

scrollbar_thumb_height :: #force_inline proc(panel_height: f32, content_h: f32) -> f32 {
    if panel_height <= 0 || content_h <= 0 {
        return 0
    }

    thumb_h := max(SCROLLBAR_THUMB_MIN_HEIGHT, panel_height * (panel_height / content_h))
    return clamp(thumb_h, 0.0, panel_height)
}

scrollbar_thumb_y :: #force_inline proc(
    panel_y, panel_height, thumb_h, scroll_y, max_scroll: f32
) -> f32 {
    if max_scroll <= 0 || panel_height <= thumb_h {
        return panel_y
    }
    return panel_y + (scroll_y / max_scroll) * (panel_height - thumb_h)
}

handle_scrollbar_drag :: proc(
    mouse: rl.Vector2,
    thumb: rl.Rectangle,
    panel_y: f32,
    panel_height: f32,
    thumb_h: f32,
    max_scroll: f32,
    scroll_y: ^f32,
    dragging: ^bool,
    drag_off: ^f32,
) {
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
        dragging^ = true
        drag_off^ = mouse.y - thumb.y
    }

    if !dragging^ {
        return
    }

    if !rl.IsMouseButtonDown(.LEFT) {
        dragging^ = false
        return
    }

    thumb_range := panel_height - thumb_h
    if thumb_range <= SCROLLBAR_DRAG_EPSILON || max_scroll <= 0 {
        scroll_y^ = 0
        return
    }

    new_thumb_y := mouse.y - drag_off^
    t := (new_thumb_y - panel_y) / thumb_range
    scroll_y^ = clamp(t, 0, 1) * max_scroll
}

walk_draw_tree_roots :: proc(
    ji: ^core.EuclidJuliaInterface,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
) -> TreeHit {
    hit := TreeHit{SelectedID = -1, ToggledID = -1}

    for i in 0..<ji.NextAnimationIndex {
        if ji.Animations[i].ParentId >= 0 {
            continue
        }

        root_hit := walk_draw_tree_node_limited(
            ji,
            i,
            0,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            ji.NextAnimationIndex,
        )
        merge_tree_hit(&hit, root_hit)
    }

    return hit
}

count_visible_tree_rows_limited :: proc(
    ji: ^core.EuclidJuliaInterface, id: int, remaining: int
) -> int {
    if remaining <= 0 {
        return 0
    }

    if id < 0 || id >= ji.NextAnimationIndex {
        return 0
    }

    count := 1
    n := &ji.Animations[id]

    if !n.IsExpanded || n.FirstChildId < 0 {
        return count
    }

    child := n.FirstChildId
    steps := 0
    for child >= 0 && steps < ji.NextAnimationIndex {
        if child >= ji.NextAnimationIndex {
            break
        }
        count += count_visible_tree_rows_limited(ji, child, remaining - 1)
        child = ji.Animations[child].NextSibling
        steps += 1
    }

    return count
}

accumulate_offscreen_child_rows :: proc(
    ji: ^core.EuclidJuliaInterface,
    first_child: int,
    content_y: ^f32,
    remaining: int,
) {
    child := first_child
    steps := 0
    for child >= 0 && steps < ji.NextAnimationIndex {
        if child >= ji.NextAnimationIndex {
            break
        }

        child_rows := count_visible_tree_rows_limited(ji, child, remaining - 1)
        content_y^ += f32(child_rows) * TREE_ROW_HEIGHT
        child = ji.Animations[child].NextSibling
        steps += 1
    }
}

walk_draw_child_nodes_limited :: proc(
    ji: ^core.EuclidJuliaInterface,
    first_child: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
) -> TreeHit {
    hit := TreeHit{SelectedID = -1, ToggledID = -1}

    child := first_child
    steps := 0
    for child >= 0 && steps < ji.NextAnimationIndex {
        if child >= ji.NextAnimationIndex {
            break
        }

        child_hit := walk_draw_tree_node_limited(
            ji,
            child,
            depth + 1,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            remaining - 1,
        )
        merge_tree_hit(&hit, child_hit)
        child = ji.Animations[child].NextSibling
        steps += 1
    }

    return hit
}

expanded_first_child_id :: #force_inline proc(is_expanded: bool, first_child_id: int) -> int {
    if !is_expanded || first_child_id < 0 {
        return -1
    }
    return first_child_id
}

draw_tree_node_row :: proc(
    ji: ^core.EuclidJuliaInterface,
    id: int,
    depth: int,
    row_rect: rl.Rectangle,
    allow_clicks: bool,
    mouse: rl.Vector2,
    hit: ^TreeHit,
) {
    node := &ji.Animations[id]

    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := rl.Rectangle{
        indent_x + TREE_ROW_ICON_OFFSET_X,
        row_rect.y + TREE_ROW_ICON_OFFSET_Y,
        TREE_ROW_ICON_SIZE,
        TREE_ROW_ICON_SIZE,
    }
    label_x := int(indent_x + TREE_ROW_LABEL_OFFSET_X)

    click := allow_clicks && rl.IsMouseButtonPressed(.LEFT)
    hovered := rl.CheckCollisionPointRec(mouse, row_rect)

    if node.IsSelected {
        rl.DrawRectangleRec(row_rect, BorderColor)
    }

    if node.FirstChildId >= 0 {
        draw_tree_disclosure_icon(icon_rect, node.IsExpanded, TextColor)

        if click && rl.CheckCollisionPointRec(mouse, icon_rect) {
            hit.ToggledID = id
        }
    }

    ui_text(node.Name, label_x, int(row_rect.y + TREE_ROW_LABEL_OFFSET_Y), TextColor)

    if click && hovered {
        hit.SelectedID = id
    }
}

walk_draw_tree_node_limited :: proc(
    ji: ^core.EuclidJuliaInterface,
    id: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
) -> TreeHit {
    hit := TreeHit{SelectedID = -1, ToggledID = -1}

    if remaining <= 0 {
        return hit
    }

    if id < 0 || id >= ji.NextAnimationIndex {
        return hit
    }

    node := &ji.Animations[id]
    child_first := expanded_first_child_id(node.IsExpanded, node.FirstChildId)

    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT

    row_y_screen := panel.y + (row_y_world - scroll_y)
    row_rect := rl.Rectangle{panel.x, row_y_screen, panel.width, TREE_ROW_HEIGHT}

    if row_rect.y > panel.y + panel.height {
        if child_first >= 0 {
            accumulate_offscreen_child_rows(ji, child_first, content_y, remaining)
        }
        return hit
    }

    if row_rect.y + row_rect.height < panel.y {
        if child_first >= 0 {
            child_hit := walk_draw_child_nodes_limited(
                ji,
                child_first,
                depth,
                panel,
                content_y,
                scroll_y,
                allow_clicks,
                mouse,
                remaining,
            )
            merge_tree_hit(&hit, child_hit)
        }
        return hit
    }

    draw_tree_node_row(ji, id, depth, row_rect, allow_clicks, mouse, &hit)

    if child_first >= 0 {
        child_hit := walk_draw_child_nodes_limited(
            ji,
            child_first,
            depth,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            remaining,
        )
        merge_tree_hit(&hit, child_hit)
    }

    return hit
}

build_tree_view_panels :: proc(panel: rl.Rectangle) -> (rl.Rectangle, rl.Rectangle) {
    inner_x := panel.x + 6
    inner_y := panel.y + 6
    inner_w := panel.width - 12
    inner_h := panel.height - 12

    toolbar_panel := rl.Rectangle{
        inner_x,
        inner_y,
        inner_w,
        TREE_TOOLBAR_HEIGHT,
    }

    list_panel := rl.Rectangle{
        inner_x,
        inner_y + TREE_TOOLBAR_HEIGHT + TREE_TOOLBAR_GAP,
        inner_w,
        inner_h - TREE_TOOLBAR_HEIGHT - TREE_TOOLBAR_GAP,
    }

    if list_panel.width < 0 {
        list_panel.width = 0
    }

    if list_panel.height < 0 {
        list_panel.height = 0
    }

    return toolbar_panel, list_panel
}

draw_tree_list_panel :: proc(
    ji: ^core.EuclidJuliaInterface,
    ui_runtime: ^core.EuclidUIRuntimeState,
    list_panel: rl.Rectangle,
    mouse: rl.Vector2,
    scroll_y: ^f32,
) {
    rl.DrawRectangleRec(list_panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(list_panel, 1, BorderColor)

    total_rows := count_visible_tree_rows_all_roots(ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    max_scroll := max(0.0, content_h - list_panel.height)

    apply_wheel_scroll(mouse, list_panel, TREE_ROW_HEIGHT, scroll_y, max_scroll)

    track := rl.Rectangle{}
    thumb_h: f32 = 0
    thumb := rl.Rectangle{}
    has_scrollbar := false

    allow_tree_clicks := true
    track, thumb, thumb_h, has_scrollbar =
        build_vertical_scrollbar(list_panel, content_h, scroll_y^, max_scroll)
    if has_scrollbar {
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
            allow_tree_clicks = false
        }
    }

    rl.BeginScissorMode(i32(list_panel.x), i32(list_panel.y),
        i32(list_panel.width), i32(list_panel.height))
    {
        y_cursor: f32 = 0
        hit := walk_draw_tree_roots(ji, list_panel, &y_cursor, scroll_y^, allow_tree_clicks, mouse)
        apply_tree_hit(ji, hit)
    }
    rl.EndScissorMode()

    if has_scrollbar {
        handle_scrollbar_drag(
            mouse,
            thumb,
            list_panel.y,
            list_panel.height,
            thumb_h,
            max_scroll,
            scroll_y,
            &ui_runtime.TreeScrollDragging,
            &ui_runtime.TreeScrollDragOff,
        )

        rl.DrawRectangleRec(track, BackgroundColor)
        rl.DrawRectangleRec(thumb, BorderColor)
    }
}

draw_tree_view :: proc(state: ^core.EuclidGeneralState, scroll_y: ^f32) {
    ji := state.JuliaInterface
    ui_runtime := &state.UIRuntime

    panel := rl.Rectangle{
        ViewWidth + TREE_PANEL_PADDING,
        TREE_PANEL_PADDING,
        RightBarWidth - TREE_PANEL_PADDING * 2,
        WindowHeight - TREE_PANEL_PADDING * 2,
    }

    rl.DrawRectangleRec(panel, BackgroundColor)
    rl.DrawRectangleLinesEx(panel, 1, BorderColor)

    mouse := rl.GetMousePosition()
    toolbar_panel, list_panel := build_tree_view_panels(panel)

    toolbar_hit := draw_tree_toolbar(toolbar_panel, mouse, ui_runtime.ShowTreeSettings)
    if toolbar_hit.RefreshRequested {
        ji.PendingAnimationReset = true
    }

    if toolbar_hit.ToggleSettingsRequested {
        ui_runtime.ShowTreeSettings = !ui_runtime.ShowTreeSettings
        ui_runtime.TreeScrollDragging = false
    }

    if ui_runtime.ShowTreeSettings {
        draw_settings_view(state, list_panel, mouse)
        return
    }
    draw_tree_list_panel(ji, ui_runtime, list_panel, mouse, scroll_y)
}

draw_view_text_panel :: proc(state: ^core.EuclidGeneralState, scroll_y: ^f32) {
    if state == nil || state.JuliaInterface == nil {
        return
    }

    ui_runtime := &state.UIRuntime

    panel := rl.Rectangle{
        TREE_PANEL_PADDING,
        ViewHeight + TREE_PANEL_PADDING,
        ViewWidth - TREE_PANEL_PADDING * 2,
        BottomBarHeight - TREE_PANEL_PADDING * 2,
    }

    rl.DrawRectangleRec(panel, BackgroundColor)
    rl.DrawRectangleLinesEx(panel, 1, BorderColor)

    text_panel := rl.Rectangle{
        panel.x + 6,
        panel.y + 6,
        panel.width - 12,
        panel.height - 12,
    }

    if text_panel.width < 0 {
        text_panel.width = 0
    }

    if text_panel.height < 0 {
        text_panel.height = 0
    }

    rl.DrawRectangleRec(text_panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(text_panel, 1, BorderColor)

    view_text := julia.call_current_animation_get_view_text(state)
    max_chars := chars_per_text_row(text_panel.width - TEXT_PADDING * 2)
    total_rows := count_wrapped_text_rows(view_text, max_chars)
    content_h := TEXT_PADDING * 2 + f32(total_rows) * TEXT_ROW_HEIGHT
    max_scroll := max(0.0, content_h - text_panel.height)

    mouse := rl.GetMousePosition()
    apply_wheel_scroll(mouse, text_panel, TEXT_ROW_HEIGHT, scroll_y, max_scroll)

    rl.BeginScissorMode(i32(text_panel.x), i32(text_panel.y), i32(text_panel.width), i32(text_panel.height))
    {
        draw_wrapped_text_content(view_text, text_panel, scroll_y^)
    }
    rl.EndScissorMode()

    track, thumb, thumb_h, has_scrollbar := build_vertical_scrollbar(text_panel, content_h, scroll_y^, max_scroll)
    if has_scrollbar {

        handle_scrollbar_drag(
            mouse,
            thumb,
            text_panel.y,
            text_panel.height,
            thumb_h,
            max_scroll,
            scroll_y,
            &ui_runtime.TextScrollDragging,
            &ui_runtime.TextScrollDragOff,
        )

        rl.DrawRectangleRec(track, BackgroundColor)
        rl.DrawRectangleRec(thumb, BorderColor)
    }
}
