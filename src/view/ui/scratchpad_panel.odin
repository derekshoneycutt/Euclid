package ui

import "../../core"
import "../../dynview"
import julia "../../bridge"
import view_core "../core"
import ui_dynview "./dynview"

import "core:strings"
import rl "vendor:raylib"

SCRATCHPAD_JULIA_PROMPT :: "julia> "
SCRATCHPAD_HELP_PROMPT :: "help?> "
SCRATCHPAD_SCROLL_BOTTOM_EPSILON :: 0.5

//   Return the live terminal prompt for the active Scratchpad editor mode.
scratchpad_prompt :: #force_inline proc(mode: core.Scratchpad_Input_Mode) -> string {
    return mode == .Help ? SCRATCHPAD_HELP_PROMPT : SCRATCHPAD_JULIA_PROMPT
}

Scratchpad_Terminal_Layout :: struct {
    transcript_height: f32,
    input_rows: int,
    content_height: f32,
    max_scroll: f32,
    input_rect: rl.Rectangle,
}

//   Return whether the currently selected tree item is the scratchpad node.
is_scratchpad_selected :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }

    selected := state^.julia_interface^.selected_animation
    if selected == nil {
        return false
    }

    return selected^.name == julia.SCRATCHPAD_ANIMATION_NAME
}

//   Read the current scratchpad input text from the fixed-size UI buffer.
scratchpad_input_text :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) -> string {
    if ui_runtime == nil || ui_runtime^.scratchpad_input_len <= 0 {
        return ""
    }
    return string(ui_runtime^.scratchpad_input[:ui_runtime^.scratchpad_input_len])
}

//   Parse a non-negative integer from ASCII digits.
scratchpad_parse_non_negative_int :: proc(text: string) -> (int, bool) {
    if len(text) <= 0 {
        return 0, false
    }

    value := 0
    for i in 0..<len(text) {
        b := text[i]
        if b < '0' || b > '9' {
            return 0, false
        }
        value = value * 10 + int(b - '0')
    }
    return value, true
}

//   Decode a generic completion payload encoded as `start\nend\nreplacement`.
scratchpad_parse_completion_payload :: proc(payload: string) -> (int, int, string, bool) {
    if len(payload) <= 0 {
        return 0, 0, "", false
    }

    first_newline := -1
    second_newline := -1
    for i in 0..<len(payload) {
        if payload[i] != '\n' {
            continue
        }
        if first_newline < 0 {
            first_newline = i
        } else {
            second_newline = i
            break
        }
    }

    if first_newline < 0 || second_newline < 0 || second_newline <= first_newline + 1 {
        return 0, 0, "", false
    }

    start_text := payload[:first_newline]
    end_text := payload[first_newline + 1:second_newline]
    replace_start, ok := scratchpad_parse_non_negative_int(start_text)
    if !ok {
        return 0, 0, "", false
    }

    replace_end := 0
    replace_end, ok = scratchpad_parse_non_negative_int(end_text)
    if !ok {
        return 0, 0, "", false
    }

    replacement := payload[second_newline + 1:]
    return replace_start, replace_end, replacement, true
}

//   Decode a mode-tagged history payload encoded as `mode\ntext`.
scratchpad_parse_history_payload :: proc(
    payload: string) -> (core.Scratchpad_Input_Mode, string, bool) {

    newline := strings.index_byte(payload, '\n')
    if newline < 0 {
        return .Julia, "", false
    }
    mode_value, ok := scratchpad_parse_non_negative_int(payload[:newline])
    if !ok || mode_value > int(core.Scratchpad_Input_Mode.Help) {
        return .Julia, "", false
    }
    return core.Scratchpad_Input_Mode(mode_value), payload[newline + 1:], true
}

//   Submit one generic completion request without blocking the display thread.
request_scratchpad_completion :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    tab_pressed: bool) {

    if !tab_pressed || state == nil || ui_runtime == nil {
        return
    }

    input_text := scratchpad_input_text(ui_runtime)
    if len(input_text) <= 0 {
        return
    }

    request_id, sent := julia.try_submit_scratchpad_async(
        state, .Complete, input_text, ui_runtime^.scratchpad_input_cursor,
        ui_runtime^.scratchpad_input_mode,
        ui_runtime^.scratchpad_input_generation)
    if sent {
        ui_runtime^.scratchpad_latest_completion_request_id = request_id
    }
}

//   Return whether a scroll position is at the newest terminal content.
scratchpad_scroll_is_at_bottom :: #force_inline proc(scroll_y, max_scroll: f32) -> bool {
    return max_scroll - scroll_y <= SCRATCHPAD_SCROLL_BOTTOM_EPSILON
}

//   Measure prompt-aligned columns available to terminal input text.
scratchpad_input_columns :: proc(
    panel: rl.Rectangle,
    font: rl.Font,
    mode: core.Scratchpad_Input_Mode) -> int {

    prompt := scratchpad_prompt(mode)
    prompt_cstr := strings.clone_to_cstring(prompt, context.temp_allocator)
    prompt_width := rl.MeasureTextEx(font, prompt_cstr, TREE_FONT_SIZE, 0).x
    input_width := max(0.0, panel.width - TEXT_PADDING * 2 - prompt_width)
    return input_box_visible_cols(input_width, TEXT_WRAP_ADVANCE)
}

//   Build unified transcript and live-input geometry for one terminal frame.
scratchpad_terminal_layout :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font,
    fallback_text: string,
    scroll_y: f32) -> Scratchpad_Terminal_Layout {

    transcript_height: f32 = TEXT_PADDING
    if len(fallback_text) > 0 {
        transcript_height = dynview.scratchpad_content_height_or_fallback(
            &state^.dynview, panel, TEXT_PADDING, TEXT_WRAP_ADVANCE,
            TEXT_ROW_HEIGHT, fallback_text)
    }
    columns := scratchpad_input_columns(panel, font, ui_runtime^.scratchpad_input_mode)
    input_rows := terminal_input_row_count(
        ui_runtime^.scratchpad_input[:], ui_runtime^.scratchpad_input_len,
        ui_runtime^.scratchpad_input_cursor, columns)
    content_height := transcript_height + f32(input_rows) * TEXT_ROW_HEIGHT + TEXT_PADDING
    input_rect := rl.Rectangle{
        panel.x + TEXT_PADDING,
        panel.y + transcript_height - scroll_y,
        max(0.0, panel.width - TEXT_PADDING * 2),
        f32(input_rows) * TEXT_ROW_HEIGHT,
    }
    return Scratchpad_Terminal_Layout{
        transcript_height = transcript_height,
        input_rows = input_rows,
        content_height = content_height,
        max_scroll = max(0.0, content_height - panel.height),
        input_rect = input_rect,
    }
}

//   Apply scratchpad history up/down navigation to the current input buffer.
//   This should only run when input-box vertical caret movement was not handled.
apply_scratchpad_history_navigation :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    history_previous: bool,
    history_next: bool) {

    if history_previous {
        _, _ = julia.try_submit_scratchpad_async(
            state, .History_Previous,
            input_mode = ui_runtime^.scratchpad_input_mode,
            input_generation = ui_runtime^.scratchpad_input_generation)
    }

    if history_next {
        _, _ = julia.try_submit_scratchpad_async(
            state, .History_Next,
            input_mode = ui_runtime^.scratchpad_input_mode,
            input_generation = ui_runtime^.scratchpad_input_generation)
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
    if ui_runtime^.scratchpad_pending_submit_request_id != 0 {
        return
    }

    ui_runtime^.scratchpad_bottom_pinned = true
    request_id, sent := julia.try_submit_scratchpad_async(
        state, .Submit, input_text,
        input_mode = ui_runtime^.scratchpad_input_mode,
        input_generation = ui_runtime^.scratchpad_input_generation)
    if sent {
        ui_runtime^.scratchpad_pending_submit_request_id = request_id
    }
}

//   Apply all completed Scratchpad replies at a display-frame boundary.
apply_scratchpad_async_results :: proc(
    state: ^core.Euclid_General_State, ui_runtime: ^core.Euclid_UI_Runtime_State) {

    for {
        slot, ok := julia.poll_scratchpad_async_result(state)
        if !ok {
            flush_scratchpad_history_reset(state, ui_runtime)
            return
        }
        apply_scratchpad_async_result(ui_runtime, slot)
        julia.release_scratchpad_async_result(slot)
    }
}

//   Retry a required history reset until bounded worker storage accepts it.
flush_scratchpad_history_reset :: proc(
    state: ^core.Euclid_General_State, ui_runtime: ^core.Euclid_UI_Runtime_State) {

    if !ui_runtime^.scratchpad_history_reset_pending {
        return
    }
    _, sent := julia.try_submit_scratchpad_async(
        state, .History_Reset,
        input_generation = ui_runtime^.scratchpad_input_generation)
    if sent {
        ui_runtime^.scratchpad_history_reset_pending = false
    }
}

//   Apply one current-generation reply and ignore stale UI mutations.
apply_scratchpad_async_result :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    slot: ^julia.Scratchpad_Async_Slot) {

    if slot^.kind == .Submit &&
        slot^.request_id == ui_runtime^.scratchpad_pending_submit_request_id {
        ui_runtime^.scratchpad_pending_submit_request_id = 0
    }
    if slot^.input_generation != ui_runtime^.scratchpad_input_generation {
        return
    }

    switch slot^.kind {
    case .Submit:
        apply_scratchpad_submit_result(ui_runtime, slot)
    case .Complete:
        apply_scratchpad_completion_result(ui_runtime, slot)
    case .History_Previous, .History_Next:
        mode, text, ok := scratchpad_parse_history_payload(
            julia.scratchpad_async_result_text(slot))
        if ok {
            input_box_replace_text(
                ui_runtime^.scratchpad_input[:],
                &ui_runtime^.scratchpad_input_len,
                &ui_runtime^.scratchpad_input_cursor,
                text)
            ui_runtime^.scratchpad_input_mode = mode
            ui_runtime^.scratchpad_input_viewport_col_start = 0
        }
    case .History_Reset, .Save_History:
    }
}

//   Preserve incomplete/error input and clear only an accepted complete submit.
apply_scratchpad_submit_result :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    slot: ^julia.Scratchpad_Async_Slot) {

    if slot^.parse_result == julia.SCRATCHPAD_PARSE_INCOMPLETE {
        previous_len := ui_runtime^.scratchpad_input_len
        input_box_insert_at_caret(
            ui_runtime^.scratchpad_input[:], &ui_runtime^.scratchpad_input_len,
            &ui_runtime^.scratchpad_input_cursor, '\n')
        if ui_runtime^.scratchpad_input_len != previous_len {
            ui_runtime^.scratchpad_input_generation += 1
        }
        return
    }
    if slot^.parse_result == julia.SCRATCHPAD_PARSE_COMPLETE && slot^.succeeded {
        ui_runtime^.scratchpad_input_len = 0
        ui_runtime^.scratchpad_input_cursor = 0
        ui_runtime^.scratchpad_input_viewport_col_start = 0
        ui_runtime^.scratchpad_input_generation += 1
    }
}

//   Apply only the newest completion request for the current input generation.
apply_scratchpad_completion_result :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    slot: ^julia.Scratchpad_Async_Slot) {

    if slot^.request_id != ui_runtime^.scratchpad_latest_completion_request_id {
        return
    }
    payload := julia.scratchpad_async_result_text(slot)
    replace_start, replace_end, replacement, ok :=
        scratchpad_parse_completion_payload(payload)
    if !ok || replace_start > ui_runtime^.scratchpad_input_len ||
        replace_end > ui_runtime^.scratchpad_input_len {
        return
    }
    if input_box_replace_byte_range(
        ui_runtime^.scratchpad_input[:], &ui_runtime^.scratchpad_input_len,
        &ui_runtime^.scratchpad_input_cursor, replace_start, replace_end, replacement) {
        ui_runtime^.scratchpad_input_generation += 1
    }
}

//   Apply Julia/Help prompt transitions after one input frame.
apply_scratchpad_mode_transition :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    input_result: Input_Box_Result,
    previous_len, previous_cursor: int) -> bool {

    if ui_runtime^.scratchpad_input_mode == .Help && previous_len == 0 &&
        input_result.backspace_pressed {
        ui_runtime^.scratchpad_input_mode = .Julia
        return true
    }
    if ui_runtime^.scratchpad_input_mode != .Julia || previous_cursor != 0 ||
        input_result.paste_applied || ui_runtime^.scratchpad_input_len <= 0 ||
        ui_runtime^.scratchpad_input[0] != '?' {
        return false
    }

    _ = input_box_replace_byte_range(
        ui_runtime^.scratchpad_input[:],
        &ui_runtime^.scratchpad_input_len,
        &ui_runtime^.scratchpad_input_cursor,
        0, 1, "")
    ui_runtime^.scratchpad_input_mode = .Help
    return true
}


//   Run the scroll container for the scratchpad transcript and return its panel.
//   Updates the live scroll offset and re-pins the bottom when the user scrolls.
scratchpad_sync_scroll :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    text_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    layout: Scratchpad_Terminal_Layout,
    scroll_step: f32) -> Scroll_Container_Begin_Result {

    scratch_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.text_scroll_dragging,
        drag_offset_y = ui_runtime.text_scroll_drag_off,
    }
    pre_wheel_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_begin := scroll_container_begin(1002, text_panel,
        state^.ui_runtime.view_text_scroll_y, layout.content_height, mouse_input,
        rl.Vector2{}, text_panel, scroll_step * WHEEL_SCROLL_MULTIPLIER,
        &ui_runtime^.ui_press_owner, scratch_scroll_state)
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_begin.scroll_y_out

    if state^.ui_runtime.view_text_scroll_y != pre_wheel_scroll {
        ui_runtime^.scratchpad_bottom_pinned = scratchpad_scroll_is_at_bottom(
            state^.ui_runtime.view_text_scroll_y, layout.max_scroll)
    }

    return scratch_scroll_begin
}

//   Recompute the layout pinned to the bottom when bottom-pinning is active.
scratchpad_pin_layout_to_bottom :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    terminal_panel: rl.Rectangle,
    font: rl.Font,
    output_text_legacy: string,
    layout: Scratchpad_Terminal_Layout) -> Scratchpad_Terminal_Layout {

    if !ui_runtime^.scratchpad_bottom_pinned {
        return layout
    }
    state^.ui_runtime.view_text_scroll_y = layout.max_scroll
    return scratchpad_terminal_layout(
        state, terminal_panel, ui_runtime, font, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)
}

//   Draw Scratchpad transcript and live input as one terminal-style scroll surface.
draw_scratchpad_output_and_prompt :: proc(
    state: ^core.Euclid_General_State,
    text_panel: rl.Rectangle,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font,
    mouse_input: Mouse_Input_State) {

    output_text_legacy := julia.current_view_snapshot_text(state)
    output_text := dynview.scratchpad_text_or_fallback(&state.dynview, output_text_legacy)
    layout := scratchpad_terminal_layout(
        state, text_panel, ui_runtime, font, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)
    scroll_step :=
        dynview.scratchpad_scroll_step_or_fallback(&state.dynview, TEXT_ROW_HEIGHT)

    output_len := len(output_text)
    if output_len != ui_runtime^.scratchpad_last_output_len {
        if ui_runtime^.scratchpad_bottom_pinned {
            state^.ui_runtime.view_text_scroll_y = layout.max_scroll
        }
        ui_runtime^.scratchpad_last_output_len = output_len
    }

    mouse := mouse_input.position
    scratch_scroll_begin := scratchpad_sync_scroll(state, ui_runtime,
        text_panel, mouse_input, layout, scroll_step)
    terminal_panel := scratch_scroll_begin.view_rect

    layout = scratchpad_terminal_layout(
        state, terminal_panel, ui_runtime, font, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)

    dynview.refresh_scratchpad_copy_targets(&state.dynview, terminal_panel,
        state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING, TEXT_ROW_HEIGHT, DYNVIEW_COPY_ICON_SIZE, DYNVIEW_COPY_ICON_X_PAD)

    view_core.draw_copy_hover_backgrounds(&state^.dynview, mouse)

    ui_dynview.draw_scratchpad_styled_or_fallback(state, ui_runtime,
        output_text_legacy, terminal_panel, state^.ui_runtime.view_text_scroll_y,
        font, TEXT_PADDING, TEXT_ROW_HEIGHT, TEXT_WRAP_ADVANCE,
        TREE_FONT_SIZE, UI_TEXT_COLOR)

    _ = view_core.draw_copy_icons(&state^.dynview, terminal_panel, mouse_input)

    previous_input_len := ui_runtime^.scratchpad_input_len
    previous_input_cursor := ui_runtime^.scratchpad_input_cursor
    live_prompt := scratchpad_prompt(ui_runtime^.scratchpad_input_mode)
    input_result := handle_input_box(Input_Box_Params{
        id = 5001,
        rect = layout.input_rect,
        text_buffer = ui_runtime^.scratchpad_input[:],
        text_len_in = ui_runtime^.scratchpad_input_len,
        caret_col_in = ui_runtime^.scratchpad_input_cursor,
        viewport_col_start_in = ui_runtime^.scratchpad_input_viewport_col_start,
        enabled = true,
        has_focus = true,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = terminal_panel,
        interaction_enabled = true,
        font = font,
        font_color = rl.Color{255, 255, 255, 255},
        font_size = TREE_FONT_SIZE,
        char_advance = TEXT_WRAP_ADVANCE,
        prompt_prefix = live_prompt,
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
        terminal_mode = true,
        terminal_row_height = TEXT_ROW_HEIGHT,
    }, &ui_runtime^.ui_press_owner)

    ui_runtime^.scratchpad_input_len = input_result.text_len_out
    ui_runtime^.scratchpad_input_cursor = input_result.caret_col_out
    ui_runtime^.scratchpad_input_viewport_col_start = input_result.viewport_col_start_out

    mode_changed := apply_scratchpad_mode_transition(
        ui_runtime, input_result, previous_input_len, previous_input_cursor)
    if input_result.changed || input_result.paste_applied || mode_changed {
        ui_runtime^.scratchpad_input_generation += 1
        ui_runtime^.scratchpad_history_reset_pending = true
        flush_scratchpad_history_reset(state, ui_runtime)
    }

    apply_scratchpad_history_navigation(state, ui_runtime,
        input_result.history_previous && !input_result.moved_up,
        input_result.history_next && !input_result.moved_down)

    request_scratchpad_completion(state, ui_runtime, input_result.tab_pressed)

    submit_scratchpad_input_if_ready(state, ui_runtime, input_result.submit_pressed)

    layout = scratchpad_terminal_layout(
        state, terminal_panel, ui_runtime, font, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)
    layout = scratchpad_pin_layout_to_bottom(state, ui_runtime, terminal_panel,
        font, output_text_legacy, layout)

    prompt_font := view_core.font_runtime_resolve(
        state, core.Font_Variant_Flags.Bold, i32(TREE_FONT_SIZE))
    live_prompt = scratchpad_prompt(ui_runtime^.scratchpad_input_mode)
    prompt_color := rl.Color{56, 152, 38, 255}
    if ui_runtime^.scratchpad_input_mode == .Help {
        prompt_color = rl.Color{217, 180, 74, 255}
    }

    draw_input_box(Input_Box_Draw_Params{
        rect = layout.input_rect,
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
        prompt_prefix = live_prompt,
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
        terminal_mode = true,
        terminal_row_height = TEXT_ROW_HEIGHT,
        terminal_background_color = UI_COMPONENT_BACKGROUND_COLOR,
        terminal_prompt_color = prompt_color,
        terminal_prompt_font = prompt_font,
    })

    pre_drag_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_end := scroll_container_end(scratch_scroll_begin.scroll_ref,
        layout.content_height, state^.ui_runtime.view_text_scroll_y, mouse_input,
        rl.Vector2{}, terminal_panel, &ui_runtime^.ui_press_owner)
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = scratch_scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = scratch_scroll_end.state_out.drag_offset_y
    if state^.ui_runtime.view_text_scroll_y != pre_drag_scroll {
        ui_runtime^.scratchpad_bottom_pinned = scratchpad_scroll_is_at_bottom(
            state^.ui_runtime.view_text_scroll_y, layout.max_scroll)
    }
}
