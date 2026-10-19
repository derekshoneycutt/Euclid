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
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) ->
        ^viewmodel.Ui_Tree_Prepared_Row {
    for index in 0..<layout^.count {
        if node != nil &&
            layout^.rows[index].item^.target_animation_id == node^.stable_id {
            return &layout^.rows[index]
        }
    }
    return nil
}

// tree_layout_find_item resolves a prepared row by its display-owned placement.
tree_layout_find_item :: proc(
    layout: ^viewmodel.Ui_Tree_Prepared_Layout,
    item: ^viewmodel.Ui_Tree_Item) -> ^viewmodel.Ui_Tree_Prepared_Row {
    for index in 0..<layout^.count {
        if layout^.rows[index].item == item {
            return &layout^.rows[index]
        }
    }
    return nil
}

// tree_row_is_revealed excludes rows beyond the inherited descendant reveal.
tree_row_is_revealed :: proc(row: viewmodel.Ui_Tree_Prepared_Row) -> bool {
    return row.logical && geometry.rectangles_intersect(
        {0, row.content_y, row.reveal.width, tree_prepared_row_height(row)},
        row.reveal)
}

// Resolve a retained row height while preserving legacy base-sized test fixtures.
tree_prepared_row_height :: #force_inline proc(
    row: viewmodel.Ui_Tree_Prepared_Row) -> f32 {
    return theme.TREE_ROW_HEIGHT if row.row_height <= 0 else row.row_height
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
        row_height = theme.ui_tree_row_height(
            state^.ui_runtime.preferences.values.interface.text_size_percent),
        pressed_node = prepared^.pressed_node,
        entry_name_input = &prepared^.entry_name_input,
        entry_name_params = &prepared^.entry_name_params,
        entry_name_prepared = prepared^.entry_name_prepared,
        actions_toggle = prepared^.actions_toggle,
        actions_up = prepared^.actions_up,
        actions_down = prepared^.actions_down,
        scroll_y = prepared^.scroll.scroll_y_out,
        visibility = visibility}
    foreground := tree_reorder_foreground(
        &state^.ui_runtime.library.actions.reorder, &prepared^.layout)
    occlusion: geometry.Rectangle
    if foreground >= 0 {
        occlusion = tree_reorder_block_clip(
            prepared^.layout.rows[foreground], panel, prepared^.scroll.scroll_y_out)
    }
    ctx.reorder_foreground_index = foreground
    ctx.reorder_occlusion = occlusion
    for index in 0..<prepared^.layout.count {
        row := prepared^.layout.rows[index]
        tree_draw_prepared_row(ctx, row, index, text)
    }

}

// tree_draw_prepared_row omits fully clipped rows and preserves reorder occlusion.
tree_draw_prepared_row :: proc(
    ctx: Encoded_Tree_Walk_Context, row: viewmodel.Ui_Tree_Prepared_Row,
    index: int, text: bool) {
    row_geometry := tree_row_screen_geometry(row, ctx.panel, ctx.scroll_y)
    bounds := geometry.Rectangle(row_geometry.bounds)
    clip := geometry.Rectangle(row_geometry.clip_bounds)
    drawer := tree_actions_screen_rect(row.actions.drawer_rect, ctx.panel, ctx.scroll_y)
    if !geometry.rectangles_intersect(bounds, clip) &&
        !(row.actions.height > 0 && geometry.rectangles_intersect(drawer, clip)) {
        return
    }
    tree_draw_reorder_layer(ctx, row, row_geometry, text,
        {} if index == ctx.reorder_foreground_index else ctx.reorder_occlusion)
}

// tree_draw_reorder_layer clips background geometry and text around the opaque moving block.
tree_draw_reorder_layer :: proc(
    ctx: Encoded_Tree_Walk_Context, row: viewmodel.Ui_Tree_Prepared_Row,
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
    ctx: Encoded_Tree_Walk_Context, row: viewmodel.Ui_Tree_Prepared_Row,
    row_geometry: viewmodel.Ui_Control_Geometry, text: bool) {
    bounds := row_geometry.bounds
    clip := row_geometry.clip_bounds
    _ = native.draw_encoder_push_scissor(ctx.encoder, clip)
    if text {
        draw_encoded_prepared_tree_label(ctx, row, row_geometry)
        draw_encoded_tree_actions_text(
            ctx.state, ctx.encoder, row, ctx.panel, ctx.scroll_y)
    } else {
        current := ctx
        current.render_only = !row.logical
        draw_encoded_tree_row(current, row.item, row.depth, bounds.y, row.expanded)
        draw_encoded_tree_actions_geometry(ctx, row)
        tree_actions_draw_focus(
            ctx.encoder, &ctx.state^.ui_runtime, row, ctx.panel, ctx.scroll_y)
    }
    _ = native.draw_encoder_pop_scissor(ctx.encoder)
}

// Draw the accepted label or active editor within its row's inherited clip.
draw_encoded_prepared_tree_label :: proc(
    ctx: Encoded_Tree_Walk_Context, row: viewmodel.Ui_Tree_Prepared_Row,
    row_geometry: viewmodel.Ui_Control_Geometry) {
    bounds := row_geometry.bounds
    label_clip := tree_actions_label_clip(
        row.actions, bounds, row_geometry.clip_bounds)
    if !geometry.rectangles_intersect(label_clip, row_geometry.clip_bounds) {
        return
    }
    _ = native.draw_encoder_push_scissor(ctx.encoder, label_clip)
    if ctx.entry_name_prepared && row.logical &&
        row.item^.key == ctx.state^.ui_runtime.library.entry_name.entry_id {
        uiwidgets.draw_encoded_input_box(ctx.encoder,
            ctx.entry_name_params^, ctx.entry_name_input^)
    } else {
        selected := ctx.state^.ui_runtime.library.tree.selected_item_id == row.item^.key
        tint := theme.draw_color(ctx.encoder, .Tree_Text) if
            selected else theme.draw_color(ctx.encoder, .Text)
        text_percent :=
            ctx.state^.ui_runtime.preferences.values.interface.text_size_percent
        viewtext.draw_encoded_colored_label(&ctx.state^.font_cache, ctx.encoder,
            tree_item_label(ctx.ji, row.item,
                &ctx.state^.preferences_runtime.collections_state),
            {bounds.x + f32(row.depth) *
                theme.ui_scaled_metric(theme.TREE_INDENT, text_percent) +
                theme.ui_scaled_metric(theme.TREE_ROW_LABEL_OFFSET_X,
                    text_percent),
             bounds.y + theme.ui_scaled_metric(
                theme.TREE_ROW_LABEL_OFFSET_Y, text_percent)}, tint)
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
        wheel_step = theme.ui_tree_row_height(
            params.ui_runtime^.preferences.values.interface.text_size_percent) *
            theme.WHEEL_SCROLL_MULTIPLIER,
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
        theme.ui_tree_row_height(
            params.ui_runtime^.preferences.values.interface.text_size_percent) *
        theme.WHEEL_SCROLL_MULTIPLIER)
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
        panel = prepared^.scroll.view_rect,
        row_height = theme.ui_tree_row_height(
            params.ui_runtime^.preferences.values.interface.text_size_percent),
        scroll_y = prepared^.scroll.scroll_y_out,
        allow_clicks = !prepared^.scroll.pointer_reserved,
        mouse_input = params.mouse_input, font = params.font,
        font_resolver = params.font_resolver,
        visibility = {search = params.visibility.search,
            projection = &params.ui_runtime^.library.tree.projection}}
    tree_actions_cancel_hidden_capture(params, prepared)
    foreground := tree_reorder_foreground(
        &params.ui_runtime^.library.actions.reorder, &prepared^.layout)
    foreground_hit := tree_reorder_foreground_hit(params, ctx, prepared, foreground)
    for index in 0..<prepared^.layout.count {
        if foreground_hit && index != foreground {
            continue
        }
        tree_update_prepared_row(
            params, ctx, &prepared^.layout.rows[index], prepared, &hit)
    }
    return hit
}

// tree_reorder_foreground_hit suppresses pointer updates behind the moving row.
tree_reorder_foreground_hit :: proc(
    params: Tree_List_Params, ctx: Tree_Walk_Context,
    prepared: ^Tree_List_Preparation, foreground: int) -> bool {
    if foreground < 0 {
        return false
    }
    block := tree_reorder_block_clip(prepared^.layout.rows[foreground],
        ctx.panel, ctx.scroll_y)
    hit := geometry.rectangle_contains(
        block, uiwidgets.input_frame_mouse_position(params.mouse_input))
    if hit {
        tree_cancel_occluded_row_capture(params, prepared, foreground)
    }
    return hit
}

// tree_cancel_occluded_row_capture retires captures hidden by the moving foreground.
tree_cancel_occluded_row_capture :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation, foreground: int) {
    owner := params.ui_runtime^.input.press_owner
    if owner.kind != .List_Item {
        return
    }
    for index in 0..<prepared^.layout.count {
        if index != foreground &&
            owner.id == tree_placement_press_id(prepared^.layout.rows[index].item) {
            params.ui_runtime^.input.press_owner = {}
            return
        }
    }
}

// tree_update_prepared_row keeps row capture and drawer admission on the same viewport.
tree_update_prepared_row :: proc(
    params: Tree_List_Params, ctx: Tree_Walk_Context,
    row: ^viewmodel.Ui_Tree_Prepared_Row, prepared: ^Tree_List_Preparation,
    hit: ^Tree_Hit) {
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
    tree_actions_prepare_controls(params, row, prepared, ctx, hit)
    if tree_prepare_entry_name_input(params, ctx, row, prepared) {
        return
    }
    if !admitted {
        return
    }
    current := ctx
    current.interaction_space_rect = clip
    update_tree_node_row(current, row^.item, row^.depth,
        geometry.Rectangle(row_geometry.bounds), hit)
}

// tree_prepare_entry_name_input edits only the selected logical row's prepared field.
tree_prepare_entry_name_input :: proc(
    params: Tree_List_Params, ctx: Tree_Walk_Context,
    row: ^viewmodel.Ui_Tree_Prepared_Row, prepared: ^Tree_List_Preparation) -> bool {
    runtime := params.ui_runtime
    draft := &runtime^.library.entry_name
    if !draft^.active || draft^.entry_id != row^.item^.key ||
        runtime^.library.tree.selected_item_id != row^.item^.key ||
        !row^.logical || !row^.actions.eligible || !row^.actions.open ||
        params.visibility.search != nil && params.visibility.search^.active {
        return false
    }
    input_geometry := tree_entry_name_input_geometry(params, ctx, row^)
    rect, clip := input_geometry.rect, input_geometry.clip
    if rect.width <= 0 || clip.width <= 0 || clip.height <= 0 {
        return false
    }
    draft^.rect = rect
    draft^.clip_rect = clip
    input_params := library_entry_name_input_params(
        params, row^.item^.key, rect, clip, params.mouse_input)
    result := uiwidgets.input_box_prepare(
        input_params, &runtime^.input.press_owner)
    prepared^.entry_name_input = result
    prepared^.entry_name_params = input_params
    prepared^.entry_name_prepared = true
    return tree_apply_prepared_entry_name_input(params, prepared)
}

// tree_apply_prepared_entry_name_input commits editor changes and frame-local draw state.
tree_apply_prepared_entry_name_input :: proc(
    params: Tree_List_Params,
    prepared: ^Tree_List_Preparation) -> bool {
    runtime := params.ui_runtime
    draft := &runtime^.library.entry_name
    result := &prepared^.entry_name_input
    prepared^.entry_name_params.descriptor = result^.descriptor
    if result^.changed {
        _ = library_entry_name_edit(params.general_state, draft^.entry_id,
            string(draft^.value[:draft^.value_length]))
    }
    if result^.submit_requested {
        _ = library_entry_name_flush(params.general_state, draft^.entry_id)
    }
    if result^.hovered {
        runtime^.input.cursor = .Text
    }
    return result^.hovered
}

// tree_entry_name_input_geometry derives shared clipped bounds for the inline field.
tree_entry_name_input_geometry :: proc(
    params: Tree_List_Params, ctx: Tree_Walk_Context,
    row: viewmodel.Ui_Tree_Prepared_Row) -> Tree_Entry_Name_Input_Geometry {
    row_geometry := tree_row_screen_geometry(row, ctx.panel, ctx.scroll_y)
    rect := geometry.Rectangle{row_geometry.bounds.x + row.actions.label_clip.x,
        row_geometry.bounds.y, row.actions.label_clip.width, row_geometry.bounds.height}
    clip := tree_actions_label_clip(
        row.actions, row_geometry.bounds, row_geometry.clip_bounds)
    return {rect = rect, clip = clip}
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
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
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
        layout: viewmodel.Ui_Tree_Prepared_Layout
        if !tree_prepare_layout_scratch(params, &layout) {
            return
        }
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
    params: Tree_List_Params, layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
    runtime := params.ui_runtime
    if !runtime^.library.tree.reveal_pending {
        return
    }
    target_index := tree_projection_find(
        &runtime^.library.tree.projection, runtime^.library.tree.reveal_stable_id)
    target := runtime^.library.tree.projection.items[target_index] if
        target_index != TREE_NO_ITEM else nil
    row := tree_layout_find_item(layout, target)
    if row == nil || !tree_row_is_revealed(row^) {
        return
    }
    maximum := max(layout^.content_height - params.list_panel.height, 0)
    scroll := clamp(params.scroll_y^, 0, maximum)
    if row^.content_y < scroll {
        scroll = row^.content_y
    } else if row^.content_y + tree_prepared_row_height(row^) >
        scroll + params.list_panel.height {
        scroll = row^.content_y + tree_prepared_row_height(row^) -
            params.list_panel.height
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
    params: Tree_List_Params, layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
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
    if !tree_actions_close_context(params.ui_runtime, params.general_state) {
        return
    }
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
    params.ui_runtime^.library.motion.initialized = false
    if !tree_prepare_layout(params, &prepared^.layout) {
        log.error("library_tree_layout_rejected")
        return
    }
    prepared^.content_height = prepared^.layout.content_height
    prepared^.scroll = uiwidgets.scroll_container_visual(params.list_panel,
        prepared^.layout.content_height, params.scroll_y^,
        theme.ui_tree_row_height(
            params.ui_runtime^.preferences.values.interface.text_size_percent) *
        theme.WHEEL_SCROLL_MULTIPLIER)
}
