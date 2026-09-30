package native_accessibility

import portable "../../../accessibility"

import "core:sync"

Macos_Adapter_Operations :: struct {
    user_data: rawptr,
    content_view: proc(user_data, window: rawptr) -> rawptr,
    window_class: proc(user_data, window: rawptr) -> (rawptr, cstring),
    install_focus_forwarder: proc(user_data: rawptr, class_name: cstring) -> bool,
    create: proc(user_data, window: rawptr, owner: ^Adapter) -> rawptr,
    update: proc(user_data, native: rawptr, owner: ^Adapter) -> rawptr,
    update_focus: proc(user_data, native: rawptr, focused: bool) -> rawptr,
    raise_events: proc(user_data, events: rawptr),
    free: proc(user_data, native: rawptr),
}

// macos_raise_queued_events consumes transferred native events exactly once.
macos_raise_queued_events :: proc(
    operations: Macos_Adapter_Operations, events: rawptr) {
    if events == nil {return}
    operations.raise_events(operations.user_data, events)
}

// macos_install_focus_forwarder installs irreversible class behavior once.
macos_install_focus_forwarder :: proc(
    owner: ^Adapter, window: rawptr, operations: Macos_Adapter_Operations,
    process_state: ^Adapter_Process_State) -> bool {
    if owner == nil || window == nil || process_state == nil {
        adapter_record_macos_failure(owner, .Window_Class_Discovery)
        return false
    }
    window_class, class_name := operations.window_class(
        operations.user_data, window)
    if window_class == nil || class_name == nil {
        adapter_record_macos_failure(owner, .Window_Class_Discovery)
        return false
    }
    sync.mutex_lock(&process_state^.mutex)
    defer sync.mutex_unlock(&process_state^.mutex)
    for installed_class in
        process_state^.native_classes[:process_state^.native_class_count] {
        if installed_class == window_class {return true}
    }
    if process_state^.native_class_count == len(process_state^.native_classes) {
        adapter_record_macos_failure(owner, .Focus_Forwarder_Installation)
        return false
    }
    if !operations.install_focus_forwarder(operations.user_data, class_name) {
        adapter_record_macos_failure(owner, .Focus_Forwarder_Installation)
        return false
    }
    process_state^.native_classes[process_state^.native_class_count] = window_class
    process_state^.native_class_count += 1
    return true
}

// macos_adapter_admit_with_operations validates and creates one native adapter.
macos_adapter_admit_with_operations :: proc(
    owner: ^Adapter, window: rawptr, operations: Macos_Adapter_Operations,
    process_state: ^Adapter_Process_State) -> bool {
    if owner == nil || owner^.native != nil || window == nil {
        adapter_record_macos_failure(owner, .Cocoa_Property_Lookup)
        return false
    }
    if operations.content_view(operations.user_data, window) == nil {
        adapter_record_macos_failure(owner, .Adapter_Creation)
        return false
    }
    if !macos_install_focus_forwarder(
            owner, window, operations, process_state) {return false}
    owner^.native = operations.create(operations.user_data, window, owner)
    if owner^.native == nil {
        adapter_record_macos_failure(owner, .Adapter_Creation)
        return false
    }
    return true
}

// macos_adapter_notify_control_update_with_operations owns update event transfer.
macos_adapter_notify_control_update_with_operations :: proc(
    owner: ^Adapter, operations: Macos_Adapter_Operations) {
    if owner == nil || owner^.native == nil {return}
    publication: portable.Control_Tree_Publication
    if !portable.protected_control_snapshot(
            &owner^.control_publication, &publication) ||
       publication.generation == owner^.delivered_generation {
        return
    }
    owner^.delivered_generation = publication.generation
    adapter_record_diagnostic(owner, .Update)
    events := operations.update(operations.user_data, owner^.native, owner)
    macos_raise_queued_events(operations, events)
}

// macos_adapter_publish_controls_with_operations supports portable lifecycle tests.
macos_adapter_publish_controls_with_operations :: proc(
    owner: ^Adapter, window: rawptr, input: Adapter_Tree_Input,
    operations: Macos_Adapter_Operations,
    process_state: ^Adapter_Process_State) -> bool {
    if owner == nil {return false}
    had_native := owner^.native != nil
    if !adapter_publish_controls(owner, input) {return false}
    if had_native {
        macos_adapter_notify_control_update_with_operations(owner, operations)
        return true
    }
    if macos_adapter_admit_with_operations(
        owner, window, operations, process_state) {return true}
    adapter_close_admission(owner)
    return false
}

// macos_adapter_update_focus_with_operations owns focus event transfer.
macos_adapter_update_focus_with_operations :: proc(
    owner: ^Adapter, focused: bool, operations: Macos_Adapter_Operations) {
    if owner == nil || owner^.native == nil {return}
    events := operations.update_focus(
        operations.user_data, owner^.native, focused)
    macos_raise_queued_events(operations, events)
}

// macos_adapter_destroy_with_operations closes callbacks before native release.
macos_adapter_destroy_with_operations :: proc(
    owner: ^Adapter, operations: Macos_Adapter_Operations) {
    if owner == nil {return}
    adapter_close_admission(owner)
    if owner^.native != nil {
        operations.free(operations.user_data, owner^.native)
    }
    owner^.native = nil
    adapter_record_diagnostic(owner, .Destroy)
}