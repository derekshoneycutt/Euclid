package bridge

import protocol "../core/protocol"
import julialib "../../libs/julia/bindings"

// Bind the interactive input and environment callbacks as one bridge contract.
bind_julia_terminal_interactive_callbacks :: proc(
    host: ^Julia_Runtime_Host, main_module: ^julialib.jl_module_t) {
    host.terminal_ingest_interactive_input = julialib.jl_get_function(
        main_module, "terminal_host_ingest_interactive_input")
    host.terminal_ingest_geometry = julialib.jl_get_function(
        main_module, "terminal_host_ingest_geometry")
    host.terminal_ingest_capabilities = julialib.jl_get_function(
        main_module, "terminal_host_ingest_capabilities")
}

// Advance native Terminal identity only after Julia accepts the session start.
julia_terminal_start_session :: proc(
    host: ^Julia_Runtime_Host, generation: u64) -> bool {
    accepted := julia_terminal_session_call(
        host, host.terminal_start_session, generation)
    if accepted {
        host.terminal_generation = generation
    }
    return accepted
}

// Copy a bounded display-owned input packet into the current Julia evaluation.
julia_terminal_ingest_interactive_input :: proc(
    host: ^Julia_Runtime_Host, request: protocol.Terminal_Interactive_Input) -> bool {
    if request.animation_generation != host.terminal_generation {
        return true
    }
    if request.byte_count <= 0 || request.byte_count > len(request.bytes) {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 4 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host.runtime
    frame.roots[1] = julialib.jl_box_uint64(u64(request.request_id))
    bytes := request.bytes
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(bytes[:])), uint(request.byte_count))
    frame.roots[3] = julialib.jl_box_uint64(request.animation_generation)
    return julia_terminal_interactive_call(
        host.terminal_ingest_interactive_input, &frame, 4)
}

// Invoke a rooted interactive adapter callback and expose exceptions to diagnostics.
julia_terminal_interactive_call :: proc(
    callback: ^julialib.jl_value_t, frame: ^Julia_Terminal_Request_Gc_Frame,
    argument_count: u32) -> bool {
    result := julialib.jl_call(callback, &frame.roots[0], argument_count)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("terminal_interactive_ingress")
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
}

// Install generation-ordered pane dimensions and acknowledge the exact snapshot.
julia_terminal_ingest_geometry :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: protocol.Terminal_Geometry_Accepted) -> bool {
    if request.animation_generation != host.terminal_generation {
        return true
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame: Julia_Terminal_Request_Gc_Frame = {
        encoded_root_count = 4 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host.runtime
    frame.roots[1] = julialib.jl_box_uint64(request.geometry.generation)
    frame.roots[2] = julialib.jl_box_uint16(request.geometry.dimensions.columns)
    frame.roots[3] = julialib.jl_box_uint16(request.geometry.dimensions.rows)
    if !julia_terminal_interactive_call(host.terminal_ingest_geometry, &frame, 4) {
        return false
    }
    return send_terminal_value_until_sent(service, protocol.Terminal_Geometry_Observed{
        animation_generation = request.animation_generation,
        geometry = request.geometry,
    })
}

// Install the immutable display capability contract and acknowledge its acceptance.
julia_terminal_ingest_capabilities :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: protocol.Terminal_Capabilities_Accepted) -> bool {
    if request.animation_generation != host.terminal_generation {
        return true
    }
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
    capabilities := request.capabilities
    frame.roots[0] = host.runtime
    frame.roots[1] = julialib.jl_box_uint16(capabilities.version)
    frame.roots[2] = julialib.jl_box_uint8(u8(capabilities.encoding))
    frame.roots[3] = julialib.jl_box_uint8(u8(capabilities.color))
    frame.roots[4] = julialib.jl_box_uint8(capabilities.modify_other_keys_level)
    frame.roots[5] = julialib.jl_box_uint8(capabilities.kitty_keyboard_flags)
    frame.roots[6] = julialib.jl_box_uint32(transmute(u32)capabilities.features)
    if !julia_terminal_interactive_call(host.terminal_ingest_capabilities, &frame, 7) {
        return false
    }
    return send_terminal_value_until_sent(service,
        protocol.Terminal_Capabilities_Observed{
            animation_generation = request.animation_generation,
            capabilities = capabilities,
        })
}
