package world

import native "../native"
import math "core:math"
import projection "projection"
import geometry "../../core/geometry"
import particlemodel "../../particles/model"
import particles "../../particles"
import core "../../core"

DUST_ATLAS_PIXEL_BYTES :: DUST_ATLAS_SIZE * DUST_ATLAS_SIZE * 4
DUST_PEAK_ALPHA :: 210
DUST_HYPOCYCLOID_SUPERSAMPLE_GRID :: 4
DUST_HYPOCYCLOID_SUPERSAMPLE_COUNT ::
    DUST_HYPOCYCLOID_SUPERSAMPLE_GRID * DUST_HYPOCYCLOID_SUPERSAMPLE_GRID

// LEAPER_LIGHT_SPREAD widens a leaper's ground light relative to its sprite.
LEAPER_LIGHT_SPREAD :: 4.5
// LEAPER_LIGHT_GAIN scales white-hot leaper light before blending.
LEAPER_LIGHT_GAIN :: 0.9
// LEAPER_LIGHT_FALLOFF_HEIGHT is the hop height that doubles the light radius.
LEAPER_LIGHT_FALLOFF_HEIGHT :: 0.04

// Leaper_Light_Source describes one leaper's world position, screen offset, sprite
// diameter, light intensity, and hop lift above its ground point.
Leaper_Light_Source :: struct {
    position: geometry.Vector3,
    offset: geometry.Vector2,
    diameter, light, lift: f32,
}

// dust_atlas_set_pixel writes one white RGBA8 coverage sample.
dust_atlas_set_pixel :: #force_inline proc(
    pixels: []u8, x, y: int, alpha: u8) {
    offset := (y * DUST_ATLAS_SIZE + x) * 4
    pixels[offset] = 255
    pixels[offset + 1] = 255
    pixels[offset + 2] = 255
    pixels[offset + 3] = alpha
}

// build_native_dust_circle writes the soft circular atlas tile.
build_native_dust_circle :: proc(pixels: []u8, tile_x, tile_y: int) {
    origin_x, origin_y := tile_x * DUST_TEXTURE_SIZE, tile_y * DUST_TEXTURE_SIZE
    center := (f32(DUST_TEXTURE_SIZE) - 1) * 0.5
    for y in 0..<DUST_TEXTURE_SIZE {
        for x in 0..<DUST_TEXTURE_SIZE {
            dx, dy := f32(x) - center, f32(y) - center
            radius_t := math.clamp(
                f32(math.sqrt(f64(dx * dx + dy * dy))) / center, 0, 1)
            alpha: f32 = 1
            if radius_t > DUST_TEXTURE_SOFT_EDGE_START {
                alpha = 1 - (radius_t - DUST_TEXTURE_SOFT_EDGE_START) /
                    (1 - DUST_TEXTURE_SOFT_EDGE_START)
            }
            dust_atlas_set_pixel(pixels, origin_x + x, origin_y + y,
                u8(math.clamp(alpha * 255, 0, 255)))
        }
    }
}

// build_native_dust_hypocycloid writes one supersampled polygon atlas tile.
build_native_dust_hypocycloid :: proc(
    pixels: []u8, tile_x, tile_y, k: int) {
    points: [DUST_HYPOCYCLOID_SAMPLE_COUNT]geometry.Vector2
    count := sample_dust_hypocycloid_points(points[:], k)
    if count == 0 {
       return
    }
    center := (f32(DUST_TEXTURE_SIZE) - 1) * 0.5
    origin_x, origin_y := tile_x * DUST_TEXTURE_SIZE, tile_y * DUST_TEXTURE_SIZE
    for y in 0..<DUST_TEXTURE_SIZE {
        for x in 0..<DUST_TEXTURE_SIZE {
            coverage := 0
            for sample_y in 0..<DUST_HYPOCYCLOID_SUPERSAMPLE_GRID {
                for sample_x in 0..<DUST_HYPOCYCLOID_SUPERSAMPLE_GRID {
                    point: geometry.Vector2 = {
                        (f32(x) + (f32(sample_x) + 0.5) /
                            DUST_HYPOCYCLOID_SUPERSAMPLE_GRID - center) / center,
                        (f32(y) + (f32(sample_y) + 0.5) /
                            DUST_HYPOCYCLOID_SUPERSAMPLE_GRID - center) / center}
                    if point_in_polygon(point, points[:count]) {
                        coverage += 1
                    }
                }
            }
            if coverage > 0 {
                dust_atlas_set_pixel(pixels, origin_x + x, origin_y + y,
                    u8(coverage * 255 / DUST_HYPOCYCLOID_SUPERSAMPLE_COUNT))
            }
        }
    }
}

// build_native_dust_atlas initializes and rasterizes the complete RGBA8 atlas.
build_native_dust_atlas :: proc(pixels: []u8) -> bool {
    if len(pixels) != DUST_ATLAS_PIXEL_BYTES {
        return false
    }
    for pixel in 0..<DUST_ATLAS_SIZE * DUST_ATLAS_SIZE {
        offset := pixel * 4
        pixels[offset] = 255
        pixels[offset + 1] = 255
        pixels[offset + 2] = 255
        pixels[offset + 3] = 0
    }
    build_native_dust_circle(pixels, 0, 0)
    for variant in 1..<DUST_ATLAS_VARIANT_COUNT {
        build_native_dust_hypocycloid(pixels,
            variant % DUST_ATLAS_COLUMNS, variant / DUST_ATLAS_COLUMNS,
            variant + 2)
    }
    return true
}

// low_dust_opacity combines lifetime fade, visual peak opacity, and authored alpha.
low_dust_opacity :: #force_inline proc(
    lifetime_progress: f32, authored_alpha: u8) -> f32 {
    lifetime_opacity := math.clamp(1 - lifetime_progress, 0, 1)
    return lifetime_opacity * f32(DUST_PEAK_ALPHA) / 255 *
        f32(authored_alpha) / 255
}

// initialize_native_dust_atlas publishes the fixed RGBA8 atlas synchronously.
initialize_native_dust_atlas :: proc(
    platform: ^native.Sdl_Platform,
    runtime: ^native.Sdl_Draw_Runtime) -> bool {
    pixels, allocation_error := make(
        []u8, DUST_ATLAS_PIXEL_BYTES, context.temp_allocator)
    if allocation_error != nil {
        return false
    }
    if !build_native_dust_atlas(pixels) {
        return false
    }
    candidate := native.sdl_sampled_texture_create(
        platform, DUST_ATLAS_SIZE, DUST_ATLAS_SIZE)
    if !native.sampled_texture_is_valid(candidate) {
        return false
    }
    if !native.texture_operation_enqueue_upload(
        &runtime^.texture_operations, {
            kind = .Create,
            texture = candidate,
            format = .Rgba8,
            source = pixels,
            identity = 1,
            generation = 1,
        }) || !native.sdl_draw_submit_texture_operations(platform, runtime) {
        native.sdl_sampled_texture_release(platform, &candidate)
        return false
    }
    runtime^.dust_atlas = candidate
    return true
}

#assert(native.DUST_WORLD_INSTANCE_CAPACITY >= particlemodel.MAX_LOW_PARTICLES)
#assert(native.DUST_WORLD_INSTANCE_CAPACITY >= particlemodel.MAX_FORMATION_PARTICLES)

// Prepare region, sweep, and label targets from the owner-matched draw cache.
prepare_formation_targets :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder) {
    scale := projection.viewport_scale_factor(state^.iso_scale)
    _ = particles.formation_prepare_region_targets(
        ps, &state^.shape_world, scale)
    _ = particles.formation_prepare_sweep_targets(
        ps, &state^.shape_world, scale)
    _ = prepare_formation_labels(ps, state, encoder)
}

// encode_low_particles compacts low dust and emits one ordered custom draw.
encode_low_particles :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder, texture: rawptr) {
    projected_count := projection.iso_to_cartesian_components_batch_selected({
        ps.low_particles.pos_x[:ps^.use_max_dust_particles],
        ps.low_particles.pos_y[:ps^.use_max_dust_particles],
        ps.low_particles.pos_z[:ps^.use_max_dust_particles],
        ps.low_particle_screens[:], state^.iso_scale},
        state^.ui_runtime.rendering.use_simd_batch_projection)
    staging := native.draw_encoder_dust_staging(encoder)
    count := 0
    for screen, index in ps.low_particle_screens[:projected_count] {
        if !ps.low_particles.alive[index] || count >= len(staging) {
            continue
        }
        t := math.clamp(
            ps.low_particles.age[index] / ps.low_particles.life[index], 0, 1)
        particle_color := ps.low_particles.color[index]
        if ps.low_particles.authored_ink[index] {
            particle_color = resolve_animation_authored_ink(state, particle_color)
        }
        staging[count] = {
            center_diameter = {screen.x, screen.y,
                max(ps.low_particles.size[index] * 2, 1)},
            color = {f32(particle_color.r) / 255,
                f32(particle_color.g) / 255, f32(particle_color.b) / 255,
                low_dust_opacity(t, particle_color.a)},
            sprite_index = f32(ps.low_particles.dust_sprite_index[index]),
        }
        count += 1
    }
    if native.draw_encoder_commit_dust(encoder, count, texture) {
        ps.last_render_low = count
    }
}

// Encode active settling material back to front as one contiguous atlas submission.
encode_formation_particles :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder, texture: rawptr) {
    staging := native.draw_encoder_dust_staging(encoder)
    visible := particles.formation_prepare_draw_order(ps)
    draw := &ps^.formation.draw_order
    count := 0
    for slot in draw^.order[:visible] {
        if count >= len(staging) {
            break
        }
        visual := draw^.visuals[slot]
        screen := projection.iso_to_cartesian(visual.position, state^.iso_scale)
        tint := resolve_animation_authored_ink(state, visual.authored_color)
        tint.r = u8(math.lerp(f32(tint.r), 255, visual.white_mix))
        tint.g = u8(math.lerp(f32(tint.g), 255, visual.white_mix))
        tint.b = u8(math.lerp(f32(tint.b), 255, visual.white_mix))
        tint.a = visual.color.a
        staging[count] = {
            center_diameter = {screen.x + visual.screen_offset.x,
                screen.y + visual.screen_offset.y, max(visual.diameter, 1)},
            color = {f32(tint.r) / 255, f32(tint.g) / 255,
                f32(tint.b) / 255, f32(tint.a) / 255},
            sprite_index = 0,
        }
        count += 1
    }
    _ = native.draw_encoder_commit_dust(encoder, count, texture)
    encode_formation_lights(draw, visible, state, encoder)
}

// leaper_light_instance places one warm light on the ground under a leaper.
// Higher hops spread the light wider and dimmer, roughly conserving its energy.
leaper_light_instance :: proc(
    source: Leaper_Light_Source,
    state: ^core.Euclid_General_State) -> native.Dust_Instance {
    position := source.position
    ground := projection.iso_to_cartesian(
        {position.x, position.y, position.z - source.lift}, state^.iso_scale)
    spread := 1 + source.lift / LEAPER_LIGHT_FALLOFF_HEIGHT
    strength := LEAPER_LIGHT_GAIN * source.light / (spread * spread)
    return {
        center_diameter = {ground.x + source.offset.x, ground.y + source.offset.y,
            max(source.diameter * LEAPER_LIGHT_SPREAD * spread, 1)},
        color = {1, 0.86, 0.66, strength},
    }
}

// encode_formation_lights appends ground light for white-hot formation leapers.
encode_formation_lights :: proc(
    draw: ^particlemodel.Formation_Draw_Order, visible: int,
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    staging := native.draw_encoder_dust_staging(encoder)
    count := 0
    for slot in draw^.order[:visible] {
        visual := draw^.visuals[slot]
        if visual.light <= 0.01 || count >= len(staging) {
            continue
        }
        staging[count] = leaper_light_instance({visual.position,
            visual.screen_offset, visual.diameter, visual.light, visual.lift},
            state)
        count += 1
    }
    _ = native.draw_encoder_commit_light(encoder, count)
}

// encode_mid_particles appends trail pigment, then leapers above it, as atlas quads.
encode_mid_particles :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder, texture: rawptr) {
    count := 0
    lights := native.draw_encoder_dust_staging(encoder)
    light_count := 0
    for role in particlemodel.Trail_Particle_Role {
        for index in 0..<MAX_PARTICLES {
            if !ps.particles.alive[index] || ps.particles.role[index] != role {
                continue
            }
            visual := particles.trail_particle_visual(ps, index)
            if !visual.visible {
                continue
            }
            screen := projection.iso_to_cartesian(visual.position, state^.iso_scale)
            diameter := max(visual.diameter, 1)
            if native.draw_encoder_texture_quad(encoder,
                {screen.x - diameter * 0.5, screen.y - diameter * 0.5,
                    diameter, diameter}, {0, 0, 1.0 / DUST_ATLAS_COLUMNS,
                    1.0 / DUST_ATLAS_ROWS}, visual.color, {texture, .Linear}) {
                count += 1
            }
            if visual.light > 0.01 && light_count < len(lights) {
                lights[light_count] = leaper_light_instance({visual.position, {},
                    visual.diameter, visual.light, visual.lift}, state)
                light_count += 1
            }
        }
    }
    _ = native.draw_encoder_commit_light(encoder, light_count)
    ps.last_render_mid = count
}
