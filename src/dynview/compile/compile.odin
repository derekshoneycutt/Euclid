package dynview_compile

import dynviewmodel "../model"

import storage "../../core/storage"

import dyncore "../core"
import dynlayout "../layout"
import dynmath "../math"

import "core:os"

Dynview_Compile_State :: struct {
    plain_text_builder: storage.Bounded_Byte_Builder,
    open_block: bool,
}

//   Uniform handler shape for one dynview command kind during compilation.
Compile_Command_Handler :: #type proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32

//   Dispatch table mapping each dynview command kind to its compile handler.
COMPILE_COMMAND_HANDLERS ::
    [dynviewmodel.Dynview_Command_Kind]Compile_Command_Handler{
    .Begin_Block = compile_handle_begin_block,
    .End_Block = compile_handle_end_block,
    .Text_Run = compile_text_run,
    .Math_Glyph_Run = compile_text_run,
    .Math_Block = compile_text_run,
    .Script_Attach = compile_script_attach_recursive,
    .Frac = compile_text_run,
    .Stretch_Delimiter = compile_text_run,
    .Matrix = compile_text_run,
    .Style_Override = compile_text_run,
    .Stack = compile_text_run,
    .Large_Op = compile_large_op_recursive,
    .Accent_Bar = compile_text_run,
    .Radical_Bar = compile_text_run,
    .Line_Break = compile_handle_newline,
    .Divider = compile_handle_newline,
    .Inline_Line = compile_handle_inline_line,
    .Inline_Box = compile_handle_inline_box,
    .Inline_Circle = compile_handle_inline_circle,
    .Inline_Filled_Box = compile_handle_inline_filled_box,
    .Inline_Filled_Circle = compile_handle_inline_filled_circle,
    .Inline_Pie_Section = compile_handle_inline_pie_section,
    .Inline_Perpendicular = compile_handle_inline_box,
    .Inline_Triangle = compile_handle_inline_box,
    .Inline_Pentagon = compile_handle_inline_box,
}

Compiled_Optional_Group :: struct {
    offset, count: int,
    prefix: string,
    close: u8,
}

//   Append one compiled plain-text byte through the bounded cache builder.
append_compiled_byte :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    value: u8) -> i32 {

    status := storage.bounded_byte_builder_append(
        &state^.plain_text_builder, []u8{value})
    if status == .Ok {
        cache^.compiled_plain_text_len = state^.plain_text_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Copy one command text slice into compiled plain-text cache with bounds checks.
append_compiled_text_slice :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    text_bytes := dyncore.command_buffer_text(buffer)
    if offset + count > len(text_bytes) {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    status := storage.bounded_byte_builder_append(
        &state^.plain_text_builder, text_bytes[offset:offset + count])
    if status == .Ok {
        cache^.compiled_plain_text_len = state^.plain_text_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Require an open block before consuming block-scoped content commands.
require_open_block :: #force_inline proc(open_block: bool) -> i32 {
    if open_block {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Apply begin-block ordering rule.
compile_begin_block :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    if state^.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }

    state^.open_block = true
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply end-block ordering rule.
compile_end_block :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    if !state^.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }

    state^.open_block = false
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply text-run compilation rule.
compile_text_run :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    return append_compiled_text_slice(cache, buffer, state, cmd.text_offset, cmd.text_len)
}

//   Apply recursive script-wrapper compilation using grouped parent serialization.
compile_script_attach_recursive :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '{')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_text_slice(
        cache, buffer, state, cmd.text_offset, cmd.text_len)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '}')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sup_text_offset, cmd.script_sup_text_len, "^{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sub_text_offset, cmd.script_sub_text_len, "_{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Append a wrapped text group: prefix bytes, body bytes, then a closing byte.
append_compiled_group :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    prefix, body: string,
    close: u8) -> i32 {

    for i in 0..<len(prefix) {
        status := append_compiled_byte(cache, state, prefix[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }
    for i in 0..<len(body) {
        status := append_compiled_byte(cache, state, body[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }
    return append_compiled_byte(cache, state, close)
}

//   Append one wrapped group only when its body is non-empty.
append_compiled_optional_group :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    group: Compiled_Optional_Group) -> i32 {

    text := dyncore.text_span_from_buffer(buffer, group.offset, group.count)
    if len(text) == 0 {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return append_compiled_group(cache, state, group.prefix, text, group.close)
}

//   Apply display-style large-operator compilation with canonical limits ordering.
compile_large_op_recursive :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    base_text := dynlayout.large_op_visible_text(buffer, cmd)
    for i in 0..<len(base_text) {
        status = append_compiled_byte(cache, state, base_text[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sub_text_offset, cmd.script_sub_text_len, "_{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sup_text_offset, cmd.script_sup_text_len, "^{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-line compilation rule.
compile_inline_line :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-box compilation rule.
compile_inline_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 ||
        cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-circle compilation rule.
compile_inline_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-filled-box compilation rule.
compile_inline_filled_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 ||
        cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-filled-circle compilation rule.
compile_inline_filled_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline pie-section compilation rule.
compile_inline_pie_section :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply newline-like command rule shared by line-break and divider.
compile_newline_command :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '\n')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    return dyncore.DYNVIEW_STATUS_OK
}

//   Adapt compile_begin_block (no command buffer) to the uniform table shape.
compile_handle_begin_block :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_begin_block(cache, state, cmd)
}

//   Adapt compile_end_block (no command payload) to the uniform table shape.
compile_handle_end_block :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_end_block(cache, state)
}

//   Adapt newline commands (no command payload) to the uniform table shape.
compile_handle_newline :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_newline_command(cache, state)
}

//   Adapt compile_inline_line (no cache or buffer) to the uniform table shape.
compile_handle_inline_line :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_line(state, cmd)
}

//   Adapt compile_inline_box (no cache or buffer) to the uniform table shape.
compile_handle_inline_box :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_box(state, cmd)
}

//   Adapt compile_inline_circle (no cache or buffer) to the uniform table shape.
compile_handle_inline_circle :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_circle(state, cmd)
}

//   Adapt compile_inline_filled_box (no cache or buffer) to the uniform shape.
compile_handle_inline_filled_box :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_filled_box(state, cmd)
}

//   Adapt compile_inline_filled_circle (no cache or buffer) to the uniform shape.
compile_handle_inline_filled_circle :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_filled_circle(state, cmd)
}

//   Adapt compile_inline_pie_section (no cache or buffer) to the uniform shape.
compile_handle_inline_pie_section :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {
    return compile_inline_pie_section(state, cmd)
}

//   Compile one command into cache and enforce the ordering contract.
compile_command :: #force_inline proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    buffer: ^dynviewmodel.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: dynviewmodel.Dynview_Command) -> i32 {

    kind := cmd.kind
    if kind < .Begin_Block || kind > .Inline_Pentagon {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    handlers := COMPILE_COMMAND_HANDLERS
    handler := handlers[kind]
    if handler == nil {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    return handler(cache, buffer, state, cmd)
}

//   Initialize bounded storage for one compiled Dynview cache transaction.
compiled_builders_init :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cache_arena: ^storage.Arena_Owner) -> i32 {
    plain_status := storage.bounded_byte_builder_init(
        &state^.plain_text_builder, dynviewmodel.DYNVIEW_MAX_TEXT_BYTES, cache_arena)
    if plain_status != .Ok {
        return dyncore.compiled_builder_status(plain_status)
    }
    return dyncore.DYNVIEW_STATUS_OK
}

//   Seal and publish compiled plain text atomically.
compiled_builders_seal :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {
    plain_text, plain_status := storage.bounded_byte_builder_seal(
        &state^.plain_text_builder)
    if plain_status != .Ok {
        return dyncore.compiled_builder_status(plain_status)
    }
    cache^.compiled_plain_text = plain_text
    return dyncore.DYNVIEW_STATUS_OK
}

//   Validate ordering contract and materialize stream text for host rendering.
rebuild_compiled_plain_text :: proc(
    runtime: ^dynviewmodel.Dynview_System,
    cache_arena: ^storage.Arena_Owner) -> i32 {

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    cache^.compiled_plain_text = nil
    cache^.compiled_plain_text_len = 0

    compile_state := Dynview_Compile_State{}
    init_status := compiled_builders_init(cache, &compile_state, cache_arena)
    if init_status != dyncore.DYNVIEW_STATUS_OK {
        return init_status
    }
    for command in dyncore.command_buffer_commands(buffer) {
        status := compile_command(cache, buffer, &compile_state, command)
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }

    if compile_state.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }
    return compiled_builders_seal(cache, &compile_state)
}

//   Clear worker-built views after a failed compile without touching semantic input.
clear_partial_derived_views :: proc(cache: ^dynviewmodel.Dynview_Compile_Cache) {
    if cache == nil {
        return
    }
    cache^.compiled_plain_text_len = 0
    cache^.compiled_plain_text = nil
    clear_document_shaped_records(cache)
    dynlayout.document_layout_clear(cache)
    dynmath.layout_reset_cache(cache)
    cache^.is_valid = false
}

//   Seed mutable math measurement records from the immutable published content.
prepare_math_working_records :: proc(runtime: ^dynviewmodel.Dynview_System) {
    content := &runtime^.content
    cache := &runtime^.compile_cache
    cache^.math_program_count = len(content^.math_programs)
    cache^.math_table_descriptor_count = len(content^.math_table_descriptors)
    cache^.math_command_count = len(content^.math_commands)
    cache^.math_node_count = len(content^.math_nodes)
    copy(cache^.math_programs[:cache^.math_program_count], content^.math_programs)
    copy(cache^.math_table_descriptors[:cache^.math_table_descriptor_count],
        content^.math_table_descriptors)
    copy(cache^.math_commands[:cache^.math_command_count], content^.math_commands)
    copy(cache^.math_nodes[:cache^.math_node_count], content^.math_nodes)
}

//   Rebuild compiled text, shaped math, and layout views in dependency order.
compile_derived_views :: proc(
    runtime: ^dynviewmodel.Dynview_System,
    cache_arena: ^storage.Arena_Owner,
    shaping_service: dynmath.Math_Shaping_Service,
    prose_service: Document_Prose_Shaping_Service) -> i32 {
    status := rebuild_compiled_plain_text(runtime, cache_arena)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }
    prose_status := rebuild_document_shaped_cache(runtime, cache_arena, prose_service)
    if prose_status != .Ok {
        return shaped_builder_error_status(prose_status)
    }
    shaping_status := dynmath.rebuild_shaped_math_cache(
        runtime, cache_arena, shaping_service)
    if shaping_status != .Ok {
        return shaped_builder_error_status(shaping_status)
    }
    if len(runtime^.content.documents) > 0 {
        dynmath.layout_reset_cache(&runtime^.compile_cache)
    } else {
        layout_status := dynlayout.rebuild_layout_cache(runtime, cache_arena)
        if layout_status != dyncore.DYNVIEW_STATUS_OK {
            return layout_status
        }
    }
    document_status := dynlayout.rebuild_document_layout_cache(runtime, cache_arena)
    if document_status == .Ok {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return shaped_builder_error_status(document_status)
}

//   Compile invalidated command and layout caches through worker-owned arena lifetime.
//
// Side effects:
//   - Resets `cache_arena` before mutating derived cache state for one rebuild.
//   - Leaves the arena and cache unchanged when no rebuild is required.
compile_if_needed :: proc(
    runtime: ^dynviewmodel.Dynview_System,
    cache_arena: ^storage.Arena_Owner,
    shaping_service: dynmath.Math_Shaping_Service = {},
    prose_service: Document_Prose_Shaping_Service = {}) {

    if runtime == nil || !runtime^.enabled {
        return
    }

    if !compile_is_needed(runtime) {
        return
    }

    if !compile_worker_can_rebuild(runtime, cache_arena) {
        return
    }
    cache := &runtime^.compile_cache
    clear_partial_derived_views(cache)
    dynmath.clear_shaped_records(cache)
    storage.arena_owner_reset(cache_arena)
    if runtime^.command_buffer.command_view != nil {
        prepare_math_working_records(runtime)
    }
    buffer := &runtime^.command_buffer
    cache^.last_error_code = dyncore.DYNVIEW_STATUS_OK
    status := compile_derived_views(
        runtime, cache_arena, shaping_service, prose_service)
    cache^.compiled_revision = buffer^.revision
    cache^.compiled_command_count = len(dyncore.command_buffer_commands(buffer))
    cache^.compiled_text_bytes_len = len(dyncore.command_buffer_text(buffer))
    cache^.last_invalidation_mask = runtime^.pending_invalidation_mask
    runtime^.pending_invalidation_mask = 0

    if status != dyncore.DYNVIEW_STATUS_OK {
        fail_compile_rebuild(runtime, status)
        return
    }

    buffer^.has_stream_error = false
    cache^.is_valid = true
}

//   Mark one rebuild failure and discard all partially derived cache views.
fail_compile_rebuild :: proc(runtime: ^dynviewmodel.Dynview_System, status: i32) {
    dyncore.mark_stream_error(runtime, status)
    clear_partial_derived_views(&runtime^.compile_cache)
    dynmath.clear_shaped_records(&runtime^.compile_cache)
}

//   Validate worker ownership and arena lifetime before one invalidated rebuild.
compile_worker_can_rebuild :: #force_inline proc(
    runtime: ^dynviewmodel.Dynview_System,
    cache_arena: ^storage.Arena_Owner) -> bool {

    if runtime^.cache_access_state != .Worker_Mutable ||
        runtime^.cache_worker_thread_id != os.get_current_thread_id() {
        return false
    }
    if cache_arena == nil || !cache_arena^.initialized {
        dyncore.mark_stream_error(runtime, dyncore.DYNVIEW_STATUS_ILLEGAL_STATE)
        return false
    }
    return true
}

//   Translate bounded shaping storage failures into stable Dynview status values.
shaped_builder_error_status :: #force_inline proc(
    status: storage.Bounded_Builder_Status) -> i32 {

    switch status {
    case .Invalid_Argument:
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    case .Sealed:
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    case .Ok, .Limit_Exceeded, .Allocation_Failed:
        return dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY
    }
    return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Return whether the current command stream or layout inputs require compilation.
compile_is_needed :: proc(runtime: ^dynviewmodel.Dynview_System) -> bool {
    if runtime == nil || !runtime^.enabled {
        return false
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    return !cache^.is_valid || runtime^.pending_invalidation_mask != 0 ||
        cache^.compiled_revision != buffer^.revision
}

//   Return compiled text when validation succeeds without mutating compile state.
presentation_text_or_fallback :: proc(
    runtime: ^dynviewmodel.Dynview_System,
    fallback_text: string) -> string {

    if runtime == nil || !runtime^.enabled ||
        runtime^.cache_access_state != .Display_Readable ||
        !runtime^.compile_cache.is_valid ||
        runtime^.command_buffer.has_stream_error {
        return fallback_text
    }

    text_len := runtime^.compile_cache.compiled_plain_text_len
    return string(runtime^.compile_cache.compiled_plain_text[:text_len])
}

