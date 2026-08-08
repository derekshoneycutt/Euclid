package dynview

import "../core"

import rl "vendor:raylib"

//  Append a compiled byte information to the give cache
append_compiled_byte :: proc(cache: ^core.Dynview_Compile_Cache, b: u8) -> i32 {
    if cache^.compiled_plain_text_len >= len(cache^.compiled_plain_text) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    cache^.compiled_plain_text[cache^.compiled_plain_text_len] = b
    cache^.compiled_plain_text_len += 1
    return DYNVIEW_STATUS_OK
}

//   Copy one command text slice into compiled plain-text cache with bounds checks.
append_compiled_text_slice :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    if offset + count > buffer^.text_bytes_len {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    for i in 0..<count {
        status := append_compiled_byte(cache, buffer^.text_bytes[offset + i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return DYNVIEW_STATUS_OK
}

//   Append one byte to compiled copy payload cache and report capacity errors.
append_copy_payload_byte :: proc(cache: ^core.Dynview_Compile_Cache, b: u8) -> i32 {
    if cache^.compiled_copy_payload_len >= len(cache^.compiled_copy_payload) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    cache^.compiled_copy_payload[cache^.compiled_copy_payload_len] = b
    cache^.compiled_copy_payload_len += 1
    return DYNVIEW_STATUS_OK
}

//   Copy one command copy-text slice into compiled copy payload cache.
append_copy_payload_slice :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    if offset + count > buffer^.text_bytes_len {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    for i in 0..<count {
        status := append_copy_payload_byte(cache, buffer^.text_bytes[offset + i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return DYNVIEW_STATUS_OK
}

//   Require an open block before consuming block-scoped content commands.
require_open_block :: #force_inline proc(open_block: bool) -> i32 {
    if open_block {
        return DYNVIEW_STATUS_OK
    }
    return DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Apply begin-block ordering rule.
compile_begin_block :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    if state^.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    state^.open_block = true
    state^.block_id = cmd.block_id
    state^.block_kind = cmd.style_id
    state^.block_row_start = state^.current_row
    state^.block_row_end = state^.current_row
    state^.block_payload_start = cache^.compiled_copy_payload_len
    state^.block_has_copy_payload = false
    return DYNVIEW_STATUS_OK
}

//   Apply end-block ordering rule.
compile_end_block :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    if !state^.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    if state^.block_has_copy_payload {
        if cache^.copy_block_count >= len(cache^.copy_blocks) {
            return DYNVIEW_STATUS_OUT_OF_CAPACITY
        }

        payload_len := cache^.compiled_copy_payload_len - state^.block_payload_start
        cache^.copy_blocks[cache^.copy_block_count] = core.Dynview_Copy_Block{
            block_id = state^.block_id,
            block_kind = state^.block_kind,
            row_start = state^.block_row_start,
            row_end = state^.block_row_end,
            payload_offset = state^.block_payload_start,
            payload_len = payload_len,
        }
        cache^.copy_block_count += 1
    }

    state^.open_block = false
    return DYNVIEW_STATUS_OK
}

//   Apply text-run compilation rule.
compile_text_run :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    state^.block_row_end = state^.current_row
    return append_compiled_text_slice(cache, buffer, cmd.text_offset, cmd.text_len)
}

//   Apply recursive script-wrapper compilation using grouped parent serialization.
compile_script_attach_recursive :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, '{')
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_text_slice(cache, buffer, cmd.text_offset, cmd.text_len)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, '}')
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    sup_text := text_span_from_buffer(buffer, cmd.script_sup_text_offset, cmd.script_sup_text_len)
    if len(sup_text) > 0 {
        sup_prefix := "^{"
        for i in 0..<len(sup_prefix) {
            status = append_compiled_byte(cache, sup_prefix[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        for i in 0..<len(sup_text) {
            status = append_compiled_byte(cache, sup_text[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        status = append_compiled_byte(cache, '}')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    sub_text := text_span_from_buffer(buffer, cmd.script_sub_text_offset, cmd.script_sub_text_len)
    if len(sub_text) > 0 {
        sub_prefix := "_{"
        for i in 0..<len(sub_prefix) {
            status = append_compiled_byte(cache, sub_prefix[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        for i in 0..<len(sub_text) {
            status = append_compiled_byte(cache, sub_text[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        status = append_compiled_byte(cache, '}')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply display-style large-operator compilation with canonical limits ordering.
compile_large_op_recursive :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    base_text := large_op_visible_text(buffer, cmd)
    for i in 0..<len(base_text) {
        status = append_compiled_byte(cache, base_text[i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    sub_text := text_span_from_buffer(buffer, cmd.script_sub_text_offset, cmd.script_sub_text_len)
    if len(sub_text) > 0 {
        sub_prefix := "_{"
        for i in 0..<len(sub_prefix) {
            status = append_compiled_byte(cache, sub_prefix[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        for i in 0..<len(sub_text) {
            status = append_compiled_byte(cache, sub_text[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        status = append_compiled_byte(cache, '}')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    sup_text := text_span_from_buffer(buffer, cmd.script_sup_text_offset, cmd.script_sup_text_len)
    if len(sup_text) > 0 {
        sup_prefix := "^{"
        for i in 0..<len(sup_prefix) {
            status = append_compiled_byte(cache, sup_prefix[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        for i in 0..<len(sup_text) {
            status = append_compiled_byte(cache, sup_text[i])
            if status != DYNVIEW_STATUS_OK {
                return status
            }
        }
        status = append_compiled_byte(cache, '}')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply copyable-run compilation rule.
compile_copyable_text_run :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = append_copy_payload_slice(cache, buffer, cmd.copy_text_offset, cmd.copy_text_len)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.copy_text_len > 0 {
        state^.block_has_copy_payload = true
    }
    return DYNVIEW_STATUS_OK
}

//   Apply inline-line compilation rule.
compile_inline_line :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-box compilation rule.
compile_inline_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-circle compilation rule.
compile_inline_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-filled-box compilation rule.
compile_inline_filled_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 || cmd.inline_outline_stroke < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline-filled-circle compilation rule.
compile_inline_filled_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply inline pie-section compilation rule.
compile_inline_pie_section :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return DYNVIEW_STATUS_OK
}

//   Apply newline-like command rule shared by line-break and divider.
compile_newline_command :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    status := require_open_block(state^.open_block)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, '\n')
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if state^.block_has_copy_payload {
        status = append_copy_payload_byte(cache, '\n')
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    state^.current_row += 1
    return DYNVIEW_STATUS_OK
}

//   Compile one command into cache and enforce the ordering contract.
compile_command :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: core.Dynview_Command) -> i32 {

    switch cmd.kind {
    case .BeginBlock:
        return compile_begin_block(cache, state, cmd)
    case .EndBlock:
        return compile_end_block(cache, state)
    case .TextRun:
        return compile_text_run(cache, buffer, state, cmd)
    case .MathGlyphRun:
        return compile_text_run(cache, buffer, state, cmd)
    case .MathBlock:
        return compile_text_run(cache, buffer, state, cmd)
    case .ScriptAttachRecursive:
        return compile_script_attach_recursive(cache, buffer, state, cmd)
    case .FracRecursive:
        return compile_text_run(cache, buffer, state, cmd)
    case .StretchDelimiterRecursive:
        return compile_text_run(cache, buffer, state, cmd)
    case .MatrixRecursive:
        return compile_text_run(cache, buffer, state, cmd)
    case .LargeOpRecursive:
        return compile_large_op_recursive(cache, buffer, state, cmd)
    case .AccentBarRecursive:
        return compile_text_run(cache, buffer, state, cmd)
    case .RadicalBarRecursive:
        return compile_text_run(cache, buffer, state, cmd)
    case .CopyableTextRun:
        return compile_copyable_text_run(cache, buffer, state, cmd)
    case .LineBreak:
        return compile_newline_command(cache, state)
    case .Divider:
        return compile_newline_command(cache, state)
    case .InlineLine:
        return compile_inline_line(state, cmd)
    case .InlineBox:
        return compile_inline_box(state, cmd)
    case .InlineCircle:
        return compile_inline_circle(state, cmd)
    case .InlineFilledBox:
        return compile_inline_filled_box(state, cmd)
    case .InlineFilledCircle:
        return compile_inline_filled_circle(state, cmd)
    case .InlinePieSection:
        return compile_inline_pie_section(state, cmd)
    }

    return DYNVIEW_STATUS_INVALID_ARGUMENT
}

//   Validate ordering contract and materialize stream text for host rendering.
rebuild_compiled_plain_text :: proc(runtime: ^core.Dynview_System) -> i32 {
    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    cache^.compiled_plain_text_len = 0
    cache^.compiled_copy_payload_len = 0
    cache^.copy_block_count = 0
    cache^.copy_hit_target_count = 0

    compile_state := Dynview_Compile_State{}
    for i in 0..<buffer^.command_count {
        status := compile_command(cache, buffer, &compile_state, buffer^.commands[i])
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    if compile_state.open_block {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }
    return DYNVIEW_STATUS_OK
}

//   Rebuild scratchpad copy icon hit targets from compiled copy blocks.
rebuild_copy_hit_targets :: proc(
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    scroll_y, text_padding, row_height, icon_size, icon_x_pad: f32) {

    if runtime == nil {
        return
    }

    _ = row_height

    cache := &runtime^.compile_cache
    cache^.copy_hit_target_count = 0
    if !cache^.is_valid || !cache^.layout_is_valid {
        return
    }

    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    last_hover_bottom := panel_top
    for i in 0..<cache^.copy_block_count {
        block := cache^.copy_blocks[i]
        row_start, row_end, has_visible_items := layout_item_line_span_for_block(cache, block.block_id)
        if !has_visible_items {
            continue
        }
        if row_end >= cache^.layout_line_count {
            continue
        }

        start_line := cache^.layout_lines[row_start]
        end_line := cache^.layout_lines[row_end]
        row_top := panel.y + text_padding + start_line.y_offset - scroll_y
        row_bottom := panel.y + text_padding + end_line.y_offset +
            end_line.line_height - scroll_y
        if row_bottom < panel_top || row_top > panel_bottom {
            continue
        }
        if cache^.copy_hit_target_count >= len(cache^.copy_hit_targets) {
            break
        }

        visible_top := max(row_top, panel_top)
        visible_bottom := min(row_bottom, panel_bottom)
        visible_top = max(visible_top, last_hover_bottom)
        hover_rect := rl.Rectangle{
            panel.x + text_padding,
            visible_top,
            max(0.0, panel.width - text_padding * 2),
            max(0.0, visible_bottom - visible_top),
        }
        if hover_rect.height <= 0 || hover_rect.width <= 0 {
            continue
        }

        icon_x := panel.x + panel.width - text_padding - icon_size - icon_x_pad
        icon_y := max(panel_top + 1, min(row_top + 2, panel_bottom - icon_size - 1))
        cache^.copy_hit_targets[cache^.copy_hit_target_count] = core.Dynview_Copy_Hit_Target{
            block_id = block.block_id,
            payload_offset = block.payload_offset,
            payload_len = block.payload_len,
            rect = {icon_x, icon_y, icon_size, icon_size},
            hover_rect = hover_rect,
        }
        cache^.copy_hit_target_count += 1
        last_hover_bottom = hover_rect.y + hover_rect.height
    }
}

//   Return compiled copy payload string for one hit target index.
copy_target_payload :: proc(runtime: ^core.Dynview_System, target_index: int) -> string {
    if runtime == nil {
        return ""
    }

    cache := &runtime^.compile_cache
    if target_index < 0 || target_index >= cache^.copy_hit_target_count {
        return ""
    }

    target := cache^.copy_hit_targets[target_index]
    if target.payload_offset < 0 || target.payload_len <= 0 {
        return ""
    }
    if target.payload_offset + target.payload_len > cache^.compiled_copy_payload_len {
        return ""
    }

    return string(cache^.compiled_copy_payload[target.payload_offset:target.payload_offset + target.payload_len])
}

//   Compile command buffer metadata plus plain-text stream projection when needed.
compile_if_needed :: proc(runtime: ^core.Dynview_System) {
    if runtime == nil || !runtime^.enabled {
        return
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    should_compile := !cache^.is_valid || runtime^.pending_invalidation_mask != 0
    should_compile = should_compile || cache^.compiled_revision != buffer^.revision
    if !should_compile {
        return
    }

    cache^.last_error_code = DYNVIEW_STATUS_OK
    status := rebuild_compiled_plain_text(runtime)
    cache^.compiled_revision = buffer^.revision
    cache^.compiled_command_count = buffer^.command_count
    cache^.compiled_text_bytes_len = buffer^.text_bytes_len
    cache^.last_invalidation_mask = runtime^.pending_invalidation_mask
    runtime^.pending_invalidation_mask = 0

    if status != DYNVIEW_STATUS_OK {
        mark_stream_error(runtime, status)
        cache^.copy_hit_target_count = 0
        cache^.layout_is_valid = false
        return
    }

    layout_status := rebuild_layout_cache(runtime)
    if layout_status != DYNVIEW_STATUS_OK {
        mark_stream_error(runtime, layout_status)
        cache^.copy_hit_target_count = 0
        cache^.layout_is_valid = false
        return
    }

    buffer^.has_stream_error = false
    cache^.is_valid = true
}

//   Compile scratchpad stream and return compiled text when validation succeeds.
compiled_scratchpad_text_or_fallback :: proc(
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    font_size, wrap_advance: f32,
    style_revision: u64,
    fallback_text: string) -> string {

    if !runtime^.enabled {
        return fallback_text
    }

    track_panel(runtime, panel)
    track_font(runtime, font_size, wrap_advance)
    track_style(runtime, style_revision)
    compile_if_needed(runtime)

    if !runtime^.compile_cache.is_valid || runtime^.command_buffer.has_stream_error {
        return fallback_text
    }

    text_len := runtime^.compile_cache.compiled_plain_text_len
    return string(runtime^.compile_cache.compiled_plain_text[:text_len])
}

//   Recompute copy hit-target cache for the current scratchpad panel and scroll.
refresh_scratchpad_copy_targets :: proc(
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    scroll_y, text_padding, row_height, icon_size, icon_x_pad: f32) {

    if !runtime^.enabled {
        runtime^.compile_cache.copy_hit_target_count = 0
        return
    }

    rebuild_copy_hit_targets(runtime,
        panel, scroll_y, text_padding, row_height, icon_size, icon_x_pad)
}
