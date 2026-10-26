package ui_dust

import geometry "../../core/geometry"

// Ui_Dust_Crisp_Visibility retains mask opacity before a replacement releases arrivals.
Ui_Dust_Crisp_Visibility :: struct {
    alpha: f32,
    row_count: int,
    rows: [UI_DUST_DRAW_IN_MAX_ROWS]Ui_Dust_Reveal_Row,
    fronts: [UI_DUST_DRAW_IN_MAX_ROWS]f32,
    progress: [UI_DUST_DRAW_IN_MAX_ROWS]f32,
}

// ui_dust_crisp_visibility freezes the ordinary drawing's currently revealed portion.
ui_dust_crisp_visibility :: proc(system: ^Ui_Dust_System) -> Ui_Dust_Crisp_Visibility {
    result: Ui_Dust_Crisp_Visibility = {
        alpha = ui_dust_incoming_alpha(system),
    }
    if ui_dust_reveal_active(system) {
        result.row_count = system^.reveal_row_count
        result.rows = system^.reveal_rows
        for index in 0..<result.row_count {
            result.fronts[index] = ui_dust_reveal_front(system, index)
            result.progress[index] = ui_dust_reveal_progress(system, index)
        }
    }
    return result
}

// ui_dust_crisp_sample_alpha mirrors the renderer's stepped draw-in feather exactly.
ui_dust_crisp_sample_alpha :: proc(
    visibility: ^Ui_Dust_Crisp_Visibility, position: geometry.Vector2) -> f32 {
    for row, index in visibility^.rows[:visibility^.row_count] {
        if position.y < row.top || position.y >= row.bottom {
            continue
        }
        if visibility^.progress[index] >= 1 {
            return visibility^.alpha
        }
        front := visibility^.fronts[index]
        if visibility^.progress[index] <= 0 ||
            position.x >= front + UI_DUST_DRAW_IN_FEATHER {
            return 0
        }
        if position.x < front {
            return visibility^.alpha
        }
        step := int((position.x - front) /
            (UI_DUST_DRAW_IN_FEATHER / UI_DUST_DRAW_IN_FEATHER_STEPS))
        cover := u8(255 * (step + 1) / (UI_DUST_DRAW_IN_FEATHER_STEPS + 1))
        return visibility^.alpha * (1 - f32(cover) / 255)
    }
    return visibility^.alpha
}
