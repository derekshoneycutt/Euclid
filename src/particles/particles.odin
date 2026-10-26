package particles

import shapemodel "../shapes/model"
import curve "../shapes/curve"
import particlemodel "model"
import color "../core/color"
import geometry "../core/geometry"

// Simple particle system kinda took off away from me a bit here, but it has a few important
// points to discuss:

// Layers : Low dust, tool trails, and authored formation.

// Particle types :
//
// - Dust particles move around and collide with eachother, giving some Newtonian style
//   physics to them. They can be emitted from shapes, creating an effect of the shapes
//   being deconstructed into dust. Their lifetime is dependent on how many times the dust
//   is kicked up, as opposed to hard time restraints.
// - Trail particles follow the tools on the ground. Pigment drops a short way onto the
//   stroke and fades where it lands; leapers start small and white, hop off the stroke,
//   and cool to the stroke color. Their look is a pure function of age over life.

import "core:math"
import rand "core:math/rand"
import utf8 "core:unicode/utf8"


Vector2 :: geometry.Vector2
Vector3 :: geometry.Vector3
Color :: color.Color_RGBA8
Particle :: particlemodel.Particle
Particle_System :: particlemodel.Particle_System
Formation_Particle :: particlemodel.Formation_Particle
Formation_Particle_Handle :: particlemodel.Formation_Particle_Handle
Formation_Particle_Visual :: particlemodel.Formation_Particle_Visual
Trail_Particle :: particlemodel.Trail_Particle
Trail_Particle_Visual :: particlemodel.Trail_Particle_Visual
Formation_Draw_Order :: particlemodel.Formation_Draw_Order
FORMATION_DEPTH_BUCKETS :: particlemodel.FORMATION_DEPTH_BUCKETS
Formation_State :: particlemodel.Formation_State
Formation_Reveal_Record :: particlemodel.Formation_Reveal_Record
Formation_Target_Kind :: particlemodel.Formation_Target_Kind
Departure_Material_Sample :: particlemodel.Departure_Material_Sample
Polygon_Material_Sample :: particlemodel.Polygon_Material_Sample
MAX_PARTICLES :: particlemodel.MAX_PARTICLES
MAX_FORMATION_PARTICLES :: particlemodel.MAX_FORMATION_PARTICLES
MAX_FORMATION_REVEALS :: particlemodel.MAX_FORMATION_REVEALS
MAX_DEPARTURE_MATERIAL_SAMPLES :: particlemodel.MAX_DEPARTURE_MATERIAL_SAMPLES

SPAWN_INTERVAL :: 0.012 // seconds
// World-space scatter around the nib, a little wider than the stroke; a fraction of
// particles stray further so the edges read irregular rather than traced.
TRAIL_JITTER :: 0.003
TRAIL_STRAY_JITTER :: 0.007
TRAIL_STRAY_FRACTION :: 0.3

// Each spawn tick lays plain pigment, white-hot pigment that cools as it fades, and
// fewer leapers, since each leaper also lights the ground under it.
TRAIL_PIGMENT_PER_SPAWN :: 1
TRAIL_HOT_PIGMENT_PER_SPAWN :: 1
TRAIL_LEAPERS_PER_SPAWN :: 4
TRAIL_PIGMENT_LIFE_MIN :: 0.6
TRAIL_PIGMENT_LIFE_MAX :: 0.9
TRAIL_HOT_PIGMENT_LIFE_MIN :: 0.4
TRAIL_HOT_PIGMENT_LIFE_MAX :: 0.6
// Pigment diameters in pixels at landing, around the stroke width; they shrink as they fade.
TRAIL_PIGMENT_SIZE_MIN :: 5.0
TRAIL_PIGMENT_SIZE_MAX :: 7.0
TRAIL_HOT_PIGMENT_SIZE_MIN :: 4.0
TRAIL_HOT_PIGMENT_SIZE_MAX :: 6.0
TRAIL_PIGMENT_DROP_MIN :: 0.003
TRAIL_PIGMENT_DROP_MAX :: 0.008
TRAIL_PIGMENT_DRIFT :: 0.002
// Fraction of a pigment's life spent dropping onto the stroke.
TRAIL_PIGMENT_FALL_END :: 0.2
TRAIL_PIGMENT_END_SCALE :: 0.1

TRAIL_LEAPER_LIFE_MIN :: 0.25
TRAIL_LEAPER_LIFE_MAX :: 0.5
TRAIL_LEAPER_SIZE_MIN :: 2.0
TRAIL_LEAPER_SIZE_MAX :: 3.5
TRAIL_LEAPER_PEAK_SCALE :: 1.2
TRAIL_LEAPER_REACH_MIN :: 0.004
TRAIL_LEAPER_REACH_MAX :: 0.01
TRAIL_LEAPER_HOP_MIN :: 0.003
TRAIL_LEAPER_HOP_MAX :: 0.008
TRAIL_LEAPER_POPPER_FRACTION :: 0.15
TRAIL_LEAPER_POP_MIN :: 0.015
TRAIL_LEAPER_POP_MAX :: 0.03

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
DUST_REGION_FLOOR_Z_EPSILON :: 0.015
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
CLEAR_BURST_LINE_SAMPLES :: 96
CLEAR_BURST_ARC_DENSITY :: 192.0
CLEAR_BURST_ARC_MIN_SAMPLES :: 2
CLEAR_BURST_ARC_MAX_SAMPLES :: 900
CLEAR_BURST_CURVE_DENSITY :: CLEAR_BURST_ARC_DENSITY
CLEAR_BURST_CURVE_MIN_SAMPLES :: CLEAR_BURST_ARC_MIN_SAMPLES
CLEAR_BURST_CURVE_MAX_SAMPLES :: CLEAR_BURST_ARC_MAX_SAMPLES
CLEAR_BURST_FILLED_CIRCLE_DENSITY :: 12000.0
CLEAR_BURST_FILLED_CIRCLE_MIN_SAMPLES :: CLEAR_BURST_POINT_COUNT
CLEAR_BURST_FILLED_CIRCLE_MAX_SAMPLES :: 900
CLEAR_BURST_EDGE_REPEATS :: 1
CLEAR_BURST_POLYGON_FILL_DENSITY :: 900.0
CLEAR_BURST_POLYGON_FILL_MAX_SAMPLES :: 900
FORMATION_REGION_DENSITY :: 65536.0
FORMATION_REGION_MAX_SAMPLES :: 8192
// Every LEAPER_INTERVAL-th sample is a leaper; the rest are pigment.
FORMATION_REGION_LEAPER_INTERVAL :: 6
// Launch leaper diameter as a multiple of its landed pigment diameter.
FORMATION_REGION_LEAPER_PEAK_SCALE :: 1.5
// Leapers are drawn slightly smaller than the pigment they share a sample size with.
FORMATION_LEAPER_SIZE_SCALE :: 0.8
// Most leapers hop low a few times; this hashed fraction pops once, higher.
FORMATION_LEAPER_POPPER_FRACTION :: 0.15
FORMATION_LEAPER_POP_HEIGHT_MIN :: 0.04
FORMATION_LEAPER_POP_HEIGHT_MAX :: 0.07
// Low hoppers stay near their landing spot.
FORMATION_LEAPER_HOP_REACH_SCALE :: 0.5
// Landed material hands off to the crisp fill over this final fraction of the reveal.
FORMATION_REGION_HANDOFF_START :: 0.86
// The fill rises from this fraction so it trails the landing distribution.
FORMATION_REGION_FILL_START :: 0.3
// Label ink spends a smaller budget: particles per square logical pixel of full ink.
FORMATION_LABEL_DENSITY :: 1.2
FORMATION_LABEL_MIN_SAMPLES :: 40
FORMATION_LABEL_MAX_SAMPLES :: 512
// One glyph coverage cell spans about this fraction of the font size per side.
FORMATION_LABEL_CELL_FRACTION :: 0.17
FORMATION_LABEL_LEAPER_INTERVAL :: 14
// Label lifts and lateral reach shrink to this fraction of the region motion.
FORMATION_LABEL_MOTION_SCALE :: 0.4
// Label fragments land at this fraction of the region fragment diameter.
FORMATION_LABEL_SIZE_SCALE :: 0.6
// Crisp label ink rises later than a fill so it trails the smaller landing budget.
FORMATION_LABEL_FILL_START :: 0.45
// Sweep fragments uncovered together are born up to this many seconds apart.
FORMATION_SWEEP_BIRTH_SPREAD :: 0.12
// Region flight fractions become sweep flight seconds at this scale.
FORMATION_SWEEP_FLIGHT_SECONDS :: 1.0
// Landed sweep fragments fade over this many seconds as the crisp sector reaches them.
FORMATION_SWEEP_FADE_SECONDS :: 0.25
// The crisp sector trails the swinging leg by this many seconds.
FORMATION_SWEEP_FILL_LAG :: 0.35
// A sweep reveal outlives its authored swing so the last fragments land and fade.
FORMATION_SWEEP_TAIL :: 0.8

// Scale one target kind's shared role lifecycle to its visual budget.
Formation_Kind_Policy :: struct {
    leaper_interval: int,
    motion_scale: f32,
    size_scale: f32,
    fill_start: f32,
}

// Bound one role's hashed lifecycle ranges in reveal fractions and normalized world units.
Formation_Region_Role_Profile :: struct {
    birth_min, birth_max: f32,
    flight_min, flight_max: f32,
    height_min, height_max: f32,
    reach_min, reach_max: f32,
    size_min, size_max: f32,
}

// Store one sample's resolved role and authored-time lifecycle before slot assignment.
Formation_Region_Lifecycle :: struct {
    role: particlemodel.Formation_Particle_Role,
    hops: u8,
    birth, flight, height, size: f32,
    offset: Vector2,
}

// Store one display-frame's prepared region draw identities and readiness.
Formation_Region_Target_Preparation :: struct {
    draws: [MAX_FORMATION_REVEALS]shapemodel.Shapes_Polygon_Draw,
    draw_ready: [MAX_FORMATION_REVEALS]bool,
}

// Describe one topology replacement without extending authored reveal timing.
Formation_Region_Rebuild_Request :: struct {
    entity: shapemodel.Shape_Entity,
    draw: shapemodel.Shapes_Polygon_Draw,
    signature: u64,
    projected_scale: f32,
}

Particle_Emission :: struct {
    origin: Vector3,
    color: Color,
}

Polygon_Fill_Triangles :: struct {
    areas: [shapemodel.MAX_DRAW_CACHE_POLYGON_TRIANGLES]f32,
    triangle_offsets: [shapemodel.MAX_DRAW_CACHE_POLYGON_TRIANGLES]int,
    count: int,
    total_area: f32,
}

Polygon_Cached_Material :: struct {
    draw: shapemodel.Shapes_Polygon_Draw,
    triangles: Polygon_Fill_Triangles,
    valid: bool,
}

Circle_Dust_Emission :: struct {
    center: Vector3,
    radius: f32,
    start_theta: f32,
    sweep_theta: f32,
    color: Color,
}

// Group one world-backed clear-burst operation and its render color.
Shape_World_Burst_Context :: struct {
    particles: ^Particle_System,
    world: ^shapemodel.Shape_World,
    color: Color,
    projected_scale: f32,
}

// Set bounded density, view scale, and deterministic seed for region sampling.
Polygon_Material_Sampling :: struct {
    projected_scale: f32,
    density: f32,
    minimum_count: int,
    seed: u64,
}

// Hide_Burst_Options selects dust kicking, projected density scale, and tint opacity.
Hide_Burst_Options :: struct {
    kick_dust: bool,
    projected_scale: f32,
    opacity: f32,
}

// Emit plain pigment, white-hot pigment, and leapers at the tool tip on a fixed cadence.
emit_trail_particles :: proc(
    ps: ^Particle_System, dt: f32, emission: Particle_Emission) {
    ps.spawn_timer += dt

    for ps.spawn_timer >= SPAWN_INTERVAL {
        ps.spawn_timer -= SPAWN_INTERVAL

        for _ in 0..<TRAIL_PIGMENT_PER_SPAWN {
            spawn_trail_pigment(ps, emission, false)
        }
        for _ in 0..<TRAIL_HOT_PIGMENT_PER_SPAWN {
            spawn_trail_pigment(ps, emission, true)
        }
        for _ in 0..<TRAIL_LEAPERS_PER_SPAWN {
            spawn_trail_leaper(ps, emission)
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

// Emit one polygon using the current rendered triangulation, never a vertex fan.
emit_shape_world_polygon_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Polygon_Geometry) {
    _ = geometry
    _ = emit_shape_world_cached_polygon_burst(ctx, entity)
}

// Copy one visible polygon draw record matching the current owner incarnation.
shape_world_cached_polygon_draw :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) -> (shapemodel.Shapes_Polygon_Draw, bool) {
    cache := &world^.draw_cache
    for item in cache.items[:cache.item_count] {
        switch typed in item {
        case shapemodel.Shapes_Polygon_Draw:
            if typed.source_index == int(entity.slot) - 1 &&
                typed.source_generation == entity.generation &&
                typed.triangle_count > 0 {
                return typed, true
            }
        case shapemodel.Shapes_Label_Draw,
            shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw,
            shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw,
            shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Trochoid_Tool_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw,
            shapemodel.Shapes_Pen_Draw,
            shapemodel.Shapes_Compass_Draw:
        }
    }
    return {}, false
}

// Emit bounded samples from the exact interior triangles prepared for rendering.
emit_shape_world_cached_polygon_burst :: proc(
    ctx: Shape_World_Burst_Context, entity: shapemodel.Shape_Entity) -> bool {
    samples: [MAX_DEPARTURE_MATERIAL_SAMPLES]Polygon_Material_Sample
    count, prepared := sample_shape_world_polygon_material(
        ctx.particles, ctx.world, entity, {
            projected_scale = ctx.projected_scale,
            density = CLEAR_BURST_POLYGON_FILL_DENSITY,
            seed = shapemodel.shape_entity_pack(entity),
        }, samples[:])
    if !prepared || count <= 0 {
        ctx.particles^.departure_capture_failures += 1
        return false
    }
    emitted := false
    for sample in samples[:count] {
        emitted = emit_departure_material_sample(ctx.particles, sample.position,
            sample.coverage, ctx.color) || emitted
    }
    return emitted
}

// Copy bounded, area-weighted samples from the owner-matched rendered triangles.
sample_shape_world_polygon_material :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    request: Polygon_Material_Sampling,
    output: []Polygon_Material_Sample) -> (int, bool) {
    if ps == nil || world == nil || len(output) == 0 ||
        request.density <= 0 || math.is_nan(request.density) ||
        math.is_inf(request.density) ||
        math.is_nan(request.projected_scale) ||
        math.is_inf(request.projected_scale) {
        return 0, false
    }
    material := shape_world_cached_polygon_material(world, entity)
    if !material.valid {
        return 0, false
    }
    triangles := material.triangles
    scale := clamp(request.projected_scale, 0.25, 4)
    maximum := len(output)
    requested := math.round(f64(triangles.total_area) * f64(scale) *
        f64(scale) * f64(request.density))
    count := 1
    if requested >= f64(maximum) {
        count = maximum
    } else if requested > 1 {
        count = int(requested)
    }
    count = max(count, clamp(request.minimum_count, 1, maximum))
    polygon_material_sample_targets(
        &world^.draw_cache, material, count, request.seed, output)
    return count, true
}

// Copy deterministic stratified samples from cached rendered triangle material.
polygon_material_sample_targets :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache,
    material: Polygon_Cached_Material,
    count: int,
    seed: u64,
    output: []Polygon_Material_Sample) {
    random_state: rand.Xoshiro256_Random_State
    generator := rand.xoshiro256_random_generator(&random_state)
    rand.reset(seed, generator)
    for sample_index in 0..<count {
        target := material.triangles.total_area *
            (f32(sample_index) + rand.float32_range(0, 1, generator)) /
            f32(count)
        triangle_index := polygon_fill_triangle_index_at(material.triangles, target)
        triangle := cache.polygon_triangles[
            material.draw.first_triangle + triangle_index]
        vertices := &cache.polygon_vertices
        barycentric := sample_triangle_barycentric(generator)
        sample := triangle_barycentric_position(
            vertices^[triangle.a], vertices^[triangle.b], vertices^[triangle.c],
            barycentric)
        output[sample_index] = {
            position = sample,
            coverage = 255,
            triangle_offset = i32(
                material.triangles.triangle_offsets[triangle_index]),
            barycentric_u = barycentric.x,
            barycentric_v = barycentric.y,
        }
    }
}

// Prepare bounded region targets and refresh their current world-space attachments.
formation_prepare_region_targets :: proc(
    ps: ^Particle_System, world: ^shapemodel.Shape_World,
    projected_scale: f32) -> int {
    if ps == nil || world == nil {
        return 0
    }
    state := &ps^.formation
    prepared: Formation_Region_Target_Preparation
    for reveal_index in 0..<MAX_FORMATION_REVEALS {
        reveal := &state^.reveals[reveal_index]
        if !reveal^.active || reveal^.kind != .Region {
            continue
        }
        formation_prepare_one_region_target(
            ps, world, reveal_index, projected_scale, &prepared)
    }
    return formation_refresh_region_targets(
        ps, world, prepared.draws[:], prepared.draw_ready[:])
}

// Seed formation fragments over the sector each swinging compass newly uncovered.
// Fragment birth and flight are authored in seconds, then stored as reveal fractions.
formation_prepare_sweep_targets :: proc(
    ps: ^Particle_System, world: ^shapemodel.Shape_World,
    projected_scale: f32) -> int {
    if ps == nil || world == nil {
        return 0
    }
    state := &ps^.formation
    spawned := 0
    for &reveal, reveal_index in state^.reveals {
        if !reveal.active || reveal.kind != .Sweep {
            continue
        }
        sector, found := shape_world_cached_filled_circle_draw(
            world, shapemodel.shape_entity_unpack(reveal.owner_entity))
        if !found {
            continue
        }
        now := state^.accepted_progress
        grown := abs(sector.sweep_theta) - abs(reveal.covered_sweep)
        if grown <= 0 {
            continue
        }
        if now > reveal.last_growth {
            reveal.sweep_speed = grown / f32(now - reveal.last_growth)
        }
        reveal.last_growth = now
        scale := clamp(projected_scale, 0.25, 4)
        wanted := min(int(0.5 * sector.radius * sector.radius *
            abs(sector.sweep_theta) * scale * scale * FORMATION_REGION_DENSITY),
            FORMATION_REGION_MAX_SAMPLES)
        spawned += formation_spawn_sweep_wedge(ps, &reveal, reveal_index, sector, wanted)
        reveal.covered_sweep = sector.sweep_theta
    }
    return spawned
}

// Spawn fragments for one reveal's newly uncovered wedge up to the wanted total.
// Returns the number admitted; spawning stops early when formation storage is full.
formation_spawn_sweep_wedge :: proc(
    ps: ^Particle_System, reveal: ^Formation_Reveal_Record, reveal_index: int,
    sector: shapemodel.Shapes_Filled_Circle_Draw, wanted: int) -> int {
    spawned := 0
    for index in reveal^.material_count..<wanted {
        added := formation_add_sweep_particle(
            ps, reveal, reveal_index, sector, index)
        if !added {
            break
        }
        reveal^.material_count += 1
        spawned += 1
    }
    return spawned
}

// Admit one deterministic particle in a sweep reveal's newly uncovered wedge.
formation_add_sweep_particle :: proc(
    ps: ^Particle_System, reveal: ^Formation_Reveal_Record, reveal_index: int,
    sector: shapemodel.Shapes_Filled_Circle_Draw, index: int) -> bool {
    lifecycle := formation_lifecycle(.Sweep, reveal^.seed, index)
    elapsed := f32((ps^.formation.accepted_progress - reveal^.start_progress) /
        f64(reveal^.duration))
    theta := sector.start_theta + reveal^.covered_sweep + (sector.sweep_theta -
        reveal^.covered_sweep) * formation_particle_unit(reveal^.seed, index, 10)
    reach := sector.radius *
        math.sqrt(formation_particle_unit(reveal^.seed, index, 11))
    _, added := formation_add_particle(ps, {
        target_x = sector.center.x + math.cos(theta) * reach,
        target_y = sector.center.y + math.sin(theta) * reach,
        target_z = sector.center.z,
        offset_x = lifecycle.offset.x,
        offset_y = lifecycle.offset.y,
        height = lifecycle.height,
        birth = elapsed + lifecycle.birth *
            FORMATION_SWEEP_BIRTH_SPREAD / reveal^.duration,
        flight = lifecycle.flight *
            FORMATION_SWEEP_FLIGHT_SECONDS / reveal^.duration,
        size = lifecycle.size,
        triangle_offset = -1,
        role = lifecycle.role,
        hops = lifecycle.hops,
        color = sector.color,
        reveal_slot = i32(reveal_index),
        reveal_generation = reveal^.slot_generation,
    })
    return added
}

// Return the signed crisp sweep one filled sector presents while its reveal forms.
// The crisp sector trails the leg by the fill lag, then catches up once it stops.
formation_sweep_fill :: proc(
    ps: ^Particle_System, owner_entity: u64, sweep_theta: f32) -> f32 {
    if ps == nil {
        return sweep_theta
    }
    state := &ps^.formation
    slot := formation_find_reveal(
        state, .Sweep, owner_entity, state^.animation_generation)
    if slot < 0 {
        return sweep_theta
    }
    reveal := &state^.reveals[slot]
    since := f32(state^.accepted_progress - reveal^.last_growth)
    behind := reveal^.sweep_speed * max(FORMATION_SWEEP_FILL_LAG - since, 0)
    drawn := max(abs(reveal^.covered_sweep) - behind, 0)
    return math.sign(sweep_theta) * min(drawn, abs(sweep_theta))
}

// Find one generation-matched filled-circle draw for its owning shape.
shape_world_cached_filled_circle_draw :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) -> (shapemodel.Shapes_Filled_Circle_Draw, bool) {
    cache := &world^.draw_cache
    for item in cache.items[:cache.item_count] {
        typed, is_sector := item.(shapemodel.Shapes_Filled_Circle_Draw)
        if is_sector && typed.source_index == int(entity.slot) - 1 &&
            typed.source_generation == entity.generation {
            return typed, true
        }
    }
    return {}, false
}

// Prepare one active region's topology and copied target attachments.
formation_prepare_one_region_target :: proc(
    ps: ^Particle_System, world: ^shapemodel.Shape_World, reveal_index: int,
    projected_scale: f32, prepared: ^Formation_Region_Target_Preparation) {
    reveal := &ps^.formation.reveals[reveal_index]
    entity := shapemodel.shape_entity_unpack(reveal^.owner_entity)
    material := shape_world_cached_polygon_material(world, entity)
    if !material.valid {
        return
    }
    prepared^.draws[reveal_index] = material.draw
    prepared^.draw_ready[reveal_index] = true
    if !reveal^.dust_pushed {
        reveal^.dust_pushed = queue_dust_region_push(
            ps, &world^.draw_cache, material.draw)
    }
    signature := polygon_material_topology_signature(
        &world^.draw_cache, material.draw)
    if reveal^.topology_signature != signature {
        formation_rebuild_region_samples(
            ps, world, reveal_index, {
                entity = entity,
                draw = material.draw,
                signature = signature,
                projected_scale = projected_scale,
            })
    }
}

// Replace copied targets after a topology change without restarting authored time.
formation_rebuild_region_samples :: proc(
    ps: ^Particle_System, world: ^shapemodel.Shape_World, reveal_index: int,
    request: Formation_Region_Rebuild_Request) {
    reveal := &ps^.formation.reveals[reveal_index]
    formation_remove_reveal_particles(ps, reveal_index, reveal^.slot_generation)
    reveal^.material_count = 0
    reveal^.topology_signature = 0
    capacity := min(FORMATION_REGION_MAX_SAMPLES,
        MAX_FORMATION_PARTICLES - ps^.formation.particle_count)
    if capacity <= 0 {
        return
    }
    samples: [FORMATION_REGION_MAX_SAMPLES]Polygon_Material_Sample
    count, sampled := sample_shape_world_polygon_material(
        ps, world, request.entity, {
            projected_scale = request.projected_scale,
            density = FORMATION_REGION_DENSITY,
            seed = reveal^.seed,
        }, samples[:capacity])
    if !sampled {
        return
    }
    reveal^.material_count = formation_store_region_samples(
        ps, reveal_index, request.draw, samples[:count])
    reveal^.topology_signature = request.signature
}

// Store sampled geometry attachments as bounded formation particles.
formation_store_region_samples :: proc(
    ps: ^Particle_System, reveal_index: int,
    draw: shapemodel.Shapes_Polygon_Draw,
    samples: []Polygon_Material_Sample) -> int {
    stored_count := 0
    for sample, index in samples {
        if formation_add_region_particle(ps, reveal_index, draw, sample, index) {
            stored_count += 1
        }
    }
    return stored_count
}

// Create one bounded region particle with its target and reveal identity.
formation_add_region_particle :: proc(
    ps: ^Particle_System, reveal_index: int,
    draw: shapemodel.Shapes_Polygon_Draw,
    sample: Polygon_Material_Sample, index: int) -> bool {
    reveal := &ps^.formation.reveals[reveal_index]
    lifecycle := formation_lifecycle(.Region, reveal^.seed, index)
    _, added := formation_add_particle(ps, {
        target_x = sample.position.x,
        target_y = sample.position.y,
        target_z = sample.position.z,
        offset_x = lifecycle.offset.x,
        offset_y = lifecycle.offset.y,
        height = lifecycle.height,
        birth = lifecycle.birth,
        flight = lifecycle.flight,
        size = lifecycle.size,
        barycentric_u = sample.barycentric_u,
        barycentric_v = sample.barycentric_v,
        triangle_offset = sample.triangle_offset,
        role = lifecycle.role,
        hops = lifecycle.hops,
        color = draw.color,
        reveal_slot = i32(reveal_index),
        reveal_generation = reveal^.slot_generation,
    })
    return added
}

// Return one target kind's role cadence, motion and size scale, and crisp fill start.
formation_kind_policy :: proc(
    kind: particlemodel.Formation_Target_Kind) -> Formation_Kind_Policy {
    switch kind {
    case .Label:
        return {
            FORMATION_LABEL_LEAPER_INTERVAL,
            FORMATION_LABEL_MOTION_SCALE, FORMATION_LABEL_SIZE_SCALE,
            FORMATION_LABEL_FILL_START,
        }
    case .Region, .Sweep:
    }
    return {
        FORMATION_REGION_LEAPER_INTERVAL, 1, 1, FORMATION_REGION_FILL_START,
    }
}

// Resolve one sample's role and hashed lifecycle independently of target coordinates.
formation_lifecycle :: proc(
    kind: particlemodel.Formation_Target_Kind,
    seed: u64, index: int) -> Formation_Region_Lifecycle {
    policy := formation_kind_policy(kind)
    role := particlemodel.Formation_Particle_Role.Pigment
    if index % policy.leaper_interval == 0 {
        role = .Leaper
    }
    profile := formation_region_role_profile(role)
    angle := formation_particle_unit(seed, index, 1) * math.TAU
    reach := policy.motion_scale * math.lerp(profile.reach_min, profile.reach_max,
        math.sqrt(formation_particle_unit(seed, index, 2)))
    lifecycle: Formation_Region_Lifecycle = {
        role = role,
        hops = 1,
        birth = math.lerp(profile.birth_min, profile.birth_max,
            formation_particle_unit(seed, index, 3)),
        flight = math.lerp(profile.flight_min, profile.flight_max,
            formation_particle_unit(seed, index, 4)),
        height = policy.motion_scale * math.lerp(profile.height_min,
            profile.height_max, formation_particle_unit(seed, index, 5)),
        size = policy.size_scale * math.lerp(profile.size_min, profile.size_max,
            formation_particle_unit(seed, index, 6)),
        offset = {math.cos(angle) * reach, math.sin(angle) * reach},
    }
    if role == .Leaper {
        formation_leaper_hops(seed, index, policy, &lifecycle)
    }
    return lifecycle
}

// Make one leaper a few low decaying hops, or for a rare few, one taller pop.
formation_leaper_hops :: proc(
    seed: u64, index: int, policy: Formation_Kind_Policy,
    lifecycle: ^Formation_Region_Lifecycle) {
    pick := formation_particle_unit(seed, index, 9)
    if pick < FORMATION_LEAPER_POPPER_FRACTION {
        lifecycle^.height = policy.motion_scale * math.lerp(
            f32(FORMATION_LEAPER_POP_HEIGHT_MIN), FORMATION_LEAPER_POP_HEIGHT_MAX,
            formation_particle_unit(seed, index, 5))
        return
    }
    lifecycle^.hops = pick < (1 + FORMATION_LEAPER_POPPER_FRACTION) / 2 ? 2 : 3
    lifecycle^.offset *= FORMATION_LEAPER_HOP_REACH_SCALE
}

// Return one role's lifecycle ranges; every birth plus flight ends before the reveal.
formation_region_role_profile :: proc(
    role: particlemodel.Formation_Particle_Role) -> Formation_Region_Role_Profile {
    switch role {
    case .Leaper:
        return {0, 0.7, 0.22, 0.28, 0.006, 0.02, 0, 0.03, 1.76, 2.72}
    case .Pigment:
        return {0, 0.62, 0.2, 0.35, 0.06, 0.16, 0, 0.025, 2.2, 3.4}
    }
    return {}
}

// Hash one sample index and channel into a deterministic unit interval value.
formation_particle_unit :: proc(seed: u64, index: int, channel: u64) -> f32 {
    value := seed ~ (u64(index) * 0x9E3779B97F4A7C15) ~
        ((channel + 1) * 0xD1B54A32D192ED03)
    value += 0x9E3779B97F4A7C15
    value = (value ~ (value >> 30)) * 0xBF58476D1CE4E5B9
    value = (value ~ (value >> 27)) * 0x94D049BB133111EB
    value ~= value >> 31
    return f32(value >> 40) / f32(1 << 24)
}

// Recalculate attached region targets from the current prepared geometry.
formation_refresh_region_targets :: proc(
    ps: ^Particle_System, world: ^shapemodel.Shape_World,
    draws: []shapemodel.Shapes_Polygon_Draw, draw_ready: []bool) -> int {
    state := &ps^.formation
    refreshed := 0
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := &state^.particles[index]
        if !particle^.alive {
            continue
        }
        reveal_index := int(particle^.reveal_slot)
        if reveal_index < 0 || reveal_index >= len(draws) ||
            !draw_ready[reveal_index] {
            continue
        }
        draw := draws[reveal_index]
        triangle_offset := int(particle^.triangle_offset)
        if triangle_offset < 0 || triangle_offset >= draw.triangle_count {
            continue
        }
        triangle := world^.draw_cache.polygon_triangles[
            draw.first_triangle + triangle_offset]
        if !polygon_triangle_indices_valid(&world^.draw_cache, triangle) {
            continue
        }
        target := triangle_barycentric_position(
            world^.draw_cache.polygon_vertices[triangle.a],
            world^.draw_cache.polygon_vertices[triangle.b],
            world^.draw_cache.polygon_vertices[triangle.c],
            {particle^.barycentric_u, particle^.barycentric_v})
        particle^.target_x = target.x
        particle^.target_y = target.y
        particle^.target_z = target.z
        refreshed += 1
    }
    return refreshed
}

// Replace one label reveal's copied ink targets without restarting authored time.
// Empty or inkless input records the signature with no material so it is not retried.
formation_store_label_targets :: proc(
    ps: ^Particle_System, reveal_index: int,
    request: particlemodel.Formation_Label_Target_Request,
    ink: []particlemodel.Formation_Label_Ink_Sample) -> int {
    if ps == nil || reveal_index < 0 || reveal_index >= MAX_FORMATION_REVEALS {
        return 0
    }
    reveal := &ps^.formation.reveals[reveal_index]
    if !reveal^.active || reveal^.kind != .Label {
        return 0
    }
    formation_remove_reveal_particles(ps, reveal_index, reveal^.slot_generation)
    reveal^.topology_signature = max(request.signature, 1)
    total := formation_label_ink_weight(ink)
    count := min(formation_label_sample_count(total, request.font_size),
        MAX_FORMATION_PARTICLES - ps^.formation.particle_count)
    stored := 0
    for index in 0..<max(count, 0) {
        target := (u64(index) * 2 + 1) * total / u64(count * 2)
        sample := formation_label_ink_at_weight(ink, target)
        if formation_add_label_particle(ps, reveal_index, request, sample, index) {
            stored += 1
        }
    }
    reveal^.material_count = stored
    return stored
}

// Sum one copied ink distribution's coverage weight.
formation_label_ink_weight :: proc(
    ink: []particlemodel.Formation_Label_Ink_Sample) -> u64 {
    total: u64
    for sample in ink {
        total += u64(sample.coverage)
    }
    return total
}

// Size one label's budget from its full-coverage ink area in logical pixels.
formation_label_sample_count :: proc(total_coverage: u64, font_size: f32) -> int {
    if total_coverage == 0 || !(font_size > 0) {
        return 0
    }
    cell := font_size * FORMATION_LABEL_CELL_FRACTION
    area := f32(total_coverage) / 255 * cell * cell
    return clamp(int(area * FORMATION_LABEL_DENSITY),
        FORMATION_LABEL_MIN_SAMPLES, FORMATION_LABEL_MAX_SAMPLES)
}

// Select one ink centroid at its cumulative coverage weight.
formation_label_ink_at_weight :: proc(
    ink: []particlemodel.Formation_Label_Ink_Sample,
    target: u64) -> particlemodel.Formation_Label_Ink_Sample {
    accumulated: u64
    for sample in ink {
        accumulated += u64(sample.coverage)
        if target < accumulated {
            return sample
        }
    }
    return ink[len(ink) - 1]
}

// Create one label particle jittered inside its glyph coverage cell.
formation_add_label_particle :: proc(
    ps: ^Particle_System, reveal_index: int,
    request: particlemodel.Formation_Label_Target_Request,
    sample: particlemodel.Formation_Label_Ink_Sample, index: int) -> bool {
    reveal := &ps^.formation.reveals[reveal_index]
    lifecycle := formation_lifecycle(.Label, reveal^.seed, index)
    cell := request.font_size * FORMATION_LABEL_CELL_FRACTION
    tint := request.color
    tint.a = u8(f32(tint.a) * (0.55 + 0.45 * f32(sample.coverage) / 255))
    _, added := formation_add_particle(ps, {
        target_x = request.anchor.x,
        target_y = request.anchor.y,
        target_z = request.anchor.z,
        offset_x = lifecycle.offset.x,
        offset_y = lifecycle.offset.y,
        height = lifecycle.height,
        ink_x = sample.offset.x +
            cell * (formation_particle_unit(reveal^.seed, index, 7) - 0.5),
        ink_y = sample.offset.y +
            cell * (formation_particle_unit(reveal^.seed, index, 8) - 0.5),
        birth = lifecycle.birth,
        flight = lifecycle.flight,
        size = lifecycle.size,
        triangle_offset = -1,
        role = lifecycle.role,
        hops = lifecycle.hops,
        color = tint,
        reveal_slot = i32(reveal_index),
        reveal_generation = reveal^.slot_generation,
    })
    return added
}

// Reattach every label particle to its owner's current anchor without retiming it.
formation_refresh_label_targets :: proc(
    ps: ^Particle_System, anchors: []Vector3, anchor_ready: []bool) -> int {
    if ps == nil {
        return 0
    }
    state := &ps^.formation
    refreshed := 0
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := &state^.particles[index]
        reveal_index := int(particle^.reveal_slot)
        if !particle^.alive || reveal_index < 0 || reveal_index >= len(anchors) ||
            reveal_index >= len(anchor_ready) || !anchor_ready[reveal_index] ||
            state^.reveals[reveal_index].kind != .Label {
            continue
        }
        anchor := anchors[reveal_index]
        particle^.target_x = anchor.x
        particle^.target_y = anchor.y
        particle^.target_z = anchor.z
        refreshed += 1
    }
    return refreshed
}

// Remove only particles owned by one reveal-record incarnation.
formation_remove_reveal_particles :: proc(
    ps: ^Particle_System, reveal_index: int, reveal_generation: u64) {
    for index in 0..<MAX_FORMATION_PARTICLES {
        particle := &ps^.formation.particles[index]
        if particle^.alive && int(particle^.reveal_slot) == reveal_index &&
            particle^.reveal_generation == reveal_generation {
            _ = formation_remove_particle(ps, {
                slot = i32(index),
                generation = particle^.slot_generation,
            })
        }
    }
}

// Hash polygon connectivity independently of per-frame vertex positions.
polygon_material_topology_signature :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache,
    draw: shapemodel.Shapes_Polygon_Draw) -> u64 {
    signature := u64(1469598103934665603) + u64(draw.vertex_count)
    for index in 0..<draw.triangle_count {
        triangle := cache^.polygon_triangles[draw.first_triangle + index]
        if !polygon_triangle_indices_valid(cache, triangle) {
            continue
        }
        signature = signature * u64(1099511628211) +
            u64(triangle.a - draw.first_vertex + 1)
        signature = signature * u64(1099511628211) +
            u64(triangle.b - draw.first_vertex + 1)
        signature = signature * u64(1099511628211) +
            u64(triangle.c - draw.first_vertex + 1)
    }
    return max(signature, u64(1))
}

// Validate all three absolute indices in one cached triangle.
polygon_triangle_indices_valid :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache,
    triangle: shapemodel.Shapes_Polygon_Triangle) -> bool {
    return triangle.a >= 0 && triangle.b >= 0 && triangle.c >= 0 &&
        triangle.a < cache^.polygon_vertex_count &&
        triangle.b < cache^.polygon_vertex_count &&
        triangle.c < cache^.polygon_vertex_count
}

// Return current authored crisp opacity for one packed owner of one target kind.
// The crisp object trails the pigment landing distribution and reaches 1 at the end.
formation_reveal_opacity :: proc(
    ps: ^Particle_System, kind: particlemodel.Formation_Target_Kind,
    owner_entity: u64) -> f32 {
    if ps == nil {
        return 1
    }
    state := &ps^.formation
    slot := formation_find_reveal(
        state, kind, owner_entity, state^.animation_generation)
    if slot < 0 {
        return 1
    }
    reveal := &state^.reveals[slot]
    progress := (state^.accepted_progress - reveal^.start_progress) /
        f64(reveal^.duration)
    return math.smoothstep(formation_kind_policy(kind).fill_start, 1,
        f32(math.clamp(progress, 0, 1)))
}

// Return current authored fill opacity for one packed region identity.
formation_region_opacity :: proc(
    ps: ^Particle_System, owner_entity: u64) -> f32 {
    return formation_reveal_opacity(ps, .Region, owner_entity)
}

// Return current authored crisp ink opacity for one packed label identity.
formation_label_opacity :: proc(
    ps: ^Particle_System, owner_entity: u64) -> f32 {
    return formation_reveal_opacity(ps, .Label, owner_entity)
}

// Return the crisp fraction one owner presents, whichever reveal kind it forms under.
// Read this before cancelling so an interrupted departure carries only visible material.
formation_owner_opacity :: proc(
    ps: ^Particle_System, owner_entity: u64) -> f32 {
    return min(formation_label_opacity(ps, owner_entity),
        formation_region_opacity(ps, owner_entity))
}

// Resolve one active formation particle's authored-time position and tint.
// Particles stay hidden before birth; each role then follows its own lifecycle.
formation_particle_visual :: proc(
    ps: ^Particle_System, index: int) -> Formation_Particle_Visual {
    if ps == nil || index < 0 || index >= MAX_FORMATION_PARTICLES {
        return {}
    }
    particle := ps^.formation.particles[index]
    if !particle.alive || particle.reveal_slot < 0 ||
        particle.reveal_slot >= MAX_FORMATION_REVEALS {
        return {}
    }
    reveal := &ps^.formation.reveals[particle.reveal_slot]
    if !reveal^.active ||
        reveal^.slot_generation != particle.reveal_generation {
        return {}
    }
    elapsed := f32((ps^.formation.accepted_progress - reveal^.start_progress) /
        f64(reveal^.duration))
    if elapsed < particle.birth {
        return {}
    }
    local := math.clamp(
        (elapsed - particle.birth) / max(particle.flight, 0.001), 0, 1)
    handoff := formation_region_handoff(elapsed)
    if reveal^.kind == .Sweep {
        landed := particle.birth + particle.flight
        handoff = 1 - math.smoothstep(landed,
            landed + FORMATION_SWEEP_FADE_SECONDS / reveal^.duration, elapsed)
    }
    switch particle.role {
    case .Leaper:
        return formation_leaper_visual(particle, local, handoff)
    case .Pigment:
        return formation_pigment_visual(particle, local, handoff)
    }
    return {}
}

// Return the orthographic view depth for the iso camera looking along (1, 1, -1).
// Larger values are farther from the viewer and draw first.
formation_view_depth :: proc(position: Vector3) -> f32 {
    return position.x + position.y - position.z
}

// Resolve visible formation visuals and stably order them back to front by view depth.
// Returns the visible count; read `draw_order.order[:count]` as indices into visuals.
formation_prepare_draw_order :: proc(ps: ^Particle_System) -> int {
    if ps == nil {
        return 0
    }
    draw := &ps^.formation.draw_order
    count := 0
    nearest, farthest := max(f32), min(f32)
    for index in 0..<MAX_FORMATION_PARTICLES {
        visual := formation_particle_visual(ps, index)
        if !visual.visible {
            continue
        }
        depth := formation_view_depth(visual.position)
        draw^.visuals[count] = visual
        draw^.depths[count] = depth
        nearest = min(nearest, depth)
        farthest = max(farthest, depth)
        count += 1
    }
    formation_bucket_sort_depths(draw, count, nearest, farthest)
    return count
}

// Stably counting-sort compacted depths into far-to-near order through fixed buckets.
formation_bucket_sort_depths :: proc(
    draw: ^Formation_Draw_Order, count: int, nearest, farthest: f32) {
    draw^.buckets = {}
    span := farthest - nearest
    scale := f32(0)
    if span > 0 {
        scale = f32(FORMATION_DEPTH_BUCKETS - 1) / span
    }
    for index in 0..<count {
        draw^.buckets[formation_depth_bucket(
            draw^.depths[index], farthest, scale) + 1] += 1
    }
    for bucket in 1..=FORMATION_DEPTH_BUCKETS {
        draw^.buckets[bucket] += draw^.buckets[bucket - 1]
    }
    for index in 0..<count {
        bucket := formation_depth_bucket(draw^.depths[index], farthest, scale)
        draw^.order[draw^.buckets[bucket]] = u16(index)
        draw^.buckets[bucket] += 1
    }
}

// Map one depth to its far-to-near bucket, clamped against range rounding.
formation_depth_bucket :: proc(depth, farthest, scale: f32) -> int {
    return clamp(int((farthest - depth) * scale), 0, FORMATION_DEPTH_BUCKETS - 1)
}

// Fade and grow pigment in while it accelerates down onto its target.
formation_pigment_visual :: proc(
    particle: Formation_Particle,
    local, handoff: f32) -> Formation_Particle_Visual {
    grow := math.smoothstep(f32(0), 0.7, local)
    return formation_region_visual(particle, {
        particle.offset_x * (1 - local),
        particle.offset_y * (1 - local),
        particle.height * (1 - local * local),
    }, particle.size * (0.3 + 0.7 * grow), 0,
        grow * handoff)
}

// Launch a leaper large and pale near the surface and shrink it over decaying hops,
// cooling to polygon color midway before it settles into landed pigment.
formation_leaper_visual :: proc(
    particle: Formation_Particle,
    local, handoff: f32) -> Formation_Particle_Visual {
    shrink := math.smoothstep(f32(0), 0.5, local)
    swell := math.lerp(f32(FORMATION_REGION_LEAPER_PEAK_SCALE), 1, shrink)
    white := 1 - math.smoothstep(f32(0.4), 0.6, local)
    alpha := math.smoothstep(f32(0), 0.08, local) * handoff
    hops := f32(max(particle.hops, 1))
    hop := min(math.floor(local * hops), hops - 1)
    within := local * hops - hop
    lift := particle.height * (1 - hop / hops) * 4 * within * (1 - within)
    visual := formation_region_visual(particle, {
        particle.offset_x * (1 - local), particle.offset_y * (1 - local), lift,
    }, particle.size * FORMATION_LEAPER_SIZE_SCALE * swell, white, alpha)
    visual.light = white * alpha
    visual.lift = lift
    return visual
}

// Fade landed material over the final handoff interval as the crisp fill completes.
formation_region_handoff :: proc(elapsed: f32) -> f32 {
    return 1 - math.smoothstep(f32(FORMATION_REGION_HANDOFF_START), 1, elapsed)
}

// Compose one visual from its target displacement, pale blend, and opacity scale.
formation_region_visual :: proc(
    particle: Formation_Particle, displacement: Vector3,
    diameter, white, alpha: f32) -> Formation_Particle_Visual {
    tint := particle.color
    tint.r = u8(math.lerp(f32(tint.r), 255, white))
    tint.g = u8(math.lerp(f32(tint.g), 255, white))
    tint.b = u8(math.lerp(f32(tint.b), 255, white))
    tint.a = u8(f32(tint.a) * math.clamp(alpha, 0, 1))
    return {
        position = {
            particle.target_x + displacement.x,
            particle.target_y + displacement.y,
            particle.target_z + displacement.z,
        },
        screen_offset = {particle.ink_x, particle.ink_y},
        color = tint,
        diameter = diameter,
        visible = tint.a > 0,
    }
}

// Validate one generation-matched polygon draw and its cached triangle range.
shape_world_cached_polygon_material :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) -> Polygon_Cached_Material {
    draw, found := shape_world_cached_polygon_draw(world, entity)
    if !found {
        return {}
    }
    cache := &world^.draw_cache
    if draw.first_triangle < 0 ||
        draw.first_triangle > cache.polygon_triangle_count ||
        draw.triangle_count <= 0 ||
        draw.triangle_count >
            cache.polygon_triangle_count-draw.first_triangle {
        return {}
    }
    triangles := polygon_fill_cached_triangles(cache, draw)
    return {draw, triangles, triangles.total_area > 0}
}

// Measure every valid triangle in one prepared polygon draw record.
polygon_fill_cached_triangles :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache,
    draw: shapemodel.Shapes_Polygon_Draw) -> Polygon_Fill_Triangles {
    result: Polygon_Fill_Triangles
    for index in 0..<draw.triangle_count {
        triangle := cache^.polygon_triangles[draw.first_triangle + index]
        if triangle.a < 0 || triangle.b < 0 || triangle.c < 0 ||
            triangle.a >= cache^.polygon_vertex_count ||
            triangle.b >= cache^.polygon_vertex_count ||
            triangle.c >= cache^.polygon_vertex_count {
            continue
        }
        area := triangle_area_3d(
            cache^.polygon_vertices[triangle.a],
            cache^.polygon_vertices[triangle.b],
            cache^.polygon_vertices[triangle.c])
        if area <= 0 || math.is_nan(area) || math.is_inf(area) {
            continue
        }
        result.areas[result.count] = area
        result.triangle_offsets[result.count] = index
        result.total_area += area
        result.count += 1
    }
    if math.is_nan(result.total_area) || math.is_inf(result.total_area) {
        return {}
    }
    return result
}

// Locate one triangle using a stratified cumulative-area coordinate.
polygon_fill_triangle_index_at :: proc(
    triangles: Polygon_Fill_Triangles, target: f32) -> int {
    accumulated: f32
    for index in 0..<triangles.count {
        accumulated += triangles.areas[index]
        if target < accumulated {
            return index
        }
    }
    return triangles.count - 1
}

//   Resolve and emit one world arc using its geometry kind's density model.
emit_shape_world_arc_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    filled: bool) {
    center, center_ok := shape_world_burst_position(ctx.world, entity)
    arc, arc_ok := shapemodel.shape_component_get(
        &ctx.world.arcs, &ctx.world.registry, entity)
    if !center_ok || !arc_ok {
        return
    }
    emission: Circle_Dust_Emission = {
        center, arc.radius, arc.start_theta, arc.sweep_theta, ctx.color}
    if filled {
        emit_filled_circle_dust(ctx.particles, emission)
    } else {
        emit_circle_dust(ctx.particles, emission)
    }
}

// Emit one two-circle region from the exact triangles used for its visible fill.
emit_shape_world_circle_region_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Circle_Region_Geometry) {
    _ = geometry
    _ = emit_shape_world_cached_polygon_burst(ctx, entity)
}

// Return the Euclidean length of one world-space curve segment.
curve_segment_length :: #force_inline proc(first, second: Vector3) -> f32 {
    delta := second - first
    return f32(math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z))
}

// Emit spatially uniform dust across one explicated ordered curve.
emit_curve_polyline_dust :: proc(
    ps: ^Particle_System, vertices: []Vector3, color: Color) {
    total_length: f32
    for index in 1..<len(vertices) {
        total_length += curve_segment_length(vertices[index - 1], vertices[index])
    }
    if total_length <= 0 {
        return
    }
    sample_count := clamp(int(math.round(f64(total_length * CLEAR_BURST_CURVE_DENSITY))),
        CLEAR_BURST_CURVE_MIN_SAMPLES, CLEAR_BURST_CURVE_MAX_SAMPLES)
    segment_index := 1
    consumed: f32
    for sample_index in 0..<sample_count {
        target := total_length * f32(sample_index) / f32(sample_count - 1)
        segment_length := curve_segment_length(
            vertices[segment_index - 1], vertices[segment_index])
        for segment_index < len(vertices) - 1 && consumed + segment_length < target {
            consumed += segment_length
            segment_index += 1
            segment_length = curve_segment_length(
                vertices[segment_index - 1], vertices[segment_index])
        }
        progress: f32
        if segment_length > 0 {
            progress = (target - consumed) / segment_length
        }
        sample := vertices[segment_index - 1] +
            (vertices[segment_index] - vertices[segment_index - 1]) * progress
        spawn_dust_particle(ps, sample, color)
    }
}

// Resolve and emit one canonical trochoid through shared bounded explication.
emit_shape_world_trochoid_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity) {
    center, center_ok := shape_world_burst_position(ctx.world, entity)
    value, value_ok := shapemodel.shape_component_get(
        &ctx.world.trochoids, &ctx.world.registry, entity)
    if !center_ok || !value_ok {
        return
    }
    vertices: [curve.TROCHOID_MAX_VERTICES]Vector3
    result := curve.trochoid_explicate(center, value^, vertices[:])
    if result.status != .Invalid_Input && result.vertex_count > 1 {
        emit_curve_polyline_dust(
            ctx.particles, vertices[:result.vertex_count], ctx.color)
    }
}

// Resolve and emit one canonical literal-line cycloid through bounded explication.
emit_shape_world_cycloid_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Cycloid_Geometry) {
    first, first_ok := shape_world_burst_position(ctx.world, geometry.first)
    second, second_ok := shape_world_burst_position(ctx.world, geometry.second)
    value, value_ok := shapemodel.shape_component_get(
        &ctx.world.cycloids, &ctx.world.registry, entity)
    if !first_ok || !second_ok || !value_ok {
        return
    }
    vertices: [curve.CYCLOID_MAX_VERTICES]Vector3
    result := curve.cycloid_explicate(first, second, value^, vertices[:])
    if result.status != .Invalid_Input && result.vertex_count > 1 {
        emit_curve_polyline_dust(
            ctx.particles, vertices[:result.vertex_count], ctx.color)
    }
}

// Emit one constructed world geometry through its bounded shape explication.
emit_shape_world_constructed_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Geometry) {
    switch geometry.kind {
    case .Arc:
        emit_shape_world_arc_burst(ctx, entity, false)
    case .Filled_Arc:
        emit_shape_world_arc_burst(ctx, entity, true)
    case .Trochoid:
        emit_shape_world_trochoid_burst(ctx, entity)
    case .Cycloid:
        emit_shape_world_cycloid_burst(ctx, entity, geometry.payload.cycloid)
    case .Polygon:
        emit_shape_world_polygon_burst(ctx, entity, geometry.payload.polygon)
    case .Circle_Region:
        emit_shape_world_circle_region_burst(
            ctx, entity, geometry.payload.circle_region)
    case .Point, .Line, .Trochoid_Tool, .Cycloid_Tool,
        .Pen, .Compass:
    }
}

//   Emit one direct world geometry using the legacy sampling behavior.
emit_shape_world_geometry_burst :: proc(
    ctx: Shape_World_Burst_Context,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Geometry) {
    if geometry.kind == .Point {
        position, found := shape_world_burst_position(ctx.world, entity)
        if found {
           emit_point_burst(ctx.particles, position, ctx.color)
        }
        return
    }
    if geometry.kind == .Line {
        first, first_ok := shape_world_burst_position(
            ctx.world, geometry.payload.line.first)
        second, second_ok := shape_world_burst_position(
            ctx.world, geometry.payload.line.second)
        if first_ok && second_ok {
            emit_line_dust(ctx.particles, first, second, ctx.color)
        }
        return
    }
    emit_shape_world_constructed_burst(ctx, entity, geometry)
}

//   Emit visible non-tool geometry after resolving and kicking its clear effect.
emit_shape_world_hide_geometry_burst :: proc(
    ctx: Shape_World_Burst_Context, entity: shapemodel.Shape_Entity,
    kick_dust: bool) -> bool {
    geometry, found := shapemodel.shape_component_get(
        &ctx.world^.geometries, &ctx.world^.registry, entity)
    if !found || geometry^.kind == .Pen || geometry^.kind == .Compass ||
        geometry^.kind == .Trochoid_Tool || geometry^.kind == .Cycloid_Tool {
        return false
    }
    if kick_dust {
        kick_existing_dust(ctx.particles)
    }
    emit_shape_world_geometry_burst(ctx, entity, geometry^)
    return true
}

//   Emit clear dust for one visible entity before its presentation is hidden.
//   Opacity scales tint alpha so an interrupted formation departs only visible ink.
emit_shape_world_hide_burst :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    options: Hide_Burst_Options = {true, 1, 1}) -> bool {
    if ps == nil || world == nil || ps.use_max_dust_particles < 1 ||
        !(options.opacity > 0) ||
        !shapemodel.shape_registry_resolves(&world.registry, entity) {
        return false
    }
    style, found := shapemodel.shape_component_get(
        &world.render_styles, &world.registry, entity)
    if !found || !style^.visible {
        return false
    }
    if shapemodel.shape_component_contains(&world.labels, &world.registry, entity) {
        ps^.departure_capture_failures += 1
        return false
    }
    tint := style^.color
    tint[3] = u8(f32(tint[3]) * min(options.opacity, 1))
    return emit_shape_world_hide_geometry_burst(
        {ps, world, tint, options.projected_scale}, entity, options.kick_dust)
}

// Emit one copied material origin with its sampled coverage.
emit_departure_material_sample :: proc(
    ps: ^Particle_System, position: Vector3, coverage: u8, tint: Color) -> bool {
    if ps == nil || coverage == 0 {
        return false
    }
    color := tint
    color[3] = u8(u16(tint[3]) * u16(coverage) / 255)
    spawn_dust_particle(ps, position, color)
    return true
}

// Emit one copied shaped-label material distribution as ordinary loose dust.
emit_departure_material_burst :: proc(
    ps: ^Particle_System,
    samples: []Departure_Material_Sample,
    tint: Color) -> bool {
    if ps == nil || len(samples) == 0 ||
        len(samples) > MAX_DEPARTURE_MATERIAL_SAMPLES {
        if ps != nil {
           ps^.departure_capture_failures += 1
        }
        return false
    }
    emitted := false
    for sample in samples {
        emitted = emit_departure_material_sample(
            ps, sample.position, sample.coverage, tint) || emitted
    }
    return emitted
}

// Emit clear dust for every visible non-label shape in one canonical world.
emit_shape_world_clear_geometry_burst :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World,
    projected_scale: f32 = 1) -> bool {
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
        ctx: Shape_World_Burst_Context = {
            particles = ps,
            world = world,
            color = style.color,
            projected_scale = projected_scale,
        }
        if shapemodel.shape_component_contains(&world.labels, &world.registry, entity) {
            ps^.departure_capture_failures += 1
            continue
        }
        geometry, found := shapemodel.shape_component_get(
            &world.geometries, &world.registry, entity)
        if found {
            emit_shape_world_geometry_burst(ctx, entity, geometry^)
        }
    }
    return true
}

// Preserve the particle-package clear API while requiring prepared label ink.
emit_shape_world_clear_burst :: proc(
    ps: ^Particle_System,
    world: ^shapemodel.Shape_World) -> bool {
    return emit_shape_world_clear_geometry_burst(ps, world)
}

//   Advance particle simulation for dust and tool-trail layers.
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
    for &push in ps^.dust_region_pushes[:ps^.dust_region_push_count] {
        ps^.dust_tool_contact_field_node_visit_count +=
            dust_field_apply_region_push(&ps^.dust_field, &push)
    }
    ps^.dust_region_push_count = 0
    dust_field_finish_grounded(ps, dt)

    for i in 0..<MAX_PARTICLES {
        if !ps.particles.alive[i] {
            continue
        }
        ps.particles.age[i] += dt
        if ps.particles.age[i] >= ps.particles.life[i] {
            ps.particles.alive[i] = false
        }
    }
}






//   Emit point burst dust for one position.
emit_point_burst :: proc(ps: ^Particle_System, p: Vector3, col: Color) {
    for _ in 0..<CLEAR_BURST_POINT_COUNT {
        spawn_dust_particle(ps, p, col)
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
    formation_reset_generation(ps, ps^.formation.animation_generation)
    for i in 0..<ps^.use_max_dust_particles {
        ps.low_particles[i].alive = false
        ps.low_particles[i].age = 0
        ps.dust_slot_spawn_sequences[i] = 0
    }
    for i in 0..<MAX_PARTICLES {
        ps.particles.alive[i] = false
        ps.particles.age[i] = 0
    }
}

// Start a new animation generation and retire all formation-owned state.
formation_reset_generation :: proc(ps: ^Particle_System, generation: u64) {
    if ps == nil {
        return
    }
    state := &ps^.formation
    for index in 0..<MAX_FORMATION_PARTICLES {
        state^.particles.alive[index] = false
    }
    for index in 0..<MAX_FORMATION_REVEALS {
        state^.reveals[index].active = false
    }
    state^.particle_count = 0
    state^.reveal_count = 0
    state^.next_particle_slot = 0
    state^.next_reveal_slot = 0
    state^.animation_generation = generation
    state^.accepted_progress = 0
}

// Advance formation only to progress accepted with a committed animation batch.
formation_advance_progress :: proc(
    ps: ^Particle_System, generation: u64, progress: f64) -> bool {
    if ps == nil || math.is_nan(progress) || math.is_inf(progress) || progress < 0 {
        return false
    }
    if ps^.formation.animation_generation != generation {
        formation_reset_generation(ps, generation)
    }
    state := &ps^.formation
    if progress < state^.accepted_progress {
        return false
    }
    state^.accepted_progress = progress
    for index in 0..<MAX_FORMATION_REVEALS {
        record := &state^.reveals[index]
        if record^.active &&
            progress >= record^.start_progress + f64(record^.duration) {
            record^.active = false
            state^.reveal_count -= 1
        }
    }
    formation_reclaim_unowned_particles(ps)
    return true
}

// Replace one owner's reveal interval or record its immediate completion.
formation_start_reveal :: proc(
    ps: ^Particle_System, request: particlemodel.Formation_Reveal_Request) -> bool {
    if !formation_reveal_request_valid(ps, request) {
        return false
    }
    state := &ps^.formation
    slot := formation_find_reveal(
        state, request.kind, request.owner_entity, request.animation_generation)
    if request.duration == 0 {
        if slot >= 0 {
            state^.reveals[slot].active = false
            state^.reveal_count -= 1
            formation_reclaim_unowned_particles(ps)
        }
        return true
    }
    if slot < 0 {
        slot = formation_reserve_reveal_slot(state)
        if slot < 0 {
            return false
        }
        state^.reveal_count += 1
    }
    formation_store_reveal(state, slot, request)
    formation_reclaim_unowned_particles(ps)
    return true
}

// Store one validated reveal request into its reserved slot incarnation.
formation_store_reveal :: proc(
    state: ^particlemodel.Formation_State, slot: int,
    request: particlemodel.Formation_Reveal_Request) {
    state^.next_reveal_generation += 1
    if state^.next_reveal_generation == 0 {
        state^.next_reveal_generation = 1
    }
    duration := request.duration
    if request.kind == .Sweep {
        duration += FORMATION_SWEEP_TAIL
    }
    state^.reveals[slot] = {
        kind = request.kind,
        owner_entity = request.owner_entity,
        animation_generation = request.animation_generation,
        slot_generation = state^.next_reveal_generation,
        start_progress = request.progress,
        duration = duration,
        seed = request.seed,
        last_growth = request.progress,
        active = true,
    }
    state^.next_reveal_slot = (slot + 1) % MAX_FORMATION_REVEALS
}

// Validate one reveal request against the current generation and accepted endpoint.
formation_reveal_request_valid :: proc(
    ps: ^Particle_System, request: particlemodel.Formation_Reveal_Request) -> bool {
    return ps != nil && request.owner_entity != 0 &&
        request.animation_generation == ps^.formation.animation_generation &&
        !math.is_nan(request.duration) && !math.is_inf(request.duration) &&
        request.duration >= 0 && !math.is_nan(request.progress) &&
        !math.is_inf(request.progress) &&
        request.progress == ps^.formation.accepted_progress
}

// Cancel every active reveal owned by one packed entity and retire its fragments.
formation_cancel_owner :: proc(
    ps: ^Particle_System, owner_entity, generation: u64) -> bool {
    if ps == nil {
        return false
    }
    state := &ps^.formation
    cancelled := false
    for index in 0..<MAX_FORMATION_REVEALS {
        record := &state^.reveals[index]
        if record^.active && record^.owner_entity == owner_entity &&
            record^.animation_generation == generation {
            record^.active = false
            state^.reveal_count -= 1
            cancelled = true
        }
    }
    if cancelled {
        formation_reclaim_unowned_particles(ps)
    }
    return cancelled
}

// Add one formation particle if a dedicated slot is available and its reveal owner lives.
formation_add_particle :: proc(
    ps: ^Particle_System,
    particle: Formation_Particle) -> (Formation_Particle_Handle, bool) {
    if ps == nil || particle.reveal_slot < 0 ||
        particle.reveal_slot >= MAX_FORMATION_REVEALS {
        return {}, false
    }
    reveal := &ps^.formation.reveals[particle.reveal_slot]
    if !reveal^.active || reveal^.slot_generation != particle.reveal_generation {
        return {}, false
    }
    state := &ps^.formation
    for step in 0..<MAX_FORMATION_PARTICLES {
        index := (state^.next_particle_slot + step) % MAX_FORMATION_PARTICLES
        if state^.particles.alive[index] {
            continue
        }
        state^.next_particle_generation += 1
        if state^.next_particle_generation == 0 {
            state^.next_particle_generation = 1
        }
        stored := particle
        stored.slot_generation = state^.next_particle_generation
        stored.alive = true
        state^.particles[index] = stored
        state^.particle_count += 1
        state^.next_particle_slot = (index + 1) % MAX_FORMATION_PARTICLES
        return {i32(index), stored.slot_generation}, true
    }
    return {}, false
}

// Retire one formation particle only when the handle owns its current slot incarnation.
formation_remove_particle :: proc(
    ps: ^Particle_System, handle: Formation_Particle_Handle) -> bool {
    if ps == nil || handle.slot < 0 || handle.slot >= MAX_FORMATION_PARTICLES {
        return false
    }
    state := &ps^.formation
    index := int(handle.slot)
    if !state^.particles.alive[index] ||
        state^.particles.slot_generation[index] != handle.generation {
        return false
    }
    state^.particles.alive[index] = false
    state^.particle_count -= 1
    return true
}

// Find an active generation-qualified reveal for one semantic owner.
formation_find_reveal :: proc(
    state: ^particlemodel.Formation_State, kind: Formation_Target_Kind,
    owner_entity: u64, generation: u64) -> int {
    for index in 0..<MAX_FORMATION_REVEALS {
        record := &state^.reveals[index]
        if record^.active && record^.kind == kind &&
            record^.owner_entity == owner_entity &&
            record^.animation_generation == generation {
            return index
        }
    }
    return -1
}

// Reserve a free reveal record without overwriting active animation intent.
formation_reserve_reveal_slot :: proc(
    state: ^particlemodel.Formation_State) -> int {
    for step in 0..<MAX_FORMATION_REVEALS {
        index := (state^.next_reveal_slot + step) % MAX_FORMATION_REVEALS
        if !state^.reveals[index].active {
            return index
        }
    }
    return -1
}

// Reclaim fragments whose generation-qualified reveal no longer exists.
formation_reclaim_unowned_particles :: proc(ps: ^Particle_System) {
    state := &ps^.formation
    for index in 0..<MAX_FORMATION_PARTICLES {
        if !state^.particles.alive[index] {
            continue
        }
        reveal_slot := state^.particles.reveal_slot[index]
        if reveal_slot < 0 || reveal_slot >= MAX_FORMATION_REVEALS {
            _ = formation_remove_particle(ps, {
                slot = i32(index),
                generation = state^.particles.slot_generation[index],
            })
            continue
        }
        reveal := &state^.reveals[reveal_slot]
        if !reveal^.active ||
            reveal^.slot_generation != state^.particles.reveal_generation[index] {
            _ = formation_remove_particle(ps, {
                slot = i32(index),
                generation = state^.particles.slot_generation[index],
            })
        }
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

// Spawn one pigment fragment that drops a short way onto the stroke near the tip.
// Hot pigment lands white and cools to the stroke color over a shorter life.
spawn_trail_pigment :: proc(
    ps: ^Particle_System, emission: Particle_Emission, hot: bool) {
    index, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return
    }
    scatter: f32 = TRAIL_JITTER
    if random_f32_range(ps, 0, 1) < TRAIL_STRAY_FRACTION {
        scatter = TRAIL_STRAY_JITTER
    }
    jitter_x := random_f32_range(ps, -scatter, scatter)
    jitter_y := random_f32_range(ps, -scatter, scatter)
    angle := random_f32_range(ps, 0, math.TAU)
    drift := random_f32_range(ps, 0, TRAIL_PIGMENT_DRIFT)
    life, size := trail_pigment_life_size(ps, hot)
    ps.particles[index] = {
        ground_x = emission.origin.x + jitter_x,
        ground_y = emission.origin.y + jitter_y,
        ground_z = emission.origin.z,
        offset_x = math.cos(angle) * drift,
        offset_y = math.sin(angle) * drift,
        height = random_f32_range(ps, TRAIL_PIGMENT_DROP_MIN, TRAIL_PIGMENT_DROP_MAX),
        life = life,
        size = size,
        hot = hot ? 1 : 0,
        role = .Pigment,
        hops = 1,
        color = emission.color,
        alive = true,
    }
}

// Draw one pigment lifetime and size, from the shorter, larger hot ranges if hot.
trail_pigment_life_size :: proc(ps: ^Particle_System, hot: bool) -> (f32, f32) {
    if hot {
        return random_f32_range(
                ps, TRAIL_HOT_PIGMENT_LIFE_MIN, TRAIL_HOT_PIGMENT_LIFE_MAX),
            random_f32_range(
                ps, TRAIL_HOT_PIGMENT_SIZE_MIN, TRAIL_HOT_PIGMENT_SIZE_MAX)
    }
    return random_f32_range(ps, TRAIL_PIGMENT_LIFE_MIN, TRAIL_PIGMENT_LIFE_MAX),
        random_f32_range(ps, TRAIL_PIGMENT_SIZE_MIN, TRAIL_PIGMENT_SIZE_MAX)
}

// Spawn one leaper that makes a few low hops off the stroke, or rarely one tall pop.
spawn_trail_leaper :: proc(ps: ^Particle_System, emission: Particle_Emission) {
    index, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return
    }
    angle := random_f32_range(ps, 0, math.TAU)
    reach := random_f32_range(ps, TRAIL_LEAPER_REACH_MIN, TRAIL_LEAPER_REACH_MAX)
    hops := u8(random_i32_range(ps, 2, 3))
    height := random_f32_range(ps, TRAIL_LEAPER_HOP_MIN, TRAIL_LEAPER_HOP_MAX)
    if random_f32_range(ps, 0, 1) < TRAIL_LEAPER_POPPER_FRACTION {
        hops = 1
        height = random_f32_range(ps, TRAIL_LEAPER_POP_MIN, TRAIL_LEAPER_POP_MAX)
    }
    scatter: f32 = TRAIL_JITTER
    if random_f32_range(ps, 0, 1) < TRAIL_STRAY_FRACTION {
        scatter = TRAIL_STRAY_JITTER
    }
    ps.particles[index] = {
        ground_x = emission.origin.x + random_f32_range(ps, -scatter, scatter),
        ground_y = emission.origin.y + random_f32_range(ps, -scatter, scatter),
        ground_z = emission.origin.z,
        offset_x = math.cos(angle) * reach,
        offset_y = math.sin(angle) * reach,
        height = height,
        life = random_f32_range(ps, TRAIL_LEAPER_LIFE_MIN, TRAIL_LEAPER_LIFE_MAX),
        size = random_f32_range(ps, TRAIL_LEAPER_SIZE_MIN, TRAIL_LEAPER_SIZE_MAX),
        role = .Leaper,
        hops = hops,
        color = emission.color,
        alive = true,
    }
}

// Resolve one live trail particle's position, tint, and diameter from its age.
trail_particle_visual :: proc(
    ps: ^Particle_System, index: int) -> (visual: Trail_Particle_Visual) {
    particle := ps^.particles[index]
    if !particle.alive || particle.life <= 0 {
        return
    }
    local := math.clamp(particle.age / particle.life, 0, 1)
    switch particle.role {
    case .Leaper:
        visual = trail_leaper_visual(particle, local)
    case .Pigment:
        visual = trail_pigment_visual(particle, local)
    }
    return
}

// Drop pigment onto the stroke while it grows and cools, then shrink and fade it there.
trail_pigment_visual :: proc(
    particle: Trail_Particle, local: f32) -> Trail_Particle_Visual {
    fall := math.clamp(local / TRAIL_PIGMENT_FALL_END, 0, 1)
    settle := math.clamp(
        (local - TRAIL_PIGMENT_FALL_END) / (1 - TRAIL_PIGMENT_FALL_END), 0, 1)
    grow := math.smoothstep(f32(0), 1, fall)
    return trail_compose_visual(particle, {
        particle.offset_x * (1 - fall),
        particle.offset_y * (1 - fall),
        particle.height * (1 - fall * fall),
    }, particle.size * (0.4 + 0.6 * grow) *
        math.lerp(f32(1), TRAIL_PIGMENT_END_SCALE, settle),
        particle.hot * (1 - local), grow * (1 - settle))
}

// Hop a leaper off the stroke over decaying arcs, shrinking and cooling to the stroke
// color midway before it lands and fades.
trail_leaper_visual :: proc(
    particle: Trail_Particle, local: f32) -> Trail_Particle_Visual {
    swell := math.lerp(f32(TRAIL_LEAPER_PEAK_SCALE), 1,
        math.smoothstep(f32(0), 0.5, local))
    white := 1 - math.smoothstep(f32(0.4), 0.6, local)
    alpha := math.smoothstep(f32(0), 0.08, local) *
        (1 - math.smoothstep(f32(0.75), 1, local))
    hops := f32(max(particle.hops, 1))
    hop := min(math.floor(local * hops), hops - 1)
    within := local * hops - hop
    lift := particle.height * (1 - hop / hops) * 4 * within * (1 - within)
    visual := trail_compose_visual(particle, {
        particle.offset_x * local, particle.offset_y * local, lift,
    }, particle.size * swell, white, alpha)
    visual.light = white * alpha
    visual.lift = lift
    return visual
}

// Compose one trail visual from its ground displacement, white blend, and opacity.
trail_compose_visual :: proc(
    particle: Trail_Particle, displacement: Vector3,
    diameter, white, alpha: f32) -> Trail_Particle_Visual {
    tint := particle.color
    tint.r = u8(math.lerp(f32(tint.r), 255, white))
    tint.g = u8(math.lerp(f32(tint.g), 255, white))
    tint.b = u8(math.lerp(f32(tint.b), 255, white))
    tint.a = u8(f32(tint.a) * math.clamp(alpha, 0, 1))
    return {
        position = {
            particle.ground_x + displacement.x,
            particle.ground_y + displacement.y,
            particle.ground_z + displacement.z,
        },
        color = tint,
        diameter = diameter,
        visible = tint.a > 0,
    }
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
    ps: ^Particle_System, i: int, origin: Vector3, col: Color) {
    spawn_dust_particle_index_with_generator(
        ps, i, origin, col, particle_random_generator(ps))
}

// Initialize one low-layer dust slot using an explicitly owned random generator.
spawn_dust_particle_index_with_generator :: proc(
    ps: ^Particle_System, i: int, origin: Vector3, col: Color,
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
    ps.low_particles[i].color = col
}

// Return one deterministic scenario-request position inside its selected layout.
scenario_dust_origin :: proc(
    request: particlemodel.Scenario_Dust_Emission_Request,
    index: int, generator: rand.Generator) -> Vector3 {
    result: Vector3 = {request.x, request.y, 0}
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
        if !ok {
           break
        }
        origin := scenario_dust_origin(request, index, generator)
        spawn_dust_particle_index_with_generator(ps, slot, origin, color.WHITE, generator)
        ps^.dust_spawn_sequence += 1
        ps^.dust_slot_spawn_sequences[slot] = ps^.dust_spawn_sequence
        emitted += 1
    }
    return emitted
}

//   Reserve one low-layer slot and initialize a randomized dust particle.
spawn_dust_particle :: proc(ps: ^Particle_System, origin: Vector3, col: Color) {
    index, ok := reserve_dead_low_particle_slot(ps)
    if !ok {
        return
    }

    spawn_dust_particle_index(ps, index, origin, col)
    ps^.dust_spawn_sequence += 1
    ps^.dust_slot_spawn_sequences[index] = ps^.dust_spawn_sequence

}

//   Emit dust samples along a line segment between two points.
emit_line_dust :: proc(ps: ^Particle_System, a, b: Vector3, col: Color) {
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

// Sample folded barycentric coordinates for a uniform triangle point.
sample_triangle_barycentric :: proc(generator: rand.Generator) -> Vector2 {
    u := rand.float32_range(0, 1, generator)
    v := rand.float32_range(0, 1, generator)

    if u + v > 1.0 {
        u = 1.0 - u
        v = 1.0 - v
    }

    return {u, v}
}

// Resolve one triangle point from retained barycentric attachment coordinates.
triangle_barycentric_position :: proc(
    a, b, c: Vector3, coordinates: Vector2) -> Vector3 {
    u, v := coordinates.x, coordinates.y
    w := 1.0 - u - v
    return Vector3{
        a.x * w + b.x * u + c.x * v,
        a.y * w + b.y * u + c.y * v,
        a.z * w + b.z * u + c.z * v,
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
    if emission.radius <= 0 {
        return
    }
    sample_count := circle_dust_sample_count(
        emission.radius, emission.radius, emission.sweep_theta)
    denom := f32(sample_count - 1)
    for s in 0..<sample_count {
        t := f32(s) / denom
        theta := emission.start_theta + emission.sweep_theta * t

        sample := emission.center
        sample.x += f32(math.cos(theta)) * emission.radius
        sample.y += f32(math.sin(theta)) * emission.radius

        spawn_dust_particle(ps, sample, emission.color)
    }
}

//   Emit uniformly distributed dust throughout one rendered circular sector.
emit_filled_circle_dust :: proc(ps: ^Particle_System, emission: Circle_Dust_Emission) {
    if emission.radius <= 0 {
        return
    }
    sample_count := filled_circle_dust_sample_count(
        emission.radius, emission.radius, emission.sweep_theta)

    for _ in 0..<sample_count {
        t := random_f32_range(ps, 0.0, 1.0)
        theta := emission.start_theta + emission.sweep_theta * t
        radius := emission.radius * f32(math.sqrt(random_f32_range(ps, 0.0, 1.0)))

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

// Queue one bounded contact spanning the rendered width of a revealed text label.
queue_dust_label_reveal_contact :: proc(
    ps: ^Particle_System,
    position: Vector3,
    text: string,
    font_size, projection_scale: f32) -> bool {
    if ps == nil || len(text) == 0 || font_size <= 0 || projection_scale <= 0 {
        return false
    }
    glyph_count := utf8.rune_count_in_string(text)
    if glyph_count <= 0 {
        return false
    }
    center_offset := font_size / projection_scale
    start: Vector3 = {position.x - center_offset,
        position.y - center_offset, position.z}
    width := font_size * 0.6 * f32(glyph_count) / projection_scale
    finish: Vector3 = {start.x + width, start.y - width, start.z}
    return queue_dust_tool_contact(ps, {
        endpoint = start,
        segment_first = start,
        segment_second = finish,
        has_sweep = true,
        source = .Label,
    })
}

// Copy one revealed polygon outline so the worker pushes its ground dust aside.
// Returns false only while the queue is full, so the caller retries next frame;
// raised polygons and malformed outlines are consumed without a push.
queue_dust_region_push :: proc(
    ps: ^Particle_System, cache: ^shapemodel.Shapes_Draw_Cache,
    draw: shapemodel.Shapes_Polygon_Draw) -> bool {
    if ps^.dust_region_push_count >= particlemodel.DUST_REGION_PUSH_CAP {
        return false
    }
    if draw.vertex_count < 3 || draw.first_vertex < 0 ||
        draw.first_vertex + draw.vertex_count > cache^.polygon_vertex_count {
        return true
    }
    push := &ps^.dust_region_pushes[ps^.dust_region_push_count]
    push^.vertex_count = 0
    stride := (draw.vertex_count + particlemodel.DUST_REGION_PUSH_VERTEX_CAP - 1) /
        particlemodel.DUST_REGION_PUSH_VERTEX_CAP
    for index := 0; index < draw.vertex_count; index += stride {
        vertex := cache^.polygon_vertices[draw.first_vertex + index]
        if abs(vertex.z) > DUST_REGION_FLOOR_Z_EPSILON {
            return true
        }
        push^.vertices[push^.vertex_count] = {vertex.x, vertex.y}
        push^.vertex_count += 1
    }
    ps^.dust_region_push_count += 1
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
    case .Label:
        return previous == current
    }
    return false
}

// Coalesce adjacent redundant contacts without changing raw queue admission.
coalesce_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps == nil || ps^.dust_tool_contact_count < 2 {
       return
    }
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
        if motion.x == 0 && motion.y == 0 {
           motion = endpoint_motion
        }
        ps^.dust_tool_contact_field_node_visit_count +=
            dust_field_apply_tool_motion(&ps^.dust_field,
                {position.x, position.y}, {motion.x, motion.y})
        ps^.dust_tool_contact_sample_count += 1
    }
}

// Apply one radial sample using the force profile owned by its contact source.
apply_dust_contact_point :: proc(
    field: ^Dust_Field_State,
    position: Vector2,
    source: particlemodel.Dust_Tool_Contact_Source) -> u64 {
    if source == .Label {
        return dust_field_apply_tool_point(
            field, position, DUST_LABEL_CONTACT_PUSH_RADIUS,
            DUST_LABEL_CONTACT_PUSH_SPEED)
    }
    return dust_field_apply_tool_point(field, position)
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

// Apply one queued contact to deposited field momentum.
apply_dust_tool_contact_to_field :: proc(
    ps: ^Particle_System, intent: ^particlemodel.Dust_Tool_Contact,
    field: ^particlemodel.Dust_Field_State) {
    if intent^.source == .Compass_Filled_Sweep {
        apply_dust_filled_sweep_to_field(ps, intent)
        return
    }
    if !intent^.has_sweep {
        ps^.dust_tool_contact_field_node_visit_count +=
            apply_dust_contact_point(field,
                {intent^.endpoint.x, intent^.endpoint.y}, intent^.source)
        ps^.dust_tool_contact_sample_count += 1
        return
    }
    interval_count := dust_tool_sweep_interval_count(
        intent^.segment_first, intent^.segment_second)
    inv_intervals := f32(1.0) / f32(interval_count)
    for sample_index in 0..=interval_count {
        interpolation := f32(sample_index) * inv_intervals
        position: Vector2 = {
            math.lerp(intent^.segment_first.x, intent^.segment_second.x, interpolation),
            math.lerp(intent^.segment_first.y, intent^.segment_second.y, interpolation)}
        ps^.dust_tool_contact_field_node_visit_count +=
            apply_dust_contact_point(field, position, intent^.source)
        ps^.dust_tool_contact_sample_count += 1
    }
}

// Apply queued contacts to deposited field momentum in command order.
apply_dust_tool_contacts_to_field :: proc(ps: ^Particle_System) {
    if ps == nil {
        return
    }
    ps^.dust_tool_contact_sample_count = 0
    ps^.dust_tool_contact_field_node_visit_count = 0
    if ps^.dust_tool_contact_count == 0 {
        return
    }
    coalesce_dust_tool_contacts(ps)
    field := &ps^.dust_field
    for contact_index in 0..<ps^.dust_tool_contact_count {
        intent := &ps^.dust_tool_contacts[contact_index]
        apply_dust_tool_contact_to_field(ps, intent, field)
    }
    ps^.dust_tool_contact_count = 0
}

// Discard pending tool contacts and region pushes at a runtime generation boundary.
discard_dust_tool_contacts :: proc(ps: ^Particle_System) {
    if ps != nil {
       ps^.dust_tool_contact_count = 0
       ps^.dust_region_push_count = 0
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
