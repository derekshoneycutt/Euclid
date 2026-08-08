package bridge

import "../core"

SCENE_COMMAND_BATCH_CAPACITY :: 64
SCENE_COMMAND_POINT_BATCH_CAPACITY :: 8

Scene_Command_Kind :: enum u8 {
    Set_Point_Position,
    Set_Point_Color,
    Set_Point_Brush,
    Set_Point_Offset,
    Show_Point,
    Hide_Point,
    Hide_Point_Batch,
    Lock_Pen_Joint1,
    Move_Pen_Joint2,
    Set_Pen_Active,
    Show_Pen,
    Hide_Pen,
    Hide_Compass,
    Show_Compass,
    Set_Compass_Active,
    Lock_Compass_Joint1,
    Lock_Compass_Joint2,
    Set_Animation_Meta,
    Set_Drawing_Sound_Enabled,
    Simulate_Drawing_Sound,
    Emit_Trailing_Particle,
    Emit_Flicker_Particle,
    Notify_Animation_Cycle_Boundary,
}

Scene_Command :: struct {
    kind: Scene_Command_Kind,
    point_index: int,
    position: core.Vector3,
    color: Bridge_Color,
    scalar: f32,
    integer: int,
    flag: bool,
    point_count: int,
    point_indices: [SCENE_COMMAND_POINT_BATCH_CAPACITY]i32,
}

Scene_Command_Batch :: struct {
    animation: ^core.Euclid_Julia_Animation_Interface,
    command_count: int,
    overflowed: bool,
    commands: [SCENE_COMMAND_BATCH_CAPACITY]Scene_Command,
}

Animation_Query_Snapshot :: struct {
    points: [core.MAX_SHAPESPOINTS]core.Shapes_Point,
    metadata: [core.MAX_METAVALUES]f32,
    pen: core.Shapes_Pen,
    compass: core.Shapes_Compass,
}

//   Copy canonical query state before one asynchronous animation tick.
capture_animation_query_snapshot :: proc(
    state: ^core.Euclid_General_State, snapshot: ^Animation_Query_Snapshot) {

    copy(snapshot^.points[:], state^.point_system^.points[:])
    copy(snapshot^.metadata[:], state^.anim_metadata[:])
    snapshot^.pen = state^.pen
    snapshot^.compass = state^.compass
}

//   Return worker-owned immutable query data while an asynchronous tick runs.
active_animation_query_snapshot :: proc "contextless" (
    state: ^core.Euclid_General_State) -> ^Animation_Query_Snapshot {

    return cast(^Animation_Query_Snapshot)state^.animation_query_snapshot_target
}

//   Begin worker-side capture for one animation callback.
begin_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) {

    batch^ = Scene_Command_Batch{animation = state^.julia_interface^.current_animation}
    state^.scene_command_batch_target = rawptr(batch)
}

//   End worker-side capture without applying canonical scene mutations.
end_scene_command_batch :: proc(state: ^core.Euclid_General_State) {
    state^.scene_command_batch_target = nil
}

append_scene_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind) -> (^Scene_Command, bool) {

    if state^.scene_command_batch_target == nil {
        return nil, false
    }
    batch := cast(^Scene_Command_Batch)state^.scene_command_batch_target
    if batch^.command_count >= len(batch^.commands) {
        batch^.overflowed = true
        return nil, true
    }
    command := &batch^.commands[batch^.command_count]
    command^ = Scene_Command{kind = kind}
    batch^.command_count += 1
    return command, true
}

//   Append one point-position intent to the active bounded batch.
capture_point_position_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, position: core.Vector3) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Position)
    if command != nil {
        command^.point_index = index
        command^.position = position
    }
    return captured
}

capture_point_color_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Color)
    if command != nil {
        command^.point_index = index
        command^.color = color
    }
    return captured
}

capture_point_brush_command :: proc "contextless" (
    state: ^core.Euclid_General_State, index: int, brush_size: f32) -> bool {

    command, captured := append_scene_command(state, .Set_Point_Brush)
    if command != nil {
        command^.point_index = index
        command^.scalar = brush_size
    }
    return captured
}

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

capture_point_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, index: int) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.point_index = index
    }
    return captured
}

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
        batch := cast(^Scene_Command_Batch)state^.scene_command_batch_target
        batch^.overflowed = true
        return true
    }
    command^.point_count = int(count)
    for index in 0..<int(count) {
        command^.point_indices[index] = indices[index]
    }
    return true
}

capture_position_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, position: core.Vector3) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
    }
    return captured
}

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

capture_animation_meta_command :: proc "contextless" (
    state: ^core.Euclid_General_State, position: int, metadata: f32) -> bool {

    command, captured := append_scene_command(state, .Set_Animation_Meta)
    if command != nil {
        command^.integer = position
        command^.scalar = metadata
    }
    return captured
}

capture_scalar_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, scalar: f32) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.scalar = scalar
    }
    return captured
}

capture_flag_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, flag: bool) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.flag = flag
    }
    return captured
}

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

valid_scene_point_index :: #force_inline proc(
    state: ^core.Euclid_General_State, index: int) -> bool {

    return index >= 0 && index < state^.point_system^.next_point_index
}

//   Validate a complete batch against current canonical state without mutation.
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

//   Apply a previously validated batch in command order.
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