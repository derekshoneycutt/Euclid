package ui

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

Tree_Hit :: struct {
    SelectedID: int,
    ToggledID:  int,
}

//   Render the right-side tree panel and route toolbar interactions.
draw_tree_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {
    ji := state.julia_interface
    ui_runtime := &state.ui_runtime

    _ = draw_container(panel, .Dark_Red)

    toolbar_panel, list_panel := build_tree_view_panels(panel)

    toolbar_hit := draw_tree_toolbar(toolbar_panel, mouse_input,
        &ui_runtime.ui_press_owner,
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
        draw_settings_view(state, list_panel, mouse_input)
        return
    }

    if ui_runtime.show_tree_gif {
        draw_gif_view(state, list_panel, mouse_input)
        return
    }

    draw_tree_list_panel(ji, ui_runtime, list_panel, mouse_input,
        &state^.ui_runtime.tree_scroll_y, state.font)
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
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    font: rl.Font) -> Tree_Hit {

    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    for i in 0..<ji.next_animation_index {
        if ji.animations[i].parent_id >= 0 {
            continue
        }

        root_hit := walk_draw_tree_node_limited(ji, ui_runtime, i, 0, panel, content_y, scroll_y,
            allow_clicks, mouse_input, scroll_offset, interaction_space_rect,
            ji.next_animation_index, font)
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
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    first_child, depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    remaining: int,
    font: rl.Font) -> Tree_Hit {

    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    child := first_child
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }

        child_hit := walk_draw_tree_node_limited(ji, ui_runtime, child, depth + 1, panel,
            content_y, scroll_y, allow_clicks, mouse_input, scroll_offset,
            interaction_space_rect, remaining - 1, font)
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
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    id: int,
    depth: int,
    row_rect: rl.Rectangle,
    allow_clicks: bool,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
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

    list_item_result := draw_list_item(List_Item_Params{
        id = id,
        rect = row_rect,
        can_expand_pos_y = false,
        selected = node.is_selected,
        mouse = mouse_input,
        scroll_offset = scroll_offset,
        interaction_space_rect = interaction_space_rect,
        interaction_enabled = allow_clicks && !ui_runtime.tree_scroll_dragging,
    }, &ui_runtime.ui_press_owner)

    if node.first_child_id >= 0 {
        expander_result := draw_tree_expander(Tree_Expander_Params{
            rect = icon_rect,
            expanded = node.is_expanded,
            mouse = mouse_input,
            scroll_offset = scroll_offset,
            interaction_space_rect = interaction_space_rect,
            interaction_enabled = allow_clicks && !ui_runtime.tree_scroll_dragging,
            toggle_triggered = list_item_result.clicked,
            color = UI_TEXT_COLOR,
        })
        if expander_result.clicked {
            hit.ToggledID = id
        }
    }

    ui_text(node.name, label_x, int(row_rect.y + TREE_ROW_LABEL_OFFSET_Y),
        UI_TEXT_COLOR, font)

    if list_item_result.clicked {
        hit.SelectedID = id
    }
}

//   Traverse one tree node branch with clipping-aware row handling.
walk_draw_tree_node_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    id: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
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
            child_hit := walk_draw_child_nodes_limited(ji, ui_runtime, child_first, depth,
                panel, content_y, scroll_y, allow_clicks, mouse_input,
                scroll_offset, interaction_space_rect, remaining, font)
            merge_tree_hit(&hit, child_hit)
        }
        return hit
    }

    draw_tree_node_row(ji, ui_runtime, id, depth, row_rect, allow_clicks,
        mouse_input, scroll_offset, interaction_space_rect, &hit, font)

    if child_first >= 0 {
        child_hit := walk_draw_child_nodes_limited(ji, ui_runtime, child_first, depth,
            panel, content_y, scroll_y, allow_clicks, mouse_input,
            scroll_offset, interaction_space_rect, remaining, font)
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

    list_panel = clamp_non_negative_rect(list_panel)

    return toolbar_panel, list_panel
}

//   Render tree list body, scrollbars, and visible node rows.
draw_tree_list_panel :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    list_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    scroll_y: ^f32,
    font: rl.Font) {

    _ = draw_container(list_panel, .Grey)

    total_rows := count_visible_tree_rows_all_roots(ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    tree_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.tree_scroll_dragging,
        drag_offset_y = ui_runtime.tree_scroll_drag_off,
    }
    tree_scroll_begin := scroll_container_begin(
        1003,
        list_panel,
        scroll_y^,
        content_h,
        mouse_input,
        rl.Vector2{},
        list_panel,
        TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER,
        &ui_runtime.ui_press_owner,
        tree_scroll_state)
    view_panel := tree_scroll_begin.view_rect
    scroll_y^ = tree_scroll_begin.scroll_y_out

    allow_tree_clicks := true
    if tree_scroll_begin.scroll_ref.is_hovered_thumb && mouse_input.left_pressed {
        allow_tree_clicks = false
    }

    y_cursor: f32 = 0
    hit := walk_draw_tree_roots(ji, ui_runtime, view_panel, &y_cursor, scroll_y^,
        allow_tree_clicks, mouse_input, rl.Vector2{}, view_panel, font)
    apply_tree_hit(ji, ui_runtime, hit)

    if ui_runtime.ui_press_owner.active &&
        ui_runtime.ui_press_owner.kind == .List_Item &&
        mouse_input.left_released {

        ui_runtime.ui_press_owner.active = false
        ui_runtime.ui_press_owner.kind = .None
        ui_runtime.ui_press_owner.id = -1
    }

    tree_scroll_end := scroll_container_end(
        tree_scroll_begin.scroll_ref,
        content_h,
        scroll_y^,
        mouse_input,
        rl.Vector2{},
        view_panel,
        &ui_runtime.ui_press_owner)
    scroll_y^ = tree_scroll_end.scroll_y_out
    ui_runtime.tree_scroll_dragging = tree_scroll_end.state_out.is_dragging_thumb
    ui_runtime.tree_scroll_drag_off = tree_scroll_end.state_out.drag_offset_y
}
