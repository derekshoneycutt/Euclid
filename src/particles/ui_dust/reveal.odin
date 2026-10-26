package ui_dust

import geometry "../../core/geometry"
import math "core:math"

// ui_dust_reveal_reset empties every occupancy bin and forgets prior rows.
ui_dust_reveal_reset :: proc(system: ^Ui_Dust_System) {
    for &bin in system^.reveal_bins {
        bin = {
            left = math.F32_MAX,
            right = -math.F32_MAX,
        }
    }
    system^.reveal_row_count = 0
}

// ui_dust_reveal_bin_height returns the logical height covered by one bin.
// Tall panes widen bins so the fixed bin count always spans the viewport.
ui_dust_reveal_bin_height :: proc(system: ^Ui_Dust_System) -> f32 {
    return max(UI_DUST_DRAW_IN_BIN_HEIGHT_MIN,
        system^.viewport.height / UI_DUST_DRAW_IN_ROW_BINS)
}

// ui_dust_reveal_include accumulates one new ink sample while draw-in awaits
// targets. Samples outside the viewport clamp into its first or last bin.
ui_dust_reveal_include :: proc(
    system: ^Ui_Dust_System, position: geometry.Vector2) {
    if !ui_dust_arrival_awaiting_targets(system) ||
        system^.incoming_style != .Draw_In || !system^.viewport_initialized {
        return
    }
    offset := (position.y - system^.viewport.y) / ui_dust_reveal_bin_height(system)
    index := clamp(int(offset), 0, UI_DUST_DRAW_IN_ROW_BINS - 1)
    bin := &system^.reveal_bins[index]
    bin^.left = min(bin^.left, position.x)
    bin^.right = max(bin^.right, position.x)
}

// ui_dust_reveal_build_rows converts accumulated bins into scheduled bands that
// tile the viewport. Returns false when no ink was included.
ui_dust_reveal_build_rows :: proc(system: ^Ui_Dust_System) -> bool {
    ui_dust_reveal_collect_rows(system)
    count := system^.reveal_row_count
    if count == 0 {
        return false
    }
    for index in 0..<count - 1 {
        upper := &system^.reveal_rows[index]
        lower := &system^.reveal_rows[index + 1]
        middle := (upper^.bottom + lower^.top) / 2
        upper^.bottom = middle
        lower^.top = middle
    }
    system^.reveal_rows[0].top = system^.viewport.y
    system^.reveal_rows[count - 1].bottom =
        system^.viewport.y + system^.viewport.height
    ui_dust_reveal_schedule_rows(system)
    return true
}

// ui_dust_reveal_collect_rows merges occupied bins separated by at most the row
// gap into ink rows. Rows past the fixed budget extend the final row.
ui_dust_reveal_collect_rows :: proc(system: ^Ui_Dust_System) {
    bin_height := ui_dust_reveal_bin_height(system)
    gap_bins := int(UI_DUST_DRAW_IN_ROW_GAP / bin_height)
    count := 0
    empty_run := 0
    for bin, index in system^.reveal_bins {
        if bin.left > bin.right {
            empty_run += 1
            continue
        }
        top := system^.viewport.y + f32(index) * bin_height
        if count > 0 && (empty_run <= gap_bins || count == UI_DUST_DRAW_IN_MAX_ROWS) {
            row := &system^.reveal_rows[count - 1]
            row^.bottom = top + bin_height
            row^.left = min(row^.left, bin.left)
            row^.right = max(row^.right, bin.right)
        } else {
            system^.reveal_rows[count] = {
                top = top,
                bottom = top + bin_height,
                left = bin.left,
                right = bin.right,
            }
            count += 1
        }
        empty_run = 0
    }
    system^.reveal_row_count = count
}

// ui_dust_reveal_schedule_rows staggers row starts with substantial overlap and
// scales sweeps by row width, so the whole reveal ends within the fixed duration.
ui_dust_reveal_schedule_rows :: proc(system: ^Ui_Dust_System) {
    count := system^.reveal_row_count
    widest := f32(0)
    for row in system^.reveal_rows[:count] {
        widest = max(widest, row.right - row.left)
    }
    stagger := UI_DUST_DRAW_IN_ROW_STAGGER_MAX
    if count > 1 {
        stagger = min(stagger,
            (UI_DUST_DRAW_IN_DURATION - UI_DUST_DRAW_IN_ROW_SWEEP) / f32(count - 1))
    }
    for &row, index in system^.reveal_rows[:count] {
        fraction := f32(1)
        if widest > 0 {
            fraction = (row.right - row.left) / widest
        }
        row.start = f32(index) * stagger
        row.sweep = UI_DUST_DRAW_IN_ROW_SWEEP *
            max(UI_DUST_DRAW_IN_ROW_SWEEP_MIN_FRACTION, fraction)
    }
}

// ui_dust_reveal_active reports whether draw-in bands currently mask content.
ui_dust_reveal_active :: proc(system: ^Ui_Dust_System) -> bool {
    return system != nil && system^.incoming_active &&
        system^.incoming_style == .Draw_In && !system^.incoming_awaiting_targets
}

// ui_dust_reveal_progress returns one row's eased sweep progress in [0, 1].
ui_dust_reveal_progress :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    row := system^.reveal_rows[index]
    if row.sweep <= 0 {
        return 1
    }
    raw := clamp((system^.incoming_elapsed - row.start) / row.sweep, 0, 1)
    return (1 - math.cos(math.PI * raw)) / 2
}

// ui_dust_reveal_front returns the x where one row's feathered mask begins.
// The front starts one feather left of the ink, so no ink shows at progress 0,
// and ends at the ink's right edge, so all ink shows at progress 1.
ui_dust_reveal_front :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    row := system^.reveal_rows[index]
    start := row.left - UI_DUST_DRAW_IN_FEATHER
    return start + (row.right - start) * ui_dust_reveal_progress(system, index)
}

// ui_dust_reveal_contact_time returns when the feather's midpoint reaches an ink
// position, inverting the row's eased sweep.
ui_dust_reveal_contact_time :: proc(
    system: ^Ui_Dust_System, position: geometry.Vector2) -> f32 {
    count := system^.reveal_row_count
    if count == 0 {
        return 0
    }
    index := count - 1
    for row, candidate in system^.reveal_rows[:count] {
        if position.y < row.bottom {
            index = candidate
            break
        }
    }
    row := system^.reveal_rows[index]
    span := row.right - row.left + UI_DUST_DRAW_IN_FEATHER
    eased := clamp(
        (position.x - row.left + UI_DUST_DRAW_IN_FEATHER / 2) / span, 0, 1)
    return row.start + row.sweep * math.acos(1 - 2 * eased) / math.PI
}
