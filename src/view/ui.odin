package view

import "../core"
import "../julia"

import rl "vendor:raylib"
import "core:strings"

TREE_PANEL_PADDING :: f32(10)
TREE_ROW_HEIGHT    :: f32(22)
TREE_INDENT        :: f32(16)
TREE_FONT_SIZE     :: 18
TEXT_ROW_HEIGHT    :: f32(22)
TEXT_PADDING       :: f32(8)
TEXT_WRAP_ADVANCE  :: f32(9)


TreeHit :: struct {
    SelectedID: int,
    ToggledID:  int,
    RestartRequested: bool,
}

ui_text :: #force_inline proc(text: string, x, y: int, color: rl.Color) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawText(cloned, i32(x), i32(y), TREE_FONT_SIZE, color)
}

draw_refresh_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    p0 := rl.Vector2{rect.x + 4, rect.y + 10}
    p1 := rl.Vector2{rect.x + 8, rect.y + 6}
    p2 := rl.Vector2{rect.x + 12, rect.y + 6}
    p3 := rl.Vector2{rect.x + 12, rect.y + 12}
    p4 := rl.Vector2{rect.x + 8, rect.y + 12}
    p5 := rl.Vector2{rect.x + 4, rect.y + 8}

    rl.DrawLineEx(p0, p1, 1.5, color)
    rl.DrawLineEx(p1, p2, 1.5, color)
    rl.DrawTriangle(
        rl.Vector2{rect.x + 12, rect.y + 6},
        rl.Vector2{rect.x + 9, rect.y + 4},
        rl.Vector2{rect.x + 10, rect.y + 8},
        color,
    )

    rl.DrawLineEx(p3, p4, 1.5, color)
    rl.DrawLineEx(p4, p5, 1.5, color)
    rl.DrawTriangle(
        rl.Vector2{rect.x + 4, rect.y + 8},
        rl.Vector2{rect.x + 7, rect.y + 10},
        rl.Vector2{rect.x + 6, rect.y + 6},
        color,
    )
}

chars_per_text_row :: #force_inline proc(width: f32) -> int {
    count := int(width / TEXT_WRAP_ADVANCE)
    if count < 1 {
        return 1
    }
    return count
}

next_wrapped_text_span :: proc(text: string, start: int, max_chars: int) -> (int, int, int) {
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
    for i in 0..<ji.NextAnimationIndex {
        ji.Animations[i].IsSelected = (i == selected_id)
    }
    ji.SelectedAnimationIndex = selected_id
}

count_visible_tree_rows_all_roots :: proc(ji: ^core.EuclidJuliaInterface) -> int {
    count := 0
    for i in 0..<ji.NextAnimationIndex {
        if ji.Animations[i].ParentId < 0 {
            count += count_visible_tree_rows(ji, i)
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
    if src.RestartRequested {
        dst.RestartRequested = true
    }
}

walk_draw_tree_roots :: proc(
    ji: ^core.EuclidJuliaInterface,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
) -> TreeHit {
    hit := TreeHit{SelectedID = -1, ToggledID = -1, RestartRequested = false}

    for i in 0..<ji.NextAnimationIndex {
        if ji.Animations[i].ParentId >= 0 {
            continue
        }

        root_hit := walk_draw_tree_node(ji, i, 0, panel, content_y, scroll_y, allow_clicks)
        merge_tree_hit(&hit, root_hit)
    }

    return hit
}

count_visible_tree_rows :: proc(ji: ^core.EuclidJuliaInterface, id: int) -> int {
    if id < 0 {
        return 0
    }

    count := 1
    n := &ji.Animations[id]

    if !n.IsExpanded || n.FirstChildId < 0 {
        return count
    }

    child := n.FirstChildId
    for child >= 0 {
        count += count_visible_tree_rows(ji, child)
        child = ji.Animations[child].NextSibling
    }

    return count
}

walk_draw_tree_node :: proc(
    ji: ^core.EuclidJuliaInterface,
    id: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
) -> TreeHit {
    hit := TreeHit{SelectedID = -1, ToggledID = -1, RestartRequested = false}

    node := &ji.Animations[id]

    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT

    row_y_screen := panel.y + (row_y_world - scroll_y)
    row_rect := rl.Rectangle{panel.x, row_y_screen, panel.width, TREE_ROW_HEIGHT}

    if row_rect.y + row_rect.height < panel.y || row_rect.y > panel.y + panel.height {
        if node.IsExpanded && node.FirstChildId >= 0 {
            child := node.FirstChildId
            for child >= 0 {
                child_hit := walk_draw_tree_node(ji, child, depth + 1, panel, content_y, scroll_y, allow_clicks)
                if child_hit.SelectedID >= 0 {
                    hit.SelectedID = child_hit.SelectedID
                }
                if child_hit.ToggledID >= 0 {
                    hit.ToggledID = child_hit.ToggledID
                }
                child = ji.Animations[child].NextSibling
            }
        }
        return hit
    }

    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := rl.Rectangle{indent_x + 2, row_rect.y + 3, 16, 16}
    label_x := int(indent_x + 22)

    mouse := rl.GetMousePosition()
    click := allow_clicks && rl.IsMouseButtonPressed(.LEFT)
    hovered := rl.CheckCollisionPointRec(mouse, row_rect)

    if node.IsSelected {
        rl.DrawRectangleRec(row_rect, BorderColor)

        if hovered {
            refresh_rect := rl.Rectangle{row_rect.x + row_rect.width - 18, row_rect.y + 3, 14, 14}
            draw_refresh_icon(refresh_rect, TextColor)

            if click && rl.CheckCollisionPointRec(mouse, refresh_rect) {
                hit.RestartRequested = true
                return hit
            }
        }
    }
    if node.FirstChildId >= 0 {
        if node.IsExpanded {
            ui_text("v", int(icon_rect.x), int(icon_rect.y), TextColor)
        } else {
            ui_text(">", int(icon_rect.x), int(icon_rect.y), TextColor)
        }

        if click && rl.CheckCollisionPointRec(mouse, icon_rect) {
            hit.ToggledID = id
        }
    }

    ui_text(node.Name, label_x, int(row_rect.y + 2), TextColor)

    if click && hovered {
        hit.SelectedID = id
    }

    if node.IsExpanded && node.FirstChildId >= 0 {
        child := node.FirstChildId
        for child >= 0 {
            child_hit := walk_draw_tree_node(ji, child, depth + 1, panel, content_y, scroll_y, allow_clicks)
            if child_hit.SelectedID >= 0 {
                hit.SelectedID = child_hit.SelectedID
            }
            if child_hit.ToggledID >= 0 {
                hit.ToggledID = child_hit.ToggledID
            }
            if child_hit.RestartRequested {
                hit.RestartRequested = true
            }
            child = ji.Animations[child].NextSibling
        }
    }

    return hit
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

    list_panel := rl.Rectangle{
        panel.x + 6,
        panel.y + 6,
        panel.width - 12,
        panel.height - 12,
    }

    rl.DrawRectangleRec(list_panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(list_panel, 1, BorderColor)

    total_rows := count_visible_tree_rows_all_roots(ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    max_scroll := max(f32(0), content_h - list_panel.height)

    mouse := rl.GetMousePosition()
    if rl.CheckCollisionPointRec(mouse, list_panel) {
        wheel := rl.GetMouseWheelMove()
        scroll_y^ -= wheel * (TREE_ROW_HEIGHT * 2)
    }

    if scroll_y^ < 0 {
        scroll_y^ = 0
    }
    if scroll_y^ > max_scroll {
        scroll_y^ = max_scroll
    }

    allow_tree_clicks := true
    if max_scroll > 0 {
        track_w := f32(8)
        track := rl.Rectangle{list_panel.x + list_panel.width - track_w, list_panel.y, track_w, list_panel.height}
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, track) {
            allow_tree_clicks = false
        }
    }

    rl.BeginScissorMode(i32(list_panel.x), i32(list_panel.y), i32(list_panel.width), i32(list_panel.height))
    {
        y_cursor := f32(0)
        hit := walk_draw_tree_roots(ji, list_panel, &y_cursor, scroll_y^, allow_tree_clicks)

        if hit.ToggledID >= 0 {
            ji.Animations[hit.ToggledID].IsExpanded = !ji.Animations[hit.ToggledID].IsExpanded
        }
        if hit.SelectedID >= 0 {
            set_selected_animation(ji, hit.SelectedID)
        }
        if hit.RestartRequested {
            ji.PendingAnimationReset = true
        }
    }
    rl.EndScissorMode()

    if max_scroll > 0 {
        track_w := f32(8)
        track := rl.Rectangle{list_panel.x + list_panel.width - track_w, list_panel.y, track_w, list_panel.height}
        thumb_h := max(f32(24), list_panel.height * (list_panel.height / content_h))
        thumb_y := list_panel.y + (scroll_y^ / max_scroll) * (list_panel.height - thumb_h)
        thumb := rl.Rectangle{track.x, thumb_y, track_w, thumb_h}

        tree_mouse := rl.GetMousePosition()
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(tree_mouse, thumb) {
            ui_runtime.TreeScrollDragging = true
            ui_runtime.TreeScrollDragOff = tree_mouse.y - thumb_y
        }
        if ui_runtime.TreeScrollDragging {
            if rl.IsMouseButtonDown(.LEFT) {
                new_thumb_y := tree_mouse.y - ui_runtime.TreeScrollDragOff
                t := (new_thumb_y - list_panel.y) / (list_panel.height - thumb_h)
                scroll_y^ = clamp(t, 0, 1) * max_scroll
            } else {
                ui_runtime.TreeScrollDragging = false
            }
        }

        rl.DrawRectangleRec(track, BackgroundColor)
        rl.DrawRectangleRec(thumb, BorderColor)
    }
}

draw_view_text_panel :: proc(state: ^core.EuclidGeneralState, scroll_y: ^f32) {
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

    rl.DrawRectangleRec(text_panel, ComponentBackgroundColor)
    rl.DrawRectangleLinesEx(text_panel, 1, BorderColor)

    view_text := julia.call_current_animation_get_view_text(state)
    max_chars := chars_per_text_row(text_panel.width - TEXT_PADDING * 2)
    total_rows := count_wrapped_text_rows(view_text, max_chars)
    content_h := TEXT_PADDING * 2 + f32(total_rows) * TEXT_ROW_HEIGHT
    max_scroll := max(f32(0), content_h - text_panel.height)

    mouse := rl.GetMousePosition()
    if rl.CheckCollisionPointRec(mouse, text_panel) {
        wheel := rl.GetMouseWheelMove()
        scroll_y^ -= wheel * (TEXT_ROW_HEIGHT * 2)
    }

    if scroll_y^ < 0 {
        scroll_y^ = 0
    }
    if scroll_y^ > max_scroll {
        scroll_y^ = max_scroll
    }

    rl.BeginScissorMode(i32(text_panel.x), i32(text_panel.y), i32(text_panel.width), i32(text_panel.height))
    draw_wrapped_text_content(view_text, text_panel, scroll_y^)
    rl.EndScissorMode()

    if max_scroll > 0 {
        track_w := f32(8)
        track := rl.Rectangle{text_panel.x + text_panel.width - track_w, text_panel.y, track_w, text_panel.height}
        thumb_h := max(f32(24), text_panel.height * (text_panel.height / content_h))
        thumb_y := text_panel.y + (scroll_y^ / max_scroll) * (text_panel.height - thumb_h)
        thumb := rl.Rectangle{track.x, thumb_y, track_w, thumb_h}

        text_mouse := rl.GetMousePosition()
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(text_mouse, thumb) {
            ui_runtime.TextScrollDragging = true
            ui_runtime.TextScrollDragOff = text_mouse.y - thumb_y
        }
        if ui_runtime.TextScrollDragging {
            if rl.IsMouseButtonDown(.LEFT) {
                new_thumb_y := text_mouse.y - ui_runtime.TextScrollDragOff
                t := (new_thumb_y - text_panel.y) / (text_panel.height - thumb_h)
                scroll_y^ = clamp(t, 0, 1) * max_scroll
            } else {
                ui_runtime.TextScrollDragging = false
            }
        }

        rl.DrawRectangleRec(track, BackgroundColor)
        rl.DrawRectangleRec(thumb, BorderColor)
    }
}
