#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

// unix_adapter_new creates one Linux adapter around shared callbacks.
unix_adapter_new :: proc(owner: ^Adapter) -> ^accesskit.Unix_Adapter {
    return accesskit.accesskit_unix_adapter_new(
        accesskit_activation_callback, owner,
        accesskit_action_callback, owner,
        accesskit_deactivation_callback, owner)
}

// unix_adapter_notify_update forwards one changed static publication if active.
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
        accesskit_activation_callback, owner)
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
        accesskit_activation_callback, owner)
    accesskit.accesskit_unix_adapter_update_window_focus_state(
        cast(^accesskit.Unix_Adapter)owner^.native, publication.window_focused)
}

// unix_adapter_publish_controls wraps shared publication with Unix lifecycle.
unix_adapter_publish_controls :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input) -> bool {
    if owner == nil {
       return false
    }
    had_native := owner^.native != nil
    if !adapter_publish_controls(owner, input) {
       return false
    }
    if had_native {
        unix_adapter_notify_control_update(owner)
        return true
    }
    owner^.native = rawptr(unix_adapter_new(owner))
    if owner^.native != nil {
       return true
    }
    adapter_close_admission(owner)
    return false
}

// unix_adapter_create_button wraps initial shared button publication.
unix_adapter_create_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    if owner == nil || owner^.native != nil || !input.present {
       return false
    }
    if !adapter_publish_button(owner, input, identity) {
       return false
    }
    owner^.native = rawptr(unix_adapter_new(owner))
    if owner^.native != nil {
       return true
    }
    adapter_close_admission(owner)
    return false
}

// unix_adapter_publish_button wraps shared publication with Unix updates.
unix_adapter_publish_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    if owner == nil {
       return false
    }
    if owner^.native == nil {
        if !input.present {
           return true
        }
        return unix_adapter_create_button(owner, input, identity)
    }
    if !adapter_publish_button(owner, input, identity) {
       return false
    }
    unix_adapter_notify_update(owner)
    return true
}

// unix_adapter_drain_action preserves the public Unix API.
unix_adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    return adapter_drain_action(owner, destination)
}

// unix_adapter_create admits one static Linux tree without blocking startup.
unix_adapter_create :: proc(
    owner: ^Adapter, width, height: f64, focused: bool,
    fail_at: Adapter_Create_Failure = .None) -> bool {
    if owner == nil || owner^.native != nil {
       return false
    }
    if !adapter_initialize_static(owner, width, height, focused) {
       return false
    }
    if fail_at == .After_Publication {
        adapter_close_admission(owner)
        return false
    }
    owner^.native = rawptr(unix_adapter_new(owner))
    if owner^.native != nil {
       return true
    }
    adapter_close_admission(owner)
    return false
}

// unix_adapter_set_root_bounds forwards known X11 outer and inner rectangles.
unix_adapter_set_root_bounds :: proc(
    owner: ^Adapter, outer, inner: portable.Bounds) {
    if owner == nil || owner^.native == nil {
       return
    }
    accesskit.accesskit_unix_adapter_set_root_window_bounds(
        cast(^accesskit.Unix_Adapter)owner^.native,
        cast(accesskit.Rect)outer, cast(accesskit.Rect)inner)
}

// unix_adapter_destroy closes callbacks before freeing the native adapter.
unix_adapter_destroy :: proc(owner: ^Adapter) {
    if owner == nil {
       return
    }
    adapter_close_admission(owner)
    if owner^.native != nil {
        accesskit.accesskit_unix_adapter_free(
            cast(^accesskit.Unix_Adapter)owner^.native)
    }
    owner^.native = nil
    adapter_record_diagnostic(owner, .Destroy)
}