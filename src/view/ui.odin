package view

// Here is where we draw and handle all the UI stuff that wraps outside the animations.
// This is mostly all built off of the Julia Interfaces, and in fact, we call into the
// Odin-Julia Bridge to get the data as we need it for the view text, etc.

import "../core"
import "../julia"

import "core:fmt"
import "core:math"
import "core:strings"

import rl "vendor:raylib"

TREE_PANEL_PADDING :: 10
TREE_ROW_HEIGHT :: 22
TREE_INDENT :: 16
TREE_FONT_SIZE :: 18
TEXT_ROW_HEIGHT :: 22
TEXT_PADDING :: 8
TEXT_WRAP_ADVANCE :: 6.605
SCROLLBAR_WIDTH :: 8
SCROLLBAR_THUMB_MIN_HEIGHT :: 24
TREE_TOOLBAR_HEIGHT :: 28
TREE_TOOLBAR_BUTTON_SIZE :: 20
TREE_TOOLBAR_GAP :: 6
SETTINGS_TRACK_HEIGHT :: 8
SETTINGS_KNOB_WIDTH :: 10
WHEEL_SCROLL_MULTIPLIER :: 2
SCROLLBAR_DRAG_EPSILON :: 0.001
TREE_ROW_ICON_OFFSET_X :: 2
TREE_ROW_ICON_OFFSET_Y :: 3
TREE_ROW_ICON_SIZE :: 16
TREE_ROW_LABEL_OFFSET_X :: 22
TREE_ROW_LABEL_OFFSET_Y :: 2

SETTINGS_PANEL_INSET :: 8
SETTINGS_HEADER_TOP_OFFSET :: 8
SETTINGS_SLIDER_LABEL_TOP_OFFSET :: 36
SETTINGS_TRACK_TOP_OFFSET :: 22
SETTINGS_TRACK_HIT_PAD_Y :: 6
SETTINGS_KNOB_PAD_Y :: 4
SETTINGS_VALUE_TOP_OFFSET :: 16
SETTINGS_STATS_TOP_OFFSET :: 46
SETTINGS_STATS_ROW_GAP :: 22
SETTINGS_TOGGLE_TOP_OFFSET :: 118
SETTINGS_CHECKBOX_SIZE :: 14
SETTINGS_CHECKBOX_LABEL_GAP :: 8
SETTINGS_GIF_TOP_OFFSET :: 185
SETTINGS_GIF_SLIDER_ROW_GAP :: 36
SETTINGS_GIF_BUTTON_TOP_OFFSET :: 132
SETTINGS_GIF_BUTTON_HEIGHT :: 24
SETTINGS_GIF_STATUS_TOP_OFFSET :: 162
SCRATCHPAD_CURSOR_BLINK_HALF_PERIOD_SECONDS :: 0.53

Tree_Hit :: struct {
    SelectedID: int,
    ToggledID:  int,
}

Tree_Toolbar_Hit :: struct {
    RefreshRequested: bool,
    ToggleSettingsRequested: bool,
}

//   Render the right-side tree panel and route toolbar interactions.
//
// Parameters:
//   - state: Global app state containing tree/UI runtime and Julia interface state.
//
// Returns:
//   - none.
draw_tree_view :: proc(state: ^core.Euclid_General_State) {
    ji := state.julia_interface
    ui_runtime := &state.ui_runtime

    panel := rl.Rectangle{
        VIEW_WIDTH + TREE_PANEL_PADDING,
        TREE_PANEL_PADDING,
        RIGHT_BAR_WIDTH - TREE_PANEL_PADDING * 2,
        WINDOW_HEIGHT - TREE_PANEL_PADDING * 2,
    }

    rl.DrawRectangleRec(panel, BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    mouse := rl.GetMousePosition()
    toolbar_panel, list_panel := build_tree_view_panels(panel)

    toolbar_hit := draw_tree_toolbar(toolbar_panel, mouse, ui_runtime.show_tree_settings)
    if toolbar_hit.RefreshRequested {
        ji.pending_animation_reset = true
    }

    if toolbar_hit.ToggleSettingsRequested {
        ui_runtime.show_tree_settings = !ui_runtime.show_tree_settings
        ui_runtime.tree_scroll_dragging = false
    }

    if ui_runtime.show_tree_settings {
        draw_settings_view(state, list_panel, mouse)
        return
    }
    draw_tree_list_panel(ji, ui_runtime, list_panel, mouse, &state^.ui_runtime.tree_scroll_y, state.font)
}

//   Render wrapped animation view text with scroll handling.
//
// Parameters:
//   - state: Global app state containing current animation text and UI scroll state.
//
// Returns:
//   - none.
draw_view_text_panel :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state.julia_interface == nil {
        return
    }

    ui_runtime := &state.ui_runtime

    panel := rl.Rectangle{
        TREE_PANEL_PADDING,
        VIEW_HEIGHT + TREE_PANEL_PADDING,
        VIEW_WIDTH - TREE_PANEL_PADDING * 2,
        BOTTOM_BAR_HEIGHT - TREE_PANEL_PADDING * 2,
    }

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

    view_text := julia.call_current_animation_get_view_text(state)

    max_chars := chars_per_text_row(text_panel.width - TEXT_PADDING * 2)
    total_rows := count_wrapped_text_rows(view_text, max_chars)
    content_h := TEXT_PADDING * 2 + f32(total_rows) * TEXT_ROW_HEIGHT
    max_scroll := max(0.0, content_h - text_panel.height)
    clamp_scroll_position(&state^.ui_runtime.view_text_scroll_y, max_scroll)

    mouse := rl.GetMousePosition()
    apply_wheel_scroll(mouse, text_panel, TEXT_ROW_HEIGHT, &state^.ui_runtime.view_text_scroll_y, max_scroll)

    rl.BeginScissorMode(i32(text_panel.x), i32(text_panel.y), i32(text_panel.width), i32(text_panel.height))
    {
        draw_wrapped_text_content(view_text, text_panel, state^.ui_runtime.view_text_scroll_y, state.font)
    }
    rl.EndScissorMode()

    track, thumb, thumb_h, has_scrollbar :=
        build_vertical_scrollbar(text_panel, content_h, state^.ui_runtime.view_text_scroll_y, max_scroll)
    if has_scrollbar {

        handle_scrollbar_drag(
            mouse,
            thumb,
            text_panel.y,
            text_panel.height,
            thumb_h,
            max_scroll,
            &state^.ui_runtime.view_text_scroll_y,
            &ui_runtime.text_scroll_dragging,
            &ui_runtime.text_scroll_drag_off,
        )

        rl.DrawRectangleRec(track, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb, UI_BORDER_COLOR)
    }
}


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

        // Phase 1 keeps input ASCII-only for simple byte-safe buffer edits.
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

    if rl.IsKeyPressed(.RIGHT) && ui_runtime^.scratchpad_input_cursor < ui_runtime^.scratchpad_input_len {
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

    output_text := julia.call_current_animation_get_view_text(state)
    max_chars := chars_per_text_row(output_panel.width - TEXT_PADDING * 2)
    total_rows := count_wrapped_text_rows(output_text, max_chars)
    content_h := TEXT_PADDING * 2 + f32(total_rows) * TEXT_ROW_HEIGHT
    max_scroll := max(0.0, content_h - output_panel.height)

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
    apply_wheel_scroll(mouse, output_panel, TEXT_ROW_HEIGHT, &state^.ui_runtime.view_text_scroll_y, max_scroll)
    if state^.ui_runtime.view_text_scroll_y != pre_wheel_scroll {
        ui_runtime^.scratchpad_follow_output = true
    }

    rl.BeginScissorMode(i32(output_panel.x), i32(output_panel.y), i32(output_panel.width), i32(output_panel.height))
    {
        draw_wrapped_text_content(output_text, output_panel, state^.ui_runtime.view_text_scroll_y, font)
    }
    rl.EndScissorMode()

    track, thumb, thumb_h, has_scrollbar :=
        build_vertical_scrollbar(output_panel, content_h, state^.ui_runtime.view_text_scroll_y, max_scroll)
    if has_scrollbar {
        pre_drag_scroll := state^.ui_runtime.view_text_scroll_y
        handle_scrollbar_drag(
            mouse,
            thumb,
            output_panel.y,
            output_panel.height,
            thumb_h,
            max_scroll,
            &state^.ui_runtime.view_text_scroll_y,
            &ui_runtime.text_scroll_dragging,
            &ui_runtime.text_scroll_drag_off,
        )
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
        1,
        UI_BORDER_COLOR,
    )

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




//   Draw UTF-8 UI text using the shared font and temp C-string conversion.
ui_text :: #force_inline proc(text: string, x, y: int, color: rl.Color, font: rl.Font) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawTextEx(font, cloned, rl.Vector2{f32(x), f32(y)}, TREE_FONT_SIZE, 0, color)
}

//   Draw the circular refresh glyph used in the tree toolbar.
draw_refresh_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5
    radius := min(rect.width, rect.height) * 0.34
    thickness: f32 = 1.6
    arrow_size := radius * 0.55

    start1: f32 = math.PI * (2.0 / 9.0)
    end1: f32 = math.PI * (10.0 / 9.0)
    start2: f32 = math.PI * (11.0 / 9.0)
    end2: f32 = math.PI * (19.0 / 9.0)

    draw_arc_polyline(cx, cy, radius, start1, end1, thickness, color)
    draw_arc_arrowhead(cx, cy, radius, end1, arrow_size, thickness, color)

    draw_arc_polyline(cx, cy, radius, start2, end2, thickness, color)
    draw_arc_arrowhead(cx, cy, radius, end2, arrow_size, thickness, color)
}

//   Draw an approximated arc segment using connected line segments.
draw_arc_polyline :: proc(
    cx, cy, radius: f32,
    start_angle, end_angle: f32,
    thickness: f32,
    color: rl.Color) {
    segments := 10

    prev_angle := start_angle
    prev := rl.Vector2{
        cx + radius * f32(math.cos(f64(prev_angle))),
        cy + radius * f32(math.sin(f64(prev_angle))),
    }

    for i in 1..<(segments + 1) {
        t := f32(i) / f32(segments)
        angle := start_angle + (end_angle - start_angle) * t
        current := rl.Vector2{
            cx + radius * f32(math.cos(f64(angle))),
            cy + radius * f32(math.sin(f64(angle))),
        }

        rl.DrawLineEx(prev, current, thickness, color)
        prev = current
    }
}

//   Draw an arrowhead tangent to an arc at the provided angle.
draw_arc_arrowhead :: proc(
    cx, cy, radius: f32,
    angle: f32,
    size: f32,
    thickness: f32,
    color: rl.Color) {
    tip := rl.Vector2{
        cx + radius * f32(math.cos(f64(angle))),
        cy + radius * f32(math.sin(f64(angle))),
    }

    tangent := rl.Vector2{-f32(math.sin(f64(angle))), f32(math.cos(f64(angle)))}
    back := rl.Vector2{tip.x - tangent.x * size, tip.y - tangent.y * size}
    perp := rl.Vector2{-tangent.y, tangent.x}

    wing_scale := size * 0.55
    left := rl.Vector2{back.x + perp.x * wing_scale, back.y + perp.y * wing_scale}
    right := rl.Vector2{back.x - perp.x * wing_scale, back.y - perp.y * wing_scale}

    rl.DrawLineEx(left, tip, thickness, color)
    rl.DrawLineEx(right, tip, thickness, color)
}

//   Draw expand/collapse chevron icon for tree nodes.
draw_tree_disclosure_icon :: proc(rect: rl.Rectangle, expanded: bool, color: rl.Color) {
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5

    left_top_x: f32 = -4.0
    left_top_y: f32 = -4.0
    left_bottom_x: f32 = -4.0
    left_bottom_y: f32 = 4.0
    tip_x: f32 = 2.0
    tip_y: f32 = 0.0

    if expanded {
        lt_x := -left_top_y
        lt_y := left_top_x
        lb_x := -left_bottom_y
        lb_y := left_bottom_x
        tp_x := -tip_y
        tp_y := tip_x

        left_top_x = lt_x
        left_top_y = lt_y
        left_bottom_x = lb_x
        left_bottom_y = lb_y
        tip_x = tp_x
        tip_y = tp_y
    }

    p0 := rl.Vector2{cx + left_top_x, cy + left_top_y}
    p1 := rl.Vector2{cx + tip_x, cy + tip_y}
    p2 := rl.Vector2{cx + left_bottom_x, cy + left_bottom_y}

    rl.DrawLineEx(p0, p1, 1.6, color)
    rl.DrawLineEx(p1, p2, 1.6, color)
}

//   Draw the settings/controls glyph for the toolbar toggle.
draw_gear_icon :: proc(rect: rl.Rectangle, color: rl.Color) {
    left := rect.x + 4
    right := rect.x + rect.width - 4
    y1 := rect.y + 5
    y2 := rect.y + rect.height * 0.5
    y3 := rect.y + rect.height - 5

    thickness: f32 = 1.5
    knob_r: f32 = 2.2

    rl.DrawLineEx(rl.Vector2{left, y1}, rl.Vector2{right, y1}, thickness, color)
    rl.DrawLineEx(rl.Vector2{left, y2}, rl.Vector2{right, y2}, thickness, color)
    rl.DrawLineEx(rl.Vector2{left, y3}, rl.Vector2{right, y3}, thickness, color)

    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.36, y1}, knob_r, color)
    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.64, y2}, knob_r, color)
    rl.DrawCircleV(rl.Vector2{rect.x + rect.width * 0.46, y3}, knob_r, color)
}

//   Draw a toolbar button and return click-hit state.
draw_toolbar_icon_button :: proc(
    rect: rl.Rectangle,
    mouse: rl.Vector2,
    active: bool,
    draw_icon: proc(rect: rl.Rectangle, color: rl.Color)) -> bool {
    hovered := rl.CheckCollisionPointRec(mouse, rect)
    pressed := hovered && rl.IsMouseButtonDown(.LEFT)

    icon_rect := rect
    icon_color := UI_TEXT_COLOR

    if active || pressed {
        rl.DrawRectangleRec(rect, UI_BORDER_COLOR)
        icon_color = BACKGROUND_COLOR
    }

    if pressed {
        icon_rect.x += 0.5
        icon_rect.y += 0.5
    }

    draw_icon(icon_rect, icon_color)
    return rl.IsMouseButtonPressed(.LEFT) && hovered
}

//   Render toolbar row and report refresh/settings toggle hits.
draw_tree_toolbar :: proc(
    panel: rl.Rectangle, mouse: rl.Vector2, show_settings: bool) -> Tree_Toolbar_Hit {
    hit := Tree_Toolbar_Hit{}

    rl.DrawRectangleRec(panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    refresh_rect := rl.Rectangle{
        panel.x + 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    settings_rect := rl.Rectangle{
        panel.x + panel.width - TREE_TOOLBAR_BUTTON_SIZE - 4,
        panel.y + (panel.height - TREE_TOOLBAR_BUTTON_SIZE) * 0.5,
        TREE_TOOLBAR_BUTTON_SIZE,
        TREE_TOOLBAR_BUTTON_SIZE,
    }

    hit.RefreshRequested =
        draw_toolbar_icon_button(refresh_rect, mouse, false, draw_refresh_icon)
    hit.ToggleSettingsRequested =
        draw_toolbar_icon_button(settings_rect, mouse, show_settings, draw_gear_icon)
    return hit
}

//   Compute label, track, and hit rectangles for the dust slider.
build_settings_slider_layout :: proc(panel: rl.Rectangle) -> (f32, rl.Rectangle, rl.Rectangle) {
    slider_label_y := panel.y + SETTINGS_SLIDER_LABEL_TOP_OFFSET

    slider_track := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        slider_label_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }

    slider_hit := rl.Rectangle{
        slider_track.x,
        slider_track.y - SETTINGS_TRACK_HIT_PAD_Y,
        slider_track.width,
        slider_track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }

    return slider_label_y, slider_track, slider_hit
}

//   Convert an integer slider value into normalized [0,1] ratio.
slider_value_ratio :: proc(value, max_value: int) -> f32 {
    if max_value <= 0 {
        return 0
    }
    return f32(value) / f32(max_value)
}

//   Build knob geometry from track bounds and normalized ratio.
build_slider_knob :: proc(slider_track: rl.Rectangle, ratio: f32) -> (f32, rl.Rectangle) {
    knob_center_x := slider_track.x + ratio * slider_track.width
    knob := rl.Rectangle{
        knob_center_x - SETTINGS_KNOB_WIDTH * 0.5,
        slider_track.y - SETTINGS_KNOB_PAD_Y,
        SETTINGS_KNOB_WIDTH,
        slider_track.height + SETTINGS_KNOB_PAD_Y * 2,
    }
    return knob_center_x, knob
}

//   Apply wheel/drag input to update max dust particle setting.
update_use_max_particles_slider :: proc(
    ps: ^core.Particle_System,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    mouse: rl.Vector2,
    max_particles: int,
    slider_track: rl.Rectangle,
    slider_hit: rl.Rectangle,
    knob: rl.Rectangle,
    knob_center_x: f32) {
    if !rl.IsMouseButtonDown(.LEFT) {
        ui_runtime.settings_slider_dragging = false
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, knob) {
        ui_runtime.settings_slider_dragging = true
        ui_runtime.settings_slider_drag_offset_x = mouse.x - knob_center_x
    }

    slider_hovered := rl.CheckCollisionPointRec(mouse, slider_hit)
    if slider_hovered {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            step := max(1, max_particles / 64)
            delta := int(math.round(f64(wheel * f32(step))))
            if delta == 0 {
                if wheel > 0 {
                    delta = step
                } else {
                    delta = -step
                }
            }

            next_value := ps.use_max_dust_particles + delta
            ps.use_max_dust_particles = clamp(next_value, 0, max_particles)
        }
    }

    if slider_track.width > 0 && ui_runtime.settings_slider_dragging &&
        rl.IsMouseButtonDown(.LEFT) {

        knob_target_x := mouse.x - ui_runtime.settings_slider_drag_offset_x
        t_drag := clamp((knob_target_x - slider_track.x) / slider_track.width, 0, 1)
        next_value := int(t_drag * f32(max_particles) + 0.5)
        ps.use_max_dust_particles = clamp(next_value, 0, max_particles)
    }
}

//   Render dust-capacity slider fill, knob, and value text.
draw_use_max_particles_slider :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    knob_center_x: f32,
    knob: rl.Rectangle,
    current_value: int,
    max_particles: int,
    font: rl.Font) {
    rl.DrawRectangleRec(slider_track, BACKGROUND_COLOR)
    rl.DrawRectangleRec(
        rl.Rectangle{
            slider_track.x,
            slider_track.y,
            max(0.0, knob_center_x - slider_track.x),
            slider_track.height,
        },
        UI_BORDER_COLOR,
    )
    rl.DrawRectangleRec(knob, UI_TEXT_COLOR)

    use_max_text := fmt.tprintf("%d / %d", current_value, max_particles)
    ui_text(
        use_max_text,
        int(panel.x + SETTINGS_PANEL_INSET),
        int(slider_track.y + SETTINGS_VALUE_TOP_OFFSET),
        UI_TEXT_COLOR,
        font,
    )
}

//   Render particle render-count statistics in settings view.
draw_settings_particle_stats :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    ps: ^core.Particle_System,
    font: rl.Font) {
    stats_y := slider_track.y + SETTINGS_STATS_TOP_OFFSET
    ui_text(
        fmt.tprintf("Dust particles Rendered: %d", ps.last_render_low),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y),
        UI_TEXT_COLOR,
        font,
    )
    ui_text(
        fmt.tprintf("Trail particles Rendered: %d", ps.last_render_mid),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y + SETTINGS_STATS_ROW_GAP),
        UI_TEXT_COLOR,
        font,
    )
    ui_text(
        fmt.tprintf("Flicker particles Rendered: %d", ps.last_render_high),
        int(panel.x + SETTINGS_PANEL_INSET),
        int(stats_y + SETTINGS_STATS_ROW_GAP * 2),
        UI_TEXT_COLOR,
        font,
    )
}

//   Render and handle the Display FPS toggle control.
draw_settings_fps_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {
    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    label := "Display FPS"

    // Keep hit target larger than the box so this is easy to click.
    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.display_fps = !ui_runtime.display_fps
    }

    rl.DrawRectangleLinesEx(box, 1, UI_BORDER_COLOR)
    if ui_runtime.display_fps {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, UI_TEXT_COLOR)
        rl.DrawLineEx(p1, p2, 1.6, UI_TEXT_COLOR)
    }

    ui_text(label, int(label_x), int(row_y - 1), UI_TEXT_COLOR, font)
}

//   Render and handle the Limit FPS toggle control.
draw_settings_limit_fps_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {
    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET + 22
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    label := "Limit FPS"

    // Keep hit target larger than the box so this is easy to click.
    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.limit_fps = !ui_runtime.limit_fps
        if ui_runtime.limit_fps {
            rl.SetTargetFPS(LIMIT_FPS)
        } else {
            rl.SetTargetFPS(0)
        }
    }

    rl.DrawRectangleLinesEx(box, 1, UI_BORDER_COLOR)
    if ui_runtime.limit_fps {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, UI_TEXT_COLOR)
        rl.DrawLineEx(p1, p2, 1.6, UI_TEXT_COLOR)
    }

    ui_text(label, int(label_x), int(row_y - 1), UI_TEXT_COLOR, font)
}

//   Render and handle the SIMD batch projection toggle control.
draw_settings_simd_projection_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {
    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET + 44
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    is_available := simd_batch_projection_available()
    label := "Use SIMD Projection"
    if !is_available {
        label = "Use SIMD Projection (Unavailable)"
    }

    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if is_available && rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.use_simd_batch_projection = !ui_runtime.use_simd_batch_projection
    }

    border := UI_BORDER_COLOR
    fg := UI_TEXT_COLOR
    if !is_available {
        border = rl.Color{78, 78, 78, 255}
        fg = rl.Color{110, 110, 110, 255}
        ui_runtime.use_simd_batch_projection = false
    }

    rl.DrawRectangleLinesEx(box, 1, border)
    if ui_runtime.use_simd_batch_projection {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, fg)
        rl.DrawLineEx(p1, p2, 1.6, fg)
    }

    ui_text(label, int(label_x), int(row_y - 1), fg, font)
}

//   Render and update a reusable integer slider control.
draw_settings_integer_slider :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse: rl.Vector2,
    label: string,
    value: ^int,
    min_value: int,
    max_value: int,
    font: rl.Font) {
    ui_text(label, int(panel.x + SETTINGS_PANEL_INSET), int(row_y), UI_TEXT_COLOR, font)

    track := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }

    hit := rl.Rectangle{
        track.x,
        track.y - SETTINGS_TRACK_HIT_PAD_Y,
        track.width,
        track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }

    clamped := clamp(value^, min_value, max_value)
    denom := max(1, max_value - min_value)
    ratio := f32(clamped - min_value) / f32(denom)
    knob_center_x, knob := build_slider_knob(track, ratio)

    if rl.CheckCollisionPointRec(mouse, hit) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            delta := 1
            if wheel < 0 {
                delta = -1
            }
            clamped = clamp(clamped + delta, min_value, max_value)
        }
    }

    if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        if track.width > 0 {
            t := clamp((mouse.x - track.x) / track.width, 0, 1)
            clamped = clamp(min_value + int(t * f32(denom) + 0.5), min_value, max_value)
        }
    }

    value^ = clamped

    ratio = f32(clamped - min_value) / f32(denom)
    knob_center_x, knob = build_slider_knob(track, ratio)

    rl.DrawRectangleRec(track, BACKGROUND_COLOR)
    rl.DrawRectangleRec(
        rl.Rectangle{
            track.x,
            track.y,
            max(0.0, knob_center_x - track.x),
            track.height,
        },
        UI_BORDER_COLOR,
    )
    rl.DrawRectangleRec(knob, UI_TEXT_COLOR)

    ui_text(
        fmt.tprintf("%d", clamped),
        int(panel.x + panel.width - SETTINGS_PANEL_INSET - 18),
        int(row_y),
        UI_TEXT_COLOR,
        font,
    )
}

//   Render and process the Save/Cancel GIF action button.
draw_settings_save_gif_button :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {
    button := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_GIF_BUTTON_HEIGHT,
    }

    is_armed := ui_runtime.gif_capture_phase == .Armed
    disabled := ui_runtime.gif_capture_phase == .Recording ||
        ui_runtime.gif_capture_phase == .Finalizing
    hovered := rl.CheckCollisionPointRec(mouse, button)
    pressed := hovered && rl.IsMouseButtonDown(.LEFT)

    bg := BACKGROUND_COLOR
    fg := UI_TEXT_COLOR
    border := UI_BORDER_COLOR

    if disabled {
        bg = rl.Color{48, 48, 48, 255}
        fg = rl.Color{110, 110, 110, 255}
        border = rl.Color{78, 78, 78, 255}
    } else if pressed {
        bg = UI_BORDER_COLOR
        fg = BACKGROUND_COLOR
        border = UI_BORDER_COLOR
    } else if hovered {
        bg = UI_COMPONENT_BACKGROUND_COLOR
    }

    rl.DrawRectangleRec(button, bg)
    rl.DrawRectangleLinesEx(button, 1, border)
    button_text := "Save Gif"
    if is_armed {
        button_text = "Cancel Gif"
    }
    ui_text(button_text, int(button.x + 8), int(button.y + 3), fg, font)

    if !disabled && rl.IsMouseButtonPressed(.LEFT) && hovered {
        ui_runtime.save_gif_requested = true
    }
}

//   Return human-readable status text for GIF capture phase.
gif_capture_status_label :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) -> string {
    switch ui_runtime.gif_capture_phase {
    case .Idle:
        return "Status: Idle"
    case .Armed:
        return "Status: Armed"
    case .Recording:
        return fmt.tprintf("Status: Recording (%d frames)", ui_runtime.gif_captured_frames)
    case .Finalizing:
        return "Status: Saving"
    case .Saved:
        return "Status: Saved"
    case .Error:
        return "Status: Error"
    }

    return "Status: Idle"
}

//   Render GIF capture status and last output path when available.
draw_settings_gif_status :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {
    ui_text(gif_capture_status_label(ui_runtime), int(panel.x + SETTINGS_PANEL_INSET), int(row_y), UI_TEXT_COLOR, font)

    if ui_runtime.gif_capture_phase == .Saved && ui_runtime.last_gif_path_len > 0 {
        path_text := string(ui_runtime.last_gif_path[:ui_runtime.last_gif_path_len])
        ui_text(
            fmt.tprintf("Path: %s", path_text),
            int(panel.x + SETTINGS_PANEL_INSET),
            int(row_y + 18),
            UI_TEXT_COLOR,
            font,
        )
    }
}

//   Render full settings panel and wire all settings controls.
draw_settings_view :: proc(
    state: ^core.Euclid_General_State, panel: rl.Rectangle, mouse: rl.Vector2) {

    if state == nil || state.particle_system == nil {
        return
    }

    ps := state.particle_system
    ui_runtime := &state.ui_runtime
    font := state.font

    rl.DrawRectangleRec(panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    header_y := int(panel.y + SETTINGS_HEADER_TOP_OFFSET)
    ui_text("Settings", int(panel.x + SETTINGS_PANEL_INSET), header_y, UI_TEXT_COLOR, font)

    slider_label_y, slider_track, slider_hit := build_settings_slider_layout(panel)
    ui_text("Maximum Dust particles", int(panel.x + SETTINGS_PANEL_INSET), int(slider_label_y), UI_TEXT_COLOR, font)

    max_particles := core.MAX_LOW_PARTICLES
    ps.use_max_dust_particles = clamp(ps.use_max_dust_particles, 0, max_particles)

    ratio := slider_value_ratio(ps.use_max_dust_particles, max_particles)
    knob_center_x, knob := build_slider_knob(slider_track, ratio)

    update_use_max_particles_slider(
        ps,
        ui_runtime,
        mouse,
        max_particles,
        slider_track,
        slider_hit,
        knob,
        knob_center_x,
    )

    ratio = slider_value_ratio(ps.use_max_dust_particles, max_particles)
    knob_center_x, knob = build_slider_knob(slider_track, ratio)

    draw_use_max_particles_slider(
        panel,
        slider_track,
        knob_center_x,
        knob,
        ps.use_max_dust_particles,
        max_particles,
        font,
    )
    draw_settings_particle_stats(panel, slider_track, ps, font)
    draw_settings_fps_checkbox(panel, slider_track, mouse, ui_runtime, font)
    draw_settings_limit_fps_checkbox(panel, slider_track, mouse, ui_runtime, font)
    draw_settings_simd_projection_checkbox(panel, slider_track, mouse, ui_runtime, font)

    gif_section_y := slider_track.y + SETTINGS_GIF_TOP_OFFSET
    ui_text("GIF Export", int(panel.x + SETTINGS_PANEL_INSET), int(gif_section_y), UI_TEXT_COLOR, font)

    draw_settings_integer_slider(
        panel,
        gif_section_y + SETTINGS_GIF_SLIDER_ROW_GAP,
        mouse,
        "Downsample",
        &ui_runtime.gif_downsample_factor,
        1,
        4,
        font,
    )

    draw_settings_integer_slider(
        panel,
        gif_section_y + SETTINGS_GIF_SLIDER_ROW_GAP * 2,
        mouse,
        "Frame Step",
        &ui_runtime.gif_frame_step,
        1,
        4,
        font,
    )

    draw_settings_save_gif_button(
        panel,
        gif_section_y + SETTINGS_GIF_BUTTON_TOP_OFFSET,
        mouse,
        ui_runtime,
        font,
    )

    draw_settings_gif_status(
        panel,
        gif_section_y + SETTINGS_GIF_STATUS_TOP_OFFSET,
        ui_runtime,
        font,
    )
}

//   Estimate visible character capacity for one wrapped text row.
chars_per_text_row :: #force_inline proc(width: f32) -> int {
    count := int(width / TEXT_WRAP_ADVANCE)
    if count < 1 {
        return 1
    }
    return count
}

//   Compute the next wrapped line span and next-start index.
next_wrapped_text_span :: proc(
    text: string, start: int, max_chars: int) -> (int, int, int) {
    if start >= len(text) {
        return start, start, start
    }

    line_end := start
    chars_used := 0
    last_space := -1

    for line_end < len(text) && text[line_end] != '\n' {
        if text[line_end] == ' ' || text[line_end] == '\t' {
            last_space = line_end
        }

        chars_used += 1
        if chars_used > max_chars {
            if last_space >= start {
                line_end = last_space
            } else if line_end > start {
                line_end -= 1
            }
            break
        }

        line_end += 1
    }

    if line_end == start && line_end < len(text) && text[line_end] != '\n' {
        line_end += 1
    }

    next_start := line_end
    if next_start < len(text) && text[next_start] == '\n' {
        next_start += 1
    } else {
        for next_start < len(text) && (text[next_start] == ' ' || text[next_start] == '\t') {
            next_start += 1
        }
    }

    return start, line_end, next_start
}

//   Count wrapped line rows needed for given text and width.
count_wrapped_text_rows :: proc(text: string, max_chars: int) -> int {
    if len(text) == 0 {
        return 1
    }

    rows := 0
    start := 0
    for start < len(text) {
        _, _, next_start := next_wrapped_text_span(text, start, max_chars)
        rows += 1
        if next_start <= start {
            break
        }
        start = next_start
    }

    return rows
}

//   Draw wrapped text rows clipped to the visible panel area.
draw_wrapped_text_content :: proc(text: string, panel: rl.Rectangle, scroll_y: f32, font: rl.Font) {
    max_chars := chars_per_text_row(panel.width - TEXT_PADDING * 2)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + TEXT_PADDING), int(panel.y + TEXT_PADDING), UI_TEXT_COLOR, font)
        return
    }

    for start < len(text) {
        line_start, line_end, next_start := next_wrapped_text_span(text, start, max_chars)
        row_y := panel.y + TEXT_PADDING + f32(row) * TEXT_ROW_HEIGHT - scroll_y

        if row_y + TEXT_ROW_HEIGHT >= panel.y && row_y <= panel.y + panel.height {
            ui_text(text[line_start:line_end], int(panel.x + TEXT_PADDING), int(row_y), UI_TEXT_COLOR, font)
        }

        row += 1
        if next_start <= start {
            break
        }
        start = next_start
    }
}

//   Mark one animation selected and clear selection on others.
set_selected_animation :: proc(ji: ^core.Euclid_Julia_Interface, selected_id: int) {
    if selected_id < 0 || selected_id >= ji.next_animation_index {
        return
    }

    for i in 0..<ji.next_animation_index {
        ji.animations[i].is_selected = (i == selected_id)
    }
    ji.selected_animation_index = selected_id
}

//   Count visible rows for all root trees with expansion state.
count_visible_tree_rows_all_roots :: proc(ji: ^core.Euclid_Julia_Interface) -> int {
    count := 0
    for i in 0..<ji.next_animation_index {
        if ji.animations[i].parent_id < 0 {
            count += count_visible_tree_rows_limited(ji, i, ji.next_animation_index)
        }
    }
    return count
}

//   Merge child tree hit results into a single accumulator.
merge_tree_hit :: #force_inline proc(dst: ^Tree_Hit, src: Tree_Hit) {
    if src.SelectedID >= 0 {
        dst.SelectedID = src.SelectedID
    }
    if src.ToggledID >= 0 {
        dst.ToggledID = src.ToggledID
    }
}

//   Clamp scroll offset to [0, max_scroll] range.
clamp_scroll_position :: proc(scroll_y: ^f32, max_scroll: f32) {
    if scroll_y^ < 0 {
        scroll_y^ = 0
    }
    if scroll_y^ > max_scroll {
        scroll_y^ = max_scroll
    }
}

//   Apply mouse-wheel scrolling when cursor is over target panel.
apply_wheel_scroll :: proc(
    mouse: rl.Vector2, panel: rl.Rectangle, row_height: f32,
    scroll_y: ^f32, max_scroll: f32) {

    if !rl.CheckCollisionPointRec(mouse, panel) {
        return
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 {
        scroll_y^ -= wheel * (row_height * WHEEL_SCROLL_MULTIPLIER)
        clamp_scroll_position(scroll_y, max_scroll)
    }
}

//   Build scrollbar track/thumb geometry for current scroll state.
build_vertical_scrollbar :: proc(
    panel: rl.Rectangle,
    content_h: f32,
    scroll_y: f32,
    max_scroll: f32) -> (rl.Rectangle, rl.Rectangle, f32, bool) {
    if max_scroll <= 0 {
        return rl.Rectangle{}, rl.Rectangle{}, 0, false
    }

    track := rl.Rectangle{
        panel.x + panel.width - SCROLLBAR_WIDTH,
        panel.y,
        SCROLLBAR_WIDTH,
        panel.height,
    }

    thumb_h := scrollbar_thumb_height(panel.height, content_h)
    thumb_y := scrollbar_thumb_y(panel.y, panel.height, thumb_h, scroll_y, max_scroll)
    thumb := rl.Rectangle{track.x, thumb_y, SCROLLBAR_WIDTH, thumb_h}
    return track, thumb, thumb_h, true
}

//   Apply selection/expand hits and sync related UI state.
apply_tree_hit :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    hit: Tree_Hit) {
    if hit.ToggledID >= 0 && hit.ToggledID < ji.next_animation_index {
        ji.animations[hit.ToggledID].is_expanded = !ji.animations[hit.ToggledID].is_expanded
    }
    if hit.SelectedID >= 0 {
        set_selected_animation(ji, hit.SelectedID)
        ui_runtime.view_text_scroll_y = 0
        ui_runtime.text_scroll_dragging = false
        ui_runtime.text_scroll_drag_off = 0
        ui_runtime.scratchpad_input_len = 0
        ui_runtime.scratchpad_input_cursor = 0
        ui_runtime.scratchpad_follow_output = false
    }
}

//   Compute scrollbar thumb height from content-to-panel ratio.
scrollbar_thumb_height :: #force_inline proc(panel_height: f32, content_h: f32) -> f32 {
    if panel_height <= 0 || content_h <= 0 {
        return 0
    }

    thumb_h := max(SCROLLBAR_THUMB_MIN_HEIGHT, panel_height * (panel_height / content_h))
    return clamp(thumb_h, 0.0, panel_height)
}

//   Compute scrollbar thumb y-position from scroll offset.
scrollbar_thumb_y :: #force_inline proc(
    panel_y, panel_height, thumb_h, scroll_y, max_scroll: f32) -> f32 {
    if max_scroll <= 0 || panel_height <= thumb_h {
        return panel_y
    }
    return panel_y + (scroll_y / max_scroll) * (panel_height - thumb_h)
}

//   Handle drag lifecycle and update scroll offset from thumb drag.
handle_scrollbar_drag :: proc(
    mouse: rl.Vector2,
    thumb: rl.Rectangle,
    panel_y: f32,
    panel_height: f32,
    thumb_h: f32,
    max_scroll: f32,
    scroll_y: ^f32,
    dragging: ^bool,
    drag_off: ^f32) {
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
        dragging^ = true
        drag_off^ = mouse.y - thumb.y
    }

    if !dragging^ {
        return
    }

    if !rl.IsMouseButtonDown(.LEFT) {
        dragging^ = false
        return
    }

    thumb_range := panel_height - thumb_h
    if thumb_range <= SCROLLBAR_DRAG_EPSILON || max_scroll <= 0 {
        scroll_y^ = 0
        return
    }

    new_thumb_y := mouse.y - drag_off^
    t := (new_thumb_y - panel_y) / thumb_range
    scroll_y^ = clamp(t, 0, 1) * max_scroll
}

//   Traverse and draw root nodes, aggregating click hits.
walk_draw_tree_roots :: proc(
    ji: ^core.Euclid_Julia_Interface,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    font: rl.Font) -> Tree_Hit {
    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    for i in 0..<ji.next_animation_index {
        if ji.animations[i].parent_id >= 0 {
            continue
        }

        root_hit := walk_draw_tree_node_limited(
            ji,
            i,
            0,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            ji.next_animation_index,
            font,
        )
        merge_tree_hit(&hit, root_hit)
    }

    return hit
}

//   Count visible rows recursively with recursion guard limit.
count_visible_tree_rows_limited :: proc(
    ji: ^core.Euclid_Julia_Interface, id: int, remaining: int) -> int {
    if remaining <= 0 {
        return 0
    }

    if id < 0 || id >= ji.next_animation_index {
        return 0
    }

    count := 1
    n := &ji.animations[id]

    if !n.is_expanded || n.first_child_id < 0 {
        return count
    }

    child := n.first_child_id
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }
        count += count_visible_tree_rows_limited(ji, child, remaining - 1)
        child = ji.animations[child].next_sibling
        steps += 1
    }

    return count
}

//   Advance content cursor for skipped offscreen child branches.
accumulate_offscreen_child_rows :: proc(
    ji: ^core.Euclid_Julia_Interface,
    first_child: int,
    content_y: ^f32,
    remaining: int) {
    child := first_child
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }

        child_rows := count_visible_tree_rows_limited(ji, child, remaining - 1)
        content_y^ += f32(child_rows) * TREE_ROW_HEIGHT
        child = ji.animations[child].next_sibling
        steps += 1
    }
}

//   Traverse and draw child node branches with depth tracking.
walk_draw_child_nodes_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    first_child: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
    font: rl.Font) -> Tree_Hit {
    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    child := first_child
    steps := 0
    for child >= 0 && steps < ji.next_animation_index {
        if child >= ji.next_animation_index {
            break
        }

        child_hit := walk_draw_tree_node_limited(
            ji,
            child,
            depth + 1,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            remaining - 1,
            font,
        )
        merge_tree_hit(&hit, child_hit)
        child = ji.animations[child].next_sibling
        steps += 1
    }

    return hit
}

//   Return first child id only when node is expanded.
expanded_first_child_id :: #force_inline proc(is_expanded: bool, first_child_id: int) -> int {
    if !is_expanded || first_child_id < 0 {
        return -1
    }
    return first_child_id
}

//   Render one tree row and capture selection/toggle interactions.
draw_tree_node_row :: proc(
    ji: ^core.Euclid_Julia_Interface,
    id: int,
    depth: int,
    row_rect: rl.Rectangle,
    allow_clicks: bool,
    mouse: rl.Vector2,
    hit: ^Tree_Hit,
    font: rl.Font) {
    node := &ji.animations[id]

    indent_x := row_rect.x + f32(depth) * TREE_INDENT
    icon_rect := rl.Rectangle{
        indent_x + TREE_ROW_ICON_OFFSET_X,
        row_rect.y + TREE_ROW_ICON_OFFSET_Y,
        TREE_ROW_ICON_SIZE,
        TREE_ROW_ICON_SIZE,
    }
    label_x := int(indent_x + TREE_ROW_LABEL_OFFSET_X)

    click := allow_clicks && rl.IsMouseButtonPressed(.LEFT)
    hovered := rl.CheckCollisionPointRec(mouse, row_rect)

    if node.is_selected {
        rl.DrawRectangleRec(row_rect, UI_BORDER_COLOR)
    }

    if node.first_child_id >= 0 {
        draw_tree_disclosure_icon(icon_rect, node.is_expanded, UI_TEXT_COLOR)

        if click && rl.CheckCollisionPointRec(mouse, icon_rect) {
            hit.ToggledID = id
        }
    }

    ui_text(node.name, label_x, int(row_rect.y + TREE_ROW_LABEL_OFFSET_Y), UI_TEXT_COLOR, font)

    if click && hovered {
        hit.SelectedID = id
    }
}

//   Traverse one tree node branch with clipping-aware row handling.
walk_draw_tree_node_limited :: proc(
    ji: ^core.Euclid_Julia_Interface,
    id: int,
    depth: int,
    panel: rl.Rectangle,
    content_y: ^f32,
    scroll_y: f32,
    allow_clicks: bool,
    mouse: rl.Vector2,
    remaining: int,
    font: rl.Font) -> Tree_Hit {
    hit := Tree_Hit{SelectedID = -1, ToggledID = -1}

    if remaining <= 0 {
        return hit
    }

    if id < 0 || id >= ji.next_animation_index {
        return hit
    }

    node := &ji.animations[id]
    child_first := expanded_first_child_id(node.is_expanded, node.first_child_id)

    row_y_world := content_y^
    content_y^ += TREE_ROW_HEIGHT

    row_y_screen := panel.y + (row_y_world - scroll_y)
    row_rect := rl.Rectangle{panel.x, row_y_screen, panel.width, TREE_ROW_HEIGHT}

    if row_rect.y > panel.y + panel.height {
        if child_first >= 0 {
            accumulate_offscreen_child_rows(ji, child_first, content_y, remaining)
        }
        return hit
    }

    if row_rect.y + row_rect.height < panel.y {
        if child_first >= 0 {
            child_hit := walk_draw_child_nodes_limited(
                ji,
                child_first,
                depth,
                panel,
                content_y,
                scroll_y,
                allow_clicks,
                mouse,
                remaining,
                font,
            )
            merge_tree_hit(&hit, child_hit)
        }
        return hit
    }

    draw_tree_node_row(ji, id, depth, row_rect, allow_clicks, mouse, &hit, font)

    if child_first >= 0 {
        child_hit := walk_draw_child_nodes_limited(
            ji,
            child_first,
            depth,
            panel,
            content_y,
            scroll_y,
            allow_clicks,
            mouse,
            remaining,
            font,
        )
        merge_tree_hit(&hit, child_hit)
    }

    return hit
}

//   Build toolbar and list panel rectangles inside tree container.
build_tree_view_panels :: proc(panel: rl.Rectangle) -> (rl.Rectangle, rl.Rectangle) {
    inner_x := panel.x + 6
    inner_y := panel.y + 6
    inner_w := panel.width - 12
    inner_h := panel.height - 12

    toolbar_panel := rl.Rectangle{
        inner_x,
        inner_y,
        inner_w,
        TREE_TOOLBAR_HEIGHT,
    }

    list_panel := rl.Rectangle{
        inner_x,
        inner_y + TREE_TOOLBAR_HEIGHT + TREE_TOOLBAR_GAP,
        inner_w,
        inner_h - TREE_TOOLBAR_HEIGHT - TREE_TOOLBAR_GAP,
    }

    if list_panel.width < 0 {
        list_panel.width = 0
    }

    if list_panel.height < 0 {
        list_panel.height = 0
    }

    return toolbar_panel, list_panel
}

//   Render tree list body, scrollbars, and visible node rows.
draw_tree_list_panel :: proc(
    ji: ^core.Euclid_Julia_Interface,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    list_panel: rl.Rectangle,
    mouse: rl.Vector2,
    scroll_y: ^f32,
    font: rl.Font) {
    rl.DrawRectangleRec(list_panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(list_panel, 1, UI_BORDER_COLOR)

    total_rows := count_visible_tree_rows_all_roots(ji)
    if total_rows <= 0 {
        return
    }

    content_h := f32(total_rows) * TREE_ROW_HEIGHT
    max_scroll := max(0.0, content_h - list_panel.height)

    apply_wheel_scroll(mouse, list_panel, TREE_ROW_HEIGHT, scroll_y, max_scroll)

    track := rl.Rectangle{}
    thumb_h: f32 = 0
    thumb := rl.Rectangle{}
    has_scrollbar := false

    allow_tree_clicks := true
    track, thumb, thumb_h, has_scrollbar =
        build_vertical_scrollbar(list_panel, content_h, scroll_y^, max_scroll)
    if has_scrollbar {
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
            allow_tree_clicks = false
        }
    }

    rl.BeginScissorMode(i32(list_panel.x), i32(list_panel.y),
        i32(list_panel.width), i32(list_panel.height))
    {
        y_cursor: f32 = 0
        hit := walk_draw_tree_roots(ji, list_panel, &y_cursor, scroll_y^, allow_tree_clicks, mouse, font)
        apply_tree_hit(ji, ui_runtime, hit)
    }
    rl.EndScissorMode()

    if has_scrollbar {
        handle_scrollbar_drag(
            mouse,
            thumb,
            list_panel.y,
            list_panel.height,
            thumb_h,
            max_scroll,
            scroll_y,
            &ui_runtime.tree_scroll_dragging,
            &ui_runtime.tree_scroll_drag_off,
        )

        rl.DrawRectangleRec(track, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb, UI_BORDER_COLOR)
    }
}
