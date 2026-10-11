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
import collectionmodel "../../../collections"
import log "core:log"

TREE_SEMANTIC_LOCAL_ID :: 1
TREE_NO_ITEM :: -1

Tree_Hit :: struct {
    selected_node: ^viewmodel.Ui_Tree_Item,
    toggled_node: ^viewmodel.Ui_Tree_Item,
    hovered_node: ^viewmodel.Ui_Tree_Item,
    hovered_expander_node: ^viewmodel.Ui_Tree_Item,
}

// Tree_Visibility_Policy supplies one coherent ordinary or search-filtered topology.
Tree_Visibility_Policy :: struct {
    search: ^viewmodel.Library_Search_State,
    projection: ^viewmodel.Ui_Tree_Projection,
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
    ji: ^bridgemodel.Euclid_Julia_Interface,
    policy: Tree_Visibility_Policy,
    tree_id: viewmodel.Ui_Node_Id,
    panel: geometry.Rectangle,
    scroll_y: f32,
    row: ^int,
    layout: ^Tree_Prepared_Layout,
}

// Prepared facts for publishing one tree item's semantics.
Tree_Item_Semantic_Publication :: struct {
    item: ^viewmodel.Ui_Tree_Item,
    label: string,
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

// Tree_Projection_Walk_Context keeps bounded searches within one topology.
Tree_Projection_Walk_Context :: struct {
    projection: ^viewmodel.Ui_Tree_Projection,
    policy: Tree_Visibility_Policy,
}

//   Prepared tree scrolling and bounded hover identities for observational drawing.
Tree_List_Preparation :: struct {
    scroll: uiwidgets.Scroll_Container_Update_Result,
    content_height: f32,
    hovered_node: ^viewmodel.Ui_Tree_Item,
    hovered_expander_node: ^viewmodel.Ui_Tree_Item,
    pressed_node: ^viewmodel.Ui_Tree_Item,
    layout: Tree_Prepared_Layout,
}

//   Inputs for one tree list panel frame, grouped so the call passes one value.
Tree_List_Params :: struct {
    label: string,
    ji : ^bridgemodel.Euclid_Julia_Interface,
    collections: ^collectionmodel.Set,
    collections_revision: u64,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    list_panel : geometry.Rectangle,
    mouse_input : input.Input_Frame,
    scroll_y : ^f32,
    font : view_font.Font_Face,
    font_resolver : view_font.Font_Resolver,
    visibility: Tree_Visibility_Policy,
}

// Immutable inputs shared by recursive tree row updates.
Tree_Walk_Context :: struct {
    ji: ^bridgemodel.Euclid_Julia_Interface,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    panel: geometry.Rectangle,
    scroll_y: f32,
    allow_clicks: bool,
    mouse_input: input.Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
    hovered_node: ^viewmodel.Ui_Tree_Item,
    hovered_expander_node: ^viewmodel.Ui_Tree_Item,
    visibility: Tree_Visibility_Policy,
}

// Encoded_Tree_Walk_Context groups shared geometry for tree drawing.
Encoded_Tree_Walk_Context :: struct {
    state: ^core.Euclid_General_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle,
    scroll_y: f32,
    content_y: ^f32,
    visibility: Tree_Visibility_Policy,
    pressed_node: ^viewmodel.Ui_Tree_Item,
    render_only: bool,
}

Tree_Projection_Add_Request :: struct {
    key, target_id: uuid.Identifier,
    kind: viewmodel.Ui_Tree_Item_Kind,
    parent: int,
    expanded, selectable: bool,
}

// Find one stable placement identity in the bounded display-owned topology.
tree_projection_find :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, key: uuid.Identifier) -> int {
    for index in 0..<projection^.count {
        if projection^.items[index].key == key {
            return index
        }
    }
    return TREE_NO_ITEM
}

// Link an initialized item into its parent or the ordered root list.
tree_projection_link :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, index, parent: int) {
    if parent == TREE_NO_ITEM {
        if projection^.first_root == TREE_NO_ITEM {
            projection^.first_root = index
        } else {
            projection^.items[projection^.last_root].next_sibling = index
        }
        projection^.last_root = index
        return
    }
    branch := &projection^.items[parent]
    if branch^.first_child == TREE_NO_ITEM {
        branch^.first_child = index
    } else {
        projection^.items[branch^.last_child].next_sibling = index
    }
    branch^.last_child = index
}

// Add one projection item while preserving its prior session expansion choice.
tree_projection_add :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    previous: ^viewmodel.Ui_Tree_Projection,
    request: Tree_Projection_Add_Request) -> int {
    if projection^.count >= len(projection^.items) ||
        request.key == (uuid.Identifier{}) ||
        tree_projection_find(projection, request.key) != TREE_NO_ITEM {
        return TREE_NO_ITEM
    }
    if request.parent != TREE_NO_ITEM &&
        (request.parent < 0 || request.parent >= projection^.count) {
        return TREE_NO_ITEM
    }
    retained_expanded := request.expanded
    retained := tree_projection_find(previous, request.key)
    if retained != TREE_NO_ITEM {
        retained_expanded = previous^.items[retained].expanded
    }
    index := projection^.count
    projection^.items[index] = {
        key = request.key, target_animation_id = request.target_id,
        kind = request.kind, parent = request.parent,
        first_child = TREE_NO_ITEM,
        last_child = TREE_NO_ITEM, next_sibling = TREE_NO_ITEM,
        expanded = retained_expanded, selectable = request.selectable,
    }
    projection^.count += 1
    tree_projection_link(projection, index, request.parent)
    return index
}

// Add the visible Favorites collection hierarchy when it has durable entries.
tree_projection_add_favorites :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    previous: ^viewmodel.Ui_Tree_Projection,
    snapshot: ^collectionmodel.Set) -> bool {
    if snapshot == nil || snapshot^.entry_count == 0 {
        return true
    }
    collections_index := tree_projection_add(projection, previous, {
        key = viewmodel.TREE_COLLECTIONS_ROOT_ID,
        kind = .Collections, parent = TREE_NO_ITEM, selectable = true,
        expanded = previous^.collections_expanded,
    })
    favorites_index := tree_projection_add(projection, previous, {
        key = collectionmodel.FAVORITES_COLLECTION_ID,
        kind = .Collection, parent = collections_index, selectable = true,
        expanded = previous^.favorites_expanded,
    })
    if collections_index == TREE_NO_ITEM || favorites_index == TREE_NO_ITEM {
        return false
    }
    for entry in snapshot^.entries[:snapshot^.entry_count] {
        if entry.collection_id != collectionmodel.FAVORITES_COLLECTION_ID {
            continue
        }
        if tree_projection_add(projection, previous, {
            key = entry.id, target_id = entry.animation_id,
            kind = .Placement, parent = favorites_index, selectable = true,
        }) == TREE_NO_ITEM {
            return false
        }
    }
    return true
}

// Prepare the next display-owned projection before publishing any changed state.
tree_projection_prepare :: proc(params: Tree_List_Params) -> bool {
    if params.ji == nil || params.ui_runtime == nil ||
        (params.collections != nil &&
            collectionmodel.validate(params.collections) != .None) {
        return false
    }
    runtime := params.ui_runtime
    old := &runtime^.tree_projection
    if old^.valid && old^.content_generation == params.ji^.content_generation &&
        old^.collections_revision == params.collections_revision {
        return true
    }
    staged := tree_projection_begin(params, old)
    has_terminal: bool
    if !tree_projection_registry_info(params.ji, &has_terminal) ||
        !tree_projection_add_registry(params, old, &staged, has_terminal) {
        return false
    }
    staged.valid = true
    tree_projection_repair_selection(runtime, &staged)
    runtime^.tree_projection = staged
    return true
}

// Initialize staged metadata without carrying old item storage forward.
tree_projection_begin :: proc(
    params: Tree_List_Params,
    old: ^viewmodel.Ui_Tree_Projection) -> viewmodel.Ui_Tree_Projection {
    staged: viewmodel.Ui_Tree_Projection
    staged.first_root = TREE_NO_ITEM
    staged.last_root = TREE_NO_ITEM
    staged.content_generation = params.ji^.content_generation
    staged.collections_revision = params.collections_revision
    staged.topology_revision = old^.topology_revision + 1
    staged.collections_expanded = old^.collections_expanded
    staged.favorites_expanded = old^.favorites_expanded
    root := tree_projection_find(old, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := tree_projection_find(old, collectionmodel.FAVORITES_COLLECTION_ID)
    if root != TREE_NO_ITEM {
        staged.collections_expanded = old^.items[root].expanded
    }
    if favorites != TREE_NO_ITEM {
        staged.favorites_expanded = old^.items[favorites].expanded
    }
    return staged
}

// Validate the registry bound and report whether Collections follows Terminal.
tree_projection_registry_info :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface, has_terminal: ^bool) -> bool {
    registry_count := 0
    for node, steps := ji^.animation_head, 0;
        node != nil && steps < ji^.animation_count;
        node, steps = node^.next_in_registry, steps + 1 {
        has_terminal^ = has_terminal^ || node^.node_kind == .Terminal
        registry_count += 1
    }
    return registry_count == ji^.animation_count
}

// Append canonical nodes and insert Favorites at the approved tree boundary.
tree_projection_add_registry :: proc(
    params: Tree_List_Params,
    previous: ^viewmodel.Ui_Tree_Projection,
    staged: ^viewmodel.Ui_Tree_Projection,
    has_terminal: bool) -> bool {
    if !has_terminal &&
        !tree_projection_add_favorites(staged, previous, params.collections) {
        return false
    }
    collections_added := !has_terminal
    for node, steps := params.ji^.animation_head, 0;
        node != nil && steps < params.ji^.animation_count;
        node, steps = node^.next_in_registry, steps + 1 {
        if !tree_projection_add_animation(staged, previous, node) {
            return false
        }
        if node^.node_kind == .Terminal && !collections_added {
            if !tree_projection_add_favorites(
                staged, previous, params.collections) {
                return false
            }
            collections_added = true
        }
    }
    return true
}

// Append one canonical animation while retaining its previous display expansion.
tree_projection_add_animation :: proc(
    staged, previous: ^viewmodel.Ui_Tree_Projection,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    parent := TREE_NO_ITEM
    if node^.parent != nil {
        parent = tree_projection_find(staged, node^.parent^.stable_id)
        if parent == TREE_NO_ITEM {
            return false
        }
    }
    expanded := node^.is_expanded
    if prior := tree_projection_find(previous, node^.stable_id); prior != TREE_NO_ITEM {
        expanded = previous^.items[prior].expanded
    }
    return tree_projection_add(staged, previous, {
        key = node^.stable_id, target_id = node^.stable_id,
        kind = .Animation, parent = parent, expanded = expanded,
        selectable = true,
    }) != TREE_NO_ITEM
}

// Clear display identities whose items no longer exist in the staged topology.
tree_projection_repair_selection :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    staged: ^viewmodel.Ui_Tree_Projection) {
    selected_key := runtime^.selected_tree_item_id
    if selected_key != (uuid.Identifier{}) &&
        tree_projection_find(staged, selected_key) == TREE_NO_ITEM {
        runtime^.selected_tree_item_id = {}
    }
    if runtime^.semantic_focus != nil &&
        runtime^.semantic_focus^.active_tree_item != (uuid.Identifier{}) &&
        tree_projection_find(staged,
            runtime^.semantic_focus^.active_tree_item) == TREE_NO_ITEM {
        runtime^.semantic_focus^.active_tree_item = {}
        runtime^.tree_reveal_pending = false
    }
    if runtime^.tree_reveal_pending &&
        tree_projection_find(staged, runtime^.tree_reveal_stable_id) == TREE_NO_ITEM {
        runtime^.tree_reveal_pending = false
    }
}

// tree_item_is_visible applies the same search policy to layout and interaction.
tree_item_is_visible :: proc(
    policy: Tree_Visibility_Policy,
    item: viewmodel.Ui_Tree_Item) -> bool {
    if item.kind != .Animation {
        return policy.search == nil || !policy.search^.active
    }
    if item.target_animation_id == (uuid.Identifier{}) {
        return false
    }
    if policy.search == nil || !policy.search^.active {
        return true
    }
    for index in 0..<policy.search^.visible_id_count {
        if policy.search^.visible_ids[index] == item.target_animation_id {
            return true
        }
    }
    return false
}

// tree_item_is_effectively_expanded derives required search paths without mutation.
tree_item_is_effectively_expanded :: proc(
    policy: Tree_Visibility_Policy,
    item: viewmodel.Ui_Tree_Item) -> bool {
    if item.first_child == TREE_NO_ITEM {
        return false
    }
    if item.expanded {
        return true
    }
    if policy.search == nil || !policy.search^.active || policy.projection == nil {
        return false
    }
    for child, steps := item.first_child, 0;
        child != TREE_NO_ITEM && steps < policy.projection^.count;
        child, steps = policy.projection^.items[child].next_sibling, steps + 1 {
        if tree_item_is_visible(policy, policy.projection^.items[child]) {
            return true
        }
    }
    return false
}

// expanded_first_child returns only logically expanded children, never closing visual tails.
tree_item_first_child :: proc(
    item: viewmodel.Ui_Tree_Item,
    policy: Tree_Visibility_Policy = {}) -> int {
    if !tree_item_is_effectively_expanded(policy, item) {
        return TREE_NO_ITEM
    }
    return item.first_child
}

// Keep canonical search helpers for existing library-specific queries.
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

// Preserve the canonical branch expansion query for search and legacy tests.
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

// Return canonical children only when their parent is logically expanded.
expanded_first_child :: proc(
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    policy: Tree_Visibility_Policy = {}) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {
    if !tree_node_is_effectively_expanded(policy, node) {
        return nil
    }
    return node^.first_child
}

// tree_semantic_id identifies the Library tree independently of its rows.
tree_semantic_id :: #force_inline proc() -> viewmodel.Ui_Node_Id {
    return uisemantics.semantic_control_id(.Animation_Tree, TREE_SEMANTIC_LOCAL_ID)
}

// tree_item_semantic_id identifies one placement by its stable item key.
tree_placement_semantic_id :: #force_inline proc(
    item: ^viewmodel.Ui_Tree_Item) -> viewmodel.Ui_Node_Id {
    if item == nil {
        return {}
    }
    return {domain = .Animation_Tree, stable_id = item^.key}
}

// tree_item_semantic_id preserves canonical animation identity for existing callers.
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
    for node, steps := ji^.animation_head, 0;
        node != nil && steps < ji^.animation_count;
        node, steps = node^.next_in_registry, steps + 1 {
        if node^.stable_id == stable_id {
            return node
        }
    }
    return nil
}

// tree_item_label resolves a frame-borrowed label without storing content pointers.
tree_item_label :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    item: ^viewmodel.Ui_Tree_Item) -> string {
    if item == nil {
        return ""
    }
    switch item^.kind {
    case .Collections: return "Collections"
    case .Collection: return "Favorites"
    case .Placement:
        target := tree_find_stable_id(ji, item^.target_animation_id)
        return target^.name if target != nil else "Unavailable animation"
    case .Animation:
        target := tree_find_stable_id(ji, item^.target_animation_id)
        return target^.name if target != nil else ""
    }
    return ""
}

// tree_item_is_keyboard_active reports visible focus for one roving descendant.
tree_placement_is_keyboard_active :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    item: ^viewmodel.Ui_Tree_Item) -> bool {
    if runtime == nil || item == nil || runtime^.semantic_focus == nil {
        return false
    }
    semantic := runtime^.semantic_focus
    return semantic^.window_focused && semantic^.focus_origin == .Keyboard &&
        semantic^.logical_focus == tree_semantic_id() &&
        semantic^.active_tree_item == item^.key
}

// tree_item_is_keyboard_active preserves the canonical-item focus query contract.
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
    item: ^viewmodel.Ui_Tree_Item,
    depth: int, row_y: f32, expanded: bool = false) {
    row := geometry.Rectangle{
        ctx.panel.x, row_y, ctx.panel.width, theme.TREE_ROW_HEIGHT}
    if row.y + row.height >= ctx.panel.y &&
        row.y <= ctx.panel.y + ctx.panel.height {
        if ctx.state^.ui_runtime.selected_tree_item_id == item^.key {
            _ = native.draw_encoder_rectangle(
                ctx.encoder, geometry.Rectangle(row), theme.UI_BORDER_COLOR)
        }
        if item == ctx.pressed_node {
            highlight := theme.UI_TEXT_COLOR
            highlight.a = 24
            _ = native.draw_encoder_rectangle(ctx.encoder, row, highlight)
        }
        if !ctx.render_only &&
           tree_placement_is_keyboard_active(&ctx.state^.ui_runtime, item) {
            _ = native.draw_encoder_rectangle_outline(
                ctx.encoder, geometry.Rectangle(row), 2, theme.UI_TEXT_COLOR)
        }
        if item^.first_child != TREE_NO_ITEM {
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


// Build a frame-local capture id for one retained projection slot.
tree_placement_press_id :: #force_inline proc(
    item: ^viewmodel.Ui_Tree_Item) -> int {

    if item == nil {
        return -1
    }

    return int(uintptr(item) & uintptr(0x7fffffff))
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

// tree_resolve_active_node restores a visible UUID or chooses selected then first.
// tree_projection_visible_row resolves the logical preorder position of one item.
tree_projection_visible_row :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    target: ^viewmodel.Ui_Tree_Item,
    policy_input: Tree_Visibility_Policy) -> (int, bool) {
    if projection == nil || target == nil {
        return 0, false
    }
    policy := policy_input
    policy.projection = projection
    ctx := Tree_Projection_Walk_Context{projection, policy}
    row: int
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        if found_row, found := tree_projection_visible_row_limited(
            ctx, root, target, &row, projection^.count); found {
            return found_row, true
        }
    }
    return 0, false
}

// Walk one visible subtree while respecting caller expansion and search policy.
tree_projection_visible_row_limited :: proc(
    ctx: Tree_Projection_Walk_Context,
    index: int,
    target: ^viewmodel.Ui_Tree_Item,
    row: ^int,
    remaining: int) -> (int, bool) {
    projection := ctx.projection
    if index < 0 || index >= projection^.count || remaining <= 0 {
        return 0, false
    }
    item := &projection^.items[index]
    if !tree_item_is_visible(ctx.policy, item^) {
        return 0, false
    }
    current := row^
    row^ += 1
    if item == target {
        return current, true
    }
    if !tree_item_is_effectively_expanded(ctx.policy, item^) {
        return 0, false
    }
    for child, steps := item^.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        if found, ok := tree_projection_visible_row_limited(
            ctx, child, target, row, remaining - 1); ok {
            return found, true
        }
    }
    return 0, false
}

// tree_projection_item_at_row resolves a row in the shared visible preorder.
tree_projection_item_at_row :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    target_row: int,
    policy_input: Tree_Visibility_Policy) -> ^viewmodel.Ui_Tree_Item {
    if projection == nil || target_row < 0 {
        return nil
    }
    policy := policy_input
    policy.projection = projection
    ctx := Tree_Projection_Walk_Context{projection, policy}
    row: int
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        item := tree_projection_item_at_row_limited(
            ctx, root, target_row, &row, projection^.count)
        if item != nil {
            return item
        }
    }
    return nil
}

// Resolve one preorder position without exposing topology storage to navigation.
tree_projection_item_at_row_limited :: proc(
    ctx: Tree_Projection_Walk_Context,
    index, target_row: int,
    row: ^int,
    remaining: int) -> ^viewmodel.Ui_Tree_Item {
    projection := ctx.projection
    if index < 0 || index >= projection^.count || remaining <= 0 {
        return nil
    }
    item := &projection^.items[index]
    if !tree_item_is_visible(ctx.policy, item^) {
        return nil
    }
    if row^ == target_row {
        return item
    }
    row^ += 1
    if !tree_item_is_effectively_expanded(ctx.policy, item^) {
        return nil
    }
    for child, steps := item^.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        found := tree_projection_item_at_row_limited(
            ctx, child, target_row, row, remaining - 1)
        if found != nil {
            return found
        }
    }
    return nil
}

// Count all visible rows using the caller-owned expansion state.
tree_projection_visible_count :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    policy_input: Tree_Visibility_Policy) -> int {
    count: int
    if projection == nil {
        return count
    }
    policy := policy_input
    policy.projection = projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        count += tree_projection_visible_count_limited(
            projection, root, policy, projection^.count)
    }
    return count
}

// Count one visible subtree without exceeding the admitted topology bound.
tree_projection_visible_count_limited :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    index: int,
    policy: Tree_Visibility_Policy,
    remaining: int) -> int {
    if index < 0 || index >= projection^.count || remaining <= 0 {
        return 0
    }
    item := projection^.items[index]
    if !tree_item_is_visible(policy, item) {
        return 0
    }
    count := 1
    if !tree_item_is_effectively_expanded(policy, item) {
        return count
    }
    for child, steps := item.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        count += tree_projection_visible_count_limited(
            projection, child, policy, remaining - 1)
    }
    return count
}

// Restore active placement, then selected placement, then the first visible item.
tree_resolve_active_node :: proc(params: Tree_List_Params) -> ^viewmodel.Ui_Tree_Item {
    projection := &params.ui_runtime^.tree_projection
    active_key := uuid.Identifier{}
    if params.ui_runtime^.semantic_focus != nil {
        active_key = params.ui_runtime^.semantic_focus^.active_tree_item
    }
    active_index := tree_projection_find(projection, active_key)
    if active_index != TREE_NO_ITEM {
        active := &projection^.items[active_index]
        if _, visible := tree_projection_visible_row(
            projection, active, params.visibility); visible {
            return active
        }
    }
    selected_index := tree_projection_find(
        projection, params.ui_runtime^.selected_tree_item_id)
    if selected_index != TREE_NO_ITEM {
        selected := &projection^.items[selected_index]
        if _, visible := tree_projection_visible_row(
            projection, selected, params.visibility); visible {
            return selected
        }
    }
    return tree_projection_item_at_row(projection, 0, params.visibility)
}

// Commit roving placement identity and optional reveal intent.
tree_set_active_item :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    item: ^viewmodel.Ui_Tree_Item,
    reveal: bool) {
    if runtime == nil || runtime^.semantic_focus == nil || item == nil {
        return
    }
    runtime^.semantic_focus^.active_tree_item = item^.key
    if reveal {
        runtime^.tree_reveal_stable_id = item^.key
        runtime^.tree_reveal_pending = true
        runtime^.tree_reveal_reason = .Navigation
    }
}

// tree_set_active_node preserves canonical animation focus callers.
tree_set_active_node :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    reveal: bool) {
    if runtime == nil || node == nil || runtime^.semantic_focus == nil {
        return
    }
    runtime^.semantic_focus^.active_tree_item = node^.stable_id
    if reveal {
        runtime^.tree_reveal_stable_id = node^.stable_id
        runtime^.tree_reveal_pending = true
        runtime^.tree_reveal_reason = .Navigation
    }
}

// Resolve one tree navigation command against the combined projection.
tree_semantic_navigation_target :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item,
    kind: viewmodel.Ui_Focus_Command_Kind) -> ^viewmodel.Ui_Tree_Item {
    row, _ := tree_projection_visible_row(
        &params.ui_runtime^.tree_projection, active, params.visibility)
    count := tree_projection_visible_count(
        &params.ui_runtime^.tree_projection, params.visibility)
    #partial switch kind {
    case .Tree_Previous:
        return tree_projection_item_at_row(
            &params.ui_runtime^.tree_projection, max(row - 1, 0), params.visibility)
    case .Tree_Next:
        return tree_projection_item_at_row(
            &params.ui_runtime^.tree_projection, min(row + 1, count - 1),
            params.visibility)
    case .Tree_First:
        return tree_projection_item_at_row(
            &params.ui_runtime^.tree_projection, 0, params.visibility)
    case .Tree_Last:
        return tree_projection_item_at_row(
            &params.ui_runtime^.tree_projection, count - 1, params.visibility)
    case:
    }
    return active
}

// Apply parent navigation or collapse to one placement.
tree_apply_parent_command :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item) -> ^viewmodel.Ui_Tree_Item {
    if active^.first_child != TREE_NO_ITEM && active^.expanded {
        active^.expanded = false
    } else if active^.parent != TREE_NO_ITEM {
        return &params.ui_runtime^.tree_projection.items[active^.parent]
    }
    return active
}

// Apply child navigation or expansion through the shared projection.
tree_apply_child_command :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item) -> ^viewmodel.Ui_Tree_Item {
    policy := params.visibility
    policy.projection = &params.ui_runtime^.tree_projection
    if active^.first_child != TREE_NO_ITEM && !active^.expanded {
        active^.expanded = true
        return active
    }
    for child, steps := active^.first_child, 0;
        child != TREE_NO_ITEM && steps < policy.projection^.count;
        child, steps = policy.projection^.items[child].next_sibling, steps + 1 {
        candidate := &policy.projection^.items[child]
        if tree_item_is_visible(policy, candidate^) {
            return candidate
        }
    }
    return active
}

// Apply expansion intents to any structural or animation placement.
tree_apply_structure_command :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item,
    kind: viewmodel.Ui_Focus_Command_Kind) -> ^viewmodel.Ui_Tree_Item {
    tree_motion_anchor_action(params, active, kind)
    #partial switch kind {
    case .Tree_Parent: return tree_apply_parent_command(params, active)
    case .Tree_Child: return tree_apply_child_command(params, active)
    case .Toggle:
        active^.expanded = !active^.expanded
    case .Expand:
        active^.expanded = true
    case .Collapse:
        active^.expanded = false
    case:
    }
    return active
}

// Select one placement while resolving playback only through its canonical target.
tree_select_item :: proc(params: Tree_List_Params, item: ^viewmodel.Ui_Tree_Item) {
    params.ui_runtime^.selected_tree_item_id = item^.key
    target := tree_find_stable_id(params.ji, item^.target_animation_id)
    if target != nil {
        set_selected_animation(params.ji, target)
        params.ui_runtime^.view_text_scroll_y = 0
    }
}

// Apply one addressed command without conflating placement selection and playback.
tree_apply_semantic_command :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item,
    command: viewmodel.Ui_Focus_Command) -> ^viewmodel.Ui_Tree_Item {
    if active == nil || command.kind == .Scroll_Page ||
        command.kind == .Set_Scroll_Value {
        return active
    }
    target := tree_semantic_navigation_target(params, active, command.kind)
    target = tree_apply_structure_command(params, target, command.kind)
    if command.kind == .Select && active^.selectable {
        tree_select_item(params, active)
    }
    if target != nil {
        tree_set_active_item(params.ui_runtime, target, true)
    }
    return target
}

// Resolve semantic item IDs against the current combined projection.
tree_semantic_command_target :: proc(
    params: Tree_List_Params,
    active: ^viewmodel.Ui_Tree_Item,
    target: viewmodel.Ui_Node_Id) -> ^viewmodel.Ui_Tree_Item {
    if target == tree_semantic_id() {
        return active
    }
    if target.domain != .Animation_Tree {
        return nil
    }
    index := tree_projection_find(
        &params.ui_runtime^.tree_projection, target.stable_id)
    if index == TREE_NO_ITEM {
        return nil
    }
    item := &params.ui_runtime^.tree_projection.items[index]
    _, visible := tree_projection_visible_row(
        &params.ui_runtime^.tree_projection, item, params.visibility)
    return item if visible else nil
}

// Consume current semantic commands against the combined row hierarchy.
tree_apply_semantic_commands :: proc(params: Tree_List_Params) ->
    ^viewmodel.Ui_Tree_Item {
    active := tree_resolve_active_node(params)
    semantic := params.ui_runtime^.semantic_focus
    if semantic == nil {
        return active
    }
    for command in semantic^.commands[:semantic^.command_count] {
        target := tree_semantic_command_target(params, active, command.target)
        if target != nil {
            active = tree_apply_semantic_command(params, target, command)
        }
    }
    if active != nil {
        tree_set_active_item(params.ui_runtime, active, false)
    }
    return active
}

// register_tree_item_semantics publishes one visible branch without allocation.
tree_item_set_facts :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    policy_input: Tree_Visibility_Policy,
    item: ^viewmodel.Ui_Tree_Item) -> (u16, u16) {
    if projection == nil || item == nil {
        return 0, 0
    }
    policy := policy_input
    policy.projection = projection
    position, size: u16
    for candidate_index in 0..<projection^.count {
        candidate := &projection^.items[candidate_index]
        if candidate^.parent != item^.parent ||
            !tree_item_is_visible(policy, candidate^) {
            continue
        }
        size += 1
        if candidate == item {
            position = size
        }
    }
    return position, size
}

// Publish one visible tree node using its computed parent, state, and geometry.
tree_publish_item_semantics :: proc(
    ctx: Tree_Semantic_Context, publication: Tree_Item_Semantic_Publication) {
    row := tree_layout_find_item(ctx.layout, publication.item)
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
        clip_bounds = geometry.clip_bounds, label = publication.label,
        level = u16(publication.depth + 1),
        position_in_set = publication.position, set_size = publication.size,
    })
}

// Recursively publish the visible children of one expanded semantic node.
tree_publish_semantic_children :: proc(
    ctx: Tree_Semantic_Context,
    projection: ^viewmodel.Ui_Tree_Projection,
    item: ^viewmodel.Ui_Tree_Item,
    depth, remaining: int) {
    policy := ctx.policy
    policy.projection = projection
    for child, steps := tree_item_first_child(item^, policy), 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        register_tree_item_semantics(
            ctx, projection, &projection^.items[child], depth + 1, remaining - 1)
    }
}

// Prepare the semantic states and sibling position for one visible item.
tree_item_semantic_publication :: proc(
    ctx: Tree_Semantic_Context,
    projection: ^viewmodel.Ui_Tree_Projection,
    item: ^viewmodel.Ui_Tree_Item,
    depth: int,
    policy: Tree_Visibility_Policy) -> Tree_Item_Semantic_Publication {
    item_id := tree_placement_semantic_id(item)
    states := viewmodel.Ui_Node_State{.Visible, .Focusable}
    if item^.selectable || item^.first_child != TREE_NO_ITEM {
        states += {.Enabled}
    }
    if ctx.runtime^.selected_tree_item_id == item^.key {
        states += {.Selected}
    }
    if tree_item_is_effectively_expanded(policy, item^) {
        states += {.Expanded}
    }
    actions := viewmodel.Ui_Node_Action_Set{.Focus}
    if item^.selectable {
        actions += {.Select}
    }
    if item^.first_child != TREE_NO_ITEM {
        actions += {.Expand, .Collapse, .Toggle}
    }
    parent_id := ctx.tree_id
    if item^.parent != TREE_NO_ITEM {
        parent_id = tree_placement_semantic_id(&projection^.items[item^.parent])
    }
    position, size := tree_item_set_facts(projection, policy, item)
    return {
        item = item, label = tree_item_label(ctx.ji, item),
        depth = depth, item_id = item_id, parent_id = parent_id,
        states = states, actions = actions, position = position, size = size,
    }
}

// register_tree_item_semantics publishes one visible branch without allocation.
register_tree_item_semantics :: proc(
    ctx: Tree_Semantic_Context,
    projection: ^viewmodel.Ui_Tree_Projection,
    item: ^viewmodel.Ui_Tree_Item,
    depth, remaining: int) {
    policy := ctx.policy
    policy.projection = projection
    if item == nil || remaining <= 0 || !tree_item_is_visible(policy, item^) {
        return
    }
    publication := tree_item_semantic_publication(
        ctx, projection, item, depth, policy)
    tree_publish_item_semantics(ctx, publication)
    ctx.row^ += 1
    tree_publish_semantic_children(ctx, projection, item, depth, remaining)
}

// register_tree_semantics publishes one Tab stop and its visible descendants.
register_tree_semantics :: proc(
    params: Tree_List_Params,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    active: ^viewmodel.Ui_Tree_Item,
    layout: ^Tree_Prepared_Layout) {
    tree_id := tree_semantic_id()
    active_id := tree_placement_semantic_id(active)
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
    ctx := Tree_Semantic_Context{params.ui_runtime, params.ji, params.visibility,
        tree_id, panel, scroll.scroll_y_out, &row, layout}
    projection := &params.ui_runtime^.tree_projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        register_tree_item_semantics(
            ctx, projection, &projection^.items[root], 0, projection^.count)
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

// Expand only the ancestors needed to make one stable target row visible.
tree_expand_reveal_ancestors :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, target_index: int) {
    if target_index == TREE_NO_ITEM {
        return
    }
    parent := projection^.items[target_index].parent
    for steps := 0; parent != TREE_NO_ITEM && steps < projection^.count;
        steps += 1 {
        projection^.items[parent].expanded = true
        parent = projection^.items[parent].parent
    }
}

//   Resolve and consume one stable tree reveal request when its row is visible.
apply_pending_tree_reveal :: proc(
    params: Tree_List_Params,
    content_height: f32) {

    ui_runtime := params.ui_runtime
    if ui_runtime == nil || !ui_runtime^.tree_reveal_pending {
        return
    }
    if !tree_projection_prepare(params) {
        log.error("library_tree_projection_rejected")
        return
    }
    projection := &ui_runtime^.tree_projection
    target_index := tree_projection_find(
        projection, ui_runtime^.tree_reveal_stable_id)
    tree_expand_reveal_ancestors(projection, target_index)
    target := &projection^.items[target_index] if
        target_index != TREE_NO_ITEM else nil
    row, found := tree_projection_visible_row(
        projection, target, params.visibility)
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
        hit.toggled_node.expanded = !hit.toggled_node.expanded
        tree_set_active_item(ui_runtime, hit.toggled_node, false)
    }
    if hit.selected_node != nil {
        ui_runtime^.selected_tree_item_id = hit.selected_node^.key
        target := tree_find_stable_id(ji, hit.selected_node^.target_animation_id)
        if target != nil {
            set_selected_animation(ji, target)
            ui_runtime^.view_text_scroll_y = 0
            ui_runtime^.text_scroll_dragging = false
            ui_runtime^.text_scroll_drag_off = 0
        }
        tree_set_active_item(ui_runtime, hit.selected_node, false)
    }
}

//   Resolve one node expander and record its hover and toggle identities.
update_tree_node_expander_hit :: proc(
    ctx: Tree_Walk_Context,
    node: ^viewmodel.Ui_Tree_Item,
    icon_rect: geometry.Rectangle,
    toggle_triggered: bool,
    hit: ^Tree_Hit) {

    if node^.first_child == TREE_NO_ITEM {
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
    node: ^viewmodel.Ui_Tree_Item,
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
        id = tree_placement_press_id(node),
        rect = geometry.Rectangle(row_rect),
        can_expand_pos_y = false,
        selected = ctx.ui_runtime.selected_tree_item_id == node^.key,
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
tree_pressed_item :: proc(
    params: Tree_List_Params,
    hovered: ^viewmodel.Ui_Tree_Item) -> ^viewmodel.Ui_Tree_Item {
    owner := params.ui_runtime^.ui_press_owner
    if hovered != nil && uiwidgets.input_frame_left_down(params.mouse_input) &&
        owner.active && owner.kind == .List_Item &&
        owner.id == tree_placement_press_id(hovered) {
        return hovered
    }
    return nil
}

//   Resolve tree scrolling and row interaction before rendering.
prepare_tree_list_panel :: proc(params: Tree_List_Params) -> Tree_List_Preparation {
    if params.ji == nil ||
        params.ji^.animation_count == 0 &&
            (params.collections == nil || params.collections^.entry_count == 0) {
        params.ui_runtime^.tree_motion = {}
        return {}
    }
    if !tree_projection_prepare(params) {
        log.error("library_tree_projection_rejected")
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
    prepared.pressed_node = tree_pressed_item(params, hit.hovered_node)
    return prepared
}
