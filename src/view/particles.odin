package view

// Just drawing whatever particles are currently alive. Pretty simple, tbh

import "../core"

import "core:math"

import rl "vendor:raylib"

MAX_PARTICLES :: core.MAX_PARTICLES

//   Render alive low-layer particles and update low-layer render counters.
//
// Parameters:
//   - ps: Particle system containing low-layer particles.
//   - state: Global app state providing isometric projection scale.
//
// Returns:
//   - none.
render_low_particles :: proc(ps: ^Particle_System, state: ^Euclid_General_State) {
    count_rendered : int = 0
    for i in 0..<ps^.use_max_dust_particles {
        p := &ps.low_particles[i]
        if !p^.alive {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian(p^.position, state^.iso_scale^)

        switch p.kind {
        case .Trail:
            render_particle_trail(p, screen)
        case .Flicker:
            render_particle_flicker(p, screen)
        case .BurnOut:
            render_particle_burnout(p, screen)
        case .Dust:
            render_particle_dust(p, screen)
        }
    }
    ps.last_render_low = count_rendered
}

//   Render alive mid-layer particles and update mid-layer render counters.
//
// Parameters:
//   - ps: Particle system containing mid-layer particles.
//   - state: Global app state providing isometric projection scale.
//
// Returns:
//   - none.
render_particles :: proc(ps: ^Particle_System, state: ^Euclid_General_State) {
    count_rendered : int = 0
    for i in 0..<MAX_PARTICLES {
        p := &ps.particles[i]
        if !p^.alive {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian(p^.position, state^.iso_scale^)

        switch p.kind {
        case .Trail:
            render_particle_trail(p, screen)
        case .Flicker:
            render_particle_flicker(p, screen)
        case .BurnOut:
            render_particle_burnout(p, screen)
        case .Dust:
            render_particle_dust(p, screen)
        }
    }
    ps.last_render_mid = count_rendered
}

//   Render alive high-layer particles and update high-layer render counters.
//
// Parameters:
//   - ps: Particle system containing high-layer particles.
//   - state: Global app state providing isometric projection scale.
//
// Returns:
//   - none.
render_high_particles :: proc(ps: ^Particle_System, state: ^Euclid_General_State) {
    count_rendered : int = 0
    for i in 0..<MAX_PARTICLES {
        p := &ps.high_particles[i]
        if !p^.alive {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian(p^.position, state^.iso_scale^)

        switch p.kind {
        case .Trail:
            render_particle_trail(p, screen)
        case .Flicker:
            render_particle_flicker(p, screen)
        case .BurnOut:
            render_particle_burnout(p, screen)
        case .Dust:
            render_particle_dust(p, screen)
        }
    }
    ps.last_render_high = count_rendered
}




//   Render one trail particle with lifetime-based alpha fade.
render_particle_trail :: proc(p : ^Particle, screen: Vector2) {
    t := math.clamp(p^.age / p^.life, 0.0, 1.0)
    alpha := (1.0 - t)
    alpha_u8 := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    col := rl.Color{p^.color.r, p^.color.g, p^.color.b, alpha_u8}

    rl.DrawCircleV(screen, p^.size, col)
}

//   Render one flicker particle only while its lit window is active.
render_particle_flicker :: proc(p : ^Particle, screen: Vector2) {
    if p^.lit_frames > 0 {
        rl.DrawPixelV(screen, rl.WHITE)
    }
}

//   Render one burnout particle with color/alpha burn-down over life.
render_particle_burnout :: proc(p: ^Particle, screen: Vector2) {
    t := math.clamp(p^.age / p^.life, 0.0, 1.0)

    white : f32 = 255.0

    r := u8(math.clamp(math.lerp(white, f32(p^.color.r), t), 0.0, 255.0))
    g := u8(math.clamp(math.lerp(white, f32(p^.color.g), t), 0.0, 255.0))
    b := u8(math.clamp(math.lerp(white, f32(p^.color.b), t), 0.0, 255.0))

    alpha := 1.0 - t
    a := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    rl.DrawCircleV(screen, p^.size, rl.Color{r, g, b, a})
}

//   Render one dust particle with lifetime-based alpha fade.
render_particle_dust :: proc(p: ^Particle, screen: Vector2) {
    t := math.clamp(p^.age / p^.life, 0.0, 1.0)
    alpha := 1.0 - t
    a := u8(math.clamp(alpha * 210.0, 0.0, 255.0))

    col := rl.Color{p^.color.r, p^.color.g, p^.color.b, a}
    rl.DrawCircleV(screen, p^.size, col)
}
