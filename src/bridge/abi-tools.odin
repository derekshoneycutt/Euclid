package bridge

import "../core"
import "../particles"
import "../shapes"

import rl "vendor:raylib"

//   Read the current pen shape handle from runtime state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current pen handle, including host and joint indices.
@(export)
get_pen_view :: proc "c" (state: ^core.Euclid_General_State) -> core.Shapes_Pen {
    return state^.pen
}

//   Read the current compass shape handle from runtime state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current compass handle, including host, pivot, and joint indices.
@(export)
get_compass_view :: proc "c" (state: ^core.Euclid_General_State) -> core.Shapes_Compass {
    return state^.compass
}

//   Read the first point index owned by animation data.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Animation point-start index.
@(export)
get_shapes_anim_points_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.anim_points_start)
}

//   Read the first constraint index owned by animation data.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Animation constraint-start index.
@(export)
get_shapes_anim_constraints_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.anim_constraints_start)
}

//   Freeze current point and constraint next indices as the animation boundary.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK after boundary indices are captured.
@(export)
freeze_shapes_animation_boundary :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    shapes.freeze_system_indices(state^.point_system)
    return BRIDGE_STATUS_OK
}

//   Clear all animation-owned points and constraints.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK after animation data is cleared.
@(export)
clear_shapes_animation_data :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    shapes.clear_animation_data(
        state^.point_system, state^.particle_system, state^.iso_scale)
    return BRIDGE_STATUS_OK
}

//   Read compile-time point capacity exposed by the bridge ABI.
//
// Returns:
//   - Maximum number of shapes points.
@(export)
get_max_shapes_points :: proc "c" () -> i32 {
    return i32(MAX_SHAPESPOINTS)
}

//   Read compile-time constraint capacity exposed by the bridge ABI.
//
// Returns:
//   - Maximum number of shapes constraints.
@(export)
get_max_shapes_constraints :: proc "c" () -> i32 {
    return i32(MAX_SHAPESCONSTRAINTS)
}

//   Validate point child chains and enabled constraint references.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when graph invariants hold.
//   - BRIDGE_STATUS_INVALID_GRAPH when a child chain fails validation.
//   - BRIDGE_STATUS_INVALID_CONSTRAINT when enabled constraints reference invalid indices.
@(export)
validate_shapes_graph :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context

    for i in 0..<MAX_SHAPESPOINTS {
        point := state^.point_system^.points[i]
        if point.child_point_head >= 0 {
            validate_status := validate_parent_child_chain(state, i32(i))
            if validate_status != BRIDGE_STATUS_OK {
                return validate_status
            }
        }
    }

    for i in 0..<MAX_SHAPESCONSTRAINTS {
        constraint := state^.point_system^.constraints[i]
        if constraint.do_apply {
            if !is_point_index_in_bounds(constraint.on_point) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
            if constraint.depend_on >= 0 &&
                !is_constraint_index_in_bounds(int(constraint.depend_on)) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
        }
    }

    return BRIDGE_STATUS_OK
}


//   Enable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_pen :: proc "c" (state: ^core.Euclid_General_State) {
    if capture_point_command(state, .Show_Pen, state^.pen.host_id) {
        return
    }
    index := state^.pen.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].do_draw = true
    }
}

//   Disable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_pen :: proc "c" (state: ^core.Euclid_General_State) {
    if capture_point_command(state, .Hide_Pen, state^.pen.host_id) {
        return
    }
    index := state^.pen.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].do_draw = false
    }
}

//   Set pen active marker index and active highlight color.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child marker index.
//   - color: RGBA highlight color payload in bridge format.
@(export)
set_pen_active :: proc "c" (
    state: ^core.Euclid_General_State, active_abi: i32, color: Bridge_Color) {

    active := int(active_abi)
    if capture_active_command(state, .Set_Pen_Active, active, color) {
        return
    }
    index := state^.pen.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rl_color := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rl_color
        state^.point_system^.points[index].active_child = active
    }
}

//   Clear pen active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_pen_active :: proc "c" (
    state: ^core.Euclid_General_State) {

    index := state^.pen.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].active_child = -1
    }
}

//   Enable or disable drawing-sound accumulation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - enabled: When true, drawing-sound updates are accepted.
@(export)
set_drawing_sound_enabled :: proc "c" (state: ^core.Euclid_General_State, enabled: bool) {
    if capture_flag_command(state, .Set_Drawing_Sound_Enabled, enabled) {
        return
    }
    state^.animation_drawing_sound_enabled = enabled
}

//   Activate the steady drawing-sound texture for the current frame.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - speed: Retained for ABI compatibility; texture level is contact-based.
@(export)
simulate_drawing_sound :: proc "c" (state: ^core.Euclid_General_State, speed: f32) {
    if capture_scalar_command(state, .Simulate_Drawing_Sound, speed) {
        return
    }
    if !state^.user_drawing_sound_enabled || !state^.animation_drawing_sound_enabled {
        return
    }

    state^.chalk_audio.has_contact_this_frame = true
}

//   Move pen joint1 and enable its lock constraint at the same position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
@(export)
lock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    if capture_position_command(state, .Lock_Pen_Joint1, pos) {
        return
    }
    context = state^.saved_context
    index := state^.pen.joint1_id
    constraint_index := state^.pen.lock_point1_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
    if constraint_index >= 0 && constraint_index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraint_index].restriction = pos
        state^.point_system^.constraints[constraint_index].do_apply = true
    }
}

//   Disable the lock constraint for pen joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.lock_point1_id
    if index >= 0 && index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Move pen joint1 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1.
@(export)
move_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint1_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
}

//   Read pen joint1 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint1 position, or {0, 0, 0} when joint1 is unavailable.
@(export)
get_pen_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    pen := state^.pen
    query_snapshot := active_animation_query_snapshot(state)
    if query_snapshot != nil {
        pen = query_snapshot^.pen
    }
    index := pen.joint1_id
    if query_snapshot != nil && index >= 0 && index < MAX_SHAPESPOINTS {
        return query_snapshot^.points[index].position.? or_else {0, 0, 0}
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Move pen joint2 and enable its lock constraint at the same position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2 and its lock restriction.
@(export)
lock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint2_id
    constraint_index := state^.pen.lock_point2_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
    if constraint_index >= 0 && constraint_index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraint_index].restriction = pos
        state^.point_system^.constraints[constraint_index].do_apply = true
    }
}

//   Disable the lock constraint for pen joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.lock_point2_id
    if index >= 0 && index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Move pen joint2 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2.
@(export)
move_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    if capture_position_command(state, .Move_Pen_Joint2, pos) {
        return
    }
    context = state^.saved_context
    index := state^.pen.joint2_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
}

//   Read pen joint2 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint2 position, or {0, 0, 0} when joint2 is unavailable.
@(export)
get_pen_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    pen := state^.pen
    query_snapshot := active_animation_query_snapshot(state)
    if query_snapshot != nil {
        pen = query_snapshot^.pen
    }
    index := pen.joint2_id
    if query_snapshot != nil && index >= 0 && index < MAX_SHAPESPOINTS {
        return query_snapshot^.points[index].position.? or_else {0, 0, 0}
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Enable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_compass :: proc "c" (state: ^core.Euclid_General_State) {
    if capture_point_command(state, .Show_Compass, state^.compass.host_id) {
        return
    }
    index := state^.compass.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].do_draw = true
    }
}

//   Disable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_compass :: proc "c" (state: ^core.Euclid_General_State) {
    if capture_point_command(state, .Hide_Compass, state^.compass.host_id) {
        return
    }
    index := state^.compass.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].do_draw = false
    }
}

//   Set compass active marker index and active highlight color.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child marker index.
//   - color: RGBA highlight color payload in bridge format.
@(export)
set_compass_active :: proc "c" (
    state: ^core.Euclid_General_State, active_abi: i32, color: Bridge_Color) {

    active := int(active_abi)
    if capture_active_command(state, .Set_Compass_Active, active, color) {
        return
    }
    index := state^.compass.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rl_color := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rl_color
        state^.point_system^.points[index].active_child = active
    }
}

//   Clear compass active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_compass_active :: proc "c" (
    state: ^core.Euclid_General_State) {

    index := state^.compass.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].active_child = -1
    }
}

//   Move compass joint1, optionally emit sweep dust, and enable its lock constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
lock_compass_joint1 :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    if capture_position_flag_command(state, .Lock_Compass_Joint1, pos, sweep) {
        return
    }
    context = state^.saved_context
    point_index := state^.compass.joint1_id
    pivot_index := state^.compass.pivot_id
    constraint_index := state^.compass.lock_point1_id
    if point_index > 0 && point_index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, point_index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }
    
        point := &state^.point_system^.points[point_index]
        pivot := &state^.point_system^.points[pivot_index]
        pointpos := point^.position.? or_else { 0, 0, 0 }
        pivotpos := pivot^.position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            pivot^.position = core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraint_index >= 0 && constraint_index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraint_index].restriction = pos
        state^.point_system^.constraints[constraint_index].do_apply = true
    }
}

//   Disable the lock constraint for compass joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.lock_point1_id
    if index >= 0 && index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Move compass joint1 and optionally emit sweep dust.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
move_compass_joint1 :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint1_id
    pivot_index := state^.compass.pivot_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        point := &state^.point_system^.points[index]
        pivot := &state^.point_system^.points[pivot_index]
        pointpos := point^.position.? or_else { 0, 0, 0 }
        pivotpos := pivot^.position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            pivot^.position = core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

//   Read compass joint1 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint1 position, or {0, 0, 0} when joint1 is unavailable.
@(export)
get_compass_joint1_position :: proc "c" (
    state: ^core.Euclid_General_State) -> core.Vector3 {
    compass := state^.compass
    query_snapshot := active_animation_query_snapshot(state)
    if query_snapshot != nil {
        compass = query_snapshot^.compass
    }
    index := compass.joint1_id
    if query_snapshot != nil && index >= 0 && index < MAX_SHAPESPOINTS {
        return query_snapshot^.points[index].position.? or_else {0, 0, 0}
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Move compass joint2, optionally emit sweep dust, and enable its lock constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2 and its lock restriction.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
lock_compass_joint2 :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    if capture_position_flag_command(state, .Lock_Compass_Joint2, pos, sweep) {
        return
    }
    context = state^.saved_context
    point_index := state^.compass.joint2_id
    pivot_index := state^.compass.pivot_id
    constraint_index := state^.compass.lock_point2_id
    if point_index > 0 && point_index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, point_index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        point := &state^.point_system^.points[point_index]
        pivot := &state^.point_system^.points[pivot_index]
        pointpos := point^.position.? or_else { 0, 0, 0 }
        pivotpos := pivot^.position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            pivot^.position = core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraint_index >= 0 && constraint_index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraint_index].restriction = pos
        state^.point_system^.constraints[constraint_index].do_apply = true
    }
}

//   Disable the lock constraint for compass joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.lock_point2_id
    if index >= 0 && index < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Move compass joint2 and optionally emit sweep dust.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
move_compass_joint2 :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint2_id
    pivot_index := state^.compass.pivot_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        point := &state^.point_system^.points[index]
        pivot := &state^.point_system^.points[pivot_index]
        pointpos := point^.position.? or_else { 0, 0, 0 }
        pivotpos := pivot^.position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            pivot^.position = core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

//   Read compass joint2 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint2 position, or {0, 0, 0} when joint2 is unavailable.
@(export)
get_compass_joint2_position :: proc "c" (
    state: ^core.Euclid_General_State) -> core.Vector3 {
    compass := state^.compass
    query_snapshot := active_animation_query_snapshot(state)
    if query_snapshot != nil {
        compass = query_snapshot^.compass
    }
    index := compass.joint2_id
    if query_snapshot != nil && index >= 0 && index < MAX_SHAPESPOINTS {
        return query_snapshot^.points[index].position.? or_else {0, 0, 0}
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Emit trailing particles at a position using bridge color data.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Particle emission position.
//   - color: RGBA color payload in bridge format.
@(export)
emit_trailing_particle :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, color: Bridge_Color) {

    if capture_particle_command(state, .Emit_Trailing_Particle, pos, color) {
        return
    }
    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_trail_particles(
        state^.particle_system, state^.current_delta_time, {pos, rl_color})
}

//   Emit flicker particles at a position using bridge color data.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Particle emission position.
//   - color: RGBA color payload in bridge format.
@(export)
emit_flicker_particle :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, color: Bridge_Color) {

    if capture_particle_command(state, .Emit_Flicker_Particle, pos, color) {
        return
    }
    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_flicker_particles(
        state^.particle_system, {pos, rl_color}, 10)
}
