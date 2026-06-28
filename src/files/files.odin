package files

import "core:bytes"
import gzip "core:compress/gzip"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

ASSET_PACKAGE_DIR :: ".assets"
ASSET_PACKAGE_ARCHIVE :: "assets.pkg"
ASSET_PACKAGE_MAGIC :: "EAPK1"

read_u16_le :: #force_inline proc(data: []u8, idx: ^int, out: ^int) -> bool {
    if idx^ + 2 > len(data) {
        return false
    }
    out^ = int(data[idx^ + 0]) | (int(data[idx^ + 1]) << 8)
    idx^ += 2
    return true
}

read_u32_le :: #force_inline proc(data: []u8, idx: ^int, out: ^int) -> bool {
    if idx^ + 4 > len(data) {
        return false
    }
    out^ = int(data[idx^ + 0]) |
        (int(data[idx^ + 1]) << 8) |
        (int(data[idx^ + 2]) << 16) |
        (int(data[idx^ + 3]) << 24)
    idx^ += 4
    return true
}

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

extract_packaged_assets_blob :: proc(unpack_dir: string, payload: []u8) -> bool {
    idx := 0
    if len(payload) < len(ASSET_PACKAGE_MAGIC) + 4 {
        fmt.eprintln("asset payload invalid: too short")
        return false
    }

    if string(payload[0:len(ASSET_PACKAGE_MAGIC)]) != ASSET_PACKAGE_MAGIC {
        fmt.eprintln("asset payload invalid: magic mismatch")
        return false
    }
    idx += len(ASSET_PACKAGE_MAGIC)

    entry_count := 0
    if !read_u32_le(payload, &idx, &entry_count) || entry_count < 0 || entry_count > 100000 {
        fmt.eprintln("asset payload invalid: entry count")
        return false
    }

    for _ in 0..<entry_count {
        path_len := 0
        file_size := 0
        if !read_u16_le(payload, &idx, &path_len) || !read_u32_le(payload, &idx, &file_size) {
            fmt.eprintln("asset payload invalid: entry header read")
            return false
        }
        if path_len <= 0 || file_size < 0 || idx + path_len + file_size > len(payload) {
            fmt.eprintln("asset payload invalid: entry header bounds")
            return false
        }

        entry_path := string(payload[idx:][:path_len])
        idx += path_len
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
            if os.make_directory_all(out_dir) != nil {
                fmt.eprintln("asset payload mkdir failed: ", out_dir)
                return false
            }
        }

        file_data := payload[idx:][:file_size]
        idx += file_size
        if os.write_entire_file(out_path, file_data) != nil {
            fmt.eprintln("asset payload write failed: ", out_path)
            return false
        }
    }

    if idx != len(payload) {
        fmt.eprintln("asset payload trailing bytes remain")
        return false
    }
    return true
}

ensure_packaged_assets_unpacked :: proc(exe_dir: string) -> bool {
    archive_path, archive_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_ARCHIVE},
        context.temp_allocator,
    )
    if archive_err != nil {
        fmt.eprintln("asset unpack failed: could not build archive path")
        return false
    }

    unpack_dir, unpack_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_DIR},
        context.temp_allocator,
    )
    if unpack_err != nil {
        fmt.eprintln("asset unpack failed: could not build unpack path")
        return false
    }

    if !os.exists(archive_path) {
        fmt.eprintln("asset unpack failed: archive not found at ", archive_path)
        return os.is_directory(unpack_dir)
    }

    _ = os.remove_all(unpack_dir)
    if os.make_directory_all(unpack_dir) != nil {
        fmt.eprintln("asset unpack failed: could not create unpack dir ", unpack_dir)
        return false
    }

    desc := os.Process_Desc{
        command = []string{"tar", "-xzf", archive_path, "-C", unpack_dir},
    }

    state, _, _, exec_err := os.process_exec(desc, context.temp_allocator)
    if exec_err != nil {
        fmt.eprintln("asset unpack failed: tar extraction failed")
        return false
    }
    if !state.exited || state.exit_code != 0 {
        fmt.eprintln("asset unpack failed: tar exited with code ", state.exit_code)
        return false
    }

    return true
}

ensure_packaged_assets_unpacked_root :: proc() {
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return
    }

    _ = ensure_packaged_assets_unpacked(exe_dir)
}

packaged_asset_path :: proc(relative_path: string, allocator := context.allocator) -> string {
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return ""
    }

    if !ensure_packaged_assets_unpacked(exe_dir) {
        return ""
    }

    path, path_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_DIR, relative_path},
        allocator,
    )
    if path_err != nil {
        return ""
    }

    return path
}

cleanup_packaged_assets_dir :: proc() {
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return
    }

    unpack_dir, unpack_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_DIR},
        context.temp_allocator,
    )
    if unpack_err != nil || len(unpack_dir) == 0 {
        return
    }

    _ = os.remove_all(unpack_dir)
}
