package uilibrary

import native "../../native"
import bridgemodel "../../../bridge/model"
import core "../../../core"
import geometry "../../../core/geometry"
import view_font "../../font"
import uuid "core:encoding/uuid"
import viewmodel "../model"
import viewmessages "../../messages"
import uiwidgets "../widgets"
import treeview "../widgets/treeview"
import input "../../input"
import uisemantics "../semantics"
import theme "../theme"
import uilayout "../layout"

TREE_SEMANTIC_LOCAL_ID :: 1

Tree_Hit :: struct {
    selected_node : ^bridgemodel.Euclid_Julia_Animation_Interface,
    toggled_node : ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_node : ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_expander_node : ^bridgemodel.Euclid_Julia_Animation_Interface,
}

// Tree_Visibility_Policy supplies one coherent ordinary or search-filtered topology.
Tree_Visibility_Policy :: struct {
    search: ^viewmodel.Library_Search_State,
}

// Tree_Visible_Row_Context groups invariant state for one bounded row search.
Tree_Visible_Row_Context :: struct {
    ji: ^bridgemodel.Euclid_Julia_Interface,
    target: ^bridgemodel.Euclid_Julia_Animation_Interface,
    policy: Tree_Visibility_Policy,
}

// Tree_Semantic_Context groups current geometry for bounded item registration.
Tree_Semantic_Context :: struct {
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    policy: Tree_Visibility_Policy,
    tree_id: viewmodel.Ui_Node_Id,
    panel: geometry.Rectangle,
    scroll_y: f32,
    row: ^int,
    layout: ^Tree_Prepared_Layout,
}

// Prepared facts for publishing one tree item's semantics.
Tree_Item_Semantic_Publication :: struct {
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int,
    item_id: viewmodel.Ui_Node_Id,
    parent_id: viewmodel.Ui_Node_Id,
    states: viewmodel.Ui_Node_State,
    actions: viewmodel.Ui_Node_Action_Set,
    position: u16,
    size: u16,
}

// Tree_Visible_Node_Context groups one bounded visible-row lookup.
Tree_Visible_Node_Context :: struct {
    ji: ^bridgemodel.Euclid_Julia_Interface,
    target_row: int,
    row: ^int,
    policy: Tree_Visibility_Policy,
}

//   Prepared tree scrolling and bounded hover identities for observational drawing.
Tree_List_Preparation :: struct {
    scroll: uiwidgets.Scroll_Container_Update_Result,
    content_height: f32,
    hovered_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    pressed_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    layout: Tree_Prepared_Layout,
}

//   Inputs for one tree list panel frame, grouped so the call passes one value.
Tree_List_Params :: struct {
    label: string,
    ji : ^bridgemodel.Euclid_Julia_Interface,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    list_panel : geometry.Rectangle,
    mouse_input : input.Input_Frame,
    scroll_y : ^f32,
    font : view_font.Font_Face,
    font_resolver : view_font.Font_Resolver,
    visibility: Tree_Visibility_Policy,
}

//   Immutable per-frame tree walk inputs shared by every recursive row visit,
//   grouped so the walk procs do not thread nine loose arguments.
Tree_Walk_Context :: struct {
    ji : ^bridgemodel.Euclid_Julia_Interface,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    panel : geometry.Rectangle,
    scroll_y : f32,
    allow_clicks : bool,
    mouse_input : input.Input_Frame,
    scroll_offset : geometry.Vector2,
    interaction_space_rect : geometry.Rectangle,
    font : view_font.Font_Face,
    font_resolver : view_font.Font_Resolver,
    hovered_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    visibility: Tree_Visibility_Policy,
}


// Encoded_Tree_Walk_Context groups shared geometry for recursive tree drawing.
Encoded_Tree_Walk_Context :: struct {
    state: ^core.Euclid_General_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle,
    scroll_y: f32,
    content_y: ^f32,
    visibility: Tree_Visibility_Policy,
    pressed_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    render_only: bool,
}

// tree_node_is_visible reports whether the active topology includes one node.
tree_node_is_visible :: proc(
    policy: Tree_Visibility_Policy,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    if node == nil {
        return false
    }
    if policy.search == nil || !policy.search^.active {
        return true
    }
    for index in 0..<policy.search^.visible_id_count {
        if policy.search^.visible_ids[index] == node^.stable_id {
            return true
        }
    }
    return false
}

// tree_node_is_effectively_expanded derives required search paths without mutation.
tree_node_is_effectively_expanded :: proc(
    policy: Tree_Visibility_Policy,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    if node == nil {
        return false
    }
    if node^.is_expanded {
        return true
    }
    if policy.search == nil || !policy.search^.active {
        return false
    }
    for child := node^.first_child; child != nil; child = child^.next_sibling {
        if tree_node_is_visible(policy, child) {
            return true
        }
    }
    return false
}

// expanded_first_child returns only logically expanded children, never closing visual tails.
expanded_first_child :: proc(
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    policy: Tree_Visibility_Policy = {}) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    if node == nil || !tree_node_is_effectively_expanded(policy, node) {
        return nil
    }
    return node^.first_child
}

// tree_semantic_id identifies the Library tree independently of its rows.
tree_semantic_id :: #force_inline proc() -> viewmodel.Ui_Node_Id {
    return uisemantics.semantic_control_id(.Animation_Tree, TREE_SEMANTIC_LOCAL_ID)
}

// tree_item_semantic_id identifies one catalogue item by its permanent UUID.
tree_item_semantic_id :: #force_inline proc(
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> viewmodel.Ui_Node_Id {
    if node == nil {
        return {}
    }
    return {domain = .Animation_Tree, stable_id = node^.stable_id}
}

// tree_find_stable_id resolves one permanent animation identity.
tree_find_stable_id :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    stable_id: uuid.Identifier) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if ji == nil {
        return nil
    }
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.stable_id == stable_id {
            return node
        }
    }
    return nil
}

// tree_item_is_keyboard_active reports visible focus for one roving descendant.
tree_item_is_keyboard_active :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    if runtime == nil || node == nil || runtime^.semantic_focus == nil {
        return false
    }
    semantic := runtime^.semantic_focus
    return semantic^.window_focused && semantic^.focus_origin == .Keyboard &&
        semantic^.logical_focus == tree_semantic_id() &&
        semantic^.active_tree_item == node^.stable_id
}

// Draw the visible row background, focus outline, and disclosure control.
draw_encoded_tree_row :: proc(
    ctx: Encoded_Tree_Walk_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int, row_y: f32, expanded: bool = false) {
    row := geometry.Rectangle{
        ctx.panel.x, row_y, ctx.panel.width, theme.TREE_ROW_HEIGHT}
    if row.y + row.height >= ctx.panel.y &&
        row.y <= ctx.panel.y + ctx.panel.height {
        if node^.is_selected {
            _ = native.draw_encoder_rectangle(
                ctx.encoder, geometry.Rectangle(row), theme.UI_BORDER_COLOR)
        }
        if node == ctx.pressed_node {
            highlight := theme.UI_TEXT_COLOR
            highlight.a = 24
            _ = native.draw_encoder_rectangle(ctx.encoder, row, highlight)
        }
        if !ctx.render_only &&
           tree_item_is_keyboard_active(&ctx.state^.ui_runtime, node) {
            _ = native.draw_encoder_rectangle_outline(
                ctx.encoder, geometry.Rectangle(row), 2, theme.UI_TEXT_COLOR)
        }
        if node^.first_child != nil {
            icon := geometry.Rectangle{row.x + f32(depth) * theme.TREE_INDENT +
                theme.TREE_ROW_ICON_OFFSET_X, row.y + theme.TREE_ROW_ICON_OFFSET_Y,
                theme.TREE_ROW_ICON_SIZE, theme.TREE_ROW_ICON_SIZE}
            uiwidgets.draw_encoded_disclosure(ctx.encoder, icon, expanded)
        }
    }
}

// draw_encoded_tree_geometry encodes visible catalogue chrome without text.
draw_encoded_tree_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Tree_List_Preparation) {
    draw_encoded_prepared_tree(state, encoder, prepared, false)
    uiwidgets.draw_encoded_scrollbar(encoder, prepared.scroll.scrollbar)
}

// draw_encoded_tree_text emits the visible catalogue labels.
draw_encoded_tree_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Tree_List_Preparation) {
    draw_encoded_prepared_tree(state, encoder, prepared, true)
}

// Borrow the interface-owned title through preparation and deferred accordion drawing.
// Materialization copied it out of content storage; interface retirement, not
// content-generation retirement, ends this borrow.
selected_animation_title :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil ||
        state^.julia_interface^.selected_animation == nil {
        return viewmessages.shell_message(state, .Animation_Default_Title)
    }
    title := state^.julia_interface^.selected_animation^.name
    if len(title) == 0 {
        return viewmessages.shell_message(state, .Animation_Default_Title)
    }
    return title
}


//   Build a stable per-frame widget id for a node based on its pointer value.
tree_node_press_id :: #force_inline proc(
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> int {

    if node == nil {
        return -1
    }

    return int(uintptr(node) & uintptr(0x7fffffff))
}

//   Mark one animation selected and clear selection on others.
set_selected_animation :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    selected: ^bridgemodel.Euclid_Julia_Animation_Interface) {

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
    ji: ^bridgemodel.Euclid_Julia_Interface,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    remaining: int,
    policy: Tree_Visibility_Policy = {}) -> int {

    if ji == nil || node == nil || remaining <= 0 ||
        !tree_node_is_visible(policy, node) {
        return 0
    }

    count := 1
    if !tree_node_is_effectively_expanded(policy, node) || node.first_child == nil {
        return count
    }

    child := node.first_child
    steps := 0
    for child != nil && steps < ji.animation_count {
        count += count_visible_tree_rows_limited(
            ji, child, remaining - 1, policy)
        child = child.next_sibling
        steps += 1
    }

    return count
}

//   Count visible rows for all root trees with expansion state.
count_visible_tree_rows_all_roots :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    policy: Tree_Visibility_Policy = {}) -> int {
    if ji == nil {
        return 0
    }

    count := 0
    for node := ji.animation_head; node != nil; node = node.next_in_registry {
        if node.parent == nil {
            count += count_visible_tree_rows_limited(
                ji, node, ji.animation_count, policy)
        }
    }

    return count
}

//   Find a target's row in one visible depth-first tree branch.
tree_visible_row_limited :: proc(
    ctx: Tree_Visible_Row_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    row: ^int, remaining: int) -> (int, bool) {

    if ctx.ji == nil || node == nil || ctx.target == nil || remaining <= 0 ||
        !tree_node_is_visible(ctx.policy, node) {
        return 0, false
    }
    current_row := row^
    row^ += 1
    if node == ctx.target {
        return current_row, true
    }
    if !tree_node_is_effectively_expanded(ctx.policy, node) {
        return 0, false
    }
    for child, steps := node^.first_child, 0;
        child != nil && steps < ctx.ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {

        if found_row, found := tree_visible_row_limited(
            ctx, child, row, remaining - 1); found {
            return found_row, true
        }
    }
    return 0, false
}

//   Find a target's row across all visible root trees.
tree_visible_row :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    target: ^bridgemodel.Euclid_Julia_Animation_Interface,
    policy: Tree_Visibility_Policy = {}) -> (int, bool) {

    if ji == nil || target == nil {
        return 0, false
    }
    ctx := Tree_Visible_Row_Context{ji, target, policy}
    row := 0
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent != nil {
            continue
        }
        if found_row, found := tree_visible_row_limited(
            ctx, node, &row, ji^.animation_count); found {
            return found_row, true
        }
    }
    return 0, false
}

// tree_visible_node_at_row_limited resolves one row in a visible branch.
tree_visible_node_at_row_limited :: proc(
    ctx: Tree_Visible_Node_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    remaining: int) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if ctx.ji == nil || node == nil || remaining <= 0 ||
        !tree_node_is_visible(ctx.policy, node) {
        return nil
    }
    if ctx.row^ == ctx.target_row {
        return node
    }
    ctx.row^ += 1
    if !tree_node_is_effectively_expanded(ctx.policy, node) {
        return nil
    }
    for child, steps := node^.first_child, 0;
        child != nil && steps < ctx.ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {
        found := tree_visible_node_at_row_limited(ctx, child, remaining - 1)
        if found != nil {
            return found
        }
    }
    return nil
}

// tree_visible_node_at_row resolves one item in complete visible order.
tree_visible_node_at_row :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    target_row: int,
    policy: Tree_Visibility_Policy) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if ji == nil || target_row < 0 {
        return nil
    }
    row := 0
    ctx := Tree_Visible_Node_Context{ji, target_row, &row, policy}
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent != nil {
            continue
        }
        found := tree_visible_node_at_row_limited(ctx, node, ji^.animation_count)
        if found != nil {
            return found
        }
    }
    return nil
}

// tree_resolve_active_node restores a visible UUID or chooses selected then first.
tree_resolve_active_node :: proc(
    params: Tree_List_Params) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    active: ^bridgemodel.Euclid_Julia_Animation_Interface
    if params.ui_runtime^.semantic_focus != nil {
        active = tree_find_stable_id(
            params.ji, params.ui_runtime^.semantic_focus^.active_tree_item)
    }
    if _, found := tree_visible_row(params.ji, active, params.visibility); found {
        return active
    }
    selected := params.ji^.selected_animation
    if _, found := tree_visible_row(params.ji, selected, params.visibility); found {
        return selected
    }
    return tree_visible_node_at_row(params.ji, 0, params.visibility)
}

// tree_set_active_node commits roving identity and optional reveal intent.
tree_set_active_node :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    reveal: bool) {
    if runtime == nil || runtime^.semantic_focus == nil || node == nil {
        return
    }
    runtime^.semantic_focus^.active_tree_item = node^.stable_id
    if reveal {
        runtime^.tree_reveal_stable_id = node^.stable_id
        runtime^.tree_reveal_pending = true
        runtime^.tree_reveal_reason = .Navigation
    }
}

// tree_semantic_navigation_target resolves one roving movement command.
tree_semantic_navigation_target :: proc(
    params: Tree_List_Params,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface,
    kind: viewmodel.Ui_Focus_Command_Kind) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    row, _ := tree_visible_row(params.ji, active, params.visibility)
    count := count_visible_tree_rows_all_roots(params.ji, params.visibility)
    #partial switch kind {
    case .Tree_Previous: return tree_visible_node_at_row(
        params.ji, max(row - 1, 0), params.visibility)
    case .Tree_Next: return tree_visible_node_at_row(
        params.ji, min(row + 1, count - 1), params.visibility)
    case .Tree_First: return tree_visible_node_at_row(
        params.ji, 0, params.visibility)
    case .Tree_Last: return tree_visible_node_at_row(
        params.ji, count - 1, params.visibility)
    case:
    }
    return active
}

// tree_apply_parent_command collapses or moves to the visible parent.
tree_apply_parent_command :: proc(
    active: ^bridgemodel.Euclid_Julia_Animation_Interface) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    if active^.first_child != nil && active^.is_expanded {
        active^.is_expanded = false
    } else if active^.parent != nil {
        return active^.parent
    }
    return active
}

// tree_apply_child_command expands or moves to the first visible child.
tree_apply_child_command :: proc(
    policy: Tree_Visibility_Policy,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    if active^.first_child != nil && !active^.is_expanded {
        active^.is_expanded = true
        return active
    }
    for child := active^.first_child; child != nil; child = child^.next_sibling {
        if tree_node_is_visible(policy, child) {
            return child
        }
    }
    return active
}

// tree_apply_structure_command applies expansion and parent-child movement.
tree_apply_structure_command :: proc(
    params: Tree_List_Params,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface,
    kind: viewmodel.Ui_Focus_Command_Kind) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    tree_motion_anchor_action(params, active, kind)
    #partial switch kind {
    case .Tree_Parent: return tree_apply_parent_command(active)
    case .Tree_Child: return tree_apply_child_command(params.visibility, active)
    case .Toggle:
        if active^.first_child != nil {
            active^.is_expanded = !active^.is_expanded
        }
    case .Expand:
        if active^.first_child != nil {
            active^.is_expanded = true
        }
    case .Collapse:
        if active^.first_child != nil {
            active^.is_expanded = false
        }
    case:
    }
    return active
}

// tree_apply_semantic_command applies one addressed action through tree state.
tree_apply_semantic_command :: proc(
    params: Tree_List_Params,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface,
    command: viewmodel.Ui_Focus_Command) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    if active == nil ||
       command.kind == .Scroll_Page || command.kind == .Set_Scroll_Value {
        return active
    }
    target := tree_semantic_navigation_target(params, active, command.kind)
    target = tree_apply_structure_command(params, target, command.kind)
    if command.kind == .Select {
        set_selected_animation(params.ji, active)
        params.ui_runtime^.view_text_scroll_y = 0
    }
    if target != nil {
        tree_set_active_node(params.ui_runtime, target, true)
    }
    return target
}

// tree_semantic_command_target resolves composite and item-addressed commands.
tree_semantic_command_target :: proc(
    params: Tree_List_Params,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface,
    target: viewmodel.Ui_Node_Id) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if target == tree_semantic_id() {
        return active
    }
    if target.domain != .Animation_Tree {
        return nil
    }
    node := tree_find_stable_id(params.ji, target.stable_id)
    _, logical := tree_visible_row(params.ji, node, params.visibility)
    if !logical {
        return nil
    }
    return node
}

// tree_apply_semantic_commands consumes current commands addressed to the tree.
tree_apply_semantic_commands :: proc(
    params: Tree_List_Params) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    active := tree_resolve_active_node(params)
    semantic := params.ui_runtime^.semantic_focus
    if semantic == nil {
        return active
    }
    for command in semantic^.commands[:semantic^.command_count] {
        target := tree_semantic_command_target(params, active, command.target)
        if target == nil {
            continue
        }
        active = tree_apply_semantic_command(params, target, command)
    }
    if active != nil {
        tree_set_active_node(params.ui_runtime, active, false)
    }
    return active
}

// register_tree_item_semantics publishes one visible branch without allocation.
tree_item_set_facts :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    policy: Tree_Visibility_Policy,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> (u16, u16) {
    if ji == nil || node == nil {
        return 0, 0
    }
    position, size: u16
    for candidate := ji^.animation_head; candidate != nil;
        candidate = candidate^.next_in_registry {
        if candidate^.parent != node^.parent ||
           !tree_node_is_visible(policy, candidate) {
            continue
        }
        size += 1
        if candidate == node {
            position = size
        }
    }
    return position, size
}

// Publish one visible tree node using its computed parent, state, and geometry.
tree_publish_item_semantics :: proc(
    ctx: Tree_Semantic_Context, publication: Tree_Item_Semantic_Publication) {
    row := tree_layout_find(ctx.layout, publication.node)
    assert(row != nil, "logical tree row absent from prepared layout")
    geometry := tree_row_screen_geometry(row^, ctx.panel, ctx.scroll_y)
    states := publication.states
    actions := publication.actions
    if !tree_row_is_revealed(row^) {
        states -= {.Visible, .Enabled, .Focusable}
        actions = {}
    }
    _ = uisemantics.semantic_register_control(ctx.runtime^.semantic_focus, {
        id = publication.item_id, parent = publication.parent_id,
        role = .Tree_Item, states = states,
        actions = actions, region = .Accordion_Content,
        traversal_order = u16(ctx.row^), bounds = geometry.bounds,
        clip_bounds = geometry.clip_bounds, label = publication.node^.name,
        level = u16(publication.depth + 1),
        position_in_set = publication.position, set_size = publication.size,
    })
}

// Recursively publish the visible children of one expanded semantic node.
tree_publish_semantic_children :: proc(
    ctx: Tree_Semantic_Context, ji: ^bridgemodel.Euclid_Julia_Interface,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth, remaining: int) {
    for child, steps := expanded_first_child(node, ctx.policy), 0;
        child != nil && steps < ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {
        register_tree_item_semantics(ctx, ji, child, depth + 1, remaining - 1)
    }
}

// register_tree_item_semantics publishes one visible branch without allocation.
register_tree_item_semantics :: proc(
    ctx: Tree_Semantic_Context,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth, remaining: int) {
    if node == nil || remaining <= 0 || !tree_node_is_visible(ctx.policy, node) {
        return
    }
    item_id := tree_item_semantic_id(node)
    states := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable}
    if node^.is_selected {
        states += {.Selected}
    }
    if tree_node_is_effectively_expanded(ctx.policy, node) {
        states += {.Expanded}
    }
    actions := viewmodel.Ui_Node_Action_Set{.Focus, .Select}
    if node^.first_child != nil {
        actions += {.Expand, .Collapse, .Toggle}
    }
    parent_id := ctx.tree_id
    if node^.parent != nil {
        parent_id = tree_item_semantic_id(node^.parent)
    }
    position, size := tree_item_set_facts(ji, ctx.policy, node)
    tree_publish_item_semantics(ctx, {
        node = node, depth = depth, item_id = item_id, parent_id = parent_id,
        states = states, actions = actions, position = position, size = size,
    })
    ctx.row^ += 1
    tree_publish_semantic_children(ctx, ji, node, depth, remaining)
}

// register_tree_semantics publishes one Tab stop and its visible descendants.
register_tree_semantics :: proc(
    params: Tree_List_Params,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface,
    layout: ^Tree_Prepared_Layout) {
    tree_id := tree_semantic_id()
    active_id := tree_item_semantic_id(active)
    _ = uisemantics.semantic_register_control(params.ui_runtime^.semantic_focus, {
        id = tree_id, active_descendant = active_id, role = .Tree,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Select, .Expand, .Collapse, .Scroll},
        region = .Accordion_Content, traversal_order = 3,
        bounds = scroll.control_geometry.bounds,
        clip_bounds = scroll.control_geometry.clip_bounds,
        numeric_range = {f64(scroll.minimum), f64(scroll.maximum),
            f64(scroll.scroll_y_out), f64(scroll.step), scroll.orientation, true},
        label = params.label,
    })
    row := 0
    panel := geometry.Rectangle(scroll.control_geometry.bounds)
    ctx := Tree_Semantic_Context{params.ui_runtime, params.visibility,
        tree_id, panel, scroll.scroll_y_out, &row, layout}
    for node := params.ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent == nil {
            register_tree_item_semantics(
                ctx, params.ji, node, 0, params.ji^.animation_count)
        }
    }
}

//   Return the smallest clamped scroll that fully reveals one tree row.
tree_reveal_scroll :: proc(
    current_scroll: f32,
    row_index: int,
    viewport_height, content_height: f32) -> f32 {

    safe_viewport_height := max(viewport_height, 0)
    max_scroll := max(content_height - safe_viewport_height, 0)
    scroll := clamp(current_scroll, 0, max_scroll)
    row_top := f32(row_index) * theme.TREE_ROW_HEIGHT
    row_bottom := row_top + theme.TREE_ROW_HEIGHT
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
    target: ^bridgemodel.Euclid_Julia_Animation_Interface
    for node := params.ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.stable_id == ui_runtime^.tree_reveal_stable_id {
            target = node
            break
        }
    }
    row, found := tree_visible_row(params.ji, target, params.visibility)
    if !found {
        return
    }
    params.scroll_y^ = tree_reveal_scroll(
        params.scroll_y^, row, params.list_panel.height, content_height)
    ui_runtime^.tree_scroll_dragging = false
    ui_runtime^.tree_scroll_drag_off = 0
    if uiwidgets.scroll_container_owns_press(&ui_runtime^.ui_press_owner, 1003) {
        ui_runtime^.ui_press_owner = {}
    }
    ui_runtime^.tree_reveal_pending = false
}

//   Apply selection/expand hits and sync related UI state.
apply_tree_hit :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    hit: Tree_Hit) {

    if hit.toggled_node != nil {
        hit.toggled_node.is_expanded = !hit.toggled_node.is_expanded
        tree_set_active_node(ui_runtime, hit.toggled_node, false)
    }
    if hit.selected_node != nil {
        set_selected_animation(ji, hit.selected_node)
        tree_set_active_node(ui_runtime, hit.selected_node, false)
        ui_runtime.view_text_scroll_y = 0
        ui_runtime.text_scroll_dragging = false
        ui_runtime.text_scroll_drag_off = 0
    }
}

//   Resolve one node expander and record its hover and toggle identities.
update_tree_node_expander_hit :: proc(
    ctx: Tree_Walk_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    icon_rect: geometry.Rectangle,
    toggle_triggered: bool,
    hit: ^Tree_Hit) {

    if node.first_child == nil {
        return
    }

    expander_result := treeview.update_tree_expander(treeview.Tree_Expander_Params{
        rect = geometry.Rectangle(icon_rect),
        mouse = ctx.mouse_input,
        scroll_offset = geometry.Vector2(ctx.scroll_offset),
        interaction_space_rect = geometry.Rectangle(ctx.interaction_space_rect),
        interaction_enabled =
            ctx.allow_clicks && !ctx.ui_runtime.tree_scroll_dragging,
        toggle_triggered = toggle_triggered,
    })
    if expander_result.clicked {
        hit.toggled_node = node
    }
    if expander_result.hovered {
        hit.hovered_expander_node = node
    }
}

//   Resolve one tree row and capture selection, hover, and toggle identities.
update_tree_node_row :: proc(
    ctx: Tree_Walk_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int,
    row_rect: geometry.Rectangle,
    hit: ^Tree_Hit) {

    if node == nil {
        return
    }

    indent_x := row_rect.x + f32(depth) * theme.TREE_INDENT
    icon_rect := geometry.Rectangle{
        indent_x + theme.TREE_ROW_ICON_OFFSET_X,
        row_rect.y + theme.TREE_ROW_ICON_OFFSET_Y,
        theme.TREE_ROW_ICON_SIZE,
        theme.TREE_ROW_ICON_SIZE,
    }
    list_item_result := uiwidgets.update_list_item(uiwidgets.List_Item_Params{
        id = tree_node_press_id(node),
        rect = geometry.Rectangle(row_rect),
        can_expand_pos_y = false,
        selected = node.is_selected,
        mouse = ctx.mouse_input,
        scroll_offset = geometry.Vector2(ctx.scroll_offset),
        interaction_space_rect = geometry.Rectangle(ctx.interaction_space_rect),
        interaction_enabled = ctx.allow_clicks && !ctx.ui_runtime.tree_scroll_dragging,
    }, &ctx.ui_runtime.ui_press_owner)

    update_tree_node_expander_hit(ctx, node, icon_rect, list_item_result.clicked, hit)

    if list_item_result.clicked {
        hit.selected_node = node
    }
    if list_item_result.hovered {
        hit.hovered_node = node
    }
}

//   Commit tree scroll drag state from one update result.
commit_tree_scroll :: proc(
    params: Tree_List_Params,
    scroll: uiwidgets.Scroll_Container_Update_Result) {
    params.scroll_y^ = scroll.scroll_y_out
    params.ui_runtime.tree_scroll_dragging = scroll.state_out.is_dragging_thumb
    params.ui_runtime.tree_scroll_drag_off = scroll.state_out.drag_offset_y
}

//   Release completed list-item capture after tree interaction.
release_tree_list_capture :: proc(params: Tree_List_Params) {
    if params.ui_runtime.ui_press_owner.active &&
        params.ui_runtime.ui_press_owner.kind == .List_Item &&
        uiwidgets.input_frame_left_released(params.mouse_input) {
        params.ui_runtime.ui_press_owner = {}
    }
}

// finish_tree_interaction applies hits, publishes semantics, and releases capture.
finish_tree_interaction :: proc(
    params: Tree_List_Params,
    hit: Tree_Hit,
    prepared: ^Tree_List_Preparation) {
    if hit.toggled_node != nil {
        tree_motion_anchor(params, hit.toggled_node, &prepared^.layout)
    }
    apply_tree_hit(params.ji, params.ui_runtime, hit)
    if hit.toggled_node != nil {
        prepared^.layout = tree_prepare_layout(params)
        tree_refresh_preparation(params, prepared)
        uilayout.ui_release_geometry_capture(params.ui_runtime)
    }
    active := tree_resolve_active_node(params)
    register_tree_semantics(params, prepared^.scroll, active, &prepared^.layout)
    if hit.hovered_node != nil &&
       uiwidgets.input_frame_left_pressed(params.mouse_input) ||
       hit.selected_node != nil || hit.toggled_node != nil {
        _ = uisemantics.semantic_request_pointer_focus(
            params.ui_runtime^.semantic_focus, tree_semantic_id())
    }
    release_tree_list_capture(params)
}

// Return the hovered row only while it owns the held primary pointer press.
tree_pressed_node :: proc(
    params: Tree_List_Params,
    hovered: ^bridgemodel.Euclid_Julia_Animation_Interface) ->
    ^bridgemodel.Euclid_Julia_Animation_Interface {
    owner := params.ui_runtime^.ui_press_owner
    if hovered != nil && uiwidgets.input_frame_left_down(params.mouse_input) &&
        owner.active && owner.kind == .List_Item &&
        owner.id == tree_node_press_id(hovered) {
        return hovered
    }
    return nil
}

//   Resolve tree scrolling and row interaction before rendering.
prepare_tree_list_panel :: proc(params: Tree_List_Params) -> Tree_List_Preparation {
    if params.ji == nil || params.ji^.animation_count == 0 {
        params.ui_runtime^.tree_motion = {}
        return {}
    }
    layout := tree_prepare_layout(params)
    _ = tree_apply_semantic_commands(params)
    tree_motion_settle_navigation(params)
    layout = tree_prepare_layout(params)
    tree_apply_visual_reveal(params, &layout)
    tree_motion_apply_anchor(params, &layout)
    prepared := Tree_List_Preparation{layout = layout}
    prepared.scroll = tree_update_scroll(params, layout.content_height)
    commit_tree_scroll(params, prepared.scroll)
    tree_motion_release_anchor(params, prepared.scroll)
    hit := tree_update_prepared_rows(params, &prepared)
    finish_tree_interaction(params, hit, &prepared)
    prepared.content_height = prepared.layout.content_height
    prepared.hovered_node = hit.hovered_node
    prepared.hovered_expander_node = hit.hovered_expander_node
    prepared.pressed_node = tree_pressed_node(params, hit.hovered_node)
    return prepared
}
