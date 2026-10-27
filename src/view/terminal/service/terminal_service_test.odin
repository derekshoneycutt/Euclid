package terminalservice

import viewterminalmodel "../model"
import bridgemodel "../../../bridge/model"
import animation_model "../../../core/animation"
import runtime "base:runtime"
import bridge "../../../bridge"
import core "../../../core"
import protocol "../../../core/protocol"
import historyruntime "../../../terminal/history/runtime"
import termhist "../../../terminal/history"
import termhiststore "../../../terminal/history/store"
import input "../../input"
import terminalview ".."
import strings "core:strings"
import testing "core:testing"
import time "core:time"
import uiterminal "../../ui/terminal"

when ODIN_OS != .Linux {
    _ :: viewterminalmodel
}

Terminal_Service_Test_History_Result :: struct {
    outcome: termhiststore.History_Read_Outcome,
    submission_id: u64,
    mode: protocol.Evaluation_Mode,
    source: string,
}

// Do not retain standalone whitespace submissions or discard blank continuations.
@(test)
terminal_service_test_history_skips_empty_standalone_input :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    terminal_service_record_history(state, {
        text = "",
        submitted = true,
    })
    terminal_service_record_history(state, {
        text = " \t\n",
        submitted = true,
    })
    testing.expect_value(t, state^.terminal_history_runtime.next_submission_id, u64(0))
    testing.expect_value(t, state^.terminal_history_runtime.mutation_count, 0)
    state^.terminal_history_runtime.status = .Ready
    state^.terminal.provisional_submission_id = 1
    state^.terminal.provisional_desired_revision = 1
    terminal_service_record_history(state, {
        text = "",
        continuation = true,
        submitted = true,
    })
    testing.expect_value(t, state^.terminal_history_runtime.mutation_count, 1)
    testing.expect_value(
        t, state^.terminal_history_runtime.queued_mutations[0].kind,
        historyruntime.History_Mutation_Kind.Update)
}



// Dispatch one test envelope through the same display-owned Terminal path as production.
terminal_service_test_route_egress :: proc(
    user_data: rawptr, message: ^bridgemodel.Julia_Host_Egress) -> bool {
    state := cast(^core.Euclid_General_State)user_data
    _ = terminal_service_dispatch_egress(state, message)
    return false
}

// Initialize one link-only Julia service without starting or entering libjulia.
terminal_service_test_runtime_init :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
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
    bridge.destroy_julia_runtime_channels(service)
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
    t: ^testing.T, service: ^bridgemodel.Julia_Runtime_Service,
    request: protocol.Evaluation_Requested) {
    first: protocol.Terminal_Output_Batch = {
        request_id = request.request_id,
        animation_generation = request.animation_generation,
        bytes = "first\n",
    }
    second := first
    second.bytes = "second\n"
    testing.expect_value(t, bridge.send_terminal_output(service, first),
        bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, bridge.send_terminal_output(service, second),
        bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, bridge.send_terminal_egress(service,
        protocol.Evaluation_Completed{
            request_id = request.request_id,
            animation_generation = request.animation_generation,
            succeeded = true,
        }), bridgemodel.Communication_Send_Outcome.Sent)
}

// Initialize the animation arena and selected Terminal descriptor for service tests.
terminal_service_test_state_init :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface, generation: u64) {
    testing.expect(t, animation_model.animation_memory_init(&state^.animation_memory))
    testing.expect_value(t, animation_model.animation_memory_begin_generation(
        &state^.animation_memory, generation), animation_model.Animation_Memory_Status.Ok)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = animation
    state^.julia_interface^.current_animation = animation
    animation^.name = "Terminal"
}

// Verify recording IDs and revision dependencies survive a pending TEMP initialization.
@(test)
terminal_service_test_history_mutations_keep_submission_identity :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal.animation_generation = 12
    state^.terminal_history_runtime.status = .Uninitialized
    terminal_service_record_history(state, {
        text = "begin",
        mode = .Normal,
        submitted = true,
    })
    terminal_service_record_history(state, {
        text = "begin\n    end",
        mode = .Normal,
        continuation = true,
        submitted = true,
    })
    runtime := &state^.terminal_history_runtime
    testing.expect_value(t, runtime^.mutation_count, 2)
    first := runtime^.queued_mutations[runtime^.mutation_head]
    second := runtime^.queued_mutations[(runtime^.mutation_head + 1) %
        len(runtime^.queued_mutations)]
    testing.expect_value(t, first.record.submission_id, u64(1))
    testing.expect_value(t, first.record.source_revision, u64(1))
    testing.expect_value(t, string(runtime^.queued_sources[runtime^.mutation_head][:5]),
        "begin")
    testing.expect_value(t, second.update.submission_id, u64(1))
    testing.expect_value(t, second.update.expected_revision, u64(1))
    testing.expect_value(t, second.update.new_revision, u64(2))
    testing.expect_value(t, second.source_length, len("begin\n    end"))
    testing.expect_value(t, state^.terminal.provisional_desired_revision, u64(2))
    testing.expect(t, state^.terminal.provisional_recording_valid)
}

// Verify delayed recall applies source/mode atomically and Down restores the full draft.
@(test)
terminal_service_test_history_recall_validates_and_restores_draft :: proc(
    t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 21)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminalview.terminal_init_for_animation(
        &state^.terminal, &state^.animation_memory, 21))
    defer terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    terminal_service_test_history_reject_stale_edit(t, state)
    terminal_service_test_history_apply_and_restore(t, state)
}

// Restore the mode and cursor when recalling a durable-only history record.
@(test)
terminal_service_test_persistent_history_recall_restores_mode :: proc(
    t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 22)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminalview.terminal_init_for_animation(
        &state^.terminal, &state^.animation_memory, 22))
    defer terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    source := "saved source"
    copy(state^.terminal.history_navigation_read_source[:], transmute([]u8)source)
    terminal_service_apply_history_record(&state^.terminal, {
        ready = true,
        result = {
            outcome = termhiststore.History_Read_Outcome.Found,
            record = {
                scope = termhiststore.History_Record_Scope.Persistent,
                source_id = 17,
                mode = protocol.Evaluation_Mode.Shell,
                submitted_at_unix_ms = 42,
                source_revision = 3,
            },
            source_length = len(source),
        },
    })
    testing.expect_value(t,
        termhist.termhist_current_text(state^.terminal.history), source)
    testing.expect_value(t, state^.terminal.input_mode,
        protocol.Evaluation_Mode.Shell)
    testing.expect_value(t, state^.terminal.history_navigation_anchor_id, u64(0))
    testing.expect(t, state^.terminal.history_navigation_cursor_valid)
    testing.expect_value(t,
        state^.terminal.history_navigation_cursor.scope,
        termhiststore.History_Record_Scope.Persistent)
    testing.expect_value(t,
        state^.terminal.history_navigation_cursor.source_id, u64(17))
}

// Reject a delayed result after editing and retain the new source and prompt mode.
terminal_service_test_history_reject_stale_edit :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    term := &state^.terminal
    term^.banner_ready = true
    term^.input_mode = .Help
    termhist.termhist_insert_text(term^.history, "draft")
    _ = termhist.termhist_move_left(term^.history)
    _ = termhist.termhist_move_left(term^.history, true)
    runtime := &state^.terminal_history_runtime
    runtime^.status = .Ready
    runtime^.terminal_generation = 21
    runtime^.next_submission_id = 1
    request := terminal_service_test_history_request(
        t, state, .Up, .Older, 2)
    terminal_service_test_history_result(state, request, {
        outcome = .Found,
        submission_id = 1,
        mode = .Pkg,
        source = "prior",
    })
    _ = terminalview.terminal_update_keyboard_event(term, {
        kind = .Text,
        codepoint = '!',
    }, "")
    terminal_service_consume_history_read(state)
    testing.expect_value(t, termhist.termhist_current_text(term^.history), "dra!t")
    testing.expect_value(t, term^.input_mode, protocol.Evaluation_Mode.Help)
    testing.expect_value(t, term^.history_navigation_anchor_id, u64(0))
}

// Apply a current result, then restore source, selection, preferred column, and mode.
terminal_service_test_history_apply_and_restore :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    term := &state^.terminal
    cursor := termhist.termhist_cursor(term^.history)
    anchor := termhist.termhist_anchor(term^.history)
    preferred := term^.history.preferred_column
    term^.history_navigation_draft_mode = .Help
    term^.input_mode = .Help
    state^.terminal_history_runtime.next_submission_id = 2
    terminal_service_test_history_browse_older(t, state)
    terminal_service_test_history_browse_newer(t, state)
    testing.expect_value(t, termhist.termhist_current_text(term^.history), "dra!t")
    testing.expect_value(t, termhist.termhist_cursor(term^.history), cursor)
    testing.expect_value(t, termhist.termhist_anchor(term^.history), anchor)
    testing.expect_value(t, term^.history.preferred_column, preferred)
    testing.expect_value(t, term^.input_mode, protocol.Evaluation_Mode.Help)
}

// Verify Up traverses older records and clamps at the oldest without wrapping.
terminal_service_test_history_browse_older :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    term := &state^.terminal
    request := terminal_service_test_history_request(
        t, state, .Up, .Older, 3)
    terminal_service_test_history_release_and_complete(t, state, request, .Up, {
        outcome = .Found,
        submission_id = 2,
        mode = .Pkg,
        source = "newer\nline",
    })
    terminal_service_consume_history_read(state)
    testing.expect_value(
        t, termhist.termhist_current_text(term^.history), "newer\nline")
    testing.expect_value(t, term^.input_mode, protocol.Evaluation_Mode.Pkg)
    request = terminal_service_test_history_request(
        t, state, .Up, .Older, 2)
    terminal_service_test_history_release_and_complete(t, state, request, .Up, {
        outcome = .Found,
        submission_id = 1,
        mode = .Normal,
        source = "prior",
    })
    terminal_service_consume_history_read(state)
    testing.expect_value(t, termhist.termhist_current_text(term^.history), "prior")
    testing.expect_value(t, term^.history_navigation_anchor_id, u64(1))
    request = terminal_service_test_history_request(
        t, state, .Up, .Older, 1)
    terminal_service_test_history_release_and_complete(t, state, request, .Up, {
        outcome = .Boundary,
    })
    terminal_service_consume_history_read(state)
    testing.expect_value(t, termhist.termhist_current_text(term^.history), "prior")
    testing.expect_value(t, term^.history_navigation_anchor_id, u64(1))
}

// Verify Down returns through newer records and restores the original draft at the tail.
terminal_service_test_history_browse_newer :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    term := &state^.terminal
    request := terminal_service_test_history_request(
        t, state, .Down, .Newer, 1)
    terminal_service_test_history_release_and_complete(t, state, request, .Down, {
        outcome = .Found,
        submission_id = 2,
        mode = .Pkg,
        source = "newer\nline",
    })
    terminal_service_consume_history_read(state)
    testing.expect_value(
        t, termhist.termhist_current_text(term^.history), "newer\nline")
    testing.expect_value(t, term^.history_navigation_anchor_id, u64(2))
    request = terminal_service_test_history_request(
        t, state, .Down, .Newer, 2)
    terminal_service_test_history_release_and_complete(t, state, request, .Down, {
        outcome = .Boundary,
    })
    terminal_service_consume_history_read(state)
    testing.expect(t, !term^.history_navigation_active)
    testing.expect_value(t, term^.history_navigation_anchor_id, u64(0))
}

// Deliver a navigation key's release before its asynchronous read completion.
terminal_service_test_history_release_and_complete :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: historyruntime.History_Read_Request, key: input.Input_Key,
    result: Terminal_Service_Test_History_Result) {
    _ = terminalview.terminal_update_keyboard_event(&state^.terminal, {
        kind = .Release,
        key = key,
    }, "")
    terminal_service_test_history_result(state, request, result)
}

// Issue one key and return the queued request with its expected stable anchor.
terminal_service_test_history_request :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    key: input.Input_Key, kind: historyruntime.History_Read_Kind,
    anchor: u64) -> historyruntime.History_Read_Request {
    _ = terminalview.terminal_update_keyboard_event(&state^.terminal, {
        kind = .Press,
        key = key,
    }, "")
    terminal_service_schedule_history_read(state)
    runtime := &state^.terminal_history_runtime
    request := runtime^.interactive_reads[0]
    testing.expect_value(t, request.kind, kind)
    testing.expect_value(t, request.submission_id, anchor)
    runtime^.interactive_read_count = 0
    return request
}

// Publish one synthetic joined history result through the runtime-owned result slot.
terminal_service_test_history_result :: proc(
    state: ^core.Euclid_General_State,
    request: historyruntime.History_Read_Request,
    result: Terminal_Service_Test_History_Result) {
    runtime := &state^.terminal_history_runtime
    runtime^.read_result_request = request
    runtime^.read_result = {
        outcome = result.outcome,
        record = {
            submission_id = result.submission_id,
            mode = result.mode,
            source_revision = 1,
        },
        source_length = len(result.source),
    }
    copy(runtime^.read_result_source[:], transmute([]u8)result.source)
    runtime^.read_result_ready = true
}

// Report whether any retained terminal output row contains the requested text.
terminal_service_test_contains :: proc(
    state: ^core.Euclid_General_State, text: string) -> bool {
    for line in 0..<uiterminal.terminal_line_count(&state^.terminal) {
        if strings.contains(uiterminal.terminal_line_text(&state^.terminal, line), text) {
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
        storage[count] = {
            kind = .Text,
            codepoint = rune(byte),
        }
        count += 1
    }
    storage[count] = {
        kind = .Press,
        key = .Enter,
    }
    count += 1
    return {
        events = storage[:count],
        window_focused = true,
    }
}

// Verify literal shell submissions use a real PTY and can launch repeatedly.
@(test)
terminal_service_test_real_pty_lifecycle :: proc(t: ^testing.T) {
    when ODIN_OS == .Linux {
        state := new(core.Euclid_General_State, context.allocator)
        defer free(state, context.allocator)
        animation: bridgemodel.Euclid_Julia_Animation_Interface
        terminal_service_test_state_init(t, state, &animation, 1)
        defer animation_model.animation_memory_destroy(&state^.animation_memory)
        testing.expect(t, terminalview.terminal_init_for_animation(
            &state^.terminal, &state^.animation_memory, 1))
        defer terminalview.terminal_destroy(&state^.terminal,
            animation_model.animation_memory_allocator(&state^.animation_memory))
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
        testing.expect_value(t, state^.shell.phase,
            viewterminalmodel.Shell_Launch_Phase.Running)
        events: [64]input.Input_Event
        frame := terminal_service_test_command_frame(
            events[:], "printf interactive-ok; exit")
        shell_service_update(state, &runtime, frame)
        testing.expect(t, terminal_service_test_wait_for_shell(state, &runtime))
        testing.expect(t, terminal_service_test_contains(state, "interactive-ok"))
    }
}

// Verify a hidden selected Terminal drains PTY output without resetting its generation.
@(test)
terminal_service_test_hidden_view_preserves_session_and_output :: proc(t: ^testing.T) {
    when ODIN_OS == .Linux {
        state := new(core.Euclid_General_State, context.allocator)
        defer free(state, context.allocator)
        animation: bridgemodel.Euclid_Julia_Animation_Interface
        terminal_service_test_state_init(t, state, &animation, 2)
        defer animation_model.animation_memory_destroy(&state^.animation_memory)
        testing.expect(t, terminalview.terminal_init_for_animation(
            &state^.terminal, &state^.animation_memory, 2))
        defer terminalview.terminal_destroy(&state^.terminal,
            animation_model.animation_memory_allocator(&state^.animation_memory))
        testing.expect(t, shell_service_runtime_init(state))
        defer shell_service_runtime_destroy(state)
        terminalview.terminal_append_ansi_output(&state^.terminal, "before-hide\n")

        testing.expect(t, shell_service_submit(
            state, "/bin/printf output-while-hidden"))
        deadline := time.tick_since({}) + 5 * time.Second
        for state^.shell.phase != .Inactive && time.tick_since({}) < deadline {
            _ = terminal_service_update(state, nil, {})
        }

        testing.expect_value(t, state^.shell.phase,
            viewterminalmodel.Shell_Launch_Phase.Inactive)
        testing.expect(t, state^.terminal.initialized)
        testing.expect_value(t, state^.terminal.animation_generation, u64(2))
        testing.expect(t, terminal_service_test_contains(state, "before-hide"))
        testing.expect(t, terminal_service_test_contains(
            state, "output-while-hidden"))
    }
}

// Verify requested selection cannot activate Terminal before the switch commits.
@(test)
terminal_service_test_selection_identity :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    previous: bridgemodel.Euclid_Julia_Animation_Interface
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
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 4)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
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
        }), bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, terminal_service_test_dispatch_egress(t, state), 1)
    testing.expect(t, terminal_service_test_contains(state, "Julia Version test"))
    testing.expect(t, !terminal_service_test_contains(state, "Euclid Terminal"))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// Verify animation reset retirement permits pristine entry in the next generation.
@(test)
terminal_service_test_generation_reentry_is_pristine :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 7)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    terminalview.terminal_append_ansi_output(
        &state^.terminal, "old generation\n")

    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    testing.expect_value(t, animation_model.animation_memory_begin_generation(
        &state^.animation_memory, 8), animation_model.Animation_Memory_Status.Ok)
    testing.expect(t, terminal_service_enter(state))
    testing.expect_value(t, state^.terminal.animation_generation, u64(8))
    testing.expect(t, !terminal_service_test_contains(state, "old generation"))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// Verify typed transport applies ordered output and completion without entering Julia.
@(test)
terminal_service_test_typed_evaluation_round_trip :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 12)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
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
        bridgemodel.Communication_Send_Outcome.Sent)

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
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// Verify history admission failure cannot block or duplicate evaluation acceptance.
@(test)
terminal_service_test_history_failure_does_not_block_evaluation :: proc(
    t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 13)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    state^.terminal_history_runtime.status = .Unavailable
    testing.expect(t, terminal_service_enter(state))
    started, started_received := bridge.communication_link_try_recv(
        &state^.julia_runtime_service^.request_link)
    testing.expect(t, started_received)
    testing.expect(t, bridge.communication_link_return(
        &state^.julia_runtime_service^.request_link, started))
    testing.expect(t, terminal_service_test_contains(
        state, "History recall unavailable"))
    state^.terminal.julia_session_ready = true
    terminal_service_apply_submission(state, {
        text = "accepted once",
        mode = .Normal,
        submitted = true,
    })
    testing.expect(t, state^.terminal.awaiting_eval)
    testing.expect(t, !state^.terminal.provisional_recording_valid)
    ingress, received := bridge.communication_link_try_recv(
        &state^.julia_runtime_service^.request_link)
    testing.expect(t, received)
    request, is_request := ingress^.(protocol.Evaluation_Requested)
    testing.expect(t, is_request)
    testing.expect_value(t, request.code, "accepted once")
    testing.expect(t, bridge.communication_link_return(
        &state^.julia_runtime_service^.request_link, ingress))
    terminalview.terminal_complete_eval(&state^.terminal)
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// A failed continuation revision invalidates anchors after a newer submit is active.
@(test)
terminal_service_test_old_history_failure_invalidates_revision :: proc(
    t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    term := &state^.terminal
    testing.expect(t, terminalview.terminal_init_with_allocator(
        term, context.allocator, 1))
    defer terminalview.terminal_destroy(term, context.allocator)
    term.provisional_submission_id = 2
    term.highlighting.history[0] = {
        id = 1,
        source_revision = 2,
        terminal_generation = 1,
    }
    history := &state^.terminal_history_runtime
    history^.write_completion_serial = 1
    history^.last_completed_mutation = {
        kind = .Update,
        update = {
            submission_id = 1,
            new_revision = 2,
        },
    }
    history^.last_write_result.outcome =
        termhiststore.History_Write_Outcome.Conflict
    terminal_service_consume_history_write(state)
    testing.expect(t,
        terminalview.terminal_highlight_history_find(term, 1, 2) == nil)
}

// Verify only a current ambiguous completion may append its candidate table.
@(test)
terminal_service_test_completion_candidate_freshness :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 16)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    testing.expect(t, termhist.termhist_insert_text(state^.terminal.history, "pri"))
    request := terminalview.terminal_request_completion(&state^.terminal)
    result := bridgemodel.Julia_Host_Egress(protocol.Completion_Result{
        request_id = request.request_id,
        animation_generation = 16,
        found = false,
        insertion = "print  println\n",
        show_candidates = true,
    })
    testing.expect(t, terminal_service_dispatch_completion_result(state, &result))
    testing.expect(t, terminal_service_test_contains(state, "print  println"))

    stale_request := terminalview.terminal_request_completion(&state^.terminal)
    stale := bridgemodel.Julia_Host_Egress(protocol.Completion_Result{
        request_id = stale_request.request_id,
        animation_generation = 15,
        found = false,
        insertion = "stale candidate\n",
        show_candidates = true,
    })
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &stale))
    testing.expect(t, !terminal_service_test_contains(state, "stale candidate"))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// Background common prefixes remain previews; explicit Tab commits the same result once.
@(test)
terminal_service_test_common_prefix_tab :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 17)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    defer terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    term := &state^.terminal
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    request := terminalview.terminal_request_completion(term, false)
    result := bridgemodel.Julia_Host_Egress(protocol.Completion_Result{
        request_id = request.request_id,
        animation_generation = 17,
        found = true,
        replacement_end = 4,
        insertion = "function",
    })
    testing.expect(t, terminal_service_dispatch_completion_result(state, &result))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "func")
    testing.expect_value(t, term.completion_preview_insertion, "function")
    request = terminalview.terminal_request_completion(term, true)
    result = protocol.Completion_Result{
        request_id = request.request_id,
        animation_generation = 17,
        found = true,
        replacement_end = 4,
        insertion = "function",
        show_candidates = true,
    }
    testing.expect(t, terminal_service_dispatch_completion_result(state, &result))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "function")
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &result))
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "func")
    testing.expect(t, termhist.termhist_redo(term.history))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "function")
}

// Late explicit results and failures cannot change a newer draft or request.
@(test)
terminal_service_test_explicit_completion_stale :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 18)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    defer terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    term := &state^.terminal
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    request := terminalview.terminal_request_completion(term, true)
    testing.expect(t, termhist.termhist_insert_text(term.history, "x"))
    result := bridgemodel.Julia_Host_Egress(protocol.Completion_Result{
        request_id = request.request_id,
        animation_generation = 18,
        found = true,
        replacement_end = 4,
        insertion = "function",
        show_candidates = true,
    })
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &result))
    current := terminalview.terminal_request_completion(term, false)
    result = protocol.Completion_Failed{
        request_id = request.request_id,
        animation_generation = 18,
        reason = .Internal_Failure,
    }
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &result))
    testing.expect_value(t, term.pending_completion_request_id, current.request_id)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "funcx")
}

// Matching provider and ingress failures retire visibly without changing the draft.
@(test)
terminal_service_test_completion_failures :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 19)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    defer terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    term := &state^.terminal
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    request := terminalview.terminal_request_completion(term, true)
    failure := bridgemodel.Julia_Host_Egress(protocol.Completion_Failed{
        request_id = request.request_id,
        animation_generation = 19,
        reason = .Internal_Failure,
    })
    testing.expect(t, terminal_service_dispatch_completion_result(state, &failure))
    testing.expect_value(t, term.pending_completion_request_id, 0)
    testing.expect(t, !terminal_service_dispatch_completion_result(state, &failure))
    request = terminalview.terminal_request_completion(term, true)
    state^.julia_runtime_service.lifecycle = .Shutdown_Requested
    terminal_service_send_completion(state, request)
    testing.expect_value(t, term.pending_completion_request_id, 0)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "func")
    testing.expect(t, terminal_service_test_contains(state, "Terminal completion unavailable"))
}

// Verify late terminal egress cannot mutate a replacement animation generation.
@(test)
terminal_service_test_rejects_stale_generation_egress :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 20)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    testing.expect(t, terminal_service_enter(state))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    testing.expect_value(t, animation_model.animation_memory_begin_generation(
        &state^.animation_memory, 21), animation_model.Animation_Memory_Status.Ok)
    testing.expect(t, terminal_service_enter(state))

    stale: protocol.Terminal_Output_Batch = {
        request_id = 1,
        animation_generation = 20,
        bytes = "stale output\n",
    }
    testing.expect_value(t, bridge.send_terminal_output(
        state^.julia_runtime_service, stale), bridgemodel.Communication_Send_Outcome.Sent)
    _, received_event := bridge.try_route_julia_egress(
        state^.julia_runtime_service)
    testing.expect(t, !received_event)
    testing.expect(t, !terminal_service_test_contains(state, "stale output"))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}

// Verify display dispatch accepts current fixed responses and rejects stale families.
@(test)
terminal_service_test_dispatches_fixed_response_families :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    terminal_service_test_state_init(t, state, &animation, 30)
    defer animation_model.animation_memory_destroy(&state^.animation_memory)
    testing.expect(t, terminal_service_enter(state))
    testing.expect(t, terminalview.terminal_begin_eval(&state^.terminal, "read()"))
    request_id := state^.terminal.pending_eval_request_id
    state^.terminal.geometry.generation = 4
    geometry := state^.terminal.geometry

    messages: [5]bridgemodel.Julia_Host_Egress = {
        protocol.Terminal_Input_Acquired{
            request_id = request_id,
            animation_generation = 30,
        },
        protocol.Terminal_Input_Released{
            request_id = request_id,
            animation_generation = 30,
        },
        protocol.Terminal_Geometry_Observed{
            animation_generation = 30,
            geometry = geometry,
        },
        protocol.Terminal_Capabilities_Observed{
            animation_generation = 30,
            capabilities = terminalview.TERMINAL_CAPABILITIES,
        },
        protocol.Terminal_Session_Ready{
            animation_generation = 30,
            banner = "Julia Version test\n",
        },
    }
    for &message in messages {
        testing.expect(t, terminal_service_dispatch_egress(state, &message))
    }
    testing.expect_value(t, state^.terminal.interactive_input_request_id,
        protocol.Request_Id(0))
    testing.expect_value(t, state^.terminal.julia_geometry_generation, u64(4))
    testing.expect(t, state^.terminal.julia_capabilities_observed)

    stale := bridgemodel.Julia_Host_Egress(protocol.Terminal_Session_Stopped{
        animation_generation = 29,
    })
    testing.expect(t, !terminal_service_dispatch_egress(state, &stale))
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
}
