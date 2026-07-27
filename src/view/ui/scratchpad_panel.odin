package ui

import "../../core"
import "../../julia"

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

//   Return whether a byte belongs to an ASCII letter accepted in phase-1 backslash tokens.
scratchpad_backslash_token_letter :: #force_inline proc(b: u8) -> bool {
    return (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z')
}

//   Locate the current backslash token ending at the scratchpad caret.
scratchpad_backslash_token_bounds :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) -> (int, int, bool) {
    if ui_runtime == nil || ui_runtime^.scratchpad_input_len <= 0 || ui_runtime^.scratchpad_input_cursor <= 0 {
        return 0, 0, false
    }

    token_end := clamp(ui_runtime^.scratchpad_input_cursor, 0, ui_runtime^.scratchpad_input_len)
    token_start := token_end
    for token_start > 0 {
        b := ui_runtime^.scratchpad_input[token_start - 1]
        if b == '\\' || scratchpad_backslash_token_letter(b) {
            token_start -= 1
            continue
        }
        break
    }

    if token_start >= token_end || ui_runtime^.scratchpad_input[token_start] != '\\' {
        return 0, 0, false
    }

    return token_start, token_end, true
}

//   Apply one phase-1 backslash completion request to the scratchpad input buffer.
apply_scratchpad_backslash_completion :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    tab_pressed: bool) -> bool {

    if !tab_pressed || state == nil || ui_runtime == nil {
        return false
    }

    token_start, token_end, ok := scratchpad_backslash_token_bounds(ui_runtime)
    if !ok {
        return false
    }

    token := string(ui_runtime^.scratchpad_input[token_start:token_end])
    replacement := julia.scratchpad_complete_backslash(state, token)
    if len(replacement) == 0 {
        return false
    }

    return input_box_replace_byte_range(
        ui_runtime^.scratchpad_input[:],
        &ui_runtime^.scratchpad_input_len,
        &ui_runtime^.scratchpad_input_cursor,
        token_start,
        token_end,
        replacement)
}

//   Apply scratchpad history up/down navigation to the current input buffer.
//   This should only run when input-box vertical caret movement was not handled.
apply_scratchpad_history_navigation :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    history_previous: bool,
    history_next: bool) {

    if history_previous {
        input_box_replace_text(
            ui_runtime^.scratchpad_input[:],
            &ui_runtime^.scratchpad_input_len,
            &ui_runtime^.scratchpad_input_cursor,
            julia.scratchpad_history_previous(state))
        ui_runtime^.scratchpad_input_viewport_col_start = 0
    }

    if history_next {
        input_box_replace_text(
            ui_runtime^.scratchpad_input[:],
            &ui_runtime^.scratchpad_input_len,
            &ui_runtime^.scratchpad_input_cursor,
            julia.scratchpad_history_next(state))
        ui_runtime^.scratchpad_input_viewport_col_start = 0
    }
}

//   Submit current scratchpad input when parse state is complete.
submit_scratchpad_input_if_ready :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    submit_pressed: bool) {

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
        input_box_insert_at_caret(
            ui_runtime^.scratchpad_input[:],
            &ui_runtime^.scratchpad_input_len,
            &ui_runtime^.scratchpad_input_cursor,
            '\n')
        _ = julia.scratchpad_history_reset_cursor(state)
        return
    }

    if status != julia.SCRATCHPAD_PARSE_COMPLETE {
        return
    }

    if julia.scratchpad_queue_input(state, input_text) {
        ui_runtime^.scratchpad_input_len = 0
        ui_runtime^.scratchpad_input_cursor = 0
        ui_runtime^.scratchpad_input_viewport_col_start = 0
        _ = julia.scratchpad_history_reset_cursor(state)
    }
}


//   Draw scratchpad output in a scrollable region with a fixed prompt row.
draw_scratchpad_output_and_prompt :: proc(
    state: ^core.Euclid_General_State,
    text_panel: rl.Rectangle,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font,
    mouse_input: Mouse_Input_State) {

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

    mouse := mouse_input.position
    scratch_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.text_scroll_dragging,
        drag_offset_y = ui_runtime.text_scroll_drag_off,
    }
    pre_wheel_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_begin := scroll_container_begin(
        1002,
        output_panel,
        state^.ui_runtime.view_text_scroll_y,
        content_h,
        mouse_input,
        rl.Vector2{},
        output_panel,
        scroll_step * WHEEL_SCROLL_MULTIPLIER,
        &ui_runtime^.ui_press_owner,
        scratch_scroll_state)
    output_panel = scratch_scroll_begin.view_rect
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_begin.scroll_y_out

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

    _ = draw_dynview_copy_icons(&ui_runtime^.dynview_runtime, output_panel, mouse_input)

    pre_drag_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_end := scroll_container_end(
        scratch_scroll_begin.scroll_ref,
        content_h,
        state^.ui_runtime.view_text_scroll_y,
        mouse_input,
        rl.Vector2{},
        output_panel,
        &ui_runtime^.ui_press_owner)
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = scratch_scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = scratch_scroll_end.state_out.drag_offset_y

    if scratch_scroll_end.has_scrollbar {
        if state^.ui_runtime.view_text_scroll_y != pre_drag_scroll {
            ui_runtime^.scratchpad_follow_output = true
        }
    }

    prompt_y := int(text_panel.y + text_panel.height - TEXT_ROW_HEIGHT - 2)
    rl.DrawLineEx(
        rl.Vector2{text_panel.x + 1, f32(prompt_y - 2)},
        rl.Vector2{text_panel.x + text_panel.width - 1, f32(prompt_y - 2)},
        1, UI_BORDER_COLOR)

    input_x := text_panel.x + TEXT_PADDING
    input_w := max(0.0, text_panel.width - TEXT_PADDING * 2)
    input_rect := rl.Rectangle{input_x, f32(prompt_y), input_w, TREE_FONT_SIZE + 2}

    input_result := handle_input_box(Input_Box_Params{
        id = 5001,
        rect = input_rect,
        text_buffer = ui_runtime^.scratchpad_input[:],
        text_len_in = ui_runtime^.scratchpad_input_len,
        caret_col_in = ui_runtime^.scratchpad_input_cursor,
        viewport_col_start_in = ui_runtime^.scratchpad_input_viewport_col_start,
        enabled = true,
        has_focus = true,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = text_panel,
        interaction_enabled = true,
        font = font,
        font_color = UI_TEXT_COLOR,
        font_size = TREE_FONT_SIZE,
        char_advance = TEXT_WRAP_ADVANCE,
        prompt_prefix = "> ",
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
    }, &ui_runtime^.ui_press_owner)

    ui_runtime^.scratchpad_input_len = input_result.text_len_out
    ui_runtime^.scratchpad_input_cursor = input_result.caret_col_out
    ui_runtime^.scratchpad_input_viewport_col_start = input_result.viewport_col_start_out

    apply_scratchpad_history_navigation(
        state,
        ui_runtime,
        input_result.history_previous && !input_result.moved_up,
        input_result.history_next && !input_result.moved_down)

    completion_applied := apply_scratchpad_backslash_completion(
        state,
        ui_runtime,
        input_result.tab_pressed)

    if input_result.changed || completion_applied {
        _ = julia.scratchpad_history_reset_cursor(state)
    }

    submit_scratchpad_input_if_ready(state, ui_runtime, input_result.submit_pressed)

    draw_input_box(Input_Box_Draw_Params{
        rect = input_rect,
        text_buffer = ui_runtime^.scratchpad_input[:],
        text_len = ui_runtime^.scratchpad_input_len,
        caret_col = ui_runtime^.scratchpad_input_cursor,
        viewport_col_start = ui_runtime^.scratchpad_input_viewport_col_start,
        enabled = true,
        has_focus = true,
        mouse = mouse_input,
        font = font,
        font_color = UI_TEXT_COLOR,
        font_size = TREE_FONT_SIZE,
        char_advance = TEXT_WRAP_ADVANCE,
        prompt_prefix = "> ",
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
    })
}
