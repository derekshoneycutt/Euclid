package ui

import "../../core"
import view_core "../core"
import view_font "../font"

import rl "vendor:raylib"

Tree_Hit :: struct {
    selected_node : ^core.Euclid_Julia_Animation_Interface,
    toggled_node : ^core.Euclid_Julia_Animation_Interface,
    hovered_node : ^core.Euclid_Julia_Animation_Interface,
    hovered_expander_node : ^core.Euclid_Julia_Animation_Interface,
}

//   Prepared tree scrolling and bounded hover identities for observational drawing.
Tree_List_Preparation :: struct {
    scroll: Scroll_Container_Update_Result,
    content_height: f32,
    hovered_node: ^core.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^core.Euclid_Julia_Animation_Interface,
}

//   Mutable walk cursor: running content y plus the remaining row budget.
Tree_Walk_Cursor :: struct {
    content_y : ^f32,
    remaining : int,
}

//   Inputs for one tree list panel frame, grouped so the call passes one value.
Tree_List_Params :: struct {
    ji : ^core.Euclid_Julia_Interface,
    ui_runtime : ^core.Euclid_Ui_Runtime_State,
    list_panel : rl.Rectangle,
    mouse_input : Input_Frame,
    scroll_y : ^f32,
    font : rl.Font,
    font_resolver : view_font.Font_Resolver,
}

//   Immutable per-frame tree walk inputs shared by every recursive row visit,
//   grouped so the walk procs do not thread nine loose arguments.
Tree_Walk_Context :: struct {
    ji : ^core.Euclid_Julia_Interface,
    ui_runtime : ^core.Euclid_Ui_Runtime_State,
    panel : rl.Rectangle,
    scroll_y : f32,
    allow_clicks : bool,
    mouse_input : Input_Frame,
    scroll_offset : rl.Vector2,
    interaction_space_rect : rl.Rectangle,
    font : rl.Font,
    font_resolver : view_font.Font_Resolver,
    hovered_node: ^core.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^core.Euclid_Julia_Animation_Interface,
}

//   Resolve tree-toolbar interaction and commit its actions before rendering.
prepare_tree_view_controls :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Input_Frame) -> Tree_Toolbar_Preparation {

    ji := state.julia_interface
    ui_runtime := &state.ui_runtime
    toolbar_panel, _ := build_tree_view_panels(panel)

    show_tree := !ui_runtime.show_tree_gif && !ui_runtime.show_tree_settings
    prepared, toolbar_hit := update_tree_toolbar(Tree_Toolbar_Context{
        panel = toolbar_panel,
        mouse_input = mouse_input,
        press_owner = &ui_runtime.ui_press_owner,
        show_tree = show_tree,
        show_gif = ui_runtime.show_tree_gif,
        show_settings = ui_runtime.show_tree_settings,
        simulation_paused = ui_runtime.simulation_paused,
    })
    apply_tree_toolbar_hit(state, ji, ui_runtime, toolbar_hit)
    return prepared
}

//   Render the right-side tree panel from prepared toolbar interaction.
draw_tree_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    prepared: Ui_Control_Preparation) {

    ji := state.julia_interface
    ui_runtime := &state.ui_runtime
    _ = draw_container(panel, .Dark_Red)
    toolbar_panel, list_panel := build_tree_view_panels(panel)
    show_tree := !ui_runtime.show_tree_gif && !ui_runtime.show_tree_settings
    draw_tree_toolbar(Tree_Toolbar_Context{
        panel = toolbar_panel,
        mouse_input = mouse_input,
        press_owner = &ui_runtime.ui_press_owner,
        show_tree = show_tree,
        show_gif = ui_runtime.show_tree_gif,
        show_settings = ui_runtime.show_tree_settings,
        simulation_paused = ui_runtime.simulation_paused,
    }, prepared.tree_toolbar)

    if ui_runtime.show_tree_settings {
        draw_settings_view(state, list_panel, mouse_input, prepared.settings)
        return
    }

    if ui_runtime.show_tree_gif {
        draw_gif_view(state, list_panel, mouse_input, prepared.gif)
        return
    }

    draw_tree_list_panel(Tree_List_Params{
        ji = ji,
        ui_runtime = ui_runtime,
        list_panel = list_panel,
        mouse_input = mouse_input,
        scroll_y = &state^.ui_runtime.tree_scroll_y,
        font = view_font.cache_borrow(&state.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state.font_cache),
    }, prepared.tree)
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

//   Find a target's row in one visible depth-first tree branch.
tree_visible_row_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    node, target: ^core.Euclid_Julia_Animation_Interface,
    row: ^int,
    remaining: int) -> (int, bool) {

    if ji == nil || node == nil || target == nil || remaining <= 0 {
        return 0, false
    }
    current_row := row^
    row^ += 1
    if node == target {
        return current_row, true
    }
    if !node^.is_expanded {
        return 0, false
    }
    for child, steps := node^.first_child, 0;
        child != nil && steps < ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {

        if found_row, found := tree_visible_row_limited(
            ji, child, target, row, remaining - 1); found {
            return found_row, true
        }
    }
    return 0, false
}

//   Find a target's row across all visible root trees.
tree_visible_row :: proc(
    ji: ^core.Euclid_Julia_Interface,
    target: ^core.Euclid_Julia_Animation_Interface) -> (int, bool) {

    if ji == nil || target == nil {
        return 0, false
    }
    row := 0
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent != nil {
            continue
        }
        if found_row, found := tree_visible_row_limited(
            ji, node, target, &row, ji^.animation_count); found {
            return found_row, true
        }
    }
    return 0, false
}

//   Return the smallest clamped scroll that fully reveals one tree row.
tree_reveal_scroll :: proc(
    current_scroll: f32,
    row_index: int,
    viewport_height, content_height: f32) -> f32 {

    safe_viewport_height := max(viewport_height, 0)
    max_scroll := max(content_height - safe_viewport_height, 0)
    scroll := clamp(current_scroll, 0, max_scroll)
    row_top := f32(row_index) * TREE_ROW_HEIGHT
    row_bottom := row_top + TREE_ROW_HEIGHT
    if row_top < scroll {
        scroll = row_top
    } else if row_bottom > scroll + safe_viewport_height {
        scroll = row_bottom - safe_viewport_height
    }
    return clamp(scroll, 0, max_scroll)
}

//   Resolve and consume one stable tree reveal request when its row is visible.
apply_pending_tree_reveal :: proc(
    params: Tree_List_Params,
    content_height: f32) {

    ui_runtime := params.ui_runtime
    if ui_runtime == nil || !ui_runtime^.tree_reveal_pending {
        return
    }
    target: ^core.Euclid_Julia_Animation_Interface
    for node := params.ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.stable_id == ui_runtime^.tree_reveal_stable_id {
            target = node
            break
        }
    }
    row, found := tree_visible_row(params.ji, target)
    if !found {
        return
    }
    params.scroll_y^ = tree_reveal_scroll(
        params.scroll_y^, row, params.list_panel.height, content_height)
    ui_runtime^.tree_scroll_dragging = false
    ui_runtime^.tree_scroll_drag_off = 0
    if scroll_container_owns_press(&ui_runtime^.ui_press_owner, 1003) {
        ui_runtime^.ui_press_owner = {}
    }
    ui_runtime^.tree_reveal_pending = false
}

//   Merge child tree hit results into a single accumulator.
merge_tree_hit :: #force_inline proc(dst: ^Tree_Hit, src: Tree_Hit) {
    if src.selected_node != nil {
        dst.selected_node = src.selected_node
    }
    if src.toggled_node != nil {
        dst.toggled_node = src.toggled_node
    }
    if src.hovered_node != nil { dst.hovered_node = src.hovered_node }
    if src.hovered_expander_node != nil {
        dst.hovered_expander_node = src.hovered_expander_node
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

//   Traverse child node branches and resolve interaction with depth tracking.
walk_update_child_nodes_limited :: proc(
    ctx: Tree_Walk_Context,
    first_child: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) -> Tree_Hit {

    hit := Tree_Hit{}

    child := first_child
    steps := 0
    for child != nil && steps < ctx.ji.animation_count {
        child_hit := walk_update_tree_node_limited(ctx, child, depth + 1, content_y,
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

//   Resolve one node expander and record its hover and toggle identities.
update_tree_node_expander_hit :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    icon_rect: rl.Rectangle,
    toggle_triggered: bool,
    hit: ^Tree_Hit) {

    if node.first_child == nil {
        return
    }

    expander_result := update_tree_expander(Tree_Expander_Params{
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
    if expander_result.hovered { hit.hovered_expander_node = node }
}

//   Draw one tree node label at its indented row position.
draw_tree_node_label :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    x, y: f32) {

    view_core.ui_text_shaped({
        resolver = ctx.font_resolver,
        key = .Regular,
        text = node.name,
        position = {x, y},
        color = UI_TEXT_COLOR,
        font = view_core.ui_text_font(ctx.font),
    })
}

//   Resolve one tree row and capture selection, hover, and toggle identities.
update_tree_node_row :: proc(
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
    list_item_result := update_list_item(List_Item_Params{
        id = tree_node_press_id(node),
        rect = row_rect,
        can_expand_pos_y = false,
        selected = node.is_selected,
        mouse = ctx.mouse_input,
        scroll_offset = ctx.scroll_offset,
        interaction_space_rect = ctx.interaction_space_rect,
        interaction_enabled = ctx.allow_clicks && !ctx.ui_runtime.tree_scroll_dragging,
    }, &ctx.ui_runtime.ui_press_owner)

    update_tree_node_expander_hit(ctx, node, icon_rect, list_item_result.clicked, hit)

    if list_item_result.clicked {
        hit.selected_node = node
    }
    if list_item_result.hovered { hit.hovered_node = node }
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
    child_hit := walk_update_child_nodes_limited(ctx, child_first, depth,
        cursor.content_y, cursor.remaining)
    merge_tree_hit(hit, child_hit)
}

//   Traverse one tree node branch with clipping-aware row handling.
walk_update_tree_node_limited :: proc(
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
        update_tree_node_row(ctx, node, depth, row_rect, &hit)
    }

    walk_merge_child_hits(ctx, child_first, depth,
        Tree_Walk_Cursor{content_y, remaining}, &hit)
    return hit
}

//   Traverse and draw root nodes, aggregating click hits.
walk_update_tree_roots :: proc(
    ctx: Tree_Walk_Context,
    content_y: ^f32) -> Tree_Hit {

    hit := Tree_Hit{}

    for node := ctx.ji.animation_head; node != nil; node = node.next_in_registry {
        if node.parent != nil {
            continue
        }

        root_hit := walk_update_tree_node_limited(ctx, node, 0, content_y,
            ctx.ji.animation_count)
        merge_tree_hit(&hit, root_hit)
    }

    return hit
}

//   Draw one prepared tree row without changing interaction or application state.
draw_tree_node_row :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    row_rect: rl.Rectangle) {
    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := rl.Rectangle{indent_x + TREE_ROW_ICON_OFFSET_X,
        row_rect.y + TREE_ROW_ICON_OFFSET_Y, TREE_ROW_ICON_SIZE, TREE_ROW_ICON_SIZE}
    item_params := List_Item_Params{id = tree_node_press_id(node), rect = row_rect,
        selected = node.is_selected, mouse = ctx.mouse_input,
        interaction_space_rect = ctx.interaction_space_rect}
    draw_list_item_prepared(item_params, {drawn_rect = row_rect,
        inner_rect = row_rect, hovered = ctx.hovered_node == node},
        ctx.ui_runtime.ui_press_owner)
    if node.first_child != nil {
        expander_params := Tree_Expander_Params{rect = icon_rect,
            expanded = node.is_expanded, mouse = ctx.mouse_input,
            interaction_space_rect = ctx.interaction_space_rect,
            color = UI_TEXT_COLOR}
        hovered := ctx.hovered_expander_node == node
        draw_tree_expander_prepared(expander_params, {hovered = hovered,
            pressed = hovered && input_frame_left_down(ctx.mouse_input)})
    }
    draw_tree_node_label(ctx, node, indent_x + TREE_ROW_LABEL_OFFSET_X,
        row_rect.y + TREE_ROW_LABEL_OFFSET_Y)
}

//   Draw visible child branches without resolving any interaction.
walk_draw_child_nodes_limited :: proc(
    ctx: Tree_Walk_Context,
    first_child: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) {
    for child, steps := first_child, 0;
        child != nil && steps < ctx.ji.animation_count;
        child, steps = child.next_sibling, steps + 1 {
        walk_draw_tree_node_limited(
            ctx, child, depth + 1, content_y, remaining - 1)
    }
}

//   Draw one visible tree branch with clipping-aware row handling.
walk_draw_tree_node_limited :: proc(
    ctx: Tree_Walk_Context,
    node: ^core.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) {
    if remaining <= 0 || node == nil { return }
    child_first := expanded_first_child(node)
    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT
    row_rect := rl.Rectangle{ctx.panel.x,
        ctx.panel.y + row_y_world - ctx.scroll_y,
        ctx.panel.width, TREE_ROW_HEIGHT}
    if row_rect.y > ctx.panel.y + ctx.panel.height {
        if child_first != nil {
            accumulate_offscreen_child_rows(ctx.ji, child_first, content_y, remaining)
        }
        return
    }
    if row_rect.y + row_rect.height >= ctx.panel.y {
        draw_tree_node_row(ctx, node, depth, row_rect)
    }
    if child_first != nil {
        walk_draw_child_nodes_limited(
            ctx, child_first, depth, content_y, remaining)
    }
}

//   Draw all visible root branches without resolving interaction.
walk_draw_tree_roots :: proc(ctx: Tree_Walk_Context) {
    content_y: f32
    for node := ctx.ji.animation_head; node != nil; node = node.next_in_registry {
        if node.parent == nil {
            walk_draw_tree_node_limited(
                ctx, node, 0, &content_y, ctx.ji.animation_count)
        }
    }
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

//   Commit tree scroll drag state from one update result.
commit_tree_scroll :: proc(
    params: Tree_List_Params,
    scroll: Scroll_Container_Update_Result) {
    params.scroll_y^ = scroll.scroll_y_out
    params.ui_runtime.tree_scroll_dragging = scroll.state_out.is_dragging_thumb
    params.ui_runtime.tree_scroll_drag_off = scroll.state_out.drag_offset_y
}

//   Recount expanded topology and reclamp the prepared tree scrollbar.
reconcile_tree_topology :: proc(
    params: Tree_List_Params,
    scroll: ^Scroll_Container_Update_Result,
    content_height: ^f32) {
    content_height^ = f32(count_visible_tree_rows_all_roots(params.ji)) * TREE_ROW_HEIGHT
    max_scroll := max(content_height^ - scroll^.view_rect.height, 0)
    params.scroll_y^ = clamp(params.scroll_y^, 0, max_scroll)
    scroll^.scroll_y_out = params.scroll_y^
    scroll^.scrollbar = build_vertical_scrollbar(
        {scroll^.view_rect, content_height^, scroll^.scroll_y_out, max_scroll},
        SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
}

//   Release completed list-item capture after tree interaction.
release_tree_list_capture :: proc(params: Tree_List_Params) {
    if params.ui_runtime.ui_press_owner.active &&
        params.ui_runtime.ui_press_owner.kind == .List_Item &&
        input_frame_left_released(params.mouse_input) {
        params.ui_runtime.ui_press_owner = {}
    }
}

//   Resolve tree scrolling and row interaction before rendering.
prepare_tree_list_panel :: proc(params: Tree_List_Params) -> Tree_List_Preparation {
    total_rows := count_visible_tree_rows_all_roots(params.ji)
    if total_rows <= 0 { return {} }
    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    apply_pending_tree_reveal(params, content_h)
    scroll := scroll_container_update({id = UI_TREE_SCROLLBAR_ID,
        rect = params.list_panel, scroll_y_in = params.scroll_y^,
        content_height = content_h, mouse_input = params.mouse_input,
        interaction_space_rect = params.list_panel,
        wheel_step = TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &params.ui_runtime.ui_press_owner,
        state_in = {params.ui_runtime.tree_scroll_dragging,
            params.ui_runtime.tree_scroll_drag_off}})
    commit_tree_scroll(params, scroll)
    walk_ctx := Tree_Walk_Context{ji = params.ji, ui_runtime = params.ui_runtime,
        panel = scroll.view_rect, scroll_y = scroll.scroll_y_out,
        allow_clicks = !(scroll.pointer_reserved &&
            input_frame_left_pressed(params.mouse_input)),
        mouse_input = params.mouse_input, interaction_space_rect = scroll.view_rect,
        font = params.font, font_resolver = params.font_resolver}
    content_y: f32
    hit := walk_update_tree_roots(walk_ctx, &content_y)
    apply_tree_hit(params.ji, params.ui_runtime, hit)
    if hit.toggled_node != nil {
        reconcile_tree_topology(params, &scroll, &content_h)
    }
    release_tree_list_capture(params)
    return {scroll, content_h, hit.hovered_node, hit.hovered_expander_node}
}

//   Render the prepared tree list without mutating interaction state.
draw_tree_list_panel :: proc(
    params: Tree_List_Params,
    prepared: Tree_List_Preparation) {
    _ = draw_container(params.list_panel, .Grey)
    if prepared.content_height <= 0 { return }
    scroll_container_draw_begin(prepared.scroll)
    walk_draw_tree_roots(Tree_Walk_Context{ji = params.ji,
        ui_runtime = params.ui_runtime, panel = prepared.scroll.view_rect,
        scroll_y = prepared.scroll.scroll_y_out, mouse_input = params.mouse_input,
        interaction_space_rect = prepared.scroll.view_rect, font = params.font,
        font_resolver = params.font_resolver, hovered_node = prepared.hovered_node,
        hovered_expander_node = prepared.hovered_expander_node})
    scroll_container_draw_end(prepared.scroll)
}
