package ui

import "../../core"
import view_core "../core"
import "../font"
import "core:strings"

import rl "vendor:raylib"

INPUT_BOX_MAX_TEXT_EVENTS :: 64

Input_Box_Events :: struct {
    text_event_count : int,
    text_events : [INPUT_BOX_MAX_TEXT_EVENTS]rune,
    paste_requested : bool,
    paste_text : string,
    tab : bool,
    up : bool,
    down : bool,
    left : bool,
    right : bool,
    home : bool,
    end : bool,
    backspace : bool,
    delete : bool,
}

Input_Box_Params :: struct {
    id : int,
    rect : rl.Rectangle,
    text_buffer : []u8,
    text_len_in : int,
    caret_col_in : int,
    viewport_col_start_in : int,
    enabled : bool,
    has_focus : bool,
    mouse : Mouse_Input_State,
    scroll_offset : rl.Vector2,
    interaction_space_rect : rl.Rectangle,
    interaction_enabled : bool,
    font : rl.Font,
    font_color : rl.Color,
    font_size : f32,
    char_advance : f32,
    prompt_prefix : string,
    caret_blink_half_period_seconds : f64,
    terminal_mode : bool,
    terminal_row_height : f32,
}

Input_Box_Result :: struct {
    drawn_rect : rl.Rectangle,
    text_len_out : int,
    caret_col_out : int,
    viewport_col_start_out : int,
    changed : bool,
    moved_up : bool,
    moved_down : bool,
    history_previous : bool,
    history_next : bool,
    tab_pressed : bool,
    backspace_pressed : bool,
    paste_applied : bool,
    submit_pressed : bool,
    hovered : bool,
    pressed : bool,
}

Input_Box_Draw_Params :: struct {
    rect : rl.Rectangle,
    text_buffer : []u8,
    text_len : int,
    caret_col : int,
    viewport_col_start : int,
    enabled : bool,
    has_focus : bool,
    mouse : Mouse_Input_State,
    font : rl.Font,
    font_color : rl.Color,
    font_size : f32,
    char_advance : f32,
    prompt_prefix : string,
    caret_blink_half_period_seconds : f64,
    terminal_mode : bool,
    terminal_row_height : f32,
    terminal_background_color : rl.Color,
    terminal_prompt_color : rl.Color,
    terminal_prompt_font : rl.Font,
    font_cache : ^core.Font_Cache,
    font_key : core.Font_Key,
}

Terminal_Input_Position :: struct {
    row : int,
    col : int,
}

Input_Box_Cursor_Segments :: struct {
    before : string,
    cursor : string,
    after : string,
}

//   Source span and draw styling for one terminal input row.
Terminal_Input_Row_Draw :: struct {
    text_start, text_end: int,
    position: rl.Vector2,
    color: rl.Color,
}

//   Mutable text/caret state threaded through one frame of keyboard input,
//   grouped with the per-frame outcome flags so the apply step passes one
//   coherent value instead of a long out-parameter list.
Input_Box_Key_State :: struct {
    text_len : ^int,
    caret : ^int,
    viewport : ^int,
    moved_up : ^bool,
    moved_down : ^bool,
    paste_applied : ^bool,
}

//   Mutable caret/text state shared by input-box edit operations.
Input_Box_Edit_State :: struct {
    text_len : ^int,
    caret : ^int,
}

//   Mutable up/down movement flags produced by caret movement.
Input_Box_Movement_Flags :: struct {
    moved_up : ^bool,
    moved_down : ^bool,
}

//   Caret placement inputs for one focused non-terminal input box.
Input_Box_Caret_Placement :: struct {
    caret_col_in_line : int,
    visible_start : int,
    visible_cols : int,
    content_x : f32,
    row_y : f32,
}

//   Keyboard edit outcome for one input box frame.
Input_Box_Edit_Outcome :: struct {
    moved_up : bool,
    moved_down : bool,
    paste_applied : bool,
    changed : bool,
}

//   Interaction flags for one handled input box frame.
Input_Box_Interaction_Flags :: struct {
    owns_press : bool,
    mouse_left_down : bool,
    hovered : bool,
}

//   Mutable text/caret/viewport state threaded through one input frame.
Input_Box_Frame_State :: struct {
    text_len : ^int,
    caret : ^int,
    viewport : ^int,
}

//   Line context for one caret click within the visible text.
Input_Box_Click_Context :: struct {
    visible_cols : int,
    viewport : int,
    line_start : int,
    line_end : int,
}

//   Mouse-click geometry for one caret placement within the visible text.
Input_Box_Click_Geometry :: struct {
    hovered : bool,
    local_mouse : rl.Vector2,
    text_rect : rl.Rectangle,
    viewport : int,
    line_start : int,
    line_end : int,
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

//   Split one row around the complete UTF-8 codepoint under the caret.
input_box_cursor_segments :: proc(
    buffer: []u8, text_start, text_end, caret: int) ->
    (Input_Box_Cursor_Segments, bool) {

    if text_start < 0 || text_end > len(buffer) || text_start > caret ||
        caret >= text_end || input_box_is_utf8_trailing_byte(buffer[caret]) {
        return {}, false
    }
    next := input_box_next_codepoint_start(buffer, text_end, caret)
    return {
        before = string(buffer[text_start:caret]),
        cursor = string(buffer[caret:next]),
        after = string(buffer[next:text_end]),
    }, true
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

//   Return the end byte offset of the logical line beginning at line_start.
terminal_input_line_end :: #force_inline proc(
    buffer: []u8, text_len, line_start: int) -> int {
    line_end := clamp(line_start, 0, text_len)
    for line_end < text_len && buffer[line_end] != '\n' {
        line_end += 1
    }
    return line_end
}

//   Return wrapped row count for one logical line, preserving one row when empty.
terminal_input_line_row_count :: #force_inline proc(
    codepoint_count, columns: int) -> int {
    safe_columns := max(1, columns)
    return max(1, (codepoint_count + safe_columns - 1) / safe_columns)
}

//   Resolve one byte caret into terminal-style wrapped row and column coordinates.
terminal_input_position :: proc(
    buffer: []u8, text_len, caret, columns: int) -> Terminal_Input_Position {

    safe_len := input_box_clamp_text_len(text_len, len(buffer))
    safe_caret := input_box_clamp_cursor(caret, safe_len)
    safe_columns := max(1, columns)
    row := 0
    line_start := 0
    for {
        line_end := terminal_input_line_end(buffer, safe_len, line_start)
        if safe_caret <= line_end {
            col := input_box_count_codepoints(buffer, line_start, safe_caret)
            return Terminal_Input_Position{row + col / safe_columns, col % safe_columns}
        }

        line_cols := input_box_count_codepoints(buffer, line_start, line_end)
        row += terminal_input_line_row_count(line_cols, safe_columns)
        line_start = line_end + 1
    }
}

//   Return terminal-style wrapped rows needed for text and its active caret cell.
terminal_input_row_count :: proc(buffer: []u8, text_len, caret, columns: int) -> int {
    safe_len := input_box_clamp_text_len(text_len, len(buffer))
    safe_columns := max(1, columns)
    rows := 0
    line_start := 0
    for {
        line_end := terminal_input_line_end(buffer, safe_len, line_start)
        line_cols := input_box_count_codepoints(buffer, line_start, line_end)
        rows += terminal_input_line_row_count(line_cols, safe_columns)
        if line_end >= safe_len {
            break
        }
        line_start = line_end + 1
    }

    caret_position := terminal_input_position(buffer, safe_len, caret, safe_columns)
    return max(rows, caret_position.row + 1)
}

//   Resolve a terminal row and column to the nearest UTF-8 byte caret.
terminal_input_byte_offset_at :: proc(
    buffer: []u8, text_len, columns, target_row, target_col: int) -> int {

    safe_len := input_box_clamp_text_len(text_len, len(buffer))
    safe_columns := max(1, columns)
    row := 0
    line_start := 0
    for {
        line_end := terminal_input_line_end(buffer, safe_len, line_start)
        line_cols := input_box_count_codepoints(buffer, line_start, line_end)
        line_rows := terminal_input_line_row_count(line_cols, safe_columns)
        if target_row < row + line_rows || line_end >= safe_len {
            local_row := clamp(target_row - row, 0, line_rows - 1)
            codepoint_col := clamp(local_row * safe_columns + target_col, 0, line_cols)
            return input_box_byte_offset_for_codepoint_col(
                buffer, line_start, line_end, codepoint_col)
        }

        row += line_rows
        line_start = line_end + 1
    }
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

//   Decode one UTF-8 sequence length from text at byte offset.
input_box_utf8_sequence_len :: #force_inline proc(text: string, at: int) -> int {
    if at < 0 || at >= len(text) {
        return 0
    }

    width := input_box_utf8_lead_width(text[at])
    if width == 1 {
        return 1
    }
    if at + width > len(text) {
        return 0
    }

    for offset in 1 ..< width {
        if !input_box_is_utf8_trailing_byte(text[at + offset]) {
            return 0
        }
    }
    return width
}

//   Return expected UTF-8 sequence width from the lead byte (1 when invalid).
input_box_utf8_lead_width :: #force_inline proc(first: u8) -> int {
    width := 1
    width = 2 if (first & 0xE0) == 0xC0 else width
    width = 3 if (first & 0xF0) == 0xE0 else width
    width = 4 if (first & 0xF8) == 0xF0 else width
    return width
}

//   Return byte count from text that fits in max_bytes without splitting UTF-8 codepoints.
input_box_utf8_prefix_fit :: #force_inline proc(text: string, max_bytes: int) -> int {
    if len(text) <= 0 || max_bytes <= 0 {
        return 0
    }

    offset := 0
    for offset < len(text) {
        sequence_len := input_box_utf8_sequence_len(text, offset)
        if sequence_len <= 0 || offset + sequence_len > max_bytes {
            break
        }
        offset += sequence_len
    }

    return offset
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
        prefix_cstr :=
            strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
        prefix_width =
            max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
    }

    content_x := drawn_rect.x + prefix_width
    content_width := max(0.0, drawn_rect.width - prefix_width)
    text_rect := rl.Rectangle{content_x, drawn_rect.y, content_width, drawn_rect.height}
    return text_rect, input_box_visible_cols(content_width, params.char_advance)
}

//   Move the caret to the clicked codepoint position on the current line.
input_box_apply_mouse_caret_click :: proc(
    params: Input_Box_Params,
    click: Input_Box_Click_Geometry,
    caret: ^int) {

    if !params.enabled || !params.has_focus || !params.mouse.left_pressed ||
        !click.hovered {
        return
    }

    clicked_col :=
        input_box_clicked_col(click.text_rect, click.local_mouse, params.char_advance,
            click.viewport)
    clicked_caret := input_box_byte_offset_for_codepoint_col(
        params.text_buffer,
        click.line_start,
        click.line_end,
        clicked_col)
    caret^ = clamp(clicked_caret, click.line_start, click.line_end)
}

//   Move the caret to a clicked terminal cell across wrapped input rows.
input_box_apply_terminal_mouse_caret_click :: proc(
    params: Input_Box_Params,
    click: Input_Box_Click_Geometry,
    columns: int,
    caret: ^int) {

    if !params.enabled || !params.has_focus || !params.mouse.left_pressed ||
        !click.hovered {
        return
    }

    row_height := max(1.0, params.terminal_row_height)
    clicked_row := max(0, int((click.local_mouse.y - click.text_rect.y) / row_height))
    clicked_col :=
         max(0, int((click.local_mouse.x - click.text_rect.x) /
             max(1.0, params.char_advance)))
    caret^ = terminal_input_byte_offset_at(
        params.text_buffer, params.text_len_in, columns, clicked_row, clicked_col)
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

//   Shift the tail bytes to make room for (or remove) the length delta.
input_box_shift_tail :: proc(
    buffer: []u8, tail_start, tail_len, replace_start, shift: int) {

    if shift > 0 {
        for i := tail_len; i > 0; i -= 1 {
            buffer[tail_start + shift + i - 1] = buffer[tail_start + i - 1]
        }
        return
    }
    if shift < 0 {
        for i in 0..<tail_len {
            buffer[replace_start + (tail_start - replace_start) + shift + i] =
                buffer[tail_start + i]
        }
    }
}

//   Replace the byte range [start, end) with replacement text and move caret to replacement end.
//   Side effects: mutates text_len and caret.
input_box_replace_byte_range :: proc(
    buffer: []u8,
    edit: Input_Box_Edit_State,
    start, end: int,
    replacement: string) -> bool {

    text_len := edit.text_len
    caret := edit.caret
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

    input_box_shift_tail(buffer, replace_end, clamped_len - replace_end,
        replace_start, replacement_len - replaced_len)

    for i in 0..<replacement_len {
        buffer[replace_start + i] = replacement[i]
    }

    text_len^ = next_text_len
    caret^ = replace_start + replacement_len
    return true
}

//   Insert text at caret using UTF-8-safe truncation when capacity is limited.
//   Side effects: mutates text_len and caret.
input_box_insert_text_at_caret :: proc(
    buffer: []u8,
    text_len, caret: ^int,
    text: string) -> bool {

    if buffer == nil || text_len == nil || caret == nil || len(text) <= 0 {
        return false
    }

    clamped_len := input_box_clamp_text_len(text_len^, len(buffer))
    clamped_caret := input_box_clamp_cursor(caret^, clamped_len)
    available := len(buffer) - clamped_len
    if available <= 0 {
        text_len^ = clamped_len
        caret^ = clamped_caret
        return false
    }

    insert_len := input_box_utf8_prefix_fit(text, available)
    if insert_len <= 0 {
        text_len^ = clamped_len
        caret^ = clamped_caret
        return false
    }

    for i := clamped_len; i > clamped_caret; i -= 1 {
        buffer[i + insert_len - 1] = buffer[i - 1]
    }
    for i in 0..<insert_len {
        buffer[clamped_caret + i] = text[i]
    }

    text_len^ = clamped_len + insert_len
    caret^ = clamped_caret + insert_len
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

    ctrl_down := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    paste_pressed := rl.IsKeyPressed(.V) && ctrl_down
    if paste_pressed {
        clipboard_text := rl.GetClipboardText()
        if clipboard_text != nil {
            pasted := string(clipboard_text)
            if len(pasted) > 0 {
                input_events.paste_requested = true
                input_events.paste_text = pasted
            }
        }
    }

    return input_events
}

//   Shift viewport start so caret remains visible in the current window.
//   Side effects: mutates viewport.
input_box_update_viewport_for_caret :: #force_inline proc(
    caret, visible_cols: int, viewport: ^int) {
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
//   Apply deletion, text-event insertion, and paste for one input frame.
input_box_apply_edit_events :: proc(
    params: Input_Box_Params,
    events: Input_Box_Events,
    key_state: Input_Box_Key_State) {

    text_len := key_state.text_len
    caret := key_state.caret
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

    if events.paste_requested {
        key_state.paste_applied^ = input_box_insert_text_at_caret(
            params.text_buffer,
            text_len,
            caret,
            events.paste_text)
    }
}

//   Apply caret movement, edits, and paste for one keyboard-input frame.
input_box_apply_keyboard_events :: proc(
    params: Input_Box_Params,
    events: Input_Box_Events,
    visible_cols: int,
    key_state: Input_Box_Key_State) {

    if !params.enabled || !params.has_focus {
        return
    }

    text_len := key_state.text_len
    caret := key_state.caret
    viewport := key_state.viewport
    moved_up := key_state.moved_up
    moved_down := key_state.moved_down

    moved_up^ = false
    moved_down^ = false
    key_state.paste_applied^ = false

    input_box_apply_caret_movement(params, events, text_len^, caret,
        Input_Box_Movement_Flags{moved_up, moved_down})

    caret^ = input_box_clamp_cursor(caret^, text_len^)
    input_box_apply_edit_events(params, events, key_state)

    caret^ = input_box_clamp_cursor(caret^, text_len^)
    input_box_update_viewport_for_caret(caret^, visible_cols, viewport)
}

//   Apply directional caret-movement events (up/down/left/right/home/end).
input_box_apply_caret_movement :: proc(
    params: Input_Box_Params,
    events: Input_Box_Events,
    text_len: int,
    caret: ^int,
    moved: Input_Box_Movement_Flags) {

    if events.up {
        moved.moved_up^ = input_box_move_caret_up(params.text_buffer, text_len, caret)
    }
    if events.down {
        moved.moved_down^ =
            input_box_move_caret_down(params.text_buffer, text_len, caret)
    }
    if events.left {
        caret^ = input_box_prev_codepoint_start(params.text_buffer, 0, caret^)
    }
    if events.right {
        caret^ = input_box_next_codepoint_start(params.text_buffer, text_len, caret^)
    }
    if events.home {
        caret^ = 0
    }
    if events.end {
        caret^ = text_len
    }
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

//   Compute the final viewport column after keyboard edits.
input_box_final_viewport :: proc(
    params: Input_Box_Params,
    caret_col_in_line, visible_cols, line_len, viewport: int) -> int {

    if params.terminal_mode {
        return 0
    }
    result := min(viewport, line_len)
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &result)
    return result
}

//   Apply keyboard events for one frame, updating text/caret/viewport in place.
//
// Returns:
//   - outcome: Movement/paste/change flags produced by the edits.
input_box_run_keyboard_events :: proc(
    params: Input_Box_Params,
    events: Input_Box_Events,
    visible_cols: int,
    frame: Input_Box_Frame_State) -> Input_Box_Edit_Outcome {

    outcome := Input_Box_Edit_Outcome{}
    text_len_before := frame.text_len^
    input_box_apply_keyboard_events(
        params,
        events,
        visible_cols,
        Input_Box_Key_State{
            text_len = frame.text_len,
            caret = frame.caret,
            viewport = frame.viewport,
            moved_up = &outcome.moved_up,
            moved_down = &outcome.moved_down,
            paste_applied = &outcome.paste_applied,
        })
    outcome.changed = frame.text_len^ != text_len_before
    return outcome
}

//   Resolve hover state and press ownership for one input box frame.
input_box_resolve_press :: proc(
    params: Input_Box_Params,
    press_owner: ^core.Ui_Press_Owner_State,
    local_mouse: rl.Vector2,
    drawn_rect: rl.Rectangle) -> (bool, bool) {

    hovered_item := rl.CheckCollisionPointRec(local_mouse, drawn_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    owns_press := input_box_owns_press(press_owner, params.id)
    can_interact := params.enabled && params.interaction_enabled
    input_box_try_capture_press(params, press_owner, hovered, can_interact, &owns_press)
    input_box_release_press(params, press_owner, &owns_press)
    return hovered, owns_press
}

//   Apply a mouse click to caret placement, dispatching on terminal mode.
input_box_apply_mouse_click :: proc(
    params: Input_Box_Params,
    click: Input_Box_Click_Geometry,
    click_ctx: Input_Box_Click_Context,
    caret: ^int) {

    if params.terminal_mode {
        terminal_click := click
        terminal_click.viewport = 0
        terminal_click.line_start = 0
        terminal_click.line_end = 0
        input_box_apply_terminal_mouse_caret_click(
            params, terminal_click, click_ctx.visible_cols, caret)
        return
    }

    full_click := click
    full_click.viewport = click_ctx.viewport
    full_click.line_start = click_ctx.line_start
    full_click.line_end = click_ctx.line_end
    input_box_apply_mouse_caret_click(params, full_click, caret)
}

//   Build the result for one handled input box frame.
input_box_build_result :: proc(
    drawn_rect: rl.Rectangle,
    events: Input_Box_Events,
    outcome: Input_Box_Edit_Outcome,
    frame: Input_Box_Frame_State,
    interaction: Input_Box_Interaction_Flags) -> Input_Box_Result {

    return Input_Box_Result{
        drawn_rect = drawn_rect,
        text_len_out = frame.text_len^,
        caret_col_out = frame.caret^,
        viewport_col_start_out = frame.viewport^,
        changed = outcome.changed,
        moved_up = outcome.moved_up,
        moved_down = outcome.moved_down,
        history_previous = events.up,
        history_next = events.down,
        tab_pressed = events.tab,
        backspace_pressed = events.backspace,
        paste_applied = outcome.paste_applied,
        submit_pressed = rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER),
        hovered = interaction.hovered,
        pressed = interaction.owns_press && interaction.mouse_left_down,
    }
}

//   Resolve one input frame (mouse/key handling + state updates) without drawing.
//   Parent may inspect result and apply policy (history/submit) before drawing.
handle_input_box :: proc(
    params: Input_Box_Params,
    press_owner: ^core.Ui_Press_Owner_State) -> Input_Box_Result {

    events := capture_input_box_events()

    drawn_rect := clamp_non_negative_rect(params.rect)
    local_mouse := input_box_local_mouse(params.mouse, params.scroll_offset)
    hovered, owns_press :=
        input_box_resolve_press(params, press_owner, local_mouse, drawn_rect)

    text_len := input_box_clamp_text_len(params.text_len_in, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col_in, text_len)
    viewport := max(0, params.viewport_col_start_in)

    text_rect, visible_cols := input_box_content_layout(params, drawn_rect)
    line_start, line_end :=
        input_box_current_line_bounds(params.text_buffer, text_len, caret)
    input_box_apply_mouse_click(params,
        Input_Box_Click_Geometry{hovered, local_mouse, text_rect, 0, 0, 0},
        Input_Box_Click_Context{visible_cols, viewport, line_start, line_end}, &caret)

    outcome := input_box_run_keyboard_events(params, events, visible_cols,
        Input_Box_Frame_State{&text_len, &caret, &viewport})
    line_start, line_end =
        input_box_current_line_bounds(params.text_buffer, text_len, caret)

    line_len := input_box_count_codepoints(params.text_buffer, line_start, line_end)
    caret_col_in_line := input_box_count_codepoints(params.text_buffer, line_start, caret)
    viewport = input_box_final_viewport(params, caret_col_in_line, visible_cols,
        line_len, viewport)

    return input_box_build_result(drawn_rect, events, outcome,
        Input_Box_Frame_State{&text_len, &caret, &viewport},
        Input_Box_Interaction_Flags{owns_press, params.mouse.left_down, hovered})
}

//   Draw one input fragment through shaping when a matching cache is available.
input_box_draw_text :: proc(
    params: Input_Box_Draw_Params, draw: view_core.Shaped_Text_Draw) {

    if params.font_cache == nil {
        view_core.ui_text_draw_unshaped(draw)
        return
    }
    resolver := font.cache_terminal_resolver(params.font_cache)
    request := draw
    request.resolver = resolver
    request.key = params.font_key
    view_core.ui_text_shaped_f32(request)
}

//   Draw one terminal row with shaping split around the cursor codepoint.
draw_terminal_input_row :: proc(
    params: Input_Box_Draw_Params, draw: Terminal_Input_Row_Draw) {

    text_font := view_core.Ui_Text_Font{params.font, params.font_size}
    caret := input_box_clamp_cursor(params.caret_col, params.text_len)
    if !params.has_focus || caret < draw.text_start || caret >= draw.text_end {
        input_box_draw_text(params, {
            text = string(params.text_buffer[draw.text_start:draw.text_end]),
            position = draw.position, color = draw.color, font = text_font})
        return
    }

    segments, segmented := input_box_cursor_segments(
        params.text_buffer, draw.text_start, draw.text_end, caret)
    if !segmented {
        input_box_draw_text(params, {
            text = string(params.text_buffer[draw.text_start:draw.text_end]),
            position = draw.position, color = draw.color, font = text_font})
        return
    }
    before_columns := input_box_count_codepoints(
        params.text_buffer, draw.text_start, caret)
    input_box_draw_text(params, {text = segments.before,
        position = draw.position, color = draw.color, font = text_font})

    cursor_x := draw.position.x + f32(before_columns)*max(1.0, params.char_advance)
    view_core.ui_text_f32(
        segments.cursor, cursor_x, draw.position.y, draw.color, text_font)

    after_x := cursor_x + max(1.0, params.char_advance)
    input_box_draw_text(params, {text = segments.after,
        position = {after_x, draw.position.y}, color = draw.color, font = text_font})
}

//   Draw wrapped terminal input text aligned after the first-row prompt.
draw_terminal_input_rows :: proc(
    params: Input_Box_Draw_Params, content_x: f32,
    columns: int, display_color: rl.Color) {

    safe_len := input_box_clamp_text_len(params.text_len, len(params.text_buffer))
    row_height := max(1.0, params.terminal_row_height)
    row := 0
    line_start := 0
    for {
        line_end := terminal_input_line_end(params.text_buffer, safe_len, line_start)
        line_cols := input_box_count_codepoints(params.text_buffer, line_start, line_end)
        line_rows := terminal_input_line_row_count(line_cols, columns)
        for line_row in 0..<line_rows {
            start_col := min(line_row * columns, line_cols)
            end_col := min(start_col + columns, line_cols)
            text_start := input_box_byte_offset_for_codepoint_col(
                params.text_buffer, line_start, line_end, start_col)
            text_end := input_box_byte_offset_for_codepoint_col(
                params.text_buffer, line_start, line_end, end_col)
            if text_end > text_start {
                draw_terminal_input_row(params, {
                    text_start = text_start,
                    text_end = text_end,
                    position = {content_x, params.rect.y + f32(row)*row_height},
                    color = display_color,
                })
            }
            row += 1
        }
        if line_end >= safe_len {
            return
        }
        line_start = line_end + 1
    }
}

//   Draw a blinking terminal block cursor and invert the covered glyph.
draw_terminal_input_cursor :: proc(
    params: Input_Box_Draw_Params, content_x: f32,
    columns: int, display_color: rl.Color) {

    if !params.has_focus || !params.enabled ||
        !input_box_should_draw_caret(
            params.mouse.timestamp_seconds, params.caret_blink_half_period_seconds) {
        return
    }

    safe_len := input_box_clamp_text_len(params.text_len, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col, safe_len)
    position := terminal_input_position(params.text_buffer, safe_len, caret, columns)
    row_height := max(1.0, params.terminal_row_height)
    cursor_rect := rl.Rectangle{
        content_x + f32(position.col) * max(1.0, params.char_advance),
        params.rect.y + f32(position.row) * row_height,
        max(1.0, params.char_advance),
        row_height - 1,
    }
    rl.DrawRectangleRec(cursor_rect, display_color)

    if caret >= safe_len || params.text_buffer[caret] == '\n' {
        return
    }
    next := input_box_next_codepoint_start(params.text_buffer, safe_len, caret)
    view_core.ui_text(string(params.text_buffer[caret:next]),
        int(cursor_rect.x), int(cursor_rect.y), params.terminal_background_color,
        view_core.Ui_Text_Font{params.font, params.font_size})
}

//   Draw all wrapped terminal input rows, prompt, and full-cell cursor.
draw_terminal_input_box :: proc(params: Input_Box_Draw_Params) {
    drawn_rect := clamp_non_negative_rect(params.rect)
    prefix_cstr :=
        strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
    prefix_width :=
        max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
    content_x := drawn_rect.x + prefix_width
    columns :=
        input_box_visible_cols(drawn_rect.width - prefix_width, params.char_advance)
    display_color := params.enabled ? params.font_color : rl.Color{110, 110, 110, 255}
    prompt_color :=
        params.enabled ? params.terminal_prompt_color : rl.Color{110, 110, 110, 255}

    if len(params.prompt_prefix) > 0 {
        prompt_font := view_core.Ui_Text_Font{
            params.terminal_prompt_font, params.font_size}
        if params.font_cache != nil {
            resolver := font.cache_terminal_resolver(params.font_cache)
            view_core.ui_text_shaped({
                resolver = resolver,
                key = .Bold,
                text = params.prompt_prefix,
                position = {drawn_rect.x, drawn_rect.y},
                color = prompt_color,
                font = prompt_font,
            })
        } else {
            view_core.ui_text(
                params.prompt_prefix, int(drawn_rect.x), int(drawn_rect.y),
                prompt_color, prompt_font)
        }
    }
    draw_terminal_input_rows(params, content_x, columns, display_color)
    draw_terminal_input_cursor(params, content_x, columns, display_color)
}

//   Compute the visible text slice and clamped viewport for one non-terminal input box.
//
// Returns:
//   - visible_text: The visible text slice.
//   - visible_start: The clamped first visible column.
input_box_visible_text :: proc(
    params: Input_Box_Draw_Params,
    line_start, line_end, caret_col_in_line, visible_cols: int) -> (string, int) {

    line_len := input_box_count_codepoints(params.text_buffer, line_start, line_end)
    viewport := max(0, min(params.viewport_col_start, line_len))
    input_box_update_viewport_for_caret(caret_col_in_line, visible_cols, &viewport)

    visible_start := clamp(viewport, 0, line_len)
    visible_end := clamp(visible_start + visible_cols, visible_start, line_len)
    if visible_end <= visible_start {
        return "", visible_start
    }

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
    return string(params.text_buffer[text_start:text_end]), visible_start
}

//   Draw the blinking caret for one focused non-terminal input box.
input_box_draw_caret :: #force_inline proc(
    params: Input_Box_Draw_Params,
    placement: Input_Box_Caret_Placement,
    color: rl.Color) {

    if !params.has_focus || !params.enabled ||
        !input_box_should_draw_caret(
            params.mouse.timestamp_seconds,
            params.caret_blink_half_period_seconds) {
        return
    }

    caret_col_local := clamp(
        placement.caret_col_in_line - placement.visible_start, 0, placement.visible_cols)
    caret_x := placement.content_x +
        f32(caret_col_local) * max(1.0, params.char_advance) - 4.0
    view_core.ui_text("|", int(caret_x), int(placement.row_y), color,
        view_core.Ui_Text_Font{params.font, params.font_size})
}

//   Measure the prompt prefix width in pixels for one input box.
input_box_prefix_width :: #force_inline proc(params: Input_Box_Draw_Params) -> f32 {
    if len(params.prompt_prefix) == 0 {
        return 0
    }
    prefix_cstr :=
        strings.clone_to_cstring(params.prompt_prefix, context.temp_allocator)
    return max(0.0, rl.MeasureTextEx(params.font, prefix_cstr, params.font_size, 0).x)
}

//   Draw the visible text and prompt for one non-terminal input box.
input_box_draw_content :: proc(
    params: Input_Box_Draw_Params,
    drawn_rect: rl.Rectangle,
    visible_text: string,
    content_x: f32) {

    display_color := params.font_color
    if !params.enabled {
        display_color = rl.Color{110, 110, 110, 255}
    }

    if len(visible_text) > 0 {
        input_box_draw_text(params, {
            text = visible_text,
            position = {content_x, drawn_rect.y},
            color = display_color,
            font = {params.font, params.font_size},
        })
    }

    if len(params.prompt_prefix) > 0 {
        view_core.ui_text(params.prompt_prefix,
            int(drawn_rect.x),
            int(drawn_rect.y),
            display_color,
            view_core.Ui_Text_Font{params.font, params.font_size})
    }
}

//   Draw input text and caret from caller-provided post-policy state.
draw_input_box :: proc(params: Input_Box_Draw_Params) {
    if params.terminal_mode {
        draw_terminal_input_box(params)
        return
    }

    drawn_rect := clamp_non_negative_rect(params.rect)

    text_len := input_box_clamp_text_len(params.text_len, len(params.text_buffer))
    caret := input_box_clamp_cursor(params.caret_col, text_len)
    line_start, line_end :=
        input_box_current_line_bounds(params.text_buffer, text_len, caret)

    prefix_width := input_box_prefix_width(params)
    content_x := drawn_rect.x + prefix_width
    content_width := max(0.0, drawn_rect.width - prefix_width)
    visible_cols := input_box_visible_cols(content_width, params.char_advance)

    caret_col_in_line := input_box_count_codepoints(params.text_buffer, line_start, caret)
    visible_text, visible_start := input_box_visible_text(params,
        line_start, line_end, caret_col_in_line, visible_cols)

    input_box_draw_content(params, drawn_rect, visible_text, content_x)

    display_color := params.font_color
    if !params.enabled {
        display_color = rl.Color{110, 110, 110, 255}
    }
    input_box_draw_caret(params,
        Input_Box_Caret_Placement{
            caret_col_in_line, visible_start, visible_cols, content_x, drawn_rect.y},
        display_color)
}
