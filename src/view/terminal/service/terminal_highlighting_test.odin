package terminalservice

import bridgemodel "../../../bridge/model"
import bridge "../../../bridge"
import core "../../../core"
import protocol "../../../core/protocol"
import termhist "../../../terminal/history"
import terminalview ".."
import uiterminal "../../ui/terminal"
import evidence_session "../../../evidence/session"
import trace "../../../evidence/trace"
import "core:testing"

// Transport admission failure records an outcome without dropping safe prompt decoration.
@(test)
terminal_service_test_highlight_failure_preserves_presentation :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    term := &state.terminal
    testing.expect(t, terminalview.terminal_init_with_allocator(
        term, context.allocator, 1))
    defer terminalview.terminal_destroy(term, context.allocator)
    term.banner_ready = true
    term.julia_session_ready = true
    testing.expect(t, termhist.termhist_insert_text(term.history, "ab"))
    terminalview.terminal_highlight_observe_live(term, 0)
    request, ready := terminalview.terminal_highlight_take_request(term, 1)
    testing.expect(t, ready)
    runs := [1]protocol.Highlight_Run{{end_byte = 2, weight = .Bold}}
    testing.expect(t, terminalview.terminal_highlight_publish(term,
        {request.identity, request.source, runs[:]}))
    testing.expect(t, termhist.termhist_insert_text(term.history, "X"))
    terminal_highlight_service_update(state, {}, 2)
    terminal_highlight_service_update(state, {}, 3)
    mapped := terminalview.terminal_live_highlight_runs(term)
    testing.expect_value(t, len(mapped), 2)
    testing.expect_value(t, mapped[0].weight, protocol.Highlight_Weight.Bold)
    testing.expect_value(t, mapped[0].end_byte, u32(2))
    testing.expect_value(t, mapped[1].weight, protocol.Highlight_Weight.Normal)
    testing.expect_value(t, term.highlighting.failure_count, u64(1))
}

// Round-trip actual producer-owned envelopes and return them before reading retained runs.
@(test)
terminal_service_test_highlight_transport_publication :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    state.evidence_session.enabled = true
    state.evidence_session.lanes = evidence_session.ALL_LANES
    trace.ring_init(&state.evidence_ring, .Display)
    term := &state.terminal
    term.banner_ready = true
    term.julia_session_ready = true
    termhist.termhist_insert_text(term.history, "α")
    terminal_highlight_service_update(state, {}, 0)
    terminal_highlight_service_update(state, {}, 1)
    envelope, received := bridge.communication_link_try_recv(
        &state.julia_runtime_service.request_link)
    testing.expect(t, received && envelope != nil)
    request, typed := envelope^.(protocol.Highlight_Requested)
    testing.expect(t, typed && request.source == "α")
    runs := [1]protocol.Highlight_Run{{end_byte = 2, weight = .Bold}}
    testing.expect_value(t, bridge.send_terminal_highlight_result(
        state.julia_runtime_service, {request.identity, request.source, runs[:]}),
        bridgemodel.Communication_Send_Outcome.Sent)
    bridge.communication_link_return(&state.julia_runtime_service.request_link, envelope)
    testing.expect_value(t, terminal_service_test_dispatch_egress(t, state), 1)
    _ = bridge.drain_julia_egress_returns(state.julia_runtime_service)
    _ = bridge.drain_julia_ingress_returns(state.julia_runtime_service)
    testing.expect_value(t, terminalview.terminal_live_highlight_runs(term)[0].weight,
        protocol.Highlight_Weight.Bold)
    terminal_service_test_highlight_publication(
        t, state.evidence_ring.events[0], request.identity)
}

// Accepted evidence retains the request identity and complete UTF-8 coverage counters.
terminal_service_test_highlight_publication :: proc(
    t: ^testing.T, event: trace.Event, identity: protocol.Highlight_Identity) {
    testing.expect_value(t, event.kind, trace.Kind.Terminal_Live_Highlight_Published)
    testing.expect_value(t, trace.event_identity(event),
        trace.Identity{.Terminal_Highlight, u64(identity.request_id),
            identity.animation_generation})
    testing.expect_value(t, event.revision, identity.source_revision)
    testing.expect_value(t, event.payload.counts, trace.Count_Payload{2, 1})
}

// Visible history is issued even while evaluation hides the live editor.
@(test)
terminal_service_test_highlight_history_during_evaluation :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    term := &state.terminal
    term.banner_ready = true
    term.julia_session_ready = true
    termhist.termhist_insert_text(term.history, "x = 1")
    source := terminalview.terminal_submit(term)
    testing.expect(t, terminalview.terminal_begin_eval(term, source))
    prepared := uiterminal.Terminal_Prepared_Frame{
        available = true, layout = {line_height = 20},
        scroll = {view_rect = {height = 200}},
    }
    terminal_highlight_service_update(state, prepared, 1)
    envelope, received := bridge.communication_link_try_recv(
        &state.julia_runtime_service.request_link)
    testing.expect(t, received && envelope != nil)
    request, typed := envelope^.(protocol.Highlight_Requested)
    testing.expect(t, typed && request.identity.target_kind == .History_Entry)
    failure := bridgemodel.Julia_Host_Egress(protocol.Highlight_Failed{
        request.identity, .Mailbox_Full})
    testing.expect(t, terminal_service_dispatch_egress(state, &failure))
    bridge.communication_link_return(&state.julia_runtime_service.request_link, envelope)
    terminal_highlight_service_update(state, prepared, 2)
    _, duplicate := bridge.communication_link_try_recv(
        &state.julia_runtime_service.request_link)
    testing.expect(t, !duplicate)
    testing.expect(t, term.awaiting_eval && term.history.history_len == 1)
}

// Stale, malformed, and failed replies remain distinct from publication in typed evidence.
@(test)
terminal_service_test_highlight_outcome_evidence :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    state.evidence_session.enabled = true
    state.evidence_session.lanes = evidence_session.ALL_LANES
    term := &state.terminal
    term.banner_ready = true
    term.julia_session_ready = true
    termhist.termhist_insert_text(term.history, "x")
    runs := [1]protocol.Highlight_Run{{end_byte = 1}}
    for outcome in 0..<3 {
        trace.ring_init(&state.evidence_ring, .Display)
        terminalview.terminal_highlight_invalidate(term)
        terminalview.terminal_highlight_observe_live(term, 0)
        request, ready := terminalview.terminal_highlight_take_request(term, 1)
        testing.expect(t, ready)
        if outcome == 0 {
            terminalview.terminal_highlight_set_face_generation(term, 2)
        }
        message := bridgemodel.Julia_Host_Egress(protocol.Highlight_Result{
            request.identity, "y" if outcome == 1 else request.source, runs[:]})
        if outcome == 2 {
            message = protocol.Highlight_Failed{request.identity, .Mailbox_Full}
        }
        _ = terminal_highlight_dispatch(state, &message)
        terminal_service_test_highlight_outcome(t, state.evidence_ring.events[0], outcome)
        testing.expect_value(t, len(terminalview.terminal_live_highlight_runs(term)), 0)
    }
}

// Check exact outcome kind and flags so rejection cannot masquerade as accepted source.
terminal_service_test_highlight_outcome :: proc(
    t: ^testing.T, event: trace.Event, outcome: int) {
    expected := trace.Kind.Terminal_Highlight_Failed if outcome == 2 else
        trace.Kind.Terminal_Highlight_Discarded
    testing.expect_value(t, event.kind, expected)
    testing.expect(t, .Required in event.flags)
    testing.expect_value(t, .Stale in event.flags, outcome == 0)
    testing.expect_value(t, .Failure in event.flags, outcome != 0)
    if outcome == 2 {
        testing.expect_value(t, event.payload.request.reason,
            u16(protocol.Highlight_Failure_Reason.Mailbox_Full))
    }
}
