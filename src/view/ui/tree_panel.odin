package ui

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

Tree_Hit :: struct {
    SelectedID: int,
    ToggledID:  int,
}

Tree_Toolbar_Hit :: struct {
    RefreshRequested: bool,
    TogglePauseRequested: bool,
    ToggleGifRequested: bool,
    ToggleSettingsRequested: bool,
}

//   Render the right-side tree panel and route toolbar interactions.
draw_tree_view :: proc(state: ^core.Euclid_General_State) {
    ji := state.julia_interface
    ui_runtime := &state.ui_runtime

    panel := rl.Rectangle{
        VIEW_WIDTH + TREE_PANEL_PADDING,
        TREE_PANEL_PADDING,
        RIGHT_BAR_WIDTH - TREE_PANEL_PADDING * 2,
        WINDOW_HEIGHT - TREE_PANEL_PADDING * 2,
    }

    rl.DrawRectangleRec(panel, BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    mouse := rl.GetMousePosition()
    toolbar_panel, list_panel := build_tree_view_panels(panel)

    toolbar_hit := draw_tree_toolbar(toolbar_panel, mouse,
        ui_runtime.show_tree_gif, ui_runtime.show_tree_settings, ui_runtime.simulation_paused)

    if toolbar_hit.RefreshRequested {
        if ui_runtime.simulation_paused &&
            (ui_runtime.gif_capture_phase == .Armed ||
            ui_runtime.gif_capture_phase == .Recording ||
            ui_runtime.gif_capture_phase == .Finalizing) {
            view_core.cancel_gif_capture_with_note(state,
                "Canceled: refresh during pause interrupts GIF capture.")
        }

        ui_runtime.simulation_paused = false
        ji.pending_animation_reset = true
    }

    if toolbar_hit.TogglePauseRequested {
        ui_runtime.simulation_paused = !ui_runtime.simulation_paused
    }

    if toolbar_hit.ToggleSettingsRequested {
        ui_runtime.show_tree_settings = !ui_runtime.show_tree_settings
        if ui_runtime.show_tree_settings {
            ui_runtime.show_tree_gif = false
        }
        ui_runtime.tree_scroll_dragging = false
    }

    if toolbar_hit.ToggleGifRequested {
        ui_runtime.show_tree_gif = !ui_runtime.show_tree_gif
        if ui_runtime.show_tree_gif {
            ui_runtime.show_tree_settings = false
        }
        ui_runtime.tree_scroll_dragging = false
    }

    if ui_runtime.show_tree_settings {
        draw_settings_view(state, list_panel, mouse)
        return
    }

    if ui_runtime.show_tree_gif {
        draw_gif_view(state, list_panel, mouse)
        return
    }

    draw_tree_list_panel(ji, ui_runtime, list_panel, mouse,
        &state^.ui_runtime.tree_scroll_y, state.font)
}

//   Draw a toolbar button and return click-hit state.
draw_toolbar_icon_button :: proc(
    rect: rl.Rectangle,
    mouse: rl.Vector2,
    active: bool,
    draw_icon: proc(rect: rl.Rectangle, color: rl.Color)) -> bool {

    hovered := rl.CheckCollisionPointRec(mouse, rect)
    pressed := hovered && rl.IsMouseButtonDown(.LEFT)

    icon_rect := rect
    icon_color := UI_TEXT_COLOR

    if active || pressed {
        rl.DrawRectangleRec(rect, UI_BORDER_COLOR)
        icon_color = BACKGROUND_COLOR
    }

    if pressed {
        icon_rect.x += 0.5
        icon_rect.y += 0.5
    }

    draw_icon(icon_rect, icon_color)
    return rl.IsMouseButtonPressed(.LEFT) && hovered
}

//   Render toolbar row and report refresh/settings toggle hits.
draw_tree_toolbar :: proc(
    panel: rl.Rectangle,
    mouse: rl.Vector2,
    show_gif: bool,
    show_settings: bool,
    simulation_paused: bool) -> Tree_Toolbar_Hit {

    hit := Tree_Toolbar_Hit{}

    rl.DrawRectangleRec(panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    refresh_rect := rl.Rectangle{
        panel.x + 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    pause_rect := rl.Rectangle{
        refresh_rect.x + TREE_TOOLBAR_BUTTON_SIZE + 4,
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

    gif_rect := rl.Rectangle{
        settings_rect.x - TREE_TOOLBAR_BUTTON_SIZE - 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    hit.RefreshRequested =
        draw_toolbar_icon_button(refresh_rect, mouse, false, draw_refresh_icon)

    pause_icon := draw_pause_icon
    if simulation_paused {
        pause_icon = draw_play_icon
    }
    hit.TogglePauseRequested =
        draw_toolbar_icon_button(pause_rect, mouse, simulation_paused, pause_icon)

    hit.ToggleGifRequested =
        draw_toolbar_icon_button(gif_rect, mouse, show_gif, draw_gif_icon)

    hit.ToggleSettingsRequested =
        draw_toolbar_icon_button(settings_rect, mouse, show_settings, draw_gear_icon)
    return hit
}

//   Mark one animation selected and clear selection on others.
set_selected_animation :: proc(ji: ^core.Euclid_Julia_Interface, selected_id: int) {
    if selected_id < 0 || selected_id >= ji.next_animation_index {
        return
    }

    for i in 0..<ji.next_animation_index {
        ji.animations[i].is_selected = (i == selected_id)
    }
    ji.selected_animation_index = selected_id
}

//   Count visible rows for all root trees with expansion state.
count_visible_tree_rows_all_roots :: proc(ji: ^core.Euclid_Julia_Interface) -> int {
    count := 0
    for i in 0..<ji.next_animation_index {
        if ji.animations[i].parent_id < 0 {
            count += count_visible_tree_rows_limited(ji, i, ji.next_animation_index)
        }
    }
    return count
}

//   Merge child tree hit results into a single accumulator.
merge_tree_hit :: #force_inline proc(dst: ^Tree_Hit, src: Tree_Hit) {
    if src.SelectedID >= 0 {
        dst.SelectedID = src.SelectedID
    }
    if src.ToggledID >= 0 {
        dst.ToggledID = src.ToggledID
    }
}

//   Apply selection/expand hits and sync related UI state.
apply_tree_hit :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    hit: Tree_Hit) {

    if hit.ToggledID >= 0 && hit.ToggledID < ji.next_animation_index {
        ji.animations[hit.ToggledID].is_expanded = !ji.animations[hit.ToggledID].is_expanded
    }
    if hit.SelectedID >= 0 {
        set_selected_animation(ji, hit.SelectedID)
        ui_runtime.view_text_scroll_y = 0
        ui_runtime.text_scroll_dragging = false
        ui_runtime.text_scroll_drag_off = 0
        ui_runtime.scratchpad_input_len = 0
        ui_runtime.scratchpad_input_cursor = 0
        ui_runtime.scratchpad_follow_output = false
    }
}

//   Traverse and draw root nodes, aggregating click hits.
walk_draw_tree_roots :: proc(
    ji: ^core.Euclid_Julia_Interface,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    font: rl.Font) -> Tree_Hit {

    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    for i in 0..<ji.next_animation_index {
        if ji.animations[i].parent_id >= 0 {
            continue
        }

        root_hit := walk_draw_tree_node_limited(ji, i, 0, panel, content_y, scroll_y,
            allow_clicks, mouse, ji.next_animation_index, font)
        merge_tree_hit(&hit, root_hit)
    }

    return hit
}

//   Count visible rows recursively with recursion guard limit.
count_visible_tree_rows_limited :: proc(
    ji: ^core.Euclid_Julia_Interface, id: int, remaining: int) -> int {

    if remaining <= 0 {
        return 0
    }

    if id < 0 || id >= ji.next_animation_index {
        return 0
    }

    count := 1
    n := &ji.animations[id]

    if !n.is_expanded || n.first_child_id < 0 {
        return count
    }

    child := n.first_child_id
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }
        count += count_visible_tree_rows_limited(ji, child, remaining - 1)
        child = ji.animations[child].next_sibling
        steps += 1
    }

    return count
}

//   Advance content cursor for skipped offscreen child branches.
accumulate_offscreen_child_rows :: proc(
    ji: ^core.Euclid_Julia_Interface,
    first_child: int,
    content_y: ^f32,
    remaining: int) {

    child := first_child
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }

        child_rows := count_visible_tree_rows_limited(ji, child, remaining - 1)
        content_y^ += f32(child_rows) * TREE_ROW_HEIGHT
        child = ji.animations[child].next_sibling
        steps += 1
    }
}

//   Traverse and draw child node branches with depth tracking.
walk_draw_child_nodes_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    first_child, depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
    font: rl.Font) -> Tree_Hit {

    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    child := first_child
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }

        child_hit := walk_draw_tree_node_limited(ji, child, depth + 1, panel, content_y,
            scroll_y, allow_clicks, mouse, remaining - 1, font)
        merge_tree_hit(&hit, child_hit)
        child = ji.animations[child].next_sibling
        steps += 1
    }

    return hit
}

//   Return first child id only when node is expanded.
expanded_first_child_id :: #force_inline proc(
    is_expanded: bool, first_child_id: int) -> int {

    if !is_expanded || first_child_id < 0 {
        return -1
    }
    return first_child_id
}

//   Render one tree row and capture selection/toggle interactions.
draw_tree_node_row :: proc(
    ji: ^core.Euclid_Julia_Interface,
    id: int,
    depth: int,
    row_rect: rl.Rectangle,
    allow_clicks: bool,
    mouse: rl.Vector2,
    hit: ^Tree_Hit,
    font: rl.Font) {

    node := &ji.animations[id]

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

    if node.is_selected {
        rl.DrawRectangleRec(row_rect, UI_BORDER_COLOR)
    }

    if node.first_child_id >= 0 {
        draw_tree_disclosure_icon(icon_rect, node.is_expanded, UI_TEXT_COLOR)

        if click && rl.CheckCollisionPointRec(mouse, icon_rect) {
            hit.ToggledID = id
        }
    }

    ui_text(node.name, label_x, int(row_rect.y + TREE_ROW_LABEL_OFFSET_Y),
        UI_TEXT_COLOR, font)

    if click && hovered {
        hit.SelectedID = id
    }
}

//   Traverse one tree node branch with clipping-aware row handling.
walk_draw_tree_node_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    id: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
    font: rl.Font) -> Tree_Hit {

    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    if remaining <= 0 {
        return hit
    }

    if id < 0 || id >= ji.next_animation_index {
        return hit
    }

    node := &ji.animations[id]
    child_first := expanded_first_child_id(node.is_expanded, node.first_child_id)

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
            child_hit := walk_draw_child_nodes_limited(ji, child_first, depth, panel,
                content_y, scroll_y, allow_clicks, mouse, remaining, font)
            merge_tree_hit(&hit, child_hit)
        }
        return hit
    }

    draw_tree_node_row(ji, id, depth, row_rect, allow_clicks, mouse, &hit, font)

    if child_first >= 0 {
        child_hit := walk_draw_child_nodes_limited(ji, child_first, depth, panel,
            content_y, scroll_y, allow_clicks, mouse, remaining, font)
        merge_tree_hit(&hit, child_hit)
    }

    return hit
}

//   Build toolbar and list panel rectangles inside tree container.
build_tree_view_panels :: proc(
    panel: rl.Rectangle) -> (rl.Rectangle, rl.Rectangle) {

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

//   Render tree list body, scrollbars, and visible node rows.
draw_tree_list_panel :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    list_panel: rl.Rectangle,
    mouse: rl.Vector2,
    scroll_y: ^f32,
    font: rl.Font) {

    rl.DrawRectangleRec(list_panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(list_panel, 1, UI_BORDER_COLOR)

    total_rows := count_visible_tree_rows_all_roots(ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    max_scroll := max(0.0, content_h - list_panel.height)

    apply_wheel_scroll(
        mouse,
        list_panel,
        TREE_ROW_HEIGHT,
        scroll_y,
        max_scroll,
        WHEEL_SCROLL_MULTIPLIER,
    )

    track := rl.Rectangle{}
    thumb_h: f32 = 0
    thumb := rl.Rectangle{}
    has_scrollbar := false

    allow_tree_clicks := true
    track, thumb, thumb_h, has_scrollbar = build_vertical_scrollbar(
        list_panel,
        content_h,
        scroll_y^,
        max_scroll,
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT,
    )
    if has_scrollbar {
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
            allow_tree_clicks = false
        }
    }

    rl.BeginScissorMode(i32(list_panel.x), i32(list_panel.y),
        i32(list_panel.width), i32(list_panel.height))
    {
        y_cursor: f32 = 0
        hit := walk_draw_tree_roots(ji, list_panel, &y_cursor, scroll_y^,
            allow_tree_clicks, mouse, font)
        apply_tree_hit(ji, ui_runtime, hit)
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
            &ui_runtime.tree_scroll_dragging,
            &ui_runtime.tree_scroll_drag_off,
            SCROLLBAR_DRAG_EPSILON,
        )

        rl.DrawRectangleRec(track, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb, UI_BORDER_COLOR)
    }
}
