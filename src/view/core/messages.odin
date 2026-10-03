package view_core

import "../../core"
import contentdata "../../core/content"
import viewmodel "../model"
import "core:log"

// Borrow the current complete content generation at a display-owned call boundary.
shell_content_generation :: proc(
    state: ^core.Euclid_General_State) -> ^contentdata.Content_Generation {
    if state == nil || state.content_service == nil {
        return nil
    }
    service := state.content_service
    generation := service.active_generation
    if !service.running || generation == nil || !generation.sealed ||
       !generation.data.complete || generation.generation != service.index_generation {
        return nil
    }
    return generation
}

// Refresh static labels transactionally into display-owned storage, never SQL/arena views.
shell_messages_refresh :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    generation: ^contentdata.Content_Generation) -> contentdata.Content_Message_Status {
    if generation == nil { return .Invalid_State }
    if runtime.shell_message_generation == generation.generation { return .Ok }
    bytes: [80][128]u8
    lengths: [80]u16
    required := contentdata.CONTENT_REQUIRED_MESSAGES
    for identity, ordinal in required {
        id := contentdata.Content_Message_Id(identity.native_id)
        view, status := contentdata.content_message_lookup(generation, id)
        if status != .Ok { return status }
        if view.message.argument_count != 0 { continue }
        text, formatted := contentdata.content_message_format(
            generation, id, nil, bytes[ordinal][:])
        if formatted != .Ok { return formatted }
        lengths[ordinal] = u16(len(text))
    }
    runtime.shell_message_bytes = bytes
    runtime.shell_message_lengths = lengths
    runtime.shell_message_generation = generation.generation
    return .Ok
}

// Return a display-owned static label; failures are explicit diagnostics, not prose fallbacks.
shell_message :: proc(
    state: ^core.Euclid_General_State, id: contentdata.Content_Message_Id) -> string {
    generation := shell_content_generation(state)
    if state == nil {
        log.errorf("shell_message_failed id=%d status=Invalid_State", u16(id))
        return ""
    }
    status := shell_messages_refresh(&state.ui_runtime, generation)
    _, ordinal := contentdata.content_message_identity(id)
    if status == .Ok && ordinal < 0 { status = .Missing_Key }
    if status == .Ok && state.ui_runtime.shell_message_lengths[ordinal] == 0 {
        status = .Signature_Mismatch
    }
    if status != .Ok {
        log.errorf("shell_message_failed id=%d status=%v", u16(id), status)
        return ""
    }
    runtime := &state.ui_runtime
    length := runtime.shell_message_lengths[ordinal]
    return string(runtime.shell_message_bytes[ordinal][:length])
}

// Format ephemeral text into the caller's bounded owner and report every failure.
shell_format :: proc(
    state: ^core.Euclid_General_State, id: contentdata.Content_Message_Id,
    arguments: []contentdata.Content_Format_Argument, storage: []u8) -> string {
    text, status := contentdata.content_message_format(
        shell_content_generation(state), id, arguments, storage)
    if status != .Ok {
        log.errorf("shell_message_failed id=%d status=%v", u16(id), status)
    }
    return text
}
