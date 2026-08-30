package ui

import "../../core"
import "../../dynview"
import julia "../../bridge"
import view_core "../core"
import "../font"
import ui_dynview "./dynview"

import "core:strings"
import rl "vendor:raylib"

SCRATCHPAD_JULIA_PROMPT :: "julia> "
SCRATCHPAD_HELP_PROMPT :: "help?> "
SCRATCHPAD_SCROLL_BOTTOM_EPSILON :: 0.5

Scratchpad_Terminal_Layout :: struct {
    transcript_height : f32,
    input_rows : int,
    content_height : f32,
    max_scroll : f32,
    input_rect : rl.Rectangle,
}

Scratchpad_Completion_Payload :: struct {
    replace_start : int,
    replace_end : int,
    replacement : string,
    ok : bool,
}

Scratchpad_History_Payload :: struct {
    mode : core.Scratchpad_Input_Mode,
    text : string,
    ok : bool,
}

//   Shared panel/font context for scratchpad layout and scroll operations.
Scratchpad_Panel_Context :: struct {
    state : ^core.Euclid_General_State,
    ui_runtime : ^core.Euclid_Ui_Runtime_State,
    panel : rl.Rectangle,
    font : rl.Font,
}

//   Return the live terminal prompt for the active Scratchpad editor mode.
scratchpad_prompt :: #force_inline proc(mode: core.Scratchpad_Input_Mode) -> string {
    return mode == .Help ? SCRATCHPAD_HELP_PROMPT : SCRATCHPAD_JULIA_PROMPT
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
scratchpad_input_text :: proc(ui_runtime: ^core.Euclid_Ui_Runtime_State) -> string {
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

//   Find the first and second newline offsets in one payload.
//
// Returns:
//   - first: Offset of the first newline, or -1.
//   - second: Offset of the second newline, or -1.
scratchpad_find_payload_newlines :: proc(payload: string) -> (int, int) {
    first := -1
    second := -1
    for i in 0..<len(payload) {
        if payload[i] != '\n' {
            continue
        }
        if first < 0 {
            first = i
        } else {
            second = i
            break
        }
    }
    return first, second
}

//   Decode a generic completion payload encoded as `start\nend\nreplacement`.
scratchpad_parse_completion_payload :: proc(
    payload: string) -> Scratchpad_Completion_Payload {
    if len(payload) <= 0 {
        return Scratchpad_Completion_Payload{0, 0, "", false}
    }

    first_newline, second_newline := scratchpad_find_payload_newlines(payload)
    if first_newline < 0 || second_newline < 0 || second_newline <= first_newline + 1 {
        return Scratchpad_Completion_Payload{0, 0, "", false}
    }

    start_text := payload[:first_newline]
    end_text := payload[first_newline + 1:second_newline]
    replace_start, ok := scratchpad_parse_non_negative_int(start_text)
    if !ok {
        return Scratchpad_Completion_Payload{0, 0, "", false}
    }

    replace_end := 0
    replace_end, ok = scratchpad_parse_non_negative_int(end_text)
    if !ok {
        return Scratchpad_Completion_Payload{0, 0, "", false}
    }

    replacement := payload[second_newline + 1:]
    return Scratchpad_Completion_Payload{
        replace_start = replace_start,
        replace_end = replace_end,
        replacement = replacement,
        ok = true,
    }
}

//   Decode a mode-tagged history payload encoded as `mode\ntext`.
scratchpad_parse_history_payload :: proc(
    payload: string) -> Scratchpad_History_Payload {

    newline := strings.index_byte(payload, '\n')
    if newline < 0 {
        return Scratchpad_History_Payload{.Julia, "", false}
    }
    mode_value, ok := scratchpad_parse_non_negative_int(payload[:newline])
    if !ok || mode_value > int(core.Scratchpad_Input_Mode.Help) {
        return Scratchpad_History_Payload{.Julia, "", false}
    }
    return Scratchpad_History_Payload{
        core.Scratchpad_Input_Mode(mode_value), payload[newline + 1:], true}
}

//   Submit one generic completion request without blocking the display thread.
request_scratchpad_completion :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    tab_pressed: bool) {

    if !tab_pressed || state == nil || ui_runtime == nil {
        return
    }

    input_text := scratchpad_input_text(ui_runtime)
    if len(input_text) <= 0 {
        return
    }

    request_id, sent := julia.try_submit_scratchpad_async(
        state, .Complete, julia.get_scratchpad_submission(
            input_text, ui_runtime^.scratchpad_input_cursor,
            ui_runtime^.scratchpad_input_mode,
            ui_runtime^.scratchpad_input_generation))
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
    ctx: Scratchpad_Panel_Context,
    fallback_text: string,
    scroll_y: f32) -> Scratchpad_Terminal_Layout {

    state := ctx.state
    panel := ctx.panel
    ui_runtime := ctx.ui_runtime
    font := ctx.font

    transcript_height: f32 = TEXT_PADDING
    if len(fallback_text) > 0 {
        transcript_height = dynview.scratchpad_content_height_or_fallback(&state^.dynview,
            panel, {
                text_padding = TEXT_PADDING,
                wrap_advance = TEXT_WRAP_ADVANCE,
                row_height = TEXT_ROW_HEIGHT,
                text = fallback_text,
            })
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
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    history_previous: bool,
    history_next: bool) {

    if history_previous {
        _, _ = julia.try_submit_scratchpad_async(
            state, .History_Previous,
            julia.get_scratchpad_submission(
                input_mode = ui_runtime^.scratchpad_input_mode,
                input_generation = ui_runtime^.scratchpad_input_generation))
    }

    if history_next {
        _, _ = julia.try_submit_scratchpad_async(
            state, .History_Next,
            julia.get_scratchpad_submission(
                input_mode = ui_runtime^.scratchpad_input_mode,
                input_generation = ui_runtime^.scratchpad_input_generation))
    }
}

//   Submit current scratchpad input when parse state is complete.
submit_scratchpad_input_if_ready :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
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
        state, .Submit,
        julia.get_scratchpad_submission(input_text,
            input_mode = ui_runtime^.scratchpad_input_mode,
            input_generation = ui_runtime^.scratchpad_input_generation))
    if sent {
        ui_runtime^.scratchpad_pending_submit_request_id = request_id
    }
}

//   Apply all completed Scratchpad replies at a display-frame boundary.
apply_scratchpad_async_results :: proc(
    state: ^core.Euclid_General_State, ui_runtime: ^core.Euclid_Ui_Runtime_State) {

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
    state: ^core.Euclid_General_State, ui_runtime: ^core.Euclid_Ui_Runtime_State) {

    if !ui_runtime^.scratchpad_history_reset_pending {
        return
    }
    _, sent := julia.try_submit_scratchpad_async(
        state, .History_Reset,
        julia.get_scratchpad_submission(
            input_generation = ui_runtime^.scratchpad_input_generation))
    if sent {
        ui_runtime^.scratchpad_history_reset_pending = false
    }
}

//   Apply one current-generation reply and ignore stale UI mutations.
apply_scratchpad_async_result :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    slot: ^julia.Scratchpad_Async_Slot) {

    forced_submit := ui_runtime^.scratchpad_forced_bottom_request_id != 0 &&
        slot^.kind == .Submit &&
        slot^.request_id == ui_runtime^.scratchpad_forced_bottom_request_id
    if slot^.kind == .Submit &&
        slot^.request_id == ui_runtime^.scratchpad_pending_submit_request_id {
        ui_runtime^.scratchpad_pending_submit_request_id = 0
    }
    if forced_submit {
        ui_runtime^.scratchpad_forced_bottom_request_id = 0
        ui_runtime^.scratchpad_bottom_pinned = true
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
        history_payload := scratchpad_parse_history_payload(
            julia.scratchpad_async_result_text(slot))
        if history_payload.ok {
            input_box_replace_text(
                ui_runtime^.scratchpad_input[:],
                &ui_runtime^.scratchpad_input_len,
                &ui_runtime^.scratchpad_input_cursor,
                history_payload.text)
            ui_runtime^.scratchpad_input_mode = history_payload.mode
            ui_runtime^.scratchpad_input_viewport_col_start = 0
        }
    case .History_Reset, .Save_History:
    }
}

//   Preserve incomplete/error input and clear only an accepted complete submit.
apply_scratchpad_submit_result :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
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
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    slot: ^julia.Scratchpad_Async_Slot) {

    if slot^.request_id != ui_runtime^.scratchpad_latest_completion_request_id {
        return
    }
    payload := julia.scratchpad_async_result_text(slot)
    completion_payload := scratchpad_parse_completion_payload(payload)
    if !completion_payload.ok ||
        completion_payload.replace_start > ui_runtime^.scratchpad_input_len ||
        completion_payload.replace_end > ui_runtime^.scratchpad_input_len {
        return
    }
    if input_box_replace_byte_range(
        ui_runtime^.scratchpad_input[:],
        Input_Box_Edit_State{
            text_len = &ui_runtime^.scratchpad_input_len,
            caret = &ui_runtime^.scratchpad_input_cursor,
        },
        completion_payload.replace_start,
        completion_payload.replace_end,
        completion_payload.replacement) {
        ui_runtime^.scratchpad_input_generation += 1
    }
}

//   Apply Julia/Help prompt transitions after one input frame.
apply_scratchpad_mode_transition :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
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
        Input_Box_Edit_State{
            text_len = &ui_runtime^.scratchpad_input_len,
            caret = &ui_runtime^.scratchpad_input_cursor,
        },
        0, 1, "")
    ui_runtime^.scratchpad_input_mode = .Help
    return true
}


//   Run the scroll container for the scratchpad transcript and return its panel.
//   Updates the live scroll offset and re-pins the bottom when the user scrolls.
scratchpad_sync_scroll :: proc(
    ctx: Scratchpad_Panel_Context,
    mouse_input: Mouse_Input_State,
    layout: Scratchpad_Terminal_Layout,
    scroll_step: f32) -> Scroll_Container_Begin_Result {

    state := ctx.state
    ui_runtime := ctx.ui_runtime
    text_panel := ctx.panel
    scratch_scroll_state := Scroll_Container_State{
        is_dragging_thumb = ui_runtime.text_scroll_dragging,
        drag_offset_y = ui_runtime.text_scroll_drag_off,
    }
    pre_wheel_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_begin := scroll_container_begin(Scroll_Container_Begin_Params{
        id = 1002,
        rect = text_panel,
        scroll_y_in = state^.ui_runtime.view_text_scroll_y,
        content_height_hint = layout.content_height,
        mouse_input = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = text_panel,
        wheel_step = scroll_step * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &ui_runtime^.ui_press_owner,
        state_in = scratch_scroll_state,
    })
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_begin.scroll_y_out

    if state^.ui_runtime.view_text_scroll_y != pre_wheel_scroll &&
        ui_runtime^.scratchpad_forced_bottom_request_id == 0 {

        ui_runtime^.scratchpad_bottom_pinned = scratchpad_scroll_is_at_bottom(
            state^.ui_runtime.view_text_scroll_y, layout.max_scroll)
    }

    return scratch_scroll_begin
}

//   Recompute the layout pinned to the bottom when bottom-pinning is active.
scratchpad_pin_layout_to_bottom :: proc(
    ctx: Scratchpad_Panel_Context,
    output_text_legacy: string,
    layout: Scratchpad_Terminal_Layout) -> Scratchpad_Terminal_Layout {

    if !ctx.ui_runtime^.scratchpad_bottom_pinned {
        return layout
    }
    ctx.state^.ui_runtime.view_text_scroll_y = layout.max_scroll
    return scratchpad_terminal_layout(ctx, output_text_legacy,
        ctx.state^.ui_runtime.view_text_scroll_y)
}

//   Draw the transcript text and copy affordances for one scratchpad frame.
draw_scratchpad_transcript :: proc(
    ctx: Scratchpad_Panel_Context,
    output_text_legacy: string,
    terminal_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    dynview.refresh_scratchpad_copy_targets(&ctx.state.dynview, {
        panel = terminal_panel,
        scroll_y = ctx.state^.ui_runtime.view_text_scroll_y,
        text_padding = TEXT_PADDING,
        icon_size = DYNVIEW_COPY_ICON_SIZE,
        icon_x_pad = DYNVIEW_COPY_ICON_X_PAD,
    })

    view_core.draw_copy_hover_backgrounds(&ctx.state^.dynview, mouse_input.position)

    ui_dynview.draw_scratchpad_styled_or_fallback(ctx.state, ctx.ui_runtime,
        ui_dynview.Fallback_Text_Content{output_text_legacy, UI_TEXT_COLOR},
        ui_dynview.Scratchpad_Draw_Params{
            panel = terminal_panel,
            scroll_y = ctx.state^.ui_runtime.view_text_scroll_y,
            font = ctx.font,
            font_cache = &ctx.state^.font_cache,
            metrics = ui_dynview.Wrapped_Text_Metrics{
                padding = TEXT_PADDING,
                row_height = TEXT_ROW_HEIGHT,
                wrap_advance = TEXT_WRAP_ADVANCE,
                font_size = TREE_FONT_SIZE,
            },
        })

    _ = view_core.draw_copy_icons(&ctx.state^.dynview, terminal_panel, mouse_input)
}

//   Build the input-box params for the scratchpad live terminal input.
scratchpad_input_box_params :: #force_inline proc(
    ctx: Scratchpad_Panel_Context,
    layout: Scratchpad_Terminal_Layout,
    terminal_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) -> Input_Box_Params {

    ui_runtime := ctx.ui_runtime
    return Input_Box_Params{
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
        font = ctx.font,
        font_color = rl.Color{255, 255, 255, 255},
        font_size = TREE_FONT_SIZE,
        char_advance = TEXT_WRAP_ADVANCE,
        prompt_prefix = scratchpad_prompt(ui_runtime^.scratchpad_input_mode),
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
        terminal_mode = true,
        terminal_row_height = TEXT_ROW_HEIGHT,
    }
}

//   Apply the side effects of one handled input frame (state commit + actions).
apply_scratchpad_input_result :: proc(
    ctx: Scratchpad_Panel_Context,
    input_result: Input_Box_Result,
    previous_input_len, previous_input_cursor: int) {

    state := ctx.state
    ui_runtime := ctx.ui_runtime
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
}

//   Handle the live input box for one scratchpad frame, applying edit side effects.
handle_scratchpad_input :: proc(
    ctx: Scratchpad_Panel_Context,
    layout: Scratchpad_Terminal_Layout,
    terminal_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    ui_runtime := ctx.ui_runtime
    previous_input_len := ui_runtime^.scratchpad_input_len
    previous_input_cursor := ui_runtime^.scratchpad_input_cursor
    input_result := handle_input_box(
        scratchpad_input_box_params(ctx, layout, terminal_panel, mouse_input),
        &ui_runtime^.ui_press_owner)

    apply_scratchpad_input_result(ctx, input_result,
        previous_input_len, previous_input_cursor)
}

//   Draw the live input box with the resolved prompt styling.
draw_scratchpad_input_box :: proc(
    ctx: Scratchpad_Panel_Context,
    layout: Scratchpad_Terminal_Layout,
    mouse_input: Mouse_Input_State) {

    ui_runtime := ctx.ui_runtime
    prompt_font := font.cache_resolve(&ctx.state^.font_cache, .Bold)
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
        font = ctx.font,
        font_color = UI_TEXT_COLOR,
        font_size = TREE_FONT_SIZE,
        char_advance = TEXT_WRAP_ADVANCE,
        prompt_prefix = scratchpad_prompt(ui_runtime^.scratchpad_input_mode),
        caret_blink_half_period_seconds = SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS,
        terminal_mode = true,
        terminal_row_height = TEXT_ROW_HEIGHT,
        terminal_background_color = UI_COMPONENT_BACKGROUND_COLOR,
        terminal_prompt_color = prompt_color,
        terminal_prompt_font = prompt_font,
        font_cache = &ctx.state^.font_cache,
        font_key = .Regular,
    })
}

//   Finalize the scroll container for one scratchpad frame, updating pin state.
scratchpad_finish_scroll :: proc(
    ctx: Scratchpad_Panel_Context,
    scroll_begin: Scroll_Container_Begin_Result,
    layout: Scratchpad_Terminal_Layout,
    terminal_panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    state := ctx.state
    ui_runtime := ctx.ui_runtime
    pre_drag_scroll := state^.ui_runtime.view_text_scroll_y
    scratch_scroll_end := scroll_container_end(Scroll_Container_End_Params{
        scroll_ref = scroll_begin.scroll_ref,
        content_height_final = layout.content_height,
        scroll_y_in = state^.ui_runtime.view_text_scroll_y,
        mouse_input = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = terminal_panel,
        press_owner = &ui_runtime^.ui_press_owner,
    })
    state^.ui_runtime.view_text_scroll_y = scratch_scroll_end.scroll_y_out
    ui_runtime.text_scroll_dragging = scratch_scroll_end.state_out.is_dragging_thumb
    ui_runtime.text_scroll_drag_off = scratch_scroll_end.state_out.drag_offset_y
    if state^.ui_runtime.view_text_scroll_y != pre_drag_scroll &&
        ui_runtime^.scratchpad_forced_bottom_request_id == 0 {

        ui_runtime^.scratchpad_bottom_pinned = scratchpad_scroll_is_at_bottom(
            state^.ui_runtime.view_text_scroll_y, layout.max_scroll)
    }
}

//   Track transcript length changes and re-pin the scroll to the bottom.
scratchpad_track_output_length :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    output_len: int,
    max_scroll: f32) {

    if output_len == ui_runtime^.scratchpad_last_output_len {
        return
    }
    if ui_runtime^.scratchpad_bottom_pinned {
        state^.ui_runtime.view_text_scroll_y = max_scroll
    }
    ui_runtime^.scratchpad_last_output_len = output_len
}

//   Draw Scratchpad transcript and live input as one terminal-style scroll surface.
draw_scratchpad_output_and_prompt :: proc(
    state: ^core.Euclid_General_State,
    text_panel: rl.Rectangle,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    font: rl.Font,
    mouse_input: Mouse_Input_State) {

    output_text_legacy := julia.current_view_snapshot_text(state)
    output_text := dynview.scratchpad_text_or_fallback(&state.dynview, output_text_legacy)
    panel_ctx := Scratchpad_Panel_Context{state, ui_runtime, text_panel, font}
    layout := scratchpad_terminal_layout(panel_ctx, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)
    scroll_step :=
        dynview.scratchpad_scroll_step_or_fallback(&state.dynview, TEXT_ROW_HEIGHT)
    scratchpad_track_output_length(state, ui_runtime, len(output_text),
        layout.max_scroll)

    scratch_scroll_begin := scratchpad_sync_scroll(
        panel_ctx, mouse_input, layout, scroll_step)
    terminal_panel := scratch_scroll_begin.view_rect
    ctx := Scratchpad_Panel_Context{state, ui_runtime, terminal_panel, font}

    layout = scratchpad_terminal_layout(ctx, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)

    draw_scratchpad_transcript(panel_ctx, output_text_legacy, terminal_panel,
        mouse_input)

    handle_scratchpad_input(ctx, layout, terminal_panel, mouse_input)

    layout = scratchpad_terminal_layout(ctx, output_text_legacy,
        state^.ui_runtime.view_text_scroll_y)
    layout = scratchpad_pin_layout_to_bottom(ctx, output_text_legacy, layout)

    draw_scratchpad_input_box(ctx, layout, mouse_input)

    scratchpad_finish_scroll(ctx, scratch_scroll_begin, layout, terminal_panel,
        mouse_input)
}
