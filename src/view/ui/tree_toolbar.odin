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
    mouse_input:      Input_Frame,
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

//   Fixed prepared interaction results for all tree toolbar buttons.
Tree_Toolbar_Preparation :: struct {
    slots: Tree_Toolbar_Slots,
    refresh: Icon_Button_Result,
    pause: Icon_Button_Result,
    settings: Icon_Button_Result,
    gif: Icon_Button_Result,
    books: Icon_Button_Result,
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

//   Build one toolbar icon-button parameter record.
tree_toolbar_button_params :: #force_inline proc(
    ctx: Tree_Toolbar_Context,
    id: int,
    rect: rl.Rectangle,
    icon_id: Icon_Button_Id,
    toggle: bool) -> Icon_Button_Params {

    return Icon_Button_Params{
        id = id,
        rect = rect,
        icon_id = icon_id,
        toggle = toggle,
        mouse = ctx.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        inset_scale = 1.0,
    }
}

//   Resolve toolbar interaction and return fixed visual preparation plus action hits.
update_tree_toolbar :: proc(
    ctx: Tree_Toolbar_Context) -> (Tree_Toolbar_Preparation, Tree_Toolbar_Hit) {
    slots := tree_toolbar_layout_slots(ctx)
    pause_icon_id := Icon_Button_Id.Pause
    if ctx.simulation_paused {
        pause_icon_id = .Play
    }
    prepared := Tree_Toolbar_Preparation{slots = slots}
    prepared.refresh = update_icon_button(tree_toolbar_button_params(
        ctx, 2001, slots.refresh, .Refresh, false), ctx.press_owner)
    prepared.pause = update_icon_button(tree_toolbar_button_params(
        ctx, 2002, slots.pause, pause_icon_id, ctx.simulation_paused), ctx.press_owner)
    prepared.gif = update_icon_button(tree_toolbar_button_params(
        ctx, 2003, slots.gif, .Gif, ctx.show_gif), ctx.press_owner)
    prepared.books = update_icon_button(tree_toolbar_button_params(
        ctx, 2005, slots.books, .Books, ctx.show_tree), ctx.press_owner)
    prepared.settings = update_icon_button(tree_toolbar_button_params(
        ctx, 2004, slots.settings, .Gear, ctx.show_settings), ctx.press_owner)
    return prepared, {
        refresh_requested = prepared.refresh.clicked,
        toggle_pause_requested = prepared.pause.clicked,
        toggle_tree_requested = prepared.books.clicked,
        toggle_gif_requested = prepared.gif.clicked,
        toggle_settings_requested = prepared.settings.clicked,
    }
}

//   Render the toolbar from prepared interaction results without mutation.
draw_tree_toolbar :: proc(
    ctx: Tree_Toolbar_Context,
    prepared: Tree_Toolbar_Preparation) {

    _ = draw_container(ctx.panel, .Grey)
    pause_icon_id := Icon_Button_Id.Pause
    if ctx.simulation_paused { pause_icon_id = .Play }
    draw_icon_button_prepared(tree_toolbar_button_params(
        ctx, 2001, prepared.slots.refresh, .Refresh, false), prepared.refresh)
    draw_icon_button_prepared(tree_toolbar_button_params(
        ctx, 2002, prepared.slots.pause, pause_icon_id,
        ctx.simulation_paused), prepared.pause)
    draw_icon_button_prepared(tree_toolbar_button_params(
        ctx, 2003, prepared.slots.gif, .Gif, ctx.show_gif), prepared.gif)
    draw_icon_button_prepared(tree_toolbar_button_params(
        ctx, 2005, prepared.slots.books, .Books, ctx.show_tree), prepared.books)
    draw_icon_button_prepared(tree_toolbar_button_params(
        ctx, 2004, prepared.slots.settings, .Gear,
        ctx.show_settings), prepared.settings)
}