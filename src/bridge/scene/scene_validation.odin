package bridge_scene

import bridgemodel "../model"
import shapemodel "../../shapes/model"
import animation_model "../../core/animation"
import modifier "../../animation"
import "../../core"
import "../../particles"
import math "core:math"

//   Check a command point index against the initialized canonical point span.
// Resolve one packed command identity against the current canonical world.
validate_command_shape_entity :: proc(
    state: ^core.Euclid_General_State,
    command: ^Scene_Command) -> (shapemodel.Shape_Entity, bool) {
    return bridge_shape_resolve(state, command^.entity)
}

// Validate one authored reveal descriptor against its generation-qualified target.
validate_command_animation_reveal :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    descriptor := command^.reveal
    if descriptor.owner_entity != command^.entity ||
        !shapemodel.shape_scalar_is_finite(descriptor.duration) ||
        descriptor.duration < 0 {
        return false
    }
    entity, found := validate_command_shape_entity(state, command)
    if !found {
        return false
    }
    switch descriptor.kind {
    case .Label:
        return command^.kind == .Reveal_Label &&
            shapemodel.shape_component_contains(
                &state^.shape_world.labels, &state^.shape_world.registry, entity)
    case .Region:
        if command^.kind != .Reveal_Region {
            return false
        }
        geometry, has_geometry := shapemodel.shape_component_get(
            &state^.shape_world.geometries, &state^.shape_world.registry, entity)
        return has_geometry && (geometry.kind == .Filled_Arc ||
            geometry.kind == .Circle_Region || geometry.kind == .Polygon)
    case .Sweep:
        if command^.kind != .Reveal_Sweep {
            return false
        }
        geometry, has_geometry := shapemodel.shape_component_get(
            &state^.shape_world.geometries, &state^.shape_world.registry, entity)
        return has_geometry && geometry.kind == .Filled_Arc
    }
    return false
}

// Resolve native joint sentinels without confusing them with packed shape IDs.
native_modifier_tool_entity :: proc(
    state: ^core.Euclid_General_State, entity: u64) -> shapemodel.Shape_Entity {
    switch entity {
    case 0:
        return state^.world_pen.joint1
    case 1:
        return state^.world_pen.joint2
    case 2:
        return state^.world_compass.joint1
    case 3:
        return state^.world_compass.joint2
    case:
        return shapemodel.shape_entity_unpack(entity)
    }
}

// Resolve the physical host for a native tool-style output.
native_modifier_tool_host :: proc(
    state: ^core.Euclid_General_State, entity: u64) -> u64 {
    if entity <= 1 {
        return shapemodel.shape_entity_pack(state^.world_pen.shape)
    }
    return shapemodel.shape_entity_pack(state^.world_compass.shape)
}

// Validate native tool movement against the resolved transform and snap owner.
native_modifier_tool_output_valid :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) -> bool {
    entity := native_modifier_tool_entity(state, evaluated.entity)
    if evaluated.kind == .Set_Tool_Lock {
        _, found := tool_lock_constraint(state, entity)
        return found
    }
    return shapemodel.shape_component_contains(
        &state^.shape_world.transforms, &state^.shape_world.registry, entity)
}

// Validate native point-style outputs against canonical render-style ownership.
native_modifier_style_output_valid :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) -> bool {
    command: Scene_Command = {
        entity = evaluated.entity,
    }
    entity, found := validate_command_shape_entity(state, &command)
    return found && shapemodel.shape_component_contains(
        &state^.shape_world.render_styles,
        &state^.shape_world.registry, entity)
}

// Resolve tool-host sentinels before validating their render-style ownership.
native_modifier_tool_style_output_valid :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) -> bool {
    style := evaluated^
    style.entity = native_modifier_tool_host(state, evaluated.entity)
    return evaluated.entity <= 3 && native_modifier_style_output_valid(state, &style)
}

// Require a canonical arc component for a native sweep output.
native_modifier_arc_output_valid :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) -> bool {
    entity, found := validate_command_shape_entity(
        state, &Scene_Command{
            entity = evaluated.entity,
        })
    return found && shapemodel.shape_component_contains(
        &state^.shape_world.arcs, &state^.shape_world.registry, entity)
}

// Validate native reveal ownership with the captured Julia descriptor contract.
native_sweep_reveal_valid :: proc(
    state: ^core.Euclid_General_State, evaluated: ^modifier.Modifier_Output) -> bool {
    command := native_sweep_reveal_command(evaluated)
    return validate_command_animation_reveal(state, &command)
}

// Validate every output in one native modifier evaluation.
native_modifier_output_valid :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) -> bool {
    #partial switch evaluated.kind {
    case .Reveal_Sweep:
        return native_sweep_reveal_valid(state, evaluated)
    case .Set_Shape_Orientation:
        return validate_command_shape_orientation(state, &Scene_Command{
            entity = evaluated.entity,
            orientation = evaluated.orientation,
        })
    case .Set_Conic_Sample, .Set_Conic_Active, .Set_Conic_Visible, .Set_Conic_Frontier:
        return native_conic_output_valid(state, evaluated)
    case .Set_Cycloid_Guide_Sample, .Set_Trochoid_Guide_Sample,
        .Set_Rolling_Guide_Visible, .Set_Cycloid_Frontier, .Set_Trochoid_Frontier:
        return native_rolling_output_valid(state, evaluated)
    case .Set_Tool_Position, .Set_Tool_Lock:
        return native_modifier_tool_output_valid(state, evaluated)
    case .Set_Tool_Style, .Set_Tool_Visible, .Set_Tool_Active:
        return native_modifier_tool_style_output_valid(state, evaluated)
    case .Set_Point_Position:
        return validate_command_shape_transform(
            state, &Scene_Command{
                kind = .Set_Shape_Position,
                entity = evaluated.entity,
                position = evaluated.position,
            })
    case .Set_Point_Color, .Set_Point_Brush,
        .Set_Point_Visible, .Set_Point_Active_Color,
        .Set_Point_Active_Feature:
        return native_modifier_style_output_valid(state, evaluated)
    case .Set_Shape_Arc:
        return native_modifier_arc_output_valid(state, evaluated)
    case:
        return true
    }
}

// Validate every native output against canonical shape/tool ownership.
validate_native_modifier_marker :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    if state == nil || command == nil ||
        !modifier.modifier_request_valid(command^.modifier) {
        return false
    }
    if command^.modifier.kind == .Identity {
        return true
    }
    output: modifier.Modifier_Output_Buffer
    status := modifier.evaluate_modifier(command^.modifier, &output)
    if status != .Ok || output.count <= 0 {
        return false
    }
    for output_index in 0..<output.count {
        evaluated := &output.outputs[output_index]
        if !native_modifier_output_valid(state, evaluated) {
            return false
        }
    }
    return true
}

// Validate one packed command target that requires a transform component.
validate_command_shape_transform :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && shapemodel.shape_scalar_is_finite(command.position.x) &&
        shapemodel.shape_scalar_is_finite(command.position.y) &&
        shapemodel.shape_scalar_is_finite(command.position.z) &&
        shapemodel.shape_component_contains(
        &state^.shape_world.transforms, &state^.shape_world.registry, entity)
}

// Validate one packed command target that requires a render-style component.
validate_command_shape_style :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && shapemodel.shape_component_contains(
        &state^.shape_world.render_styles, &state^.shape_world.registry, entity)
}

// Validate one complete arc mutation against host membership and value rules.
validate_command_shape_arc :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && shapemodel.shape_component_contains(
        &state^.shape_world.arcs, &state^.shape_world.registry, entity) &&
        shapemodel.shape_arc_is_valid(command^.arc)
}

// Validate one complete trochoid mutation against host membership and value rules.
validate_command_shape_trochoid :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found || !shapemodel.shape_trochoid_is_valid(command^.trochoid) {
        return false
    }
    current, has_value := shapemodel.shape_component_get(
        &state^.shape_world.trochoids, &state^.shape_world.registry, entity)
    style, has_style := shapemodel.shape_component_get(
        &state^.shape_world.render_styles, &state^.shape_world.registry, entity)
    return has_value && has_style &&
        (current.mode == command^.trochoid.mode || !style.visible)
}

// Validate one reveal frontier against the target's complete directed domain.
validate_command_shape_trochoid_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found {
        return false
    }
    value, has_value := shapemodel.shape_component_get(
        &state^.shape_world.trochoids, &state^.shape_world.registry, entity)
    return has_value && shapemodel.shape_scalar_is_finite(command^.scalar) &&
        shapemodel.shape_parameter_is_in_directed_domain(value.parameter_start,
            value.parameter_finish, command^.scalar)
}

// Validate complete guide configuration against singleton identity and visibility.
validate_command_trochoid_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape)
    if command^.entity != expected ||
        !shapemodel.shape_trochoid_tool_is_valid(command^.trochoid_tool) {
        return false
    }
    current, has_value := shapemodel.shape_component_get(
        &state^.shape_world.trochoid_tools, &state^.shape_world.registry,
        state^.world_trochoid_tool.shape)
    style, has_style := shapemodel.shape_component_get(
        &state^.shape_world.render_styles, &state^.shape_world.registry,
        state^.world_trochoid_tool.shape)
    return has_value && has_style &&
        (current.mode == command^.trochoid_tool.mode || !style.visible)
}

// Validate one finite rolling-parameter update for the singleton guide.
validate_command_trochoid_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_trochoid_tool.shape)
    return command^.entity == expected &&
        shapemodel.shape_scalar_is_finite(command^.scalar) &&
        shapemodel.shape_component_contains(&state^.shape_world.trochoid_tools,
            &state^.shape_world.registry, state^.world_trochoid_tool.shape)
}

// Resolve one canonical Cycloid host's current literal endpoint positions.
command_cycloid_line :: proc(state: ^core.Euclid_General_State,
    entity: shapemodel.Shape_Entity,
    kind: shapemodel.Shape_Geometry_Kind) -> (Command_Cycloid_Line, bool) {
    geometry, found := shapemodel.shape_component_get(
        &state^.shape_world.geometries, &state^.shape_world.registry, entity)
    if !found || geometry.kind != kind {
        return {}, false
    }
    first_entity := geometry.payload.cycloid.first
    second_entity := geometry.payload.cycloid.second
    if kind == .Cycloid_Tool {
        first_entity = geometry.payload.cycloid_tool.first
        second_entity = geometry.payload.cycloid_tool.second
    }
    first, first_ok := shapemodel.shape_component_get(
        &state^.shape_world.transforms, &state^.shape_world.registry, first_entity)
    second, second_ok := shapemodel.shape_component_get(
        &state^.shape_world.transforms, &state^.shape_world.registry, second_entity)
    if !first_ok || !second_ok {
        return {}, false
    }
    return {first.position, second.position}, true
}

// Validate one complete Cycloid mutation against its immutable literal rail.
validate_command_shape_cycloid :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found || !shapemodel.shape_component_contains(&state^.shape_world.cycloids,
        &state^.shape_world.registry, entity) ||
        !shapemodel.shape_cycloid_is_valid(command^.cycloid) {
        return false
    }
    return true
}

// Validate one Cycloid reveal frontier against its directed domain.
validate_command_shape_cycloid_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found {
        return false
    }
    value, has_value := shapemodel.shape_component_get(&state^.shape_world.cycloids,
        &state^.shape_world.registry, entity)
    return has_value && shapemodel.shape_parameter_is_in_directed_domain(
        value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate one atomic permanent-guide endpoint update against current scalar state.
validate_command_cycloid_tool_line :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    value, found := shapemodel.shape_component_get(
        &state^.shape_world.cycloid_tools, &state^.shape_world.registry,
        state^.world_cycloid_tool.shape)
    return command^.entity == expected && found &&
        shapemodel.shape_cycloid_line_is_valid(command^.position,
            command^.second_position, value.rolling_radius,
            value.parameter_start, value.parameter_finish)
}

// Validate one complete permanent Cycloid-guide scalar mutation.
validate_command_cycloid_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    if command^.entity != expected ||
        !shapemodel.shape_cycloid_tool_is_valid(command^.cycloid_tool) {
        return false
    }
    line, found := command_cycloid_line(
        state, state^.world_cycloid_tool.shape, .Cycloid_Tool)
    return found && shapemodel.shape_cycloid_line_is_valid(line.first, line.second,
        command^.cycloid_tool.rolling_radius,
        command^.cycloid_tool.parameter_start,
        command^.cycloid_tool.parameter_finish)
}

// Validate one permanent Cycloid-guide rolling parameter update.
validate_command_cycloid_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_cycloid_tool.shape)
    value, found := shapemodel.shape_component_get(
        &state^.shape_world.cycloid_tools, &state^.shape_world.registry,
        state^.world_cycloid_tool.shape)
    return command^.entity == expected && found &&
        shapemodel.shape_parameter_is_in_directed_domain(
            value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate a complete parabola update without mutating its canonical component.
validate_command_shape_parabola :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found || !shapemodel.shape_parabola_is_valid(command^.parabola) {
        return false
    }
    return shapemodel.shape_component_contains(&state^.shape_world.parabolas,
        &state^.shape_world.registry, entity)
}

// Validate a parabola frontier against the host's immutable directed domain.
validate_command_shape_parabola_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    value, present := shapemodel.shape_component_get(&state^.shape_world.parabolas,
        &state^.shape_world.registry, entity)
    return found && present && shapemodel.shape_parameter_is_in_directed_domain(
        value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate a complete update for an existing hyperbola host.
validate_command_shape_hyperbola :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found || !shapemodel.shape_hyperbola_is_valid(command^.hyperbola) {
        return false
    }
    return shapemodel.shape_component_contains(&state^.shape_world.hyperbolas,
        &state^.shape_world.registry, entity)
}

// Validate a hyperbola frontier against the host's immutable directed domain.
validate_command_shape_hyperbola_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    value, present := shapemodel.shape_component_get(&state^.shape_world.hyperbolas,
        &state^.shape_world.registry, entity)
    return found && present && shapemodel.shape_parameter_is_in_directed_domain(
        value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate complete parabola tool geometry independently from its current position.
validate_command_parabola_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_parabola_tool)
    return command^.entity == expected &&
        shapemodel.shape_component_contains(&state^.shape_world.parabola_tools,
            &state^.shape_world.registry, state^.world_parabola_tool) &&
        shapemodel.shape_parabola_tool_is_valid(command^.parabola_tool)
}

// Validate a parabola tool pose parameter against its configured domain.
validate_command_parabola_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    value, found := shapemodel.shape_component_get(&state^.shape_world.parabola_tools,
        &state^.shape_world.registry, state^.world_parabola_tool)
    return command^.entity == shapemodel.shape_entity_pack(state^.world_parabola_tool) &&
        found && shapemodel.shape_parameter_is_in_directed_domain(
            value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate the contact-highlight mutation for the permanent parabola tool.
validate_command_parabola_tool_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return command^.entity == shapemodel.shape_entity_pack(state^.world_parabola_tool) &&
        shapemodel.shape_component_contains(&state^.shape_world.parabola_tools,
            &state^.shape_world.registry, state^.world_parabola_tool)
}

// Validate complete hyperbola tool geometry independently from its position.
validate_command_hyperbola_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    expected := shapemodel.shape_entity_pack(state^.world_hyperbola_tool)
    return command^.entity == expected &&
        shapemodel.shape_component_contains(&state^.shape_world.hyperbola_tools,
            &state^.shape_world.registry, state^.world_hyperbola_tool) &&
        shapemodel.shape_hyperbola_tool_is_valid(command^.hyperbola_tool)
}

// Validate a hyperbola tool pose parameter against its configured finite domain.
validate_command_hyperbola_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    value, found := shapemodel.shape_component_get(&state^.shape_world.hyperbola_tools,
        &state^.shape_world.registry, state^.world_hyperbola_tool)
    return command^.entity == shapemodel.shape_entity_pack(state^.world_hyperbola_tool) &&
        found && shapemodel.shape_parameter_is_in_directed_domain(
            value.parameter_start, value.parameter_finish, command^.scalar)
}

// Validate the contact-highlight mutation for the permanent hyperbola tool.
validate_command_hyperbola_tool_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return command^.integer >= int(shapemodel.Hyperbola_Branches.Both) &&
        command^.integer <= int(shapemodel.Hyperbola_Branches.Negative) &&
        command^.entity == shapemodel.shape_entity_pack(state^.world_hyperbola_tool) &&
        shapemodel.shape_component_contains(&state^.shape_world.hyperbola_tools,
            &state^.shape_world.registry, state^.world_hyperbola_tool)
}

// Validate one packed command target that requires an active-feature component.
validate_command_shape_active_feature :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && shapemodel.shape_component_contains(
        &state^.shape_world.active_features, &state^.shape_world.registry, entity)
}

// Validate one packed tool target whose direct snap constraint must exist.
validate_command_tool_lock :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found {
        return false
    }
    _, constraint_found := tool_lock_constraint(state, entity)
    return constraint_found
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
        state^.julia_interface == nil {
        return false
    }
    if batch^.command_count < 0 || batch^.command_count > len(batch^.commands) {
        return false
    }
    return batch^.animation == state^.julia_interface^.current_animation
}

// Count commands that can enqueue one compound tool-contact intent.
native_modifier_tool_contact_count :: proc(request: modifier.Modifier_Request) -> int {
    output: modifier.Modifier_Output_Buffer
    status := modifier.evaluate_modifier(request, &output)
    assert(status == .Ok)
    count := 0
    for index in 0..<output.count {
        value := &output.outputs[index]
        produces_contact := value.kind == .Set_Tool_Position ||
            value.kind == .Queue_Tool_Contact ||
            (value.kind == .Set_Tool_Lock && value.flag)
        if produces_contact && tool_dust_contact_on_floor(value.position) {
            count += 1
        }
    }
    return count
}

// Count direct and native-expanded floor contacts before any owner mutation.
scene_command_batch_tool_contact_count :: proc(batch: ^Scene_Command_Batch) -> int {
    count := 0
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        if command^.kind == .Apply_Native_Modifier {
            count += native_modifier_tool_contact_count(command^.modifier)
            continue
        }
        produces_contact := command^.kind == .Set_Tool_Position ||
            (command^.kind == .Set_Tool_Lock && command^.flag)
        if produces_contact && tool_dust_contact_on_floor(command^.position) {
            count += 1
        }
    }
    return count
}

//   Validate a complete batch against current canonical state without mutation.
// Validation also rejects stale animation identity, truncated point lists, invalid tool
// dependencies, and any prior capture overflow. Commit must remain all-or-nothing.
validate_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !scene_command_batch_wellformed(state, batch) {
        return false
    }
    if !scene_command_batch_progress_valid(state, batch) {
        return false
    }
    if !scene_command_batch_reveals_fit(state, batch) {
        return false
    }
    if animation_model.animation_value_store_validate_pending(
        &state^.animation_values,
        state^.animation_values.generation,
        &batch^.animation_value_writes) != .Ok {
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
    if !scene_command_batch_planes_valid(state, batch) {
        return false
    }
    contact_count := scene_command_batch_tool_contact_count(batch)
    return contact_count == 0 || particles.can_queue_dust_tool_contacts(
        &state^.particle_system, contact_count)
}

// Validate the proposed accepted timeline against the owning animation service.
scene_command_batch_progress_valid :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {
    if math.is_nan(batch^.animation_progress) ||
        math.is_inf(batch^.animation_progress) || batch^.animation_progress < 0 {
        return false
    }
    if state^.julia_runtime_service == nil {
        return batch^.animation_progress >=
            state^.particle_system.formation.accepted_progress
    }
    service := state^.julia_runtime_service
    return batch^.animation_generation == service^.animation_generation &&
        batch^.tick_sequence > service^.animation_last_committed_sequence &&
        batch^.animation_progress >= service^.animation_progress &&
        batch^.animation_progress >=
            state^.particle_system.formation.accepted_progress
}

// Preflight reveal-record capacity after endpoint completions and same-owner supersession.
scene_command_batch_reveals_fit :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {
    formation := &state^.particle_system.formation
    live_count := 0
    for record in formation^.reveals {
        if record.active && record.animation_generation == batch^.animation_generation &&
            batch^.animation_progress < record.start_progress + f64(record.duration) {
            live_count += 1
        }
    }
    for command_index in 0..<batch^.command_count {
        command, has_reveal := scene_command_animation_reveal(
            &batch^.commands[command_index])
        if !has_reveal {
            continue
        }
        descriptor := command.reveal
        if scene_reveal_superseded_later(batch, command_index) {
            continue
        }
        existing := scene_find_live_reveal(
            formation, descriptor, batch^.animation_generation,
            batch^.animation_progress) >= 0
        if descriptor.duration == 0 && existing {
            live_count -= 1
        } else if descriptor.duration > 0 && !existing {
            live_count += 1
        }
    }
    return live_count <= len(formation^.reveals)
}

// Find whether a later descriptor supersedes this reveal in callback order.
scene_reveal_superseded_later :: proc(
    batch: ^Scene_Command_Batch, command_index: int) -> bool {
    command, has_reveal := scene_command_animation_reveal(
        &batch^.commands[command_index])
    if !has_reveal {
        return false
    }
    descriptor := command.reveal
    for later_index in command_index+1..<batch^.command_count {
        later, later_has_reveal := scene_command_animation_reveal(
            &batch^.commands[later_index])
        if later_has_reveal && later.reveal.kind == descriptor.kind &&
            later.reveal.owner_entity == descriptor.owner_entity {
            return true
        }
    }
    return false
}

// Give native sweep effects the same descriptor used by captured Julia reveals.
native_sweep_reveal_command :: proc(
    evaluated: ^modifier.Modifier_Output) -> Scene_Command {
    return {
        kind = .Reveal_Sweep,
        entity = evaluated.entity,
        reveal = {
            kind = .Sweep,
            owner_entity = evaluated.entity,
            duration = evaluated.scalar,
        },
    }
}

// Resolve a direct or native-expanded reveal for shared admission and FIFO supersession.
scene_command_animation_reveal :: proc(
    command: ^Scene_Command) -> (Scene_Command, bool) {
    #partial switch command.kind {
    case .Reveal_Label, .Reveal_Region, .Reveal_Sweep:
        return command^, true
    case .Apply_Native_Modifier:
        output: modifier.Modifier_Output_Buffer
        if modifier.evaluate_modifier(command.modifier, &output) != .Ok {
            return {}, false
        }
        for index in 0..<output.count {
            if output.outputs[index].kind == .Reveal_Sweep {
                return native_sweep_reveal_command(&output.outputs[index]), true
            }
        }
    }
    return {}, false
}

// Locate one record that survives through this batch's accepted endpoint.
scene_find_live_reveal :: proc(
    formation: ^particles.Formation_State,
    descriptor: bridgemodel.Animation_Reveal_Descriptor,
    generation: u64, progress: f64) -> int {
    target_kind := formation_target_kind(descriptor.kind)
    for index in 0..<len(formation^.reveals) {
        record := &formation^.reveals[index]
        if record^.active && record^.kind == target_kind &&
            record^.owner_entity == descriptor.owner_entity &&
            record^.animation_generation == generation &&
            progress < record^.start_progress + f64(record^.duration) {
            return index
        }
    }
    return -1
}

