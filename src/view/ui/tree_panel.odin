package ui

import native "../native"

import viewmodel "../model"
import view_core "../core"

import bridgemodel "../../bridge/model"
import "../../core"
import geometry "../../core/geometry"
import view_font "../font"
import "core:encoding/uuid"

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
    scroll: Scroll_Container_Update_Result,
    content_height: f32,
    hovered_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    pressed_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
}

//   Mutable walk cursor: running content y plus the remaining row budget.
Tree_Walk_Cursor :: struct {
    content_y : ^f32,
    remaining : int,
}

//   Inputs for one tree list panel frame, grouped so the call passes one value.
Tree_List_Params :: struct {
    label: string,
    ji : ^bridgemodel.Euclid_Julia_Interface,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    list_panel : geometry.Rectangle,
    mouse_input : Input_Frame,
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
    mouse_input : Input_Frame,
    scroll_offset : geometry.Vector2,
    interaction_space_rect : geometry.Rectangle,
    font : view_font.Font_Face,
    font_resolver : view_font.Font_Resolver,
    hovered_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    hovered_expander_node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    visibility: Tree_Visibility_Policy,
}

// Frame-local prepared values consumed by accordion child drawing.
Accordion_Draw_Preparation :: struct {
    controls: Ui_Control_Preparation,
    terminal: Terminal_Prepared_Frame,
    presentation: Presentation_Preparation,
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

// tree_semantic_id identifies the Library tree independently of its rows.
tree_semantic_id :: #force_inline proc() -> viewmodel.Ui_Node_Id {
    return semantic_control_id(.Animation_Tree, TREE_SEMANTIC_LOCAL_ID)
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
    depth: int, row_y: f32) {
    row := geometry.Rectangle{
        ctx.panel.x, row_y, ctx.panel.width, TREE_ROW_HEIGHT}
    if row.y + row.height >= ctx.panel.y &&
        row.y <= ctx.panel.y + ctx.panel.height {
        if node^.is_selected {
            _ = native.draw_encoder_rectangle(
                ctx.encoder, geometry.Rectangle(row), UI_BORDER_COLOR)
        }
        if node == ctx.pressed_node {
            highlight := UI_TEXT_COLOR
            highlight.a = 24
            _ = native.draw_encoder_rectangle(ctx.encoder, row, highlight)
        }
        if tree_item_is_keyboard_active(&ctx.state^.ui_runtime, node) {
            _ = native.draw_encoder_rectangle_outline(
                ctx.encoder, geometry.Rectangle(row), 2, UI_TEXT_COLOR)
        }
        if node^.first_child != nil {
            icon := geometry.Rectangle{row.x + f32(depth) * TREE_INDENT +
                TREE_ROW_ICON_OFFSET_X, row.y + TREE_ROW_ICON_OFFSET_Y,
                TREE_ROW_ICON_SIZE, TREE_ROW_ICON_SIZE}
            draw_encoded_disclosure(ctx.encoder, icon,
                tree_node_is_effectively_expanded(ctx.visibility, node))
        }
    }
}

// draw_encoded_tree_node encodes one visible tree branch without its labels.
draw_encoded_tree_node :: proc(
    ctx: Encoded_Tree_Walk_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth, remaining: int) {
    if ctx.ji == nil || node == nil || remaining <= 0 ||
        !tree_node_is_visible(ctx.visibility, node) {
        return
    }
    row_y := ctx.panel.y + ctx.content_y^ - ctx.scroll_y
    ctx.content_y^ += TREE_ROW_HEIGHT
    draw_encoded_tree_row(ctx, node, depth, row_y)
    if !tree_node_is_effectively_expanded(ctx.visibility, node) {
        return
    }
    for child, steps := node^.first_child, 0;
        child != nil && steps < ctx.ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {
        draw_encoded_tree_node(ctx, child, depth + 1, remaining - 1)
    }
}

// draw_encoded_tree_geometry encodes visible catalogue chrome without text.
draw_encoded_tree_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle,
    pressed_node: ^bridgemodel.Euclid_Julia_Animation_Interface = nil) {
    if state == nil || state^.julia_interface == nil {
        return
    }
    ji := state^.julia_interface
    visibility := Tree_Visibility_Policy{search = &state^.ui_runtime.library_search}
    content_height := f32(count_visible_tree_rows_all_roots(
        ji, visibility)) * TREE_ROW_HEIGHT
    max_scroll := max(content_height - panel.height, 0)
    scroll_y := clamp(state^.ui_runtime.tree_scroll_y, 0, max_scroll)
    scrollbar := build_vertical_scrollbar(
        {panel, content_height, scroll_y, max_scroll},
        SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
    _ = native.draw_encoder_push_scissor(encoder, geometry.Rectangle(panel))
    content_y: f32
    ctx := Encoded_Tree_Walk_Context{
        state = state, ji = ji, encoder = encoder, panel = panel,
        scroll_y = scroll_y, content_y = &content_y, visibility = visibility,
        pressed_node = pressed_node}
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent == nil {
            draw_encoded_tree_node(ctx, node, 0, ji^.animation_count)
        }
    }
    _ = native.draw_encoder_pop_scissor(encoder)
    draw_encoded_scrollbar(encoder, scrollbar)
}

// draw_encoded_tree_node_text emits visible labels in one bounded tree walk.
draw_encoded_tree_node_text :: proc(
    ctx: Encoded_Tree_Walk_Context,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth, remaining: int) {
    if node == nil || remaining <= 0 ||
        !tree_node_is_visible(ctx.visibility, node) {
        return
    }
    row_y := ctx.panel.y + ctx.content_y^ - ctx.scroll_y
    ctx.content_y^ += TREE_ROW_HEIGHT
    if row_y + TREE_ROW_HEIGHT >= ctx.panel.y &&
        row_y <= ctx.panel.y + ctx.panel.height {
        draw_encoded_label(ctx.state, ctx.encoder, node^.name,
            ctx.panel.x + f32(depth) * TREE_INDENT + TREE_ROW_LABEL_OFFSET_X,
            row_y + TREE_ROW_LABEL_OFFSET_Y)
    }
    if !tree_node_is_effectively_expanded(ctx.visibility, node) {
        return
    }
    for child, steps := node^.first_child, 0;
        child != nil && steps < ctx.ji^.animation_count;
        child, steps = child^.next_sibling, steps + 1 {
        draw_encoded_tree_node_text(ctx, child, depth + 1, remaining - 1)
    }
}

// draw_encoded_tree_text emits the visible catalogue labels.
draw_encoded_tree_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    ji := state^.julia_interface
    if ji == nil {
        return
    }
    visibility := Tree_Visibility_Policy{search = &state^.ui_runtime.library_search}
    content_height := f32(count_visible_tree_rows_all_roots(
        ji, visibility)) * TREE_ROW_HEIGHT
    scroll_y := clamp(state^.ui_runtime.tree_scroll_y,
        0, max(content_height - panel.height, 0))
    content_y: f32
    ctx := Encoded_Tree_Walk_Context{state, ji, encoder, panel,
        scroll_y, &content_y, visibility, nil}
    _ = native.draw_encoder_push_scissor(encoder, geometry.Rectangle(panel))
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.parent == nil {
            draw_encoded_tree_node_text(ctx, node, 0, ji^.animation_count)
        }
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

// Borrow the interface-owned title through preparation and deferred accordion drawing.
// Materialization copied it out of content storage; interface retirement, not
// content-generation retirement, ends this borrow.
selected_animation_title :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil ||
        state^.julia_interface^.selected_animation == nil {
        return view_core.shell_message(state, .Animation_Default_Title)
    }
    title := state^.julia_interface^.selected_animation^.name
    if len(title) == 0 {
        return view_core.shell_message(state, .Animation_Default_Title)
    }
    return title
}

// Prepare accordion headers and commit one active section before child updates.
prepare_accordion_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: Input_Frame) -> Accordion_Preparation {
    ui_runtime := &state^.ui_runtime
    active_before := ui_runtime^.active_accordion_section
    sections := accordion_sections_for_layout(
        ui_runtime^.current_layout_mode, selected_animation_title(state), state)
    prepared := prepare_accordion(Accordion_Context{
        panel = geometry.Rectangle(panel),
        mouse_input = mouse_input,
        press_owner = &ui_runtime^.ui_press_owner,
        semantic_focus = ui_runtime^.semantic_focus,
        active = ui_runtime^.active_accordion_section,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        transition = &ui_runtime^.accordion_transition,
        reduce_motion = ui_reduced_motion(ui_runtime),
    }, sections, &ui_runtime^.active_accordion_section)
    if active_before != ui_runtime^.active_accordion_section {
        ui_release_geometry_capture(ui_runtime)
        ui_runtime^.tooltip = {}
        ui_runtime^.context_menu.active = false
        _ = ui_publish_presentation_visibility(ui_runtime)
    }
    return prepared
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
    if active == nil {
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
    if !tree_node_is_visible(params.visibility, node) {
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
    bounds := geometry.Rectangle{ctx.panel.x,
        ctx.panel.y + f32(ctx.row^) * TREE_ROW_HEIGHT - ctx.scroll_y,
        ctx.panel.width, TREE_ROW_HEIGHT}
    _ = semantic_register_control(ctx.runtime^.semantic_focus, {
        id = publication.item_id, parent = publication.parent_id,
        role = .Tree_Item, states = publication.states,
        actions = publication.actions, region = .Accordion_Content,
        traversal_order = u16(ctx.row^), bounds = viewmodel.Rectangle(bounds),
        clip_bounds = viewmodel.Rectangle(ctx.panel), label = publication.node^.name,
        level = u16(publication.depth + 1),
        position_in_set = publication.position, set_size = publication.size,
    })
}

// Recursively publish the visible children of one expanded semantic node.
tree_publish_semantic_children :: proc(
    ctx: Tree_Semantic_Context, ji: ^bridgemodel.Euclid_Julia_Interface,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth, remaining: int) {
    if !tree_node_is_effectively_expanded(ctx.policy, node) {
        return
    }
    for child, steps := node^.first_child, 0;
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
    scroll: Scroll_Container_Update_Result,
    active: ^bridgemodel.Euclid_Julia_Animation_Interface) {
    tree_id := tree_semantic_id()
    active_id := tree_item_semantic_id(active)
    _ = semantic_register_control(params.ui_runtime^.semantic_focus, {
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
        tree_id, panel, scroll.scroll_y_out, &row}
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
    if src.hovered_node != nil {
        dst.hovered_node = src.hovered_node
    }
    if src.hovered_expander_node != nil {
        dst.hovered_expander_node = src.hovered_expander_node
    }
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

//   Advance content cursor for skipped offscreen child branches.
accumulate_offscreen_child_rows :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    first_child: ^bridgemodel.Euclid_Julia_Animation_Interface,
    content_y: ^f32,
    remaining: int,
    policy: Tree_Visibility_Policy = {}) {

    child := first_child
    steps := 0
    for child != nil && steps < ji.animation_count {
        child_rows := count_visible_tree_rows_limited(
            ji, child, remaining - 1, policy)
        content_y^ += f32(child_rows) * TREE_ROW_HEIGHT
        child = child.next_sibling
        steps += 1
    }
}

//   Traverse child node branches and resolve interaction with depth tracking.
walk_update_child_nodes_limited :: proc(
    ctx: Tree_Walk_Context,
    first_child: ^bridgemodel.Euclid_Julia_Animation_Interface,
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
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    policy: Tree_Visibility_Policy = {}) ->
    ^bridgemodel.Euclid_Julia_Animation_Interface {

    if node == nil || !tree_node_is_effectively_expanded(policy, node) {
        return nil
    }

    return node.first_child
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

    expander_result := update_tree_expander(Tree_Expander_Params{
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

    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := geometry.Rectangle{
        indent_x + TREE_ROW_ICON_OFFSET_X,
        row_rect.y + TREE_ROW_ICON_OFFSET_Y,
        TREE_ROW_ICON_SIZE,
        TREE_ROW_ICON_SIZE,
    }
    list_item_result := update_list_item(List_Item_Params{
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

//   Walk and merge child-node hits for one expanded parent.
walk_merge_child_hits :: proc(
    ctx: Tree_Walk_Context,
    child_first: ^bridgemodel.Euclid_Julia_Animation_Interface,
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
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: ^f32,
    remaining: int) -> Tree_Hit {

    hit := Tree_Hit{}

    if remaining <= 0 || node == nil {
        return hit
    }

    if !tree_node_is_visible(ctx.visibility, node) {
        return hit
    }
    child_first := expanded_first_child(node, ctx.visibility)

    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT

    row_y_screen := ctx.panel.y + (row_y_world - ctx.scroll_y)
    row_rect := geometry.Rectangle{ctx.panel.x, row_y_screen, ctx.panel.width,
        TREE_ROW_HEIGHT}

    if row_rect.y > ctx.panel.y + ctx.panel.height {
        if child_first != nil {
            accumulate_offscreen_child_rows(
                ctx.ji, child_first, content_y, remaining, ctx.visibility)
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
    content_height^ = f32(count_visible_tree_rows_all_roots(
        params.ji, params.visibility)) * TREE_ROW_HEIGHT
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

// finish_tree_interaction applies hits, publishes semantics, and releases capture.
finish_tree_interaction :: proc(
    params: Tree_List_Params,
    hit: Tree_Hit,
    scroll: ^Scroll_Container_Update_Result,
    content_height: ^f32) {
    apply_tree_hit(params.ji, params.ui_runtime, hit)
    if hit.toggled_node != nil {
        reconcile_tree_topology(params, scroll, content_height)
    }
    active := tree_resolve_active_node(params)
    register_tree_semantics(params, scroll^, active)
    if hit.hovered_node != nil && input_frame_left_pressed(params.mouse_input) ||
        hit.selected_node != nil || hit.toggled_node != nil {
        _ = semantic_request_pointer_focus(
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
    if hovered != nil && input_frame_left_down(params.mouse_input) &&
        owner.active && owner.kind == .List_Item &&
        owner.id == tree_node_press_id(hovered) {
        return hovered
    }
    return nil
}

//   Resolve tree scrolling and row interaction before rendering.
prepare_tree_list_panel :: proc(params: Tree_List_Params) -> Tree_List_Preparation {
    _ = tree_apply_semantic_commands(params)
    total_rows := count_visible_tree_rows_all_roots(params.ji, params.visibility)
    if total_rows <= 0 {
        return {}
    }
    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    apply_pending_tree_reveal(params, content_h)
    scroll := scroll_container_update({id = UI_TREE_SCROLLBAR_ID,
        rect = params.list_panel, scroll_y_in = params.scroll_y^,
        content_height = content_h, mouse_input = params.mouse_input,
        interaction_space_rect = params.list_panel,
        wheel_step = TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &params.ui_runtime.ui_press_owner,
        state_in = {params.ui_runtime.tree_scroll_dragging,
            params.ui_runtime.tree_scroll_drag_off},
        semantic_focus = params.ui_runtime.semantic_focus,
        semantic_id = tree_semantic_id()})
    commit_tree_scroll(params, scroll)
    walk_ctx := Tree_Walk_Context{ji = params.ji, ui_runtime = params.ui_runtime,
        panel = scroll.view_rect, scroll_y = scroll.scroll_y_out,
        allow_clicks = !(scroll.pointer_reserved &&
            input_frame_left_pressed(params.mouse_input)),
        mouse_input = params.mouse_input,
        interaction_space_rect = scroll.view_rect,
        font = params.font, font_resolver = params.font_resolver,
        visibility = params.visibility}
    content_y: f32
    hit := walk_update_tree_roots(walk_ctx, &content_y)
    finish_tree_interaction(params, hit, &scroll, &content_h)
    return {scroll, content_h, hit.hovered_node, hit.hovered_expander_node,
        tree_pressed_node(params, hit.hovered_node)}
}
