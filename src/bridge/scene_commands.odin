package bridge

import "../core"

// Scene commands isolate asynchronous Julia callbacks from canonical display state.
// The Julia owner thread writes one bounded batch while the display thread reads an
// immutable query snapshot. The display thread validates the entire completed batch
// before applying any command, so invalid or overflowed batches cannot partially commit.

SCENE_COMMAND_BATCH_CAPACITY :: core.SCENE_COMMAND_BATCH_CAPACITY
SCENE_COMMAND_POINT_BATCH_CAPACITY :: core.SCENE_COMMAND_POINT_BATCH_CAPACITY

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
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind) -> (^Scene_Command, bool) {

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

//   Copy a bounded point-index list into one hide command.
// Invalid counts mark the complete batch overflowed so commit remains transactional.
capture_hide_point_batch_command :: proc "contextless" (
    state: ^core.Euclid_General_State, indices: [^]i32, count: i32) -> bool {

    if state^.scene_command_batch_target == nil {
        return false
    }
    command, _ := append_scene_command(state, .Hide_Point_Batch)
    if command == nil {
        return true
    }
    if count < 0 || int(count) > len(command^.point_indices) {
        batch := state^.scene_command_batch_target
        batch^.overflowed = true
        return true
    }
    command^.point_count = int(count)
    for index in 0..<int(count) {
        command^.point_indices[index] = indices[index]
    }
    return true
}

//   Capture a position payload for a tool movement or lock command.
capture_position_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, position: core.Vector3) -> bool {

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

//   Validate a complete batch against current canonical state without mutation.
// Validation also rejects stale animation identity, truncated point lists, invalid tool
// dependencies, and any prior capture overflow. Commit must remain all-or-nothing.
validate_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if state == nil || batch == nil || batch^.overflowed || state^.julia_interface == nil ||
        state^.point_system == nil || batch^.command_count < 0 ||
        batch^.command_count > len(batch^.commands) ||
        batch^.animation != state^.julia_interface^.current_animation {
        return false
    }
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        switch command^.kind {
        case .Set_Point_Position, .Set_Point_Color, .Set_Point_Brush,
            .Set_Point_Offset, .Show_Point, .Hide_Point:
            if !valid_scene_point_index(state, command^.point_index) {
                return false
            }
        case .Hide_Point_Batch:
            if command^.point_count < 0 || command^.point_count > len(command^.point_indices) {
                return false
            }
            for point_index in command^.point_indices[:command^.point_count] {
                if !valid_scene_point_index(state, int(point_index)) {
                    return false
                }
            }
        case .Lock_Pen_Joint1:
            if !valid_scene_point_index(state, state^.pen.joint1_id) ||
                state^.pen.lock_point1_id < 0 ||
                state^.pen.lock_point1_id >= state^.point_system^.next_constraint_index {
                return false
            }
        case .Move_Pen_Joint2:
            if !valid_scene_point_index(state, state^.pen.joint2_id) {
                return false
            }
        case .Set_Pen_Active, .Show_Pen, .Hide_Pen:
            if !valid_scene_point_index(state, state^.pen.host_id) {
                return false
            }
        case .Hide_Compass:
            if !valid_scene_point_index(state, state^.compass.host_id) {
                return false
            }
        case .Show_Compass, .Set_Compass_Active:
            if !valid_scene_point_index(state, state^.compass.host_id) {
                return false
            }
        case .Lock_Compass_Joint1:
            if !valid_scene_point_index(state, state^.compass.joint1_id) ||
                !valid_scene_point_index(state, state^.compass.pivot_id) ||
                state^.compass.lock_point1_id < 0 ||
                state^.compass.lock_point1_id >= state^.point_system^.next_constraint_index {
                return false
            }
        case .Lock_Compass_Joint2:
            if !valid_scene_point_index(state, state^.compass.joint2_id) ||
                !valid_scene_point_index(state, state^.compass.pivot_id) ||
                state^.compass.lock_point2_id < 0 ||
                state^.compass.lock_point2_id >= state^.point_system^.next_constraint_index {
                return false
            }
        case .Set_Animation_Meta:
            if command^.integer < 0 || command^.integer >= len(state^.anim_metadata) {
                return false
            }
        case .Set_Drawing_Sound_Enabled, .Simulate_Drawing_Sound,
            .Emit_Trailing_Particle, .Emit_Flicker_Particle,
            .Notify_Animation_Cycle_Boundary:
        }
    }
    return true
}

//   Validate and apply one completed batch in original callback order.
// This procedure runs on the display thread at the fixed-step boundary; commands may
// invoke canonical helpers that emit particles or update audio and tool state.
commit_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !validate_scene_command_batch(state, batch) {
        return false
    }
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        switch command^.kind {
        case .Set_Point_Position:
            set_point_position_with_floor_crossing_dust(
                state, command^.point_index, command^.position)
        case .Set_Point_Color:
            set_point_color(state, command^.point_index, command^.color)
        case .Set_Point_Brush:
            set_point_brush(state, command^.point_index, command^.scalar)
        case .Set_Point_Offset:
            _ = set_point_offset(state, i32(command^.point_index), command^.scalar)
        case .Show_Point:
            show_point(state, command^.point_index)
        case .Hide_Point:
            hide_point(state, command^.point_index)
        case .Hide_Point_Batch:
            hide_point_batch(
                state, &command^.point_indices[0], i32(command^.point_count))
        case .Lock_Pen_Joint1:
            lock_pen_joint1(state, command^.position)
        case .Move_Pen_Joint2:
            move_pen_joint2(state, command^.position)
        case .Set_Pen_Active:
            set_pen_active(state, command^.integer, command^.color)
        case .Show_Pen:
            show_pen(state)
        case .Hide_Pen:
            hide_pen(state)
        case .Hide_Compass:
            hide_compass(state)
        case .Show_Compass:
            show_compass(state)
        case .Set_Compass_Active:
            set_compass_active(state, command^.integer, command^.color)
        case .Lock_Compass_Joint1:
            lock_compass_joint1(state, command^.position, command^.flag)
        case .Lock_Compass_Joint2:
            lock_compass_joint2(state, command^.position, command^.flag)
        case .Set_Animation_Meta:
            set_animation_meta(state, command^.integer, command^.scalar)
        case .Set_Drawing_Sound_Enabled:
            set_drawing_sound_enabled(state, command^.flag)
        case .Simulate_Drawing_Sound:
            simulate_drawing_sound(state, command^.scalar)
        case .Emit_Trailing_Particle:
            emit_trailing_particle(state, command^.position, command^.color)
        case .Emit_Flicker_Particle:
            emit_flicker_particle(state, command^.position, command^.color)
        case .Notify_Animation_Cycle_Boundary:
            notify_animation_cycle_boundary_local(state)
        }
    }
    return true
}