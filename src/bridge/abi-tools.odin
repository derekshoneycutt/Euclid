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
get_Shapes_anim_points_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
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
get_Shapes_anim_constraints_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
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
freeze_Shapes_animation_boundary :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
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
clear_Shapes_animation_data :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    shapes.clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    return BRIDGE_STATUS_OK
}

//   Read compile-time point capacity exposed by the bridge ABI.
//
// Returns:
//   - Maximum number of shapes points.
@(export)
get_max_Shapes_points :: proc "c" () -> i32 {
    return i32(MAX_SHAPESPOINTS)
}

//   Read compile-time constraint capacity exposed by the bridge ABI.
//
// Returns:
//   - Maximum number of shapes constraints.
@(export)
get_max_Shapes_constraints :: proc "c" () -> i32 {
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
validate_Shapes_graph :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context

    for i in 0..<MAX_SHAPESPOINTS {
        point := state^.point_system^.points[i]
        if point.child_point_head >= 0 {
            validateStatus := validate_parent_child_chain(state, i32(i))
            if validateStatus != BRIDGE_STATUS_OK {
                return validateStatus
            }
        }
    }

    for i in 0..<MAX_SHAPESCONSTRAINTS {
        constraint := state^.point_system^.constraints[i]
        if constraint.do_apply {
            if !is_point_index_in_bounds(constraint.on_point) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
            if constraint.depend_on >= 0 && !is_constraint_index_in_bounds(int(constraint.depend_on)) {
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
    state: ^core.Euclid_General_State, active: int, color: Bridge_Color) {

    index := state^.pen.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rlColor
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
    state^.drawing_sound_enabled = enabled
}

//   Accumulate drawing-sound activity for the current frame.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - speed: Requested speed; negative values are clamped to zero.
@(export)
simulate_drawing_sound :: proc "c" (state: ^core.Euclid_General_State, speed: f32) {
    if !state^.drawing_sound_enabled {
        return
    }

    use_speed := speed
    if use_speed < 0 {
        use_speed = 0
    }

    state^.chalk_audio.has_contact_this_frame = true
    if use_speed > state^.chalk_audio.accum_speed {
        state^.chalk_audio.accum_speed = use_speed
    }
}

//   Move pen joint1 and enable its lock constraint at the same position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
@(export)
lock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint1_id
    constraintIndex := state^.pen.lock_point1_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
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
    index := state^.pen.joint1_id
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
    constraintIndex := state^.pen.lock_point2_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
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
    index := state^.pen.joint2_id
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
    state: ^core.Euclid_General_State, active: int, color: Bridge_Color) {

    index := state^.compass.host_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rlColor
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
lock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    pointIndex := state^.compass.joint1_id
    pivotIndex := state^.compass.pivot_id
    constraintIndex := state^.compass.lock_point1_id
    if pointIndex > 0 && pointIndex < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, pointIndex, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }
    
        pointpos := state^.point_system^.points[pointIndex].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
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
move_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint1_id
    pivotIndex := state^.compass.pivot_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[index].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
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
get_compass_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.compass.joint1_id
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
lock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    pointIndex := state^.compass.joint2_id
    pivotIndex := state^.compass.pivot_id
    constraintIndex := state^.compass.lock_point2_id
    if pointIndex > 0 && pointIndex < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, pointIndex, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[pointIndex].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_SHAPESCONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
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
move_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint2_id
    pivotIndex := state^.compass.pivot_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_dust_effects(state, index, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[index].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
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
get_compass_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.compass.joint2_id
    if index >= 0 && index < MAX_SHAPESPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Store animation metadata at a slot index.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Metadata slot index.
//   - metadata: Value to store when pos is in range.
@(export)
set_animation_meta :: proc "c" (state: ^core.Euclid_General_State, pos: int, metadata: f32) {
    if pos >= 0 && pos < len(state^.anim_metadata) {
        state^.anim_metadata[pos] = metadata
    }
}

//   Read animation metadata from a slot index.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Metadata slot index.
//
// Returns:
//   - Metadata value when pos is in range, otherwise 0.
@(export)
get_animation_meta :: proc "c" (state: ^core.Euclid_General_State, pos: int) -> f32 {
    if pos >= 0 && pos <= len(state^.anim_metadata) {
        return state^.anim_metadata[pos]
    }
    return 0
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

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_trail_particles(
        state^.particle_system, state^.current_delta_time, pos.x, pos.y, pos.z, rlColor)
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

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_flicker_particles(state^.particle_system, pos.x, pos.y, pos.z, rlColor, 10)
}
