package uilibrary

import collections "../../../collections"
import content "../../../core/content"
import geometry "../../../core/geometry"
import uuid "core:encoding/uuid"
import log "core:log"
import native "../../native"
import viewmessages "../../messages"
import viewmodel "../model"
import uiwidgets "../widgets"
import uisemantics "../semantics"
import theme "../theme"

TREE_ACTION_TOGGLE :: u64(1)
TREE_ACTION_UP :: u64(2)
TREE_ACTION_DOWN :: u64(3)
TREE_ACTION_DRAWER :: u64(8)
TREE_ENTRY_NAME_INPUT :: u64(5)
TREE_ENTRY_NAME_TEXT_RUN :: u64(6)

// tree_actions_semantic_id qualifies controls by placement and content lifetime.
tree_actions_semantic_id :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier,
    action: u64) -> viewmodel.Ui_Node_Id {
    return {domain = .Library_Action, local_id = action,
        stable_id = entry_id, generation = params.ji^.content_generation}
}

// tree_actions_repair_context_focus repairs only focus owned by a retired drawer.
tree_actions_repair_context_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    semantic := runtime^.semantic_focus
    if semantic != nil && semantic^.logical_focus.domain == .Library_Action {
        semantic^.logical_focus = tree_semantic_id()
        semantic^.last_region = .Accordion_Content
        semantic^.last_traversal_order = 3
    }
    runtime^.library.actions.last_focus = {}
    runtime^.library.actions.reveal_pending = false
}

// tree_actions_focus_toggle preserves input origin when an action becomes unavailable.
tree_actions_focus_toggle :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier) {
    semantic := params.ui_runtime^.semantic_focus
    if semantic == nil || semantic^.logical_focus.domain != .Library_Action ||
        semantic^.logical_focus.stable_id != entry_id {
        return
    }
    semantic^.logical_focus = tree_actions_semantic_id(
        params, entry_id, TREE_ACTION_TOGGLE)
    semantic^.last_region = .Accordion_Content
    semantic^.last_traversal_order = 4
    params.ui_runtime^.library.actions.reveal_pending = true
}

// tree_actions_repair_move_focus retains an interior action or returns to disclosure.
tree_actions_repair_move_focus :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier,
    direction: collections.Move_Direction) {
    semantic := params.ui_runtime^.semantic_focus
    if semantic == nil || semantic^.logical_focus.domain != .Library_Action ||
        semantic^.logical_focus.stable_id != entry_id {
        return
    }
    action := TREE_ACTION_UP if direction == .Up else TREE_ACTION_DOWN
    if semantic^.logical_focus.local_id == action &&
        !tree_actions_neighbor_exists(params.collections, entry_id, direction) {
        tree_actions_focus_toggle(params, entry_id)
    }
    params.ui_runtime^.library.actions.reveal_pending = true
}

// tree_actions_command_item rejects stale, hidden, or deselected action identities.
tree_actions_command_item :: proc(
    params: Tree_List_Params,
    target: viewmodel.Ui_Node_Id) -> ^viewmodel.Ui_Tree_Item {
    if target.domain != .Library_Action || target.local_id < TREE_ACTION_TOGGLE ||
        target.local_id > TREE_ACTION_DOWN &&
            target.local_id != TREE_ENTRY_NAME_INPUT ||
        target.generation != params.ji^.content_generation ||
        params.general_state != nil &&
            params.ui_runtime^.layout.active_accordion_section != .Library {
        return nil
    }
    index := tree_projection_find(
        &params.ui_runtime^.library.tree.projection, target.stable_id)
    if index == TREE_NO_ITEM {
        return nil
    }
    item := params.ui_runtime^.library.tree.projection.items[index]
    if !tree_actions_eligible(
        &params.ui_runtime^.library.tree.projection,
        params.ui_runtime^.library.tree.selected_item_id,
        params.visibility.search != nil && params.visibility.search^.active,
        item) {
        return nil
    }
    if target.local_id == TREE_ENTRY_NAME_INPUT &&
        (!params.ui_runtime^.library.actions.drawer.open ||
         params.ui_runtime^.library.actions.drawer.entry_id != item^.key) {
        return nil
    }
    return item
}

// tree_actions_apply_command converges keyboard and native intents with owned mutations.
tree_actions_apply_command :: proc(
    params: Tree_List_Params, command: viewmodel.Ui_Focus_Command) {
    item := tree_actions_command_item(params, command.target)
    if item == nil {
        log.warn("library_tree_actions_stale_command")
        return
    }
    if command.kind != .Dismiss &&
        !tree_actions_command_visible(params, item, command.target.local_id) {
        log.warn("library_tree_actions_hidden_command")
        return
    }
    action := command.target.local_id
    motion := &params.ui_runtime^.library.actions.drawer
    if command.kind == .Dismiss {
        if motion^.entry_id == item^.key && motion^.open {
            tree_actions_toggle(params, item^.key)
        }
        return
    }
    if action == TREE_ACTION_TOGGLE && (command.kind == .Activate ||
        command.kind == .Expand && !motion^.open ||
        command.kind == .Collapse && motion^.open) {
        tree_actions_toggle(params, item^.key)
    } else if action != TREE_ACTION_TOGGLE &&
        action != TREE_ENTRY_NAME_INPUT && command.kind == .Activate {
        direction := collections.Move_Direction.Up if action == TREE_ACTION_UP else .Down
        _ = tree_actions_move(params, item^.key, direction)
    }
    if command.kind == .Focus {
        params.ui_runtime^.library.actions.reveal_pending = true
    }
}

// tree_actions_command_visible rechecks current clipping and drawer admission.
tree_actions_command_visible :: proc(
    params: Tree_List_Params,
    item: ^viewmodel.Ui_Tree_Item,
    action: u64) -> bool {
    layout: viewmodel.Ui_Tree_Prepared_Layout
    if !tree_prepare_layout_scratch(params, &layout) {
        return false
    }
    row := tree_layout_find_item(&layout, item)
    if row == nil || !row^.logical || !row^.actions.eligible {
        return false
    }
    if action == TREE_ACTION_TOGGLE {
        bounds := tree_actions_screen_rect(
            row^.actions.toggle_rect, params.list_panel, params.scroll_y^)
        clip := tree_row_screen_geometry(row^, params.list_panel, params.scroll_y^)
        return geometry.rectangles_intersect(bounds, clip.clip_bounds)
    }
    if action == TREE_ENTRY_NAME_INPUT {
        if !row^.actions.open {
            return false
        }
        row_geometry := tree_row_screen_geometry(
            row^, params.list_panel, params.scroll_y^)
        bounds := tree_actions_label_clip(
            row^.actions, row_geometry.bounds, row_geometry.clip_bounds)
        return geometry.rectangles_intersect(bounds, row_geometry.clip_bounds)
    }
    if !row^.actions.open {
        return false
    }
    return tree_actions_move_command_visible(params, row, action)
}

// tree_actions_move_command_visible admits only an enabled, clipped move button.
tree_actions_move_command_visible :: proc(
    params: Tree_List_Params, row: ^viewmodel.Ui_Tree_Prepared_Row, action: u64) -> bool {
    direction := collections.Move_Direction.Up if action == TREE_ACTION_UP else .Down
    if !tree_actions_neighbor_exists(params.collections, row^.item^.key, direction) {
        return false
    }
    bounds := row^.actions.move_up_rect if action == TREE_ACTION_UP else
        row^.actions.move_down_rect
    return geometry.rectangles_intersect(
        tree_actions_screen_rect(bounds, params.list_panel, params.scroll_y^),
        tree_actions_screen_clip(row^, params.list_panel, params.scroll_y^))
}

// tree_actions_apply_commands revalidates each queued action after earlier mutations.
tree_actions_apply_commands :: proc(params: Tree_List_Params) {
    semantic := params.ui_runtime^.semantic_focus
    if semantic == nil {
        return
    }
    for command in semantic^.commands[:semantic^.command_count] {
        if command.target.domain == .Library_Action &&
            command.target.local_id != TREE_ENTRY_NAME_TEXT_RUN {
            if command.target.local_id != TREE_ENTRY_NAME_INPUT ||
                command.kind == .Dismiss {
                tree_actions_apply_command(params, command)
                tree_actions_refresh_projection(params)
            }
        }
    }
}

// tree_actions_refresh_projection reacquires row pointers at the current durable revision.
tree_actions_refresh_projection :: proc(params: Tree_List_Params) {
    if params.general_state == nil {
        return
    }
    updated := params
    updated.collections_revision =
        params.general_state^.preferences_runtime.collection_revision
    if !tree_projection_prepare(updated) {
        log.error("library_tree_actions_projection_rejected")
    }
}

// tree_actions_prepare_focus reveals newly addressed controls, never ordinary scrolls.
tree_actions_prepare_focus :: proc(params: Tree_List_Params) {
    runtime := params.ui_runtime
    semantic := runtime^.semantic_focus
    if semantic == nil || semantic^.logical_focus.domain != .Library_Action {
        runtime^.library.actions.last_focus = {}
        return
    }
    target := semantic^.logical_focus
    if tree_actions_command_item(params, target) == nil {
        tree_actions_repair_context_focus(runtime)
        return
    }
    if runtime^.library.actions.last_focus != target {
        runtime^.library.actions.reveal_pending = true
        runtime^.library.actions.last_focus = target
    }
    if target.local_id != TREE_ACTION_TOGGLE {
        if target.local_id == TREE_ENTRY_NAME_INPUT {
            motion := &runtime^.library.actions.drawer
            if !motion^.open || motion^.entry_id != target.stable_id {
                tree_actions_focus_toggle(params, target.stable_id)
            }
            return
        }
        tree_actions_prepare_move_focus(params, target)
    }
}

// tree_actions_prepare_move_focus preserves only currently enabled move-button focus.
tree_actions_prepare_move_focus :: proc(
    params: Tree_List_Params, target: viewmodel.Ui_Node_Id) {
    runtime := params.ui_runtime
    motion := &runtime^.library.actions.drawer
    direction := collections.Move_Direction.Up if
        target.local_id == TREE_ACTION_UP else .Down
    if !motion^.open || motion^.entry_id != target.stable_id ||
        !tree_actions_neighbor_exists(params.collections, target.stable_id, direction) {
        tree_actions_focus_toggle(params, target.stable_id)
    } else if runtime^.library.actions.reveal_pending {
        index := tree_projection_find(
            &runtime^.library.tree.projection, target.stable_id)
        motion^.height = tree_actions_full_height(
            params.list_panel.width, tree_item_depth(
                &runtime^.library.tree.projection,
                runtime^.library.tree.projection.items[index]))
        motion^.running = false
    }
}

// tree_actions_reveal_focus scrolls the addressed action rectangle into the list viewport.
tree_actions_reveal_focus :: proc(
    params: Tree_List_Params, layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
    runtime := params.ui_runtime
    if !runtime^.library.actions.reveal_pending || runtime^.semantic_focus == nil {
        return
    }
    target := runtime^.semantic_focus^.logical_focus
    for row in layout^.rows[:layout^.count] {
        if row.item^.key != target.stable_id || !row.actions.eligible {
            continue
        }
        bounds := row.actions.toggle_rect
        if target.local_id == TREE_ENTRY_NAME_INPUT {
            bounds = {row.actions.label_clip.x, row.content_y,
                row.actions.label_clip.width, theme.TREE_ROW_HEIGHT}
        } else if target.local_id == TREE_ACTION_UP {
            bounds = row.actions.move_up_rect
        } else if target.local_id == TREE_ACTION_DOWN {
            bounds = row.actions.move_down_rect
        }
        if runtime^.library.actions.reorder.active {
            bounds.y += row.canonical_y - row.content_y
        }
        scroll := params.scroll_y^
        if bounds.y < scroll {
            scroll = bounds.y
        } else if bounds.y + bounds.height > scroll + params.list_panel.height {
            scroll = bounds.y + bounds.height - params.list_panel.height
        }
        params.scroll_y^ = clamp(scroll, 0,
            max(layout^.content_height - params.list_panel.height, 0))
        runtime^.library.actions.reveal_pending = false
        return
    }
}

// tree_actions_control_states excludes clipped and disabled controls from interaction.
tree_actions_control_states :: proc(
    bounds, clip: geometry.Rectangle, enabled: bool) -> viewmodel.Ui_Node_State {
    states := viewmodel.Ui_Node_State{.Visible}
    if enabled {
        states += {.Enabled, .Focusable, .Tab_Stop}
    }
    if !geometry.rectangles_intersect(bounds, clip) {
        states -= {.Enabled, .Focusable, .Tab_Stop}
    }
    return states
}

// tree_actions_publish_button publishes a truthful final-frame ordinary action.
tree_actions_publish_button :: proc(
    params: Tree_List_Params, id: viewmodel.Ui_Node_Id,
    bounds: viewmodel.Ui_Control_Geometry, enabled: bool, label: string) {
    states := tree_actions_control_states(bounds.bounds, bounds.clip_bounds, enabled)
    parent := id
    parent.local_id = TREE_ACTION_DRAWER
    actions: viewmodel.Ui_Node_Action_Set
    if .Enabled in states {
        actions = {.Focus, .Activate}
    }
    _ = uisemantics.semantic_register_control(params.ui_runtime^.semantic_focus, {
        id = id, parent = parent,
        role = .Button, states = states, actions = actions,
        region = .Accordion_Content, traversal_order = u32(id.local_id + 4),
        bounds = bounds.bounds, clip_bounds = bounds.clip_bounds, label = label,
    })
}

// tree_actions_publish_row copies placement-qualified disclosure and drawer semantics.
tree_actions_publish_row :: proc(
    params: Tree_List_Params, row: viewmodel.Ui_Tree_Prepared_Row,
    panel: geometry.Rectangle, scroll_y: f32) {
    entry_id := row.item^.key
    toggle := tree_actions_screen_rect(row.actions.toggle_rect, panel, scroll_y)
    clip := tree_row_screen_geometry(row, panel, scroll_y).clip_bounds
    states := tree_actions_control_states(toggle, clip, true)
    if params.ui_runtime^.library.actions.drawer.open {
        states += {.Expanded}
    }
    storage: [content.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    label := viewmessages.shell_format(params.general_state, .Library_Actions_For,
        []content.Content_Format_Argument{{name = "name",
            value = tree_item_label(params.ji, row.item, params.collections)}},
        storage[:])
    drawer_id := tree_actions_semantic_id(params, entry_id, TREE_ACTION_DRAWER)
    _ = uisemantics.semantic_register_control(params.ui_runtime^.semantic_focus, {
        id = tree_actions_semantic_id(params, entry_id, TREE_ACTION_TOGGLE),
        parent = tree_placement_semantic_id(row.item),
        controls = drawer_id,
        role = .Button, states = states,
        actions = {.Focus, .Activate, .Expand, .Collapse},
        region = .Accordion_Content, traversal_order = 4,
        bounds = toggle, clip_bounds = clip, label = label,
    })
    _ = uisemantics.semantic_register_control(params.ui_runtime^.semantic_focus, {
        id = drawer_id, parent = tree_placement_semantic_id(row.item),
        role = .Panel, states = {.Visible},
        bounds = tree_actions_screen_rect(row.actions.drawer_rect, panel, scroll_y),
        clip_bounds = tree_actions_screen_clip(row, panel, scroll_y), label = label,
    })
    tree_actions_publish_moves(params, row, panel, scroll_y)
}

// tree_actions_publish_moves keeps closed buttons absent and endpoints non-actionable.
tree_actions_publish_moves :: proc(
    params: Tree_List_Params, row: viewmodel.Ui_Tree_Prepared_Row,
    panel: geometry.Rectangle, scroll_y: f32) {
    if !row.actions.open {
        return
    }
    clip := tree_actions_screen_clip(row, panel, scroll_y)
    tree_actions_publish_button(params,
        tree_actions_semantic_id(params, row.item^.key, TREE_ACTION_UP),
        {tree_actions_screen_rect(row.actions.move_up_rect, panel, scroll_y), clip},
        row.actions.move_up_enabled,
        viewmessages.shell_message(params.general_state, .Library_Move_Up))
    tree_actions_publish_button(params,
        tree_actions_semantic_id(params, row.item^.key, TREE_ACTION_DOWN),
        {tree_actions_screen_rect(row.actions.move_down_rect, panel, scroll_y), clip},
        row.actions.move_down_enabled,
        viewmessages.shell_message(params.general_state, .Library_Move_Down))
}

// tree_actions_publish registers controls once, after final topology and geometry settle.
tree_actions_publish :: proc(
    params: Tree_List_Params, prepared: ^Tree_List_Preparation) {
    if params.ui_runtime^.semantic_focus == nil {
        return
    }
    for row in prepared^.layout.rows[:prepared^.layout.count] {
        if row.actions.eligible && row.logical {
            tree_actions_publish_row(params, row,
                prepared^.scroll.view_rect, prepared^.scroll.scroll_y_out)
            tree_actions_pointer_focus(params, row)
        }
    }
    if prepared^.entry_name_prepared {
        draft := &params.ui_runtime^.library.entry_name
        input_params := library_entry_name_input_params(
            params, draft^.entry_id, draft^.rect, draft^.clip_rect, {})
        uiwidgets.input_box_publish_prepared_semantics(
            input_params, &params.ui_runtime^.input.press_owner,
            &prepared^.entry_name_input)
    }
}

// tree_actions_pointer_focus focuses the exact action press without selecting its row.
tree_actions_pointer_focus :: proc(
    params: Tree_List_Params, row: viewmodel.Ui_Tree_Prepared_Row) {
    owner := params.ui_runtime^.input.press_owner
    if !owner.active || !tree_actions_capture_matches(owner, row.actions) {
        return
    }
    action := TREE_ACTION_TOGGLE
    if owner.id == row.actions.move_up_id {
        action = TREE_ACTION_UP
    } else if owner.id == row.actions.move_down_id {
        action = TREE_ACTION_DOWN
    }
    _ = uisemantics.semantic_request_pointer_focus(params.ui_runtime^.semantic_focus,
        tree_actions_semantic_id(params, row.item^.key, action))
}

// tree_actions_draw_focus outlines only the keyboard-focused current action.
tree_actions_draw_focus :: proc(
    encoder: ^native.Draw_Encoder, runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    row: viewmodel.Ui_Tree_Prepared_Row, panel: geometry.Rectangle, scroll_y: f32) {
    semantic := runtime^.semantic_focus
    if semantic == nil || !semantic^.window_focused ||
        semantic^.focus_origin != .Keyboard ||
        semantic^.logical_focus.domain != .Library_Action ||
        semantic^.logical_focus.stable_id != row.item^.key {
        return
    }
    action := semantic^.logical_focus.local_id
    bounds := row.actions.toggle_rect
    clip := tree_row_screen_geometry(row, panel, scroll_y).clip_bounds
    if action != TREE_ACTION_TOGGLE {
        if !row.actions.open {
            return
        }
        bounds = row.actions.move_up_rect if action == TREE_ACTION_UP else
            row.actions.move_down_rect
        clip = tree_actions_screen_clip(row, panel, scroll_y)
    }
    bounds = tree_actions_screen_rect(bounds, panel, scroll_y)
    if geometry.rectangles_intersect(bounds, clip) {
        _ = native.draw_encoder_push_scissor(encoder, clip)
        uiwidgets.draw_encoded_focus_ring(encoder, bounds)
        _ = native.draw_encoder_pop_scissor(encoder)
    }
}
