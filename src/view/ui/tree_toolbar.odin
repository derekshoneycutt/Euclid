package ui

import "../../core"

import rl "vendor:raylib"

Tree_Toolbar_Hit :: struct {
    refresh_requested: bool,
    toggle_pause_requested: bool,
    toggle_tree_requested: bool,
    toggle_gif_requested: bool,
    toggle_settings_requested: bool,
}

//   Shared context for one toolbar frame's buttons.
Tree_Toolbar_Context :: struct {
    panel:            rl.Rectangle,
    mouse_input:      Mouse_Input_State,
    press_owner:      ^core.Ui_Press_Owner_State,
    show_tree:        bool,
    show_gif:         bool,
    show_settings:    bool,
    simulation_paused: bool,
}

//   Placed button rects for one toolbar frame.
Tree_Toolbar_Slots :: struct {
    refresh:  rl.Rectangle,
    pause:    rl.Rectangle,
    settings: rl.Rectangle,
    gif:      rl.Rectangle,
    books:    rl.Rectangle,
}

//   Place one toolbar slot in the lane and advance the cursor.
tree_toolbar_place_slot :: #force_inline proc(
    lane: rl.Rectangle, size: f32, origin_x: f32, direction: int,
    cursor: Stack_Panel_Cursor) -> Stack_Panel_Result {

    return stack_panel_place_segment(Stack_Panel_Params{
        origin_x = origin_x,
        origin_y = lane.y,
        axis = .X,
        direction_sign = direction,
        rect = lane,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = size,
        cursor_in = cursor,
    })
}

//   Lay out the toolbar button slots for one frame.
tree_toolbar_layout_slots :: proc(
    ctx: Tree_Toolbar_Context) -> Tree_Toolbar_Slots {

    panel := ctx.panel
    lane_y := panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5
    lane := rl.Rectangle{panel.x, lane_y, panel.width, TREE_TOOLBAR_BUTTON_SIZE}

    left_x := panel.x + TREE_TOOLBAR_EDGE_PAD
    left_cursor := stack_panel_cursor_zero()
    refresh_slot := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_SIZE,
        left_x, 1, left_cursor)
    left_gap := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_GAP,
        left_x, 1, refresh_slot.cursor_out)
    pause_slot := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_SIZE,
        left_x, 1, left_gap.cursor_out)

    right_x := panel.x + panel.width - TREE_TOOLBAR_EDGE_PAD
    right_cursor := stack_panel_cursor_zero()
    settings_slot := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_SIZE,
        right_x, -1, right_cursor)
    right_gap := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_GAP,
        right_x, -1, settings_slot.cursor_out)
    gif_slot := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_SIZE,
        right_x, -1, right_gap.cursor_out)
    books_slot := tree_toolbar_place_slot(lane, TREE_TOOLBAR_BUTTON_SIZE,
        right_x, -1, gif_slot.cursor_out)

    return Tree_Toolbar_Slots{
        refresh = refresh_slot.segment_rect,
        pause = pause_slot.segment_rect,
        settings = settings_slot.segment_rect,
        gif = gif_slot.segment_rect,
        books = books_slot.segment_rect,
    }
}

//   Draw one toolbar icon button and report whether it was clicked.
tree_toolbar_button :: #force_inline proc(
    ctx: Tree_Toolbar_Context,
    id: int,
    rect: rl.Rectangle,
    icon_id: Icon_Button_Id,
    toggle: bool) -> bool {

    button := draw_icon_button(Icon_Button_Params{
        id = id,
        rect = rect,
        icon_id = icon_id,
        toggle = toggle,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }, ctx.press_owner)
    return button.clicked
}

//   Render toolbar row and report refresh/tree/gif/settings toggle hits.
draw_tree_toolbar :: proc(
    ctx: Tree_Toolbar_Context) -> Tree_Toolbar_Hit {

    hit := Tree_Toolbar_Hit{}

    _ = draw_container(ctx.panel, .Grey)

    slots := tree_toolbar_layout_slots(ctx)

    hit.refresh_requested = tree_toolbar_button(ctx, 2001, slots.refresh,
        .Refresh, false)

    pause_icon_id := Icon_Button_Id.Pause
    if ctx.simulation_paused {
        pause_icon_id = .Play
    }
    hit.toggle_pause_requested = tree_toolbar_button(ctx, 2002, slots.pause,
        pause_icon_id, ctx.simulation_paused)

    hit.toggle_gif_requested = tree_toolbar_button(ctx, 2003, slots.gif,
        .Gif, ctx.show_gif)

    hit.toggle_tree_requested = tree_toolbar_button(ctx, 2005, slots.books,
        .Books, ctx.show_tree)

    hit.toggle_settings_requested = tree_toolbar_button(ctx, 2004, slots.settings,
        .Gear, ctx.show_settings)
    return hit
}