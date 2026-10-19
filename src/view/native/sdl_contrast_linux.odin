#+build linux

package native

import log "core:log"
import "core:thread"
import "core:time"
import posix "core:sys/posix"

SDL_GIO_CONTRAST_NODELETE :: posix.RTLD_Flag_Bits(12)
SDL_PORTAL_SETTINGS_TIMEOUT_MS :: i32(750)
SDL_G_BUS_TYPE_SESSION :: i32(2)

// Sdl_Contrast_Gio borrows the optional ABI until query and deadline workers join.
Sdl_Contrast_Gio :: struct {
    g_cancellable_new: proc "c" () -> rawptr,
    g_cancellable_cancel: proc "c" (cancellable: rawptr),
    g_cancellable_is_cancelled: proc "c" (cancellable: rawptr) -> i32,
    g_bus_get_sync: proc "c" (bus_type: i32, cancellable: rawptr,
        error: ^rawptr) -> rawptr,
    g_dbus_connection_call_sync: proc "c" (connection: rawptr,
        bus_name, object_path, interface_name, method_name: cstring,
        parameters, reply_type: rawptr, flags: u32, timeout_msec: i32,
        cancellable: rawptr, error: ^rawptr) -> rawptr,
    g_dbus_error_get_remote_error: proc "c" (error: rawptr) -> cstring,
    g_free: proc "c" (memory: rawptr),
    g_variant_new_string: proc "c" (value: cstring) -> rawptr,
    g_variant_new_tuple: proc "c" (children: ^rawptr, count: uintptr) -> rawptr,
    g_variant_ref_sink: proc "c" (value: rawptr) -> rawptr,
    g_variant_get_child_value: proc "c" (value: rawptr, index: uintptr) -> rawptr,
    g_variant_get_variant: proc "c" (value: rawptr) -> rawptr,
    g_variant_get_type_string: proc "c" (value: rawptr) -> cstring,
    g_variant_get_uint32: proc "c" (value: rawptr) -> u32,
    g_variant_unref: proc "c" (value: rawptr),
    g_object_unref: proc "c" (value: rawptr),
    g_error_free: proc "c" (error: rawptr),
}

// Sdl_Contrast_Deadline borrows a cancellable until the query owner joins its timer.
Sdl_Contrast_Deadline :: struct {
    gio: Sdl_Contrast_Gio,
    cancellable: rawptr,
}

// sdl_contrast_deadline_worker cancels both bus connection and method I/O at 750 ms.
sdl_contrast_deadline_worker :: proc(data: rawptr) {
    deadline := cast(^Sdl_Contrast_Deadline)data
    time.sleep(time.Duration(SDL_PORTAL_SETTINGS_TIMEOUT_MS) * time.Millisecond)
    deadline^.gio.g_cancellable_cancel(deadline^.cancellable)
}

// sdl_query_system_contrast polls or starts one bounded worker for the portal read.
sdl_query_system_contrast :: proc(
    preference: ^Sdl_Contrast_Preference,
    should_query: bool) -> Sdl_Contrast_Query_Result {
    if preference^.worker != nil {
        if !thread.is_done(preference^.worker) {
            return {status = .Pending}
        }
        thread.join(preference^.worker)
        thread.destroy(preference^.worker)
        preference^.worker = nil
        return {requested = preference^.worker_requested,
            status = preference^.worker_status, complete = true}
    }
    if !should_query {
        return {status = preference^.status}
    }
    preference^.worker_status = .Pending
    preference^.worker = thread.create_and_start_with_data(
        rawptr(preference), sdl_contrast_linux_worker)
    if preference^.worker == nil {
        return {status = .Failed, complete = true}
    }
    return {status = .Pending}
}

// sdl_contrast_linux_worker owns the portal call and publishes only its bounded result.
sdl_contrast_linux_worker :: proc(data: rawptr) {
    preference := cast(^Sdl_Contrast_Preference)data
    requested, status := sdl_contrast_linux_read_portal()
    preference^.worker_requested = requested
    preference^.worker_status = status
}

// sdl_contrast_linux_read_portal admits the optional GIO ABI and reads the standard key.
sdl_contrast_linux_read_portal :: proc() -> (bool, Sdl_Contrast_Status) {
    handle := posix.dlopen("libgio-2.0.so.0", {.NOW, SDL_GIO_CONTRAST_NODELETE})
    if handle == nil {
        return false, .Unavailable
    }
    defer {
        if posix.dlclose(handle) != 0 {
            log.error("interface_contrast_gio_handle_release_failed")
        }
    }
    gio, loaded := sdl_contrast_gio_symbols(handle)
    if !loaded {
        return false, .Unavailable
    }
    return sdl_contrast_portal_read(gio)
}

// sdl_contrast_portal_read owns a deadline spanning bus acquisition and ReadOne.
sdl_contrast_portal_read :: proc(
    gio: Sdl_Contrast_Gio) -> (bool, Sdl_Contrast_Status) {
    cancellable := gio.g_cancellable_new()
    if cancellable == nil {
        return false, .Failed
    }
    defer gio.g_object_unref(cancellable)
    deadline := Sdl_Contrast_Deadline{gio = gio, cancellable = cancellable}
    timer := thread.create_and_start_with_data(
        rawptr(&deadline), sdl_contrast_deadline_worker)
    if timer == nil {
        return false, .Failed
    }
    defer {
        thread.join(timer)
        thread.destroy(timer)
    }
    return sdl_contrast_portal_read_cancellable(gio, cancellable)
}

// sdl_contrast_portal_read_cancellable balances the connection and owned parameters.
sdl_contrast_portal_read_cancellable :: proc(
    gio: Sdl_Contrast_Gio,
    cancellable: rawptr) -> (bool, Sdl_Contrast_Status) {
    error: rawptr
    connection := gio.g_bus_get_sync(SDL_G_BUS_TYPE_SESSION, cancellable, &error)
    if connection == nil {
        if error != nil { gio.g_error_free(error) }
        if gio.g_cancellable_is_cancelled(cancellable) != 0 {
            return false, .Failed
        }
        return false, .Unavailable
    }
    defer gio.g_object_unref(connection)
    namespace := gio.g_variant_new_string("org.freedesktop.appearance")
    key := gio.g_variant_new_string("contrast")
    children := [2]rawptr{namespace, key}
    parameters := gio.g_variant_ref_sink(
        gio.g_variant_new_tuple(&children[0], uintptr(len(children))))
    defer gio.g_variant_unref(parameters)
    error = nil
    reply := gio.g_dbus_connection_call_sync(
        connection, "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
        "ReadOne", parameters, nil, 0, SDL_PORTAL_SETTINGS_TIMEOUT_MS,
        cancellable, &error)
    if reply == nil {
        status := sdl_contrast_portal_error_status(gio, error)
        if error != nil { gio.g_error_free(error) }
        return false, status
    }
    defer gio.g_variant_unref(reply)
    return sdl_contrast_portal_decode_reply(gio, reply)
}

// sdl_contrast_portal_decode_reply validates tuple and variant shape before extraction.
sdl_contrast_portal_decode_reply :: proc(
    gio: Sdl_Contrast_Gio, reply: rawptr) -> (bool, Sdl_Contrast_Status) {
    if reply == nil || string(gio.g_variant_get_type_string(reply)) != "(v)" {
        return false, .Failed
    }
    value_wrapper := gio.g_variant_get_child_value(reply, 0)
    if value_wrapper == nil {
        return false, .Failed
    }
    defer gio.g_variant_unref(value_wrapper)
    value := gio.g_variant_get_variant(value_wrapper)
    if value == nil {
        return false, .Failed
    }
    defer gio.g_variant_unref(value)
    if string(gio.g_variant_get_type_string(value)) != "u" {
        return false, .Failed
    }
    contrast := gio.g_variant_get_uint32(value)
    // The portal specification maps unknown uint32 values to no preference.
    return contrast == 1, .Supported
}

// sdl_contrast_portal_error_status distinguishes absent portal support from query failure.
sdl_contrast_portal_error_status :: proc(
    gio: Sdl_Contrast_Gio, error: rawptr) -> Sdl_Contrast_Status {
    if error == nil {
        return .Failed
    }
    remote_error := gio.g_dbus_error_get_remote_error(error)
    if remote_error == nil {
        return .Failed
    }
    name := string(remote_error)
    unavailable := name == "org.freedesktop.DBus.Error.ServiceUnknown" ||
        name == "org.freedesktop.DBus.Error.UnknownMethod" ||
        name == "org.freedesktop.DBus.Error.UnknownObject" ||
        name == "org.freedesktop.DBus.Error.UnknownInterface" ||
        name == "org.freedesktop.DBus.Error.InvalidArgs" ||
        name == "org.freedesktop.portal.Error.NotFound"
    gio.g_free(rawptr(remote_error))
    return .Unavailable if unavailable else .Failed
}

// sdl_contrast_gio_symbols admits every required function before invoking GIO.
sdl_contrast_gio_symbols :: proc(
    handle: posix.Symbol_Table) -> (Sdl_Contrast_Gio, bool) {
    gio: Sdl_Contrast_Gio
    gio.g_cancellable_new = auto_cast posix.dlsym(handle, "g_cancellable_new")
    gio.g_cancellable_cancel = auto_cast posix.dlsym(handle, "g_cancellable_cancel")
    gio.g_cancellable_is_cancelled = auto_cast posix.dlsym(
        handle, "g_cancellable_is_cancelled")
    gio.g_bus_get_sync = auto_cast posix.dlsym(handle, "g_bus_get_sync")
    gio.g_dbus_connection_call_sync = auto_cast posix.dlsym(
        handle, "g_dbus_connection_call_sync")
    gio.g_dbus_error_get_remote_error = auto_cast posix.dlsym(
        handle, "g_dbus_error_get_remote_error")
    gio.g_free = auto_cast posix.dlsym(handle, "g_free")
    gio.g_variant_new_string = auto_cast posix.dlsym(handle, "g_variant_new_string")
    gio.g_variant_new_tuple = auto_cast posix.dlsym(handle, "g_variant_new_tuple")
    gio.g_variant_ref_sink = auto_cast posix.dlsym(handle, "g_variant_ref_sink")
    gio.g_variant_get_child_value = auto_cast posix.dlsym(
        handle, "g_variant_get_child_value")
    gio.g_variant_get_variant = auto_cast posix.dlsym(handle, "g_variant_get_variant")
    gio.g_variant_get_type_string = auto_cast posix.dlsym(
        handle, "g_variant_get_type_string")
    gio.g_variant_get_uint32 = auto_cast posix.dlsym(handle, "g_variant_get_uint32")
    gio.g_variant_unref = auto_cast posix.dlsym(handle, "g_variant_unref")
    gio.g_object_unref = auto_cast posix.dlsym(handle, "g_object_unref")
    gio.g_error_free = auto_cast posix.dlsym(handle, "g_error_free")
    complete := gio.g_cancellable_new != nil && gio.g_cancellable_cancel != nil &&
        gio.g_cancellable_is_cancelled != nil && gio.g_bus_get_sync != nil &&
        gio.g_dbus_connection_call_sync != nil &&
        gio.g_dbus_error_get_remote_error != nil && gio.g_free != nil &&
        gio.g_variant_new_string != nil &&
        gio.g_variant_new_tuple != nil && gio.g_variant_ref_sink != nil &&
        gio.g_variant_get_child_value != nil &&
        gio.g_variant_get_variant != nil && gio.g_variant_get_type_string != nil &&
        gio.g_variant_get_uint32 != nil && gio.g_variant_unref != nil &&
        gio.g_object_unref != nil && gio.g_error_free != nil
    return gio, complete
}

// sdl_contrast_native_destroy joins the worker before its platform state retires.
sdl_contrast_native_destroy :: proc(preference: ^Sdl_Contrast_Preference) {
    if preference^.worker != nil {
        thread.join(preference^.worker)
        thread.destroy(preference^.worker)
    }
    preference^ = {}
}
