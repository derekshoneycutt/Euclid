package particles

import "../core"
Vector2 :: core.Vector2
Vector3 :: core.Vector3
Particle :: core.Particle
ParticleSystem :: core.ParticleSystem
KinePointSystem :: core.KinePointSystem


import "core:math"
import rl "vendor:raylib"

MAX_LOW_PARTICLES :: core.MAX_LOW_PARTICLES
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

DUST_CONTACT_PUSH_RADIUS :: f32(0.02)
DUST_CONTACT_PUSH_SPEED :: f32(0.0035)

DUST_KICK_FADE_MIN :: 0.03
DUST_KICK_FADE_MAX :: 0.08
DUST_EXISTING_UP_KICK_MIN :: 0.0012
DUST_EXISTING_UP_KICK_MAX :: 0.0048
DUST_EXISTING_XY_KICK :: 0.0011

CLEAR_BURST_POINT_COUNT :: 28
CLEAR_BURST_LINE_SAMPLES :: 40
CLEAR_BURST_CIRCLE_SAMPLES :: 120

random_f32_range :: proc(min_v, max_v: f32) -> f32 {
    t := f32(rl.GetRandomValue(0, 10000)) / 10000.0
    return math.lerp(min_v, max_v, t)
}

reset_particles :: proc(ps: ^ParticleSystem) {
    ps.NextIndex = 0
    ps.SpawnTimer = 0
    for i in 0..<MAX_LOW_PARTICLES {
        ps.LowParticles[i].Alive = false
        ps.LowParticles[i].Age = 0
    }
    for i in 0..<MAX_PARTICLES {
        ps.Particles[i].Alive = false
        ps.Particles[i].Age = 0
        ps.HighParticles[i].Alive = false
        ps.HighParticles[i].Age = 0
    }
}

reserve_dead_low_particle_slot :: proc(ps: ^ParticleSystem) -> (^Particle, bool) {
    for step in 0..<MAX_LOW_PARTICLES {
        index := (ps.NextIndex + step) % MAX_LOW_PARTICLES
        if !ps.LowParticles[index].Alive {
            ps.NextIndex = (index + 1) % MAX_LOW_PARTICLES
            return &ps.LowParticles[index], true
        }
    }

    return nil, false
}

reserve_dead_high_particle_slot :: proc(ps: ^ParticleSystem) -> (^Particle, bool) {
    for step in 0..<MAX_PARTICLES {
        index := (ps.NextIndex + step) % MAX_PARTICLES
        if !ps.HighParticles[index].Alive {
            ps.NextIndex = (index + 1) % MAX_PARTICLES
            return &ps.HighParticles[index], true
        }
    }

    return nil, false
}

reserve_dead_particle_slot :: proc(ps: ^ParticleSystem) -> (^Particle, bool) {
    for step in 0..<MAX_PARTICLES {
        index := (ps.NextIndex + step) % MAX_PARTICLES
        if !ps.Particles[index].Alive {
            ps.NextIndex = (index + 1) % MAX_PARTICLES
            return &ps.Particles[index], true
        }
    }

    return nil, false
}

spawn_particle :: proc(
    ps: ^ParticleSystem, tip_x, tip_y: f32, tip_color: rl.Color) -> (Vector3, bool) {

    p, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return Vector3{}, false
    }

    // Tiny spawn jitter so the trail is less uniform.
    jitter_x := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    p.Position.x = tip_x + jitter_x
    p.Position.y = tip_y + jitter_y
    p.Position.z = 0.0

    p.Age = 0

    life_scale := f32(rl.GetRandomValue(LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    p.Life = PARTICLE_LIFE * life_scale

    p.Size = PARTICLE_SIZE_START
    p.Color = tip_color
    p.Alive = true

    p.Type = .Trail
    p.Velocities = Vector3{}
    p.LitFrames = 0

    spawn_pos := p.Position
    return spawn_pos, true
}

spawn_flicker_particle :: proc(ps: ^ParticleSystem, origin: Vector3) {

    p, ok := reserve_dead_high_particle_slot(ps)
    if !ok {
        return
    }

    angle := random_f32_range(0.0, 6.2831855)
    radius := random_f32_range(0.0, FLICKER_SPAWN_RADIUS)

    p.Position.x = origin.x + f32(math.cos(angle)) * radius
    p.Position.y = origin.y + f32(math.sin(angle)) * radius
    p.Position.z = origin.z

    p.Velocities.x = random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    p.Velocities.y = random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP)
    p.Velocities.z = random_f32_range(FLICKER_UP_SPEED_MIN, FLICKER_UP_SPEED_MAX)

    p.Type = .Flicker
    p.Color = rl.WHITE
    p.Size = 1.0
    p.Age = 0
    p.Life = random_f32_range(FLICKER_LIFE_MIN, FLICKER_LIFE_MAX)
    p.LitFrames = 0
    p.Alive = true

}

spawn_burnout_particle :: proc(
    ps: ^ParticleSystem, tip_x, tip_y: f32, tip_color: rl.Color) {

    p, ok := reserve_dead_particle_slot(ps)
    if !ok {
        return
    }

    jitter_x := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS
    jitter_y := (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * JITTER_PIXELS

    p.Position.x = tip_x + jitter_x
    p.Position.y = tip_y + jitter_y
    p.Position.z = 0.0

    p.Age = 0
    life_scale := f32(rl.GetRandomValue(LIFE_VARIATION_MIN, LIFE_VARIATION_MAX)) / 100.0
    p.Life = BURNOUT_LIFE * life_scale

    p.Size = BURNOUT_SIZE_START
    p.Color = tip_color
    p.Alive = true

    p.Type = .BurnOut
    p.Velocities = Vector3{}
    p.LitFrames = 0

}

emit_trail_particles :: proc(ps: ^ParticleSystem, dt, tip_x, tip_y: f32, tip_color: rl.Color) {
    ps.SpawnTimer += dt

    for ps.SpawnTimer >= SPAWN_INTERVAL {
        ps.SpawnTimer -= SPAWN_INTERVAL

        trail_pos, ok := spawn_particle(ps, tip_x, tip_y, tip_color)
        if !ok {
            continue
        }

        for _ in 0..<FLICKERS_PER_TRAIL_SPAWN {
            spawn_flicker_particle(ps, trail_pos)
        }

        for _ in 0..<BURNOUT_PER_TRAIL_SPAWN {
            spawn_burnout_particle(ps, tip_x, tip_y, tip_color)
        }
    }
}

emit_silence :: proc(ps: ^ParticleSystem, dt: f32) {
    ps.SpawnTimer += dt

    for ps.SpawnTimer >= SPAWN_INTERVAL {
        ps.SpawnTimer -= SPAWN_INTERVAL
    }
}

clamp_xy_bounds :: proc "contextless" (p: ^Particle) {
    if p.Position.x < DUST_XY_MIN {
        p.Position.x = DUST_XY_MIN
        p.Velocities.x = -p.Velocities.x * 0.45
    } else if p.Position.x > DUST_XY_MAX {
        p.Position.x = DUST_XY_MAX
        p.Velocities.x = -p.Velocities.x * 0.45
    }

    if p.Position.y < DUST_XY_MIN {
        p.Position.y = DUST_XY_MIN
        p.Velocities.y = -p.Velocities.y * 0.45
    } else if p.Position.y > DUST_XY_MAX {
        p.Position.y = DUST_XY_MAX
        p.Velocities.y = -p.Velocities.y * 0.45
    }
}

push_dust_away_from_xy :: proc (ps: ^ParticleSystem, x, y: f32) {
    push_radius_sq := DUST_CONTACT_PUSH_RADIUS * DUST_CONTACT_PUSH_RADIUS

    for i in 0..<MAX_LOW_PARTICLES {
        p := &ps.LowParticles[i]
        if !p.Alive || p.Type != .Dust {
            continue
        }

        dx := p.Position.x - x
        dy := p.Position.y - y
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

        p.Velocities.x += nx * push
        p.Velocities.y += ny * push

        p.Position.x += nx * push
        p.Position.y += ny * push
        clamp_xy_bounds(p)
    }
}

spawn_dust_particle :: proc(ps: ^ParticleSystem, origin: Vector3, col: rl.Color) {
    p, ok := reserve_dead_low_particle_slot(ps)
    if !ok {
        return
    }

    p.Type = .Dust
    p.Alive = true
    p.Age = 0
    p.Life = random_f32_range(DUST_LIFE_MIN, DUST_LIFE_MAX)

    p.Position = origin
    p.Position.x += random_f32_range(-0.0022, 0.0022)
    p.Position.y += random_f32_range(-0.0022, 0.0022)
    p.Position.z = DUST_FLOOR_Z

    p.Velocities.x = random_f32_range(DUST_VX_MIN, DUST_VX_MAX)
    p.Velocities.y = random_f32_range(DUST_VY_MIN, DUST_VY_MAX)
    p.Velocities.z = random_f32_range(DUST_VZ_MIN, DUST_VZ_MAX)

    p.Size = random_f32_range(DUST_SIZE_START_MIN, DUST_SIZE_START_MAX)
    p.Color = col
    p.LitFrames = 0

}

kick_existing_dust :: proc(ps: ^ParticleSystem) {
    for i in 0..<MAX_LOW_PARTICLES {
        p := &ps.LowParticles[i]
        if !p.Alive || p.Type != .Dust {
            continue
        }

        // Dust only fades when it is kicked by a new clear burst.
        p.Age += random_f32_range(DUST_KICK_FADE_MIN, DUST_KICK_FADE_MAX)

        p.Velocities.x += random_f32_range(-DUST_EXISTING_XY_KICK, DUST_EXISTING_XY_KICK)
        p.Velocities.y += random_f32_range(-DUST_EXISTING_XY_KICK, DUST_EXISTING_XY_KICK)
        p.Velocities.z += random_f32_range(DUST_EXISTING_UP_KICK_MIN, DUST_EXISTING_UP_KICK_MAX)

        if p.Age >= p.Life {
            p.Alive = false
        }
    }
}

emit_line_dust :: proc(ps: ^ParticleSystem, a, b: Vector3, col: rl.Color) {
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

normalize_theta :: proc(theta: f32) -> f32 {
    t := theta
    if t < 0 {
        t += 2.0 * math.PI
    }
    return t
}

compute_sweep_delta :: proc(start_theta, end_theta: f32) -> f32 {
    start_n := normalize_theta(start_theta)
    end_n := normalize_theta(end_theta)

    delta := end_n - start_n
    if delta < 0 {
        delta += 2.0 * math.PI
    }
    return delta
}

emit_circle_dust :: proc(ps: ^ParticleSystem, center, start, finish: Vector3, col: rl.Color) {
    start_vec := start - center
    end_vec := finish - center

    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))
    if start_radius <= 0 && end_radius <= 0 {
        return
    }

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta)

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

emit_kine_hide_burst :: proc(ps: ^ParticleSystem, ks: ^KinePointSystem, index: int) {
    if index < 0 || index >= MAX_KINEPOINTS {
        return
    }

    kp := &ks.Points[index]
    if !kp.DoDraw {
        return
    }

    if kp.Type != .Point && kp.Type != .Line && kp.Type != .Circle && kp.Type != .FilledCircle {
        return
    }

    kick_existing_dust(ps)

    col := kp.Color.? or_else rl.WHITE
    switch kp.Type {
        case .Point:
            p, ok := kp.Position.?
            if ok {
                for _ in 0..<CLEAR_BURST_POINT_COUNT {
                    spawn_dust_particle(ps, p, col)
                }
            }
        case .Line:
            a_id := kp.ChildPointHead
            if a_id < 0 || a_id >= MAX_KINEPOINTS {
                return
            }

            b_id := ks.Points[a_id].NextChildPoint
            if b_id < 0 || b_id >= MAX_KINEPOINTS {
                return
            }

            a, a_ok := ks.Points[a_id].Position.?
            b, b_ok := ks.Points[b_id].Position.?
            if a_ok && b_ok {
                emit_line_dust(ps, a, b, col)
            }
        case .Circle, .FilledCircle:
            center, center_ok := kp.Position.?
            if !center_ok {
                return
            }

            start_id := kp.ChildPointHead
            if start_id < 0 || start_id >= MAX_KINEPOINTS {
                return
            }

            end_id := ks.Points[start_id].NextChildPoint
            if end_id < 0 || end_id >= MAX_KINEPOINTS {
                return
            }

            start, start_ok := ks.Points[start_id].Position.?
            finish, finish_ok := ks.Points[end_id].Position.?
            if !start_ok || !finish_ok {
                return
            }

            if kp.ActiveChild > 1 {
                start, finish = finish, start
            }

            emit_circle_dust(ps, center, start, finish, col)
        case .Pen, .Compass:
            return
    }
}

emit_kine_clear_burst :: proc(ps: ^ParticleSystem, ks: ^KinePointSystem) {
    kick_existing_dust(ps)

    for i in 0..<MAX_KINEPOINTS {
        kp := &ks.Points[i]
        if !kp.DoDraw {
            continue
        }

        if kp.Type != .Point && kp.Type != .Line && kp.Type != .Circle && kp.Type != .FilledCircle {
            continue
        }

        col := kp.Color.? or_else rl.WHITE

        switch kp.Type {
            case .Point:
                p, ok := kp.Position.?
                if ok {
                    for _ in 0..<CLEAR_BURST_POINT_COUNT {
                        spawn_dust_particle(ps, p, col)
                    }
                }
            case .Line:
                a_id := kp.ChildPointHead
                if a_id < 0 || a_id >= MAX_KINEPOINTS {
                    continue
                }

                b_id := ks.Points[a_id].NextChildPoint
                if b_id < 0 || b_id >= MAX_KINEPOINTS {
                    continue
                }

                a, a_ok := ks.Points[a_id].Position.?
                b, b_ok := ks.Points[b_id].Position.?
                if a_ok && b_ok {
                    emit_line_dust(ps, a, b, col)
                }
            case .Circle, .FilledCircle:
                center, center_ok := kp.Position.?
                if !center_ok {
                    continue
                }

                start_id := kp.ChildPointHead
                if start_id < 0 || start_id >= MAX_KINEPOINTS {
                    continue
                }

                end_id := ks.Points[start_id].NextChildPoint
                if end_id < 0 || end_id >= MAX_KINEPOINTS {
                    continue
                }

                start, start_ok := ks.Points[start_id].Position.?
                finish, finish_ok := ks.Points[end_id].Position.?
                if !start_ok || !finish_ok {
                    continue
                }

                if kp.ActiveChild > 1 {
                    start, finish = finish, start
                }

                emit_circle_dust(ps, center, start, finish, col)
            case .Pen, .Compass:
                continue
        }
    }
}

update_particles :: proc(ps: ^ParticleSystem, dt: f32) {
    for i in 0..<MAX_LOW_PARTICLES {
        lp := &ps.LowParticles[i]
        update_particle(lp, dt)
    }
    for i in 0..<MAX_PARTICLES {
        p := &ps.Particles[i]
        update_particle(p, dt)
        hp := &ps.HighParticles[i]
        update_particle(hp, dt)
    }
}

update_particle :: proc(p : ^Particle, dt: f32) {
    if !p.Alive {
        return
    }

    if p.Type != .Dust {
        p.Age += dt
        if p.Age >= p.Life {
            p.Alive = false
            return
        }
    }

    switch p.Type {
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

update_particle_trail :: proc(p : ^Particle) {
    t := math.clamp(f32(p.Age / p.Life), 0.0, 1.0)
    p.Size = math.lerp(f32(PARTICLE_SIZE_START), PARTICLE_SIZE_END, t)
}

update_particle_flicker :: proc(p : ^Particle) {
    p.Position += p.Velocities
    p.Velocities.x += random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25
    p.Velocities.y += random_f32_range(-FLICKER_XY_DRIFT_STEP, FLICKER_XY_DRIFT_STEP) * 0.25

    if p.LitFrames > 0 {
        p.LitFrames -= 1
    } else {
        if random_f32_range(0.0, 1.0) < FLICKER_CHANCE_PER_STEP {
            p.LitFrames = i16(rl.GetRandomValue(FLICKER_LIT_FRAMES_MIN, FLICKER_LIT_FRAMES_MAX))
        }
    }
}

update_particle_burnout :: proc(p: ^Particle) {
    t := math.clamp(f32(p.Age / p.Life), 0.0, 1.0)
    p.Size = math.lerp(f32(BURNOUT_SIZE_START), BURNOUT_SIZE_END, t)
}

update_particle_dust :: proc(p: ^Particle) {
    p.Velocities.z += DUST_GRAVITY

    p.Position += p.Velocities

    p.Velocities.x *= DUST_DRAG_XY
    p.Velocities.y *= DUST_DRAG_XY
    p.Velocities.z *= DUST_DRAG_Z

    if p.Position.z < DUST_FLOOR_Z {
        p.Position.z = DUST_FLOOR_Z
        if p.Velocities.z < 0 {
            p.Velocities.z = -p.Velocities.z * DUST_BOUNCE
        }
    }

    clamp_xy_bounds(p)

    t := math.clamp(f32(p.Age / p.Life), 0.0, 1.0)
    p.Size = math.lerp(f32(DUST_SIZE_START_MAX), DUST_SIZE_END, t)
}
