package view

import "../bridge"
import "../core"
import "../core/protocol"
import view_core "core"

TERMINAL_TICK_FIXED_RATE_HZ :: u64(view_core.LIMIT_FPS)
TERMINAL_TICK_NANOSECONDS_PER_SECOND :: u64(1_000_000_000)

// Convert a requested period to the slowest matching fixed-step interval.
terminal_tick_interval_steps :: proc(requested_period_ns: u64) -> u64 {
    whole_seconds := requested_period_ns / TERMINAL_TICK_NANOSECONDS_PER_SECOND
    remainder_ns := requested_period_ns % TERMINAL_TICK_NANOSECONDS_PER_SECOND
    if whole_seconds > max(u64) / TERMINAL_TICK_FIXED_RATE_HZ {
        return max(u64)
    }
    steps := whole_seconds * TERMINAL_TICK_FIXED_RATE_HZ
    scaled_remainder := remainder_ns * TERMINAL_TICK_FIXED_RATE_HZ
    steps += scaled_remainder / TERMINAL_TICK_NANOSECONDS_PER_SECOND
    if scaled_remainder % TERMINAL_TICK_NANOSECONDS_PER_SECOND != 0 {
        steps += 1
    }
    return max(steps, u64(1))
}

// Install one newer stream request for the active Terminal generation.
terminal_tick_configure :: proc(
    state: ^core.Euclid_General_State,
    request: protocol.Tick_Stream_Configure_Requested) -> bool {
    if state == nil || !state^.terminal.initialized ||
       request.animation_generation != state^.terminal.animation_generation ||
       request.stream_generation == 0 { return false }
    publisher := &state^.terminal_tick_publisher
    if request.animation_generation == publisher^.animation_generation &&
       request.stream_generation < publisher^.stream_generation { return false }
    interval_steps := terminal_tick_interval_steps(request.requested_period_ns)
    publisher^ = {
        animation_generation = request.animation_generation,
        stream_generation = request.stream_generation,
        interval_steps = interval_steps,
        acknowledgement = {
            animation_generation = request.animation_generation,
            stream_generation = request.stream_generation,
            interval_steps = interval_steps,
            active = true,
        },
        active = true,
        acknowledgement_pending = true,
    }
    return true
}

// Stop one exact stream while retaining its final acknowledgement for Julia.
terminal_tick_stop :: proc(
    state: ^core.Euclid_General_State,
    request: protocol.Tick_Stream_Stop_Requested) -> bool {
    if state == nil { return false }
    publisher := &state^.terminal_tick_publisher
    if !publisher^.active ||
       request.animation_generation != publisher^.animation_generation ||
       request.stream_generation != publisher^.stream_generation { return false }
    publisher^.active = false
    publisher^.accumulated_steps = 0
    publisher^.pulse = {}
    publisher^.pulse_pending = false
    publisher^.acknowledgement = {
        animation_generation = request.animation_generation,
        stream_generation = request.stream_generation,
        active = false,
    }
    publisher^.acknowledgement_pending = true
    return true
}

// Record one deterministic update in bounded coalesced publisher state.
terminal_tick_record_step :: proc(
    publisher: ^core.Terminal_Tick_Publisher, simulation_tick: u64) {
    if publisher == nil || !publisher^.active { return }
    if publisher^.pulse_pending {
        publisher^.pulse.last_simulation_tick = simulation_tick
        publisher^.pulse.step_count += 1
        return
    }
    if publisher^.accumulated_steps == 0 {
        publisher^.accumulated_first_tick = simulation_tick
    }
    publisher^.accumulated_last_tick = simulation_tick
    publisher^.accumulated_steps += 1
    if publisher^.acknowledgement_pending ||
       publisher^.accumulated_steps < publisher^.interval_steps { return }
    publisher^.next_sequence += 1
    publisher^.pulse = {
        animation_generation = publisher^.animation_generation,
        stream_generation = publisher^.stream_generation,
        sequence = publisher^.next_sequence,
        first_simulation_tick = publisher^.accumulated_first_tick,
        last_simulation_tick = publisher^.accumulated_last_tick,
        step_count = publisher^.accumulated_steps,
    }
    publisher^.accumulated_steps = 0
    publisher^.pulse_pending = true
}

// Publish pending acknowledgement and pulse traffic without blocking display work.
terminal_tick_publish :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_runtime_service == nil { return }
    publisher := &state^.terminal_tick_publisher
    if publisher^.acknowledgement_pending {
        outcome := bridge.send_terminal_ingress(
            state^.julia_runtime_service, publisher^.acknowledgement)
        if outcome != .Sent { return }
        publisher^.acknowledgement_pending = false
    }
    if publisher^.pulse_pending && bridge.send_terminal_ingress(
        state^.julia_runtime_service, publisher^.pulse) == .Sent {
        publisher^.pulse = {}
        publisher^.pulse_pending = false
    }
}

// Dispatch one Julia tick stream control request on the display thread.
terminal_tick_dispatch_egress :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Tick_Stream_Configure_Requested:
        return terminal_tick_configure(state, payload)
    case protocol.Tick_Stream_Stop_Requested:
        return terminal_tick_stop(state, payload)
    }
    return false
}