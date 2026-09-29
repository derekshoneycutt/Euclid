#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

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

// unix_adapter_drain_action validates one copied request against current publication.
unix_adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    if owner == nil || destination == nil {return .Closing}
    request: portable.Queued_Action
    if !portable.action_queue_pop(&owner^.actions, &request) {return .Empty}
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
    publication: portable.Static_Publication
    if !portable.protected_snapshot(&owner^.publication, &publication) {
        return .Closing
    }
    if request^.action != .Click && request^.action != .Focus {
        return .Invalid_Target
    }
    copied := portable.Queued_Action{
        kind = u16(request^.action),
        target_native_id = u64(request^.target_node),
        publication_generation = publication.generation,
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