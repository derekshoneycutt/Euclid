package view

// We draw the basic surface and all the shapes and tools here

// Only the tools are drawn with shaders. Everything else is the ordinary 2D tools,
// drawn with an isometric projection

import "../kine"
import "../core"
import "../files"
import view_core "core"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

CIRCLE_ARC_SEGMENTS :: 96

COMPASS_TOPCIRCLE_SEGMENTS :: 30
COMPASS_TOPCIRCLE_VECTORS :: COMPASS_TOPCIRCLE_SEGMENTS + 1
COMPASS_TOPCIRCLE_RADIUS :: 0.25
COMPASS_HINGE_CROSS_EPSILON :: 0.0001
COMPASS_DEPTH_TIE_EPSILON :: 0.0001

SHADOW_MIN_THICKNESS :: 0.5
SHADOW_ALPHA_BASE :: 90
SHADOW_ALPHA_MIN :: 35
SHADOW_ALPHA_HEIGHT_SCALE :: 35.0
SHADOW_EPSILON_LZ :: 0.0001

STROKE3D_AMBIENT :: 0.28
STROKE3D_DIFFUSE :: 1.05
STROKE3D_SPECULAR_STRENGTH :: 0.26
STROKE3D_SPECULAR_POWER :: 18.0

LABEL_DECORATION_STROKE_SCALE :: 0.14
LABEL_DECORATION_WIDTH_SCALE :: 0.72
LABEL_DECORATION_HEIGHT_SCALE :: 0.5
LABEL_DECORATION_PRIME_SIZE_SCALE :: 1
LABEL_DECORATION_PRIME_X_OFFSET_SCALE :: 0.72
LABEL_DECORATION_PRIME_Y_OFFSET_SCALE :: 0.30


//   Initialize stroke3d shader handles and uniform locations from packaged assets.
//
// Parameters:
//   - state: Global app state that stores shader handles and uniform locations.
//
// Returns:
//   - none.
init_stroke3d_shader :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d

    vertex_path := files.packaged_asset_path("shaders/stroke3d.vs", context.temp_allocator)
    fragment_path := files.packaged_asset_path("shaders/stroke3d.fs", context.temp_allocator)
    if len(vertex_path) == 0 || len(fragment_path) == 0 {
        fmt.println("stroke3d shader paths could not be resolved from assets.pkg; pen/compass 3D shading disabled")
        s^.ready = false
        return
    }

    vertex_cstr := strings.clone_to_cstring(vertex_path, context.temp_allocator)
    fragment_cstr := strings.clone_to_cstring(fragment_path, context.temp_allocator)

    if !rl.FileExists(vertex_cstr) || !rl.FileExists(fragment_cstr) {
        fmt.println("stroke3d shader files not found; pen/compass 3D shading disabled")
        fmt.println("stroke3d expected paths: vs=", vertex_path, " fs=", fragment_path)
        s^.ready = false
        return
    }

    s^.shader = rl.LoadShader(vertex_cstr, fragment_cstr)
    if s^.shader.id == 0 {
        fmt.println("stroke3d shader failed to load; pen/compass 3D shading disabled")
        s^.ready = false
        return
    }

    s^.loc_light_dir = rl.GetShaderLocation(s^.shader, "uLightDirView")
    s^.loc_ambient = rl.GetShaderLocation(s^.shader, "uAmbient")
    s^.loc_diffuse = rl.GetShaderLocation(s^.shader, "uDiffuse")
    s^.loc_specular_strength = rl.GetShaderLocation(s^.shader, "uSpecularStrength")
    s^.loc_specular_power = rl.GetShaderLocation(s^.shader, "uSpecularPower")
    s^.loc_p0 = rl.GetShaderLocation(s^.shader, "uP0")
    s^.loc_p1 = rl.GetShaderLocation(s^.shader, "uP1")
    s^.loc_radius = rl.GetShaderLocation(s^.shader, "uRadius")
    s^.loc_viewport_height = rl.GetShaderLocation(s^.shader, "uViewportHeight")

    if s^.loc_p0 < 0 || s^.loc_p1 < 0 || s^.loc_radius < 0 || s^.loc_viewport_height < 0 {
        fmt.println("stroke3d shader missing required uniforms; pen/compass 3D shading disabled")
        fmt.println("stroke3d uniform locations p0=", s^.loc_p0, " p1=", s^.loc_p1,
            " radius=", s^.loc_radius, " viewportHeight=", s^.loc_viewport_height)
        rl.UnloadShader(s^.shader)
        s^.ready = false
        return
    }

    s^.ready = true
}

//   Unload stroke3d shader resources and mark shader state as unavailable.
//
// Parameters:
//   - state: Global app state containing stroke3d shader state.
//
// Returns:
//   - none.
shutdown_stroke3d_shader :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d

    if !s^.ready {
        return
    }

    rl.UnloadShader(s^.shader)
    s^.ready = false
}

//   Render the base isometric drawing plane and its border triangles.
//
// Parameters:
//   - state: Global app state providing surface geometry and iso projection scale.
//
// Returns:
//   - none.
draw_drawing_surface :: proc(state: ^Euclid_General_State) {
    room := state^.draw_surface

    surface_zeros : Vector3 = room^.zeros + { room.edge_size, room.edge_size, 0 }
    surface_right_up : Vector3 = room^.right_up + { -room.edge_size, room.edge_size, 0 }
    surface_left_down : Vector3 = room^.left_down + { room.edge_size, -room.edge_size, 0 }
    surface_right_down : Vector3 = room^.right_down + { -room.edge_size, -room.edge_size, 0 }

    world_points := [8]Vector3{
        room.zeros,
        room.right_up,
        room.left_down,
        room.right_down,
        surface_zeros,
        surface_right_up,
        surface_left_down,
        surface_right_down,
    }
    xs, ys, zs: [8]f32
    projected: [8]Vector2
    _ = project_iso_points_batch_with_components(
        state,
        world_points[:],
        xs[:],
        ys[:],
        zs[:],
        projected[:])

    rl.DrawTriangle(projected[0], projected[1], projected[2], room.edge_color)
    rl.DrawTriangle(projected[3], projected[2], projected[1], room.edge_color)
    rl.DrawTriangle(projected[4], projected[5], projected[6], room.color)
    rl.DrawTriangle(projected[7], projected[6], projected[5], room.color)
}

//   Render cached low-layer geometry items (labels, primitives, and polygons).
//
// Parameters:
//   - state: Global app state containing the draw cache to render.
//
// Returns:
//   - none.
draw_kine_points_low_cached :: proc(state: ^Euclid_General_State) {
    for i in 0..<state^.point_system^.draw_cache.item_count {
        item := &state^.point_system^.draw_cache.items[i]
        switch &item_typed in item {
        case core.Kine_Label_Draw:
            draw_cached_label(state, &item_typed)
        case core.Kine_Point_Draw:
            draw_cached_point(state, &item_typed)
        case core.Kine_Line_Draw:
            draw_cached_line(state, &item_typed)
        case core.Kine_Circle_Draw:
            draw_cached_circle(state, &item_typed)
        case core.Kine_Filled_Circle_Draw:
            draw_cached_filledcircle(state, &item_typed)
        case core.Kine_Polygon_Draw:
            draw_cached_polygon(state, &item_typed)
        case:
            continue
        }
    }
}

//   Render cached high-layer tool visuals and active markers with stroke3d mode.
//
// Parameters:
//   - state: Global app state containing pen/compass draw-cache entries.
//
// Returns:
//   - none.
draw_kine_points_high_cached :: proc(state: ^Euclid_General_State) {
    if state^.point_system^.draw_cache.draw_pen {
        draw_cached_pen_active_dot(state, &state^.point_system^.draw_cache.pen)
    }
    if state^.point_system^.draw_cache.draw_compass {
        draw_cached_compass_active_dot(state, &state^.point_system^.draw_cache.compass)
    }

    begin_stroke3d_mode(state)

    if state^.point_system^.draw_cache.draw_pen {
        draw_cached_pen(state, &state^.point_system^.draw_cache.pen)
    }
    if state^.point_system^.draw_cache.draw_compass {
        draw_cached_compass(state, &state^.point_system^.draw_cache.compass)
    }

    end_stroke3d_mode(state)
}

//   Render cached shadow overlays for pen and compass tool geometry.
//
// Parameters:
//   - state: Global app state containing tool shadow draw-cache entries.
//
// Returns:
//   - none.
draw_kine_points_shadows_cached :: proc(state: ^Euclid_General_State) {
    if state^.point_system^.draw_cache.draw_pen {
        draw_cached_pen_shadow(state, &state^.point_system^.draw_cache.pen)
    }
    if state^.point_system^.draw_cache.draw_compass {
        draw_cached_compass_shadow(state, &state^.point_system^.draw_cache.compass)
    }
}






//   Set a float uniform on the stroke3d shader when location is valid.
set_stroke3d_uniform_float :: #force_inline proc(state: ^Euclid_General_State, location: i32, value: f32) {
    if location < 0 {
        return
    }
    local_value := value
    rl.SetShaderValue(state^.stroke_3d.shader, location, &local_value, .FLOAT)
}


//   Set a vec2 uniform on the stroke3d shader when location is valid.
set_stroke3d_uniform_vec2 :: #force_inline proc(state: ^Euclid_General_State, location: i32, value: Vector2) {
    if location < 0 {
        return
    }
    vec_data := [2]f32{value.x, value.y}
    rl.SetShaderValue(state^.stroke_3d.shader, location, &vec_data[0], .VEC2)
}


//   Compute render-to-screen scale factors for shader-space thickness correction.
get_stroke3d_render_scale :: #force_inline proc() -> Vector2 {
    screen_w := f32(rl.GetScreenWidth())
    screen_h := f32(rl.GetScreenHeight())
    render_w := f32(rl.GetRenderWidth())
    render_h := f32(rl.GetRenderHeight())

    sx := f32(1.0)
    sy := f32(1.0)

    if screen_w > 0 && render_w > 0 {
        sx = render_w / screen_w
    }
    if screen_h > 0 && render_h > 0 {
        sy = render_h / screen_h
    }

    return Vector2{sx, sy}
}


//   Update stroke3d segment uniforms for endpoints and stroke radius.
set_stroke3d_segment :: #force_inline proc(state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32) {
    s := &state^.stroke_3d
    scale := get_stroke3d_render_scale()
    p0Scaled := Vector2{p0.x * scale.x, p0.y * scale.y}
    p1Scaled := Vector2{p1.x * scale.x, p1.y * scale.y}
    avg_scale := (scale.x + scale.y) * 0.5

    set_stroke3d_uniform_vec2(state, s^.loc_p0, p0Scaled)
    set_stroke3d_uniform_vec2(state, s^.loc_p1, p1Scaled)
    set_stroke3d_uniform_float(state, s^.loc_radius, thickness * 0.5 * avg_scale)
}


//   Draw one segment with stroke3d lighting when available, else standard line draw.
draw_stroke3d_segment :: #force_inline proc(state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32, color: rl.Color) {
    s := &state^.stroke_3d
    if s^.ready {
        rlgl.DrawRenderBatchActive()
        set_stroke3d_segment(state, p0, p1, thickness)
    }
    rl.DrawLineEx(p0, p1, thickness, color)
}


//   Decide if joint1->pivot should be drawn last to preserve hinge-side layering.
//
// Notes:
//   - Uses projected hinge winding as primary rule.
//   - Falls back to world-depth ordering near collinear poses.
compass_draw_joint1_leg_last :: #force_inline proc(comp: ^kine.Kine_Compass_Draw, c0, c1, c2: Vector2) -> bool {
    v01 := c0 - c1
    v21 := c2 - c1
    hinge_cross := v01.x * v21.y - v01.y * v21.x

    if math.abs(hinge_cross) > COMPASS_HINGE_CROSS_EPSILON {
        return hinge_cross > 0
    }

    mid1 := (comp^.joint1 + comp^.pivot) * 0.5
    mid2 := (comp^.joint2 + comp^.pivot) * 0.5
    depth1 := mid1.x + mid1.y - mid1.z
    depth2 := mid2.x + mid2.y - mid2.z

    if depth1 > depth2 + COMPASS_DEPTH_TIE_EPSILON {
        return true
    }
    if depth2 > depth1 + COMPASS_DEPTH_TIE_EPSILON {
        return false
    }

    return comp^.active_child == 1
}


//   Bind stroke3d shader and upload per-frame lighting/render uniforms.
//
// Notes:
//   - Must be paired with end_stroke3d_mode in the same draw pass.
begin_stroke3d_mode :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d

    if !s^.ready {
        return
    }

    light := -state^.iso_scale^.main_light_dir
    light = linalg.normalize(light)

    light_dir_data := [3]f32{light.x, light.y, light.z}
    if s^.loc_light_dir >= 0 {
        rl.SetShaderValue(s^.shader, s^.loc_light_dir, &light_dir_data[0], .VEC3)
    }

    set_stroke3d_uniform_float(state, s^.loc_ambient, STROKE3D_AMBIENT)
    set_stroke3d_uniform_float(state, s^.loc_diffuse, STROKE3D_DIFFUSE)
    set_stroke3d_uniform_float(state, s^.loc_specular_strength, STROKE3D_SPECULAR_STRENGTH)
    set_stroke3d_uniform_float(state, s^.loc_specular_power, STROKE3D_SPECULAR_POWER)
    set_stroke3d_uniform_float(state, s^.loc_viewport_height, f32(rl.GetRenderHeight()))

    rl.BeginShaderMode(s^.shader)
}


//   Flush pending batch and unbind stroke3d shader mode.
//
// Notes:
//   - Completes the begin_stroke3d_mode/end_stroke3d_mode pair.
end_stroke3d_mode :: proc(state: ^Euclid_General_State) {
    if !state^.stroke_3d.ready {
        return
    }
    rlgl.DrawRenderBatchActive()
    rl.EndShaderMode()
}

//   Compute positive angular sweep between start and end angles.
compute_sweep_delta :: proc(start_theta, end_theta: f32) -> f32 {
    start_n := start_theta
    if start_n < 0 {
        start_n += 2.0 * math.PI
    }
    end_n := end_theta
    if end_n < 0 {
        end_n += 2.0 * math.PI
    }

    delta := end_n - start_n
    if delta < 0 {
        delta += 2.0 * math.PI
    }
    return delta
}


//   Compute shadow alpha attenuation from average object height.
shadow_alpha_from_height :: proc(avg_height: f32) -> u8 {
    atten := f32(SHADOW_ALPHA_BASE) - avg_height * SHADOW_ALPHA_HEIGHT_SCALE
    atten = math.clamp(atten, f32(SHADOW_ALPHA_MIN), f32(SHADOW_ALPHA_BASE))
    return u8(atten)
}

//   Build a shadow color using computed alpha attenuation.
make_shadow_color :: proc(source: rl.Color, avg_height: f32) -> rl.Color {
    _ = source
    a := shadow_alpha_from_height(avg_height)
    return rl.Color{0, 0, 0, a}
}

//   Project a 3D point onto the floor plane using light direction.
project_to_floor_shadow :: proc(p: Vector3, scale: Iso_Scale) -> Vector3 {
    if !scale.use_directional_shadow {
        return {p.x, p.y, 0}
    }

    l := scale.main_light_dir
    if math.abs(l.z) < SHADOW_EPSILON_LZ {
        return {p.x, p.y, 0}
    }

    t := -p.z / l.z
    return p + l * t
}

//   Project a floor-shadow point into 2D screen coordinates.
shadow_to_screen :: proc(p: Vector3, state: ^Euclid_General_State) -> Vector2 {
    p_shadow := project_to_floor_shadow(p, state^.iso_scale^)
    return view_core.iso_to_cartesian(p_shadow, state^.iso_scale^)
}

//   Batch-project world points by first decomposing into x/y/z SoA component slices.
project_iso_points_batch_with_components :: proc(
    state: ^Euclid_General_State,
    world_points: []Vector3,
    xs, ys, zs: []f32,
    out: []Vector2) -> int {
    count := len(world_points)
    if len(xs) < count {
        count = len(xs)
    }
    if len(ys) < count {
        count = len(ys)
    }
    if len(zs) < count {
        count = len(zs)
    }
    if len(out) < count {
        count = len(out)
    }

    for i in 0..<count {
        p := world_points[i]
        xs[i] = p.x
        ys[i] = p.y
        zs[i] = p.z
    }

    return view_core.iso_to_cartesian_components_batch_selected(
        xs[:count],
        ys[:count],
        zs[:count],
        out[:count],
        state^.iso_scale^,
        state^.ui_runtime.use_simd_batch_projection)
}




//   Render one cached label draw item.
draw_cached_label :: proc(state: ^Euclid_General_State, p: ^kine.Kine_Label_Draw) {
    c := view_core.iso_to_cartesian(p^.point1, state^.iso_scale^)
    rl.DrawTextCodepoint(state^.font, p^.label, c, p^.brush_size, p^.color)

    width := p^.brush_size * LABEL_DECORATION_WIDTH_SCALE
    height := p^.brush_size * LABEL_DECORATION_HEIGHT_SCALE

    switch p^.decoration_kind {
    case .None:
    case .Prime:
        prime_pos := rl.Vector2{
            c.x + width * LABEL_DECORATION_PRIME_X_OFFSET_SCALE,
            c.y - height * LABEL_DECORATION_PRIME_Y_OFFSET_SCALE,
        }
        prime_size := math.max(16.0, p^.brush_size * LABEL_DECORATION_PRIME_SIZE_SCALE)
        rl.DrawTextCodepoint(state^.font, '\'', prime_pos, prime_size, p^.color)
    case .Hat:
        //TODO: Do this
    case .Bar:
        //TODO: Do this
    }
}


//   Render one cached point draw item.
draw_cached_point :: proc(state: ^Euclid_General_State, p: ^kine.Kine_Point_Draw) {
    c := view_core.iso_to_cartesian(p^.point1, state^.iso_scale^)
    rl.DrawCircleV(c, p^.brush_size, p^.color)
}


//   Render one cached line draw item.
draw_cached_line :: proc(state: ^Euclid_General_State, l: ^kine.Kine_Line_Draw) {
    c0 := view_core.iso_to_cartesian(l^.point1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(l^.point2, state^.iso_scale^)
    rl.DrawLineEx(c0, c1, l^.brush_size, l^.color)
}


//   Render one cached circle/arc draw item.
draw_cached_circle :: proc(state: ^Euclid_General_State, c: ^kine.Kine_Circle_Draw) {
    start := c^.start
    finish := c^.end
    center := c^.center

    start_vec := start - center
    end_vec := finish - center

    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta) + c^.offset

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    arc_world[0] = start
    seg_count := f32(CIRCLE_ARC_SEGMENTS)

    for i in 1..=CIRCLE_ARC_SEGMENTS {
        t := f32(i) / seg_count
        theta := start_theta + sweep_delta * t
        radius := math.lerp(start_radius, end_radius, t)

        curr_world := Vector3{
            center.x + f32(math.cos(theta)) * radius,
            center.y + f32(math.sin(theta)) * radius,
            center.z,
        }

        arc_world[i] = curr_world
    }

    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    arc_screen: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(
        state,
        arc_world[:],
        xs[:],
        ys[:],
        zs[:],
        arc_screen[:])

    for i in 1..=CIRCLE_ARC_SEGMENTS {
        rl.DrawLineEx(arc_screen[i - 1], arc_screen[i], c^.brush_size, c^.color)
    }
}

//   Render one cached filled-circle draw item.
draw_cached_filledcircle :: proc(state: ^Euclid_General_State, c: ^kine.Kine_Filled_Circle_Draw) {
    start := c^.start
    finish := c^.end
    center := c^.center
    isocenter := view_core.iso_to_cartesian(center, state^.iso_scale^)

    start_vec := start - center
    end_vec := finish - center

    start_radius := f32(math.sqrt(start_vec.x * start_vec.x + start_vec.y * start_vec.y))
    end_radius := f32(math.sqrt(end_vec.x * end_vec.x + end_vec.y * end_vec.y))

    start_theta := f32(math.atan2(start_vec.y, start_vec.x))
    end_theta := f32(math.atan2(end_vec.y, end_vec.x))
    sweep_delta := compute_sweep_delta(start_theta, end_theta) + c^.offset

    points: [CIRCLE_ARC_SEGMENTS + 2]rl.Vector2
    points[0] = isocenter

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    arc_world[0] = start

    seg_count := f32(CIRCLE_ARC_SEGMENTS)
    for i in 1..=CIRCLE_ARC_SEGMENTS {
        t := f32(i) / seg_count
        theta := start_theta + sweep_delta * t
        radius := math.lerp(start_radius, end_radius, t)

        arc_world[i] = Vector3{
            center.x + f32(math.cos(theta)) * radius,
            center.y + f32(math.sin(theta)) * radius,
            center.z,
        }
    }

    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    arc_screen: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(
        state,
        arc_world[:],
        xs[:],
        ys[:],
        zs[:],
        arc_screen[:])
    for i in 0..<len(arc_screen) {
        points[i + 1] = arc_screen[i]
    }

    rl.DrawTriangleFan(&points[0], len(points), c^.color)
}


//   Batch-project cached polygon vertices into screen space.
project_cached_polygon_vertices :: #force_inline proc(
    state: ^Euclid_General_State,
    poly: ^kine.Kine_Polygon_Draw,
    projected: []Vector2) -> bool {

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    xs, ys, zs: [core.MAX_DRAW_CACHE_POLYGON_VERTICES]f32

    _ = project_iso_points_batch_with_components(
        state,
        vertices,
        xs[:],
        ys[:],
        zs[:],
        projected)

    return true
}

//   Draw all cached triangles for a polygon using projected vertex positions.
draw_cached_polygon_triangles :: #force_inline proc(
    cache: ^core.Kine_Draw_Cache,
    poly: ^kine.Kine_Polygon_Draw,
    projected: []Vector2) {

    triangles := cache^.polygon_triangles[poly^.first_triangle:poly^.first_triangle + poly^.triangle_count]
    for tri in triangles {
        i0 := tri.a - poly^.first_vertex
        i1 := tri.b - poly^.first_vertex
        i2 := tri.c - poly^.first_vertex
        if i0 < 0 || i0 >= poly^.vertex_count {
            continue
        }
        if i1 < 0 || i1 >= poly^.vertex_count {
            continue
        }
        if i2 < 0 || i2 >= poly^.vertex_count {
            continue
        }

        rl.DrawTriangle(projected[i0], projected[i1], projected[i2], poly^.color)
    }
}

//   Render one cached polygon draw item.
draw_cached_polygon :: proc(state: ^Euclid_General_State, poly: ^kine.Kine_Polygon_Draw) {
    if poly^.vertex_count < 3 || poly^.triangle_count <= 0 {
        return
    }

    projected: [core.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    if !project_cached_polygon_vertices(state, poly, projected[:]) {
        return
    }

    cache := &state^.point_system^.draw_cache
    draw_cached_polygon_triangles(cache, poly, projected[:])
}


//   Render one cached pen tool draw item.
draw_cached_pen :: proc(state: ^Euclid_General_State, pen: ^kine.Kine_Pen_Draw) {
    c0 := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)

    draw_stroke3d_segment(state, c0, c1, pen^.brush_size, pen^.color)
}


//   Render active-end indicator for cached pen tool.
draw_cached_pen_active_dot :: proc(state: ^Euclid_General_State, pen: ^kine.Kine_Pen_Draw) {
    c0 := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)

    if pen^.active_child == 1 {
        active := pen^.color
        if pen^.has_active_color {
            active = pen^.active_color
        }
        rl.DrawCircleV(c0, pen^.brush_size, active)
    } else if pen^.active_child == 2 {
        active := pen^.color
        if pen^.has_active_color {
            active = pen^.active_color
        }
        rl.DrawCircleV(c1, pen^.brush_size, active)
    }
}


//   Render compass top arc segment that lies outside the swing angle.
draw_outside_arc_compass_cached :: proc(
    p0, p1, p2: Vector3,
    state: ^Euclid_General_State,
    brush_size: f32,
    color: rl.Color) {
    a := p0 - p1
    b := p2 - p1

    a_len := linalg.length(a)
    b_len := linalg.length(b)
    if a_len <= 0.00001 || b_len <= 0.00001 {
        return
    }

    an := a / a_len
    bn := b / b_len

    n := linalg.cross(an, bn)
    n_len := linalg.length(n)
    if n_len <= 0.00001 {
        return
    }
    n /= n_len

    dot_ab := math.clamp(linalg.dot(an, bn), -1, 1)
    cross_ab := linalg.cross(an, bn)
    theta_short := math.atan2(linalg.dot(n, cross_ab), dot_ab)

    sign := f32(1.0)
    if theta_short < 0 {
        sign = -1.0
    }
    theta_out := theta_short - 2.0 * math.PI * sign

    u := an
    v := linalg.normalize(linalg.cross(n, u))

    radius := math.min(a_len, b_len) * COMPASS_TOPCIRCLE_RADIUS
    if radius <= 0 {
        return
    }

    step := theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)

    prev3d := p1 + u * radius
    prev := view_core.iso_to_cartesian(prev3d, state^.iso_scale^)

    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := u * math.cos(t) + v * math.sin(t)
        curr3d := p1 + dir * radius
        curr := view_core.iso_to_cartesian(curr3d, state^.iso_scale^)

        draw_stroke3d_segment(state, prev, curr, brush_size, color)
        prev = curr
    }
}


//   Render one cached compass tool draw item.
draw_cached_compass :: proc(state: ^Euclid_General_State, comp: ^kine.Kine_Compass_Draw) {
    c0 := view_core.iso_to_cartesian(comp^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(comp^.pivot, state^.iso_scale^)
    c2 := view_core.iso_to_cartesian(comp^.joint2, state^.iso_scale^)

    draw_joint1_last := compass_draw_joint1_leg_last(comp, c0, c1, c2)
    if draw_joint1_last {
        draw_stroke3d_segment(state, c1, c2, comp^.brush_size, comp^.color)
        draw_stroke3d_segment(state, c0, c1, comp^.brush_size, comp^.color)
    } else {
        draw_stroke3d_segment(state, c0, c1, comp^.brush_size, comp^.color)
        draw_stroke3d_segment(state, c1, c2, comp^.brush_size, comp^.color)
    }

    draw_outside_arc_compass_cached(
        comp^.joint1,
        comp^.pivot,
        comp^.joint2,
        state,
        comp^.brush_size,
        comp^.color,
    )
}


//   Render active-end indicator for cached compass tool.
draw_cached_compass_active_dot :: proc(state: ^Euclid_General_State, comp: ^kine.Kine_Compass_Draw) {
    c0 := view_core.iso_to_cartesian(comp^.joint1, state^.iso_scale^)
    c2 := view_core.iso_to_cartesian(comp^.joint2, state^.iso_scale^)

    if comp^.active_child == 1 {
        active := comp^.color
        if comp^.has_active_color {
            active = comp^.active_color
        }
        rl.DrawCircleV(c0, comp^.brush_size, active)
    } else if comp^.active_child == 3 {
        active := comp^.color
        if comp^.has_active_color {
            active = comp^.active_color
        }
        rl.DrawCircleV(c2, comp^.brush_size, active)
    }
}


//   Render floor shadow for cached pen tool geometry.
draw_cached_pen_shadow :: proc(state: ^Euclid_General_State, pen: ^kine.Kine_Pen_Draw) {
    s0 := shadow_to_screen(pen^.joint1, state)
    s1 := shadow_to_screen(pen^.joint2, state)

    avg_height := (pen^.joint1.z + pen^.joint2.z) * 0.5
    shadow_color := make_shadow_color(pen^.color, avg_height)
    thickness := math.max(pen^.brush_size * 0.8, SHADOW_MIN_THICKNESS)

    rl.DrawLineEx(s0, s1, thickness, shadow_color)
}


//   Render floor-shadow arc segment outside the compass swing angle.
draw_outside_arc_compass_shadow_cached :: proc(
    p0, p1, p2: Vector3,
    state: ^Euclid_General_State,
    brush_size: f32,
    color: rl.Color) {
    if brush_size <= 0 {
        return
    }

    a := p0 - p1
    b := p2 - p1

    a_len := linalg.length(a)
    b_len := linalg.length(b)
    if a_len <= 0.00001 || b_len <= 0.00001 {
        return
    }

    an := a / a_len
    bn := b / b_len

    n := linalg.cross(an, bn)
    n_len := linalg.length(n)
    if n_len <= 0.00001 {
        return
    }
    n /= n_len

    dot_ab := math.clamp(linalg.dot(an, bn), -1, 1)
    cross_ab := linalg.cross(an, bn)
    theta_short := math.atan2(linalg.dot(n, cross_ab), dot_ab)

    sign := f32(1.0)
    if theta_short < 0 {
        sign = -1.0
    }
    theta_out := theta_short - 2.0 * math.PI * sign

    u := an
    v := linalg.normalize(linalg.cross(n, u))

    radius := math.min(a_len, b_len) * COMPASS_TOPCIRCLE_RADIUS
    if radius <= 0 {
        return
    }

    step := theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)

    prev3d := p1 + u * radius
    prev := shadow_to_screen(prev3d, state)

    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := u * math.cos(t) + v * math.sin(t)
        curr3d := p1 + dir * radius
        curr := shadow_to_screen(curr3d, state)

        rl.DrawLineEx(prev, curr, brush_size, color)
        prev = curr
    }
}


//   Render floor shadow for cached compass tool geometry.
draw_cached_compass_shadow :: proc(state: ^Euclid_General_State, comp: ^kine.Kine_Compass_Draw) {
    s0 := shadow_to_screen(comp^.joint1, state)
    s1 := shadow_to_screen(comp^.pivot, state)
    s2 := shadow_to_screen(comp^.joint2, state)

    avg_height := (comp^.joint1.z + comp^.pivot.z + comp^.joint2.z) / 3.0
    shadow_color := make_shadow_color(comp^.color, avg_height)
    thickness := math.max(comp^.brush_size * 0.8, SHADOW_MIN_THICKNESS)

    draw_joint1_last := compass_draw_joint1_leg_last(comp, s0, s1, s2)
    if draw_joint1_last {
        rl.DrawLineEx(s1, s2, thickness, shadow_color)
        rl.DrawLineEx(s0, s1, thickness, shadow_color)
    } else {
        rl.DrawLineEx(s0, s1, thickness, shadow_color)
        rl.DrawLineEx(s1, s2, thickness, shadow_color)
    }

    draw_outside_arc_compass_shadow_cached(
        comp^.joint1,
        comp^.pivot,
        comp^.joint2,
        state,
        thickness,
        shadow_color,
    )
}
