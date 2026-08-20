package view

// Just drawing whatever particles are currently alive. Pretty simple, tbh

import "../core"
import "../files"
import view_core "core"

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

MAX_PARTICLES :: core.MAX_PARTICLES
MAX_LOW_PARTICLES :: core.MAX_LOW_PARTICLES
DUST_TEXTURE_SIZE :: 64
DUST_ATLAS_COLUMNS :: 3
DUST_ATLAS_ROWS :: 3
DUST_ATLAS_VARIANT_COUNT :: core.DUST_ATLAS_VARIANT_COUNT
DUST_ATLAS_SIZE :: DUST_TEXTURE_SIZE * DUST_ATLAS_COLUMNS
DUST_TEXTURE_SOFT_EDGE_START :: 0.58
DUST_VERTEX_POSITION_LOCATION :: 0
DUST_VERTEX_TEXCOORD_LOCATION :: 1
DUST_INSTANCE_GEOMETRY_LOCATION :: 2
DUST_INSTANCE_COLOR_LOCATION :: 3
DUST_INSTANCE_VARIANT_LOCATION :: 4
DUST_HYPOCYCLOID_SAMPLE_COUNT :: 128

//   Render alive low-layer particles and update low-layer render counters.
//
// Parameters:
//   - ps: Particle system containing low-layer particles.
//   - state: Global app state providing isometric projection scale.
//
// Returns:
//   - none.
render_low_particles :: proc(ps: ^Particle_System, state: ^Euclid_General_State) {
    ensure_dust_texture(state)
    if !state^.dust_render.ready {
        return
    }

    if state^.ui_runtime.use_gpu_dust_instancing {
        ensure_dust_instancing(state)
    }

    iso_scale := state^.iso_scale^

    projected_count := view_core.iso_to_cartesian_components_batch_selected(
        {ps.low_particles.pos_x[:ps^.use_max_dust_particles],
            ps.low_particles.pos_y[:ps^.use_max_dust_particles],
            ps.low_particles.pos_z[:ps^.use_max_dust_particles],
            ps.low_particle_screens[:], iso_scale},
        state^.ui_runtime.use_simd_batch_projection)

    count_rendered := stage_low_particle_instances(
        ps, state, ps.low_particle_screens[:projected_count])
    if state^.ui_runtime.use_gpu_dust_instancing &&
        state^.dust_render.instancing_ready &&
        draw_low_particle_instances(state, count_rendered) {
        ps.last_render_low = count_rendered
        return
    }

    draw_low_particles_immediate(ps, state, ps.low_particle_screens[:projected_count])
    ps.last_render_low = count_rendered
}

//   Compact live low particles into fixed GPU instance staging arrays.
stage_low_particle_instances :: proc(
    ps: ^Particle_System,
    state: ^Euclid_General_State,
    screens: []Vector2) -> int {
    dust_render := &state^.dust_render
    count := 0

    for screen, i in screens {
        if !ps.low_particles.alive[i] {
            continue
        }

        t := math.clamp(ps.low_particles.age[i] / ps.low_particles.life[i], 0.0, 1.0)
        alpha := 1.0 - t
        dust_color := ps.low_particles.color[i]
        diameter := max(ps.low_particles.size[i] * 2.0, 1.0)

        dust_render^.instance_geometry[count] = {screen.x, screen.y, diameter}
        dust_render^.instance_colors[count] = {
            f32(dust_color.r) / 255.0,
            f32(dust_color.g) / 255.0,
            f32(dust_color.b) / 255.0,
            math.clamp(alpha * 210.0 / 255.0, 0.0, 1.0),
        }
        dust_render^.instance_sprite_indices[count] =
            f32(ps.low_particles.dust_sprite_index[i])
        count += 1
    }

    return count
}

//   Upload staged instance geometry, color, and sprite-index buffers to the GPU.
//
// Returns:
//   - ok: true when the VAO was enabled for drawing.
dust_upload_instance_buffers :: proc(
    dust_render: ^core.Dust_Render_State, count: int) -> bool {

    geometry_size := count * size_of(dust_render^.instance_geometry[0])
    color_size := count * size_of(dust_render^.instance_colors[0])

    rlgl.DrawRenderBatchActive()
    rlgl.UpdateVertexBuffer(
        dust_render^.instance_geometry_vbo_id,
        &dust_render^.instance_geometry[0][0],
        c.int(geometry_size),
        0)
    rlgl.UpdateVertexBuffer(
        dust_render^.instance_color_vbo_id,
        &dust_render^.instance_colors[0][0],
        c.int(color_size),
        0)
    rlgl.UpdateVertexBuffer(
        dust_render^.instance_sprite_index_vbo_id,
        &dust_render^.instance_sprite_indices[0],
        c.int(count * size_of(dust_render^.instance_sprite_indices[0])),
        0)

    return rlgl.EnableVertexArray(dust_render^.vao_id)
}

//   Bind shader, viewport, and texture, then issue the instanced draw call.
dust_issue_instanced_draw :: proc(
    dust_render: ^core.Dust_Render_State, count: int) {

    viewport := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
    texture_slot := i32(0)
    rlgl.EnableShader(dust_render^.shader.id)
    rlgl.SetUniform(
        dust_render^.viewport_location,
        &viewport[0],
        c.int(rl.ShaderUniformDataType.VEC2),
        1)
    rlgl.SetUniform(
        dust_render^.texture_location,
        &texture_slot,
        c.int(rl.ShaderUniformDataType.SAMPLER2D),
        1)
    rlgl.ActiveTextureSlot(0)
    rlgl.EnableTexture(dust_render^.texture.id)
    rlgl.DrawVertexArrayInstanced(0, 6, c.int(count))
    rlgl.DisableTexture()
    rlgl.DisableShader()
    rlgl.DisableVertexArray()
}

//   Draw staged dust instances in one GPU draw call.
draw_low_particle_instances :: proc(state: ^Euclid_General_State, count: int) -> bool {
    if count == 0 {
        return true
    }
    dust_render := &state^.dust_render
    if !dust_upload_instance_buffers(dust_render, count) {
        return false
    }
    dust_issue_instanced_draw(dust_render, count)
    return true
}

//   Render staged low particles through the original immediate-mode path.
draw_low_particles_immediate :: proc(
    ps: ^Particle_System,
    state: ^Euclid_General_State,
    screens: []Vector2) {
    dust_render := &state^.dust_render
    rlgl.SetTexture(dust_render^.texture.id)
    rlgl.Begin(rlgl.QUADS)
    tile_u := 1.0 / f32(DUST_ATLAS_COLUMNS)
    tile_v := 1.0 / f32(DUST_ATLAS_ROWS)

    for screen, i in screens {
        if !ps.low_particles.alive[i] {
            continue
        }

        t := math.clamp(ps.low_particles.age[i] / ps.low_particles.life[i], 0.0, 1.0)
        alpha := 1.0 - t
        a := u8(math.clamp(alpha * 210.0, 0.0, 255.0))

        dust_color := ps.low_particles.color[i]

        diameter := ps.low_particles.size[i] * 2.0
        if diameter < 1.0 {
            diameter = 1.0
        }
        radius := diameter * 0.5

        rlgl.Color4ub(dust_color.r, dust_color.g, dust_color.b, a)

        rlgl.TexCoord2f(0.0, 0.0)
        rlgl.Vertex2f(screen.x - radius, screen.y - radius)
        rlgl.TexCoord2f(0.0, tile_v)
        rlgl.Vertex2f(screen.x - radius, screen.y + radius)
        rlgl.TexCoord2f(tile_u, tile_v)
        rlgl.Vertex2f(screen.x + radius, screen.y + radius)
        rlgl.TexCoord2f(tile_u, 0.0)
        rlgl.Vertex2f(screen.x + radius, screen.y - radius)
    }

    rlgl.End()
    rlgl.SetTexture(0)
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
    ensure_dust_texture(state)
    if !state^.dust_render.ready {
        return
    }

    iso_scale := state^.iso_scale^

    screens: [MAX_PARTICLES]Vector2
    projected_count := view_core.iso_to_cartesian_components_batch_selected(
        {ps.particles.pos_x[:], ps.particles.pos_y[:], ps.particles.pos_z[:],
            screens[:], iso_scale},
        state^.ui_runtime.use_simd_batch_projection)

    count_rendered : int = 0
    for i in 0..<projected_count {
        if !ps.particles.alive[i] {
            continue
        }
        count_rendered += 1

        screen := screens[i]
        render_particle_ember_mid_index(state, ps, i, screen)
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

    screens: [MAX_PARTICLES]Vector2
    projected_count := view_core.iso_to_cartesian_components_batch_selected(
        {ps.high_particles.pos_x[:], ps.high_particles.pos_y[:],
            ps.high_particles.pos_z[:], screens[:], iso_scale},
        state^.ui_runtime.use_simd_batch_projection)

    count_rendered : int = 0
    for i in 0..<projected_count {
        if !ps.high_particles.alive[i] {
            continue
        }
        count_rendered += 1

        screen := screens[i]

        render_particle_flicker_high_index(ps, i, screen)
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
    dust_render := &state^.dust_render
    release_dust_instancing_resources(dust_render)
    dust_render^.instancing_attempted = false

    if dust_render^.ready {
        rl.UnloadTexture(dust_render^.texture)
        dust_render^.ready = false
    }
}

//   Release all complete or partially initialized dust instancing resources.
release_dust_instancing_resources :: proc(dust_render: ^core.Dust_Render_State) {
    if dust_render^.instance_color_vbo_id != 0 {
        rlgl.UnloadVertexBuffer(dust_render^.instance_color_vbo_id)
        dust_render^.instance_color_vbo_id = 0
    }
    if dust_render^.instance_sprite_index_vbo_id != 0 {
        rlgl.UnloadVertexBuffer(dust_render^.instance_sprite_index_vbo_id)
        dust_render^.instance_sprite_index_vbo_id = 0
    }
    if dust_render^.instance_geometry_vbo_id != 0 {
        rlgl.UnloadVertexBuffer(dust_render^.instance_geometry_vbo_id)
        dust_render^.instance_geometry_vbo_id = 0
    }
    if dust_render^.quad_texcoords_vbo_id != 0 {
        rlgl.UnloadVertexBuffer(dust_render^.quad_texcoords_vbo_id)
        dust_render^.quad_texcoords_vbo_id = 0
    }
    if dust_render^.quad_positions_vbo_id != 0 {
        rlgl.UnloadVertexBuffer(dust_render^.quad_positions_vbo_id)
        dust_render^.quad_positions_vbo_id = 0
    }
    if dust_render^.vao_id != 0 {
        rlgl.UnloadVertexArray(dust_render^.vao_id)
        dust_render^.vao_id = 0
    }
    if dust_render^.shader.id != 0 {
        rl.UnloadShader(dust_render^.shader)
        dust_render^.shader = {}
    }
    dust_render^.instancing_ready = false
}

//   Lazily create shader and buffer resources for screen-space dust instancing.
ensure_dust_instancing :: proc(state: ^Euclid_General_State) {
    dust_render := &state^.dust_render
    if dust_render^.instancing_ready || dust_render^.instancing_attempted {
        return
    }
    dust_render^.instancing_attempted = true

    if rlgl.GetVersion() < .OPENGL_33 {
        fmt.println("dust instancing requires OpenGL 3.3; using immediate rendering")
        return
    }

    if !load_dust_instancing_shader(dust_render) {
        release_dust_instancing_resources(dust_render)
        return
    }
    if !load_dust_instancing_buffers(dust_render) {
        release_dust_instancing_resources(dust_render)
        return
    }

    dust_render^.instancing_ready = true
}

//   Load the packaged dust shader and resolve its required uniforms.
load_dust_instancing_shader :: proc(dust_render: ^core.Dust_Render_State) -> bool {
    vertex_path :=
        files.packaged_asset_path("shaders/dust_instanced.vs", context.temp_allocator)
    fragment_path :=
        files.packaged_asset_path("shaders/dust_instanced.fs", context.temp_allocator)
    if len(vertex_path) == 0 || len(fragment_path) == 0 {
        fmt.println("dust shader paths could not be resolved; using immediate rendering")
        return false
    }

    vertex_cstr := strings.clone_to_cstring(vertex_path, context.temp_allocator)
    fragment_cstr := strings.clone_to_cstring(fragment_path, context.temp_allocator)
    dust_render^.shader = rl.LoadShader(vertex_cstr, fragment_cstr)
    if dust_render^.shader.id == 0 {
        fmt.println("dust shader failed to load; using immediate rendering")
        return false
    }

    dust_render^.viewport_location =
        rl.GetShaderLocation(dust_render^.shader, "uViewport")
    dust_render^.texture_location = rl.GetShaderLocation(dust_render^.shader, "texture0")
    if dust_render^.viewport_location < 0 || dust_render^.texture_location < 0 {
        fmt.println("dust shader is missing required uniforms; using immediate rendering")
        return false
    }
    return true
}

//   Load the two static unit-quad vertex buffers (positions and texcoords).
//
// Returns:
//   - ok: true when both buffers loaded and their attributes were enabled.
dust_load_quad_buffers :: proc(dust_render: ^core.Dust_Render_State) -> bool {
    // Two triangles covering the unit quad each dust instance is stamped onto.
    quad_positions := [12]f32{
        -0.5, -0.5,
        -0.5,  0.5,
         0.5,  0.5,
        -0.5, -0.5,
         0.5,  0.5,
         0.5, -0.5,
    }
    quad_texcoords := [12]f32{
        0.0, 0.0,
        0.0, 1.0,
        1.0, 1.0,
        0.0, 0.0,
        1.0, 1.0,
        1.0, 0.0,
    }

    dust_render^.quad_positions_vbo_id = rlgl.LoadVertexBuffer(
        &quad_positions[0], c.int(size_of(quad_positions)), false)
    rlgl.SetVertexAttribute(DUST_VERTEX_POSITION_LOCATION, 2, rlgl.FLOAT, false, 0, 0)
    rlgl.EnableVertexAttribute(DUST_VERTEX_POSITION_LOCATION)

    dust_render^.quad_texcoords_vbo_id = rlgl.LoadVertexBuffer(
        &quad_texcoords[0], c.int(size_of(quad_texcoords)), false)
    rlgl.SetVertexAttribute(DUST_VERTEX_TEXCOORD_LOCATION, 2, rlgl.FLOAT, false, 0, 0)
    rlgl.EnableVertexAttribute(DUST_VERTEX_TEXCOORD_LOCATION)

    return dust_render^.quad_positions_vbo_id != 0 &&
        dust_render^.quad_texcoords_vbo_id != 0
}

//   Load one dynamic per-instance buffer with a divisor of 1.
//
// Parameters:
//   - data: Source buffer base address.
//   - byte_size: Total byte size of the buffer.
//   - location: Vertex attribute location.
//   - components: Float components per attribute element.
//   - out_id: Destination for the created buffer id.
//
// Returns:
//   - ok: true when the buffer id is non-zero.
dust_load_instance_buffer :: proc(
    data: rawptr, byte_size: int, location, components: u32, out_id: ^u32) -> bool {
    out_id^ = rlgl.LoadVertexBuffer(data, c.int(byte_size), true)
    rlgl.SetVertexAttribute(location, i32(components), rlgl.FLOAT, false, 0, 0)
    rlgl.EnableVertexAttribute(location)
    rlgl.SetVertexAttributeDivisor(location, 1)
    return out_id^ != 0
}

//   Create the static quad and reusable dynamic instance buffers.
load_dust_instancing_buffers :: proc(dust_render: ^core.Dust_Render_State) -> bool {
    dust_render^.vao_id = rlgl.LoadVertexArray()
    if dust_render^.vao_id == 0 || !rlgl.EnableVertexArray(dust_render^.vao_id) {
        fmt.println("dust vertex array could not be created; using immediate rendering")
        return false
    }

    quad_ok := dust_load_quad_buffers(dust_render)
    geometry_ok := dust_load_instance_buffer(
        &dust_render^.instance_geometry[0][0],
        size_of(dust_render^.instance_geometry),
        DUST_INSTANCE_GEOMETRY_LOCATION, 3,
        &dust_render^.instance_geometry_vbo_id)
    color_ok := dust_load_instance_buffer(
        &dust_render^.instance_colors[0][0],
        size_of(dust_render^.instance_colors),
        DUST_INSTANCE_COLOR_LOCATION, 4,
        &dust_render^.instance_color_vbo_id)
    sprite_ok := dust_load_instance_buffer(
        &dust_render^.instance_sprite_indices[0],
        size_of(dust_render^.instance_sprite_indices),
        DUST_INSTANCE_VARIANT_LOCATION, 1,
        &dust_render^.instance_sprite_index_vbo_id)

    rlgl.DisableVertexArray()
    return quad_ok && geometry_ok && color_ok && sprite_ok
}

//   Build the dust texture atlas used by the instanced low-particle renderer.
build_dust_texture_atlas :: proc() -> rl.Image {
    image := rl.GenImageColor(
        DUST_ATLAS_SIZE,
        DUST_ATLAS_SIZE,
        rl.Color{255, 255, 255, 0})

    draw_dust_circle_tile(&image, 0, 0)
    for variant in 1..<DUST_ATLAS_VARIANT_COUNT {
        draw_dust_hypocycloid_tile(&image, variant % DUST_ATLAS_COLUMNS,
            variant / DUST_ATLAS_COLUMNS, variant + 2)
    }

    return image
}

//   Draw the soft circle tile into one atlas cell.
draw_dust_circle_tile :: proc(image: ^rl.Image, tile_x, tile_y: int) {
    origin_x := tile_x * DUST_TEXTURE_SIZE
    origin_y := tile_y * DUST_TEXTURE_SIZE
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
            rl.ImageDrawPixel(image, i32(origin_x + x), i32(origin_y + y),
                rl.Color{255, 255, 255, a})
        }
    }
}
// Draw one hypocycloid tile into the atlas using polygon coverage.
draw_dust_hypocycloid_tile :: proc(image: ^rl.Image, tile_x, tile_y, k: int) {
    origin_x := tile_x * DUST_TEXTURE_SIZE
    origin_y := tile_y * DUST_TEXTURE_SIZE

    points: [DUST_HYPOCYCLOID_SAMPLE_COUNT]Vector2
    point_count := sample_dust_hypocycloid_points(points[:], k)
    if point_count <= 0 {
        return
    }
    samples := points[:point_count]

    subpixels := [4]Vector2{
        {0.25, 0.25},
        {0.75, 0.25},
        {0.25, 0.75},
        {0.75, 0.75},
    }

    center := (f32(DUST_TEXTURE_SIZE) - 1) * 0.5
    inv_center := 1.0 / center

    for y in 0..<DUST_TEXTURE_SIZE {
        for x in 0..<DUST_TEXTURE_SIZE {
            coverage : f32 = 0.0

            for sample_i in 0..<4 {
                sample_x := (f32(x) + subpixels[sample_i].x - center) * inv_center
                sample_y := (f32(y) + subpixels[sample_i].y - center) * inv_center

                if point_in_polygon(Vector2{sample_x, sample_y}, samples) {
                    coverage += 1.0
                }
            }

            if coverage <= 0.0 {
                continue
            }

            a := u8(math.clamp(coverage * 63.75, 0.0, 255.0)) 
            rl.ImageDrawPixel(image, i32(origin_x + x), i32(origin_y + y),
                rl.Color{255, 255, 255, a})
        }
    }
}

// Test whether a point lies inside a polygon via ray casting (Jordan Curve Theorem).
point_in_polygon :: proc(point: Vector2, polygon: []Vector2) -> bool {
    inside := false
    j := len(polygon) - 1
    
    for i in 0..<len(polygon) {
        pi := polygon[i]
        pj := polygon[j]
        
        if (pi.y > point.y) != (pj.y > point.y) {
            if point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside = !inside
            }
        }
        j = i
    }
    return inside
}

//   Sample a normalized hypocycloid curve into a fixed point buffer.
sample_dust_hypocycloid_points :: proc(
    points: []Vector2,
    k: int) -> int {
    
    if k < 3 || len(points) < DUST_HYPOCYCLOID_SAMPLE_COUNT {
        return 0
    }

    r_minus_r := f32(k - 1)
    freq := f64(k - 1) 

    max_radius := f32(0.0)

    for i in 0..<DUST_HYPOCYCLOID_SAMPLE_COUNT {
        theta := 2.0 * math.PI * f64(i) / f64(DUST_HYPOCYCLOID_SAMPLE_COUNT)
        
        x := r_minus_r * f32(math.cos(theta)) + 1.0 * f32(math.cos(freq * theta))
        y := r_minus_r * f32(math.sin(theta)) - 1.0 * f32(math.sin(freq * theta))
        
        radius := math.sqrt_f32(x * x + y * y)
        if radius > max_radius {
            max_radius = radius
        }
        points[i] = Vector2{x, y}
    }

    if max_radius <= 0.0 {
        return 0
    }

    scale := 0.82 / max_radius
    for i in 0..<DUST_HYPOCYCLOID_SAMPLE_COUNT {
        points[i].x *= scale
        points[i].y *= scale
    }

    return DUST_HYPOCYCLOID_SAMPLE_COUNT
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

    image := build_dust_texture_atlas()
    defer rl.UnloadImage(image)

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




//   Render one mid-layer ember particle with lifetime-based alpha fade.
render_particle_ember_mid_index :: proc(
    state: ^Euclid_General_State,
    ps: ^Particle_System,
    i: int,
    screen: Vector2) {
    t := math.clamp(ps.particles.age[i] / ps.particles.life[i], 0.0, 1.0)
    particle_color := ps.particles.color[i]
    white_mix := math.lerp(ps.particles.ember_white_at_birth[i], 0.0, t)

    r := u8(math.clamp(math.lerp(f32(particle_color.r), 255.0, white_mix), 0.0, 255.0))
    g := u8(math.clamp(math.lerp(f32(particle_color.g), 255.0, white_mix), 0.0, 255.0))
    b := u8(math.clamp(math.lerp(f32(particle_color.b), 255.0, white_mix), 0.0, 255.0))

    a := u8(math.clamp((1.0 - t) * 255.0, 0.0, 255.0))

    col := rl.Color{r, g, b, a}
    if !draw_particle_quad(state, screen, ps.particles.size[i] * 2.0, col) {
        rl.DrawCircleV(screen, ps.particles.size[i], col)
    }
}

//   Render one high-layer flicker particle only while its lit window is active.
render_particle_flicker_high_index :: proc(
    ps: ^Particle_System, i: int, screen: Vector2) {
    if ps.high_particles.lit_frames[i] > 0 {
        rl.DrawPixelV(screen, rl.WHITE)
    }
}
