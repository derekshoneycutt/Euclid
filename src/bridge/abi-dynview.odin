package bridge

import "../core"

import rl "vendor:raylib"

//   Reset the dynview command stream for the current frame.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the stream is reset.
//   - BRIDGE_STATUS_INVALID_ARGUMENT when state is nil.
@(export)
dynview_reset_stream :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    runtime^.command_buffer.command_count = 0
    runtime^.command_buffer.text_bytes_len = 0
    runtime^.command_buffer.has_stream_error = false
    runtime^.command_buffer.stream_open_block = false
    runtime^.command_buffer.stream_open_block_id = -1
    runtime^.compile_cache.math_program_count = 0
    runtime^.compile_cache.math_command_count = 0
    runtime^.compile_cache.math_node_count = 0
    runtime^.command_buffer.revision += 1
    runtime^.compile_cache.last_error_code = BRIDGE_STATUS_OK
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Start a new dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - block_kind: Style id assigned to the new block.
//   - block_id: Block identifier used for pairing with the matching end command.
//
// Returns:
//   - BRIDGE_STATUS_OK when the block starts successfully.
//   - BRIDGE_STATUS_ILLEGAL_STATE when a block is already open.
@(export)
dynview_begin_block :: proc "c" (
    state: ^core.Euclid_General_State, block_kind, block_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, false)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if buffer^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }

    status = dynview_push_command(runtime, core.Dynview_Command{
        kind = .BeginBlock,
        block_id = block_id,
        style_id = block_kind,
    })
    if status != BRIDGE_STATUS_OK {
        return status
    }

    buffer^.stream_open_block = true
    buffer^.stream_open_block_id = block_id
    return BRIDGE_STATUS_OK
}

//   Append one visible text run to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: UTF-8 text payload to append to the current block.
//   - style_id: Style id assigned to the emitted text run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_text_run :: proc "c" (
    state: ^core.Euclid_General_State, text: cstring, style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .TextRun,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
    })
}

//   Append one visible text run with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: UTF-8 text payload to append to the current block.
//   - style_id: Style id assigned to the emitted text run.
//   - brush_color: Brush color override for the text run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_text_run_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    text: cstring,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .TextRun,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one visible math-glyph run to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: Glyph payload to append to the current block.
//   - style_id: Style id assigned to the emitted math-glyph run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_math_glyph_run :: proc "c" (
    state: ^core.Euclid_General_State, text: cstring, style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .MathGlyphRun,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
    })
}

//   Append one whole inline math block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - latex_source: Placeholder LaTeX source payload.
//   - style_id: Style id assigned to the emitted block command.
//
// Returns:
//   - BRIDGE_STATUS_INVALID_ARGUMENT until recursive program storage is wired.
@(export)
dynview_math_block :: proc "c" (
    state: ^core.Euclid_General_State,
    latex_source: cstring,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if latex_source == nil || style_id < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    _ = latex_source
    _ = style_id
    return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
}

//   Report whether the compile cache can hold the whole recursive math payload.
dynview_math_capacity_available :: proc(
    cache: ^core.Dynview_Compile_Cache,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int) -> bool {

    if cache^.math_program_count >= core.DYNVIEW__MAX_MATH_PROGRAMS {
        return false
    }
    extra_programs, extra_commands :=
        dynview_count_recursive_math_capacity(ops, op_count)
    if cache^.math_program_count + 1 + extra_programs >
        core.DYNVIEW__MAX_MATH_PROGRAMS {
        return false
    }
    return cache^.math_command_count + op_count + extra_commands <=
        core.DYNVIEW__MAX_MATH_COMMANDS
}

//   Report whether the math-block arguments are non-nil and non-empty.
dynview_math_block_args_valid :: proc(
    plain_text: cstring,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: i32,
    top_level_op_count: i32,
    text_blob: cstring) -> bool {

    return plain_text != nil && text_blob != nil && ops != nil &&
        op_count > 0 && top_level_op_count > 0
}

//   Append the plain-text and shared blob payloads, returning both spans.
dynview_append_math_text_payloads :: proc(
    runtime: ^core.Dynview_System,
    plain_text, text_blob: cstring) -> (
        plain_offset, plain_count, blob_offset, blob_count: int, status: i32) {

    status = dynview_append_text_payload(
        runtime, string(plain_text), &plain_offset, &plain_count)
    if status != BRIDGE_STATUS_OK {
        return 0, 0, 0, 0, status
    }

    status = dynview_append_text_payload(
        runtime, string(text_blob), &blob_offset, &blob_count)
    if status != BRIDGE_STATUS_OK {
        return 0, 0, 0, 0, status
    }

    return plain_offset, plain_count, blob_offset, blob_count, BRIDGE_STATUS_OK
}

//   Append one whole inline math block from a flat child-command payload.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - plain_text: Plain-text copy payload for the math block.
//   - style_id: Style id assigned to the emitted block command.
//   - ops: Flat child-command program payload consumed by the importer.
//   - op_count: Number of math ops in the payload.
//   - top_level_op_count: Number of top-level ops in the payload.
//   - text_blob: Shared text blob backing the math op spans.
//
// Returns:
//   - BRIDGE_STATUS_OK when the block is imported successfully.
//   - BRIDGE_STATUS_INVALID_ARGUMENT when the payload is malformed.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when the compile cache is full.
@(export)
dynview_math_block_from_ops :: proc "c" (
    state: ^core.Euclid_General_State,
    plain_text: cstring,
    style_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: i32,
    top_level_op_count: i32,
    text_blob: cstring) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if !dynview_math_block_args_valid(plain_text, ops, op_count,
        top_level_op_count, text_blob) {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    cache := &runtime^.compile_cache
    if !dynview_math_capacity_available(cache, ops, int(op_count)) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    plain_offset, plain_count, blob_offset, blob_count, payload_status :=
        dynview_append_math_text_payloads(runtime, plain_text, text_blob)
    if payload_status != BRIDGE_STATUS_OK {
        return payload_status
    }

    program_id := cache^.math_program_count
    next_child_program_id := program_id + 1
    cursor := 0

    status = dynview_import_math_program_from_ops(cache, buffer^.stream_open_block_id,
        ops, int(op_count), &cursor, int(top_level_op_count), blob_offset, blob_count,
        program_id, &next_child_program_id)
    if status != BRIDGE_STATUS_OK {
        return dynview_fail(runtime, status)
    }
    if cursor != int(op_count) {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    cache^.math_programs[program_id].valid = true
    cache^.math_programs[program_id].copy_text_offset = plain_offset
    cache^.math_programs[program_id].copy_text_len = plain_count
    cache^.math_program_count = next_child_program_id

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .MathBlock,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        math_program_id = i32(program_id),
        text_offset = plain_offset,
        text_len = plain_count,
    })
}

//   Append one non-rendering copyable payload segment to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - copy_text: Plain-text payload to copy into the dynview stream.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_copyable_text_run :: proc "c" (
    state: ^core.Euclid_General_State,
    copy_text: cstring) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    copy_text_value := ""
    if copy_text != nil {
        copy_text_value = string(copy_text)
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, copy_text_value, &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .CopyableTextRun,
        block_id = buffer^.stream_open_block_id,
        copy_text_offset = offset,
        copy_text_len = count,
    })
}

//   Append one inline line atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - length: Line length in world units.
//   - thickness: Line stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_line :: proc "c" (
    state: ^core.Euclid_General_State,
    length, thickness: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if length <= 0 || thickness <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineLine,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = length,
        inline_atom_stroke = thickness,
    })
}

//   Append one inline box atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - width: Box width in world units.
//   - height: Box height in world units.
//   - stroke: Box outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_box :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineBox,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_atom_stroke = stroke,
        inline_box_height = height,
    })
}

//   Append one inline circle atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - stroke: Circle outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    radius, stroke: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineCircle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        inline_atom_stroke = stroke,
    })
}

//   Append one inline line atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - length: Line length in world units.
//   - thickness: Line stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_line_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    length, thickness: f32,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if length <= 0 || thickness <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineLine,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = length,
        inline_atom_stroke = thickness,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one inline box atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - width: Box width in world units.
//   - height: Box height in world units.
//   - stroke: Box outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_box_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineBox,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_atom_stroke = stroke,
        inline_box_height = height,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one inline circle atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - stroke: Circle outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_circle_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    radius, stroke: f32,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineCircle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        inline_atom_stroke = stroke,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one filled inline box atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - width: Box width in world units.
//   - height: Box height in world units.
//   - style_id: Style id assigned to the emitted atom.
//   - fill_color: Fill color for the atom.
//   - outline_stroke: Optional outline stroke thickness.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_filled_box :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height: f32,
    style_id: i32,
    fill_color: Bridge_Color,
    outline_stroke: f32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || outline_stroke < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineFilledBox,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_box_height = height,
        has_brush_color = true,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        inline_outline_stroke = outline_stroke,
    })
}

//   Append one filled inline circle atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - style_id: Style id assigned to the emitted atom.
//   - fill_color: Fill color for the atom.
//   - outline_stroke: Optional outline stroke thickness.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_filled_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    radius: f32,
    style_id: i32,
    fill_color: Bridge_Color,
    outline_stroke: f32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || outline_stroke < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineFilledCircle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        has_brush_color = true,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        inline_outline_stroke = outline_stroke,
    })
}

//   Append one inline perpendicular atom with two independently colored legs.
@(export)
dynview_inline_perpendicular :: proc "c" (
    state: ^core.Euclid_General_State,
    length, stem_height, stroke: f32,
    style_id: i32,
    top_color, stem_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if length <= 0 || stem_height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlinePerpendicular,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = length,
        inline_box_height = stem_height,
        inline_atom_stroke = stroke,
        brush_color = rl.Color{top_color.r, top_color.g, top_color.b, top_color.a},
        shape_edge_color_1 =
            rl.Color{stem_color.r, stem_color.g, stem_color.b, stem_color.a},
    })
}

//   Append one inline triangle atom with optional fill and three edge colors.
@(export)
dynview_inline_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32,
    filled: bool,
    fill_color, edge1_color, edge2_color, edge3_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineTriangle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_box_height = height,
        inline_atom_stroke = stroke,
        shape_is_filled = filled,
        has_brush_color = filled,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        shape_edge_color_1 =
            rl.Color{edge1_color.r, edge1_color.g, edge1_color.b, edge1_color.a},
        shape_edge_color_2 =
            rl.Color{edge2_color.r, edge2_color.g, edge2_color.b, edge2_color.a},
        shape_edge_color_3 =
            rl.Color{edge3_color.r, edge3_color.g, edge3_color.b, edge3_color.a},
    })
}

//   Append one inline box atom with independently colored edges.
@(export)
dynview_inline_box_edges :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32,
    edge1_color, edge2_color, edge3_color, edge4_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlineBox,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_atom_stroke = stroke,
        inline_box_height = height,
        shape_edge_color_1 =
            rl.Color{edge1_color.r, edge1_color.g, edge1_color.b, edge1_color.a},
        shape_edge_color_2 =
            rl.Color{edge2_color.r, edge2_color.g, edge2_color.b, edge2_color.a},
        shape_edge_color_3 =
            rl.Color{edge3_color.r, edge3_color.g, edge3_color.b, edge3_color.a},
        shape_edge_color_4 =
            rl.Color{edge4_color.r, edge4_color.g, edge4_color.b, edge4_color.a},
    })
}

//   Append one inline pentagon atom with optional fill and five edge colors.
@(export)
dynview_inline_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32,
    filled: bool,
    fill_color,
        edge1_color, edge2_color, edge3_color,
        edge4_color, edge5_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlinePentagon,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_box_height = height,
        inline_atom_stroke = stroke,
        shape_is_filled = filled,
        has_brush_color = filled,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        shape_edge_color_1 =
            rl.Color{edge1_color.r, edge1_color.g, edge1_color.b, edge1_color.a},
        shape_edge_color_2 =
            rl.Color{edge2_color.r, edge2_color.g, edge2_color.b, edge2_color.a},
        shape_edge_color_3 =
            rl.Color{edge3_color.r, edge3_color.g, edge3_color.b, edge3_color.a},
        shape_edge_color_4 =
            rl.Color{edge4_color.r, edge4_color.g, edge4_color.b, edge4_color.a},
        shape_edge_color_5 =
            rl.Color{edge5_color.r, edge5_color.g, edge5_color.b, edge5_color.a},
    })
}

//   Append one filled inline pie-section atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - start_angle_degrees: Start angle for the pie section.
//   - end_angle_degrees: End angle for the pie section.
//   - style_id: Style id assigned to the emitted atom.
//   - fill_color: Fill color for the atom.
//   - outline_stroke: Optional outline stroke thickness.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_pie_section :: proc "c" (
    state: ^core.Euclid_General_State,
    radius, start_angle_degrees, end_angle_degrees: f32,
    style_id: i32,
    filled: bool,
    fill_color: Bridge_Color,
    arc_color: Bridge_Color,
    outline_stroke: f32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || outline_stroke < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .InlinePieSection,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        has_brush_color = true,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        inline_outline_stroke = outline_stroke,
        pie_start_angle_degrees = start_angle_degrees,
        pie_end_angle_degrees = end_angle_degrees,
        pie_is_filled = filled,
        has_outline_color = true,
        outline_color = rl.Color{arc_color.r, arc_color.g, arc_color.b, arc_color.a},
    })
}

//   Insert an explicit line break in the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_line_break :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .LineBreak,
        block_id = buffer^.stream_open_block_id,
    })
}

//   End the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the block closes successfully.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_end_block :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    status = dynview_push_command(runtime, core.Dynview_Command{
        kind = .EndBlock,
        block_id = buffer^.stream_open_block_id,
    })
    if status != BRIDGE_STATUS_OK {
        return status
    }

    buffer^.stream_open_block = false
    buffer^.stream_open_block_id = -1
    return BRIDGE_STATUS_OK
}

