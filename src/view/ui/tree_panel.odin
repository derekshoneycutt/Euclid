package ui

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

Tree_Hit :: struct {
    selected_node: ^core.Euclid_Julia_Animation_Interface,
    toggled_node: ^core.Euclid_Julia_Animation_Interface,
}

//   Mutable walk cursor: running content y plus the remaining row budget.
Tree_Walk_Cursor :: struct {
    content_y: ^f32,
    remaining: int,
}

//   Inputs for one tree list panel frame, grouped so the call passes one value.
Tree_List_Params :: struct {
    ji:          ^core.Euclid_Julia_Interface,
    ui_runtime:  ^core.Euclid_Ui_Runtime_State,
    list_panel:  rl.Rectangle,
    mouse_input: Mouse_Input_State,
    scroll_y:    ^f32,
    font:        rl.Font,
}

//   Immutable per-frame tree walk inputs shared by every recursive row visit,
//   grouped so the walk procs do not thread nine loose arguments.
Tree_Walk_Context :: struct {
    ji:                     ^core.Euclid_Julia_Interface,
    ui_runtime:             ^core.Euclid_Ui_Runtime_State,
    panel:                  rl.Rectangle,
    scroll_y:               f32,
    allow_clicks:           bool,
    mouse_input:            Mouse_Input_State,
    scroll_offset:          rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    font:                   rl.Font,
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

    show_tree := !ui_runtime.show_tree_gif && !ui_runtime.show_tree_settings
    toolbar_hit := draw_tree_toolbar(Tree_Toolbar_Context{
        panel = toolbar_panel,
        mouse_input = mouse_input,
        press_owner = &ui_runtime.ui_press_owner,
        show_tree = show_tree,
        show_gif = ui_runtime.show_tree_gif,
        show_settings = ui_runtime.show_tree_settings,
        simulation_paused = ui_runtime.simulation_paused,
    })

    apply_tree_toolbar_hit(state, ji, ui_runtime, toolbar_hit)

    if ui_runtime.show_tree_settings {
        draw_settings_view(state, list_panel, mouse_input)
        return
    }

    if ui_runtime.show_tree_gif {
        draw_gif_view(state, list_panel, mouse_input)
        return
    }

    draw_tree_list_panel(Tree_List_Params{
        ji = ji,
        ui_runtime = ui_runtime,
        list_panel = list_panel,
        mouse_input = mouse_input,
        scroll_y = &state^.ui_runtime.tree_scroll_y,
        font = state.font,
    })
}

//   Cancel an in-flight GIF capture when the user refreshes while paused.
cancel_gif_capture_if_paused_mid_capture :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State) {

    if !ui_runtime.simulation_paused {
        return
    }
    phase := ui_runtime.gif_capture_phase
    if phase == .Armed || phase == .Recording || phase == .Finalizing {
        view_core.cancel_gif_capture_with_note(state,
            "Canceled: refresh during pause interrupts GIF capture.")
    }
}

//   Apply one toolbar interaction to tree panel state.
apply_tree_toolbar_hit :: proc(
    state: ^core.Euclid_General_State,
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    toolbar_hit: Tree_Toolbar_Hit) {

    if toolbar_hit.refresh_requested {
        cancel_gif_capture_if_paused_mid_capture(state, ui_runtime)
        ui_runtime.simulation_paused = false
        ji.pending_animation_reset = true
    }

    if toolbar_hit.toggle_pause_requested {
        ui_runtime.simulation_paused = !ui_runtime.simulation_paused
    }

    if toolbar_hit.toggle_tree_requested {
        ui_runtime.show_tree_gif = false
        ui_runtime.show_tree_settings = false
        ui_runtime.tree_scroll_dragging = false
    }

    if toolbar_hit.toggle_settings_requested {
        ui_runtime.show_tree_settings = !ui_runtime.show_tree_settings
        ui_runtime.show_tree_gif = ui_runtime.show_tree_gif &&
            !ui_runtime.show_tree_settings
        ui_runtime.tree_scroll_dragging = false
    }

    if toolbar_hit.toggle_gif_requested {
        ui_runtime.show_tree_gif = !ui_runtime.show_tree_gif
        ui_runtime.show_tree_settings = ui_runtime.show_tree_settings &&
            !ui_runtime.show_tree_gif
        ui_runtime.tree_scroll_dragging = false
    }
}

//   Build a stable per-frame widget id for a node based on its pointer value.
tree_node_press_id :: #force_inline proc(
    node: ^core.Euclid_Julia_Animation_Interface) -> int {

    if node == nil {
        return -1
    }

    return int(uintptr(node) & uintptr(0x7fffffff))
}

//   Mark one animation selected and clear selection on others.
set_selected_animation :: proc(
    ji: ^core.Euclid_Julia_Interface,
    selected: ^core.Euclid_Julia_Animation_Interface) {

    if ji == nil || selected == nil {
        return
    }

    for node := ji.animation_head; node != nil; node = node.next_in_registry {
        node.is_selected = (node == selected)
    }
    ji.selected_animation = selected
}

//   Count visible rows recursively with recursion guard limit.
count_visible_tree_rows_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    node: ^core.Euclid_Julia_Animation_Interface,
    remaining: int) -> int {

    if ji == nil || node == nil || remaining <= 0 {
        return 0
    }

    count := 1
    if !node.is_expanded || node.first_child == nil {
        return count
    }

    child := node.first_child
    steps := 0
    for child != nil && steps < ji.animation_count {
        count += count_visible_tree_rows_limited(ji, child, remaining - 1)
        child = child.next_sibling
        steps += 1
    }

    return count
}

//   Count visible rows for all root trees with expansion state.
count_visible_tree_rows_all_roots :: proc(ji: ^core.Euclid_Julia_Interface) -> int {
    if ji == nil {
        return 0
    }

    count := 0
    for node := ji.animation_head; node != nil; node = node.next_in_registry {
        if node.parent == nil {
            count += count_visible_tree_rows_limited(ji, node, ji.animation_count)
        }
    }

    return count
}

//   Merge child tree hit results into a single accumulator.
merge_tree_hit :: #force_inline proc(dst: ^Tree_Hit, src: Tree_Hit) {
    if src.selected_node != nil {
        dst.selected_node = src.selected_node
    }
    if src.toggled_node != nil {
        dst.toggled_node = src.toggled_node
    }
}

//   Apply selection/expand hits and sync related UI state.
apply_tree_hit :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    hit: Tree_Hit) {

    if hit.toggled_node != nil {
        hit.toggled_node.is_expanded = !hit.toggled_node.is_expanded
    }
    if hit.selected_node != nil {
        set_selected_animation(ji, hit.selected_node)
        ui_runtime.view_text_scroll_y = 0
        ui_runtime.text_scroll_dragging = false
        ui_runtime.text_scroll_drag_off = 0
        ui_runtime.scratchpad_input_len = 0
        ui_runtime.scratchpad_input_cursor = 0
        ui_runtime.scratchpad_input_mode = .Julia
        ui_runtime.scratchpad_bottom_pinned = true
    }
}

//   Advance content cursor for skipped offscreen child branches.
accumulate_offscreen_child_rows :: proc(
    ji: ^core.Euclid_Julia_Interface,
    first_child: ^core.Euclid_Julia_Animation_Interface,
    content_y: ^f32,
    remaining: int) {

    child := first_child
    steps := 0
    for child != nil && steps < ji.animation_count {
        child_rows := count_visible_tree_rows_limited(ji, child, remaining - 1)
        content_y^ += f32(child_rows) * TREE_ROW_HEIGHT
        child = child.next_sibling
        steps += 1
    }
}

//   Traverse and draw child node branches with depth tracking.
walk_draw_child_nodes_limited :: proc(
    ctx: Tree_Walk_Context,
    first_child: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) -> Tree_Hit {

    hit := Tree_Hit{}

    child := first_child
    steps := 0
    for child != nil && steps < ctx.ji.animation_count {
        child_hit := walk_draw_tree_node_limited(ctx, child, depth + 1, content_y,
            remaining - 1)
        merge_tree_hit(&hit, child_hit)
        child = child.next_sibling
        steps += 1
    }

    return hit
}

//   Return first child pointer only when node is expanded.
expanded_first_child :: #force_inline proc(
    node: ^core.Euclid_Julia_Animation_Interface) ->
    ^core.Euclid_Julia_Animation_Interface {

    if node == nil || !node.is_expanded {
        return nil
    }

    return node.first_child
}

//   Draw the expander for a node with children and report a toggle click.
draw_tree_node_expander :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    icon_rect: rl.Rectangle,
    toggle_triggered: bool,
    hit: ^Tree_Hit) {

    if node.first_child == nil {
        return
    }

    expander_result := draw_tree_expander(Tree_Expander_Params{
        rect = icon_rect,
        expanded = node.is_expanded,
        mouse = ctx.mouse_input,
        scroll_offset = ctx.scroll_offset,
        interaction_space_rect = ctx.interaction_space_rect,
        interaction_enabled =
            ctx.allow_clicks && !ctx.ui_runtime.tree_scroll_dragging,
        toggle_triggered = toggle_triggered,
        color = UI_TEXT_COLOR,
    })
    if expander_result.clicked {
        hit.toggled_node = node
    }
}

//   Render one tree row and capture selection/toggle interactions.
draw_tree_node_row :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    row_rect: rl.Rectangle,
    hit: ^Tree_Hit) {

    if node == nil {
        return
    }

    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := rl.Rectangle{
        indent_x + TREE_ROW_ICON_OFFSET_X,
        row_rect.y + TREE_ROW_ICON_OFFSET_Y,
        TREE_ROW_ICON_SIZE,
        TREE_ROW_ICON_SIZE,
    }
    label_x := int(indent_x + TREE_ROW_LABEL_OFFSET_X)

    list_item_result := draw_list_item(List_Item_Params{
        id = tree_node_press_id(node),
        rect = row_rect,
        can_expand_pos_y = false,
        selected = node.is_selected,
        mouse = ctx.mouse_input,
        scroll_offset = ctx.scroll_offset,
        interaction_space_rect = ctx.interaction_space_rect,
        interaction_enabled = ctx.allow_clicks && !ctx.ui_runtime.tree_scroll_dragging,
    }, &ctx.ui_runtime.ui_press_owner)

    draw_tree_node_expander(ctx, node, icon_rect, list_item_result.clicked, hit)

    view_core.ui_text(node.name, label_x, int(row_rect.y + TREE_ROW_LABEL_OFFSET_Y),
        UI_TEXT_COLOR, view_core.ui_text_font(ctx.font))

    if list_item_result.clicked {
        hit.selected_node = node
    }
}

//   Walk and merge child-node hits for one expanded parent.
walk_merge_child_hits :: proc(
    ctx: Tree_Walk_Context,
    child_first: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    cursor: Tree_Walk_Cursor,
    hit: ^Tree_Hit) {

    if child_first == nil {
        return
    }
    child_hit := walk_draw_child_nodes_limited(ctx, child_first, depth,
        cursor.content_y, cursor.remaining)
    merge_tree_hit(hit, child_hit)
}

//   Traverse one tree node branch with clipping-aware row handling.
walk_draw_tree_node_limited :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) -> Tree_Hit {

    hit := Tree_Hit{}

    if remaining <= 0 || node == nil {
        return hit
    }

    child_first := expanded_first_child(node)

    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT

    row_y_screen := ctx.panel.y + (row_y_world - ctx.scroll_y)
    row_rect := rl.Rectangle{ctx.panel.x, row_y_screen, ctx.panel.width,
        TREE_ROW_HEIGHT}

    if row_rect.y > ctx.panel.y + ctx.panel.height {
        if child_first != nil {
            accumulate_offscreen_child_rows(ctx.ji, child_first, content_y, remaining)
        }
        return hit
    }

    if row_rect.y + row_rect.height >= ctx.panel.y {
        draw_tree_node_row(ctx, node, depth, row_rect, &hit)
    }

    walk_merge_child_hits(ctx, child_first, depth,
        Tree_Walk_Cursor{content_y, remaining}, &hit)
    return hit
}

//   Traverse and draw root nodes, aggregating click hits.
walk_draw_tree_roots :: proc(
    ctx: Tree_Walk_Context,
    content_y: ^f32) -> Tree_Hit {

    hit := Tree_Hit{}

    for node := ctx.ji.animation_head; node != nil; node = node.next_in_registry {
        if node.parent != nil {
            continue
        }

        root_hit := walk_draw_tree_node_limited(ctx, node, 0, content_y,
            ctx.ji.animation_count)
        merge_tree_hit(&hit, root_hit)
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

//   Begin the tree list scroll container and return it with the clamped panel.
tree_list_scroll_begin :: proc(
    params: Tree_List_Params, content_h: f32) -> Scroll_Container_Begin_Result {

    scroll_begin := scroll_container_begin(Scroll_Container_Begin_Params{
        id = 1003,
        rect = params.list_panel,
        scroll_y_in = params.scroll_y^,
        content_height_hint = content_h,
        mouse_input = params.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = params.list_panel,
        wheel_step = TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &params.ui_runtime.ui_press_owner,
        state_in = Scroll_Container_State{
            is_dragging_thumb = params.ui_runtime.tree_scroll_dragging,
            drag_offset_y = params.ui_runtime.tree_scroll_drag_off,
        },
    })
    params.scroll_y^ = scroll_begin.scroll_y_out
    return scroll_begin
}

//   Walk and draw the visible tree rows, then release any completed press.
tree_list_walk_and_release :: proc(
    params: Tree_List_Params,
    scroll_begin: Scroll_Container_Begin_Result) {

    ui_runtime := params.ui_runtime
    allow_tree_clicks := true
    if scroll_begin.scroll_ref.is_hovered_thumb && params.mouse_input.left_pressed {
        allow_tree_clicks = false
    }

    y_cursor: f32 = 0
    walk_ctx := Tree_Walk_Context{
        ji = params.ji,
        ui_runtime = ui_runtime,
        panel = scroll_begin.view_rect,
        scroll_y = params.scroll_y^,
        allow_clicks = allow_tree_clicks,
        mouse_input = params.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = scroll_begin.view_rect,
        font = params.font,
    }
    hit := walk_draw_tree_roots(walk_ctx, &y_cursor)
    apply_tree_hit(params.ji, ui_runtime, hit)

    if ui_runtime.ui_press_owner.active &&
        ui_runtime.ui_press_owner.kind == .List_Item &&
        params.mouse_input.left_released {

        ui_runtime.ui_press_owner.active = false
        ui_runtime.ui_press_owner.kind = .None
        ui_runtime.ui_press_owner.id = -1
    }
}

//   End the tree list scroll container and commit drag state.
tree_list_scroll_end :: proc(
    params: Tree_List_Params,
    content_h: f32,
    scroll_begin: Scroll_Container_Begin_Result) {

    ui_runtime := params.ui_runtime
    scroll_end := scroll_container_end(
        Scroll_Container_End_Params{
            scroll_ref = scroll_begin.scroll_ref,
            content_height_final = content_h,
            scroll_y_in = params.scroll_y^,
            mouse_input = params.mouse_input,
            scroll_offset = rl.Vector2{},
            interaction_space_rect = scroll_begin.view_rect,
            press_owner = &ui_runtime.ui_press_owner,
        })
    params.scroll_y^ = scroll_end.scroll_y_out
    ui_runtime.tree_scroll_dragging = scroll_end.state_out.is_dragging_thumb
    ui_runtime.tree_scroll_drag_off = scroll_end.state_out.drag_offset_y
}

//   Render tree list body, scrollbars, and visible node rows.
draw_tree_list_panel :: proc(params: Tree_List_Params) {

    _ = draw_container(params.list_panel, .Grey)

    total_rows := count_visible_tree_rows_all_roots(params.ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    scroll_begin := tree_list_scroll_begin(params, content_h)
    tree_list_walk_and_release(params, scroll_begin)
    tree_list_scroll_end(params, content_h, scroll_begin)
}
