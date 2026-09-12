package bridge

import "../core"
import "../particles"

import rl "vendor:raylib"

// Resolve one tool transform from the active immutable snapshot or canonical world.
tool_position :: proc(
    state: ^core.Euclid_General_State,
    entity: core.Shape_Entity) -> (core.Vector3, bool) {
    snapshot := active_animation_query_snapshot(state)
    if snapshot != nil {
        transform, found := core.shape_component_get(
            &snapshot^.shapes.transforms, &snapshot^.shapes.registry, entity)
        if found {return transform^.position, true}
        return {}, false
    }
    if state^.shape_world == nil {return {}, false}
    transform, found := core.shape_component_get(
        &state^.shape_world^.transforms, &state^.shape_world^.registry, entity)
    if !found {return {}, false}
    return transform^.position, true
}

// Resolve the direct snap constraint owned by one canonical tool joint.
tool_lock_constraint :: proc(
    state: ^core.Euclid_General_State,
    entity: core.Shape_Entity) -> (^core.Shape_Constraint, bool) {
    if state^.shape_world == nil {return nil, false}
    index: u16
    switch entity {
    case state^.world_pen.joint1:
        index = state^.world_pen.joint1_lock_constraint
    case state^.world_pen.joint2:
        index = state^.world_pen.joint2_lock_constraint
    case state^.world_compass.joint1:
        index = state^.world_compass.joint1_lock_constraint
    case state^.world_compass.joint2:
        index = state^.world_compass.joint2_lock_constraint
    case:
        return nil, false
    }
    if index >= state^.shape_world^.constraints.count {return nil, false}
    constraint := &state^.shape_world^.constraints.values[index]
    if constraint^.kind != .Snap_Point ||
        constraint^.payload.snap_point.point != entity {
        return nil, false
    }
    return constraint, true
}

// Move one canonical tool joint and emit owner-side floor contact effects.
set_tool_position :: proc(
    state: ^core.Euclid_General_State, entity: core.Shape_Entity,
    position: core.Vector3, sweep: bool) {
    command, captured := append_scene_command(state, .Set_Tool_Position)
    if command != nil {
        command^.entity = core.shape_entity_pack(entity)
        command^.position = position
        command^.flag = sweep
    }
    if captured || state^.shape_world == nil {return}
    transform, found := core.shape_component_get_mut(
        &state^.shape_world^.transforms, &state^.shape_world^.registry, entity)
    if !found {return}
    transform^.position = position
    push_dust_if_floor_contact(state, position)
    if sweep && (entity == state^.world_compass.joint1 ||
        entity == state^.world_compass.joint2) {
        first, first_found := tool_position(state, state^.world_compass.joint1)
        second, second_found := tool_position(state, state^.world_compass.joint2)
        if first_found && second_found &&
            f32(abs(first.z)) <= FLOOR_CONTACT_Z_EPSILON &&
            f32(abs(second.z)) <= FLOOR_CONTACT_Z_EPSILON {
            push_dust_along_floor_segment(state, first, second)
        }
    }
}

// Enable or disable one canonical tool joint's direct snap constraint.
set_tool_lock :: proc(
    state: ^core.Euclid_General_State, entity: core.Shape_Entity,
    position: core.Vector3, enabled, sweep: bool) {
    command, captured := append_scene_command(state, .Set_Tool_Lock)
    if command != nil {
        command^.entity = core.shape_entity_pack(entity)
        command^.position = position
        command^.flag = enabled
        command^.integer = int(sweep)
    }
    if captured {return}
    constraint, found := tool_lock_constraint(state, entity)
    if !found {return}
    if enabled {
        set_tool_position(state, entity, position, sweep)
        constraint^.payload.snap_point.position = position
    }
    constraint^.enabled = enabled
}

//   Enable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_pen :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(state, core.shape_entity_pack(state^.world_pen.shape), 1)
}

//   Disable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_pen :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(state, core.shape_entity_pack(state^.world_pen.shape), 0)
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

    context = state^.saved_context
    if active_abi < 0 || active_abi > i32(max(u16)) {return}
    packed := core.shape_entity_pack(state^.world_pen.shape)
    _ = shape_set_active_color(state, packed, color)
    _ = shape_set_active_feature(state, packed, u16(active_abi))
}

//   Clear pen active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_pen_active :: proc "c" (
    state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_active_feature(
        state, core.shape_entity_pack(state^.world_pen.shape), max(u16))
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
    context = state^.saved_context
    set_tool_lock(state, state^.world_pen.joint1, pos, true, false)
}

//   Disable the lock constraint for pen joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    set_tool_lock(state, state^.world_pen.joint1, {}, false, false)
}

//   Move pen joint1 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1.
@(export)
move_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    set_tool_position(state, state^.world_pen.joint1, pos, false)
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
    context = state^.saved_context
    position, found := tool_position(state, state^.world_pen.joint1)
    if found {return position}
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
    set_tool_lock(state, state^.world_pen.joint2, pos, true, false)
}

//   Disable the lock constraint for pen joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    set_tool_lock(state, state^.world_pen.joint2, {}, false, false)
}

//   Move pen joint2 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2.
@(export)
move_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    set_tool_position(state, state^.world_pen.joint2, pos, false)
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
    context = state^.saved_context
    position, found := tool_position(state, state^.world_pen.joint2)
    if found {return position}
    return {0, 0, 0}
}

//   Enable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_compass :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(
        state, core.shape_entity_pack(state^.world_compass.shape), 1)
}

//   Disable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_compass :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(
        state, core.shape_entity_pack(state^.world_compass.shape), 0)
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

    context = state^.saved_context
    if active_abi < 0 || active_abi > i32(max(u16)) {return}
    packed := core.shape_entity_pack(state^.world_compass.shape)
    _ = shape_set_active_color(state, packed, color)
    _ = shape_set_active_feature(state, packed, u16(active_abi))
}

//   Clear compass active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_compass_active :: proc "c" (
    state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_active_feature(
        state, core.shape_entity_pack(state^.world_compass.shape), max(u16))
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
    context = state^.saved_context
    set_tool_lock(state, state^.world_compass.joint1, pos, true, sweep)
}

//   Disable the lock constraint for compass joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    set_tool_lock(state, state^.world_compass.joint1, {}, false, false)
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
    set_tool_position(state, state^.world_compass.joint1, pos, sweep)
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
    context = state^.saved_context
    position, found := tool_position(state, state^.world_compass.joint1)
    if found {return position}
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
    context = state^.saved_context
    set_tool_lock(state, state^.world_compass.joint2, pos, true, sweep)
}

//   Disable the lock constraint for compass joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    set_tool_lock(state, state^.world_compass.joint2, {}, false, false)
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
    set_tool_position(state, state^.world_compass.joint2, pos, sweep)
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
    context = state^.saved_context
    position, found := tool_position(state, state^.world_compass.joint2)
    if found {return position}
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
