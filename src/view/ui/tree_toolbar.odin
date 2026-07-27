package ui

import "../../core"

import rl "vendor:raylib"

Tree_Toolbar_Hit :: struct {
    RefreshRequested: bool,
    TogglePauseRequested: bool,
    ToggleTreeRequested: bool,
    ToggleGifRequested: bool,
    ToggleSettingsRequested: bool,
}

//   Render toolbar row and report refresh/tree/gif/settings toggle hits.
draw_tree_toolbar :: proc(
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    press_owner: ^core.Ui_Press_Owner_State,
    show_tree: bool,
    show_gif: bool,
    show_settings: bool,
    simulation_paused: bool) -> Tree_Toolbar_Hit {

    hit := Tree_Toolbar_Hit{}

    _ = draw_container(panel, .Grey)

    lane_y := panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5
    lane_rect := rl.Rectangle{panel.x, lane_y, panel.width, TREE_TOOLBAR_BUTTON_SIZE}

    left_cursor := stack_panel_cursor_zero()
    refresh_slot := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = 1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_SIZE,
        cursor_in = left_cursor,
    })
    left_cursor = refresh_slot.cursor_out

    left_gap := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = 1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_GAP,
        cursor_in = left_cursor,
    })
    left_cursor = left_gap.cursor_out

    pause_slot := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = 1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_SIZE,
        cursor_in = left_cursor,
    })

    right_cursor := stack_panel_cursor_zero()
    settings_slot := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + panel.width - TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = -1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_SIZE,
        cursor_in = right_cursor,
    })
    right_cursor = settings_slot.cursor_out

    right_gap := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + panel.width - TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = -1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_GAP,
        cursor_in = right_cursor,
    })
    right_cursor = right_gap.cursor_out

    gif_slot := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + panel.width - TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = -1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_SIZE,
        cursor_in = right_cursor,
    })
    right_cursor = gif_slot.cursor_out

    books_slot := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = panel.x + panel.width - TREE_TOOLBAR_EDGE_PAD,
        origin_y = lane_rect.y,
        axis = .X,
        direction_sign = -1,
        rect = lane_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = TREE_TOOLBAR_BUTTON_SIZE,
        cursor_in = right_cursor,
    })

    refresh_rect := refresh_slot.segment_rect
    pause_rect := pause_slot.segment_rect
    settings_rect := settings_slot.segment_rect
    gif_rect := gif_slot.segment_rect
    books_rect := books_slot.segment_rect

    refresh_button := draw_icon_button(Icon_Button_Params{
        id = 2001,
        rect = refresh_rect,
        icon_id = .Refresh,
        toggle = false,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, press_owner)
    hit.RefreshRequested = refresh_button.clicked

    pause_icon_id := Icon_Button_Id.Pause
    if simulation_paused {
        pause_icon_id = .Play
    }
    pause_button := draw_icon_button(Icon_Button_Params{
        id = 2002,
        rect = pause_rect,
        icon_id = pause_icon_id,
        toggle = simulation_paused,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, press_owner)
    hit.TogglePauseRequested = pause_button.clicked

    gif_button := draw_icon_button(Icon_Button_Params{
        id = 2003,
        rect = gif_rect,
        icon_id = .Gif,
        toggle = show_gif,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, press_owner)
    hit.ToggleGifRequested = gif_button.clicked

    tree_button := draw_icon_button(Icon_Button_Params{
        id = 2005,
        rect = books_rect,
        icon_id = .Books,
        toggle = show_tree,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, press_owner)
    hit.ToggleTreeRequested = tree_button.clicked

    settings_button := draw_icon_button(Icon_Button_Params{
        id = 2004,
        rect = settings_rect,
        icon_id = .Gear,
        toggle = show_settings,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, press_owner)
    hit.ToggleSettingsRequested = settings_button.clicked
    return hit
}