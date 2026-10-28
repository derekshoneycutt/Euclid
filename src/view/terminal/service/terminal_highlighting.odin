package terminalservice

import core "../../../core"
import protocol "../../../core/protocol"
import historyruntime "../../../terminal/history/runtime"
import bridgemodel "../../../bridge/model"
import julia "../../../bridge"
import terminalview ".."
import uiterminal "../../ui/terminal"
import evidence_session "../../../evidence/session"
import trace "../../../evidence/trace"
import "core:log"

// Route borrowed outcomes through display validation before bridge storage is returned.
terminal_highlight_dispatch :: proc(
    state: ^core.Euclid_General_State,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Highlight_Result:
        stale := true
        if state.terminal.highlighting != nil {
            slot := terminalview.terminal_highlight_pending_slot(
                &state.terminal, payload.identity)
            stale = slot == nil || !terminalview.terminal_highlight_slot_current(
                &state.terminal, slot)
        }
        accepted := terminalview.terminal_highlight_publish(&state.terminal, payload)
        terminal_highlight_record_result(state, payload, accepted, stale)
        return accepted
    case protocol.Highlight_Failed:
        accepted := terminalview.terminal_highlight_fail(&state.terminal, payload)
        terminal_highlight_record_outcome(state, payload.identity,
            .Terminal_Highlight_Failed if accepted else .Terminal_Highlight_Discarded,
            {.Required, .Failure} if accepted else {.Required, .Stale},
            {
                request = {
                    reason = u16(payload.reason),
                },
            })
        return accepted
    }
    return false
}

// Issue at most one bounded snapshot per visible frame, prioritizing debounced live text.
terminal_highlight_service_update :: proc(
    state: ^core.Euclid_General_State,
    prepared: uiterminal.Terminal_Prepared_Frame, now: f64) {
    term := &state.terminal
    terminalview.terminal_highlight_observe_live(term, now)
    if prepared.available && prepared.layout.line_height > 0 {
        first := int(prepared.scroll.scroll_y_out / prepared.layout.line_height)
        count := int(prepared.scroll.view_rect.height / prepared.layout.line_height) + 2
        terminalview.terminal_highlight_observe_history(term, first, first + count)
    }
    terminal_highlight_schedule_source_read(state)
    request, ready := terminalview.terminal_highlight_take_request(term, now)
    if !ready {
        return
    }
    outcome := julia.send_terminal_highlight_request(state.julia_runtime_service, request)
    if outcome != .Sent {
        failure := bridgemodel.Julia_Host_Egress(protocol.Highlight_Failed{
            identity = request.identity,
            reason = .Transport_Capacity,
        })
        _ = terminal_highlight_dispatch(state, &failure)
    }
}

// Queue one speculative keyed source lookup after interactive recall admission.
terminal_highlight_schedule_source_read :: proc(state: ^core.Euclid_General_State) {
    history := &state.terminal_history_runtime
    term := &state.terminal
    if history^.status != .Ready {
        return
    }
    source_request, ready :=
        terminalview.terminal_highlight_source_request_next(term)
    if !ready {
        return
    }
    id := source_request.submission_id
    revision := source_request.source_revision
    term^.history_source_request_id += 1
    if term^.history_source_request_id == 0 {
        term^.history_source_request_id = 1
    }
    request: historyruntime.History_Read_Request = {
        kind = .By_Id,
        priority = .Speculative,
        target = .Highlighting,
        submission_id = id,
        request_id = term^.history_source_request_id,
        terminal_generation = term^.animation_generation,
        source_revision = revision,
        face_generation = term^.highlighting.face_generation,
    }
    if terminalview.history_runtime_request_read(history, request) {
        _ = terminalview.terminal_highlight_source_fetch_begin(
            term, id, revision, request.request_id)
        term^.history_source_admission_reported = false
    } else if !term^.history_source_admission_reported {
        log.warn("terminal_history_highlight_delayed reason=request_admission")
        term^.history_source_admission_reported = true
    }
}

// Distinguish exact accepted source from stale replies and malformed current publications.
terminal_highlight_record_result :: proc(
    state: ^core.Euclid_General_State, result: protocol.Highlight_Result,
    accepted, stale: bool) {
    kind: trace.Kind = .Terminal_Highlight_Discarded
    flags: trace.Flags = {.Required}
    if accepted {
        kind = .Terminal_Live_Highlight_Published if
            result.identity.target_kind == .Live_Input else
                .Terminal_History_Highlight_Published
    } else if stale {
        flags += {.Stale}
    } else {
        flags += {.Failure}
    }
    terminal_highlight_record_outcome(state, result.identity, kind, flags, {
        counts = {
            u32(len(result.source)),
            u32(len(result.runs)),
        },
    } if accepted else {})
}

// Record display-owned outcomes without source bytes or borrowed transport storage.
terminal_highlight_record_outcome :: proc(
    state: ^core.Euclid_General_State, identity: protocol.Highlight_Identity,
    kind: trace.Kind, flags: trace.Flags, payload: trace.Event_Payload) {
    _ = evidence_session.session_record(&state.evidence_session, &state.evidence_ring, {
        lane = .Presentation,
        kind = kind,
        flags = flags,
        correlation_kind = .Terminal_Highlight,
        correlation = u64(identity.request_id),
        generation = identity.animation_generation,
        revision = identity.source_revision,
        tick = state.fixed_step,
        payload = payload,
    })
}
