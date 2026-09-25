package files

// The main point here is to unpack assets.pkg from next to the executable into a
// user-writable location and provide the unpacked file paths to other modules.

import "core:bytes"
import "core:compress/gzip"
import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

ASSET_PACKAGE_ROOT_DIR :: "EuclidApp"
ASSET_PACKAGE_DIR :: "assets"
ASSET_PACKAGE_ARCHIVE :: "assets.pkg"
ASSET_PACKAGE_IDENTITY :: "assets.pkg.identity"
ASSET_CACHE_SCHEMA_DIR :: "v3"
GIF_OUTPUT_DIR_NAME :: "gifs"
SYSIMAGE_CACHE_DIR_NAME :: "sysimages"
ASSET_MANIFEST_MAX_BYTES :: 4096

when ODIN_OS == .Windows {
    PACKAGED_SYSIMAGE_FILENAME :: "euclid-sysimage.dll"
    PACKAGED_SYSIMAGE_PLATFORM :: "nt-" + ODIN_ARCH_STRING
} else when ODIN_OS == .Darwin {
    PACKAGED_SYSIMAGE_FILENAME :: "euclid-sysimage.dylib"
    PACKAGED_SYSIMAGE_PLATFORM :: "darwin-" + ODIN_ARCH_STRING
} else {
    PACKAGED_SYSIMAGE_FILENAME :: "euclid-sysimage.so"
    PACKAGED_SYSIMAGE_PLATFORM :: "linux-" + ODIN_ARCH_STRING
}

Asset_Root_Config :: struct {
    asset_root_override: string,
}

// Gif_Output_Transaction owns one reserved sibling temporary path until publication.
Gif_Output_Transaction :: struct {
    final_path: string,
    temporary_path: string,
}


Unpack_Targets :: struct {
    archive_path: string,
    unpack_dir:   string,
    package_identity: string,
    archive_sha256: string,
    ok:           bool,
}

Packaged_Sysimage_Metadata :: struct {
    relative_path:     string,
    input_fingerprint: string,
    artifact_sha256:   string,
    package_identity:  string,
}

Asset_Package_Sidecar :: struct {
    package_identity: string,
    archive_sha256:   string,
}

Asset_Sidecar_Parse_State :: struct {
    sidecar: Asset_Package_Sidecar,
    schema_seen: bool,
    identity_seen: bool,
    digest_seen: bool,
}

Manifest_Parse_State :: struct {
    metadata:    Packaged_Sysimage_Metadata,
    schema_seen: bool,
    path_seen:   bool,
    input_seen:  bool,
    digest_seen: bool,
    identity_seen: bool,
    platform_ok: bool,
}

//   Release strings retained by packaged sysimage metadata.
destroy_packaged_sysimage_metadata :: proc(
    metadata: ^Packaged_Sysimage_Metadata, allocator: mem.Allocator) {
    if metadata == nil {
        return
    }
    delete(metadata.relative_path, allocator)
    delete(metadata.input_fingerprint, allocator)
    delete(metadata.artifact_sha256, allocator)
    delete(metadata.package_identity, allocator)
    metadata^ = {}
}

//   Release strings retained from one package identity sidecar.
destroy_asset_package_sidecar :: proc(
    sidecar: ^Asset_Package_Sidecar, allocator: mem.Allocator) {
    if sidecar == nil {return}
    delete(sidecar.package_identity, allocator)
    delete(sidecar.archive_sha256, allocator)
    sidecar^ = {}
}

//   Return whether text is one full lowercase SHA-256 digest.
is_lower_sha256 :: proc(value: string) -> bool {
    if len(value) != 64 {
        return false
    }
    for character in value {
        if !(character >= '0' && character <= '9') &&
           !(character >= 'a' && character <= 'f') {
            return false
        }
    }
    return true
}

//   Decode one canonical lowercase SHA-256 identity into fixed storage.
parse_lower_sha256 :: proc(value: string) -> ([32]byte, bool) {
    if !is_lower_sha256(value) {return {}, false}
    result: [32]byte
    for index in 0..<32 {
        high := value[index * 2]
        low := value[index * 2 + 1]
        high_value := high <= '9' ? high - '0' : high - 'a' + 10
        low_value := low <= '9' ? low - '0' : low - 'a' + 10
        result[index] = byte(high_value << 4 | low_value)
    }
    return result, true
}

//   Clone one manifest value exactly once.
assign_unique_manifest_string :: proc(
    target: ^string, seen: ^bool, value: string,
    allocator: mem.Allocator) -> bool {
    if seen^ {
        return false
    }
    target^ = strings.clone(value, allocator)
    seen^ = true
    return true
}

//   Capture one recognized manifest field while rejecting duplicates.
assign_sysimage_manifest_field :: proc(
    state: ^Manifest_Parse_State, key, value: string,
    allocator: mem.Allocator) -> bool {
    switch key {
    case "schema_version":
        if state.schema_seen || value != "3" { return false }
        state.schema_seen = true
    case "package_identity":
        return assign_unique_manifest_string(
            &state.metadata.package_identity, &state.identity_seen,
            value, allocator)
    case "sysimage_path":
        return assign_unique_manifest_string(
            &state.metadata.relative_path, &state.path_seen, value, allocator)
    case "sysimage_input_fingerprint":
        return assign_unique_manifest_string(
            &state.metadata.input_fingerprint, &state.input_seen,
            value, allocator)
    case "sysimage_artifact_sha256":
        return assign_unique_manifest_string(
            &state.metadata.artifact_sha256, &state.digest_seen,
            value, allocator)
    case "sysimage_platform":
        state.platform_ok = value == PACKAGED_SYSIMAGE_PLATFORM
    }
    return true
}

//   Parse and validate bounded packaged sysimage metadata.
parse_packaged_sysimage_manifest :: proc(
    source: string, allocator: mem.Allocator) -> (Packaged_Sysimage_Metadata, bool) {
    if len(source) == 0 || len(source) > ASSET_MANIFEST_MAX_BYTES {
        return {}, false
    }
    state := Manifest_Parse_State{}
    remaining := source
    for len(remaining) > 0 {
        newline := strings.index_byte(remaining, '\n')
        line := remaining
        if newline >= 0 {
            line = remaining[:newline]
            remaining = remaining[newline + 1:]
        } else {
            remaining = ""
        }
        separator := strings.index_byte(line, '=')
        if separator <= 0 || !assign_sysimage_manifest_field(
            &state, line[:separator], line[separator + 1:], allocator) {
            destroy_packaged_sysimage_metadata(&state.metadata, allocator)
            return {}, false
        }
    }
    valid := state.schema_seen && state.identity_seen && state.path_seen &&
        state.input_seen && state.digest_seen && state.platform_ok &&
        is_safe_asset_relative_path(state.metadata.relative_path) &&
        strings.has_prefix(state.metadata.relative_path, "sysimage/") &&
        strings.has_suffix(state.metadata.relative_path, PACKAGED_SYSIMAGE_FILENAME) &&
        is_lower_sha256(state.metadata.package_identity) &&
        is_lower_sha256(state.metadata.input_fingerprint) &&
        is_lower_sha256(state.metadata.artifact_sha256)
    if !valid {
        destroy_packaged_sysimage_metadata(&state.metadata, allocator)
    }
    return state.metadata, valid
}

//   Assign one recognized sidecar field while rejecting duplicates.
assign_asset_sidecar_field :: proc(
    state: ^Asset_Sidecar_Parse_State, key, value: string,
    allocator: mem.Allocator) -> bool {
    switch key {
    case "schema_version":
        if state.schema_seen || value != "1" {return false}
        state.schema_seen = true
    case "package_identity":
        if state.identity_seen {return false}
        state.sidecar.package_identity = strings.clone(value, allocator)
        state.identity_seen = true
    case "archive_sha256":
        if state.digest_seen {return false}
        state.sidecar.archive_sha256 = strings.clone(value, allocator)
        state.digest_seen = true
    case:
        return false
    }
    return true
}

//   Parse one bounded package identity sidecar.
parse_asset_package_sidecar :: proc(
    source: string, allocator: mem.Allocator) -> (Asset_Package_Sidecar, bool) {
    if len(source) == 0 || len(source) > ASSET_MANIFEST_MAX_BYTES {
        return {}, false
    }
    state: Asset_Sidecar_Parse_State
    remaining := source
    for len(remaining) > 0 {
        newline := strings.index_byte(remaining, '\n')
        line := remaining
        if newline >= 0 {
            line = remaining[:newline]
            remaining = remaining[newline + 1:]
        } else {remaining = ""}
        separator := strings.index_byte(line, '=')
        if separator <= 0 || !assign_asset_sidecar_field(
            &state, line[:separator], line[separator + 1:], allocator) {
            destroy_asset_package_sidecar(&state.sidecar, allocator)
            return {}, false
        }
    }
    valid := state.schema_seen && state.identity_seen && state.digest_seen &&
        is_lower_sha256(state.sidecar.package_identity) &&
        is_lower_sha256(state.sidecar.archive_sha256)
    if !valid {destroy_asset_package_sidecar(&state.sidecar, allocator)}
    return state.sidecar, valid
}

//   Read the committed identity paired with one adjacent assets package.
read_asset_package_sidecar :: proc(
    exe_dir: string, allocator: mem.Allocator) -> (Asset_Package_Sidecar, bool) {
    path, path_err := filepath.join(
        []string{exe_dir, ASSET_PACKAGE_IDENTITY}, context.temp_allocator)
    if path_err != nil {return {}, false}
    source, read_err := os.read_entire_file(path, context.temp_allocator)
    if read_err != nil {return {}, false}
    return parse_asset_package_sidecar(string(source), allocator)
}

//   Read validated sysimage metadata from one extracted asset tree.
read_packaged_sysimage_metadata :: proc(
    unpack_dir: string, allocator: mem.Allocator) -> (Packaged_Sysimage_Metadata, bool) {
    manifest_path, path_err := filepath.join(
        []string{unpack_dir, "manifest.txt"}, context.temp_allocator)
    if path_err != nil {
        return {}, false
    }
    source, read_err := os.read_entire_file(manifest_path, context.temp_allocator)
    if read_err != nil {
        return {}, false
    }
    return parse_packaged_sysimage_manifest(string(source), allocator)
}

//   Compare a SHA-256 digest with its canonical lowercase hexadecimal form.
sha256_digest_matches :: proc(digest: [32]byte, expected: string) -> bool {
    HEX :: "0123456789abcdef"
    hexadecimal := HEX
    if len(expected) != 64 {
        return false
    }
    for value, index in digest {
          if expected[index * 2] != hexadecimal[value >> 4] ||
              expected[index * 2 + 1] != hexadecimal[value & 0x0f] {
            return false
        }
    }
    return true
}

//   Verify one regular file against its expected SHA-256 without loading it whole.
file_matches_sha256 :: proc(path, expected: string) -> bool {
    file, open_err := os.open(path)
    if open_err != nil {
        return false
    }
    defer os.close(file)
    hash := sha2.Context_256{}
    sha2.init_256(&hash)
    buffer: [64 * 1024]byte
    for {
        count, read_err := os.read(file, buffer[:])
        if count > 0 {
            sha2.update(&hash, buffer[:count])
        }
        if read_err == .EOF {
            break
        }
        if read_err != nil {
            return false
        }
        if count == 0 {
            break
        }
    }
    digest: [32]byte
    sha2.final(&hash, digest[:])
    return sha256_digest_matches(digest, expected)
}

//   Return the immutable cache root beside the mutable unpack directory.
resolve_sysimage_cache_root :: proc(
    unpack_dir: string, allocator: mem.Allocator) -> (string, bool) {
    schema_root := filepath.dir(unpack_dir)
    assets_root := filepath.dir(schema_root)
    package_root := schema_root
    if filepath.base(schema_root) == ASSET_CACHE_SCHEMA_DIR &&
       filepath.base(assets_root) == ASSET_PACKAGE_DIR {
        package_root = filepath.dir(assets_root)
    }
    path, path_err := filepath.join(
        []string{package_root, SYSIMAGE_CACHE_DIR_NAME}, allocator)
    return path, path_err == nil && len(path) > 0
}

//   Copy and atomically publish one verified image at an empty destination path.
publish_verified_sysimage_copy :: proc(
    source, destination, expected_digest: string) -> bool {
    candidate := fmt.tprintf("%s.candidate", destination)
    _ = os.remove(candidate)
    if os.copy_file(candidate, source) != nil ||
       !file_matches_sha256(candidate, expected_digest) ||
       os.rename(candidate, destination) != nil ||
       !file_matches_sha256(destination, expected_digest) {
        _ = os.remove(candidate)
        return false
    }
    return true
}

//   Materialize and verify one image at its immutable digest-addressed path.
materialize_packaged_sysimage :: proc(
    unpack_dir: string, metadata: ^Packaged_Sysimage_Metadata,
    allocator: mem.Allocator) -> (string, bool) {
    source, source_err := filepath.join(
        []string{unpack_dir, metadata.relative_path}, context.temp_allocator)
    if source_err != nil || !file_matches_sha256(source, metadata.artifact_sha256) {
        return "", false
    }
    cache_root, root_ok := resolve_sysimage_cache_root(
        unpack_dir, context.temp_allocator)
    if !root_ok {
        return "", false
    }
    directory, directory_err := filepath.join(
        []string{cache_root, metadata.artifact_sha256}, context.temp_allocator)
    if directory_err != nil || !ensure_directory_exists(directory) {
        return "", false
    }
    destination, destination_err := filepath.join(
        []string{directory, PACKAGED_SYSIMAGE_FILENAME}, allocator)
    if destination_err != nil {
        return "", false
    }
    if file_matches_sha256(destination, metadata.artifact_sha256) {
        return destination, true
    }
    _ = os.remove(destination)
    if !publish_verified_sysimage_copy(
        source, destination, metadata.artifact_sha256) {
        delete(destination, allocator)
        return "", false
    }
    return destination, true
}

//   Materialize the image declared by the currently extracted asset tree.
materialize_current_packaged_sysimage :: proc(
    exe_dir: string, allocator: mem.Allocator) -> (string, bool) {
    unpack_dir, unpack_ok := resolve_current_asset_unpack_dir(
        exe_dir, context.temp_allocator)
    if !unpack_ok {
        return "", false
    }
    metadata, metadata_ok := read_packaged_sysimage_metadata(
        unpack_dir, context.temp_allocator)
    if !metadata_ok {
        return "", false
    }
    return materialize_packaged_sysimage(unpack_dir, &metadata, allocator)
}

//   Resolve the mandatory verified image, retrying one archive extraction on damage.
resolve_packaged_sysimage_path :: proc(
    config: ^Asset_Root_Config = nil,
    allocator := context.temp_allocator) -> (string, bool) {
    exe_dir, exe_ok := resolve_executable_dir_with_config(
        config, context.temp_allocator)
    if !exe_ok || !ensure_packaged_assets_unpacked_with_force(exe_dir, false) {
        return "", false
    }
    path, ok := materialize_current_packaged_sysimage(exe_dir, allocator)
    if ok {
        return path, true
    }
    if !ensure_packaged_assets_unpacked_with_force(exe_dir, true) {
        return "", false
    }
    return materialize_current_packaged_sysimage(exe_dir, allocator)
}

//   Return the active extracted package's validated sysimage input fingerprint.
packaged_sysimage_input_fingerprint :: proc(
    allocator: mem.Allocator) -> (string, bool) {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {return "", false}
    unpack_dir, unpack_ok := resolve_current_asset_unpack_dir(
        exe_dir, context.temp_allocator)
    if !unpack_ok {
        return "", false
    }
    metadata, metadata_ok := read_packaged_sysimage_metadata(
        unpack_dir, context.temp_allocator)
    if !metadata_ok {
        return "", false
    }
    return strings.clone(metadata.input_fingerprint, allocator), true
}

//   Construct a packaged-asset-root config that can override the executable-root lookup.
//
// Parameters:
//   - root_dir: Directory that directly contains assets.pkg.
//   - allocator: Allocator used for the retained override path.
//
// Returns:
//   - config: Config containing the override root when provided.
make_asset_root_config :: proc(
    root_dir: string, allocator: mem.Allocator) -> Asset_Root_Config {
    config := Asset_Root_Config{}
    if len(root_dir) > 0 {
        config.asset_root_override = strings.clone(root_dir, allocator)
    }
    return config
}

//   Release any override path captured in a packaged-asset-root config.
//
// Parameters:
//   - config: Config whose override path should be freed.
//   - allocator: Allocator used by the override path.
//
// Returns:
//   - none.
destroy_asset_root_config :: proc(
    config: ^Asset_Root_Config, allocator := context.allocator) {
    if config == nil {
        return
    }

    if len(config.asset_root_override) > 0 {
        delete(config.asset_root_override, allocator)
        config.asset_root_override = ""
    }
}

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
        allocator)
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
resolve_writable_pictures_dir :: proc(
    allocator := context.temp_allocator) -> (string, bool) {
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

//   Generate the timestamped filename used for one GIF export.
gif_output_filename :: proc() -> string {
    now := time.now()
    year := time.year(now)
    month := int(time.month(now))
    day := time.day(now)
    hour, minute, second, nanos := time.precise_clock(now)
    millis := nanos / 1_000_000
    return fmt.tprintf("Euclid_%04d-%02d-%02d_%02d-%02d-%02d-%03d.gif",
        year, month, day, hour, minute, second, millis)
}

//   Reserve an empty sibling temporary file for one exact GIF output filename.
reserve_gif_output_transaction_in_directory :: proc(
    output_dir, filename: string,
    allocator: mem.Allocator) -> (Gif_Output_Transaction, bool) {
    if len(output_dir) == 0 || len(filename) == 0 ||
       filepath.base(filename) != filename || !strings.has_suffix(filename, ".gif") {
        return {}, false
    }

    final_path, final_error := filepath.join(
        []string{output_dir, filename}, allocator)
    if final_error != nil || len(final_path) == 0 || os.exists(final_path) {
        delete(final_path, allocator)
        return {}, false
    }
    temporary_path := fmt.aprintf(
        "%s.partial.gif", final_path[:len(final_path) - len(".gif")],
        allocator=allocator)
    temporary_file, open_error := os.open(
        temporary_path, {.Write, .Create, .Excl})
    if open_error != nil {
        delete(temporary_path, allocator)
        delete(final_path, allocator)
        return {}, false
    }
    os.close(temporary_file)
    return {final_path = final_path, temporary_path = temporary_path}, true
}

//   Reserve one generated GIF destination and its sibling temporary file.
reserve_gif_output_transaction :: proc(
    allocator: mem.Allocator) -> (Gif_Output_Transaction, bool) {
    output_dir, output_ok := resolve_writable_pictures_dir(context.temp_allocator)
    if !output_ok {
        return {}, false
    }
    return reserve_gif_output_transaction_in_directory(
        output_dir, gif_output_filename(), allocator)
}

//   Atomically publish a completed temporary GIF at its reserved final path.
publish_gif_output_transaction :: proc(transaction: ^Gif_Output_Transaction) -> bool {
    if transaction == nil || len(transaction.final_path) == 0 ||
       len(transaction.temporary_path) == 0 || os.exists(transaction.final_path) {
        return false
    }
    return os.rename(transaction.temporary_path, transaction.final_path) == nil
}

//   Remove an unpublished temporary GIF and release transaction path storage.
destroy_gif_output_transaction :: proc(
    transaction: ^Gif_Output_Transaction, allocator: mem.Allocator) {
    if transaction == nil {
        return
    }
    if len(transaction.temporary_path) > 0 && os.exists(transaction.temporary_path) {
        _ = os.remove(transaction.temporary_path)
    }
    delete(transaction.temporary_path, allocator)
    delete(transaction.final_path, allocator)
    transaction^ = {}
}

//   Ensure assets.pkg is unpacked for the current executable directory.
//
// Parameters:
//   - none.
//
// Returns:
//   - ok: true when packaged assets are available for path resolution.
//
// Notes:
//   - Lower-level path resolution may reuse a previously validated unpack tree.
ensure_packaged_assets_unpacked_root :: proc(
    config: ^Asset_Root_Config = nil) -> bool {

    exe_dir, exe_ok := resolve_executable_dir_with_config(config, context.temp_allocator)
    if !exe_ok {
        return false
    }

    return ensure_packaged_assets_unpacked_with_force(exe_dir, false)
}

//   Return whether assets.pkg exists beside the selected application executable.
packaged_asset_archive_exists_root :: proc(
    config: ^Asset_Root_Config = nil) -> bool {

    exe_dir, exe_ok := resolve_executable_dir_with_config(config, context.temp_allocator)
    if !exe_ok {
        fmt.eprintln("asset startup failed: could not resolve executable directory")
        return false
    }
    archive_path, archive_ok := join_archive_path(exe_dir, context.temp_allocator)
    if !archive_ok || !os.exists(archive_path) {
        fmt.eprintln("asset startup failed: archive not found at ", archive_path)
        return false
    }
    _, sidecar_ok := read_asset_package_sidecar(
        exe_dir, context.temp_allocator)
    if !sidecar_ok {
        fmt.eprintln("asset startup failed: package identity is missing or invalid")
        return false
    }
    return true
}

//   Force a fresh unpack of assets.pkg from the executable directory.
//
// Parameters:
//   - config: Optional packaged-asset root override configuration.
//
// Returns:
//   - ok: true when reload succeeds and assets are ready for path resolution.
reload_packaged_assets_root :: proc(config: ^Asset_Root_Config = nil) -> bool {
    exe_dir, exe_ok := resolve_executable_dir_with_config(config, context.temp_allocator)
    if !exe_ok {
        return false
    }

    return ensure_packaged_assets_unpacked_with_force(exe_dir, true)
}

//   Reload assets only when their image fingerprint matches the active runtime.
reload_compatible_packaged_assets_root :: proc(
    expected_fingerprint: string,
    config: ^Asset_Root_Config = nil) -> bool {
    exe_dir, exe_ok := resolve_executable_dir_with_config(config, context.temp_allocator)
    if !exe_ok || !is_lower_sha256(expected_fingerprint) {
        return false
    }
    targets := resolve_unpack_targets(exe_dir)
    if !targets.ok {
        return false
    }
    return replace_packaged_asset_tree(
        targets.archive_path, targets.unpack_dir, targets.package_identity,
        targets.archive_sha256, expected_fingerprint)
}

//   Force a fresh unpack of assets.pkg from an explicit root config.
reload_packaged_assets_root_with_config :: proc(
    config: ^Asset_Root_Config) -> bool {
    return reload_packaged_assets_root(config)
}

//   Read the committed semantic identity of the adjacent assets package.
//
// Parameters:
//   - none.
//
// Returns:
//   - identity: Fixed SHA-256 identity when the sidecar is valid.
//   - ok: true when the committed identity was read and decoded.
packaged_asset_package_identity :: proc() -> ([32]byte, bool) {
    exe_dir, exe_ok := resolve_executable_dir(context.temp_allocator)
    if !exe_ok {
        return {}, false
    }
    sidecar, sidecar_ok := read_asset_package_sidecar(
        exe_dir, context.temp_allocator)
    if !sidecar_ok {return {}, false}
    return parse_lower_sha256(sidecar.package_identity)
}

//   Resolve an absolute path for a packaged asset relative path.
//
// Parameters:
//   - relative_path: Asset path relative to the unpack root (for example "julia/script.jl").
//   - allocator: Allocator used for the returned joined path.
//
// Returns:
//   - asset_path: Joined absolute path when successful, otherwise "".
packaged_asset_path :: proc(
    relative_path: string, allocator: mem.Allocator) -> string {
    return packaged_asset_path_with_config(nil, relative_path, allocator)
}

//   Resolve an absolute path for a packaged asset relative path under an optional root config.
packaged_asset_path_with_config :: proc(
    config: ^Asset_Root_Config,
    relative_path: string,
    allocator: mem.Allocator) -> string {
    exe_dir, exe_ok := resolve_executable_dir_with_config(config, context.temp_allocator)
    if !exe_ok {
        return ""
    }

    if !ensure_packaged_assets_unpacked_with_force(exe_dir, false) {
        return ""
    }

    unpack_dir, unpack_ok := resolve_current_asset_unpack_dir(
        exe_dir, context.temp_allocator)
    if !unpack_ok {
        return ""
    }

    path, path_err := filepath.join([]string{unpack_dir, relative_path}, allocator)
    if path_err != nil {
        return ""
    }

    return path
}

//   Resolve executable directory once with standard validity checks.
resolve_executable_dir :: proc(allocator := context.temp_allocator) -> (string, bool) {
    return resolve_executable_dir_with_config(nil, allocator)
}

//   Resolve the executable directory while honoring an explicit asset-root config.
resolve_executable_dir_with_config :: proc(
    config: ^Asset_Root_Config,
    allocator := context.temp_allocator) -> (string, bool) {
    if config != nil && len(config.asset_root_override) > 0 {
        return config.asset_root_override, true
    }

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

//   Resolve the writable cache generation for one semantic package identity.
//
// Notes:
//   - Prefers user cache directory and falls back to temp directory.
resolve_asset_unpack_dir :: proc(
    package_identity: string,
    allocator := context.temp_allocator) -> (string, bool) {
    if !is_lower_sha256(package_identity) {return "", false}
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
        []string{base_dir, ASSET_PACKAGE_ROOT_DIR, ASSET_PACKAGE_DIR,
            ASSET_CACHE_SCHEMA_DIR, package_identity},
        allocator)
    if unpack_err != nil || len(unpack_dir) == 0 {
        return "", false
    }

    return unpack_dir, true
}

//   Resolve the cache generation committed beside one executable directory.
resolve_current_asset_unpack_dir :: proc(
    exe_dir: string,
    allocator := context.temp_allocator) -> (string, bool) {
    sidecar, sidecar_ok := read_asset_package_sidecar(
        exe_dir, context.temp_allocator)
    if !sidecar_ok {return "", false}
    return resolve_asset_unpack_dir(sidecar.package_identity, allocator)
}

//   Return whether all fixed baseline files exist in one extracted tree.
baseline_asset_entries_exist :: proc(unpack_dir: string) -> bool {
    required_entries := []string{
        "julia/script.jl",
        "content/animation_catalog_generation.jl",
        "content/animation_catalog_data.jl",
        "compass_icon.png",
        "JuliaMono-Regular.ttf",
        "NewCMSansMath-Regular.otf",
        "manifest.txt",
    }

    for entry in required_entries {
        path, path_err :=
            filepath.join([]string{unpack_dir, entry}, context.temp_allocator)
        if path_err != nil || !os.exists(path) {
            return false
        }
    }
    return true
}

//   Return whether this platform's compiled terminfo entry exists when required.
platform_terminfo_exists :: proc(unpack_dir: string) -> bool {
    relative_path := ""
    when ODIN_OS == .Linux {
        relative_path = "terminfo/e/euclid"
    } else when ODIN_OS == .Darwin {
        relative_path = "terminfo/65/euclid"
    } else {
        return true
    }
    path, path_err := filepath.join(
        []string{unpack_dir, relative_path}, context.temp_allocator)
    return path_err == nil && os.exists(path)
}

//   Check whether an unpack directory has baseline assets and a declared image.
is_assets_unpack_ready :: proc(
    unpack_dir, expected_package_identity: string) -> bool {
    if !os.is_directory(unpack_dir) || !baseline_asset_entries_exist(unpack_dir) {
        return false
    }
    metadata, metadata_ok := read_packaged_sysimage_metadata(
        unpack_dir, context.temp_allocator)
    if !metadata_ok {
        return false
    }
    if metadata.package_identity != expected_package_identity {return false}
    image_path, image_err := filepath.join(
        []string{unpack_dir, metadata.relative_path}, context.temp_allocator)
    if image_err != nil || !os.exists(image_path) {
        return false
    }
    return platform_terminfo_exists(unpack_dir)
}

//   Resolve archive/unpack paths and validate baseline unpack prerequisites.
//
// Returns:
//   - archive_path: Expected archive file path.
//   - unpack_dir: Writable unpack root directory.
//   - ok: true when both paths are valid and unpack dir can be resolved.
resolve_unpack_targets :: proc(exe_dir: string) -> Unpack_Targets {
    archive_path, archive_ok := join_archive_path(exe_dir, context.temp_allocator)
    if !archive_ok {
        fmt.eprintln("asset unpack failed: could not build archive path")
        return {}
    }
    sidecar, sidecar_ok := read_asset_package_sidecar(
        exe_dir, context.temp_allocator)
    if !sidecar_ok {
        fmt.eprintln("asset unpack failed: package identity is missing or invalid")
        return {}
    }
    unpack_dir, unpack_ok := resolve_asset_unpack_dir(
        sidecar.package_identity, context.temp_allocator)
    if !unpack_ok {
        fmt.eprintln("asset unpack failed: could not resolve writable unpack directory")
        return {}
    }
    return Unpack_Targets{archive_path, unpack_dir,
        sidecar.package_identity, sidecar.archive_sha256, true}
}

//   Decide whether unpack work is needed based on archive presence and force flag.
//
// Returns:
//   - continue_unpack: true when caller should proceed with unpack work.
//   - result: return value the caller should use when unpack should not continue.
should_continue_unpack :: proc(
    archive_path, unpack_dir, package_identity: string,
    force: bool) -> (bool, bool) {
    if !os.exists(archive_path) {
        fmt.eprintln("asset unpack failed: archive not found at ", archive_path)
        return false, os.is_directory(unpack_dir)
    }

    if !force && is_assets_unpack_ready(unpack_dir, package_identity) {
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

//   Publish a validated candidate tree while preserving the previous tree on failure.
publish_candidate_unpack_directory :: proc(
    candidate_dir, unpack_dir, backup_dir: string) -> bool {
    _ = os.remove_all(backup_dir)
    had_active := os.is_directory(unpack_dir)
    if had_active && os.rename(unpack_dir, backup_dir) != nil {
        fmt.eprintln("asset unpack failed: could not preserve active asset tree")
        return false
    }
    if os.rename(candidate_dir, unpack_dir) != nil {
        if had_active {
            _ = os.rename(backup_dir, unpack_dir)
        }
        fmt.eprintln("asset unpack failed: could not publish candidate asset tree")
        return false
    }
    _ = os.remove_all(backup_dir)
    return true
}

//   Extract and validate an archive into a sibling candidate directory.
replace_packaged_asset_tree :: proc(
    archive_path, unpack_dir, package_identity, archive_sha256: string,
    expected_fingerprint: string = "") -> bool {
    candidate_dir := fmt.tprintf("%s.candidate", unpack_dir)
    backup_dir := fmt.tprintf("%s.previous", unpack_dir)
    if !file_matches_sha256(archive_path, archive_sha256) {
        fmt.eprintln("asset unpack failed: archive digest does not match identity")
        return false
    }
    if !prepare_unpack_directory(candidate_dir) {
        return false
    }
    if !decode_and_extract_archive_payload(archive_path, candidate_dir) ||
       !is_assets_unpack_ready(candidate_dir, package_identity) {
        _ = os.remove_all(candidate_dir)
        fmt.eprintln("asset unpack failed: candidate asset tree is incomplete")
        return false
    }
    if len(expected_fingerprint) > 0 {
        metadata, metadata_ok := read_packaged_sysimage_metadata(
            candidate_dir, context.temp_allocator)
        if !metadata_ok || metadata.input_fingerprint != expected_fingerprint {
            _ = os.remove_all(candidate_dir)
            fmt.eprintln("Julia asset reload requires restart: sysimage changed")
            return false
        }
    }
    if !publish_candidate_unpack_directory(candidate_dir, unpack_dir, backup_dir) {
        _ = os.remove_all(candidate_dir)
        return false
    }
    return true
}

//   Unpack assets.pkg for an executable directory with optional forced refresh.
//
// Notes:
//   - When force is true, existing unpacked content is removed and rebuilt.
ensure_packaged_assets_unpacked_with_force :: proc(
    exe_dir: string, force: bool) -> bool {
    targets := resolve_unpack_targets(exe_dir)
    if !targets.ok {
        return false
    }

    continue_unpack, early_result :=
        should_continue_unpack(targets.archive_path, targets.unpack_dir,
            targets.package_identity, force)
    if !continue_unpack {
        return early_result
    }

    return replace_packaged_asset_tree(
        targets.archive_path, targets.unpack_dir, targets.package_identity,
        targets.archive_sha256)
}
