package ui_dynview

import "../../../core"
import dyncore "../../../dynview/core"
import dynlayout "../../../dynview/layout"
import "../../input"

import "core:math"
import "core:strings"

import rl "vendor:raylib"

DYNVIEW_SELECTION_COLOR :: rl.Color{86, 105, 122, 150}

// Group one presentation viewport and its fallback typography for selection.
Dynview_Selection_View :: struct {
    panel: rl.Rectangle,
    scroll_y: f32,
    text_padding: f32,
    row_height: f32,
    wrap_advance: f32,
    fallback_text: string,
}

// Group one selection mode with its current ordered unit count and revision.
Dynview_Selection_Content :: struct {
    mode: core.Dynview_Selection_Mode,
    revision: u64,
    unit_count: int,
}

// Group mutable owners and frame data for one pointer-selection update.
Dynview_Selection_Update :: struct {
    runtime: ^core.Dynview_System,
    selection: ^core.Dynview_Selection_State,
    press_owner: ^core.Ui_Press_Owner_State,
    content: Dynview_Selection_Content,
    view: Dynview_Selection_View,
    frame: input.Input_Frame,
}

// Append authored separation between two selected semantic document targets.
dynview_document_write_separator :: proc(
    builder: ^strings.Builder,
    separator: core.Dynview_Document_Selection_Separator) {

    switch separator {
    case .Line:
        strings.write_byte(builder, '\n')
    case .Block:
        strings.write_string(builder, "\n\n")
    case .None:
    }
}

// Return ordered half-open unit boundaries for one selection anchor and head.
dynview_selection_ordered :: proc(
    anchor, head: core.Dynview_Selection_Position) -> (
        core.Dynview_Selection_Position, core.Dynview_Selection_Position) {

    if anchor.unit_index <= head.unit_index {
        return anchor, head
    }
    return head, anchor
}

// Compose selected semantic-document targets from sealed canonical and source bytes.
dynview_document_selection_text :: proc(
    text: []u8,
    targets: []core.Dynview_Document_Layout_Copy_Target,
    anchor, head: core.Dynview_Selection_Position) -> string {

    start, end := dynview_selection_ordered(anchor, head)
    if start.unit_index < 0 || end.unit_index > len(targets) ||
        start.unit_index >= end.unit_index {
        return ""
    }

    builder := strings.builder_make(context.temp_allocator)
    for target, relative_index in targets[start.unit_index:end.unit_index] {
        if target.offset < 0 || target.count < 0 ||
            target.count > len(text)-target.offset {
            return ""
        }
        if relative_index > 0 {
            dynview_document_write_separator(&builder, target.separator_before)
        }
        strings.write_string(&builder,
            string(text[target.offset:target.offset+target.count]))
    }
    return strings.to_string(builder)
}

// Resolve the selectable model currently rendered by one presentation runtime.
dynview_selection_content :: proc(
    runtime: ^core.Dynview_System,
    fallback_text: string) -> Dynview_Selection_Content {

    if runtime == nil {
        return {.Wrapped_Text, 0,
            dyncore.text_codepoint_count_span(fallback_text, 0, len(fallback_text))}
    }
    revision := runtime^.content.revision
    if dynlayout.document_layout_is_authoritative(runtime) {
        return {.Semantic_Document, revision,
            len(runtime^.compile_cache.document_layout_copy_targets)}
    }
    if runtime^.content.presentation_mime == .Text_Plain {
        return {.Wrapped_Text, revision,
            dyncore.text_codepoint_count_span(fallback_text, 0, len(fallback_text))}
    }
    if runtime^.enabled && runtime^.cache_access_state == .Display_Readable &&
        runtime^.compile_cache.is_valid && !runtime^.command_buffer.has_stream_error &&
        len(runtime^.content.presentation_bytes) > 0 {
        return {.Atomic_Source, revision, 1}
    }
    return {.Wrapped_Text, revision,
        dyncore.text_codepoint_count_span(fallback_text, 0, len(fallback_text))}
}

// Clear one display-owned presentation selection and its press-independent state.
dynview_selection_clear :: proc(selection: ^core.Dynview_Selection_State) {
    if selection != nil {
        selection^ = {}
    }
}

// Reconcile stored logical positions with the currently rendered presentation.
dynview_selection_reconcile :: proc(
    selection: ^core.Dynview_Selection_State,
    content: Dynview_Selection_Content) {

    if selection^.mode != content.mode || selection^.revision != content.revision ||
        selection^.anchor.unit_index < 0 || selection^.head.unit_index < 0 ||
        selection^.anchor.unit_index > content.unit_count ||
        selection^.head.unit_index > content.unit_count {
        dynview_selection_clear(selection)
        selection^.mode = content.mode
        selection^.revision = content.revision
    }
}

// Return the screen-space rectangle for one semantic document selection target.
dynview_document_target_rect :: #force_inline proc(
    target: core.Dynview_Document_Layout_Copy_Target,
    view: Dynview_Selection_View) -> rl.Rectangle {

    return {
        view.panel.x+view.text_padding+target.x,
        view.panel.y+view.text_padding-view.scroll_y+target.y,
        target.width,
        target.height,
    }
}

// Return squared distance from one point to the nearest point in a rectangle.
dynview_selection_rect_distance_squared :: #force_inline proc(
    point: rl.Vector2, rect: rl.Rectangle) -> f32 {

    dx := max(rect.x-point.x, max(point.x-(rect.x+rect.width), 0))
    dy := max(rect.y-point.y, max(point.y-(rect.y+rect.height), 0))
    return dx*dx+dy*dy
}

// Resolve the nearest semantic target boundary to one screen-space pointer.
dynview_document_hit_boundary :: proc(
    targets: []core.Dynview_Document_Layout_Copy_Target,
    view: Dynview_Selection_View,
    point: rl.Vector2) -> core.Dynview_Selection_Position {

    if len(targets) == 0 {return {}}
    nearest := 0
    nearest_distance := dynview_selection_rect_distance_squared(
        point, dynview_document_target_rect(targets[0], view))
    for target, index in targets[1:] {
        rect := dynview_document_target_rect(target, view)
        distance := dynview_selection_rect_distance_squared(point, rect)
        if distance < nearest_distance {
            nearest, nearest_distance = index+1, distance
        }
    }
    rect := dynview_document_target_rect(targets[nearest], view)
    boundary := nearest
    if point.x >= rect.x+rect.width*0.5 {boundary += 1}
    return {unit_index = boundary}
}

// Return the byte boundary after a requested number of UTF-8 codepoints.
dynview_text_byte_boundary :: proc(text: string, unit_index: int) -> int {
    if unit_index <= 0 {return 0}
    units := 0
    for offset := 0; offset < len(text); {
        if units == unit_index {return offset}
        offset += max(1, dyncore.text_utf8_sequence_len(text, offset))
        units += 1
    }
    return len(text)
}

// Resolve a wrapped fallback pointer to its nearest UTF-8 codepoint boundary.
dynview_wrapped_hit_boundary :: proc(
    text: string,
    view: Dynview_Selection_View,
    point: rl.Vector2) -> core.Dynview_Selection_Position {

    max_chars := dyncore.chars_per_text_row(
        view.panel.width-view.text_padding*2, view.wrap_advance)
    target_row := max(0, int((point.y-view.panel.y-view.text_padding+
        view.scroll_y)/view.row_height))
    start, row := 0, 0
    for start < len(text) {
        span := dyncore.next_wrapped_text_span(text, start, max_chars)
        if row == target_row || span.next_start <= start {
            row_units := dyncore.text_codepoint_count_span(
                text, span.line_start, span.line_end)
            column := int((point.x-view.panel.x-view.text_padding+
                view.wrap_advance*0.5)/view.wrap_advance)
            byte_offset := span.line_start
            for _ in 0..<math.clamp(column, 0, row_units) {
                byte_offset += max(1, dyncore.text_utf8_sequence_len(text, byte_offset))
            }
            return {unit_index = dyncore.text_codepoint_count_span(
                text, 0, byte_offset)}
        }
        start, row = span.next_start, row+1
    }
    return {unit_index = dyncore.text_codepoint_count_span(text, 0, len(text))}
}

// Resolve one pointer to the current presentation mode's nearest logical boundary.
dynview_selection_hit_boundary :: proc(
    runtime: ^core.Dynview_System,
    content: Dynview_Selection_Content,
    view: Dynview_Selection_View,
    point: rl.Vector2) -> core.Dynview_Selection_Position {

    switch content.mode {
    case .Semantic_Document:
        return dynview_document_hit_boundary(
            runtime^.compile_cache.document_layout_copy_targets, view, point)
    case .Atomic_Source:
        rect, ok := dynview_atomic_selection_rect(runtime, view)
        if !ok {return {}}
        return {unit_index = point.x >= rect.x+rect.width*0.5 ? 1 : 0}
    case .Wrapped_Text:
        return dynview_wrapped_hit_boundary(view.fallback_text, view, point)
    case .None:
        return {}
    }
    return {}
}

// Report whether a pointer press belongs to the existing exact-source icon.
dynview_selection_hits_copy_icon :: proc(
    runtime: ^core.Dynview_System, point: rl.Vector2) -> bool {
    if runtime == nil {return false}
    for target in runtime^.compile_cache.copy_hit_targets {
        if rl.CheckCollisionPointRec(point, target.rect) {return true}
    }
    return false
}

// Return whether the shared press owner belongs to Dynview selection.
dynview_selection_owns_press :: #force_inline proc(
    owner: ^core.Ui_Press_Owner_State) -> bool {
    return owner^.active && owner^.kind == .Dynview_Selection
}

// Advance mouse selection while respecting shared panel press ownership.
dynview_selection_update_mouse :: proc(
    update: Dynview_Selection_Update) {

    runtime, selection := update.runtime, update.selection
    owner, content := update.press_owner, update.content
    view, frame := update.view, update.frame
    point := rl.Vector2{frame.mouse_position.x, frame.mouse_position.y}
    if .Left in frame.mouse_pressed && !owner^.active && content.unit_count > 0 &&
        rl.CheckCollisionPointRec(point, view.panel) &&
        !dynview_selection_hits_copy_icon(runtime, point) {
        position := dynview_selection_hit_boundary(runtime, content, view, point)
        selection^.anchor, selection^.head = position, position
        selection^.active, selection^.dragging = false, true
        owner^ = {active = true, kind = .Dynview_Selection, id = 1001}
    }
    if !dynview_selection_owns_press(owner) {return}
    selection^.head = dynview_selection_hit_boundary(runtime, content, view, point)
    if .Left in frame.mouse_released || .Left not_in frame.mouse_down {
        selection^.active = selection^.anchor != selection^.head
        selection^.dragging = false
        owner^ = {id = -1}
    }
}

// Select every logical unit or copy the active selection for keyboard chords.
dynview_selection_update_keyboard :: proc(
    runtime: ^core.Dynview_System,
    selection: ^core.Dynview_Selection_State,
    content: Dynview_Selection_Content,
    fallback_text: string,
    frame: input.Input_Frame) {

    if input.input_chord_pressed(frame, .A, {.Control}) && content.unit_count > 0 {
        selection^.anchor = {unit_index = 0}
        selection^.head = {unit_index = content.unit_count}
        selection^.active = true
    }
    if !selection^.active || !input.input_chord_pressed(frame, .C, {.Control}) {
        return
    }
    selected := dynview_selection_text(runtime, selection^, fallback_text)
    if len(selected) > 0 {input.input_set_clipboard_text(selected)}
}

// Compose one active selection according to its presentation mode.
dynview_selection_text :: proc(
    runtime: ^core.Dynview_System,
    selection: core.Dynview_Selection_State,
    fallback_text: string) -> string {

    if !selection.active {return ""}
    start, end := dynview_selection_ordered(selection.anchor, selection.head)
    switch selection.mode {
    case .Semantic_Document:
        return dynview_document_selection_text(runtime^.content.document_text,
            runtime^.compile_cache.document_layout_copy_targets, start, end)
    case .Atomic_Source:
        if start.unit_index == 0 && end.unit_index == 1 {
            return string(runtime^.content.presentation_bytes)
        }
    case .Wrapped_Text:
        byte_start := dynview_text_byte_boundary(fallback_text, start.unit_index)
        byte_end := dynview_text_byte_boundary(fallback_text, end.unit_index)
        return fallback_text[byte_start:byte_end]
    case .None:
    }
    return ""
}

// Return the visible bounds occupied by the legacy standalone presentation layout.
dynview_atomic_selection_rect :: proc(
    runtime: ^core.Dynview_System,
    view: Dynview_Selection_View) -> (rl.Rectangle, bool) {

    cache := &runtime^.compile_cache
    if cache^.layout_item_count <= 0 {return {}, false}
    first := cache^.layout_items[0]
    left := view.panel.x+view.text_padding+first.content_offset_x
    top := view.panel.y+view.text_padding+
        f32(first.row_offset)*cache^.last_cell_height-view.scroll_y+
        first.content_offset_y
    right := left+max(first.draw_width, first.math_advance)
    bottom := top+max(first.draw_height,
        f32(first.row_span)*cache^.last_cell_height)
    for item in cache^.layout_items[1:cache^.layout_item_count] {
        x := view.panel.x+view.text_padding+item.content_offset_x
        y := view.panel.y+view.text_padding+
            f32(item.row_offset)*cache^.last_cell_height-view.scroll_y+
            item.content_offset_y
        left, top = min(left, x), min(top, y)
        right = max(right, x+max(item.draw_width, item.math_advance))
        bottom = max(bottom, y+max(item.draw_height,
            f32(item.row_span)*cache^.last_cell_height))
    }
    return {left, top, max(0, right-left), max(0, bottom-top)}, true
}

// Draw selected wrapped fallback codepoints one visible row at a time.
dynview_selection_draw_wrapped :: proc(
    selection: core.Dynview_Selection_State,
    view: Dynview_Selection_View) {

    start, end := dynview_selection_ordered(selection.anchor, selection.head)
    start_byte := dynview_text_byte_boundary(view.fallback_text, start.unit_index)
    end_byte := dynview_text_byte_boundary(view.fallback_text, end.unit_index)
    max_chars := dyncore.chars_per_text_row(
        view.panel.width-view.text_padding*2, view.wrap_advance)
    row_start, row := 0, 0
    for row_start < len(view.fallback_text) {
        span := dyncore.next_wrapped_text_span(view.fallback_text, row_start, max_chars)
        selected_start := max(start_byte, span.line_start)
        selected_end := min(end_byte, span.line_end)
        if selected_start < selected_end {
            x_units := dyncore.text_codepoint_count_span(
                view.fallback_text, span.line_start, selected_start)
            width_units := dyncore.text_codepoint_count_span(
                view.fallback_text, selected_start, selected_end)
            rl.DrawRectangleRec({
                view.panel.x+view.text_padding+f32(x_units)*view.wrap_advance,
                view.panel.y+view.text_padding+f32(row)*view.row_height-view.scroll_y,
                f32(width_units)*view.wrap_advance,
                view.row_height,
            }, DYNVIEW_SELECTION_COLOR)
        }
        if span.next_start <= row_start {break}
        row_start, row = span.next_start, row+1
    }
}

// Draw selected semantic targets as clipped screen-space background rectangles.
dynview_selection_draw_document :: proc(
    runtime: ^core.Dynview_System,
    selection: core.Dynview_Selection_State,
    view: Dynview_Selection_View) {

    start, end := dynview_selection_ordered(selection.anchor, selection.head)
    targets := runtime^.compile_cache.document_layout_copy_targets
    if start.unit_index < 0 || end.unit_index > len(targets) {return}
    for target in targets[start.unit_index:end.unit_index] {
        rect := dynview_document_target_rect(target, view)
        rl.DrawRectangleRec(rect, DYNVIEW_SELECTION_COLOR)
    }
}

// Draw one active selection behind the presentation content.
dynview_selection_draw :: proc(
    runtime: ^core.Dynview_System,
    selection: core.Dynview_Selection_State,
    view: Dynview_Selection_View) {

    if !selection.active && !selection.dragging {return}
    switch selection.mode {
    case .Semantic_Document:
        dynview_selection_draw_document(runtime, selection, view)
    case .Atomic_Source:
        start, end := dynview_selection_ordered(selection.anchor, selection.head)
        if start.unit_index == 0 && end.unit_index == 1 {
            rect, ok := dynview_atomic_selection_rect(runtime, view)
            if ok {rl.DrawRectangleRec(rect, DYNVIEW_SELECTION_COLOR)}
        }
    case .Wrapped_Text:
        dynview_selection_draw_wrapped(selection, view)
    case .None:
    }
}