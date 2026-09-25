package bridge

import dynviewmodel "../dynview/model"

//   Mark the current Dynview stream and compile cache invalid.
dynview_fail :: #force_inline proc(
    runtime: ^dynviewmodel.Dynview_System, code: i32) -> i32 {
    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == 0 {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
    return code
}

//   Append one command to bounded Dynview staging.
dynview_push_command :: #force_inline proc(
    runtime: ^dynviewmodel.Dynview_System,
    command: dynviewmodel.Dynview_Command) -> i32 {

    buffer := &runtime^.command_buffer
    if buffer^.command_count >= len(buffer^.commands) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    buffer^.commands[buffer^.command_count] = command
    buffer^.command_count += 1
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Append text to bounded Dynview staging and return its span.
dynview_append_text_payload :: #force_inline proc(
    runtime: ^dynviewmodel.Dynview_System,
    text: string,
    offset_out, count_out: ^int) -> i32 {

    buffer := &runtime^.command_buffer
    text_len := len(text)
    if buffer^.text_bytes_len + text_len > len(buffer^.text_bytes) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    start := buffer^.text_bytes_len
    copy(buffer^.text_bytes[start:], transmute([]u8)text)
    buffer^.text_bytes_len += text_len
    offset_out^ = start
    count_out^ = text_len
    return BRIDGE_STATUS_OK
}
