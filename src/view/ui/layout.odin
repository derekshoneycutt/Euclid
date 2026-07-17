package ui

import "../../core"

import rl "vendor:raylib"

//   Compute baseline UI region mapping for the current layout mode.
compute_ui_regions :: proc(mode: core.Ui_Layout_Mode) -> core.Ui_Regions {
    regions := core.Ui_Regions{}

    switch mode {
    case .Baseline:
        regions.world_rect = rl.Rectangle{0, 0, VIEW_WIDTH, VIEW_HEIGHT}

        regions.tree_rect = rl.Rectangle{
            VIEW_WIDTH + TREE_PANEL_PADDING,
            TREE_PANEL_PADDING,
            RIGHT_BAR_WIDTH - TREE_PANEL_PADDING * 2,
            WINDOW_HEIGHT - TREE_PANEL_PADDING * 2,
        }

        regions.text_rect = rl.Rectangle{
            TREE_PANEL_PADDING,
            VIEW_HEIGHT + TREE_PANEL_PADDING,
            VIEW_WIDTH - TREE_PANEL_PADDING * 2,
            BOTTOM_BAR_HEIGHT - TREE_PANEL_PADDING * 2,
        }

        _, list_panel := build_tree_view_panels(regions.tree_rect)
        regions.settings_rect = list_panel
        regions.gif_rect = list_panel

        text_inner := rl.Rectangle{
            regions.text_rect.x + 6,
            regions.text_rect.y + 6,
            regions.text_rect.width - 12,
            regions.text_rect.height - 12,
        }
        if text_inner.width < 0 {
            text_inner.width = 0
        }
        if text_inner.height < 0 {
            text_inner.height = 0
        }
        regions.scratchpad_rect = text_inner
    }

    return regions
}

//   Validate region geometry before draw dispatch.
validate_ui_regions :: proc(regions: core.Ui_Regions) -> bool {
    if regions.world_rect.width < 0 || regions.world_rect.height < 0 {
        return false
    }

    if regions.tree_rect.width < 0 || regions.tree_rect.height < 0 {
        return false
    }

    if regions.text_rect.width < 0 || regions.text_rect.height < 0 {
        return false
    }

    if regions.settings_rect.width < 0 || regions.settings_rect.height < 0 {
        return false
    }

    if regions.gif_rect.width < 0 || regions.gif_rect.height < 0 {
        return false
    }

    if regions.scratchpad_rect.width < 0 || regions.scratchpad_rect.height < 0 {
        return false
    }

    return true
}
