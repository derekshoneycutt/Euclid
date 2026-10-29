#+test

package terminalview

import model "model"
import protocol "../../core/protocol"
import termhist "../../terminal/history"
import termhiststore "../../terminal/history/store"
import "core:testing"
import "core:strings"

// Establish a display owner with prompt/session readiness but no Julia dependency.
terminal_highlight_test_init :: proc(t: ^testing.T, term: ^model.Terminal_State) {
    testing.expect(t, terminal_init(term))
    term.banner_ready = true
    term.julia_session_ready = true
}

// Publish one default-style run through the production atomic publication path.
terminal_highlight_test_publish :: proc(
    term: ^model.Terminal_State, request: protocol.Highlight_Requested) -> bool {
    runs: [1]protocol.Highlight_Run = {{
        end_byte = u32(len(request.source)),
    }}
    return terminal_highlight_publish(term, {
        identity = request.identity,
        source = request.source,
        runs = runs[:],
    })
}

// Build a keyed identity for a simulated joined source-read completion.
terminal_highlight_test_source_identity :: proc(
    term: ^model.Terminal_State, id, revision, request_id: u64,
    face_generation := u64(0)) -> protocol.Highlight_Identity {
    face := face_generation
    if face == 0 {
        face = term.highlighting.face_generation
    }
    return {
        request_id = protocol.Request_Id(request_id),
        animation_generation = term.animation_generation,
        target_kind = .History_Entry,
        target_id = id,
        source_revision = revision,
        face_generation = face,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }
}

// Commit source through ordinary grid/history ownership without starting evaluation.
terminal_highlight_test_submit :: proc(
    t: ^testing.T, term: ^model.Terminal_State, source: string) {
    termhist.termhist_clear(term.history)
    testing.expect(t, termhist.termhist_insert_text(term.history, source))
    testing.expect_value(t, terminal_submit(term), source)
    if term.collecting_continuation {
        term.provisional_desired_revision += 1
    } else {
        term.provisional_submission_id += 1
        term.provisional_desired_revision = 1
    }
    terminal_highlight_end_submission(term, term.provisional_submission_id,
        term.provisional_desired_revision, source)
}

// Only quiet Normal-mode source schedules, and cursor-only edits do not reschedule.
@(test)
terminal_test_highlight_live_debounce :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "α = \"hi\""))
    terminal_highlight_observe_live(&term, 1)
    _, early := terminal_highlight_take_request(&term, 1.1)
    testing.expect(t, !early)
    request, ready := terminal_highlight_take_request(&term, 1.12)
    testing.expect(t, ready)
    testing.expect_value(t, request.source, "α = \"hi\"")
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 1)
    term.history.cursor = 0
    terminal_highlight_observe_live(&term, 3)
    _, again := terminal_highlight_take_request(&term, 3)
    testing.expect(t, !again)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 1)
}

// Edit/undo cannot resurrect stale source-revision results, even for identical bytes.
@(test)
terminal_test_highlight_stale_live_revision :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 0)
    first, _ := terminal_highlight_take_request(&term, 1)
    termhist.termhist_insert_text(term.history, "y")
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
    termhist.termhist_clear(term.history)
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 1)
    second, ready := terminal_highlight_take_request(&term, 2)
    testing.expect(t, ready && first.identity != second.identity)
    testing.expect(t, !terminal_highlight_test_publish(&term, first))
    testing.expect(t, terminal_highlight_test_publish(&term, second))
    testing.expect_value(t, term.highlighting.stale_count, u64(1))
}

// Incomplete coverage, malformed style, and source mismatch reject the entire result.
@(test)
terminal_test_highlight_atomic_rejection :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_insert_text(term.history, "αx")
    for kind in 0..<4 {
        terminal_highlight_invalidate(&term)
        terminal_highlight_observe_live(&term, 0)
        request, ready := terminal_highlight_take_request(&term, 1)
        testing.expect(t, ready)
        runs: [1]protocol.Highlight_Run = {{
            end_byte = 3,
        }}
        source := request.source
        switch kind {
        case 0:
            runs[0].end_byte = 1
        case 1:
            runs[0].italic = 2
        case 2:
            source = "xxx"
        case 3:
            runs[0].foreground_kind = .Ansi; runs[0].foreground = 16
        }
        testing.expect(t, !terminal_highlight_publish(&term,
            {request.identity, source, runs[:]}))
        testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
        _, retry := terminal_highlight_take_request(&term, 2)
        testing.expect(t, !retry)
    }
}

// Faces invalidate both accepted and pending source without changing editable bytes.
@(test)
terminal_test_highlight_faces_and_modes :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 0)
    first, _ := terminal_highlight_take_request(&term, 1)
    testing.expect(t, terminal_highlight_test_publish(&term, first))
    testing.expect(t, terminal_highlight_set_face_generation(&term, 2))
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
    terminal_highlight_observe_live(&term, 1)
    second, ready := terminal_highlight_take_request(&term, 2)
    testing.expect(t, ready && second.identity.face_generation == 2)
    term.input_mode = .Help
    testing.expect(t, !terminal_highlight_test_publish(&term, second))
    terminal_highlight_observe_live(&term, 2)
    _, help := terminal_highlight_take_request(&term, 3)
    testing.expect(t, !help)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "x")
}

// Failure and transport saturation stay plain instead of sending unchanged work each frame.
@(test)
terminal_test_highlight_failure_and_pending_bound :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    requests: [model.TERMINAL_HIGHLIGHT_PENDING_CAPACITY]protocol.Highlight_Requested
    for &request in requests {
        termhist.termhist_insert_text(term.history, "x")
        terminal_highlight_observe_live(&term, 0)
        ready: bool
        request, ready = terminal_highlight_take_request(&term, 1)
        testing.expect(t, ready)
    }
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 0)
    _, full := terminal_highlight_take_request(&term, 1)
    testing.expect(t, !full)
    testing.expect(t, !terminal_highlight_test_publish(&term, requests[0]))
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    testing.expect(t, terminal_highlight_fail(&term,
        {request.identity, .Transport_Capacity}))
    terminal_highlight_observe_live(&term, 2)
    _, retry := terminal_highlight_take_request(&term, 2)
    testing.expect(t, !retry)
}

// Submission hides live runs and requests exact multiline history only when visible.
@(test)
terminal_test_highlight_visible_history :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "α = 1\nβ = 2")
    terminal_highlight_observe_history(&term, 100, 110)
    _, hidden := terminal_highlight_take_request(&term, 1)
    testing.expect(t, !hidden)
    terminal_highlight_observe_history(&term, 1, 2)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    testing.expect_value(t,
        request.identity.target_kind, protocol.Highlight_Target.History_Entry)
    testing.expect_value(t, request.source, "α = 1\nβ = 2")
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    terminal_highlight_observe_history(&term, 0, 2)
    _, duplicate := terminal_highlight_take_request(&term, 2)
    testing.expect(t, !duplicate)
    entry := terminal_highlight_history_find(
        &term, request.identity.target_id, request.identity.source_revision)
    testing.expect(t,
        entry != nil && terminal_history_highlight_slot(&term, entry) != nil)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
}

// Explorer identities separate equal session/saved IDs and reuse exact selected source.
@(test)
terminal_test_highlight_explorer_scoped_candidates :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    rows: [2]termhiststore.History_Candidate_Summary = {
        {
            record = {
                submission_id = 17,
                scope = .Persistent,
                source_id = 17,
                mode = .Normal,
                source_revision = 3,
            },
        },
        {
            record = {
                submission_id = 17,
                scope = .Session,
                source_id = 17,
                mode = .Normal,
                source_revision = 3,
            },
        },
    }
    preview: [32]u8
    copy(preview[:], "saved source")
    explorer: model.History_Explorer_State = {
        active = true,
        opening_generation = 1,
        query_generation = 1,
        identity = {
            terminal_generation = term.animation_generation,
            opening_generation = 1,
            query_generation = 1,
            runtime_epoch = 1,
        },
        rows = rows[:],
        row_count = 2,
        selected_index = 0,
        preview_record = rows[0].record,
        preview_source = preview[:],
        preview_length = len("saved source"),
        preview_status = .Ready,
    }
    terminal_highlight_observe_explorer(&term, &explorer)
    saved := terminal_highlight_cache_slot_scoped(
        &term, .Persistent_History_Entry, 17, 3)
    session := terminal_highlight_cache_slot_scoped(&term, .History_Entry, 17, 3)
    testing.expect(t, saved != nil && session != nil && saved != session)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    testing.expect_value(t, request.identity.target_kind,
        protocol.Highlight_Target.Persistent_History_Entry)
    testing.expect_value(t, request.identity.target_id, u64(17))
    testing.expect_value(t, request.source, "saved source")
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    cached := terminal_highlight_cached_runs(
        &term, .Persistent_History_Entry, 17, 3)
    testing.expect_value(t, len(cached), 1)
    if len(cached) > 0 {
        testing.expect_value(t, cached[0].end_byte, u32(len("saved source")))
    }
    source_request, fetch_ready := terminal_highlight_source_request_next(&term)
    testing.expect(t, fetch_ready)
    testing.expect_value(t, source_request.target_kind,
        protocol.Highlight_Target.History_Entry)
    testing.expect_value(t, source_request.submission_id, u64(17))
}

// Closing and reopening retires old explorer work even for the same source revision.
@(test)
terminal_test_highlight_explorer_reopen_rejects_stale_result :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    rows: [1]termhiststore.History_Candidate_Summary = {{
        record = {
            scope = .Persistent,
            source_id = 9,
            mode = .Normal,
            source_revision = 1,
        },
    }}
    preview: [32]u8
    copy(preview[:], "saved")
    explorer: model.History_Explorer_State = {
        active = true,
        opening_generation = 1,
        query_generation = 1,
        identity = {
            terminal_generation = term.animation_generation,
            opening_generation = 1,
            query_generation = 1,
            runtime_epoch = 1,
        },
        rows = rows[:],
        row_count = 1,
        selected_index = 0,
        preview_record = rows[0].record,
        preview_source = preview[:],
        preview_length = len("saved"),
        preview_status = .Ready,
    }
    terminal_highlight_observe_explorer(&term, &explorer)
    stale, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    explorer.active = false
    terminal_highlight_observe_explorer(&term, &explorer)
    testing.expect(t, !terminal_highlight_test_publish(&term, stale))
    explorer.active = true
    explorer.opening_generation = 2
    explorer.query_generation = 1
    explorer.identity.opening_generation = 2
    explorer.identity.runtime_epoch = 2
    terminal_highlight_observe_explorer(&term, &explorer)
    current, current_ready := terminal_highlight_take_request(&term, 2)
    testing.expect(t, current_ready && current.identity != stale.identity)
    testing.expect(t, terminal_highlight_test_publish(&term, current))
}

// Help-mode history remains plain and never enters the Julia classifier.
@(test)
terminal_test_highlight_explorer_skips_non_julia_modes :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    rows: [1]termhiststore.History_Candidate_Summary = {{
        record = {
            scope = .Persistent,
            source_id = 4,
            mode = .Help,
            source_revision = 1,
        },
    }}
    explorer: model.History_Explorer_State = {
        active = true,
        opening_generation = 1,
        query_generation = 1,
        rows = rows[:],
        row_count = 1,
        selected_index = 0,
    }
    terminal_highlight_observe_explorer(&term, &explorer)
    _, ready := terminal_highlight_take_request(&term, 1)
    _, source_ready := terminal_highlight_source_request_next(&term)
    testing.expect(t, !ready && !source_ready)
    testing.expect_value(t, term.highlighting.explorer_candidate_count, 0)
}

// Cache eviction is bounded, but an older still-visible command can be re-requested.
@(test)
terminal_test_highlight_history_eviction_and_revisit :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    for i in 0..<20 {
        terminal_highlight_test_submit(t, &term, "x")
        terminal_highlight_observe_history(&term, i, i + 1)
        request, ready := terminal_highlight_take_request(&term, 1)
        testing.expect(t, ready)
        testing.expect(t, terminal_highlight_test_publish(&term, request))
    }
    terminal_highlight_test_revisit_evicted_source(t, &term)
}

// Refetch an evicted visible source and classify it from its bounded cache slot.
terminal_highlight_test_revisit_evicted_source :: proc(
    t: ^testing.T, term: ^model.Terminal_State) {
    testing.expect(t, term.highlighting.eviction_count > 0)
    testing.expect(t, !terminal_highlight_test_has_cached_id(term, 1))
    entry := terminal_highlight_history_find(term, 1, 1)
    visible_line := terminal_highlight_test_visible_line(term, entry)
    testing.expect(t, visible_line >= 0)
    terminal_highlight_observe_history(term, visible_line, visible_line + 1)
    source_request, missing := terminal_highlight_source_request_next(term)
    id := source_request.submission_id
    revision := source_request.source_revision
    testing.expect(t, missing)
    testing.expect_value(t, id, u64(1))
    testing.expect_value(t, revision, u64(1))
    testing.expect(t, terminal_highlight_source_fetch_begin(term, id, revision, 100))
    terminal_highlight_test_publish_source_fetch(term, id, revision, 100)
    terminal_highlight_observe_history(term, visible_line, visible_line + 1)
    old, ready := terminal_highlight_take_request(term, 1)
    testing.expect(t, ready)
    testing.expect_value(t, old.identity.target_id, u64(1))
    terminal_highlight_test_expect_pending_source(t, term, old)
    testing.expect(t, terminal_highlight_test_publish(term, old))
}

// Check whether any bounded slot still owns a submission identity.
terminal_highlight_test_has_cached_id :: proc(
    term: ^model.Terminal_State, id: u64) -> bool {
    for &slot in term^.highlighting.cache {
        if slot.identity.target_id == id {
            return true
        }
    }
    return false
}

// Resolve one anchored visible line for a retained submission.
terminal_highlight_test_visible_line :: proc(
    term: ^model.Terminal_State,
    entry: ^model.Terminal_Highlight_History) -> int {
    if entry == nil {
        return -1
    }
    for line in 0..<terminal_line_count(term) {
        if terminal_highlight_line_for_row(
            entry, terminal_output_semantic_row(term, line)) != nil {
            return line
        }
    }
    return -1
}

// Simulate copying fetched source into its matched bounded cache slot.
terminal_highlight_test_publish_source_fetch :: proc(
    term: ^model.Terminal_State, id, revision, request_id: u64) {
    slot := terminal_highlight_source_fetch_slot(term, request_id)
    if slot == nil {
        return
    }
    slot.source[0] = 'x'
    identity := terminal_highlight_test_source_identity(
        term, id, revision, request_id)
    terminal_highlight_source_fetch_publish(term, identity, true, 1)
}

// Assert that a scheduled cached source remains current and exact.
terminal_highlight_test_expect_pending_source :: proc(
    t: ^testing.T, term: ^model.Terminal_State,
    request: protocol.Highlight_Requested) {
    slot := terminal_highlight_pending_slot(term, request.identity)
    testing.expect(t, slot != nil)
    if slot != nil {
        testing.expect(t, terminal_highlight_slot_current(term, slot))
        testing.expect_value(t, string(slot.source[:slot.source_length]), "x")
    }
}

// Continuation history keeps its submission identity and advances source revision.
@(test)
terminal_test_highlight_history_replacement :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "begin")
    terminal_highlight_observe_history(&term, 0, 1)
    first, _ := terminal_highlight_take_request(&term, 1)
    testing.expect(t, terminal_begin_eval(&term, "begin"))
    terminal_continue_eval(&term)
    terminal_highlight_test_submit(t, &term, "begin")
    testing.expect(t, !terminal_highlight_test_publish(&term, first))
    testing.expect(t,
        terminal_highlight_history_find(&term, first.identity.target_id,
            first.identity.source_revision) == nil)
    terminal_highlight_observe_history(&term, 0, 1)
    retry, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    testing.expect_value(t, retry.identity.target_id, first.identity.target_id)
    testing.expect_value(t, retry.identity.source_revision,
        first.identity.source_revision + 1)
}

// Session/source mismatches do not consume pending identities or publish borrowed runs.
@(test)
terminal_test_highlight_identity_and_copy :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 0)
    request, _ := terminal_highlight_take_request(&term, 1)
    runs: [1]protocol.Highlight_Run = {{
        end_byte = 1,
        weight = .Bold,
    }}
    result: protocol.Highlight_Result = {
        request.identity,
        request.source,
        runs[:],
    }
    result.identity.animation_generation += 1
    testing.expect(t, !terminal_highlight_publish(&term, result))
    result.identity = request.identity
    testing.expect(t, terminal_highlight_publish(&term, result))
    runs[0].weight = .Dim
    testing.expect_value(t, terminal_live_highlight_runs(&term)[0].weight,
        protocol.Highlight_Weight.Bold)
    terminal_destroy(&term, context.allocator)
    testing.expect(t, !terminal_highlight_publish(&term, result))
}

// Soft wraps retain one source identity and do not create duplicate history requests.
@(test)
terminal_test_highlight_wrapped_history :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    source: [200]u8
    for &byte in source {
        byte = 'a'
    }
    terminal_highlight_test_submit(t, &term, string(source[:]))
    row := terminal_output_semantic_row(&term, 1)
    entry := &term.highlighting.history[0]
    testing.expect(t, row.grapheme_offset > 0)
    testing.expect(t, terminal_highlight_line_for_row(entry, row) != nil)
    terminal_highlight_observe_history(&term, 1, 2)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready && request.source == string(source[:]))
    testing.expect(t, terminal_highlight_test_publish(&term, request))
}

// Several visible hard lines from one submission share one source lookup.
@(test)
terminal_test_highlight_source_fetch_coalesces_lines :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "first\nsecond")
    terminal_highlight_observe_history(&term, 0, 2)
    slot := terminal_highlight_cache_slot(
        &term, term.provisional_submission_id, term.provisional_desired_revision)
    testing.expect(t, slot != nil)
    if slot == nil {
        return
    }
    slot.source_length = 0
    slot.phase = .Empty
    source_request, ready := terminal_highlight_source_request_next(&term)
    id := source_request.submission_id
    revision := source_request.source_revision
    testing.expect(t, ready)
    testing.expect(t, terminal_highlight_source_fetch_begin(
        &term, id, revision, 100))
    _, duplicate := terminal_highlight_source_request_next(&term)
    testing.expect(t, !duplicate)
    old_face := term.highlighting.face_generation
    testing.expect(t, terminal_highlight_set_face_generation(&term, old_face + 1))
    slot = terminal_highlight_source_fetch_slot(&term, 100)
    if slot != nil {
        slot.source[0] = 'f'
        identity := terminal_highlight_test_source_identity(
            &term, id, revision, 100, old_face)
        terminal_highlight_source_fetch_publish(
            &term, identity, true, 1)
    }
    _, retry := terminal_highlight_source_request_next(&term)
    testing.expect(t, retry)
}

// Live work wins over visible history and remains independent of completion/evaluation IDs.
@(test)
terminal_test_highlight_live_priority :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "x")
    terminal_highlight_observe_history(&term, 0, 1)
    termhist.termhist_insert_text(term.history, "y")
    terminal_highlight_observe_live(&term, 0)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready && request.identity.target_kind == .Live_Input)
    testing.expect_value(t, term.next_completion_request_id, protocol.Request_Id(0))
    testing.expect_value(t, term.next_eval_request_id, protocol.Request_Id(0))
    history, history_ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, history_ready && history.identity.target_kind == .History_Entry)
}

// A full visible cache is stable across frames rather than repeatedly evicting visible work.
@(test)
terminal_test_highlight_visible_cache_pressure :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    for _ in 0..<12 {
        terminal_highlight_test_submit(t, &term, "x")
    }
    terminal_highlight_observe_history(&term, 0, 12)
    for _ in 0..<model.TERMINAL_HIGHLIGHT_CACHE_CAPACITY {
        request, ready := terminal_highlight_take_request(&term, 1)
        testing.expect(t, ready)
        testing.expect(t, terminal_highlight_test_publish(&term, request))
    }
    for _ in 0..<3 {
        terminal_highlight_observe_history(&term, 0, 12)
        _, retry := terminal_highlight_take_request(&term, 1)
        testing.expect(t, !retry)
    }
    testing.expect(t, term.highlighting.cache_saturated)
    testing.expect_value(t, term.highlighting.eviction_count, u64(0))
    testing.expect_value(t, term.highlighting.rejected_count, u64(1))
}

// Face changes re-request historical source, without modifying the stored command.
@(test)
terminal_test_highlight_history_face_change :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "x")
    terminal_highlight_observe_history(&term, 0, 1)
    first, _ := terminal_highlight_take_request(&term, 1)
    testing.expect(t, terminal_highlight_test_publish(&term, first))
    terminal_highlight_set_face_generation(&term, 2)
    terminal_highlight_observe_history(&term, 0, 1)
    second, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready && second.identity.face_generation == 2)
    testing.expect_value(t, second.source, "x")
    testing.expect_value(t, second.identity.target_id, first.identity.target_id)
}

// Capacity and malformed UTF-8 fail once per source revision without affecting editing.
@(test)
terminal_test_highlight_source_bounds :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    source := make([]u8, protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES + 1,
        context.allocator)
    defer delete(source, context.allocator)
    for &byte in source {
        byte = 'x'
    }
    termhist.termhist_insert_text(term.history, string(source[:len(source) - 1]))
    terminal_highlight_observe_live(&term, 0)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready && len(request.source) == len(source) - 1)
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    termhist.termhist_insert_text(term.history, "x")
    terminal_highlight_observe_live(&term, 1)
    _, oversized := terminal_highlight_take_request(&term, 2)
    testing.expect(t, !oversized && len(terminal_live_highlight_runs(&term)) == 0)
    terminal_highlight_observe_live(&term, 2)
    testing.expect_value(t, term.highlighting.rejected_count, u64(1))
    termhist.termhist_clear(term.history)
    termhist.termhist_insert_text(term.history, "\xff")
    terminal_highlight_observe_live(&term, 3)
    _, invalid := terminal_highlight_take_request(&term, 4)
    testing.expect(t, !invalid)
}

// Removing provisional display provenance prevents checkpoint ID reuse accepting old styles.
@(test)
terminal_test_highlight_continuation_replacement :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "begin")
    testing.expect(t, terminal_begin_eval(&term, "begin"))
    terminal_highlight_observe_history(&term, 0, 1)
    first, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    terminal_continue_eval(&term)
    testing.expect(t, !terminal_highlight_test_publish(&term, first))
    terminal_highlight_test_submit(t, &term, "begin\nend")
    terminal_highlight_observe_history(&term, 0, 2)
    second, new_ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, new_ready && second.identity.target_id == first.identity.target_id)
    testing.expect_value(t, second.identity.source_revision,
        first.identity.source_revision + 1)
    testing.expect_value(t, second.source, "begin\nend")
    testing.expect_value(t, term.provisional_desired_revision, u64(2))
}

// Mode-specific submissions never enter Julia highlighting, and evicted anchors go stale.
@(test)
terminal_test_highlight_non_julia_and_history_eviction :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    term.input_mode = .Shell
    terminal_highlight_test_submit(t, &term, "echo hi")
    terminal_highlight_observe_history(&term, 0, 1)
    _, shell := terminal_highlight_take_request(&term, 1)
    testing.expect(t, !shell)
    term.input_mode = .Normal
    terminal_highlight_test_submit(t, &term, "x")
    terminal_highlight_observe_history(&term, 1, 2)
    request, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    for &entry in term.highlighting.history {
        entry.id = 0
    }
    testing.expect(t, !terminal_highlight_test_publish(&term, request))
    testing.expect(t, term.provisional_submission_id == 2)
    testing.expect(t, strings.contains(
        terminal_line_text(&term, 1), "x"))
}

// Hidden in-flight history keeps its slot so revisiting cannot duplicate Julia work.
@(test)
terminal_test_highlight_pending_history_not_evicted :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    for _ in 0..<12 {
        terminal_highlight_test_submit(t, &term, "x")
    }
    terminal_highlight_observe_history(&term, 0, 1)
    pending, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    terminal_highlight_observe_history(&term, 1, 12)
    for _ in 0..<model.TERMINAL_HIGHLIGHT_CACHE_CAPACITY - 1 {
        request, issued := terminal_highlight_take_request(&term, 1)
        testing.expect(t, issued)
        testing.expect(t, terminal_highlight_test_publish(&term, request))
    }
    terminal_highlight_observe_history(&term, 0, 1)
    _, duplicate := terminal_highlight_take_request(&term, 1)
    testing.expect(t, !duplicate)
    testing.expect(t, terminal_highlight_test_publish(&term, pending))
}
