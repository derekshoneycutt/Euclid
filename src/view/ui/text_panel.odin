package ui

import "../../core"
import "../../dynview"
import julia "../../bridge"
import view_core "../core"
import "../font"
import ui_dynview "./dynview"

import rl "vendor:raylib"

//   Grouped inputs for ending the view-text scroll container.
View_Text_Scroll_End :: struct {
    text_panel:  rl.Rectangle,
    content_h:   f32,
    mouse_input: Mouse_Input_State,
}

//   Compute the bordered text viewport used by normal and Scratchpad views.
view_text_content_panel :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    panel_geometry := container_geometry(panel, 1)
    text_panel := rl.Rectangle{
        panel_geometry.inner_rect.x + 5,
        panel_geometry.inner_rect.y + 5,
        panel_geometry.inner_rect.width - 10,
        panel_geometry.inner_rect.height - 10,
    }
    return container_geometry(text_panel, 1).drawn_rect
}

//   Begin the view-text scroll container and return it with the clamped panel.
view_text_scroll_begin :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    text_panel: rl.Rectangle,
    content_h: f32,
    mouse_input: Mouse_Input_State) -> Scroll_Container_Begin_Result {

    scroll_step := dynview.scratchpad_scroll_step_or_fallback(&state.dynview,
        TEXT_ROW_HEIGHT)
    scroll_begin := scroll_container_begin(Scroll_Container_Begin_Params{
        id = 1001,
        rect = text_panel,
        scroll_y_in = state^.ui_runtime.view_text_scroll_y,
        content_height_hint = content_h,
        mouse_input = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = text_panel,
        wheel_step = scroll_step * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &ui_runtime^.ui_press_owner,
        state_in = Scroll_Container_State{
            is_dragging_thumb = ui_runtime.text_scroll_dragging,
            drag_offset_y = ui_runtime.text_scroll_drag_off,
        },
    })
    state^.ui_runtime.view_text_scroll_y = scroll_begin.scroll_y_out
    return scroll_begin
}

//   Draw the view-text transcript content and copy affordances.
view_text_draw_content :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    text_panel: rl.Rectangle,
    view_text: string,
    mouse_input: Mouse_Input_State) {

    dynview.refresh_scratchpad_copy_targets(&state.dynview, {
        panel = text_panel,
        scroll_y = state^.ui_runtime.view_text_scroll_y,
        text_padding = TEXT_PADDING,
        icon_size = DYNVIEW_COPY_ICON_SIZE,
        icon_x_pad = DYNVIEW_COPY_ICON_X_PAD,
    })

    ui_dynview.draw_scratchpad_styled_or_fallback(state, ui_runtime,
        ui_dynview.Fallback_Text_Content{view_text, UI_TEXT_COLOR},
        ui_dynview.Scratchpad_Draw_Params{
            panel = text_panel,
            scroll_y = state^.ui_runtime.view_text_scroll_y,
            font = font.cache_borrow(&state.font_cache, .Regular),
            metrics = ui_dynview.Wrapped_Text_Metrics{
                padding = TEXT_PADDING,
                row_height = TEXT_ROW_HEIGHT,
                wrap_advance = TEXT_WRAP_ADVANCE,
                font_size = TREE_FONT_SIZE,
            },
        })

    _ = view_core.draw_copy_icons(&state^.dynview, text_panel, mouse_input)
}

//   End the view-text scroll container and commit drag state.
view_text_scroll_end :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    input: View_Text_Scroll_End,
    scroll_begin: Scroll_Container_Begin_Result) {

    scroll_end := scroll_container_end(Scroll_Container_End_Params{
        scroll_ref = scroll_begin.scroll_ref,
        content_height_final = input.content_h,
        scroll_y_in = state^.ui_runtime.view_text_scroll_y,
        mouse_input = input.mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = input.text_panel,
        press_owner = &ui_runtime^.ui_press_owner,
    })
    state^.ui_runtime.view_text_scroll_y = scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = scroll_end.state_out.drag_offset_y
}

//   Render wrapped animation view text with scroll handling.
draw_view_text_panel :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {
    if state == nil || state.julia_interface == nil {
        return
    }

    ui_runtime := &state.ui_runtime
    _ = draw_container(panel, .Dark_Red)
    text_panel := view_text_content_panel(panel)
    text_panel = draw_container(text_panel, .Grey).drawn_rect

    if is_scratchpad_selected(state) {
        draw_scratchpad_output_and_prompt(
            state, text_panel, ui_runtime,
            font.cache_borrow(&state.font_cache, .Regular), mouse_input)
        return
    }

    view_text := julia.current_view_snapshot_text(state)
    content_h := dynview.scratchpad_content_height_or_fallback(&state.dynview,
        text_panel, {
            text_padding = TEXT_PADDING,
            wrap_advance = TEXT_WRAP_ADVANCE,
            row_height = TEXT_ROW_HEIGHT,
            text = view_text,
        })

    scroll_begin := view_text_scroll_begin(state, ui_runtime, text_panel,
        content_h, mouse_input)
    text_panel = scroll_begin.view_rect

    view_text_draw_content(state, ui_runtime, text_panel, view_text, mouse_input)

    view_text_scroll_end(state, ui_runtime,
        View_Text_Scroll_End{text_panel, content_h, mouse_input},
        scroll_begin)
}
