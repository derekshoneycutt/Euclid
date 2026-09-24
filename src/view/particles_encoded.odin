package view

import native "native"
import view_core "core"
import color "../core/color"

import "core:math"

DUST_ATLAS_PIXEL_BYTES :: DUST_ATLAS_SIZE * DUST_ATLAS_SIZE * 4
DUST_PEAK_ALPHA :: 210
DUST_HYPOCYCLOID_SUPERSAMPLE_GRID :: 4
DUST_HYPOCYCLOID_SUPERSAMPLE_COUNT ::
    DUST_HYPOCYCLOID_SUPERSAMPLE_GRID * DUST_HYPOCYCLOID_SUPERSAMPLE_GRID

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
    points: [DUST_HYPOCYCLOID_SAMPLE_COUNT]Vector2
    count := sample_dust_hypocycloid_points(points[:], k)
    if count == 0 {return}
    center := (f32(DUST_TEXTURE_SIZE) - 1) * 0.5
    origin_x, origin_y := tile_x * DUST_TEXTURE_SIZE, tile_y * DUST_TEXTURE_SIZE
    for y in 0..<DUST_TEXTURE_SIZE {
        for x in 0..<DUST_TEXTURE_SIZE {
            coverage := 0
            for sample_y in 0..<DUST_HYPOCYCLOID_SUPERSAMPLE_GRID {
                for sample_x in 0..<DUST_HYPOCYCLOID_SUPERSAMPLE_GRID {
                    point := Vector2{
                        (f32(x) + (f32(sample_x) + 0.5) /
                            DUST_HYPOCYCLOID_SUPERSAMPLE_GRID - center) / center,
                        (f32(y) + (f32(sample_y) + 0.5) /
                            DUST_HYPOCYCLOID_SUPERSAMPLE_GRID - center) / center}
                    if point_in_polygon(point, points[:count]) {coverage += 1}
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
    if len(pixels) != DUST_ATLAS_PIXEL_BYTES {return false}
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
    if allocation_error != nil {return false}
    if !build_native_dust_atlas(pixels) {return false}
    candidate := native.sdl_sampled_texture_create(
        platform, DUST_ATLAS_SIZE, DUST_ATLAS_SIZE)
    if !native.sampled_texture_is_valid(candidate) {return false}
    if !native.texture_operation_enqueue_upload(
        &runtime^.texture_operations, {
            kind = .Create, texture = candidate, format = .Rgba8,
            source = pixels, identity = 1, generation = 1,
        }) ||
        !native.sdl_draw_submit_texture_operations(platform, runtime) {
        native.sdl_sampled_texture_release(platform, &candidate)
        return false
    }
    runtime^.dust_atlas = candidate
    return true
}

// encode_low_particles compacts low dust and emits one ordered custom draw.
encode_low_particles :: proc(
    ps: ^Particle_System, state: ^Euclid_General_State,
    encoder: ^native.Draw_Encoder, texture: rawptr) {
    projected_count := view_core.iso_to_cartesian_components_batch_selected({
        ps.low_particles.pos_x[:ps^.use_max_dust_particles],
        ps.low_particles.pos_y[:ps^.use_max_dust_particles],
        ps.low_particles.pos_z[:ps^.use_max_dust_particles],
        ps.low_particle_screens[:], state^.iso_scale^},
        state^.ui_runtime.use_simd_batch_projection)
    count := 0
    for screen, index in ps.low_particle_screens[:projected_count] {
        if !ps.low_particles.alive[index] {continue}
        t := math.clamp(
            ps.low_particles.age[index] / ps.low_particles.life[index], 0, 1)
        particle_color := ps.low_particles.color[index]
        encoder^.dust_instances[count] = {
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

// encode_mid_particles appends atlas-textured ember quads in source order.
encode_mid_particles :: proc(
    ps: ^Particle_System, state: ^Euclid_General_State,
    encoder: ^native.Draw_Encoder, texture: rawptr) {
    screens: [MAX_PARTICLES]Vector2
    projected_count := view_core.iso_to_cartesian_components_batch_selected({
        ps.particles.pos_x[:], ps.particles.pos_y[:], ps.particles.pos_z[:],
        screens[:], state^.iso_scale^}, state^.ui_runtime.use_simd_batch_projection)
    count := 0
    for screen, index in screens[:projected_count] {
        if !ps.particles.alive[index] {continue}
        t := math.clamp(ps.particles.age[index] / ps.particles.life[index], 0, 1)
        particle_color := ps.particles.color[index]
        white_mix := math.lerp(ps.particles.ember_white_at_birth[index], 0, t)
        tint := color.Color_RGBA8{u8(math.clamp(math.lerp(f32(particle_color.r), 255,
            white_mix), 0, 255)), u8(math.clamp(math.lerp(
            f32(particle_color.g), 255, white_mix), 0, 255)),
            u8(math.clamp(math.lerp(f32(particle_color.b), 255, white_mix), 0, 255)),
            u8(math.clamp((1 - t) * 255, 0, 255))}
        diameter := max(ps.particles.size[index] * 2, 1)
        if native.draw_encoder_texture_quad(encoder,
            {screen.x - diameter * 0.5, screen.y - diameter * 0.5,
                diameter, diameter}, {0, 0, 1.0 / DUST_ATLAS_COLUMNS,
                1.0 / DUST_ATLAS_ROWS}, tint, {texture, .Linear}) {count += 1}
    }
    ps.last_render_mid = count
}

// encode_high_particles appends lit one-pixel flickers in source order.
encode_high_particles :: proc(
    ps: ^Particle_System, state: ^Euclid_General_State,
    encoder: ^native.Draw_Encoder) {
    screens: [MAX_PARTICLES]Vector2
    projected_count := view_core.iso_to_cartesian_components_batch_selected({
        ps.high_particles.pos_x[:], ps.high_particles.pos_y[:],
        ps.high_particles.pos_z[:], screens[:], state^.iso_scale^},
        state^.ui_runtime.use_simd_batch_projection)
    count := 0
    for screen, index in screens[:projected_count] {
        if !ps.high_particles.alive[index] {continue}
        count += 1
        if ps.high_particles.lit_frames[index] > 0 {
            _ = native.draw_encoder_rectangle(
                encoder, {screen.x, screen.y, 1, 1}, {255, 255, 255, 255})
        }
    }
    ps.last_render_high = count
}
