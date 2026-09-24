package files

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"


//   Create a clean per-test sandbox directory under the OS temp directory.
prepare_sandbox_dir :: proc(dir_name: string) -> (string, bool) {
    temp_dir, temp_err := os.temp_directory(context.temp_allocator)
    if temp_err != nil || len(temp_dir) == 0 {
        return "", false
    }

    path, path_err := filepath.join([]string{temp_dir, dir_name}, context.allocator)
    if path_err != nil || len(path) == 0 {
        return "", false
    }

    _ = os.remove_all(path)
    if os.make_directory_all(path) != nil {
        return "", false
    }

    return path, true
}

//   Verify GIF transactions hide partial output until atomic publication.
@(test)
gif_output_transaction_publishes_only_complete_file :: proc(t: ^testing.T) {
    sandbox, ready := prepare_sandbox_dir("euclid-gif-transaction-test")
    testing.expect(t, ready)
    defer delete(sandbox)
    defer os.remove_all(sandbox)
    transaction, reserved := reserve_gif_output_transaction_in_directory(
        sandbox, "capture.gif", context.allocator)
    testing.expect(t, reserved)
    defer destroy_gif_output_transaction(&transaction, context.allocator)
    testing.expect(t, os.exists(transaction.temporary_path))
    testing.expect(t, !os.exists(transaction.final_path))

    payload := []u8{'G', 'I', 'F', '8', '9', 'a'}
    testing.expect(t, os.write_entire_file(transaction.temporary_path, payload) == nil)
    testing.expect(t, publish_gif_output_transaction(&transaction))
    testing.expect(t, !os.exists(transaction.temporary_path))
    testing.expect(t, os.exists(transaction.final_path))
}

//   Verify abort cleanup removes a reserved partial GIF without publishing it.
@(test)
gif_output_transaction_abort_removes_partial_file :: proc(t: ^testing.T) {
    sandbox, ready := prepare_sandbox_dir("euclid-gif-transaction-abort-test")
    testing.expect(t, ready)
    defer delete(sandbox)
    defer os.remove_all(sandbox)
    transaction, reserved := reserve_gif_output_transaction_in_directory(
        sandbox, "capture.gif", context.allocator)
    testing.expect(t, reserved)
    temporary_path := fmt.aprintf("%s", transaction.temporary_path, context.allocator)
    final_path := fmt.aprintf("%s", transaction.final_path, context.allocator)
    defer delete(temporary_path)
    defer delete(final_path)

    destroy_gif_output_transaction(&transaction, context.allocator)
    testing.expect(t, !os.exists(temporary_path))
    testing.expect(t, !os.exists(final_path))
    testing.expect_value(t, transaction, Gif_Output_Transaction{})
}

//   Write one required file entry (with parent dirs) under a test root.
write_required_entry :: proc(root_dir, rel_path: string) -> bool {
    last_separator := -1
    for i in 0..<len(rel_path) {
        if rel_path[i] == '/' {
            last_separator = i
        }
    }

    if last_separator > 0 {
        parent_rel := rel_path[:last_separator]
        parent_dir, parent_join_err := filepath.join(
            []string{root_dir, parent_rel}, context.allocator)
        if parent_join_err != nil {
            return false
        }
        defer delete(parent_dir)
        if !os.is_directory(parent_dir) && os.make_directory_all(parent_dir) != nil {
            return false
        }
    }

    full_path, join_err := filepath.join([]string{root_dir, rel_path}, context.allocator)
    if join_err != nil {
        return false
    }
    defer delete(full_path)

    return os.write_entire_file(full_path, []u8{'x'}) == nil
}

//   Write the required image and its matching package manifest.
write_test_sysimage_manifest :: proc(unpack_dir: string) -> bool {
    fingerprint := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    image_path := fmt.tprintf(
        "sysimage/%s/%s", fingerprint, PACKAGED_SYSIMAGE_FILENAME)
    if !write_required_entry(unpack_dir, image_path) {
        return false
    }
    manifest_path, manifest_err := filepath.join(
        []string{unpack_dir, "manifest.txt"}, context.allocator)
    if manifest_err != nil {
        return false
    }
    defer delete(manifest_path)
    manifest := fmt.tprintf(
        "schema_version=2\nsysimage_path=%s\n" +
        "sysimage_input_fingerprint=%s\nsysimage_artifact_sha256=%s\n" +
        "sysimage_platform=%s\n",
        image_path, fingerprint, fingerprint, PACKAGED_SYSIMAGE_PLATFORM)
    if os.write_entire_file(manifest_path, manifest) != nil {
        return false
    }
    return true
}

//   Build the full required unpack tree (scripts, icon, fonts, manifest).
build_ready_unpack_tree :: proc(unpack_dir: string) -> bool {
    required := []string{
        "julia/script.jl",
        "content/animation_catalog_generation.jl",
        "content/animation_catalog_data.jl",
        "compass_icon.png",
        "JuliaMono-Regular.ttf",
        "NewCMSansMath-Regular.otf",
    }

    for rel_path in required {
        if !write_required_entry(unpack_dir, rel_path) {
            return false
        }
    }
    if !write_test_sysimage_manifest(unpack_dir) {
        return false
    }

    when ODIN_OS == .Linux {
        if !write_required_entry(unpack_dir, "terminfo/e/euclid") {
            return false
        }
    } else when ODIN_OS == .Darwin {
        if !write_required_entry(unpack_dir, "terminfo/65/euclid") {
            return false
        }
    }

    return true
}

//   Verify is_assets_unpack_ready reports false until every required entry exists.
@(test)
is_assets_unpack_ready_requires_all_entries :: proc(t: ^testing.T) {
    unpack_dir, ok := prepare_sandbox_dir("euclid_unpack_ready")
    defer delete(unpack_dir)
    defer _ = os.remove_all(unpack_dir)
    testing.expect(t, ok)

    testing.expect(t, !is_assets_unpack_ready(unpack_dir))

    testing.expect(t, build_ready_unpack_tree(unpack_dir))
    testing.expect(t, is_assets_unpack_ready(unpack_dir))

    math_path, join_error := filepath.join(
        []string{unpack_dir, "NewCMSansMath-Regular.otf"}, context.allocator)
    defer delete(math_path)
    testing.expect(t, join_error == nil)
    testing.expect(t, os.remove(math_path) == nil)
    testing.expect(t, !is_assets_unpack_ready(unpack_dir))
}

//   Verify should_continue_unpack across the missing/partial/complete/forced matrix.
@(test)
should_continue_unpack_matrix :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_unpack_should_continue")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)

    archive_path, archive_join_err := filepath.join(
        []string{sandbox, "assets.pkg"}, context.allocator)
    unpack_dir, unpack_join_err := filepath.join(
        []string{sandbox, "unpack"}, context.allocator)
    defer delete(archive_path)
    defer delete(unpack_dir)
    testing.expect(t, archive_join_err == nil)
    testing.expect(t, unpack_join_err == nil)

    continue_unpack, result := should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, !result)

    testing.expect(t, os.make_directory_all(unpack_dir) == nil)
    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, result)

    testing.expect(t, os.write_entire_file(archive_path, []u8{'a'}) == nil)

    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, continue_unpack)
    testing.expect(t, !result)

    testing.expect(t, build_ready_unpack_tree(unpack_dir))
    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, result)

    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, true)
    testing.expect(t, continue_unpack)
    testing.expect(t, !result)
}

//   Verify prepare_unpack_directory clears stale contents and recreates the directory.
@(test)
prepare_unpack_directory_clears_and_recreates :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_prepare_unpack")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)

    nested_file := "inner/data.bin"
    testing.expect(t, write_required_entry(sandbox, nested_file))

    nested_file_path, nested_err := filepath.join(
        []string{sandbox, nested_file}, context.allocator)
    defer delete(nested_file_path)
    testing.expect(t, nested_err == nil)
    testing.expect(t, os.exists(nested_file_path))

    testing.expect(t, prepare_unpack_directory(sandbox))
    testing.expect(t, os.is_directory(sandbox))
    testing.expect(t, !os.exists(nested_file_path))
}

//   Verify candidate publication replaces valid trees and preserves them on failure.
@(test)
publish_candidate_unpack_directory_is_transactional :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_publish_unpack")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)
    active := fmt.tprintf("%s/active", sandbox)
    candidate := fmt.tprintf("%s/candidate", sandbox)
    backup := fmt.tprintf("%s/backup", sandbox)
    testing.expect(t, os.make_directory_all(active) == nil)
    testing.expect(t, write_required_entry(active, "old.txt"))

    testing.expect(t, !publish_candidate_unpack_directory(
        fmt.tprintf("%s/missing", sandbox), active, backup))
    testing.expect(t, os.exists(fmt.tprintf("%s/old.txt", active)))

    testing.expect(t, os.make_directory_all(candidate) == nil)
    testing.expect(t, write_required_entry(candidate, "new.txt"))
    testing.expect(t, publish_candidate_unpack_directory(candidate, active, backup))
    testing.expect(t, !os.exists(fmt.tprintf("%s/old.txt", active)))
    testing.expect(t, os.exists(fmt.tprintf("%s/new.txt", active)))
}

//   Verify a rejected candidate archive leaves the active asset tree untouched.
@(test)
replace_packaged_asset_tree_preserves_active_on_rejection :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_incompatible_unpack")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)
    active := fmt.tprintf("%s/assets", sandbox)
    archive := fmt.tprintf("%s/assets.pkg", sandbox)
    testing.expect(t, os.make_directory_all(active) == nil)
    testing.expect(t, write_required_entry(active, "active.txt"))
    testing.expect(t, os.write_entire_file(archive, "invalid archive") == nil)
    fingerprint := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    testing.expect(t, !replace_packaged_asset_tree(archive, active, fingerprint))
    testing.expect(t, os.exists(fmt.tprintf("%s/active.txt", active)))
}

//   Verify digest-addressed image materialization reuses and repairs its cache.
@(test)
materialize_packaged_sysimage_repairs_corrupt_cache :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_sysimage_materialize")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)
    unpack_dir := fmt.tprintf("%s/assets", sandbox)
    image_relative := fmt.tprintf("sysimage/input/%s", PACKAGED_SYSIMAGE_FILENAME)
    testing.expect(t, os.make_directory_all(unpack_dir) == nil)
    testing.expect(t, write_required_entry(unpack_dir, image_relative))
    digest := "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881"
    metadata := Packaged_Sysimage_Metadata{image_relative, "input", digest}

    cached, cached_ok := materialize_packaged_sysimage(
        unpack_dir, &metadata, context.allocator)
    defer delete(cached)
    testing.expect(t, cached_ok)
    testing.expect(t, file_matches_sha256(cached, digest))
    testing.expect(t, os.write_entire_file(cached, "corrupt") == nil)
    repaired, repaired_ok := materialize_packaged_sysimage(
        unpack_dir, &metadata, context.allocator)
    defer delete(repaired)
    testing.expect(t, repaired_ok)
    testing.expect_value(t, repaired, cached)
    testing.expect(t, file_matches_sha256(repaired, digest))
}

//   Verify resolve_writable_gif_output_dir rejects empty input and creates the dir.
@(test)
resolve_writable_gif_output_dir_behaviour :: proc(t: ^testing.T) {
    output_dir, ok := resolve_writable_gif_output_dir("")
    testing.expect(t, !ok)
    testing.expect_value(t, output_dir, "")

    base_dir, base_ok := prepare_sandbox_dir("euclid_gif_output")
    defer delete(base_dir)
    defer _ = os.remove_all(base_dir)
    testing.expect(t, base_ok)

    expected_output, expected_err := filepath.join(
        []string{base_dir, GIF_OUTPUT_DIR_NAME}, context.allocator)
    defer delete(expected_output)
    testing.expect(t, expected_err == nil)

    output_dir, ok = resolve_writable_gif_output_dir(base_dir)
    testing.expect(t, ok)
    testing.expect_value(t, output_dir, expected_output)
    testing.expect(t, os.is_directory(output_dir))
}
