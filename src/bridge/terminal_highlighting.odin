package bridge

import bridgemodel "model"
import protocol "../core/protocol"
import julialib "../../libs/julia/bindings"

// Copy bounded source into Julia-inbox storage; never retain caller storage.
send_terminal_highlight_request :: proc(
    service: ^Julia_Runtime_Service,
    request: protocol.Highlight_Requested) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
       len(request.source) > protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES {
        return .Allocation_Failed
    }
    if service.lifecycle == .Shutdown_Requested || service.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return consumer_mailbox_publish(
        &service.julia_inbox, bridgemodel.Julia_Host_Ingress(request))
}

// Publish only complete results, reporting storage/queue pressure without partial envelopes.
send_terminal_highlight_result :: proc(
    service: ^Julia_Runtime_Service,
    result: protocol.Highlight_Result) -> bridgemodel.Communication_Send_Outcome {
    if service == nil || !protocol.highlight_result_valid(result) {
        return .Allocation_Failed
    }
    if service.lifecycle == .Shutdown_Requested || service.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(result))
}

// Box the immutable identity and source under explicit roots on the Julia owner thread.
julia_terminal_ingest_highlight :: proc(
    host: ^Julia_Runtime_Host, request: protocol.Highlight_Requested) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if host == nil || host.runtime == nil || gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 3 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host.runtime
    identity := request.identity
    frame.roots[1] = julialib.jl_new_bits(
        host.terminal_highlight_identity_type, &identity)
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(request.source)), len(request.source))
    if frame.roots[1] == nil || frame.roots[2] == nil {
        return false
    }
    result := julialib.jl_call(host.terminal_ingest_highlight, &frame.roots[0], 3)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_ingest_highlight")
        return false
    }
    return true
}

// Copy the pointer-free identity while its enclosing command remains rooted.
decode_highlight_identity :: proc(command: ^julialib.jl_value_t) ->
    protocol.Highlight_Identity {
    value := julialib.jl_get_nth_field(command, 1)
    identity := cast(^protocol.Highlight_Identity)value
    return identity^
}

// Decode a rooted typed run vector; no Julia pointer escapes the synchronous send.
decode_highlight_result :: proc(command: ^julialib.jl_value_t) ->
    protocol.Highlight_Result {
    source_value := julialib.jl_get_nth_field(command, 2)
    // Julia strings may contain NUL; their byte size is not a C-string length.
    source := julialib.jl_string_ptr(source_value)
    source_length := int(julialib.jl_unbox_int32(julialib.jl_get_nth_field(command, 3)))
    array := cast(^julialib.jl_array_t)julialib.jl_get_nth_field(command, 4)
    count := int(julialib.jl_array_len(array))
    data := cast([^]protocol.Highlight_Run)julialib.jl_array_data_raw(array)
    return {
        identity = decode_highlight_identity(command),
        source = string((cast([^]u8)source)[:source_length]),
        runs = data[:count],
    }
}

// Translate transport exhaustion to one explicit failure instead of retrying allocation forever.
julia_terminal_send_highlight :: proc(
    service: ^Julia_Runtime_Service,
    command: ^julialib.jl_value_t, kind: i32) -> bool {
    identity := decode_highlight_identity(command)
    if kind == 2 {
        reason := protocol.Highlight_Failure_Reason(julialib.jl_unbox_int32(
            julialib.jl_get_nth_field(command, 5)))
        return send_terminal_value_until_sent(service, protocol.Highlight_Failed{
            identity = identity,
            reason = reason,
        })
    }
    result := decode_highlight_result(command)
    if !protocol.highlight_result_valid(result) {
        return send_terminal_value_until_sent(service, protocol.Highlight_Failed{
            identity = identity,
            reason = .Internal_Failure,
        })
    }
    for {
        outcome := send_terminal_highlight_result(service, result)
        if outcome == .Sent {
            return true
        }
        if outcome == .Allocation_Failed {
            return send_terminal_value_until_sent(service, protocol.Highlight_Failed{
                identity = identity,
                reason = .Transport_Capacity,
            })
        }
        if !julia_egress_wait_for_capacity(service, outcome) {
            return false
        }
    }
}

// Drain complete highlight commands with a GC root covering every field access and copy.
julia_terminal_emit_highlights :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    for {
        command := julialib.jl_call1(host.terminal_take_highlight, host.runtime)
        if command == nil || julialib.jl_exception_occurred() != nil {
            print_julia_exception("terminal_host_take_highlight")
            return false
        }
        gc_stack := julialib.jl_get_pgcstack()
        if gc_stack == nil {
            return false
        }
        frame: Julia_Terminal_Command_Gc_Frame = {
            encoded_root_count = 1 << 2,
            previous = gc_stack^,
            command = command,
        }
        gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
        kind := julialib.jl_unbox_int32(julialib.jl_get_nth_field(command, 0))
        if kind == 0 {
            gc_stack^ = frame.previous
            return true
        }
        sent := julia_terminal_send_highlight(service, command, kind)
        gc_stack^ = frame.previous
        if !sent {
            return false
        }
    }
}
