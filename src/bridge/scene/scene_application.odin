package bridge_scene

import bridge_events "../events"
import bridgemodel "../model"
import shapemodel "../../shapes/model"
import audio "../../audio"
import animation_model "../../core/animation"
import modifier "../../animation"
import "../../core"
import "../../particles"

// Apply one validated packed-entity transform mutation.
apply_set_shape_position :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    entity := shapemodel.shape_entity_unpack(command.entity)
    value, found := shapemodel.shape_component_get_mut(
        &state.shape_world.transforms, &state.shape_world.registry, entity)
    assert(found)
    value.position = command.position
}

// Apply one packed tool transform mutation with its owner-side effects.
apply_set_tool_position :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_tool_position(state, shapemodel.shape_entity_unpack(command^.entity),
        command^.position, command^.flag)
}

// Apply one packed tool snap-lock mutation.
apply_set_tool_lock :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_tool_lock(state, shapemodel.shape_entity_unpack(command^.entity),
        command^.position, command^.flag, command^.integer != 0)
}

// Apply one validated packed-entity color mutation.
apply_set_shape_color :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_color(state, command^.entity, command^.color)
}

// Apply one validated packed-entity active-color mutation.
apply_set_shape_active_color :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_active_color(state, command^.entity, command^.color)
}

// Apply one validated packed-entity brush mutation.
apply_set_shape_brush :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_brush_size(state, command^.entity, command^.scalar)
}

// Apply one validated complete arc mutation atomically.
apply_set_shape_arc :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_arc(state, command^.entity, {
        radius = command^.arc.radius,
        start_theta = command^.arc.start_theta,
        sweep_theta = command^.arc.sweep_theta,
    })
}

// Apply one validated complete trochoid mutation atomically.
apply_set_shape_trochoid :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.trochoid
    _ = shape_set_trochoid(state, command^.entity, {i32(value.mode),
        value.fixed_radius, value.rolling_radius, value.tracer_distance,
        value.tracer_phase, value.rotation, value.parameter_start,
        value.parameter_finish, value.draw_parameter})
}

// Apply one validated trochoid reveal-frontier mutation.
apply_set_shape_trochoid_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_trochoid_frontier(state, command^.entity, command^.scalar)
}

// Apply one validated complete singleton-guide configuration.
apply_set_trochoid_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.trochoid_tool
    _ = set_trochoid_tool_geometry(state, {i32(value.mode), value.fixed_radius,
        value.rolling_radius, value.parameter, value.rotation,
        value.orientation_phase})
}

// Apply one validated singleton-guide rolling parameter.
apply_set_trochoid_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_trochoid_tool_parameter(state, command^.scalar)
}

// Apply one validated complete Cycloid scalar mutation.
apply_set_shape_cycloid :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    entity := shapemodel.shape_entity_unpack(command.entity)
    current, found := shapemodel.shape_component_get_mut(
        &state.shape_world.cycloids, &state.shape_world.registry, entity)
    assert(found)
    previous := current^
    current^ = command.cycloid
    bridge_cycloid_preserve_previous(current, previous)
}

// Apply one validated Cycloid reveal-frontier mutation.
apply_set_shape_cycloid_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_cycloid_frontier(state, command^.entity, command^.scalar)
}

// Apply one validated atomic permanent-guide endpoint update.
apply_set_cycloid_tool_line :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_cycloid_tool_line(state, command^.position, command^.second_position)
}

// Apply one validated complete permanent Cycloid-guide scalar mutation.
apply_set_cycloid_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.cycloid_tool
    _ = set_cycloid_tool_geometry(state, {value.rolling_radius,
        value.parameter_start, value.parameter_finish, value.parameter,
        value.orientation_phase})
}

// Apply one validated permanent Cycloid-guide rolling parameter update.
apply_set_cycloid_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_cycloid_tool_parameter(state, command^.scalar)
}

// Apply a validated complete parabola mutation through its bridge contract.
apply_set_shape_parabola :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.parabola
    _ = shape_set_parabola(state, command^.entity, {value.focal_distance, value.rotation,
        value.parameter_start, value.parameter_finish, value.draw_parameter})
}

// Apply one validated parabola frontier mutation.
apply_set_shape_parabola_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_parabola_frontier(state, command^.entity, command^.scalar)
}

// Apply a validated complete hyperbola mutation.
apply_set_shape_hyperbola :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.hyperbola
    _ = shape_set_hyperbola(state, command^.entity, {value.semimajor,
        value.semiminor, value.rotation, value.parameter_start,
        value.parameter_finish, value.draw_parameter})
}

// Apply one validated common hyperbola frontier mutation.
apply_set_shape_hyperbola_frontier :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_hyperbola_frontier(state, command^.entity, command^.scalar)
}

// Apply a validated parabola tool geometry update transactionally.
apply_set_parabola_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.parabola_tool
    _ = set_parabola_tool_geometry(state, {value.focal_distance, value.link_length,
        value.rotation, value.parameter_start, value.parameter_finish, value.parameter})
}

// Apply a validated parabola tool parameter update.
apply_set_parabola_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_parabola_tool_parameter(state, command^.scalar)
}

// Apply a validated parabola tool contact-highlight update.
apply_set_parabola_tool_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_parabola_tool_active(state, i32(command^.flag), command^.color)
}

// Apply a validated hyperbola tool geometry update transactionally.
apply_set_hyperbola_tool :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    value := command^.hyperbola_tool
    _ = set_hyperbola_tool_geometry(state, {value.semimajor, value.semiminor,
        value.rotation, value.parameter_start, value.parameter_finish,
        value.parameter, value.rail_half_length})
}

// Apply a validated hyperbola tool parameter update.
apply_set_hyperbola_tool_parameter :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_hyperbola_tool_parameter(state, command^.scalar)
}

// Apply a validated hyperbola tool contact-highlight update.
apply_set_hyperbola_tool_active :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = set_hyperbola_tool_active(state, i32(command^.flag), command^.color,
        shapemodel.Hyperbola_Branches(command^.integer))
}

// Apply one validated packed-entity visibility mutation.
apply_set_shape_visible :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_visible(state, command^.entity, u8(command^.flag))
}

// Apply one validated packed-entity active-feature mutation.
apply_set_shape_active_feature :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_active_feature(state, command^.entity, u16(command^.integer))
}

// Map one bridge reveal kind to its native population kind.
formation_target_kind :: proc(
    kind: bridgemodel.Animation_Reveal_Kind) -> particles.Formation_Target_Kind {
    switch kind {
    case .Label:
        return .Label
    case .Region:
        return .Region
    case .Sweep:
        return .Sweep
    }
    return .Label
}

//   Apply one emit-trailing-particle command and record its emission.
apply_emit_trailing_particle :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    emit_trailing_particle(state, command^.position, command^.color)
}

// Start one validated reveal at the accepted animation endpoint.
apply_animation_reveal :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command,
    batch: ^Scene_Command_Batch) {
    assert(state != nil && batch != nil)
    seed := command^.reveal.owner_entity ~
        (batch^.animation_generation * 0x9e3779b97f4a7c15) ~
        batch^.tick_sequence
    accepted := particles.formation_start_reveal(
        &state^.particle_system,
        {
            kind = formation_target_kind(command^.reveal.kind),
            owner_entity = command^.reveal.owner_entity,
            animation_generation = batch^.animation_generation,
            progress = batch^.animation_progress,
            duration = command^.reveal.duration,
            seed = seed,
        })
    assert(accepted)
}

//   Apply one animation-cycle-boundary notification command.
apply_notify_animation_cycle_boundary :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    bridge_events.notify_animation_cycle_boundary_local(state)
}

// Report whether one accepted batch represents grounded drawing activity.
scene_command_batch_has_drawing_activity :: proc(batch: ^Scene_Command_Batch) -> bool {
    if batch == nil {
        return false
    }
    for command_index in 0..<batch^.command_count {
        if scene_command_has_drawing_activity(&batch^.commands[command_index]) {
            return true
        }
    }
    return false
}

// Observe native-expanded trails through the same drawing-audio policy as direct ink.
scene_command_has_drawing_activity :: proc(command: ^Scene_Command) -> bool {
    if command.kind == .Emit_Trailing_Particle {
        return true
    }
    if command.kind != .Apply_Native_Modifier {
        return false
    }
    output: modifier.Modifier_Output_Buffer
    status := modifier.evaluate_modifier(command.modifier, &output)
    assert(status == .Ok)
    for index in 0..<output.count {
        if output.outputs[index].kind == .Emit_Trailing_Particle ||
            output.outputs[index].kind == .Emit_Radial_Trail {
            return true
        }
    }
    return false
}

//   Validate and apply one completed batch in original callback order.
// This procedure runs on the display thread at the fixed-step boundary; commands may
// invoke canonical helpers that emit particles or update audio and tool state.
commit_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !validate_scene_command_batch(state, batch) {
        audio.set_drawing_activity(&state^.chalk_audio, false)
        record_scene_batch_evidence(state, .Scene_Batch_Rejected, true)
        return false
    }
    if animation_model.animation_value_store_apply_pending(
        &state^.animation_values,
        state^.animation_values.generation,
        &batch^.animation_value_writes) != .Ok {
        audio.set_drawing_activity(&state^.chalk_audio, false)
        record_scene_batch_evidence(state, .Scene_Batch_Rejected, true)
        return false
    }
    assert(particles.formation_advance_progress(
        &state^.particle_system, batch^.animation_generation,
        batch^.animation_progress))

    apply_scene_command_batch(state, batch)
    record_scene_batch_evidence(state, .Scene_Batch_Committed, false)
    return true
}

// Apply commands in callback order after complete batch preflight succeeds.
apply_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) {
    appliers := SCENE_COMMAND_APPLIERS
    hide_burst_kicked := false
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        if command^.kind == .Apply_Native_Modifier {
            apply_native_modifier_batch_command(state, batch, command_index)
        } else if command^.kind == .Reveal_Label || command^.kind == .Reveal_Region ||
            command^.kind == .Reveal_Sweep {
            if !scene_reveal_superseded_later(batch, command_index) {
                apply_animation_reveal(state, command, batch)
            }
        } else if command^.kind == .Set_Shape_Visible {
            _, emitted := shape_set_visible_local(
                state, command^.entity, u8(command^.flag), !hide_burst_kicked)
            hide_burst_kicked = hide_burst_kicked || emitted
        } else {
            applier := appliers[command^.kind]
            if applier != nil {
                applier(state, command)
            }
        }
        record_scene_command_evidence(state, command)
    }
    particles.formation_reclaim_unowned_particles(&state^.particle_system)
    audio.set_drawing_activity(&state^.chalk_audio,
        scene_command_batch_has_drawing_activity(batch))
}

