#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "base:runtime"

// unix_static_nodes creates the complete root and child records for one publication.
unix_static_nodes :: proc(
    publication: ^portable.Static_Publication) -> (^accesskit.Node, ^accesskit.Node) {
    root := accesskit.accesskit_node_new(.Application)
    child := accesskit.accesskit_node_new(.Label)
    if root == nil || child == nil {
        if root != nil {accesskit.accesskit_node_free(root)}
        if child != nil {accesskit.accesskit_node_free(child)}
        return nil, nil
    }
    child_id := accesskit.Node_Id(publication^.child_id)
    accesskit.accesskit_node_set_children(root, 1, &child_id)
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    accesskit.accesskit_node_set_value_with_length(
        child, cast(cstring)&publication^.label[0],
        uintptr(publication^.label_length))
    accesskit.accesskit_node_set_bounds(
        child, cast(accesskit.Rect)publication^.child_bounds)
    return root, child
}

// unix_tree_update translates one validated static publication into AccessKit storage.
unix_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    if portable.publication_validate(publication) != .Ok {return nil}
    root_id := accesskit.Node_Id(publication^.root_id)
    child_id := accesskit.Node_Id(publication^.child_id)
    root, child := unix_static_nodes(publication)
    if root == nil {return nil}
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(2, root_id)
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

// unix_action_callback frees unsupported Phase 1 requests without application mutation.
unix_action_callback :: proc "c" (
    request: ^accesskit.Action_Request, user_data: rawptr) {
    context = runtime.default_context()
    adapter_record_diagnostic(cast(^Adapter)user_data, .Action)
    if request != nil {accesskit.accesskit_action_request_free(request)}
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

// unix_adapter_update publishes current static bounds and host focus.
unix_adapter_update :: proc(
    owner: ^Adapter, width, height: f64, focused: bool) -> bool {
    if owner == nil || owner^.native == nil {return false}
    if portable.protected_publish(
        &owner^.publication, width, height, focused) != .Ok {
        return false
    }
    publication: portable.Static_Publication
    if !portable.protected_snapshot(&owner^.publication, &publication) {
        return false
    }
    if publication.generation == owner^.delivered_generation {return true}
    owner^.delivered_generation = publication.generation
    adapter_record_diagnostic(owner, .Update)
    accesskit.accesskit_unix_adapter_update_if_active(
        cast(^accesskit.Unix_Adapter)owner^.native,
        unix_activation_callback, owner)
    accesskit.accesskit_unix_adapter_update_window_focus_state(
        cast(^accesskit.Unix_Adapter)owner^.native, focused)
    return true
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