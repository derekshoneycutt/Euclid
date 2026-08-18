package view

// We draw the basic surface and all the shapes and tools here

// Only the tools are drawn with shaders. Everything else is the ordinary 2D tools,
// drawn with an isometric projection

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
Z_SPLIT_EPSILON :: 0.0001
Z_SPLIT_ALPHA_FACTOR :: 0.25
TOOL_POLYGON_CLIP_EPSILON :: 0.0001
TOOL_POLYGON_SEGMENT_EPSILON :: 0.00001
PEN_BOTTOM_CLIP_BIAS :: Vector3{-0.01, -0.01, 0.01}
PEN_CLIP_FRONT_DIRECTION :: Vector3{-1.0, -1.0, 1.0}

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
LABEL_DECORATION_DOUBLEPRIME_SPACING_SCALE :: 0.44


Pen_Polygon_Crossing :: struct {
    pen_index: int,
    polygon_index: int,
    pen: core.Shapes_Pen_Draw,
    polygon: core.Shapes_Polygon_Draw,
    back0: Vector3,
    back1: Vector3,
    front0: Vector3,
    front1: Vector3,
    has_back: bool,
    has_front: bool,
}


//   Initialize stroke3d shader handles and uniform locations from packaged assets.
//
// Parameters:
//   - state: Global app state that stores shader handles and uniform locations.
//
// Returns:
//   - none.
init_stroke3d_shader :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d

    vertex_path :=
        files.packaged_asset_path("shaders/stroke3d.vs", context.temp_allocator)
    fragment_path :=
        files.packaged_asset_path("shaders/stroke3d.fs", context.temp_allocator)
    if len(vertex_path) == 0 || len(fragment_path) == 0 {
        fmt.println(
            "stroke3d shader paths could not be resolved from assets.pkg; pen/compass 3D shading disabled")
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
        fmt.println(
            "stroke3d shader missing required uniforms; pen/compass 3D shading disabled")
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
    surface_right_down : Vector3 =
        room^.right_down + { -room.edge_size, -room.edge_size, 0 }

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
draw_shapes_points_low_cached :: proc(state: ^Euclid_General_State) {
    for i in 0..<state^.point_system^.draw_cache.item_count {
        draw_cached_item_low(state, &state^.point_system^.draw_cache.items[i])
    }
}

//   Render cached higher-layer items after shadows and particles.
//
// Parameters:
//   - state: Global app state containing the draw cache to render.
//
// Returns:
//   - none.
draw_shapes_points_high_merged_cached :: proc(state: ^Euclid_General_State) {
    crossing := Pen_Polygon_Crossing {
        pen_index = -1,
        polygon_index = -1,
    }
    has_crossing := find_pen_polygon_crossing(state, &crossing)

    for i in 0..<state^.point_system^.draw_cache.item_count {
        if has_crossing {
            if i == crossing.polygon_index {
                draw_pen_polygon_crossing(state, &crossing)
                continue
            }
            if i == crossing.pen_index {
                continue
            }
        }

        draw_cached_item_high_merged(state, &state^.point_system^.draw_cache.items[i])
    }
}

//   Render cached shadow overlays for pen and compass tool geometry.
//
// Parameters:
//   - state: Global app state containing tool shadow draw-cache entries.
//
// Returns:
//   - none.
draw_shapes_points_shadows_cached :: proc(state: ^Euclid_General_State) {
    if state^.point_system^.draw_cache.draw_pen {
        draw_cached_pen_shadow(state, &state^.point_system^.draw_cache.pen)
    }
    if state^.point_system^.draw_cache.draw_compass {
        draw_cached_compass_shadow(state, &state^.point_system^.draw_cache.compass)
    }
}

//   Render floor shadows for cached low-layer geometry when any defining point is above the surface.
//
// Notes:
//   - Flat and below-surface geometry draws no shadow.
//   - Labels are intentionally excluded from the shape-shadow pass.
draw_shapes_shapes_shadows_cached :: proc(state: ^Euclid_General_State) {
    for i in 0..<state^.point_system^.draw_cache.item_count {
        draw_cached_item_shadow(state, &state^.point_system^.draw_cache.items[i])
    }
}

//   Draw one cached item only when it belongs to the lower geometry layer.
draw_cached_item_low :: proc(state: ^Euclid_General_State,
    item: ^core.Shapes_Draw_Cache_Item) {
    switch &item_typed in item {
    case core.Shapes_Label_Draw:
        draw_cached_label(state, &item_typed)
    case core.Shapes_Point_Draw:
        draw_cached_point_low(state, &item_typed)
    case core.Shapes_Line_Draw:
        draw_cached_line_low(state, &item_typed)
    case core.Shapes_Circle_Draw:
        draw_cached_circle_low(state, &item_typed)
    case core.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_low(state, &item_typed)
    case core.Shapes_Polygon_Draw:
        draw_cached_polygon_low(state, &item_typed)
    case core.Shapes_Pen_Draw,
        core.Shapes_Compass_Draw:
    }
}

//   Draw one cached item only when it belongs to the merged higher layer.
draw_cached_item_high_merged :: proc(state: ^Euclid_General_State,
    item: ^core.Shapes_Draw_Cache_Item) {
    switch &item_typed in item {
    case core.Shapes_Label_Draw:
    case core.Shapes_Point_Draw:
        draw_cached_point_high(state, &item_typed)
    case core.Shapes_Line_Draw:
        draw_cached_line_high(state, &item_typed)
    case core.Shapes_Circle_Draw:
        draw_cached_circle_high(state, &item_typed)
    case core.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_high(state, &item_typed)
    case core.Shapes_Polygon_Draw:
        draw_cached_polygon_high(state, &item_typed)
    case core.Shapes_Pen_Draw:
        draw_cached_pen_full(state, &item_typed)
    case core.Shapes_Compass_Draw:
        draw_cached_compass_full(state, &item_typed)
    }
}

//   Draw one cached item's floor shadow when that item can cast one.
draw_cached_item_shadow :: proc(state: ^Euclid_General_State,
    item: ^core.Shapes_Draw_Cache_Item) {
    switch &item_typed in item {
    case core.Shapes_Label_Draw,
        core.Shapes_Pen_Draw,
        core.Shapes_Compass_Draw:
    case core.Shapes_Point_Draw:
        draw_cached_point_shadow(state, &item_typed)
    case core.Shapes_Line_Draw:
        draw_cached_line_shadow(state, &item_typed)
    case core.Shapes_Circle_Draw:
        draw_cached_circle_shadow(state, &item_typed)
    case core.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_shadow(state, &item_typed)
    case core.Shapes_Polygon_Draw:
        draw_cached_polygon_shadow(state, &item_typed)
    }
}

//   Return true when a cached point draw item belongs to the elevated layer.
draw_cached_point_is_elevated :: #force_inline proc(p: ^core.Shapes_Point_Draw) -> bool {
    return shadow_point_is_elevated(p^.point1)
}

//   Return true when a cached circle draw item belongs to the elevated layer.
draw_cached_circle_is_elevated :: #force_inline proc(
    c: ^core.Shapes_Circle_Draw) -> bool {
    circle_points := [3]Vector3{c^.center, c^.start, c^.end}
    return has_any_elevated_shadow_point(circle_points[:])
}

//   Return true when a cached filled-circle draw item belongs to the elevated layer.
draw_cached_filledcircle_is_elevated :: #force_inline proc(
    c: ^core.Shapes_Filled_Circle_Draw) -> bool {
    circle_points := [3]Vector3{c^.center, c^.start, c^.end}
    return has_any_elevated_shadow_point(circle_points[:])
}

//   Return true when any cached polygon vertex belongs to the elevated layer.
draw_cached_polygon_is_elevated :: #force_inline proc(
    state: ^Euclid_General_State,
    poly: ^core.Shapes_Polygon_Draw) -> bool {

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    return has_any_elevated_shadow_point(vertices)
}

//   Draw one cached point only when it belongs to the lower geometry layer.
draw_cached_point_low :: #force_inline proc(
    state: ^Euclid_General_State, p: ^core.Shapes_Point_Draw) {
    if !draw_cached_point_is_elevated(p) {
        draw_cached_point(state, p)
    }
}

//   Draw one cached point only when it belongs to the merged higher layer.
draw_cached_point_high :: #force_inline proc(
    state: ^Euclid_General_State, p: ^core.Shapes_Point_Draw) {
    if draw_cached_point_is_elevated(p) {
        draw_cached_point(state, p)
    }
}

//   Draw one cached line only when it belongs to the lower geometry layer.
draw_cached_line_low :: #force_inline proc(
    state: ^Euclid_General_State, l: ^core.Shapes_Line_Draw) {
    draw_cached_line(state, l, false)
}

//   Draw one cached line only when it belongs to the merged higher layer.
draw_cached_line_high :: #force_inline proc(
    state: ^Euclid_General_State, l: ^core.Shapes_Line_Draw) {
    draw_cached_line(state, l, true)
}

//   Draw one cached circle only when it belongs to the lower geometry layer.
draw_cached_circle_low :: #force_inline proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Circle_Draw) {
    if !draw_cached_circle_is_elevated(c) {
        draw_cached_circle(state, c)
    }
}

//   Draw one cached circle only when it belongs to the merged higher layer.
draw_cached_circle_high :: #force_inline proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Circle_Draw) {
    if draw_cached_circle_is_elevated(c) {
        draw_cached_circle(state, c)
    }
}

//   Draw one cached filled circle only when it belongs to the lower geometry layer.
draw_cached_filledcircle_low :: #force_inline proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Filled_Circle_Draw) {
    if !draw_cached_filledcircle_is_elevated(c) {
        draw_cached_filledcircle(state, c)
    }
}

//   Draw one cached filled circle only when it belongs to the merged higher layer.
draw_cached_filledcircle_high :: #force_inline proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Filled_Circle_Draw) {
    if draw_cached_filledcircle_is_elevated(c) {
        draw_cached_filledcircle(state, c)
    }
}

//   Draw one cached polygon only when it belongs to the lower geometry layer.
draw_cached_polygon_low :: #force_inline proc(
    state: ^Euclid_General_State, poly: ^core.Shapes_Polygon_Draw) {
    if !draw_cached_polygon_is_elevated(state, poly) {
        draw_cached_polygon(state, poly)
    }
}

//   Draw one cached polygon only when it belongs to the merged higher layer.
draw_cached_polygon_high :: #force_inline proc(
    state: ^Euclid_General_State, poly: ^core.Shapes_Polygon_Draw) {
    if draw_cached_polygon_is_elevated(state, poly) {
        draw_cached_polygon(state, poly)
    }
}

//   Render one full cached pen item for the merged higher layer.
draw_cached_pen_full :: proc(
    state: ^Euclid_General_State, pen: ^core.Shapes_Pen_Draw) {
    draw_cached_pen_active_dot(state, pen)
    begin_stroke3d_mode(state)
    draw_cached_pen(state, pen)
    end_stroke3d_mode(state)
}

//   Render one full cached compass item for the merged higher layer.
draw_cached_compass_full :: proc(
    state: ^Euclid_General_State, comp: ^core.Shapes_Compass_Draw) {
    draw_cached_compass_active_dot(state, comp)
    begin_stroke3d_mode(state)
    draw_cached_compass(state, comp)
    end_stroke3d_mode(state)
}






//   Set a float uniform on the stroke3d shader when location is valid.
set_stroke3d_uniform_float :: #force_inline proc(
    state: ^Euclid_General_State, location: i32, value: f32) {
    if location < 0 {
        return
    }
    local_value := value
    rl.SetShaderValue(state^.stroke_3d.shader, location, &local_value, .FLOAT)
}


//   Set a vec2 uniform on the stroke3d shader when location is valid.
set_stroke3d_uniform_vec2 :: #force_inline proc(
    state: ^Euclid_General_State, location: i32, value: Vector2) {
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
set_stroke3d_segment :: #force_inline proc(
    state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32) {
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
draw_stroke3d_segment :: #force_inline proc(
    state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32, color: rl.Color) {
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
compass_draw_joint1_leg_last :: #force_inline proc(
    comp: ^core.Shapes_Compass_Draw, c0, c1, c2: Vector2) -> bool {
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
    set_stroke3d_uniform_float(state,
        s^.loc_specular_strength, STROKE3D_SPECULAR_STRENGTH)
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

//   Return true when one point should cast a floor shadow.
shadow_point_is_elevated :: #force_inline proc(point: Vector3) -> bool {
    return point.z > 0
}

//   Return true when any cached point in one slice is above the drawing surface.
has_any_elevated_shadow_point :: #force_inline proc(points: []Vector3) -> bool {
    for point in points {
        if shadow_point_is_elevated(point) {
            return true
        }
    }
    return false
}

//   Classify one z value against the split plane using a symmetric epsilon dead-zone.
z_split_sign :: #force_inline proc(z: f32) -> int {
    if z > Z_SPLIT_EPSILON {
        return 1
    }
    if z < -Z_SPLIT_EPSILON {
        return -1
    }
    return 0
}

//   Return true when one point belongs to the selected z-halfspace.
z_split_point_in_halfspace :: #force_inline proc(
    point: Vector3, keep_above: bool) -> bool {
    sign := z_split_sign(point.z)
    if keep_above {
        return sign > 0
    }
    return sign <= 0
}

//   Compute one segment intersection point against the z=0 plane.
z_split_intersection_with_plane :: #force_inline proc(
    point0, point1: Vector3) -> Vector3 {
    dz := point1.z - point0.z
    if math.abs(dz) <= Z_SPLIT_EPSILON {
        return point0
    }

    t := -point0.z / dz
    t = math.clamp(t, 0, 1)
    return linalg.lerp(point0, point1, t)
}

//   Clip one segment against either z<=0 or z>0 halfspace.
z_split_clip_segment_halfspace :: #force_inline proc(
    point0, point1: Vector3,
    keep_above: bool,
    out0, out1: ^Vector3) -> bool {

    point0_in := z_split_point_in_halfspace(point0, keep_above)
    point1_in := z_split_point_in_halfspace(point1, keep_above)

    if point0_in && point1_in {
        out0^ = point0
        out1^ = point1
        return true
    }

    if !point0_in && !point1_in {
        return false
    }

    intersection := z_split_intersection_with_plane(point0, point1)
    if point0_in {
        out0^ = point0
        out1^ = intersection
    } else {
        out0^ = intersection
        out1^ = point1
    }

    return true
}

//   Apply 0.25x alpha attenuation for lower z-split fragments.
z_split_lower_fragment_color :: #force_inline proc(color: rl.Color) -> rl.Color {
    attenuated := u8(math.clamp(int(f32(color.a) * Z_SPLIT_ALPHA_FACTOR + 0.5), 0, 255))
    return rl.Color{color.r, color.g, color.b, attenuated}
}

//   Return true when one segment has enough length to render reliably.
segment_has_length :: #force_inline proc(point0, point1: Vector3) -> bool {
    delta := point1 - point0
    return linalg.dot(delta, delta) >
        TOOL_POLYGON_SEGMENT_EPSILON * TOOL_POLYGON_SEGMENT_EPSILON
}

//   Classify one plane distance with tool-front priority in near-equal cases.
tool_plane_side :: #force_inline proc(distance: f32) -> int {
    if distance > TOOL_POLYGON_CLIP_EPSILON {
        return 1
    }
    if distance < -TOOL_POLYGON_CLIP_EPSILON {
        return -1
    }
    return 1
}

//   Compute signed distance from one point to one plane.
plane_signed_distance :: #force_inline proc(
    point, plane_point, plane_normal: Vector3) -> f32 {
    return linalg.dot(plane_normal, point - plane_point)
}

//   Compute one segment/plane intersection point if the denominator is stable.
segment_plane_intersection :: proc(
    point0, point1: Vector3,
    plane_point, plane_normal: Vector3,
    out: ^Vector3) -> bool {

    direction := point1 - point0
    denom := linalg.dot(plane_normal, direction)
    if math.abs(denom) <= TOOL_POLYGON_SEGMENT_EPSILON {
        return false
    }

    numer := linalg.dot(plane_normal, plane_point-point0)
    t := numer / denom
    if t < 0 || t > 1 {
        return false
    }

    out^ = point0 + direction * t
    return true
}

//   Return true when one 3D point lies inside one triangle using barycentric weights.
point_in_triangle :: #force_inline proc(point, a, b, c: Vector3) -> bool {
    v0 := b - a
    v1 := c - a
    v2 := point - a

    d00 := linalg.dot(v0, v0)
    d01 := linalg.dot(v0, v1)
    d11 := linalg.dot(v1, v1)
    d20 := linalg.dot(v2, v0)
    d21 := linalg.dot(v2, v1)
    denom := d00 * d11 - d01 * d01
    if math.abs(denom) <= TOOL_POLYGON_SEGMENT_EPSILON {
        return false
    }

    inv := 1.0 / denom
    bary_v := (d11*d20 - d01*d21) * inv
    bary_w := (d00*d21 - d01*d20) * inv
    bary_u := 1.0 - bary_v - bary_w

    return bary_u >= -TOOL_POLYGON_CLIP_EPSILON &&
        bary_v >= -TOOL_POLYGON_CLIP_EPSILON &&
        bary_w >= -TOOL_POLYGON_CLIP_EPSILON
}

//   Resolve one stable polygon plane from cached polygon triangles.
polygon_plane :: proc(
    state: ^Euclid_General_State,
    polygon: ^core.Shapes_Polygon_Draw,
    plane_point, plane_normal: ^Vector3) -> bool {

    // #vet forgives(cyclomatic_complexity) — polygon plane-fit kernel.
    // The guards are triangle-index bounds and degenerate-normal rejection over the
    // triangle list; intrinsic to the geometry, not incidental branching.
    if polygon^.vertex_count < 3 || polygon^.triangle_count <= 0 {
        return false
    }

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[
        polygon^.first_vertex:polygon^.first_vertex + polygon^.vertex_count]
    triangles := cache^.polygon_triangles[
        polygon^.first_triangle:polygon^.first_triangle + polygon^.triangle_count]

    for tri in triangles {
        local_a := tri.a - polygon^.first_vertex
        local_b := tri.b - polygon^.first_vertex
        local_c := tri.c - polygon^.first_vertex
        if local_a < 0 || local_a >= polygon^.vertex_count {
            continue
        }
        if local_b < 0 || local_b >= polygon^.vertex_count {
            continue
        }
        if local_c < 0 || local_c >= polygon^.vertex_count {
            continue
        }

        a := vertices[local_a]
        b := vertices[local_b]
        c := vertices[local_c]
        normal := linalg.cross(b-a, c-a)
        if linalg.dot(normal, normal) <= TOOL_POLYGON_SEGMENT_EPSILON {
            continue
        }

        plane_point^ = a
        plane_normal^ = normal
        return true
    }

    return false
}

//   Return true when one point lies inside any cached triangle of one polygon.
point_inside_polygon :: proc(
    state: ^Euclid_General_State,
    polygon: ^core.Shapes_Polygon_Draw,
    point: Vector3) -> bool {

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[
        polygon^.first_vertex:polygon^.first_vertex + polygon^.vertex_count]
    triangles := cache^.polygon_triangles[
        polygon^.first_triangle:polygon^.first_triangle + polygon^.triangle_count]

    for tri in triangles {
        local_a := tri.a - polygon^.first_vertex
        local_b := tri.b - polygon^.first_vertex
        local_c := tri.c - polygon^.first_vertex
        if local_a < 0 || local_a >= polygon^.vertex_count {
            continue
        }
        if local_b < 0 || local_b >= polygon^.vertex_count {
            continue
        }
        if local_c < 0 || local_c >= polygon^.vertex_count {
            continue
        }

        if point_in_triangle(
            point, vertices[local_a], vertices[local_b], vertices[local_c]) {
            return true
        }
    }

    return false
}

//   Draw one world-space pen segment fragment with standard cached pen styling.
draw_pen_segment_fragment :: #force_inline proc(
    state: ^Euclid_General_State,
    pen: ^core.Shapes_Pen_Draw,
    point0, point1: Vector3) {

    c0 := view_core.iso_to_cartesian(point0, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(point1, state^.iso_scale^)
    draw_stroke3d_segment(state, c0, c1, pen^.brush_size, pen^.color)
}

//   Build one pen/polygon crossing event using z=0 clipping as stage one.
build_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    pen: ^core.Shapes_Pen_Draw,
    polygon: ^core.Shapes_Polygon_Draw,
    crossing: ^Pen_Polygon_Crossing) -> bool {

    // #vet forgives(cyclomatic_complexity) — pen/polygon clipping pipeline.
    // The branches are half-space clip, plane-side classification, and front/back
    // emission of a geometry crossing; each is a distinct geometric stage.
    stage0_start, stage0_end: Vector3
    if !z_split_clip_segment_halfspace(
        pen^.joint1,
        pen^.joint2,
        true,
        &stage0_start,
        &stage0_end) {
        return false
    }

    plane_point, plane_normal: Vector3
    if !polygon_plane(state, polygon, &plane_point, &plane_normal) {
        return false
    }

    // Keep front/back classification stable regardless of polygon triangle winding.
    if linalg.dot(plane_normal, PEN_CLIP_FRONT_DIRECTION) < 0 {
        plane_normal *= -1.0
    }

    clip_start := stage0_start
    clip_end := stage0_end
    if linalg.dot(stage0_start-pen^.joint1, stage0_start-pen^.joint1) <=
        linalg.dot(stage0_end-pen^.joint1, stage0_end-pen^.joint1) {
        clip_start += PEN_BOTTOM_CLIP_BIAS
    } else {
        clip_end += PEN_BOTTOM_CLIP_BIAS
    }

    raw_distance0 := plane_signed_distance(stage0_start, plane_point, plane_normal)
    raw_distance1 := plane_signed_distance(stage0_end, plane_point, plane_normal)
    distance0 := plane_signed_distance(clip_start, plane_point, plane_normal)
    distance1 := plane_signed_distance(clip_end, plane_point, plane_normal)
    side0 := tool_plane_side(distance0)
    side1 := tool_plane_side(distance1)
    on_plane0 := math.abs(raw_distance0) <= TOOL_POLYGON_CLIP_EPSILON
    on_plane1 := math.abs(raw_distance1) <= TOOL_POLYGON_CLIP_EPSILON

    crossing^.has_back = false
    crossing^.has_front = false

    if side0 == side1 {
        if !(on_plane0 || on_plane1) {
            return false
        }

        contact_point := stage0_start
        if !on_plane0 && on_plane1 {
            contact_point = stage0_end
        }
        if !point_inside_polygon(state, polygon, contact_point) {
            return false
        }

        if side0 > 0 {
            crossing^.front0 = stage0_start
            crossing^.front1 = stage0_end
            crossing^.has_front = segment_has_length(crossing^.front0, crossing^.front1)
            return crossing^.has_front
        }

        crossing^.back0 = stage0_start
        crossing^.back1 = stage0_end
        crossing^.has_back = segment_has_length(crossing^.back0, crossing^.back1)
        return crossing^.has_back
    }

    intersection := Vector3{}
    if !segment_plane_intersection(
        clip_start,
        clip_end,
        plane_point,
        plane_normal,
        &intersection) {
        return false
    }
    if !point_inside_polygon(state, polygon, intersection) {
        return false
    }

    clip_direction := clip_end - clip_start
    clip_len_sq := linalg.dot(clip_direction, clip_direction)
    if clip_len_sq <= TOOL_POLYGON_SEGMENT_EPSILON {
        return false
    }
    intersection_t := linalg.dot(intersection-clip_start, clip_direction) / clip_len_sq
    intersection_t = math.clamp(intersection_t, 0, 1)
    intersection_unbiased := linalg.lerp(stage0_start, stage0_end, intersection_t)

    if side0 < side1 {
        crossing^.back0 = stage0_start
        crossing^.back1 = intersection_unbiased
        crossing^.front0 = intersection_unbiased
        crossing^.front1 = stage0_end
    } else {
        crossing^.back0 = stage0_end
        crossing^.back1 = intersection_unbiased
        crossing^.front0 = intersection_unbiased
        crossing^.front1 = stage0_start
    }

    crossing^.has_back = segment_has_length(crossing^.back0, crossing^.back1)
    crossing^.has_front = segment_has_length(crossing^.front0, crossing^.front1)
    return crossing^.has_back || crossing^.has_front
}

//   Find one pen/polygon crossing pair in current high merged cache items.
find_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    out_crossing: ^Pen_Polygon_Crossing) -> bool {

    // #vet forgives(cyclomatic_complexity) — crossing-search driver.
    // The guards skip non-crossing candidate pairs over the merged draw cache;
    // load-bearing filtering, not incidental control flow.
    cache := &state^.point_system^.draw_cache
    pen_index := -1
    pen := core.Shapes_Pen_Draw {}

    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case core.Shapes_Pen_Draw:
            pen = item_typed
            pen_index = i
            break
        case core.Shapes_Label_Draw,
            core.Shapes_Point_Draw,
            core.Shapes_Line_Draw,
            core.Shapes_Circle_Draw,
            core.Shapes_Filled_Circle_Draw,
            core.Shapes_Polygon_Draw,
            core.Shapes_Compass_Draw:
        }
        if pen_index >= 0 {
            break
        }
    }
    if pen_index < 0 {
        return false
    }

    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case core.Shapes_Polygon_Draw:
            if !draw_cached_polygon_is_elevated(state, &item_typed) {
                continue
            }

            trial := Pen_Polygon_Crossing {}
            if !build_pen_polygon_crossing(state, &pen, &item_typed, &trial) {
                continue
            }

            trial.pen_index = pen_index
            trial.polygon_index = i
            trial.pen = pen
            trial.polygon = item_typed
            out_crossing^ = trial
            return true
        case core.Shapes_Label_Draw,
            core.Shapes_Point_Draw,
            core.Shapes_Line_Draw,
            core.Shapes_Circle_Draw,
            core.Shapes_Filled_Circle_Draw,
            core.Shapes_Pen_Draw,
            core.Shapes_Compass_Draw:
        }
    }

    return false
}

//   Draw interleaving for one crossing pen/polygon pair.
draw_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    crossing: ^Pen_Polygon_Crossing) {

    draw_cached_pen_active_dot(state, &crossing^.pen)

    begin_stroke3d_mode(state)
    if crossing^.has_back {
        draw_pen_segment_fragment(state, &crossing^.pen, crossing^.back0, crossing^.back1)
    }
    end_stroke3d_mode(state)

    draw_cached_polygon(state, &crossing^.polygon)

    begin_stroke3d_mode(state)
    if crossing^.has_front {
        draw_pen_segment_fragment(state, &crossing^.pen,
            crossing^.front0, crossing^.front1)
    }
    end_stroke3d_mode(state)
}

//   Compute average height across one point slice for shadow alpha attenuation.
average_shadow_height :: #force_inline proc(points: []Vector3) -> f32 {
    if len(points) <= 0 {
        return 0
    }

    total: f32 = 0
    for point in points {
        total += point.z
    }

    return total / f32(len(points))
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
draw_cached_label :: proc(state: ^Euclid_General_State, p: ^core.Shapes_Label_Draw) {
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
    case .Double_Prime:
        prime_pos := rl.Vector2{
            c.x + width * LABEL_DECORATION_PRIME_X_OFFSET_SCALE,
            c.y - height * LABEL_DECORATION_PRIME_Y_OFFSET_SCALE,
        }
        prime_size := math.max(16.0, p^.brush_size * LABEL_DECORATION_PRIME_SIZE_SCALE)
        second_prime_pos := rl.Vector2{
            prime_pos.x + prime_size * LABEL_DECORATION_DOUBLEPRIME_SPACING_SCALE,
            prime_pos.y,
        }
        rl.DrawTextCodepoint(state^.font, '\'', prime_pos, prime_size, p^.color)
        rl.DrawTextCodepoint(state^.font, '\'', second_prime_pos, prime_size, p^.color)
    case .Triple_Prime:
        prime_pos := rl.Vector2{
            c.x + width * LABEL_DECORATION_PRIME_X_OFFSET_SCALE,
            c.y - height * LABEL_DECORATION_PRIME_Y_OFFSET_SCALE,
        }
        prime_size := math.max(16.0, p^.brush_size * LABEL_DECORATION_PRIME_SIZE_SCALE)
        second_prime_pos := rl.Vector2{
            prime_pos.x + prime_size * LABEL_DECORATION_DOUBLEPRIME_SPACING_SCALE,
            prime_pos.y,
        }
        third_prime_pos := rl.Vector2{
            second_prime_pos.x + prime_size * LABEL_DECORATION_DOUBLEPRIME_SPACING_SCALE,
            second_prime_pos.y,
        }
        rl.DrawTextCodepoint(state^.font, '\'', prime_pos, prime_size, p^.color)
        rl.DrawTextCodepoint(state^.font, '\'', second_prime_pos, prime_size, p^.color)
        rl.DrawTextCodepoint(state^.font, '\'', third_prime_pos, prime_size, p^.color)
    case .Hat:
        //TODO: Do this
    case .Bar:
        //TODO: Do this
    }
}


//   Render one cached point floor shadow.
draw_cached_point_shadow :: proc(
    state: ^Euclid_General_State, p: ^core.Shapes_Point_Draw) {
    if !shadow_point_is_elevated(p^.point1) {
        return
    }

    shadow := shadow_to_screen(p^.point1, state)
    shadow_color := make_shadow_color(p^.color, p^.point1.z)
    rl.DrawCircleV(shadow, p^.brush_size, shadow_color)
}


//   Render one cached line floor shadow.
draw_cached_line_shadow :: proc(state: ^Euclid_General_State, l: ^core.Shapes_Line_Draw) {
    line_points := [2]Vector3{l^.point1, l^.point2}
    if !has_any_elevated_shadow_point(line_points[:]) {
        return
    }

    // Shadow pass keeps only the visible-above-plane fragment for split lines.
    clipped0 := Vector3{}
    clipped1 := Vector3{}
    if !z_split_clip_segment_halfspace(l^.point1, l^.point2, true, &clipped0, &clipped1) {
        return
    }

    s0 := shadow_to_screen(clipped0, state)
    s1 := shadow_to_screen(clipped1, state)
    clipped_points := [2]Vector3{clipped0, clipped1}
    avg_height := average_shadow_height(clipped_points[:])
    shadow_color := make_shadow_color(l^.color, avg_height)
    thickness := math.max(l^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    rl.DrawLineEx(s0, s1, thickness, shadow_color)
}


//   Render one cached circle/arc floor shadow.
draw_cached_circle_shadow :: proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Circle_Draw) {
    circle_points := [3]Vector3{c^.center, c^.start, c^.end}
    if !has_any_elevated_shadow_point(circle_points[:]) {
        return
    }

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
    thickness := math.max(c^.brush_size * 0.8, SHADOW_MIN_THICKNESS)

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

    for i in 1..=CIRCLE_ARC_SEGMENTS {
        clipped0 := Vector3{}
        clipped1 := Vector3{}
        if !z_split_clip_segment_halfspace(
            arc_world[i - 1],
            arc_world[i],
            true,
            &clipped0,
            &clipped1) {

            continue
        }

        s0 := shadow_to_screen(clipped0, state)
        s1 := shadow_to_screen(clipped1, state)
        clipped_points := [2]Vector3{clipped0, clipped1}
        clipped_avg_height := average_shadow_height(clipped_points[:])
        clipped_shadow_color := make_shadow_color(c^.color, clipped_avg_height)
        rl.DrawLineEx(s0, s1, thickness, clipped_shadow_color)
    }
}


//   Render one cached filled-circle floor shadow.
draw_cached_filledcircle_shadow :: proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Filled_Circle_Draw) {
    circle_points := [3]Vector3{c^.center, c^.start, c^.end}
    if !has_any_elevated_shadow_point(circle_points[:]) {
        return
    }

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
    avg_height := average_shadow_height(circle_points[:])
    shadow_color := make_shadow_color(c^.color, avg_height)

    points: [CIRCLE_ARC_SEGMENTS + 2]rl.Vector2
    points[0] = shadow_to_screen(center, state)

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

    for i in 0..<len(arc_world) {
        points[i + 1] = shadow_to_screen(arc_world[i], state)
    }

    rl.DrawTriangleFan(&points[0], len(points), shadow_color)
}


//   Render one cached point draw item.
draw_cached_point :: proc(state: ^Euclid_General_State, p: ^core.Shapes_Point_Draw) {
    c := view_core.iso_to_cartesian(p^.point1, state^.iso_scale^)
    rl.DrawCircleV(c, p^.brush_size, p^.color)
}


//   Render one cached line draw item.
draw_cached_line :: proc(
    state: ^Euclid_General_State, l: ^core.Shapes_Line_Draw, keep_above: bool) {
    clipped0 := Vector3{}
    clipped1 := Vector3{}
    if !z_split_clip_segment_halfspace(
        l^.point1, l^.point2, keep_above, &clipped0, &clipped1) {
        return
    }

    color := l^.color
    if !keep_above && (z_split_sign(clipped0.z) < 0 || z_split_sign(clipped1.z) < 0) {
        color = z_split_lower_fragment_color(color)
    }

    c0 := view_core.iso_to_cartesian(clipped0, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(clipped1, state^.iso_scale^)
    rl.DrawLineEx(c0, c1, l^.brush_size, color)
}


//   Render one cached circle/arc draw item.
draw_cached_circle :: proc(state: ^Euclid_General_State, c: ^core.Shapes_Circle_Draw) {
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
draw_cached_filledcircle :: proc(
    state: ^Euclid_General_State, c: ^core.Shapes_Filled_Circle_Draw) {
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
    poly: ^core.Shapes_Polygon_Draw,
    projected: []Vector2) -> bool {

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
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
    cache: ^core.Shapes_Draw_Cache,
    poly: ^core.Shapes_Polygon_Draw,
    projected: []Vector2,
    color: rl.Color) {

    triangles := cache^.polygon_triangles[
        poly^.first_triangle:poly^.first_triangle + poly^.triangle_count]
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

        rl.DrawTriangle(projected[i0], projected[i1], projected[i2], color)
    }
}


//   Render one cached polygon floor shadow.
draw_cached_polygon_shadow :: proc(
    state: ^Euclid_General_State, poly: ^core.Shapes_Polygon_Draw) {
    if poly^.vertex_count < 3 || poly^.triangle_count <= 0 {
        return
    }

    cache := &state^.point_system^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    if !has_any_elevated_shadow_point(vertices) {
        return
    }

    projected: [core.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    for i in 0..<poly^.vertex_count {
        projected[i] = shadow_to_screen(vertices[i], state)
    }

    shadow_color := make_shadow_color(poly^.color, average_shadow_height(vertices))
    draw_cached_polygon_triangles(cache, poly, projected[:], shadow_color)
}

//   Render one cached polygon draw item.
draw_cached_polygon :: proc(
    state: ^Euclid_General_State, poly: ^core.Shapes_Polygon_Draw) {
    if poly^.vertex_count < 3 || poly^.triangle_count <= 0 {
        return
    }

    projected: [core.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    if !project_cached_polygon_vertices(state, poly, projected[:]) {
        return
    }

    cache := &state^.point_system^.draw_cache
    draw_cached_polygon_triangles(cache, poly, projected[:], poly^.color)
}


//   Render one cached pen tool draw item.
draw_cached_pen :: proc(state: ^Euclid_General_State, pen: ^core.Shapes_Pen_Draw) {
    c0 := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)

    draw_stroke3d_segment(state, c0, c1, pen^.brush_size, pen^.color)
}


//   Render active-end indicator for cached pen tool.
draw_cached_pen_active_dot :: proc(
    state: ^Euclid_General_State, pen: ^core.Shapes_Pen_Draw) {
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
draw_cached_compass :: proc(
    state: ^Euclid_General_State, comp: ^core.Shapes_Compass_Draw) {
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
draw_cached_compass_active_dot :: proc(
    state: ^Euclid_General_State, comp: ^core.Shapes_Compass_Draw) {
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
draw_cached_pen_shadow :: proc(state: ^Euclid_General_State, pen: ^core.Shapes_Pen_Draw) {
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
draw_cached_compass_shadow :: proc(
    state: ^Euclid_General_State, comp: ^core.Shapes_Compass_Draw) {
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
