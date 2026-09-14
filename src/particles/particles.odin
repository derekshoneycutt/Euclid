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
import "core:mem"
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

DUST_KICK_FADE_MIN :: 0.03
DUST_KICK_FADE_MAX :: 0.08
DUST_EXISTING_UP_KICK_MIN :: 0.0012
DUST_EXISTING_UP_KICK_MAX :: 0.0148
DUST_EXISTING_XY_KICK :: 0.0011

DUST_COLLISION_MIN_SEPARATION :: particlemodel.DUST_COLLISION_MIN_SEPARATION
DUST_COLLISION_RESTITUTION :: 0.42
DUST_COLLISION_REST_SPEED :: 0.0005
DUST_COLLISION_POSITION_SLOP :: 0.0001
DUST_COLLISION_ZERO_DISTANCE_SQ :: 1e-12
DUST_COLLISION_NORMAL_JITTER_RADIANS :: 0.18
DUST_FLOOR_REST_SPEED :: 0.006

PARTICLE_RANDOM_SEED :: u64(0x9e3779b97f4a7c15)

DUST_GRID_CELL_SIZE :: particlemodel.DUST_GRID_CELL_SIZE
DUST_GRID_DIM :: particlemodel.DUST_GRID_DIM
DUST_GRID_DIM_SQUARED :: particlemodel.DUST_GRID_DIM_SQUARED
DUST_COLLISION_CELL_SAMPLE_CAP :: particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP
DUST_COLLISION_GRID_CELL_SIZE :: particlemodel.DUST_COLLISION_GRID_CELL_SIZE
DUST_COLLISION_GRID_DIM :: particlemodel.DUST_COLLISION_GRID_DIM
DUST_COLLISION_GRID_CELL_COUNT :: particlemodel.DUST_COLLISION_GRID_CELL_COUNT
DUST_COLLISION_PAIR_CAP :: particlemodel.DUST_COLLISION_PAIR_CAP
DUST_COLLISION_REFINED_CHILD_COUNT :: 4
DUST_COLLISION_REFINED_CHILD_QUOTA ::
    DUST_COLLISION_CELL_SAMPLE_CAP / DUST_COLLISION_REFINED_CHILD_COUNT
DUST_TOOL_CONTACT_CAP :: particlemodel.DUST_TOOL_CONTACT_CAP
DUST_CONTACT_CANDIDATE_WORD_COUNT :: particlemodel.DUST_CONTACT_CANDIDATE_WORD_COUNT
DUST_RELAXATION_LEAVES_PER_PARENT ::
    particlemodel.DUST_RELAXATION_LEAVES_PER_PARENT
DUST_RELAXATION_LEAF_COUNT :: particlemodel.DUST_RELAXATION_LEAF_COUNT

DUST_COLLISION_GRID_NEIGHBORS :: [5][2]int{{0,0},{1,0},{-1,1},{0,1},{1,1}}

DUST_RELAXATION_SPLIT_2_ENTER :: 24
DUST_RELAXATION_SPLIT_2_EXIT :: 16
DUST_RELAXATION_SPLIT_4_ENTER :: 96
DUST_RELAXATION_SPLIT_4_EXIT :: 72
DUST_RELAXATION_MIN_PARTICLES :: 4
DUST_RELAXATION_RESIDUAL_RETAIN :: 0.96
DUST_ACTIVITY_GRACE_FRAMES :: u8(8)
DUST_SLEEP_MEAN_SPEED_SQ :: 1e-8
DUST_SLEEP_RESIDUAL_ENERGY :: 1e-8
DUST_SLEEP_MAX_COLLISION_IMPULSE :: 0.00025
DUST_SLEEP_MAX_POSITION_CORRECTION :: 0.00005
DUST_SLEEP_QUIET_FRAMES :: u16(45)
DUST_WAKE_NEIGHBOR_SPEED :: 0.003

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

Dust_Contact_Push :: struct {
    x, y, radius, radius_sq: f32,
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

Dust_Collision_Grid :: struct {
    cell_y, cell_x, cell_index, cell_count: int,
    radius_sq: f32,
}

Dust_Pair_Response :: struct {
    ia, ib: int,
    nx, ny, penetration: f32,
}

// Hold one bounded spatially balanced sample for an overloaded collision cell.
Dust_Refined_Collision_Samples :: struct {
    indices: [DUST_COLLISION_CELL_SAMPLE_CAP]i32,
    child_counts: [DUST_COLLISION_REFINED_CHILD_COUNT]i32,
    count: int,
}

// Wake one low-layer particle before an authored or collision impulse.
wake_dust_particle :: #force_inline proc(ps: ^Particle_System, i: int) {
    if ps^.dust_sleeping[i] {
        ps^.dust_sleeping[i] = false
        ps^.dust_sleeping_count -= 1
        ps^.dust_wake_transition_count += 1
    }
    ps^.dust_sleep_quiet_frames[i] = 0
    ps^.dust_activity_frames[i] = DUST_ACTIVITY_GRACE_FRAMES
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

//   Push nearby dust particles away from a 2D contact position.
//
// Parameters:
//   - ps: Particle system containing dust particles.
//   - x: Contact x position.
//   - y: Contact y position.
//
// Returns:
//   - none.
push_dust_away_from_xy_index :: proc(
    ps: ^Particle_System, i: int, contact: Dust_Contact_Push) {
    dx := ps.low_particles.pos_x[i] - contact.x
    dy := ps.low_particles.pos_y[i] - contact.y
    dist_sq := dx * dx + dy * dy
    if dist_sq > contact.radius_sq {
        return
    }
    wake_dust_particle(ps, i)

    dist := f32(math.sqrt(f64(dist_sq)))
    nx, ny: f32
    if dist > f32(0.00001) {
        inv_dist := f32(1.0) / dist
        nx = dx * inv_dist
        ny = dy * inv_dist
    } else {
        theta := random_f32_range(ps, f32(0.0), f32(2.0 * math.PI))
        nx = f32(math.cos(theta))
        ny = f32(math.sin(theta))
    }

    falloff := f32(1.0) - math.clamp(dist / contact.radius, f32(0.0), f32(1.0))
    push := DUST_CONTACT_PUSH_SPEED * falloff

    ps.low_particles.vel_x[i] += nx * push
    ps.low_particles.vel_y[i] += ny * push

    ps.low_particles.pos_x[i] += nx * push
    ps.low_particles.pos_y[i] += ny * push
    clamp_xy_bounds_index(ps, i)
}

//   Push nearby dust particles away from a 2D contact position.
//
// Parameters:
//   - ps: Particle system containing dust particles.
//   - x: Contact x position.
//   - y: Contact y position.
//
// Returns:
//   - none.
push_dust_away_from_xy :: proc (ps: ^Particle_System, x, y: f32) {
    if ps^.use_max_dust_particles < 1 {
        return
    }

    push_radius := f32(DUST_CONTACT_PUSH_RADIUS)
    contact := Dust_Contact_Push{x, y, push_radius, push_radius * push_radius}

    for i in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[i].alive {
            continue
        }
        push_dust_away_from_xy_index(ps, i, contact)
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
    wake_dust_particle(ps, i)
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
    if ps^.dust_tool_contact_count > 0 {
        build_exact_dust_grid(ps)
        replay_dust_tool_contacts(ps)
    }

    integrate_dust_positions(ps)

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

    for i in 0..<ps^.use_max_dust_particles {
        update_particle_dust_index(ps, i)
    }

    build_exact_dust_grid(ps)
    resolve_dust_collisions_on_fine_grid(ps)
    relax_dense_grounded_dust(ps)
    advance_dust_activity_grace(ps)

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

// Integrate only awake low-layer dust positions.
integrate_dust_positions :: proc(ps: ^Particle_System) {
    for i in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[i].alive || ps^.dust_sleeping[i] {
            continue
        }
        ps.low_particles.pos_x[i] += ps.low_particles.vel_x[i]
        ps.low_particles.pos_y[i] += ps.low_particles.vel_y[i]
        ps.low_particles.pos_z[i] += ps.low_particles.vel_z[i]
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

// Clear all persistent adaptive relaxation and sleeping state.
reset_dust_relaxation_state :: proc(ps: ^Particle_System) {
    ps.dust_relaxation_active_leaf_count = 0
    ps.dust_relaxation_dense_leaf_count = 0
    ps.dust_relaxation_energy_removed = 0
    ps.dust_sleeping_count = 0
    ps.dust_sleep_transition_count = 0
    ps.dust_wake_transition_count = 0
    ps.dust_sleeping_pair_skip_count = 0
    ps.dust_relaxation_frame = 0
    mem.set(&ps^.dust_relaxation_parent_counts[0], 0,
        size_of(ps^.dust_relaxation_parent_counts))
    mem.set(&ps^.dust_relaxation_parent_levels[0], 0,
        size_of(ps^.dust_relaxation_parent_levels))
    mem.set(&ps^.dust_relaxation_leaf_counts[0], 0,
        size_of(ps^.dust_relaxation_leaf_counts))
    mem.set(&ps^.dust_relaxation_leaf_momentum_x[0], 0,
        size_of(ps^.dust_relaxation_leaf_momentum_x))
    mem.set(&ps^.dust_relaxation_leaf_momentum_y[0], 0,
        size_of(ps^.dust_relaxation_leaf_momentum_y))
    mem.set(&ps^.dust_relaxation_leaf_residual_energy[0], 0,
        size_of(ps^.dust_relaxation_leaf_residual_energy))
    mem.set(&ps^.dust_relaxation_leaf_quiet_frames[0], 0,
        size_of(ps^.dust_relaxation_leaf_quiet_frames))
    mem.set(&ps^.dust_relaxation_leaf_last_seen[0], 0,
        size_of(ps^.dust_relaxation_leaf_last_seen))
}

//   Reset particle-system runtime counters and mark all particle slots as dead.
reset_particles :: proc(ps: ^Particle_System) {
    ps.next_index = 0
    ps.spawn_timer = 0
    ps.dust_tool_contact_count = 0
    ps.dust_tool_contact_overflow_count = 0
    ps.dust_active_cell_count = 0
    ps.dust_collision_active_cell_count = 0
    ps.dust_collision_candidate_count = 0
    ps.dust_collision_correction_count = 0
    ps.dust_collision_max_correction = 0
    ps.dust_collision_rest_contact_count = 0
    ps.dust_floor_rest_count = 0
    ps.dust_collision_refined_cell_count = 0
    ps.dust_contact_candidate_count = 0
    ps.dust_spawn_sequence = 0
    reset_dust_relaxation_state(ps)
    for i in 0..<ps^.use_max_dust_particles {
        ps.low_particles[i].alive = false
        ps.low_particles[i].age = 0
        ps.dust_slot_spawn_sequences[i] = 0
        ps.dust_activity_frames[i] = 0
        ps.dust_sleep_quiet_frames[i] = 0
        ps.dust_sleeping[i] = false
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
    if ps^.dust_sleeping[i] {
        ps^.dust_sleeping_count -= 1
    }
    ps^.dust_sleeping[i] = false
    ps^.dust_sleep_quiet_frames[i] = 0
    ps^.dust_activity_frames[i] = DUST_ACTIVITY_GRACE_FRAMES
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

//   Map x/y position into the dust collision grid cell index.
dust_grid_cell_index :: proc(x, y: f32) -> int {
    cx := clamp(int(x / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    cy := clamp(int(y / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    return cy * DUST_GRID_DIM + cx
}

// Build exact contiguous cell membership for every live dust particle.
build_exact_dust_grid :: proc(ps: ^Particle_System) {
    mem.set(&ps^.dust_exact_counts[0], 0, size_of(ps^.dust_exact_counts))
    ps^.dust_active_cell_count = 0
    for particle_index in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[particle_index].alive {
            continue
        }
        cell := dust_grid_cell_index(
            ps.low_particles.pos_x[particle_index],
            ps.low_particles.pos_y[particle_index])
        if ps^.dust_exact_counts[cell] == 0 {
            ps^.dust_active_cells[ps^.dust_active_cell_count] = i32(cell)
            ps^.dust_active_cell_count += 1
        }
        ps^.dust_exact_counts[cell] += 1
    }

    ps^.dust_exact_offsets[0] = 0
    for cell in 0..<DUST_GRID_DIM_SQUARED {
        ps^.dust_exact_offsets[cell + 1] =
            ps^.dust_exact_offsets[cell] + ps^.dust_exact_counts[cell]
        ps^.dust_exact_cursors[cell] = ps^.dust_exact_offsets[cell]
    }
    for particle_index in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[particle_index].alive {
            continue
        }
        cell := dust_grid_cell_index(
            ps.low_particles.pos_x[particle_index],
            ps.low_particles.pos_y[particle_index])
        cursor := &ps^.dust_exact_cursors[cell]
        ps^.dust_exact_indices[cursor^] = i32(particle_index)
        cursor^ += 1
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
    stored_contact.has_sweep = stored_contact.has_sweep && stored_contact.sample_count > 0
    ps^.dust_tool_contacts[ps^.dust_tool_contact_count] = stored_contact
    ps^.dust_tool_contact_count += 1
    return true
}

// Mark exact-grid members whose cells overlap one contact-space rectangle.
mark_dust_contact_candidate_cells :: proc(
    ps: ^Particle_System, min_x, min_y, max_x, max_y: f32) {
    first_x := clamp(int(min_x / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    first_y := clamp(int(min_y / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    last_x := clamp(int(max_x / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    last_y := clamp(int(max_y / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    for cell_y in first_y..=last_y {
        for cell_x in first_x..=last_x {
            cell := cell_y * DUST_GRID_DIM + cell_x
            first := int(ps^.dust_exact_offsets[cell])
            last := int(ps^.dust_exact_offsets[cell + 1])
            for exact_index in first..<last {
                particle_index := int(ps^.dust_exact_indices[exact_index])
                word := particle_index / 64
                bit := u64(particle_index % 64)
                ps^.dust_contact_candidate_bits[word] |= u64(1) << bit
            }
        }
    }
}

// Collect the ordered unique slot union covered by every queued tool contact.
collect_dust_contact_candidates :: proc(ps: ^Particle_System) {
    mem.set(&ps^.dust_contact_candidate_bits[0], 0,
        size_of(ps^.dust_contact_candidate_bits))
    ps^.dust_contact_candidate_count = 0
    radius := f32(DUST_CONTACT_PUSH_RADIUS)
    for contact_index in 0..<ps^.dust_tool_contact_count {
        intent := &ps^.dust_tool_contacts[contact_index]
        mark_dust_contact_candidate_cells(ps,
            intent^.endpoint.x - radius, intent^.endpoint.y - radius,
            intent^.endpoint.x + radius, intent^.endpoint.y + radius)
        if intent^.has_sweep {
            mark_dust_contact_candidate_cells(ps,
                min(intent^.segment_first.x, intent^.segment_second.x) - radius,
                min(intent^.segment_first.y, intent^.segment_second.y) - radius,
                max(intent^.segment_first.x, intent^.segment_second.x) + radius,
                max(intent^.segment_first.y, intent^.segment_second.y) + radius)
        }
    }
    word_count := (ps^.use_max_dust_particles + 63) / 64
    for word_index in 0..<word_count {
        word := ps^.dust_contact_candidate_bits[word_index]
        for bit_index in 0..<64 {
            particle_index := word_index * 64 + bit_index
            if particle_index >= ps^.use_max_dust_particles {
                break
            }
            if word & (u64(1) << u64(bit_index)) != 0 {
                ps^.dust_contact_candidates[ps^.dust_contact_candidate_count] =
                    i32(particle_index)
                ps^.dust_contact_candidate_count += 1
            }
        }
    }
}

// Wake sleeping dust in contact-intersected parent cells and one-cell halo.
wake_dust_tool_point_halo :: proc(
    ps: ^Particle_System, x, y, radius: f32, max_spawn_sequence: u64) {
    first_x := clamp(int((x - radius) / DUST_GRID_CELL_SIZE) - 1,
        0, DUST_GRID_DIM - 1)
    first_y := clamp(int((y - radius) / DUST_GRID_CELL_SIZE) - 1,
        0, DUST_GRID_DIM - 1)
    last_x := clamp(int((x + radius) / DUST_GRID_CELL_SIZE) + 1,
        0, DUST_GRID_DIM - 1)
    last_y := clamp(int((y + radius) / DUST_GRID_CELL_SIZE) + 1,
        0, DUST_GRID_DIM - 1)
    for cell_y in first_y..=last_y {
        for cell_x in first_x..=last_x {
            cell := cell_y * DUST_GRID_DIM + cell_x
            first := int(ps^.dust_exact_offsets[cell])
            last := int(ps^.dust_exact_offsets[cell + 1])
            for exact_index in first..<last {
                particle_index := int(ps^.dust_exact_indices[exact_index])
                if ps^.dust_sleeping[particle_index] &&
                    ps^.dust_slot_spawn_sequences[particle_index] <= max_spawn_sequence {
                    wake_dust_particle(ps, particle_index)
                }
            }
        }
    }
}

// Apply one point push to contact candidates in ascending particle-slot order.
replay_dust_point_contact :: proc(
    ps: ^Particle_System, x, y: f32, max_spawn_sequence: u64) {
    radius := f32(DUST_CONTACT_PUSH_RADIUS)
    contact := Dust_Contact_Push{x, y, radius, radius * radius}
    wake_dust_tool_point_halo(ps, x, y, radius, max_spawn_sequence)
    for candidate_index in 0..<ps^.dust_contact_candidate_count {
        particle_index := int(ps^.dust_contact_candidates[candidate_index])
        if ps.low_particles[particle_index].alive &&
            ps^.dust_slot_spawn_sequences[particle_index] <= max_spawn_sequence {
            push_dust_away_from_xy_index(ps, particle_index, contact)
        }
    }
}

// Replay queued endpoint and sampled sweep pushes in original command order.
replay_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps == nil || ps^.dust_tool_contact_count == 0 {
        return
    }
    collect_dust_contact_candidates(ps)
    for contact_index in 0..<ps^.dust_tool_contact_count {
        intent := &ps^.dust_tool_contacts[contact_index]
        replay_dust_point_contact(ps, intent^.endpoint.x, intent^.endpoint.y,
            intent^.max_spawn_sequence)
        if !intent^.has_sweep {
            continue
        }
        sample_count := int(intent^.sample_count)
        inv_samples := f32(1.0) / f32(sample_count)
        for sample_index in 0..<sample_count {
            interpolation := f32(sample_index) * inv_samples
            replay_dust_point_contact(ps,
                math.lerp(intent^.segment_first.x, intent^.segment_second.x,
                    interpolation),
                math.lerp(intent^.segment_first.y, intent^.segment_second.y,
                    interpolation),
                intent^.max_spawn_sequence)
        }
    }
    ps^.dust_tool_contact_count = 0
}

// Replay pending tool contacts before another ordered particle mutation.
flush_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps == nil || ps^.dust_tool_contact_count == 0 {
        return
    }
    build_exact_dust_grid(ps)
    replay_dust_tool_contacts(ps)
}

//   Return a deterministic frame-varying hash for dense collision sampling.
dust_collision_hash :: #force_inline proc(seed: u64) -> u64 {
    hash := seed
    hash = (hash ~ (hash >> 30)) * 0xbf58476d1ce4e5b9
    hash = (hash ~ (hash >> 27)) * 0x94d049bb133111eb
    return hash ~ (hash >> 31)
}

//   Return one stable bounded separation angle for a degenerate particle pair.
dust_pair_separation_angle :: #force_inline proc(ia, ib: int) -> f32 {
    seed := u64(u32(ia)) * 0x9e3779b185ebca87 ~
        u64(u32(ib)) * 0xc2b2ae3d27d4eb4f
    unit := f32(u32(dust_collision_hash(seed) >> 32) & 0x00ffffff) / 16777215.0
    return (unit - 0.5) * 2.0 * math.PI
}

//   Apply the collision impulse when two separated particles are approaching.
apply_dust_pair_impulse :: #force_inline proc(
    ps: ^Particle_System,
    ia, ib: int,
    nx, ny: f32) {

    vn := (ps.low_particles.vel_x[ib] - ps.low_particles.vel_x[ia]) * nx +
        (ps.low_particles.vel_y[ib] - ps.low_particles.vel_y[ia]) * ny
    if vn >= 0 {
        return
    }
    restitution: f32 = DUST_COLLISION_RESTITUTION
    if -vn <= DUST_COLLISION_REST_SPEED {
        restitution = 0
        ps^.dust_collision_rest_contact_count += 1
    }
    impulse := -(1.0 + restitution) * vn * 0.5
    ps^.dust_contact_impulse[ia] = max(ps^.dust_contact_impulse[ia], impulse)
    ps^.dust_contact_impulse[ib] = max(ps^.dust_contact_impulse[ib], impulse)
    ps.low_particles.vel_x[ia] -= impulse * nx
    ps.low_particles.vel_y[ia] -= impulse * ny
    ps.low_particles.vel_x[ib] += impulse * nx
    ps.low_particles.vel_y[ib] += impulse * ny
}

// Wake sleeping dust in the contacted particle's exact-grid parent halo.
wake_dust_collision_halo :: proc(ps: ^Particle_System, particle_index: int) {
    center := dust_grid_cell_index(ps.low_particles.pos_x[particle_index],
        ps.low_particles.pos_y[particle_index])
    center_x := center % DUST_GRID_DIM
    center_y := center / DUST_GRID_DIM
    for cell_y in max(center_y - 1, 0)..=min(center_y + 1, DUST_GRID_DIM - 1) {
        for cell_x in max(center_x - 1, 0)..=min(center_x + 1, DUST_GRID_DIM - 1) {
            cell := cell_y * DUST_GRID_DIM + cell_x
            first := int(ps^.dust_exact_offsets[cell])
            last := int(ps^.dust_exact_offsets[cell + 1])
            for exact_index in first..<last {
                neighbor := int(ps^.dust_exact_indices[exact_index])
                if ps^.dust_sleeping[neighbor] {wake_dust_particle(ps, neighbor)}
            }
        }
    }
}

//   Resolve one dust-particle pair collision with positional and velocity response.
separate_dust_pair :: #force_inline proc(
    ps: ^Particle_System,
    response: Dust_Pair_Response) {

    if response.penetration <= DUST_COLLISION_POSITION_SLOP {
        return
    }
    correction := (response.penetration - DUST_COLLISION_POSITION_SLOP) * 0.5
    ps^.dust_collision_correction_count += 1
    ps^.dust_collision_max_correction = max(
        ps^.dust_collision_max_correction, correction)
    ps^.dust_contact_correction[response.ia] = max(
        ps^.dust_contact_correction[response.ia], correction)
    ps^.dust_contact_correction[response.ib] = max(
        ps^.dust_contact_correction[response.ib], correction)
    ps.low_particles.pos_x[response.ia] -= response.nx * correction
    ps.low_particles.pos_y[response.ia] -= response.ny * correction
    ps.low_particles.pos_x[response.ib] += response.nx * correction
    ps.low_particles.pos_y[response.ib] += response.ny * correction
    clamp_xy_bounds_index(ps, response.ia)
    clamp_xy_bounds_index(ps, response.ib)
}

// Wake one sleeping contact on meaningful impact or penetration.
wake_dust_pair :: proc(
    ps: ^Particle_System, ia, ib: int, penetration: f32) -> bool {

    if ps^.dust_sleeping[ia] && ps^.dust_sleeping[ib] {return false}
    sleeping_a := ps^.dust_sleeping[ia]
    sleeping_b := ps^.dust_sleeping[ib]
    if !sleeping_a && !sleeping_b {return true}
    relative_x := ps.low_particles.vel_x[ib] - ps.low_particles.vel_x[ia]
    relative_y := ps.low_particles.vel_y[ib] - ps.low_particles.vel_y[ia]
    neighbor_speed_sq: f32 = DUST_WAKE_NEIGHBOR_SPEED * DUST_WAKE_NEIGHBOR_SPEED
    energetic := relative_x * relative_x + relative_y * relative_y >= neighbor_speed_sq
    correction := max(penetration - DUST_COLLISION_POSITION_SLOP, 0) * 0.5
    if !energetic && correction <= DUST_SLEEP_MAX_POSITION_CORRECTION {return false}
    if sleeping_a {wake_dust_particle(ps, ia)}
    if sleeping_b {wake_dust_particle(ps, ib)}
    if energetic && sleeping_a {wake_dust_collision_halo(ps, ia)}
    if energetic && sleeping_b {wake_dust_collision_halo(ps, ib)}
    return true
}

//   Resolve one dust-particle pair collision with positional and velocity response.
resolve_dust_pair :: proc(
    ps: ^Particle_System,
    ia, ib: int) {
    dx := ps.low_particles.pos_x[ib] - ps.low_particles.pos_x[ia]
    dy := ps.low_particles.pos_y[ib] - ps.low_particles.pos_y[ia]
    dist_sq := dx * dx + dy * dy
    min_sep_sq: f32 = DUST_COLLISION_MIN_SEPARATION *
        DUST_COLLISION_MIN_SEPARATION
    if dist_sq >= min_sep_sq {
        return
    }

    dist := math.sqrt(dist_sq)
    penetration := DUST_COLLISION_MIN_SEPARATION - dist
    if !wake_dust_pair(ps, ia, ib, penetration) {
        ps^.dust_sleeping_pair_skip_count += 1
        return
    }
    nx, ny: f32
    if dist_sq < DUST_COLLISION_ZERO_DISTANCE_SQ {
        angle := dust_pair_separation_angle(ia, ib)
        nx = f32(math.cos(angle))
        ny = f32(math.sin(angle))
    } else {
        nx = dx / dist
        ny = dy / dist
    }

    separate_dust_pair(ps, {ia, ib, nx, ny, penetration})

    apply_dust_pair_impulse(ps, ia, ib, nx, ny)
}

//   Cache one detected dust collision pair in the static per-frame pair list.
cache_dust_collision_pair :: #force_inline proc(ps: ^Particle_System, ia, ib: int) {
    if ps^.dust_pair_count >= DUST_COLLISION_PAIR_CAP {
        ps^.dust_pair_dropped_count += 1
        return
    }

    ps^.dust_pair_a[ps^.dust_pair_count] = i32(ia)
    ps^.dust_pair_b[ps^.dust_pair_count] = i32(ib)
    ps^.dust_pair_count += 1
}

// Map x/y position into the fine collision-grid cell index.
dust_collision_grid_cell_index :: proc(x, y: f32) -> int {
    cell_x := clamp(int(x / DUST_COLLISION_GRID_CELL_SIZE),
        0, DUST_COLLISION_GRID_DIM - 1)
    cell_y := clamp(int(y / DUST_COLLISION_GRID_CELL_SIZE),
        0, DUST_COLLISION_GRID_DIM - 1)
    return cell_y * DUST_COLLISION_GRID_DIM + cell_x
}

//   Resolve dust collisions for one cell against configured neighbor cells.
resolve_dust_collisions_on_grid :: proc(
    ps: ^Particle_System,
    grid: Dust_Collision_Grid) -> u64 {

    if grid.cell_count == 0 {
        return 0
    }

    candidate_count: u64
    for off in DUST_COLLISION_GRID_NEIGHBORS {
        ncx, ncy := grid.cell_x + off[0], grid.cell_y + off[1]
        if ncx < 0 || ncx >= DUST_COLLISION_GRID_DIM ||
            ncy < 0 || ncy >= DUST_COLLISION_GRID_DIM {
            continue
        }
        cb := ncy * DUST_COLLISION_GRID_DIM + ncx
        nb := int(ps^.dust_counts[cb])
        same_cell := grid.cell_index == cb

        for li in 0..<grid.cell_count {
            ia := int(ps^.dust_buckets[
                ps^.dust_collision_offsets[grid.cell_index] + i32(li)])
            lj_start := li + 1 if same_cell else 0
            for lj in lj_start..<nb {
                ib := int(ps^.dust_buckets[
                    ps^.dust_collision_offsets[cb] + i32(lj)])
                candidate_count += 1
                dx := ps.low_particles.pos_x[ib] - ps.low_particles.pos_x[ia]
                dy := ps.low_particles.pos_y[ib] - ps.low_particles.pos_y[ia]
                dist_sq := dx * dx + dy * dy
                if dist_sq < grid.radius_sq {
                    cache_dust_collision_pair(ps, ia, ib)
                }
            }
        }
    }
    return candidate_count
}

// Count fine-grid occupancy and assign compact sampled-cell ranges.
prepare_dust_collision_grid :: proc(ps: ^Particle_System) {
    for particle_index in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[particle_index].alive {continue}
        cell := dust_collision_grid_cell_index(
            ps.low_particles.pos_x[particle_index],
            ps.low_particles.pos_y[particle_index])
        if ps^.dust_seen_counts[cell] == 0 {
            ps^.dust_collision_active_cells[ps^.dust_collision_active_cell_count] =
                i32(cell)
            ps^.dust_collision_active_cell_count += 1
        }
        ps^.dust_seen_counts[cell] += 1
    }
    ps^.dust_collision_offsets[0] = 0
    for cell in 0..<DUST_COLLISION_GRID_CELL_COUNT {
        count := min(ps^.dust_seen_counts[cell],
            i32(DUST_COLLISION_CELL_SAMPLE_CAP))
        ps^.dust_counts[cell] = count
        ps^.dust_collision_offsets[cell + 1] =
            ps^.dust_collision_offsets[cell] + count
    }
    }

// Fill one awake or sleeping pass of the bounded fine-grid reservoir.
populate_dust_collision_grid_pass :: proc(ps: ^Particle_System, sleeping: bool) {
    for particle_index in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles[particle_index].alive ||
            ps^.dust_sleeping[particle_index] != sleeping {
            continue
        }
        cell := dust_collision_grid_cell_index(
            ps.low_particles.pos_x[particle_index],
            ps.low_particles.pos_y[particle_index])
        seen := ps^.dust_counts[cell] + 1
        ps^.dust_counts[cell] = seen
        slot := seen - 1
        if !sleeping && seen > i32(DUST_COLLISION_CELL_SAMPLE_CAP) {
            seed := u64(u32(cell)) * 0x9e3779b185ebca87 ~
                u64(u32(particle_index)) * 0xc2b2ae3d27d4eb4f ~
                ps^.dust_collision_frame
            slot = i32(dust_collision_hash(seed) % u64(seen))
        }
        if slot < i32(DUST_COLLISION_CELL_SAMPLE_CAP) {
            ps^.dust_buckets[ps^.dust_collision_offsets[cell] + slot] =
                i32(particle_index)
        }
    }
}

// Fill compact fine-grid ranges with awake work before stable sleeping members.
populate_dust_collision_grid :: proc(ps: ^Particle_System) {
    mem.set(&ps^.dust_counts[0], 0, size_of(ps^.dust_counts))
    populate_dust_collision_grid_pass(ps, false)
    populate_dust_collision_grid_pass(ps, true)
    for active_index in 0..<ps^.dust_collision_active_cell_count {
        cell := ps^.dust_collision_active_cells[active_index]
        ps^.dust_counts[cell] = min(
            ps^.dust_counts[cell], i32(DUST_COLLISION_CELL_SAMPLE_CAP))
    }
}

// Map one particle in a fine collision cell to its 2x2 refinement child.
dust_collision_refined_child :: #force_inline proc(
    ps: ^Particle_System, particle_index: int) -> int {
    child_size := f32(DUST_COLLISION_GRID_CELL_SIZE * 0.5)
    child_x := int(ps.low_particles.pos_x[particle_index] / child_size) & 1
    child_y := int(ps.low_particles.pos_y[particle_index] / child_size) & 1
    return child_y * 2 + child_x
}

// Report whether a bounded refined sample already contains one particle slot.
dust_refined_sample_contains :: #force_inline proc(
    samples: ^Dust_Refined_Collision_Samples, particle_index: i32) -> bool {
    for index in 0..<samples.count {
        if samples.indices[index] == particle_index {return true}
    }
    return false
}

// Append exact members up to each 2x2 child's spatial quota.
append_dust_refined_child_quotas :: proc(
    ps: ^Particle_System, fine_cell: int, sleeping: bool,
    samples: ^Dust_Refined_Collision_Samples) {
    fine_x := fine_cell % DUST_COLLISION_GRID_DIM
    fine_y := fine_cell / DUST_COLLISION_GRID_DIM
    parent := (fine_y / 5) * DUST_GRID_DIM + fine_x / 5
    first := int(ps^.dust_exact_offsets[parent])
    last := int(ps^.dust_exact_offsets[parent + 1])
    for exact_index in first..<last {
        particle_index := int(ps^.dust_exact_indices[exact_index])
        if ps^.dust_sleeping[particle_index] != sleeping ||
            dust_collision_grid_cell_index(ps.low_particles.pos_x[particle_index],
                ps.low_particles.pos_y[particle_index]) != fine_cell {
            continue
        }
        child := dust_collision_refined_child(ps, particle_index)
        if samples.child_counts[child] >= DUST_COLLISION_REFINED_CHILD_QUOTA {
            continue
        }
        samples.indices[samples.count] = i32(particle_index)
        samples.child_counts[child] += 1
        samples.count += 1
    }
}

// Fill unused refined capacity from the existing active-first bounded sample.
append_dust_refined_existing_sample :: proc(
    ps: ^Particle_System, first, count: int, awake_only: bool,
    samples: ^Dust_Refined_Collision_Samples) {
    for index in 0..<count {
        particle_index := ps^.dust_buckets[first + index]
        if samples.count >= DUST_COLLISION_CELL_SAMPLE_CAP {return}
        if awake_only && ps^.dust_sleeping[particle_index] {continue}
        if dust_refined_sample_contains(samples, particle_index) {continue}
        samples.indices[samples.count] = particle_index
        samples.count += 1
    }
}

// Rebalance one overloaded fine-cell sample across fixed 2x2 child quotas.
refine_dust_collision_bucket :: proc(ps: ^Particle_System, cell: int) {
    if ps^.dust_seen_counts[cell] <= i32(DUST_COLLISION_CELL_SAMPLE_CAP) {return}
    first := int(ps^.dust_collision_offsets[cell])
    old_count := int(ps^.dust_counts[cell])
    samples: Dust_Refined_Collision_Samples
    append_dust_refined_child_quotas(ps, cell, false, &samples)
    append_dust_refined_existing_sample(ps, first, old_count, true, &samples)
    append_dust_refined_child_quotas(ps, cell, true, &samples)
    append_dust_refined_existing_sample(ps, first, old_count, false, &samples)
    for index in 0..<samples.count {
        ps^.dust_buckets[first + index] = samples.indices[index]
    }
    ps^.dust_counts[cell] = i32(samples.count)
    ps^.dust_collision_refined_cell_count += 1
}

// Reset bounded fine-grid collision storage and per-frame diagnostics.
reset_dust_collision_frame :: proc(ps: ^Particle_System) {
    mem.set(&ps^.dust_counts[0], 0, size_of(ps^.dust_counts))
    mem.set(&ps^.dust_seen_counts[0], 0, size_of(ps^.dust_seen_counts))
    ps^.dust_collision_active_cell_count = 0
    ps^.dust_collision_candidate_count = 0
    ps^.dust_pair_count = 0
    ps^.dust_pair_dropped_count = 0
    ps^.dust_collision_correction_count = 0
    ps^.dust_collision_max_correction = 0
    ps^.dust_collision_rest_contact_count = 0
    mem.set(&ps^.dust_contact_impulse[0], 0, size_of(ps^.dust_contact_impulse))
    mem.set(&ps^.dust_contact_correction[0], 0,
        size_of(ps^.dust_contact_correction))
    ps^.dust_collision_frame += 1
}

// Rebalance every overloaded active collision bucket across spatial quotas.
refine_dust_collision_buckets :: proc(ps: ^Particle_System) {
    ps^.dust_collision_refined_cell_count = 0
    for active_index in 0..<ps^.dust_collision_active_cell_count {
        refine_dust_collision_bucket(
            ps, int(ps^.dust_collision_active_cells[active_index]))
    }
}

// Collect bounded collision pairs from every active fine-grid cell.
collect_dust_collision_pairs :: proc(ps: ^Particle_System, min_sep_sq: f32) {
    for index in 0..<ps^.dust_collision_active_cell_count {
        cell := int(ps^.dust_collision_active_cells[index])
        count := int(ps^.dust_counts[cell])
        cell_y := cell / DUST_COLLISION_GRID_DIM
        cell_x := cell % DUST_COLLISION_GRID_DIM
        ps^.dust_collision_candidate_count += resolve_dust_collisions_on_grid(
            ps, {cell_y, cell_x, cell, count, min_sep_sq})
    }
}

// Apply every collision pair retained by the bounded collection pass.
resolve_cached_dust_collision_pairs :: proc(ps: ^Particle_System) {
    for index in 0..<ps^.dust_pair_count {
        resolve_dust_pair(ps, int(ps^.dust_pair_a[index]),
            int(ps^.dust_pair_b[index]))
    }
}

// Build sampled collision buckets from exact membership and resolve pairs.
resolve_dust_collisions_on_fine_grid :: proc(ps: ^Particle_System) {
    if ps^.use_max_dust_particles < 1 {
        return
    }

    reset_dust_collision_frame(ps)
    prepare_dust_collision_grid(ps)
    populate_dust_collision_grid(ps)
    refine_dust_collision_buckets(ps)
    min_sep_sq: f32 = DUST_COLLISION_MIN_SEPARATION *
        DUST_COLLISION_MIN_SEPARATION
    collect_dust_collision_pairs(ps, min_sep_sq)
    resolve_cached_dust_collision_pairs(ps)
}

// Build current exact membership and resolve pairwise dust collisions.
resolve_dust_collisions :: proc(ps: ^Particle_System) {
    build_exact_dust_grid(ps)
    resolve_dust_collisions_on_fine_grid(ps)
}

// Select the relaxation subdivision level using occupancy hysteresis.
dust_relaxation_level :: #force_inline proc(count: i32, previous: u8) -> u8 {
    switch previous {
    case 0:
        return 1 if count >= DUST_RELAXATION_SPLIT_2_ENTER else 0
    case 1:
        if count >= DUST_RELAXATION_SPLIT_4_ENTER {return 2}
        return 0 if count < DUST_RELAXATION_SPLIT_2_EXIT else 1
    case:
        return 1 if count < DUST_RELAXATION_SPLIT_4_EXIT else 2
    }
}

// Map one grounded particle to a deterministic adaptive relaxation leaf.
dust_relaxation_leaf_index :: #force_inline proc(
    ps: ^Particle_System, particle_index: int) -> int {
    x := ps.low_particles.pos_x[particle_index]
    y := ps.low_particles.pos_y[particle_index]
    parent := dust_grid_cell_index(x, y)
    level := ps^.dust_relaxation_parent_levels[parent]
    divisions := 1 << level
    parent_x := parent % DUST_GRID_DIM
    parent_y := parent / DUST_GRID_DIM
    local_x := clamp(int((x / DUST_GRID_CELL_SIZE - f32(parent_x)) *
        f32(divisions)), 0, divisions - 1)
    local_y := clamp(int((y / DUST_GRID_CELL_SIZE - f32(parent_y)) *
        f32(divisions)), 0, divisions - 1)
    return parent * DUST_RELAXATION_LEAVES_PER_PARENT + local_y * 4 + local_x
}

// Clear bounded adaptive relaxation accumulators for a new frame.
reset_dust_relaxation_accumulators :: proc(ps: ^Particle_System) {
    mem.set(&ps^.dust_relaxation_parent_counts[0], 0,
        size_of(ps^.dust_relaxation_parent_counts))
    mem.set(&ps^.dust_relaxation_leaf_counts[0], 0,
        size_of(ps^.dust_relaxation_leaf_counts))
    mem.set(&ps^.dust_relaxation_leaf_momentum_x[0], 0,
        size_of(ps^.dust_relaxation_leaf_momentum_x))
    mem.set(&ps^.dust_relaxation_leaf_momentum_y[0], 0,
        size_of(ps^.dust_relaxation_leaf_momentum_y))
    mem.set(&ps^.dust_relaxation_leaf_residual_energy[0], 0,
        size_of(ps^.dust_relaxation_leaf_residual_energy))
    mem.set(&ps^.dust_relaxation_leaf_max_impulse[0], 0,
        size_of(ps^.dust_relaxation_leaf_max_impulse))
    mem.set(&ps^.dust_relaxation_leaf_max_correction[0], 0,
        size_of(ps^.dust_relaxation_leaf_max_correction))
    ps^.dust_relaxation_active_leaf_count = 0
    ps^.dust_relaxation_frame += 1
}

// Apply occupancy hysteresis and invalidate leaves whose subdivision changed.
update_dust_relaxation_levels :: proc(ps: ^Particle_System) {
    for parent in 0..<DUST_GRID_DIM_SQUARED {
        old_level := ps^.dust_relaxation_parent_levels[parent]
        new_level := dust_relaxation_level(
            ps^.dust_relaxation_parent_counts[parent], old_level)
        ps^.dust_relaxation_parent_levels[parent] = new_level
        if new_level != old_level {
            first_leaf := parent * DUST_RELAXATION_LEAVES_PER_PARENT
            for local in 0..<DUST_RELAXATION_LEAVES_PER_PARENT {
                ps^.dust_relaxation_leaf_quiet_frames[first_leaf + local] = 0
            }
        }
    }
}

// Build adaptive grounded-cell occupancy in fixed storage.
prepare_dust_relaxation :: proc(ps: ^Particle_System) {
    reset_dust_relaxation_accumulators(ps)
    for i in 0..<ps^.use_max_dust_particles {
        if ps.low_particles[i].alive && ps.low_particles.pos_z[i] <= DUST_FLOOR_Z &&
            ps^.dust_activity_frames[i] == 0 {
            parent := dust_grid_cell_index(
                ps.low_particles.pos_x[i], ps.low_particles.pos_y[i])
            ps^.dust_relaxation_parent_counts[parent] += 1
        }
    }
    update_dust_relaxation_levels(ps)
}

// Deposit quiet grounded particle momentum into adaptive relaxation leaves.
deposit_dust_relaxation_momentum :: proc(ps: ^Particle_System) {
    for i in 0..<ps^.use_max_dust_particles {
        ps^.dust_relaxation_leaf_indices[i] = -1
        if !ps.low_particles[i].alive || ps.low_particles.pos_z[i] > DUST_FLOOR_Z ||
            ps^.dust_activity_frames[i] > 0 {
            continue
        }
        leaf := dust_relaxation_leaf_index(ps, i)
        ps^.dust_relaxation_leaf_indices[i] = i32(leaf)
        if ps^.dust_relaxation_leaf_counts[leaf] == 0 {
            active := ps^.dust_relaxation_active_leaf_count
            ps^.dust_relaxation_active_leaves[active] = i32(leaf)
            ps^.dust_relaxation_active_leaf_count += 1
            if ps^.dust_relaxation_leaf_last_seen[leaf] + 1 !=
                ps^.dust_relaxation_frame {
                ps^.dust_relaxation_leaf_quiet_frames[leaf] = 0
            }
            ps^.dust_relaxation_leaf_last_seen[leaf] = ps^.dust_relaxation_frame
        }
        ps^.dust_relaxation_leaf_counts[leaf] += 1
        ps^.dust_relaxation_leaf_momentum_x[leaf] += ps.low_particles.vel_x[i]
        ps^.dust_relaxation_leaf_momentum_y[leaf] += ps.low_particles.vel_y[i]
        ps^.dust_relaxation_leaf_max_impulse[leaf] = max(
            ps^.dust_relaxation_leaf_max_impulse[leaf],
            ps^.dust_contact_impulse[i])
        ps^.dust_relaxation_leaf_max_correction[leaf] = max(
            ps^.dust_relaxation_leaf_max_correction[leaf],
            ps^.dust_contact_correction[i])
    }
}

// Damp dense local velocity residuals while preserving each leaf's XY momentum.
apply_dust_relaxation :: proc(ps: ^Particle_System) {
    ps^.dust_relaxation_dense_leaf_count = 0
    ps^.dust_relaxation_energy_removed = 0
    for active in 0..<ps^.dust_relaxation_active_leaf_count {
        leaf := int(ps^.dust_relaxation_active_leaves[active])
        if ps^.dust_relaxation_leaf_counts[leaf] >= DUST_RELAXATION_MIN_PARTICLES {
            ps^.dust_relaxation_dense_leaf_count += 1
        }
    }
    for i in 0..<ps^.use_max_dust_particles {
        leaf := int(ps^.dust_relaxation_leaf_indices[i])
        if leaf < 0 || ps^.dust_relaxation_leaf_counts[leaf] <
            DUST_RELAXATION_MIN_PARTICLES {
            continue
        }
        count := f32(ps^.dust_relaxation_leaf_counts[leaf])
        mean_x := ps^.dust_relaxation_leaf_momentum_x[leaf] / count
        mean_y := ps^.dust_relaxation_leaf_momentum_y[leaf] / count
        residual_x := ps.low_particles.vel_x[i] - mean_x
        residual_y := ps.low_particles.vel_y[i] - mean_y
        old_energy := residual_x * residual_x + residual_y * residual_y
        ps^.dust_relaxation_leaf_residual_energy[leaf] += old_energy
        ps.low_particles.vel_x[i] = mean_x + residual_x *
            DUST_RELAXATION_RESIDUAL_RETAIN
        ps.low_particles.vel_y[i] = mean_y + residual_y *
            DUST_RELAXATION_RESIDUAL_RETAIN
        retain_sq: f32 = DUST_RELAXATION_RESIDUAL_RETAIN *
            DUST_RELAXATION_RESIDUAL_RETAIN
        ps^.dust_relaxation_energy_removed += old_energy * (f32(1.0) - retain_sq)
    }
}

// Report whether one occupied relaxation leaf has negligible unresolved work.
dust_relaxation_leaf_is_quiet :: #force_inline proc(
    ps: ^Particle_System, leaf: int) -> bool {

    count_f := f32(ps^.dust_relaxation_leaf_counts[leaf])
    mean_x := ps^.dust_relaxation_leaf_momentum_x[leaf] / count_f
    mean_y := ps^.dust_relaxation_leaf_momentum_y[leaf] / count_f
    mean_speed_sq := mean_x * mean_x + mean_y * mean_y
    residual := ps^.dust_relaxation_leaf_residual_energy[leaf] / count_f
    return mean_speed_sq <= DUST_SLEEP_MEAN_SPEED_SQ &&
        residual <= DUST_SLEEP_RESIDUAL_ENERGY &&
        ps^.dust_relaxation_leaf_max_impulse[leaf] <=
            DUST_SLEEP_MAX_COLLISION_IMPULSE &&
        ps^.dust_relaxation_leaf_max_correction[leaf] <=
            DUST_SLEEP_MAX_POSITION_CORRECTION
}

// Update quiet counters and sleep eligible grounded particles.
update_dust_sleeping :: proc(ps: ^Particle_System) {
    for active in 0..<ps^.dust_relaxation_active_leaf_count {
        leaf := int(ps^.dust_relaxation_active_leaves[active])
        if dust_relaxation_leaf_is_quiet(ps, leaf) {
            quiet := ps^.dust_relaxation_leaf_quiet_frames[leaf]
            ps^.dust_relaxation_leaf_quiet_frames[leaf] = min(
                quiet + 1, DUST_SLEEP_QUIET_FRAMES)
        } else {
            ps^.dust_relaxation_leaf_quiet_frames[leaf] = 0
        }
    }
    for i in 0..<ps^.use_max_dust_particles {
        leaf := int(ps^.dust_relaxation_leaf_indices[i])
        if ps^.dust_sleeping[i] {
            continue
        }
        if leaf < 0 || !dust_relaxation_leaf_is_quiet(ps, leaf) {
            ps^.dust_sleep_quiet_frames[i] = 0
            continue
        }
        ps^.dust_sleep_quiet_frames[i] = min(
            ps^.dust_sleep_quiet_frames[i] + 1, DUST_SLEEP_QUIET_FRAMES)
        if ps^.dust_sleep_quiet_frames[i] < DUST_SLEEP_QUIET_FRAMES {continue}
        ps^.dust_sleeping[i] = true
        ps^.dust_sleeping_count += 1
        ps^.dust_sleep_transition_count += 1
        ps.low_particles.vel_x[i] = 0
        ps.low_particles.vel_y[i] = 0
        ps.low_particles.vel_z[i] = 0
    }
}

// Apply one deterministic dense-grounded residual damping pass.
relax_dense_grounded_dust :: proc(ps: ^Particle_System) {
    prepare_dust_relaxation(ps)
    deposit_dust_relaxation_momentum(ps)
    apply_dust_relaxation(ps)
    update_dust_sleeping(ps)
}

// Advance bounded post-disturbance grace without consuming random state.
advance_dust_activity_grace :: proc(ps: ^Particle_System) {
    for i in 0..<ps^.use_max_dust_particles {
        if ps^.dust_activity_frames[i] > 0 {
            ps^.dust_activity_frames[i] -= 1
        }
    }
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
    if !ps.low_particles[i].alive || ps^.dust_sleeping[i] {
        return
    }

    ps.low_particles.vel_z[i] += DUST_GRAVITY

    ps.low_particles.vel_x[i] *= DUST_DRAG_XY
    ps.low_particles.vel_y[i] *= DUST_DRAG_XY
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
