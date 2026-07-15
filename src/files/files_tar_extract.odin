package files

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

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
extract_packaged_asset_file_entry :: proc(
    unpack_dir, entry_path: string, file_data: []u8) -> bool {

    if !is_safe_asset_relative_path(entry_path) {
        fmt.eprintln("asset payload invalid path: ", entry_path)
        return false
    }

    out_path, out_err := filepath.join(
        []string{unpack_dir, entry_path}, context.temp_allocator)
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
        []string{unpack_dir, entry_path}, context.temp_allocator)
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
handle_packaged_asset_tar_entry :: proc(
    unpack_dir, entry_path: string, file_data: []u8, typeflag: u8) -> bool {

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

//   Read one 512-byte tar header at idx and advance to entry-data start.
//
// Returns:
//   - header: Tar header block.
//   - data_idx: Payload index immediately after header.
//   - done: True when end-of-archive marker is reached.
//   - ok: False when payload is malformed.
read_tar_header :: proc(payload: []u8, idx: int) -> ([]u8, int, bool, bool) {
    if idx + 512 > len(payload) {
        fmt.eprintln("asset payload invalid: truncated tar header")
        return nil, idx, false, false
    }

    header := payload[idx:][:512]
    data_idx := idx + 512
    if bytes_are_zero(header) {
        return header, data_idx, true, true
    }

    return header, data_idx, false, true
}

//   Parse and validate tar entry path and size from one tar header block.
//
// Returns:
//   - entry_path: Relative entry path.
//   - file_size: Entry payload size in bytes.
//   - ok: False when entry metadata is invalid.
parse_tar_entry_metadata :: proc(header: []u8) -> (string, int, bool) {
    entry_path, path_ok := parse_tar_entry_path(header)
    if !path_ok {
        return "", 0, false
    }

    entry_size: i64 = 0
    if !parse_tar_octal_i64(header[124:136], &entry_size) || entry_size < 0 {
        fmt.eprintln("asset payload invalid: tar entry size")
        return "", 0, false
    }

    return entry_path, int(entry_size), true
}

//   Slice entry file bytes and compute the next tar-header index.
//
// Returns:
//   - file_data: Entry payload bytes.
//   - next_idx: Index of the next tar header.
//   - ok: False when payload bounds are invalid.
slice_tar_entry_data :: proc(payload: []u8, data_idx, file_size: int) -> ([]u8, int, bool) {
    if data_idx + file_size > len(payload) {
        fmt.eprintln("asset payload invalid: tar entry size bounds")
        return nil, data_idx, false
    }

    file_data := payload[data_idx:][:file_size]
    padding := (512 - (file_size % 512)) % 512
    next_idx := data_idx + file_size + padding
    if next_idx > len(payload) {
        fmt.eprintln("asset payload invalid: tar padding bounds")
        return nil, data_idx, false
    }

    return file_data, next_idx, true
}

//   Extract a gzip-decoded tar payload blob into the unpack directory.
//
// Notes:
//   - Supports regular files, directories, and skips pax metadata entries.
extract_packaged_assets_blob :: proc(unpack_dir: string, payload: []u8) -> bool {
    idx := 0

    for {
        header, data_idx, done, header_ok := read_tar_header(payload, idx)
        if !header_ok {
            return false
        }
        if done {
            return true
        }

        entry_path, file_size, meta_ok := parse_tar_entry_metadata(header)
        if !meta_ok {
            return false
        }

        file_data, next_idx, data_ok := slice_tar_entry_data(payload, data_idx, file_size)
        if !data_ok {
            return false
        }

        if !handle_packaged_asset_tar_entry(unpack_dir, entry_path, file_data, header[156]) {
            return false
        }

        idx = next_idx
    }
}
