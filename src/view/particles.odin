package view

// Just drawing whatever particles are currently alive. Pretty simple, tbh

import "../core"

import "core:math"

import rl "vendor:raylib"

MAX_PARTICLES :: core.MAX_PARTICLES
DUST_TEXTURE_SIZE :: 64
DUST_TEXTURE_SOFT_EDGE_START :: 0.58

//   Render alive low-layer particles and update low-layer render counters.
//
// Parameters:
//   - ps: Particle system containing low-layer particles.
//   - state: Global app state providing isometric projection scale.
//
// Returns:
//   - none.
render_low_particles :: proc(ps: ^Particle_System, state: ^Euclid_General_State) {
    iso_scale := state^.iso_scale^

    count_rendered : int = 0
    for i in 0..<ps^.use_max_dust_particles {
        if !ps.low_particles.alive[i] {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian_inline(ps.low_particles.position[i], iso_scale)

        t := math.clamp(ps.low_particles.age[i] / ps.low_particles.life[i], 0.0, 1.0)
        alpha := 1.0 - t
        a := u8(math.clamp(alpha * 210.0, 0.0, 255.0))

        dust_color := ps.low_particles.color[i]

        col := rl.Color{
            dust_color.r,
            dust_color.g,
            dust_color.b,
            a}

        if draw_particle_quad(state, screen, ps.low_particles.size[i] * 2.0, col) {
            continue
        }

        if ps.low_particles.size[i] <= 1 {
            rl.DrawPixelV(screen, col)
        } else {
            rl.DrawCircleV(screen, ps.low_particles.size[i], col)
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
    iso_scale := state^.iso_scale^

    count_rendered : int = 0
    for i in 0..<MAX_PARTICLES {
        if !ps.particles.alive[i] {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian_inline(
            ps.particles.position[i],
            iso_scale)

        switch ps.particles.kind[i] {
        case .Trail:
            render_particle_trail_mid_index(state, ps, i, screen)
        case .Flicker:
            render_particle_flicker_mid_index(ps, i, screen)
        case .BurnOut:
            render_particle_burnout_mid_index(state, ps, i, screen)
        case .Dust:
            continue
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
    iso_scale := state^.iso_scale^

    count_rendered : int = 0
    for i in 0..<MAX_PARTICLES {
        if !ps.high_particles.alive[i] {
            continue
        }
        count_rendered += 1

        screen := iso_to_cartesian_inline(ps.high_particles.position[i], iso_scale)

        switch ps.high_particles.kind[i] {
        case .Trail:
            render_particle_trail_high_index(state, ps, i, screen)
        case .Flicker:
            render_particle_flicker_high_index(ps, i, screen)
        case .BurnOut:
            render_particle_burnout_high_index(state, ps, i, screen)
        case .Dust:
            continue
        }
    }
    ps.last_render_high = count_rendered
}



//   Release particle renderer resources created at runtime.
//
// Parameters:
//   - state: Global app state storing particle render resources.
//
// Returns:
//   - none.
shutdown_particle_render_resources :: proc(state: ^Euclid_General_State) {
    if !state^.dust_render.ready {
        return
    }

    rl.UnloadTexture(state^.dust_render.texture)
    state^.dust_render.ready = false
}


//   Lazily create a soft circular dust texture for textured-quad rendering.
//
// Parameters:
//   - state: Global app state storing particle render resources.
//
// Returns:
//   - none.
ensure_dust_texture :: proc(state: ^Euclid_General_State) {
    if state^.dust_render.ready {
        return
    }

    image := rl.GenImageColor(
        DUST_TEXTURE_SIZE,
        DUST_TEXTURE_SIZE,
        rl.Color{255, 255, 255, 0})
    defer rl.UnloadImage(image)

    center := (f32(DUST_TEXTURE_SIZE) - 1) * 0.5
    max_dist := center

    for y in 0..<DUST_TEXTURE_SIZE {
        for x in 0..<DUST_TEXTURE_SIZE {
            dx := f32(x) - center
            dy := f32(y) - center
            dist := f32(math.sqrt(f64(dx * dx + dy * dy)))
            radius_t := math.clamp(dist / max_dist, 0.0, 1.0)

            alpha : f32
            if radius_t <= DUST_TEXTURE_SOFT_EDGE_START {
                alpha = 1.0
            } else {
                edge_t := (radius_t - DUST_TEXTURE_SOFT_EDGE_START) /
                    (1.0 - DUST_TEXTURE_SOFT_EDGE_START)
                alpha = 1.0 - edge_t
            }

            a := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

            rl.ImageDrawPixel(&image, i32(x), i32(y), rl.Color{255, 255, 255, a})
        }
    }

    state^.dust_render.texture = rl.LoadTextureFromImage(image)
    state^.dust_render.ready = state^.dust_render.texture.id != 0
}


//   Draw one particle as a textured quad, preserving world-space size.
//
// Parameters:
//   - state: Global app state storing particle render resources.
//   - screen: Screen-space center for the particle.
//   - diameter: Desired on-screen diameter in pixels.
//   - col: Final color tint including alpha.
//
// Returns:
//   - true when a textured quad was rendered; false when fallback is needed.
draw_particle_quad :: proc(
    state: ^Euclid_General_State,
    screen: Vector2,
    diameter: f32,
    col: rl.Color) -> bool {
    ensure_dust_texture(state)
    if !state^.dust_render.ready {
        return false
    }

    use_diameter := diameter
    if use_diameter < 1.0 {
        use_diameter = 1.0
    }

    src := rl.Rectangle{0, 0, f32(DUST_TEXTURE_SIZE), f32(DUST_TEXTURE_SIZE)}
    dst := rl.Rectangle{screen.x, screen.y, use_diameter, use_diameter}
    origin := rl.Vector2{use_diameter * 0.5, use_diameter * 0.5}

    rl.DrawTexturePro(state^.dust_render.texture, src, dst, origin, 0, col)
    return true
}




//   Render one mid-layer trail particle with lifetime-based alpha fade.
render_particle_trail_mid_index :: proc(
    state: ^Euclid_General_State,
    ps: ^Particle_System,
    i: int,
    screen: Vector2) {
    t := math.clamp(ps.particles.age[i] / ps.particles.life[i], 0.0, 1.0)
    alpha := (1.0 - t)
    alpha_u8 := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    particle_color := ps.particles.color[i]
    col := rl.Color{particle_color.r, particle_color.g, particle_color.b, alpha_u8}

    if !draw_particle_quad(state, screen, ps.particles.size[i] * 2.0, col) {
        rl.DrawCircleV(screen, ps.particles.size[i], col)
    }
}

//   Render one high-layer trail particle with lifetime-based alpha fade.
render_particle_trail_high_index :: proc(
    state: ^Euclid_General_State,
    ps: ^Particle_System,
    i: int,
    screen: Vector2) {
    t := math.clamp(ps.high_particles.age[i] / ps.high_particles.life[i], 0.0, 1.0)
    alpha := (1.0 - t)
    alpha_u8 := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    particle_color := ps.high_particles.color[i]
    col := rl.Color{particle_color.r, particle_color.g, particle_color.b, alpha_u8}

    if !draw_particle_quad(state, screen, ps.high_particles.size[i] * 2.0, col) {
        rl.DrawCircleV(screen, ps.high_particles.size[i], col)
    }
}

//   Render one mid-layer flicker particle only while its lit window is active.
render_particle_flicker_mid_index :: proc(ps: ^Particle_System, i: int, screen: Vector2) {
    if ps.particles.lit_frames[i] > 0 {
        rl.DrawPixelV(screen, rl.WHITE)
    }
}

//   Render one high-layer flicker particle only while its lit window is active.
render_particle_flicker_high_index :: proc(ps: ^Particle_System, i: int, screen: Vector2) {
    if ps.high_particles.lit_frames[i] > 0 {
        rl.DrawPixelV(screen, rl.WHITE)
    }
}

//   Render one mid-layer burnout particle with color/alpha burn-down over life.
render_particle_burnout_mid_index :: proc(
    state: ^Euclid_General_State,
    ps: ^Particle_System,
    i: int,
    screen: Vector2) {
    t := math.clamp(ps.particles.age[i] / ps.particles.life[i], 0.0, 1.0)

    white : f32 = 255.0

    particle_color := ps.particles.color[i]

    r := u8(math.clamp(math.lerp(white, f32(particle_color.r), t), 0.0, 255.0))
    g := u8(math.clamp(math.lerp(white, f32(particle_color.g), t), 0.0, 255.0))
    b := u8(math.clamp(math.lerp(white, f32(particle_color.b), t), 0.0, 255.0))

    alpha := 1.0 - t
    a := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    col := rl.Color{r, g, b, a}
    if !draw_particle_quad(state, screen, ps.particles.size[i] * 2.0, col) {
        rl.DrawCircleV(screen, ps.particles.size[i], col)
    }
}

//   Render one high-layer burnout particle with color/alpha burn-down over life.
render_particle_burnout_high_index :: proc(
    state: ^Euclid_General_State,
    ps: ^Particle_System,
    i: int,
    screen: Vector2) {
    t := math.clamp(ps.high_particles.age[i] / ps.high_particles.life[i], 0.0, 1.0)

    white : f32 = 255.0

    particle_color := ps.high_particles.color[i]

    r := u8(math.clamp(math.lerp(white, f32(particle_color.r), t), 0.0, 255.0))
    g := u8(math.clamp(math.lerp(white, f32(particle_color.g), t), 0.0, 255.0))
    b := u8(math.clamp(math.lerp(white, f32(particle_color.b), t), 0.0, 255.0))

    alpha := 1.0 - t
    a := u8(math.clamp(alpha * 255.0, 0.0, 255.0))

    col := rl.Color{r, g, b, a}
    if !draw_particle_quad(state, screen, ps.high_particles.size[i] * 2.0, col) {
        rl.DrawCircleV(screen, ps.high_particles.size[i], col)
    }
}
