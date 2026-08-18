package bridge

import "../core"
import "../trace"

// Scene commands isolate asynchronous Julia callbacks from canonical display state.
// The Julia owner thread writes one bounded batch while the display thread reads an
// immutable query snapshot. The display thread validates the entire completed batch
// before applying any command, so invalid or overflowed batches cannot partially commit.

SCENE_COMMAND_BATCH_CAPACITY :: core.SCENE_COMMAND_BATCH_CAPACITY
SCENE_COMMAND_POINT_BATCH_CAPACITY :: core.SCENE_COMMAND_POINT_BATCH_CAPACITY

//   Per-kind validator shape: report whether one command is valid against state.
Scene_Command_Validator :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool

//   Dispatch table mapping each scene command kind to its validator. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_VALIDATORS :: [Scene_Command_Kind]Scene_Command_Validator{
    .Set_Point_Position = validate_command_point_index,
    .Set_Point_Color = validate_command_point_index,
    .Set_Point_Brush = validate_command_point_index,
    .Set_Point_Offset = validate_command_point_index,
    .Show_Point = validate_command_point_index,
    .Hide_Point = validate_command_point_index,
    .Hide_Point_Batch = validate_command_hide_point_batch,
    .Lock_Pen_Joint1 = validate_command_lock_pen_joint1,
    .Move_Pen_Joint2 = validate_command_move_pen_joint2,
    .Set_Pen_Active = validate_command_pen_host,
    .Show_Pen = validate_command_pen_host,
    .Hide_Pen = validate_command_pen_host,
    .Hide_Compass = validate_command_compass_host,
    .Show_Compass = validate_command_compass_host,
    .Set_Compass_Active = validate_command_compass_host,
    .Lock_Compass_Joint1 = validate_command_lock_compass_joint1,
    .Lock_Compass_Joint2 = validate_command_lock_compass_joint2,
    .Set_Animation_Meta = validate_command_animation_meta,
    .Set_Drawing_Sound_Enabled = validate_command_noop,
    .Simulate_Drawing_Sound = validate_command_noop,
    .Emit_Trailing_Particle = validate_command_noop,
    .Emit_Flicker_Particle = validate_command_noop,
    .Notify_Animation_Cycle_Boundary = validate_command_noop,
}

//   Per-kind applier shape: apply one validated command against canonical state.
Scene_Command_Applier :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command)

//   Dispatch table mapping each scene command kind to its applier. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_APPLIERS :: [Scene_Command_Kind]Scene_Command_Applier{
    .Set_Point_Position = apply_set_point_position,
    .Set_Point_Color = apply_set_point_color,
    .Set_Point_Brush = apply_set_point_brush,
    .Set_Point_Offset = apply_set_point_offset,
    .Show_Point = apply_show_point,
    .Hide_Point = apply_hide_point,
    .Hide_Point_Batch = apply_hide_point_batch,
    .Lock_Pen_Joint1 = apply_lock_pen_joint1,
    .Move_Pen_Joint2 = apply_move_pen_joint2,
    .Set_Pen_Active = apply_set_pen_active,
    .Show_Pen = apply_show_pen,
    .Hide_Pen = apply_hide_pen,
    .Hide_Compass = apply_hide_compass,
    .Show_Compass = apply_show_compass,
    .Set_Compass_Active = apply_set_compass_active,
    .Lock_Compass_Joint1 = apply_lock_compass_joint1,
    .Lock_Compass_Joint2 = apply_lock_compass_joint2,
    .Set_Animation_Meta = apply_set_animation_meta,
    .Set_Drawing_Sound_Enabled = apply_set_drawing_sound_enabled,
    .Simulate_Drawing_Sound = apply_simulate_drawing_sound,
    .Emit_Trailing_Particle = apply_emit_trailing_particle,
    .Emit_Flicker_Particle = apply_emit_flicker_particle,
    .Notify_Animation_Cycle_Boundary = apply_notify_animation_cycle_boundary,
}

// Core owns these data shapes because they are referenced by Euclid_General_State.
// Bridge owns their capture, validation, and commit behavior.
Scene_Command_Kind :: core.Scene_Command_Kind
Scene_Command :: core.Scene_Command
Scene_Command_Batch :: core.Scene_Command_Batch
Animation_Query_Snapshot :: core.Animation_Query_Snapshot

//   Copy the canonical values a Julia animation may query during one asynchronous tick.
// The snapshot remains worker-owned until that tick completes; callbacks must not read
// concurrently mutating point-system or animation metadata through another path.
capture_animation_query_snapshot :: proc(
    state: ^core.Euclid_General_State, snapshot: ^Animation_Query_Snapshot) {

    copy(snapshot^.points[:], state^.point_system^.points[:])
    copy(snapshot^.metadata[:], state^.anim_metadata[:])
    snapshot^.pen = state^.pen
    snapshot^.compass = state^.compass
}

//   Return the worker-owned immutable query snapshot active for the current callback.
// Returns nil outside scene capture; callers must preserve that distinction rather than
// falling back to canonical display state.
active_animation_query_snapshot :: proc "contextless" (
    state: ^core.Euclid_General_State) -> ^Animation_Query_Snapshot {

    return state^.animation_query_snapshot_target
}

//   Reset and attach one worker-owned command batch for the current animation callback.
// The target remains active until end_scene_command_batch and must not outlive its slot.
begin_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) {

    batch^ = Scene_Command_Batch{animation = state^.julia_interface^.current_animation}
    state^.scene_command_batch_target = batch
}

//   Detach the worker batch after callback capture without mutating canonical scene state.
end_scene_command_batch :: proc(state: ^core.Euclid_General_State) {
    state^.scene_command_batch_target = nil
}

//   Reserve and initialize one command in the active bounded batch.
// Returns captured=true when capture mode handled the operation, including overflow.
// Overflow marks the whole batch invalid and deliberately suppresses direct mutation.
append_scene_command :: proc "contextless" (
    state: ^core.Euclid_General_State,
    kind: Scene_Command_Kind) -> (^Scene_Command, bool) {

    if state^.scene_command_batch_target == nil {
        return nil, false
    }
    batch := state^.scene_command_batch_target
    if batch^.command_count >= len(batch^.commands) {
        batch^.overflowed = true
        return nil, true
    }
    command := &batch^.commands[batch^.command_count]
    command^ = Scene_Command{kind = kind}
    batch^.command_count += 1
    return command, true
}

//   Capture a point-position mutation when an asynchronous scene batch is active.
capture_point_position_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, position: core.Vector3) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Position)
    if command != nil {
        command^.point_index = index
        command^.position = position
    }
    return captured
}

//   Capture a point-color mutation while preserving the bridge color payload exactly.
capture_point_color_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Color)
    if command != nil {
        command^.point_index = index
        command^.color = color
    }
    return captured
}

//   Capture a point brush-size mutation for later display-thread validation and commit.
capture_point_brush_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, brush_size: f32) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Brush)
    if command != nil {
        command^.point_index = index
        command^.scalar = brush_size
    }
    return captured
}

//   Capture a point-indexed scalar command such as a child offset mutation.
capture_point_scalar_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    index: int, scalar: f32) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.point_index = index
        command^.scalar = scalar
    }
    return captured
}

//   Capture a point-indexed command that carries no payload beyond its target index.
capture_point_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, index: int) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.point_index = index
    }
    return captured
}

//   Copy a bounded point-index list into hide commands.
// Large batches are split into multiple commands so reset and tear-down paths do
// not invalidate the whole scene batch when they hide more points than the per-command
// point-index array can hold.
capture_hide_point_batch_command :: proc "contextless" (
    state: ^core.Euclid_General_State, indices: [^]i32, count: i32) -> bool {

    if state^.scene_command_batch_target == nil {
        return false
    }
    if count < 0 {
        batch := state^.scene_command_batch_target
        batch^.overflowed = true
        return true
    }

    remaining := int(count)
    offset := 0
    for remaining > 0 {
        command, _ := append_scene_command(state, .Hide_Point_Batch)
        if command == nil {
            batch := state^.scene_command_batch_target
            batch^.overflowed = true
            return true
        }

        chunk_size := remaining
        if chunk_size > len(command^.point_indices) {
            chunk_size = len(command^.point_indices)
        }
        command^.point_count = chunk_size
        for point_index in 0..<chunk_size {
            command^.point_indices[point_index] = indices[offset + point_index]
        }

        remaining -= chunk_size
        offset += chunk_size
    }
    return true
}

//   Capture a position payload for a tool movement or lock command.
capture_position_command :: proc "contextless" (
    state: ^core.Euclid_General_State,
    kind: Scene_Command_Kind, position: core.Vector3) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
    }
    return captured
}

//   Capture a position and boolean option used by compass lock commands.
capture_position_flag_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    position: core.Vector3, flag: bool) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
        command^.flag = flag
    }
    return captured
}

//   Capture tool activation state and its associated display color.
capture_active_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    active: int, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.integer = active
        command^.color = color
    }
    return captured
}

//   Capture one indexed animation metadata write for ordered commit with scene changes.
capture_animation_meta_command :: proc "contextless" (
    state: ^core.Euclid_General_State, position: int, metadata: f32) -> bool {

    command, captured := append_scene_command(state, .Set_Animation_Meta)
    if command != nil {
        command^.integer = position
        command^.scalar = metadata
    }
    return captured
}

//   Capture a scalar-only scene command such as simulated drawing-sound intensity.
capture_scalar_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, scalar: f32) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.scalar = scalar
    }
    return captured
}

//   Capture a boolean-only scene command such as drawing-sound enablement.
capture_flag_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, flag: bool) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.flag = flag
    }
    return captured
}

//   Capture one particle emission with the position and color observed by Julia.
capture_particle_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    position: core.Vector3, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
        command^.color = color
    }
    return captured
}

//   Check a command point index against the initialized canonical point span.
valid_scene_point_index :: #force_inline proc(
    state: ^core.Euclid_General_State, index: int) -> bool {

    return index >= 0 && index < state^.point_system^.next_point_index
}

//   Validate one point-indexed command against the canonical point span.
validate_command_point_index :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, command^.point_index)
}

//   Validate one hide-point-batch command: bounds plus every listed index.
validate_command_hide_point_batch :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    if command^.point_count < 0 ||
        command^.point_count > len(command^.point_indices) {
        return false
    }
    for point_index in command^.point_indices[:command^.point_count] {
        if !valid_scene_point_index(state, int(point_index)) {
            return false
        }
    }
    return true
}

//   Validate a pen-joint1 lock: the joint host and the constraint slot.
validate_command_lock_pen_joint1 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.pen.joint1_id) &&
        state^.pen.lock_point1_id >= 0 &&
        state^.pen.lock_point1_id < state^.point_system^.next_constraint_index
}

//   Validate a pen-joint2 move: the joint host index.
validate_command_move_pen_joint2 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.pen.joint2_id)
}

//   Validate a pen host-dependent command (active/show/hide).
validate_command_pen_host :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.pen.host_id)
}

//   Validate a compass host-dependent command (show/hide/active).
validate_command_compass_host :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.compass.host_id)
}

//   Validate a compass-joint1 lock: joint, pivot, and constraint slot.
validate_command_lock_compass_joint1 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.compass.joint1_id) &&
        valid_scene_point_index(state, state^.compass.pivot_id) &&
        state^.compass.lock_point1_id >= 0 &&
        state^.compass.lock_point1_id < state^.point_system^.next_constraint_index
}

//   Validate a compass-joint2 lock: joint, pivot, and constraint slot.
validate_command_lock_compass_joint2 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return valid_scene_point_index(state, state^.compass.joint2_id) &&
        valid_scene_point_index(state, state^.compass.pivot_id) &&
        state^.compass.lock_point2_id >= 0 &&
        state^.compass.lock_point2_id < state^.point_system^.next_constraint_index
}

//   Validate an animation-metadata write: the metadata index must be in range.
validate_command_animation_meta :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return command^.integer >= 0 && command^.integer < len(state^.anim_metadata)
}

//   Validate a command with no state dependency (always valid).
validate_command_noop :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return true
}

//   Report whether a batch is structurally usable before per-command validation.
// Rejects nil inputs, stale animation identity, truncated lists, and overflow.
scene_command_batch_wellformed :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if state == nil || batch == nil || batch^.overflowed ||
        state^.julia_interface == nil || state^.point_system == nil {
        return false
    }
    if batch^.command_count < 0 || batch^.command_count > len(batch^.commands) {
        return false
    }
    return batch^.animation == state^.julia_interface^.current_animation
}

//   Validate a complete batch against current canonical state without mutation.
// Validation also rejects stale animation identity, truncated point lists, invalid tool
// dependencies, and any prior capture overflow. Commit must remain all-or-nothing.
validate_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !scene_command_batch_wellformed(state, batch) {
        return false
    }

    validators := SCENE_COMMAND_VALIDATORS
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        validator := validators[command^.kind]
        if validator == nil || !validator(state, command) {
            return false
        }
    }
    return true
}

//   Apply one set-point-position command and record its position-change event.
apply_set_point_position :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    previous_position := state^.point_system^.points[command^.point_index].position
    set_point_position_with_floor_crossing_dust(
        state, command^.point_index, command^.position)
    _ = trace.record_point_event(
        &state^.trace_state, "point.position_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{
            from_position = previous_position,
            to_position = command^.position,
        })
}

//   Apply one set-point-color command and record its style-change event.
apply_set_point_color :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_point_color(state, i32(command^.point_index), command^.color)
    _ = trace.record_point_event(
        &state^.trace_state, "point.style_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{color = command^.color})
}

//   Apply one set-point-brush command and record its style-change event.
apply_set_point_brush :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_point_brush(state, i32(command^.point_index), command^.scalar)
    _ = trace.record_point_event(
        &state^.trace_state, "point.style_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{brush_size = command^.scalar})
}

//   Apply one set-point-offset command and record its style-change event.
apply_set_point_offset :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_point_offset(state, i32(command^.point_index), command^.scalar)
    _ = trace.record_point_event(
        &state^.trace_state, "point.style_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{offset = command^.scalar})
}

//   Apply one show-point command and record its visibility-change event.
apply_show_point :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    show_point(state, i32(command^.point_index))
    _ = trace.record_point_event(
        &state^.trace_state, "point.visibility_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{visible = true})
}

//   Apply one hide-point command and record its visibility-change event.
apply_hide_point :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    hide_point(state, i32(command^.point_index))
    _ = trace.record_point_event(
        &state^.trace_state, "point.visibility_changed", command^.point_index,
        trace.Trace_Point_Event_Fields{visible = false})
}

//   Apply one hide-point-batch command.
apply_hide_point_batch :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    hide_point_batch(state, &command^.point_indices[0], i32(command^.point_count))
}

//   Apply one pen-joint1 lock command and record its joint-change event.
apply_lock_pen_joint1 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    lock_pen_joint1(state, command^.position)
    _ = trace.record_tool_event(
        &state^.trace_state, "pen.joint_changed", "pen", "joint1",
        command^.position, nil, nil)
}

//   Apply one pen-joint2 move command and record its joint-change event.
apply_move_pen_joint2 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    move_pen_joint2(state, command^.position)
    _ = trace.record_tool_event(
        &state^.trace_state, "pen.joint_changed", "pen", "joint2",
        command^.position, nil, nil)
}

//   Apply one set-pen-active command and record its active-change event.
apply_set_pen_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_pen_active(state, i32(command^.integer), command^.color)
    _ = trace.record_tool_event(
        &state^.trace_state, "pen.active_changed", "pen", "",
        nil, nil, command^.integer)
}

//   Apply one show-pen command and record its visibility-change event.
apply_show_pen :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    show_pen(state)
    _ = trace.record_tool_event(
        &state^.trace_state, "pen.visibility_changed", "pen", "",
        nil, true, nil)
}

//   Apply one hide-pen command and record its visibility-change event.
apply_hide_pen :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    hide_pen(state)
    _ = trace.record_tool_event(
        &state^.trace_state, "pen.visibility_changed", "pen", "",
        nil, false, nil)
}

//   Apply one hide-compass command and record its visibility-change event.
apply_hide_compass :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    hide_compass(state)
    _ = trace.record_tool_event(
        &state^.trace_state, "compass.visibility_changed", "compass", "",
        nil, false, nil)
}

//   Apply one show-compass command and record its visibility-change event.
apply_show_compass :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    show_compass(state)
    _ = trace.record_tool_event(
        &state^.trace_state, "compass.visibility_changed", "compass", "",
        nil, true, nil)
}

//   Apply one set-compass-active command and record its active-change event.
apply_set_compass_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_compass_active(state, i32(command^.integer), command^.color)
    _ = trace.record_tool_event(
        &state^.trace_state, "compass.active_changed", "compass", "",
        nil, nil, command^.integer)
}

//   Apply one compass-joint1 lock command and record its joint-change event.
apply_lock_compass_joint1 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    lock_compass_joint1(state, command^.position, command^.flag)
    _ = trace.record_tool_event(
        &state^.trace_state, "compass.joint_changed", "compass", "joint1",
        command^.position, nil, nil)
}

//   Apply one compass-joint2 lock command and record its joint-change event.
apply_lock_compass_joint2 :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    lock_compass_joint2(state, command^.position, command^.flag)
    _ = trace.record_tool_event(
        &state^.trace_state, "compass.joint_changed", "compass", "joint2",
        command^.position, nil, nil)
}

//   Apply one set-animation-meta command.
apply_set_animation_meta :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_animation_meta(state, i32(command^.integer), command^.scalar)
}

//   Apply one set-drawing-sound-enabled command.
apply_set_drawing_sound_enabled :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_drawing_sound_enabled(state, command^.flag)
}

//   Apply one simulate-drawing-sound command.
apply_simulate_drawing_sound :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    simulate_drawing_sound(state, command^.scalar)
}

//   Apply one emit-trailing-particle command and record its emission.
apply_emit_trailing_particle :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    emit_trailing_particle(state, command^.position, command^.color)
    _ = trace.record_particles_emitted(
        &state^.trace_state, "trail", "mid", 1, command^.position, command^.color)
}

//   Apply one emit-flicker-particle command and record its emission.
apply_emit_flicker_particle :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    emit_flicker_particle(state, command^.position, command^.color)
    _ = trace.record_particles_emitted(
        &state^.trace_state, "flicker", "high", 10, command^.position,
        command^.color)
}

//   Apply one animation-cycle-boundary notification command.
apply_notify_animation_cycle_boundary :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    notify_animation_cycle_boundary_local(state)
}

//   Validate and apply one completed batch in original callback order.
// This procedure runs on the display thread at the fixed-step boundary; commands may
// invoke canonical helpers that emit particles or update audio and tool state.
commit_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !validate_scene_command_batch(state, batch) {
        return false
    }

    appliers := SCENE_COMMAND_APPLIERS
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        applier := appliers[command^.kind]
        if applier != nil {
            applier(state, command)
        }
    }
    return true
}