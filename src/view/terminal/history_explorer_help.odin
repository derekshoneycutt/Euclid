package terminalview

import viewterminalmodel "model"
import termhist "../../terminal/history"
import input "../input"
import "core:strings"

// Only the entire whitespace-trimmed query selects help; embedded question marks search.
history_explorer_help_kind :: proc(
    query: string) -> viewterminalmodel.History_Explorer_Help {
    text := strings.trim_space(query)
    if text == "?" {
        return .Short
    }
    if text == "??" {
        return .Extended
    }
    return .None
}

// Save only query bytes and selection; page, preview, and scroll stay in their existing owner.
history_explorer_save_query :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) {
    if explorer.help != .None {
        return
    }
    query := &explorer.query_editor
    text := termhist.termhist_current_text(query)
    copy(explorer.saved_query[:], text)
    explorer.saved_query_length = len(text)
    explorer.saved_query_cursor = query.cursor
    explorer.saved_query_anchor = query.anchor
}

// Restore the suspended editor; the service revalidates runtime identity before publication/recall.
history_explorer_restore_query :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) -> bool {
    if !termhist.termhist_load_entry(&explorer.query_editor,
        explorer.saved_query[:explorer.saved_query_length]) {
        explorer.status = .Capacity
        explorer.status_failure.kind = .Capacity
        return false
    }
    _ = termhist.termhist_set_cursor(&explorer.query_editor, explorer.saved_query_anchor)
    _ = termhist.termhist_set_cursor(
        &explorer.query_editor, explorer.saved_query_cursor, true)
    explorer.help = .None
    explorer.accept_requested = false
    return true
}

// Help consumes recall and candidate navigation; scrolling never changes the suspended page.
history_explorer_help_key :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> bool {
    if explorer.help == .None {
        return false
    }
    if event.key == .Escape {
        _ = history_explorer_restore_query(explorer)
        return true
    }
    if event.key == .Enter || event.key == .Keypad_Enter {
        return true
    }
    if event.key == .Up || event.key == .Down ||
       event.key == .Page_Up || event.key == .Page_Down {
        delta := -1 if event.key == .Up || event.key == .Page_Up else 1
        if event.key == .Page_Up || event.key == .Page_Down {
            delta *= 8
        }
        explorer.help_scroll_lines = max(0, explorer.help_scroll_lines + delta)
        return true
    }
    return event.modifiers == {.Control} &&
        (event.key == .P || event.key == .N || event.key == .V) ||
        .Alt in event.modifiers
}
