package ui

import viewmodel "../model"

import dyncore "../../dynview/core"
import geometry "../../core/geometry"
import input "../input"
import native "../native"
import view_core "../core"
import view_font "../font"

INPUT_BOX_TEXT_INSET :: f32(4)

// Input_Box_Params groups borrowed content, geometry, and routed frame interaction.
Input_Box_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    text: string,
    content_revision: u64,
    state: ^viewmodel.Ui_Input_Box_State,
    frame: Input_Frame,
    focused: bool,
    pointer_routed: bool,
    column_advance: f32,
    font: view_font.Font_Face,
    resolver: view_font.Font_Resolver,
}

// Input_Box_Update reports the selected copy range produced by one update.
Input_Box_Update :: struct {
    copy_start: int,
    copy_end: int,
    copy_requested: bool,
}

// Input_Box_Result carries prepared interaction and clipped draw geometry.
Input_Box_Result :: struct {
    hovered: bool,
    focused: bool,
    inner: geometry.Rectangle,
    text_x: f32,
    selection: geometry.Rectangle,
    caret: geometry.Rectangle,
}

// input_box_clamp_boundary clamps one byte offset to a UTF-8 codepoint boundary.
input_box_clamp_boundary :: proc(text: string, offset: int) -> int {
    result := clamp(offset, 0, len(text))
    for result > 0 && result < len(text) &&
        dyncore.text_is_utf8_trailing_byte(text[result]) {
        result -= 1
    }
    return result
}

// input_box_previous_boundary returns the codepoint boundary before one offset.
input_box_previous_boundary :: proc(text: string, offset: int) -> int {
    result := input_box_clamp_boundary(text, offset)
    if result <= 0 {return 0}
    result -= 1
    for result > 0 && dyncore.text_is_utf8_trailing_byte(text[result]) {
        result -= 1
    }
    return result
}

// input_box_next_boundary returns the codepoint boundary after one offset.
input_box_next_boundary :: proc(text: string, offset: int) -> int {
    result := input_box_clamp_boundary(text, offset)
    if result >= len(text) {return len(text)}
    return min(len(text), result + max(1,
        dyncore.text_utf8_sequence_len(text, result)))
}

// input_box_byte_column returns the codepoint column for one byte boundary.
input_box_byte_column :: #force_inline proc(text: string, offset: int) -> int {
    boundary := input_box_clamp_boundary(text, offset)
    return dyncore.text_codepoint_count_span(text, 0, boundary)
}

// input_box_column_boundary returns the byte boundary nearest one codepoint column.
input_box_column_boundary :: proc(text: string, column: int) -> int {
    offset := 0
    for _ in 0..<max(0, column) {
        if offset >= len(text) {break}
        offset = input_box_next_boundary(text, offset)
    }
    return offset
}

// input_box_reconcile_content resets interaction to newly published borrowed text.
input_box_reconcile_content :: proc(
    state: ^viewmodel.Ui_Input_Box_State, text: string, revision: u64) -> bool {
    if state == nil {return false}
    if state^.content_revision != revision {
        state^.cursor_byte = len(text)
        state^.anchor_byte = len(text)
        state^.scroll_x = 0
        state^.content_revision = revision
        state^.dragging = false
        return true
    }
    state^.cursor_byte = input_box_clamp_boundary(text, state^.cursor_byte)
    state^.anchor_byte = input_box_clamp_boundary(text, state^.anchor_byte)
    return false
}

// input_box_move_cursor applies one read-only navigation key and selection policy.
input_box_move_cursor :: proc(
    state: ^viewmodel.Ui_Input_Box_State, text: string,
    key: input.Input_Key, extend: bool) {
    destination := state^.cursor_byte
    selection_start := min(state^.anchor_byte, state^.cursor_byte)
    selection_end := max(state^.anchor_byte, state^.cursor_byte)
    #partial switch key {
    case .Left:
        destination = selection_start if !extend && selection_start != selection_end else
            input_box_previous_boundary(text, destination)
    case .Right:
        destination = selection_end if !extend && selection_start != selection_end else
            input_box_next_boundary(text, destination)
    case .Home: destination = 0
    case .End: destination = len(text)
    case: return
    }
    if !extend {state^.anchor_byte = destination}
    state^.cursor_byte = destination
}

// input_box_apply_keyboard updates read-only navigation and reports copy intent.
input_box_apply_keyboard :: proc(
    state: ^viewmodel.Ui_Input_Box_State,
    text: string, frame: input.Input_Frame) -> Input_Box_Update {
    result: Input_Box_Update
    if state == nil {return result}
    for event in frame.events {
        if event.kind != .Press && event.kind != .Repeat {continue}
        control := .Control in event.modifiers
        if control && event.key == .A {
            state^.anchor_byte = 0
            state^.cursor_byte = len(text)
        } else if control && event.key == .C {
            result.copy_start = min(state^.anchor_byte, state^.cursor_byte)
            result.copy_end = max(state^.anchor_byte, state^.cursor_byte)
            result.copy_requested = result.copy_end > result.copy_start
        } else if !control {
            input_box_move_cursor(
                state, text, event.key, .Shift in event.modifiers)
        }
    }
    return result
}

// input_box_hit_boundary maps one screen x coordinate to a borrowed-text boundary.
input_box_hit_boundary :: proc(params: Input_Box_Params, x: f32) -> int {
    if params.column_advance <= 0 {return 0}
    local_x := x - params.rect.x - INPUT_BOX_TEXT_INSET + params.state^.scroll_x
    column := int(max(f32(0), local_x) / params.column_advance + 0.5)
    return input_box_column_boundary(params.text, column)
}

// input_box_update_pointer resolves shared capture and UTF-8-safe drag selection.
input_box_update_pointer :: proc(
    params: Input_Box_Params, hovered: bool,
    owner: ^viewmodel.Ui_Press_Owner_State) {
    owns := owner^.active && owner^.kind == .Input_Box && owner^.id == params.id
    if params.pointer_routed && hovered && input_frame_left_pressed(params.frame) &&
        !owner^.active {
        owner^ = {active = true, kind = .Input_Box, id = params.id}
        params.state^.cursor_byte = input_box_hit_boundary(
            params, params.frame.mouse_position.x)
        params.state^.anchor_byte = params.state^.cursor_byte
        params.state^.dragging = true
        owns = true
    }
    if owns && input_frame_left_down(params.frame) {
        params.state^.cursor_byte = input_box_hit_boundary(
            params, params.frame.mouse_position.x)
    }
    if owns && input_frame_left_released(params.frame) {
        params.state^.cursor_byte = input_box_hit_boundary(
            params, params.frame.mouse_position.x)
        params.state^.dragging = false
        owner^ = {}
    }
}

// input_box_reveal_cursor clamps horizontal scrolling around the active caret.
input_box_reveal_cursor :: proc(
    params: Input_Box_Params, align_end: bool) {
    visible_width := max(f32(0), params.rect.width - INPUT_BOX_TEXT_INSET * 2)
    total_width := f32(input_box_byte_column(params.text, len(params.text))) *
        params.column_advance
    maximum := max(f32(0), total_width - visible_width + 1)
    cursor_x := f32(input_box_byte_column(
        params.text, params.state^.cursor_byte)) * params.column_advance
    if align_end {
        params.state^.scroll_x = maximum
    } else if cursor_x < params.state^.scroll_x {
        params.state^.scroll_x = cursor_x
    } else if cursor_x + 1 > params.state^.scroll_x + visible_width {
        params.state^.scroll_x = cursor_x - visible_width + 1
    }
    params.state^.scroll_x = clamp(params.state^.scroll_x, 0, maximum)
}

// input_box_prepare updates one read-only field and builds its draw geometry.
input_box_prepare :: proc(
    params: Input_Box_Params,
    owner: ^viewmodel.Ui_Press_Owner_State) -> Input_Box_Result {
    changed := input_box_reconcile_content(
        params.state, params.text, params.content_revision)
    hovered := geometry.rectangle_contains(params.rect,
        {params.frame.mouse_position.x, params.frame.mouse_position.y})
    input_box_update_pointer(params, hovered, owner)
    if params.focused {
        copy := input_box_apply_keyboard(params.state, params.text, params.frame)
        if copy.copy_requested {
            input.input_set_clipboard_text(params.text[copy.copy_start:copy.copy_end])
        }
    }
    input_box_reveal_cursor(params, changed)
    return input_box_draw_result(params, hovered)
}

// input_box_draw_result derives clipped selection and caret rectangles.
input_box_draw_result :: proc(
    params: Input_Box_Params, hovered: bool) -> Input_Box_Result {
    inner := params.rect
    inner.x += INPUT_BOX_TEXT_INSET
    inner.width = max(f32(0), inner.width - INPUT_BOX_TEXT_INSET * 2)
    start := min(params.state^.anchor_byte, params.state^.cursor_byte)
    end := max(params.state^.anchor_byte, params.state^.cursor_byte)
    start_x := f32(input_box_byte_column(params.text, start)) * params.column_advance
    end_x := f32(input_box_byte_column(params.text, end)) * params.column_advance
    caret_x := f32(input_box_byte_column(
        params.text, params.state^.cursor_byte)) * params.column_advance
    text_y := params.rect.y + (params.rect.height - TREE_FONT_SIZE) * 0.5
    return {hovered = hovered, focused = params.focused, inner = inner,
        text_x = inner.x - params.state^.scroll_x,
        selection = {inner.x + start_x - params.state^.scroll_x, text_y,
            end_x - start_x, TREE_FONT_SIZE},
        caret = {inner.x + caret_x - params.state^.scroll_x, text_y,
            1, TREE_FONT_SIZE}}
}

// draw_encoded_input_box renders one prepared read-only field inside its clip.
draw_encoded_input_box :: proc(
    encoder: ^native.Draw_Encoder,
    params: Input_Box_Params, prepared: Input_Box_Result) {
    _ = native.draw_encoder_rectangle(
        encoder, params.rect, UI_COMPONENT_BACKGROUND_COLOR)
    border := UI_BORDER_COLOR
    if prepared.focused {border = UI_TEXT_COLOR}
    _ = native.draw_encoder_rectangle_outline(encoder, params.rect, 1, border)
    _ = native.draw_encoder_push_scissor(encoder, prepared.inner)
    if prepared.selection.width > 0 {
        _ = native.draw_encoder_rectangle(encoder, prepared.selection, UI_BORDER_COLOR)
    }
    _ = view_core.ui_text_shaped({encoder = encoder, resolver = params.resolver,
        key = .Regular, text = params.text,
        position = {prepared.text_x, prepared.caret.y}, color = UI_TEXT_COLOR,
        font = view_core.ui_text_font(params.font)})
    if prepared.focused {
        _ = native.draw_encoder_rectangle(encoder, prepared.caret, UI_TEXT_COLOR)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}