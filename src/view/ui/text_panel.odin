package ui

import "../../core"
import "../../julia"

import rl "vendor:raylib"

//   Render wrapped animation view text with scroll handling.
draw_view_text_panel :: proc(state: ^core.Euclid_General_State, panel: rl.Rectangle) {
    if state == nil || state.julia_interface == nil {
        return
    }

    ui_runtime := &state.ui_runtime

    rl.DrawRectangleRec(panel, BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    text_panel := rl.Rectangle{
        panel.x + 6,
        panel.y + 6,
        panel.width - 12,
        panel.height - 12,
    }

    if text_panel.width < 0 {
        text_panel.width = 0
    }

    if text_panel.height < 0 {
        text_panel.height = 0
    }

    rl.DrawRectangleRec(text_panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(text_panel, 1, UI_BORDER_COLOR)

    handle_scratchpad_keyboard_input(state)

    if is_scratchpad_selected(state) {
        draw_scratchpad_output_and_prompt(state, text_panel, ui_runtime, state.font)
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

    total_rows := dynview_scratchpad_styled_rows_or_fallback(
        ui_runtime,
        text_panel,
        TEXT_PADDING,
        TEXT_WRAP_ADVANCE,
        view_text)
    content_h := TEXT_PADDING * 2 + f32(total_rows) * TEXT_ROW_HEIGHT
    max_scroll := max(0.0, content_h - text_panel.height)
    clamp_scroll_position(&state^.ui_runtime.view_text_scroll_y, max_scroll)

    mouse := rl.GetMousePosition()
    apply_wheel_scroll(mouse, text_panel, TEXT_ROW_HEIGHT,
        &state^.ui_runtime.view_text_scroll_y, max_scroll, WHEEL_SCROLL_MULTIPLIER)

    dynview_refresh_scratchpad_copy_targets(
        ui_runtime,
        text_panel,
        state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING,
        TEXT_ROW_HEIGHT,
        DYNVIEW_COPY_ICON_SIZE,
        DYNVIEW_COPY_ICON_X_PAD)

    rl.BeginScissorMode(i32(text_panel.x), i32(text_panel.y),
        i32(text_panel.width), i32(text_panel.height))
    {
        dynview_draw_scratchpad_styled_or_fallback(
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

            _ = draw_scratchpad_dynview_copy_icons(&ui_runtime^.dynview_runtime, text_panel, mouse)
    }
    rl.EndScissorMode()

    track, thumb, thumb_h, has_scrollbar := build_vertical_scrollbar(
        text_panel,
        content_h,
        state^.ui_runtime.view_text_scroll_y,
        max_scroll,
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)

    if has_scrollbar {
        handle_scrollbar_drag(mouse, thumb, text_panel.y, text_panel.height,
            thumb_h, max_scroll, &state^.ui_runtime.view_text_scroll_y,
            &ui_runtime.text_scroll_dragging, &ui_runtime.text_scroll_drag_off,
            SCROLLBAR_DRAG_EPSILON)

        rl.DrawRectangleRec(track, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb, UI_BORDER_COLOR)
    }
}
