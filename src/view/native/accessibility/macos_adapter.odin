#+build darwin

package native_accessibility

import accesskit "../../../../libs/accesskit"

import objc "core:sys/darwin/Foundation"

MACOS_ADAPTER_OPERATIONS :: Macos_Adapter_Operations{
    content_view = macos_native_content_view,
    window_class = macos_native_window_class,
    install_focus_forwarder = macos_native_install_focus_forwarder,
    create = macos_native_create,
    update = macos_native_update,
    update_focus = macos_native_update_focus,
    raise_events = macos_native_raise_events,
    free = macos_native_free,
}

// macos_native_content_view returns one borrowed NSView for admission checks.
macos_native_content_view :: proc(_: rawptr, window: rawptr) -> rawptr {
    return rawptr(objc.Window_contentView(cast(^objc.Window)window))
}

// macos_native_window_class discovers one Objective-C runtime class and name.
macos_native_window_class :: proc(
    _: rawptr, window: rawptr) -> (rawptr, cstring) {
    window_class := objc.object_getClass(cast(objc.id)window)
    if window_class == nil {return nil, nil}
    return rawptr(window_class), objc.class_getName(window_class)
}

// macos_native_install_focus_forwarder mutates one NSWindow subclass.
macos_native_install_focus_forwarder :: proc(
    _: rawptr, class_name: cstring) -> bool {
    accesskit.accesskit_macos_add_focus_forwarder_to_window_class(class_name)
    return true
}

// macos_native_create constructs one AccessKit adapter for a borrowed NSWindow.
macos_native_create :: proc(_: rawptr, window: rawptr, owner: ^Adapter) -> rawptr {
    return rawptr(accesskit.accesskit_macos_subclassing_adapter_for_window(
        window, accesskit_activation_callback, owner,
        accesskit_action_callback, owner))
}

// macos_native_update forwards one changed tree to an active adapter.
macos_native_update :: proc(_: rawptr, native: rawptr, owner: ^Adapter) -> rawptr {
    return rawptr(accesskit.accesskit_macos_subclassing_adapter_update_if_active(
        cast(^accesskit.Macos_Subclassing_Adapter)native,
        accesskit_activation_callback, owner))
}

// macos_native_update_focus forwards one host-focus transition.
macos_native_update_focus :: proc(
    _: rawptr, native: rawptr, focused: bool) -> rawptr {
    return rawptr(
        accesskit.accesskit_macos_subclassing_adapter_update_view_focus_state(
            cast(^accesskit.Macos_Subclassing_Adapter)native, focused))
}

// macos_native_raise_events raises and frees transferred native events.
macos_native_raise_events :: proc(_: rawptr, events: rawptr) {
    accesskit.accesskit_macos_queued_events_raise(
        cast(^accesskit.Macos_Queued_Events)events)
}

// macos_native_free releases one admitted subclassing adapter.
macos_native_free :: proc(_: rawptr, native: rawptr) {
    accesskit.accesskit_macos_subclassing_adapter_free(
        cast(^accesskit.Macos_Subclassing_Adapter)native)
}

// macos_adapter_publish_controls publishes before native adapter admission.
macos_adapter_publish_controls :: proc(
    owner: ^Adapter, process_state: ^Adapter_Process_State,
    window: rawptr, input: Adapter_Tree_Input) -> bool {
    return macos_adapter_publish_controls_with_operations(
        owner, window, input, MACOS_ADAPTER_OPERATIONS, process_state)
}

// macos_adapter_update_focus forwards host focus and consumes queued events.
macos_adapter_update_focus :: proc(owner: ^Adapter, focused: bool) {
    macos_adapter_update_focus_with_operations(
        owner, focused, MACOS_ADAPTER_OPERATIONS)
}

// macos_adapter_drain_action preserves the shared display-thread action API.
macos_adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    return adapter_drain_action(owner, destination)
}

// macos_adapter_destroy closes callbacks before releasing the native adapter.
macos_adapter_destroy :: proc(owner: ^Adapter) {
    macos_adapter_destroy_with_operations(owner, MACOS_ADAPTER_OPERATIONS)
}