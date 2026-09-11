package view

import "base:runtime"
import bridge "../bridge"
import "../core"
import protocol "../core/protocol"
import termhist "../terminal/history"
import "input"
import terminalview "terminal"
import "ui"

import "core:strings"
import "core:testing"
import "core:time"

// Dispatch one test envelope through the same display-owned Terminal path as production.
terminal_service_test_route_egress :: proc(
    user_data: rawptr, message: ^core.Julia_Host_Egress) -> bool {
    state := cast(^core.Euclid_General_State)user_data
    _ = terminal_service_dispatch_egress(state, message)
    return false
}

// Initialize one link-only Julia service without starting or entering libjulia.
terminal_service_test_runtime_init :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    service := new(core.Julia_Runtime_Service, context.allocator)
    testing.expect_value(t, bridge.init_julia_runtime_channels(service),
        runtime.Allocator_Error.None)
    service.lifecycle = .Ready
    state^.julia_runtime_service = service
    bridge.configure_julia_egress_dispatch(
        service, terminal_service_test_route_egress, rawptr(state))
}

// Destroy one link-only Julia service after reclaiming all returned envelopes.
terminal_service_test_runtime_destroy :: proc(state: ^core.Euclid_General_State) {
    service := state^.julia_runtime_service
    bridge.clear_julia_egress_dispatch(service)
    _ = bridge.drain_julia_ingress_returns(service)
    _ = bridge.drain_julia_egress_returns(service)
    bridge.communication_link_destroy(&service^.event_link)
    bridge.communication_link_destroy(&service^.request_link)
    free(service, context.allocator)
    state^.julia_runtime_service = nil
}

// Drain borrowed terminal messages through the display-owned dispatcher.
terminal_service_test_dispatch_egress :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) -> int {
    testing.expect(t, state != nil && state^.julia_runtime_service != nil)
    return bridge.drain_julia_egress(state^.julia_runtime_service)
}

// Produce two ordered output batches and one completion as the simulated Julia owner.
terminal_service_test_send_evaluation_result :: proc(
    t: ^testing.T, service: ^core.Julia_Runtime_Service,
    request: protocol.Evaluation_Requested) {
    first := protocol.Terminal_Output_Batch{
        request_id = request.request_id,
        animation_generation = request.animation_generation,
        bytes = "first\n",
    }
    second := first
    second.bytes = "second\n"
    testing.expect_value(t, bridge.send_terminal_output(service, first),
        core.Communication_Send_Outcome.Sent)
    testing.expect_value(t, bridge.send_terminal_output(service, second),
        core.Communication_Send_Outcome.Sent)
    testing.expect_value(t, bridge.send_terminal_egress(service,
        protocol.Evaluation_Completed{
            request_id = request.request_id,
            animation_generation = request.animation_generation,
            succeeded = true,
        }), core.Communication_Send_Outcome.Sent)
}

// Initialize the animation arena and selected Terminal descriptor for service tests.
terminal_service_test_state_init :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    animation: ^core.Euclid_Julia_Animation_Interface, generation: u64) {
    testing.expect(t, core.animation_memory_init(&state^.animation_memory))
    testing.expect_value(t, core.animation_memory_begin_generation(
        &state^.animation_memory, generation), core.Animation_Memory_Status.Ok)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = animation
    state^.julia_interface^.current_animation = animation
    animation^.name = "Terminal"
}

// Report whether any retained terminal output row contains the requested text.
terminal_service_test_contains :: proc(
    state: ^core.Euclid_General_State, text: string) -> bool {
    for line in 0..<ui.terminal_line_count(&state^.terminal) {
        if strings.contains(ui.terminal_line_text(&state^.terminal, line), text) {
            return true
        }
    }
    return false
}

// Pump one real native shell command until its PTY output and completion drain.
terminal_service_test_wait_for_shell :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^input.Input_Runtime = nil) -> bool {
    deadline := time.tick_since({}) + 5 * time.Second
    for time.tick_since({}) < deadline {
        shell_service_update(state, runtime)
        if state^.shell.phase == .Inactive {
            return true
        }
    }
    return false
}

// Build one ordered text-and-Enter frame for a running terminal process.
terminal_service_test_command_frame :: proc(
    storage: []input.Input_Event, command: string) -> input.Input_Frame {
    count := 0
    for byte in transmute([]u8)command {
        storage[count] = {kind = .Text, codepoint = rune(byte)}
        count += 1
    }
    storage[count] = {kind = .Press, key = .Enter}
    count += 1
    return {events = storage[:count], window_focused = true}
}

// Verify literal shell submissions use a real PTY and can launch repeatedly.
@(test)
terminal_service_test_real_pty_lifecycle :: proc(t: ^testing.T) {
    when ODIN_OS == .Linux {
        state := new(core.Euclid_General_State, context.allocator)
        defer free(state, context.allocator)
        animation: core.Euclid_Julia_Animation_Interface
        terminal_service_test_state_init(t, state, &animation, 1)
        defer core.animation_memory_destroy(&state^.animation_memory)
        testing.expect(t, terminalview.terminal_init_for_animation(
            &state^.terminal, &state^.animation_memory, 1))
        defer terminalview.terminal_destroy(&state^.terminal)
        testing.expect(t, shell_service_runtime_init(state))
        defer shell_service_runtime_destroy(state)

        testing.expect(t, shell_service_submit(
            state, "/bin/sh -c 'printf phase6-ok; exit 3'"))
        testing.expect(t, terminal_service_test_wait_for_shell(state))
        testing.expect(t, terminal_service_test_contains(state, "phase6-ok"))
        testing.expect(t, terminal_service_test_contains(
            state, "process exited with status 3"))
        testing.expect(t, !state^.terminal.awaiting_eval)

        testing.expect(t, shell_service_submit(state, "/bin/printf reopened"))
        testing.expect(t, terminal_service_test_wait_for_shell(state))
        testing.expect(t, terminal_service_test_contains(state, "reopened"))

        runtime: input.Input_Runtime
        testing.expect(t, shell_service_submit(
            state, "/bin/bash --noprofile --norc"))
        shell_service_update(state, &runtime)
        testing.expect_value(t, state^.shell.phase, core.Shell_Launch_Phase.Running)
        events: [64]input.Input_Event
        frame := terminal_service_test_command_frame(
            events[:], "printf interactive-ok; exit")
        shell_service_update(state, &runtime, frame, admit_input = true)
        testing.expect(t, terminal_service_test_wait_for_shell(state, &runtime))
        testing.expect(t, terminal_service_test_contains(state, "interactive-ok"))
    }
}

// Verify requested selection cannot activate Terminal before the switch commits.
@(test)
terminal_service_test_selection_identity :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    previous: core.Euclid_Julia_Animation_Interface
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = &animation
    state^.julia_interface^.current_animation = &previous
    animation.name = "Terminal"
    testing.expect(t, !terminal_animation_selected(state))
    animation.name = "Terminal"
    testing.expect(t, !terminal_animation_selected(state))
    state^.julia_interface^.current_animation = &animation
    testing.expect(t, terminal_animation_selected(state))
}

// Verify Terminal entry requests Julia ownership before publishing its ready banner.
@(test)
terminal_service_test_entry_waits_for_julia_session :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 4)
    defer core.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    testing.expect(t, !terminal_service_test_contains(state, "Euclid Terminal"))
    ingress, received := bridge.communication_link_try_recv(
        &state^.julia_runtime_service^.request_link)
    testing.expect(t, received)
    started, is_started := ingress^.(protocol.Terminal_Session_Started)
    testing.expect(t, is_started)
    testing.expect_value(t, started.animation_generation, u64(4))
    testing.expect(t, bridge.communication_link_return(
        &state^.julia_runtime_service^.request_link, ingress))
    testing.expect_value(t, bridge.send_terminal_session_ready(
        state^.julia_runtime_service, protocol.Terminal_Session_Ready{
            animation_generation = 4,
            banner = "Julia Version test\n\x1b[1mready\x1b[0m\n",
        }), core.Communication_Send_Outcome.Sent)
    testing.expect_value(t, terminal_service_test_dispatch_egress(t, state), 1)
    testing.expect(t, terminal_service_test_contains(state, "Julia Version test"))
    testing.expect(t, !terminal_service_test_contains(state, "Euclid Terminal"))
    terminalview.terminal_destroy(&state^.terminal)
}

// Verify animation reset retirement permits pristine entry in the next generation.
@(test)
terminal_service_test_generation_reentry_is_pristine :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 7)
    defer core.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    terminalview.terminal_append_ansi_output(
        &state^.terminal, "old generation\n")

    terminalview.terminal_destroy(&state^.terminal)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &state^.animation_memory, 8), core.Animation_Memory_Status.Ok)
    testing.expect(t, terminal_service_enter(state))
    testing.expect_value(t, state^.terminal.animation_generation, u64(8))
    testing.expect(t, !terminal_service_test_contains(state, "old generation"))
    terminalview.terminal_destroy(&state^.terminal)
}

// Verify typed transport applies ordered output and completion without entering Julia.
@(test)
terminal_service_test_typed_evaluation_round_trip :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 12)
    defer core.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    started, started_received := bridge.communication_link_try_recv(
        &state^.julia_runtime_service^.request_link)
    testing.expect(t, started_received)
    testing.expect(t, bridge.communication_link_return(
        &state^.julia_runtime_service^.request_link, started))
    state^.terminal.julia_session_ready = true
    testing.expect_value(t, terminal_service_submit_evaluation(state, "1 + 1"),
        core.Communication_Send_Outcome.Sent)

    ingress, received := bridge.communication_link_try_recv(
        &state^.julia_runtime_service^.request_link)
    testing.expect(t, received)
    request, is_request := ingress^.(protocol.Evaluation_Requested)
    testing.expect(t, is_request)
    testing.expect_value(t, request.code, "1 + 1")
    testing.expect_value(t, request.animation_generation, u64(12))
    testing.expect(t, bridge.communication_link_return(
        &state^.julia_runtime_service^.request_link, ingress))

    terminal_service_test_send_evaluation_result(
        t, state^.julia_runtime_service, request)
    testing.expect_value(t, terminal_service_test_dispatch_egress(t, state), 3)
    testing.expect(t, terminal_service_test_contains(state, "first"))
    testing.expect(t, terminal_service_test_contains(state, "second"))
    testing.expect(t, !state^.terminal.awaiting_eval)
    terminalview.terminal_destroy(&state^.terminal)
}

// Verify only a current ambiguous completion may append its candidate table.
@(test)
terminal_service_test_completion_candidate_freshness :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 16)
    defer core.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    testing.expect(t, termhist.termhist_insert_text(state^.terminal.history, "pri"))
    request := terminalview.terminal_request_completion(&state^.terminal)
    result := core.Julia_Host_Egress(protocol.Completion_Result{
        request_id = request.request_id,
        animation_generation = 16,
        found = false,
        insertion = "print  println\n",
        show_candidates = true,
    })
    testing.expect(t, terminal_service_dispatch_completion_result(state, &result))
    testing.expect(t, terminal_service_test_contains(state, "print  println"))

    stale_request := terminalview.terminal_request_completion(&state^.terminal)
    stale := core.Julia_Host_Egress(protocol.Completion_Result{
        request_id = stale_request.request_id,
        animation_generation = 15,
        found = false,
        insertion = "stale candidate\n",
        show_candidates = true,
    })
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &stale))
    testing.expect(t, !terminal_service_test_contains(state, "stale candidate"))
    terminalview.terminal_destroy(&state^.terminal)
}

// Verify late terminal egress cannot mutate a replacement animation generation.
@(test)
terminal_service_test_rejects_stale_generation_egress :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 20)
    defer core.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    terminalview.terminal_destroy(&state^.terminal)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &state^.animation_memory, 21), core.Animation_Memory_Status.Ok)
    testing.expect(t, terminal_service_enter(state))

    stale := protocol.Terminal_Output_Batch{
        request_id = 1,
        animation_generation = 20,
        bytes = "stale output\n",
    }
    testing.expect_value(t, bridge.send_terminal_output(
        state^.julia_runtime_service, stale), core.Communication_Send_Outcome.Sent)
    _, received_event := bridge.try_route_julia_egress(
        state^.julia_runtime_service)
    testing.expect(t, !received_event)
    testing.expect(t, !terminal_service_test_contains(state, "stale output"))
    terminalview.terminal_destroy(&state^.terminal)
}

// Verify display dispatch accepts current fixed responses and rejects stale families.
@(test)
terminal_service_test_dispatches_fixed_response_families :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: core.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 30)
    defer core.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    testing.expect(t, terminalview.terminal_begin_eval(&state^.terminal, "read()"))
    request_id := state^.terminal.pending_eval_request_id
    state^.terminal.geometry.generation = 4
    geometry := state^.terminal.geometry

    messages := [5]core.Julia_Host_Egress{
        protocol.Terminal_Input_Acquired{
            request_id = request_id, animation_generation = 30},
        protocol.Terminal_Input_Released{
            request_id = request_id, animation_generation = 30},
        protocol.Terminal_Geometry_Observed{
            animation_generation = 30, geometry = geometry},
        protocol.Terminal_Capabilities_Observed{
            animation_generation = 30,
            capabilities = terminalview.TERMINAL_CAPABILITIES},
        protocol.Terminal_Session_Ready{
            animation_generation = 30, banner = "Julia Version test\n"},
    }
    for &message in messages {
        testing.expect(t, terminal_service_dispatch_egress(state, &message))
    }
    testing.expect_value(t, state^.terminal.interactive_input_request_id,
        protocol.Request_Id(0))
    testing.expect_value(t, state^.terminal.julia_geometry_generation, u64(4))
    testing.expect(t, state^.terminal.julia_capabilities_observed)

    stale := core.Julia_Host_Egress(protocol.Terminal_Session_Stopped{
        animation_generation = 29})
    testing.expect(t, !terminal_service_dispatch_egress(state, &stale))
    terminalview.terminal_destroy(&state^.terminal)
}