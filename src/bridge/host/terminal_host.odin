package julia_host

import transport "../transport"
import bridgemodel "../model"
import protocol "../../core/protocol"
import julialib "../../../libs/julia/bindings"
import "core:c"
import "core:log"
import "core:time"

//   Invoke one Terminal session lifecycle callback on the Julia owner thread.
julia_terminal_session_call :: proc(
    host: ^Julia_Runtime_Host, callback: ^julialib.jl_value_t,
    generation: u64) -> bool {
    if host == nil || host^.runtime == nil || callback == nil {
        return false
    }
    result := julialib.jl_call2(
        callback, host^.runtime, julialib.jl_box_uint64(generation))
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_session_lifecycle")
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
}

//   Submit one borrowed evaluation source to the rooted Julia Terminal host.
julia_terminal_ingest_evaluation :: proc(
    host: ^Julia_Runtime_Host, request: protocol.Evaluation_Requested) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if host == nil || host^.runtime == nil || gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 5 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_box_uint64(u64(request.request_id))
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(request.code)), len(request.code))
    frame.roots[3] = julialib.jl_box_int32(i32(request.mode))
    frame.roots[4] = julialib.jl_box_uint64(request.animation_generation)
    result := julialib.jl_call(
        host^.terminal_ingest_evaluation, &frame.roots[0], 5)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_ingest_evaluation")
        return false
    }
    host^.terminal_request_id = request.request_id
    host^.terminal_generation = request.animation_generation
    return julialib.jl_unbox_bool(result) != 0
}

//   Register one borrowed completion source with the rooted Julia Terminal host.
julia_terminal_ingest_completion :: proc(
    host: ^Julia_Runtime_Host, request: protocol.Completion_Requested) -> bool {
    if host == nil || host^.runtime == nil {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    callback := host^.terminal_ingest_completion_preview
    if request.show_candidates {
        callback = host^.terminal_ingest_completion_candidates
    }
    if callback == nil || gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 5 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_box_uint64(u64(request.request_id))
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(request.code)), len(request.code))
    frame.roots[3] = julialib.jl_box_int32(i32(request.cursor_byte))
    frame.roots[4] = julialib.jl_box_uint64(request.animation_generation)
    result := julialib.jl_call(callback, &frame.roots[0], 5)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_ingest_completion")
        return false
    }
    return true
}

//   Deliver one native tick-stream configuration result on the Julia owner thread.
julia_terminal_ingest_tick_configuration :: proc(
    host: ^Julia_Runtime_Host,
    acknowledgement: protocol.Tick_Stream_Configuration_Acknowledged) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 5 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_box_uint64(acknowledgement.animation_generation)
    frame.roots[2] = julialib.jl_box_uint64(acknowledgement.stream_generation)
    frame.roots[3] = julialib.jl_box_uint64(acknowledgement.interval_steps)
    frame.roots[4] = julialib.jl_box_bool(c.int8_t(acknowledgement.active))
    result := julialib.jl_call(
        host^.terminal_ingest_tick_configuration, &frame.roots[0], 5)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_ingest_tick_stream_configuration")
        return false
    }
    return true
}

//   Deliver one coalesced native fixed-step pulse on the Julia owner thread.
julia_terminal_ingest_tick_pulse :: proc(
    host: ^Julia_Runtime_Host, pulse: protocol.Tick_Pulse) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 7 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_box_uint64(pulse.animation_generation)
    frame.roots[2] = julialib.jl_box_uint64(pulse.stream_generation)
    frame.roots[3] = julialib.jl_box_uint64(pulse.sequence)
    frame.roots[4] = julialib.jl_box_uint64(pulse.first_simulation_tick)
    frame.roots[5] = julialib.jl_box_uint64(pulse.last_simulation_tick)
    frame.roots[6] = julialib.jl_box_uint64(pulse.step_count)
    result := julialib.jl_call(
        host^.terminal_ingest_tick_pulse, &frame.roots[0], 7)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_ingest_tick_pulse")
        return false
    }
    return true
}

// Publish Julia's evaluation-scoped input lease through the ordinary Terminal egress.
julia_terminal_emit_input_lease :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request_id: protocol.Request_Id, acquired: bool) -> bool {
    value := bridgemodel.Julia_Host_Egress(protocol.Terminal_Input_Released{
        request_id = request_id,
        animation_generation = host.terminal_generation,
    })
    if acquired {
        value = protocol.Terminal_Input_Acquired{
            request_id = request_id,
            animation_generation = host.terminal_generation,
        }
    }
    return send_terminal_value_until_sent(service, value)
}

//   Copy one Julia evaluation command into a display-inbox Terminal envelope.
send_terminal_value_until_sent :: proc(
    service: ^Julia_Runtime_Service, value: bridgemodel.Julia_Host_Egress) -> bool {
    for {
        outcome := send_terminal_egress(service, value)
        if outcome == .Sent {
            return true
        }
        if !julia_egress_wait_for_capacity(service, outcome) {
            return false
        }
    }
}

// Retry only recoverable receiver pressure; closure/allocation errors terminate explicitly.
julia_egress_wait_for_capacity :: proc(
    service: ^Julia_Runtime_Service,
    outcome: bridgemodel.Communication_Send_Outcome) -> bool {
    if outcome == .Queue_Full || outcome == .Storage_Full {
        transport.consumer_mailbox_wait(&service.display_inbox, time.Millisecond, true)
        return true
    }
    if outcome != .Runtime_Stopping {
        log.errorf("julia_egress_publication_failed outcome=%d", int(outcome))
    }
    return false
}

//   Retry one dynamic Terminal output batch until sent or runtime shutdown.
send_terminal_output_until_sent :: proc(
    service: ^Julia_Runtime_Service, output: protocol.Terminal_Output_Batch) -> bool {
    for {
        outcome := send_terminal_output(service, output)
        if outcome == .Sent {
            return true
        }
        if !julia_egress_wait_for_capacity(service, outcome) {
            return false
        }
    }
}

//   Copy one Julia Terminal output command into receiver-owned storage.
julia_terminal_emit_output :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    command: ^julialib.jl_value_t, request_id: protocol.Request_Id) -> bool {
    text_value := julialib.jl_get_nth_field(command, 2)
    byte_count := int(julialib.jl_unbox_int32(julialib.jl_get_nth_field(command, 3)))
    truncated := u64(julialib.jl_unbox_uint64(julialib.jl_get_nth_field(command, 4)))
    bytes := string(([^]u8)(julialib.jl_string_ptr(text_value))[:byte_count])
    return send_terminal_output_until_sent(service, {
        request_id = request_id,
        animation_generation = host^.terminal_generation,
        bytes = bytes,
        truncated_bytes = truncated,
    })
}

//   Emit one completed or incomplete Julia Terminal evaluation command.
julia_terminal_emit_completion :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request_id: protocol.Request_Id, complete: bool) -> bool {
    value := bridgemodel.Julia_Host_Egress(protocol.Evaluation_Incomplete{
        request_id = request_id,
        animation_generation = host^.terminal_generation,
    })
    if complete {
        value = protocol.Evaluation_Completed{
            request_id = request_id,
            animation_generation = host^.terminal_generation,
            succeeded = true,
        }
    }
    return send_terminal_value_until_sent(service, value)
}

//   Copy one Julia evaluation command into a display-inbox Terminal envelope.
julia_terminal_emit_evaluation :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    command: ^julialib.jl_value_t) -> (bool, bool) {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false, false
    }
    frame: Julia_Terminal_Command_Gc_Frame = {
        encoded_root_count = 1 << 2,
        previous = gc_stack^,
        command = command,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    kind := i32(julialib.jl_unbox_int32(
        julialib.jl_get_nth_field(command, 0)))
    if kind == 0 {
        gc_stack^ = frame.previous
        return false, true
    }
    request_id := protocol.Request_Id(julialib.jl_unbox_uint64(
        julialib.jl_get_nth_field(command, 1)))
    sent := true
    if kind == 1 {
        sent = julia_terminal_emit_output(service, host, command, request_id)
    } else if kind == 2 || kind == 3 {
        sent = julia_terminal_emit_completion(service, host, request_id, kind == 2)
    } else if kind == 5 || kind == 6 {
        sent = julia_terminal_emit_input_lease(service, host, request_id, kind == 5)
    }
    gc_stack^ = frame.previous
    return true, sent
}

//   Fetch and publish Julia's startup banner for one installed Terminal session.
julia_terminal_emit_session_ready :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    generation: u64) -> bool {
    result := julialib.jl_call0(host^.terminal_startup_banner)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_startup_banner")
        return false
    }
    banner := string(julialib.jl_string_ptr(result))
    for {
        outcome := send_terminal_session_ready(service, {
            animation_generation = generation,
            banner = banner,
        })
        if outcome == .Sent {
            return true
        }
        if !julia_egress_wait_for_capacity(service, outcome) {
            return false
        }
    }
}



// Read primitive lifecycle fields while the Julia command is rooted.
julia_terminal_lifecycle_command_read :: proc(
    host: ^Julia_Runtime_Host) -> Julia_Terminal_Lifecycle_Command {
    command := julialib.jl_call1(
        host^.terminal_take_session_lifecycle, host^.runtime)
    if command == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_take_session_lifecycle")
        return {}
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return {}
    }
    frame: Julia_Terminal_Command_Gc_Frame = {
        encoded_root_count = 1 << 2,
        previous = gc_stack^,
        command = command,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    result: Julia_Terminal_Lifecycle_Command = {
        kind = i32(julialib.jl_unbox_int32(
            julialib.jl_get_nth_field(command, 0))),
        generation = u64(julialib.jl_unbox_uint64(
            julialib.jl_get_nth_field(command, 1))),
        valid = true,
    }
    gc_stack^ = frame.previous
    return result
}

//   Publish every ready Terminal session lifecycle observation.
julia_terminal_emit_session_lifecycle :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    for {
        command := julia_terminal_lifecycle_command_read(host)
        if !command.valid {
            return false
        }
        if command.kind == 0 {
            return true
        }
        if command.kind == 2 {
            if !send_terminal_value_until_sent(service,
                protocol.Terminal_Session_Stopped{
                    animation_generation = command.generation,
                }) {
                return true
            }
        } else if !julia_terminal_emit_session_ready(
            service, host, command.generation) {
            return false
        }
    }
}

//   Publish every ready tick-stream configure or stop request.
julia_terminal_emit_tick_stream :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    for {
        command := julialib.jl_call1(host^.terminal_take_tick_stream, host^.runtime)
        if command == nil || julialib.jl_exception_occurred() != nil {
            return false
        }
        kind := i32(julialib.jl_unbox_int32(julialib.jl_get_nth_field(command, 0)))
        if kind == 0 {
            return true
        }
        animation_generation := u64(julialib.jl_unbox_uint64(
            julialib.jl_get_nth_field(command, 1)))
        stream_generation := u64(julialib.jl_unbox_uint64(
            julialib.jl_get_nth_field(command, 2)))
        value: bridgemodel.Julia_Host_Egress
        if kind == 1 {
            value = protocol.Tick_Stream_Configure_Requested{
                animation_generation = animation_generation,
                stream_generation = stream_generation,
                requested_period_ns = u64(julialib.jl_unbox_uint64(
                    julialib.jl_get_nth_field(command, 3))),
            }
        } else {
            value = protocol.Tick_Stream_Stop_Requested{
                animation_generation = animation_generation,
                stream_generation = stream_generation,
            }
        }
        if !send_terminal_value_until_sent(service, value) {
            return false
        }
    }
}

//   Publish one rooted Julia completion command through the native protocol.
julia_terminal_send_completion :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    command: ^julialib.jl_value_t, kind: i32,
    request_id: protocol.Request_Id) -> bool {
    if kind == 2 {
        return send_terminal_value_until_sent(service, protocol.Completion_Failed{
            request_id = request_id,
            animation_generation = host^.terminal_generation,
            reason = protocol.Completion_Failure_Reason(julialib.jl_unbox_int32(
                julialib.jl_get_nth_field(command, 7))),
        })
    }
    insertion_value := julialib.jl_get_nth_field(command, 6)
    return send_terminal_completion_until_sent(service, {
        request_id = request_id,
        animation_generation = host^.terminal_generation,
        found = julialib.jl_unbox_bool(
            julialib.jl_get_nth_field(command, 2)) != 0,
        replacement_start = int(julialib.jl_unbox_int32(
            julialib.jl_get_nth_field(command, 3))),
        replacement_end = int(julialib.jl_unbox_int32(
            julialib.jl_get_nth_field(command, 4))),
        insertion = string(julialib.jl_string_ptr(insertion_value)),
        show_candidates = julialib.jl_unbox_bool(
            julialib.jl_get_nth_field(command, 5)) != 0,
    })
}

// Reject permanent capacity failures before retrying transient completion backpressure.
send_terminal_completion_until_sent :: proc(
    service: ^Julia_Runtime_Service, result: protocol.Completion_Result) -> bool {
    if len(result.insertion) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        log.warnf("terminal_completion_rejected reason=result_capacity bytes=%d",
            len(result.insertion))
        return send_terminal_value_until_sent(service, protocol.Completion_Failed{
            request_id = result.request_id,
            animation_generation = result.animation_generation,
            reason = .Internal_Failure,
        })
    }
    for {
        outcome := send_terminal_completion_result(service, result)
        if outcome == .Sent {
            return true
        }
        if !julia_egress_wait_for_capacity(service, outcome) {
            return false
        }
    }
}

//   Copy every ready completion result into the display-owned inbox.
julia_terminal_emit_completions :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    for {
        command := julialib.jl_call1(host^.terminal_take_completion, host^.runtime)
        if command == nil || julialib.jl_exception_occurred() != nil {
            print_julia_exception("terminal_host_take_completion")
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
        kind := i32(julialib.jl_unbox_int32(julialib.jl_get_nth_field(command, 0)))
        if kind == 0 {
            gc_stack^ = frame.previous
            return true
        }
        request_id := protocol.Request_Id(julialib.jl_unbox_uint64(
            julialib.jl_get_nth_field(command, 1)))
        sent := julia_terminal_send_completion(
            service, host, command, kind, request_id)
        gc_stack^ = frame.previous
        if !sent {
            return false
        }
    }
}

// Publish ready lifecycle, tick, and editor outcomes before ordered evaluation output.
julia_terminal_emit_ready_commands :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    return julia_terminal_emit_session_lifecycle(service, host) &&
        julia_terminal_emit_tick_stream(service, host) &&
        julia_terminal_emit_completions(service, host) &&
        julia_terminal_emit_highlights(service, host)
}

//   Pump bounded Julia Terminal work and publish every ready evaluation command.
julia_terminal_service :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host) -> bool {
    if host == nil || host^.runtime == nil {
        return false
    }
    result := julialib.jl_call1(host^.terminal_pump, host^.runtime)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_host_pump")
        return false
    }
    host.idle_wait = time.Duration(julialib.jl_unbox_int64(result))
    if !julia_terminal_emit_ready_commands(service, host) {
        return false
    }
    for {
        command := julialib.jl_call1(
            host^.terminal_take_evaluation, host^.runtime)
        if command == nil || julialib.jl_exception_occurred() != nil {
            print_julia_exception("terminal_host_take_evaluation")
            return false
        }
        available, sent := julia_terminal_emit_evaluation(service, host, command)
        if !sent {
            return false
        }
        if !available {
            return true
        }
    }
}

//   Dispatch one typed Terminal ingress envelope on the sole Julia owner thread.
julia_terminal_dispatch_ingress :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    message: ^bridgemodel.Julia_Host_Ingress) -> bool {
    #partial switch payload in message^ {
    case protocol.Terminal_Session_Started:
        return julia_terminal_start_session(host, payload.animation_generation)
    case protocol.Terminal_Session_Closed:
        return julia_terminal_session_call(
            host, host^.terminal_close_session, payload.animation_generation)
    case protocol.Evaluation_Requested:
        return julia_terminal_ingest_evaluation(host, payload)
    case protocol.Terminal_Interactive_Input:
        return julia_terminal_ingest_interactive_input(host, payload)
    case protocol.Terminal_Geometry_Accepted:
        return julia_terminal_ingest_geometry(service, host, payload)
    case protocol.Terminal_Capabilities_Accepted:
        return julia_terminal_ingest_capabilities(service, host, payload)
    case protocol.Completion_Requested:
        return julia_terminal_ingest_completion(host, payload)
    case protocol.Highlight_Requested:
        return julia_terminal_ingest_highlight(host, payload)
    case protocol.Tick_Stream_Configuration_Acknowledged:
        return julia_terminal_ingest_tick_configuration(host, payload)
    case protocol.Tick_Pulse:
        return julia_terminal_ingest_tick_pulse(host, payload)
    }
    return false
}
