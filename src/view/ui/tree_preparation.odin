package ui

import bridgemodel "../../bridge/model"
import geometry "../../core/geometry"
import viewmodel "../model"
import "../../core"
import "../native"

// tree_layout_find locates a frame-borrowed row without confusing logical and visual order.
tree_layout_find :: proc(
    layout: ^Tree_Prepared_Layout,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> ^Tree_Prepared_Row {
    for index in 0..<layout^.count {
        if layout^.rows[index].node == node {
            return &layout^.rows[index]
        }
    }
    return nil
}

// tree_row_is_revealed excludes rows beyond the inherited descendant reveal.
tree_row_is_revealed :: proc(row: Tree_Prepared_Row) -> bool {
    return row.logical && geometry.rectangles_intersect(
        {0, row.content_y, row.reveal.width, TREE_ROW_HEIGHT}, row.reveal)
}

// draw_encoded_prepared_tree shares full-size row positions and clips across both passes.
draw_encoded_prepared_tree :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Tree_List_Preparation, text: bool) {
    panel := prepared.scroll.view_rect
    ctx := Encoded_Tree_Walk_Context{
        state = state, ji = state^.julia_interface, encoder = encoder, panel = panel,
        pressed_node = prepared.pressed_node,
        visibility = {search = &state^.ui_runtime.library_search}}
    for index in 0..<prepared.layout.count {
        row := prepared.layout.rows[index]
        row_geometry := tree_row_screen_geometry(row, panel, prepared.scroll.scroll_y_out)
        bounds := geometry.Rectangle(row_geometry.bounds)
        clip := geometry.Rectangle(row_geometry.clip_bounds)
        if !geometry.rectangles_intersect(bounds, clip) {
            continue
        }
        _ = native.draw_encoder_push_scissor(encoder, clip)
        if text {
            draw_encoded_label(state, encoder, row.node^.name,
                bounds.x + f32(row.depth) * TREE_INDENT + TREE_ROW_LABEL_OFFSET_X,
                bounds.y + TREE_ROW_LABEL_OFFSET_Y)
        } else {
            ctx.render_only = !row.logical
            draw_encoded_tree_row(ctx, row.node, row.depth, bounds.y, row.expanded)
        }
        _ = native.draw_encoder_pop_scissor(encoder)
    }
}

// tree_update_scroll resolves ordinary scrolling against current animated content extent.
tree_update_scroll :: proc(
    params: Tree_List_Params, content_height: f32) -> Scroll_Container_Update_Result {
    return scroll_container_update({id = UI_TREE_SCROLLBAR_ID,
        rect = params.list_panel, scroll_y_in = params.scroll_y^,
        content_height = content_height, mouse_input = params.mouse_input,
        interaction_space_rect = params.list_panel,
        wheel_step = TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &params.ui_runtime^.ui_press_owner,
        state_in = {params.ui_runtime^.tree_scroll_dragging,
            params.ui_runtime^.tree_scroll_drag_off},
        semantic_focus = params.ui_runtime^.semantic_focus,
        semantic_id = tree_semantic_id()})
}

// tree_refresh_preparation keeps range, visual height, and scrollbar aligned after toggling.
tree_refresh_preparation :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    visual := scroll_container_visual(params.list_panel,
        prepared^.layout.content_height, params.scroll_y^,
        TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER)
    params.scroll_y^ = visual.scroll_y_out
    prepared^.scroll.maximum = visual.maximum
    prepared^.scroll.scroll_y_out = visual.scroll_y_out
    prepared^.scroll.scrollbar = visual.scrollbar
    prepared^.content_height = prepared^.layout.content_height
}

// tree_update_prepared_rows admits only logical revealed rows and cancels hidden releases.
tree_update_prepared_rows :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) -> Tree_Hit {
    hit: Tree_Hit
    tree_cancel_hidden_capture(params, prepared)
    ctx := Tree_Walk_Context{ji = params.ji, ui_runtime = params.ui_runtime,
        panel = prepared^.scroll.view_rect, scroll_y = prepared^.scroll.scroll_y_out,
        allow_clicks = !prepared^.scroll.pointer_reserved,
        mouse_input = params.mouse_input, font = params.font,
        font_resolver = params.font_resolver, visibility = params.visibility}
    for row in prepared^.layout.rows[:prepared^.layout.count] {
        row_geometry := tree_row_screen_geometry(
            row, ctx.panel, prepared^.scroll.scroll_y_out)
        clip := geometry.Rectangle(row_geometry.clip_bounds)
        owns := params.ui_runtime^.ui_press_owner.active &&
            params.ui_runtime^.ui_press_owner.kind == .List_Item &&
            params.ui_runtime^.ui_press_owner.id == tree_node_press_id(row.node)
        admitted := tree_row_is_revealed(row) &&
            geometry.rectangles_intersect(geometry.Rectangle(row_geometry.bounds), clip)
        if owns && (!admitted || input_frame_left_released(params.mouse_input) &&
            !geometry.rectangle_contains(clip,
                input_frame_mouse_position(params.mouse_input))) {
            params.ui_runtime^.ui_press_owner = {}
        }
        if !admitted {
            continue
        }
        ctx.interaction_space_rect = clip
        update_tree_node_row(ctx, row.node, row.depth,
            geometry.Rectangle(row_geometry.bounds), &hit)
    }
    return hit
}

// tree_cancel_hidden_capture releases rows removed or clipped by an immediate topology change.
tree_cancel_hidden_capture :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    owner := params.ui_runtime^.ui_press_owner
    if !owner.active || owner.kind != .List_Item {
        return
    }
    for row in prepared^.layout.rows[:prepared^.layout.count] {
        if owner.id != tree_node_press_id(row.node) || !tree_row_is_revealed(row) {
            continue
        }
        bounds := tree_row_screen_geometry(
            row, prepared^.scroll.view_rect, prepared^.scroll.scroll_y_out)
        if geometry.rectangles_intersect(
            geometry.Rectangle(bounds.bounds), geometry.Rectangle(bounds.clip_bounds)) {
            return
        }
    }
    params.ui_runtime^.ui_press_owner = {}
}

// tree_motion_anchor stores the initiating parent's screen offset, not child visibility.
tree_motion_anchor :: proc(
    params: Tree_List_Params,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    layout: ^Tree_Prepared_Layout) {
    row := tree_layout_find(layout, node)
    if row == nil || !row^.logical {
        return
    }
    motion := &params.ui_runtime^.tree_motion
    motion^.anchor_id = node^.stable_id
    motion^.anchor_view_y = row^.content_y - params.scroll_y^
    motion^.anchored = true
}

// tree_motion_anchor_action samples before any addressed structural mutation.
tree_motion_anchor_action :: proc(
    params: Tree_List_Params,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    kind: viewmodel.Ui_Focus_Command_Kind) {
    changes := kind == .Toggle || kind == .Expand && !node^.is_expanded ||
        kind == .Collapse && node^.is_expanded ||
        kind == .Tree_Parent && node^.is_expanded ||
        kind == .Tree_Child && !node^.is_expanded
    if changes && node^.first_child != nil {
        layout := tree_prepare_layout(params)
        tree_motion_anchor(params, node, &layout)
    }
}

// tree_motion_settle_navigation finishes only the ancestors needed by the requested row.
tree_motion_settle_navigation :: proc(params: Tree_List_Params) {
    runtime := params.ui_runtime
    if !runtime^.tree_reveal_pending || runtime^.tree_reveal_reason != .Navigation {
        return
    }
    target := tree_find_stable_id(params.ji, runtime^.tree_reveal_stable_id)
    if target == nil {
        return
    }
    for parent, steps := target^.parent, 0;
        parent != nil && steps < params.ji^.animation_count;
        parent, steps = parent^.parent, steps + 1 {
        index := tree_motion_index(&runtime^.tree_motion, parent)
        runtime^.tree_motion.branches[index].running = false
    }
}

// tree_apply_visual_reveal honors keyboard/external reveal using fractional visual positions.
tree_apply_visual_reveal :: proc(
    params: Tree_List_Params, layout: ^Tree_Prepared_Layout) {
    runtime := params.ui_runtime
    if !runtime^.tree_reveal_pending {
        return
    }
    target := tree_find_stable_id(params.ji, runtime^.tree_reveal_stable_id)
    row := tree_layout_find(layout, target)
    if row == nil || !tree_row_is_revealed(row^) {
        return
    }
    maximum := max(layout^.content_height - params.list_panel.height, 0)
    scroll := clamp(params.scroll_y^, 0, maximum)
    if row^.content_y < scroll {
        scroll = row^.content_y
    } else if row^.content_y + TREE_ROW_HEIGHT > scroll + params.list_panel.height {
        scroll = row^.content_y + TREE_ROW_HEIGHT - params.list_panel.height
    }
    params.scroll_y^ = clamp(scroll, 0, maximum)
    runtime^.tree_reveal_pending = false
    motion := &runtime^.tree_motion
    motion^.anchored = motion^.anchored && motion^.anchor_id == row^.node^.stable_id
    if motion^.anchored {
        motion^.anchor_view_y = row^.content_y - params.scroll_y^
    }
    runtime^.tree_scroll_dragging = false
    runtime^.tree_scroll_drag_off = 0
    if scroll_container_owns_press(&runtime^.ui_press_owner, UI_TREE_SCROLLBAR_ID) {
        runtime^.ui_press_owner = {}
    }
}

// tree_motion_apply_anchor defers to explicit wheel/drag input and ordinary row reveal.
tree_motion_apply_anchor :: proc(
    params: Tree_List_Params, layout: ^Tree_Prepared_Layout) {
    motion := &params.ui_runtime^.tree_motion
    if params.mouse_input.mouse_wheel_delta != 0 ||
       params.ui_runtime^.tree_scroll_dragging {
        motion^.anchored = false
    }
    if !motion^.anchored {
        return
    }
    for row in layout^.rows[:layout^.count] {
        if row.node^.stable_id == motion^.anchor_id && row.logical {
            params.scroll_y^ = clamp(row.content_y - motion^.anchor_view_y,
                0, max(layout^.content_height - params.list_panel.height, 0))
            return
        }
    }
    motion^.anchored = false
}

// tree_motion_release_anchor prevents compensation from competing with ordinary scrolling.
tree_motion_release_anchor :: proc(
    params: Tree_List_Params, scroll: Scroll_Container_Update_Result) {
    if scroll.changed || scroll.pointer_reserved || scroll.wheel_consumed ||
        !tree_motion_running(&params.ui_runtime^.tree_motion) {
        params.ui_runtime^.tree_motion.anchored = false
    }
}

// tree_motion_running reports whether any admitted branch has an unfinished deadline.
tree_motion_running :: proc(motion: ^viewmodel.Ui_Tree_Motion) -> bool {
    for index in 0..<motion^.count {
        if motion^.branches[index].running {
            return true
        }
    }
    return false
}

// prepare_tree_visual settles hidden Library content without commands, semantics, or scrolling.
prepare_tree_visual :: proc(params: Tree_List_Params) -> Tree_List_Preparation {
    if params.ji == nil || params.ji^.animation_count == 0 {
        params.ui_runtime^.tree_motion = {}
        return {}
    }
    tree_motion_reset(params)
    layout := tree_prepare_layout(params)
    return {layout = layout, content_height = layout.content_height,
        scroll = scroll_container_visual(params.list_panel,
            layout.content_height, params.scroll_y^,
            TREE_ROW_HEIGHT * WHEEL_SCROLL_MULTIPLIER)}
}
