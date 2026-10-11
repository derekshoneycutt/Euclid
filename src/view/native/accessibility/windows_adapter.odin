#+build windows

package native_accessibility

import accesskit "../../../../libs/accesskit"

WINDOWS_ADAPTER_OPERATIONS :: Windows_Adapter_Operations{
    create = windows_native_create,
    update = windows_native_update,
    raise_events = windows_native_raise_events,
    free = windows_native_free,
}

// windows_native_create constructs AccessKit around SDL's borrowed HWND.
windows_native_create :: proc(_: rawptr, hwnd: rawptr, owner: ^Adapter) -> rawptr {
    return rawptr(accesskit.accesskit_windows_subclassing_adapter_new(
        hwnd, accesskit_activation_callback, owner,
        accesskit_action_callback, owner))
}

// windows_native_update forwards one changed tree to an active adapter.
windows_native_update :: proc(_: rawptr, native: rawptr, owner: ^Adapter) -> rawptr {
    return rawptr(accesskit.accesskit_windows_subclassing_adapter_update_if_active(
        cast(^accesskit.Windows_Subclassing_Adapter)native,
        accesskit_activation_callback, owner))
}

// windows_native_raise_events raises and frees transferred native events.
windows_native_raise_events :: proc(_: rawptr, events: rawptr) {
    accesskit.accesskit_windows_queued_events_raise(
        cast(^accesskit.Windows_Queued_Events)events)
}

// windows_native_free releases one admitted subclassing adapter.
windows_native_free :: proc(_: rawptr, native: rawptr) {
    accesskit.accesskit_windows_subclassing_adapter_free(
        cast(^accesskit.Windows_Subclassing_Adapter)native)
}

// windows_adapter_publish_controls publishes before native adapter admission.
windows_adapter_publish_controls :: proc(
    owner: ^Adapter, hwnd: rawptr, input: Adapter_Tree_Input) -> bool {
    return windows_adapter_publish_controls_with_operations(
        owner, hwnd, input, WINDOWS_ADAPTER_OPERATIONS)
}

// windows_adapter_drain_action preserves the shared display-thread action API.
windows_adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    return adapter_drain_action(owner, destination)
}

// windows_adapter_destroy closes callbacks before releasing the HWND adapter.
windows_adapter_destroy :: proc(owner: ^Adapter) {
    windows_adapter_destroy_with_operations(owner, WINDOWS_ADAPTER_OPERATIONS)
}