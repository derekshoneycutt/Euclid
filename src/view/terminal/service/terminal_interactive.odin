package terminalservice

import core "../../../core"
import protocol "../../../core/protocol"
import julia "../../../bridge"
import input "../../input"
import terminalview ".."
import "core:log"

// Retry the latest owner-accepted Terminal snapshots until Julia acknowledges them.
terminal_service_publish_interactive_environment :: proc(
    state: ^core.Euclid_General_State) {
    term := &state.terminal
    if term.geometry.generation > term.julia_geometry_generation {
        outcome := julia.send_terminal_ingress(state.julia_runtime_service,
            protocol.Terminal_Geometry_Accepted{
                animation_generation = term.animation_generation,
                geometry = term.geometry,
            })
        if outcome != .Sent {
            return
        }
    }
    if !term.julia_capabilities_observed {
        _ = julia.send_terminal_ingress(state.julia_runtime_service,
            protocol.Terminal_Capabilities_Accepted{
                animation_generation = term.animation_generation,
                capabilities = terminalview.TERMINAL_CAPABILITIES,
            })
    }
}

// Preserve queued bytes under pressure, bound to one evaluation and Terminal generation.
terminal_service_deliver_interactive_input :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime) {
    request: protocol.Terminal_Interactive_Input = {
        request_id = state.terminal.interactive_input_request_id,
        animation_generation = state.terminal.animation_generation,
    }
    request.byte_count = input.input_runtime_copy_queued_bytes(runtime, request.bytes[:])
    if request.byte_count == 0 {
        return
    }
    outcome := julia.send_terminal_ingress(state.julia_runtime_service, request)
    if outcome == .Sent {
        _ = input.input_runtime_pop_queued_bytes(runtime, request.byte_count)
    } else {
        runtime.byte_delivery_rejection_count += 1
        log.warnf("terminal_interactive_input_deferred outcome=%d", int(outcome))
    }
}

// Route ordinary encoded terminal keys exclusively to the current Julia input lease.
terminal_service_interactive_input :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime,
    frame: input.Input_Frame) {
    if runtime == nil {
        return
    }
    term := &state.terminal
    if !term.awaiting_eval || term.interactive_input_request_id == 0 {
        if runtime.owner.kind == .Julia_Interactive {
            _ = input.input_runtime_set_owner(runtime, {})
        }
        return
    }
    _ = input.input_runtime_set_owner(runtime, {
        kind = .Julia_Interactive,
        id = u64(term.interactive_input_request_id),
        generation = term.animation_generation,
    })
    input.input_terminal_enqueue_interpreter_frame(
        runtime, &term.output_interpreter, frame)
    terminal_service_deliver_interactive_input(state, runtime)
}
