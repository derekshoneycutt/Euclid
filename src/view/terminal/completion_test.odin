#+test
package terminalview

import viewterminalmodel "model"
import protocol "../../core/protocol"
import termhist "../../terminal/history"
import native "../native"
import "core:mem"
import "core:testing"

// Results at capacity are retained whole; oversized previews and lists retire visibly.
@(test)
terminal_test_completion_result_capacity :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    bytes := make([]u8, protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES + 1,
        context.allocator)
    defer delete(bytes, context.allocator)
    for &byte in bytes {
        byte = 'x'
    }
    request := terminal_request_completion(&term)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true, replacement_end = 4,
        insertion = string(bytes[:len(bytes) - 1]),
    }))
    testing.expect_value(t, len(term.completion_preview_insertion), len(bytes) - 1)
    for found in ([2]bool{false, true}) {
        request = terminal_request_completion(&term)
        testing.expect(t, !terminal_set_completion_preview(&term, {
            request_id = request.request_id, found = found, replacement_end = 4,
            insertion = string(bytes),
        }))
        testing.expect_value(t, term.pending_completion_request_id, 0)
        testing.expect_value(t, term.completion_preview_insertion, "")
        testing.expect_value(t, termhist.termhist_current_text(term.history), "func")
    }
}

// Oversized source is rejected without truncation, rescheduling, or draft mutation.
@(test)
terminal_test_completion_source_capacity :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    bytes := make([]u8, protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES + 1,
        context.allocator)
    defer delete(bytes, context.allocator)
    for &byte in bytes {
        byte = 'x'
    }
    testing.expect(t, termhist.termhist_insert_text(term.history,
        string(bytes[:len(bytes) - 1])))
    request := terminal_request_completion(&term)
    testing.expect(t, request.requested)
    testing.expect_value(t, len(request.code), len(bytes) - 1)
    testing.expect(t, termhist.termhist_insert_text(term.history, "x"))
    request = terminal_request_completion(&term)
    testing.expect(t, !request.requested)
    testing.expect_value(t, term.pending_completion_request_id, 0)
    testing.expect(t, !term.completion_request_scheduled)
    testing.expect_value(t, termhist.termhist_current_text(term.history), string(bytes))
    keyboard := terminal_update_keyboard_event(&term, {kind = .Press, key = .Tab}, "")
    _ = terminal_apply_keyboard_update(&term, keyboard, 1)
    testing.expect(t, !term.completion_request_scheduled)
    testing.expect(t, !terminal_take_scheduled_completion(&term, 2).requested)
}

// Byte ranges in multiline source preserve both surrounding lines and undo atomically.
@(test)
terminal_test_completion_multiline_acceptance :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    source := "α = 1\nprintl\nend"
    testing.expect(t, termhist.termhist_insert_text(term.history, source))
    testing.expect(t, termhist.termhist_set_cursor(term.history, 13))
    request := terminal_request_completion(&term)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true,
        replacement_start = 7, replacement_end = 13, insertion = "println",
    }))
    testing.expect(t, terminal_accept_completion_preview(&term))
    testing.expect_value(t, termhist.termhist_current_text(term.history),
        "α = 1\nprintln\nend")
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t, termhist.termhist_current_text(term.history), source)
    testing.expect_value(t, termhist.termhist_cursor(term.history), 13)
}

// Prefix previews are non-mutating, Right accepts, and Tab without a preview requests work.
@(test)
terminal_test_common_prefix_interaction :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    update := terminal_update_keyboard_event(&term, {kind = .Press, key = .Tab}, "")
    testing.expect(t, update.completion.requested && update.completion.show_candidates)
    request := terminal_request_completion(&term, false)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true,
        replacement_end = 4, insertion = "function",
    }))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "func")
    _ = terminal_update_keyboard_event(&term, {kind = .Press, key = .Right}, "")
    testing.expect_value(t, termhist.termhist_current_text(term.history), "function")
    update = terminal_update_keyboard_event(&term, {kind = .Press, key = .Tab}, "")
    testing.expect(t, update.completion.requested)
    testing.expect_value(t, update.completion.code, "function")
}

// Preview/request copies use established backing and never retain response views.
@(test)
terminal_test_completion_storage_reuse :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "func"))
    source_storage := raw_data(term.pending_completion_storage)
    preview_storage := raw_data(term.completion_preview_storage)
    storage: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    term.history.borrowed_allocator = mem.arena_allocator(&arena)
    for _ in 0..<10 {
        request := terminal_request_completion(&term, false)
        text := [8]u8{'f', 'u', 'n', 'c', 't', 'i', 'o', 'n'}
        testing.expect(t, terminal_set_completion_preview(&term, {
            request_id = request.request_id, found = true,
            replacement_end = 4, insertion = string(text[:]),
        }))
        text[0] = 'X'
        testing.expect_value(t, term.completion_preview_insertion, "function")
        testing.expect_value(t,
            raw_data(term.pending_completion_storage), source_storage)
        testing.expect_value(t,
            raw_data(term.completion_preview_storage), preview_storage)
    }
    term.history.borrowed_allocator = context.allocator
}

// Invalid grapheme ranges reject before renderer slicing or editable-source mutation.
@(test)
terminal_test_completion_invalid_range :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "α"))
    request := terminal_request_completion(&term)
    testing.expect(t, !terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true,
        replacement_start = 1, replacement_end = 2, insertion = "x",
    }))
    testing.expect_value(t, term.pending_completion_request_id, 0)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "α")
}

// Extension drawing starts after typed text, whereas Unicode replacement masks its source.
@(test)
terminal_test_completion_preview_draw_commands :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    vertices: [512]native.Draw_Vertex
    indices: [768]u32
    batches: [128]native.Draw_Batch
    commands: [128]native.Draw_Command
    encoder: native.Draw_Encoder
    sources := [2]string{"func", "\\alpha"}
    replacements := [2]string{"function", "α"}
    for source, index in sources {
        termhist.termhist_clear(term.history)
        testing.expect(t, termhist.termhist_insert_text(term.history, source))
        request := terminal_request_completion(&term, false)
        testing.expect(t, terminal_set_completion_preview(&term, {
            request_id = request.request_id, found = true,
            replacement_end = len(source), insertion = replacements[index],
        }))
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {400, 200}, {400, 200}))
        terminal_draw_completion_preview(&term, {
            encoder = &encoder, font = {base_size = 16, space_advance = 10},
            resolver = {resolve = terminal_syntax_test_font},
            theme = {completion_preview = {1, 2, 3, 255},
                cursor_foreground = {4, 5, 6, 255}},
        })
        testing.expect(t, encoder.vertex_count > 0)
        color := Color{1, 2, 3, 255} if index == 0 else Color{4, 5, 6, 255}
        testing.expect_value(t, vertices[0].color, color)
        expected_x := f32(109.5) if index == 0 else f32(70)
        testing.expect_value(t, vertices[0].position.x, expected_x)
    }
}
