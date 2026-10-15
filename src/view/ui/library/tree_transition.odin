package uilibrary

import uilayout "../layout"
import collections "../../../collections"
import bridgemodel "../../../bridge/model"
import contentmodel "../../../core/content"
import geometry "../../../core/geometry"
import viewmodel "../model"
import theme "../theme"
import uiaccordion "../layout/accordion"
import uiwidgets "../widgets"
import uuid "core:encoding/uuid"

#assert(viewmodel.UI_TREE_NODE_CAPACITY >= contentmodel.CATALOG_RECORD_CAPACITY)

// Tree_Prepared_Row borrows projection and animation data only for this frame.
Tree_Prepared_Row :: struct {
    item: ^viewmodel.Ui_Tree_Item,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: f32,
    canonical_y: f32,
    reveal: geometry.Rectangle,
    logical: bool,
    expanded: bool,
    actions: Tree_Actions_Layout,
    actions_toggle: uiwidgets.Icon_Button_Result,
    actions_up: uiwidgets.Text_Button_Result,
    actions_down: uiwidgets.Text_Button_Result,
}

// Tree_Prepared_Layout bounds all rows, including visual-only closing descendants.
Tree_Prepared_Layout :: struct {
    rows: [viewmodel.UI_TREE_NODE_CAPACITY]Tree_Prepared_Row,
    count: int,
    content_height: f32,
}

// Tree_Motion_Admission snapshots facts that can invalidate retained branch motion.
Tree_Motion_Admission :: struct {
    generation: u64,
    topology_revision: u64,
    query_revision: u64,
    search_generation: u64,
    search_active: bool,
    count: int,
    panel: geometry.Rectangle,
    reduce_motion: bool,
    programmatic_reveal: bool,
}

// Tree_Geometry_Context borrows only the bounded state used by tree layout.
Tree_Geometry_Context :: struct {
    ji: ^bridgemodel.Euclid_Julia_Interface,
    projection: ^viewmodel.Ui_Tree_Projection,
    motion: ^viewmodel.Ui_Tree_Motion,
    drawer: ^viewmodel.Ui_Tree_Actions_Motion,
    collections: ^collections.Set,
    selected_item_id: uuid.Identifier,
    search_active: bool,
    visibility: Tree_Visibility_Policy,
    panel: geometry.Rectangle,
    now_seconds: f64,
    reduce_motion: bool,
}

// Tree_Frame_Context composes coordinator facts once at the panel boundary.
Tree_Frame_Context :: struct {
    geometry: Tree_Geometry_Context,
    admission: Tree_Motion_Admission,
}

// Tree_Layout_Context shares one bounded output and retained motion for a DFS.
Tree_Layout_Context :: struct {
    geometry: Tree_Geometry_Context,
    layout: ^Tree_Prepared_Layout,
}

// tree_motion_index resolves one retained identity without generation-owned pointers.
tree_motion_index :: proc(
    motion: ^viewmodel.Ui_Tree_Motion,
    key: uuid.Identifier) -> int {
    for index in 0..<motion^.count {
        if motion^.branches[index].stable_id == key {
            return index
        }
    }
    return -1
}

// tree_motion_needs_reset rejects incompatible retained geometry and motion policy.
tree_motion_needs_reset :: proc(
    motion: ^viewmodel.Ui_Tree_Motion,
    current: Tree_Motion_Admission) -> bool {
    return !motion^.initialized || motion^.generation != current.generation ||
        motion^.panel != current.panel || motion^.count != current.count ||
        motion^.topology_revision != current.topology_revision ||
        motion^.query_revision != current.query_revision ||
        motion^.search_generation != current.search_generation ||
        motion^.search_active != current.search_active || current.reduce_motion ||
        current.programmatic_reveal
}

// tree_motion_reset initializes every admitted identity and snaps logical topology.
tree_motion_reset :: proc(
    ctx: Tree_Geometry_Context,
    admission: Tree_Motion_Admission) {
    motion := ctx.motion
    motion^ = {
        initialized = true,
        generation = admission.generation,
        topology_revision = admission.topology_revision,
        query_revision = admission.query_revision,
        search_generation = admission.search_generation,
        search_active = admission.search_active,
        panel = admission.panel,
    }
    projection := ctx.projection
    policy := ctx.visibility
    policy.projection = ctx.projection
    for index in 0..<projection^.count {
        item := projection^.items[index]
        assert(motion^.count < len(motion^.branches),
            "admitted tree exceeds catalogue capacity")
        motion^.branches[motion^.count] = {
            stable_id = item.key,
            expanded = tree_item_is_effectively_expanded(policy, item)}
        motion^.count += 1
    }
}

// tree_motion_sample_branch follows changing child extents without extending its deadline.
tree_motion_sample_branch :: proc(
    branch: ^viewmodel.Ui_Tree_Branch_Motion, full_height: f32, now: f64) {
    branch^.full_height = full_height
    target := full_height if branch^.expanded else 0
    if !branch^.running {
        branch^.height = target
        return
    }
    ease := uiaccordion.interface_motion_ease(branch^.start_seconds, now)
    branch^.height = clamp(branch^.start_height +
        (target - branch^.start_height) * ease, 0, full_height)
    if now >= branch^.start_seconds + uiaccordion.INTERFACE_TRANSITION_SECONDS {
        branch^.height = target
        branch^.running = false
    }
}

// tree_motion_measure computes current nested extents bottom-up within the catalogue bound.
tree_motion_measure :: proc(
    ctx: Tree_Geometry_Context,
    item_index, remaining: int) -> f32 {
    projection := ctx.projection
    if item_index < 0 || remaining <= 0 || item_index >= projection^.count {
        return 0
    }
    item := projection^.items[item_index]
    if !tree_item_is_visible(ctx.visibility, item) {
        return 0
    }
    full_height: f32
    for child, steps := item.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        full_height += tree_motion_measure(ctx, child, remaining - 1)
    }
    motion_index := tree_motion_index(ctx.motion, item.key)
    assert(motion_index >= 0, "tree identity absent from admitted motion registry")
    branch := &ctx.motion^.branches[motion_index]
    tree_motion_sample_branch(branch, full_height, ctx.now_seconds)
    actions_height := tree_actions_sample(ctx, &item)
    return theme.TREE_ROW_HEIGHT + actions_height + branch^.height
}

// tree_motion_measure_roots samples even hidden branches so their deadlines still finish.
tree_motion_measure_roots :: proc(ctx: Tree_Geometry_Context) -> f32 {
    height: f32
    projection := ctx.projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        height += tree_motion_measure(ctx, root, projection^.count)
    }
    return height
}

// tree_motion_item_extent combines row, attached actions, and descendant reveal.
tree_motion_item_extent :: proc(
    ctx: Tree_Geometry_Context, item: ^viewmodel.Ui_Tree_Item) -> f32 {
    index := tree_motion_index(ctx.motion, item^.key)
    return theme.TREE_ROW_HEIGHT +
        tree_actions_current_height(ctx.drawer, item^.key) +
        ctx.motion^.branches[index].height
}

// tree_motion_admit retargets changed explicit topology from the last sampled geometry.
tree_motion_admit :: proc(ctx: Tree_Geometry_Context) {
    motion := ctx.motion
    projection := ctx.projection
    policy := ctx.visibility
    policy.projection = projection
    for item_index in 0..<projection^.count {
        item := &projection^.items[item_index]
        index := tree_motion_index(motion, item^.key)
        assert(index >= 0, "tree identity absent from admitted motion registry")
        branch := &motion^.branches[index]
        expanded := tree_item_is_effectively_expanded(policy, item^)
        if branch^.expanded == expanded {
            continue
        }
        branch^.expanded = expanded
        branch^.start_height = branch^.height
        branch^.start_seconds = ctx.now_seconds
        branch^.running = !ctx.reduce_motion
    }
}

// tree_frame_context resolves application-owned facts for narrow tree geometry.
tree_frame_context :: proc(params: Tree_List_Params) -> Tree_Frame_Context {
    runtime := params.ui_runtime
    projection := &runtime^.library.tree.projection
    search := &runtime^.library.search
    reduce_motion := params.reduce_motion
    geometry_ctx := Tree_Geometry_Context{
        ji = params.ji,
        projection = projection,
        motion = &runtime^.library.motion,
        drawer = &runtime^.library.actions.drawer,
        collections = params.collections,
        selected_item_id = runtime^.library.tree.selected_item_id,
        search_active = params.visibility.search != nil &&
            params.visibility.search^.active,
        visibility = params.visibility,
        panel = geometry.Rectangle(params.list_panel),
        now_seconds = params.mouse_input.sample_time_seconds,
        reduce_motion = reduce_motion,
    }
    geometry_ctx.visibility.projection = projection
    return {
        geometry = geometry_ctx,
        admission = {
            generation = params.ji^.content_generation,
            topology_revision = projection^.topology_revision,
            query_revision = search^.query_revision,
            search_generation = search^.committed_generation,
            search_active = search^.active,
            count = projection^.count,
            panel = geometry.Rectangle(params.list_panel),
            reduce_motion = reduce_motion,
            programmatic_reveal = runtime^.library.tree.reveal_pending &&
                runtime^.library.tree.reveal_reason == .Programmatic,
        },
    }
}

// tree_reveal_intersection composes tree ancestry without growing the native scissor stack.
tree_reveal_intersection :: proc(
    first, second: geometry.Rectangle) -> geometry.Rectangle {
    return uilayout.stack_panel_clamp_x(
        uilayout.stack_panel_clamp_y(first, second), second)
}

// tree_layout_append records full-size rows beneath inherited content-space reveals.
tree_layout_append :: proc(
    ctx: Tree_Layout_Context, row: Tree_Prepared_Row) {
    item := row.item
    if item == nil || row.depth >= ctx.geometry.projection^.count ||
        !tree_item_is_visible(ctx.geometry.visibility, item^) {
        return
    }
    assert(ctx.layout^.count < len(ctx.layout^.rows),
        "prepared tree exceeds admitted capacity")
    motion := ctx.geometry.motion
    branch := &motion^.branches[tree_motion_index(motion, item^.key)]
    prepared_row := row
    prepared_row.canonical_y = row.content_y
    prepared_row.node = tree_find_stable_id(
        ctx.geometry.ji, item^.target_animation_id)
    prepared_row.expanded = branch^.expanded
    prepared_row.actions = tree_actions_layout(
        ctx.geometry, item, row.depth, row.content_y)
    ctx.layout^.rows[ctx.layout^.count] = prepared_row
    ctx.layout^.count += 1
    tree_layout_append_children(ctx, prepared_row, branch^.height)
}

// tree_layout_append_children places descendants beneath the sampled drawer and branch reveal.
tree_layout_append_children :: proc(
    ctx: Tree_Layout_Context, row: Tree_Prepared_Row, branch_height: f32) {
    if branch_height <= 0 && !row.expanded {
        return
    }
    child_y := row.content_y + theme.TREE_ROW_HEIGHT + row.actions.height
    reveal := tree_reveal_intersection(
        {0, child_y, ctx.geometry.panel.width, branch_height}, row.reveal)
    projection := ctx.geometry.projection
    for child, steps := row.item^.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        child_item := &projection^.items[child]
        tree_layout_append(ctx, {item = child_item, depth = row.depth + 1,
            content_y = child_y, reveal = reveal,
            logical = row.logical && row.expanded})
        if tree_item_is_visible(ctx.geometry.visibility, child_item^) {
            child_y += tree_motion_item_extent(ctx.geometry, child_item)
        }
    }
}

// tree_prepare_layout samples into caller-owned storage shared by all consumers.
tree_prepare_layout :: proc(
    params: Tree_List_Params,
    layout: ^Tree_Prepared_Layout) {
    frame := tree_frame_context(params)
    tree_layout_prepare(frame.geometry, frame.admission, layout)
    tree_reorder_apply(
        &params.ui_runtime^.library.actions.reorder,
        &params.ui_runtime^.library.actions.drawer,
        tree_reorder_admission(params),
        params.mouse_input.sample_time_seconds,
        layout)
}

// tree_layout_prepare resets and fills one caller-owned frame layout.
tree_layout_prepare :: proc(
    ctx: Tree_Geometry_Context,
    admission: Tree_Motion_Admission,
    layout: ^Tree_Prepared_Layout) {
    layout^.count = 0
    layout^.content_height = 0
    if tree_motion_needs_reset(ctx.motion, admission) {
        tree_motion_reset(ctx, admission)
    }
    tree_motion_admit(ctx)
    layout^.content_height = tree_motion_measure_roots(ctx)
    ctx.motion^.visual_height = layout^.content_height
    walk := Tree_Layout_Context{geometry = ctx, layout = layout}
    y: f32
    clip := geometry.Rectangle{0, 0, ctx.panel.width, layout^.content_height}
    projection := ctx.projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        item := &projection^.items[root]
        tree_layout_append(walk, {item = item, content_y = y,
            reveal = clip, logical = true})
        if tree_item_is_visible(ctx.visibility, item^) {
            y += tree_motion_item_extent(ctx, item)
        }
    }
}

// tree_row_screen_geometry intersects row ancestry with the final scrolled viewport.
tree_row_screen_geometry :: proc(
    row: Tree_Prepared_Row, panel: geometry.Rectangle,
    scroll_y: f32) -> viewmodel.Ui_Control_Geometry {
    bounds := geometry.Rectangle{
        panel.x, panel.y + row.content_y - scroll_y, panel.width, theme.TREE_ROW_HEIGHT}
    clip := row.reveal
    clip.x += panel.x
    clip.y += panel.y - scroll_y
    clip = tree_reveal_intersection(clip, panel)
    return {bounds = geometry.Rectangle(bounds), clip_bounds = geometry.Rectangle(clip)}
}
