package termemulator

import termgrid "../grid"
import termshellintegration "../shell_integration"

// Commit one exact OSC 133 payload at the grid's current logical position.
shell_integration_admit_marker :: proc(
    state: ^termshellintegration.Shell_Integration_State,
    grid: ^termgrid.Grid,
    payload: []u8,
    persistent := true) -> bool {
    if state == nil || grid == nil || len(payload) == 0 ||
        len(payload) > termshellintegration.SHELL_MARKER_PAYLOAD_BYTE_CAPACITY {
        if state != nil {
            state.marker_rejection_count += 1
        }
        return false
    }
    admission := termshellintegration.shell_integration_parse_marker(payload)
    if !admission.valid {
        state.marker_rejection_count += 1
        return false
    }
    markers := &grid.rows[grid.cursor.row].shell_markers
    markers.present[admission.kind] = true
    markers.columns[admission.kind] = u16(
        clamp(grid.cursor.column, 0, int(max(u16))))
    if admission.kind == .Finished {
        markers.finished_status = admission.status
        markers.finished_status_present = admission.status_present
    }
    if persistent {
        row := &grid.rows[grid.cursor.row]
        termshellintegration.shell_command_admit_marker(state, admission, {
            logical_line_id = row.logical_line_id,
            grapheme_offset = termgrid.grid_row_grapheme_offset(
                row, grid.cursor.column),
        })
    }
    state.marker_acceptance_count += 1
    return true
}