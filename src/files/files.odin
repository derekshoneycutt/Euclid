package files

// The main point here is to unpack assets.pkg from next to the executable into a
// user-writable location and provide the unpacked file paths to other modules.

import "core:bytes"
import "core:compress/gzip"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:time"

ASSET_PACKAGE_ROOT_DIR :: "EuclidApp"
ASSET_PACKAGE_DIR :: "assets"
ASSET_PACKAGE_ARCHIVE :: "assets.pkg"
GIF_OUTPUT_DIR_NAME :: "gifs"

//   Join a base directory with GIF_OUTPUT_DIR_NAME and ensure it exists.
//
// Parameters:
//   - base_dir: Candidate writable base directory.
//   - allocator: Allocator used for path join.
//
// Returns:
//   - output_dir: Joined output directory path when successful, otherwise "".
//   - ok: true when join succeeded and directory exists/was created.
resolve_writable_gif_output_dir :: proc(
    base_dir: string, allocator := context.temp_allocator) -> (string, bool) {

    if len(base_dir) == 0 {
        return "", false
    }

    output_dir, output_err := filepath.join(
        []string{base_dir, GIF_OUTPUT_DIR_NAME},
        allocator,
    )
    if output_err != nil || !ensure_directory_exists(output_dir) {
        return "", false
    }

    return output_dir, true
}

//   Resolve a writable directory for GIF output and create it if needed.
//
// Parameters:
//   - allocator: Allocator used for temporary path joins and directory resolution.
//
// Returns:
//   - output_dir: Writable path ending in GIF_OUTPUT_DIR_NAME when successful, otherwise "".
//   - ok: true when a writable directory was resolved/created, otherwise false.
resolve_writable_pictures_dir :: proc(allocator := context.temp_allocator) -> (string, bool) {
    pictures_dir, _ := os.user_pictures_dir(allocator)
    data_dir, _ := os.user_data_dir(allocator)
    cache_dir, _ := os.user_cache_dir(allocator)
    temp_dir, _ := os.temp_directory(allocator)

    candidate_dirs := []string{pictures_dir, data_dir, cache_dir, temp_dir}
    for base_dir in candidate_dirs {
        output_dir, ok := resolve_writable_gif_output_dir(base_dir, allocator)
        if ok {
            return output_dir, true
        }
    }

    return "", false
}

//   Ensure assets.pkg is unpacked for the current executable directory.
//
// Parameters:
//   - none.
//
// Returns:
//   - none.
//
// Notes:
//   - Safe for startup use; failures are handled internally.
ensure_packaged_assets_unpacked_root :: proc() {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {
        return
    }

    _ = ensure_packaged_assets_unpacked_with_force(exe_dir, false)
}

//   Force a fresh unpack of assets.pkg from the executable directory.
//
// Parameters:
//   - none.
//
// Returns:
//   - ok: true when reload succeeds and assets are ready for path resolution.
reload_packaged_assets_root :: proc() -> bool {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {
        return false
    }

    return ensure_packaged_assets_unpacked_with_force(exe_dir, true)
}

//   Read the packaged archive modification time as unix nanoseconds.
//
// Parameters:
//   - none.
//
// Returns:
//   - mtime_unix_nano: Archive modification timestamp when available, otherwise 0.
//   - ok: true when the timestamp was retrieved, otherwise false.
packaged_asset_archive_modification_unix_nano :: proc() -> (i64, bool) {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {
        return 0, false
    }

    archive_path, archive_ok := join_archive_path(exe_dir, context.temp_allocator)
    if !archive_ok || !os.exists(archive_path) {
        return 0, false
    }

    info, stat_err := os.stat(archive_path, context.temp_allocator)
    if stat_err != nil {
        return 0, false
    }
    defer os.file_info_delete(info, context.temp_allocator)

    return time.time_to_unix_nano(info.modification_time), true
}

//   Resolve an absolute path for a packaged asset relative path.
//
// Parameters:
//   - relative_path: Asset path relative to the unpack root (for example "julia/script.jl").
//   - allocator: Allocator used for the returned joined path.
//
// Returns:
//   - asset_path: Joined absolute path when successful, otherwise "".
packaged_asset_path :: proc(relative_path: string, allocator := context.allocator) -> string {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {
        return ""
    }

    if !ensure_packaged_assets_unpacked_with_force(exe_dir, false) {
        return ""
    }

    unpack_dir, unpack_ok := resolve_asset_unpack_dir(context.temp_allocator)
    if !unpack_ok {
        return ""
    }

    path, path_err := filepath.join([]string{unpack_dir, relative_path}, allocator)
    if path_err != nil {
        return ""
    }

    return path
}

//   Remove the unpacked packaged-assets directory from writable storage.
//
// Parameters:
//   - none.
//
// Returns:
//   - none.
//
// Notes:
//   - Intended for process shutdown cleanup.
cleanup_packaged_assets_dir :: proc() {
    unpack_dir, unpack_ok := resolve_asset_unpack_dir(context.temp_allocator)
    if !unpack_ok {
        return
    }

    _ = os.remove_all(unpack_dir)
}




//   Resolve executable directory once with standard validity checks.
resolve_executable_dir :: proc(allocator := context.temp_allocator) -> (string, bool) {

    exe_dir, exe_err := os.get_executable_directory(allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return "", false
    }

    return exe_dir, true
}

//   Build an assets archive path from a known executable directory.
join_archive_path :: proc(
    exe_dir: string, allocator := context.temp_allocator) -> (string, bool) {

    archive_path, archive_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_ARCHIVE}, allocator)

    if archive_err != nil || len(archive_path) == 0 {
        return "", false
    }

    return archive_path, true
}

//   Ensure a directory path exists, creating parent directories as needed.
//
// Notes:
//   - Returns false for empty input paths.
ensure_directory_exists :: proc(path: string) -> bool {
    if len(path) == 0 {
        return false
    }

    if os.is_directory(path) {
        return true
    }

    return os.make_directory_all(path) == nil
}

//   Resolve the writable root directory where assets.pkg contents are unpacked.
//
// Notes:
//   - Prefers user cache directory and falls back to temp directory.
resolve_asset_unpack_dir :: proc(allocator := context.temp_allocator) -> (string, bool) {
    base_dir := ""
    cache_dir, _ := os.user_cache_dir(allocator)
    temp_dir, _ := os.temp_directory(allocator)
    candidate_dirs := []string{cache_dir, temp_dir}

    for candidate in candidate_dirs {
        if len(candidate) > 0 {
            base_dir = candidate
            break
        }
    }

    if len(base_dir) == 0 {
        return "", false
    }

    unpack_dir, unpack_err := filepath.join(
        []string{base_dir, ASSET_PACKAGE_ROOT_DIR, ASSET_PACKAGE_DIR},
        allocator,
    )
    if unpack_err != nil || len(unpack_dir) == 0 {
        return "", false
    }

    return unpack_dir, true
}

//   Check whether the unpack directory contains required baseline asset entries.
//
// Notes:
//   - This is a lightweight readiness check, not a full archive integrity check.
is_assets_unpack_ready :: proc(unpack_dir: string) -> bool {
    if !os.is_directory(unpack_dir) {
        return false
    }

    required_entries := []string{
        "julia/script.jl",
        "compass_icon.png",
        "font.ttf",
        "font_mono.ttf",
        "manifest.txt",
    }

    for entry in required_entries {
        path, path_err := filepath.join([]string{unpack_dir, entry}, context.temp_allocator)
        if path_err != nil || !os.exists(path) {
            return false
        }
    }

    return true
}

//   Resolve archive/unpack paths and validate baseline unpack prerequisites.
//
// Returns:
//   - archive_path: Expected archive file path.
//   - unpack_dir: Writable unpack root directory.
//   - ok: true when both paths are valid and unpack dir can be resolved.
resolve_unpack_targets :: proc(exe_dir: string) -> (string, string, bool) {
    archive_path, archive_ok := join_archive_path(exe_dir, context.temp_allocator)
    if !archive_ok {
        fmt.eprintln("asset unpack failed: could not build archive path")
        return "", "", false
    }

    unpack_dir, unpack_ok := resolve_asset_unpack_dir(context.temp_allocator)
    if !unpack_ok {
        fmt.eprintln("asset unpack failed: could not resolve writable unpack directory")
        return "", "", false
    }

    return archive_path, unpack_dir, true
}

//   Decide whether unpack work is needed based on archive presence and force flag.
//
// Returns:
//   - continue_unpack: true when caller should proceed with unpack work.
//   - result: return value the caller should use when unpack should not continue.
should_continue_unpack :: proc(archive_path, unpack_dir: string, force: bool) -> (bool, bool) {
    if !os.exists(archive_path) {
        fmt.eprintln("asset unpack failed: archive not found at ", archive_path)
        return false, os.is_directory(unpack_dir)
    }

    if !force && is_assets_unpack_ready(unpack_dir) {
        return false, true
    }

    return true, false
}

//   Reset and recreate unpack directory before writing extracted assets.
prepare_unpack_directory :: proc(unpack_dir: string) -> bool {
    _ = os.remove_all(unpack_dir)
    if os.make_directory_all(unpack_dir) != nil {
        fmt.eprintln("asset unpack failed: could not create unpack dir ", unpack_dir)
        return false
    }

    return true
}

//   Decode archive gzip payload and extract tar entries into unpack directory.
decode_and_extract_archive_payload :: proc(archive_path, unpack_dir: string) -> bool {
    decompressed := bytes.Buffer{}
    defer bytes.buffer_destroy(&decompressed)

    gzip_err := gzip.load_from_file(archive_path, &decompressed)
    if gzip_err != nil {
        fmt.eprintln("asset unpack failed: gzip decode failed for ", archive_path)
        return false
    }

    payload := bytes.buffer_to_bytes(&decompressed)
    if !extract_packaged_assets_blob(unpack_dir, payload) {
        fmt.eprintln("asset unpack failed: tar payload parse/write failed")
        return false
    }

    return true
}

//   Unpack assets.pkg for an executable directory with optional forced refresh.
//
// Notes:
//   - When force is true, existing unpacked content is removed and rebuilt.
ensure_packaged_assets_unpacked_with_force :: proc(exe_dir: string, force: bool) -> bool {
    archive_path, unpack_dir, targets_ok := resolve_unpack_targets(exe_dir)
    if !targets_ok {
        return false
    }

    continue_unpack, early_result := should_continue_unpack(archive_path, unpack_dir, force)
    if !continue_unpack {
        return early_result
    }

    if !prepare_unpack_directory(unpack_dir) {
        return false
    }

    return decode_and_extract_archive_payload(archive_path, unpack_dir)
}
