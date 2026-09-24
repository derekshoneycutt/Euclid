package view

import view_core "core"
import native "native"

import "../files"

import "core:log"
import "core:mem"
import "core:strings"

// Sdl_Gif_Capture_Context owns native encoding and transactional output paths.
Sdl_Gif_Capture_Context :: struct {
    encoder: native.Sdl_Gif_Encoder,
    transaction: files.Gif_Output_Transaction,
    allocator: mem.Allocator,
}

// sdl_gif_capture_abort closes native state and removes unpublished output.
sdl_gif_capture_abort :: proc(user_data: rawptr) {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {return}
    native.sdl_gif_encoder_abort(&owner.encoder)
    files.destroy_gif_output_transaction(&owner.transaction, owner.allocator)
}

// sdl_gif_capture_begin reserves output and opens one native GIF stream.
sdl_gif_capture_begin :: proc(
    user_data: rawptr, width, height: int) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil || owner.allocator.procedure == nil {return false}
    sdl_gif_capture_abort(user_data)
    transaction, reserved := files.reserve_gif_output_transaction(owner.allocator)
    if !reserved {
        log.error("sdl_gif_capture_reserve_failed")
        return false
    }
    owner.transaction = transaction
    temporary_path := strings.clone_to_cstring(
        owner.transaction.temporary_path, context.temp_allocator)
    if !native.sdl_gif_encoder_begin(
        &owner.encoder, temporary_path, width, height) {
        log.errorf(
            "sdl_gif_capture_open_failed width=%d height=%d", width, height)
        sdl_gif_capture_abort(user_data)
        return false
    }
    return true
}

// sdl_gif_capture_add_frame submits one borrowed frame to the active stream.
sdl_gif_capture_add_frame :: proc(
    user_data: rawptr, frame: view_core.Gif_Capture_Frame) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {return false}
    return native.sdl_gif_encoder_add_frame(&owner.encoder, {
        pixels = frame.pixels,
        width = frame.width,
        height = frame.height,
        pitch_bytes = frame.pitch_bytes,
        duration_ms = frame.duration_ms,
    })
}

// sdl_gif_capture_close closes and atomically publishes one completed stream.
sdl_gif_capture_close :: proc(user_data: rawptr) -> bool {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil || !native.sdl_gif_encoder_close(&owner.encoder) {
        sdl_gif_capture_abort(user_data)
        return false
    }
    if !files.publish_gif_output_transaction(&owner.transaction) {
        sdl_gif_capture_abort(user_data)
        return false
    }
    return true
}

// sdl_gif_capture_published_path returns the current published path while owned.
sdl_gif_capture_published_path :: proc(user_data: rawptr) -> string {
    owner := cast(^Sdl_Gif_Capture_Context)user_data
    if owner == nil {return ""}
    return owner.transaction.final_path
}

// sdl_gif_capture_operations exposes the display-owned encoder to capture policy.
sdl_gif_capture_operations :: proc(
    owner: ^Sdl_Gif_Capture_Context) -> view_core.Gif_Capture_Operations {
    if owner == nil {return {}}
    return {
        user_data = rawptr(owner),
        begin = sdl_gif_capture_begin,
        add_frame = sdl_gif_capture_add_frame,
        close = sdl_gif_capture_close,
        abort = sdl_gif_capture_abort,
        published_path = sdl_gif_capture_published_path,
    }
}

// bind_sdl_gif_capture admits one display-lifetime GIF encoder owner.
bind_sdl_gif_capture :: proc(
    owner: ^Sdl_Gif_Capture_Context,
    session: ^view_core.Gif_Capture_Session) -> bool {
    if owner == nil || session == nil {return false}
    owner.allocator = context.allocator
    return view_core.gif_capture_bind_operations(
        session, sdl_gif_capture_operations(owner))
}

// unbind_sdl_gif_capture releases any retained native or path state.
unbind_sdl_gif_capture :: proc(owner: ^Sdl_Gif_Capture_Context) {
    if owner == nil {return}
    sdl_gif_capture_abort(rawptr(owner))
    owner.allocator = {}
}