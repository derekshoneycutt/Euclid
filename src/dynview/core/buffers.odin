package dynview_core

import app_core "../../core"

DYNVIEW_STATUS_OK :: 0
DYNVIEW_STATUS_INVALID_ARGUMENT :: 2
DYNVIEW_STATUS_OUT_OF_CAPACITY :: 5
DYNVIEW_STATUS_ILLEGAL_STATE :: 6

//   Mark one command stream invalid while preserving its first compile error.
mark_stream_error :: proc(runtime: ^app_core.Dynview_System, code: i32) {
    if runtime == nil {
        return
    }

    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == DYNVIEW_STATUS_OK {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
}

//   Return the active immutable command prefix or the worker staging prefix.
command_buffer_commands :: #force_inline proc(
    buffer: ^app_core.Dynview_Command_Buffer) -> []app_core.Dynview_Command {

    if buffer^.command_view != nil {
        return buffer^.command_view
    }
    return buffer^.commands[:buffer^.command_count]
}

//   Return the active immutable text prefix or the worker staging prefix.
command_buffer_text :: #force_inline proc(
    buffer: ^app_core.Dynview_Command_Buffer) -> []u8 {

    if buffer^.text_view != nil {
        return buffer^.text_view
    }
    return buffer^.text_bytes[:buffer^.text_bytes_len]
}

//   Extract a text span from the shared dynview byte buffer using explicit bounds.
text_span_from_buffer :: #force_inline proc(
    buffer: ^app_core.Dynview_Command_Buffer,
    text_offset, text_len: int) -> string {

    if text_offset < 0 || text_len < 0 {
        return ""
    }
    text_bytes := command_buffer_text(buffer)
    if text_offset + text_len > len(text_bytes) {
        return ""
    }
    return string(text_bytes[text_offset:text_offset + text_len])
}

//   Extract the validated text payload for one dynview command.
text_for_command :: #force_inline proc(
    buffer: ^app_core.Dynview_Command_Buffer,
    command: app_core.Dynview_Command) -> string {

    return text_span_from_buffer(buffer, command.text_offset, command.text_len)
}

//   Convert bounded-builder status to the stable Dynview compile status surface.
compiled_builder_status :: #force_inline proc(
    status: app_core.Bounded_Builder_Status) -> i32 {
    switch status {
    case .Ok:
        return DYNVIEW_STATUS_OK
    case .Limit_Exceeded, .Allocation_Failed:
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    case .Invalid_Argument, .Sealed:
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }
    return DYNVIEW_STATUS_ILLEGAL_STATE
}
