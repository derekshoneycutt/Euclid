package uioverlay

import core "../../../core"
import collections "../../../collections"
import geometry "../../../core/geometry"
import uuid "core:encoding/uuid"
import crypto "core:crypto"
import log "core:log"
import viewmodel "../model"
import viewpreferences "../../preferences"
import uilibrary "../library"
import theme "../theme"

MEMBERSHIP_CONTROL_ID :: 2104
MEMBERSHIP_ROW_HEIGHT :: f32(30)
MEMBERSHIP_PADDING :: f32(8)

// Custom destinations include empty and read-only heads, but never Favorites.
membership_available :: proc(state: ^core.Euclid_General_State) -> bool {
    set := &state.preferences_runtime.collections_state
    for head in set.collections[:set.collection_count] {
        if head.role == .User {
            return true
        }
    }
    return false
}

// Popup identities capture their opening serial; checkboxes additionally capture owner UUIDs.
membership_id :: proc(
    menu: ^viewmodel.Ui_Collection_Membership_State,
    id: uuid.Identifier = {}) -> viewmodel.Ui_Node_Id {
    return {
        domain = .Collection_Membership,
        stable_id = id,
        generation = menu.serial,
    }
}

// Sort reusable indexes in Library order only when the accepted collection revision changes.
membership_order :: proc(state: ^core.Euclid_General_State) -> bool {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    if menu.revision == state.preferences_runtime.collection_revision &&
       menu.count > 0 {
        return true
    }
    if !viewmodel.ui_membership_reserve(menu, set.collection_count) {
        log.error("collection_membership_workspace_failed")
        return false
    }
    count := 0
    for head, index in set.collections[:set.collection_count] {
        if head.role != .User {
            continue
        }
        position := count
        for position > 0 &&
            set.collections[menu.order[position - 1]].order > head.order {
            menu.order[position] = menu.order[position - 1]
            position -= 1
        }
        menu.order[position] = index
        count += 1
    }
    menu.count = count
    menu.revision = state.preferences_runtime.collection_revision
    return count > 0
}

// Discard popup transactions and optionally restore the star-adjacent trigger's focus.
membership_close :: proc(state: ^core.Euclid_General_State, restore: bool) {
    menu := &state.ui_runtime.membership
    menu.active, menu.pending_valid = false, false
    menu.press_owner = {}
    menu.pressed = {}
    if state.ui_runtime.semantic_focus == nil {
        return
    }
    focus := state.ui_runtime.semantic_focus
    if restore {
        focus.logical_focus = {
            domain = .Animation_Control,
            local_id = MEMBERSHIP_CONTROL_ID,
        }
        focus.focus_origin = .Keyboard
    } else if focus.logical_focus.domain == .Collection_Membership {
        focus.logical_focus = {}
    }
}

// Opening captures selection, generation and anchor; no collection data is copied into the popup.
membership_open :: proc(
    state: ^core.Euclid_General_State, anchor: geometry.Rectangle) -> bool {
    if state.julia_interface == nil {
        return false
    }
    target := state.julia_interface.selected_animation
    if target == nil || target.node_kind != .Animation || !membership_order(state) {
        log.warn("collection_membership_open_rejected")
        return false
    }
    menu := &state.ui_runtime.membership
    context_menu_close(&state.ui_runtime.context_menu,
        state.ui_runtime.semantic_focus, false)
    menu.serial += 1
    menu.active = true
    menu.animation_id = target.stable_id
    menu.generation = state.julia_interface.content_generation
    menu.anchor = anchor
    menu.viewport = geometry.Rectangle(state.ui_runtime.layout.ui_regions.world_rect)
    menu.window = state.ui_runtime.layout.window
    menu.text_size_percent =
        state.ui_runtime.preferences.values.interface.text_size_percent
    menu.row_height = max(MEMBERSHIP_ROW_HEIGHT,
        theme.ui_font_size(menu.text_size_percent) + 12)
    menu.header_height = menu.row_height + 8
    menu.scroll_y, menu.drag_offset = 0, 0
    menu.focused =
        state.preferences_runtime.collections_state.collections[menu.order[0]].id
    menu.pending_valid, menu.dragging = false, false
    membership_place(state)
    origin := state.ui_runtime.semantic_focus.focus_origin
    membership_focus(state, menu.focused)
    state.ui_runtime.semantic_focus.focus_origin = origin
    return true
}

// Anchor loss, recording, target changes and generation replacement invalidate opening intent.
membership_valid :: proc(state: ^core.Euclid_General_State) -> bool {
    menu := &state.ui_runtime.membership
    if state.julia_interface == nil {
        return false
    }
    target := state.julia_interface.selected_animation
    return target != nil && target.node_kind == .Animation &&
        target.stable_id == menu.animation_id &&
        state.julia_interface.content_generation == menu.generation &&
        state.gif_capture_status.gif_capture_phase != .Recording &&
        menu.window == state.ui_runtime.layout.window &&
        menu.text_size_percent ==
            state.ui_runtime.preferences.values.interface.text_size_percent &&
        collections.find_collection(
            &state.preferences_runtime.collections_state, menu.focused) >= 0 &&
        menu.viewport == geometry.Rectangle(
            state.ui_runtime.layout.ui_regions.world_rect) &&
        membership_available(state)
}

// Bound the header and scroll viewport to the current world pane.
membership_place :: proc(state: ^core.Euclid_General_State) {
    menu := &state.ui_runtime.membership
    pane := menu.viewport
    width := min(f32(360), max(pane.width - 16, 0))
    height := min(f32(menu.count)*menu.row_height + menu.header_height + 8,
        max(pane.height - 16, 0))
    menu.bounds = {clamp(menu.anchor.x + menu.anchor.width - width,
        pane.x + 8, pane.x + max(8, pane.width - width - 8)),
        max(pane.y + 8, menu.anchor.y - height - 4), width, height}
    menu.clip = {menu.bounds.x + 8, menu.bounds.y + menu.header_height,
        max(width - 16, 0), max(height - menu.header_height - 8, 0)}
    menu.scroll_y = clamp(menu.scroll_y, 0,
        max(f32(menu.count)*menu.row_height - menu.clip.height, 0))
}

// Capture the exact accepted placement at activation so later stale removal cannot retarget.
membership_request :: proc(state: ^core.Euclid_General_State, id: uuid.Identifier) {
    menu := &state.ui_runtime.membership
    index, failure := collections.collection_edit_index(
        &state.preferences_runtime.collections_state, id)
    if !menu.active || !membership_valid(state) || failure != .None || index < 0 {
        log.warn("collection_membership_stale_action")
        return
    }
    if menu.pending_valid {
        log.warn("collection_membership_pending_action_rejected")
        return
    }
    identity, policy := collections.collection_animation_identity(
        &state.preferences_runtime.collections_state, id, menu.animation_id)
    if policy != .None && policy != .Not_In_Collection {
        log.warnf("collection_membership_query_rejected policy=%v", policy)
        return
    }
    menu.pending, menu.pending_placement = id, identity
    menu.pending_checked, menu.pending_valid = policy == .None, true
}

// Generate a fresh collision-checked identity without reviving removed aliases or positions.
membership_new_id :: proc(set: ^collections.Set) -> (uuid.Identifier, bool) {
    if !crypto.HAS_RAND_BYTES {
        return {}, false
    }
    for _ in 0..<4 {
        candidate: uuid.Identifier
        {
            context.random_generator = crypto.random_generator()
            candidate = uuid.generate_v4()
        }
        if candidate != (uuid.Identifier{}) &&
           collections.find_entry(set, candidate) < 0 &&
            collections.find_collection(set, candidate) < 0 {
            return candidate, true
        }
    }
    return {}, false
}

// Resolve pending intent after flushing a destructive target's dirty name in queue order.
membership_pending_mutation :: proc(
    state: ^core.Euclid_General_State) -> (collections.Mutation, bool) {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    mutation: collections.Mutation
    failure: collections.Policy_Error
    if menu.pending_checked {
        if !uilibrary.library_entry_name_flush(state, menu.pending_placement.entry_id) {
            log.warn("collection_membership_name_flush_rejected")
            return {}, false
        }
        mutation, failure = collections.make_collection_animation_remove_mutation(
            set, menu.pending_placement)
    } else {
        id, ok := membership_new_id(set)
        if !ok {
            log.error("collection_membership_identity_failed")
            return {}, false
        }
        mutation, failure = collections.make_collection_animation_add_mutation(
            set, menu.pending, id, menu.animation_id)
    }
    if failure != .None {
        log.warnf("collection_membership_rejected policy=%v", failure)
        return {}, false
    }
    return mutation, true
}

// Apply accepted membership before Library borrows projection rows for this frame.
membership_commit :: proc(state: ^core.Euclid_General_State) {
    menu := &state.ui_runtime.membership
    if !menu.pending_valid {
        return
    }
    menu.pending_valid = false
    if !menu.active || !membership_valid(state) {
        log.warn("collection_membership_stale_commit")
        return
    }
    mutation, ok := membership_pending_mutation(state)
    if !ok {
        return
    }
    result := viewpreferences.settings_save_collection_mutation(
        state, mutation, state.julia_interface.selected_animation.name)
    if result != .None {
        log.errorf("collection_membership_rejected error=%v", result)
    }
}
