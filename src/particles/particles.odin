package particles

import shapemodel "../shapes/model"
import particlemodel "model"

// Simple particle system kinda took off away from me a bit here, but it has a few important
// points to discuss:

// 3 Layers : Low, Middle, High.
// Technically, we try to not be picky about what kind of particle is in each, but there's
// a clear pattern. Low has dust, Middle has Ember, and the high layer has the
// Flicker particles.

// Particle types :
//
// - Dust particles move around and collide with eachother, giving some Newtonian style
//   physics to them. They can be emitted from shapes, creating an effect of the shapes
//   being deconstructed into dust. Their lifetime is dependent on how many times the dust
//   is kicked up, as opposed to hard time restraints.
// - Ember particles are used for both trail and burnout effects and create the kind of
//   flat-magic-fire feel that trails behind tools on the ground. A per-particle white
//   blend factor controls whether the particle starts as white-hot burnout or plain trail.
// - Flicker move in a 3D velocity away from the point of emission. They randomly show as
//   single pixels drawn on the screen. The result is a kind of sparkling flicker effect.

import "core:math"
import rand "core:math/rand"

import rl "vendor:raylib"

Vector2 :: rl.Vector2
Vector3 :: rl.Vector3
Particle :: particlemodel.Particle
Particle_System :: particlemodel.Particle_System
MAX_PARTICLES :: particlemodel.MAX_PARTICLES

SPAWN_INTERVAL :: 0.012 // seconds
PARTICLE_LIFE :: 0.75  // seconds
PARTICLE_SIZE_START :: 5.0
PARTICLE_SIZE_END :: 0.5
FLOOR_Z :: 0.0
JITTER_PIXELS :: 0.0055
LIFE_VARIATION_MIN :: 80
LIFE_VARIATION_MAX :: 120

BURNOUT_LIFE :: 0.5
BURNOUT_SIZE_START :: 3.5
BURNOUT_SIZE_END :: 0.0
BURNOUT_PER_TRAIL_SPAWN :: 3

FLICKERS_PER_TRAIL_SPAWN :: 4
FLICKER_LIFE_MIN :: 0.0
FLICKER_LIFE_MAX :: 0.5
FLICKER_SPAWN_RADIUS :: 0.001
FLICKER_UP_SPEED_MIN :: 0.0
FLICKER_UP_SPEED_MAX :: 0.001
FLICKER_XY_DRIFT_STEP :: 0.001
FLICKER_CHANCE_PER_STEP :: 0.07
FLICKER_LIT_FRAMES_MIN :: 1
FLICKER_LIT_FRAMES_MAX :: 2

DUST_FLOOR_Z :: 0.0
DUST_GRAVITY :: -0.0016
DUST_BOUNCE :: 0.28
DUST_DRAG_XY :: 0.985
DUST_DRAG_Z :: 0.992
DUST_SIZE_START_MIN :: 0.5
DUST_SIZE_START_MAX :: 1.25
DUST_SIZE_END :: 0.15
DUST_LIFE_MIN :: 0.65
DUST_LIFE_MAX :: 1.75
DUST_VX_MIN :: -0.0025
DUST_VX_MAX :: 0.0025
DUST_VY_MIN :: -0.0025
DUST_VY_MAX :: 0.0025
DUST_VZ_MIN :: 0.0045
DUST_VZ_MAX :: 0.011

DUST_XY_MIN :: 0.0
DUST_XY_MAX :: 1.0

DUST_CONTACT_PUSH_RADIUS :: 0.01
DUST_CONTACT_PUSH_SPEED :: 0.0035
DUST_TOOL_SWEEP_MAX_INTERVALS :: 144

DUST_KICK_FADE_MIN :: 0.03
DUST_KICK_FADE_MAX :: 0.08
DUST_EXISTING_UP_KICK_MIN :: 0.0012
DUST_EXISTING_UP_KICK_MAX :: 0.0148
DUST_EXISTING_XY_KICK :: 0.0011

DUST_FLOOR_REST_SPEED :: 0.006

PARTICLE_RANDOM_SEED :: u64(0x9e3779b97f4a7c15)

DUST_TOOL_CONTACT_CAP :: particlemodel.DUST_TOOL_CONTACT_CAP

CLEAR_BURST_POINT_COUNT :: 28
CLEAR_BURST_LABEL_COUNT :: 12
CLEAR_BURST_LINE_SAMPLES :: 96
CLEAR_BURST_ARC_DENSITY :: 192.0
CLEAR_BURST_ARC_MIN_SAMPLES :: 2
CLEAR_BURST_ARC_MAX_SAMPLES :: 900
CLEAR_BURST_FILLED_CIRCLE_DENSITY :: 12000.0
CLEAR_BURST_FILLED_CIRCLE_MIN_SAMPLES :: CLEAR_BURST_POINT_COUNT
CLEAR_BURST_FILLED_CIRCLE_MAX_SAMPLES :: 900
CLEAR_BURST_EDGE_REPEATS :: 1
CLEAR_BURST_POLYGON_FILL_DENSITY :: 900.0
CLEAR_BURST_POLYGON_FILL_MIN_SAMPLES :: 10
CLEAR_BURST_POLYGON_FILL_MAX_SAMPLES :: 900

Particle_Emission :: struct {
    origin: Vector3,
    color: rl.Color,
}

Particle_Soa_Batch :: struct {
    pos_x, pos_y, pos_z: []f32,
    vel_x, vel_y, vel_z: []f32,
}

Polygon_Fill_Triangles :: struct {
    areas: [10]f32,
    count: int,
    total_area: f32,
}

Circle_Dust_Emission :: struct {
    center, start, finish: Vector3,
    offset: f32,
    color: rl.Color,
}

// Group one world-backed clear-burst operation and its render color.
Shape_World_Burst_Context :: struct {
    particles: ^Particle_System,
    world: ^shapemodel.Shape_World,
    color: rl.Color,
}

//   Emit high-layer flicker particles at a 2D origin.
//
// Parameters:
//   - ps: Particle system receiving new flicker particles.
//   - x: World-space x position for emission.
//   - y: World-space y position for emission.
//   - color: Flicker color.
//   - count: Number of flicker particles to emit.
//
// Returns:
//   - none.
emit_flicker_particles :: proc(
    ps: ^Particle_System, emission: Particle_Emission, count: int = 1) {
    if count <= 0 {
        return
    }

    for _ in 0..<count {
        spawn_flicker_particle(ps, emission.origin, emission.color)
    }
}

//   Emit Ember particles over time and attach burnout-style/Flicker effects.
//
// Parameters:
//   - ps: Particle system receiving emitted particles.
//   - dt: Simulation delta time in seconds.
//   - tip_x: Tool-tip x position used as emission origin.
//   - tip_y: Tool-tip y position used as emission origin.
//   - tip_z: Tool-tip z position used as emission origin.
//   - tip_color: Base Ember color used for both plain and burnout-style Ember particles.
//
// Returns:
//   - none.
emit_trail_particles :: proc(
    ps: ^Particle_System, dt: f32, emission: Particle_Emission) {
    ps.spawn_timer += dt

    for ps.spawn_timer >= SPAWN_INTERVAL {
        ps.spawn_timer -= SPAWN_INTERVAL

        trail_pos, ok := spawn_ember_particle(
            ps, emission.origin.x, emission.origin.y, emission.origin.z, emission.color)
        if !ok {
            continue
        }

        for _ in 0..<FLICKERS_PER_TRAIL_SPAWN {
            spawn_flicker_particle(ps, trail_pos, rl.WHITE)
        }

        for _ in 0..<BURNOUT_PER_TRAIL_SPAWN {
            spawn_burnout_ember_particle(
                ps, emission.origin.x, emission.origin.y, emission.origin.z,
                emission.color)
        }
    }
}

//   Kick currently alive dust particles to create burst-like disturbance and fade.
//
// Parameters:
//   - ps: Particle system containing dust particles.
//
// Returns:
//   - none.
kick_existing_dust_index :: proc(ps: ^Particle_System, i: int) {
    // Dust only fades when it is kicked by a new clear burst.
    ps.low_particles[i].age +=
        random_f32_range(ps, DUST_KICK_FADE_MIN, DUST_KICK_FADE_MAX)

    ps.low_particles.vel_x[i] += random_f32_range(ps,
        -DUST_EXISTING_XY_KICK,
        DUST_EXISTING_XY_KICK)
    ps.low_particles.vel_y[i] += random_f32_range(ps,
        -DUST_EXISTING_XY_KICK,
        DUST_EXISTING_XY_KICK)
    ps.low_particles.vel_z[i] += random_f32_range(ps,
        DUST_EXISTING_UP_KICK_MIN,
        DUST_EXISTING_UP_KICK_MAX)

    if ps.low_particles[i].age >= ps.low_particles[i].life {
        ps.low_particles[i].alive = false
    }
}

//   Kick currently alive dust particles to create burst-like disturbance and fade.
//
// Parameters:
//   - ps: Particle system containing dust particles.
//
// Returns:
//   - none.
kick_existing_dust :: proc(ps: ^Particle_System) {
    for i in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[i].alive {
            continue
        }

        kick_existing_dust_index(ps, i)
    }

}

//   Resolve one direct world transform position for particle emission.
shape_world_burst_position :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) -> (Vector3, bool) {
    transform, found := shapemodel.shape_component_get(
        &world.transforms, &world.registry, entity)
    if !found {
        return {}, false
    }
    return transform.position, true
}

//   Emit one world polygon through the existing bounded fill sampler.
emit_shape_world_polygon_burst :: proc(
    ctx: Shape_World_Burst_Context,
    geometry: shapemodel.Shape_Polygon_Geometry) {
    entities, found := shapemodel.shape_polygon_vertices(ctx.world, geometry)
    vertices: [12]Vector3
    if !found || len(entities) > len(vertices) {
        return
    }
    for entity, index in entities {
        position, position_found := shape_world_burst_position(ctx.world, entity)
        if !position_found {
            return
        }
        vertices[index] = position
    }
    emit_polygon_fill_dust(
        ctx.particles, &vertices, len(entities), ctx.color)
}

//   Resolve and emit one world arc using its geometry kind's density model.
emit_shape_world_arc_burst :: proc(
    ctx: Shape_World_Burst_Context,
    geometry: shapemodel.Shape_Arc_Geometry,
    offset: f32,
    filled: bool) {
    center, center_ok := shape_world_burst_position(ctx.world, geometry.center)
    start, start_ok := shape_world_burst_position(ctx.world, geometry.start)
    finish, finish_ok := shape_world_burst_position(ctx.world, geometry.finish)
    if !center_ok || !start_ok || !finish_ok {
        return
    }
    emission := Circle_Dust_Emission{center, start, finish, offset, ctx.color}
    if filled {
        emit_filled_circle_dust(ctx.particles, emission)
    } else {
        emit_circle_dust(ctx.particles, emission)
    }
}

//   Emit one direct world geometry using the legacy sampling behavior.
emit_shape_world_geometry_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Geometry,
    offset: f32) {
    switch geometry.kind {
    case .Point:
        position, found := shape_world_burst_position(ctx.world, entity)
        if found {emit_point_burst(ctx.particles, position, ctx.color)}
    case .Line:
        first, first_ok := shape_world_burst_position(
            ctx.world, geometry.payload.line.first)
        second, second_ok := shape_world_burst_position(
            ctx.world, geometry.payload.line.second)
        if first_ok && second_ok {
            emit_line_dust(ctx.particles, first, second, ctx.color)
        }
    case .Arc:
        emit_shape_world_arc_burst(ctx, geometry.payload.arc,
            offset, false)
    case .Filled_Arc:
        emit_shape_world_arc_burst(ctx, geometry.payload.arc,
            offset, true)
    case .Polygon:
        emit_shape_world_polygon_burst(ctx, geometry.payload.polygon)
    case .Pen, .Compass:
    }
}

//   Emit clear dust for one visible entity before its presentation is hidden.
emit_shape_world_hide_burst :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    kick_dust: bool = true) -> bool {
    if ps == nil || world == nil || ps.use_max_dust_particles < 1 ||
        !shapemodel.shape_registry_resolves(&world.registry, entity) {
        return false
    }
    style, found := shapemodel.shape_component_get(
        &world.render_styles, &world.registry, entity)
    if !found || !style^.visible {
        return false
    }
    if shapemodel.shape_component_contains(&world.labels, &world.registry, entity) {
        position, position_found := shape_world_burst_position(world, entity)
        if !position_found {return false}
        if kick_dust {kick_existing_dust(ps)}
        emit_label_burst(ps, position, style^.color)
        return true
    }
    geometry, geometry_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, entity)
    if !geometry_found || geometry^.kind == .Pen || geometry^.kind == .Compass {
        return false
    }
    if kick_dust {kick_existing_dust(ps)}
    emit_shape_world_geometry_burst(
        {ps, world, style^.color}, entity, geometry^, style^.offset)
    return true
}

//   Emit clear dust for every visible label and geometry in one canonical world.
emit_shape_world_clear_burst :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World) -> bool {
    if ps == nil || world == nil || ps.use_max_dust_particles < 1 {
        return false
    }
    kick_existing_dust(ps)
    for index in 0..<world.render_styles.count {
        entity := world.render_styles.entities[index]
        style := world.render_styles.values[index]
        if !style.visible ||
           !shapemodel.shape_registry_resolves(&world.registry, entity) {
            continue
        }
        ctx := Shape_World_Burst_Context{ps, world, style.color}
        if shapemodel.shape_component_contains(&world.labels, &world.registry, entity) {
            position, found := shape_world_burst_position(world, entity)
            if found {emit_label_burst(ps, position, style.color)}
            continue
        }
        geometry, found := shapemodel.shape_component_get(
            &world.geometries, &world.registry, entity)
        if found {
            emit_shape_world_geometry_burst(ctx, entity, geometry^, style.offset)
        }
    }
    return true
}

//   Advance particle simulation for dust, Ember, and Flicker layers.
//
// Parameters:
//   - ps: Particle system to update.
//   - dt: Simulation delta time in seconds.
//
// Returns:
//   - none.
update_particles :: proc(ps: ^Particle_System, dt: f32) {
    ps^.dust_floor_rest_count = 0
    update_and_deposit_low_dust(ps)
    apply_dust_tool_contacts_to_field(ps)

    integrate_particle_positions_soa_batch({
        ps.particles.pos_x[:],
        ps.particles.pos_y[:],
        ps.particles.pos_z[:],
        ps.particles.vel_x[:],
        ps.particles.vel_y[:],
        ps.particles.vel_z[:],
    })

    integrate_particle_positions_soa_batch({
        ps.high_particles.pos_x[:],
        ps.high_particles.pos_y[:],
        ps.high_particles.pos_z[:],
        ps.high_particles.vel_x[:],
        ps.high_particles.vel_y[:],
        ps.high_particles.vel_z[:],
    })

    dust_field_finish_grounded(ps, dt)

    update_mid_ember_particles(ps, dt)

    for i in 0..<MAX_PARTICLES {
        update_high_flicker_particle_index(ps, i, dt)
    }
}






//   Emit point burst dust for one position.
emit_point_burst :: proc(ps: ^Particle_System, p: Vector3, col: rl.Color) {
    for _ in 0..<CLEAR_BURST_POINT_COUNT {
        spawn_dust_particle(ps, p, col)
    }
}

//   Emit label burst dust for one position.
emit_label_burst :: proc(ps: ^Particle_System, p: Vector3, col: rl.Color) {
    for _ in 0..<CLEAR_BURST_LABEL_COUNT {
        spawn_dust_particle(ps, p, col)
    }
}

//   Integrate positions for one SoA particle bucket using velocity.
//
// Parameters:
//   - pos_x: SoA x-position slice.
//   - pos_y: SoA y-position slice.
//   - pos_z: SoA z-position slice.
//   - vel_x: SoA x-velocity slice.
//   - vel_y: SoA y-velocity slice.
//   - vel_z: SoA z-velocity slice.
//
// Returns:
//   - none.
integrate_particle_positions_soa_batch :: proc(
    particles: Particle_Soa_Batch) {
    for i in 0..<len(particles.pos_x) {
        particles.pos_x[i] += particles.vel_x[i]
        particles.pos_y[i] += particles.vel_y[i]
        particles.pos_z[i] += particles.vel_z[i]
    }
}

// Integrate every live low-layer dust particle using its current velocity.
integrate_dust_positions :: proc(ps: ^Particle_System) {
    for i in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[i].alive {
            continue
        }
        ps.low_particles.pos_x[i] += ps.low_particles.vel_x[i]
        ps.low_particles.pos_y[i] += ps.low_particles.vel_y[i]
        ps.low_particles.pos_z[i] += ps.low_particles.vel_z[i]
    }
}

// Integrate, transition, and deposit live low dust in stable slot order.
update_and_deposit_low_dust :: proc(ps: ^Particle_System) {
    dust_field_begin_deposit(ps)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] {
            continue
        }
        ps^.low_particles.pos_x[index] += ps^.low_particles.vel_x[index]
        ps^.low_particles.pos_y[index] += ps^.low_particles.vel_y[index]
        ps^.low_particles.pos_z[index] += ps^.low_particles.vel_z[index]
        update_particle_dust_index(ps, index)
        if ps^.low_particles.pos_z[index] <= DUST_FLOOR_Z {
            dust_field_deposit_grounded_index(ps, index)
        }
    }
}

//   Return the deterministic random generator owned by one particle system.
particle_random_generator :: proc(ps: ^Particle_System) -> rand.Generator {
    state := &ps^.rng_state
    if (state^.s[0] | state^.s[1] | state^.s[2] | state^.s[3]) == 0 {
        generator := rand.xoshiro256_random_generator(state)
        rand.reset(PARTICLE_RANDOM_SEED, generator)
        return generator
    }
    return rand.xoshiro256_random_generator(state)
}

//   Generate a deterministic float in the half-open [min_v, max_v) range.
random_f32_range :: proc(ps: ^Particle_System, min_v, max_v: f32) -> f32 {
    return rand.float32_range(min_v, max_v, particle_random_generator(ps))
}

//   Generate a deterministic integer in the inclusive [min_v, max_v] range.
random_i32_range :: proc(ps: ^Particle_System, min_v, max_v: i32) -> i32 {
    if min_v >= max_v {
        return min_v
    }
    return rand.int32_range(min_v, max_v + 1, particle_random_generator(ps))
}

//   Clear queued tool contacts and their lifetime diagnostics.
reset_dust_tool_contact_state :: proc(ps: ^Particle_System) {
    ps.dust_tool_contact_count = 0
    ps.dust_tool_contact_overflow_count = 0
    ps.dust_tool_contact_coalesced_count = 0
    ps.dust_tool_contact_sample_count = 0
    ps.dust_tool_contact_field_node_visit_count = 0
}

//   Reset particle-system runtime counters and mark all particle slots as dead.
reset_particles :: proc(ps: ^Particle_System) {
    ps.next_index = 0
    ps.spawn_timer = 0
    reset_dust_tool_contact_state(ps)
    ps.dust_floor_rest_count = 0
    dust_field_clear(&ps^.dust_field)
    ps.dust_transfer_count = 0
    ps.dust_grounded_count = 0
    ps.dust_peak_speed_sq = 0
    ps.dust_kinetic_measure = 0
    ps.dust_spawn_sequence = 0
    for i in 0..<ps^.use_max_dust_particles {
        ps.low_particles[i].alive = false
        ps.low_particles[i].age = 0
        ps.dust_slot_spawn_sequences[i] = 0
    }
    for i in 0..<MAX_PARTICLES {
        ps.particles.alive[i] = false
        ps.particles.age[i] = 0
        ps.high_particles.alive[i] = false
        ps.high_particles.age[i] = 0
    }
}

//   Reserve a low-layer slot for dust particles, preferring dead entries.
//
// Notes:
//   - Falls back to ring overwrite when all dust slots are alive.
reserve_dead_low_particle_slot :: proc(ps: ^Particle_System) -> (int, bool) {
    if ps^.use_max_dust_particles < 1 {
        return -1, false
    }

    for step in 0..<ps^.use_max_dust_particles {
        index := (ps.next_index + step) % ps^.use_max_dust_particles
        if !ps.low_particles[index].alive {
            ps.next_index = (index + 1) % ps^.use_max_dust_particles
            return index, true
        }
    }

    index := ps.next_index % ps^.use_max_dust_particles
    ps.next_index = (index + 1) % ps^.use_max_dust_particles
    return index, true
}

//   Reserve a high-layer slot using ring-buffer indexing.
//
// Notes:
//   - Always returns a slot by advancing next_index modulo MAX_PARTICLES.
reserve_dead_high_particle_slot :: proc(ps: ^Particle_System) -> (int, bool) {
    index := ps.next_index % MAX_PARTICLES
    ps.next_index = (index + 1) % MAX_PARTICLES
    return index, true

    // TODO: this is preserved for future evaluation, although it seems unnecessary
    /*for step in 0..<MAX_PARTICLES {
        index := (ps.next_index + step) % MAX_PARTICLES
        if !ps.high_particles.alive[index] {
            ps.next_index = (index + 1) % MAX_PARTICLES
            return index, true
        }
    }

    return nil, false*/
}

//   Reserve a mid-layer slot using ring-buffer indexing.
//
// Notes:
//   - Always returns a slot by advancing next_index modulo MAX_PARTICLES.
reserve_dead_particle_slot :: proc(ps: ^Particle_System) -> (int, bool) {
    index := ps.next_index % MAX_PARTICLES
    ps.next_index = (index + 1) % MAX_PARTICLES
    return index, true

    // TODO: this is preserved for future evaluation, although it seems unnecessary
    /*for step in 0..<MAX_PARTICLES {
        index := (ps.next_index + step) % MAX_PARTICLES
        if !ps.particles.alive[index] {
            ps.next_index = (index + 1) % MAX_PARTICLES
            return index, true
        }
    }

    return nil, false*/
}

//   Spawn one ember particle near the provided tool-tip position.
spawn_ember_particle :: proc(
    ps: ^Particle_System, tip_x, tip_y, tip_z: f32,
    tip_color: rl.Color) -> (Vector3, bool) {

    index, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return Vector3{}, false
    }

    // Tiny spawn jitter so Ember particles are less uniform.
    jitter_x := (f32(random_i32_range(ps, -1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(random_i32_range(ps, -1000, 1000)) / 1000.0) * JITTER_PIXELS
    ps.particles.pos_x[index] = tip_x + jitter_x
    ps.particles.pos_y[index] = tip_y + jitter_y
    ps.particles.pos_z[index] = tip_z

    ps.particles.age[index] = 0

    life_scale :=
        f32(random_i32_range(ps, LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    ps.particles.life[index] = PARTICLE_LIFE * life_scale

    ps.particles.size[index] = PARTICLE_SIZE_START
    ps.particles.ember_size_start[index] = PARTICLE_SIZE_START
    ps.particles.ember_size_end[index] = PARTICLE_SIZE_END
    ps.particles.ember_white_at_birth[index] = 0.0
    ps.particles.color[index] = tip_color
    ps.particles.alive[index] = true

    ps.particles.vel_x[index] = 0
    ps.particles.vel_y[index] = 0
    ps.particles.vel_z[index] = 0
    ps.particles.lit_frames[index] = 0

    spawn_pos := Vector3{ps.particles.pos_x[index],
        ps.particles.pos_y[index], ps.particles.pos_z[index]}
    return spawn_pos, true
}

//   Spawn one high-layer flicker particle at an origin with random drift.
spawn_flicker_particle :: proc(ps: ^Particle_System, origin: Vector3, color: rl.Color) {

    index, ok := reserve_dead_high_particle_slot(ps)
    if !ok {
        return
    }

    angle := random_f32_range(ps, 0.0, 6.2831855)
    radius := random_f32_range(ps, 0.0, FLICKER_SPAWN_RADIUS)

    ps.high_particles.pos_x[index] = origin.x + f32(math.cos(angle)) * radius
    ps.high_particles.pos_y[index] = origin.y + f32(math.sin(angle)) * radius
    ps.high_particles.pos_z[index] = origin.z

    ps.high_particles.vel_x[index] = random_f32_range(
        ps, -FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    ps.high_particles.vel_y[index] = random_f32_range(
        ps, -FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    ps.high_particles.vel_z[index] = random_f32_range(
        ps, FLICKER_UP_SPEED_MIN, FLICKER_UP_SPEED_MAX)

    ps.high_particles.color[index] = color
    ps.high_particles.size[index] = 1.0
    ps.high_particles.ember_size_start[index] = 0.0
    ps.high_particles.ember_size_end[index] = 0.0
    ps.high_particles.ember_white_at_birth[index] = 0.0
    ps.high_particles.age[index] = 0
    ps.high_particles.life[index] =
        random_f32_range(ps, FLICKER_LIFE_MIN, FLICKER_LIFE_MAX)
    ps.high_particles.lit_frames[index] = 0
    ps.high_particles.alive[index] = true

}

//   Spawn one burnout-style ember particle near the provided tool-tip position.
spawn_burnout_ember_particle :: proc(
    ps: ^Particle_System, tip_x, tip_y, tip_z: f32, tip_color: rl.Color) {

    index, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return
    }

    jitter_x := (f32(random_i32_range(ps, -1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(random_i32_range(ps, -1000, 1000)) / 1000.0) * JITTER_PIXELS

    ps.particles.pos_x[index] = tip_x + jitter_x
    ps.particles.pos_y[index] = tip_y + jitter_y
    ps.particles.pos_z[index] = tip_z

    ps.particles.age[index] = 0
    life_scale :=
        f32(random_i32_range(ps, LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    ps.particles.life[index] = BURNOUT_LIFE * life_scale

    ps.particles.size[index] = BURNOUT_SIZE_START
    ps.particles.ember_size_start[index] = BURNOUT_SIZE_START
    ps.particles.ember_size_end[index] = BURNOUT_SIZE_END
    ps.particles.ember_white_at_birth[index] = 1.0
    ps.particles.color[index] = tip_color
    ps.particles.alive[index] = true

    ps.particles.vel_x[index] = 0
    ps.particles.vel_y[index] = 0
    ps.particles.vel_z[index] = 0
    ps.particles.lit_frames[index] = 0

}

//   Clamp one low-layer dust particle's x/y position to dust bounds and apply bounce damping.
clamp_xy_bounds_index :: proc(ps: ^Particle_System, i: int) {
    if ps.low_particles.pos_x[i] < DUST_XY_MIN {
        ps.low_particles.pos_x[i] = DUST_XY_MIN
        ps.low_particles.vel_x[i] = -ps.low_particles.vel_x[i] * 0.45
    } else if ps.low_particles.pos_x[i] > DUST_XY_MAX {
        ps.low_particles.pos_x[i] = DUST_XY_MAX
        ps.low_particles.vel_x[i] = -ps.low_particles.vel_x[i] * 0.45
    }

    if ps.low_particles.pos_y[i] < DUST_XY_MIN {
        ps.low_particles.pos_y[i] = DUST_XY_MIN
        ps.low_particles.vel_y[i] = -ps.low_particles.vel_y[i] * 0.45
    } else if ps.low_particles.pos_y[i] > DUST_XY_MAX {
        ps.low_particles.pos_y[i] = DUST_XY_MAX
        ps.low_particles.vel_y[i] = -ps.low_particles.vel_y[i] * 0.45
    }
}

//   Spawn one low-layer dust particle around an origin with random kick values.
spawn_dust_particle_index :: proc(
    ps: ^Particle_System, i: int, origin: Vector3, col: rl.Color) {
    spawn_dust_particle_index_with_generator(
        ps, i, origin, col, particle_random_generator(ps))
}

// Initialize one low-layer dust slot using an explicitly owned random generator.
spawn_dust_particle_index_with_generator :: proc(
    ps: ^Particle_System, i: int, origin: Vector3, col: rl.Color,
    generator: rand.Generator) {
    ps.low_particles[i].alive = true
    ps.low_particles[i].age = 0
    ps.low_particles[i].life = rand.float32_range(
        DUST_LIFE_MIN, DUST_LIFE_MAX, generator)
    ps.low_particles[i].dust_sprite_index = u8(rand.int32_range(
        0, particlemodel.DUST_ATLAS_VARIANT_COUNT, generator))

    ps.low_particles.pos_x[i] = origin.x + rand.float32_range(-0.0022, 0.0022, generator)
    ps.low_particles.pos_y[i] = origin.y + rand.float32_range(-0.0022, 0.0022, generator)
    ps.low_particles.pos_z[i] = origin.z

    ps.low_particles.vel_x[i] = rand.float32_range(DUST_VX_MIN, DUST_VX_MAX, generator)
    ps.low_particles.vel_y[i] = rand.float32_range(DUST_VY_MIN, DUST_VY_MAX, generator)
    ps.low_particles.vel_z[i] = rand.float32_range(DUST_VZ_MIN, DUST_VZ_MAX, generator)

    ps.low_particles[i].size =
        rand.float32_range(DUST_SIZE_START_MIN, DUST_SIZE_START_MAX, generator)
    ps.low_particles[i].ember_size_start = 0.0
    ps.low_particles[i].ember_size_end = 0.0
    ps.low_particles[i].ember_white_at_birth = 0.0
    ps.low_particles[i].color = col
    ps.low_particles[i].lit_frames = 0
}

// Return one deterministic scenario-request position inside its selected layout.
scenario_dust_origin :: proc(
    request: particlemodel.Scenario_Dust_Emission_Request,
    index: int, generator: rand.Generator) -> Vector3 {
    result := Vector3{request.x, request.y, 0}
    switch request.distribution {
    case .Point:
    case .Disc:
        radial := math.sqrt(rand.float32(generator)) * request.radius
        angle := rand.float32(generator) * f32(2 * math.PI)
        result.x += radial * f32(math.cos(angle))
        result.y += radial * f32(math.sin(angle))
    case .Grid:
        side := max(int(math.ceil(math.sqrt(f32(request.count)))), 1)
        if side > 1 {
            spacing := request.radius * 2 / f32(side - 1)
            result.x += f32(index % side) * spacing - request.radius
            result.y += f32(index / side) * spacing - request.radius
        }
    }
    result.x = clamp(result.x, DUST_XY_MIN, DUST_XY_MAX)
    result.y = clamp(result.y, DUST_XY_MIN, DUST_XY_MAX)
    return result
}

// Emit one deterministic diagnostic request without advancing authored-emission RNG.
emit_scenario_dust :: proc(
    ps: ^Particle_System,
    request: particlemodel.Scenario_Dust_Emission_Request) -> int {
    local_state: rand.Xoshiro256_Random_State
    generator := rand.xoshiro256_random_generator(&local_state)
    rand.reset(request.seed, generator)
    emitted := 0
    for index in 0..<int(request.count) {
        slot, ok := reserve_dead_low_particle_slot(ps)
        if !ok {break}
        origin := scenario_dust_origin(request, index, generator)
        spawn_dust_particle_index_with_generator(ps, slot, origin, rl.WHITE, generator)
        ps^.dust_spawn_sequence += 1
        ps^.dust_slot_spawn_sequences[slot] = ps^.dust_spawn_sequence
        emitted += 1
    }
    return emitted
}

//   Reserve one low-layer slot and initialize a randomized dust particle.
spawn_dust_particle :: proc(ps: ^Particle_System, origin: Vector3, col: rl.Color) {
    index, ok := reserve_dead_low_particle_slot(ps)
    if !ok {
        return
    }

    spawn_dust_particle_index(ps, index, origin, col)
    ps^.dust_spawn_sequence += 1
    ps^.dust_slot_spawn_sequences[index] = ps^.dust_spawn_sequence

}

//   Emit dust samples along a line segment between two points.
emit_line_dust :: proc(ps: ^Particle_System, a, b: Vector3, col: rl.Color) {
    sample_count := max(CLEAR_BURST_LINE_SAMPLES, 2)
    denom := f32(sample_count - 1)
    for s in 0..<sample_count {
        t := f32(s) / denom
        sample := a
        sample.x = a.x + (b.x - a.x) * t
        sample.y = a.y + (b.y - a.y) * t
        sample.z = a.z + (b.z - a.z) * t

        for _ in 0..<CLEAR_BURST_EDGE_REPEATS {
            spawn_dust_particle(ps, sample, col)
        }
    }
}

//   Compute unsigned 3D area for one triangle.
triangle_area_3d :: #force_inline proc(a, b, c: Vector3) -> f32 {
    ab := b - a
    ac := c - a

    cross_x := ab.y * ac.z - ab.z * ac.y
    cross_y := ab.z * ac.x - ab.x * ac.z
    cross_z := ab.x * ac.y - ab.y * ac.x

    cross_len := f32(math.sqrt(cross_x * cross_x + cross_y * cross_y + cross_z * cross_z))
    return cross_len * 0.5
}

//   Sample one random point in a triangle using barycentric folding.
sample_triangle_point :: proc(ps: ^Particle_System, a, b, c: Vector3) -> Vector3 {
    u := random_f32_range(ps, 0.0, 1.0)
    v := random_f32_range(ps, 0.0, 1.0)

    if u + v > 1.0 {
        u = 1.0 - u
        v = 1.0 - v
    }

    w := 1.0 - u - v
    return Vector3{
        a.x * w + b.x * u + c.x * v,
        a.y * w + b.y * u + c.y * v,
        a.z * w + b.z * u + c.z * v,
    }
}

//   Emit dust samples inside a polygon with area-scaled density.
polygon_fill_triangles :: #force_inline proc(
    vertices: ^[12]Vector3,
    vertex_count: int) -> Polygon_Fill_Triangles {

    result := Polygon_Fill_Triangles{count = vertex_count - 2}
    for i in 0..<result.count {
        area := triangle_area_3d(vertices[0], vertices[i + 1], vertices[i + 2])
        result.areas[i] = area
        result.total_area += area
    }
    return result
}

//   Select one triangle index using its area as the sampling weight.
polygon_fill_triangle_index :: #force_inline proc(
    ps: ^Particle_System,
    triangles: Polygon_Fill_Triangles) -> int {

    pick := random_f32_range(ps, 0.0, triangles.total_area)
    accumulated: f32
    for i in 0..<triangles.count {
        accumulated += triangles.areas[i]
        if pick <= accumulated {
            return i
        }
    }
    return triangles.count - 1
}

//   Emit dust samples inside a polygon with area-scaled density.
emit_polygon_fill_dust :: proc(
    ps: ^Particle_System,
    vertices: ^[12]Vector3,
    vertex_count: int,
    col: rl.Color) {
    if vertex_count < 3 {
        return
    }

    triangles := polygon_fill_triangles(vertices, vertex_count)

    if triangles.total_area <= 0 {
        return
    }

    fill_count := int(math.round(
        f64(triangles.total_area * CLEAR_BURST_POLYGON_FILL_DENSITY)))
    fill_count = clamp(
        fill_count,
        CLEAR_BURST_POLYGON_FILL_MIN_SAMPLES,
        CLEAR_BURST_POLYGON_FILL_MAX_SAMPLES)

    for _ in 0..<fill_count {
        tri_index := polygon_fill_triangle_index(ps, triangles)
        sample := sample_triangle_point(
            ps, vertices[0],
            vertices[tri_index + 1],
            vertices[tri_index + 2])
        spawn_dust_particle(ps, sample, col)
    }
}

//   Normalize angle to non-negative range by adding one full turn when needed.
normalize_theta :: proc(theta: f32) -> f32 {
    t := theta
    if t < 0 {
        t += 2.0 * math.PI
    }
    return t
}

//   Compute positive sweep delta between start and end angles.
compute_sweep_delta :: proc(start_theta, end_theta: f32) -> f32 {
    start_n := normalize_theta(start_theta)
    end_n := normalize_theta(end_theta)

    delta := end_n - start_n
    if delta < 0 {
        delta += 2.0 * math.PI
    }
    return delta
}

//   Derive one bounded particle count from the rendered arc length.
circle_dust_sample_count :: proc(start_radius, end_radius, sweep_delta: f32) -> int {
    average_radius := (start_radius + end_radius) * 0.5
    arc_length := average_radius * abs(sweep_delta)
    count := int(math.round(f64(arc_length * CLEAR_BURST_ARC_DENSITY)))
    return clamp(count, CLEAR_BURST_ARC_MIN_SAMPLES, CLEAR_BURST_ARC_MAX_SAMPLES)
}

//   Derive one bounded particle count from the rendered sector area.
filled_circle_dust_sample_count :: proc(
    start_radius, end_radius, sweep_delta: f32) -> int {
    mean_radius_sq := (
        start_radius * start_radius + start_radius * end_radius +
        end_radius * end_radius) / 3.0
    area := 0.5 * abs(sweep_delta) * mean_radius_sq
    count := int(math.round(f64(area * CLEAR_BURST_FILLED_CIRCLE_DENSITY)))
    return clamp(count,
        CLEAR_BURST_FILLED_CIRCLE_MIN_SAMPLES,
        CLEAR_BURST_FILLED_CIRCLE_MAX_SAMPLES)
}

//   Emit dust samples along a circular/arc sweep between start and finish points.
emit_circle_dust :: proc(ps: ^Particle_System, emission: Circle_Dust_Emission) {
    start_vec := emission.start - emission.center
    end_vec := emission.finish - emission.center

    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))
    if start_radius <= 0 && end_radius <= 0 {
        return
    }

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta) + emission.offset

    sample_count := circle_dust_sample_count(
        start_radius, end_radius, sweep_delta)
    denom := f32(sample_count - 1)
    for s in 0..<sample_count {
        t := f32(s) / denom
        theta := start_theta + sweep_delta * t
        radius := math.lerp(start_radius, end_radius, t)

        sample := emission.center
        sample.x += f32(math.cos(theta)) * radius
        sample.y += f32(math.sin(theta)) * radius

        spawn_dust_particle(ps, sample, emission.color)
    }
}

//   Emit uniformly distributed dust throughout one rendered circular sector.
emit_filled_circle_dust :: proc(ps: ^Particle_System, emission: Circle_Dust_Emission) {
    start_vec := emission.start - emission.center
    end_vec := emission.finish - emission.center
    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))
    if start_radius <= 0 && end_radius <= 0 {
        return
    }

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta) + emission.offset
    sample_count := filled_circle_dust_sample_count(
        start_radius, end_radius, sweep_delta)

    for _ in 0..<sample_count {
        t := random_f32_range(ps, 0.0, 1.0)
        theta := start_theta + sweep_delta * t
        outer_radius := math.lerp(start_radius, end_radius, t)
        radius := outer_radius * f32(math.sqrt(random_f32_range(ps, 0.0, 1.0)))

        sample := emission.center
        sample.x += f32(math.cos(theta)) * radius
        sample.y += f32(math.sin(theta)) * radius
        spawn_dust_particle(ps, sample, emission.color)
    }
}

// Queue one ordered tool contact for replay by the particle worker.
can_queue_dust_tool_contacts :: proc(ps: ^Particle_System, count: int) -> bool {
    return ps != nil && count >= 0 &&
        ps^.dust_tool_contact_count + count <= DUST_TOOL_CONTACT_CAP
}

// Queue one ordered tool contact for replay by the particle worker.
queue_dust_tool_contact :: proc(
    ps: ^Particle_System, contact: particlemodel.Dust_Tool_Contact) -> bool {
    if ps == nil || ps^.dust_tool_contact_count >= DUST_TOOL_CONTACT_CAP {
        if ps != nil {
            ps^.dust_tool_contact_overflow_count += 1
        }
        return false
    }
    stored_contact := contact
    stored_contact.max_spawn_sequence = ps^.dust_spawn_sequence
    ps^.dust_tool_contacts[ps^.dust_tool_contact_count] = stored_contact
    ps^.dust_tool_contact_count += 1
    return true
}

// Report whether one adjacent contact makes its predecessor redundant.
dust_tool_contacts_can_coalesce :: proc(
    previous, current: particlemodel.Dust_Tool_Contact) -> bool {
    if previous.source != current.source ||
        previous.max_spawn_sequence != current.max_spawn_sequence {
        return false
    }
    switch current.source {
    case .Compass_Filled_Sweep:
        return previous == current
    case .Point, .Scenario:
        return !previous.has_sweep && !current.has_sweep &&
            previous.endpoint == current.endpoint
    }
    return false
}

// Coalesce adjacent redundant contacts without changing raw queue admission.
coalesce_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps == nil || ps^.dust_tool_contact_count < 2 {return}
    write_count := 1
    for read_index in 1..<ps^.dust_tool_contact_count {
        current := ps^.dust_tool_contacts[read_index]
        previous := &ps^.dust_tool_contacts[write_count - 1]
        if dust_tool_contacts_can_coalesce(previous^, current) {
            ps^.dust_tool_contact_coalesced_count += 1
            continue
        }
        ps^.dust_tool_contacts[write_count] = current
        write_count += 1
    }
    ps^.dust_tool_contact_count = write_count
}

// Return radius-bounded intervals for one compass span in board-space XY.
dust_tool_sweep_interval_count :: proc(first, second: Vector3) -> int {
    delta_x := second.x - first.x
    delta_y := second.y - first.y
    length := math.sqrt(delta_x * delta_x + delta_y * delta_y)
    intervals := int(math.ceil(f64(length / f32(DUST_CONTACT_PUSH_RADIUS))))
    return clamp(intervals, 1, DUST_TOOL_SWEEP_MAX_INTERVALS)
}

// Return intervals covering the largest corresponding filled-leg displacement.
dust_filled_sweep_interval_count :: proc(
    intent: ^particlemodel.Dust_Tool_Contact) -> int {
    first_count := dust_tool_sweep_interval_count(
        intent^.previous_segment_first, intent^.segment_first)
    second_count := dust_tool_sweep_interval_count(
        intent^.previous_segment_second, intent^.segment_second)
    return max(first_count, second_count)
}

// Apply one interpolated leg of a compound filled-compass sweep.
apply_dust_filled_sweep_leg :: proc(
    ps: ^Particle_System, intent: ^particlemodel.Dust_Tool_Contact,
    sweep_t: f32) {
    first := math.lerp(intent^.previous_segment_first, intent^.segment_first, sweep_t)
    second := math.lerp(
        intent^.previous_segment_second, intent^.segment_second, sweep_t)
    interval_count := dust_tool_sweep_interval_count(first, second)
    endpoint_motion := intent^.segment_second - intent^.previous_segment_second
    for sample_index in 0..=interval_count {
        leg_t := f32(sample_index) / f32(interval_count)
        previous := math.lerp(
            intent^.previous_segment_first, intent^.previous_segment_second, leg_t)
        current := math.lerp(intent^.segment_first, intent^.segment_second, leg_t)
        position := math.lerp(first, second, leg_t)
        motion := current - previous
        if motion.x == 0 && motion.y == 0 {motion = endpoint_motion}
        ps^.dust_tool_contact_field_node_visit_count +=
            dust_field_apply_tool_motion(&ps^.dust_field,
                {position.x, position.y}, {motion.x, motion.y})
        ps^.dust_tool_contact_sample_count += 1
    }
}

// Apply one filled-compass contact over its complete ruled sweep area.
apply_dust_filled_sweep_to_field :: proc(
    ps: ^Particle_System, intent: ^particlemodel.Dust_Tool_Contact) {
    interval_count := dust_filled_sweep_interval_count(intent)
    for sweep_index in 0..=interval_count {
        apply_dust_filled_sweep_leg(
            ps, intent, f32(sweep_index) / f32(interval_count))
    }
}

// Apply queued contacts to deposited field momentum in command order.
apply_dust_tool_contacts_to_field :: proc(ps: ^Particle_System) {
    if ps == nil {return}
    ps^.dust_tool_contact_sample_count = 0
    ps^.dust_tool_contact_field_node_visit_count = 0
    if ps^.dust_tool_contact_count == 0 {return}
    coalesce_dust_tool_contacts(ps)
    field := &ps^.dust_field
    for contact_index in 0..<ps^.dust_tool_contact_count {
        intent := &ps^.dust_tool_contacts[contact_index]
        if intent^.source == .Compass_Filled_Sweep {
            apply_dust_filled_sweep_to_field(ps, intent)
            continue
        }
        if !intent^.has_sweep {
            ps^.dust_tool_contact_field_node_visit_count +=
                dust_field_apply_tool_point(
                    field, {intent^.endpoint.x, intent^.endpoint.y})
            ps^.dust_tool_contact_sample_count += 1
            continue
        }
        interval_count := dust_tool_sweep_interval_count(
            intent^.segment_first, intent^.segment_second)
        inv_intervals := f32(1.0) / f32(interval_count)
        for sample_index in 0..=interval_count {
            interpolation := f32(sample_index) * inv_intervals
            position := Vector2{
                math.lerp(intent^.segment_first.x, intent^.segment_second.x,
                    interpolation),
                math.lerp(intent^.segment_first.y, intent^.segment_second.y,
                    interpolation)}
            ps^.dust_tool_contact_field_node_visit_count +=
                dust_field_apply_tool_point(field, position)
                    ps^.dust_tool_contact_sample_count += 1
        }
    }
    ps^.dust_tool_contact_count = 0
}

// Discard pending tool contacts at a runtime generation boundary.
discard_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps != nil {ps^.dust_tool_contact_count = 0}
}

//   Batch update for mid-layer ember particles.
update_mid_ember_particles :: proc(ps: ^Particle_System, dt: f32) {
    for i in 0..<MAX_PARTICLES {
        if !ps.particles.alive[i] {
            continue
        }

        ps.particles.age[i] += dt
        if ps.particles.age[i] >= ps.particles.life[i] {
            ps.particles.alive[i] = false
            continue
        }

        t := math.clamp(f32(ps.particles.age[i] / ps.particles.life[i]), 0.0, 1.0)
        ps.particles.size[i] = math.lerp(
            ps.particles.ember_size_start[i],
            ps.particles.ember_size_end[i],
            t)
    }
}


//   Scalar update for one high-layer flicker particle (preserves RNG order).
update_high_flicker_particle_index :: proc(ps: ^Particle_System, i: int, dt: f32) {
    if !ps.high_particles.alive[i] {
        return
    }

    ps.high_particles.age[i] += dt
    if ps.high_particles.age[i] >= ps.high_particles.life[i] {
        ps.high_particles.alive[i] = false
        return
    }

    update_particle_flicker_high_index(ps, i)
}

//   Update one high-layer flicker particle position, drift, and lit-frame state.
update_particle_flicker_high_index :: proc(ps: ^Particle_System, i: int) {
    ps.high_particles.vel_x[i] += random_f32_range(
        ps, -FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25
    ps.high_particles.vel_y[i] += random_f32_range(
        ps, -FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25

    if ps.high_particles.lit_frames[i] > 0 {
        ps.high_particles.lit_frames[i] -= 1
    } else {
        if random_f32_range(ps, 0.0, 1.0) < FLICKER_CHANCE_PER_STEP {
            ps.high_particles.lit_frames[i] =
            i16(random_i32_range(ps, FLICKER_LIT_FRAMES_MIN, FLICKER_LIT_FRAMES_MAX))
        }
    }
}

//   Update one low-layer dust particle physics, floor bounce, bounds clamp, and size fade.
update_particle_dust_index :: proc(ps: ^Particle_System, i: int) {
    if !ps.low_particles[i].alive {
        return
    }

    ps.low_particles.vel_z[i] += DUST_GRAVITY

    if ps.low_particles.pos_z[i] > DUST_FLOOR_Z {
        ps.low_particles.vel_x[i] *= DUST_DRAG_XY
        ps.low_particles.vel_y[i] *= DUST_DRAG_XY
    }
    ps.low_particles.vel_z[i] *= DUST_DRAG_Z

    if ps.low_particles.pos_z[i] <= DUST_FLOOR_Z {
        ps.low_particles.pos_z[i] = DUST_FLOOR_Z
        if ps.low_particles.vel_z[i] < 0 {
            impact_speed := -ps.low_particles.vel_z[i]
            if impact_speed <= DUST_FLOOR_REST_SPEED {
                ps.low_particles.vel_z[i] = 0
                ps^.dust_floor_rest_count += 1
            } else {
                ps.low_particles.vel_z[i] = impact_speed * DUST_BOUNCE
            }
        }
    }

    clamp_xy_bounds_index(ps, i)

    t := math.clamp(f32(ps.low_particles[i].age / ps.low_particles[i].life), 0.0, 1.0)
    ps.low_particles[i].size = math.lerp(f32(DUST_SIZE_START_MAX), DUST_SIZE_END, t)
}
