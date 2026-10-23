package terminalview

import protocol "../../core/protocol"
import termhist "../../terminal/history"
import model "model"
import "core:log"
import "core:unicode/utf8"

// Forget decoration without clearing large retained buffers or pending bridge transactions.
terminal_highlight_clear_presentation :: proc(term: ^model.Terminal_State) {
    p := &term.highlighting.presentation
    p.source_length = 0
    p.run_count = 0
    p.authoritative = false
}

// Check presentation identity even when an edit precedes the next scheduling update.
terminal_highlight_presentation_current :: proc(term: ^model.Terminal_State) -> bool {
    p := &term.highlighting.presentation
    return p.source_length > 0 && term.history != nil &&
        terminal_prompt_visible(term) && term.input_mode == .Normal &&
        p.identity.animation_generation == term.animation_generation &&
        p.identity.face_generation == term.highlighting.face_generation &&
        p.identity.source_revision ==
            termhist.termhist_content_revision(term.history) + 1 &&
        p.reset_revision == termhist.termhist_reset_revision(term.history) &&
        string(p.source[:p.source_length]) ==
            termhist.termhist_current_text(term.history)
}

// Find non-overlapping unchanged edges, excluding partially matching UTF-8 codepoints.
terminal_highlight_unchanged_edges :: proc(old, source: string) -> (int, int) {
    prefix := 0
    for prefix < min(len(old), len(source)) && old[prefix] == source[prefix] {
        prefix += 1
    }
    for prefix > 0 && prefix < len(old) && old[prefix] & 0xc0 == 0x80 {
        prefix -= 1
    }
    suffix := 0
    for suffix < min(len(old), len(source)) - prefix &&
        old[len(old) - suffix - 1] == source[len(source) - suffix - 1] {
        suffix += 1
    }
    for suffix > 0 && old[len(old) - suffix] & 0xc0 == 0x80 {
        suffix -= 1
    }
    return prefix, suffix
}

// Append coalesced coverage, reserving a default tail if bounded scratch becomes full.
terminal_highlight_append_presentation :: proc(
    p: ^model.Terminal_Highlight_Presentation,
    run: protocol.Highlight_Run,
    source_length: int) {
    if run.start_byte == run.end_byte || p.degraded {
        return
    }
    if p.scratch_count > 0 {
        previous := p.scratch[p.scratch_count - 1]
        previous.start_byte = run.start_byte
        previous.end_byte = run.end_byte
        if previous == run {
            p.scratch[p.scratch_count - 1].end_byte = run.end_byte
            return
        }
    }
    next := run
    if p.scratch_count == len(p.scratch) - 1 && int(run.end_byte) < source_length {
        next = {start_byte = run.start_byte, end_byte = u32(source_length)}
        p.degraded = true
        if !p.degradation_reported {
            log.warn(
                "terminal provisional highlight capacity exhausted; remaining styles are plain")
            p.degradation_reported = true
        }
    }
    p.scratch[p.scratch_count] = next
    p.scratch_count += 1
}

// Copy only retained source intervals, translating suffix styles into current byte space.
terminal_highlight_map_interval :: proc(
    p: ^model.Terminal_Highlight_Presentation,
    start, end, delta, source_length: int) {
    for original in p.runs[:p.run_count] {
        first := max(int(original.start_byte), start)
        last := min(int(original.end_byte), end)
        if first >= last {
            continue
        }
        run := original
        run.start_byte = u32(first + delta)
        run.end_byte = u32(last + delta)
        terminal_highlight_append_presentation(p, run, source_length)
        if p.degraded {
            break
        }
    }
}

// Map the last displayed snapshot, never resurrecting styles from an older exact result.
terminal_highlight_map_presentation :: proc(
    p: ^model.Terminal_Highlight_Presentation, source: string) {
    old := string(p.source[:p.source_length])
    prefix, suffix := terminal_highlight_unchanged_edges(old, source)
    p.scratch_count = 0
    p.degraded = false
    terminal_highlight_map_interval(p, 0, prefix, 0, len(source))
    terminal_highlight_append_presentation(p, {
        start_byte = u32(prefix), end_byte = u32(len(source) - suffix),
    }, len(source))
    terminal_highlight_map_interval(p, len(old) - suffix, len(old),
        len(source) - len(old), len(source))
    copy(p.runs[:], p.scratch[:p.scratch_count])
    p.run_count = p.scratch_count
    p.authoritative = false
}

// Synchronize safe decoration before drawing; source bounds retain the plain-text policy.
terminal_highlight_observe_presentation :: proc(
    term: ^model.Terminal_State,
    source: string, revision, reset_revision: u64) {
    p := &term.highlighting.presentation
    if len(source) == 0 || len(source) > len(p.source) || !utf8.valid_string(source) {
        terminal_highlight_clear_presentation(term)
        return
    }
    if p.reset_revision != reset_revision ||
        p.identity.animation_generation != term.animation_generation ||
        p.identity.face_generation != term.highlighting.face_generation {
        terminal_highlight_clear_presentation(term)
    }
    if p.source_length > 0 && p.run_count > 0 {
        terminal_highlight_map_presentation(p, source)
    }
    copy(p.source[:], transmute([]u8)source)
    p.source_length = len(source)
    p.reset_revision = reset_revision
    p.identity = {
        animation_generation = term.animation_generation,
        source_revision = revision, face_generation = term.highlighting.face_generation,
    }
}

// Install exact styles only after full result validation, copying all producer-owned storage.
terminal_highlight_publish_presentation :: proc(
    term: ^model.Terminal_State, result: protocol.Highlight_Result) {
    p := &term.highlighting.presentation
    copy(p.source[:], transmute([]u8)result.source)
    copy(p.runs[:], result.runs)
    p.source_length = len(result.source)
    p.run_count = len(result.runs)
    p.identity = result.identity
    p.reset_revision = termhist.termhist_reset_revision(term.history)
    p.authoritative = true
}
