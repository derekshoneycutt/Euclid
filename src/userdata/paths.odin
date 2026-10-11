package userdata

import "core:os"
import "core:path/filepath"
import "core:mem"
import "core:strings"

// Return an allocator-owned durable path; the caller must delete it with allocator.
default_database_path :: proc(allocator: mem.Allocator) -> (string, Path_Error) {
    base, os_error := os.user_data_dir(allocator)
    defer delete(base, allocator)
    if os_error != nil || len(base) == 0 {
        return "", .Operating_System
    }
    path, join_error := filepath.join(
        []string{base, DATABASE_DIRECTORY_NAME, DATABASE_FILENAME}, allocator)
    if join_error != nil {
        return "", .Operating_System
    }
    return userdata_owned_path_validate(path, allocator)
}

// Return an allocator-owned absolute path, including for already absolute input.
resolve_database_path :: proc(
    filename: string, allocator: mem.Allocator) -> (string, Path_Error) {
    if !userdata_path_is_valid(filename) {
        return "", .Invalid
    }
    if len(filename) > DATABASE_PATH_MAX_BYTES {
        return "", .Too_Long
    }
    if filepath.is_abs(filename) {
        return userdata_owned_path_validate(strings.clone(filename, allocator), allocator)
    }
    working_directory, os_error := os.get_working_directory(allocator)
    defer delete(working_directory, allocator)
    if os_error != nil || len(working_directory) == 0 {
        return "", .Operating_System
    }
    path, join_error := filepath.join(
        []string{working_directory, filename}, allocator)
    if join_error != nil {
        return "", .Operating_System
    }
    return userdata_owned_path_validate(path, allocator)
}

// Release an owned path on validation failure instead of discarding its allocation.
userdata_owned_path_validate :: proc(
    path: string, allocator: mem.Allocator) -> (string, Path_Error) {
    validated, failure := userdata_path_validate(path)
    if failure != .None {
        delete(path, allocator)
    }
    return validated, failure
}

// Validate the stable bounded UTF-8 path contract before filesystem or SQLite use.
userdata_path_validate :: proc(path: string) -> (string, Path_Error) {
    if !userdata_path_is_valid(path) {
        return "", .Invalid
    }
    if len(path) > DATABASE_PATH_MAX_BYTES {
        return "", .Too_Long
    }
    return path, .None
}

// Reject empty paths and embedded NUL bytes at the native filesystem boundary.
userdata_path_is_valid :: proc(path: string) -> bool {
    if len(path) == 0 {
        return false
    }
    for value in transmute([]u8)path {
        if value == 0 {
            return false
        }
    }
    return true
}
