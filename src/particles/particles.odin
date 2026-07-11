package particles

// Simple particle system kinda took off away from me a bit here, but it has a few important
// points to discuss:

// 3 Layers : Low, Middle, High.
// Technically, we try to not be picky about what kind of particle is in each, but there's
// a clear pattern. Low has dust, Middle has Trail and BurnOut, and the high layer has the
// Flicker particles.

// Particle types :
//
// - Dust particles move around and collide with eachother, giving some Newtonian style
//   physics to them. They can be emitted from shapes, creating an effect of the shapes
//   being deconstructed into dust. Their lifetime is dependent on how many times the dust
//   is kicked up, as opposed to hard time restraints.
// - Trail and Burnout are always used together and create the kind of flat-magic-fire
//   feel that trails behind tools on the ground. Trail is just a single color and fades
//   away, BurnOut starts white and burns into the color as it fades.
// - Flicker move in a 3D velocity away from the point of emission. They randomly show as
//   single pixels drawn on the screen. The result is a kind of sparkling flicker effect.

import "../core"

import "core:math"
import "core:mem"

import rl "vendor:raylib"

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Particle :: core.Particle
Particle_System :: core.Particle_System
Kine_Point_System :: core.Kine_Point_System

MAX_PARTICLES :: core.MAX_PARTICLES
MAX_KINEPOINTS :: core.MAX_KINEPOINTS

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

DUST_CONTACT_PUSH_RADIUS :: 0.04
DUST_CONTACT_PUSH_SPEED :: 0.0035

DUST_KICK_FADE_MIN :: 0.03
DUST_KICK_FADE_MAX :: 0.08
DUST_EXISTING_UP_KICK_MIN :: 0.0012
DUST_EXISTING_UP_KICK_MAX :: 0.0148
DUST_EXISTING_XY_KICK :: 0.0011

DUST_COLLISION_RADIUS :: 0.004
DUST_COLLISION_RESTITUTION :: 0.42
DUST_COLLISION_POSITION_SLOP :: 0.0001

DUST_GRID_CELL_SIZE :: core.DUST_GRID_CELL_SIZE
DUST_GRID_DIM :: core.DUST_GRID_DIM
DUST_GRID_DIM_SQUARED :: core.DUST_GRID_DIM_SQUARED
DUST_GRID_BUCKET_CAP :: core.DUST_GRID_BUCKET_CAP
DUST_GRID_BUCKET_COUNT :: core.DUST_GRID_BUCKET_COUNT

DUST_GRID_NEIGHBORS :: [5][2]int{{0,0},{1,0},{-1,1},{0,1},{1,1}}

CLEAR_BURST_POINT_COUNT :: 28
CLEAR_BURST_LINE_SAMPLES :: 75
CLEAR_BURST_CIRCLE_SAMPLES :: 120

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
emit_flicker_particles :: proc(ps: ^Particle_System, x, y, z: f32, color: rl.Color, count: int = 1) {
    origin := Vector3{x, y, z}
    if count <= 0 {
        return
    }

    for _ in 0..<count {
        spawn_flicker_particle(ps, origin, color)
    }
}

//   Emit trail particles over time and attach burnout/flicker effects.
//
// Parameters:
//   - ps: Particle system receiving emitted particles.
//   - dt: Simulation delta time in seconds.
//   - tip_x: Tool-tip x position used as emission origin.
//   - tip_y: Tool-tip y position used as emission origin.
//   - tip_z: Tool-tip z position used as emission origin.
//   - tip_color: Base trail/burnout color.
//
// Returns:
//   - none.
emit_trail_particles :: proc(ps: ^Particle_System, dt, tip_x, tip_y, tip_z: f32, tip_color: rl.Color) {
    ps.spawn_timer += dt

    for ps.spawn_timer >= SPAWN_INTERVAL {
        ps.spawn_timer -= SPAWN_INTERVAL

        trail_pos, ok := spawn_particle(ps, tip_x, tip_y, tip_z, tip_color)
        if !ok {
            continue
        }

        for _ in 0..<FLICKERS_PER_TRAIL_SPAWN {
            spawn_flicker_particle(ps, trail_pos, rl.WHITE)
        }

        for _ in 0..<BURNOUT_PER_TRAIL_SPAWN {
            spawn_burnout_particle(ps, tip_x, tip_y, tip_z, tip_color)
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
push_dust_away_from_xy :: proc (ps: ^Particle_System, x, y: f32) {
    if ps^.use_max_dust_particles < 1 {
        return
    }

    push_radius_sq : f32 = DUST_CONTACT_PUSH_RADIUS * DUST_CONTACT_PUSH_RADIUS

    for i in 0..<ps^.use_max_dust_particles {
        p := &ps.low_particles[i]
        if !p.alive || p.kind != .Dust {
            continue
        }

        dx := p.position.x - x
        dy := p.position.y - y
        dist_sq := dx * dx + dy * dy
        if dist_sq > push_radius_sq {
            continue
        }

        dist := f32(math.sqrt(f64(dist_sq)))
        nx, ny: f32
        if dist > f32(0.00001) {
            inv_dist := f32(1.0) / dist
            nx = dx * inv_dist
            ny = dy * inv_dist
        } else {
            theta := random_f32_range(f32(0.0), f32(2.0 * math.PI))
            nx = f32(math.cos(theta))
            ny = f32(math.sin(theta))
        }

        falloff := f32(1.0) - math.clamp(dist / DUST_CONTACT_PUSH_RADIUS, f32(0.0), f32(1.0))
        push := DUST_CONTACT_PUSH_SPEED * falloff

        p.velocities.x += nx * push
        p.velocities.y += ny * push

        p.position.x += nx * push
        p.position.y += ny * push
        clamp_xy_bounds(p)
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
        p := &ps.low_particles[i]
        if !p.alive || p.kind != .Dust {
            continue
        }

        // Dust only fades when it is kicked by a new clear burst.
        p.age += random_f32_range(DUST_KICK_FADE_MIN, DUST_KICK_FADE_MAX)

        p.velocities.x += random_f32_range(-DUST_EXISTING_XY_KICK, DUST_EXISTING_XY_KICK)
        p.velocities.y += random_f32_range(-DUST_EXISTING_XY_KICK, DUST_EXISTING_XY_KICK)
        p.velocities.z += random_f32_range(DUST_EXISTING_UP_KICK_MIN, DUST_EXISTING_UP_KICK_MAX)

        if p.age >= p.life {
            p.alive = false
        }
    }
}

//   Emit dust burst particles for a specific drawable kine item.
//
// Parameters:
//   - ps: Particle system receiving emitted dust.
//   - ks: Kine point system used to resolve geometry for the selected item.
//   - index: Point index of the drawable kine host item.
//   - kick_dust: When true, pre-kicks existing dust before emitting new dust.
//
// Returns:
//   - none.
emit_kine_hide_burst :: proc(ps: ^Particle_System, ks: ^Kine_Point_System, index: int, kick_dust: bool = true) {
    if index < 0 || index >= MAX_KINEPOINTS || ps^.use_max_dust_particles < 1 {
        return
    }

    kp := &ks.points[index]
    if !kp.do_draw {
        return
    }

    if kp.kind != .Label && kp.kind != .Point && kp.kind != .Line && kp.kind != .Circle &&
        kp.kind != .FilledCircle && kp.kind != .Triangle && kp.kind != .Square &&
        kp.kind != .Pentagon {
        return
    }

    if kick_dust {
        kick_existing_dust(ps)
    }

    col := kp.color.? or_else rl.WHITE
    switch kp.kind {
    case .Label:
        p, ok := kp.position.?
        if ok {
            for _ in 0..<CLEAR_BURST_POINT_COUNT {
                spawn_dust_particle(ps, p, col)
            }
        }
    case .Point:
        p, ok := kp.position.?
        if ok {
            for _ in 0..<CLEAR_BURST_POINT_COUNT {
                spawn_dust_particle(ps, p, col)
            }
        }
    case .Line:
        a_id := kp.child_point_head
        if a_id < 0 || a_id >= MAX_KINEPOINTS {
            return
        }

        b_id := ks.points[a_id].next_child_point
        if b_id < 0 || b_id >= MAX_KINEPOINTS {
            return
        }

        a, a_ok := ks.points[a_id].position.?
        b, b_ok := ks.points[b_id].position.?
        if a_ok && b_ok {
            emit_line_dust(ps, a, b, col)
        }
    case .Triangle:
        emit_polygon_edge_dust(ps, ks, kp.child_point_head, 3, col)
    case .Square:
        emit_polygon_edge_dust(ps, ks, kp.child_point_head, 4, col)
    case .Pentagon:
        emit_polygon_edge_dust(ps, ks, kp.child_point_head, 5, col)
    case .Circle, .FilledCircle:
        center, center_ok := kp.position.?
        if !center_ok {
            return
        }

        start_id := kp.child_point_head
        if start_id < 0 || start_id >= MAX_KINEPOINTS {
            return
        }

        end_id := ks.points[start_id].next_child_point
        if end_id < 0 || end_id >= MAX_KINEPOINTS {
            return
        }

        start, start_ok := ks.points[start_id].position.?
        finish, finish_ok := ks.points[end_id].position.?
        if !start_ok || !finish_ok {
            return
        }

        if kp.active_child > 1 {
            start, finish = finish, start
        }

        emit_circle_dust(ps, center, start, finish, kp.offset, col)
    case .Pen, .Compass:
        return
    }
}

//   Emit dust bursts across all currently drawable kine items.
//
// Parameters:
//   - ps: Particle system receiving emitted dust.
//   - ks: Kine point system used to resolve drawable geometry.
//
// Returns:
//   - none.
emit_kine_clear_burst :: proc(ps: ^Particle_System, ks: ^Kine_Point_System) {
    if  ps^.use_max_dust_particles < 1 {
        return
    }

    kick_existing_dust(ps)

    for i in 0..<MAX_KINEPOINTS {
        kp := &ks.points[i]
        if !kp.do_draw {
            continue
        }

        if kp.kind != .Label && kp.kind != .Point && kp.kind != .Line && kp.kind != .Circle &&
            kp.kind != .FilledCircle && kp.kind != .Triangle && kp.kind != .Square &&
            kp.kind != .Pentagon {
            continue
        }

        col := kp.color.? or_else rl.WHITE

        switch kp.kind {
        case .Label:
            p, ok := kp.position.?
            if ok {
                for _ in 0..<CLEAR_BURST_POINT_COUNT {
                    spawn_dust_particle(ps, p, col)
                }
            }
        case .Point:
            p, ok := kp.position.?
            if ok {
                for _ in 0..<CLEAR_BURST_POINT_COUNT {
                    spawn_dust_particle(ps, p, col)
                }
            }
        case .Line:
            a_id := kp.child_point_head
            if a_id < 0 || a_id >= MAX_KINEPOINTS {
                continue
            }

            b_id := ks.points[a_id].next_child_point
            if b_id < 0 || b_id >= MAX_KINEPOINTS {
                continue
            }

            a, a_ok := ks.points[a_id].position.?
            b, b_ok := ks.points[b_id].position.?
            if a_ok && b_ok {
                emit_line_dust(ps, a, b, col)
            }
        case .Triangle:
            emit_polygon_edge_dust(ps, ks, kp.child_point_head, 3, col)
        case .Square:
            emit_polygon_edge_dust(ps, ks, kp.child_point_head, 4, col)
        case .Pentagon:
            emit_polygon_edge_dust(ps, ks, kp.child_point_head, 5, col)
        case .Circle, .FilledCircle:
            center, center_ok := kp.position.?
            if !center_ok {
                continue
            }

            start_id := kp.child_point_head
            if start_id < 0 || start_id >= MAX_KINEPOINTS {
                continue
            }

            end_id := ks.points[start_id].next_child_point
            if end_id < 0 || end_id >= MAX_KINEPOINTS {
                continue
            }

            start, start_ok := ks.points[start_id].position.?
            finish, finish_ok := ks.points[end_id].position.?
            if !start_ok || !finish_ok {
                continue
            }

            if kp.active_child > 1 {
                start, finish = finish, start
            }

            emit_circle_dust(ps, center, start, finish, kp.offset, col)
        case .Pen, .Compass:
            continue
        }
    }
}

//   Advance particle simulation for dust, trail, burnout, and flicker layers.
//
// Parameters:
//   - ps: Particle system to update.
//   - dt: Simulation delta time in seconds.
//
// Returns:
//   - none.
update_particles :: proc(ps: ^Particle_System, dt: f32) {
    for i in 0..<ps^.use_max_dust_particles {
        lp := &ps.low_particles[i]
        update_particle_dust(lp)
    }

    resolve_dust_collisions(ps)

    for i in 0..<MAX_PARTICLES {
        p := &ps.particles[i]
        update_particle(p, dt)
        hp := &ps.high_particles[i]
        update_particle(hp, dt)
    }
}






//   Generate a random float in the inclusive [min_v, max_v] range.
random_f32_range :: proc(min_v, max_v: f32) -> f32 {
    t := f32(rl.GetRandomValue(0, 10000)) / 10000.0
    return math.lerp(min_v, max_v, t)
}

//   Reset particle-system runtime counters and mark all particle slots as dead.
reset_particles :: proc(ps: ^Particle_System) {
    ps.next_index = 0
    ps.spawn_timer = 0
    for i in 0..<ps^.use_max_dust_particles {
        ps.low_particles[i].alive = false
        ps.low_particles[i].age = 0
    }
    for i in 0..<MAX_PARTICLES {
        ps.particles[i].alive = false
        ps.particles[i].age = 0
        ps.high_particles[i].alive = false
        ps.high_particles[i].age = 0
    }
}

//   Reserve a low-layer slot for dust particles, preferring dead entries.
//
// Notes:
//   - Falls back to ring overwrite when all dust slots are alive.
reserve_dead_low_particle_slot :: proc(ps: ^Particle_System) -> (^Particle, bool) {
    if ps^.use_max_dust_particles < 1 {
        return nil, false
    }

    for step in 0..<ps^.use_max_dust_particles {
        index := (ps.next_index + step) % ps^.use_max_dust_particles
        if !ps.low_particles[index].alive {
            ps.next_index = (index + 1) % ps^.use_max_dust_particles
            return &ps.low_particles[index], true
        }
    }

    index := ps.next_index % ps^.use_max_dust_particles
    ps.next_index = (index + 1) % ps^.use_max_dust_particles
    return &ps.low_particles[index], true
}

//   Reserve a high-layer slot using ring-buffer indexing.
//
// Notes:
//   - Always returns a slot by advancing next_index modulo MAX_PARTICLES.
reserve_dead_high_particle_slot :: proc(ps: ^Particle_System) -> (^Particle, bool) {
    index := ps.next_index % MAX_PARTICLES
    ps.next_index = (index + 1) % MAX_PARTICLES
    return &ps.high_particles[index], true

    // TODO: this is preserved for future evaluation, although it seems unnecessary
    /*for step in 0..<MAX_PARTICLES {
        index := (ps.next_index + step) % MAX_PARTICLES
        if !ps.high_particles[index].alive {
            ps.next_index = (index + 1) % MAX_PARTICLES
            return &ps.high_particles[index], true
        }
    }

    return nil, false*/
}

//   Reserve a mid-layer slot using ring-buffer indexing.
//
// Notes:
//   - Always returns a slot by advancing next_index modulo MAX_PARTICLES.
reserve_dead_particle_slot :: proc(ps: ^Particle_System) -> (^Particle, bool) {
    index := ps.next_index % MAX_PARTICLES
    ps.next_index = (index + 1) % MAX_PARTICLES
    return &ps.particles[index], true

    // TODO: this is preserved for future evaluation, although it seems unnecessary
    /*for step in 0..<MAX_PARTICLES {
        index := (ps.next_index + step) % MAX_PARTICLES
        if !ps.particles[index].alive {
            ps.next_index = (index + 1) % MAX_PARTICLES
            return &ps.particles[index], true
        }
    }

    return nil, false*/
}

//   Spawn one trail particle near the provided tool-tip position.
spawn_particle :: proc(
    ps: ^Particle_System, tip_x, tip_y, tip_z: f32, tip_color: rl.Color) -> (Vector3, bool) {

    p, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return Vector3{}, false
    }

    // Tiny spawn jitter so the trail is less uniform.
    jitter_x := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    p.position.x = tip_x + jitter_x
    p.position.y = tip_y + jitter_y
    p.position.z = tip_z

    p.age = 0

    life_scale := f32(rl.GetRandomValue(LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    p.life = PARTICLE_LIFE * life_scale

    p.size = PARTICLE_SIZE_START
    p.color = tip_color
    p.alive = true

    p.kind = .Trail
    p.velocities = Vector3{}
    p.lit_frames = 0

    spawn_pos := p.position
    return spawn_pos, true
}

//   Spawn one high-layer flicker particle at an origin with random drift.
spawn_flicker_particle :: proc(ps: ^Particle_System, origin: Vector3, color: rl.Color) {

    p, ok := reserve_dead_high_particle_slot(ps)
    if !ok {
        return
    }

    angle := random_f32_range(0.0, 6.2831855)
    radius := random_f32_range(0.0, FLICKER_SPAWN_RADIUS)

    p.position.x = origin.x + f32(math.cos(angle)) * radius
    p.position.y = origin.y + f32(math.sin(angle)) * radius
    p.position.z = origin.z

    p.velocities.x = random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    p.velocities.y = random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    p.velocities.z = random_f32_range(FLICKER_UP_SPEED_MIN, FLICKER_UP_SPEED_MAX)

    p.kind = .Flicker
    p.color = color
    p.size = 1.0
    p.age = 0
    p.life = random_f32_range(FLICKER_LIFE_MIN, FLICKER_LIFE_MAX)
    p.lit_frames = 0
    p.alive = true

}

//   Spawn one burnout particle near the provided tool-tip position.
spawn_burnout_particle :: proc(
    ps: ^Particle_System, tip_x, tip_y, tip_z: f32, tip_color: rl.Color) {

    p, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return
    }

    jitter_x := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS

    p.position.x = tip_x + jitter_x
    p.position.y = tip_y + jitter_y
    p.position.z = tip_z

    p.age = 0
    life_scale := f32(rl.GetRandomValue(LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    p.life = BURNOUT_LIFE * life_scale

    p.size = BURNOUT_SIZE_START
    p.color = tip_color
    p.alive = true

    p.kind = .BurnOut
    p.velocities = Vector3{}
    p.lit_frames = 0

}

//   Advance spawn timer without emitting particles.
emit_silence :: proc(ps: ^Particle_System, dt: f32) {
    ps.spawn_timer += dt

    for ps.spawn_timer >= SPAWN_INTERVAL {
        ps.spawn_timer -= SPAWN_INTERVAL
    }
}

//   Clamp a particle's x/y position to dust bounds and apply bounce damping.
clamp_xy_bounds :: proc "contextless" (p: ^Particle) {
    if p.position.x < DUST_XY_MIN {
        p.position.x = DUST_XY_MIN
        p.velocities.x = -p.velocities.x * 0.45
    } else if p.position.x > DUST_XY_MAX {
        p.position.x = DUST_XY_MAX
        p.velocities.x = -p.velocities.x * 0.45
    }

    if p.position.y < DUST_XY_MIN {
        p.position.y = DUST_XY_MIN
        p.velocities.y = -p.velocities.y * 0.45
    } else if p.position.y > DUST_XY_MAX {
        p.position.y = DUST_XY_MAX
        p.velocities.y = -p.velocities.y * 0.45
    }
}

//   Spawn one low-layer dust particle around an origin with random kick values.
spawn_dust_particle :: proc(ps: ^Particle_System, origin: Vector3, col: rl.Color) {
    p, ok := reserve_dead_low_particle_slot(ps)
    if !ok {
        return
    }

    p.kind = .Dust
    p.alive = true
    p.age = 0
    p.life = random_f32_range(DUST_LIFE_MIN, DUST_LIFE_MAX)

    p.position = origin
    p.position.x += random_f32_range(-0.0022, 0.0022)
    p.position.y += random_f32_range(-0.0022, 0.0022)

    p.velocities.x = random_f32_range(DUST_VX_MIN, DUST_VX_MAX)
    p.velocities.y = random_f32_range(DUST_VY_MIN, DUST_VY_MAX)
    p.velocities.z = random_f32_range(DUST_VZ_MIN, DUST_VZ_MAX)

    p.size = random_f32_range(DUST_SIZE_START_MIN, DUST_SIZE_START_MAX)
    p.color = col
    p.lit_frames = 0

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

        for _ in 0..<2 {
            spawn_dust_particle(ps, sample, col)
        }
    }
}

//   Emit dust along each edge of a polygon resolved from kine child-point links.
//
// Notes:
//   - Supports up to the local fixed vertex buffer size.
emit_polygon_edge_dust :: proc(
    ps: ^Particle_System,
    ks: ^Kine_Point_System,
    first_child_id: int,
    vertex_count: int,
    col: rl.Color) {
    if vertex_count < 3 {
        return
    }

    if first_child_id < 0 || first_child_id >= MAX_KINEPOINTS {
        return
    }

    vertices: [12]Vector3

    current_id := first_child_id
    for i in 0..<vertex_count {
        if current_id < 0 || current_id >= MAX_KINEPOINTS {
            return
        }

        v, ok := ks.points[current_id].position.?
        if !ok {
            return
        }

        vertices[i] = v
        current_id = ks.points[current_id].next_child_point
    }

    for i in 0..<vertex_count {
        next_i := i + 1
        if next_i >= vertex_count {
            next_i = 0
        }
        emit_line_dust(ps, vertices[i], vertices[next_i], col)
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

//   Emit dust samples along a circular/arc sweep between start and finish points.
emit_circle_dust :: proc(ps: ^Particle_System, center, start, finish: Vector3, offset: f32, col: rl.Color) {
    start_vec := start - center
    end_vec := finish - center

    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))
    if start_radius <= 0 && end_radius <= 0 {
        return
    }

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta) + offset

    sample_count := max(CLEAR_BURST_CIRCLE_SAMPLES, 2)
    denom := f32(sample_count - 1)
    for s in 0..<sample_count {
        t := f32(s) / denom
        theta := start_theta + sweep_delta * t
        radius := math.lerp(start_radius, end_radius, t)

        sample := center
        sample.x += f32(math.cos(theta)) * radius
        sample.y += f32(math.sin(theta)) * radius

        for _ in 0..<2 {
            spawn_dust_particle(ps, sample, col)
        }
    }
}

//   Map x/y position into the dust collision grid cell index.
dust_grid_cell_index :: proc(x, y: f32) -> int {
    cx := clamp(int(x / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    cy := clamp(int(y / DUST_GRID_CELL_SIZE), 0, DUST_GRID_DIM - 1)
    return cy * DUST_GRID_DIM + cx
}

//   Resolve one dust-particle pair collision with positional and velocity response.
resolve_dust_pair :: proc(a, b: ^Particle, min_sep, radius_sq: f32) {
    dx := b.position.x - a.position.x
    dy := b.position.y - a.position.y
    dist_sq := dx * dx + dy * dy
    if dist_sq >= radius_sq || dist_sq < 1e-12 {
        return
    }

    dist   := math.sqrt(dist_sq)
    nx, ny := dx / dist, dy / dist

    pen := min_sep - dist
    if pen > DUST_COLLISION_POSITION_SLOP {
        corr := (pen - DUST_COLLISION_POSITION_SLOP) * 0.5
        a.position.x -= nx * corr
        a.position.y -= ny * corr
        b.position.x += nx * corr
        b.position.y += ny * corr
        clamp_xy_bounds(a)
        clamp_xy_bounds(b)
    }

    vn := (b.velocities.x - a.velocities.x) * nx +
          (b.velocities.y - a.velocities.y) * ny
    if vn >= 0 {
        return
    }

    imp := -(1.0 + DUST_COLLISION_RESTITUTION) * vn * 0.5
    a.velocities.x -= imp * nx
    a.velocities.y -= imp * ny
    b.velocities.x += imp * nx
    b.velocities.y += imp * ny
}

//   Resolve dust collisions for one cell against configured neighbor cells.
resolve_dust_collisions_on_grid :: proc(
    ps: ^Particle_System,
    cy, cx, ca, na: int, radius_sq, min_sep: f32) {

    if na == 0 {
        return
    }

    for off in DUST_GRID_NEIGHBORS {
        ncx, ncy := cx + off[0], cy + off[1]
        if ncx < 0 || ncx >= DUST_GRID_DIM || ncy < 0 || ncy >= DUST_GRID_DIM {
            continue
        }
        cb := ncy * DUST_GRID_DIM + ncx
        nb := int(ps^.dust_counts[cb])
        same_cell := ca == cb

        for li in 0..<na {
            a := &ps.low_particles[ps^.dust_buckets[ca * DUST_GRID_BUCKET_CAP + li]]
            lj_start := li + 1 if same_cell else 0
            for lj in lj_start..<nb {
                resolve_dust_pair(a,
                    &ps.low_particles[ps^.dust_buckets[cb * DUST_GRID_BUCKET_CAP + lj]],
                    min_sep, radius_sq)
            }
        }
    }
}

//   Build temporary dust grid buckets and resolve pairwise dust collisions.
resolve_dust_collisions :: proc(ps: ^Particle_System) {
    if ps^.use_max_dust_particles < 1 {
        return
    }

    mem.set(&ps^.dust_buckets[0], 0, size_of(ps^.dust_buckets))
    mem.set(&ps^.dust_counts[0], 0, size_of(ps^.dust_counts))

    for i in 0..<ps^.use_max_dust_particles {
        p := &ps.low_particles[i]
        if !p.alive || p.kind != .Dust {
            continue
        }
        c := dust_grid_cell_index(p.position.x, p.position.y)
        if ps^.dust_counts[c] < i32(DUST_GRID_BUCKET_CAP) {
            ps^.dust_buckets[c * DUST_GRID_BUCKET_CAP + int(ps^.dust_counts[c])] = i32(i)
            ps^.dust_counts[c] += 1
        }
    }

    radius_sq : f32 = DUST_COLLISION_RADIUS * DUST_COLLISION_RADIUS
    min_sep : f32 = DUST_COLLISION_RADIUS * 2.0

    for cy in 0..<DUST_GRID_DIM {
        for cx in 0..<DUST_GRID_DIM {
            ca := cy * DUST_GRID_DIM + cx
            na := int(ps^.dust_counts[ca])
            resolve_dust_collisions_on_grid(ps, cy, cx, ca, na, radius_sq, min_sep)
        }
    }
}

//   Advance one particle by type-specific behavior and lifetime rules.
update_particle :: proc(p : ^Particle, dt: f32) {
    if !p.alive {
        return
    }

    if p.kind != .Dust {
        p.age += dt
        if p.age >= p.life {
            p.alive = false
            return
        }
    }

    switch p.kind {
    case .Trail:
        update_particle_trail(p)
    case .Flicker:
        update_particle_flicker(p)
    case .BurnOut:
        update_particle_burnout(p)
    case .Dust:
        update_particle_dust(p)
    }
}

//   Update trail particle size based on normalized lifetime.
update_particle_trail :: proc(p : ^Particle) {
    t := math.clamp(f32(p.age / p.life), 0.0, 1.0)
    p.size = math.lerp(f32(PARTICLE_SIZE_START), PARTICLE_SIZE_END, t)
}

//   Update flicker particle position, drift, and intermittent lit-frame state.
update_particle_flicker :: proc(p : ^Particle) {
    p.position += p.velocities
    p.velocities.x += random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25
    p.velocities.y += random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25

    if p.lit_frames > 0 {
        p.lit_frames -= 1
    } else {
        if random_f32_range(0.0, 1.0) < FLICKER_CHANCE_PER_STEP {
            p.lit_frames = i16(rl.GetRandomValue(FLICKER_LIT_FRAMES_MIN, FLICKER_LIT_FRAMES_MAX))
        }
    }
}

//   Update burnout particle size based on normalized lifetime.
update_particle_burnout :: proc(p: ^Particle) {
    t := math.clamp(f32(p.age / p.life), 0.0, 1.0)
    p.size = math.lerp(f32(BURNOUT_SIZE_START), BURNOUT_SIZE_END, t)
}

//   Update dust particle physics, floor bounce, bounds clamp, and size fade.
update_particle_dust :: proc(p: ^Particle) {
    p.velocities.z += DUST_GRAVITY

    p.position += p.velocities

    p.velocities.x *= DUST_DRAG_XY
    p.velocities.y *= DUST_DRAG_XY
    p.velocities.z *= DUST_DRAG_Z

    if p.position.z < DUST_FLOOR_Z {
        p.position.z = DUST_FLOOR_Z
        if p.velocities.z < 0 {
            p.velocities.z = -p.velocities.z * DUST_BOUNCE
        }
    }

    clamp_xy_bounds(p)

    t := math.clamp(f32(p.age / p.life), 0.0, 1.0)
    p.size = math.lerp(f32(DUST_SIZE_START_MAX), DUST_SIZE_END, t)
}
