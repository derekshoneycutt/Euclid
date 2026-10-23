#+test

package terminalview

import protocol "../../core/protocol"
import termhist "../../terminal/history"
import model "model"
import "core:testing"

// Seed distinct native appearances using the real exact-result publication path.
terminal_presentation_test_seed :: proc(
    t: ^testing.T, term: ^model.Terminal_State, source: string) {
    terminal_highlight_test_init(t, term)
    testing.expect(t, termhist.termhist_insert_text(term.history, source))
    terminal_highlight_observe_live(term, 0)
    request, ready := terminal_highlight_take_request(term, 1)
    testing.expect(t, ready)
    runs := [1]protocol.Highlight_Run{{
        end_byte = u32(len(source)), foreground_kind = .Rgb,
        foreground = 0x123456, weight = .Bold, italic = 1,
    }}
    testing.expect(t, terminal_highlight_publish(term,
        {request.identity, request.source, runs[:]}))
}

// Check source coverage and exact RGB/default appearance through the renderer-facing view.
terminal_presentation_test_colors :: proc(
    t: ^testing.T, term: ^model.Terminal_State, expected: []u32) {
    runs := terminal_live_highlight_runs(term)
    source := termhist.termhist_current_text(term.history)
    testing.expect_value(t, len(source), len(expected))
    offset := u32(0)
    for run in runs {
        testing.expect_value(t, run.start_byte, offset)
        testing.expect(t, run.end_byte > run.start_byte)
        testing.expect(t, protocol.highlight_run_style_valid(run))
        offset = run.end_byte
    }
    testing.expect_value(t, offset, u32(len(source)))
    for color, index in expected {
        run := terminal_syntax_run_at(runs, index)
        testing.expect_value(t, run.foreground, color)
        testing.expect_value(t, run.weight,
            protocol.Highlight_Weight.Bold if color != 0 else .Normal)
    }
}

// Insertions retain both edges during debounce, pending work, and exact replacement.
@(test)
terminal_test_presentation_insert_pending :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    term.history.cursor = 2
    testing.expect(t, termhist.termhist_insert_text(term.history, "XY"))
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
    terminal_highlight_observe_live(&term, 2)
    colors := [6]u32{0x123456, 0x123456, 0, 0, 0x123456, 0x123456}
    terminal_presentation_test_colors(t, &term, colors[:])
    _, early := terminal_highlight_take_request(&term, 2.1)
    testing.expect(t, !early)
    request, ready := terminal_highlight_take_request(&term, 3)
    testing.expect(t, ready)
    terminal_presentation_test_colors(t, &term, colors[:])
    testing.expect(t, !term.highlighting.presentation.authoritative)
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    testing.expect(t, term.highlighting.presentation.authoritative)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 1)
}

// Further edits use the last provisional snapshot rather than resurrecting old styles.
@(test)
terminal_test_presentation_repeated_edits :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 1, 2, "X"))
    terminal_highlight_observe_live(&term, 2)
    first, _ := terminal_highlight_take_request(&term, 3)
    first_source := "aXcd"
    first.source = first_source
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 2, 3, "Y"))
    terminal_highlight_observe_live(&term, 4)
    colors := [4]u32{0x123456, 0, 0, 0x123456}
    terminal_presentation_test_colors(t, &term, colors[:])
    testing.expect(t, !terminal_highlight_test_publish(&term, first))
    terminal_presentation_test_colors(t, &term, colors[:])
    second, ready := terminal_highlight_take_request(&term, 5)
    testing.expect(t, ready)
    testing.expect(t,
        terminal_highlight_fail(&term, {second.identity, .Transport_Capacity}))
    terminal_presentation_test_colors(t, &term, colors[:])
    terminal_highlight_observe_live(&term, 6)
    _, retry := terminal_highlight_take_request(&term, 7)
    testing.expect(t, !retry)
}

// Deletions coalesce retained styles; replacements and batched edits only default the middle.
@(test)
terminal_test_presentation_edit_ranges :: proc(t: ^testing.T) {
    for variant in 0..<5 {
        term: model.Terminal_State
        terminal_presentation_test_seed(t, &term, "abcdef")
        switch variant {
        case 0: _ = termhist.termhist_replace_input_range(term.history, 0, 0, "X")
        case 1: _ = termhist.termhist_insert_text(term.history, "X")
        case 2: _ = termhist.termhist_replace_input_range(term.history, 2, 4, "")
        case 3: _ = termhist.termhist_replace_input_range(term.history, 2, 4, "XY")
        case 4:
            _ = termhist.termhist_replace_input_range(term.history, 1, 2, "X")
            _ = termhist.termhist_replace_input_range(term.history, 4, 5, "Y")
        }
        terminal_highlight_observe_live(&term, 2)
        runs := terminal_live_highlight_runs(&term)
        testing.expect(t, len(runs) > 0)
        if variant == 2 {
            testing.expect_value(t, len(runs), 1)
            testing.expect_value(t, runs[0].end_byte, u32(4))
        } else {
            middle := 0 if variant == 0 else 6 if variant == 1 else
                2 if variant == 3 else 3
            testing.expect_value(t,
                terminal_syntax_run_at(runs, middle).foreground, u32(0))
        }
        terminal_destroy(&term, context.allocator)
    }
}

// Shared leading/trailing UTF-8 bytes never retain styles on partial codepoints.
@(test)
terminal_test_presentation_unicode_edges :: proc(t: ^testing.T) {
    prefix, suffix := terminal_highlight_unchanged_edges("aαz", "aβz")
    testing.expect_value(t, prefix, 1)
    testing.expect_value(t, suffix, 1)
    prefix, suffix = terminal_highlight_unchanged_edges("aαz", "aѱz")
    testing.expect_value(t, prefix, 1)
    testing.expect_value(t, suffix, 1)
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "aα\n界e\u0301z")
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 1, 3, "β"))
    terminal_highlight_observe_live(&term, 2)
    runs := terminal_live_highlight_runs(&term)
    testing.expect_value(t, runs[0].end_byte, u32(1))
    testing.expect_value(t, runs[1].start_byte, u32(1))
    testing.expect_value(t, runs[1].end_byte, u32(3))
    testing.expect_value(t, runs[2].start_byte, u32(3))
    testing.expect_value(t, runs[2].end_byte, u32(len("aβ\n界e\u0301z")))
}

// Whole-buffer resets and visibility boundaries cannot carry unrelated decoration.
@(test)
terminal_test_presentation_reset_boundaries :: proc(t: ^testing.T) {
    for variant in 0..<6 {
        term: model.Terminal_State
        terminal_presentation_test_seed(t, &term, "abcd")
        switch variant {
        case 0:
            termhist.termhist_clear(term.history)
            _ = termhist.termhist_insert_text(term.history, "abcd")
        case 1: _ = termhist.termhist_load_entry(
            term.history, term.history.text[:term.history.text_len])
        case 2: term.input_mode = .Help
        case 3: term.awaiting_eval = true
        case 4: _ = terminal_highlight_set_face_generation(&term, 2)
        case 5: term.animation_generation += 1
        }
        terminal_highlight_observe_live(&term, 2)
        testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
        terminal_destroy(&term, context.allocator)
    }
}

// Malformed current publications report rejection without erasing mapped decoration.
@(test)
terminal_test_presentation_malformed_result :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "X"))
    terminal_highlight_observe_live(&term, 2)
    request, ready := terminal_highlight_take_request(&term, 3)
    testing.expect(t, ready)
    runs := [1]protocol.Highlight_Run{{end_byte = 1}}
    testing.expect(t, !terminal_highlight_publish(&term,
        {request.identity, request.source, runs[:]}))
    colors := [5]u32{0x123456, 0x123456, 0x123456, 0x123456, 0}
    terminal_presentation_test_colors(t, &term, colors[:])
    testing.expect_value(t, term.highlighting.rejected_count, u64(1))
}

// Clipping preserves distinct appearances on both sides of a multi-run replacement.
@(test)
terminal_test_presentation_distinct_runs :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcdef")
    defer terminal_destroy(&term, context.allocator)
    terminal_highlight_invalidate(&term)
    terminal_highlight_observe_live(&term, 1)
    request, _ := terminal_highlight_take_request(&term, 2)
    runs := [3]protocol.Highlight_Run{
        {end_byte = 2, foreground_kind = .Rgb, foreground = 1},
        {start_byte = 2, end_byte = 4, foreground_kind = .Rgb, foreground = 2},
        {start_byte = 4, end_byte = 6, foreground_kind = .Rgb, foreground = 3},
    }
    testing.expect(t, terminal_highlight_publish(&term,
        {request.identity, request.source, runs[:]}))
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 1, 5, "X"))
    terminal_highlight_observe_live(&term, 3)
    mapped := terminal_live_highlight_runs(&term)
    testing.expect_value(t, len(mapped), 3)
    testing.expect_value(t, mapped[0].foreground, u32(1))
    testing.expect_value(t, mapped[1].foreground, u32(0))
    testing.expect_value(t, mapped[2].foreground, u32(3))
    testing.expect_value(t, mapped[2].start_byte, u32(2))
}

// Maximum fragmentation degrades only the unrepresentable tail and keeps complete coverage.
@(test)
terminal_test_presentation_run_capacity :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_highlight_test_init(t, &term)
    defer terminal_destroy(&term, context.allocator)
    source := make([]u8, protocol.TERMINAL_HIGHLIGHT_RUN_CAPACITY, context.allocator)
    defer delete(source, context.allocator)
    for &byte in source {
        byte = 'x'
    }
    testing.expect(t, termhist.termhist_insert_text(term.history, string(source)))
    terminal_highlight_observe_live(&term, 0)
    request, _ := terminal_highlight_take_request(&term, 1)
    runs := make([]protocol.Highlight_Run, len(source), context.allocator)
    defer delete(runs, context.allocator)
    for &run, index in runs {
        run = {start_byte = u32(index), end_byte = u32(index + 1),
            foreground_kind = .Rgb, foreground = u32(index % 2 + 1)}
    }
    testing.expect(t, terminal_highlight_publish(&term,
        {request.identity, request.source, runs}))
    term.history.cursor = 1
    testing.expect(t, termhist.termhist_insert_text(term.history, "XY"))
    terminal_highlight_observe_live(&term, 2)
    mapped := terminal_live_highlight_runs(&term)
    testing.expect_value(t, len(mapped), protocol.TERMINAL_HIGHLIGHT_RUN_CAPACITY)
    testing.expect_value(t, mapped[0].foreground, u32(1))
    testing.expect_value(t, mapped[len(mapped) - 1].foreground_kind,
        protocol.Highlight_Color_Kind.Default)
    testing.expect(t, term.highlighting.presentation.degradation_reported)
    offset := u32(0)
    for run in mapped {
        testing.expect_value(t, run.start_byte, offset)
        testing.expect(t, run.end_byte > offset)
        offset = run.end_byte
    }
    testing.expect_value(t, offset, u32(len(source) + 2))
}

// Pending saturation and identical-byte edits preserve colors without accepting old revisions.
@(test)
terminal_test_presentation_pending_saturation :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    for index in 0..<model.TERMINAL_HIGHLIGHT_PENDING_CAPACITY {
        testing.expect(t, termhist.termhist_replace_input_range(term.history, 1, 2, "b"))
        terminal_highlight_observe_live(&term, f64(index * 2 + 2))
        _, ready := terminal_highlight_take_request(&term, f64(index * 2 + 3))
        testing.expect(t, ready)
    }
    term.history.cursor = term.history.text_len
    testing.expect(t, termhist.termhist_insert_text(term.history, "X"))
    terminal_highlight_observe_live(&term, 20)
    _, full := terminal_highlight_take_request(&term, 21)
    testing.expect(t, !full)
    colors := [5]u32{0x123456, 0x123456, 0x123456, 0x123456, 0}
    terminal_presentation_test_colors(t, &term, colors[:])
}

// Recall/draft restoration reset styles even when the recalled command shares all its bytes.
@(test)
terminal_test_presentation_recall_and_delete_all :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_history_push(term.history, "abcd"))
    testing.expect(t, termhist.termhist_history_prev(term.history))
    terminal_highlight_observe_live(&term, 2)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
    request, _ := terminal_highlight_take_request(&term, 3)
    testing.expect(t, terminal_highlight_test_publish(&term, request))
    testing.expect(t, termhist.termhist_history_next(term.history))
    terminal_highlight_observe_live(&term, 4)
    testing.expect_value(t, len(terminal_live_highlight_runs(&term)), 0)
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 0, 4, ""))
    terminal_highlight_observe_live(&term, 5)
    testing.expect_value(t, term.highlighting.presentation.source_length, 0)
}

// Real completion and clipboard insertion preserve surrounding styles without resetting input.
@(test)
terminal_test_presentation_completion_and_paste :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "x=\\alpha")
    defer terminal_destroy(&term, context.allocator)
    completion := terminal_request_completion(&term)
    testing.expect(t, completion.requested)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = completion.request_id, found = true,
        replacement_start = 2, replacement_end = len("x=\\alpha"), insertion = "α",
    }))
    testing.expect(t, terminal_accept_completion_preview(&term))
    terminal_highlight_observe_live(&term, 2)
    completed := [4]u32{0x123456, 0x123456, 0, 0}
    terminal_presentation_test_colors(t, &term, completed[:])
    testing.expect(t, terminal_insert_clipboard_text(&term, "β"))
    terminal_highlight_observe_live(&term, 3)
    pasted := [6]u32{0x123456, 0x123456, 0, 0, 0, 0}
    terminal_presentation_test_colors(t, &term, pasted[:])
    term.history.cursor = 0
    terminal_highlight_observe_live(&term, 4)
    terminal_presentation_test_colors(t, &term, pasted[:])
}
