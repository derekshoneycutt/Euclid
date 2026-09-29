package ui

import viewmodel "../model"

import dyncore "../../dynview/core"
import geometry "../../core/geometry"
import input "../input"
import native "../native"
import view_core "../core"
import view_font "../font"
import "core:unicode/utf8"

INPUT_BOX_TEXT_INSET :: f32(4)

// Input_Box_Params groups borrowed content, geometry, and routed frame interaction.
Input_Box_Params :: struct {
    rect: geometry.Rectangle,
    clip_rect: geometry.Rectangle,
    descriptor: viewmodel.Ui_Editable_Text_Descriptor,
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    state: ^viewmodel.Ui_Input_Box_State,
    frame: Input_Frame,
    focused: bool,
    pointer_routed: bool,
    column_advance: f32,
    font: view_font.Font_Face,
    resolver: view_font.Font_Resolver,
    edit_target: Input_Box_Edit_Target,
}

// Input_Box_Update reports the selected copy range produced by one update.
Input_Box_Update :: struct {
    copy_start: int,
    copy_end: int,
    copy_requested: bool,
    changed: bool,
    submit_requested: bool,
    tab_requested: bool,
    copied_length: int,
    copied_bytes: [viewmodel.LIBRARY_SEARCH_QUERY_BYTE_CAPACITY]u8,
}

// Input_Box_Edit_Target supplies caller-owned bounded text storage.
Input_Box_Edit_Target :: struct {
    bytes: []u8,
    length: ^int,
}

// Input_Box_Result carries prepared interaction and clipped draw geometry.
Input_Box_Result :: struct {
    hovered: bool,
    focused: bool,
    control_geometry: viewmodel.Ui_Control_Geometry,
    descriptor: viewmodel.Ui_Editable_Text_Descriptor,
    text_geometry: viewmodel.Ui_Editable_Text_Geometry,
    inner: geometry.Rectangle,
    text_x: f32,
    selection: geometry.Rectangle,
    caret: geometry.Rectangle,
    changed: bool,
    submit_requested: bool,
    tab_requested: bool,
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

// input_box_replace_selection replaces the selected bytes without splitting UTF-8.
input_box_replace_selection :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    replacement: string) -> bool {
    if state == nil || target.length == nil {return false}
    text_length := clamp(target.length^, 0, len(target.bytes))
    text := string(target.bytes[:text_length])
    first := min(input_box_clamp_boundary(text, state^.anchor_byte),
        input_box_clamp_boundary(text, state^.cursor_byte))
    last := max(input_box_clamp_boundary(text, state^.anchor_byte),
        input_box_clamp_boundary(text, state^.cursor_byte))
    available := len(target.bytes) - (text_length - (last - first))
    inserted := min(len(replacement), max(0, available))
    for inserted > 0 && inserted < len(replacement) &&
        dyncore.text_is_utf8_trailing_byte(replacement[inserted]) {
        inserted -= 1
    }
    if first == last && inserted == 0 {return false}
    tail_length := text_length - last
    copy(target.bytes[first + inserted:first + inserted + tail_length],
        target.bytes[last:text_length])
    copy(target.bytes[first:first + inserted], transmute([]u8)replacement[:inserted])
    target.length^ = first + inserted + tail_length
    state^.cursor_byte = first + inserted
    state^.anchor_byte = state^.cursor_byte
    return first != last || inserted > 0
}

// input_box_delete_selection removes a selection or one adjacent codepoint.
input_box_delete_selection :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    backwards: bool) -> bool {
    text := string(target.bytes[:clamp(target.length^, 0, len(target.bytes))])
    first := min(state^.anchor_byte, state^.cursor_byte)
    last := max(state^.anchor_byte, state^.cursor_byte)
    if first == last {
        if backwards {first = input_box_previous_boundary(text, first)}
        else {last = input_box_next_boundary(text, last)}
    }
    state^.anchor_byte = first
    state^.cursor_byte = last
    return input_box_replace_selection(state, target, "")
}

// input_box_capture_selection copies the current selected bytes into an update.
input_box_capture_selection :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    result: ^Input_Box_Update) {
    result^.copy_start = min(state^.anchor_byte, state^.cursor_byte)
    result^.copy_end = max(state^.anchor_byte, state^.cursor_byte)
    result^.copy_requested = result^.copy_end > result^.copy_start
    result^.copied_length = min(result^.copy_end - result^.copy_start,
        len(result^.copied_bytes))
    copy(result^.copied_bytes[:result^.copied_length],
        target.bytes[result^.copy_start:result^.copy_start + result^.copied_length])
}

// input_box_apply_edit_control handles one supported control-key edit chord.
input_box_apply_edit_control :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event, clipboard_text: string,
    result: ^Input_Box_Update) -> bool {
    if event.key == .A {
        state^.anchor_byte = 0
        state^.cursor_byte = target.length^
    } else if event.key == .C || event.key == .X {
        input_box_capture_selection(state, target, result)
        if event.key == .X && result^.copy_requested {
            result^.changed = input_box_delete_selection(
                state, target, false) || result^.changed
        }
    } else if event.key == .V {
        result^.changed = input_box_replace_selection(
            state, target, clipboard_text) || result^.changed
    } else {
        return false
    }
    return true
}

// input_box_apply_edit_event applies one text or keyboard event to bounded storage.
input_box_apply_edit_event :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event, clipboard_text: string,
    result: ^Input_Box_Update) {
    if event.kind == .Text {
        encoded, count := utf8.encode_rune(event.codepoint)
        result^.changed = input_box_replace_selection(
            state, target, string(encoded[:count])) || result^.changed
        return
    }
    if event.kind != .Press && event.kind != .Repeat {return}
    control := .Control in event.modifiers
    if control && input_box_apply_edit_control(
        state, target, event, clipboard_text, result) {return}
    if control {return}
    if event.key == .Backspace || event.key == .Delete {
        result^.changed = input_box_delete_selection(
            state, target, event.key == .Backspace) || result^.changed
    } else if event.key == .Enter {
        result^.submit_requested = true
    } else if event.key == .Tab {
        result^.tab_requested = true
    } else {
        text := string(target.bytes[:target.length^])
        input_box_move_cursor(
            state, text, event.key, .Shift in event.modifiers)
    }
}

// input_box_apply_edit_keyboard mutates caller-owned text from one ordered frame.
input_box_apply_edit_keyboard :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    frame: input.Input_Frame, clipboard_text: string = "") -> Input_Box_Update {
    result: Input_Box_Update
    if state == nil || target.length == nil {return result}
    for event in frame.events {
        input_box_apply_edit_event(
            state, target, event, clipboard_text, &result)
    }
    return result
}

// input_box_frame_requests_paste reports whether one frame contains Ctrl+V.
input_box_frame_requests_paste :: proc(frame: input.Input_Frame) -> bool {
    for event in frame.events {
        if (event.kind == .Press || event.kind == .Repeat) &&
            event.key == .V && .Control in event.modifiers {return true}
    }
    return false
}

// input_box_apply_focused_input resolves editable or read-only keyboard policy.
input_box_apply_focused_input :: proc(
    params: Input_Box_Params, resolved: ^Input_Box_Params) -> Input_Box_Update {
    if params.descriptor.mode == .Read_Only || params.edit_target.length == nil {
        return input_box_apply_keyboard(
            params.state, params.descriptor.text, params.frame)
    }
    clipboard_text := ""
    if input_box_frame_requests_paste(params.frame) {
        clipboard_text = input.input_get_clipboard_text()
    }
    update := input_box_apply_edit_keyboard(
        params.state, params.edit_target, params.frame, clipboard_text)
    resolved^.descriptor.text = string(
        params.edit_target.bytes[:params.edit_target.length^])
    return update
}

// input_box_hit_boundary maps one screen x coordinate to a borrowed-text boundary.
input_box_hit_boundary :: proc(params: Input_Box_Params, x: f32) -> int {
    if params.column_advance <= 0 {return 0}
    local_x := x - params.rect.x - INPUT_BOX_TEXT_INSET + params.state^.scroll_x
    column := int(max(f32(0), local_x) / params.column_advance + 0.5)
    return input_box_column_boundary(params.descriptor.text, column)
}

// input_box_update_pointer resolves shared capture and UTF-8-safe drag selection.
input_box_update_pointer :: proc(
    params: Input_Box_Params, hovered: bool,
    owner: ^viewmodel.Ui_Press_Owner_State) {
    press_id := int(params.descriptor.id.local_id)
    owns := owner^.active && owner^.kind == .Input_Box && owner^.id == press_id
    if params.pointer_routed && hovered && input_frame_left_pressed(params.frame) &&
        !owner^.active {
        owner^ = {active = true, kind = .Input_Box, id = press_id}
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
    text := params.descriptor.text
    total_width := f32(input_box_byte_column(text, len(text))) * params.column_advance
    maximum := max(f32(0), total_width - visible_width + 1)
    cursor_x := f32(input_box_byte_column(
        text, params.state^.cursor_byte)) * params.column_advance
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
    resolved := params
    changed := input_box_reconcile_content(
        params.state, params.descriptor.text, params.descriptor.content_revision)
    hovered := geometry.rectangle_contains(params.rect,
        {params.frame.mouse_position.x, params.frame.mouse_position.y})
    input_box_update_pointer(params, hovered, owner)
    update: Input_Box_Update
    if params.focused {
        update = input_box_apply_focused_input(params, &resolved)
        if update.copy_requested {
            copied := params.descriptor.text[update.copy_start:update.copy_end]
            if update.copied_length > 0 {
                copied = string(update.copied_bytes[:update.copied_length])
            }
            input.input_set_clipboard_text(copied)
        }
    }
    input_box_reveal_cursor(resolved, changed)
    result := input_box_draw_result(resolved, hovered)
    result.changed = update.changed
    result.submit_requested = update.submit_requested
    result.tab_requested = update.tab_requested
    input_box_publish_semantics(resolved, owner, &result)
    return result
}

// input_box_result_descriptor projects current bounded selection into the descriptor.
input_box_result_descriptor :: proc(params: Input_Box_Params) ->
    viewmodel.Ui_Editable_Text_Descriptor {
    descriptor := params.descriptor
    descriptor.cursor_byte = input_box_clamp_boundary(
        descriptor.text, params.state^.cursor_byte)
    descriptor.anchor_byte = input_box_clamp_boundary(
        descriptor.text, params.state^.anchor_byte)
    return descriptor
}

// input_box_draw_result derives clipped selection and caret rectangles.
input_box_draw_result :: proc(
    params: Input_Box_Params, hovered: bool) -> Input_Box_Result {
    inner := params.rect
    inner.x += INPUT_BOX_TEXT_INSET
    inner.width = max(f32(0), inner.width - INPUT_BOX_TEXT_INSET * 2)
    start := min(params.state^.anchor_byte, params.state^.cursor_byte)
    end := max(params.state^.anchor_byte, params.state^.cursor_byte)
    text := params.descriptor.text
    start_x := f32(input_box_byte_column(text, start)) * params.column_advance
    end_x := f32(input_box_byte_column(text, end)) * params.column_advance
    caret_x := f32(input_box_byte_column(
        text, params.state^.cursor_byte)) * params.column_advance
    text_y := params.rect.y + (params.rect.height - TREE_FONT_SIZE) * 0.5
    descriptor := input_box_result_descriptor(params)
    selection := geometry.Rectangle{inner.x + start_x - params.state^.scroll_x,
        text_y, end_x - start_x, TREE_FONT_SIZE}
    caret := geometry.Rectangle{inner.x + caret_x - params.state^.scroll_x,
        text_y, 1, TREE_FONT_SIZE}
    control := viewmodel.Ui_Control_Geometry{
        viewmodel.Rectangle(params.rect), viewmodel.Rectangle(params.clip_rect)}
    return {hovered = hovered, focused = params.focused,
        control_geometry = control, descriptor = descriptor,
        text_geometry = {
            control = control,
            caret = viewmodel.Rectangle(caret),
            selection = viewmodel.Rectangle(selection),
            cursor_column = input_box_byte_column(
                descriptor.text, descriptor.cursor_byte),
            anchor_column = input_box_byte_column(
                descriptor.text, descriptor.anchor_byte),
        }, inner = inner,
        text_x = inner.x - params.state^.scroll_x,
        selection = selection, caret = caret}
}

// input_box_publish_semantics registers prepared text state and pointer focus.
input_box_publish_semantics :: proc(
    params: Input_Box_Params, owner: ^viewmodel.Ui_Press_Owner_State,
    result: ^Input_Box_Result) {
    descriptor := result^.descriptor
    if params.semantic_focus == nil || descriptor.id == {} {return}
    states := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.mode == .Read_Only {states += {.Read_Only}}
    _ = semantic_register_control(params.semantic_focus, {
        id = descriptor.id, parent = descriptor.parent, role = .Input,
        states = states, actions = {.Focus}, region = descriptor.region,
        traversal_order = descriptor.traversal_order,
        bounds = result^.text_geometry.control.bounds,
        clip_bounds = result^.text_geometry.control.clip_bounds,
        label = descriptor.label, value = descriptor.text,
    })
    _ = semantic_focus_for_press(params.semantic_focus, owner, .Input_Box,
        int(descriptor.id.local_id), descriptor.id)
}

// draw_encoded_input_box renders one prepared read-only field inside its clip.
draw_encoded_input_box :: proc(
    encoder: ^native.Draw_Encoder,
    params: Input_Box_Params, prepared: Input_Box_Result) {
    _ = native.draw_encoder_rectangle(
        encoder, prepared.control_geometry.bounds, UI_COMPONENT_BACKGROUND_COLOR)
    border := UI_BORDER_COLOR
    if prepared.focused {border = UI_TEXT_COLOR}
    _ = native.draw_encoder_rectangle_outline(
        encoder, prepared.control_geometry.bounds, 1, border)
    _ = native.draw_encoder_push_scissor(encoder, prepared.inner)
    if prepared.selection.width > 0 {
        _ = native.draw_encoder_rectangle(encoder, prepared.selection, UI_BORDER_COLOR)
    }
    _ = view_core.ui_text_shaped({encoder = encoder, resolver = params.resolver,
        key = .Regular, text = params.descriptor.text,
        position = {prepared.text_x, prepared.caret.y}, color = UI_TEXT_COLOR,
        font = view_core.ui_text_font(params.font)})
    if prepared.focused {
        _ = native.draw_encoder_rectangle(encoder, prepared.caret, UI_TEXT_COLOR)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}