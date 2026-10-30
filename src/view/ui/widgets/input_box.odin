package uiwidgets

import coretext "../../../core/text"
import geometry "../../../core/geometry"
import input "../../input"
import native "../../native"
import view_font "../../font"
import utf8 "core:unicode/utf8"
import unicode "core:unicode"
import viewmodel "../model"
import viewtext "../text"
import theme "../theme"
import uisemantics "../semantics"

INPUT_BOX_TEXT_INSET :: f32(4)
INPUT_BOX_COMPACT_TEXT_INSET :: f32(2)

// Input_Box_Padding selects the shared text inset for an input box.
Input_Box_Padding :: enum {
    Default,
    Compact,
}

// Input_Box_Run_Kind defines the three homogeneous double-click selection classes.
Input_Box_Run_Kind :: enum {
    Word,
    Whitespace,
    Punctuation,
}

// Input_Box_Params groups borrowed content, geometry, and routed frame interaction.
Input_Box_Params :: struct {
    rect: geometry.Rectangle,
    clip_rect: geometry.Rectangle,
    descriptor: viewmodel.Ui_Editable_Text_Descriptor,
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    controls: viewmodel.Ui_Node_Id,
    state: ^viewmodel.Ui_Input_Box_State,
    frame: input.Input_Frame,
    // Zero uses the semantic local ID; remapped controls supply their portable input ID.
    text_input_id: int,
    focused: bool,
    pointer_routed: bool,
    defer_semantics: bool,
    padding: Input_Box_Padding,
    control_scale: f32,
    column_advance: f32,
    font_size: f32,
    font: view_font.Font_Face,
    resolver: view_font.Font_Resolver,
    edit_target: Input_Box_Edit_Target,
    edit_policy: Input_Box_Edit_Policy,
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
    suggestion_accepted: bool,
    edit_rejected: bool,
}

// Input_Box_Edit_Target supplies caller-owned bounded text storage.
Input_Box_Edit_Target :: struct {
    bytes: []u8,
    length: ^int,
}

// Input_Box_Edit_Range describes one half-open UTF-8 byte interval.
Input_Box_Edit_Range :: struct {
    first: int,
    last: int,
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
    edit_rejected: bool,
    submit_requested: bool,
    tab_requested: bool,
    suggestion_accepted: bool,
    unicode_completion: Unicode_Completion,
    unicode_hint: geometry.Rectangle,
}

// input_box_text_inset resolves the horizontal inset used by every input surface.
input_box_text_inset :: #force_inline proc(params: Input_Box_Params) -> f32 {
    scale := f32(1) if params.control_scale <= 0 else params.control_scale
    if params.padding == .Compact {
        return INPUT_BOX_COMPACT_TEXT_INSET * scale
    }
    return INPUT_BOX_TEXT_INSET * scale
}

// input_box_clamp_boundary clamps one byte offset to a complete grapheme boundary.
input_box_clamp_boundary :: proc(text: string, offset: int) -> int {
    return coretext.text_grapheme_clamp_boundary(text, offset)
}

// input_box_previous_boundary returns the grapheme boundary before one offset.
input_box_previous_boundary :: proc(text: string, offset: int) -> int {
    return coretext.text_grapheme_previous_boundary(text, offset)
}

// input_box_next_boundary returns the grapheme boundary after one offset.
input_box_next_boundary :: proc(text: string, offset: int) -> int {
    return coretext.text_grapheme_next_boundary(text, offset)
}

// input_box_byte_column returns the display-cell column at one byte boundary.
input_box_byte_column :: #force_inline proc(text: string, offset: int) -> int {
    return coretext.text_grapheme_column(text, offset)
}

// input_box_column_boundary maps a display-cell column to the nearest cluster edge.
input_box_column_boundary :: proc(text: string, column: int) -> int {
    return coretext.text_grapheme_boundary_for_column(text, column)
}

// input_box_reconcile_content resets interaction to newly published borrowed text.
input_box_reconcile_content :: proc(
    state: ^viewmodel.Ui_Input_Box_State, text: string, revision: u64) -> bool {
    if state == nil {
        return false
    }
    if state^.content_revision != revision {
        state^.cursor_byte = len(text)
        state^.anchor_byte = len(text)
        state^.scroll_x = 0
        state^.content_revision = revision
        state^.dragging = false
        state^.fixed_selection = false
        state^.unicode_dismissed = false
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
    case .Home:
        destination = 0
    case .End:
        destination = len(text)
    case:
        return
    }
    if !extend {
        state^.anchor_byte = destination
    }
    state^.cursor_byte = destination
}

// input_box_apply_keyboard updates read-only navigation and reports copy intent.
input_box_apply_keyboard :: proc(
    state: ^viewmodel.Ui_Input_Box_State,
    text: string, frame: input.Input_Frame) -> Input_Box_Update {
    result: Input_Box_Update
    if state == nil {
        return result
    }
    for event in frame.events {
        if event.kind != .Press && event.kind != .Repeat {
            continue
        }
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

// input_box_replace_range admits one complete single-line UTF-8 edit atomically.
input_box_replace_range :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    range: Input_Box_Edit_Range, replacement: string,
    result: ^Input_Box_Update = nil) -> bool {
    if state == nil || target.length == nil {
        return false
    }
    if target.length^ < 0 || target.length^ > len(target.bytes) {
        if result != nil {
            result^.edit_rejected = true
        }
        return false
    }
    text_length := target.length^
    text := string(target.bytes[:text_length])
    if !input_box_edit_is_admissible(text, range, replacement) {
        if result != nil {
            result^.edit_rejected = true
        }
        return false
    }
    final_length := text_length - (range.last - range.first) + len(replacement)
    if final_length > len(target.bytes) {
        if result != nil {
            result^.edit_rejected = true
        }
        return false
    }
    return input_box_commit_replacement(
        state, target, range, replacement, final_length)
}

// input_box_edit_is_admissible validates source, range, UTF-8, and field policy.
input_box_edit_is_admissible :: proc(
    text: string, range: Input_Box_Edit_Range, replacement: string) -> bool {
    return utf8.valid_string(text) && utf8.valid_string(replacement) &&
        range.first >= 0 && range.last >= range.first && range.last <= len(text) &&
        input_box_clamp_boundary(text, range.first) == range.first &&
        input_box_clamp_boundary(text, range.last) == range.last &&
        !input_box_edit_contains_line_break(replacement)
}

// input_box_commit_replacement applies one admitted bounded edit and updates selection.
input_box_commit_replacement :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    range: Input_Box_Edit_Range, replacement: string, final_length: int) -> bool {
    text := string(target.bytes[:target.length^])
    tail_length := len(text) - range.last
    changed := text[range.first:range.last] != replacement
    copy(target.bytes[range.first + len(replacement):
        range.first + len(replacement) + tail_length],
        target.bytes[range.last:len(text)])
    copy(target.bytes[range.first:range.first + len(replacement)],
        transmute([]u8)replacement)
    target.length^ = final_length
    state^.cursor_byte = range.first + len(replacement)
    state^.anchor_byte = state^.cursor_byte
    if changed {
        state^.unicode_dismissed = false
    }
    return changed
}

// input_box_edit_contains_line_break rejects single-line field replacements.
input_box_edit_contains_line_break :: proc(text: string) -> bool {
    for codepoint in text {
        if codepoint == '\r' || codepoint == '\n' {
            return true
        }
    }
    return false
}

// input_box_replace_selection replaces the selected grapheme range atomically.
input_box_replace_selection :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    replacement: string, result: ^Input_Box_Update = nil) -> bool {
    if target.length == nil || state == nil {
        return false
    }
    if target.length^ < 0 || target.length^ > len(target.bytes) {
        if result != nil {
            result^.edit_rejected = true
        }
        return false
    }
    first := min(state^.anchor_byte, state^.cursor_byte)
    last := max(state^.anchor_byte, state^.cursor_byte)
    return input_box_replace_range(state, target, {
        first = first,
        last = last,
    }, replacement, result)
}

// input_box_delete_selection removes a selection or one adjacent grapheme.
input_box_delete_selection :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    backwards: bool, result: ^Input_Box_Update) -> bool {
    if state == nil || target.length == nil {
        return false
    }
    if target.length^ < 0 || target.length^ > len(target.bytes) {
        result^.edit_rejected = true
        return false
    }
    text := string(target.bytes[:target.length^])
    first := min(state^.anchor_byte, state^.cursor_byte)
    last := max(state^.anchor_byte, state^.cursor_byte)
    if first == last {
        if backwards {
            first = input_box_previous_boundary(text, first)
        } else {
            last = input_box_next_boundary(text, last)
        }
    }
    return input_box_replace_range(state, target, {
        first = first,
        last = last,
    }, "", result)
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
                state, target, false, result) || result^.changed
        }
    } else if event.key == .V {
        result^.changed = input_box_replace_selection(
            state, target, clipboard_text, result) || result^.changed
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
            state, target, string(encoded[:count]), result) || result^.changed
        return
    }
    if event.kind == .Text_Preedit {
        input_box_update_preedit(state, target, event)
        return
    }
    if event.kind == .Text_Cancel {
        input_box_clear_preedit(state)
        return
    }
    if event.kind == .Text_Commit {
        input_box_apply_commit_event(state, target, event, result)
        return
    }
    if event.kind != .Press && event.kind != .Repeat {
        return
    }
    input_box_apply_key_edit(
        state, target, event, clipboard_text, result)
}

// input_box_apply_commit_event replaces the active selection atomically.
input_box_apply_commit_event :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event, result: ^Input_Box_Update) {
    if int(event.text_length) > len(event.text) {
        result^.edit_rejected = true
        return
    }
    payload := event
    replacement := input.input_event_text_payload(&payload)
    range: Input_Box_Edit_Range = {
        first = min(state^.anchor_byte, state^.cursor_byte),
        last = max(state^.anchor_byte, state^.cursor_byte),
    }
    if state^.preedit_active {
        if state^.preedit_content_revision != state^.content_revision {
            result^.edit_rejected = true
            input_box_clear_preedit(state)
            return
        }
        range = {state^.preedit_replace_start, state^.preedit_replace_end}
    }
    input_box_clear_preedit(state)
    result^.changed = input_box_replace_range(
        state, target, range, replacement, result) || result^.changed
}

// input_box_apply_key_edit applies one ordinary editable keyboard event.
input_box_apply_key_edit :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event, clipboard_text: string,
    result: ^Input_Box_Update) {
    control := .Control in event.modifiers
    if control && input_box_apply_edit_control(
        state, target, event, clipboard_text, result) {
        return
    }
    if control {
        return
    }
    if event.key == .Backspace || event.key == .Delete {
        result^.changed = input_box_delete_selection(
            state, target, event.key == .Backspace, result) || result^.changed
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

// input_box_clear_preedit discards composition without changing committed text.
input_box_clear_preedit :: proc(state: ^viewmodel.Ui_Input_Box_State) {
    if state == nil {
        return
    }
    state^.preedit_active = false
    state^.preedit_length = 0
}

// input_box_preedit_byte_offset maps an SDL codepoint offset into UTF-8 storage.
input_box_preedit_byte_offset :: proc(text: string, codepoints: int) -> int {
    if codepoints <= 0 {
        return 0
    }
    offset, remaining := 0, codepoints
    for offset < len(text) && remaining > 0 {
        _, width := utf8.decode_rune(text[offset:])
        offset += width
        remaining -= 1
    }
    return offset
}

// input_box_update_preedit retains one bounded composition snapshot separately.
input_box_update_preedit :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event) {
    payload := event
    if state == nil || target.length == nil ||
        int(event.text_length) > len(state^.preedit) ||
        !utf8.valid_string(input.input_event_text_payload(&payload)) {
        return
    }
    if event.text_length == 0 {
        input_box_clear_preedit(state)
        return
    }
    if !state^.preedit_active {
        state^.preedit_replace_start = min(state^.anchor_byte, state^.cursor_byte)
        state^.preedit_replace_end = max(state^.anchor_byte, state^.cursor_byte)
        state^.preedit_content_revision = state^.content_revision
        state^.preedit_active = true
    }
    preedit_text := input.input_event_text_payload(&payload)
    copy(state^.preedit[:len(preedit_text)], transmute([]u8)preedit_text)
    state^.preedit_length = int(event.text_length)
    preedit := string(state^.preedit[:state^.preedit_length])
    rune_count := utf8.rune_count(preedit)
    start_codepoint := clamp(int(event.preedit_start), 0, rune_count)
    selection_count := clamp(
        int(event.preedit_length), 0, rune_count - start_codepoint)
    start := input_box_clamp_boundary(
        preedit, input_box_preedit_byte_offset(preedit, start_codepoint))
    end_offset := input_box_preedit_byte_offset(
        preedit, start_codepoint + selection_count)
    end := input_box_clamp_boundary(preedit, end_offset)
    state^.preedit_selection_start = start
    state^.preedit_selection_end = end
}

// input_box_apply_edit_keyboard mutates caller-owned text from one ordered frame.
input_box_apply_edit_keyboard :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    frame: input.Input_Frame, clipboard_text: string = "",
    policy: Input_Box_Edit_Policy = {}) -> Input_Box_Update {
    result: Input_Box_Update
    if state == nil || target.length == nil {
        return result
    }
    for event in frame.events {
        composing := state^.preedit_active
        if input.input_event_composition_owns_key(event, &composing) {
            continue
        }
        if input_box_apply_completion_event(state, target, event, policy, &result) {
            continue
        }
        input_box_apply_edit_event(
            state, target, event, clipboard_text, &result)
    }
    return result
}

// input_box_frame_requests_paste reports whether one frame contains Ctrl+V.
input_box_frame_requests_paste :: proc(frame: input.Input_Frame) -> bool {
    for event in frame.events {
        if (event.kind == .Press || event.kind == .Repeat) &&
            event.key == .V && .Control in event.modifiers {
            return true
        }
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
    policy := params.edit_policy
    policy.unicode_completion = input_box_unicode_enabled(params)
    filtered_events: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    filtered_count := 0
    target_id := params.text_input_id if params.text_input_id != 0 else
        int(params.descriptor.id.local_id)
    for event in params.frame.events {
        if event.kind == .Text || event.kind == .Text_Commit ||
            event.kind == .Text_Preedit || event.kind == .Text_Cancel {
            target := event.text_target
            if target.kind != .None &&
                (target.kind != .Input_Box ||
                 target.id != target_id) {
                continue
            }
        }
        filtered_events[filtered_count] = event
        filtered_count += 1
    }
    routed_frame := params.frame
    routed_frame.events = filtered_events[:filtered_count]
    update := input_box_apply_edit_keyboard(
        params.state, params.edit_target, routed_frame, clipboard_text, policy)
    resolved^.descriptor.text = string(
        params.edit_target.bytes[:params.edit_target.length^])
    return update
}

// input_box_copy_focused_selection publishes one bounded copy result.
input_box_copy_focused_selection :: proc(
    params: Input_Box_Params, update: ^Input_Box_Update) {
    if !update^.copy_requested {
        return
    }
    copied := params.descriptor.text[update^.copy_start:update^.copy_end]
    if update^.copied_length > 0 {
        copied = string(update^.copied_bytes[:update^.copied_length])
    }
    input.input_set_clipboard_text(copied)
}

// input_box_merge_focused_update combines ordered keyboard results with semantic edits.
input_box_merge_focused_update :: proc(
    update: ^Input_Box_Update, focused: Input_Box_Update) {
    update^.changed = update^.changed || focused.changed
    update^.edit_rejected = update^.edit_rejected || focused.edit_rejected
    update^.submit_requested = focused.submit_requested
    update^.tab_requested = focused.tab_requested
    update^.suggestion_accepted = focused.suggestion_accepted
    if focused.copy_requested {
        update^.copy_start = focused.copy_start
        update^.copy_end = focused.copy_end
        update^.copy_requested = true
        update^.copied_length = focused.copied_length
        update^.copied_bytes = focused.copied_bytes
    }
}

// input_box_apply_semantic_text consumes copied native edits through owner storage.
input_box_apply_semantic_text :: proc(
    params: Input_Box_Params, resolved: ^Input_Box_Params,
    update: ^Input_Box_Update) -> bool {
    if params.semantic_focus == nil || params.edit_target.length == nil ||
       params.descriptor.mode != .Editable {
        return false
    }
    changed := false
    commands := params.semantic_focus^.commands[:params.semantic_focus^.command_count]
    for &command in commands {
        if command.target != params.descriptor.id {
            continue
        }
        text := string(params.edit_target.bytes[:params.edit_target.length^])
        if command.kind == .Set_Text_Selection {
            params.state^.anchor_byte = input_box_column_boundary(
                text, int(command.selection_anchor))
            params.state^.cursor_byte = input_box_column_boundary(
                text, int(command.selection_focus))
        } else if command.kind == .Replace_Selected_Text ||
                  command.kind == .Replace_Text {
            replacement := string(command.payload[:command.payload_length])
            if command.kind == .Replace_Text {
                changed = input_box_replace_range(params.state, params.edit_target, {
                    first = 0,
                    last = len(text),
                }, replacement, update) || changed
            } else {
                changed = input_box_replace_selection(
                    params.state, params.edit_target, replacement, update) || changed
            }
        }
    }
    resolved^.descriptor.text = string(
        params.edit_target.bytes[:params.edit_target.length^])
    return changed
}

// input_box_hit_boundary maps one screen x coordinate to a borrowed-text boundary.
input_box_hit_boundary :: proc(params: Input_Box_Params, x: f32) -> int {
    if params.column_advance <= 0 {
        return 0
    }
    local_x := x - params.rect.x - input_box_text_inset(params) +
        params.state^.scroll_x
    column := int(max(f32(0), local_x) / params.column_advance + 0.5)
    return input_box_column_boundary(params.descriptor.text, column)
}

// input_box_run_kind classifies a codepoint into a word, space, or punctuation run.
input_box_run_kind :: proc(
    text: string, offset: int) -> Input_Box_Run_Kind {

    value, _ := utf8.decode_rune_in_string(text[offset:])
    if value == '_' || unicode.is_letter(value) || unicode.is_digit(value) {
        return .Word
    }
    if unicode.is_space(value) {
        return .Whitespace
    }
    return .Punctuation
}

// input_box_select_run selects the homogeneous UTF-8 run containing one codepoint.
input_box_select_run :: proc(
    state: ^viewmodel.Ui_Input_Box_State, text: string,
    offset: int) {

    if len(text) == 0 {
        state^.anchor_byte = 0
        state^.cursor_byte = 0
        return
    }
    first := input_box_clamp_boundary(text, offset)
    if first == len(text) {
        first = input_box_previous_boundary(text, first)
    }
    kind := input_box_run_kind(text, first)
    last := input_box_next_boundary(text, first)
    for first > 0 {
        previous := input_box_previous_boundary(text, first)
        if input_box_run_kind(text, previous) != kind {
            break
        }
        first = previous
    }
    for last < len(text) && input_box_run_kind(text, last) == kind {
        last = input_box_next_boundary(text, last)
    }
    state^.anchor_byte = first
    state^.cursor_byte = last
}

// input_box_begin_selection resolves an admitted click without changing single-hit rounding.
input_box_begin_selection :: proc(params: Input_Box_Params) {
    state := params.state
    clicks := params.frame.mouse_left_clicks
    state^.fixed_selection = clicks >= 2
    state^.dragging = true
    if clicks >= 3 {
        state^.anchor_byte = 0
        state^.cursor_byte = len(params.descriptor.text)
    } else if clicks == 2 {
        local_x := params.frame.mouse_position.x - params.rect.x -
            input_box_text_inset(params) + state^.scroll_x
        column := 0
        if params.column_advance > 0 {
            column = int(max(f32(0), local_x) / params.column_advance)
        }
        input_box_select_run(state, params.descriptor.text,
            input_box_column_boundary(params.descriptor.text, column))
    } else {
        state^.cursor_byte = input_box_hit_boundary(
            params, params.frame.mouse_position.x)
        state^.anchor_byte = state^.cursor_byte
    }
}

// input_box_update_pointer captures character drags or fixed multi-click selections.
input_box_update_pointer :: proc(
    params: Input_Box_Params, hovered: bool,
    owner: ^viewmodel.Ui_Press_Owner_State) {
    press_id := int(params.descriptor.id.local_id)
    owns := owner^.active && owner^.kind == .Input_Box && owner^.id == press_id
    if params.pointer_routed && hovered && input_frame_left_pressed(params.frame) &&
        !owner^.active {
        owner^ = {
            active = true,
            kind = .Input_Box,
            id = press_id,
        }
        input_box_begin_selection(params)
        owns = true
    }
    if owns && input_frame_left_down(params.frame) && !params.state^.fixed_selection {
        params.state^.cursor_byte = input_box_hit_boundary(
            params, params.frame.mouse_position.x)
    }
    if owns && input_frame_left_released(params.frame) {
        if !params.state^.fixed_selection {
            params.state^.cursor_byte = input_box_hit_boundary(
                params, params.frame.mouse_position.x)
        }
        params.state^.dragging = false
        params.state^.fixed_selection = false
        owner^ = {}
    }
}

// input_box_reveal_cursor clamps horizontal scrolling around the active caret.
input_box_reveal_cursor :: proc(
    params: Input_Box_Params, align_end: bool) {
    inset := input_box_text_inset(params)
    visible_width := max(f32(0), params.rect.width - inset * 2)
    text := params.descriptor.text
    if input_box_unicode_enabled(params) &&
        len(input_box_unicode_candidate(params.state, text).text) > 0 {
        visible_width -= params.column_advance * 4
    }
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

// input_box_prepare applies routed edits and publishes current text and draw geometry.
input_box_prepare :: proc(
    params: Input_Box_Params,
    owner: ^viewmodel.Ui_Press_Owner_State) -> Input_Box_Result {
    resolved := params
    changed := input_box_reconcile_content(
        params.state, params.descriptor.text, params.descriptor.content_revision)
    if !params.focused {
        input_box_clear_preedit(params.state)
    }
    update: Input_Box_Update
    semantic_changed := input_box_apply_semantic_text(
        params, &resolved, &update)
    if semantic_changed {
        resolved.edit_policy.end_suggestion = ""
    }
    hovered := geometry.rectangle_contains(params.rect,
        {params.frame.mouse_position.x, params.frame.mouse_position.y})
    input_box_update_pointer(resolved, hovered, owner)
    if params.focused {
        focused_update := input_box_apply_focused_input(resolved, &resolved)
        input_box_copy_focused_selection(resolved, &focused_update)
        input_box_merge_focused_update(&update, focused_update)
    }
    input_box_reveal_cursor(resolved, changed)
    result := input_box_draw_result(resolved, hovered)
    result.changed = update.changed || semantic_changed
    result.edit_rejected = update.edit_rejected
    result.submit_requested = update.submit_requested
    result.tab_requested = update.tab_requested
    result.suggestion_accepted = update.suggestion_accepted
    if !params.defer_semantics {
        input_box_publish_semantics(resolved, owner, &result)
    }
    return result
}

// input_box_publish_prepared_semantics publishes a control after its parent nodes exist.
input_box_publish_prepared_semantics :: proc(
    params: Input_Box_Params, owner: ^viewmodel.Ui_Press_Owner_State,
    result: ^Input_Box_Result) {
    input_box_publish_semantics(params, owner, result)
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
    inset := input_box_text_inset(params)
    inner.x += inset
    inner.width = max(f32(0), inner.width - inset * 2)
    candidate: Unicode_Completion
    if input_box_unicode_enabled(params) {
        candidate = input_box_unicode_candidate(params.state, params.descriptor.text)
        if len(candidate.text) > 0 {
            inner.width -= params.column_advance * 4
        }
    }
    descriptor := input_box_result_descriptor(params)
    text_geometry := input_box_text_geometry(params, inner, descriptor)
    caret := text_geometry.caret
    return {
        hovered = hovered,
        focused = params.focused,
        control_geometry = text_geometry.control,
        descriptor = descriptor,
        text_geometry = text_geometry,
        inner = inner,
        text_x = inner.x - params.state^.scroll_x,
        selection = text_geometry.selection,
        caret = caret,
        unicode_completion = candidate,
        unicode_hint = {
            caret.x + params.column_advance * 0.5,
            caret.y,
            params.column_advance * 3,
            caret.height,
        },
    }
}

// input_box_text_geometry projects one UTF-8 selection into scrolled cell geometry.
input_box_text_geometry :: proc(
    params: Input_Box_Params, inner: geometry.Rectangle,
    descriptor: viewmodel.Ui_Editable_Text_Descriptor) ->
        viewmodel.Ui_Editable_Text_Geometry {
    cursor := input_box_byte_column(descriptor.text, descriptor.cursor_byte)
    anchor := input_box_byte_column(descriptor.text, descriptor.anchor_byte)
    start_x := f32(min(cursor, anchor)) * params.column_advance
    width := f32(abs(cursor - anchor)) * params.column_advance
    font_size := theme.TREE_FONT_SIZE if params.font_size <= 0 else params.font_size
    text_y := params.rect.y + (params.rect.height - font_size) * 0.5
    return {
        control = {params.rect, params.clip_rect},
        caret = {
            inner.x + f32(cursor) * params.column_advance - params.state^.scroll_x,
            text_y,
            1,
            font_size,
        },
        selection = {
            inner.x + start_x - params.state^.scroll_x,
            text_y,
            width,
            font_size,
        },
        cursor_column = cursor,
        anchor_column = anchor,
    }
}

// Publish one semantic text-run child beneath its editable input control.
input_box_publish_text_run :: proc(
    params: Input_Box_Params, descriptor: viewmodel.Ui_Editable_Text_Descriptor,
    result: Input_Box_Result) {
    if descriptor.text_run_id == (viewmodel.Ui_Node_Id{}) {
        return
    }
    _ = uisemantics.semantic_register_control(params.semantic_focus, {
        id = descriptor.text_run_id,
        parent = descriptor.id,
        role = .Text_Run,
        states = {.Visible, .Enabled},
        region = descriptor.region,
        traversal_order = descriptor.traversal_order,
        bounds = result.inner,
        clip_bounds = result.text_geometry.control.clip_bounds,
        value = descriptor.text,
        text_present = true,
    })
}

// input_box_publish_semantics registers prepared text state and pointer focus.
input_box_publish_semantics :: proc(
    params: Input_Box_Params, owner: ^viewmodel.Ui_Press_Owner_State,
    result: ^Input_Box_Result) {
    descriptor := result^.descriptor
    if params.semantic_focus == nil || descriptor.id == {} {
        return
    }
    states: viewmodel.Ui_Node_State = {.Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.mode == .Read_Only {
        states += {.Read_Only}
    }
    _ = uisemantics.semantic_register_control(params.semantic_focus, {
        id = descriptor.id,
        parent = descriptor.parent,
        controls = params.controls,
        role = .Input,
        states = states,
        actions = {.Focus, .Replace_Selected_Text, .Set_Text_Selection},
        region = descriptor.region,
        traversal_order = descriptor.traversal_order,
        bounds = result^.text_geometry.control.bounds,
        clip_bounds = result^.text_geometry.control.clip_bounds,
        text_input_area = result^.caret,
        label = descriptor.label,
        value = descriptor.text,
        placeholder = descriptor.placeholder,
        text_cursor_byte = descriptor.cursor_byte,
        text_anchor_byte = descriptor.anchor_byte,
        text_present = true,
    })
    input_box_publish_text_run(params, descriptor, result^)
    _ = uisemantics.semantic_focus_for_press(params.semantic_focus, owner, .Input_Box,
        int(descriptor.id.local_id), descriptor.id)
}

// draw_encoded_input_box renders prepared text, selection, caret, and completion.
draw_encoded_input_box :: proc(
    encoder: ^native.Draw_Encoder,
    params: Input_Box_Params, prepared: Input_Box_Result) {
    _ = native.draw_encoder_rectangle(
        encoder, prepared.control_geometry.bounds, theme.UI_COMPONENT_BACKGROUND_COLOR)
    border := theme.draw_color(encoder, .Control_Border)
    if prepared.focused {
        border = theme.draw_color(encoder, .Text)
    }
    if prepared.edit_rejected {
        border = theme.draw_color(encoder, .Error_Text)
    }
    _ = native.draw_encoder_rectangle_outline(
        encoder, prepared.control_geometry.bounds,
        f32(1) if params.control_scale <= 0 else params.control_scale, border)
    _ = native.draw_encoder_push_scissor(encoder, prepared.inner)
    if prepared.selection.width > 0 {
        _ = native.draw_encoder_rectangle(
            encoder, prepared.selection,
            theme.draw_color(encoder, .Selection_Background))
    }
    draw_encoded_input_box_text(encoder, params, prepared)
    draw_encoded_input_box_preedit(encoder, params, prepared)
    draw_encoded_input_box_caret(encoder, prepared)
    _ = native.draw_encoder_pop_scissor(encoder)
    draw_encoded_input_box_completion(encoder, params, prepared)
}

// draw_encoded_input_box_preedit presents composition without committing its bytes.
draw_encoded_input_box_preedit :: proc(
    encoder: ^native.Draw_Encoder, params: Input_Box_Params,
    prepared: Input_Box_Result) {
    state := params.state
    if state == nil || !state^.preedit_active || state^.preedit_length <= 0 {
        return
    }
    x := input_box_preedit_x(encoder, params, prepared)
    preedit := string(state^.preedit[:state^.preedit_length])
    width := f32(input_box_byte_column(preedit, len(preedit))) *
        params.column_advance
    _ = viewtext.ui_text_shaped({
        encoder = encoder,
        resolver = params.resolver,
        key = .Regular,
        text = preedit,
        position = {x, prepared.caret.y},
        color = theme.draw_color(encoder, .Text),
        font = viewtext.ui_text_font(params.font,
            encoder^.ui_text_size_percent if encoder != nil else 100),
    })
    input_box_draw_preedit_selection(
        encoder, params, prepared, preedit, x)
    if width > 0 {
        _ = native.draw_encoder_rectangle(encoder,
            {x, prepared.caret.y + prepared.caret.height - 1, width, 1},
            theme.draw_color(encoder, .Text))
    }
}

// input_box_preedit_x masks the captured replacement and returns its display x.
input_box_preedit_x :: proc(
    encoder: ^native.Draw_Encoder, params: Input_Box_Params,
    prepared: Input_Box_Result) -> f32 {
    state := params.state
    source := params.descriptor.text
    start := input_box_clamp_boundary(source, state^.preedit_replace_start)
    end := input_box_clamp_boundary(source, state^.preedit_replace_end)
    x := prepared.text_x + f32(input_box_byte_column(source, start)) *
        params.column_advance
    replacement_width := f32(input_box_byte_column(source, end) -
        input_box_byte_column(source, start)) * params.column_advance
    if replacement_width > 0 {
        _ = native.draw_encoder_rectangle(encoder, {
            x,
            prepared.caret.y,
            replacement_width,
            prepared.caret.height,
        }, theme.UI_COMPONENT_BACKGROUND_COLOR)
    }
    return x
}

// input_box_draw_preedit_selection highlights SDL's selected preedit segment.
input_box_draw_preedit_selection :: proc(
    encoder: ^native.Draw_Encoder, params: Input_Box_Params,
    prepared: Input_Box_Result, preedit: string, x: f32) {
    state := params.state
    selection_start := input_box_byte_column(
        preedit, state^.preedit_selection_start)
    selection_end := input_box_byte_column(
        preedit, state^.preedit_selection_end)
    if selection_end <= selection_start {
        return
    }
    selection_text := preedit[
        state^.preedit_selection_start:state^.preedit_selection_end]
    selection_x := x + f32(selection_start) * params.column_advance
    selection_bounds: geometry.Rectangle = {
        selection_x,
        prepared.caret.y,
        f32(selection_end - selection_start) * params.column_advance,
        prepared.caret.height,
    }
    _ = native.draw_encoder_rectangle(
        encoder, selection_bounds, theme.draw_color(encoder, .Selection_Background))
    _ = native.draw_encoder_push_scissor(encoder, selection_bounds)
    _ = viewtext.ui_text_shaped({
        encoder = encoder,
        resolver = params.resolver,
        key = .Regular,
        text = selection_text,
        position = {selection_x, prepared.caret.y},
        color = theme.draw_color(encoder, .Selection_Text),
        font = viewtext.ui_text_font(params.font,
            encoder^.ui_text_size_percent if encoder != nil else 100),
    })
    _ = native.draw_encoder_pop_scissor(encoder)
}

// draw_encoded_input_box_text clips full shaped runs so selection never changes glyph layout.
draw_encoded_input_box_text :: proc(
    encoder: ^native.Draw_Encoder,
    params: Input_Box_Params, prepared: Input_Box_Result) {
    request: viewtext.Shaped_Text_Draw = {
        encoder = encoder,
        resolver = params.resolver,
        key = .Regular,
        text = params.descriptor.text,
        position = {prepared.text_x, prepared.caret.y},
        color = theme.draw_color(encoder, .Text),
        font = viewtext.ui_text_font(params.font,
            encoder^.ui_text_size_percent if encoder != nil else 100),
    }
    if prepared.selection.width <= 0 {
        _ = viewtext.ui_text_shaped(request)
        return
    }
    left, right := prepared.inner, prepared.inner
    left.width = max(0, min(prepared.selection.x, left.x + left.width) - left.x)
    right.x = max(right.x, prepared.selection.x + prepared.selection.width)
    right.width = max(0, prepared.inner.x + prepared.inner.width - right.x)
    clips: [3]geometry.Rectangle = {left, right, prepared.selection}
    for clip, index in clips {
        if clip.width <= 0 {
            continue
        }
        request.color =
            theme.draw_color(encoder, .Selection_Text) if index == 2 else
                theme.draw_color(encoder, .Text)
        _ = native.draw_encoder_push_scissor(encoder, clip)
        _ = viewtext.ui_text_shaped(request)
        _ = native.draw_encoder_pop_scissor(encoder)
    }
}

// draw_encoded_input_box_caret contrasts each caret fragment with its selected or plain backing.
draw_encoded_input_box_caret :: proc(
    encoder: ^native.Draw_Encoder, prepared: Input_Box_Result) {
    if !prepared.focused {
        return
    }
    _ = native.draw_encoder_rectangle(
        encoder, prepared.caret, theme.draw_color(encoder, .Text))
    if prepared.selection.width > 0 {
        _ = native.draw_encoder_push_scissor(encoder, prepared.selection)
        _ = native.draw_encoder_rectangle(
            encoder, prepared.caret, theme.draw_color(encoder, .Selection_Text))
        _ = native.draw_encoder_pop_scissor(encoder)
    }
}

// draw_encoded_input_box_completion borrows the regular text path for the inline hint.
draw_encoded_input_box_completion :: proc(
    encoder: ^native.Draw_Encoder, params: Input_Box_Params,
    prepared: Input_Box_Result) {
    if len(prepared.unicode_completion.text) == 0 {
        return
    }
    bytes: [12]u8
    count := copy(bytes[:], prepared.unicode_completion.text)
    count += copy(bytes[count:], " \u2192")
    _ = native.draw_encoder_push_scissor(encoder, prepared.control_geometry.bounds)
    _ = viewtext.ui_text_shaped({
        encoder = encoder,
        resolver = params.resolver,
        key = .Regular,
        text = string(bytes[:count]),
        position = {prepared.unicode_hint.x, prepared.unicode_hint.y},
        color = theme.draw_color(encoder, .Text),
        font = viewtext.ui_text_font(params.font,
            encoder^.ui_text_size_percent if encoder != nil else 100),
    })
    _ = native.draw_encoder_pop_scissor(encoder)
}