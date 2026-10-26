#+test
package capturebackend

import files "../../../files"
import capturemodel "../model"
import storage "../../../core/storage"

import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:testing"

Sdl_Gif_Capture_Test_Transaction :: struct {
    transaction: files.Gif_Output_Transaction,
    final_path: string,
    temporary_path: string,
    reserved: bool,
}

// Prepare one isolated output directory and bind its capture owner.
sdl_gif_capture_test_setup :: proc(
    t: ^testing.T, owner: ^Sdl_Gif_Capture_Context,
    session: ^capturemodel.Gif_Capture_Session) -> string {
    temp_directory, temp_error := os.temp_directory(context.temp_allocator)
    testing.expect(t, temp_error == nil)
    directory_name := fmt.aprintf(
        "euclid-sdl-gif-capture-lifecycle-%d", sync.current_thread_id(),
        allocator = context.temp_allocator)
    directory, directory_error := filepath.join(
        []string{temp_directory, directory_name}, context.allocator)
    testing.expect(t, directory_error == nil)
    _ = os.remove_all(directory)
    testing.expect(t, os.make_directory_all(directory) == nil)
    testing.expect(t, bind_sdl_gif_capture(owner, session))
    return directory
}

// Release one test owner and its temporary filesystem state.
sdl_gif_capture_test_teardown :: proc(
    owner: ^Sdl_Gif_Capture_Context, directory: string) {
    unbind_sdl_gif_capture(owner)
    _ = os.remove_all(directory)
    delete(directory, context.allocator)
}

// Reserve a transaction and preserve path copies for post-reset assertions.
sdl_gif_capture_test_reserve :: proc(
    owner: ^Sdl_Gif_Capture_Context, directory, filename: string) ->
        Sdl_Gif_Capture_Test_Transaction {
    allocator := storage.arena_owner_allocator(&owner.storage)
    transaction, reserved := files.reserve_gif_output_transaction_in_directory(
        directory, filename, allocator)
    if !reserved {
        return {}
    }
    return {
        transaction = transaction,
        final_path = strings.clone(transaction.final_path, context.allocator),
        temporary_path = strings.clone(
            transaction.temporary_path, context.allocator),
        reserved = true,
    }
}

// Encode two frames through the callback owner and atomically publish the result.
sdl_gif_capture_test_publish :: proc(
    owner: ^Sdl_Gif_Capture_Context,
    directory, filename: string) -> (string, bool) {
    output := sdl_gif_capture_test_reserve(owner, directory, filename)
    if !output.reserved {
        return "", false
    }
    if !sdl_gif_capture_begin_transaction(owner, output.transaction, 2, 1) {
        delete(output.final_path, context.allocator)
        return "", false
    }
    pixels: [8]u8 = {255, 0, 0, 255, 0, 255, 0, 255}
    durations := [?]u64{40, 80}
    for duration in durations {
        if !sdl_gif_capture_stage_frame(
            rawptr(owner), {
                pixels = pixels[:],
                width = 2,
                height = 1,
                pitch_bytes = 8,
            }) ||
            !sdl_gif_capture_commit_frame(rawptr(owner), duration) {

            sdl_gif_capture_abort(rawptr(owner))
            delete(output.final_path, context.allocator)
            return "", false
        }
    }
    if !sdl_gif_capture_close(rawptr(owner)) {
        delete(output.final_path, context.allocator)
        return "", false
    }
    return output.final_path, true
}

// Verify a rejected frame stage and cancellation both close and reclaim storage.
@(test)
sdl_gif_capture_stage_failure_and_cancellation_abort :: proc(t: ^testing.T) {
    owner: Sdl_Gif_Capture_Context
    session: capturemodel.Gif_Capture_Session
    directory := sdl_gif_capture_test_setup(t, &owner, &session)
    pixels: [8]u8 = {255, 0, 0, 255, 0, 255, 0, 255}
    failed_stage := sdl_gif_capture_test_reserve(
        &owner, directory, "failed-stage.gif")
    testing.expect(t, failed_stage.reserved)
    testing.expect(t,
        sdl_gif_capture_begin_transaction(&owner, failed_stage.transaction, 2, 1))
    testing.expect(t, !sdl_gif_capture_stage_frame(rawptr(&owner), {
        pixels = pixels[:],
        width = 1,
        height = 1,
        pitch_bytes = 4,
    }))
    sdl_gif_capture_abort(rawptr(&owner))
    testing.expect(t, !os.exists(failed_stage.temporary_path))
    testing.expect(t, !os.exists(failed_stage.final_path))
    delete(failed_stage.final_path, context.allocator)
    delete(failed_stage.temporary_path, context.allocator)

    cancelled := sdl_gif_capture_test_reserve(
        &owner, directory, "cancelled.gif")
    testing.expect(t, cancelled.reserved)
    testing.expect(t, sdl_gif_capture_begin_transaction(
        &owner, cancelled.transaction, 2, 1))
    testing.expect(t, sdl_gif_capture_stage_frame(rawptr(&owner), {
        pixels = pixels[:],
        width = 2,
        height = 1,
        pitch_bytes = 8,
    }))
    sdl_gif_capture_abort(rawptr(&owner))
    testing.expect(t, !os.exists(cancelled.temporary_path))
    testing.expect(t, !os.exists(cancelled.final_path))
    delete(cancelled.final_path, context.allocator)
    delete(cancelled.temporary_path, context.allocator)
    sdl_gif_capture_test_teardown(&owner, directory)
}

// Verify a failed close removes its unpublished transaction.
@(test)
sdl_gif_capture_failed_close_rolls_back_transaction :: proc(t: ^testing.T) {
    owner: Sdl_Gif_Capture_Context
    session: capturemodel.Gif_Capture_Session
    directory := sdl_gif_capture_test_setup(t, &owner, &session)
    output := sdl_gif_capture_test_reserve(
        &owner, directory, "failed-close.gif")
    testing.expect(t, output.reserved)
    testing.expect(t, sdl_gif_capture_begin_transaction(
        &owner, output.transaction, 2, 1))
    testing.expect(t, !sdl_gif_capture_close(rawptr(&owner)))
    testing.expect(t, !os.exists(output.temporary_path))
    testing.expect(t, !os.exists(output.final_path))
    delete(output.final_path, context.allocator)
    delete(output.temporary_path, context.allocator)
    sdl_gif_capture_test_teardown(&owner, directory)
}

// Verify publication paths survive reuse and owner shutdown after being copied.
@(test)
sdl_gif_capture_reuses_storage_and_preserves_published_paths :: proc(
    t: ^testing.T) {
    owner: Sdl_Gif_Capture_Context
    session: capturemodel.Gif_Capture_Session
    directory := sdl_gif_capture_test_setup(t, &owner, &session)
    first_path, first_ok := sdl_gif_capture_test_publish(
        &owner, directory, "first.gif")
    testing.expect(t, first_ok)
    testing.expect(t, os.exists(first_path))
    first_status_path := strings.clone(first_path, context.allocator)
    sdl_gif_capture_abort(rawptr(&owner))
    testing.expect(t, os.exists(first_path))
    diagnostics := storage.arena_owner_diagnostics(&owner.storage)
    testing.expect_value(t, diagnostics.current_used, uint(0))

    second_path, second_ok := sdl_gif_capture_test_publish(
        &owner, directory, "second.gif")
    testing.expect(t, second_ok)
    testing.expect(t, os.exists(first_status_path))
    testing.expect(t, os.exists(second_path))
    testing.expect(t, sdl_gif_capture_published_path(rawptr(&owner)) == second_path)
    unbind_sdl_gif_capture(&owner)
    testing.expect(t, !owner.storage.initialized)
    testing.expect(t, os.exists(first_status_path))
    testing.expect(t, os.exists(second_path))
    _ = os.remove(first_path)
    _ = os.remove(second_path)
    _ = os.remove_all(directory)
    delete(directory, context.allocator)
    delete(first_path, context.allocator)
    delete(first_status_path, context.allocator)
    delete(second_path, context.allocator)
}
