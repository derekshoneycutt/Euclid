package uilibrary

import collections "../../../collections"
import geometry "../../../core/geometry"
import uuid "core:encoding/uuid"
import viewmodel "../model"
import theme "../theme"
import uiaccordion "../layout/accordion"
import log "core:log"

// Tree_Reorder_Admission holds current facts that can interrupt a sampled swap.
Tree_Reorder_Admission :: struct {
    generation: u64,
    topology_revision: u64,
    owner: uuid.Identifier,
    panel: geometry.Rectangle,
    drawer_height: f32,
    search_active: bool,
    library_active: bool,
    reduce_motion: bool,
}

// tree_reorder_capture samples current Favorites positions before an attempted mutation.
tree_reorder_capture :: proc(
    params: Tree_List_Params,
    result: ^viewmodel.Ui_Tree_Reorder_Motion) {
    result^ = {}
    if params.reduce_motion {
        return
    }
    projection := &params.ui_runtime^.library.tree.projection
    if !viewmodel.ui_tree_projection_reserve_reorder(
        projection, projection^.count) {
        log.error("library_tree_reorder_workspace_allocation_failed")
        return
    }
    result^.rows = projection^.reorder_rows
    layout: viewmodel.Ui_Tree_Prepared_Layout
    if !tree_prepare_layout_scratch(params, &layout) {
        return
    }
    result^.owner = params.ui_runtime^.library.tree.selected_item_id
    result^.generation = params.ji^.content_generation
    result^.panel = params.list_panel
    result^.start_seconds = params.mouse_input.sample_time_seconds
    result^.drawer_height = params.ui_runtime^.library.actions.drawer.height
    for row in layout.rows[:layout.count] {
        parent := row.item^.parent
        if !row.logical || row.item^.kind != .Placement || parent == TREE_NO_ITEM ||
            projection^.items[parent].key != collections.FAVORITES_COLLECTION_ID {
            continue
        }
        result^.rows[result^.count] = {id = row.item^.key, from_y = row.content_y}
        result^.count += 1
    }
    result^.active = result^.count > 1
    result^.retarget_pending = result^.active
}

// tree_reorder_admission resolves discontinuity facts at the panel boundary.
tree_reorder_admission :: proc(params: Tree_List_Params) -> Tree_Reorder_Admission {
    runtime := params.ui_runtime
    return {
        generation = params.ji^.content_generation,
        topology_revision = runtime^.library.tree.projection.topology_revision,
        owner = runtime^.library.tree.selected_item_id,
        panel = params.list_panel,
        drawer_height = runtime^.library.actions.drawer.height,
        search_active = params.visibility.search != nil &&
            params.visibility.search^.active,
        library_active = runtime^.layout.active_accordion_section == .Library,
        reduce_motion = params.reduce_motion,
    }
}

// tree_reorder_compatible rejects discontinuities without treating an accepted swap as one.
tree_reorder_compatible :: proc(
    motion: ^viewmodel.Ui_Tree_Reorder_Motion,
    drawer: ^viewmodel.Ui_Tree_Actions_Motion,
    current: Tree_Reorder_Admission) -> bool {
    return !current.reduce_motion &&
        motion^.generation == current.generation &&
        motion^.panel == current.panel &&
        motion^.topology_revision == current.topology_revision &&
        motion^.owner == current.owner &&
        drawer^.entry_id == motion^.owner && drawer^.open &&
        drawer^.height == motion^.drawer_height &&
        !current.search_active && current.library_active
}

// tree_reorder_index resolves retained positions solely by placement identity.
tree_reorder_index :: proc(
    motion: ^viewmodel.Ui_Tree_Reorder_Motion, id: uuid.Identifier) -> int {
    for index in 0..<motion^.count {
        if motion^.rows[index].id == id {
            return index
        }
    }
    return -1
}

// tree_reorder_apply samples positions once per timestamp without moving ancestor clips.
tree_reorder_apply :: proc(
    motion: ^viewmodel.Ui_Tree_Reorder_Motion,
    drawer: ^viewmodel.Ui_Tree_Actions_Motion,
    current: Tree_Reorder_Admission,
    now: f64,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
    if !motion^.active {
        return
    }
    if !tree_reorder_compatible(motion, drawer, current) ||
        now >= motion^.start_seconds + uiaccordion.INTERFACE_TRANSITION_SECONDS {
        motion^ = {}
        return
    }
    ease := uiaccordion.interface_motion_ease(motion^.start_seconds, now)
    for &row in layout^.rows[:layout^.count] {
        index := tree_reorder_index(motion, row.item^.key)
        if index < 0 {
            continue
        }
        retained := &motion^.rows[index]
        if motion^.retarget_pending {
            retained^.target_y = row.canonical_y
        }
        y := retained^.from_y + (retained^.target_y - retained^.from_y) * ease
        tree_reorder_translate_row(&row, y - row.content_y)
    }
    motion^.retarget_pending = false
}

// tree_reorder_translate_row keeps a placement, disclosure, and attached drawer together.
tree_reorder_translate_row :: proc(
    row: ^viewmodel.Ui_Tree_Prepared_Row, offset: f32) {
    row^.content_y += offset
    row^.actions.toggle_rect.y += offset
    row^.actions.drawer_rect.y += offset
    row^.actions.move_up_rect.y += offset
    row^.actions.move_down_rect.y += offset
}

// tree_reorder_foreground finds the selected visual block during a running exchange.
tree_reorder_foreground :: proc(
    motion: ^viewmodel.Ui_Tree_Reorder_Motion,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) -> int {
    if !motion^.active {
        return -1
    }
    for index in 0..<layout^.count {
        if layout^.rows[index].item^.key == motion^.owner {
            return index
        }
    }
    return -1
}

// tree_reorder_block_clip bounds the opaque foreground row and drawer in screen space.
tree_reorder_block_clip :: proc(
    row: viewmodel.Ui_Tree_Prepared_Row,
    panel: geometry.Rectangle, scroll_y: f32) -> geometry.Rectangle {
    bounds := tree_row_screen_geometry(row, panel, scroll_y)
    block := bounds.bounds
    block.height = theme.TREE_ROW_HEIGHT + row.actions.height
    return tree_reveal_intersection(block, bounds.clip_bounds)
}

// tree_reorder_visible_geometry excludes foreground occlusion from addressed row admission.
tree_reorder_visible_geometry :: proc(
    motion: ^viewmodel.Ui_Tree_Reorder_Motion,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
    row: viewmodel.Ui_Tree_Prepared_Row, panel: geometry.Rectangle,
    scroll_y: f32) -> viewmodel.Ui_Control_Geometry {
    result := tree_row_screen_geometry(row, panel, scroll_y)
    foreground := tree_reorder_foreground(motion, layout)
    if foreground < 0 || layout^.rows[foreground].item^.key == row.item^.key {
        return result
    }

    block := tree_reorder_block_clip(layout^.rows[foreground], panel, scroll_y)
    visible := tree_reveal_intersection(result.bounds, result.clip_bounds)
    if !geometry.rectangles_intersect(visible, block) {
        return result
    }
    if visible.y < block.y {
        visible.height = block.y - visible.y
    } else {
        bottom := visible.y + visible.height
        visible.y = min(block.y + block.height, bottom)
        visible.height = bottom - visible.y
    }
    result.clip_bounds = visible
    return result
}

// tree_reorder_command_visible rechecks current visual admission before native selection.
tree_reorder_command_visible :: proc(
    params: Tree_List_Params, item: ^viewmodel.Ui_Tree_Item) -> bool {
    if !params.ui_runtime^.library.actions.reorder.active {
        return true
    }
    layout: viewmodel.Ui_Tree_Prepared_Layout
    if !tree_prepare_layout_scratch(params, &layout) {
        return false
    }
    row := tree_layout_find_item(&layout, item)
    if row == nil {
        return false
    }
    bounds := tree_reorder_visible_geometry(
        &params.ui_runtime^.library.actions.reorder,
        &layout, row^, params.list_panel, params.scroll_y^)
    return geometry.rectangles_intersect(bounds.bounds, bounds.clip_bounds)
}
