package ui

import "core:strings"

import rl "vendor:raylib"

INPUT_BOX_MAX_TEXT_EVENTS :: 64

Input_Box_Events :: struct {
    text_event_count: int,
    text_events: [INPUT_BOX_MAX_TEXT_EVENTS]u8,
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    home: bool,
    end: bool,
    backspace: bool,
    delete: bool,
}

Input_Box_Params :: struct {
    id: int,
    rect: rl.Rectangle,
    text_buffer: []u8,
    text_len_in: int,
    caret_col_in: int,
    viewport_col_start_in: int,
    enabled: bool,
    has_focus: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
    font: rl.Font,
    font_color: rl.Color,
    font_size: f32,
    char_advance: f32,
    prompt_prefix: string,
    caret_blink_half_period_seconds: f64,
}

Input_Box_Result :: struct {
    drawn_rect: rl.Rectangle,
    text_len_out: int,
    caret_col_out: int,
    viewport_col_start_out: int,
    changed: bool,
    moved_up: bool,
    moved_down: bool,
    history_previous: bool,
    history_next: bool,
    submit_pressed: bool,
    hovered: bool,
    pressed: bool,
}

Input_Box_Draw_Params :: struct {
    rect: rl.Rectangle,
    text_buffer: []u8,
    text_len: int,
    caret_col: int,
    viewport_col_start: int,
    enabled: bool,
    has_focus: bool,
    mouse: Mouse_Input_State,
    font: rl.Font,
    font_color: rl.Color,
    font_size: f32,
    char_advance: f32,
    prompt_prefix: string,
    caret_blink_half_period_seconds: f64,
}

//   Resolve whether caret should be visible for the current blink phase.
input_box_should_draw_caret :: #force_inline proc(
    timestamp_seconds, half_period_seconds: f64) -> bool {

    if half_period_seconds <= 0 {
        return true
    }

    phase := int(timestamp_seconds / half_period_seconds)
    return phase % 2 == 0
}

//   Clamp input rect so width and height are never negative.
input_box_clamp_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
}

//   Convert screen-space mouse coordinates into input-local coordinates.
input_box_local_mouse :: #force_inline proc(
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.position.x - scroll_offset.x,
        mouse_input.position.y - scroll_offset.y,
    }
}

//   Clamp requested text length to available buffer capacity.
input_box_clamp_text_len :: #force_inline proc(text_len, capacity: int) -> int {
    if capacity <= 0 {
        return 0
    }
    return clamp(text_len, 0, capacity)
}

//   Clamp caret column into the inclusive range [0, text_len].
input_box_clamp_cursor :: #force_inline proc(cursor, text_len: int) -> int {
    return clamp(cursor, 0, max(0, text_len))
}

//   Compute visible column count for current draw width and character advance.
input_box_visible_cols :: #force_inline proc(width, advance: f32) -> int {
    safe_advance := max(1.0, advance)
    cols := int(width / safe_advance)
    if cols < 1 {
        return 1
    }
    return cols
}

//   Insert one byte at caret position when buffer capacity allows.
//   Side effects: mutates text_len and caret.
input_box_insert_byte :: proc(buffer: []u8, text_len, caret: ^int, b: u8) {
    if buffer == nil || caret^ < 0 {
        return
    }

    if text_len^ >= len(buffer) {
        return
    }

    for i := text_len^; i > caret^; i -= 1 {
        buffer[i] = buffer[i - 1]
    }
    buffer[caret^] = b
    text_len^ += 1
    caret^ += 1
}

//   Insert one byte at caller-provided caret after clamping text and caret bounds.
//   Side effects: mutates text_len and caret.
input_box_insert_at_caret :: proc(buffer: []u8, text_len, caret: ^int, b: u8) {
    if buffer == nil || text_len == nil || caret == nil {
        return
    }

    clamped_len := input_box_clamp_text_len(text_len^, len(buffer))
    text_len^ = clamped_len
    caret^ = input_box_clamp_cursor(caret^, clamped_len)
    input_box_insert_byte(buffer, text_len, caret, b)
}

//   Remove one byte to the left of caret.
//   Side effects: mutates text_len and caret.
input_box_backspace_byte :: proc(buffer: []u8, text_len, caret: ^int) {
    if buffer == nil || caret^ <= 0 || text_len^ <= 0 {
        return
    }

    remove_at := caret^ - 1
    for i := remove_at; i < text_len^ - 1; i += 1 {
        buffer[i] = buffer[i + 1]
    }

    text_len^ -= 1
    caret^ -= 1
}

//   Remove one byte at caret position.
//   Side effects: mutates text_len.
input_box_delete_byte :: proc(buffer: []u8, text_len, caret: ^int) {
    if buffer == nil || caret^ < 0 || caret^ >= text_len^ {
        return
    }

    for i := caret^; i < text_len^ - 1; i += 1 {
        buffer[i] = buffer[i + 1]
    }
    text_len^ -= 1
}

//   Replace text buffer contents and move caret to end of copied text.
//   Side effects: mutates text_len and caret.
input_box_replace_text :: proc(buffer: []u8, text_len, caret: ^int, text: string) {
    if buffer == nil || text_len == nil || caret == nil {
        return
    }

    text_len^ = 0
    caret^ = 0
    if len(text) == 0 {
        return
    }

    copy_len := min(len(text), len(buffer))
    for i in 0..<copy_len {
        buffer[i] = text[i]
    }
    text_len^ = copy_len
    caret^ = copy_len
}

//   Capture one frame of keyboard text/edit events for Input_Box processing.
capture_input_box_events_ascii :: proc() -> Input_Box_Events {
    input_events := Input_Box_Events{}
    for {
        codepoint := rl.GetCharPressed()
        if codepoint == 0 {
            break
        }

        if codepoint >= 32 && codepoint < 127 &&
            input_events.text_event_count < INPUT_BOX_MAX_TEXT_EVENTS {

            index := input_events.text_event_count
            input_events.text_events[index] = u8(codepoint)
            input_events.text_event_count += 1
        }
    }

    input_events.left = rl.IsKeyPressed(.LEFT)
    input_events.right = rl.IsKeyPressed(.RIGHT)
    input_events.up = rl.IsKeyPressed(.UP)
    input_events.down = rl.IsKeyPressed(.DOWN)
    input_events.home = rl.IsKeyPressed(.HOME)
    input_events.end = rl.IsKeyPressed(.END)
    input_events.backspace = rl.IsKeyPressed(.BACKSPACE)
    input_events.delete = rl.IsKeyPressed(.DELETE)
    return input_events
}

//   Shift viewport start so caret remains visible in the current window.
//   Side effects: mutates viewport.
input_box_update_viewport_for_caret :: #force_inline proc(caret, visible_cols: int, viewport: ^int) {
    if caret < viewport^ {
        viewport^ = caret
    }

    max_visible_col := viewport^ + visible_cols
    if caret > max_visible_col {
        viewport^ = caret - visible_cols
    }

    if viewport^ < 0 {
        viewport^ = 0
    }
}

//   Apply one frame of keyboard events to text and caret state.
//   Side effects: mutates text_len, caret, and viewport.
input_box_apply_keyboard_events :: proc(
    params: Input_Box_Params,
    events: Input_Box_Events,
    visible_cols: int,
    text_len, caret, viewport: ^int,
    moved_up, moved_down: ^bool) {

    if !params.enabled || !params.has_focus {
        return
    }

    moved_up^ = false
    moved_down^ = false

    if events.up {
        moved_up^ = input_box_move_caret_up(params.text_buffer, text_len^, caret)
    }
    if events.down {
        moved_down^ = input_box_move_caret_down(params.text_buffer, text_len^, caret)
    }

    if events.left {
        caret^ -= 1
    }
    if events.right {
        caret^ += 1
    }
    if events.home {
        caret^ = 0
    }
    if events.end {
        caret^ = text_len^
    }

    caret^ = input_box_clamp_cursor(caret^, text_len^)

    if events.backspace {
        input_box_backspace_byte(params.text_buffer, text_len, caret)
    }
    if events.delete {
        input_box_delete_byte(params.text_buffer, text_len, caret)
    }

    caret^ = input_box_clamp_cursor(caret^, text_len^)
    for i in 0..<events.text_event_count {
        b := events.text_events[i]
        if b >= 32 {
            input_box_insert_byte(params.text_buffer, text_len, caret, b)
        }
    }

    caret^ = input_box_clamp_cursor(caret^, text_len^)
    input_box_update_viewport_for_caret(caret^, visible_cols, viewport)
}

//   Map local mouse x-position to nearest caret column in visible text space.
input_box_clicked_col :: #force_inline proc(
    rect: rl.Rectangle,
    local_mouse: rl.Vector2,
    char_advance: f32,
    viewport_col_start: int) -> int {

    safe_advance := max(1.0, char_advance)
    local_x := max(0.0, local_mouse.x - rect.x)
    return viewport_col_start + int(local_x / safe_advance + 0.5)
}

//   Return byte bounds [line_start, line_end) for the line containing caret.
input_box_current_line_bounds :: #force_inline proc(
    buffer: []u8,
    text_len, caret: int) -> (int, int) {

    if buffer == nil || text_len <= 0 {
        return 0, 0
    }

    clamped_caret := input_box_clamp_cursor(caret, text_len)
    line_start := clamped_caret
    if line_start > 0 && line_start == text_len {
        line_start -= 1
    }

    for line_start > 0 && buffer[line_start - 1] != '\n' {
        line_start -= 1
    }

    line_end := clamped_caret
    for line_end < text_len && buffer[line_end] != '\n' {
        line_end += 1
    }

    return line_start, line_end
}

//   Move caret to previous line while preserving visual column when possible.
//   Returns true only when caret moved inside current multiline text.
input_box_move_caret_up :: proc(buffer: []u8, text_len: int, caret: ^int) -> bool {
    if buffer == nil || text_len <= 0 {
        return false
    }

    clamped_caret := input_box_clamp_cursor(caret^, text_len)
    line_start, _ := input_box_current_line_bounds(buffer, text_len, clamped_caret)
    if line_start <= 0 {
        return false
    }

    col := max(0, clamped_caret - line_start)
    prev_line_end := line_start - 1
    prev_line_start := prev_line_end
    for prev_line_start > 0 && buffer[prev_line_start - 1] != '\n' {
        prev_line_start -= 1
    }

    prev_line_len := max(0, prev_line_end - prev_line_start)
    caret^ = prev_line_start + min(col, prev_line_len)
    return true
}

//   Move caret to next line while preserving visual column when possible.
//   Returns true only when caret moved inside current multiline text.
input_box_move_caret_down :: proc(buffer: []u8, text_len: int, caret: ^int) -> bool {
    if buffer == nil || text_len <= 0 {
        return false
    }

    clamped_caret := input_box_clamp_cursor(caret^, text_len)
    line_start, line_end := input_box_current_line_bounds(buffer, text_len, clamped_caret)
    if line_end >= text_len {
        return false
    }

    col := max(0, clamped_caret - line_start)
    next_line_start := line_end + 1
    next_line_end := next_line_start
    for next_line_end < text_len && buffer[next_line_end] != '\n' {
        next_line_end += 1
    }

    next_line_len := max(0, next_line_end - next_line_start)
    caret^ = next_line_start + min(col, next_line_len)
    return true
}

//   Resolve one input frame (mouse/key handling + state updates) without drawing.
//   Parent may inspect result and apply policy (history/submit) before drawing.
handle_input_box :: proc(
    params: Input_Box_Params,
    press_active: ^bool,
    press_id: ^int) -> Input_Box_Result {

    events := capture_input_box_events_ascii()
    history_previous := events.up
    history_next := events.down
    submit_pressed := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)

    drawn_rect := input_box_clamp_rect(params.rect)
    local_mouse := input_box_local_mouse(params.mouse, params.scroll_offset)

    hovered_item := rl.CheckCollisionPointRec(local_mouse, drawn_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    owns_press := press_active^ && press_id^ == params.id
    can_interact := params.enabled && params.interaction_enabled
    if can_interact && !owns_press && params.mouse.left_pressed && hovered {
        press_active^ = true
        press_id^ = params.id
        owns_press = true
    }

    if owns_press && params.mouse.left_released {
        press_active^ = false
        press_id^ = -1
        owns_press = false
    }

    text_len := input_box_clamp_text_len(params.text_len_in, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col_in, text_len)
    viewport := max(0, params.viewport_col_start_in)

    prefix_width: f32 = 0
    if len(params.prompt_prefix) > 0 {
        prefix_cstr := strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
        prefix_width = max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
    }

    content_x := drawn_rect.x + prefix_width
    content_width := max(0.0, drawn_rect.width - prefix_width)
    visible_cols := input_box_visible_cols(content_width, params.char_advance)

    text_rect := rl.Rectangle{content_x, drawn_rect.y, content_width, drawn_rect.height}
    line_start, line_end := input_box_current_line_bounds(params.text_buffer, text_len, caret)

    if params.enabled && params.has_focus && params.mouse.left_pressed && hovered {
        clicked_col := input_box_clicked_col(text_rect, local_mouse, params.char_advance, viewport)
        clicked_caret := line_start + clicked_col
        caret = clamp(clicked_caret, line_start, line_end)
    }

    text_len_before := text_len
    moved_up := false
    moved_down := false
    input_box_apply_keyboard_events(
        params,
        events,
        visible_cols,
        &text_len,
        &caret,
        &viewport,
        &moved_up,
        &moved_down)
    line_start, line_end = input_box_current_line_bounds(params.text_buffer, text_len, caret)

    line_len := max(0, line_end - line_start)
    caret_col_in_line := max(0, caret - line_start)

    viewport = min(viewport, line_len)
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &viewport)

    visible_start := clamp(viewport, 0, line_len)
    visible_end := clamp(visible_start + visible_cols, visible_start, line_len)
    visible_text := ""
    if visible_end > visible_start {
        text_start := line_start + visible_start
        text_end := line_start + visible_end
        visible_text = string(params.text_buffer[text_start:text_end])
    }

    return Input_Box_Result{
        drawn_rect = drawn_rect,
        text_len_out = text_len,
        caret_col_out = caret,
        viewport_col_start_out = viewport,
        changed = text_len != text_len_before,
        moved_up = moved_up,
        moved_down = moved_down,
        history_previous = history_previous,
        history_next = history_next,
        submit_pressed = submit_pressed,
        hovered = hovered,
        pressed = owns_press && params.mouse.left_down,
    }
}

//   Draw input text and caret from caller-provided post-policy state.
draw_input_box :: proc(params: Input_Box_Draw_Params) {
    drawn_rect := input_box_clamp_rect(params.rect)

    text_len := input_box_clamp_text_len(params.text_len, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col, text_len)
    line_start, line_end := input_box_current_line_bounds(params.text_buffer, text_len, caret)

    prefix_width: f32 = 0
    if len(params.prompt_prefix) > 0 {
        prefix_cstr := strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
        prefix_width = max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
    }

    content_x := drawn_rect.x + prefix_width
    content_width := max(0.0, drawn_rect.width - prefix_width)
    visible_cols := input_box_visible_cols(content_width, params.char_advance)

    line_len := max(0, line_end - line_start)
    caret_col_in_line := max(0, caret - line_start)
    viewport := max(0, min(params.viewport_col_start, line_len))
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &viewport)

    visible_start := clamp(viewport, 0, line_len)
    visible_end := clamp(visible_start + visible_cols, visible_start, line_len)
    visible_text := ""
    if visible_end > visible_start {
        text_start := line_start + visible_start
        text_end := line_start + visible_end
        visible_text = string(params.text_buffer[text_start:text_end])
    }

    display_color := params.font_color
    if !params.enabled {
        display_color = rl.Color{110, 110, 110, 255}
    }

    if len(visible_text) > 0 {
        ui_text(visible_text,
            int(content_x),
            int(drawn_rect.y),
            display_color,
            params.font,
            params.font_size)
    }

    if len(params.prompt_prefix) > 0 {
        ui_text(params.prompt_prefix,
            int(drawn_rect.x),
            int(drawn_rect.y),
            display_color,
            params.font,
            params.font_size)
    }

    if params.has_focus && params.enabled &&
        input_box_should_draw_caret(
            params.mouse.timestamp_seconds,
            params.caret_blink_half_period_seconds) {

        caret_col_local := clamp(caret_col_in_line - visible_start, 0, visible_cols)
        caret_x := content_x + f32(caret_col_local) * max(1.0, params.char_advance) - 4.0
        ui_text("|", int(caret_x), int(drawn_rect.y), display_color, params.font, params.font_size)
    }
}
