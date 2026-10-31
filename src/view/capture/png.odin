package viewcapture

import log "core:log"
import strings "core:strings"
import files "../../files"
import capturemodel "model"

// png_capture_save exports and transactionally publishes one borrowed world-only source.
// Pixel storage belongs to operations; paths use operation scratch and never escape it.
png_capture_save :: proc(
    status: ^capturemodel.Png_Capture_Status, gif: capturemodel.Gif_Capture_View,
    width, height: int, operations: capturemodel.Framebuffer_Capture_Operations) {
    if status.phase != .Pending {
        return
    }
    status.phase = .Error
    if capturemodel.gif_capture_locks_playback_rate(gif.phase, gif.requested) {
        log.error("png_capture_gif_active")
        return
    }
    source_operations := operations
    source_operations.load = operations.load_world
    transaction, reserved := files.reserve_image_output_transaction(
        .Png, context.temp_allocator)
    if !reserved {
        log.error("png_capture_reserve_failed")
        return
    }
    defer files.destroy_image_output_transaction(
        &transaction, context.temp_allocator)
    if !png_capture_export_transaction(
        status, &transaction, width, height, source_operations) {
        log.error("png_capture_export_failed")
    }
}

// Export to a reserved temporary file and retain its complete path only after publication.
png_capture_export_transaction :: proc(
    status: ^capturemodel.Png_Capture_Status,
    transaction: ^files.Image_Output_Transaction, width, height: int,
    operations: capturemodel.Framebuffer_Capture_Operations) -> bool {
    if len(transaction.final_path) == 0 ||
        len(transaction.final_path) >= len(status.last_path) {
        return false
    }
    image, acquired := framebuffer_acquire_with_operations(operations)
    if !acquired {
        return false
    }
    defer framebuffer_release_with_operations(&image, operations)
    if !framebuffer_crop_with_operations(&image, width, height, operations) ||
        !framebuffer_export_with_operations(&image, strings.clone_to_cstring(
            transaction.temporary_path, context.temp_allocator), operations) ||
        !files.publish_image_output_transaction(transaction) {
        return false
    }
    copy(status.last_path[:], transmute([]u8)transaction.final_path)
    status.path_len = len(transaction.final_path)
    status.path_revision += 1
    status.width, status.height = width, height
    status.phase = .Saved
    log.infof("png_capture_saved path=%s width=%d height=%d",
        transaction.final_path, width, height)
    return true
}
