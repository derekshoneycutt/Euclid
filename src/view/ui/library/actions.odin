package uilibrary

import core "../../../core"
import collections "../../../collections"
import geometry "../../../core/geometry"
import native "../../native"
import theme "../theme"
import uiaccordion "../layout/accordion"
import uiwidgets "../widgets"
import viewmodel "../model"
import viewpreferences "../../preferences"
import viewtext "../text"
import viewmessages "../../messages"
import log "core:log"
import uuid "core:encoding/uuid"

TREE_ACTION_CONTROL_ID_BASE :: -100000
TREE_ACTION_DRAWER_PADDING :: f32(4)
TREE_ACTION_BUTTON_GAP :: f32(4)
TREE_ACTION_BUTTON_HEIGHT :: f32(24)
TREE_ACTION_HORIZONTAL_MIN_WIDTH :: f32(190)
TREE_ACTION_TOGGLE_WIDTH :: f32(22)
TREE_ACTION_DRAWER_MIN_HEIGHT :: f32(32)

Tree_Actions_Layout :: struct {
    eligible: bool,
    open: bool,
    height: f32,
    toggle_rect: geometry.Rectangle,
    label_clip: geometry.Rectangle,
    drawer_rect: geometry.Rectangle,
    move_up_rect: geometry.Rectangle,
    move_down_rect: geometry.Rectangle,
    move_up_enabled: bool,
    move_down_enabled: bool,
    toggle_id: int,
    move_up_id: int,
    move_down_id: int,
}

// tree_actions_cancel_context_capture releases only action-widget press ownership.
tree_actions_cancel_context_capture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if runtime^.input.press_owner.active &&
        tree_actions_control_id_owned(runtime^.input.press_owner.id) {
        runtime^.input.press_owner = {}
    }
}

// tree_actions_close_context discards drawer state and cancels its owned gesture.
tree_actions_close_context :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if runtime == nil {
        return
    }
    if runtime^.input.press_owner.active &&
        tree_actions_control_id_owned(runtime^.input.press_owner.id) {
        runtime^.input.press_owner = {}
    }
    tree_actions_repair_context_focus(runtime)
    runtime^.library.actions.drawer = {}
    runtime^.library.actions.reorder = {}
    runtime^.library.actions.press_entry = {}
}

// tree_actions_eligible admits only the selected Favorites placement in its visible path.
tree_actions_eligible :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    selected_item_id: uuid.Identifier,
    search_active: bool,
    item: ^viewmodel.Ui_Tree_Item) -> bool {
    if item == nil || item^.kind != .Placement ||
        item^.key != selected_item_id || search_active {
        return false
    }
    parent := item^.parent
    if parent == TREE_NO_ITEM || parent < 0 || parent >= projection^.count {
        return false
    }
    collection := projection^.items[parent]
    return collection.kind == .Collection &&
        collection.key == collections.FAVORITES_COLLECTION_ID &&
        tree_actions_ancestors_expanded(projection, parent)
}

// tree_actions_ancestors_expanded rejects controls hidden by either collection branch.
tree_actions_ancestors_expanded :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, index: int) -> bool {
    for parent, steps := index, 0;
        parent != TREE_NO_ITEM && steps < projection^.count;
        parent, steps = projection^.items[parent].parent, steps + 1 {
        if !projection^.items[parent].expanded {
            return false
        }
    }
    return true
}

// tree_actions_reconcile closes an owner that no longer matches current UI context.
tree_actions_reconcile :: proc(params: Tree_List_Params) {
    runtime := params.ui_runtime
    if runtime^.input.press_owner.active &&
        tree_actions_control_id_owned(runtime^.input.press_owner.id) &&
        runtime^.library.actions.press_entry != runtime^.library.tree.selected_item_id {
        tree_actions_cancel_context_capture(runtime)
    }
    motion := &runtime^.library.actions.drawer
    if motion^.entry_id == (uuid.Identifier{}) {
        return
    }
    owner := tree_projection_find(&runtime^.library.tree.projection, motion^.entry_id)
    if owner == TREE_NO_ITEM ||
        !tree_actions_eligible(
            &runtime^.library.tree.projection,
            runtime^.library.tree.selected_item_id,
            params.visibility.search != nil && params.visibility.search^.active,
            &runtime^.library.tree.projection.items[owner]) {
        tree_actions_close_context(runtime)
        return
    }
    if params.general_state != nil &&
        params.general_state^.ui_runtime.layout.active_accordion_section != .Library {
        tree_actions_close_context(runtime)
    }
}

// tree_actions_full_height chooses one bounded button arrangement for this pane width.
tree_actions_full_height :: proc(panel_width: f32, depth: int) -> f32 {
    label_x := f32(depth) * theme.TREE_INDENT + theme.TREE_ROW_LABEL_OFFSET_X
    available := max(panel_width - label_x - TREE_ACTION_DRAWER_PADDING, 0)
    if available >= TREE_ACTION_HORIZONTAL_MIN_WIDTH {
        return TREE_ACTION_DRAWER_MIN_HEIGHT
    }
    return TREE_ACTION_BUTTON_HEIGHT * 2 + TREE_ACTION_BUTTON_GAP +
        TREE_ACTION_DRAWER_PADDING * 2
}

// tree_actions_current_height returns sampled drawer extent for one owner identity.
tree_actions_current_height :: proc(
    motion: ^viewmodel.Ui_Tree_Actions_Motion,
    key: uuid.Identifier) -> f32 {
    if motion^.entry_id == key {
        return motion^.height
    }
    return 0
}

// tree_actions_sample advances the selected drawer using the shared disclosure policy.
tree_actions_sample :: proc(
    ctx: Tree_Geometry_Context, item: ^viewmodel.Ui_Tree_Item) -> f32 {
    motion := ctx.drawer
    if motion^.entry_id != item^.key {
        return 0
    }
    target := tree_actions_full_height(
        ctx.panel.width, tree_item_depth(ctx.projection, item))
    if !motion^.open {
        target = 0
    }
    if !motion^.running {
        motion^.height = target
    } else {
        ease := uiaccordion.interface_motion_ease(
            motion^.start_seconds, ctx.now_seconds)
        motion^.height = clamp(motion^.start_height +
            (target - motion^.start_height) * ease, 0, max(target, motion^.start_height))
        if ctx.now_seconds >=
            motion^.start_seconds + uiaccordion.INTERFACE_TRANSITION_SECONDS {
            motion^.height = target
            motion^.running = false
        }
    }
    if !motion^.open && !motion^.running && motion^.height <= 0 {
        motion^ = {}
        return 0
    }
    return motion^.height
}

// tree_item_depth resolves one bounded item's indentation from its projection chain.
tree_item_depth :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    item: ^viewmodel.Ui_Tree_Item) -> int {
    depth := 0
    for parent, steps := item^.parent, 0;
        parent != TREE_NO_ITEM && steps < projection^.count;
        parent, steps = projection^.items[parent].parent,
            steps + 1 {
        depth += 1
    }
    return depth
}

// tree_actions_toggle starts or reverses motion only for the current selected entry.
tree_actions_toggle :: proc(params: Tree_List_Params, entry_id: uuid.Identifier) {
    index := tree_projection_find(&params.ui_runtime^.library.tree.projection, entry_id)
    if index == TREE_NO_ITEM ||
        !tree_actions_eligible(
            &params.ui_runtime^.library.tree.projection,
            params.ui_runtime^.library.tree.selected_item_id,
            params.visibility.search != nil && params.visibility.search^.active,
            &params.ui_runtime^.library.tree.projection.items[index]) {
        return
    }
    motion := &params.ui_runtime^.library.actions.drawer
    if motion^.entry_id != entry_id {
        motion^ = {entry_id = entry_id}
    }
    motion^.open = !motion^.open
    motion^.start_height = motion^.height
    motion^.start_seconds = params.mouse_input.sample_time_seconds
    motion^.running = !params.reduce_motion
    if !motion^.open {
        params.ui_runtime^.library.actions.reorder = {}
        tree_actions_focus_toggle(params, entry_id)
    }
}

// tree_actions_layout prepares shared content-space geometry for every consumer.
tree_actions_layout :: proc(
    ctx: Tree_Geometry_Context, item: ^viewmodel.Ui_Tree_Item,
    depth: int, content_y: f32) -> Tree_Actions_Layout {
    result: Tree_Actions_Layout
    if !tree_actions_eligible(
        ctx.projection, ctx.selected_item_id, ctx.search_active, item) {
        return result
    }
    result.eligible = true
    item_index := tree_projection_find(ctx.projection, item^.key)
    result.toggle_id = tree_actions_control_id(item_index, 0)
    result.toggle_rect = {ctx.panel.width - TREE_ACTION_TOGGLE_WIDTH,
        content_y, TREE_ACTION_TOGGLE_WIDTH, theme.TREE_ROW_HEIGHT}
    label_x := f32(depth) * theme.TREE_INDENT + theme.TREE_ROW_LABEL_OFFSET_X
    result.label_clip = {label_x, content_y,
        max(result.toggle_rect.x - label_x, 0), theme.TREE_ROW_HEIGHT}
    if ctx.drawer.entry_id != item^.key || ctx.drawer.height <= 0 {
        return result
    }
    result.open = ctx.drawer.open
    result.height = ctx.drawer.height
    result.drawer_rect = {0, content_y + theme.TREE_ROW_HEIGHT,
        ctx.panel.width, ctx.drawer.height}
    tree_actions_layout_buttons(ctx.collections, ctx.projection, item, &result)
    return result
}

// tree_actions_layout_buttons prepares responsive action rectangles and endpoint states.
tree_actions_layout_buttons :: proc(
    collections: ^collections.Set,
    projection: ^viewmodel.Ui_Tree_Projection,
    item: ^viewmodel.Ui_Tree_Item,
    layout: ^Tree_Actions_Layout) {
    available := max(layout^.drawer_rect.width - layout^.label_clip.x -
        TREE_ACTION_DRAWER_PADDING, 0)
    inner := geometry.Rectangle{
        layout^.label_clip.x + TREE_ACTION_DRAWER_PADDING,
        layout^.drawer_rect.y + TREE_ACTION_DRAWER_PADDING,
        max(available - TREE_ACTION_DRAWER_PADDING * 2, 0),
        TREE_ACTION_BUTTON_HEIGHT}
    if available >= TREE_ACTION_HORIZONTAL_MIN_WIDTH {
        width := (inner.width - TREE_ACTION_BUTTON_GAP) * 0.5
        layout^.move_up_rect = {inner.x, inner.y, width, inner.height}
        layout^.move_down_rect = {inner.x + width + TREE_ACTION_BUTTON_GAP,
            inner.y, width, inner.height}
    } else {
        layout^.move_up_rect = inner
        layout^.move_down_rect = {inner.x,
            inner.y + TREE_ACTION_BUTTON_HEIGHT + TREE_ACTION_BUTTON_GAP,
            inner.width, TREE_ACTION_BUTTON_HEIGHT}
    }
    layout^.move_up_enabled = tree_actions_neighbor_exists(
        collections, item^.key, .Up)
    layout^.move_down_enabled = tree_actions_neighbor_exists(
        collections, item^.key, .Down)
    item_index := tree_projection_find(
        projection, item^.key)
    layout^.move_up_id = tree_actions_control_id(item_index, 1)
    layout^.move_down_id = tree_actions_control_id(item_index, 2)
}

// tree_actions_neighbor_exists derives disabled state from the authoritative sibling model.
tree_actions_neighbor_exists :: proc(
    set: ^collections.Set, entry_id: uuid.Identifier,
    direction: collections.Move_Direction) -> bool {
    if set == nil {
        return false
    }
    _, failure := collections.sibling_neighbor(set, entry_id, direction)
    return failure == .None
}

// tree_actions_control_id assigns each current projection slot a distinct gesture identity.
tree_actions_control_id :: #force_inline proc(index, action: int) -> int {
    return TREE_ACTION_CONTROL_ID_BASE - index * 3 - action
}

// tree_actions_control_id_owned identifies the bounded ID band reserved for this drawer.
tree_actions_control_id_owned :: #force_inline proc(id: int) -> bool {
    return id <= TREE_ACTION_CONTROL_ID_BASE &&
        id >= TREE_ACTION_CONTROL_ID_BASE -
            viewmodel.UI_TREE_NODE_CAPACITY * 3 - 2
}

// tree_actions_label_clip returns the reserved-name area in screen coordinates.
tree_actions_label_clip :: proc(
    layout: Tree_Actions_Layout, bounds,
    clip: geometry.Rectangle) -> geometry.Rectangle {
    if !layout.eligible {
        return bounds
    }
    return tree_reveal_intersection({bounds.x + layout.label_clip.x,
        bounds.y, layout.label_clip.width, bounds.height}, clip)
}

// tree_actions_screen_rect translates content-space control geometry after scrolling.
tree_actions_screen_rect :: #force_inline proc(
    rect, panel: geometry.Rectangle, scroll_y: f32) -> geometry.Rectangle {
    return {panel.x + rect.x, panel.y + rect.y - scroll_y, rect.width, rect.height}
}

// tree_actions_screen_clip clips controls to drawer extent, ancestry, and viewport.
tree_actions_screen_clip :: proc(
    row: Tree_Prepared_Row, panel: geometry.Rectangle, scroll_y: f32) ->
        geometry.Rectangle {
    drawer := tree_actions_screen_rect(row.actions.drawer_rect, panel, scroll_y)
    reveal := row.reveal
    reveal.x += panel.x
    reveal.y += panel.y - scroll_y
    reveal = tree_reveal_intersection(reveal, panel)
    return tree_reveal_intersection(drawer, reveal)
}

// tree_actions_prepare_controls resolves owned pointer gestures against prepared clips.
tree_actions_prepare_controls :: proc(
    params: Tree_List_Params, row: ^Tree_Prepared_Row,
    ctx: Tree_Walk_Context, hit: ^Tree_Hit) {
    if !row^.actions.eligible {
        return
    }
    row_geometry := tree_row_screen_geometry(row^, ctx.panel, ctx.scroll_y)
    toggle_clip := geometry.Rectangle(row_geometry.clip_bounds)
    toggle := tree_actions_screen_rect(row^.actions.toggle_rect, ctx.panel, ctx.scroll_y)
    row^.actions_toggle = uiwidgets.update_icon_button({
        id = row^.actions.toggle_id, rect = toggle, icon_id = .None,
        toggle = row^.actions.open, mouse = params.mouse_input,
        interaction_space_rect = toggle_clip,
        interaction_enabled = ctx.allow_clicks &&
            !params.ui_runtime^.library.tree.scroll_dragging,
        inset_scale = 1, semantics = {clip_bounds = toggle_clip},
    }, &params.ui_runtime^.input.press_owner)
    if row^.actions_toggle.clicked {
        hit^.actions_toggle_id = row^.item^.key
    }
    if params.ui_runtime^.input.press_owner.active &&
        params.ui_runtime^.input.press_owner.id == row^.actions.toggle_id {
        params.ui_runtime^.library.actions.press_entry = row^.item^.key
    }
    if !row^.actions.open {
        tree_actions_cancel_closed_capture(params.ui_runtime, row^.actions)
        return
    }
    tree_actions_prepare_move_buttons(params, row, ctx, hit)
}

// tree_actions_prepare_move_buttons hit tests the drawer's two ordinary text controls.
tree_actions_prepare_move_buttons :: proc(
    params: Tree_List_Params, row: ^Tree_Prepared_Row,
    ctx: Tree_Walk_Context, hit: ^Tree_Hit) {
    clip := tree_actions_screen_clip(row^, ctx.panel, ctx.scroll_y)
    tree_actions_cancel_clipped_capture(params.ui_runtime, row^.actions, clip)
    if clip.width <= 0 || clip.height <= 0 {
        return
    }
    up := tree_actions_screen_rect(row^.actions.move_up_rect, ctx.panel, ctx.scroll_y)
    down := tree_actions_screen_rect(row^.actions.move_down_rect, ctx.panel, ctx.scroll_y)
    row^.actions_up = uiwidgets.update_text_button(tree_actions_button_params(
        params, row^.actions.move_up_id, {up, clip},
        row^.actions.move_up_enabled, ctx.allow_clicks),
        &params.ui_runtime^.input.press_owner)
    row^.actions_down = uiwidgets.update_text_button(tree_actions_button_params(
        params, row^.actions.move_down_id, {down, clip},
        row^.actions.move_down_enabled, ctx.allow_clicks),
        &params.ui_runtime^.input.press_owner)
    if params.ui_runtime^.input.press_owner.active &&
        (params.ui_runtime^.input.press_owner.id == row^.actions.move_up_id ||
         params.ui_runtime^.input.press_owner.id == row^.actions.move_down_id) {
        params.ui_runtime^.library.actions.press_entry = row^.item^.key
    }
    if row^.actions_up.clicked {
        tree_actions_record_move(hit, row^.item^.key, .Up)
    } else if row^.actions_down.clicked {
        tree_actions_record_move(hit, row^.item^.key, .Down)
    }
}

// tree_actions_button_params keeps interaction geometry and disabled policy aligned.
tree_actions_button_params :: proc(
    params: Tree_List_Params, id: int,
    bounds: viewmodel.Ui_Control_Geometry, enabled: bool,
    allow_clicks: bool) -> uiwidgets.Text_Button_Params {
    return {
        id = id, rect = bounds.bounds, enabled = enabled,
        mouse = params.mouse_input, interaction_space_rect = bounds.clip_bounds,
        interaction_enabled = allow_clicks &&
        !params.ui_runtime^.library.tree.scroll_dragging &&
            enabled,
        font = params.font, font_resolver = params.font_resolver,
        semantics = {clip_bounds = bounds.clip_bounds},
    }
}

// tree_actions_record_move captures only the stable owner and typed direction.
tree_actions_record_move :: proc(
    hit: ^Tree_Hit, entry_id: uuid.Identifier,
    direction: collections.Move_Direction) {
    hit^.actions_move_id = entry_id
    hit^.actions_move_direction = direction
}

// tree_actions_cancel_closed_capture cancels controls as soon as closing begins.
tree_actions_cancel_closed_capture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, layout: Tree_Actions_Layout) {
    owner := runtime^.input.press_owner
    if owner.active && owner.kind == .Text_Button &&
        (owner.id == layout.move_up_id || owner.id == layout.move_down_id) {
        runtime^.input.press_owner = {}
    }
}

// tree_actions_cancel_clipped_capture prevents releases through a hidden drawer tail.
tree_actions_cancel_clipped_capture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    layout: Tree_Actions_Layout, clip: geometry.Rectangle) {
    owner := runtime^.input.press_owner
    if owner.active && owner.kind == .Text_Button &&
        (owner.id == layout.move_up_id || owner.id == layout.move_down_id) &&
        (clip.width <= 0 || clip.height <= 0) {
        runtime^.input.press_owner = {}
    }
}

// tree_actions_cancel_hidden_capture drops a gesture whose control left shared geometry.
tree_actions_cancel_hidden_capture :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    runtime := params.ui_runtime
    owner := runtime^.input.press_owner
    if !owner.active || owner.kind != .Icon_Button && owner.kind != .Text_Button {
        return
    }
    if prepared^.scroll.changed || prepared^.scroll.pointer_reserved ||
        prepared^.scroll.wheel_consumed {
        tree_actions_cancel_context_capture(runtime)
        return
    }
    for row in prepared^.layout.rows[:prepared^.layout.count] {
        if !tree_actions_capture_matches(owner, row.actions) {
            continue
        }
        if tree_actions_capture_visible(
            owner, row, prepared^.scroll.view_rect, prepared^.scroll.scroll_y_out) {
            return
        }
        runtime^.input.press_owner = {}
        return
    }
    tree_actions_cancel_context_capture(runtime)
}

// tree_actions_capture_matches recognizes only this row's three transient controls.
tree_actions_capture_matches :: #force_inline proc(
    owner: viewmodel.Ui_Press_Owner_State,
    layout: Tree_Actions_Layout) -> bool {
    return owner.id == layout.toggle_id || owner.id == layout.move_up_id ||
        owner.id == layout.move_down_id
}

// tree_actions_capture_visible admits only the clipped rectangle owning a gesture.
tree_actions_capture_visible :: proc(
    owner: viewmodel.Ui_Press_Owner_State, row: Tree_Prepared_Row,
    panel: geometry.Rectangle, scroll_y: f32) -> bool {
    if !row.logical || !row.actions.eligible {
        return false
    }
    if owner.kind == .Icon_Button {
        bounds := tree_actions_screen_rect(row.actions.toggle_rect, panel, scroll_y)
        clip := tree_row_screen_geometry(row, panel, scroll_y).clip_bounds
        return geometry.rectangles_intersect(bounds, clip)
    }
    if !row.actions.open {
        return false
    }
    clip := tree_actions_screen_clip(row, panel, scroll_y)
    button := row.actions.move_up_rect if owner.id == row.actions.move_up_id else
        row.actions.move_down_rect
    bounds := tree_actions_screen_rect(button, panel, scroll_y)
    return geometry.rectangles_intersect(bounds, clip)
}

// tree_actions_move_is_admitted checks the selected, open Favorites placement.
tree_actions_move_is_admitted :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier) -> bool {
    state := params.general_state
    if state == nil {
        log.error("library_tree_actions_move_without_current_owner")
        return false
    }
    index := tree_projection_find(&params.ui_runtime^.library.tree.projection, entry_id)
    if index == TREE_NO_ITEM ||
        !tree_actions_eligible(
            &params.ui_runtime^.library.tree.projection,
            params.ui_runtime^.library.tree.selected_item_id,
            params.visibility.search != nil && params.visibility.search^.active,
            &params.ui_runtime^.library.tree.projection.items[index]) ||
        state^.ui_runtime.layout.active_accordion_section != .Library ||
        entry_id != state^.ui_runtime.library.actions.drawer.entry_id ||
        !state^.ui_runtime.library.actions.drawer.open ||
        entry_id != state^.ui_runtime.library.tree.selected_item_id {
        log.error("library_tree_actions_move_without_current_owner")
        return false
    }
    return true
}

// tree_actions_move submits a fresh immutable swap through the durable mutation queue.
tree_actions_move :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier,
    direction: collections.Move_Direction) -> bool {
    state := params.general_state
    if !tree_actions_move_is_admitted(params, entry_id) {
        return false
    }
    mutation, failure := collections.make_sibling_move(
        &state^.preferences_runtime.collections_state, entry_id, direction)
    if failure != .None {
        log.errorf("library_tree_actions_move_rejected policy=%v", failure)
        return false
    }
    sampled: viewmodel.Ui_Tree_Reorder_Motion
    tree_reorder_capture(params, &sampled)
    result := viewpreferences.settings_save_collection_mutation(state, mutation)
    if result != .None {
        log.errorf("library_tree_actions_move_rejected error=%v", result)
        return false
    }
    tree_actions_refresh_projection(params)
    sampled.topology_revision =
        params.ui_runtime^.library.tree.projection.topology_revision
    params.ui_runtime^.library.actions.reorder = sampled
    tree_actions_repair_move_focus(params, entry_id, direction)
    return true
}

// draw_encoded_tree_actions_geometry renders disclosure and attached button surfaces.
draw_encoded_tree_actions_geometry :: proc(
    encoder: ^native.Draw_Encoder,
    row: Tree_Prepared_Row, panel: geometry.Rectangle, scroll_y: f32) {
    if !row.actions.eligible || !row.logical {
        return
    }
    row_geometry := tree_row_screen_geometry(row, panel, scroll_y)
    clip := geometry.Rectangle(row_geometry.clip_bounds)
    toggle := tree_actions_screen_rect(row.actions.toggle_rect, panel, scroll_y)
    if geometry.rectangles_intersect(toggle, clip) {
        _ = native.draw_encoder_push_scissor(encoder, clip)
        draw_tree_actions_toggle(encoder, toggle, row.actions_toggle, row.actions.open)
        _ = native.draw_encoder_pop_scissor(encoder)
    }
    draw_tree_actions_drawer_surfaces(encoder, row, panel, scroll_y)
}

// draw_tree_actions_drawer_surfaces extends the selected row's fill through its drawer.
draw_tree_actions_drawer_surfaces :: proc(
    encoder: ^native.Draw_Encoder,
    row: Tree_Prepared_Row, panel: geometry.Rectangle, scroll_y: f32) {
    if row.actions.height <= 0 {
        return
    }
    drawer_clip := tree_actions_screen_clip(row, panel, scroll_y)
    if drawer_clip.width <= 0 || drawer_clip.height <= 0 {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, drawer_clip)
    drawer := tree_actions_screen_rect(row.actions.drawer_rect, panel, scroll_y)
    _ = native.draw_encoder_rectangle(
        encoder, drawer, theme.UI_BORDER_COLOR)
    if row.actions.open {
        draw_tree_actions_button_surface(
            encoder,
            tree_actions_screen_rect(row.actions.move_up_rect, panel, scroll_y),
            row.actions_up, row.actions.move_up_enabled)
        draw_tree_actions_button_surface(
            encoder,
            tree_actions_screen_rect(row.actions.move_down_rect, panel, scroll_y),
            row.actions_down, row.actions.move_down_enabled)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

// draw_tree_actions_toggle inverts the ellipsis while its drawer is logically open.
draw_tree_actions_toggle :: proc(
    encoder: ^native.Draw_Encoder, rect: geometry.Rectangle,
    result: uiwidgets.Icon_Button_Result, open: bool) {
    dot_color := theme.UI_TEXT_COLOR
    if open {
        _ = native.draw_encoder_rectangle(encoder, rect, theme.UI_TEXT_COLOR)
        dot_color = theme.UI_BORDER_COLOR
    } else if result.hovered || result.pressed || result.action.activated {
        highlight := theme.UI_TEXT_COLOR
        highlight.a = 24
        _ = native.draw_encoder_rectangle(encoder, rect, highlight)
    }
    center := geometry.Vector2{rect.x + rect.width * 0.5,
        rect.y + rect.height * 0.5}
    radius := f32(1.5)
    spacing := f32(4)
    for dot in -1..=1 {
        _ = native.draw_encoder_circle(encoder,
            center + geometry.Vector2{0, f32(dot) * spacing}, radius,
            dot_color)
    }
}

// draw_tree_actions_button_surface preserves borderless button fills and enabled feedback.
draw_tree_actions_button_surface :: proc(
    encoder: ^native.Draw_Encoder, rect: geometry.Rectangle,
    result: uiwidgets.Text_Button_Result, enabled: bool) {
    fill := theme.UI_COMPONENT_BACKGROUND_COLOR
    if !enabled {
        fill.a = 150
    }
    _ = native.draw_encoder_rectangle(encoder, rect, fill)
    if enabled && (result.hovered || result.pressed || result.action.activated) {
        highlight := theme.UI_TEXT_COLOR
        highlight.a = 24
        _ = native.draw_encoder_rectangle(encoder, rect, highlight)
    }
}

// draw_encoded_tree_actions_text emits labels only while the drawer accepts actions.
draw_encoded_tree_actions_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    row: Tree_Prepared_Row, panel: geometry.Rectangle, scroll_y: f32) {
    if !row.actions.open || !row.logical {
        return
    }
    clip := tree_actions_screen_clip(row, panel, scroll_y)
    if clip.width <= 0 || clip.height <= 0 {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, clip)
    draw_tree_actions_button_label(state, encoder,
        {tree_actions_screen_rect(row.actions.move_up_rect, panel, scroll_y), clip},
        viewmessages.shell_message(state, .Library_Move_Up),
        row.actions.move_up_enabled)
    draw_tree_actions_button_label(state, encoder,
        {tree_actions_screen_rect(row.actions.move_down_rect, panel, scroll_y), clip},
        viewmessages.shell_message(state, .Library_Move_Down),
        row.actions.move_down_enabled)
    _ = native.draw_encoder_pop_scissor(encoder)
}

// draw_tree_actions_button_label centers one bounded label and dims disabled actions.
draw_tree_actions_button_label :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    bounds: viewmodel.Ui_Control_Geometry, label: string, enabled: bool) {
    rect := bounds.bounds
    clip := tree_reveal_intersection(rect, bounds.clip_bounds)
    if !geometry.rectangles_intersect(rect, clip) {
        return
    }
    text_color := theme.UI_TEXT_COLOR
    if !enabled {
        text_color.a = 110
    }
    _ = native.draw_encoder_push_scissor(encoder, clip)
    viewtext.draw_encoded_colored_label(&state^.font_cache, encoder, label,
        {rect.x + TREE_ACTION_DRAWER_PADDING,
         rect.y + (rect.height - theme.TREE_FONT_SIZE) * 0.5}, text_color)
    _ = native.draw_encoder_pop_scissor(encoder)
}
