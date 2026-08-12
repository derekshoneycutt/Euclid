package view_tests

import "core:testing"

import app_bridge "../../src/bridge"
import app_core "../../src/core"
import app_dynview "../../src/dynview"

@(test)
scratchpad_history_prompt_matches_live_input_indent :: proc(t: ^testing.T) {
    prompt_style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_PROMPT)
    input_block := app_dynview.block_format_for_kind(app_bridge.BRIDGE_DYNVIEW_BLOCK_INPUT)
    output_block := app_dynview.block_format_for_kind(app_bridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT)
    merged := app_dynview.style_with_block_format(prompt_style, input_block)

    testing.expect_value(t, merged.indent_cols, 0)
    testing.expect_value(t, input_block.paragraph_spacing_before, f32(0))
    testing.expect_value(t, input_block.paragraph_spacing_after, f32(0))
    testing.expect_value(t, output_block.paragraph_spacing_before, f32(0))
    testing.expect_value(t, output_block.paragraph_spacing_after, f32(0))
}

@(test)
scratchpad_native_error_underline_style_is_stable :: proc(t: ^testing.T) {
    testing.expect_value(t,
        app_bridge.BRIDGE_DYNVIEW_STYLE_UNDERLINE,
        app_dynview.DYNVIEW_STYLE_UNDERLINE)

    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_UNDERLINE)
    testing.expect(t, style.underline)
    testing.expect_value(t, style.font_flags, app_core.Font_Variant_Flags.Regular)
}

@(test)
julia_interface_generation_slots_are_stable_and_alternate :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]

    staging, staging_index := app_bridge.julia_interface_staging_slot(state)
    testing.expect_value(t, staging_index, 1)
    testing.expect(t, staging == &state^.julia_interface_slots[1])

    state^.julia_interface_active_slot = staging_index
    state^.julia_interface = staging
    next_staging, next_staging_index := app_bridge.julia_interface_staging_slot(state)
    testing.expect_value(t, next_staging_index, 0)
    testing.expect(t, next_staging == &state^.julia_interface_slots[0])
}

@(test)
view_snapshot_rejects_recycled_interface_pointer_from_old_generation :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    animation := &state^.julia_interface_slots[0].null_animation
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.current_animation = animation
    service^.runtime_generation = 2
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    snapshot^ = app_bridge.View_Snapshot{
        runtime_generation = 0,
        animation = animation,
    }

    testing.expect(t, !app_bridge.view_snapshot_matches_current(state, service, snapshot))
    snapshot^.runtime_generation = service^.runtime_generation
    testing.expect(t, app_bridge.view_snapshot_matches_current(state, service, snapshot))
}

@(test)
scene_command_batch_commits_point_positions_in_order :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 2
    batch := app_bridge.Scene_Command_Batch{animation = animation}

    state^.scene_command_batch_target = &batch
    testing.expect(t, app_bridge.capture_point_position_command(
        state, 0, app_core.Vector3{1, 2, 3}))
    testing.expect(t, app_bridge.capture_point_position_command(
        state, 1, app_core.Vector3{4, 5, 6}))
    state^.scene_command_batch_target = nil

    testing.expect(t, app_bridge.commit_scene_command_batch(state, &batch))
    position_0, ok_0 := point_system^.points[0].position.?
    position_1, ok_1 := point_system^.points[1].position.?
    testing.expect(t, ok_0 && position_0 == app_core.Vector3{1, 2, 3})
    testing.expect(t, ok_1 && position_1 == app_core.Vector3{4, 5, 6})
}

@(test)
scene_command_batch_rejects_invalid_tail_atomically :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].position = app_core.Vector3{9, 9, 9}
    batch := app_bridge.Scene_Command_Batch{animation = animation, command_count = 2}
    batch.commands[0] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 0, position = {1, 2, 3}}
    batch.commands[1] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 1, position = {4, 5, 6}}

    testing.expect(t, !app_bridge.commit_scene_command_batch(state, &batch))
    position := point_system^.points[0].position.? or_else app_core.Vector3{}
    testing.expect(t, position == app_core.Vector3{9, 9, 9})
}

@(test)
scene_command_batch_rejects_overflow_and_stale_animation :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    current := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current)
    stale := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(stale)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current
    state^.point_system = point_system

    overflowed := app_bridge.Scene_Command_Batch{animation = current, overflowed = true}
    stale_batch := app_bridge.Scene_Command_Batch{animation = stale}
    testing.expect(t, !app_bridge.validate_scene_command_batch(state, &overflowed))
    testing.expect(t, !app_bridge.validate_scene_command_batch(state, &stale_batch))
}

@(test)
animation_tick_reject_reason_classifies_stale_generation_and_sequence :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    current := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current
    state^.julia_interface^.selected_animation = current
    service^.animation_generation = 3
    service^.animation_last_committed_sequence = 7

    slot := app_bridge.Animation_Tick_Slot{
        generation = 2,
        sequence = 8,
        animation = current,
    }
    testing.expect_value(
        t, app_bridge.animation_tick_reject_reason(state, service, &slot), "stale_generation")

    slot.generation = 3
    slot.sequence = 7
    testing.expect_value(
        t, app_bridge.animation_tick_reject_reason(state, service, &slot), "stale_sequence")
}

@(test)
scene_command_batch_defers_general_point_properties_until_commit :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].offset = 1
    batch: app_bridge.Scene_Command_Batch

    app_bridge.begin_scene_command_batch(state, &batch)
    testing.expect(t, app_bridge.capture_point_scalar_command(
        state, .Set_Point_Offset, 0, 2))
    testing.expect_value(t, point_system^.points[0].offset, f32(1))
    app_bridge.end_scene_command_batch(state)

    testing.expect(t, app_bridge.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, point_system^.points[0].offset, f32(2))
}

@(test)
scene_command_batch_rejects_invalid_implicit_compass_handle_atomically :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].position = app_core.Vector3{9, 9, 9}
    state^.compass.joint1_id = 1
    batch := app_bridge.Scene_Command_Batch{animation = animation, command_count = 2}
    batch.commands[0] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 0, position = {1, 2, 3}}
    batch.commands[1] = app_bridge.Scene_Command{kind = .Lock_Compass_Joint1}

    testing.expect(t, !app_bridge.commit_scene_command_batch(state, &batch))
    position := point_system^.points[0].position.? or_else app_core.Vector3{}
    testing.expect(t, position == app_core.Vector3{9, 9, 9})
}

@(test)
animation_query_snapshot_is_immutable_during_worker_tick :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.point_system = point_system
    state^.pen.joint1_id = 0
    state^.anim_metadata[3] = 7
    point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    snapshot: app_bridge.Animation_Query_Snapshot
    app_bridge.capture_animation_query_snapshot(state, &snapshot)

    state^.anim_metadata[3] = 11
    point_system^.points[0].position = app_core.Vector3{4, 5, 6}
    state^.animation_query_snapshot_target = &snapshot
    testing.expect_value(t, app_bridge.get_animation_meta(state, 3), f32(7))
    testing.expect(t, app_bridge.get_pen_joint1_position(state) == app_core.Vector3{1, 2, 3})
    point_view := app_bridge.get_point_view(state, 0)
    testing.expect(t, point_view.has_position && point_view.position == app_core.Vector3{1, 2, 3})
    state^.animation_query_snapshot_target = nil
}

@(test)
animation_tick_rejects_stale_generation_and_sequence :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state^.julia_interface = interface
    interface^.current_animation = animation
    interface^.selected_animation = animation
    service^.animation_generation = 4
    service^.animation_last_committed_sequence = 8
    slot := app_bridge.Animation_Tick_Slot{
        generation = 4, sequence = 9, animation = animation}

    testing.expect(t, app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.generation = 3
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.generation = 4
    slot.sequence = 8
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.sequence = 9
    interface^.pending_animation_reset = true
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
}

@(test)
animation_tick_coalescing_caps_backlog_without_queue_growth :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)

    for _ in 0..<100 {
        app_bridge.coalesce_animation_tick(service, f32(1.0 / 60.0))
    }

    testing.expect_value(t, service^.animation_accumulated_dt,
        app_bridge.MAX_ACCUMULATED_ANIMATION_DT)
    testing.expect_value(t, service^.animation_ticks_coalesced, u64(100))
}

@(test)
julia_runtime_failure_event_records_request_identity :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.active_request_id = 8
    service^.active_request_kind = .Animation_Tick
    event := app_bridge.Julia_Event{
        kind = .Invoke_Complete,
        request_kind = .Invoke,
        request_id = 7,
        succeeded = false,
    }

    app_bridge.accept_julia_event(service, event)

    testing.expect_value(t, service^.failed_request_count, u64(1))
    testing.expect_value(t, service^.last_failed_request_id, u64(7))
    testing.expect(t, service^.last_failed_request_kind == .Invoke)
    testing.expect_value(t, service^.active_request_id, u64(8))
}

@(test)
julia_runtime_terminal_failure_does_not_report_stopped :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.lifecycle = .Shutdown_Requested
    event := app_bridge.Julia_Event{
        kind = .Shutdown_Complete,
        request_kind = .Shutdown,
        request_id = 4,
        succeeded = false,
    }

    app_bridge.accept_julia_event(service, event)

    testing.expect(t, service^.lifecycle == .Failed)
}

@(test)
julia_runtime_diagnostics_report_failure_and_saturation :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.lifecycle = .Ready
    service^.failed_request_count = 3
    service^.last_failed_request_id = 12
    service^.last_failed_request_kind = .Animation_Tick
    service^.request_saturation_count = 5
    service^.reload_state = .Failed
    service^.runtime_generation = 9

    diagnostics := app_bridge.julia_runtime_diagnostics(service)

    testing.expect(t, diagnostics.lifecycle == .Ready)
    testing.expect_value(t, diagnostics.failed_request_count, u64(3))
    testing.expect_value(t, diagnostics.last_failed_request_id, u64(12))
    testing.expect(t, diagnostics.last_failed_request_kind == .Animation_Tick)
    testing.expect_value(t, diagnostics.request_saturation_count, u64(5))
    testing.expect(t, diagnostics.reload_state == .Failed)
    testing.expect_value(t, diagnostics.runtime_generation, u64(9))
}

@(test)
julia_reload_failure_records_package_revision :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)

    app_bridge.mark_julia_reload_failed(service, 1234)

    testing.expect(t, service^.reload_state == .Failed)
    testing.expect_value(t, service^.reload_failed_mtime_unix_nano, i64(1234))
    testing.expect_value(t, service^.runtime_generation, u64(0))
}

@(test)
text_wrapping_helpers_handle_empty_and_long_tokens :: proc(t: ^testing.T) {
    // Validates wrapping helpers handle empty input and long tokens while still advancing span boundaries.
    testing.expect_value(t, app_dynview.chars_per_text_row(0, 8), 1)
    testing.expect_value(t, app_dynview.count_wrapped_text_rows("", 20), 1)

    text := "supercalifragilistic"
    span := app_dynview.next_wrapped_text_span(text, 0, 4)

    testing.expect_value(t, span.line_start, 0)
    testing.expect(t, span.line_end > span.line_start)
    testing.expect(t, span.next_start > span.line_start)

    rows := app_dynview.count_wrapped_text_rows("aaaa bbbb cccc", 4)
    testing.expect(t, rows >= 3)
}

@(test)
font_weight_resolution_prefers_heaviest_requested_flag :: proc(t: ^testing.T) {
    // Ensures font-weight resolution chooses the heaviest requested weight when multiple flags are set.
    flags := app_core.Font_Variant_Flags(
        u32(app_core.Font_Variant_Flags.Light) |
        u32(app_core.Font_Variant_Flags.Bold) |
        u32(app_core.Font_Variant_Flags.Italic))

    resolved := app_core.font_resolve_weight_from_flags(flags)
    testing.expect_value(t, resolved, app_core.Font_Weight.Bold)

    heavier := app_core.Font_Variant_Flags(
        u32(flags) |
        u32(app_core.Font_Variant_Flags.ExtraBold) |
        u32(app_core.Font_Variant_Flags.Black))
    resolved_heavier := app_core.font_resolve_weight_from_flags(heavier)
    testing.expect_value(t, resolved_heavier, app_core.Font_Weight.Black)
}

@(test)
view_snapshot_copy_preserves_recursive_math_spans :: proc(t: ^testing.T) {
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    runtime := new(app_core.Dynview_System)
    defer free(runtime)

    snapshot^.command_buffer.command_count = 1
    snapshot^.command_buffer.commands[0].kind = .MathBlock
    snapshot^.math_program_count = 1
    snapshot^.math_programs[0] = app_core.Dynview_Math_Program{
        valid = true,
        root_node_index = 0,
        node_count = 1,
    }
    snapshot^.math_node_count = 1
    snapshot^.math_nodes[0].kind = .GlyphRun
    snapshot^.math_command_count = 1
    snapshot^.math_commands[0].kind = .MathGlyphRun
    runtime^.compile_cache.is_valid = true
    runtime^.compile_cache.layout_is_valid = true

    app_bridge.copy_view_snapshot_to_runtime(snapshot, runtime)

    testing.expect_value(t, runtime^.command_buffer.command_count, 1)
    testing.expect_value(t, runtime^.compile_cache.math_program_count, 1)
    testing.expect(t, runtime^.compile_cache.math_programs[0].valid)
    testing.expect_value(t, runtime^.compile_cache.math_nodes[0].kind,
        app_core.Dynview_Math_Node_Kind.GlyphRun)
    testing.expect_value(t, runtime^.compile_cache.math_commands[0].kind,
        app_core.Dynview_Command_Kind.MathGlyphRun)
    testing.expect(t, !runtime^.compile_cache.is_valid)
    testing.expect(t, !runtime^.compile_cache.layout_is_valid)
}

@(test)
view_snapshot_validation_rejects_incomplete_streams :: proc(t: ^testing.T) {
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)

    testing.expect(t, app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.command_buffer.stream_open_block = true
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.command_buffer.stream_open_block = false
    snapshot^.command_buffer.has_stream_error = true
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
}

@(test)
completed_view_snapshot_is_found_without_event_index :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.view_snapshots[0].state = .Published
    service^.view_snapshots[0].generation = 10
    service^.view_snapshots[1].state = .Complete
    service^.view_snapshots[1].generation = 11

    completed_index := app_bridge.newest_completed_view_snapshot_index(service)
    app_bridge.release_superseded_completed_view_snapshots(service, completed_index)

    testing.expect_value(t, completed_index, 1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Published)
    testing.expect_value(t, service^.view_snapshots[1].state,
        app_bridge.View_Snapshot_Slot_State.Complete)
}

@(test)
newest_completed_view_snapshot_supersedes_older_completion :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.view_snapshots[0].state = .Complete
    service^.view_snapshots[0].generation = 10
    service^.view_snapshots[1].state = .Complete
    service^.view_snapshots[1].generation = 11

    completed_index := app_bridge.newest_completed_view_snapshot_index(service)
    app_bridge.release_superseded_completed_view_snapshots(service, completed_index)

    testing.expect_value(t, completed_index, 1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Free)
    testing.expect_value(t, service^.view_snapshots[1].state,
        app_bridge.View_Snapshot_Slot_State.Complete)
}

@(test)
stale_view_snapshot_clears_previous_animation_commands :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    previous_animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(previous_animation)
    current_animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current_animation)

    service^.published_view_snapshot_index = 0
    service^.view_snapshots[0].state = .Published
    service^.view_snapshots[0].animation = previous_animation
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current_animation
    state^.dynview.command_buffer.command_count = 1

    app_bridge.clear_stale_published_view(state, service)

    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Free)
    testing.expect_value(t, state^.dynview.command_buffer.command_count, 0)
}

@(test)
dynview_text_span_and_script_attach_helpers_respect_bounds :: proc(t: ^testing.T) {
    // Validates dynview text span extraction bounds checks for base and scripted spans.
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    text := "abc"
    for i in 0..<len(text) {
        buffer.text_bytes[i] = u8(text[i])
    }
    buffer.text_bytes_len = len(text)

    span := app_dynview.text_span_from_buffer(buffer, 1, 2)
    testing.expect_value(t, span, "bc")

    out_of_bounds := app_dynview.text_span_from_buffer(buffer, 2, 5)
    testing.expect_value(t, out_of_bounds, "")

    cmd := app_core.Dynview_Command{
        script_base_text_offset = 0,
        script_base_text_len = 3,
        script_sup_text_offset = 1,
        script_sup_text_len = 1,
    }
    base_text := app_dynview.text_span_from_buffer(
        buffer,
        cmd.script_base_text_offset,
        cmd.script_base_text_len)
    testing.expect_value(t, base_text, "abc")
}

@(test)
dynview_layout_prepare_style_placement_forces_line_break_and_indent :: proc(t: ^testing.T) {
    // Verifies style placement can force a line break and apply configured indentation at the next line start.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    state := app_dynview.Dynview_Layout_State{col = 2, line_index = 0}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{item_start = 0, item_count = 1}
    style := app_dynview.Dynview_Text_Style{force_line_start = true, indent_cols = 3}

    status := app_dynview.layout_prepare_style_placement(cache, &state, &acc, style, 12)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_line_count, 1)
    testing.expect_value(t, state.line_index, 1)
    testing.expect_value(t, state.col, 3)
    testing.expect_value(t, cache.layout_lines[0].item_count, 1)
}

@(test)
dynview_layout_push_item_records_block_and_column_metadata :: proc(t: ^testing.T) {
    // Confirms pushed layout items capture block metadata and advance line-column bookkeeping correctly.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    state := app_dynview.Dynview_Layout_State{active_block_id = 7, line_index = 2, col = 1}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{}
    item := app_core.Dynview_Layout_Item{
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        col_span = 3,
        ascent = 8,
        descent = 2,
    }

    status := app_dynview.layout_push_item(cache, &state, &acc, item)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_item_count, 1)
    testing.expect_value(t, cache.layout_items[0].block_id, 7)
    testing.expect_value(t, cache.layout_items[0].col_start, 1)
    testing.expect_value(t, state.col, 4)
    testing.expect_value(t, acc.item_count, 1)
}

@(test)
dynview_layout_consume_text_run_wraps_and_places_segments :: proc(t: ^testing.T) {
    // Checks wrapped text-run consumption emits layout items and lines with a valid reported last line index.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_panel_width = 48
    cache.last_wrap_advance = 8
    cache.last_font_size = 12

    state := app_dynview.Dynview_Layout_State{}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{}
    cmd := app_core.Dynview_Command{
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        has_brush_color = true,
        brush_color = {64, 99, 216, 255},
    }
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_OUTPUT)

    status, last_line := app_dynview.layout_consume_text_run(
        cache,
        &state,
        &acc,
        cmd,
        "hello world",
        style,
        12)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect(t, cache.layout_item_count > 0)
    testing.expect(t, cache.layout_line_count > 0)
    testing.expect(t, last_line >= 0)
    for item_index in 0..<cache.layout_item_count {
        testing.expect(t, cache.layout_items[item_index].has_brush_color)
        testing.expect_value(t, cache.layout_items[item_index].brush_color.r, u8(64))
        testing.expect_value(t, cache.layout_items[item_index].brush_color.g, u8(99))
        testing.expect_value(t, cache.layout_items[item_index].brush_color.b, u8(216))
    }
}

@(test)
dynview_math_helpers_scale_script_geometry :: proc(t: ^testing.T) {
    // Ensures script math helper outputs produce sensible ascent, descent, offsets, and visual padding values.
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_BOLD)
    ascent, descent := app_dynview.style_ascent_descent(style, 12)

    testing.expect(t, ascent > descent)
    testing.expect(t, ascent > 8)

    offsets := app_dynview.script_draw_offsets(12, 1.0, 0.25, 0.25)
    top_pad, bottom_pad := app_dynview.script_visual_padding(offsets.script_font_size)

    testing.expect(t, offsets.script_font_size > 1.0)
    testing.expect(t, offsets.sup_raise_px >= 0)
    testing.expect(t, offsets.sub_drop_px >= 0)
    testing.expect(t, top_pad > 0)
    testing.expect(t, bottom_pad > 0)
}

@(test)
dynview_math_size_helpers_scale_with_content_and_kind :: proc(t: ^testing.T) {
    // Verifies delimiter and large-operator sizing helpers scale with content height and operator kind.
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_OUTPUT)

    width_none := app_dynview.stretch_delimiter_width(style, 8, 16, 10, app_dynview.DELIMITER_KIND_NONE)
    width_paren := app_dynview.stretch_delimiter_width(style, 8, 16, 50, app_dynview.DELIMITER_KIND_LEFT_PAREN)
    width_bigger := app_dynview.stretch_delimiter_width(style, 8, 16, 120, app_dynview.DELIMITER_KIND_LEFT_PAREN)

    testing.expect_value(t, width_none, f32(0))
    testing.expect(t, width_paren > 0)
    testing.expect(t, width_bigger > width_paren)

    glyph_scale_sum := app_dynview.large_op_glyph_scale(app_dynview.LARGE_OP_KIND_SUM)
    glyph_scale_int := app_dynview.large_op_glyph_scale(app_dynview.LARGE_OP_KIND_INT)
    limit_scale := app_dynview.large_op_limit_scale(0.8)
    gap := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, glyph_scale_sum > 1)
    testing.expect(t, glyph_scale_int > glyph_scale_sum)
    testing.expect(t, limit_scale > 0)
    testing.expect(t, gap > 0)
}

@(test)
dynview_measure_math_program_aggregates_child_metrics :: proc(t: ^testing.T) {
    // Confirms math program measurement aggregates child command metrics into non-zero outer dimensions.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_wrap_advance = 8
    cache^.math_program_count = 1
    cache^.math_command_count = 1

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes_len = 2

    cache^.math_commands[0] = app_core.Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }

    program := &cache^.math_programs[0]
    program^.valid = true
    program^.command_start = 0
    program^.command_count = 1

    ok := app_dynview.measure_math_program(cache, buffer, program, 12)

    testing.expect(t, ok)
    testing.expect(t, program.draw_width > 0)
    testing.expect(t, program.ascent > 0)
    testing.expect(t, program.descent > 0)
}

@(test)
dynview_math_spacing_helpers_produce_stable_positive_sizes :: proc(t: ^testing.T) {
    // Checks fraction and radical spacing helpers return positive values and scale upward with larger inputs.
    side_pad_small := app_dynview.fraction_side_padding(10, 4)
    side_pad_large := app_dynview.fraction_side_padding(24, 10)
    vert_gap_small := app_dynview.fraction_vertical_gap(10)
    vert_gap_large := app_dynview.fraction_vertical_gap(24)

    testing.expect(t, side_pad_small > 0)
    testing.expect(t, side_pad_large > side_pad_small)
    testing.expect(t, vert_gap_small > 0)
    testing.expect(t, vert_gap_large > vert_gap_small)

    lead_width := app_dynview.radical_lead_width(16, 8)
    front_pad, back_pad := app_dynview.radical_side_paddings(16, 8)
    testing.expect(t, lead_width > 0)
    testing.expect(t, front_pad > 0)
    testing.expect(t, back_pad > 0)
}

@(test)
dynview_large_operator_gap_for_integral_is_tighter_than_sum :: proc(t: ^testing.T) {
    // Verifies integral stacked-limit gap is intentionally tighter than the sum/product stacked-limit gap.
    gap_sum := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_SUM, 16, 0.25)
    gap_int := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, gap_sum > 0)
    testing.expect(t, gap_int > 0)
    testing.expect(t, gap_int < gap_sum)
}

@(test)
dynview_measure_math_program_rejects_invalid_shapes :: proc(t: ^testing.T) {
    // Ensures math program measurement rejects invalid or out-of-range command windows.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)

    invalid_program := app_core.Dynview_Math_Program{}
    invalid_program.valid = false
    testing.expect(t, !app_dynview.measure_math_program(cache, buffer, &invalid_program, 12))

    invalid_program.valid = true
    invalid_program.command_start = 0
    invalid_program.command_count = 0
    testing.expect(t, !app_dynview.measure_math_program(cache, buffer, &invalid_program, 12))

    cache^.math_command_count = 1
    invalid_program.command_start = 1
    invalid_program.command_count = 1
    testing.expect(t, !app_dynview.measure_math_program(cache, buffer, &invalid_program, 12))
}

@(test)
dynview_measure_math_program_sums_multiple_command_widths :: proc(t: ^testing.T) {
    // Confirms measured width increases when additional child commands are included in the same math program.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_wrap_advance = 8
    cache^.math_program_count = 2
    cache^.math_command_count = 2

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes[2] = 'c'
    buffer.text_bytes_len = 3

    cache^.math_commands[0] = app_core.Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }
    cache^.math_commands[1] = app_core.Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 2,
        text_len = 1,
    }

    one_cmd := &cache^.math_programs[0]
    one_cmd^.valid = true
    one_cmd^.command_start = 0
    one_cmd^.command_count = 1

    two_cmd := &cache^.math_programs[1]
    two_cmd^.valid = true
    two_cmd^.command_start = 0
    two_cmd^.command_count = 2

    ok_one := app_dynview.measure_math_program(cache, buffer, one_cmd, 12)
    ok_two := app_dynview.measure_math_program(cache, buffer, two_cmd, 12)

    testing.expect(t, ok_one)
    testing.expect(t, ok_two)
    testing.expect(t, two_cmd.draw_width > one_cmd.draw_width)
}

@(test)
dynview_reset_cache_clears_layout_state :: proc(t: ^testing.T) {
    // Verifies layout cache reset clears counters, aggregate metrics, and layout validity state.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.layout_line_count = 2
    cache.layout_item_count = 3
    cache.layout_total_height = 9
    cache.layout_average_line_height = 4
    cache.layout_is_valid = true

    app_dynview.layout_reset_cache(cache)

    testing.expect_value(t, cache.layout_line_count, 0)
    testing.expect_value(t, cache.layout_item_count, 0)
    testing.expect_value(t, cache.layout_total_height, f32(0))
    testing.expect_value(t, cache.layout_average_line_height, f32(0))
    testing.expect(t, !cache.layout_is_valid)
}

@(test)
dynview_custom_font_style_flags_decode_correctly :: proc(t: ^testing.T) {
    // Checks custom-font style ids decode expected flags and non-custom ids do not use that decoding path.
    custom_flags := app_core.Font_Variant_Flags(
        u32(app_core.Font_Variant_Flags.Light) |
        u32(app_core.Font_Variant_Flags.Bold) |
        u32(app_core.Font_Variant_Flags.Italic))

    style_id := app_dynview.DYNVIEW_STYLE_CUSTOM_FONT | i32(u32(custom_flags) &
        u32(app_dynview.DYNVIEW_STYLE_CUSTOM_FONT_MASK))
    style, ok := app_dynview.style_from_custom_font_flags(style_id)

    testing.expect(t, ok)
    testing.expect(t, style.italic)
    testing.expect_value(t, style.font_flags, custom_flags)
    testing.expect_value(t, style.wrap_scale, f32(1.0))
    testing.expect_value(t, style.line_height_multiplier, f32(1.0))

    // Non-custom style ids should not decode through the custom-font flag path.
    _, normal_ok := app_dynview.style_from_custom_font_flags(app_dynview.DYNVIEW_STYLE_OUTPUT)
    testing.expect(t, !normal_ok)
}