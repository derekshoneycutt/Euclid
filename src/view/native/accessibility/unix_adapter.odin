#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "core:math"
import "base:runtime"
import "core:log"
import "core:unicode/utf8"

// unix_configure_child copies the complete portable child record into AccessKit.
unix_configure_child :: proc(
    child: ^accesskit.Node, publication: ^portable.Static_Publication) {
    if publication^.child_role == .Button {
        accesskit.accesskit_node_set_label_with_length(
            child, cast(cstring)&publication^.label[0],
            uintptr(publication^.label_length))
        if !publication^.child_enabled {accesskit.accesskit_node_set_disabled(child)}
        if publication^.child_supports_focus {
            accesskit.accesskit_node_add_action(child, .Focus)
        }
        if publication^.child_supports_activate {
            accesskit.accesskit_node_add_action(child, .Click)
        }
    } else {
        accesskit.accesskit_node_set_value_with_length(
            child, cast(cstring)&publication^.label[0],
            uintptr(publication^.label_length))
    }
    accesskit.accesskit_node_set_bounds(
        child, cast(accesskit.Rect)publication^.child_bounds)
}

// unix_static_nodes creates the complete root and child records for one publication.
unix_static_nodes :: proc(
    publication: ^portable.Static_Publication) -> (^accesskit.Node, ^accesskit.Node) {
    root := accesskit.accesskit_node_new(.Application)
    child_role := accesskit.Role.Label
    if publication^.child_role == .Button {child_role = .Button}
    child := accesskit.accesskit_node_new(child_role)
    if root == nil || child == nil {
        if root != nil {accesskit.accesskit_node_free(root)}
        if child != nil {accesskit.accesskit_node_free(child)}
        return nil, nil
    }
    child_id := accesskit.Node_Id(publication^.child_id)
    accesskit.accesskit_node_set_children(root, 1, &child_id)
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    unix_configure_child(child, publication)
    return root, child
}

// unix_root_tree_update builds one complete root-only update after child removal.
unix_root_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    root := accesskit.accesskit_node_new(.Application)
    if root == nil {return nil}
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(1, root_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    return update
}

// unix_child_tree_update builds one complete rooted child update.
unix_child_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    child_id := accesskit.Node_Id(publication^.child_id)
    focus_id := root_id
    if publication^.window_focused && publication^.child_focused {
        focus_id = child_id
    }
    root, child := unix_static_nodes(publication)
    if root == nil {return nil}
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(2, focus_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        accesskit.accesskit_node_free(child)
        return nil
    }
    tree := accesskit.accesskit_tree_info_new(root_id)
    if tree == nil {
        accesskit.accesskit_tree_update_free(update)
        accesskit.accesskit_node_free(root)
        accesskit.accesskit_node_free(child)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    accesskit.accesskit_tree_update_push_node(update, child_id, child)
    accesskit.accesskit_tree_update_set_tree_info(update, tree)
    accesskit.accesskit_tree_update_set_tree_id(update, {})
    return update
}

// unix_tree_update translates one validated publication into AccessKit storage.
unix_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    if portable.publication_validate(publication) != .Ok {return nil}
    if !publication^.child_present {return unix_root_tree_update(publication)}
    return unix_child_tree_update(publication)
}

// unix_control_role maps one portable ordinary-control role to AccessKit.
unix_control_role :: proc(role: portable.Publication_Role) -> accesskit.Role {
    switch role {
    case .Checkbox: return .Check_Box
    case .Slider: return .Slider
    case .Status: return .Status
    case .Search_Input: return .Search_Input
    case .Text_Run: return .Text_Run
    case .Tree: return .Tree
    case .Tree_Item: return .Tree_Item
    case .Button, .Accordion_Header: return .Button
    case .Label: return .Label
    }
    return .Unknown
}

// unix_configure_control_actions advertises only owner-supported native actions.
unix_configure_control_actions :: proc(
    node: ^accesskit.Node, actions: portable.Publication_Action_Set) {
    if .Focus in actions {accesskit.accesskit_node_add_action(node, .Focus)}
    if .Activate in actions || .Toggle in actions {
        accesskit.accesskit_node_add_action(node, .Click)
    }
    if .Increment in actions {
        accesskit.accesskit_node_add_action(node, .Increment)
    }
    if .Decrement in actions {
        accesskit.accesskit_node_add_action(node, .Decrement)
    }
    if .Set_Value in actions {
        accesskit.accesskit_node_add_action(node, .Set_Value)
    }
    if .Replace_Selected_Text in actions {
        accesskit.accesskit_node_add_action(node, .Replace_Selected_Text)
    }
    if .Set_Text_Selection in actions {
        accesskit.accesskit_node_add_action(node, .Set_Text_Selection)
    }
    if .Select in actions {accesskit.accesskit_node_add_action(node, .Click)}
    if .Expand in actions {accesskit.accesskit_node_add_action(node, .Expand)}
    if .Collapse in actions {accesskit.accesskit_node_add_action(node, .Collapse)}
    if .Scroll in actions {
        accesskit.accesskit_node_add_action(node, .Scroll_Up)
        accesskit.accesskit_node_add_action(node, .Scroll_Down)
    }
}

// unix_configure_control_state publishes role-specific ordinary-control state.
unix_configure_control_state :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    if !control.enabled {accesskit.accesskit_node_set_disabled(node)}
    if control.role == .Checkbox {
        toggled := accesskit.Toggled.False
        if control.checked {toggled = .True}
        accesskit.accesskit_node_set_toggled(node, toggled)
    }
    if control.selected {
        accesskit.accesskit_node_set_selected(node, true)
    }
    if control.role == .Accordion_Header {
        accesskit.accesskit_node_set_expanded(node, control.expanded)
    }
    if control.role == .Tree_Item && .Toggle in control.actions {
        accesskit.accesskit_node_set_expanded(node, control.expanded)
    }
    if control.role == .Status {
        accesskit.accesskit_node_set_live(node, .Polite)
    }
}

// unix_configure_control_range publishes one complete finite numeric range.
unix_configure_control_range :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    range := control.range
    if !range.present {return}
    if control.role == .Tree {
        accesskit.accesskit_node_set_scroll_y(node, range.current)
        accesskit.accesskit_node_set_scroll_y_min(node, range.minimum)
        accesskit.accesskit_node_set_scroll_y_max(node, range.maximum)
    }
    accesskit.accesskit_node_set_min_numeric_value(node, range.minimum)
    accesskit.accesskit_node_set_max_numeric_value(node, range.maximum)
    accesskit.accesskit_node_set_numeric_value(node, range.current)
    accesskit.accesskit_node_set_numeric_value_step(node, range.step)
    orientation := accesskit.Orientation.Horizontal
    if range.vertical {orientation = .Vertical}
    accesskit.accesskit_node_set_orientation(node, orientation)
}

// unix_configure_control_set_facts publishes one TreeItem's structural position.
unix_configure_control_set_facts :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    if control.role != .Tree_Item {return}
    if control.level > 0 {
        accesskit.accesskit_node_set_level(node, uintptr(control.level))
    }
    if control.set_size > 0 {
        accesskit.accesskit_node_set_size_of_set(node, uintptr(control.set_size))
    }
    if control.position_in_set > 0 {
        accesskit.accesskit_node_set_position_in_set(
            node, uintptr(control.position_in_set))
    }
}

// unix_configure_control_text publishes copied editable text and selection facts.
unix_configure_control_text :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    if !control.text_present {return}
    placeholder := portable.control_publication_text(
        publication, control.placeholder_offset, control.placeholder_length)
    if len(placeholder) > 0 {
        accesskit.accesskit_node_set_placeholder_with_length(
            node, cast(cstring)raw_data(placeholder), uintptr(len(placeholder)))
    }
    if control.role != .Search_Input && control.character_count > 0 {
        first := int(control.character_offset)
        accesskit.accesskit_node_set_character_lengths(node,
            uintptr(control.character_count), &publication^.character_lengths[first])
    }
    if control.role != .Search_Input && control.word_start_count > 0 {
        first := int(control.word_start_offset)
        accesskit.accesskit_node_set_word_starts(node,
            uintptr(control.word_start_count), &publication^.word_starts[first])
    }
    if control.role != .Search_Input {return}
    selection_id := control.native_id
    for candidate in publication^.controls[:publication^.control_count] {
        if candidate.parent_native_id == control.native_id &&
           candidate.role == .Text_Run {
            selection_id = candidate.native_id
            break
        }
    }
    native_id := accesskit.Node_Id(selection_id)
    selection := accesskit.Text_Selection{
        anchor = {native_id, uintptr(control.anchor_character)},
        focus = {native_id, uintptr(control.cursor_character)},
    }
    accesskit.accesskit_node_set_text_selection(node, selection)
}

// unix_configure_control copies one complete portable record into AccessKit.
unix_configure_control :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    label := portable.control_publication_text(
        publication, control.label_offset, control.label_length)
    value := portable.control_publication_text(
        publication, control.value_offset, control.value_length)
    accesskit.accesskit_node_set_label_with_length(
        node, cast(cstring)raw_data(label), uintptr(len(label)))
    if control.role == .Text_Run ||
       control.role != .Search_Input && len(value) > 0 {
        accesskit.accesskit_node_set_value_with_length(
            node, cast(cstring)raw_data(value), uintptr(len(value)))
    }
    unix_configure_control_actions(node, control.actions)
    unix_configure_control_state(node, control)
    unix_configure_control_range(node, control)
    unix_configure_control_set_facts(node, control)
    unix_configure_control_text(node, publication, control)
    accesskit.accesskit_node_set_bounds(node, cast(accesskit.Rect)control.bounds)
}

// unix_configure_control_hierarchy publishes ordered children and active descendant.
unix_configure_control_hierarchy :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    child_ids: [portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id
    child_count := 0
    for candidate in publication^.controls[:publication^.control_count] {
        if candidate.parent_native_id != control.native_id {continue}
        child_ids[child_count] = accesskit.Node_Id(candidate.native_id)
        child_count += 1
    }
    accesskit.accesskit_node_set_children(
        node, uintptr(child_count), &child_ids[0])
    if control.active_descendant_native_id != 0 {
        accesskit.accesskit_node_set_active_descendant(
            node, accesskit.Node_Id(control.active_descendant_native_id))
    } else {
        accesskit.accesskit_node_clear_active_descendant(node)
    }
    if control.controls_native_id != 0 {
        relation := accesskit.Node_Id(control.controls_native_id)
        accesskit.accesskit_node_set_controls(node, 1, &relation)
    }
}

// unix_control_root_update creates and transfers one complete synthetic root.
unix_control_root_update :: proc(
    publication: ^portable.Control_Tree_Publication,
    child_ids: ^[portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id,
    child_count: int,
    focus_id: accesskit.Node_Id) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    root := accesskit.accesskit_node_new(.Application)
    if root == nil {return nil}
    accesskit.accesskit_node_set_children(
        root, uintptr(child_count), &child_ids^[0])
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(
        uintptr(publication^.control_count + 1), focus_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        return nil
    }
    tree := accesskit.accesskit_tree_info_new(root_id)
    if tree == nil {
        accesskit.accesskit_tree_update_free(update)
        accesskit.accesskit_node_free(root)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    accesskit.accesskit_tree_update_set_tree_info(update, tree)
    accesskit.accesskit_tree_update_set_tree_id(update, {})
    return update
}

// unix_control_push_nodes transfers every complete child into one tree update.
unix_control_push_nodes :: proc(
    update: ^accesskit.Tree_Update,
    publication: ^portable.Control_Tree_Publication) -> bool {
    for control in publication^.controls[:publication^.control_count] {
        child := accesskit.accesskit_node_new(unix_control_role(control.role))
        if child == nil {return false}
        unix_configure_control(child, publication, control)
        unix_configure_control_hierarchy(child, publication, control)
        accesskit.accesskit_tree_update_push_node(
            update, accesskit.Node_Id(control.native_id), child)
    }
    return true
}

// unix_control_tree_update builds one complete rooted ordinary-control update.
unix_control_tree_update :: proc(
    publication: ^portable.Control_Tree_Publication) -> ^accesskit.Tree_Update {
    if portable.control_tree_validate(publication) != .Ok {return nil}
    focus_id := accesskit.Node_Id(publication^.root_id)
    child_ids: [portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id
    child_count := 0
    for control in publication^.controls[:publication^.control_count] {
        if control.parent_native_id == publication^.root_id {
            child_ids[child_count] = accesskit.Node_Id(control.native_id)
            child_count += 1
        }
        if publication^.window_focused && control.focused {
            focus_id = accesskit.Node_Id(control.native_id)
        }
    }
    update := unix_control_root_update(
        publication, &child_ids, child_count, focus_id)
    if update == nil {return nil}
    if !unix_control_push_nodes(update, publication) {
        accesskit.accesskit_tree_update_free(update)
        return nil
    }
    return update
}

// unix_adapter_notify_update forwards one changed complete publication if active.
unix_adapter_notify_update :: proc(owner: ^Adapter) {
    publication: portable.Static_Publication
    if !portable.protected_snapshot(&owner^.publication, &publication) ||
       publication.generation == owner^.delivered_generation {
        return
    }
    owner^.delivered_generation = publication.generation
    adapter_record_diagnostic(owner, .Update)
    accesskit.accesskit_unix_adapter_update_if_active(
        cast(^accesskit.Unix_Adapter)owner^.native,
        unix_activation_callback, owner)
    accesskit.accesskit_unix_adapter_update_window_focus_state(
        cast(^accesskit.Unix_Adapter)owner^.native, publication.window_focused)
}

// unix_adapter_notify_control_update forwards one changed complete control tree.
unix_adapter_notify_control_update :: proc(owner: ^Adapter) {
    publication: portable.Control_Tree_Publication
    if !portable.protected_control_snapshot(
            &owner^.control_publication, &publication) ||
       publication.generation == owner^.delivered_generation {
        return
    }
    owner^.delivered_generation = publication.generation
    adapter_record_diagnostic(owner, .Update)
    accesskit.accesskit_unix_adapter_update_if_active(
        cast(^accesskit.Unix_Adapter)owner^.native,
        unix_activation_callback, owner)
    accesskit.accesskit_unix_adapter_update_window_focus_state(
        cast(^accesskit.Unix_Adapter)owner^.native, publication.window_focused)
}

// unix_adapter_stage_controls resolves native IDs into complete portable records.
unix_adapter_input_index :: proc(
    input: Adapter_Tree_Input,
    identity: portable.Qualified_Identity) -> int {
    if identity == {} {return -1}
    for source, index in input.controls {
        if source.identity == identity {return index}
    }
    return -1
}

// unix_adapter_stage_validation builds temporary IDs without consuming registry IDs.
unix_adapter_stage_validation :: proc(
    input: Adapter_Tree_Input,
    controls: ^[portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input) ->
    bool {
    for source, index in input.controls {
        for prior in input.controls[:index] {
            if prior.identity == source.identity {
                log.warnf("accessibility_control_identity_duplicate index=%d prior=%d",
                    index, unix_adapter_input_index(input, source.identity))
                return false
            }
        }
        controls^[index] = source.control
        controls^[index].native_id = u64(index + 2)
        parent_index := unix_adapter_input_index(input, source.parent_identity)
        if source.parent_identity != {} && parent_index < 0 {return false}
        if parent_index >= 0 {controls^[index].parent_native_id = u64(parent_index + 2)}
        active_index := unix_adapter_input_index(
            input, source.active_descendant_identity)
        if source.active_descendant_identity != {} && active_index < 0 {return false}
        if active_index >= 0 {
            controls^[index].active_descendant_native_id = u64(active_index + 2)
        }
        controls_index := unix_adapter_input_index(input, source.controls_identity)
        if source.controls_identity != {} && controls_index < 0 {return false}
        if controls_index >= 0 {
            controls^[index].controls_native_id = u64(controls_index + 2)
        }
    }
    validation: portable.Control_Tree_Publication
    status := portable.control_tree_build(&validation, {
        root_bounds = input.root_bounds, window_focused = input.window_focused,
        controls = controls^[:len(input.controls)],
    })
    if status != .Ok {
        log.warnf("accessibility_control_validation_failed status=%v controls=%d",
            status, len(input.controls))
        return false
    }
    return true
}

// unix_adapter_resolve_relation maps one optional semantic identity to a native ID.
unix_adapter_resolve_relation :: proc(
    input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64,
    identity: portable.Qualified_Identity) -> (u64, bool) {
    if identity == {} {return 0, true}
    index := unix_adapter_input_index(input, identity)
    if index < 0 {return 0, false}
    return native_ids^[index], true
}

// unix_adapter_resolve_control_ids assigns monotonic IDs to staged identities.
unix_adapter_resolve_control_ids :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64) -> bool {
    for source, index in input.controls {
        native_id, resolved := portable.native_id_resolve(
            &owner^.native_ids, source.identity)
        if !resolved {
            log.warnf(
                "accessibility_control_identity_rejected index=%d owner=%d " +
                "local_id=%d has_uuid=%v registry_count=%d",
                index, source.identity.owner_domain, source.identity.local_id,
                source.identity.stable_uuid != ([16]u8{}), owner^.native_ids.count)
            return false
        }
        native_ids^[index] = native_id
    }
    return true
}

// unix_adapter_stage_control resolves one record's hierarchy relations.
unix_adapter_stage_control :: proc(
    input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64,
    source: Adapter_Control_Input, index: int,
    destination: ^portable.Control_Publication_Input) -> bool {
    destination^ = source.control
    destination^.native_id = native_ids^[index]
    parent_id, parent_ok := unix_adapter_resolve_relation(
        input, native_ids, source.parent_identity)
    active_id, active_ok := unix_adapter_resolve_relation(
        input, native_ids, source.active_descendant_identity)
    controls_id, controls_ok := unix_adapter_resolve_relation(
        input, native_ids, source.controls_identity)
    if !parent_ok || !active_ok || !controls_ok {return false}
    destination^.parent_native_id = parent_id
    destination^.active_descendant_native_id = active_id
    destination^.controls_native_id = controls_id
    return true
}

// unix_adapter_stage_controls resolves native IDs into complete portable records.
unix_adapter_stage_controls :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input,
    controls: ^[portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input,
    count: ^int) -> bool {
    if owner == nil || controls == nil || count == nil ||
       len(input.controls) > portable.CONTROL_NODE_CAPACITY {return false}
    if owner^.native_ids.count == 0 {
        portable.native_id_registry_init(&owner^.native_ids)
    }
    validation_controls:
        [portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input
    if !unix_adapter_stage_validation(input, &validation_controls) {return false}
    native_ids: [portable.CONTROL_NODE_CAPACITY]u64
    if !unix_adapter_resolve_control_ids(owner, input, &native_ids) {return false}
    for source, index in input.controls {
        if !unix_adapter_stage_control(
            input, &native_ids, source, index, &controls^[index]) {return false}
    }
    count^ = len(input.controls)
    return true
}

// unix_adapter_retire_absent_controls retires IDs missing from the new tree.
unix_adapter_retire_absent_controls :: proc(
    owner: ^Adapter, controls: []portable.Control_Publication_Input) {
    for old_id in owner^.control_native_ids[:owner^.control_count] {
        retained := false
        for control in controls {
            if control.native_id == old_id {retained = true; break}
        }
        if !retained {_ = portable.native_id_retire(&owner^.native_ids, old_id)}
    }
    owner^.control_native_ids = {}
    owner^.control_count = len(controls)
    for control, index in controls {
        owner^.control_native_ids[index] = control.native_id
    }
}

// unix_adapter_publish_controls publishes one complete ordinary-control tree.
unix_adapter_publish_controls :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input) -> bool {
    if owner == nil {return false}
    controls: [portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input
    control_count: int
    if !unix_adapter_stage_controls(owner, input, &controls, &control_count) {
        return false
    }
    slice := controls[:control_count]
    status := portable.protected_publish_controls(&owner^.control_publication, {
            root_bounds = input.root_bounds,
            window_focused = input.window_focused,
            controls = slice,
        })
    if status != .Ok {
        log.warnf("accessibility_control_publish_failed status=%v controls=%d",
            status, control_count)
        return false
    }
    unix_adapter_retire_absent_controls(owner, slice)
    if owner^.native == nil {
        native := accesskit.accesskit_unix_adapter_new(
            unix_activation_callback, owner, unix_action_callback, owner,
            unix_deactivation_callback, owner)
        owner^.native = rawptr(native)
        if owner^.native == nil {
            unix_adapter_close_admission(owner)
            return false
        }
        return true
    }
    unix_adapter_notify_control_update(owner)
    return true
}

// unix_adapter_create_button admits the first committed real-button publication.
unix_adapter_create_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    if owner == nil || owner^.native != nil || !input.present {return false}
    portable.native_id_registry_init(&owner^.native_ids)
    child_id, child_ok := portable.native_id_resolve(&owner^.native_ids, identity)
    if !child_ok {return false}
    publication_input := input
    publication_input.child_id = child_id
    if portable.protected_publish_button(
        &owner^.publication, publication_input) != .Ok {
        return false
    }
    native := accesskit.accesskit_unix_adapter_new(
        unix_activation_callback, owner, unix_action_callback, owner,
        unix_deactivation_callback, owner)
    owner^.native = rawptr(native)
    if owner^.native == nil {
        unix_adapter_close_admission(owner)
        return false
    }
    owner^.child_identity = identity
    owner^.child_native_id = child_id
    owner^.child_present = true
    return true
}

// unix_adapter_publish_button publishes changes and retires removed identities.
unix_adapter_publish_present_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    child_id, child_ok := portable.native_id_resolve(&owner^.native_ids, identity)
    if !child_ok {return false}
    publication_input := input
    publication_input.child_id = child_id
    if portable.protected_publish_button(
        &owner^.publication, publication_input) != .Ok {
        return false
    }
    if owner^.child_present && owner^.child_native_id != child_id {
        _ = portable.native_id_retire(
            &owner^.native_ids, owner^.child_native_id)
    }
    owner^.child_identity = identity
    owner^.child_native_id = child_id
    owner^.child_present = true
    return true
}

// unix_adapter_publish_removed_button retires the prior child after root publication.
unix_adapter_publish_removed_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input) -> bool {
    if portable.protected_publish_button(&owner^.publication, input) != .Ok {
        return false
    }
    if owner^.child_present {
        _ = portable.native_id_retire(
            &owner^.native_ids, owner^.child_native_id)
    }
    owner^.child_identity = {}
    owner^.child_native_id = 0
    owner^.child_present = false
    return true
}

// unix_adapter_publish_button publishes changes and retires removed identities.
unix_adapter_publish_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    if owner == nil {return false}
    if owner^.native == nil {
        if !input.present {return true}
        return unix_adapter_create_button(owner, input, identity)
    }
    published := false
    if input.present {
        published = unix_adapter_publish_present_button(owner, input, identity)
    } else {
        published = unix_adapter_publish_removed_button(owner, input)
    }
    if !published {return false}
    unix_adapter_notify_update(owner)
    return true
}

// unix_adapter_validate_action resolves one current request into display-owned facts.
unix_adapter_validate_action :: proc(
    owner: ^Adapter, request: portable.Queued_Action,
    publication: portable.Static_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if request.publication_generation != publication.generation {
        return .Stale_Generation
    }
    identity, found := portable.native_id_lookup(
        &owner^.native_ids, request.target_native_id)
    if !found {
        return .Unknown_Target
    }
    if !publication.child_present || request.target_native_id != publication.child_id {
        return .Removed_Target
    }
    if request.kind == u16(accesskit.Action.Focus) &&
       publication.child_supports_focus {
        destination^ = {kind = .Focus, identity = identity}
        return .Ok
    }
    if request.kind == u16(accesskit.Action.Click) &&
       publication.child_supports_activate {
        if !publication.child_enabled {
            return .Disabled_Target
        }
        destination^ = {kind = .Activate, identity = identity}
        return .Ok
    }
    return .Unsupported_Action
}

// unix_control_by_native_id finds one current complete publication record.
unix_control_by_native_id :: proc(
    publication: ^portable.Control_Tree_Publication,
    native_id: u64) -> ^portable.Control_Publication {
    for index in 0..<publication^.control_count {
        candidate := &publication^.controls[index]
        if candidate^.native_id == native_id {return candidate}
    }
    return nil
}

// unix_validate_numeric_action validates and copies one exact ranged value.
unix_validate_numeric_action :: proc(
    control: ^portable.Control_Publication,
    request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    value := request.numeric_value
    valid := request.has_numeric_value &&
        !math.is_nan(value) && !math.is_inf(value) && control^.range.present &&
        value >= control^.range.minimum && value <= control^.range.maximum
    if !valid {return .Invalid_Value}
    if control^.role == .Tree && .Scroll in control^.actions {
        destination^.kind = .Set_Scroll_Value
        destination^.numeric_value = value
        return .Ok
    }
    if .Set_Value not_in control^.actions {return .Invalid_Value}
    destination^.kind = .Set_Value
    destination^.numeric_value = value
    return .Ok
}

// unix_validate_text_action copies one already-bounded UTF-8 replacement.
unix_validate_text_action :: proc(
    control: ^portable.Control_Publication, request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if .Replace_Selected_Text not_in control^.actions ||
       request.payload_length < 0 ||
       request.payload_length > len(request.payload) {return .Invalid_Value}
    payload := request.payload
    text := string(payload[:request.payload_length])
    if !utf8.valid_string(text) {return .Invalid_Value}
    destination^.kind = .Replace_Selected_Text
    if request.replace_entire_text {destination^.kind = .Replace_Text}
    destination^.payload_length = request.payload_length
    copy(destination^.payload[:request.payload_length],
        payload[:request.payload_length])
    return .Ok
}

// unix_validate_selection_action checks character indices against current text.
unix_validate_selection_action :: proc(
    control: ^portable.Control_Publication, request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if .Set_Text_Selection not_in control^.actions || !control^.text_present ||
       request.selection_anchor > control^.character_count ||
       request.selection_focus > control^.character_count {
        return .Invalid_Value
    }
    destination^.kind = .Set_Text_Selection
    destination^.selection_anchor = request.selection_anchor
    destination^.selection_focus = request.selection_focus
    return .Ok
}

// unix_map_click_action toggles branches and selects leaf TreeItems.
unix_map_click_action :: proc(
    control: ^portable.Control_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if control^.role == .Tree_Item && .Toggle in control^.actions {
        destination^.kind = .Toggle
        return .Ok
    }
    if .Select in control^.actions {destination^.kind = .Select; return .Ok}
    if .Toggle in control^.actions {destination^.kind = .Toggle; return .Ok}
    if .Activate in control^.actions {destination^.kind = .Activate; return .Ok}
    return .Unsupported_Action
}

// unix_map_control_action maps one supported native action to its owner command.
unix_map_control_action :: proc(
    control: ^portable.Control_Publication,
    request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    required: portable.Publication_Action
    mapped: Adapter_Action_Kind
    action := accesskit.Action(request.kind)
    switch action {
    case .Focus:
        required, mapped = .Focus, .Focus
    case .Click:
        return unix_map_click_action(control, destination)
    case .Increment:
        required, mapped = .Increment, .Increment
    case .Decrement:
        required, mapped = .Decrement, .Decrement
    case .Set_Value:
        return unix_validate_numeric_action(control, request, destination)
    case .Replace_Selected_Text:
        return unix_validate_text_action(control, request, destination)
    case .Set_Text_Selection:
        return unix_validate_selection_action(control, request, destination)
    case .Expand:
        required, mapped = .Expand, .Expand
    case .Collapse:
        required, mapped = .Collapse, .Collapse
    case .Scroll_Up:
        required, mapped = .Scroll, .Scroll
        destination^.numeric_value = -1
    case .Scroll_Down:
        required, mapped = .Scroll, .Scroll
        destination^.numeric_value = 1
    case .Blur, .Scroll_Left, .Scroll_Right, .Scroll_Into_View,
         .Set_Scroll_Offset:
        return .Unsupported_Action
    }
    if required not_in control^.actions {return .Unsupported_Action}
    destination^.kind = mapped
    return .Ok
}

// unix_adapter_validate_control_action resolves one current ordinary-control request.
unix_adapter_validate_control_action :: proc(
    owner: ^Adapter, request: portable.Queued_Action,
    publication: ^portable.Control_Tree_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if request.publication_generation != publication^.generation {
        return .Stale_Generation
    }
    identity, found := portable.native_id_lookup(
        &owner^.native_ids, request.target_native_id)
    if !found {return .Unknown_Target}
    control := unix_control_by_native_id(publication, request.target_native_id)
    if control == nil {return .Removed_Target}
    if !control^.enabled {return .Disabled_Target}
    destination^.identity = identity
    return unix_map_control_action(control, request, destination)
}

// unix_adapter_drain_action validates one copied request against current publication.
unix_adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    if owner == nil || destination == nil {return .Closing}
    request: portable.Queued_Action
    if !portable.action_queue_pop(&owner^.actions, &request) {return .Empty}
    control_publication: portable.Control_Tree_Publication
    if portable.protected_control_snapshot(
            &owner^.control_publication, &control_publication) {
        status := unix_adapter_validate_control_action(
            owner, request, &control_publication, destination)
        adapter_record_action_rejection(owner, status)
        return status
    }
    publication: portable.Static_Publication
    if !portable.protected_snapshot(&owner^.publication, &publication) {
        adapter_record_action_rejection(owner, .Closing)
        return .Closing
    }
    status := unix_adapter_validate_action(
        owner, request, publication, destination)
    adapter_record_action_rejection(owner, status)
    return status
}

// unix_activation_callback transfers one complete protected tree to AccessKit.
unix_activation_callback :: proc "c" (user_data: rawptr) -> ^accesskit.Tree_Update {
    context = runtime.default_context()
    owner := cast(^Adapter)user_data
    adapter_record_diagnostic(owner, .Activation)
    control_publication: portable.Control_Tree_Publication
    if owner != nil && portable.protected_control_snapshot(
            &owner^.control_publication, &control_publication) {
        return unix_control_tree_update(&control_publication)
    }
    publication: portable.Static_Publication
    if owner == nil ||
       !portable.protected_snapshot(&owner^.publication, &publication) {
        adapter_record_diagnostic(owner, .Rejected_Callback)
        return nil
    }
    return unix_tree_update(&publication)
}

// unix_action_generation snapshots the generation against which ingress validates.
unix_action_generation :: proc(owner: ^Adapter) -> (u64, bool) {
    controls: portable.Control_Tree_Publication
    if portable.protected_control_snapshot(&owner^.control_publication, &controls) {
        return controls.generation, true
    }
    publication: portable.Static_Publication
    if portable.protected_snapshot(&owner^.publication, &publication) {
        return publication.generation, true
    }
    return 0, false
}

// unix_action_supported admits only actions translated by this adapter.
unix_action_supported :: proc(action: accesskit.Action) -> bool {
    #partial switch action {
    case .Click, .Focus, .Increment, .Decrement, .Set_Value,
         .Replace_Selected_Text, .Set_Text_Selection, .Expand, .Collapse,
         .Scroll_Up, .Scroll_Down:
        return true
    case: return false
    }
}

// unix_copy_text_value copies one native string payload into bounded storage.
unix_copy_text_value :: proc(
    request: ^accesskit.Action_Request,
    copied: ^portable.Queued_Action) -> portable.Action_Queue_Status {
    if !request^.data.has_value || request^.data.value.tag != .Value ||
       request^.data.value.payload.value == nil {return .Invalid_Target}
    source := cast([^]u8)request^.data.value.payload.value
    for copied^.payload_length < len(copied^.payload) &&
        source[copied^.payload_length] != 0 {
        copied^.payload[copied^.payload_length] = source[copied^.payload_length]
        copied^.payload_length += 1
    }
    if copied^.payload_length == len(copied^.payload) &&
       source[copied^.payload_length] != 0 {return .Payload_Overflow}
    return .Ok
}

// unix_text_run_target resolves the position node for one editable owner.
unix_text_run_target :: proc(
    publication: ^portable.Control_Tree_Publication,
    owner_id: u64) -> accesskit.Node_Id {
    for control in publication^.controls[:publication^.control_count] {
        if control.parent_native_id == owner_id && control.role == .Text_Run {
            return accesskit.Node_Id(control.native_id)
        }
    }
    return accesskit.Node_Id(owner_id)
}

// unix_copy_selection_value validates and copies one TextRun selection payload.
unix_copy_selection_value :: proc(
    request: ^accesskit.Action_Request,
    publication: ^portable.Control_Tree_Publication,
    copied: ^portable.Queued_Action) -> portable.Action_Queue_Status {
    if !request^.data.has_value ||
       request^.data.value.tag != .Set_Text_Selection {return .Invalid_Target}
    selection := request^.data.value.payload.set_text_selection
    target := unix_text_run_target(publication, copied^.target_native_id)
    if selection.anchor.node != target || selection.focus.node != target ||
       selection.anchor.character_index > uintptr(max(u16)) ||
       selection.focus.character_index > uintptr(max(u16)) {
        return .Invalid_Target
    }
    copied^.selection_anchor = u16(selection.anchor.character_index)
    copied^.selection_focus = u16(selection.focus.character_index)
    return .Ok
}

// unix_copy_action_request copies one supported request into bounded owner storage.
unix_copy_action_request :: proc(
    owner: ^Adapter, request: ^accesskit.Action_Request) -> portable.Action_Queue_Status {
    if owner == nil || request == nil {return .Invalid_Target}
    generation, live := unix_action_generation(owner)
    if !live {return .Closing}
    control_publication: portable.Control_Tree_Publication
    _ = portable.protected_control_snapshot(
        &owner^.control_publication, &control_publication)
    if !unix_action_supported(request^.action) {return .Invalid_Target}
    copied := portable.Queued_Action{
        kind = u16(request^.action),
        target_native_id = u64(request^.target_node),
        publication_generation = generation,
    }
    if request^.action == .Set_Value && request^.data.has_value &&
       request^.data.value.tag == .Numeric_Value {
        copied.numeric_value = request^.data.value.payload.numeric_value
        copied.has_numeric_value = true
    }
    text_value := request^.action == .Replace_Selected_Text ||
        request^.action == .Set_Value && request^.data.has_value &&
        request^.data.value.tag == .Value
    if request^.action == .Set_Value &&
       !copied.has_numeric_value && !text_value {return .Invalid_Target}
    if text_value {
        copied.replace_entire_text = request^.action == .Set_Value
        copied.kind = u16(accesskit.Action.Replace_Selected_Text)
        status := unix_copy_text_value(request, &copied)
        if status != .Ok {return status}
    }
    if request^.action == .Set_Text_Selection {
        status := unix_copy_selection_value(
            request, &control_publication, &copied)
        if status != .Ok {return status}
    }
    return portable.action_queue_push(&owner^.actions, &copied)
}

// unix_action_callback copies supported ingress and frees upstream ownership once.
unix_action_callback :: proc "c" (
    request: ^accesskit.Action_Request, user_data: rawptr) {
    context = runtime.default_context()
    owner := cast(^Adapter)user_data
    adapter_record_diagnostic(owner, .Action)
    if request == nil {return}
    defer accesskit.accesskit_action_request_free(request)
    _ = unix_copy_action_request(owner, request)
}

// unix_deactivation_callback records that native clients no longer need updates.
unix_deactivation_callback :: proc "c" (user_data: rawptr) {
    context = runtime.default_context()
    adapter_record_diagnostic(cast(^Adapter)user_data, .Deactivation)
}

// unix_adapter_close_admission rejects callbacks before native teardown begins.
unix_adapter_close_admission :: proc(owner: ^Adapter) {
    if owner == nil {return}
    portable.protected_close(&owner^.publication)
    portable.protected_control_close(&owner^.control_publication)
    portable.action_queue_close(&owner^.actions)
}

// unix_adapter_create admits one static Linux tree without blocking application startup.
unix_adapter_create :: proc(
    owner: ^Adapter, width, height: f64, focused: bool,
    fail_at: Adapter_Create_Failure = .None) -> bool {
    if owner == nil || owner^.native != nil {return false}
    portable.native_id_registry_init(&owner^.native_ids)
    child_id, child_ok := portable.native_id_resolve(&owner^.native_ids, {
        domain = .Synthetic,
        local_id = portable.STATIC_CHILD_ID,
    })
    if !child_ok || child_id != portable.STATIC_CHILD_ID {return false}
    if portable.protected_publish(
        &owner^.publication, width, height, focused) != .Ok {
        return false
    }
    if fail_at == .After_Publication {
        unix_adapter_close_admission(owner)
        return false
    }
    native := accesskit.accesskit_unix_adapter_new(
        unix_activation_callback, owner, unix_action_callback, owner,
        unix_deactivation_callback, owner)
    owner^.native = rawptr(native)
    if owner^.native != nil {return true}
    unix_adapter_close_admission(owner)
    return false
}

// unix_adapter_set_root_bounds forwards known X11 outer and inner rectangles.
unix_adapter_set_root_bounds :: proc(
    owner: ^Adapter, outer, inner: portable.Bounds) {
    if owner == nil || owner^.native == nil {return}
    accesskit.accesskit_unix_adapter_set_root_window_bounds(
        cast(^accesskit.Unix_Adapter)owner^.native,
        cast(accesskit.Rect)outer, cast(accesskit.Rect)inner)
}

// unix_adapter_destroy closes callback admission before freeing the native adapter.
unix_adapter_destroy :: proc(owner: ^Adapter) {
    if owner == nil {return}
    unix_adapter_close_admission(owner)
    if owner^.native != nil {
        accesskit.accesskit_unix_adapter_free(
            cast(^accesskit.Unix_Adapter)owner^.native)
    }
    owner^.native = nil
    adapter_record_diagnostic(owner, .Destroy)
}