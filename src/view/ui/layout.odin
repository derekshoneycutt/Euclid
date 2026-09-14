package ui

import viewmodel "../model"


import rl "vendor:raylib"

//   Build the non-negative Terminal content rectangle inside the text panel.
layout_terminal_rect :: proc(text_rect: rl.Rectangle) -> rl.Rectangle {
    return clamp_non_negative_rect({
        text_rect.x + 6,
        text_rect.y + 6,
        text_rect.width - 12,
        text_rect.height - 12,
    })
}

//   Compute UI regions from clamped vertical and horizontal split coordinates.
compute_ui_regions :: proc(
    mode: viewmodel.Ui_Layout_Mode,
    vertical_split_x, horizontal_split_y: f32) -> viewmodel.Ui_Regions {
    regions := viewmodel.Ui_Regions{}
    split_x := clamp(vertical_split_x, f32(WORLD_MIN_WIDTH),
        f32(WINDOW_WIDTH - RIGHT_PANEL_MIN_WIDTH))
    split_y := clamp(horizontal_split_y, f32(WORLD_MIN_HEIGHT),
        f32(WINDOW_HEIGHT - BOTTOM_PANEL_MIN_HEIGHT))

    switch mode {
    case .Baseline:
        regions.world_rect = rl.Rectangle{0, 0, split_x, split_y}

        regions.accordion_rect = rl.Rectangle{
            split_x + TREE_PANEL_PADDING,
            TREE_PANEL_PADDING,
            f32(WINDOW_WIDTH) - split_x - TREE_PANEL_PADDING * 2,
            WINDOW_HEIGHT - TREE_PANEL_PADDING * 2,
        }

        regions.text_rect = rl.Rectangle{
            TREE_PANEL_PADDING,
            split_y + TREE_PANEL_PADDING,
            split_x - TREE_PANEL_PADDING * 2,
            f32(WINDOW_HEIGHT) - split_y - TREE_PANEL_PADDING * 2,
        }

        regions.terminal_rect = layout_terminal_rect(regions.text_rect)
    }

    return regions
}

//   Validate region geometry before draw dispatch.
//   Report whether one rectangle has non-negative dimensions.
ui_rect_valid :: #force_inline proc(rect: rl.Rectangle) -> bool {
    return rect.width >= 0 && rect.height >= 0
}

//   Validate that every UI region has non-negative dimensions.
validate_ui_regions :: proc(regions: viewmodel.Ui_Regions) -> bool {
    rects := [?]rl.Rectangle{
        regions.world_rect,
        regions.accordion_rect,
        regions.text_rect,
        regions.terminal_rect,
    }
    for rect in rects {
        if !ui_rect_valid(rect) {
            return false
        }
    }

    return true
}
