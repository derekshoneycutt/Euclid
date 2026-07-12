package files

// The main point here is to unpack assets.pkg from next to the executable into a
// user-writable location and provide the unpacked file paths to other modules.

import "core:bytes"
import "core:compress/gzip"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
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
resolve_writable_gif_output_dir :: proc(base_dir: string, allocator := context.temp_allocator) -> (string, bool) {
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
    pictures_dir, pictures_err := os.user_pictures_dir(allocator)
    if pictures_err == nil && len(pictures_dir) > 0 {
        output_dir, ok := resolve_writable_gif_output_dir(pictures_dir, allocator)
        if ok {
            return output_dir, true
        }
    }

    data_dir, data_err := os.user_data_dir(allocator)
    if data_err == nil && len(data_dir) > 0 {
        output_dir, ok := resolve_writable_gif_output_dir(data_dir, allocator)
        if ok {
            return output_dir, true
        }
    }

    cache_dir, cache_err := os.user_cache_dir(allocator)
    if cache_err == nil && len(cache_dir) > 0 {
        output_dir, ok := resolve_writable_gif_output_dir(cache_dir, allocator)
        if ok {
            return output_dir, true
        }
    }

    temp_dir, temp_err := os.temp_directory(allocator)
    if temp_err == nil && len(temp_dir) > 0 {
        output_dir, ok := resolve_writable_gif_output_dir(temp_dir, allocator)
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
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return
    }

    _ = ensure_packaged_assets_unpacked(exe_dir)
}

//   Force a fresh unpack of assets.pkg from the executable directory.
//
// Parameters:
//   - none.
//
// Returns:
//   - ok: true when reload succeeds and assets are ready for path resolution.
reload_packaged_assets_root :: proc() -> bool {
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
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
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return 0, false
    }

    archive_path, archive_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_ARCHIVE},
        context.temp_allocator,
    )
    if archive_err != nil || !os.exists(archive_path) {
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
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return ""
    }

    if !ensure_packaged_assets_unpacked(exe_dir) {
        return ""
    }

    unpack_dir, unpack_ok := resolve_asset_unpack_dir(context.temp_allocator)
    if !unpack_ok {
        return ""
    }

    path, path_err := filepath.join(
        []string{unpack_dir, relative_path},
        allocator,
    )
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
    base_dir, base_err := os.user_cache_dir(allocator)
    if base_err != nil || len(base_dir) == 0 {
        base_dir, base_err = os.temp_directory(allocator)
        if base_err != nil || len(base_dir) == 0 {
            return "", false
        }
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
        "font.otf",
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

//   Return true when every byte in the slice is zero.
bytes_are_zero :: #force_inline proc(data: []u8) -> bool {
    for b in data {
        if b != 0 {
            return false
        }
    }
    return true
}

//   Trim leading and trailing spaces/nulls from a tar header field byte slice.
trim_tar_field :: #force_inline proc(data: []u8) -> []u8 {
    start := 0
    for start < len(data) && (data[start] == ' ' || data[start] == 0) {
        start += 1
    }

    stop := len(data)
    for stop > start && (data[stop - 1] == ' ' || data[stop - 1] == 0) {
        stop -= 1
    }

    return data[start:stop]
}

//   Parse an octal tar header field into an i64 value.
//
// Notes:
//   - Empty trimmed fields are treated as zero.
parse_tar_octal_i64 :: #force_inline proc(field: []u8, out: ^i64) -> bool {
    cleaned := trim_tar_field(field)
    if len(cleaned) == 0 {
        out^ = 0
        return true
    }

    value: i64 = 0
    for ch in cleaned {
        if ch < '0' || ch > '7' {
            return false
        }
        value = value * 8 + i64(ch - '0')
    }

    out^ = value
    return true
}

//   Validate that an archive entry path is a safe relative path.
//
// Notes:
//   - Rejects absolute paths and parent-directory traversal segments.
is_safe_asset_relative_path :: proc(path: string) -> bool {
    if len(path) == 0 || filepath.is_abs(path) {
        return false
    }

    clean_path, clean_err := filepath.clean(path, context.temp_allocator)
    if clean_err != nil || len(clean_path) == 0 || filepath.is_abs(clean_path) {
        return false
    }

    if clean_path == ".." ||
       strings.has_prefix(clean_path, "../") ||
       strings.has_prefix(clean_path, "..\\") {
        return false
    }

    return true
}

//   Parse a tar entry path from a 512-byte tar header block.
//
// Notes:
//   - Combines prefix/name fields when prefix is present.
parse_tar_entry_path :: #force_inline proc(header: []u8) -> (string, bool) {
    name := string(trim_tar_field(header[0:100]))
    prefix := string(trim_tar_field(header[345:500]))
    if len(prefix) == 0 {
        return name, true
    }

    joined, join_err := filepath.join([]string{prefix, name}, context.temp_allocator)
    if join_err != nil {
        fmt.eprintln("asset payload invalid: tar path join failed")
        return "", false
    }

    return joined, true
}

//   Write one regular-file tar entry into the unpack directory.
extract_packaged_asset_file_entry :: proc(unpack_dir, entry_path: string, file_data: []u8) -> bool {
    if !is_safe_asset_relative_path(entry_path) {
        fmt.eprintln("asset payload invalid path: ", entry_path)
        return false
    }

    out_path, out_err := filepath.join(
        []string{unpack_dir, entry_path},
        context.temp_allocator,
    )
    if out_err != nil {
        fmt.eprintln("asset payload path join failed: ", entry_path)
        return false
    }

    out_dir, _ := filepath.split(out_path)
    if len(out_dir) > 0 {
        if !os.is_directory(out_dir) && os.make_directory_all(out_dir) != nil {
            fmt.eprintln("asset payload mkdir failed: ", out_dir)
            return false
        }
    }

    if os.write_entire_file(out_path, file_data) != nil {
        fmt.eprintln("asset payload write failed: ", out_path)
        return false
    }

    return true
}

//   Ensure one directory tar entry exists in the unpack directory.
extract_packaged_asset_dir_entry :: proc(unpack_dir, entry_path: string) -> bool {
    if !is_safe_asset_relative_path(entry_path) {
        fmt.eprintln("asset payload invalid dir path: ", entry_path)
        return false
    }

    out_dir, out_err := filepath.join(
        []string{unpack_dir, entry_path},
        context.temp_allocator,
    )
    if out_err != nil {
        fmt.eprintln("asset payload dir join failed: ", entry_path)
        return false
    }

    if !os.is_directory(out_dir) && os.make_directory_all(out_dir) != nil {
        fmt.eprintln("asset payload mkdir failed: ", out_dir)
        return false
    }

    return true
}

//   Dispatch one tar entry based on type flag.
handle_packaged_asset_tar_entry :: proc(unpack_dir, entry_path: string, file_data: []u8, typeflag: u8) -> bool {
    switch typeflag {
    case 0, '0':
        return extract_packaged_asset_file_entry(unpack_dir, entry_path, file_data)

    case '5':
        return extract_packaged_asset_dir_entry(unpack_dir, entry_path)

    case 'x', 'g':
        // Skip pax metadata entries; the following real entry will be handled normally.
        return true

    case:
        fmt.eprintln("asset payload invalid: unsupported tar type: ", typeflag)
        return false
    }
}

//   Extract a gzip-decoded tar payload blob into the unpack directory.
//
// Notes:
//   - Supports regular files, directories, and skips pax metadata entries.
extract_packaged_assets_blob :: proc(unpack_dir: string, payload: []u8) -> bool {
    idx := 0

    for {
        if idx + 512 > len(payload) {
            fmt.eprintln("asset payload invalid: truncated tar header")
            return false
        }

        header := payload[idx:][:512]
        idx += 512

        if bytes_are_zero(header) {
            return true
        }

        entry_path, path_ok := parse_tar_entry_path(header)
        if !path_ok {
            return false
        }

        entry_size: i64 = 0
        if !parse_tar_octal_i64(header[124:136], &entry_size) || entry_size < 0 {
            fmt.eprintln("asset payload invalid: tar entry size")
            return false
        }

        file_size := int(entry_size)
        if idx + file_size > len(payload) {
            fmt.eprintln("asset payload invalid: tar entry size bounds")
            return false
        }

        file_data := payload[idx:][:file_size]
        padding := (512 - (file_size % 512)) % 512
        next_idx := idx + file_size + padding
        if next_idx > len(payload) {
            fmt.eprintln("asset payload invalid: tar padding bounds")
            return false
        }

        if !handle_packaged_asset_tar_entry(unpack_dir, entry_path, file_data, header[156]) {
            return false
        }

        idx = next_idx
    }
}

//   Ensure packaged assets are unpacked for a specific executable directory.
//
// Notes:
//   - Uses non-forced behavior and may reuse existing unpacked assets.
ensure_packaged_assets_unpacked :: proc(exe_dir: string) -> bool {
    return ensure_packaged_assets_unpacked_with_force(exe_dir, false)
}

//   Unpack assets.pkg for an executable directory with optional forced refresh.
//
// Notes:
//   - When force is true, existing unpacked content is removed and rebuilt.
ensure_packaged_assets_unpacked_with_force :: proc(exe_dir: string, force: bool) -> bool {
    archive_path, archive_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_ARCHIVE},
        context.temp_allocator,
    )
    if archive_err != nil {
        fmt.eprintln("asset unpack failed: could not build archive path")
        return false
    }

    unpack_dir, unpack_ok := resolve_asset_unpack_dir(context.temp_allocator)
    if !unpack_ok {
        fmt.eprintln("asset unpack failed: could not resolve writable unpack directory")
        return false
    }

    if !os.exists(archive_path) {
        fmt.eprintln("asset unpack failed: archive not found at ", archive_path)
        return os.is_directory(unpack_dir)
    }

    if !force && is_assets_unpack_ready(unpack_dir) {
        return true
    }

    _ = os.remove_all(unpack_dir)
    if os.make_directory_all(unpack_dir) != nil {
        fmt.eprintln("asset unpack failed: could not create unpack dir ", unpack_dir)
        return false
    }

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