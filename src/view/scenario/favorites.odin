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
import uiaccordion "../ui/layout/accordion"
import uuid "core:encoding/uuid"
import log "core:log"

// One bounded placement and playback baseline for Favorites acceptance.
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

// Compare one custom placement name using `address|expected` scenario syntax.
scenario_favorites_name_matches :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    address, expected := scenario_favorites_split_on(text, '|')
    if address == text {
        return false
    }
    item := scenario_favorites_item(runtime, address)
    if item == nil {
        return false
    }
    set := &runtime^.state^.preferences_runtime.collections_state
    entry_index := collections.find_entry(set, item^.key)
    if entry_index < 0 {
        return false
    }
    entry := &set^.entries[entry_index]
    actual := string(entry.custom_name[:entry.custom_name_length])
    return actual == expected
}

// Split one bounded scenario string at its first requested delimiter.
scenario_favorites_split_on :: proc(
    text: string, delimiter: rune) -> (string, string) {
    for value, index in text {
        if value == delimiter {
            return text[:index], text[index + 1:]
        }
    }
    return text, ""
}

// Confirm the published Favorite editor is the ordinary effective input owner.
scenario_favorites_name_editor_focused :: proc(
    ui: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    focus := ui^.input.interaction_frame.effective_focus
    return uilibrary.library_entry_name_visible(ui) &&
        focus.kind == .Input_Box &&
        focus.id == uilibrary.TREE_ENTRY_NAME_INPUT_ID
}

// Override only scenario-authored pointer facts through the ordinary UI input path.
scenario_pointer_frame :: proc(
    runtime: ^Scenario_Runtime, frame: input.Input_Frame) -> input.Input_Frame {
    result := frame
    if runtime^.reorder_sample_active {
        result.sample_time_seconds = runtime^.reorder_sample_time
    } else {
        result.sample_time_seconds = max(
            result.sample_time_seconds, runtime^.reorder_sample_floor)
    }
    runtime^.reorder_frame_time = result.sample_time_seconds
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
        geometry.Rectangle(state^.ui_runtime.layout.ui_regions.world_rect), true)
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
    projection := &state^.ui_runtime.library.tree.projection
    index := uilibrary.tree_projection_find(projection, key)
    return &projection^.items[index] if index >= 0 else nil
}

// Address a published tree occurrence; hidden or disabled rows reject actions.
scenario_library_placement :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if text == "expand_all" {
        return scenario_favorites_expand_all(runtime)
    }
    if text == "scroll_top" {
        return scenario_library_queue_command(runtime,
            {target = uilibrary.tree_semantic_id(), kind = .Set_Scroll_Value})
    }
    if text == "focus_library" {
        return uisemantics.semantic_apply_external_action(
            runtime^.state^.ui_runtime.semantic_focus,
            uisemantics.semantic_control_id(.Accordion,
                int(viewmodel.Ui_Accordion_Section.Library) + 1),
            .Focus)
    }
    operation, address := scenario_favorites_split(text)
    if operation == "swap_sample" {
        return scenario_reorder_sample(runtime, address)
    }
    item := scenario_favorites_item(runtime, address)
    if item == nil {
        return false
    }
    if operation == "name_press" || operation == "name_release" {
        return scenario_library_name_pointer(runtime, item, operation)
    }
    if operation == "actions_focus" || operation == "actions_open" ||
        operation == "move_up" || operation == "move_down" {
        return scenario_reorder_control(runtime, item, operation)
    }
    return scenario_library_published_action(runtime, item, operation)
}

// Route pointer focus to the published placement-owned name input.
scenario_library_name_pointer :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string) -> bool {
    draft := &runtime^.state^.ui_runtime.library.entry_name
    if !draft^.active || draft^.entry_id != item^.key ||
        draft^.rect.width <= 0 || draft^.rect.height <= 0 {
        return false
    }
    pointer_operation := "press" if operation == "name_press" else "release"
    return scenario_favorites_pointer(
        runtime, draft^.rect, pointer_operation)
}

// scenario_library_published_action admits pointer and semantic actions on published tree rows.
scenario_library_published_action :: proc(
    runtime: ^Scenario_Runtime,
    item: ^viewmodel.Ui_Tree_Item, operation: string) -> bool {
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

// scenario_reorder_control addresses ordinary published disclosure and move controls.
scenario_reorder_control :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string) -> bool {
    state := runtime^.state
    action := uilibrary.TREE_ACTION_TOGGLE
    if operation == "move_up" {
        action = uilibrary.TREE_ACTION_UP
    } else if operation == "move_down" {
        action = uilibrary.TREE_ACTION_DOWN
    }
    id := viewmodel.Ui_Node_Id{domain = .Library_Action, local_id = action,
        stable_id = item^.key, generation = state^.julia_interface^.content_generation}
    kind := viewmodel.Ui_Focus_Command_Kind.Activate
    if operation == "actions_focus" {
        kind = .Focus
    } else if operation == "actions_open" {
        kind = .Expand
    }
    return scenario_library_queue_command(runtime, {target = id, kind = kind})
}

// scenario_library_queue_command validates now and defers mutations to the ordinary owner phase.
scenario_library_queue_command :: proc(
    runtime: ^Scenario_Runtime, command: viewmodel.Ui_Focus_Command) -> bool {
    accepted := uisemantics.semantic_apply_external_action(
        runtime^.state^.ui_runtime.semantic_focus,
        command.target, command.kind, command.numeric_value)
    if accepted && command.kind != .Focus {
        runtime^.pending_reorder_command = command
    }
    return accepted
}

// scenario_reorder_drain delivers addressed actions after keyboard resets the command buffer.
scenario_reorder_drain :: proc(runtime: ^Scenario_Runtime) {
    command := runtime^.pending_reorder_command
    runtime^.pending_reorder_command = {}
    if command.kind == .None {
        return
    }
    if !uisemantics.semantic_apply_external_action(
        runtime^.state^.ui_runtime.semantic_focus,
        command.target, command.kind, command.numeric_value) {
        log.error("scenario_reorder_command_rejected")
        runtime^.runner.status = .Failed
        runtime^.runner.failure_count += 1
    }
}

// scenario_reorder_sample freezes only the test input clock at an accepted swap's sample.
scenario_reorder_sample :: proc(runtime: ^Scenario_Runtime, sample: string) -> bool {
    if sample == "resume" {
        runtime^.reorder_sample_active = false
        return true
    }
    if sample == "hold" {
        runtime^.reorder_sample_time = runtime^.reorder_frame_time
        runtime^.reorder_sample_floor = runtime^.reorder_frame_time
        runtime^.reorder_sample_active = true
        return true
    }
    motion := &runtime^.state^.ui_runtime.library.actions.reorder
    if !motion^.active {
        return false
    }
    fraction: f64
    switch sample {
    case "start": fraction = 0
    case "middle": fraction = 0.5
    case: return false
    }
    sampled_at := motion^.start_seconds +
        fraction * uiaccordion.INTERFACE_TRANSITION_SECONDS
    if sampled_at < runtime^.reorder_sample_floor {
        return false
    }
    runtime^.reorder_sample_time = sampled_at
    runtime^.reorder_sample_floor = runtime^.reorder_sample_time
    runtime^.reorder_sample_active = true
    return true
}

// Resolve the supported action word to its semantic tree command.
scenario_library_command :: proc(
    operation: string) -> (viewmodel.Ui_Focus_Command_Kind, bool) {
    switch operation {
    case "focus": return .Focus, true
    case "select": return .Select, true
    case "expand": return .Expand, true
    case "collapse": return .Collapse, true
    }
    return {}, false
}

// Apply an admitted semantic tree action while preserving occurrence-specific keyboard focus.
scenario_library_apply :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string, clip: geometry.Rectangle) -> bool {
    focus := runtime^.state^.ui_runtime.semantic_focus
    id := uilibrary.tree_placement_semantic_id(item)
    kind, valid := scenario_library_command(operation)
    if !valid {
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
        scroll_y = &runtime^.state^.ui_runtime.library.tree.scroll_y,
        list_panel = clip,
        visibility = {search = &runtime^.state^.ui_runtime.library.search},
        reduce_motion =
            runtime^.state^.ui_runtime.preferences.values.interface.reduce_motion ||
                runtime^.state^.ui_runtime.platform_reduce_motion,
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
        scroll_y = &state^.ui_runtime.library.tree.scroll_y,
        list_panel = snapshot^.nodes[index].bounds,
        visibility = {search = &state^.ui_runtime.library.search},
        reduce_motion = state^.ui_runtime.preferences.values.interface.reduce_motion ||
            state^.ui_runtime.platform_reduce_motion,
    }
    projection := &state^.ui_runtime.library.tree.projection
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
    projection := &state^.ui_runtime.library.tree.projection
    snapshot := uisemantics.semantic_snapshot(state^.ui_runtime.semantic_focus)
    if !projection^.valid || projection^.count != ji^.animation_count + eligible + 2 ||
        projection^.count != state^.ui_runtime.library.motion.count ||
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
    indexes: [collections.ENTRY_CAPACITY]int
    count, failure := collections.ordered_siblings(
        set, collections.FAVORITES_COLLECTION_ID, {}, indexes[:])
    if failure != .None {
        log.errorf("scenario_favorites_order_rejected policy=%v", failure)
        return false
    }
    remaining := text
    for index in indexes[:count] {
        entry := set^.entries[index]
        name, suffix := scenario_favorites_split(remaining)
        animation := scenario_find_animation(runtime^.state^.julia_interface, name)
        if animation == nil || entry.animation_id != animation^.stable_id {
            return false
        }
        remaining = suffix
    }
    return len(remaining) == 0
}

// Compare the current placement with an explicitly remembered identity.
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
    remembered := runtime^.favorites_memory.placement
    if remembered == (uuid.Identifier{}) {
        return false
    }
    return (remembered == item^.key) == (operation == "same_placement")
}

// Check the addressed drawer's open choice without mistaking a closing tail for controls.
scenario_favorites_drawer :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    item := scenario_favorites_item(runtime, argument)
    if item == nil {
        return false
    }
    motion := runtime^.state^.ui_runtime.library.actions.drawer
    opened := motion.open && motion.entry_id == item^.key
    return opened if operation == "actions_open" else !motion.open
}

// Check placement selection, disclosure and visibility against the published tree.
scenario_favorites_placement_assertion :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    state := runtime^.state
    switch operation {
    case "absent":
        return scenario_favorites_item(runtime, argument) == nil
    case "remember", "replaced", "same_placement":
        return scenario_favorites_remember_placement(runtime, operation, argument)
    case "actions_open", "actions_closed":
        return scenario_favorites_drawer(runtime, operation, argument)
    case "selected":
        item := scenario_favorites_item(runtime, argument)
        return item != nil && state^.ui_runtime.library.tree.selected_item_id == item^.key
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
        return state^.ui_runtime.library.tree.selected_item_id == (uuid.Identifier{})
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
        state^.ui_runtime.layout.current_layout_mode, "", state)
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
        if handled, accepted := scenario_favorites_name_assertion(
            runtime, operation, argument); handled {
            return accepted
        }
        return scenario_favorites_placement_assertion(runtime, operation, argument)
    }
}

// Evaluate persisted-name, draft, and inline name-editor focus assertions.
scenario_favorites_name_assertion :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> (bool, bool) {
    draft := &runtime^.state^.ui_runtime.library.entry_name
    switch operation {
    case "name":
        return true, scenario_favorites_name_matches(runtime, argument)
    case "draft":
        return true, draft^.active &&
            string(draft^.value[:draft^.value_length]) == argument
    case "name_editor_focused":
        return true, scenario_favorites_name_editor_focused(
            &runtime^.state^.ui_runtime)
    case "name_editor_active":
        return true, draft^.active
    case "name_editor_input_focus":
        focus := runtime^.state^.ui_runtime.input.interaction_frame.effective_focus
        return true, focus.kind == .Input_Box &&
            focus.id == uilibrary.TREE_ENTRY_NAME_INPUT_ID
    case:
        return false, false
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
