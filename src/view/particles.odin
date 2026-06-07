package view

import "../core"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

MAX_PARTICLES :: core.MAX_PARTICLES

render_particles :: proc(ps: ^ParticleSystem, state: ^EuclidGeneralState) {
    for i in 0..<MAX_PARTICLES {
        p := &ps.Particles[i]
        if !p^.Alive {
            continue
        }

        screen := iso_to_cartesian(p^.Position, state^.IsoScale^)

        switch p.Type {
            case .Trail:
                render_particle_trail(p, screen)
            case .Flicker:
                render_particle_flicker(p, screen)
            case .BurnOut:
                render_particle_burnout(p, screen)
        }
    }
}

render_particle_trail :: proc(p : ^Particle, screen: Vector2) {
    t := math.clamp(p^.Age / p^.Life, 0.0, 1.0)
    alpha := (1.0 - t)
    alpha_u8 := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    col := rl.Color{p^.Color.r, p^.Color.g, p^.Color.b, alpha_u8}

    rl.DrawCircleV(screen, p^.Size, col)
}

render_particle_flicker :: proc(p : ^Particle, screen: Vector2) {
    if p^.LitFrames > 0 {
        rl.DrawPixelV(screen, rl.WHITE)
    }
}

render_particle_burnout :: proc(p: ^Particle, screen: Vector2) {
    t := math.clamp(p^.Age / p^.Life, 0.0, 1.0)

    white : f32 = 255.0

    r := u8(math.clamp(math.lerp(white, f32(p^.Color.r), t), 0.0, 255.0))
    g := u8(math.clamp(math.lerp(white, f32(p^.Color.g), t), 0.0, 255.0))
    b := u8(math.clamp(math.lerp(white, f32(p^.Color.b), t), 0.0, 255.0))

    alpha := 1.0 - t
    a := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    rl.DrawCircleV(screen, p^.Size, rl.Color{r, g, b, a})
}
