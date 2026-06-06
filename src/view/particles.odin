package view

import "../core"
import "core:math"
import rl "vendor:raylib"

MAX_PARTICLES :: core.MAX_PARTICLES

render_particles :: proc(ps: ^ParticleSystem, state: ^EuclidGeneralState) {
    for i in 0..<MAX_PARTICLES {
        p := ps.Particles[i]
        if !p.Alive {
            continue
        }

        t := math.clamp(p.Age / p.Life, 0.0, 1.0)
        alpha := (1.0 - t)
        // Softer fade option:
        // alpha = alpha * alpha
        alpha_u8 := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

        col := rl.Color{p.Color.r, p.Color.g, p.Color.b, alpha_u8}
 
        rl.DrawCircleV(iso_to_cartesian(p.Position, state^.IsoScale^), p.Size, col)
    }
}
