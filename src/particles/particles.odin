package particles

import "../core"
Vector2 :: core.Vector2
Vector3 :: core.Vector3
Particle :: core.Particle
ParticleSystem :: core.ParticleSystem


import "core:math"
import rl "vendor:raylib"

MAX_PARTICLES :: core.MAX_PARTICLES
SPAWN_INTERVAL :: 0.012 // seconds
PARTICLE_LIFE :: 0.75  // seconds
PARTICLE_SIZE_START :: 5.0
PARTICLE_SIZE_END :: 0.5
FLOOR_Z :: 0.0
JITTER_PIXELS :: 0.0055
LIFE_VARIATION_MIN :: 80
LIFE_VARIATION_MAX :: 120

BURNOUT_LIFE            :: 0.5
BURNOUT_SIZE_START      :: 3.5
BURNOUT_SIZE_END        :: 0.0
BURNOUT_PER_TRAIL_SPAWN :: 3

FLICKERS_PER_TRAIL_SPAWN  :: 5
FLICKER_LIFE_MIN          :: 0.0
FLICKER_LIFE_MAX          :: 0.5
FLICKER_SPAWN_RADIUS      :: 0.001
FLICKER_UP_SPEED_MIN      :: 0.0
FLICKER_UP_SPEED_MAX      :: 0.001
FLICKER_XY_DRIFT_STEP     :: 0.001
FLICKER_CHANCE_PER_STEP   :: 0.07
FLICKER_LIT_FRAMES_MIN    :: 1
FLICKER_LIT_FRAMES_MAX    :: 2

random_f32_range :: proc(min_v, max_v: f32) -> f32 {
    t := f32(rl.GetRandomValue(0, 10000)) / 10000.0
    return math.lerp(min_v, max_v, t)
}

reset_particles :: proc(ps: ^ParticleSystem) {
    ps.NextIndex = 0
    ps.SpawnTimer = 0
    for i in 0..<MAX_PARTICLES {
        ps.Particles[i].Alive = false
        ps.Particles[i].Age = 0
    }
}

spawn_particle :: proc(
    ps: ^ParticleSystem, tip_x, tip_y: f32, tip_color: rl.Color) -> Vector3 {

    p := &ps.Particles[ps.NextIndex]

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
    ps.NextIndex = (ps.NextIndex + 1) % MAX_PARTICLES
    return spawn_pos
}

spawn_flicker_particle :: proc(ps: ^ParticleSystem, origin: Vector3) {

    p := &ps.Particles[ps.NextIndex]

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

    ps.NextIndex = (ps.NextIndex + 1) % MAX_PARTICLES
}

spawn_burnout_particle :: proc(
    ps: ^ParticleSystem, tip_x, tip_y: f32, tip_color: rl.Color) {

    p := &ps.Particles[ps.NextIndex]

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

    ps.NextIndex = (ps.NextIndex + 1) % MAX_PARTICLES
}

emit_trail_particles :: proc(ps: ^ParticleSystem, dt, tip_x, tip_y: f32, tip_color: rl.Color) {
    ps.SpawnTimer += dt

    for ps.SpawnTimer >= SPAWN_INTERVAL {
        ps.SpawnTimer -= SPAWN_INTERVAL

        trail_pos := spawn_particle(ps, tip_x, tip_y, tip_color)

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

update_particles :: proc(ps: ^ParticleSystem, dt: f32) {
    for i in 0..<MAX_PARTICLES {
        p := &ps.Particles[i]
        if !p.Alive {
            continue
        }

        p.Age += dt
        if p.Age >= p.Life {
            p.Alive = false
            continue
        }

        switch p.Type {
            case .Trail:
                update_particle_trail(p)
            case .Flicker:
                update_particle_flicker(p)
            case .BurnOut:
                update_particle_burnout(p)
        }
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
