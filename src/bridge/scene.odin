package bridge

import "../core"
import "../particles"
import shapemodel "../shapes/model"

import "core:math"

// Report whether one tool endpoint participates in floor dust contact.
tool_dust_contact_on_floor :: #force_inline proc(position: Vector3) -> bool {
    return f32(math.abs(f64(position.z))) <= FLOOR_CONTACT_Z_EPSILON
}

// Convert a boolean value to its C ABI u8 representation.
to_u8 :: #force_inline proc(value: bool) -> u8 {
    if value {
        return 1
    }
    return 0
}

// Queue one tool endpoint at the floor boundary.
queue_tool_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    endpoint: Vector3) {
    if !tool_dust_contact_on_floor(endpoint) {
        return
    }
    accepted := particles.queue_dust_tool_contact(
        state^.particle_system, {endpoint = endpoint, source = .Point})
    assert(accepted)
}

// Queue one text-width contact when a floor label becomes visible.
queue_revealed_label_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    entity: shapemodel.Shape_Entity,
    font_size: f32) {
    if state == nil || state^.particle_system == nil || state^.iso_scale == nil {
        return
    }
    label, has_label := shapemodel.shape_component_get(
        &state^.shape_world.labels, &state^.shape_world.registry, entity)
    transform, has_transform := shapemodel.shape_component_get(
        &state^.shape_world.transforms, &state^.shape_world.registry, entity)
    if !has_label || !has_transform ||
        !tool_dust_contact_on_floor(transform^.position) {
        return
    }
    text, has_text := shapemodel.shape_label_source(
        &state^.shape_world.label_store, label^)
    if !has_text {
        return
    }
    _ = particles.queue_dust_label_reveal_contact(
        state^.particle_system, transform^.position, text, font_size,
        state^.iso_scale^.scale)
}

// Queue one compound filled-compass sweep when both legs lie on the floor.
queue_compass_filled_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    previous_first, previous_second, current_first, current_second: Vector3) {
    if !tool_dust_contact_on_floor(previous_first) ||
        !tool_dust_contact_on_floor(previous_second) ||
        !tool_dust_contact_on_floor(current_first) ||
        !tool_dust_contact_on_floor(current_second) {
        queue_tool_dust_contact(state, current_second)
        return
    }
    accepted := particles.queue_dust_tool_contact(state^.particle_system, {
        endpoint = current_second,
        previous_segment_first = previous_first,
        previous_segment_second = previous_second,
        segment_first = current_first,
        segment_second = current_second,
        has_sweep = true,
        source = .Compass_Filled_Sweep,
    })
    assert(accepted)
}
