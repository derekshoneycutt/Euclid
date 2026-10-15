package uilibrary

import bridgemodel "../../../bridge/model"
import geometry "../../../core/geometry"
import core "../../../core"
import native "../../native"
import viewmodel "../model"
import theme "../theme"
import uiwidgets "../widgets"
import viewtext "../text"
import log "core:log"

UI_TREE_SCROLLBAR_ID :: 1003

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

// tree_layout_find_item resolves a prepared row by its display-owned placement.
tree_layout_find_item :: proc(
    layout: ^Tree_Prepared_Layout,
    item: ^viewmodel.Ui_Tree_Item) -> ^Tree_Prepared_Row {
    for index in 0..<layout^.count {
        if layout^.rows[index].item == item {
            return &layout^.rows[index]
        }
    }
    return nil
}

// tree_row_is_revealed excludes rows beyond the inherited descendant reveal.
tree_row_is_revealed :: proc(row: Tree_Prepared_Row) -> bool {
    return row.logical && geometry.rectangles_intersect(
        {0, row.content_y, row.reveal.width, theme.TREE_ROW_HEIGHT}, row.reveal)
}

// draw_encoded_prepared_tree shares full-size row positions and clips across both passes.
draw_encoded_prepared_tree :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: ^Tree_List_Preparation, text: bool) {
    panel := prepared^.scroll.view_rect
    visibility := Tree_Visibility_Policy{
        search = &state^.ui_runtime.library.search,
        projection = &state^.ui_runtime.library.tree.projection,
    }
    ctx := Encoded_Tree_Walk_Context{
        state = state, ji = state^.julia_interface, encoder = encoder, panel = panel,
        pressed_node = prepared^.pressed_node,
        scroll_y = prepared^.scroll.scroll_y_out,
        visibility = visibility}
    foreground := tree_reorder_foreground(
        &state^.ui_runtime.library.actions.reorder, &prepared^.layout)
    occlusion: geometry.Rectangle
    if foreground >= 0 {
        occlusion = tree_reorder_block_clip(
            prepared^.layout.rows[foreground], panel, prepared^.scroll.scroll_y_out)
    }
    for index in 0..<prepared^.layout.count {
        row := prepared^.layout.rows[index]
        row_geometry := tree_row_screen_geometry(
            row, panel, prepared^.scroll.scroll_y_out)
        bounds := geometry.Rectangle(row_geometry.bounds)
        clip := geometry.Rectangle(row_geometry.clip_bounds)
        drawer := tree_actions_screen_rect(
            row.actions.drawer_rect, panel, prepared^.scroll.scroll_y_out)
        if !geometry.rectangles_intersect(bounds, clip) &&
            !(row.actions.height > 0 && geometry.rectangles_intersect(drawer, clip)) {
            continue
        }
        tree_draw_reorder_layer(ctx, row, row_geometry, text,
            {} if index == foreground else occlusion)
    }

}

// tree_draw_reorder_layer clips background geometry and text around the opaque moving block.
tree_draw_reorder_layer :: proc(
    ctx: Encoded_Tree_Walk_Context, row: Tree_Prepared_Row,
    bounds: viewmodel.Ui_Control_Geometry, text: bool, occlusion: geometry.Rectangle) {
    clip := bounds.clip_bounds
    if occlusion.height <= 0 || !geometry.rectangles_intersect(clip, occlusion) {
        draw_encoded_prepared_tree_row(ctx, row, bounds, text)
        return
    }
    above := bounds
    above.clip_bounds.height = max(min(occlusion.y, clip.y + clip.height) - clip.y, 0)
    below := bounds
    below.clip_bounds.y = max(clip.y, occlusion.y + occlusion.height)
    below.clip_bounds.height = max(clip.y + clip.height - below.clip_bounds.y, 0)
    if above.clip_bounds.height > 0 {
        draw_encoded_prepared_tree_row(ctx, row, above, text)
    }
    if below.clip_bounds.height > 0 {
        draw_encoded_prepared_tree_row(ctx, row, below, text)
    }
}

// draw_encoded_prepared_tree_row shares one inherited clip between row and drawer.
draw_encoded_prepared_tree_row :: proc(
    ctx: Encoded_Tree_Walk_Context, row: Tree_Prepared_Row,
    row_geometry: viewmodel.Ui_Control_Geometry, text: bool) {
    bounds := row_geometry.bounds
    clip := row_geometry.clip_bounds
    _ = native.draw_encoder_push_scissor(ctx.encoder, clip)
    if text {
        label_clip := tree_actions_label_clip(row.actions, bounds, clip)
        if geometry.rectangles_intersect(label_clip, clip) {
            _ = native.draw_encoder_push_scissor(ctx.encoder, label_clip)
            viewtext.draw_encoded_label(&ctx.state^.font_cache, ctx.encoder,
                tree_item_label(ctx.ji, row.item),
                bounds.x + f32(row.depth) *
                    theme.TREE_INDENT + theme.TREE_ROW_LABEL_OFFSET_X,
                bounds.y + theme.TREE_ROW_LABEL_OFFSET_Y)
            _ = native.draw_encoder_pop_scissor(ctx.encoder)
        }
        draw_encoded_tree_actions_text(
            ctx.state, ctx.encoder, row, ctx.panel, ctx.scroll_y)
    } else {
        current := ctx
        current.render_only = !row.logical
        draw_encoded_tree_row(current, row.item, row.depth, bounds.y, row.expanded)
        draw_encoded_tree_actions_geometry(ctx.encoder, row, ctx.panel, ctx.scroll_y)
        tree_actions_draw_focus(
            ctx.encoder, &ctx.state^.ui_runtime, row, ctx.panel, ctx.scroll_y)
    }
    _ = native.draw_encoder_pop_scissor(ctx.encoder)
}

// tree_update_scroll resolves ordinary scrolling against current animated content extent.
tree_update_scroll :: proc(
    params: Tree_List_Params,
    content_height: f32) -> uiwidgets.Scroll_Container_Update_Result {
    return uiwidgets.scroll_container_update({id = UI_TREE_SCROLLBAR_ID,
        rect = params.list_panel, scroll_y_in = params.scroll_y^,
        content_height = content_height, mouse_input = params.mouse_input,
        interaction_space_rect = params.list_panel,
        wheel_step = theme.TREE_ROW_HEIGHT * theme.WHEEL_SCROLL_MULTIPLIER,
        press_owner = &params.ui_runtime^.input.press_owner,
        state_in = {params.ui_runtime^.library.tree.scroll_dragging,
            params.ui_runtime^.library.tree.scroll_drag_off},
        semantic_focus = params.ui_runtime^.semantic_focus,
        semantic_id = tree_semantic_id()})
}

// tree_refresh_preparation keeps range, visual height, and scrollbar aligned after toggling.
tree_refresh_preparation :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    visual := uiwidgets.scroll_container_visual(params.list_panel,
        prepared^.layout.content_height, params.scroll_y^,
        theme.TREE_ROW_HEIGHT * theme.WHEEL_SCROLL_MULTIPLIER)
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
    ctx := Tree_Walk_Context{
        ji = params.ji,
        tree = &params.ui_runtime^.library.tree,
        interaction = &params.ui_runtime^.input,
        panel = prepared^.scroll.view_rect, scroll_y = prepared^.scroll.scroll_y_out,
        allow_clicks = !prepared^.scroll.pointer_reserved,
        mouse_input = params.mouse_input, font = params.font,
        font_resolver = params.font_resolver,
        visibility = {search = params.visibility.search,
            projection = &params.ui_runtime^.library.tree.projection}}
    tree_actions_cancel_hidden_capture(params, prepared)
    foreground := tree_reorder_foreground(
        &params.ui_runtime^.library.actions.reorder, &prepared^.layout)
    foreground_hit := false
    if foreground >= 0 {
        block := tree_reorder_block_clip(prepared^.layout.rows[foreground],
            ctx.panel, ctx.scroll_y)
        foreground_hit = geometry.rectangle_contains(
            block, uiwidgets.input_frame_mouse_position(params.mouse_input))
    }
    for index in 0..<prepared^.layout.count {
        if foreground_hit && index != foreground {
            if params.ui_runtime^.input.press_owner.kind == .List_Item &&
                params.ui_runtime^.input.press_owner.id ==
                    tree_placement_press_id(prepared^.layout.rows[index].item) {
                params.ui_runtime^.input.press_owner = {}
            }
            continue
        }
        tree_update_prepared_row(params, ctx, &prepared^.layout.rows[index], &hit)
    }
    return hit
}

// tree_update_prepared_row keeps row capture and drawer admission on the same viewport.
tree_update_prepared_row :: proc(
    params: Tree_List_Params, ctx: Tree_Walk_Context,
    row: ^Tree_Prepared_Row, hit: ^Tree_Hit) {
    row_geometry := tree_row_screen_geometry(row^, ctx.panel, ctx.scroll_y)
    clip := geometry.Rectangle(row_geometry.clip_bounds)
    owns := params.ui_runtime^.input.press_owner.active &&
        params.ui_runtime^.input.press_owner.kind == .List_Item &&
        params.ui_runtime^.input.press_owner.id == tree_placement_press_id(row^.item)
    admitted := tree_row_is_revealed(row^) &&
        geometry.rectangles_intersect(geometry.Rectangle(row_geometry.bounds), clip)
    if owns &&
       (!admitted || uiwidgets.input_frame_left_released(params.mouse_input) &&
        !geometry.rectangle_contains(clip,
            uiwidgets.input_frame_mouse_position(params.mouse_input))) {
        params.ui_runtime^.input.press_owner = {}
    }
    tree_actions_prepare_controls(params, row, ctx, hit)
    if !admitted {
        return
    }
    current := ctx
    current.interaction_space_rect = clip
    update_tree_node_row(current, row^.item, row^.depth,
        geometry.Rectangle(row_geometry.bounds), hit)
}

// tree_cancel_hidden_capture releases rows removed or clipped by an immediate topology change.
tree_cancel_hidden_capture :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    owner := params.ui_runtime^.input.press_owner
    if !owner.active || owner.kind != .List_Item {
        return
    }
    for row in prepared^.layout.rows[:prepared^.layout.count] {
        if owner.id != tree_placement_press_id(row.item) || !tree_row_is_revealed(row) {
            continue
        }
        bounds := tree_row_screen_geometry(
            row, prepared^.scroll.view_rect, prepared^.scroll.scroll_y_out)
        if geometry.rectangles_intersect(
            geometry.Rectangle(bounds.bounds), geometry.Rectangle(bounds.clip_bounds)) {
            return
        }
    }
    params.ui_runtime^.input.press_owner = {}
}

// tree_motion_anchor stores the initiating parent's screen offset, not child visibility.
tree_motion_anchor :: proc(
    params: Tree_List_Params,
    item: ^viewmodel.Ui_Tree_Item,
    layout: ^Tree_Prepared_Layout) {
    row := tree_layout_find_item(layout, item)
    if row == nil || !row^.logical {
        return
    }
    motion := &params.ui_runtime^.library.motion
    motion^.anchor_id = item^.key
    motion^.anchor_view_y = row^.content_y - params.scroll_y^
    motion^.anchored = true
}

// tree_motion_anchor_action samples before any addressed structural mutation.
tree_motion_anchor_action :: proc(
    params: Tree_List_Params,
    item: ^viewmodel.Ui_Tree_Item,
    kind: viewmodel.Ui_Focus_Command_Kind) {
    changes := kind == .Toggle || kind == .Expand && !item^.expanded ||
        kind == .Collapse && item^.expanded ||
        kind == .Tree_Parent && item^.expanded ||
        kind == .Tree_Child && !item^.expanded
    if changes && item^.first_child != TREE_NO_ITEM {
        layout: Tree_Prepared_Layout
        tree_prepare_layout(params, &layout)
        tree_motion_anchor(params, item, &layout)
    }
}

// tree_motion_settle_navigation finishes only the ancestors needed by the requested row.
tree_motion_settle_navigation :: proc(params: Tree_List_Params) {
    runtime := params.ui_runtime
    if !runtime^.library.tree.reveal_pending ||
       runtime^.library.tree.reveal_reason != .Navigation {
        return
    }
    projection := &runtime^.library.tree.projection
    target_index := tree_projection_find(
        projection, runtime^.library.tree.reveal_stable_id)
    if target_index == TREE_NO_ITEM {
        return
    }
    for parent, steps := projection^.items[target_index].parent, 0;
        parent != TREE_NO_ITEM && steps < projection^.count;
        parent, steps = projection^.items[parent].parent, steps + 1 {
        projection^.items[parent].expanded = true
        index := tree_motion_index(
            &runtime^.library.motion, projection^.items[parent].key)
        runtime^.library.motion.branches[index].expanded = true
        runtime^.library.motion.branches[index].height =
            runtime^.library.motion.branches[index].full_height
        runtime^.library.motion.branches[index].running = false
    }
}

// tree_apply_visual_reveal honors keyboard/external reveal using fractional visual positions.
tree_apply_visual_reveal :: proc(
    params: Tree_List_Params, layout: ^Tree_Prepared_Layout) {
    runtime := params.ui_runtime
    if !runtime^.library.tree.reveal_pending {
        return
    }
    target_index := tree_projection_find(
        &runtime^.library.tree.projection, runtime^.library.tree.reveal_stable_id)
    target := &runtime^.library.tree.projection.items[target_index] if
        target_index != TREE_NO_ITEM else nil
    row := tree_layout_find_item(layout, target)
    if row == nil || !tree_row_is_revealed(row^) {
        return
    }
    maximum := max(layout^.content_height - params.list_panel.height, 0)
    scroll := clamp(params.scroll_y^, 0, maximum)
    if row^.content_y < scroll {
        scroll = row^.content_y
    } else if row^.content_y + theme.TREE_ROW_HEIGHT > scroll + params.list_panel.height {
        scroll = row^.content_y + theme.TREE_ROW_HEIGHT - params.list_panel.height
    }
    params.scroll_y^ = clamp(scroll, 0, maximum)
    runtime^.library.tree.reveal_pending = false
    motion := &runtime^.library.motion
    motion^.anchored = motion^.anchored && motion^.anchor_id == row^.item^.key
    if motion^.anchored {
        motion^.anchor_view_y = row^.content_y - params.scroll_y^
    }
    runtime^.library.tree.scroll_dragging = false
    runtime^.library.tree.scroll_drag_off = 0
    if uiwidgets.scroll_container_owns_press(
       &runtime^.input.press_owner, UI_TREE_SCROLLBAR_ID) {
        runtime^.input.press_owner = {}
    }
}

// tree_motion_apply_anchor defers to explicit wheel/drag input and ordinary row reveal.
tree_motion_apply_anchor :: proc(
    params: Tree_List_Params, layout: ^Tree_Prepared_Layout) {
    motion := &params.ui_runtime^.library.motion
    if params.mouse_input.mouse_wheel_delta != 0 ||
       params.ui_runtime^.library.tree.scroll_dragging {
        motion^.anchored = false
    }
    if !motion^.anchored {
        return
    }
    for row in layout^.rows[:layout^.count] {
        if row.item^.key == motion^.anchor_id && row.logical {
            params.scroll_y^ = clamp(row.content_y - motion^.anchor_view_y,
                0, max(layout^.content_height - params.list_panel.height, 0))
            return
        }
    }
    motion^.anchored = false
}

// tree_motion_release_anchor prevents compensation from competing with ordinary scrolling.
tree_motion_release_anchor :: proc(
    params: Tree_List_Params, scroll: uiwidgets.Scroll_Container_Update_Result) {
    if scroll.changed || scroll.pointer_reserved || scroll.wheel_consumed ||
        !tree_motion_running(&params.ui_runtime^.library.motion) {
        params.ui_runtime^.library.motion.anchored = false
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
prepare_tree_visual :: proc(
    params: Tree_List_Params,
    prepared: ^Tree_List_Preparation) {
    prepared^ = {}
    tree_actions_close_context(params.ui_runtime)
    if params.ji == nil ||
        params.ji^.animation_count == 0 &&
            (params.collections == nil || params.collections^.entry_count == 0) {
        params.ui_runtime^.library.motion = {}
        return
    }
    if !tree_projection_prepare(params) {
        log.error("library_tree_projection_rejected")
        return
    }
    frame := tree_frame_context(params)
    tree_motion_reset(frame.geometry, frame.admission)
    tree_prepare_layout(params, &prepared^.layout)
    prepared^.content_height = prepared^.layout.content_height
    prepared^.scroll = uiwidgets.scroll_container_visual(params.list_panel,
        prepared^.layout.content_height, params.scroll_y^,
        theme.TREE_ROW_HEIGHT * theme.WHEEL_SCROLL_MULTIPLIER)
}
