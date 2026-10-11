package diagnostics

import "core:log"
import "core:os"
import "core:sync"

// Diagnostic levels are ordered from verbose investigation details to process-ending
// failures. Domain events and trace-hot-path evidence must not be projected here.
Diagnostic_Level :: log.Level

// Application-owned state shared by every thread context using the configured logger.
Logging_State :: struct {
    mutex : sync.Mutex,
    file : ^os.File,
    logger : log.Logger,
    enabled : bool,
}

//   Serialize one formatted core logger record into the lifecycle-owned file.
//
// Notes:
//   - Formatting has already used the caller's temporary allocator before this procedure.
//   - Do not call this sink from allocator implementations or semantic trace emission.
//
// Side effects:
//   - Locks the shared sink and writes one complete record when logging remains enabled.
synchronized_file_logger_proc :: proc(
    data: rawptr, level: log.Level, text: string, options: log.Options,
    location := #caller_location) {
    state := (^Logging_State)(data)
    sync.mutex_lock(&state^.mutex)
    defer sync.mutex_unlock(&state^.mutex)
    if !state^.enabled || state^.file == nil {
        return
    }
    file_data := log.File_Console_Logger_Data{
        file_handle = state^.file,
        ident = "euclid",
    }
    log.file_logger_proc(rawptr(&file_data), level, text, options, location)
}

//   Open one synchronized diagnostic file sink for explicit context installation.
//
// Returns:
//   - True after the path is opened and the logger is ready; false with no live sink.
//
// Side effects:
//   - Creates or truncates the requested file. The lifecycle owner installs `state.logger`.
logging_start :: proc(
    state: ^Logging_State, path: string,
    lowest_level := Diagnostic_Level.Debug) -> bool {
    if state == nil || state^.enabled || len(path) == 0 {
        return false
    }
    file, open_error := os.create(path)
    if open_error != nil {
        return false
    }
    state^.file = file
    state^.logger = log.Logger{
        procedure = synchronized_file_logger_proc,
        data = rawptr(state),
        lowest_level = lowest_level,
        options = log.Default_File_Logger_Opts + {.Thread_Id},
    }
    state^.enabled = true
    return true
}

//   Disable logging and close its file after every context has detached from the sink.
//
// Side effects:
//   - Closes the owned file. The lifecycle owner must first install a different logger.
logging_stop :: proc(state: ^Logging_State) {
    if state == nil || !state^.enabled {
        return
    }
    sync.mutex_lock(&state^.mutex)
    state^.enabled = false
    file := state^.file
    state^.file = nil
    sync.mutex_unlock(&state^.mutex)
    if file != nil {
        os.close(file)
    }
}
