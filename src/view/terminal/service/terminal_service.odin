package terminalservice

import bridgemodel "../../../bridge/model"
import core "../../../core"
import animation_model "../../../core/animation"
import protocol "../../../core/protocol"
import evidence_session "../../../evidence/session"
import historyruntime "../../../terminal/history/runtime"
import termhist "../../../terminal/history"
import termhiststore "../../../persistence/userdata/history"
import julia "../../../bridge"
import termsession "../../../terminal/session"
import font "../../font"
import input "../../input"
import native "../../native"
import terminalview ".."
import viewterminalmodel "../model"
import uiterminal "../../ui/terminal"
import uipresentation "../../ui/presentation"
import "core:log"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

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
        terminalview.terminal_destroy(&state^.terminal,
            animation_model.animation_memory_allocator(&state^.animation_memory))
        return false
    }
    if !terminal_graphics_bind_generation(state, generation) {
        termsession.terminal_session_destroy(&state^.shell.session)
        terminalview.terminal_destroy(&state^.terminal,
            animation_model.animation_memory_allocator(&state^.animation_memory))
        return false
    }
    terminalview.history_runtime_attach_generation(
        &state^.terminal_history_runtime, generation)
    if state^.terminal_history_runtime.status == .Unavailable {
        terminal_service_report_history_unavailable(&state^.terminal)
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
    mode: protocol.Evaluation_Mode = .Normal) -> bridgemodel.Communication_Send_Outcome {
    if state == nil || state^.julia_runtime_service == nil ||
        !state^.terminal.initialized || !terminalview.terminal_begin_eval(
            &state^.terminal, text) {
        return .Runtime_Stopping
    }
    request: protocol.Evaluation_Requested = {
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
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
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
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    #partial switch payload in message^ {
    case protocol.Completion_Result:
        if terminal_service_generation_matches(state, payload.animation_generation) {
            accepted := terminalview.terminal_set_completion_preview(
                &state^.terminal, {
                    request_id = payload.request_id,
                    found = payload.found,
                    replacement_start = payload.replacement_start,
                    replacement_end = payload.replacement_end,
                    insertion = payload.insertion,
                })
            if accepted && payload.show_candidates && !payload.found &&
                len(payload.insertion) > 0 {
                terminalview.terminal_append_ansi_output(
                    &state^.terminal, payload.insertion)
            }
            if accepted && payload.show_candidates && payload.found {
                return terminalview.terminal_accept_completion_preview(&state^.terminal)
            }
            return accepted
        }
    case protocol.Completion_Failed:
        if terminal_service_generation_matches(state, payload.animation_generation) {
            accepted := terminalview.terminal_fail_completion(
                &state^.terminal, payload.request_id)
            if accepted {
                terminalview.terminal_reject_completion(
                    &state^.terminal, "provider_or_transport_failure")
            }
            return accepted
        }
    }
    return false
}

// Dispatch one borrowed interactive-input lease value on the display thread.
terminal_service_dispatch_input :: proc(
    state: ^core.Euclid_General_State,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
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
        state, ready.animation_generation) {
        return false
    }
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
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
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
            terminalview.terminal_highlight_invalidate(&state^.terminal)
            return true
        }
    }
    return false
}

// Dispatch one borrowed terminal egress value through its display-owned message family.
terminal_service_dispatch_egress :: proc(
    state: ^core.Euclid_General_State,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    return terminal_tick_dispatch_egress(state, message) ||
        terminal_service_dispatch_evaluation(state, message) ||
        terminal_service_dispatch_completion_result(state, message) ||
        terminal_highlight_dispatch(state, message) ||
        terminal_service_dispatch_input(state, message) ||
        terminal_service_dispatch_observation(state, message)
}

// Open one terminal hyperlink after its URI passed terminal validation.
terminal_service_open_uri :: proc(_: rawptr, uri: cstring) -> bool {
    return native.sdl_platform_open_url(uri)
}

// Publish one validated OSC clipboard value through the display-owned OS boundary.
terminal_service_write_clipboard :: proc(_: rawptr, text: string) -> bool {
    return input.input_set_clipboard_text(text)
}

// Update the selected fixed-panel Terminal before simulation preparation.
terminal_service_apply_submission :: proc(
    state: ^core.Euclid_General_State,
    submission: terminalview.Terminal_Submission) {
    if !submission.submitted {
        return
    }
    terminal_service_record_history(state, submission)
    if submission.mode == .Shell {
        _ = shell_service_submit(state, submission.text)
    } else {
        _ = terminal_service_submit_evaluation(
            state, submission.text, submission.mode)
    }
}

// Admit one bounded history mutation without making recording a submission prerequisite.
terminal_service_record_history :: proc(
    state: ^core.Euclid_General_State,
    submission: terminalview.Terminal_Submission) {
    term := &state^.terminal
    if !submission.continuation &&
       !terminal_service_history_source_has_content(submission.text) {
        term^.provisional_recording_valid = false
        return
    }
    result := historyruntime.History_Runtime_Enqueue_Result.Not_Ready
    if submission.continuation {
        result = terminal_service_record_continuation(state, submission)
    } else {
        result = terminal_service_record_new_submission(state, submission)
    }
    term^.provisional_recording_valid = result ==
        historyruntime.History_Runtime_Enqueue_Result.Queued
    terminalview.terminal_highlight_end_submission(
        term, term^.provisional_submission_id,
        term^.provisional_desired_revision, submission.text)
    if !term^.provisional_recording_valid {
        log.warnf("terminal_history_write_rejected reason=%d",
            int(result))
    }
}

// Reject standalone blank input while preserving blank continuation lines.
terminal_service_history_source_has_content :: proc(source: string) -> bool {
    for offset := 0; offset < len(source); {
        rune, width := utf8.decode_rune(source[offset:])
        if !unicode.is_space(rune) {
            return true
        }
        offset += width
    }
    return false
}

// Record one continuation against its exact provisional identity and desired revision.
terminal_service_record_continuation :: proc(
    state: ^core.Euclid_General_State,
    submission: terminalview.Terminal_Submission) ->
        historyruntime.History_Runtime_Enqueue_Result {
    term := &state^.terminal
    id := term^.provisional_submission_id
    expected := term^.provisional_desired_revision
    if id == 0 || expected == 0 || expected >= max(u64) - 1 {
        log.warn("terminal_history_write_rejected reason=continuation_identity")
        return .Not_Ready
    }
    next := expected + 1
    result := terminalview.history_runtime_enqueue_update(
        &state^.terminal_history_runtime, {
            submission_id = id,
            persistent_entry_id = term^.provisional_persistent_entry_id,
            expected_revision = expected,
            new_revision = next,
            mode = submission.mode,
            source = submission.text,
        })
    term^.provisional_desired_revision = next
    return result
}

// Assign a fresh launch identity and queue the first immutable source revision.
terminal_service_record_new_submission :: proc(
    state: ^core.Euclid_General_State,
    submission: terminalview.Terminal_Submission) ->
        historyruntime.History_Runtime_Enqueue_Result {
    term := &state^.terminal
    history := &state^.terminal_history_runtime
    id := terminalview.history_runtime_reserve_submission_id(history)
    if id == 0 {
        log.warn("terminal_history_write_rejected reason=identity_capacity")
        return .Not_Ready
    }
    term^.provisional_submission_id = id
    term^.provisional_persistent_entry_id = 0
    term^.provisional_desired_revision = 1
    term^.provisional_committed_revision = 0
    return terminalview.history_runtime_enqueue_insert(history, {
        submission_id = id,
        mode = submission.mode,
        submitted_at_unix_ms =
            time.time_to_unix_nano(time.now()) / 1_000_000,
        terminal_generation = term^.animation_generation,
        source_revision = 1,
    }, submission.text)
}

// Publish joined write revision outcomes to the currently attached Terminal.
terminal_service_consume_history_write :: proc(state: ^core.Euclid_General_State) {
    history := &state^.terminal_history_runtime
    term := &state^.terminal
    if history^.write_completion_serial == term^.history_write_completion_serial {
        return
    }
    term^.history_write_completion_serial = history^.write_completion_serial
    mutation := history^.last_completed_mutation
    if mutation.kind == .Insert {
        terminal_service_apply_insert_result(term, history, mutation)
    } else if mutation.kind == .Update {
        terminal_service_apply_update_result(term, history, mutation)
    }
    if history^.last_write_result.persistence_failed {
        terminal_service_notify_persistence_failure(term)
    }
}

// Apply a joined insert result and retire any source that was not retained.
terminal_service_apply_insert_result :: proc(
    term: ^viewterminalmodel.Terminal_State,
    history: ^historyruntime.History_Runtime,
    mutation: historyruntime.History_Mutation) {
    id := mutation.record.submission_id
    revision := mutation.record.source_revision
    if history^.last_write_result.outcome == .Stored {
        if id == term^.provisional_submission_id {
            term^.provisional_committed_revision = revision
            term^.provisional_persistent_entry_id =
                history^.last_write_result.persistent_entry_id
        }
        return
    }
    terminalview.terminal_highlight_remove_revision(term, id, revision)
    if id == term^.provisional_submission_id {
        term^.provisional_recording_valid = false
    }
    log.warnf("terminal_history_write_failed submission_id=%d revision=%d",
        id, revision)
}

// Apply a joined continuation result without retaining a failed newer revision.
terminal_service_apply_update_result :: proc(
    term: ^viewterminalmodel.Terminal_State,
    history: ^historyruntime.History_Runtime,
    mutation: historyruntime.History_Mutation) {
    request := mutation.update
    if history^.last_write_result.outcome == .Updated {
        if request.submission_id == term^.provisional_submission_id {
            term^.provisional_committed_revision = request.new_revision
        }
        return
    }
    terminalview.terminal_highlight_remove_revision(
        term, request.submission_id, request.new_revision)
    if request.submission_id == term^.provisional_submission_id {
        term^.provisional_recording_valid = false
    }
    log.warnf(
        "terminal_history_update_failed submission_id=%d expected_revision=%d new_revision=%d",
        request.submission_id, request.expected_revision, request.new_revision)
}

// Consume one joined recall result and apply it only to its captured editor epoch.
terminal_service_consume_history_read :: proc(state: ^core.Euclid_General_State) {
    term := &state^.terminal
    history := &state^.terminal_history_runtime
    request := history^.read_result_request
    destination := terminal_service_history_read_destination(term, request)
    completion, consumed := terminalview.history_runtime_consume_read_result(
        history, destination)
    if !completion.ready {
        return
    }
    if history^.persistence_status == .Failed {
        terminal_service_notify_persistence_failure(term)
    }
    if completion.request.target == .Highlighting {
        terminal_service_consume_highlight_source(term, completion, consumed)
        return
    }
    if completion.request.target == .Navigation {
        terminal_service_apply_navigation_read(term, completion, consumed)
    } else {
        log.error("terminal_history_read_target_invalid")
    }
}

// Select the owner-bounded destination for one interactive or speculative read.
terminal_service_history_read_destination :: proc(
    term: ^viewterminalmodel.Terminal_State,
    request: historyruntime.History_Read_Request) -> []u8 {
    if request.target == .Highlighting {
        slot := terminalview.terminal_highlight_source_fetch_slot(
            term, request.request_id)
        if slot != nil {
            return slot.source[:]
        }
    }
    return term.history_navigation_read_source[:]
}

// Apply a joined navigation read only to the matching pending editor operation.
terminal_service_apply_navigation_read :: proc(
    term: ^viewterminalmodel.Terminal_State,
    completion: historyruntime.History_Read_Completion, consumed: bool) {
    if completion.request.request_id != term^.history_navigation_pending_id {
        return
    }
    term^.history_navigation_pending_id = 0
    if !consumed {
        terminal_service_fail_history_navigation(term, "result_capacity")
        return
    }
    if completion.request.terminal_generation != term^.animation_generation ||
       completion.request.navigation_epoch != term^.history_navigation_epoch {
        return
    }
    if completion.result.outcome == termhiststore.History_Read_Outcome.Found {
        terminal_service_apply_history_record(term, completion)
    } else if completion.result.outcome ==
        termhiststore.History_Read_Outcome.Boundary {
        terminal_service_apply_history_boundary(term, completion.request.kind)
    } else if completion.result.outcome ==
        termhiststore.History_Read_Outcome.Not_Found &&
        completion.request.kind == .Latest {
        terminal_service_apply_history_boundary(term, completion.request.kind)
    } else {
        terminal_service_fail_history_navigation(term, "read_failed")
    }
    terminal_service_pop_history_intent(term)
}

// Make optional durable-storage failures visible without changing evaluation outcome.
terminal_service_notify_persistence_failure :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    if term == nil || term^.history_persistence_notified {
        return
    }
    term^.history_persistence_notified = true
    terminalview.terminal_append_output_line(
        term, "Terminal history persistence failed; saved history may be unavailable.")
}

// Publish speculative source only when the fetched database revision matches its request.
terminal_service_consume_highlight_source :: proc(
    term: ^viewterminalmodel.Terminal_State,
    completion: historyruntime.History_Read_Completion, consumed: bool) {
    request := completion.request
    result := completion.result
    found := consumed && result.outcome ==
        termhiststore.History_Read_Outcome.Found &&
        result.record.scope == request.source_scope &&
        result.record.source_id == request.submission_id &&
        result.record.source_revision == request.source_revision
    target_kind: protocol.Highlight_Target = .History_Entry
    if request.source_scope == .Persistent {
        target_kind = .Persistent_History_Entry
    }
    identity: protocol.Highlight_Identity = {
        request_id = protocol.Request_Id(request.request_id),
        animation_generation = request.terminal_generation,
        target_kind = target_kind,
        target_id = request.submission_id,
        source_revision = request.source_revision,
        face_generation = request.face_generation,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }
    terminalview.terminal_highlight_source_fetch_publish(
        term, identity, found, result.source_length)
}

// Atomically replace the editor source and prompt mode after a bounded read succeeds.
terminal_service_apply_history_record :: proc(
    term: ^viewterminalmodel.Terminal_State,
    completion: historyruntime.History_Read_Completion) {
    length := completion.result.source_length
    if length < 0 || length > len(term.history_navigation_read_source) ||
       !termhist.termhist_load_entry(
            term.history, term.history_navigation_read_source[:length]) {
        terminal_service_fail_history_navigation(term, "editor_capacity")
        return
    }
    term.input_mode = completion.result.record.mode
    term.history_navigation_anchor_id = completion.result.record.submission_id
    term.history_navigation_cursor = {
        submitted_at_unix_ms = completion.result.record.submitted_at_unix_ms,
        scope = completion.result.record.scope,
        source_id = completion.result.record.source_id,
    }
    term.history_navigation_cursor_valid = true
}

// Restore the saved draft only when Down reaches the history tail.
terminal_service_apply_history_boundary :: proc(
    term: ^viewterminalmodel.Terminal_State,
    kind: historyruntime.History_Read_Kind) {
    if kind != .Newer && kind != .Latest {
        return
    }
    if !termhist.termhist_restore_backup(term.history) {
        terminal_service_fail_history_navigation(term, "draft_restore")
        return
    }
    term.input_mode = term.history_navigation_draft_mode
    term.history_navigation_anchor_id = 0
    term.history_navigation_cursor = {}
    term.history_navigation_cursor_valid = false
    term.history_navigation_active = false
}

// Report a failed recall without changing its source, mode, or stable anchor.
terminal_service_fail_history_navigation :: proc(
    term: ^viewterminalmodel.Terminal_State, reason: string) {
    log.warnf("terminal_history_navigation_failed reason=%s", reason)
    term.history_navigation_intent_count = 0
}

// Notify once when the retained-history store cannot support Terminal recall.
terminal_service_report_history_unavailable :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    if term == nil || term^.history_unavailable_notified {
        return
    }
    term^.history_unavailable_notified = true
    log.warn("terminal_history_recall_unavailable")
    terminalview.terminal_append_output_line(
        term, "History recall unavailable: user-data storage is not available.")
}

// Remove the completed direction while preserving later ordered navigation intent.
terminal_service_pop_history_intent :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    if term.history_navigation_intent_count <= 0 {
        return
    }
    for index in 1..<term.history_navigation_intent_count {
        term.history_navigation_intents[index - 1] =
            term.history_navigation_intents[index]
    }
    term.history_navigation_intent_count -= 1
}

// Submit the oldest queued recall intent with its stable anchor and editor epoch.
terminal_service_schedule_history_read :: proc(state: ^core.Euclid_General_State) {
    term := &state^.terminal
    history := &state^.terminal_history_runtime
    if term^.history_navigation_pending_id != 0 ||
       term^.history_navigation_intent_count == 0 {
        return
    }
    if history^.status == .Uninitialized || history^.status == .Initializing {
        return
    }
    if history^.status == .Unavailable || history^.status == .Failed ||
       history^.status == .Closing || history^.status == .Closed {
        terminal_service_report_history_unavailable(term)
        terminal_service_fail_history_navigation(term, "history_unavailable")
        return
    }
    term^.history_navigation_request_id += 1
    if term^.history_navigation_request_id == 0 {
        term^.history_navigation_request_id = 1
    }
    request := terminal_service_history_read_request(term, history)
    if terminalview.history_runtime_request_read(history, request) {
        term^.history_navigation_pending_id = request.request_id
        term^.history_navigation_admission_reported = false
    } else if !term^.history_navigation_admission_reported {
        log.warn("terminal_history_navigation_delayed reason=request_admission")
        term^.history_navigation_admission_reported = true
    }
}

// Materialize the oldest direction as a generation- and epoch-correlated store request.
terminal_service_history_read_request :: proc(
    term: ^viewterminalmodel.Terminal_State,
    history: ^historyruntime.History_Runtime) ->
        historyruntime.History_Read_Request {
    direction := term^.history_navigation_intents[0]
    if history^.persist_enabled && !term^.history_navigation_cursor_valid {
        return {
            kind = .Latest,
            priority = .Interactive,
            request_id = term^.history_navigation_request_id,
            terminal_generation = term^.animation_generation,
            navigation_epoch = term^.history_navigation_epoch,
        }
    }
    anchor := term^.history_navigation_anchor_id
    if direction < 0 && anchor == max(u64) {
        anchor = history^.next_submission_id + 1
    }
    kind := historyruntime.History_Read_Kind.Older
    if direction > 0 {
        kind = .Newer
    }
    return {
        kind = kind,
        priority = .Interactive,
        submission_id = anchor,
        request_id = term^.history_navigation_request_id,
        terminal_generation = term^.animation_generation,
        navigation_epoch = term^.history_navigation_epoch,
        cursor = term^.history_navigation_cursor,
        cursor_valid = term^.history_navigation_cursor_valid,
    }
}

// Send one correlated completion snapshot through the Julia-host ingress link.
terminal_service_send_completion :: proc(
    state: ^core.Euclid_General_State,
    completion: terminalview.Terminal_Completion_Request) {

    if !completion.requested {
        return
    }
    outcome := julia.send_terminal_completion_request(
        state^.julia_runtime_service, {
            request_id = completion.request_id,
            animation_generation = state^.terminal.animation_generation,
            code = completion.code,
            cursor_byte = completion.cursor_byte,
            show_candidates = completion.show_candidates,
        })
    if outcome != .Sent {
        if terminalview.terminal_fail_completion(
            &state^.terminal, completion.request_id) {
            terminalview.terminal_reject_completion(
                &state^.terminal, "request_transport_failure")
        }
    }
}

// Add UI-owned effective focus to a frame copy routed to Terminal consumers.
terminal_service_routed_frame :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame) -> input.Input_Frame {
    result := frame
    interaction := state^.ui_runtime.input.interaction_frame
    result.terminal_focus_known = true
    result.terminal_focused = interaction.terminal_focused
    result.terminal_focus_changed = interaction.terminal_focus_changed
    return result
}

// Continue non-visual Terminal owners while its selected View is hidden.
terminal_service_update_hidden :: proc(
    state: ^core.Euclid_General_State) {
    terminal_service_retire_history_explorer(state)
    shell_service_update(state)
    terminal_graphics_update(state)
}

// Prepare and service one visible Terminal panel frame.
terminal_service_update_visible :: proc(
    state: ^core.Euclid_General_State, input_runtime: ^input.Input_Runtime,
    frame: input.Input_Frame) -> uiterminal.Terminal_Prepared_Frame {
    bounds := uiterminal.terminal_content_panel(
        state^.ui_runtime.layout.ui_regions.text_rect)
    terminal_font := font.cache_resolve(&state^.font_cache, .Regular)
    terminal_frame := terminal_service_routed_frame(state, frame)
    terminal_service_consume_history_write(state)
    prepared := uiterminal.terminal_prepare_frame(
        state, terminal_frame, terminal_font, bounds,
        input_runtime != nil && card(input_runtime^.mouse_captured) > 0)
    shell_service_update(
        state, input_runtime, prepared.content_frame, prepared.geometry_change)
    state^.terminal.history_explorer_open_allowed =
        state^.shell.phase == .Inactive
    update := uiterminal.terminal_update(
        &state^.terminal, prepared.content_frame, terminal_font, bounds)
    terminal_service_consume_history_read(state)
    terminal_service_update_history_explorer(state)
    update.geometry_change = prepared.geometry_change
    terminal_service_apply_submission(state, update.submission)
    terminal_service_schedule_history_read(state)
    terminal_service_send_completion(state, update.completion)
    terminal_highlight_service_update(state, prepared, frame.sample_time_seconds)
    _ = terminalview.terminal_publish_clipboard_actions(
        &state^.terminal, state^.terminal.output_producer, {
            write = terminal_service_write_clipboard,
        })
    terminal_graphics_update(state)
    _ = terminalview.terminal_activate_hyperlink(
        &state^.terminal, update.hyperlink_activation, {
            activate = terminal_service_open_uri,
        })
    uiterminal.terminal_refresh_explorer_frame(state, &prepared)
    return prepared
}

// Update the selected fixed-panel Terminal before simulation preparation.
terminal_service_update :: proc(
    state: ^core.Euclid_General_State, input_runtime: ^input.Input_Runtime,
    frame: input.Input_Frame) -> uiterminal.Terminal_Prepared_Frame {
    shell_service_maintenance(state)
    if !terminal_animation_selected(state) {
        terminal_service_retire_history_explorer(state)
        return {}
    }
    if !state^.terminal.initialized && !terminal_service_enter(state) {
        return {}
    }
    terminal_service_request_session(state)
    if !uipresentation.ui_presentation_is_visible(
        &state^.ui_runtime.presentation) {
        terminal_service_update_hidden(state)
        return {}
    }
    if !state^.terminal.julia_session_ready {
        terminal_service_retire_history_explorer(state)
        return {}
    }
    return terminal_service_update_visible(state, input_runtime, frame)
}
