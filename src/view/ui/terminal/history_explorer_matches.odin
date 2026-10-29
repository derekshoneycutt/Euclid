package uiterminal

import content "../../../core/content"
import termhistsearch "../../../terminal/history/search"
import termhiststore "../../../terminal/history/store"
import geometry "../../../core/geometry"
import viewterminalmodel "../../terminal/model"
import native "../../native"
import theme "../theme"

// Intersect original byte intervals, expanding partial matches to a complete display grapheme.
terminal_explorer_fragment_matches :: proc(
    fragment: Terminal_Explorer_Text_Fragment,
    ranges: []termhistsearch.Search_Range) -> bool {
    for span in ranges {
        if span.start_byte < fragment.source_end &&
           span.end_byte > fragment.source_start {
            return true
        }
    }
    return false
}

// Overlines occupy a separate rail from syntax underlines and never replace syntax faces.
terminal_explorer_draw_match :: proc(
    draw: Terminal_Explorer_Draw, source_draw: Terminal_Explorer_Source_Draw,
    fragment: Terminal_Explorer_Text_Fragment, position: geometry.Vector2) {
    if !terminal_explorer_fragment_matches(fragment, source_draw.matches) {
        return
    }
    rail: geometry.Rectangle = {
        position.x, position.y,
        f32(fragment.columns)*draw.prepared.layout.column_width, 1,
    }
    _ = native.draw_encoder_rectangle(
        draw.encoder, rail, theme.draw_color(draw.encoder, .Text))
}

// Keep skipped patterns informational, and distinguish real failures from unavailable emphasis.
terminal_explorer_status_message :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) -> content.Content_Message_Id {
    if explorer.status == .Failed {
        return terminal_explorer_failure_message(explorer.status_failure)
    }
    if explorer.status == .Ready || explorer.status == .Empty {
        if explorer.preview_status == .Ready &&
           explorer.preview_matches.failure.kind != .None {
            return .Terminal_History_Ranges_Failed
        }
        for row in explorer.rows[:explorer.row_count] {
            if row.matches.failure.kind != .None {
                return .Terminal_History_Ranges_Failed
            }
        }
        if explorer.skipped_regex_count > 0 {
            return .Terminal_History_Skipped
        }
    }
    return terminal_explorer_status_id(explorer.status)
}

// Distinguish execution failures without treating skipped patterns as query failures.
terminal_explorer_failure_message :: proc(
    failure: termhiststore.History_Store_Error) -> content.Content_Message_Id {
    #partial switch failure.kind {
    case .Cancelled:
        return .Terminal_History_Cancelled
    case .Sqlite:
        return .Terminal_History_Sql_Failed
    case .Search:
        if failure.search_error == .Invalid_Query || failure.search_error == .Capacity {
            return .Terminal_History_Invalid_Query
        }
        return .Terminal_History_Resource_Failed
    }
    return .Terminal_History_Failed
}
