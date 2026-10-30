package uilibrary

import collections "../../../collections"
import uuid "core:encoding/uuid"
import log "core:log"
import math "core:math"
import geometry "../../../core/geometry"
import content "../../../core/content"
import viewmodel "../model"
import viewpreferences "../../preferences"
import uiwidgets "../widgets"
import native "../../native"
import theme "../theme"
import viewmessages "../../messages"

TREE_COLLECTION_DELETE :: u64(10)
TREE_DELETE_GUARD_SECONDS :: f64(0.5)
TREE_DELETE_SHAKE_SECONDS :: f64(0.3)

// Place deletion on its own full-width row below routine ordering controls.
tree_collection_delete_layout :: proc(
    layout: ^viewmodel.Ui_Tree_Actions_Layout,
    inner: geometry.Rectangle, item_index: int,
    scale := f32(1)) {
    layout.delete_rect = {inner.x,
        layout.move_down_rect.y +
            (TREE_ACTION_BUTTON_HEIGHT + TREE_ACTION_BUTTON_GAP) * scale,
        inner.width, TREE_ACTION_BUTTON_HEIGHT * scale}
    layout.delete_id = tree_actions_control_id(item_index, 3)
}

// Arm first; every repeated activation restarts the quiet interval across all input origins.
tree_collection_delete :: proc(
    params: Tree_List_Params, id: uuid.Identifier,
    multiple_pointer_click: bool = false) -> bool {
    if !tree_actions_move_is_admitted(params, id) {
        return false
    }
    _, failure := collections.collection_edit_index(params.collections, id)
    if failure != .None {
        log.warnf("library_collection_delete_rejected policy=%v", failure)
        return false
    }
    confirmation := &params.ui_runtime^.library.actions.delete_confirmation
    now := params.mouse_input.sample_time_seconds
    same := confirmation^.armed && confirmation^.collection_id == id &&
        confirmation^.generation == params.ji^.content_generation
    previous := confirmation^.last_activation_seconds
    confirmation^ = {
        collection_id = id,
        generation = params.ji^.content_generation,
        armed = true,
        last_activation_seconds = now,
        shake_started_seconds = now if !same else confirmation^.shake_started_seconds,
    }
    if !same {
        return true
    }
    if !tree_collection_delete_quiet(previous, now) ||
        multiple_pointer_click {
        return true
    }
    return tree_collection_delete_submit(params, id)
}

// Strictly exceed the last-attempt boundary; backward samples never confirm.
tree_collection_delete_quiet :: proc(previous, now: f64) -> bool {
    return now > previous + TREE_DELETE_GUARD_SECONDS
}

// Flush accepted naming first; rejected flush or queue admission leaves the armed owner intact.
tree_collection_delete_submit :: proc(
    params: Tree_List_Params, id: uuid.Identifier) -> bool {
    if !library_entry_name_flush(params.general_state, id) {
        return false
    }
    mutation, failure := collections.make_collection_delete_mutation(
        params.collections, id)
    if failure != .None {
        log.warnf("library_collection_delete_rejected policy=%v", failure)
        return false
    }
    result := viewpreferences.settings_save_collection_mutation(
        params.general_state, mutation)
    if result != .None {
        log.warnf("library_collection_delete_rejected error=%v", result)
        return false
    }
    return true
}

// Context loss invalidates destructive intent even when a failed editor flush retains a drawer.
tree_collection_delete_reconcile :: proc(params: Tree_List_Params) {
    runtime := params.ui_runtime
    confirmation := &runtime^.library.actions.delete_confirmation
    if !confirmation.armed {
        return
    }
    _, failure := collections.collection_edit_index(
        params.collections, confirmation.collection_id)
    if failure != .None ||
         confirmation^.generation != params.ji^.content_generation ||
         confirmation^.collection_id != runtime^.library.tree.selected_item_id ||
         confirmation^.collection_id != runtime^.library.actions.drawer.entry_id ||
         !runtime^.library.actions.drawer.open ||
         runtime^.layout.active_accordion_section != .Library ||
         params.visibility.search != nil && params.visibility.search^.active {
        confirmation^ = {}
    }
}

// Return the explicit text warning; color and shake never carry confirmation alone.
tree_collection_delete_message :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    id: uuid.Identifier) -> content.Content_Message_Id {
    confirmation := runtime^.library.actions.delete_confirmation
    return .Library_Confirm_Delete if confirmation.armed &&
        confirmation.collection_id == id else .Library_Delete_Collection
}

// A closed drawer retires delete focus; an open one reveals its full destructive row.
tree_collection_delete_prepare_focus :: proc(
    params: Tree_List_Params, target: viewmodel.Ui_Node_Id) {
    runtime := params.ui_runtime
    motion := &runtime^.library.actions.drawer
    if !motion^.open || motion^.entry_id != target.stable_id {
        tree_actions_focus_toggle(params, target.stable_id)
        return
    }
    if runtime^.library.actions.reveal_pending {
        projection := &runtime^.library.tree.projection
        index := tree_projection_find(projection, target.stable_id)
        motion^.height = tree_actions_full_height(
            params.list_panel.width,
            tree_item_depth(projection, projection^.items[index])) +
            TREE_ACTION_BUTTON_HEIGHT + TREE_ACTION_BUTTON_GAP
        motion^.running = false
    }
}

// Shift the whole prepared block, including hit targets and semantic rectangles, once per layout.
tree_collection_delete_apply_motion :: proc(
    params: Tree_List_Params, layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
    confirmation := params.ui_runtime^.library.actions.delete_confirmation
    if !confirmation.armed || params.reduce_motion {
        return
    }
    elapsed := params.mouse_input.sample_time_seconds - confirmation.shake_started_seconds
    if elapsed < 0 || elapsed >= TREE_DELETE_SHAKE_SECONDS {
        return
    }
    offset := f32(math.sin(elapsed / TREE_DELETE_SHAKE_SECONDS * 6 * math.PI) *
        5 * (1 - elapsed / TREE_DELETE_SHAKE_SECONDS))
    for &row in layout^.rows[:layout^.count] {
        if row.item^.key != confirmation.collection_id {
            continue
        }
        row.offset_x = offset
        row.actions.toggle_rect.x += offset
        row.actions.drawer_rect.x += offset
        row.actions.move_up_rect.x += offset
        row.actions.move_down_rect.x += offset
        row.actions.delete_rect.x += offset
    }
}

// Publish the destructive control only for a logically open custom head.
tree_collection_delete_publish :: proc(
    params: Tree_List_Params, row: viewmodel.Ui_Tree_Prepared_Row,
    panel: geometry.Rectangle, scroll_y: f32) {
    if row.item^.kind != .Collection || !row.actions.open {
        return
    }
    tree_actions_publish_button(params,
        tree_actions_semantic_id(params, row.item^.key, TREE_COLLECTION_DELETE),
        {tree_actions_screen_rect(row.actions.delete_rect, panel, scroll_y),
            tree_actions_screen_clip(row, panel, scroll_y)}, row.actions.delete_enabled,
        viewmessages.shell_message(params.general_state,
            tree_collection_delete_message(params.ui_runtime, row.item^.key)))
}

// Hit-test the published delete rectangle through the ordinary text-button capture owner.
tree_collection_delete_prepare :: proc(
    params: Tree_List_Params, row: ^viewmodel.Ui_Tree_Prepared_Row,
    prepared: ^Tree_List_Preparation, ctx: Tree_Walk_Context, hit: ^Tree_Hit) {
    if row^.item^.kind != .Collection {
        return
    }
    bounds := tree_actions_screen_rect(row^.actions.delete_rect, ctx.panel, ctx.scroll_y)
    clip := tree_actions_screen_clip(row^, ctx.panel, ctx.scroll_y)
    prepared^.actions_delete = uiwidgets.update_text_button(tree_actions_button_params(
        params, row^.actions.delete_id, {bounds, clip},
        row.actions.delete_enabled, ctx.allow_clicks),
        &params.ui_runtime^.input.press_owner)
    if prepared^.actions_delete.clicked {
        hit^.actions_delete_id = row^.item^.key
    }
    if params.ui_runtime^.input.press_owner.active &&
        params.ui_runtime^.input.press_owner.id == row^.actions.delete_id {
        params.ui_runtime^.library.actions.press_entry = row^.item^.key
        if uiwidgets.input_frame_left_pressed(params.mouse_input) {
            params.ui_runtime^.library.actions.delete_pointer_clicks =
                params.mouse_input.mouse_left_clicks
        }
    }
}

// Draw deletion separately from routine ordering and retain a text-plus-outline armed warning.
tree_collection_delete_draw :: proc(
    ctx: Encoded_Tree_Walk_Context, row: viewmodel.Ui_Tree_Prepared_Row) {
    if row.item^.kind != .Collection || !row.actions.open {
        return
    }
    rect := tree_actions_screen_rect(row.actions.delete_rect, ctx.panel, ctx.scroll_y)
    draw_tree_actions_button_surface(
        ctx.encoder, rect, ctx.actions_delete, row.actions.delete_enabled)
    confirmation := ctx.state^.ui_runtime.library.actions.delete_confirmation
    if confirmation.armed && confirmation.collection_id == row.item^.key {
        _ = native.draw_encoder_rectangle_outline(
            ctx.encoder, rect, 1, theme.UI_ERROR_COLOR)
    }
}
