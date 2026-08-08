package ui

import "../../core"
import "../../dynview"
import julia "../../bridge"
import view_core "../core"
import ui_dynview "./dynview"

import rl "vendor:raylib"

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
        draw_scratchpad_output_and_prompt(state, text_panel, ui_runtime, state.font, mouse_input)
        return
    }

    view_text := julia.current_view_snapshot_text(state)
    content_h := dynview.scratchpad_content_height_or_fallback(&state.dynview, text_panel,
        TEXT_PADDING, TEXT_WRAP_ADVANCE, TEXT_ROW_HEIGHT, view_text)
    scroll_step := dynview.scratchpad_scroll_step_or_fallback(&state.dynview, TEXT_ROW_HEIGHT)
    text_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.text_scroll_dragging,
        drag_offset_y = ui_runtime.text_scroll_drag_off,
    }
    text_scroll_begin := scroll_container_begin(1001, text_panel,
        state^.ui_runtime.view_text_scroll_y, content_h, mouse_input,
        rl.Vector2{}, text_panel, scroll_step * WHEEL_SCROLL_MULTIPLIER,
        &ui_runtime^.ui_press_owner, text_scroll_state)
    text_panel = text_scroll_begin.view_rect
    state^.ui_runtime.view_text_scroll_y = text_scroll_begin.scroll_y_out

    dynview.refresh_scratchpad_copy_targets(&state.dynview, text_panel,
        state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING, TEXT_ROW_HEIGHT,
        DYNVIEW_COPY_ICON_SIZE, DYNVIEW_COPY_ICON_X_PAD)

    ui_dynview.draw_scratchpad_styled_or_fallback(state, ui_runtime, view_text, text_panel,
        state^.ui_runtime.view_text_scroll_y,
        state.font, TEXT_PADDING, TEXT_ROW_HEIGHT, TEXT_WRAP_ADVANCE,
        TREE_FONT_SIZE, UI_TEXT_COLOR)

    _ = view_core.draw_copy_icons(&state^.dynview, text_panel, mouse_input)

    text_scroll_end := scroll_container_end(text_scroll_begin.scroll_ref, content_h,
        state^.ui_runtime.view_text_scroll_y, mouse_input, rl.Vector2{},
        text_panel, &ui_runtime^.ui_press_owner)
    state^.ui_runtime.view_text_scroll_y = text_scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = text_scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = text_scroll_end.state_out.drag_offset_y
}
