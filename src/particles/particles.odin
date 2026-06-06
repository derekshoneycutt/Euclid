package particles

import "../core"
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
JITTER_PIXELS :: 0.005
LIFE_VARIATION_MIN :: 80
LIFE_VARIATION_MAX :: 120


reset_particles :: proc(ps: ^ParticleSystem) {
    ps.NextIndex = 0
    ps.SpawnTimer = 0
    for i in 0..<MAX_PARTICLES {
        ps.Particles[i].Alive = false
        ps.Particles[i].Age = 0
    }
}

spawn_particle :: proc(ps: ^ParticleSystem, tip_x, tip_y: f32, tip_color: rl.Color) {
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

    ps.NextIndex = (ps.NextIndex + 1) % MAX_PARTICLES
}

emit_trail_particles :: proc(ps: ^ParticleSystem, dt, tip_x, tip_y: f32, tip_color: rl.Color) {
    ps.SpawnTimer += dt

    // Emit particles at a fixed cadence.
    for ps.SpawnTimer >= SPAWN_INTERVAL {
        ps.SpawnTimer -= SPAWN_INTERVAL
        spawn_particle(ps, tip_x, tip_y, tip_color)
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

        t := math.clamp(f32(p.Age / p.Life), 0.0, 1.0)
        p.Size = math.lerp(f32(PARTICLE_SIZE_START), PARTICLE_SIZE_END, t)
    }
}
