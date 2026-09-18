package bridge

import shapemodel "../shapes/model"

import "../core"
import "../particles"

import rl "vendor:raylib"

// Hold one resolved permanent Cycloid tool line.
Bridge_Cycloid_Tool_Line :: struct {
    first: rl.Vector3,
    second: rl.Vector3,
}

// Resolve one tool transform from the active immutable snapshot or canonical world.
tool_position :: proc(
    state: ^core.Euclid_General_State,
    entity: shapemodel.Shape_Entity) -> (rl.Vector3, bool) {
    snapshot := active_animation_query_snapshot(state)
    if snapshot != nil {
        transform, found := shapemodel.shape_component_get(
            &snapshot^.shapes.transforms, &snapshot^.shapes.registry, entity)
        if found {return transform^.position, true}
        return {}, false
    }
    if state^.shape_world == nil {return {}, false}
    transform, found := shapemodel.shape_component_get(
        &state^.shape_world^.transforms, &state^.shape_world^.registry, entity)
    if !found {return {}, false}
    return transform^.position, true
}

// Convert one bridge guide description into canonical tool state.
bridge_trochoid_tool_value :: proc(
    geometry: shapemodel.Bridge_Trochoid_Tool_Geometry) ->
        shapemodel.Shape_Trochoid_Tool {
    if geometry.mode < 0 ||
        geometry.mode > i32(shapemodel.Shape_Trochoid_Mode.Internal) {
        return {}
    }
    return {mode = shapemodel.Shape_Trochoid_Mode(geometry.mode),
        fixed_radius = geometry.fixed_radius, rolling_radius = geometry.rolling_radius,
        parameter = geometry.parameter, rotation = geometry.rotation,
        orientation_phase = geometry.orientation_phase}
}

// Convert one bridge description into canonical literal-line guide state.
bridge_cycloid_tool_value :: proc(
    geometry: shapemodel.Bridge_Cycloid_Tool_Geometry) ->
        shapemodel.Shape_Cycloid_Tool {
    return {rolling_radius = geometry.rolling_radius,
        parameter_start = geometry.parameter_start,
        parameter_finish = geometry.parameter_finish,
        parameter = geometry.parameter,
        orientation_phase = geometry.orientation_phase}
}

// Resolve the permanent Cycloid tool's endpoint positions from one query source.
bridge_cycloid_tool_line :: proc(source: ^Bridge_Shape_Query_Source,
    state: ^core.Euclid_General_State) -> (Bridge_Cycloid_Tool_Line, bool) {
    first, first_ok := shapemodel.shape_component_get(source^.transforms,
        source^.registry, state^.world_cycloid_tool.first)
    second, second_ok := shapemodel.shape_component_get(source^.transforms,
        source^.registry, state^.world_cycloid_tool.second)
    if !first_ok || !second_ok {
        return {}, false
    }
    return {first.position, second.position}, true
}

// Enable drawing for the process-global literal-line Cycloid guide.
@(export)
show_cycloid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    return shape_set_visible(state,
        shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape), 1)
}

// Disable drawing for the process-global literal-line Cycloid guide.
@(export)
hide_cycloid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    return shape_set_visible(state,
        shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape), 0)
}

// Atomically move both literal endpoints of the process-global Cycloid guide.
@(export)
set_cycloid_tool_line :: proc "c" (state: ^core.Euclid_General_State,
    first, second: rl.Vector3) -> i32 {
    context = state^.saved_context
    source, available := bridge_shape_query_source(state)
    if !available {
        return BRIDGE_STATUS_NOT_FOUND
    }
    current, found := shapemodel.shape_component_get(source.cycloid_tools,
        source.registry, state^.world_cycloid_tool.shape)
    if !found || !shapemodel.shape_cycloid_line_is_valid(first, second,
        current.rolling_radius, current.parameter_start, current.parameter_finish) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    packed := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    command, captured := append_scene_command(state, .Set_Cycloid_Tool_Line)
    if command != nil {
        command^.entity = packed
        command^.position = first
        command^.second_position = second
    }
    if captured {return BRIDGE_STATUS_OK}
    first_transform, first_ok := shapemodel.shape_component_get_mut(
        &state^.shape_world^.transforms, &state^.shape_world^.registry,
        state^.world_cycloid_tool.first)
    second_transform, second_ok := shapemodel.shape_component_get_mut(
        &state^.shape_world^.transforms, &state^.shape_world^.registry,
        state^.world_cycloid_tool.second)
    if !first_ok || !second_ok {return BRIDGE_STATUS_NOT_FOUND}
    first_transform.position = first
    second_transform.position = second
    return BRIDGE_STATUS_OK
}

// Atomically configure the process-global Cycloid guide's scalar state.
@(export)
set_cycloid_tool_geometry :: proc "c" (state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Cycloid_Tool_Geometry) -> i32 {
    context = state^.saved_context
    value := bridge_cycloid_tool_value(geometry)
    source, available := bridge_shape_query_source(state)
    if !available || !shapemodel.shape_cycloid_tool_is_valid(value) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    line, line_ok := bridge_cycloid_tool_line(&source, state)
    if !line_ok || !shapemodel.shape_cycloid_line_is_valid(line.first, line.second,
        value.rolling_radius, value.parameter_start, value.parameter_finish) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    packed := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    command, captured := append_scene_command(state, .Set_Cycloid_Tool)
    if command != nil {
        command^.entity = packed
        command^.cycloid_tool = value
    }
    if captured {return BRIDGE_STATUS_OK}
    current, found := shapemodel.shape_component_get_mut(
        &state^.shape_world^.cycloid_tools, &state^.shape_world^.registry,
        state^.world_cycloid_tool.shape)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    previous := current^
    current^ = value
    current.previous_rolling_radius = previous.previous_rolling_radius
    current.previous_parameter_start = previous.previous_parameter_start
    current.previous_parameter_finish = previous.previous_parameter_finish
    current.previous_parameter = previous.previous_parameter
    current.previous_orientation_phase = previous.previous_orientation_phase
    return BRIDGE_STATUS_OK
}

// Change only the process-global Cycloid guide's rolling parameter.
@(export)
set_cycloid_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State, parameter: f32) -> i32 {
    context = state^.saved_context
    source, available := bridge_shape_query_source(state)
    if !available {return BRIDGE_STATUS_NOT_FOUND}
    current, found := shapemodel.shape_component_get(source.cycloid_tools,
        source.registry, state^.world_cycloid_tool.shape)
    if !found || !shapemodel.shape_parameter_is_in_directed_domain(
        current.parameter_start, current.parameter_finish, parameter) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    packed := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    command, captured := append_scene_command(state, .Set_Cycloid_Tool_Parameter)
    if command != nil {
        command^.entity = packed
        command^.scalar = parameter
    }
    if captured {return BRIDGE_STATUS_OK}
    mutable, has_value := shapemodel.shape_component_get_mut(
        &state^.shape_world^.cycloid_tools, &state^.shape_world^.registry,
        state^.world_cycloid_tool.shape)
    if !has_value {return BRIDGE_STATUS_NOT_FOUND}
    mutable.parameter = parameter
    return BRIDGE_STATUS_OK
}

// Enable drawing for the process-global two-ring trochoid guide.
@(export)
show_trochoid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    return shape_set_visible(state,
        shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape), 1)
}

// Disable drawing for the process-global two-ring trochoid guide.
@(export)
hide_trochoid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    return shape_set_visible(state,
        shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape), 0)
}

// Move the process-global guide's fixed center and constant elevation.
@(export)
set_trochoid_tool_position :: proc "c" (
    state: ^core.Euclid_General_State, position: rl.Vector3) -> i32 {
    context = state^.saved_context
    return shape_set_position(state,
        shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape), position)
}

// Atomically configure the process-global guide's complete analytic state.
@(export)
set_trochoid_tool_geometry :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Trochoid_Tool_Geometry) -> i32 {
    context = state^.saved_context
    value := bridge_trochoid_tool_value(geometry)
    if !shapemodel.shape_trochoid_tool_is_valid(value) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    packed := shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape)
    command, captured := append_scene_command(state, .Set_Trochoid_Tool)
    if command != nil {
        command^.entity = packed
        command^.trochoid_tool = value
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    current, has_value := shapemodel.shape_component_get_mut(
        &state^.shape_world^.trochoid_tools, &state^.shape_world^.registry, entity)
    if !has_value {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := shapemodel.shape_component_get(
        &state^.shape_world^.render_styles, &state^.shape_world^.registry, entity)
    if !has_style || current.mode != value.mode && style.visible {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    previous := current^
    current^ = value
    current.previous_fixed_radius = previous.previous_fixed_radius
    current.previous_rolling_radius = previous.previous_rolling_radius
    current.previous_parameter = previous.previous_parameter
    current.previous_rotation = previous.previous_rotation
    current.previous_orientation_phase = previous.previous_orientation_phase
    return BRIDGE_STATUS_OK
}

// Change only the process-global guide's rolling parameter.
@(export)
set_trochoid_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State, parameter: f32) -> i32 {
    context = state^.saved_context
    if !shapemodel.shape_scalar_is_finite(parameter) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    packed := shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape)
    command, captured := append_scene_command(state, .Set_Trochoid_Tool_Parameter)
    if command != nil {
        command^.entity = packed
        command^.scalar = parameter
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    current, has_value := shapemodel.shape_component_get_mut(
        &state^.shape_world^.trochoid_tools, &state^.shape_world^.registry, entity)
    if !has_value {return BRIDGE_STATUS_NOT_FOUND}
    current.parameter = parameter
    return BRIDGE_STATUS_OK
}

// Resolve the direct snap constraint owned by one canonical tool joint.
tool_lock_constraint :: proc(
    state: ^core.Euclid_General_State,
    entity: shapemodel.Shape_Entity) -> (^shapemodel.Shape_Constraint, bool) {
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
    state: ^core.Euclid_General_State, entity: shapemodel.Shape_Entity,
    position: rl.Vector3, sweep: bool) {
    command, captured := append_scene_command(state, .Set_Tool_Position)
    if command != nil {
        command^.entity = shapemodel.shape_entity_pack(entity)
        command^.position = position
        command^.flag = sweep
    }
    if captured || state^.shape_world == nil {return}
    previous_first, previous_first_found := tool_position(
        state, state^.world_compass.joint1)
    previous_second, previous_second_found := tool_position(
        state, state^.world_compass.joint2)
    transform, found := shapemodel.shape_component_get_mut(
        &state^.shape_world^.transforms, &state^.shape_world^.registry, entity)
    if !found {return}
    transform^.position = position
    if sweep && entity == state^.world_compass.joint2 &&
        previous_first_found && previous_second_found {
        current_first, current_first_found := tool_position(
            state, state^.world_compass.joint1)
        current_second, current_second_found := tool_position(
            state, state^.world_compass.joint2)
        if current_first_found && current_second_found {
            queue_compass_filled_dust_contact(state, previous_first,
                previous_second, current_first, current_second)
            return
        }
    }
    queue_tool_dust_contact(state, position)
}

// Enable or disable one canonical tool joint's direct snap constraint.
set_tool_lock :: proc(
    state: ^core.Euclid_General_State, entity: shapemodel.Shape_Entity,
    position: rl.Vector3, enabled, sweep: bool) {
    command, captured := append_scene_command(state, .Set_Tool_Lock)
    if command != nil {
        command^.entity = shapemodel.shape_entity_pack(entity)
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
    _ = shape_set_visible(state, shapemodel.shape_entity_pack(state^.world_pen.shape), 1)
}

//   Disable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_pen :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(state, shapemodel.shape_entity_pack(state^.world_pen.shape), 0)
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
    packed := shapemodel.shape_entity_pack(state^.world_pen.shape)
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
        state, shapemodel.shape_entity_pack(state^.world_pen.shape), max(u16))
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
lock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: rl.Vector3) {
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
move_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: rl.Vector3) {
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
get_pen_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> rl.Vector3 {
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
lock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: rl.Vector3) {
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
move_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: rl.Vector3) {
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
get_pen_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> rl.Vector3 {
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
        state, shapemodel.shape_entity_pack(state^.world_compass.shape), 1)
}

//   Disable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_compass :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    _ = shape_set_visible(
        state, shapemodel.shape_entity_pack(state^.world_compass.shape), 0)
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
    packed := shapemodel.shape_entity_pack(state^.world_compass.shape)
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
        state, shapemodel.shape_entity_pack(state^.world_compass.shape), max(u16))
}

//   Move compass joint1, optionally emit sweep dust, and enable its lock constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
lock_compass_joint1 :: proc "c" (
    state: ^core.Euclid_General_State, pos: rl.Vector3, sweep: bool) {
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
    state: ^core.Euclid_General_State, pos: rl.Vector3, sweep: bool) {
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
    state: ^core.Euclid_General_State) -> rl.Vector3 {
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
    state: ^core.Euclid_General_State, pos: rl.Vector3, sweep: bool) {
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
    state: ^core.Euclid_General_State, pos: rl.Vector3, sweep: bool) {
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
    state: ^core.Euclid_General_State) -> rl.Vector3 {
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
    state: ^core.Euclid_General_State, pos: rl.Vector3, color: Bridge_Color) {

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
    state: ^core.Euclid_General_State, pos: rl.Vector3, color: Bridge_Color) {

    if capture_particle_command(state, .Emit_Flicker_Particle, pos, color) {
        return
    }
    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_flicker_particles(
        state^.particle_system, {pos, rl_color}, 10)
}
