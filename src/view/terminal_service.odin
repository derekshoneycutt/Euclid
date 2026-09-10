package view

import "../core"
import protocol "../core/protocol"
import evidence_session "../evidence/session"
import julia "../bridge"
import termsession "../terminal/session"
import "font"
import "input"
import terminalview "terminal"
import "ui"

import rl "vendor:raylib"

// Return whether the special Terminal animation owns the committed animation generation.
terminal_animation_selected :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }
    current := state^.julia_interface^.current_animation
    return current != nil && current^.name == julia.TERMINAL_ANIMATION_NAME
}

// Initialize a fresh Terminal and request its matching Julia session generation.
terminal_service_enter :: proc(state: ^core.Euclid_General_State) -> bool {
    generation := state^.animation_memory.generation
    if generation == 0 || !terminalview.terminal_init_for_animation(
        &state^.terminal, &state^.animation_memory, generation) {
        return false
    }
    if !shell_service_begin_generation(state, generation) {
        terminalview.terminal_destroy(&state^.terminal)
        return false
    }
    if !terminal_graphics_bind_generation(state, generation) {
        termsession.terminal_session_destroy(&state^.shell.session)
        terminalview.terminal_destroy(&state^.terminal)
        return false
    }
    outcome := julia.send_terminal_ingress(
        state^.julia_runtime_service, protocol.Terminal_Session_Started{
            animation_generation = generation,
        })
    state^.terminal.julia_session_start_sent = outcome == .Sent
    return true
}

// Retry a generation start request after bounded transport pressure.
terminal_service_request_session :: proc(state: ^core.Euclid_General_State) {
    term := &state^.terminal
    if term^.julia_session_start_sent || state^.julia_runtime_service == nil {
        return
    }
    outcome := julia.send_terminal_ingress(
        state^.julia_runtime_service, protocol.Terminal_Session_Started{
            animation_generation = term^.animation_generation,
        })
    term^.julia_session_start_sent = outcome == .Sent
}

// Submit one correlated evaluation through the display-owned Julia ingress link.
terminal_service_submit_evaluation :: proc(
    state: ^core.Euclid_General_State, text: string,
    mode: protocol.Evaluation_Mode = .Normal) -> core.Communication_Send_Outcome {
    if state == nil || state^.julia_runtime_service == nil ||
        !state^.terminal.initialized || !terminalview.terminal_begin_eval(
            &state^.terminal, text) {
        return .Runtime_Stopping
    }
    request := protocol.Evaluation_Requested{
        request_id = state^.terminal.pending_eval_request_id,
        animation_generation = state^.terminal.animation_generation,
        code = state^.terminal.pending_eval_source,
        mode = mode,
    }
    outcome := julia.send_terminal_evaluation(
        state^.julia_runtime_service, request)
    if outcome != .Sent {
        terminalview.terminal_complete_eval(&state^.terminal)
    }
    return outcome
}

// Return whether one result belongs to the active Terminal animation generation.
terminal_service_generation_matches :: proc(
    state: ^core.Euclid_General_State, generation: u64) -> bool {
    return state != nil && state^.terminal.initialized &&
        generation != 0 && generation == state^.terminal.animation_generation
}

// Apply one ordered evaluation output batch to the current display-owned Terminal.
terminal_service_dispatch_output :: proc(
    state: ^core.Euclid_General_State,
    output: protocol.Terminal_Output_Batch) -> bool {
    if !terminal_service_generation_matches(
        state, output.animation_generation) ||
        output.request_id != state^.terminal.pending_eval_request_id {
        return false
    }
    terminalview.terminal_append_ansi_output(&state^.terminal, output.bytes, {
        kind = .Julia_Evaluation,
        id = u64(output.request_id),
        generation = output.animation_generation,
    })
    return true
}

// Complete only the evaluation owned by the current Terminal generation.
terminal_service_dispatch_completion :: proc(
    state: ^core.Euclid_General_State,
    result: protocol.Evaluation_Completed) -> bool {
    if !terminal_service_generation_matches(
        state, result.animation_generation) ||
        result.request_id != state^.terminal.pending_eval_request_id {
        return false
    }
    terminalview.terminal_complete_eval(&state^.terminal)
    return true
}

// Dispatch one borrowed evaluation lifecycle value on the display thread.
terminal_service_dispatch_evaluation :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Terminal_Output_Batch:
        return terminal_service_dispatch_output(state, payload)
    case protocol.Evaluation_Incomplete:
        if terminal_service_generation_matches(
            state, payload.animation_generation) &&
            payload.request_id == state^.terminal.pending_eval_request_id {
            terminalview.terminal_continue_eval(&state^.terminal)
            return true
        }
    case protocol.Evaluation_Completed:
        return terminal_service_dispatch_completion(state, payload)
    }
    return false
}

// Dispatch one borrowed completion value on the display thread.
terminal_service_dispatch_completion_result :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Completion_Result:
        if terminal_service_generation_matches(state, payload.animation_generation) {
            return terminalview.terminal_set_completion_preview(
                &state^.terminal, {
                    request_id = payload.request_id,
                    found = payload.found,
                    replacement_start = payload.replacement_start,
                    replacement_end = payload.replacement_end,
                    insertion = payload.insertion,
                })
        }
    case protocol.Completion_Failed:
        if terminal_service_generation_matches(state, payload.animation_generation) {
            return terminalview.terminal_fail_completion(
                &state^.terminal, payload.request_id)
        }
    }
    return false
}

// Dispatch one borrowed interactive-input lease value on the display thread.
terminal_service_dispatch_input :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Terminal_Input_Acquired:
        if terminal_service_generation_matches(state, payload.animation_generation) &&
            payload.request_id == state^.terminal.pending_eval_request_id {
            state^.terminal.interactive_input_request_id = payload.request_id
            return true
        }
    case protocol.Terminal_Input_Released:
        if terminal_service_generation_matches(state, payload.animation_generation) &&
            payload.request_id == state^.terminal.interactive_input_request_id {
            state^.terminal.interactive_input_request_id = 0
            return true
        }
    }
    return false
}

// Dispatch one borrowed Terminal observation or lifecycle value on the display thread.
terminal_service_session_ready :: proc(
    state: ^core.Euclid_General_State,
    ready: protocol.Terminal_Session_Ready) -> bool {
    if !terminal_service_generation_matches(
        state, ready.animation_generation) { return false }
    state^.terminal.julia_session_ready = true
    if !state^.terminal.banner_ready {
        terminalview.terminal_display_banner(&state^.terminal, ready.banner)
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Terminal_Session_Ready,
            generation = ready.animation_generation,
            flags = {.Required},
        })
    return true
}

// Dispatch one borrowed Terminal observation or lifecycle value on the display thread.
terminal_service_dispatch_observation :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Terminal_Geometry_Observed:
        if terminal_service_generation_matches(state, payload.animation_generation) &&
            payload.geometry == state^.terminal.geometry {
            state^.terminal.julia_geometry_generation = payload.geometry.generation
            return true
        }
    case protocol.Terminal_Capabilities_Observed:
        if terminal_service_generation_matches(state, payload.animation_generation) &&
            payload.capabilities == terminalview.TERMINAL_CAPABILITIES {
            state^.terminal.julia_capabilities_observed = true
            return true
        }
    case protocol.Terminal_Session_Ready:
        return terminal_service_session_ready(state, payload)
    case protocol.Terminal_Session_Stopped:
        if terminal_service_generation_matches(
            state, payload.animation_generation) {
            state^.terminal.julia_session_ready = false
            return true
        }
    }
    return false
}

// Dispatch one borrowed terminal egress value through its display-owned message family.
terminal_service_dispatch_egress :: proc(
    state: ^core.Euclid_General_State,
    message: ^core.Julia_Host_Egress) -> bool {
    return terminal_tick_dispatch_egress(state, message) ||
        terminal_service_dispatch_evaluation(state, message) ||
        terminal_service_dispatch_completion_result(state, message) ||
        terminal_service_dispatch_input(state, message) ||
        terminal_service_dispatch_observation(state, message)
}

// Open one terminal hyperlink after its URI passed terminal validation.
terminal_service_open_uri :: proc(_: rawptr, uri: cstring) -> bool {
    rl.OpenURL(uri)
    return true
}

// Publish one validated OSC clipboard value through the display-owned OS boundary.
terminal_service_write_clipboard :: proc(_: rawptr, text: string) -> bool {
    input.input_set_clipboard_text(text)
    return true
}

// Update the selected fixed-panel Terminal before simulation preparation.
terminal_service_apply_submission :: proc(
    state: ^core.Euclid_General_State,
    submission: terminalview.Terminal_Submission) {
    if !submission.submitted { return }
    if state^.terminal.input_mode == .Shell {
        _ = shell_service_submit(state, submission.text)
    } else {
        _ = terminal_service_submit_evaluation(
            state, submission.text, state^.terminal.input_mode)
    }
}

// Update the selected fixed-panel Terminal before simulation preparation.
terminal_service_update :: proc(
    state: ^core.Euclid_General_State, input_runtime: ^input.Input_Runtime,
    frame: input.Input_Frame) {
    if !terminal_animation_selected(state) {
        return
    }
    if !state^.terminal.initialized && !terminal_service_enter(state) {
        return
    }
    terminal_service_request_session(state)
    if !state^.terminal.julia_session_ready {
        return
    }
    bounds := ui.terminal_content_panel(state^.ui_runtime.ui_regions.text_rect)
    terminal_font := font.cache_resolve(&state^.font_cache, .Terminal_Regular)
    shell_was_running := state^.shell.phase == .Running
    update := ui.terminal_update(&state^.terminal, frame, terminal_font, bounds)
    terminal_service_apply_submission(state, update.submission)
    shell_frame := terminalview.terminal_resolve_mouse_frame(
        &state^.terminal, frame, bounds)
    shell_service_update(
        state, input_runtime, shell_frame, update.geometry_change,
        shell_was_running)
    _ = terminalview.terminal_publish_clipboard_actions(
        &state^.terminal, state^.terminal.output_producer,
        {write = terminal_service_write_clipboard})
    terminal_graphics_update(state)
    _ = terminalview.terminal_activate_hyperlink(
        &state^.terminal, update.hyperlink_activation,
        {activate = terminal_service_open_uri})
}
