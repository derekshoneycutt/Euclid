package viewscenario

import scenario "../../evidence/scenario"
import collections "../../collections"
import geometry "../../core/geometry"
import input "../input"
import viewmodel "../ui/model"
import uianimation "../ui/animation"
import uilibrary "../ui/library"
import uisemantics "../ui/semantics"
import ui "../ui"
import uuid "core:encoding/uuid"
import log "core:log"

// One bounded placement baseline for remove/reappend acceptance.
Scenario_Favorites_Memory :: struct {
    placement: uuid.Identifier,
    playback: uuid.Identifier,
    animation_generation: u64,
}

// Split a bounded operation or placement address without allocating.
scenario_favorites_split :: proc(text: string) -> (string, string) {
    for value, index in text {
        if value == ':' {
            return text[:index], text[index + 1:]
        }
    }
    return text, ""
}

// Override only scenario-authored pointer facts through the ordinary UI input path.
scenario_pointer_frame :: proc(
    runtime: ^Scenario_Runtime, frame: input.Input_Frame) -> input.Input_Frame {
    result := frame
    if runtime^.pointer_override {
        result.mouse_position = {
            runtime^.pointer_position.x,
            runtime^.pointer_position.y,
        }
        result.mouse_down = {.Left} if runtime^.pointer_down else {}
        result.mouse_pressed = {.Left} if runtime^.pointer_pressed else {}
        result.mouse_released = {.Left} if runtime^.pointer_released else {}
        runtime^.pointer_pressed = false
        runtime^.pointer_released = false
    }
    return result
}

// Queue a control-addressed pointer sample for the next ordinary display frame.
scenario_favorites_pointer :: proc(
    runtime: ^Scenario_Runtime, bounds: geometry.Rectangle,
    operation: string) -> bool {
    if operation != "hover" && operation != "press" && operation != "release" {
        return false
    }
    if bounds.width <= 0 || bounds.height <= 0 {
        return false
    }
    runtime^.pointer_override = true
    runtime^.pointer_position = {
        bounds.x + bounds.width * 0.5,
        bounds.y + bounds.height * 0.5,
    }
    runtime^.pointer_pressed = operation == "press"
    runtime^.pointer_released = operation == "release"
    runtime^.pointer_down = operation == "press"
    return true
}

// Route star focus and pointer gestures through the existing UI owners.
scenario_favorite_control :: proc(
    runtime: ^Scenario_Runtime,
    operation: string) -> bool {
    state := runtime^.state
    if !uianimation.animation_favorite_eligible(state^.julia_interface) {
        return false
    }
    if operation == "leave" {
        runtime^.pointer_override = true
        runtime^.pointer_position = {-1, -1}
        runtime^.pointer_down = false
        return true
    }
    if operation == "focus" {
        return uisemantics.semantic_apply_external_action(
            state^.ui_runtime.semantic_focus,
            uisemantics.semantic_control_id(
                .Animation_Control, uianimation.ANIMATION_FAVORITE_BUTTON_ID),
            .Focus)
    }
    slots := uianimation.animation_control_layout_slots(
        geometry.Rectangle(state^.ui_runtime.ui_regions.world_rect), true)
    return scenario_favorites_pointer(runtime, slots.favorite, operation)
}

// Resolve canonical and Favorites occurrences separately using current stable identities.
scenario_favorites_item :: proc(
    runtime: ^Scenario_Runtime, address: string) -> ^viewmodel.Ui_Tree_Item {
    state := runtime^.state
    key: uuid.Identifier
    if address == "collections" {
        key = viewmodel.TREE_COLLECTIONS_ROOT_ID
    } else if address == "favorites" {
        key = collections.FAVORITES_COLLECTION_ID
    } else {
        domain, name := scenario_favorites_split(address)
        animation := scenario_find_animation(state^.julia_interface, name)
        if animation == nil {
            return nil
        }
        if domain == "catalogue" {
            key = animation^.stable_id
        } else if domain == "favorite" {
            entry, found := uianimation.animation_favorite_entry(
                &state^.preferences_runtime.collections_state, animation^.stable_id)
            if !found {
                return nil
            }
            key = entry
        } else {
            return nil
        }
    }
    projection := &state^.ui_runtime.tree_projection
    index := uilibrary.tree_projection_find(projection, key)
    return &projection^.items[index] if index >= 0 else nil
}

// Address a published tree occurrence; hidden or disabled rows reject actions.
scenario_library_placement :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if text == "expand_all" {
        return scenario_favorites_expand_all(runtime)
    }
    if text == "focus_library" {
        return uisemantics.semantic_apply_external_action(
            runtime^.state^.ui_runtime.semantic_focus,
            uisemantics.semantic_control_id(.Accordion,
                int(viewmodel.Ui_Accordion_Section.Library) + 1),
            .Focus)
    }
    operation, address := scenario_favorites_split(text)
    item := scenario_favorites_item(runtime, address)
    if item == nil {
        return false
    }
    focus := runtime^.state^.ui_runtime.semantic_focus
    id := uilibrary.tree_placement_semantic_id(item)
    snapshot := uisemantics.semantic_snapshot(focus)
    if snapshot == nil {
         return false
    }
    index := uisemantics.semantic_node_index(snapshot, id)
    if index < 0 {
        return false
    }
    node := snapshot^.nodes[index]
    if .Visible not_in node.states || .Enabled not_in node.states {
        return false
    }
    if operation == "press" || operation == "release" || operation == "hover" {
        return scenario_favorites_pointer(runtime, node.bounds, operation)
    }
    return scenario_library_apply(runtime, item, operation, node.clip_bounds)
}

// Apply an admitted semantic tree action while preserving occurrence-specific keyboard focus.
scenario_library_apply :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string, clip: geometry.Rectangle) -> bool {
    focus := runtime^.state^.ui_runtime.semantic_focus
    id := uilibrary.tree_placement_semantic_id(item)
    kind: viewmodel.Ui_Focus_Command_Kind
    switch operation {
    case "focus":
        kind = .Focus
    case "select":
        kind = .Select
    case "expand":
        kind = .Expand
    case "collapse":
        kind = .Collapse
    case:
        return false
    }
    if !uisemantics.semantic_apply_external_action(focus, id, .Focus) {
        return false
    }
    if kind == .Focus {
        uilibrary.tree_set_active_item(&runtime^.state^.ui_runtime, item, true)
        return uisemantics.semantic_apply_external_action(
            focus, uilibrary.tree_semantic_id(), .Focus)
    }
    params := uilibrary.Tree_List_Params{
        ji = runtime^.state^.julia_interface,
        ui_runtime = &runtime^.state^.ui_runtime,
        scroll_y = &runtime^.state^.ui_runtime.tree_scroll_y,
        list_panel = clip,
        visibility = {search = &runtime^.state^.ui_runtime.library_search},
    }
    _ = uilibrary.tree_apply_semantic_command(params, item, {target = id, kind = kind})
    return true
}

// Expand all existing branches through the tree owner for maximum-row acceptance.
scenario_favorites_expand_all :: proc(runtime: ^Scenario_Runtime) -> bool {
    state := runtime^.state
    snapshot := uisemantics.semantic_snapshot(state^.ui_runtime.semantic_focus)
    if snapshot == nil {
        return false
    }
    index := uisemantics.semantic_node_index(snapshot, uilibrary.tree_semantic_id())
    if index < 0 {
        return false
    }
    params := uilibrary.Tree_List_Params{
        ji = state^.julia_interface,
        ui_runtime = &state^.ui_runtime,
        scroll_y = &state^.ui_runtime.tree_scroll_y,
        list_panel = snapshot^.nodes[index].bounds,
        visibility = {search = &state^.ui_runtime.library_search},
    }
    projection := &state^.ui_runtime.tree_projection
    for item in projection^.items[:projection^.count] {
        if item.first_child != uilibrary.TREE_NO_ITEM {
            item_index := uilibrary.tree_projection_find(projection, item.key)
            target := &projection^.items[item_index]
            _ = uilibrary.tree_apply_structure_command(params, target, .Expand)
        }
    }
    return true
}

// Prove every eligible canonical animation fits the projection, motion and semantic registry.
scenario_favorites_capacity :: proc(runtime: ^Scenario_Runtime) -> bool {
    state := runtime^.state
    ji := state^.julia_interface
    eligible := 0
    for node, steps := ji^.animation_head, 0;
        node != nil && steps < ji^.animation_count;
        node, steps = node^.next_in_registry, steps + 1 {
        if node^.node_kind == .Animation {
            _, found := uianimation.animation_favorite_entry(
                &state^.preferences_runtime.collections_state, node^.stable_id)
            if !found {
                return false
            }
            eligible += 1
        }
    }
    projection := &state^.ui_runtime.tree_projection
    snapshot := uisemantics.semantic_snapshot(state^.ui_runtime.semantic_focus)
    if !projection^.valid || projection^.count != ji^.animation_count + eligible + 2 ||
        projection^.count != state^.ui_runtime.tree_motion.count ||
        eligible != state^.preferences_runtime.collections_state.entry_count ||
        eligible > collections.MUTATION_CAPACITY ||
        snapshot == nil {
        return false
    }
    for &item in projection^.items[:projection^.count] {
        if uisemantics.semantic_node_index(
            snapshot, uilibrary.tree_placement_semantic_id(&item)) < 0 {
            return false
        }
    }
    log.infof(
        "favorites_capacity_verified eligible=%d nodes=%d",
        eligible, projection^.count)
    return true
}

// Require exact ordered Favorites membership by unambiguous canonical animation names.
scenario_favorites_order :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    set := &runtime^.state^.preferences_runtime.collections_state
    remaining := text
    for entry in set^.entries[:set^.entry_count] {
        name, suffix := scenario_favorites_split(remaining)
        animation := scenario_find_animation(runtime^.state^.julia_interface, name)
        if animation == nil || entry.animation_id != animation^.stable_id {
            return false
        }
        remaining = suffix
    }
    return len(remaining) == 0
}

// Check placement identity, disclosure and visibility against the published tree.
scenario_favorites_remember_placement :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    item := scenario_favorites_item(runtime, argument)
    if item == nil {
        return false
    }
    if operation == "remember" {
        runtime^.favorites_memory.placement = item^.key
        return true
    }
    return runtime^.favorites_memory.placement != (uuid.Identifier{}) &&
        runtime^.favorites_memory.placement != item^.key
}

// Check placement selection, disclosure and visibility against the published tree.
scenario_favorites_placement_assertion :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    state := runtime^.state
    switch operation {
    case "absent":
        return scenario_favorites_item(runtime, argument) == nil
    case "remember", "replaced":
        return scenario_favorites_remember_placement(runtime, operation, argument)
    case "selected":
        item := scenario_favorites_item(runtime, argument)
        return item != nil && state^.ui_runtime.selected_tree_item_id == item^.key
    case "hidden":
        item := scenario_favorites_item(runtime, argument)
        snapshot := uisemantics.semantic_snapshot(state^.ui_runtime.semantic_focus)
        if item == nil || snapshot == nil {
            return false
        }
        index := uisemantics.semantic_node_index(
            snapshot, uilibrary.tree_placement_semantic_id(item))
        return index < 0 || .Visible not_in snapshot^.nodes[index].states
    case "selection_cleared":
        return state^.ui_runtime.selected_tree_item_id == (uuid.Identifier{})
    case "collapsed", "expanded":
        item := scenario_favorites_item(runtime, argument)
        return item != nil && item^.expanded == (operation == "expanded")
    case:
        return false
    }
}

// Remember or require an unchanged playback generation across placement removal.
scenario_favorites_playback :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    state := runtime^.state
    target := scenario_find_animation(state^.julia_interface, argument)
    if target == nil || state^.julia_interface^.selected_animation != target ||
        state^.julia_interface^.pending_animation_reset {
        return false
    }
    generation := state^.julia_runtime_service^.animation_generation
    if operation == "remember_playback" {
        runtime^.favorites_memory.playback = target^.stable_id
        runtime^.favorites_memory.animation_generation = generation
        return true
    }
    return runtime^.favorites_memory.playback == target^.stable_id &&
        runtime^.favorites_memory.animation_generation == generation
}

// Require truthful retained-failure feedback or its successful acknowledgement.
scenario_favorites_save_feedback :: proc(
    runtime: ^Scenario_Runtime, recovered: bool) -> bool {
    state := runtime^.state
    sections := ui.accordion_sections_for_layout(
        state^.ui_runtime.current_layout_mode, "", state)
    indicator := false
    for section in sections.items[:sections.count] {
        indicator = indicator || section.error_indicator &&
            len(section.accessible_value) > 0
    }
    failed := state^.preferences_runtime.user_data_failure_unresolved
    if recovered {
        return !failed && !indicator
    }
    return failed && indicator &&
        state^.preferences_runtime.collection_mutation_count > 0
}

// Dispatch explicit local tree, playback, capacity and retained-failure assertions.
scenario_assert_favorites :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    operation, argument := scenario_favorites_split(text)
    switch operation {
    case "capacity":
        return scenario_favorites_capacity(runtime)
    case "order":
        return scenario_favorites_order(runtime, argument)
    case "empty":
        return runtime^.state^.preferences_runtime.collections_state.entry_count == 0
    case "remember_playback", "playing":
        return scenario_favorites_playback(runtime, operation, argument)
    case "failure_retained", "recovered":
        return scenario_favorites_save_feedback(runtime, operation == "recovered")
    case:
        return scenario_favorites_placement_assertion(runtime, operation, argument)
    }
}

// Dispatch the bounded Favorites acceptance vocabulary without exposing SQL or model mutation.
scenario_issue_favorites_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    text := scenario.text_string(&command^.text)
    #partial switch command^.kind {
    case .Favorite_Control:
        return true, scenario_favorite_control(runtime, text)
    case .Library_Placement:
        return true, scenario_library_placement(runtime, text)
    case .Assert_Favorites:
        accepted := scenario_assert_favorites(runtime, text)
        if accepted && text == "failure_retained" {
            log.info("favorites_failure_observed")
        }
        return true, accepted
    case:
        return false, false
    }
}
