package ui

import "../../core"
import "core:strings"

import rl "vendor:raylib"

INPUT_BOX_MAX_TEXT_EVENTS :: 64

Input_Box_Events :: struct {
    text_event_count: int,
    text_events: [INPUT_BOX_MAX_TEXT_EVENTS]rune,
    tab: bool,
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
    tab_pressed: bool,
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

//   Return whether the byte is a UTF-8 continuation byte.
input_box_is_utf8_trailing_byte :: #force_inline proc(b: u8) -> bool {
    return (b & 0xC0) == 0x80
}

//   Step backward to the previous UTF-8 codepoint boundary.
input_box_prev_codepoint_start :: #force_inline proc(
    buffer: []u8,
    lower_bound, cursor: int) -> int {

    if buffer == nil || cursor <= lower_bound {
        return lower_bound
    }

    start := cursor - 1
    for start > lower_bound && input_box_is_utf8_trailing_byte(buffer[start]) {
        start -= 1
    }
    return start
}

//   Step forward to the next UTF-8 codepoint boundary.
input_box_next_codepoint_start :: #force_inline proc(
    buffer: []u8,
    upper_bound, cursor: int) -> int {

    if buffer == nil || cursor >= upper_bound {
        return upper_bound
    }

    next := cursor + 1
    for next < upper_bound && input_box_is_utf8_trailing_byte(buffer[next]) {
        next += 1
    }
    return next
}

//   Count UTF-8 codepoints in the byte range [start, end).
input_box_count_codepoints :: #force_inline proc(
    buffer: []u8,
    start, end: int) -> int {

    if buffer == nil || end <= start {
        return 0
    }

    count := 0
    for i := max(0, start); i < end; i += 1 {
        if !input_box_is_utf8_trailing_byte(buffer[i]) {
            count += 1
        }
    }
    return count
}

//   Convert a line-local codepoint column into a byte offset within that line.
input_box_byte_offset_for_codepoint_col :: #force_inline proc(
    buffer: []u8,
    line_start, line_end, codepoint_col: int) -> int {

    if buffer == nil || line_end <= line_start {
        return line_start
    }

    clamped_col := max(0, codepoint_col)
    offset := line_start
    advanced := 0
    for offset < line_end && advanced < clamped_col {
        offset = input_box_next_codepoint_start(buffer, line_end, offset)
        advanced += 1
    }
    return offset
}

//   Encode one rune into UTF-8 bytes and return the encoded length.
input_box_encode_rune_utf8 :: #force_inline proc(codepoint: rune, out: ^[4]u8) -> int {
    cp := u32(codepoint)
    if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
        return 0
    }

    if cp <= 0x7F {
        out[0] = u8(cp)
        return 1
    }
    if cp <= 0x7FF {
        out[0] = u8(0xC0 | (cp >> 6))
        out[1] = u8(0x80 | (cp & 0x3F))
        return 2
    }
    if cp <= 0xFFFF {
        out[0] = u8(0xE0 | (cp >> 12))
        out[1] = u8(0x80 | ((cp >> 6) & 0x3F))
        out[2] = u8(0x80 | (cp & 0x3F))
        return 3
    }

    out[0] = u8(0xF0 | (cp >> 18))
    out[1] = u8(0x80 | ((cp >> 12) & 0x3F))
    out[2] = u8(0x80 | ((cp >> 6) & 0x3F))
    out[3] = u8(0x80 | (cp & 0x3F))
    return 4
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

//   Return whether this input box currently owns the shared press state.
input_box_owns_press :: #force_inline proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Input_Box &&
        press_owner^.id == id
}

//   Capture shared press ownership for the input box on initial click.
input_box_try_capture_press :: proc(
    params: Input_Box_Params,
    press_owner: ^core.Ui_Press_Owner_State,
    hovered: bool,
    can_interact: bool,
    owns_press: ^bool) {

    if !can_interact || press_owner^.active || !params.mouse.left_pressed || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Input_Box
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership for the input box when the click ends.
input_box_release_press :: proc(
    params: Input_Box_Params,
    press_owner: ^core.Ui_Press_Owner_State,
    owns_press: ^bool) {

    if !owns_press^ || !params.mouse.left_released {
        return
    }

    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
}

//   Measure prompt width and derive the editable content rect and visible columns.
input_box_content_layout :: proc(
    params: Input_Box_Params,
    drawn_rect: rl.Rectangle) -> (rl.Rectangle, int) {

    prefix_width: f32 = 0
    if len(params.prompt_prefix) > 0 {
        prefix_cstr := strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
        prefix_width = max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
    }

    content_x := drawn_rect.x + prefix_width
    content_width := max(0.0, drawn_rect.width - prefix_width)
    text_rect := rl.Rectangle{content_x, drawn_rect.y, content_width, drawn_rect.height}
    return text_rect, input_box_visible_cols(content_width, params.char_advance)
}

//   Move the caret to the clicked codepoint position on the current line.
input_box_apply_mouse_caret_click :: proc(
    params: Input_Box_Params,
    hovered: bool,
    local_mouse: rl.Vector2,
    text_rect: rl.Rectangle,
    viewport: int,
    line_start, line_end: int,
    caret: ^int) {

    if !params.enabled || !params.has_focus || !params.mouse.left_pressed || !hovered {
        return
    }

    clicked_col := input_box_clicked_col(text_rect, local_mouse, params.char_advance, viewport)
    clicked_caret := input_box_byte_offset_for_codepoint_col(
        params.text_buffer,
        line_start,
        line_end,
        clicked_col)
    caret^ = clamp(clicked_caret, line_start, line_end)
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

//   Insert one UTF-8 codepoint at caret position when buffer capacity allows.
//   Side effects: mutates text_len and caret.
input_box_insert_rune :: proc(buffer: []u8, text_len, caret: ^int, codepoint: rune) {
    if buffer == nil || text_len == nil || caret == nil || caret^ < 0 {
        return
    }

    encoded: [4]u8
    encoded_len := input_box_encode_rune_utf8(codepoint, &encoded)
    if encoded_len <= 0 || text_len^ + encoded_len > len(buffer) {
        return
    }

    for i := text_len^; i > caret^; i -= 1 {
        buffer[i + encoded_len - 1] = buffer[i - 1]
    }
    for i in 0..<encoded_len {
        buffer[caret^ + i] = encoded[i]
    }

    text_len^ += encoded_len
    caret^ += encoded_len
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

//   Remove one UTF-8 codepoint to the left of caret.
//   Side effects: mutates text_len and caret.
input_box_backspace_codepoint :: proc(buffer: []u8, text_len, caret: ^int) {
    if buffer == nil || caret^ <= 0 || text_len^ <= 0 {
        return
    }

    remove_at := input_box_prev_codepoint_start(buffer, 0, caret^)
    remove_len := caret^ - remove_at
    for i := remove_at; i < text_len^ - remove_len; i += 1 {
        buffer[i] = buffer[i + remove_len]
    }

    text_len^ -= remove_len
    caret^ = remove_at
}

//   Remove one UTF-8 codepoint at caret position.
//   Side effects: mutates text_len.
input_box_delete_codepoint :: proc(buffer: []u8, text_len, caret: ^int) {
    if buffer == nil || caret^ < 0 || caret^ >= text_len^ {
        return
    }

    remove_end := input_box_next_codepoint_start(buffer, text_len^, caret^)
    remove_len := remove_end - caret^
    for i := caret^; i < text_len^ - remove_len; i += 1 {
        buffer[i] = buffer[i + remove_len]
    }
    text_len^ -= remove_len
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

//   Replace the byte range [start, end) with replacement text and move caret to replacement end.
//   Side effects: mutates text_len and caret.
input_box_replace_byte_range :: proc(
    buffer: []u8,
    text_len, caret: ^int,
    start, end: int,
    replacement: string) -> bool {

    if buffer == nil || text_len == nil || caret == nil {
        return false
    }

    clamped_len := input_box_clamp_text_len(text_len^, len(buffer))
    replace_start := clamp(start, 0, clamped_len)
    replace_end := clamp(end, replace_start, clamped_len)
    replaced_len := replace_end - replace_start
    replacement_len := len(replacement)
    next_text_len := clamped_len - replaced_len + replacement_len
    if next_text_len > len(buffer) {
        return false
    }

    tail_start := replace_end
    tail_len := clamped_len - tail_start
    if replacement_len > replaced_len {
        shift := replacement_len - replaced_len
        for i := tail_len; i > 0; i -= 1 {
            buffer[tail_start + shift + i - 1] = buffer[tail_start + i - 1]
        }
    } else if replacement_len < replaced_len {
        for i in 0..<tail_len {
            buffer[replace_start + replacement_len + i] = buffer[tail_start + i]
        }
    }

    for i in 0..<replacement_len {
        buffer[replace_start + i] = replacement[i]
    }

    text_len^ = next_text_len
    caret^ = replace_start + replacement_len
    return true
}

//   Capture one frame of keyboard text/edit events for Input_Box processing.
capture_input_box_events :: proc() -> Input_Box_Events {
    input_events := Input_Box_Events{}
    for {
        codepoint := rl.GetCharPressed()
        if codepoint == 0 {
            break
        }

        if codepoint >= 32 &&
            input_events.text_event_count < INPUT_BOX_MAX_TEXT_EVENTS {

            index := input_events.text_event_count
            input_events.text_events[index] = rune(codepoint)
            input_events.text_event_count += 1
        }
    }

    input_events.tab = rl.IsKeyPressed(.TAB)
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
        caret^ = input_box_prev_codepoint_start(params.text_buffer, 0, caret^)
    }
    if events.right {
        caret^ = input_box_next_codepoint_start(params.text_buffer, text_len^, caret^)
    }
    if events.home {
        caret^ = 0
    }
    if events.end {
        caret^ = text_len^
    }

    caret^ = input_box_clamp_cursor(caret^, text_len^)

    if events.backspace {
        input_box_backspace_codepoint(params.text_buffer, text_len, caret)
    }
    if events.delete {
        input_box_delete_codepoint(params.text_buffer, text_len, caret)
    }

    caret^ = input_box_clamp_cursor(caret^, text_len^)
    for i in 0..<events.text_event_count {
        codepoint := events.text_events[i]
        if codepoint >= rune(32) {
            input_box_insert_rune(params.text_buffer, text_len, caret, codepoint)
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

    col := input_box_count_codepoints(buffer, line_start, clamped_caret)
    prev_line_end := line_start - 1
    prev_line_start := prev_line_end
    for prev_line_start > 0 && buffer[prev_line_start - 1] != '\n' {
        prev_line_start -= 1
    }

    prev_line_len := input_box_count_codepoints(buffer, prev_line_start, prev_line_end)
    target_col := min(col, prev_line_len)
    caret^ = input_box_byte_offset_for_codepoint_col(
        buffer,
        prev_line_start,
        prev_line_end,
        target_col)
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

    col := input_box_count_codepoints(buffer, line_start, clamped_caret)
    next_line_start := line_end + 1
    next_line_end := next_line_start
    for next_line_end < text_len && buffer[next_line_end] != '\n' {
        next_line_end += 1
    }

    next_line_len := input_box_count_codepoints(buffer, next_line_start, next_line_end)
    target_col := min(col, next_line_len)
    caret^ = input_box_byte_offset_for_codepoint_col(
        buffer,
        next_line_start,
        next_line_end,
        target_col)
    return true
}

//   Resolve one input frame (mouse/key handling + state updates) without drawing.
//   Parent may inspect result and apply policy (history/submit) before drawing.
handle_input_box :: proc(
    params: Input_Box_Params,
    press_owner: ^core.Ui_Press_Owner_State) -> Input_Box_Result {

    events := capture_input_box_events()
    history_previous := events.up
    history_next := events.down
    tab_pressed := events.tab
    submit_pressed := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)

    drawn_rect := clamp_non_negative_rect(params.rect)
    local_mouse := input_box_local_mouse(params.mouse, params.scroll_offset)

    hovered_item := rl.CheckCollisionPointRec(local_mouse, drawn_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    owns_press := input_box_owns_press(press_owner, params.id)
    can_interact := params.enabled && params.interaction_enabled
    input_box_try_capture_press(params, press_owner, hovered, can_interact, &owns_press)
    input_box_release_press(params, press_owner, &owns_press)

    text_len := input_box_clamp_text_len(params.text_len_in, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col_in, text_len)
    viewport := max(0, params.viewport_col_start_in)

    text_rect, visible_cols := input_box_content_layout(params, drawn_rect)
    line_start, line_end := input_box_current_line_bounds(params.text_buffer, text_len, caret)
    input_box_apply_mouse_caret_click(
        params,
        hovered,
        local_mouse,
        text_rect,
        viewport,
        line_start,
        line_end,
        &caret)

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

    line_len := input_box_count_codepoints(params.text_buffer, line_start, line_end)
    caret_col_in_line := input_box_count_codepoints(params.text_buffer, line_start, caret)

    viewport = min(viewport, line_len)
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &viewport)

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
        tab_pressed = tab_pressed,
        submit_pressed = submit_pressed,
        hovered = hovered,
        pressed = owns_press && params.mouse.left_down,
    }
}

//   Draw input text and caret from caller-provided post-policy state.
draw_input_box :: proc(params: Input_Box_Draw_Params) {
    drawn_rect := clamp_non_negative_rect(params.rect)

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

    line_len := input_box_count_codepoints(params.text_buffer, line_start, line_end)
    caret_col_in_line := input_box_count_codepoints(params.text_buffer, line_start, caret)
    viewport := max(0, min(params.viewport_col_start, line_len))
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &viewport)

    visible_start := clamp(viewport, 0, line_len)
    visible_end := clamp(visible_start + visible_cols, visible_start, line_len)
    visible_text := ""
    if visible_end > visible_start {
        text_start := input_box_byte_offset_for_codepoint_col(
            params.text_buffer,
            line_start,
            line_end,
            visible_start)
        text_end := input_box_byte_offset_for_codepoint_col(
            params.text_buffer,
            line_start,
            line_end,
            visible_end)
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
