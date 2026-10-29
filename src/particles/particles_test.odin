package particles

import particlemodel "model"
import shapemodel "../shapes/model"
import curve "../shapes/curve"
import shapes "../shapes"
import color "../core/color"

import "core:math"
import "core:testing"

import test_helpers "../test_helpers"

Particle_Test_Polygon :: struct {
    entity: shapemodel.Shape_Entity,
    draw: shapemodel.Shapes_Polygon_Draw,
    prepared: bool,
}

// Carry one test fixture's target identity and preparation result.
Particle_Test_Formation_Setup :: struct {
    entity: shapemodel.Shape_Entity,
    count: int,
    prepared: bool,
}

// Verify theta normalization and sweep delta wrap correctly across zero.
@(test)
normalize_theta_and_sweep_delta_are_stable :: proc(t: ^testing.T) {
    theta := normalize_theta(f32(-0.5))
    test_helpers.expect_close(t, theta, f32(2.0 * math.PI - 0.5),
        "normalize_theta should wrap negatives")

    delta := compute_sweep_delta(
        f32(1.5 * math.PI),
        f32(0.5 * math.PI))
    test_helpers.expect_close(t, delta, f32(math.PI),
        "sweep delta should wrap across zero")
}

// Count live low-layer particles within the configured test capacity.
count_live_low_particles :: proc(ps: ^particlemodel.Particle_System) -> int {
    count: int
    for alive in ps.low_particles.alive[:ps.use_max_dust_particles] {
        if alive {
            count += 1
        }
    }
    return count
}

// Create one visible polygon fixture and prepare its rendered draw cache.
particle_test_visible_polygon :: proc(
    world: ^shapemodel.Shape_World,
    positions: []Vector3,
    vertices: []shapemodel.Shape_Entity) ->
    (shapemodel.Shape_Entity, bool) {
    polygon, status := shapes.world_create_polygon_into(world, positions, {
        color = color.WHITE,
        brush_size = 1,
    }, vertices)
    if status != shapemodel.Shape_World_Status.Ok {
        return {}, false
    }
    style, found := shapemodel.shape_component_get_mut(
        &world^.render_styles, &world^.registry, polygon.shape)
    if !found {
        return {}, false
    }
    style^.visible = true
    shapes.build_shape_world_draw_cache(world, 1)
    return polygon.shape, true
}

// Create a visible test square and retain its prepared draw record.
particle_test_visible_square :: proc(
    world: ^shapemodel.Shape_World,
    z: f32,
    vertices: []shapemodel.Shape_Entity) -> Particle_Test_Polygon {
    positions: [4]Vector3 = {
        {0.2, 0.2, z}, {0.8, 0.2, z},
        {0.8, 0.8, z}, {0.2, 0.8, z},
    }
    entity, prepared := particle_test_visible_polygon(
        world, positions[:], vertices)
    if !prepared {
        return {
            entity = entity,
        }
    }
    draw, found := shape_world_cached_polygon_draw(world, entity)
    return {
        entity = entity,
        draw = draw,
        prepared = found,
    }
}

// Begin one deterministic region reveal against the accepted animation timeline.
particle_test_start_region_reveal :: proc(
    ps: ^particlemodel.Particle_System, entity: shapemodel.Shape_Entity) -> bool {
    formation_reset_generation(ps, 7)
    if !formation_advance_progress(ps, 7, 0) {
        return false
    }
    return formation_start_reveal(ps, {
        kind = .Region,
        owner_entity = shapemodel.shape_entity_pack(entity),
        animation_generation = 7,
        progress = 0,
        duration = 1,
        seed = 19,
    })
}

// Verify outlined arc emission scales with visible arc length.
@(test)
circle_dust_emission_scales_with_arc_length :: proc(t: ^testing.T) {
    quarter := new(particlemodel.Particle_System, context.allocator)
    full := new(particlemodel.Particle_System, context.allocator)
    defer free(quarter)
    defer free(full)
    quarter.use_max_dust_particles = 1000
    full.use_max_dust_particles = 1000
    white := color.WHITE

    emit_circle_dust(quarter, {
        center = {},
        radius = 0.2,
        sweep_theta = f32(math.PI/2),
        color = white,
    })
    emit_circle_dust(full, {
        center = {},
        radius = 0.2,
        sweep_theta = f32(2*math.PI),
        color = white,
    })

    quarter_count := count_live_low_particles(quarter)
    full_count := count_live_low_particles(full)
    testing.expect(t, quarter_count < full_count)
    testing.expect(t, full_count >= quarter_count * 3)
}

// Verify filled arc emission occupies the sector interior instead of only its rim.
@(test)
filled_circle_dust_emission_samples_sector_interior :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps.use_max_dust_particles = 1000

    emit_filled_circle_dust(ps, {
        center = {},
        radius = 0.2,
        sweep_theta = f32(math.PI/3),
        color = color.WHITE,
    })

    interior_count: int
    for index in 0..<ps.use_max_dust_particles {
        if !ps.low_particles.alive[index] {
            continue
        }
        radius_sq := ps.low_particles.pos_x[index] * ps.low_particles.pos_x[index] +
            ps.low_particles.pos_y[index] * ps.low_particles.pos_y[index]
        if radius_sq < 0.01 {
            interior_count += 1
        }
    }
    testing.expect(t, count_live_low_particles(ps) >= 200)
    testing.expect(t, interior_count >= 40)
}

// Verify longer revealed trochoid intervals produce proportionally more hide dust.
@(test)
trochoid_dust_emission_scales_with_revealed_length :: proc(t: ^testing.T) {
    partial := new(particlemodel.Particle_System, context.allocator)
    full := new(particlemodel.Particle_System, context.allocator)
    defer free(partial)
    defer free(full)
    partial.use_max_dust_particles = 1000
    full.use_max_dust_particles = 1000
    value: shapemodel.Shape_Trochoid = {
        mode = .External,
        fixed_radius = 0.2,
        rolling_radius = 0.2,
        tracer_distance = 0.2,
        parameter_start = 0,
        parameter_finish = 2 * math.PI,
        draw_parameter = math.PI / 2,
    }
    vertices: [curve.TROCHOID_MAX_VERTICES]Vector3
    partial_result := curve.trochoid_explicate({}, value, vertices[:])
    emit_curve_polyline_dust(partial, vertices[:partial_result.vertex_count],
        color.WHITE)
    value.draw_parameter = value.parameter_finish
    full_result := curve.trochoid_explicate({}, value, vertices[:])
    emit_curve_polyline_dust(full, vertices[:full_result.vertex_count],
        color.WHITE)

    partial_count := count_live_low_particles(partial)
    full_count := count_live_low_particles(full)
    testing.expect(t, partial_count < full_count)
    testing.expect(t, partial_count >= CLEAR_BURST_CURVE_MIN_SAMPLES)
}

// Verify hiding the permanent cycloid guide neither emits nor kicks dust.
@(test)
cycloid_tool_hide_is_silent :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(world)
    defer free(particles)
    tool, status := shapes.world_create_cycloid_tool(world, {
        first = {0, 0, 0},
        second = {1, 0, 0},
        rolling_radius = 0.05,
        parameter_start = 0,
        parameter_finish = 2 * math.PI,
        parameter = 0,
        style = {
            color = color.WHITE,
            brush_size = 5,
        },
    })
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    style, found := shapemodel.shape_component_get_mut(
        &world.render_styles, &world.registry, tool.shape)
    testing.expect(t, found)
    style.visible = true
    particles.use_max_dust_particles = 1
    particles.low_particles[0].alive = true
    particles.low_particles[0].life = 10

    emitted := emit_shape_world_hide_burst(particles, world, tool.shape)

    testing.expect(t, !emitted)
    testing.expect_value(t, particles.low_particles[0].age, f32(0))
    testing.expect_value(t, particles.low_particles.vel_z[0], f32(0))
    testing.expect_value(t, count_live_low_particles(particles), 1)
}

// Verify slot reservation prefers dead slots and wraps at the particle cap.
@(test)
reserve_dead_low_particle_slot_prefers_dead_then_wraps :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.next_index = 0

    idx0, ok0 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok0)
    testing.expect_value(t, idx0, 0)
    testing.expect_value(t, ps^.next_index, 1)

    ps^.low_particles.alive[1] = true
    idx1, ok1 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok1)
    testing.expect_value(t, idx1, 2)
    testing.expect_value(t, ps^.next_index, 0)

    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true
    ps^.low_particles.alive[2] = true
    idx2, ok2 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok2)
    testing.expect_value(t, idx2, 0)
}

// Verify the reservation ring index wraps back to zero at the cap.
@(test)
reserve_dead_particle_slot_ring_advances :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.next_index = MAX_PARTICLES - 1

    idx, ok := reserve_dead_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, MAX_PARTICLES - 1)
    testing.expect_value(t, ps^.next_index, 0)
}

// Assert two particle systems have matching low-particle slots and RNG state.
expect_dust_systems_match :: proc(
    t: ^testing.T, actual, expected: ^particlemodel.Particle_System) {
    for index in 0..<expected^.use_max_dust_particles {
        testing.expect_value(t, actual^.low_particles[index],
            expected^.low_particles[index])
    }
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

// Queue one point contact at every live low-particle slot.
queue_dust_slot_contacts :: proc(
    t: ^testing.T, ps: ^particlemodel.Particle_System) {
    for index in 0..<ps^.use_max_dust_particles {
        testing.expect(t, queue_dust_tool_contact(ps, {
            endpoint = {
                ps^.low_particles.pos_x[index],
                ps^.low_particles.pos_y[index],
                0,
            },
        }))
    }
}

// Solve queued tool contacts through the grounded vector-field path.
solve_test_dust_tool_contacts :: proc(ps: ^particlemodel.Particle_System) {
    dust_field_deposit_grounded(ps)
    apply_dust_tool_contacts_to_field(ps)
    dust_field_evolve(&ps^.dust_field, f32(1.0 / 60.0))
    dust_field_assign_grounded(ps)
}

// Verify queue admission is bounded and records rejected contact intents.
@(test)
dust_tool_contact_queue_is_bounded :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    for _ in 0..<DUST_TOOL_CONTACT_CAP {
        testing.expect(t, queue_dust_tool_contact(ps, {}))
    }

    testing.expect(t, !can_queue_dust_tool_contacts(ps, 1))
    testing.expect(t, !queue_dust_tool_contact(ps, {}))
    testing.expect_value(t, ps^.dust_tool_contact_count, DUST_TOOL_CONTACT_CAP)
    testing.expect_value(t, ps^.dust_tool_contact_overflow_count, 1)
}

// Verify a revealed UTF-8 label queues a contact across its rendered text width.
@(test)
dust_label_reveal_contact_covers_text_width :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    testing.expect(t, queue_dust_label_reveal_contact(
        ps, {0.5, 0.5, 0}, "∠A′", 16, 800))

    contact := ps^.dust_tool_contacts[0]
    testing.expect_value(t, ps^.dust_tool_contact_count, 1)
    testing.expect_value(t, contact.source, particlemodel.Dust_Tool_Contact_Source.Label)
    testing.expect(t, contact.has_sweep)
    testing.expect(t, contact.segment_second.x > contact.segment_first.x)
    testing.expect(t, contact.segment_second.y < contact.segment_first.y)
    testing.expect(t, contact.segment_first.x < 0.5)
    testing.expect(t, contact.segment_first.y < 0.5)
}

// Verify a label contact pushes grounded dust away from both sides of its text line.
@(test)
dust_label_reveal_contact_pushes_from_text :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    above := 128 * DUST_FIELD_DIM + 125
    below := 122 * DUST_FIELD_DIM + 125
    ps^.dust_field.density[above] = 1
    ps^.dust_field.density[below] = 1
    ps^.dust_field.support_bounds = {125, 122, 125, 128, true}
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.4, 0.6, 0},
        segment_first = {0.4, 0.6, 0},
        segment_second = {0.6, 0.4, 0},
        has_sweep = true,
        source = .Label,
    }))

    apply_dust_tool_contacts_to_field(ps)

    testing.expect(t, ps^.dust_field.momentum_x[above] > 0)
    testing.expect(t, ps^.dust_field.momentum_y[above] > 0)
    testing.expect(t, ps^.dust_field.momentum_x[below] < 0)
    testing.expect(t, ps^.dust_field.momentum_y[below] < 0)
}

// Verify label contacts reach farther and push harder than ordinary tool contacts.
@(test)
dust_label_contact_uses_stronger_push :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    node := 125 * DUST_FIELD_DIM + 129
    ps^.dust_field.density[node] = 1
    ps^.dust_field.support_bounds = {129, 125, 129, 125, true}
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.5, 0.5, 0},
        source = .Label,
    }))

    apply_dust_tool_contacts_to_field(ps)

    testing.expect(t, ps^.dust_field.momentum_x[node] > 0)
}

// Verify only exact duplicate filled sweeps coalesce within one spawn boundary.
@(test)
dust_tool_contacts_coalesce_only_with_matching_semantics :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    first_sweep: particlemodel.Dust_Tool_Contact = {
        endpoint = {0.1, 0.2, 0},
        segment_first = {0.1, 0.2, 0},
        segment_second = {0.4, 0.2, 0},
        has_sweep = true,
        previous_segment_first = {0.1, 0.2, 0},
        previous_segment_second = {0.4, 0.2, 0},
        source = .Compass_Filled_Sweep,
    }
    distinct_sweep := first_sweep
    distinct_sweep.endpoint = {0.5, 0.2, 0}
    distinct_sweep.segment_second = distinct_sweep.endpoint
    duplicate: particlemodel.Dust_Tool_Contact = {
        endpoint = {0.7, 0.8, 0},
        source = .Point,
    }
    testing.expect(t, queue_dust_tool_contact(ps, first_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, first_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, distinct_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    scenario := duplicate
    scenario.source = .Scenario
    testing.expect(t, queue_dust_tool_contact(ps, scenario))
    ps^.dust_spawn_sequence += 1
    testing.expect(t, queue_dust_tool_contact(ps, scenario))

    coalesce_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 5)
    testing.expect_value(t, ps^.dust_tool_contact_coalesced_count, u64(2))
    testing.expect_value(t, ps^.dust_tool_contacts[0], first_sweep)
    testing.expect_value(t, ps^.dust_tool_contacts[1], distinct_sweep)
    testing.expect_value(t, ps^.dust_tool_contacts[2], duplicate)
}

// Verify a compound filled sweep reaches interior nodes but not distant support.
@(test)
dust_filled_compass_sweep_covers_ruled_sector :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    interior: [3][2]int = {{110, 110}, {120, 120}, {130, 110}}
    outside: [2]int = {175, 175}
    for point in interior {
        ps^.dust_field.density[point.y * DUST_FIELD_DIM + point.x] = 1
    }
    outside_node := outside.y * DUST_FIELD_DIM + outside.x
    ps^.dust_field.density[outside_node] = 1
    ps^.dust_field.support_bounds = {110, 110, 175, 175, true}
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.4, 0.6, 0},
        previous_segment_first = {0.4, 0.4, 0},
        previous_segment_second = {0.6, 0.4, 0},
        segment_first = {0.4, 0.4, 0},
        segment_second = {0.4, 0.6, 0},
        has_sweep = true,
        source = .Compass_Filled_Sweep,
    }))

    apply_dust_tool_contacts_to_field(ps)

    for point in interior {
        node := point.y * DUST_FIELD_DIM + point.x
        testing.expect(t, ps^.dust_field.momentum_x[node] < 0)
        testing.expect(t, ps^.dust_field.momentum_y[node] > 0)
    }
    testing.expect_value(t, ps^.dust_field.momentum_x[outside_node], f32(0))
    testing.expect_value(t, ps^.dust_field.momentum_y[outside_node], f32(0))
}

// Verify floor-tool force never changes an airborne particle's ballistic state.
@(test)
dust_tool_contact_does_not_affect_airborne_particle :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 1
    actual^.use_max_dust_particles = 1
    expected^.low_particles[0] = {
        pos_x = 0.505,
        pos_y = 0.5,
        pos_z = 0.1,
        vel_x = 0.001,
        vel_y = -0.002,
        life = 100,
        alive = true,
    }
    actual^.low_particles[0] = expected^.low_particles[0]
    testing.expect(t, queue_dust_tool_contact(actual, {
        endpoint = {0.5, 0.5, 0},
    }))

    update_particles(expected, f32(1.0 / 60.0))
    update_particles(actual, f32(1.0 / 60.0))

    testing.expect_value(t, actual^.low_particles[0], expected^.low_particles[0])
}

// Verify generation boundaries discard pending field force without applying it.
@(test)
dust_tool_contact_discard_clears_pending_force :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.2, 0.25, 0},
    }))

    discard_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
}

// Verify authored vertical kick returns grounded dust to airborne authority.
@(test)
dust_kick_creates_airborne_particle :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {
        pos_x = 0.5,
        pos_y = 0.5,
        pos_z = DUST_FLOOR_Z,
        life = 1,
        color = color.WHITE,
        alive = true,
    }

    kick_existing_dust_index(ps, 0)
    integrate_dust_positions(ps)
    update_particle_dust_index(ps, 0)

    testing.expect(t, ps^.low_particles.pos_z[0] > DUST_FLOOR_Z)
}

// Verify gravity does not create a recurring bounce for grounded dust at rest.
@(test)
update_particle_dust_index_keeps_grounded_particle_at_rest :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles[0].life = 1
    ps^.low_particles.pos_z[0] = DUST_FLOOR_Z

    update_particle_dust_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect_value(t, ps^.low_particles.vel_z[0], f32(0))
    testing.expect_value(t, ps^.dust_floor_rest_count, 1)
}

// Verify maximum authored vertical launch converges to grounded rest.
@(test)
update_particle_dust_index_settles_authored_vertical_launch :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles[0].life = 1
    ps^.low_particles.vel_z[0] = DUST_VZ_MAX

    for _ in 0..<120 {
        integrate_dust_positions(ps)
        update_particle_dust_index(ps, 0)
    }

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect_value(t, ps^.low_particles.vel_z[0], f32(0))
}

// Verify two fresh particle systems produce identical seeded random ranges.
@(test)
particle_random_ranges_use_independent_seeded_generators :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)

    testing.expect_value(t,
        random_f32_range(first, -1, 1),
        random_f32_range(second, -1, 1))
    testing.expect_value(t,
        random_i32_range(first, -10, 10),
        random_i32_range(second, -10, 10))
}

// Verify scenario emission is deterministic without consuming authored RNG state.
@(test)
scenario_dust_emission_is_deterministic_and_rng_isolated :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)
    control := new(particlemodel.Particle_System, context.allocator)
    defer free(control)
    first^.use_max_dust_particles = 32
    second^.use_max_dust_particles = 32
    control^.use_max_dust_particles = 32
    request: particlemodel.Scenario_Dust_Emission_Request = {
        distribution = .Disc,
        count = 16,
        x = 0.5,
        y = 0.5,
        radius = 0.04,
        seed = 17,
    }

    testing.expect_value(t, emit_scenario_dust(first, request), 16)
    testing.expect_value(t, emit_scenario_dust(second, request), 16)
    for index in 0..<16 {
        testing.expect_value(t,
            first^.low_particles[index], second^.low_particles[index])
        testing.expect_value(t,
            first^.dust_slot_spawn_sequences[index], u64(index + 1))
    }
    testing.expect_value(t,
        random_f32_range(first, -1, 1), random_f32_range(control, -1, 1))
}

// Verify identical emission, contact, and kick streams remain deterministic.
@(test)
scenario_dust_contact_and_kick_stream_is_deterministic :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)
    first^.use_max_dust_particles = 16
    second^.use_max_dust_particles = 16
    request: particlemodel.Scenario_Dust_Emission_Request = {
        distribution = .Point,
        count = 16,
        x = 0.51,
        y = 0.51,
        seed = 23,
    }
    testing.expect_value(t, emit_scenario_dust(first, request), 16)
    testing.expect_value(t, emit_scenario_dust(second, request), 16)

    for _ in 0..<360 {
        update_particles(first, 1.0 / 60.0)
        update_particles(second, 1.0 / 60.0)
    }
    queue_dust_slot_contacts(t, first)
    queue_dust_slot_contacts(t, second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)
    kick_existing_dust(first)
    kick_existing_dust(second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)

    expect_dust_systems_match(t, first, second)
}

// Verify grounded particles receive field velocity while airborne particles do not.
@(test)
dust_update_affects_only_grounded_particles :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    ps^.low_particles[0] = {
        pos_x = 0.25,
        pos_y = 0.75,
        pos_z = DUST_FLOOR_Z,
        vel_x = 0.003,
        vel_y = -0.002,
        alive = true,
    }
    ps^.low_particles[1] = {
        pos_x = 0.25,
        pos_y = 0.75,
        pos_z = DUST_FLOOR_Z + 0.1,
        vel_x = -0.004,
        vel_y = 0.005,
        alive = true,
    }
    airborne_velocity: Vector2 = {
        ps^.low_particles.vel_x[1],
        ps^.low_particles.vel_y[1],
    }

    dust_field_update_grounded(ps, f32(1.0 / 60.0))

    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0.003)
    testing.expect_value(t, ps^.low_particles.vel_x[1], airborne_velocity.x)
    testing.expect_value(t, ps^.low_particles.vel_y[1], airborne_velocity.y)
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 1,
        "only grounded density")
}

// Verify landing momentum enters the vector field before exact assignment.
@(test)
update_particles_deposits_landing_momentum :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {
        pos_x = 0.5,
        pos_y = 0.5,
        pos_z = 0.001,
        vel_x = 0.003,
        vel_y = -0.002,
        vel_z = -0.01,
        life = 10,
        alive = true,
    }

    update_particles(ps, f32(1.0 / 60.0))

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 1,
        "landing density")
}

// Verify the production step performs no legacy grounded solver work.
@(test)
update_particles_bypasses_legacy_grounded_authorities :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    for index in 0..<2 {
        ps^.low_particles[index] = {
            pos_x = 0.5,
            pos_y = 0.5,
            pos_z = DUST_FLOOR_Z,
            life = 10,
            alive = true,
        }
    }

    update_particles(ps, f32(1.0 / 60.0))

    testing.expect_value(t, ps^.dust_grounded_count, 2)
    testing.expect(t, ps^.dust_peak_speed_sq >= 0)
}

// Verify P2G caches grounded particles once in stable slot order.
@(test)
dust_transfers_are_stable_and_grounded_only :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    ps^.low_particles[0] = {
        pos_x = 0.2,
        pos_y = 0.3,
        pos_z = DUST_FLOOR_Z,
        vel_x = 0.001,
        life = 10,
        alive = true,
    }
    ps^.low_particles[1] = {
        pos_x = 0.4,
        pos_y = 0.5,
        pos_z = DUST_FLOOR_Z + 0.1,
        vel_x = 0.007,
        life = 10,
        alive = true,
    }
    ps^.low_particles[3] = {
        pos_x = 0.7,
        pos_y = 0.8,
        pos_z = DUST_FLOOR_Z,
        vel_y = -0.002,
        life = 10,
        alive = true,
    }

    dust_field_deposit_grounded(ps)

    testing.expect_value(t, ps^.dust_transfer_count, 2)
    testing.expect_value(t, ps^.dust_transfers[0].particle_index, i32(0))
    testing.expect_value(t, ps^.dust_transfers[1].particle_index, i32(3))
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 2,
        "grounded transfer density")
}

// Verify the fused low-dust pass matches the former stable three-pass sequence.
expect_low_dust_deposit_state_equal :: proc(t: ^testing.T,
    actual, expected: ^particlemodel.Particle_System) {
    for index in 0..<expected^.use_max_dust_particles {
        testing.expect_value(t, actual^.low_particles[index],
            expected^.low_particles[index])
    }
    testing.expect_value(t, actual^.dust_floor_rest_count,
        expected^.dust_floor_rest_count)
    testing.expect_value(t, actual^.dust_field.support_bounds,
        expected^.dust_field.support_bounds)
    testing.expect_value(t, actual^.dust_transfer_count,
        expected^.dust_transfer_count)
}

// Verify the fused low-dust pass matches the former stable three-pass sequence.
@(test)
update_and_deposit_low_dust_matches_sequential_reference :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(actual)
    expected^.use_max_dust_particles = 5
    actual^.use_max_dust_particles = expected^.use_max_dust_particles
    expected^.low_particles[0] = {
        pos_x = 0.3,
        pos_y = 0.4,
        pos_z = DUST_FLOOR_Z,
        vel_x = 0.001,
        vel_y = -0.002,
        life = 10,
        alive = true,
    }
    expected^.low_particles[1] = {
        pos_x = 0.5,
        pos_y = 0.6,
        pos_z = 0.001,
        vel_x = 0.003,
        vel_y = 0.002,
        vel_z = -0.01,
        life = 10,
        alive = true,
    }
    expected^.low_particles[2] = {
        pos_x = 0.7,
        pos_y = 0.8,
        pos_z = 0.2,
        vel_x = -0.004,
        vel_y = 0.005,
        vel_z = 0.003,
        life = 10,
        alive = true,
    }
    expected^.low_particles[4] = {
        pos_x = 1,
        pos_y = 0,
        pos_z = DUST_FLOOR_Z,
        vel_x = 0.01,
        vel_y = -0.01,
        life = 10,
        alive = true,
    }
    for index in 0..<5 {
        actual^.low_particles[index] = expected^.low_particles[index]
    }

    integrate_dust_positions(expected)
    for index in 0..<5 {
        update_particle_dust_index(expected, index)
    }
    dust_field_deposit_grounded(expected)
    update_and_deposit_low_dust(actual)
    expect_low_dust_deposit_state_equal(t, actual, expected)
}

// Verify reset_particles zeroes runtime state and marks every slot dead.
@(test)
reset_particles_clears_runtime_state_and_marks_all_slots_dead :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.spawn_timer = 1.0
    ps^.next_index = 3
    ps^.low_particles.alive[0] = true
    ps^.low_particles.age[0] = 0.25
    ps^.particles.alive[0] = true
    ps^.particles.age[0] = 0.5
    ps^.dust_transfer_count = 2

    reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect_value(t, ps^.dust_transfer_count, 0)
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect_value(t, ps^.formation.particle_count, 0)
    testing.expect_value(t, ps^.formation.reveal_count, 0)
}

// Verify accepted progress, independent durations, supersession, and endpoint retirement.
@(test)
formation_reveals_follow_only_accepted_animation_progress :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    formation_reset_generation(ps, 7)
    testing.expect(t, formation_advance_progress(ps, 7, 1.0))
    testing.expect(t, formation_start_reveal(ps, {
        kind = .Region,
        owner_entity = 101,
        animation_generation = 7,
        progress = 1.0,
        duration = 2.0,
        seed = 11,
    }))
    testing.expect(t, formation_start_reveal(ps, {
        kind = .Label,
        owner_entity = 202,
        animation_generation = 7,
        progress = 1.0,
        duration = 0.5,
        seed = 12,
    }))
    testing.expect_value(t, ps^.formation.reveal_count, 2)

    label_slot := formation_find_reveal(&ps^.formation, .Label, 202, 7)
    first_slot_generation := ps^.formation.reveals[label_slot].slot_generation
    testing.expect(t, formation_start_reveal(ps, {
        kind = .Label,
        owner_entity = 202,
        animation_generation = 7,
        progress = 1.0,
        duration = 1.0,
        seed = 13,
    }))
    testing.expect_value(t, ps^.formation.reveal_count, 2)
    testing.expect(t,
        ps^.formation.reveals[label_slot].slot_generation != first_slot_generation)
    testing.expect_value(t, ps^.formation.reveals[label_slot].start_progress, 1.0)

    update_particles(ps, 0.75)
    testing.expect_value(t, ps^.formation.accepted_progress, 1.0)
    testing.expect(t, formation_advance_progress(ps, 7, 2.0))
    testing.expect_value(t, ps^.formation.reveal_count, 1)
    testing.expect(t, formation_advance_progress(ps, 7, 3.0))
    testing.expect_value(t, ps^.formation.reveal_count, 0)
}

// Verify formation slots reject pressure and stale handles without overwriting live slots.
@(test)
formation_particle_slots_are_bounded_and_generation_checked :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    formation_reset_generation(ps, 3)
    testing.expect(t, formation_advance_progress(ps, 3, 0))
    testing.expect(t, formation_start_reveal(ps, {
        kind = .Label,
        owner_entity = 42,
        animation_generation = 3,
        progress = 0,
        duration = 10,
        seed = 9,
    }))
    reveal_slot := formation_find_reveal(&ps^.formation, .Label, 42, 3)
    reveal_generation := ps^.formation.reveals[reveal_slot].slot_generation
    first := formation_test_fill_particle_slots(t, ps, reveal_slot, reveal_generation)
    _, added := formation_add_particle(ps, {
        reveal_slot = i32(reveal_slot),
        reveal_generation = reveal_generation,
    })
    testing.expect(t, !added)
    testing.expect(t, formation_remove_particle(ps, first))
    replacement, replacement_added := formation_add_particle(ps, {
        reveal_slot = i32(reveal_slot),
        reveal_generation = reveal_generation,
    })
    testing.expect(t, replacement_added)
    testing.expect_value(t, replacement.slot, first.slot)
    testing.expect(t, replacement.generation != first.generation)
    testing.expect(t, !formation_remove_particle(ps, first))
    testing.expect_value(t, ps^.formation.particle_count, MAX_FORMATION_PARTICLES)

    formation_reset_generation(ps, 4)
    testing.expect_value(t, ps^.formation.particle_count, 0)
    testing.expect_value(t, ps^.formation.reveal_count, 0)
    testing.expect(t, !formation_remove_particle(ps, replacement))
}

// Fill every available formation slot and return the first generation-qualified handle.
formation_test_fill_particle_slots :: proc(
    t: ^testing.T, ps: ^particlemodel.Particle_System,
    reveal_slot: int, reveal_generation: u64) -> Formation_Particle_Handle {
    first: Formation_Particle_Handle
    for index in 0..<MAX_FORMATION_PARTICLES {
        handle, added := formation_add_particle(ps, {
            reveal_slot = i32(reveal_slot),
            reveal_generation = reveal_generation,
            target_x = f32(index),
        })
        testing.expect(t, added)
        if index == 0 {
            first = handle
        }
    }
    testing.expect_value(t, ps^.formation.particle_count, MAX_FORMATION_PARTICLES)
    return first
}

// Verify reset_particles clears queued contact state and diagnostics.
@(test)
reset_particles_clears_dust_tool_contact_state :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.dust_tool_contact_count = 2
    ps^.dust_tool_contact_overflow_count = 3
    ps^.dust_tool_contact_coalesced_count = 4
    ps^.dust_tool_contact_sample_count = 5

    reset_particles(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
    testing.expect_value(t, ps^.dust_tool_contact_overflow_count, 0)
    testing.expect_value(t, ps^.dust_tool_contact_coalesced_count, u64(0))
    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(0))
    testing.expect_value(t, ps^.dust_tool_contact_field_node_visit_count, u64(0))
}

// Verify slot reservation wraps to index zero when every slot is alive.
@(test)
reserve_dead_low_particle_slot_wraps_when_all_slots_alive :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.next_index = 0
    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true

    idx, ok := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, 0)
    testing.expect_value(t, ps^.next_index, 1)
}

// Seed one world line with direct endpoint transforms and configurable visibility.
seed_shape_world_particle_line :: proc(
    world: ^shapemodel.Shape_World,
    visible: bool) {
    shape, first, second: shapemodel.Shape_Entity
    assert(shapemodel.shape_world_create_entity(world, &shape) == .Ok)
    assert(shapemodel.shape_world_create_entity(world, &first) == .Ok)
    assert(shapemodel.shape_world_create_entity(world, &second) == .Ok)
    assert(shapemodel.shape_component_insert(&world.transforms, &world.registry,
        first, shapemodel.Shape_Transform{
            position = {0, 0, 0},
        }) == .Ok)
    assert(shapemodel.shape_component_insert(&world.transforms, &world.registry,
        second, shapemodel.Shape_Transform{
            position = {1, 0, 0},
        }) == .Ok)
    assert(shapemodel.shape_component_insert(&world.render_styles, &world.registry,
        shape, shapemodel.Shape_Render_Style{
            visible = visible,
        }) == .Ok)
    geometry: shapemodel.Shape_Geometry = {
        kind = .Line,
    }
    geometry.payload.line = {
        first = first,
        second = second,
    }
    assert(shapemodel.shape_component_insert(&world.geometries, &world.registry,
        shape, geometry) == .Ok)
}

// Verify world clear particles resolve direct line entities without child topology.
@(test)
emit_shape_world_clear_burst_spawns_dust_for_direct_line :: proc(t: ^testing.T) {
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles)
    particles.use_max_dust_particles = 4
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    seed_shape_world_particle_line(world, true)

    emit_shape_world_clear_burst(particles, world)

    testing.expect(t, particles.low_particles.alive[0])
    testing.expect(t, particles.low_particles.alive[1])
}

// Verify hidden world geometry does not participate in clear particle emission.
@(test)
emit_shape_world_clear_burst_skips_hidden_geometry :: proc(t: ^testing.T) {
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles)
    particles.use_max_dust_particles = 4
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    seed_shape_world_particle_line(world, false)

    emit_shape_world_clear_burst(particles, world)

    for alive in particles.low_particles.alive[:particles.use_max_dust_particles] {
        testing.expect(t, !alive)
    }
}

// Verify outgoing samples follow the rendered concave polygon beyond twelve vertices.
@(test)
emit_shape_world_polygon_burst_uses_rendered_concave_triangles :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = MAX_DEPARTURE_MATERIAL_SAMPLES
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    positions: [16]Vector3 = {
        {0, 0, 0}, {2, 0, 0}, {4, 0, 0}, {4, 0.8, 0},
        {1, 0.8, 0}, {1.1, 1, 0}, {1, 1.5, 0}, {1, 2.5, 0},
        {1.1, 3, 0}, {1, 3.2, 0}, {4, 3.2, 0}, {4, 4, 0},
        {2, 4, 0}, {0, 4, 0}, {0, 2, 0}, {0, 1, 0},
    }
    vertices: [16]shapemodel.Shape_Entity
    polygon, status := shapes.world_create_polygon_into(world, positions[:], {
        color = color.WHITE,
        brush_size = 1,
    }, vertices[:])
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world.render_styles.values[0].visible = true
    shapes.build_shape_world_draw_cache(world, 1)
    draw, prepared := shape_world_cached_polygon_draw(world, polygon.shape)
    testing.expect(t, prepared)
    testing.expect(t, draw.triangle_count > 10)

    testing.expect(t, emit_shape_world_hide_burst(
        ps, world, polygon.shape, {false, 1, 1}))
    for index in 0..<ps^.use_max_dust_particles {
        x := ps^.low_particles.pos_x[index]
        y := ps^.low_particles.pos_y[index]
        in_open_notch := x > 1.15 && x < 3.9 && y > 1.05 && y < 3.15
        testing.expect(t, !in_open_notch)
    }
}

// Verify region targets are bounded value copies rather than draw-cache aliases.
@(test)
sample_shape_world_polygon_material_copies_bounded_targets :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    vertices: [4]shapemodel.Shape_Entity
    polygon := particle_test_visible_square(world, 0.1, vertices[:])
    testing.expect(t, polygon.prepared)
    output: [4]Polygon_Material_Sample
    request: Polygon_Material_Sampling = {
        projected_scale = 1,
        density = 900,
        seed = 42,
    }

    count, ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, request, output[:])

    testing.expect(t, ready)
    testing.expect_value(t, count, len(output))
    original := output[0].position
    testing.expect_value(t, output[0].coverage, u8(255))
    testing.expect(t, output[0].position.x >= 0.2 && output[0].position.x <= 0.8)
    testing.expect(t, output[0].position.y >= 0.2 && output[0].position.y <= 0.8)
    world.draw_cache.polygon_vertices[0].x = 0.99
    testing.expect_value(t, output[0].position, original)
}

// Compare deterministic material targets from repeated identical requests.
particle_test_material_samples_match :: proc(
    first, second: []Polygon_Material_Sample, count: int) -> bool {
    if count > len(first) || count > len(second) {
        return false
    }
    for index in 0..<count {
        if first[index].position != second[index].position {
            return false
        }
    }
    return true
}

// Check that every copied target remains inside the test square.
particle_test_material_samples_inside_square :: proc(
    samples: []Polygon_Material_Sample) -> bool {
    for sample in samples {
        if sample.position.x < 0.2 || sample.position.x > 0.8 ||
            sample.position.y < 0.2 || sample.position.y > 0.8 {
            return false
        }
    }
    return true
}

// Verify requested density and scale control copied region sample counts.
@(test)
sample_shape_world_polygon_material_respects_density_and_scale :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    vertices: [4]shapemodel.Shape_Entity
    polygon := particle_test_visible_square(world, 0, vertices[:])
    testing.expect(t, polygon.prepared)
    low_scale: [MAX_DEPARTURE_MATERIAL_SAMPLES]Polygon_Material_Sample
    high_scale: [MAX_DEPARTURE_MATERIAL_SAMPLES]Polygon_Material_Sample
    minimum: [16]Polygon_Material_Sample
    sparse: [1]Polygon_Material_Sample
    low_count, low_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, {
            projected_scale = 0.5,
            density = 100,
            seed = 7,
        }, low_scale[:])
    high_count, high_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, {
            projected_scale = 2,
            density = 100,
            seed = 7,
        }, high_scale[:])
    sparse_count, sparse_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, {
            projected_scale = 1,
            density = 0.001,
            seed = 11,
        }, sparse[:])
    minimum_count, minimum_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, {
            projected_scale = 1,
            density = 0.001,
            minimum_count = 8,
            seed = 11,
        }, minimum[:])
    testing.expect(t, low_ready && high_ready)
    testing.expect(t, sparse_ready)
    testing.expect(t, minimum_ready)
    testing.expect_value(t, low_count, 9)
    testing.expect_value(t, high_count, 144)
    testing.expect_value(t, sparse_count, 1)
    testing.expect_value(t, minimum_count, 8)
    testing.expect(t, particle_test_material_samples_inside_square(sparse[:]))
}

// Verify an identical seed reproduces the same bounded polygon targets.
@(test)
sample_shape_world_polygon_material_is_seed_deterministic :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    vertices: [4]shapemodel.Shape_Entity
    polygon := particle_test_visible_square(world, 0, vertices[:])
    testing.expect(t, polygon.prepared)
    first: [4]Polygon_Material_Sample
    second: [4]Polygon_Material_Sample
    request: Polygon_Material_Sampling = {
        projected_scale = 1,
        density = 900,
        seed = 42,
    }
    first_count, first_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, request, first[:])
    second_count, second_ready := sample_shape_world_polygon_material(
        ps, world, polygon.entity, request, second[:])
    testing.expect(t, first_ready && second_ready)
    testing.expect_value(t, first_count, len(first))
    testing.expect_value(t, second_count, len(second))
    testing.expect(t, particle_test_material_samples_inside_square(first[:]))
    testing.expect(t, particle_test_material_samples_match(
        first[:], second[:], first_count))
}

// Verify concave region formation attaches to prepared triangles and completes on time.
@(test)
formation_region_targets_follow_geometry_and_authored_progress :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    setup := particle_test_prepare_formation_region(ps, world)
    testing.expect(t, setup.prepared)
    testing.expect_value(t, setup.count, FORMATION_REGION_MAX_SAMPLES)
    testing.expect_value(t, ps^.formation.particle_count, setup.count)
    testing.expect_value(t, formation_region_opacity(
        ps, shapemodel.shape_entity_pack(setup.entity)), f32(0))
    testing.expect(t, particle_test_formation_visible_count(ps) < setup.count / 20)
    testing.expect(t, particle_test_formation_attachments_valid(ps))
    particle_index, topology_rebuilt := particle_test_rebuild_formation_topology(
        ps, world, setup.entity, setup.count)
    testing.expect(t, topology_rebuilt)
    testing.expect(t, particle_test_formation_moves_and_completes(
        ps, world, setup.entity, particle_index))
}

// Verify normalized catalogue geometry produces thousands of forming fragments.
@(test)
formation_region_density_matches_normalized_polygon_area :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    positions: [5]Vector3 = {
        {0.50, 0.76, 0}, {0.31, 0.62, 0}, {0.38, 0.36, 0},
        {0.62, 0.36, 0}, {0.69, 0.62, 0},
    }
    vertices: [5]shapemodel.Shape_Entity
    entity, prepared := particle_test_visible_polygon(world, positions[:], vertices[:])
    testing.expect(t, prepared && particle_test_start_region_reveal(ps, entity))
    count := formation_prepare_region_targets(ps, world, 1)
    testing.expect(t, count >= 6000 && count <= FORMATION_REGION_MAX_SAMPLES)
    testing.expect_value(t, ps^.formation.particle_count, count)
    roles := particle_test_formation_role_counts(ps)
    testing.expect(t, roles[.Leaper] >= 600)
    testing.expect_value(t, roles[.Pigment] + roles[.Leaper], count)
    testing.expect_value(t, formation_prepare_region_targets(ps, world, 2), count)
    testing.expect_value(t, ps^.formation.particle_count, count)
}

// Verify hashed region lifecycles stagger births and keep every role inside its reveal.
@(test)
formation_region_lifecycles_stagger_roles_within_reveal :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    setup := particle_test_prepare_formation_region(ps, world)
    testing.expect(t, setup.prepared)
    earliest, latest := f32(1), f32(0)
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := ps^.formation.particles[index]
        if !particle.alive {
            continue
        }
        earliest = min(earliest, particle.birth)
        latest = max(latest, particle.birth)
        testing.expect(t, particle.birth + particle.flight <= 0.98)
    }
    testing.expect(t, earliest < 0.01 && latest > 0.6)
    roles := particle_test_formation_role_counts(ps)
    testing.expect_value(t, roles[.Leaper],
        (setup.count + FORMATION_REGION_LEAPER_INTERVAL - 1) /
            FORMATION_REGION_LEAPER_INTERVAL)
}

// Verify most leapers make low decaying hops while a hashed few pop once, higher.
@(test)
formation_leapers_mostly_hop_low :: proc(t: ^testing.T) {
    poppers, hoppers := 0, 0
    for index := 0; index < 4000; index += FORMATION_REGION_LEAPER_INTERVAL {
        lifecycle := formation_lifecycle(.Region, 0xC0FFEE, index)
        testing.expect_value(t,
            lifecycle.role, particlemodel.Formation_Particle_Role.Leaper)
        if lifecycle.hops == 1 {
            poppers += 1
            testing.expect(t, lifecycle.height >= FORMATION_LEAPER_POP_HEIGHT_MIN)
        } else {
            hoppers += 1
            testing.expect(t, lifecycle.hops == 2 || lifecycle.hops == 3)
            testing.expect(t, lifecycle.height <= 0.02)
        }
    }
    testing.expect(t, poppers > 60 && poppers < 145)
    testing.expect(t, hoppers > poppers * 4)
}

// Verify pigment and leaper visuals follow their authored lifecycles.
@(test)
formation_region_role_visuals_follow_lifecycles :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    setup := particle_test_prepare_formation_region(ps, world)
    testing.expect(t, setup.prepared)
    testing.expect(t, particle_test_pigment_lifecycle(ps))
    testing.expect(t, particle_test_leaper_lifecycle(ps))
}

// Verify formation draw order covers visible material back to front and stays stable.
@(test)
formation_draw_order_sorts_visible_material_back_to_front :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    setup := particle_test_prepare_formation_region(ps, world)
    testing.expect(t, setup.prepared)
    testing.expect(t, formation_advance_progress(ps, 7, 0.5))
    count := formation_prepare_draw_order(ps)
    testing.expect(t, count > 0)
    testing.expect_value(t, count, particle_test_formation_visible_count(ps))
    testing.expect(t, particle_test_draw_order_back_to_front(
        &ps^.formation.draw_order, count))
}

// Verify equal depths keep compaction order and unequal depths sort far to near.
@(test)
formation_bucket_sort_depths_is_stable_far_to_near :: proc(t: ^testing.T) {
    draw := new(particlemodel.Formation_Draw_Order, context.allocator)
    defer free(draw, context.allocator)
    depths: [6]f32 = {0.2, 0.9, 0.2, -0.4, 0.9, 0.2}
    for depth, index in depths {
        draw^.depths[index] = depth
    }
    formation_bucket_sort_depths(draw, len(depths), -0.4, 0.9)
    expected: [6]u16 = {1, 4, 0, 2, 5, 3}
    for slot, index in expected {
        testing.expect_value(t, draw^.order[index], slot)
    }
}

// Check that each ordered depth is no nearer than one bucket behind its successor.
particle_test_draw_order_back_to_front :: proc(
    draw: ^particlemodel.Formation_Draw_Order, count: int) -> bool {
    nearest, farthest := max(f32), min(f32)
    for index in 0..<count {
        nearest = min(nearest, draw^.depths[index])
        farthest = max(farthest, draw^.depths[index])
    }
    tolerance := (farthest - nearest) / f32(FORMATION_DEPTH_BUCKETS - 1)
    seen: [MAX_FORMATION_PARTICLES]bool
    for index in 0..<count {
        slot := int(draw^.order[index])
        if seen[slot] {
            return false
        }
        seen[slot] = true
        if index > 0 && draw^.depths[slot] >
            draw^.depths[draw^.order[index - 1]] + tolerance {
            return false
        }
    }
    return true
}

// Count live formation particles by role.
particle_test_formation_role_counts :: proc(
    ps: ^particlemodel.Particle_System) -> [particlemodel.Formation_Particle_Role]int {
    counts: [particlemodel.Formation_Particle_Role]int
    for index in 0..<MAX_FORMATION_PARTICLES {
        if ps^.formation.particles.alive[index] {
            counts[ps^.formation.particles.role[index]] += 1
        }
    }
    return counts
}

// Count formation particles visible at the current accepted progress.
particle_test_formation_visible_count :: proc(
    ps: ^particlemodel.Particle_System) -> int {
    count := 0
    for index in 0..<MAX_FORMATION_PARTICLES {
        if formation_particle_visual(ps, index).visible {
            count += 1
        }
    }
    return count
}

// Find the first live particle of one role whose lifecycle starts inside a range.
particle_test_find_formation_role :: proc(
    ps: ^particlemodel.Particle_System, role: particlemodel.Formation_Particle_Role,
    birth_min, birth_max: f32) -> int {
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := ps^.formation.particles[index]
        if particle.alive && particle.role == role &&
            particle.birth >= birth_min && particle.birth <= birth_max {
            return index
        }
    }
    return -1
}

// Probe one fraction of a particle's flight without retiring the reveal.
particle_test_formation_visual_at :: proc(
    ps: ^particlemodel.Particle_System, index: int,
    local: f32) -> Formation_Particle_Visual {
    particle := ps^.formation.particles[index]
    ps^.formation.accepted_progress = f64(particle.birth + particle.flight * local)
    return formation_particle_visual(ps, index)
}

// Verify pigment stays hidden before birth, falls in its own color, and lands fully.
particle_test_pigment_lifecycle :: proc(ps: ^particlemodel.Particle_System) -> bool {
    index := particle_test_find_formation_role(ps, .Pigment, 0.2, 0.4)
    if index < 0 {
        return false
    }
    particle := ps^.formation.particles[index]
    hidden := !particle_test_formation_visual_at(ps, index, -0.1).visible
    falling := particle_test_formation_visual_at(ps, index, 0.5)
    landed := particle_test_formation_visual_at(ps, index, 1.02)
    return hidden && falling.visible &&
        falling.position.z > particle.target_z &&
        falling.color.a < landed.color.a &&
        falling.diameter < landed.diameter &&
        falling.color.r == particle.color.r &&
        falling.authored_color == particle.color &&
        falling.white_mix == 0 &&
        landed.position.x == particle.target_x &&
        landed.position.z == particle.target_z &&
        landed.color.a == particle.color.a
}

// Verify a leaper launches large and pale, shrinks hopping, and lands in polygon color.
particle_test_leaper_lifecycle :: proc(ps: ^particlemodel.Particle_System) -> bool {
    index := particle_test_find_formation_role(ps, .Leaper, 0.1, 0.5)
    if index < 0 {
        return false
    }
    particle := ps^.formation.particles[index]
    launch := particle_test_formation_visual_at(ps, index, 0.05)
    apex := particle_test_formation_visual_at(
        ps, index, 0.5 / f32(max(particle.hops, 1)))
    falling := particle_test_formation_visual_at(ps, index, 0.75)
    landed := particle_test_formation_visual_at(ps, index, 1.02)
    scale := particle.size * FORMATION_LEAPER_SIZE_SCALE
    return launch.visible && launch.diameter > scale * 1.35 &&
        launch.color.r == 255 && launch.color.g == 255 && launch.color.b == 255 &&
        launch.authored_color == particle.color && launch.white_mix > 0.9 &&
        launch.position.z < apex.position.z &&
        apex.diameter < launch.diameter &&
        falling.color.r == particle.color.r &&
        falling.color.g == particle.color.g &&
        falling.color.b == particle.color.b &&
        falling.authored_color == particle.color && falling.white_mix == 0 &&
        landed.visible && landed.diameter == scale &&
        landed.color == particle.color &&
        landed.position.z == particle.target_z
}

// Check the trailing fill opacity at half of a reveal.
particle_test_formation_half_fill :: proc(opacity: f32) -> bool {
    return abs(opacity - 0.198251) < 0.00001
}

// Prepare one concave polygon and start its deterministic region reveal.
particle_test_prepare_formation_region :: proc(
    ps: ^particlemodel.Particle_System,
    world: ^shapemodel.Shape_World) -> Particle_Test_Formation_Setup {
    positions: [16]Vector3 = {
        {0, 0, 0.1}, {2, 0, 0.1}, {4, 0, 0.1}, {4, 0.8, 0.1},
        {1, 0.8, 0.1}, {1.1, 1, 0.1}, {1, 1.5, 0.1}, {1, 2.5, 0.1},
        {1.1, 3, 0.1}, {1, 3.2, 0.1}, {4, 3.2, 0.1}, {4, 4, 0.1},
        {2, 4, 0.1}, {0, 4, 0.1}, {0, 2, 0.1}, {0, 1, 0.1},
    }
    vertices: [16]shapemodel.Shape_Entity
    entity, prepared := particle_test_visible_polygon(world, positions[:], vertices[:])
    if !prepared || !particle_test_start_region_reveal(ps, entity) {
        return {
            entity = entity,
        }
    }
    return {
        entity = entity,
        count = formation_prepare_region_targets(ps, world, 1),
        prepared = true,
    }
}

// Validate copied triangle coordinates for all live formation fragments.
particle_test_formation_attachments_valid :: proc(
    ps: ^particlemodel.Particle_System) -> bool {
    for index in 0..<MAX_FORMATION_PARTICLES {
        sample := &ps^.formation.particles[index]
        if sample^.alive {
            if sample^.barycentric_u < 0 || sample^.barycentric_v < 0 ||
                sample^.barycentric_u + sample^.barycentric_v > 1 {
                return false
            }
            in_notch := sample^.target_x > 1.15 && sample^.target_x < 3.9 &&
                sample^.target_y > 1.05 && sample^.target_y < 3.15
            if in_notch {
                return false
            }
        }
    }
    return true
}

// Rebuild a reveal's sampled attachments after a prepared topology revision.
particle_test_rebuild_formation_topology :: proc(
    ps: ^particlemodel.Particle_System, world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity, count: int) -> (int, bool) {
    reveal_slot := formation_find_reveal(
        &ps^.formation, .Region, shapemodel.shape_entity_pack(entity), 7)
    original_start := ps^.formation.reveals[reveal_slot].start_progress
    original_signature := ps^.formation.reveals[reveal_slot].topology_signature
    draw, draw_found := shape_world_cached_polygon_draw(world, entity)
    if !draw_found {
        return -1, false
    }
    triangle := &world^.draw_cache.polygon_triangles[
        draw.first_triangle]
    triangle^.a, triangle^.b = triangle^.b, triangle^.a
    _ = formation_prepare_region_targets(ps, world, 1)
    rebuilt := ps^.formation.reveals[reveal_slot].topology_signature !=
        original_signature &&
        ps^.formation.reveals[reveal_slot].start_progress == original_start &&
        ps^.formation.particle_count == count
    particle_index := -1
    for index in 0..<MAX_FORMATION_PARTICLES {
        if ps^.formation.particles.alive[index] {
            particle_index = index
            break
        }
    }
    return particle_index, rebuilt && particle_index >= 0
}

// Verify attached targets move with elevated geometry and finish on authored time.
particle_test_formation_moves_and_completes :: proc(
    ps: ^particlemodel.Particle_System, world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity, particle_index: int) -> bool {
    original_target := ps^.formation.particles.target_x[particle_index]
    for index in 0..<world^.draw_cache.polygon_vertex_count {
        world^.draw_cache.polygon_vertices[index].x += 0.1
        world^.draw_cache.polygon_vertices[index].z += 0.2
    }
    _ = formation_prepare_region_targets(ps, world, 1)
    moved := ps^.formation.particles.target_x[particle_index] > original_target &&
        ps^.formation.particles.target_z[particle_index] == f32(0.3)
    if !moved || !formation_advance_progress(ps, 7, 0.5) ||
        !particle_test_formation_half_fill(
            formation_region_opacity(ps, shapemodel.shape_entity_pack(entity))) {
        return false
    }
    if !formation_advance_progress(ps, 7, 1) ||
        ps^.formation.particle_count != 0 ||
        formation_region_opacity(ps, shapemodel.shape_entity_pack(entity)) != 1 {
        return false
    }
    return true
}

// Verify target publication midway through a reveal catches up without restarting.
@(test)
formation_region_late_target_publication_catches_up :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    entity, created := particle_test_create_late_region(world)
    testing.expect(t, created)
    formation_reset_generation(ps, 9)
    testing.expect(t, formation_advance_progress(ps, 9, 0))
    testing.expect(t, formation_start_reveal(ps, {
        kind = .Region,
        owner_entity = shapemodel.shape_entity_pack(entity),
        animation_generation = 9,
        progress = 0,
        duration = 1,
        seed = 29,
    }))
    testing.expect_value(t, formation_prepare_region_targets(ps, world, 1), 0)
    testing.expect(t, formation_advance_progress(ps, 9, 0.5))
    shapes.build_shape_world_draw_cache(world, 1)
    testing.expect(t, formation_prepare_region_targets(ps, world, 1) > 0)
    slot := formation_find_reveal(
        &ps^.formation, .Region, shapemodel.shape_entity_pack(entity), 9)
    testing.expect_value(t, ps^.formation.reveals[slot].start_progress, f64(0))
    testing.expect(t, particle_test_formation_half_fill(formation_region_opacity(
        ps, shapemodel.shape_entity_pack(entity))))
}

// Create a visible polygon without preparing its draw cache yet.
particle_test_create_late_region :: proc(
    world: ^shapemodel.Shape_World) -> (shapemodel.Shape_Entity, bool) {
    positions: [16]Vector3 = {
        {0, 0, 0.1}, {2, 0, 0.1}, {4, 0, 0.1}, {4, 0.8, 0.1},
        {1, 0.8, 0.1}, {1.1, 1, 0.1}, {1, 1.5, 0.1}, {1, 2.5, 0.1},
        {1.1, 3, 0.1}, {1, 3.2, 0.1}, {4, 3.2, 0.1}, {4, 4, 0.1},
        {2, 4, 0.1}, {0, 4, 0.1}, {0, 2, 0.1}, {0, 1, 0.1},
    }
    vertices: [16]shapemodel.Shape_Entity
    polygon, status := shapes.world_create_polygon_into( world, positions[:], {
        color = color.WHITE,
        brush_size = 1,
    }, vertices[:])
    if status != shapemodel.Shape_World_Status.Ok {
        return {}, false
    }
    style, found := shapemodel.shape_component_get_mut(
        &world^.render_styles, &world^.registry, polygon.shape)
    if !found {
        return {}, false
    }
    style^.visible = true
    return polygon.shape, true
}

// Count emitted positions in four equal-area cells of the test square.
particle_material_quadrant_counts :: proc(
    ps: ^particlemodel.Particle_System) -> [4]int {
    counts: [4]int
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] {
            continue
        }
        bucket := 0
        if ps^.low_particles.pos_x[index] >= 0.5 {
            bucket += 1
        }
        if ps^.low_particles.pos_y[index] >= 0.5 {
            bucket += 2
        }
        counts[bucket] += 1
    }
    return counts
}

// Verify equivalent polygon triangulations preserve material coverage.
particle_test_expect_equivalent_quadrant_counts :: proc(
    t: ^testing.T,
    first, second: ^particlemodel.Particle_System) {
    first_counts := particle_material_quadrant_counts(first)
    second_counts := particle_material_quadrant_counts(second)
    for index in 0..<len(first_counts) {
        testing.expect(t, first_counts[index] > 55 && first_counts[index] < 108)
        delta := first_counts[index] - second_counts[index]
        if delta < 0 {
            delta = -delta
        }
        testing.expect(t, delta < 25)
    }
}

// Verify alternate rendered diagonals preserve comparable material coverage.
@(test)
polygon_material_sampling_is_stable_across_equivalent_triangulations :: proc(
    t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    first := new(particlemodel.Particle_System, context.allocator)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    defer free(second)
    first^.use_max_dust_particles = MAX_DEPARTURE_MATERIAL_SAMPLES
    second^.use_max_dust_particles = MAX_DEPARTURE_MATERIAL_SAMPLES
    vertices: [4]shapemodel.Shape_Entity
    polygon := particle_test_visible_square(world, 0, vertices[:])
    testing.expect(t, polygon.prepared)
    tint: color.Color_RGBA8 = {120, 180, 220, 128}
    context_a: Shape_World_Burst_Context = {first, world, tint, 1, true}
    testing.expect(t, emit_shape_world_cached_polygon_burst(
        context_a, polygon.entity))
    testing.expect_value(t, first^.low_particles.color[0][3], u8(128))
    base := polygon.draw.first_vertex
    world.draw_cache.polygon_triangles[polygon.draw.first_triangle] = {
        base, base+1, base+3,
    }
    world.draw_cache.polygon_triangles[polygon.draw.first_triangle+1] = {
        base+1, base+2, base+3,
    }
    context_b: Shape_World_Burst_Context = {second, world, tint, 1, true}
    testing.expect(t, emit_shape_world_cached_polygon_burst(
        context_b, polygon.entity))

    particle_test_expect_equivalent_quadrant_counts(t, first, second)
}

// Verify stale cached polygon generations do not release replacement material.
@(test)
emit_shape_world_polygon_burst_rejects_stale_draw_generation :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = MAX_DEPARTURE_MATERIAL_SAMPLES
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    positions: [4]Vector3 = {
        {0.2, 0.2, 0}, {0.8, 0.2, 0},
        {0.8, 0.8, 0}, {0.2, 0.8, 0},
    }
    vertices: [4]shapemodel.Shape_Entity
    polygon, prepared := particle_test_visible_polygon(
        world, positions[:], vertices[:])
    testing.expect(t, prepared)
    #partial switch &typed in &world.draw_cache.items[0] {
    case shapemodel.Shapes_Polygon_Draw:
        typed.source_generation += 1
    case:
    }

    _, cached := shape_world_cached_polygon_draw(world, polygon)
    testing.expect(t, !cached)
    _ = emit_shape_world_hide_burst(ps, world, polygon, {false, 1, 1})
    testing.expect_value(t, count_live_low_particles(ps), 0)
    testing.expect_value(t, ps^.departure_capture_failures, u64(1))
}

// Verify circle-region departure excludes the rendered difference cutout.
@(test)
emit_shape_world_lune_burst_respects_material_cutout :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = MAX_DEPARTURE_MATERIAL_SAMPLES
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    input: shapes.Circle_Region_Input = {
        first_center = {0.35, 0.5, 0},
        second_center = {0.5, 0.5, 0},
        first_radius = 0.2,
        second_radius = 0.2,
        style = {
            color = color.WHITE,
            brush_size = 1,
        },
    }
    lune, status := shapes.world_create_lune(world, input)
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    style, found := shapemodel.shape_component_get_mut(
        &world.render_styles, &world.registry, lune.shape)
    testing.expect(t, found)
    style^.visible = true
    shapes.build_shape_world_draw_cache(world, 1)

    testing.expect(t, emit_shape_world_hide_burst(
        ps, world, lune.shape, {false, 1, 1}))
    testing.expect(t, count_live_low_particles(ps) > 10)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] {
            continue
        }
        first_dx := ps^.low_particles.pos_x[index] - input.first_center.x
        first_dy := ps^.low_particles.pos_y[index] - input.first_center.y
        second_dx := ps^.low_particles.pos_x[index] - input.second_center.x
        second_dy := ps^.low_particles.pos_y[index] - input.second_center.y
        testing.expect(t, first_dx*first_dx+first_dy*first_dy <= 0.041)
        testing.expect(t, second_dx*second_dx+second_dy*second_dy >= 0.037)
    }
}

// Verify invalid and zero-area triangles do not enter area-weighted selection.
@(test)
polygon_fill_cached_triangles_skips_degenerate_and_invalid_indices :: proc(
    t: ^testing.T) {
    cache: shapemodel.Shapes_Draw_Cache
    cache.polygon_vertices[0] = {0, 0, 0}
    cache.polygon_vertices[1] = {1, 0, 0}
    cache.polygon_vertices[2] = {0, 1, 0}
    cache.polygon_triangles[0] = {0, 1, 2}
    cache.polygon_triangles[1] = {0, 0, 1}
    cache.polygon_triangles[2] = {0, 1, MAX_DEPARTURE_MATERIAL_SAMPLES}
    cache.polygon_vertex_count = 3
    cache.polygon_triangle_count = 3

    triangles := polygon_fill_cached_triangles(&cache, {
        first_triangle = 0,
        triangle_count = 3,
    })

    testing.expect_value(t, triangles.count, 1)
    test_helpers.expect_close(t, triangles.total_area, f32(0.5),
        "only nondegenerate valid triangles contribute area")
    testing.expect_value(t, polygon_fill_triangle_index_at(triangles, 0.49), 0)

    skewed: Polygon_Fill_Triangles = {
        count = 2,
        total_area = 1,
    }
    skewed.areas[0] = 0.001
    skewed.areas[1] = 0.999
    tiny_triangle_samples: int
    for index in 0..<10 {
        target := (f32(index) + 0.5)/10
        if polygon_fill_triangle_index_at(skewed, target) == 0 {
            tiny_triangle_samples += 1
        }
    }
    testing.expect_value(t, tiny_triangle_samples, 0)
}

// Verify shaped-label coverage attenuates alpha while retaining its world height.
@(test)
emit_departure_material_burst_preserves_coverage_and_plane :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    samples: [2]Departure_Material_Sample = {
        {{0.25, 0.4, 0.3}, 128},
        {{0.75, 0.6, 0.5}, 255},
    }
    tint: Color = {20, 40, 60, 200}

    testing.expect(t, emit_departure_material_burst(ps, samples[:], tint))

    testing.expect_value(t, count_live_low_particles(ps), 2)
    testing.expect_value(t, ps^.low_particles.color[0][3], u8(100))
    testing.expect_value(t, ps^.low_particles.color[1][3], u8(200))
    testing.expect(t, ps^.low_particles.authored_ink[0])
    testing.expect(t, ps^.low_particles.authored_ink[1])
    test_helpers.expect_close(t, ps^.low_particles.pos_z[0], f32(0.3),
        "label departure remains on its source plane")
    test_helpers.expect_close(t, ps^.low_particles.pos_z[1], f32(0.5),
        "label departure remains on its source plane")
}

// Verify out-of-bounds particles clamp to the bounds and bounce their velocity.
@(test)
clamp_xy_bounds_index_bounces_particles_back_inside_bounds :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1

    ps^.low_particles.pos_x[0] = -0.5
    ps^.low_particles.pos_y[0] = 1.2
    ps^.low_particles.vel_x[0] = -0.1
    ps^.low_particles.vel_y[0] = 0.2

    clamp_xy_bounds_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_x[0], DUST_XY_MIN)
    testing.expect_value(t, ps^.low_particles.pos_y[0], DUST_XY_MAX)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
}

// Start one deterministic label reveal at accepted progress zero.
particle_test_start_formation_label :: proc(
    ps: ^particlemodel.Particle_System, owner: u64, duration: f32) -> int {
    if ps^.formation.animation_generation != 11 {
        formation_reset_generation(ps, 11)
        _ = formation_advance_progress(ps, 11, 0)
    }
    if !formation_start_reveal(ps, {
        kind = .Label,
        owner_entity = owner,
        animation_generation = 11,
        progress = ps^.formation.accepted_progress,
        duration = duration,
        seed = 43,
    }) {
        return -1
    }
    return formation_find_reveal(&ps^.formation, .Label, owner, 11)
}

// Fill one synthetic glyph-coverage grid with full and partial ink.
particle_test_label_ink :: proc(
    output: []particlemodel.Formation_Label_Ink_Sample, shift: f32) {
    for index in 0..<len(output) {
        output[index] = {
            offset = {f32(index % 8) * 3 + shift, f32(index / 8) * 3 - 12},
            coverage = index % 3 == 0 ? 128 : 255,
        }
    }
}

// Verify label particles copy coverage-budgeted ink offsets at the label anchor.
@(test)
formation_label_targets_follow_copied_ink_and_budget :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps, context.allocator)
    slot := particle_test_start_formation_label(ps, 77, 1)
    testing.expect(t, slot >= 0)
    ink: [32]particlemodel.Formation_Label_Ink_Sample
    particle_test_label_ink(ink[:], 0)
    request: particlemodel.Formation_Label_Target_Request = {
        anchor = {0.3, 0.4, 0.05},
        color = {200, 100, 50, 255},
        font_size = 16,
        signature = 5,
    }
    expected := formation_label_sample_count(
        formation_label_ink_weight(ink[:]), 16)
    testing.expect(t, expected > FORMATION_LABEL_MIN_SAMPLES &&
        expected < FORMATION_LABEL_MAX_SAMPLES)
    testing.expect_value(t,
        formation_store_label_targets(ps, slot, request, ink[:]), expected)
    testing.expect_value(t, ps^.formation.reveals[slot].material_count, expected)
    half_cell := f32(16 * FORMATION_LABEL_CELL_FRACTION * 0.5 + 0.001)
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := ps^.formation.particles[index]
        if !particle.alive {
            continue
        }
        testing.expect_value(t, particle.target_x, f32(0.3))
        testing.expect_value(t, particle.target_z, f32(0.05))
        testing.expect(t, particle.ink_x >= -half_cell &&
            particle.ink_x <= 21 + half_cell)
        testing.expect(t, particle.ink_y >= -12 - half_cell &&
            particle.ink_y <= -3 + half_cell)
    }
    testing.expect_value(t,
        formation_store_label_targets(ps, slot, request, {}), 0)
    testing.expect_value(t, ps^.formation.particle_count, 0)
    testing.expect_value(t, ps^.formation.reveals[slot].topology_signature, u64(5))
}

// Verify ink rebuilds and anchor moves keep authored reveal time.
@(test)
formation_label_rebuild_and_anchor_refresh_keep_time :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps, context.allocator)
    slot := particle_test_start_formation_label(ps, 78, 1)
    testing.expect(t, formation_advance_progress(ps, 11, 0.5))
    ink: [24]particlemodel.Formation_Label_Ink_Sample
    particle_test_label_ink(ink[:], 0)
    request: particlemodel.Formation_Label_Target_Request = {
        anchor = {0.5, 0.5, 0},
        color = {255, 255, 255, 255},
        font_size = 16,
        signature = 5,
    }
    first := formation_store_label_targets(ps, slot, request, ink[:])
    particle_test_label_ink(ink[:], 4)
    request.signature = 6
    testing.expect_value(t,
        formation_store_label_targets(ps, slot, request, ink[:]), first)
    testing.expect_value(t, ps^.formation.particle_count, first)
    testing.expect_value(t, ps^.formation.reveals[slot].start_progress, f64(0))
    testing.expect(t, particle_test_label_half_fill(formation_label_opacity(ps, 78)))
    anchors: [MAX_FORMATION_REVEALS]Vector3
    ready: [MAX_FORMATION_REVEALS]bool
    anchors[slot] = {0.1, 0.2, 0.3}
    ready[slot] = true
    testing.expect_value(t,
        formation_refresh_label_targets(ps, anchors[:], ready[:]), first)
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := ps^.formation.particles[index]
        if particle.alive {
            testing.expect_value(t, particle.target_y, f32(0.2))
        }
    }
}

// Check the label crisp-ink fill at half progress against smoothstep(0.45, 1, t).
particle_test_label_half_fill :: proc(opacity: f32) -> bool {
    x := (f32(0.5) - FORMATION_LABEL_FILL_START) / (1 - FORMATION_LABEL_FILL_START)
    return abs(opacity - x * x * (3 - 2 * x)) < 0.00001
}

// Verify simultaneous labels keep independent durations and the label fill curve.
@(test)
formation_label_opacity_follows_independent_durations :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps, context.allocator)
    testing.expect(t, particle_test_start_formation_label(ps, 81, 1) >= 0)
    testing.expect(t, particle_test_start_formation_label(ps, 82, 2) >= 0)
    testing.expect_value(t, formation_label_opacity(ps, 81), f32(0))
    testing.expect(t, formation_advance_progress(ps, 11, 0.4))
    testing.expect_value(t, formation_label_opacity(ps, 81), f32(0))
    testing.expect(t, formation_advance_progress(ps, 11, 1))
    testing.expect(t, particle_test_label_half_fill(formation_label_opacity(ps, 82)))
    testing.expect_value(t, formation_label_opacity(ps, 81), f32(1))
    testing.expect_value(t, formation_owner_opacity(ps, 81), f32(1))
    testing.expect_value(t, formation_label_opacity(ps, 99), f32(1))
}

// Verify label lifecycles use the smaller leaper cadence, reach, and size policy.
@(test)
formation_label_lifecycle_uses_smaller_budget_policy :: proc(t: ^testing.T) {
    leapers := 0
    for index in 0..<140 {
        label := formation_lifecycle(.Label, 43, index)
        region := formation_lifecycle(.Region, 43, index)
        if label.role == .Leaper {
            leapers += 1
        }
        if label.role == region.role {
            testing.expect(t, abs(label.size -
                region.size * FORMATION_LABEL_SIZE_SCALE) < 0.0001)
            testing.expect(t, abs(label.height -
                region.height * FORMATION_LABEL_MOTION_SCALE) < 0.0001)
            testing.expect_value(t, label.birth, region.birth)
        }
    }
    testing.expect_value(t, leapers, 140 / FORMATION_LABEL_LEAPER_INTERVAL)
}

// Trail emission lays pigment on every tick and starts leapers white over the stroke.
@(test)
trail_emission_spawns_pigment_and_white_leapers :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    stroke: color.Color_RGBA8 = {40, 80, 160, 255}
    emit_trail_particles(ps, SPAWN_INTERVAL * 40, {
        origin = {0.5, 0.5, 0},
        color = stroke,
    })

    pigment, leapers := 0, 0
    for index in 0..<MAX_PARTICLES {
        if !ps^.particles.alive[index] {
            continue
        }
        switch ps^.particles.role[index] {
        case .Pigment:
            pigment += 1
        case .Leaper:
            leapers += 1
            ps^.particles.age[index] = ps^.particles.life[index] * 0.1
            visual := trail_particle_visual(ps, index)
            testing.expect(t, visual.color.b > stroke.b)
        }
    }
    testing.expect_value(t, pigment,
        40 * (TRAIL_PIGMENT_PER_SPAWN + TRAIL_HOT_PIGMENT_PER_SPAWN))
    testing.expect_value(t, leapers, 40 * TRAIL_LEAPERS_PER_SPAWN)
}
