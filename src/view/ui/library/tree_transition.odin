package uilibrary

import uilayout "../layout"
import bridgemodel "../../../bridge/model"
import contentmodel "../../../core/content"
import geometry "../../../core/geometry"
import viewmodel "../model"
import theme "../theme"
import uiaccordion "../layout/accordion"
import uuid "core:encoding/uuid"

#assert(viewmodel.UI_TREE_NODE_CAPACITY >= contentmodel.CATALOG_RECORD_CAPACITY)

// Tree_Prepared_Row borrows projection and animation data only for this frame.
Tree_Prepared_Row :: struct {
    item: ^viewmodel.Ui_Tree_Item,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    depth: int,
    content_y: f32,
    reveal: geometry.Rectangle,
    logical: bool,
    expanded: bool,
}

// Tree_Prepared_Layout bounds all rows, including visual-only closing descendants.
Tree_Prepared_Layout :: struct {
    rows: [viewmodel.UI_TREE_NODE_CAPACITY]Tree_Prepared_Row,
    count: int,
    content_height: f32,
}

// Tree_Layout_Context shares one bounded output and retained motion for a DFS.
Tree_Layout_Context :: struct {
    params: Tree_List_Params,
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

// tree_motion_needs_reset rejects geometry, generation, search, and policy discontinuities.
tree_motion_needs_reset :: proc(params: Tree_List_Params) -> bool {
    motion := &params.ui_runtime^.tree_motion
    search := &params.ui_runtime^.library_search
    return !motion^.initialized || motion^.generation != params.ji^.content_generation ||
        motion^.panel != geometry.Rectangle(params.list_panel) ||
        motion^.count != params.ui_runtime^.tree_projection.count ||
        motion^.topology_revision !=
            params.ui_runtime^.tree_projection.topology_revision ||
        motion^.query_revision != search^.query_revision ||
        motion^.search_generation != search^.committed_generation ||
        motion^.search_active != search^.active ||
        uiaccordion.ui_reduced_motion(params.ui_runtime) ||
        params.ui_runtime^.tree_reveal_pending &&
            params.ui_runtime^.tree_reveal_reason == .Programmatic
}

// tree_motion_reset initializes every admitted identity and snaps logical topology.
tree_motion_reset :: proc(params: Tree_List_Params) {
    motion := &params.ui_runtime^.tree_motion
    search := &params.ui_runtime^.library_search
    motion^ = {
        initialized = true, generation = params.ji^.content_generation,
        topology_revision = params.ui_runtime^.tree_projection.topology_revision,
        query_revision = search^.query_revision,
        search_generation = search^.committed_generation, search_active = search^.active,
        panel = geometry.Rectangle(params.list_panel),
    }
    projection := &params.ui_runtime^.tree_projection
    policy := params.visibility
    policy.projection = projection
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
    params: Tree_List_Params,
    item_index, remaining: int) -> f32 {
    projection := &params.ui_runtime^.tree_projection
    if item_index < 0 || remaining <= 0 || item_index >= projection^.count {
        return 0
    }
    item := projection^.items[item_index]
    if !tree_item_is_visible(params.visibility, item) {
        return 0
    }
    full_height: f32
    for child, steps := item.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        full_height += tree_motion_measure(params, child, remaining - 1)
    }
    motion_index := tree_motion_index(&params.ui_runtime^.tree_motion, item.key)
    assert(motion_index >= 0, "tree identity absent from admitted motion registry")
    branch := &params.ui_runtime^.tree_motion.branches[motion_index]
    tree_motion_sample_branch(branch, full_height, params.mouse_input.sample_time_seconds)
    return theme.TREE_ROW_HEIGHT + branch^.height
}

// tree_motion_measure_roots samples even hidden branches so their deadlines still finish.
tree_motion_measure_roots :: proc(params: Tree_List_Params) -> f32 {
    height: f32
    projection := &params.ui_runtime^.tree_projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        height += tree_motion_measure(params, root, projection^.count)
    }
    return height
}

// tree_motion_admit retargets changed explicit topology from the last sampled geometry.
tree_motion_admit :: proc(params: Tree_List_Params) {
    motion := &params.ui_runtime^.tree_motion
    projection := &params.ui_runtime^.tree_projection
    policy := params.visibility
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
        branch^.start_seconds = params.mouse_input.sample_time_seconds
        branch^.running = !uiaccordion.ui_reduced_motion(params.ui_runtime)
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
    if item == nil || row.depth >= ctx.params.ui_runtime^.tree_projection.count ||
        !tree_item_is_visible(ctx.params.visibility, item^) {
        return
    }
    assert(ctx.layout^.count < len(ctx.layout^.rows),
        "prepared tree exceeds admitted capacity")
    motion := &ctx.params.ui_runtime^.tree_motion
    branch := &motion^.branches[tree_motion_index(motion, item^.key)]
    prepared_row := row
    prepared_row.node = tree_find_stable_id(
        ctx.params.ji, item^.target_animation_id)
    prepared_row.expanded = branch^.expanded
    ctx.layout^.rows[ctx.layout^.count] = prepared_row
    ctx.layout^.count += 1
    if branch^.height <= 0 && !branch^.expanded {
        return
    }
    child_y := row.content_y + theme.TREE_ROW_HEIGHT
    reveal := tree_reveal_intersection(
        {0, child_y, ctx.params.list_panel.width, branch^.height}, row.reveal)
    projection := &ctx.params.ui_runtime^.tree_projection
    for child, steps := item^.first_child, 0;
        child != TREE_NO_ITEM && steps < projection^.count;
        child, steps = projection^.items[child].next_sibling, steps + 1 {
        child_item := &projection^.items[child]
        tree_layout_append(ctx, {item = child_item, depth = row.depth + 1,
            content_y = child_y, reveal = reveal,
            logical = row.logical && branch^.expanded})
        if tree_item_is_visible(ctx.params.visibility, child_item^) {
            child_y += theme.TREE_ROW_HEIGHT +
                motion^.branches[tree_motion_index(motion, child_item^.key)].height
        }
    }
}

// tree_prepare_layout samples once and returns the visual extent shared by all consumers.
tree_prepare_layout :: proc(params: Tree_List_Params) -> Tree_Prepared_Layout {
    if tree_motion_needs_reset(params) {
        tree_motion_reset(params)
    }
    tree_motion_admit(params)
    result: Tree_Prepared_Layout
    result.content_height = tree_motion_measure_roots(params)
    params.ui_runtime^.tree_motion.visual_height = result.content_height
    ctx := Tree_Layout_Context{params, &result}
    y: f32
    clip := geometry.Rectangle{0, 0, params.list_panel.width, result.content_height}
    projection := &params.ui_runtime^.tree_projection
    for root, steps := projection^.first_root, 0;
        root != TREE_NO_ITEM && steps < projection^.count;
        root, steps = projection^.items[root].next_sibling, steps + 1 {
        item := &projection^.items[root]
        tree_layout_append(ctx, {item = item, node = tree_find_stable_id(
            params.ji, item^.target_animation_id), content_y = y,
            reveal = clip, logical = true})
        if tree_item_is_visible(params.visibility, item^) {
            y += theme.TREE_ROW_HEIGHT +
                params.ui_runtime^.tree_motion.branches[
                    tree_motion_index(&params.ui_runtime^.tree_motion, item^.key)].height
        }
    }
    return result
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
