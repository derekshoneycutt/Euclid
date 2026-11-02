package native

import "core:log"
import "core:strings"
import "core:sync"
import "core:unicode/utf8"

import sdl "vendor:sdl3"

SDL_FILE_DIALOG_PATH_CAPACITY :: 4096
SDL_FILE_DIALOG_LOCATION_CAPACITY :: 4096
SDL_COLLECTIONS_DEFAULT_FILENAME :: "collections.euclid"

Sdl_File_Dialog_State :: enum u8 {
    Idle,
    Open,
    Chosen,
    Cancelled,
    Failed,
}

Sdl_File_Dialog_Start_Result :: enum u8 {
    Started,
    Busy,
    Invalid_Request,
    Native_Failure,
}

Sdl_File_Dialog_Result_Kind :: enum u8 {
    Idle,
    Pending,
    Chosen,
    Cancelled,
    Failed,
}

Sdl_File_Dialog_Text :: struct {
    title: cstring,
    accept: cstring,
}

// Sdl_File_Dialog_Result owns one copied path returned to the display thread.
Sdl_File_Dialog_Result :: struct {
    kind: Sdl_File_Dialog_Result_Kind,
    path: [SDL_FILE_DIALOG_PATH_CAPACITY + 1]u8,
    path_length: int,
}

// Keep this callback storage at one stable address until SDL calls back.
Sdl_File_Dialog :: struct {
    mutex: sync.Mutex,
    state: Sdl_File_Dialog_State,
    filter: sdl.DialogFileFilter,
    location: [SDL_FILE_DIALOG_LOCATION_CAPACITY + 1]u8,
    path: [SDL_FILE_DIALOG_PATH_CAPACITY + 1]u8,
    location_length: int,
    path_length: int,
}

// Start an asynchronous single-file open dialog with a retained .euclid filter.
sdl_file_dialog_start_open :: proc(
    dialog: ^Sdl_File_Dialog, window: ^sdl.Window,
    default_location: string) -> Sdl_File_Dialog_Start_Result {
    return sdl_file_dialog_launch(
        dialog, window, default_location, .OPENFILE,
        {
            title = cstring("Import Euclid Collections"),
            accept = cstring("Open"),
        })
}

// Start an asynchronous save dialog with a retained .euclid filter.
sdl_file_dialog_start_save :: proc(
    dialog: ^Sdl_File_Dialog, window: ^sdl.Window,
    default_location: string) -> Sdl_File_Dialog_Start_Result {
    return sdl_file_dialog_launch(
        dialog, window, default_location, .SAVEFILE,
        {
            title = cstring("Export Euclid Collections"),
            accept = cstring("Save"),
        })
}

// Reserve the one active slot and copy default-location bytes into owned storage.
sdl_file_dialog_reserve :: proc(
    dialog: ^Sdl_File_Dialog,
    default_location: string) -> Sdl_File_Dialog_Start_Result {
    if dialog == nil ||
        len(default_location) > SDL_FILE_DIALOG_LOCATION_CAPACITY ||
        !utf8.valid_string(default_location) ||
        strings.contains(default_location, "\x00") {
        return .Invalid_Request
    }
    sync.mutex_lock(&dialog.mutex)
    defer sync.mutex_unlock(&dialog.mutex)
    if dialog.state != .Idle {
        return .Busy
    }
    dialog.state = .Open
    dialog.filter = {
        name = cstring("Euclid collections (*.euclid)"),
        pattern = cstring("euclid"),
    }
    dialog.location_length = len(default_location)
    copy(dialog.location[:dialog.location_length],
        transmute([]u8)default_location)
    dialog.location[dialog.location_length] = 0
    dialog.path_length = 0
    dialog.path[0] = 0
    return .Started
}

// Poll and clear one completed result; callbacks never publish UI state themselves.
sdl_file_dialog_poll :: proc(
    dialog: ^Sdl_File_Dialog) -> Sdl_File_Dialog_Result {
    if dialog == nil {
        return {
            kind = .Failed,
        }
    }
    sync.mutex_lock(&dialog.mutex)
    defer sync.mutex_unlock(&dialog.mutex)
    switch dialog.state {
    case .Idle:
        return {
            kind = .Idle,
        }
    case .Open:
        return {
            kind = .Pending,
        }
    case .Chosen:
        result: Sdl_File_Dialog_Result = {
            kind = .Chosen,
            path = dialog.path,
            path_length = dialog.path_length,
        }
        sdl_file_dialog_clear_locked(dialog)
        return result
    case .Cancelled:
        sdl_file_dialog_clear_locked(dialog)
        return {
            kind = .Cancelled,
        }
    case .Failed:
        sdl_file_dialog_clear_locked(dialog)
        return {
            kind = .Failed,
        }
    }
    sdl_file_dialog_clear_locked(dialog)
    return {
        kind = .Failed,
    }
}

// Launch SDL's asynchronous properties-based dialog after reserving stable inputs.
sdl_file_dialog_launch :: proc(
    dialog: ^Sdl_File_Dialog, window: ^sdl.Window,
    default_location: string, dialog_type: sdl.FileDialogType,
    text: Sdl_File_Dialog_Text) -> Sdl_File_Dialog_Start_Result {
    if window == nil {
        return .Invalid_Request
    }
    reserve_result := sdl_file_dialog_reserve(dialog, default_location)
    if reserve_result != .Started {
        return reserve_result
    }
    properties := sdl.CreateProperties()
    if properties == 0 {
        sdl_file_dialog_cancel_start(dialog)
        log.errorf("sdl_file_dialog_properties_failed error=%s", sdl.GetError())
        return .Native_Failure
    }
    defer sdl.DestroyProperties(properties)
    if !sdl_file_dialog_set_properties(
        properties, dialog, window, text.title, text.accept) {
        sdl_file_dialog_cancel_start(dialog)
        log.errorf("sdl_file_dialog_configuration_failed error=%s", sdl.GetError())
        return .Native_Failure
    }
    sdl.ShowFileDialogWithProperties(
        dialog_type, sdl_file_dialog_callback, rawptr(dialog), properties)
    return .Started
}

// Set supported SDL dialog properties and retain its filter pointer through callback.
sdl_file_dialog_set_properties :: proc(
    properties: sdl.PropertiesID, dialog: ^Sdl_File_Dialog,
    window: ^sdl.Window, title, accept: cstring) -> bool {
    return sdl.SetPointerProperty(
        properties, sdl.PROP_FILE_DIALOG_FILTERS_POINTER,
        rawptr(&dialog.filter)) &&
        sdl.SetNumberProperty(
            properties, sdl.PROP_FILE_DIALOG_NFILTERS_NUMBER, 1) &&
        sdl.SetPointerProperty(
            properties, sdl.PROP_FILE_DIALOG_WINDOW_POINTER, rawptr(window)) &&
        sdl.SetStringProperty(
            properties, sdl.PROP_FILE_DIALOG_LOCATION_STRING,
            cstring(&dialog.location[0])) &&
        sdl.SetBooleanProperty(
            properties, sdl.PROP_FILE_DIALOG_MANY_BOOLEAN, false) &&
        sdl.SetStringProperty(
            properties, sdl.PROP_FILE_DIALOG_TITLE_STRING,
            title) &&
        sdl.SetStringProperty(
            properties, sdl.PROP_FILE_DIALOG_ACCEPT_STRING,
            accept)
}

// SDL may invoke this callback from another thread; copy only into the locked slot.
sdl_file_dialog_callback :: proc "c" (
    userdata: rawptr, filelist: [^]cstring, _: i32) {
    if userdata == nil {
        return
    }
    dialog := cast(^Sdl_File_Dialog)userdata
    sync.mutex_lock(&dialog.mutex)
    defer sync.mutex_unlock(&dialog.mutex)
    if dialog.state != .Open {
        return
    }
    if filelist == nil {
        dialog.state = .Failed
        return
    }
    if filelist[0] == nil {
        dialog.state = .Cancelled
        return
    }
    sdl_file_dialog_copy_path_locked(dialog, filelist[0])
}

// Copy one complete UTF-8 path or report failure without exposing truncation.
sdl_file_dialog_copy_path_locked :: proc "contextless" (
    dialog: ^Sdl_File_Dialog, source: cstring) {
    bytes := cast([^]u8)source
    for index in 0..<len(dialog.path) {
        value := bytes[index]
        if value == 0 {
            if index == 0 || !utf8.valid_string(string(dialog.path[:index])) {
                dialog.state = .Failed
                return
            }
            dialog.path[index] = 0
            dialog.path_length = index
            dialog.state = .Chosen
            return
        }
        if index == SDL_FILE_DIALOG_PATH_CAPACITY {
            dialog.state = .Failed
            return
        }
        dialog.path[index] = value
    }
    dialog.state = .Failed
}

// Release a reservation when SDL property setup fails before a dialog can open.
sdl_file_dialog_cancel_start :: proc(dialog: ^Sdl_File_Dialog) {
    sync.mutex_lock(&dialog.mutex)
    defer sync.mutex_unlock(&dialog.mutex)
    if dialog.state == .Open {
        sdl_file_dialog_clear_locked(dialog)
    }
}

// Clear one completed or abandoned request while its mutex is held.
sdl_file_dialog_clear_locked :: proc "contextless" (
    dialog: ^Sdl_File_Dialog) {
    dialog.state = .Idle
    dialog.location_length = 0
    dialog.path_length = 0
    dialog.location[0] = 0
    dialog.path[0] = 0
}
