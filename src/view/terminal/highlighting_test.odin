#+test

package terminalview

import model "model"
import protocol "../../core/protocol"
import termhist "../../terminal/history"
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
    runs := [1]protocol.Highlight_Run{{end_byte = u32(len(request.source))}}
    return terminal_highlight_publish(term, {
        identity = request.identity, source = request.source, runs = runs[:],
    })
}

// Commit source through ordinary grid/history ownership without starting evaluation.
terminal_highlight_test_submit :: proc(
    t: ^testing.T, term: ^model.Terminal_State, source: string) {
    testing.expect(t, termhist.termhist_insert_text(term.history, source))
    testing.expect_value(t, terminal_submit(term), source)
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
        runs := [1]protocol.Highlight_Run{{end_byte = 3}}
        source := request.source
        switch kind {
        case 0: runs[0].end_byte = 1
        case 1: runs[0].italic = 2
        case 2: source = "xxx"
        case 3: runs[0].foreground_kind = .Ansi; runs[0].foreground = 16
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
    entry := terminal_highlight_history_find(&term, request.identity.target_id)
    testing.expect(t,
        entry != nil && terminal_history_highlight_slot(&term, entry) != nil)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
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
    testing.expect(t, term.highlighting.eviction_count > 0)
    terminal_highlight_observe_history(&term, 0, 1)
    old, ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, ready)
    testing.expect_value(t, old.identity.target_id, term.history.history[0].id)
    testing.expect(t, terminal_highlight_test_publish(&term, old))
}

// Replacing provisional history assigns a new identity even if the bytes are unchanged.
@(test)
terminal_test_highlight_history_replacement :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_test_submit(t, &term, "begin")
    terminal_highlight_observe_history(&term, 0, 1)
    first, _ := terminal_highlight_take_request(&term, 1)
    termhist.termhist_insert_text(term.history, "begin")
    testing.expect(t, termhist.termhist_accept_current(term.history, 0, true))
    testing.expect(t, !terminal_highlight_test_publish(&term, first))
    testing.expect(t,
        terminal_highlight_history_find(&term, first.identity.target_id) == nil)
    terminal_highlight_observe_history(&term, 0, 1)
    _, retry := terminal_highlight_take_request(&term, 1)
    testing.expect(t, !retry)
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
    runs := [1]protocol.Highlight_Run{{end_byte = 1, weight = .Bold}}
    result := protocol.Highlight_Result{request.identity, request.source, runs[:]}
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
    termhist.termhist_insert_text(term.history, "end")
    _ = terminal_submit(&term)
    terminal_highlight_observe_history(&term, 0, 2)
    second, new_ready := terminal_highlight_take_request(&term, 1)
    testing.expect(t, new_ready && second.identity.target_id != first.identity.target_id)
    testing.expect_value(t, second.source, "begin\nend")
    testing.expect_value(t, term.history.history_len, 1)
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
    testing.expect_value(t, term.history.history_len, 2)
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
