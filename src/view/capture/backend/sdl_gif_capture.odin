package capturebackend

import native "../../native"
import files "../../../files"
import log "core:log"
import strings "core:strings"
import capturemodel "../model"
import storage "../../../core/storage"

// Sdl_Gif_Capture_Context owns one arena spanning encoding and published-path use.
Sdl_Gif_Capture_Context :: struct {
    encoder: native.Sdl_Gif_Encoder,
    transaction: files.Gif_Output_Transaction,
    storage: storage.Arena_Owner,
}

// sdl_gif_capture_abort closes native state and removes unpublished output.
sdl_gif_capture_abort :: proc(user_data: rawptr) {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {
        return
    }
    allocator := storage.arena_owner_allocator(&owner.storage)
    native.sdl_gif_encoder_abort(&owner.encoder, allocator)
    files.destroy_gif_output_transaction(&owner.transaction, allocator)
    storage.arena_owner_reset(&owner.storage)
}

// sdl_gif_capture_begin reserves output and opens one native GIF stream.
sdl_gif_capture_begin :: proc(
    user_data: rawptr, width, height: int) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil || !owner.storage.initialized {
        return false
    }
    sdl_gif_capture_abort(user_data)
    allocator := storage.arena_owner_allocator(&owner.storage)
    transaction, reserved := files.reserve_gif_output_transaction(allocator)
    if !reserved {
        log.error("sdl_gif_capture_reserve_failed")
        return false
    }
    return sdl_gif_capture_begin_transaction(owner, transaction, width, height)
}

// Open a previously reserved transaction using this capture's storage domain.
sdl_gif_capture_begin_transaction :: proc(
    owner: ^Sdl_Gif_Capture_Context, transaction: files.Gif_Output_Transaction,
    width, height: int) -> bool {
    if owner == nil {
        return false
    }
    if !owner.storage.initialized {
        log.error("sdl_gif_capture_storage_uninitialized")
        return false
    }
    owner.transaction = transaction
    if len(transaction.temporary_path) == 0 || len(transaction.final_path) == 0 {
        log.error("sdl_gif_capture_transaction_invalid")
        sdl_gif_capture_abort(rawptr(owner))
        return false
    }
    temporary_path := strings.clone_to_cstring(
        owner.transaction.temporary_path, context.temp_allocator)
    allocator := storage.arena_owner_allocator(&owner.storage)
    if !native.sdl_gif_encoder_begin(
        &owner.encoder, temporary_path, width, height, allocator) {
        log.errorf(
            "sdl_gif_capture_open_failed width=%d height=%d", width, height)
        sdl_gif_capture_abort(rawptr(owner))
        return false
    }
    return true
}

// sdl_gif_capture_stage_frame copies one borrowed frame into native staging.
sdl_gif_capture_stage_frame :: proc(
    user_data: rawptr, frame: capturemodel.Gif_Capture_Frame) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {
        return false
    }
    return native.sdl_gif_encoder_stage_frame(&owner.encoder, {
        pixels = frame.pixels,
        width = frame.width,
        height = frame.height,
        pitch_bytes = frame.pitch_bytes,
    })
}

// sdl_gif_capture_commit_frame submits the staged frame with its resolved duration.
sdl_gif_capture_commit_frame :: proc(user_data: rawptr, duration_ms: u64) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {
        return false
    }
    return native.sdl_gif_encoder_commit_frame(&owner.encoder, duration_ms)
}

// sdl_gif_capture_close closes and atomically publishes one completed stream.
sdl_gif_capture_close :: proc(user_data: rawptr) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil || !owner.storage.initialized {
        return false
    }
    allocator := storage.arena_owner_allocator(&owner.storage)
    if !native.sdl_gif_encoder_close(&owner.encoder, allocator) {
        sdl_gif_capture_abort(user_data)
        return false
    }
    if !files.publish_gif_output_transaction(&owner.transaction) {
        sdl_gif_capture_abort(user_data)
        return false
    }
    return true
}

// Borrow the published path; capture policy must copy it before the next reset/unbind.
sdl_gif_capture_published_path :: proc(user_data: rawptr) -> string {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {
        return ""
    }
    return owner.transaction.final_path
}

// sdl_gif_capture_operations exposes the display-owned encoder to capture policy.
sdl_gif_capture_operations :: proc(
    owner: ^Sdl_Gif_Capture_Context) -> capturemodel.Gif_Capture_Operations {
    if owner == nil {
        return {}
    }
    return {
        user_data = rawptr(owner),
        begin = sdl_gif_capture_begin,
        stage_frame = sdl_gif_capture_stage_frame,
        commit_frame = sdl_gif_capture_commit_frame,
        close = sdl_gif_capture_close,
        abort = sdl_gif_capture_abort,
        published_path = sdl_gif_capture_published_path,
    }
}

// bind_sdl_gif_capture admits one display-lifetime GIF encoder owner.
bind_sdl_gif_capture :: proc(
    owner: ^Sdl_Gif_Capture_Context,
    session: ^capturemodel.Gif_Capture_Session) -> bool {
    if owner == nil || session == nil {
        return false
    }
    if !storage.arena_owner_init(&owner.storage) {
        log.error("sdl_gif_capture_storage_init_failed")
        return false
    }
    if !capturemodel.gif_capture_bind_operations(
        session, sdl_gif_capture_operations(owner)) {
        log.error("sdl_gif_capture_bind_failed")
        storage.arena_owner_destroy(&owner.storage)
        return false
    }
    return true
}

// unbind_sdl_gif_capture releases any retained native or path state.
unbind_sdl_gif_capture :: proc(owner: ^Sdl_Gif_Capture_Context) {
    if owner == nil {
        return
    }
    sdl_gif_capture_abort(rawptr(owner))
    storage.arena_owner_destroy(&owner.storage)
}