#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "core:math"
import "base:runtime"

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
    if control.role == .Status {
        accesskit.accesskit_node_set_live(node, .Polite)
    }
}

// unix_configure_control_range publishes one complete finite numeric range.
unix_configure_control_range :: proc(
    node: ^accesskit.Node, range: portable.Numeric_Range) {
    if !range.present {return}
    accesskit.accesskit_node_set_min_numeric_value(node, range.minimum)
    accesskit.accesskit_node_set_max_numeric_value(node, range.maximum)
    accesskit.accesskit_node_set_numeric_value(node, range.current)
    accesskit.accesskit_node_set_numeric_value_step(node, range.step)
    orientation := accesskit.Orientation.Horizontal
    if range.vertical {orientation = .Vertical}
    accesskit.accesskit_node_set_orientation(node, orientation)
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
    if len(value) > 0 {
        accesskit.accesskit_node_set_value_with_length(
            node, cast(cstring)raw_data(value), uintptr(len(value)))
    }
    unix_configure_control_actions(node, control.actions)
    unix_configure_control_state(node, control)
    unix_configure_control_range(node, control.range)
    accesskit.accesskit_node_set_bounds(node, cast(accesskit.Rect)control.bounds)
}

// unix_control_root_update creates and transfers one complete synthetic root.
unix_control_root_update :: proc(
    publication: ^portable.Control_Tree_Publication,
    child_ids: ^[portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id,
    focus_id: accesskit.Node_Id) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    root := accesskit.accesskit_node_new(.Application)
    if root == nil {return nil}
    accesskit.accesskit_node_set_children(
        root, uintptr(publication^.control_count), &child_ids^[0])
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
    for control, index in publication^.controls[:publication^.control_count] {
        child_ids[index] = accesskit.Node_Id(control.native_id)
        if publication^.window_focused && control.focused {
            focus_id = child_ids[index]
        }
    }
    update := unix_control_root_update(publication, &child_ids, focus_id)
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
    for source, index in input.controls {
        validation_controls[index] = source.control
        validation_controls[index].native_id = u64(index + 2)
    }
    validation: portable.Control_Tree_Publication
    if portable.control_tree_build(&validation, {
            root_bounds = input.root_bounds,
            window_focused = input.window_focused,
            controls = validation_controls[:len(input.controls)],
        }) != .Ok {return false}
    for source, index in input.controls {
        native_id, resolved := portable.native_id_resolve(
            &owner^.native_ids, source.identity)
        if !resolved {return false}
        controls^[index] = source.control
        controls^[index].native_id = native_id
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
    if portable.protected_publish_controls(&owner^.control_publication, {
            root_bounds = input.root_bounds,
            window_focused = input.window_focused,
            controls = slice,
        }) != .Ok {return false}
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
    valid := .Set_Value in control^.actions && request.has_numeric_value &&
        !math.is_nan(value) && !math.is_inf(value) && control^.range.present &&
        value >= control^.range.minimum && value <= control^.range.maximum
    if !valid {return .Invalid_Value}
    destination^.kind = .Set_Value
    destination^.numeric_value = value
    return .Ok
}

// unix_map_click_action preserves toggle precedence over ordinary activation.
unix_map_click_action :: proc(
    control: ^portable.Control_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
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
    case .Blur: return .Unsupported_Action
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

// unix_copy_action_request copies one supported request into bounded owner storage.
unix_copy_action_request :: proc(
    owner: ^Adapter, request: ^accesskit.Action_Request) -> portable.Action_Queue_Status {
    if owner == nil || request == nil {return .Invalid_Target}
    generation: u64
    control_publication: portable.Control_Tree_Publication
    if portable.protected_control_snapshot(
            &owner^.control_publication, &control_publication) {
        generation = control_publication.generation
    } else {
        publication: portable.Static_Publication
        if !portable.protected_snapshot(&owner^.publication, &publication) {
            return .Closing
        }
        generation = publication.generation
    }
     if request^.action != .Click && request^.action != .Focus &&
         request^.action != .Increment && request^.action != .Decrement &&
         request^.action != .Set_Value {
        return .Invalid_Target
    }
    copied := portable.Queued_Action{
        kind = u16(request^.action),
        target_native_id = u64(request^.target_node),
        publication_generation = generation,
    }
    if request^.action == .Set_Value {
        if !request^.data.has_value ||
           request^.data.value.tag != .Numeric_Value {
            return .Invalid_Target
        }
        copied.numeric_value = request^.data.value.payload.numeric_value
        copied.has_numeric_value = true
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