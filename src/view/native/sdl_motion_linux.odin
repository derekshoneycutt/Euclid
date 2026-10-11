#+build linux

package native

import "core:os"
import "core:strings"
import posix "core:sys/posix"
import "core:log"

// GObject type registration retains code pointers for the process lifetime.
SDL_GIO_NODELETE :: posix.RTLD_Flag_Bits(12)

// Sdl_Motion_Gio borrows optional GSettings entry points for one bounded policy query.
Sdl_Motion_Gio :: struct {
    g_settings_schema_source_get_default: proc "c" () -> rawptr,
    g_settings_schema_source_lookup: proc "c" (source: rawptr,
        name: cstring, recursive: i32) -> rawptr,
    g_settings_schema_has_key: proc "c" (schema: rawptr, name: cstring) -> i32,
    g_settings_schema_unref: proc "c" (schema: rawptr),
    g_settings_new_full: proc "c" (schema, backend: rawptr, path: cstring) -> rawptr,
    g_settings_get_boolean: proc "c" (settings: rawptr, key: cstring) -> i32,
    g_object_unref: proc "c" (object: rawptr),
}

// sdl_gsettings_motion reads only an admitted schema/key without assuming a desktop.
sdl_gsettings_motion :: proc(
    gio: Sdl_Motion_Gio, source: rawptr,
    schema_name: cstring) -> (bool, Sdl_Motion_Status) {
    schema := gio.g_settings_schema_source_lookup(source, schema_name, 1)
    if schema == nil {
        return false, .Unavailable
    }
    defer gio.g_settings_schema_unref(schema)
    if gio.g_settings_schema_has_key(schema, "enable-animations") == 0 {
        return false, .Unavailable
    }
    settings := gio.g_settings_new_full(schema, nil, nil)
    if settings == nil {
        return false, .Failed
    }
    defer gio.g_object_unref(settings)
    return gio.g_settings_get_boolean(settings, "enable-animations") == 0, .Supported
}

// sdl_query_reduced_motion supports optional GNOME/Cinnamon GSettings without shell calls.
sdl_query_reduced_motion :: proc() -> (bool, Sdl_Motion_Status) {
    desktop_storage: [256]u8
    desktop, error := os.lookup_env(desktop_storage[:], "XDG_CURRENT_DESKTOP")
    if error != nil {
        return false, .Unavailable
    }
    schema: cstring
    if strings.contains(desktop, "GNOME") {
        schema = "org.gnome.desktop.interface"
    } else if strings.contains(desktop, "Cinnamon") ||
        strings.contains(desktop, "X-Cinnamon") {
        schema = "org.cinnamon.desktop.interface"
    } else {
        return false, .Unavailable
    }
    return sdl_query_gsettings_motion(schema)
}

// sdl_query_gsettings_motion balances handles while keeping registered GIO types resident.
sdl_query_gsettings_motion :: proc(schema: cstring) -> (bool, Sdl_Motion_Status) {
    handle := posix.dlopen("libgio-2.0.so.0", {.NOW, SDL_GIO_NODELETE})
    if handle == nil {
        return false, .Unavailable
    }
    defer {
        if posix.dlclose(handle) != 0 {
            log.error("interface_motion_gio_handle_release_failed")
        }
    }
    gio, loaded := sdl_motion_gio_symbols(handle)
    if !loaded { return false, .Failed }
    source := gio.g_settings_schema_source_get_default()
    if source == nil {
        return false, .Unavailable
    }
    return sdl_gsettings_motion(gio, source, schema)
}

// sdl_motion_gio_symbols admits the complete optional ABI before calling any entry point.
sdl_motion_gio_symbols :: proc(handle: posix.Symbol_Table) -> (Sdl_Motion_Gio, bool) {
    gio: Sdl_Motion_Gio
    gio.g_settings_schema_source_get_default = auto_cast posix.dlsym(handle,
        "g_settings_schema_source_get_default")
    gio.g_settings_schema_source_lookup = auto_cast posix.dlsym(handle,
        "g_settings_schema_source_lookup")
    gio.g_settings_schema_has_key = auto_cast posix.dlsym(handle,
        "g_settings_schema_has_key")
    gio.g_settings_schema_unref = auto_cast posix.dlsym(handle,
        "g_settings_schema_unref")
    gio.g_settings_new_full = auto_cast posix.dlsym(handle, "g_settings_new_full")
    gio.g_settings_get_boolean = auto_cast posix.dlsym(handle, "g_settings_get_boolean")
    gio.g_object_unref = auto_cast posix.dlsym(handle, "g_object_unref")
    complete := gio.g_settings_schema_source_get_default != nil &&
        gio.g_settings_schema_source_lookup != nil &&
        gio.g_settings_schema_has_key != nil &&
        gio.g_settings_schema_unref != nil && gio.g_settings_new_full != nil &&
        gio.g_settings_get_boolean != nil && gio.g_object_unref != nil
    return gio, complete
}
