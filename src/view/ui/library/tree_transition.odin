package uilibrary

import uilayout "../layout"
import collections "../../../collections"
import bridgemodel "../../../bridge/model"
import geometry "../../../core/geometry"
import log "core:log"
import viewmodel "../model"
import theme "../theme"
import uiaccordion "../layout/accordion"
import uuid "core:encoding/uuid"

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
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
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
    branches := motion^.branches
    motion^ = {
        initialized = true,
        generation = admission.generation,
        topology_revision = admission.topology_revision,
        query_revision = admission.query_revision,
        search_generation = admission.search_generation,
        search_active = admission.search_active,
        panel = admission.panel,
        branches = branches,
    }
    projection := ctx.projection
    policy := ctx.visibility
    policy.projection = ctx.projection
    for index in 0..<projection^.count {
        item := projection^.items[index]
        assert(motion^.count < len(motion^.branches),
            "tree motion workspace is smaller than the admitted projection")
        motion^.branches[motion^.count] = {
            stable_id = item.key,
            expanded = tree_item_is_effectively_expanded(policy, item^)}
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

// tree_motion_measure_step advances one bottom-up extent frame.
tree_motion_measure_step :: proc(
    ctx: Tree_Geometry_Context,
    stack_count: int) -> viewmodel.Ui_Tree_Traversal_Step {
    projection := ctx.projection
    frames := projection^.traversal_frames
    frame := &frames[stack_count - 1]
    child_index := frame^.next_child
    if child_index != TREE_NO_ITEM &&
        frame^.sibling_steps < projection^.count {
        child := projection^.items[child_index]
        frame^.next_child = child^.next_sibling
        frame^.sibling_steps += 1
        if !tree_item_is_visible(ctx.visibility, child^) {
            return {stack_count = stack_count, valid = true}
        }
        if stack_count >= len(frames) {
            return {stack_count = stack_count}
        }
        frames[stack_count] = {
            item_index = child_index, next_child = child^.first_child}
        return {stack_count = stack_count + 1, valid = true}
    }
    item := projection^.items[frame^.item_index]
    motion_index := tree_motion_index(ctx.motion, item^.key)
    assert(motion_index >= 0, "tree identity absent from admitted motion registry")
    branch := &ctx.motion^.branches[motion_index]
    tree_motion_sample_branch(branch, frame^.children_height, ctx.now_seconds)
    extent := theme.TREE_ROW_HEIGHT + tree_actions_sample(ctx, item) + branch^.height
    if stack_count == 1 {
        return {extent = extent, complete = true, valid = true}
    }
    frames[stack_count - 2].children_height += extent
    return {stack_count = stack_count - 1, valid = true}
}

// tree_motion_measure_subtree samples descendant extents with owner-backed frames.
tree_motion_measure_subtree :: proc(
    ctx: Tree_Geometry_Context, root_index: int) -> (f32, bool) {
    projection := ctx.projection
    if root_index < 0 || root_index >= projection^.count {
        return 0, true
    }
    root := projection^.items[root_index]
    if !tree_item_is_visible(ctx.visibility, root^) {
        return 0, true
    }
    frames := projection^.traversal_frames
    if len(frames) == 0 {
        return 0, false
    }
    frames[0] = {item_index = root_index, next_child = root^.first_child}
    stack_count := 1
    for stack_count > 0 {
        step := tree_motion_measure_step(ctx, stack_count)
        if !step.valid {
            return 0, false
        }
        stack_count = step.stack_count
        if step.complete {
            return step.extent, true
        }
    }
    return 0, false
}

// tree_motion_measure_roots samples every visible root without native recursion.
tree_motion_measure_roots :: proc(ctx: Tree_Geometry_Context) -> (f32, bool) {
    height: f32
    projection := ctx.projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        root_height, valid := tree_motion_measure_subtree(ctx, root)
        if !valid {
            return 0, false
        }
        height += root_height
    }
    return height, true
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
        item := projection^.items[item_index]
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

// tree_layout_step enters or advances one explicit depth-first frame.
tree_layout_step :: proc(
    ctx: Tree_Layout_Context, stack_count: int) -> (int, bool) {
    projection := ctx.geometry.projection
    frames := projection^.traversal_frames
    frame := &frames[stack_count - 1]
    item := projection^.items[frame^.item_index]
    if !frame^.entered {
        return tree_layout_enter_frame(ctx, frame, item, stack_count)
    }
    child_index := frame^.next_child
    if child_index == TREE_NO_ITEM ||
        frame^.sibling_steps >= projection^.count {
        return stack_count - 1, true
    }
    return tree_layout_push_child(ctx, frame, child_index, stack_count)
}

// tree_layout_enter_frame appends one admitted node and retains child geometry.
tree_layout_enter_frame :: proc(
    ctx: Tree_Layout_Context,
    frame: ^viewmodel.Ui_Tree_Traversal_Frame,
    item: ^viewmodel.Ui_Tree_Item,
    stack_count: int) -> (int, bool) {
    if frame^.depth >= ctx.geometry.projection^.count ||
        !tree_item_is_visible(ctx.geometry.visibility, item^) {
        return stack_count - 1, true
    }
    motion_index := tree_motion_index(ctx.geometry.motion, item^.key)
    branch := &ctx.geometry.motion^.branches[motion_index]
    actions := tree_actions_layout(
        ctx.geometry, item, frame^.depth, frame^.content_y)
    if ctx.layout^.count >= len(ctx.layout^.rows) {
        return stack_count, false
    }
    ctx.layout^.rows[ctx.layout^.count] = {
        item = item, depth = frame^.depth,
        content_y = frame^.content_y, canonical_y = frame^.content_y,
        reveal = frame^.reveal, logical = frame^.logical,
        expanded = branch^.expanded, actions = actions,
    }
    ctx.layout^.count += 1
    if branch^.height <= 0 && !branch^.expanded {
        return stack_count - 1, true
    }
    frame^.next_child = item^.first_child
    frame^.child_y = frame^.content_y + theme.TREE_ROW_HEIGHT + actions.height
    frame^.reveal = tree_reveal_intersection(
        {0, frame^.child_y, ctx.geometry.panel.width, branch^.height},
        frame^.reveal)
    frame^.expanded = branch^.expanded
    frame^.entered = true
    return stack_count, true
}

// tree_layout_push_child advances a parent and admits its next visible child.
tree_layout_push_child :: proc(
    ctx: Tree_Layout_Context,
    frame: ^viewmodel.Ui_Tree_Traversal_Frame,
    child_index, stack_count: int) -> (int, bool) {
    projection := ctx.geometry.projection
    child := projection^.items[child_index]
    frame^.next_child = child^.next_sibling
    frame^.sibling_steps += 1
    if !tree_item_is_visible(ctx.geometry.visibility, child^) {
        return stack_count, true
    }
    child_y := frame^.child_y
    frame^.child_y += tree_motion_item_extent(ctx.geometry, child)
    if stack_count >= len(projection^.traversal_frames) {
        return stack_count, false
    }
    projection^.traversal_frames[stack_count] = {
        item_index = child_index,
        depth = frame^.depth + 1,
        content_y = child_y,
        reveal = frame^.reveal,
        logical = frame^.logical && frame^.expanded,
    }
    return stack_count + 1, true
}

// tree_layout_append walks a subtree iteratively beneath inherited reveal geometry.
tree_layout_append :: proc(
    ctx: Tree_Layout_Context,
    row: viewmodel.Ui_Tree_Prepared_Row) -> bool {
    projection := ctx.geometry.projection
    if row.item == nil || row.depth >= projection^.count ||
        !tree_item_is_visible(ctx.geometry.visibility, row.item^) {
        return true
    }
    root_index := tree_projection_find(projection, row.item^.key)
    if root_index == TREE_NO_ITEM || len(projection^.traversal_frames) == 0 {
        return false
    }
    projection^.traversal_frames[0] = {
        item_index = root_index, depth = row.depth,
        content_y = row.content_y, reveal = row.reveal, logical = row.logical,
    }
    stack_count := 1
    for stack_count > 0 {
        next_count, valid := tree_layout_step(ctx, stack_count)
        if !valid {
            return false
        }
        stack_count = next_count
    }
    return true
}

// tree_prepare_layout samples into caller-owned storage shared by all consumers.
tree_prepare_layout :: proc(
    params: Tree_List_Params,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) -> bool {
    frame := tree_frame_context(params)
    if !tree_layout_prepare_mode(frame.geometry, frame.admission, layout, false) {
        return false
    }
    tree_reorder_apply(
        &params.ui_runtime^.library.actions.reorder,
        &params.ui_runtime^.library.actions.drawer,
        tree_reorder_admission(params),
        params.mouse_input.sample_time_seconds,
        layout)
    return true
}

// tree_prepare_layout_scratch isolates command checks from finalized frame rows.
tree_prepare_layout_scratch :: proc(
    params: Tree_List_Params,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) -> bool {
    frame := tree_frame_context(params)
    if !tree_layout_prepare_mode(frame.geometry, frame.admission, layout, true) {
        return false
    }
    tree_reorder_apply(
        &params.ui_runtime^.library.actions.reorder,
        &params.ui_runtime^.library.actions.drawer,
        tree_reorder_admission(params),
        params.mouse_input.sample_time_seconds,
        layout)
    return true
}

// tree_layout_prepare resets and fills one caller-owned frame layout.
tree_layout_prepare :: proc(
    ctx: Tree_Geometry_Context,
    admission: Tree_Motion_Admission,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) -> bool {
    return tree_layout_prepare_mode(ctx, admission, layout, false)
}

// tree_layout_prepare_workspaces admits all reusable storage before borrowing it.
tree_layout_prepare_workspaces :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    motion: ^viewmodel.Ui_Tree_Motion,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
    scratch: bool) -> bool {
    if !viewmodel.ui_tree_projection_reserve_motion(
        projection, projection^.count) {
        log.error("library_tree_motion_workspace_allocation_failed")
        return false
    }
    if !viewmodel.ui_tree_projection_reserve_prepared_rows(
        projection, scratch, projection^.count) {
        log.error("library_tree_layout_workspace_allocation_failed")
        return false
    }
    if !viewmodel.ui_tree_projection_reserve_traversal(
        projection, projection^.count) {
        log.error("library_tree_traversal_workspace_allocation_failed")
        return false
    }
    motion^.branches = projection^.motion_branches
    layout^.rows = projection.frame_rows
    if scratch {
        layout^.rows = projection.scratch_rows
    }
    return true
}

// tree_layout_prepare_mode selects stable frame rows or independent scratch rows.
tree_layout_prepare_mode :: proc(
    ctx: Tree_Geometry_Context,
    admission: Tree_Motion_Admission,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
    scratch: bool) -> bool {
    projection := ctx.projection
    if !tree_layout_prepare_workspaces(
        projection, ctx.motion, layout, scratch) {
        layout^.count = 0
        return false
    }
    layout^.count = 0
    layout^.content_height = 0
    if tree_motion_needs_reset(ctx.motion, admission) {
        tree_motion_reset(ctx, admission)
    }
    tree_motion_admit(ctx)
    content_height, measured := tree_motion_measure_roots(ctx)
    if !measured {
        log.error("library_tree_motion_traversal_failed")
        layout^.count = 0
        return false
    }
    layout^.content_height = content_height
    ctx.motion^.visual_height = layout^.content_height
    return tree_layout_append_roots(ctx, layout)
}

// Append ordered roots after bottom-up measurement has fixed their extents.
tree_layout_append_roots :: proc(
    ctx: Tree_Geometry_Context,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) -> bool {
    projection := ctx.projection
    walk := Tree_Layout_Context{geometry = ctx, layout = layout}
    y: f32
    clip := geometry.Rectangle{0, 0, ctx.panel.width, layout^.content_height}
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        item := projection^.items[root]
        if !tree_layout_append(walk, {item = item, content_y = y,
            reveal = clip, logical = true}) {
            log.error("library_tree_layout_traversal_failed")
            layout^.count = 0
            return false
        }
        if tree_item_is_visible(ctx.visibility, item^) {
            y += tree_motion_item_extent(ctx, item)
        }
    }
    return true
}

// tree_row_screen_geometry intersects row ancestry with the final scrolled viewport.
tree_row_screen_geometry :: proc(
    row: viewmodel.Ui_Tree_Prepared_Row, panel: geometry.Rectangle,
    scroll_y: f32) -> viewmodel.Ui_Control_Geometry {
    bounds := geometry.Rectangle{
        panel.x, panel.y + row.content_y - scroll_y, panel.width, theme.TREE_ROW_HEIGHT}
    clip := row.reveal
    clip.x += panel.x
    clip.y += panel.y - scroll_y
    clip = tree_reveal_intersection(clip, panel)
    return {bounds = geometry.Rectangle(bounds), clip_bounds = geometry.Rectangle(clip)}
}
