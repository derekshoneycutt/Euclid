package ui

import "../../core"
import "../../julia"

import rl "vendor:raylib"

//   Render wrapped animation view text with scroll handling.
draw_view_text_panel :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {
    if state == nil || state.julia_interface == nil {
        return
    }

    ui_runtime := &state.ui_runtime
    panel_container := draw_container(panel, .Dark_Red)

    text_panel := rl.Rectangle{
        panel_container.inner_rect.x + 5,
        panel_container.inner_rect.y + 5,
        panel_container.inner_rect.width - 10,
        panel_container.inner_rect.height - 10,
    }
    text_panel = draw_container(text_panel, .Grey).drawn_rect

    if is_scratchpad_selected(state) {
        draw_scratchpad_output_and_prompt(state, text_panel, ui_runtime, state.font, mouse_input)
        return
    }

    dynview_reset_command_buffer(&ui_runtime^.dynview_runtime)
    view_text := julia.call_current_animation_get_view_text(state)
    _ = dynview_compiled_scratchpad_text_or_fallback(
        ui_runtime,
        text_panel,
        TREE_FONT_SIZE,
        TEXT_WRAP_ADVANCE,
        DYNVIEW_STYLE_REVISION_PLAIN_TEXT,
        view_text)

    content_h := dynview_scratchpad_content_height_or_fallback(
        ui_runtime,
        text_panel,
        TEXT_PADDING,
        TEXT_WRAP_ADVANCE,
        TEXT_ROW_HEIGHT,
        view_text)
    scroll_step := dynview_scratchpad_scroll_step_or_fallback(ui_runtime, TEXT_ROW_HEIGHT)
    text_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.text_scroll_dragging,
        drag_offset_y = ui_runtime.text_scroll_drag_off,
    }
    text_scroll_begin := scroll_container_begin(
        1001,
        text_panel,
        state^.ui_runtime.view_text_scroll_y,
        content_h,
        mouse_input,
        rl.Vector2{},
        text_panel,
        scroll_step * WHEEL_SCROLL_MULTIPLIER,
        &ui_runtime^.ui_press_owner,
        text_scroll_state)
    text_panel = text_scroll_begin.view_rect
    state^.ui_runtime.view_text_scroll_y = text_scroll_begin.scroll_y_out

    dynview_refresh_scratchpad_copy_targets(
        ui_runtime,
        text_panel,
        state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING,
        TEXT_ROW_HEIGHT,
        DYNVIEW_COPY_ICON_SIZE,
        DYNVIEW_COPY_ICON_X_PAD)

    dynview_draw_scratchpad_styled_or_fallback(
        state,
        ui_runtime,
        view_text,
        text_panel,
        state^.ui_runtime.view_text_scroll_y,
        state.font,
        TEXT_PADDING,
        TEXT_ROW_HEIGHT,
        TEXT_WRAP_ADVANCE,
        TREE_FONT_SIZE,
        UI_TEXT_COLOR)

    _ = draw_dynview_copy_icons(&ui_runtime^.dynview_runtime, text_panel, mouse_input)

    text_scroll_end := scroll_container_end(
        text_scroll_begin.scroll_ref,
        content_h,
        state^.ui_runtime.view_text_scroll_y,
        mouse_input,
        rl.Vector2{},
        text_panel,
        &ui_runtime^.ui_press_owner)
    state^.ui_runtime.view_text_scroll_y = text_scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = text_scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = text_scroll_end.state_out.drag_offset_y
}
