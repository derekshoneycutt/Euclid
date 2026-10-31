package viewcapture

import files "../../files"
import capturemodel "model"
import "core:testing"
import "core:os"
import "core:fmt"
import "core:sync"
import "core:path/filepath"
import "core:log"

// Verify pending admission is bounded and rejects both active and requested GIF work.
@(test)
png_capture_admission_preserves_playback_and_path :: proc(t: ^testing.T) {
    previous_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = previous_logger
    status: capturemodel.Png_Capture_Status
    copy(status.last_path[:], "previous.png")
    status.path_len = len("previous.png")
    status.path_revision = 7
    phases := [?]capturemodel.Gif_Capture_Phase{.Armed, .Recording, .Finalizing}
    for phase in phases {
        testing.expect(t, !capturemodel.png_capture_request(&status, {
            phase = phase,
        }))
    }
    testing.expect(t, !capturemodel.png_capture_request(&status, {
        requested = true,
    }))
    testing.expect(t, capturemodel.png_capture_request(&status, {}))
    testing.expect(t, !capturemodel.png_capture_request(&status, {}))
    testing.expect_value(t, capturemodel.png_capture_path(&status), "previous.png")
    testing.expect_value(t, status.path_revision, u64(7))
    png_capture_save(&status, {
        requested = true,
    }, 2, 2, {})
    testing.expect_value(t, status.phase, capturemodel.Png_Capture_Phase.Error)
    testing.expect_value(t, capturemodel.png_capture_path(&status), "previous.png")
    testing.expect(t, capturemodel.png_capture_request(&status, {
        phase = .Saved,
    }))
}

// Prepare an isolated directory for testing publication with injected framebuffer calls.
png_test_directory :: proc(t: ^testing.T) -> string {
    root, error := os.temp_directory(context.temp_allocator)
    testing.expect(t, error == nil)
    directory, join_error := filepath.join([]string{root,
        fmt.tprintf("euclid-png-policy-%d", sync.current_thread_id())},
        context.allocator)
    testing.expect(t, join_error == nil)
    testing.expect(t, os.make_directory_all(directory) == nil)
    return directory
}

// Verify successful publication, failure retention, source cleanup and revision isolation.
@(test)
png_capture_publication_and_failure_retire_pixels :: proc(t: ^testing.T) {
    directory := png_test_directory(t)
    defer delete(directory, context.allocator)
    defer os.remove_all(directory)
    pixels: [16]u8
    source := framebuffer_test_source(pixels[:], 2, 2)
    source.export_succeeds = true
    operations := framebuffer_test_operations(&source)
    status: capturemodel.Png_Capture_Status = {
        phase = .Pending,
    }
    transaction, reserved := files.reserve_image_output_transaction_in_directory(
        directory, "success.png", .Png, context.allocator)
    testing.expect(t, reserved)
    defer files.destroy_image_output_transaction(&transaction, context.allocator)
    testing.expect(t, png_capture_export_transaction(
        &status, &transaction, 2, 2, operations))
    testing.expect_value(t, status.phase, capturemodel.Png_Capture_Phase.Saved)
    testing.expect_value(t, status.path_revision, u64(1))
    testing.expect_value(t,
        capturemodel.png_capture_path(&status), transaction.final_path)
    testing.expect_value(t, source.reset_count, 1)
    testing.expect(t, !source.capture_active)
    png_test_failed_transaction(t, &status, &source, directory)
}

// Exercise export and crop failure while retaining the last successful path.
png_test_failed_transaction :: proc(
    t: ^testing.T, status: ^capturemodel.Png_Capture_Status,
    source: ^Framebuffer_Capture_Test_State, directory: string) {
    saved := status^
    transaction, reserved := files.reserve_image_output_transaction_in_directory(
        directory, "failure.png", .Png, context.allocator)
    testing.expect(t, reserved)
    defer files.destroy_image_output_transaction(&transaction, context.allocator)
    source.export_succeeds = false
    status.phase = .Error
    testing.expect(t, !png_capture_export_transaction(status, &transaction,
        2, 2, framebuffer_test_operations(source)))
    testing.expect_value(t, status.path_revision, saved.path_revision)
    testing.expect_value(t, status.last_path, saved.last_path)
    testing.expect(t, !os.exists(transaction.final_path))
    testing.expect(t, !source.capture_active)
    source.fail_allocation_at = source.allocation_count + 2
    testing.expect(t, !png_capture_export_transaction(status, &transaction,
        1, 1, framebuffer_test_operations(source)))
    testing.expect(t, !source.capture_active)
    testing.expect_value(t, status.last_path, saved.last_path)
}
