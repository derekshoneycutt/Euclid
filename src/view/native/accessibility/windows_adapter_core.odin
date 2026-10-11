package native_accessibility

import portable "../../../accessibility"

Windows_Adapter_Operations :: struct {
    user_data: rawptr,
    create: proc(user_data, hwnd: rawptr, owner: ^Adapter) -> rawptr,
    update: proc(user_data, native: rawptr, owner: ^Adapter) -> rawptr,
    raise_events: proc(user_data, events: rawptr),
    free: proc(user_data, native: rawptr),
}

// windows_raise_queued_events consumes transferred native events exactly once.
windows_raise_queued_events :: proc(
    operations: Windows_Adapter_Operations, events: rawptr) {
    if events == nil {
       return
    }
    operations.raise_events(operations.user_data, events)
}

// windows_adapter_admit_with_operations constructs one pre-published HWND adapter.
windows_adapter_admit_with_operations :: proc(
    owner: ^Adapter, hwnd: rawptr, operations: Windows_Adapter_Operations) -> bool {
    if owner == nil {
       return false
    }
    if owner^.windows_admission_attempted || owner^.native != nil {
       return false
    }
    owner^.windows_admission_attempted = true
    if hwnd == nil {
        adapter_record_windows_failure(owner, .Hwnd_Property_Lookup)
        adapter_close_admission(owner)
        return false
    }
    publication: portable.Control_Tree_Publication
    if !portable.protected_control_snapshot(
            &owner^.control_publication, &publication) {
        adapter_record_windows_failure(owner, .Initial_Publication)
        adapter_close_admission(owner)
        return false
    }
    owner^.native = operations.create(operations.user_data, hwnd, owner)
    if owner^.native == nil {
        adapter_record_windows_failure(owner, .Adapter_Creation)
        adapter_close_admission(owner)
        return false
    }
    owner^.delivered_generation = publication.generation
    return true
}

// windows_adapter_notify_control_update_with_operations owns update event transfer.
windows_adapter_notify_control_update_with_operations :: proc(
    owner: ^Adapter, operations: Windows_Adapter_Operations) {
    if owner == nil || owner^.native == nil {
       return
    }
    publication: portable.Control_Tree_Publication
    if !portable.protected_control_snapshot(
            &owner^.control_publication, &publication) ||
       publication.generation == owner^.delivered_generation {
        return
    }
    owner^.delivered_generation = publication.generation
    adapter_record_diagnostic(owner, .Update)
    events := operations.update(operations.user_data, owner^.native, owner)
    windows_raise_queued_events(operations, events)
}

// windows_adapter_publish_controls_with_operations owns first admission and updates.
windows_adapter_publish_controls_with_operations :: proc(
    owner: ^Adapter, hwnd: rawptr, input: Adapter_Tree_Input,
    operations: Windows_Adapter_Operations) -> bool {
    if owner == nil || owner^.windows_admission_attempted && owner^.native == nil {
        return false
    }
    had_native := owner^.native != nil
    if !adapter_publish_controls(owner, input) {
        if !had_native {
            owner^.windows_admission_attempted = true
            adapter_record_windows_failure(owner, .Initial_Publication)
            adapter_close_admission(owner)
        }
        return false
    }
    if had_native {
        windows_adapter_notify_control_update_with_operations(owner, operations)
        return true
    }
    return windows_adapter_admit_with_operations(owner, hwnd, operations)
}

// windows_adapter_destroy_with_operations closes callbacks before native release.
windows_adapter_destroy_with_operations :: proc(
    owner: ^Adapter, operations: Windows_Adapter_Operations) {
    if owner == nil {
        return
    }
    adapter_close_admission(owner)
    if owner^.native != nil {
        operations.free(operations.user_data, owner^.native)
        owner^.native = nil
        adapter_record_diagnostic(owner, .Destroy)
    }
}