package ui

import "../../core"
import "../../julia"

import "core:fmt"

import rl "vendor:raylib"

//   Return whether the currently selected tree item is the scratchpad node.
is_scratchpad_selected :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }

    selected := state^.julia_interface^.selected_animation_index
    if selected < 0 || selected >= state^.julia_interface^.next_animation_index {
        return false
    }

    return state^.julia_interface^.animations[selected].name == julia.SCRATCHPAD_ANIMATION_NAME
}

//   Read the current scratchpad input text from the fixed-size UI buffer.
scratchpad_input_text :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) -> string {
    if ui_runtime == nil || ui_runtime^.scratchpad_input_len <= 0 {
        return ""
    }
    return string(ui_runtime^.scratchpad_input[:ui_runtime^.scratchpad_input_len])
}

//   Clamp scratchpad cursor index so it always targets a valid byte boundary.
scratchpad_clamp_cursor :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if ui_runtime == nil {
        return
    }

    if ui_runtime^.scratchpad_input_cursor < 0 {
        ui_runtime^.scratchpad_input_cursor = 0
    }
    if ui_runtime^.scratchpad_input_cursor > ui_runtime^.scratchpad_input_len {
        ui_runtime^.scratchpad_input_cursor = ui_runtime^.scratchpad_input_len
    }
}

//   Insert one byte at the current scratchpad cursor when capacity allows.
scratchpad_insert_input_byte :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State, b: u8) {
    if ui_runtime == nil {
        return
    }

    scratchpad_clamp_cursor(ui_runtime)

    if ui_runtime^.scratchpad_input_len >= len(ui_runtime^.scratchpad_input) {
        return
    }

    for i := ui_runtime^.scratchpad_input_len; i > ui_runtime^.scratchpad_input_cursor; i -= 1 {
        ui_runtime^.scratchpad_input[i] = ui_runtime^.scratchpad_input[i - 1]
    }

    ui_runtime^.scratchpad_input[ui_runtime^.scratchpad_input_cursor] = b
    ui_runtime^.scratchpad_input_len += 1
    ui_runtime^.scratchpad_input_cursor += 1
}

//   Delete one byte to the left of cursor in scratchpad input.
scratchpad_backspace_input_byte :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if ui_runtime == nil {
        return
    }

    scratchpad_clamp_cursor(ui_runtime)
    if ui_runtime^.scratchpad_input_cursor <= 0 || ui_runtime^.scratchpad_input_len <= 0 {
        return
    }

    remove_at := ui_runtime^.scratchpad_input_cursor - 1
    for i := remove_at; i < ui_runtime^.scratchpad_input_len - 1; i += 1 {
        ui_runtime^.scratchpad_input[i] = ui_runtime^.scratchpad_input[i + 1]
    }

    ui_runtime^.scratchpad_input_len -= 1
    ui_runtime^.scratchpad_input_cursor -= 1
}

//   Delete one byte at cursor in scratchpad input.
scratchpad_delete_input_byte :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if ui_runtime == nil {
        return
    }

    scratchpad_clamp_cursor(ui_runtime)
    if ui_runtime^.scratchpad_input_cursor >= ui_runtime^.scratchpad_input_len {
        return
    }

    for i := ui_runtime^.scratchpad_input_cursor; i < ui_runtime^.scratchpad_input_len - 1; i += 1 {
        ui_runtime^.scratchpad_input[i] = ui_runtime^.scratchpad_input[i + 1]
    }

    ui_runtime^.scratchpad_input_len -= 1
}

//   Replace scratchpad input contents with provided text (clamped to buffer size).
scratchpad_replace_input_text :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State, text: string) {
    if ui_runtime == nil {
        return
    }

    ui_runtime^.scratchpad_input_len = 0
    if len(text) == 0 {
        return
    }

    cap_len := min(len(text), len(ui_runtime^.scratchpad_input))
    for i in 0..<cap_len {
        ui_runtime^.scratchpad_input[i] = text[i]
    }
    ui_runtime^.scratchpad_input_len = cap_len
    ui_runtime^.scratchpad_input_cursor = cap_len
}

//   Capture printable scratchpad input bytes and return whether input was edited.
consume_scratchpad_printable_input :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State) -> bool {
    did_edit_input := false
    for {
        codepoint := rl.GetCharPressed()
        if codepoint == 0 {
            break
        }

        // ASCII gate
        if codepoint >= 32 && codepoint < 127 {
            scratchpad_insert_input_byte(ui_runtime, u8(codepoint))
            did_edit_input = true
        }
    }

    if did_edit_input {
        _ = julia.scratchpad_history_reset_cursor(state)
    }

    return did_edit_input
}

//   Handle backspace in scratchpad input and reset history cursor when edited.
handle_scratchpad_backspace :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if !rl.IsKeyPressed(.BACKSPACE) {
        return
    }

    scratchpad_backspace_input_byte(ui_runtime)
    _ = julia.scratchpad_history_reset_cursor(state)
}

//   Handle forward delete in scratchpad input and reset history cursor when edited.
handle_scratchpad_delete :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if !rl.IsKeyPressed(.DELETE) {
        return
    }

    scratchpad_delete_input_byte(ui_runtime)
    _ = julia.scratchpad_history_reset_cursor(state)
}

//   Apply cursor movement key controls for scratchpad input.
handle_scratchpad_cursor_movement :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    scratchpad_clamp_cursor(ui_runtime)

    if rl.IsKeyPressed(.LEFT) && ui_runtime^.scratchpad_input_cursor > 0 {
        ui_runtime^.scratchpad_input_cursor -= 1
    }

    if rl.IsKeyPressed(.RIGHT) &&
        ui_runtime^.scratchpad_input_cursor < ui_runtime^.scratchpad_input_len {

        ui_runtime^.scratchpad_input_cursor += 1
    }

    if rl.IsKeyPressed(.HOME) {
        ui_runtime^.scratchpad_input_cursor = 0
    }

    if rl.IsKeyPressed(.END) {
        ui_runtime^.scratchpad_input_cursor = ui_runtime^.scratchpad_input_len
    }
}

//   Apply scratchpad history up/down navigation to the current input buffer.
apply_scratchpad_history_navigation :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State) {
    if rl.IsKeyPressed(.UP) {
        scratchpad_replace_input_text(ui_runtime, julia.scratchpad_history_previous(state))
    }

    if rl.IsKeyPressed(.DOWN) {
        scratchpad_replace_input_text(ui_runtime, julia.scratchpad_history_next(state))
    }
}

//   Submit current scratchpad input when parse state is complete.
submit_scratchpad_input_if_ready :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State) {

    submit_pressed := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)
    if !submit_pressed {
        return
    }

    input_text := scratchpad_input_text(ui_runtime)
    if len(input_text) == 0 {
        return
    }

    ui_runtime^.scratchpad_follow_output = true

    status := julia.scratchpad_classify_input(state, input_text)
    if status == julia.SCRATCHPAD_PARSE_INCOMPLETE {
        // Newline is intentionally injected to support multiline completion flow.
        scratchpad_insert_input_byte(ui_runtime, '\n')
        _ = julia.scratchpad_history_reset_cursor(state)
        return
    }

    if status != julia.SCRATCHPAD_PARSE_COMPLETE {
        return
    }

    if julia.scratchpad_queue_input(state, input_text) {
        ui_runtime^.scratchpad_input_len = 0
        ui_runtime^.scratchpad_input_cursor = 0
        _ = julia.scratchpad_history_reset_cursor(state)
    }
}


//   Draw scratchpad output in a scrollable region with a fixed prompt row.
draw_scratchpad_output_and_prompt :: proc(
    state: ^core.Euclid_General_State,
    text_panel: rl.Rectangle,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    prompt_band_h: f32 = TEXT_ROW_HEIGHT + TEXT_PADDING
    output_panel := text_panel
    output_panel.height = text_panel.height - prompt_band_h

    if output_panel.height < TEXT_ROW_HEIGHT {
        output_panel.height = TEXT_ROW_HEIGHT
    }

    output_text_legacy := julia.call_current_animation_get_view_text(state)
    output_text := dynview_compiled_scratchpad_text_or_fallback(
        ui_runtime,
        output_panel,
        TREE_FONT_SIZE,
        TEXT_WRAP_ADVANCE,
        DYNVIEW_STYLE_REVISION_PLAIN_TEXT,
        output_text_legacy)
    content_h := dynview_scratchpad_content_height_or_fallback(
        ui_runtime,
        output_panel,
        TEXT_PADDING,
        TEXT_WRAP_ADVANCE,
        TEXT_ROW_HEIGHT,
        output_text_legacy)
    max_scroll := max(0.0, content_h - output_panel.height)
    scroll_step := dynview_scratchpad_scroll_step_or_fallback(ui_runtime, TEXT_ROW_HEIGHT)

    output_len := len(output_text)
    if output_len != ui_runtime^.scratchpad_last_output_len {
        if ui_runtime^.scratchpad_follow_output {
            // Follow new command output by snapping to newest lines exactly once per update.
            state^.ui_runtime.view_text_scroll_y = max_scroll
        } else {
            state^.ui_runtime.view_text_scroll_y = 0
        }
        ui_runtime^.scratchpad_last_output_len = output_len
    }

    clamp_scroll_position(&state^.ui_runtime.view_text_scroll_y, max_scroll)

    mouse := rl.GetMousePosition()
    pre_wheel_scroll := state^.ui_runtime.view_text_scroll_y
    apply_wheel_scroll(mouse, output_panel, scroll_step,
        &state^.ui_runtime.view_text_scroll_y, max_scroll, WHEEL_SCROLL_MULTIPLIER)

    if state^.ui_runtime.view_text_scroll_y != pre_wheel_scroll {
        ui_runtime^.scratchpad_follow_output = true
    }

    dynview_refresh_scratchpad_copy_targets(
        ui_runtime,
        output_panel,
        state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING,
        TEXT_ROW_HEIGHT,
        DYNVIEW_COPY_ICON_SIZE,
        DYNVIEW_COPY_ICON_X_PAD)

    rl.BeginScissorMode(i32(output_panel.x), i32(output_panel.y), i32(output_panel.width), i32(output_panel.height))
    {
        draw_dynview_copy_hover_backgrounds(&ui_runtime^.dynview_runtime, mouse)

        dynview_draw_scratchpad_styled_or_fallback(
            ui_runtime,
            output_text_legacy,
            output_panel,
            state^.ui_runtime.view_text_scroll_y,
            font,
            TEXT_PADDING,
            TEXT_ROW_HEIGHT,
            TEXT_WRAP_ADVANCE,
            TREE_FONT_SIZE,
            UI_TEXT_COLOR)

        _ = draw_dynview_copy_icons(&ui_runtime^.dynview_runtime, output_panel, mouse)
    }
    rl.EndScissorMode()

    track, thumb, thumb_h, has_scrollbar := build_vertical_scrollbar(
        output_panel,
        content_h,
        state^.ui_runtime.view_text_scroll_y,
        max_scroll,
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)

    if has_scrollbar {
        pre_drag_scroll := state^.ui_runtime.view_text_scroll_y
        handle_scrollbar_drag(mouse, thumb, output_panel.y, output_panel.height,
            thumb_h, max_scroll, &state^.ui_runtime.view_text_scroll_y,
            &ui_runtime.text_scroll_dragging, &ui_runtime.text_scroll_drag_off,
            SCROLLBAR_DRAG_EPSILON)

        if state^.ui_runtime.view_text_scroll_y != pre_drag_scroll {
            ui_runtime^.scratchpad_follow_output = true
        }

        rl.DrawRectangleRec(track, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb, UI_BORDER_COLOR)
    }

    prompt_y := int(text_panel.y + text_panel.height - TEXT_ROW_HEIGHT - 2)
    rl.DrawLineEx(
        rl.Vector2{text_panel.x + 1, f32(prompt_y - 2)},
        rl.Vector2{text_panel.x + text_panel.width - 1, f32(prompt_y - 2)},
        1, UI_BORDER_COLOR)

    scratchpad_clamp_cursor(ui_runtime)
    cursor := ui_runtime^.scratchpad_input_cursor
    input_text := scratchpad_input_text(ui_runtime)

    blink_phase := int(rl.GetTime() / SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS)
    cursor_glyph := " "

    if blink_phase % 2 == 0 {
        cursor_glyph = "|"
    }

    prompt_text := fmt.tprintf("> %s%s%s", input_text[:cursor], cursor_glyph, input_text[cursor:])
    ui_text(prompt_text, int(text_panel.x + TEXT_PADDING), prompt_y, UI_TEXT_COLOR, font)
}

//   Route keyboard input to scratchpad and queue complete submissions.
handle_scratchpad_keyboard_input :: proc(state: ^core.Euclid_General_State) {
    if !is_scratchpad_selected(state) {
        return
    }

    ui_runtime := &state^.ui_runtime
    _ = consume_scratchpad_printable_input(state, ui_runtime)
    handle_scratchpad_cursor_movement(ui_runtime)
    handle_scratchpad_backspace(state, ui_runtime)
    handle_scratchpad_delete(state, ui_runtime)
    apply_scratchpad_history_navigation(state, ui_runtime)
    submit_scratchpad_input_if_ready(state, ui_runtime)
}
