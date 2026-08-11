package bridge

import "../core"

//   Convert bridge decoration integer values to label decoration enum values.
//
// Parameters:
//   - kind: Bridge decoration constant encoded as i32.
//
// Returns:
//   - Matching label decoration enum value, or .None for unsupported values.
label_decoration_kind_from_i32 :: #force_inline proc(
    kind: i32) -> core.Shapes_Label_Decoration_Kind {
    switch kind {
    case BRIDGE_LABEL_DECORATION_PRIME:
        return .Prime
    case BRIDGE_LABEL_DECORATION_DOUBLEPRIME:
        return .DoublePrime
    case BRIDGE_LABEL_DECORATION_TRIPLEPRIME:
        return .TriplePrime
    case BRIDGE_LABEL_DECORATION_HAT:
        return .Hat
    case BRIDGE_LABEL_DECORATION_BAR:
        return .Bar
    }

    return .None
}

//   Mark dynview stream state as failed and lock compile cache into invalid state.
//
// Notes:
//   - Preserves the first encountered error code for diagnostic stability.
dynview_fail :: #force_inline proc(runtime: ^core.Dynview_System, code: i32) -> i32 {
    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == 0 {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
    return code
}

//   Append one dynview command to the command buffer.
//
// Returns:
//   - BRIDGE_STATUS_OK when command is enqueued.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when command buffer is full.
dynview_push_command :: #force_inline proc(
    runtime: ^core.Dynview_System,
    command: core.Dynview_Command) -> i32 {

    buffer := &runtime^.command_buffer
    if buffer^.command_count >= len(buffer^.commands) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    buffer^.commands[buffer^.command_count] = command
    buffer^.command_count += 1
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Append text bytes into dynview payload storage and return payload span.
//
// Parameters:
//   - text: Text payload to append to the shared dynview byte buffer.
//   - offset_out: Receives start offset of appended bytes.
//   - count_out: Receives appended byte count.
//
// Returns:
//   - BRIDGE_STATUS_OK when payload is appended.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when byte buffer has insufficient space.
dynview_append_text_payload :: #force_inline proc(
    runtime: ^core.Dynview_System,
    text: string,
    offset_out, count_out: ^int) -> i32 {

    buffer := &runtime^.command_buffer
    text_len := len(text)
    if buffer^.text_bytes_len + text_len > len(buffer^.text_bytes) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    start := buffer^.text_bytes_len
    for i in 0..<text_len {
        buffer^.text_bytes[start + i] = text[i]
    }

    buffer^.text_bytes_len += text_len
    offset_out^ = start
    count_out^ = text_len
    return BRIDGE_STATUS_OK
}

//   Convert a bridge math-op kind into the matching dynview command kind.
//
// Notes:
//   - Unsupported bridge kinds fall back to a text run so the importer can keep
//     making progress instead of failing the whole program.
dynview_math_command_kind_from_bridge :: #force_inline proc(
    kind: i32) -> (core.Dynview_Command_Kind, bool) {
    switch kind {
    case BRIDGE_DYNVIEW_MATH_OP_TEXT_RUN:
        return .TextRun, true
    case BRIDGE_DYNVIEW_MATH_OP_MATH_GLYPH_RUN:
        return .MathGlyphRun, true
    case BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE:
        return .ScriptAttachRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE:
        return .FracRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE:
        return .StretchDelimiterRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE:
        return .MatrixRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_LARGE_OP_RECURSIVE:
        return .LargeOpRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE:
        return .AccentBarRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE:
        return .RadicalBarRecursive, true
    }
    return .TextRun, false
}

//   Return whether an op's text spans fit inside the shared text blob.
//
// Notes:
//   - Each span is checked against the shared blob bounds before the importer
//     emits any dynview command using the payload offsets.
dynview_math_op_spans_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op, blob_count: int) -> bool {
    if op.text_offset < 0 || op.text_len < 0 ||
        op.index_text_offset < 0 || op.index_text_len < 0 ||
        op.sup_text_offset < 0 || op.sup_text_len < 0 ||
        op.sub_text_offset < 0 || op.sub_text_len < 0 {
        return false
    }

    return int(op.text_offset + op.text_len) <= blob_count &&
        int(op.index_text_offset + op.index_text_len) <= blob_count &&
        int(op.sup_text_offset + op.sup_text_len) <= blob_count &&
        int(op.sub_text_offset + op.sub_text_len) <= blob_count
}

//   Import one recursive child program into the dynview compile cache.
//
// Notes:
//   - The helper reserves the next available program id and reuses the shared
//     recursive importer to pull the requested subtree into the cache.
dynview_import_child_program :: proc(
    cache: ^core.Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    direct_count: int,
    blob_offset, blob_count: int,
    next_program_id: ^int) -> (program_id: i32, status: i32) {

    if direct_count <= 0 || next_program_id == nil {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if next_program_id^ >= core.DYNVIEW__MAX_MATH_PROGRAMS {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }

    host_program_id := next_program_id^
    next_program_id^ += 1
    child_status: i32 = dynview_import_math_program_from_ops(cache, block_id, ops,
        op_count, cursor, direct_count, blob_offset, blob_count, host_program_id,
        next_program_id)
    if child_status != BRIDGE_STATUS_OK {
        return 0, child_status
    }

    return i32(host_program_id), BRIDGE_STATUS_OK
}

//   Import the numerator and denominator subprograms for a fraction op.
//
// Notes:
//   - The fraction branches are imported from the same flat bridge stream.
//   - The helper advances the shared cursor and program allocation state for both
//     children before returning the assigned program ids.
dynview_import_fraction_children :: proc(
    cache: ^core.Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    op: Bridge_Dynview_Math_Op,
    blob_offset, blob_count: int,
    next_program_id: ^int) -> (
        numerator_program_id: i32, denominator_program_id: i32, status: i32) {

    numerator_direct_count := int(op.child_program_id)
    denominator_direct_count := int(op.secondary_child_program_id)
    if numerator_direct_count <= 0 || denominator_direct_count <= 0 {
        return 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if next_program_id^ + 1 >= core.DYNVIEW__MAX_MATH_PROGRAMS {
        return 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }

    numerator_result, numerator_status := dynview_import_child_program(cache, block_id,
        ops, op_count, cursor, numerator_direct_count, blob_offset, blob_count,
        next_program_id)
    if numerator_status != BRIDGE_STATUS_OK {
        return 0, 0, numerator_status
    }

    denominator_result, denominator_status := dynview_import_child_program(cache,
        block_id, ops, op_count, cursor, denominator_direct_count,
        blob_offset, blob_count, next_program_id)
    if denominator_status != BRIDGE_STATUS_OK {
        return 0, 0, denominator_status
    }

    return numerator_result, denominator_result, BRIDGE_STATUS_OK
}

//   Import one math program from the flat bridge op stream.
//
// Notes:
//   - The helper reserves command slots for the requested subtree size and then
//     walks the bridge ops into the dynview compile cache.
dynview_import_math_program_from_ops :: proc(
    cache: ^core.Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    direct_count: int,
    blob_offset, blob_count: int,
    program_id: int,
    next_program_id: ^int) -> i32 {

    if direct_count <= 0 || cache == nil || cursor == nil || next_program_id == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    command_start := cache^.math_command_count
    if command_start + direct_count > core.DYNVIEW__MAX_MATH_COMMANDS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    cache^.math_command_count += direct_count

    for local_index in 0..<direct_count {
        if cursor^ >= op_count {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }

        op := ops[cursor^]
        cursor^ += 1
        command_kind, ok := dynview_math_command_kind_from_bridge(op.kind)
        if !ok || !dynview_math_op_spans_valid(op, blob_count) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }

        child_program_id := i32(op.child_program_id)
        secondary_child_program_id: i32 = 0
        status: i32 = BRIDGE_STATUS_OK
        switch command_kind {
        case .ScriptAttachRecursive, .AccentBarRecursive, .RadicalBarRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count <= 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            child_program_id, status = dynview_import_child_program(cache, block_id,
                ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                next_program_id)
            if status != BRIDGE_STATUS_OK {
                return status
            }
        case .FracRecursive:
            numerator_program_id, denominator_program_id, child_status :=
                dynview_import_fraction_children(cache, block_id, ops, op_count, cursor,
                    op, blob_offset, blob_count, next_program_id)
            if child_status != BRIDGE_STATUS_OK {
                return child_status
            }
            child_program_id = numerator_program_id
            secondary_child_program_id = denominator_program_id
        case .StretchDelimiterRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count > 0 {
                child_program_id, status = dynview_import_child_program(cache, block_id,
                    ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                    next_program_id)
                if status != BRIDGE_STATUS_OK {
                    return status
                }
            } else {
                child_program_id = 0
            }
        case .MatrixRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count <= 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            child_program_id, status = dynview_import_child_program(cache, block_id,
                ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                next_program_id)
            if status != BRIDGE_STATUS_OK {
                return status
            }
        case .BeginBlock, .EndBlock,
             .TextRun, .MathGlyphRun, .MathBlock,
             .LargeOpRecursive, .CopyableTextRun, .LineBreak, .Divider,
             .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox,
               .InlineFilledCircle, .InlinePieSection, .InlinePerpendicular,
               .InlineTriangle, .InlinePentagon:
        }

        cache^.math_commands[command_start + local_index] = core.Dynview_Command{
            kind = command_kind,
            block_id = block_id,
            style_id = op.style_id,
            math_program_id = child_program_id,
            secondary_math_program_id = secondary_child_program_id,
            text_offset = blob_offset + int(op.text_offset),
            text_len = int(op.text_len),
            script_base_text_offset = blob_offset + int(op.text_offset),
            script_base_text_len = int(op.text_len),
            script_sup_text_offset = blob_offset + int(op.sup_text_offset),
            script_sup_text_len = int(op.sup_text_len),
            script_sub_text_offset = blob_offset + int(op.sub_text_offset),
            script_sub_text_len = int(op.sub_text_len),
            script_style_id = op.script_style_id,
            script_scale = op.script_scale,
            script_sup_raise = op.script_sup_raise,
            script_sub_drop = op.script_sub_drop,
            script_gap = op.script_gap,
            accent_mode = op.accent_mode,
            radical_mode = op.radical_mode,
            large_op_kind = op.large_op_kind,
            radical_index_text_offset = blob_offset + int(op.index_text_offset),
            radical_index_text_len = int(op.index_text_len),
            accent_style_id = op.accent_style_id,
            accent_thickness = op.accent_thickness,
            accent_offset = op.accent_offset,
        }
    }

    cache^.math_programs[program_id] = core.Dynview_Math_Program{
        valid = true,
        command_start = command_start,
        command_count = direct_count,
    }
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the dynview runtime for the current bridge state.
//
// Notes:
//   - The helper reuses the bridge state's saved context so the caller can access
//     the active dynview runtime without reaching into the state internals.
dynview_require_runtime :: proc(
    state: ^core.Euclid_General_State,
    runtime_out: ^^core.Dynview_System) -> i32 {

    if state == nil || runtime_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    context = state^.saved_context
    runtime_out^ = state^.dynview_emit_target
    if runtime_out^ == nil {
        runtime_out^ = &state^.dynview
    }
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the active dynview command buffer.
//
// Notes:
//   - The helper exposes the current command buffer while optionally enforcing
//     that a dynview block is already open before commands are appended.
dynview_require_buffer :: proc(
    runtime: ^core.Dynview_System,
    buffer_out: ^^core.Dynview_Command_Buffer,
    require_open_block: bool) -> i32 {

    if runtime == nil || buffer_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer_out^ = &runtime^.command_buffer
    buffer := buffer_out^
    if require_open_block && !buffer^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }
    return BRIDGE_STATUS_OK
}

//   Count the extra math programs and commands needed by recursive ops.
//
// Notes:
//   - Recursive math nodes reserve additional program and command slots based on
//     their child structure so the compile cache can be sized up front.
dynview_count_recursive_math_capacity :: proc(
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int) -> (extra_programs: int, extra_commands: int) {

    for i in 0..<op_count {
        switch ops[i].kind {
        case BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE:
            extra_programs += 1
            extra_commands += 1
        case BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE:
            extra_programs += 2
            extra_commands += 2
        case BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE:
            if ops[i].child_program_id > 0 {
                extra_programs += 1
                extra_commands += 1
            }
        }
    }

    return
}