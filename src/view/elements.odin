package view

import colormodel "../color/model"
import viewmodel "model"
import rendershader "render/shader"

import shapemodel "../shapes/model"

// We draw the basic surface and all the shapes and tools here

// Only the tools are drawn with shaders. Everything else is the ordinary 2D tools,
// drawn with an isometric projection

import "../files"
import view_core "core"
import "font"
import render_raylib "render/raylib"
import rendermetrics "../render/metrics"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

Tool_Brush_Material :: struct {
    roughness:     f32,
    fresnel_0:     f32,
    specular_tint: f32,
    shadow_limit:  f32,
}

CIRCLE_ARC_SEGMENTS :: 96

COMPASS_TOPCIRCLE_SEGMENTS :: 48
COMPASS_TOPCIRCLE_VECTORS :: COMPASS_TOPCIRCLE_SEGMENTS + 1
COMPASS_TOPCIRCLE_RADIUS :: 0.25
TROCHOID_TOOL_RING_SEGMENTS :: 64
TROCHOID_TOOL_RING_VECTORS :: TROCHOID_TOOL_RING_SEGMENTS + 1
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
// Polished, used bare titanium alloy tinted toward Euclid's established tool color.
STROKE3D_TITANIUM_MATERIAL :: Tool_Brush_Material{
    roughness = 0.34,
    fresnel_0 = 0.48,
    specular_tint = 0.45,
    shadow_limit = 0.30,
}
STROKE3D_VIEW_RIGHT :: Vector3{0.70710678, -0.70710678, 0.0}
STROKE3D_VIEW_UP :: Vector3{0.40824829, 0.40824829, 0.81649658}
STROKE3D_VIEW_FORWARD :: Vector3{-0.57735027, -0.57735027, 0.57735027}

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
    pen: shapemodel.Shapes_Pen_Draw,
    polygon: shapemodel.Shapes_Polygon_Draw,
    back0: Vector3,
    back1: Vector3,
    front0: Vector3,
    front1: Vector3,
    has_back: bool,
    has_front: bool,
}

// Hold resolved ordering decisions for one merged-layer draw pass.
High_Merged_Draw_Context :: struct {
    crossing: Pen_Polygon_Crossing,
    has_crossing: bool,
    defer_guide: bool,
    guide_index: int,
    compass_index: int,
    pen_receives_compass: bool,
    compass_receives_pen: bool,
}

//   Resolved tool_brush shader program paths.
Tool_Brush_Shader_Paths :: struct {
    vertex:   cstring,
    fragment: cstring,
}

//   Plane-clipping context for one pen segment against one polygon plane.
Pen_Polygon_Clip_Context :: struct {
    stage0_start:  Vector3,
    stage0_end:    Vector3,
    clip_start:    Vector3,
    clip_end:      Vector3,
    plane_point:   Vector3,
    plane_normal:  Vector3,
    raw_distance0: f32,
    raw_distance1: f32,
    side0:         int,
    side1:         int,
    on_plane0:     bool,
    on_plane1:     bool,
}

//   Circle/arc geometry shared by draw and shadow passes.
Circle_Arc_Geometry :: struct {
    center:       Vector3,
    sweep_delta:  f32,
    radius:       f32,
    start_theta:  f32,
}

//   Batch world points plus their SoA scratch and output slices.
Iso_Batch_Project_Params :: struct {
    world_points: []Vector3,
    xs, ys, zs:   []f32,
    out:          []Vector2,
}

//   Shared basis for the compass top-circle arc that lies outside the swing angle.
Compass_Top_Circle_Basis :: struct {
    u:         Vector3,
    v:         Vector3,
    radius:    f32,
    theta_out: f32,
}

//   Draw inputs for one compass outside-arc segment.
Compass_Arc_Draw :: struct {
    state:      ^Euclid_General_State,
    brush_size: f32,
    color:      rl.Color,
}

//   Fixed arc samples shared by strip geometry and intersection metadata.
Compass_Arc_Samples :: struct {
    tangents_view: [COMPASS_TOPCIRCLE_VECTORS]Vector3,
    left:          [COMPASS_TOPCIRCLE_VECTORS]Vector2,
    right:         [COMPASS_TOPCIRCLE_VECTORS]Vector2,
    auxiliary:     [COMPASS_TOPCIRCLE_VECTORS]Vector2,
}

// Hold one closed guide ring's projected strip samples.
Trochoid_Tool_Ring_Samples :: struct {
    tangents_view: [TROCHOID_TOOL_RING_VECTORS]Vector3,
    left:          [TROCHOID_TOOL_RING_VECTORS]Vector2,
    right:         [TROCHOID_TOOL_RING_VECTORS]Vector2,
    auxiliary:     [TROCHOID_TOOL_RING_VECTORS]Vector2,
}

//   Cached geometry and optional pen occluder used to draw both compass legs.
Compass_Leg_Draw_Context :: struct {
    state:            ^Euclid_General_State,
    comp:             ^shapemodel.Shapes_Compass_Draw,
    c0, c1, c2:       Vector2,
    leg1, leg2:       Tool_Brush_Occluder,
    pen_occluder:     Tool_Brush_Occluder,
    has_pen_occluder: bool,
}

//   One projected tool segment used as bounded shadow context.
Tool_Brush_Occluder :: struct {
    p0:        Vector2,
    p1:        Vector2,
    thickness: f32,
    depth0:    f32,
    depth1:    f32,
    tangent:   Vector3,
}

//   Allocation-free occluders uploaded for one receiving tool segment.
Tool_Brush_Occluder_Context :: struct {
    occluders: [viewmodel.MAX_TOOL_BRUSH_OCCLUDERS]Tool_Brush_Occluder,
    count:     int,
}

//   Return canonical view depth, with larger values closer to the camera.
tool_brush_view_depth :: #force_inline proc(point: Vector3) -> f32 {
    return linalg.dot(point, STROKE3D_VIEW_FORWARD)
}

//   Build projected and view-space metadata for one world-space tool segment.
make_tool_brush_occluder :: #force_inline proc(
    state: ^Euclid_General_State,
    p0, p1: Vector3, thickness: f32) -> Tool_Brush_Occluder {

    direction := p1 - p0
    tangent := Vector3{}
    if linalg.dot(direction, direction) > 0.00000001 {
        tangent = linalg.normalize(tool_brush_light_to_view(direction))
    }
    return Tool_Brush_Occluder{
        p0 = view_core.iso_to_cartesian(p0, state^.iso_scale^),
        p1 = view_core.iso_to_cartesian(p1, state^.iso_scale^),
        thickness = thickness,
        depth0 = tool_brush_view_depth(p0),
        depth1 = tool_brush_view_depth(p1),
        tangent = tangent,
    }
}

//   Build the fixed leg slots consumed by arc attachment blending.
make_compass_arc_occluders :: #force_inline proc(
    leg1, leg2: Tool_Brush_Occluder) -> Tool_Brush_Occluder_Context {
    return Tool_Brush_Occluder_Context{
        occluders = {leg1, leg2},
        count = viewmodel.MAX_TOOL_BRUSH_OCCLUDERS,
    }
}

//   Return true when a caster can affect the receiving segment in screen space.
tool_brush_occluder_overlaps :: #force_inline proc(
    receiver, caster: Tool_Brush_Occluder) -> bool {
    receiver_radius := receiver.thickness * 0.5
    caster_radius := caster.thickness * 0.5
    padding := receiver_radius + caster_radius * 4.0

    receiver_min := Vector2{
        math.min(receiver.p0.x, receiver.p1.x) - padding,
        math.min(receiver.p0.y, receiver.p1.y) - padding,
    }
    receiver_max := Vector2{
        math.max(receiver.p0.x, receiver.p1.x) + padding,
        math.max(receiver.p0.y, receiver.p1.y) + padding,
    }
    caster_min := Vector2{
        math.min(caster.p0.x, caster.p1.x),
        math.min(caster.p0.y, caster.p1.y),
    }
    caster_max := Vector2{
        math.max(caster.p0.x, caster.p1.x),
        math.max(caster.p0.y, caster.p1.y),
    }

    return receiver_min.x <= caster_max.x && receiver_max.x >= caster_min.x &&
        receiver_min.y <= caster_max.y && receiver_max.y >= caster_min.y
}

//   Append one relevant caster to a bounded receiver context.
append_tool_brush_occluder :: #force_inline proc(
    ctx: ^Tool_Brush_Occluder_Context,
    receiver, caster: Tool_Brush_Occluder) {
    if ctx^.count >= viewmodel.MAX_TOOL_BRUSH_OCCLUDERS ||
        !tool_brush_occluder_overlaps(receiver, caster) {
        return
    }

    ctx^.occluders[ctx^.count] = caster
    ctx^.count += 1
}

//   Resolve which tool receives interaction shadows from cache draw order.
tool_brush_interaction_receivers :: #force_inline proc(
    pen_draw_index, compass_index: int) -> (bool, bool) {
    pen_receives_compass := pen_draw_index >= 0 && compass_index > pen_draw_index
    compass_receives_pen := compass_index >= 0 && pen_draw_index > compass_index
    return pen_receives_compass, compass_receives_pen
}

// Return whether a depth-sorted guide must move immediately before the compass.
trochoid_tool_defers_to_compass :: #force_inline proc(
    guide_index, compass_index: int) -> bool {
    return guide_index >= 0 && compass_index >= 0 && guide_index > compass_index
}


//   Initialize tool_brush shader handles and uniform locations from packaged assets.
//
// Parameters:
//   - state: Global app state that stores shader handles and uniform locations.
//
// Returns:
//   - none.
init_tool_brush_shader :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d
    contract := rendershader.STROKE3D_CONTRACT

    paths: Tool_Brush_Shader_Paths
    if !tool_brush_shader_paths(&contract, &paths) {
        s^.ready = false
        return
    }

    shader := rl.LoadShader(paths.vertex, paths.fragment)
    if shader.id == 0 {
        fmt.println("tool_brush shader failed to load; pen/compass 3D shading disabled")
        s^.ready = false
        return
    }

    locations: [rendershader.STROKE3D_UNIFORM_COUNT]i32
    validation := resolve_shader_uniform_locations(&contract, shader, locations[:])
    if validation.failure != .None {
        fmt.println(
            "tool_brush shader missing required uniforms; pen/compass 3D shading disabled")
        if validation.requirement_index >= 0 {
            fmt.println("tool_brush missing uniform ",
                contract.uniforms[validation.requirement_index].name)
        }
        rl.UnloadShader(shader)
        s^.ready = false
        return
    }
    if !tool_brush_store_shader(state, shader) {
        s^.ready = false
        return
    }
    tool_brush_cache_uniform_locations(s, &contract, locations[:])

    s^.ready = true
}

// Transfer one validated tool shader into display-owned native storage.
tool_brush_store_shader :: proc(
    state: ^Euclid_General_State, shader: rl.Shader) -> bool {
    handle, stored := render_raylib.resource_tables_store_shader(
        &state^.render_resources, shader)
    if !stored {
        rl.UnloadShader(shader)
        fmt.println("tool_brush shader resource table is full; shading disabled")
        return false
    }
    state^.stroke_3d.shader = handle
    return true
}

//   Resolve and validate the tool_brush shader asset paths.
//
// Parameters:
//   - paths: Destination for the resolved vertex/fragment C-strings when true.
//
// Returns:
//   - ok: true when both paths resolve to existing files.
tool_brush_shader_paths :: proc(
    contract: ^rendershader.Shader_Program_Contract,
    paths: ^Tool_Brush_Shader_Paths) -> bool {
    vertex_path :=
        files.packaged_asset_path(contract^.vertex_asset, context.temp_allocator)
    fragment_path :=
        files.packaged_asset_path(contract^.fragment_asset, context.temp_allocator)
    if len(vertex_path) == 0 || len(fragment_path) == 0 {
        fmt.println(
            "tool_brush shader paths could not be resolved from assets.pkg; pen/compass 3D shading disabled")
        return false
    }

    paths^.vertex = strings.clone_to_cstring(vertex_path, context.temp_allocator)
    paths^.fragment = strings.clone_to_cstring(fragment_path, context.temp_allocator)
    if !rl.FileExists(paths^.vertex) || !rl.FileExists(paths^.fragment) {
        fmt.println(
            "tool_brush shader files not found; pen/compass 3D shading disabled")
        fmt.println(
            "tool_brush expected paths: vs=", vertex_path, " fs=", fragment_path)
        return false
    }

    return true
}

// Resolve every descriptor uniform and validate required locations.
resolve_shader_uniform_locations :: proc(
    contract: ^rendershader.Shader_Program_Contract,
    shader: rl.Shader, locations: []i32) -> rendershader.Validation_Result {
    if len(locations) != len(contract^.uniforms) {
        return {.Location_Count, -1}
    }
    for requirement, index in contract^.uniforms {
        locations[index] = rl.GetShaderLocation(shader, requirement.name)
    }
    return rendershader.validate_uniform_locations(contract, locations)
}

// Cache validated descriptor locations in the typed stroke render record.
tool_brush_cache_uniform_locations :: proc(
    s: ^viewmodel.Tool_Render_State,
    contract: ^rendershader.Shader_Program_Contract, locations: []i32) {
    tool_brush_cache_material_locations(s, contract, locations)
    tool_brush_cache_geometry_locations(s, contract, locations)
    tool_brush_cache_occluder_locations(s, contract, locations)
}

// Cache frame and material descriptor locations in the typed stroke record.
tool_brush_cache_material_locations :: proc(
    s: ^viewmodel.Tool_Render_State,
    contract: ^rendershader.Shader_Program_Contract, locations: []i32) {
    s^.loc_light_dir = shader_location(contract, locations, .Light_Direction)
    s^.loc_ambient = shader_location(contract, locations, .Ambient)
    s^.loc_diffuse = shader_location(contract, locations, .Diffuse)
    s^.loc_material_roughness = shader_location(contract, locations, .Material_Roughness)
    s^.loc_material_fresnel_0 = shader_location(contract, locations, .Material_Fresnel0)
    s^.loc_material_specular_tint =
        shader_location(contract, locations, .Material_Specular_Tint)
    s^.loc_material_shadow_limit =
        shader_location(contract, locations, .Material_Shadow_Limit)
}

// Cache geometry descriptor locations in the typed stroke render record.
tool_brush_cache_geometry_locations :: proc(
    s: ^viewmodel.Tool_Render_State,
    contract: ^rendershader.Shader_Program_Contract, locations: []i32) {
    s^.loc_p0 = shader_location(contract, locations, .Segment_Start)
    s^.loc_p1 = shader_location(contract, locations, .Segment_End)
    s^.loc_radius = shader_location(contract, locations, .Segment_Radius)
    s^.loc_viewport_height = shader_location(contract, locations, .Viewport)
    s^.loc_stroke_mode = shader_location(contract, locations, .Stroke_Mode)
    s^.loc_strip_alpha = shader_location(contract, locations, .Strip_Alpha)
    s^.loc_strip_color = shader_location(contract, locations, .Strip_Color)
    s^.loc_strip_side_extent = shader_location(contract, locations, .Strip_Side_Extent)
    s^.loc_arc_intersections_enabled =
        shader_location(contract, locations, .Arc_Intersections_Enabled)
    s^.loc_intersection_depth_width =
        shader_location(contract, locations, .Intersection_Depth_Width)
    s^.loc_attachment_extent = shader_location(contract, locations, .Attachment_Extent)
    s^.loc_occluder_count = shader_location(contract, locations, .Occluder_Count)
}

// Cache bounded occluder array locations in the typed stroke render record.
tool_brush_cache_occluder_locations :: proc(
    s: ^viewmodel.Tool_Render_State,
    contract: ^rendershader.Shader_Program_Contract, locations: []i32) {
    for i in 0..<viewmodel.MAX_TOOL_BRUSH_OCCLUDERS {
        element := u8(i)
        s^.loc_occluder_p0[i] =
            shader_location(contract, locations, .Occluder_Start, element)
        s^.loc_occluder_p1[i] =
            shader_location(contract, locations, .Occluder_End, element)
        s^.loc_occluder_radius[i] =
            shader_location(contract, locations, .Occluder_Radius, element)
        s^.loc_occluder_depth0[i] =
            shader_location(contract, locations, .Occluder_Depth_Start, element)
        s^.loc_occluder_depth1[i] =
            shader_location(contract, locations, .Occluder_Depth_End, element)
        s^.loc_occluder_tangent[i] =
            shader_location(contract, locations, .Occluder_Tangent, element)
    }
}

// Return one validated location by semantic identity and array element.
shader_location :: #force_inline proc(
    contract: ^rendershader.Shader_Program_Contract, locations: []i32,
    semantic: rendershader.Uniform_Semantic, element: u8 = 0) -> i32 {
    index, ok := rendershader.uniform_index(contract, semantic, element)
    assert(ok)
    return locations[index]
}

//   Unload tool_brush shader resources and mark shader state as unavailable.
//
// Parameters:
//   - state: Global app state containing tool_brush shader state.
//
// Returns:
//   - none.
shutdown_tool_brush_shader :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d
    _ = render_raylib.resource_tables_release_shader(
        &state^.render_resources, s^.shader)
    s^.shader = {}
    s^.ready = false
}

// Draw one projected surface interior and its distinct border triangles.
draw_projected_surface :: proc(
    state: ^Euclid_General_State,
    projected: [8]Vector2, edge_color, surface_color: rl.Color) {
    rl.DrawTriangle(projected[0], projected[1], projected[2], edge_color)
    rl.DrawTriangle(projected[3], projected[2], projected[1], edge_color)
    rl.DrawTriangle(projected[4], projected[5], projected[6], surface_color)
    rl.DrawTriangle(projected[7], projected[6], projected[5], surface_color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions, 4)
    rendermetrics.record(&state^.render_metrics, .Generated_Indices, 12)
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
    surface_left_down : Vector3 =
        room^.left_down + { room.edge_size, -room.edge_size, 0 }
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
        Iso_Batch_Project_Params{
            world_points = world_points[:],
            xs = xs[:],
            ys = ys[:],
            zs = zs[:],
            out = projected[:],
        })

    draw_projected_surface(state, projected,
        render_raylib.color(room.edge_color), render_raylib.color(room.color))
}

//   Render cached low-layer geometry items (labels, primitives, and polygons).
//
// Parameters:
//   - state: Global app state containing the draw cache to render.
//
// Returns:
//   - none.
draw_shapes_points_low_cached :: proc(state: ^Euclid_General_State) {
    for i in 0..<state^.shape_world^.draw_cache.item_count {
        draw_cached_item_low(state, &state^.shape_world^.draw_cache.items[i])
    }
}

// Draw one cache position according to resolved merged-layer ordering.
draw_shapes_high_merged_item :: proc(
    state: ^Euclid_General_State,
    cache: ^shapemodel.Shapes_Draw_Cache,
    index: int,
    ctx: ^High_Merged_Draw_Context) {
    if ctx^.defer_guide && index == ctx^.guide_index {return}
    if ctx^.defer_guide && index == ctx^.compass_index {
        draw_cached_trochoid_tool_full(state, &cache^.trochoid_tool)
    }
    if ctx^.has_crossing && index == ctx^.crossing.polygon_index {
        compass_caster: ^shapemodel.Shapes_Compass_Draw = nil
        if ctx^.pen_receives_compass {compass_caster = &cache^.compass}
        draw_pen_polygon_crossing(state, &ctx^.crossing, compass_caster)
        return
    }
    if ctx^.has_crossing && index == ctx^.crossing.pen_index {return}
    draw_cached_item_high_merged(state, &cache^.items[index],
        ctx^.pen_receives_compass, ctx^.compass_receives_pen)
}

//   Render cached higher-layer items after shadows and particles.
//
// Parameters:
//   - state: Global app state containing the draw cache to render.
//
// Returns:
//   - none.
draw_shapes_points_high_merged_cached :: proc(state: ^Euclid_General_State) {
    ctx := High_Merged_Draw_Context{}
    ctx.crossing.pen_index = -1
    ctx.crossing.polygon_index = -1
    ctx.has_crossing = find_pen_polygon_crossing(state, &ctx.crossing)
    cache := &state^.shape_world^.draw_cache
    _, pen_index := find_cached_pen_item(cache)
    _, compass_index := find_cached_compass_item(cache)
    _, guide_index := find_cached_trochoid_tool_item(cache)
    pen_draw_index := pen_index
    if ctx.has_crossing {pen_draw_index = ctx.crossing.polygon_index}
    ctx.pen_receives_compass, ctx.compass_receives_pen =
        tool_brush_interaction_receivers(pen_draw_index, compass_index)
    ctx.defer_guide = trochoid_tool_defers_to_compass(guide_index, compass_index)
    ctx.guide_index = guide_index
    ctx.compass_index = compass_index
    for i in 0..<cache^.item_count {
        draw_shapes_high_merged_item(state, cache, i, &ctx)
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
    if state^.shape_world^.draw_cache.draw_trochoid_tool {
        draw_cached_trochoid_tool_shadow(
            state, &state^.shape_world^.draw_cache.trochoid_tool)
    }
    if state^.shape_world^.draw_cache.draw_cycloid_tool {
        draw_cached_cycloid_tool_shadow(
            state, &state^.shape_world^.draw_cache.cycloid_tool)
    }
    if state^.shape_world^.draw_cache.draw_pen {
        draw_cached_pen_shadow(state, &state^.shape_world^.draw_cache.pen)
    }
    if state^.shape_world^.draw_cache.draw_compass {
        draw_cached_compass_shadow(state, &state^.shape_world^.draw_cache.compass)
    }
}

//   Render floor shadows for cached low-layer geometry when any defining point is above the surface.
//
// Notes:
//   - Flat and below-surface geometry draws no shadow.
//   - Labels are intentionally excluded from the shape-shadow pass.
draw_shapes_shapes_shadows_cached :: proc(state: ^Euclid_General_State) {
    for i in 0..<state^.shape_world^.draw_cache.item_count {
        draw_cached_item_shadow(state, &state^.shape_world^.draw_cache.items[i])
    }
}

//   Draw one cached item only when it belongs to the lower geometry layer.
draw_cached_item_low :: proc(state: ^Euclid_General_State,
    item: ^shapemodel.Shapes_Draw_Cache_Item) {
    switch &item_typed in item {
    case shapemodel.Shapes_Label_Draw:
        draw_cached_label(state, &item_typed)
    case shapemodel.Shapes_Point_Draw:
        draw_cached_point_low(state, &item_typed)
    case shapemodel.Shapes_Line_Draw:
        draw_cached_line_low(state, &item_typed)
    case shapemodel.Shapes_Circle_Draw:
        draw_cached_circle_low(state, &item_typed)
    case shapemodel.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_low(state, &item_typed)
    case shapemodel.Shapes_Curve_Draw:
        draw_cached_curve_low(state, &item_typed)
    case shapemodel.Shapes_Polygon_Draw:
        draw_cached_polygon_low(state, &item_typed)
    case shapemodel.Shapes_Trochoid_Tool_Draw,
        shapemodel.Shapes_Cycloid_Tool_Draw:
    case shapemodel.Shapes_Pen_Draw,
        shapemodel.Shapes_Compass_Draw:
    }
}

//   Draw the cached pen with the compass caster selected by merged-layer ordering.
draw_cached_pen_high_merged :: #force_inline proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    receives_compass: bool) {

    compass_caster: ^shapemodel.Shapes_Compass_Draw = nil
    if receives_compass {
        compass_caster = &state^.shape_world^.draw_cache.compass
    }
    draw_cached_pen_full(state, pen, compass_caster)
}

//   Draw the cached compass with the pen caster selected by merged-layer ordering.
draw_cached_compass_high_merged :: #force_inline proc(
    state: ^Euclid_General_State,
    compass: ^shapemodel.Shapes_Compass_Draw,
    receives_pen: bool) {

    pen_caster: ^shapemodel.Shapes_Pen_Draw = nil
    if receives_pen {
        pen_caster = &state^.shape_world^.draw_cache.pen
    }
    draw_cached_compass_full(state, compass, pen_caster)
}

// Draw one cached instrument in the merged higher layer when applicable.
draw_cached_instrument_high_merged :: proc(state: ^Euclid_General_State,
    item: ^shapemodel.Shapes_Draw_Cache_Item,
    pen_receives_compass, compass_receives_pen: bool) -> bool {
    switch &item_typed in item {
    case shapemodel.Shapes_Trochoid_Tool_Draw:
        draw_cached_trochoid_tool_full(state, &item_typed)
    case shapemodel.Shapes_Cycloid_Tool_Draw:
        draw_cached_cycloid_tool_full(state, &item_typed)
    case shapemodel.Shapes_Pen_Draw:
        draw_cached_pen_high_merged(state, &item_typed, pen_receives_compass)
    case shapemodel.Shapes_Compass_Draw:
        draw_cached_compass_high_merged(state, &item_typed, compass_receives_pen)
    case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Point_Draw,
        shapemodel.Shapes_Line_Draw, shapemodel.Shapes_Circle_Draw,
        shapemodel.Shapes_Filled_Circle_Draw, shapemodel.Shapes_Curve_Draw,
        shapemodel.Shapes_Polygon_Draw:
        return false
    }
    return true
}

//   Draw one cached item only when it belongs to the merged higher layer.
draw_cached_item_high_merged :: proc(state: ^Euclid_General_State,
    item: ^shapemodel.Shapes_Draw_Cache_Item,
    pen_receives_compass, compass_receives_pen: bool) {
    if draw_cached_instrument_high_merged(
        state, item, pen_receives_compass, compass_receives_pen) {return}
    switch &item_typed in item {
    case shapemodel.Shapes_Label_Draw:
    case shapemodel.Shapes_Point_Draw: draw_cached_point_high(state, &item_typed)
    case shapemodel.Shapes_Line_Draw: draw_cached_line_high(state, &item_typed)
    case shapemodel.Shapes_Circle_Draw: draw_cached_circle_high(state, &item_typed)
    case shapemodel.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_high(state, &item_typed)
    case shapemodel.Shapes_Curve_Draw: draw_cached_curve_high(state, &item_typed)
    case shapemodel.Shapes_Polygon_Draw: draw_cached_polygon_high(state, &item_typed)
    case shapemodel.Shapes_Trochoid_Tool_Draw,
        shapemodel.Shapes_Cycloid_Tool_Draw, shapemodel.Shapes_Pen_Draw,
        shapemodel.Shapes_Compass_Draw:
    }
}

//   Draw one cached item's floor shadow when that item can cast one.
draw_cached_item_shadow :: proc(state: ^Euclid_General_State,
    item: ^shapemodel.Shapes_Draw_Cache_Item) {
    switch &item_typed in item {
    case shapemodel.Shapes_Label_Draw,
        shapemodel.Shapes_Trochoid_Tool_Draw,
        shapemodel.Shapes_Cycloid_Tool_Draw,
        shapemodel.Shapes_Pen_Draw,
        shapemodel.Shapes_Compass_Draw:
    case shapemodel.Shapes_Point_Draw:
        draw_cached_point_shadow(state, &item_typed)
    case shapemodel.Shapes_Line_Draw:
        draw_cached_line_shadow(state, &item_typed)
    case shapemodel.Shapes_Circle_Draw:
        draw_cached_circle_shadow(state, &item_typed)
    case shapemodel.Shapes_Filled_Circle_Draw:
        draw_cached_filledcircle_shadow(state, &item_typed)
    case shapemodel.Shapes_Curve_Draw:
        draw_cached_curve_shadow(state, &item_typed)
    case shapemodel.Shapes_Polygon_Draw:
        draw_cached_polygon_shadow(state, &item_typed)
    }
}

//   Return true when a cached point draw item belongs to the elevated layer.
draw_cached_point_is_elevated :: #force_inline proc(
    p: ^shapemodel.Shapes_Point_Draw) -> bool {
    return shadow_point_is_elevated(p^.point1)
}

//   Return true when a cached circle draw item belongs to the elevated layer.
draw_cached_circle_is_elevated :: #force_inline proc(
    c: ^shapemodel.Shapes_Circle_Draw) -> bool {
    return shadow_point_is_elevated(c^.center)
}

//   Return true when a cached filled-circle draw item belongs to the elevated layer.
draw_cached_filledcircle_is_elevated :: #force_inline proc(
    c: ^shapemodel.Shapes_Filled_Circle_Draw) -> bool {
    return shadow_point_is_elevated(c^.center)
}

// Return true when any explicated curve vertex belongs to the elevated layer.
draw_cached_curve_is_elevated :: #force_inline proc(
    state: ^Euclid_General_State,
    curve: ^shapemodel.Shapes_Curve_Draw) -> bool {
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.curve_vertices[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    return has_any_elevated_shadow_point(vertices)
}

//   Return true when any cached polygon vertex belongs to the elevated layer.
draw_cached_polygon_is_elevated :: #force_inline proc(
    state: ^Euclid_General_State,
    poly: ^shapemodel.Shapes_Polygon_Draw) -> bool {

    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    return has_any_elevated_shadow_point(vertices)
}

//   Draw one cached point only when it belongs to the lower geometry layer.
draw_cached_point_low :: #force_inline proc(
    state: ^Euclid_General_State, p: ^shapemodel.Shapes_Point_Draw) {
    if !draw_cached_point_is_elevated(p) {
        draw_cached_point(state, p)
    }
}

//   Draw one cached point only when it belongs to the merged higher layer.
draw_cached_point_high :: #force_inline proc(
    state: ^Euclid_General_State, p: ^shapemodel.Shapes_Point_Draw) {
    if draw_cached_point_is_elevated(p) {
        draw_cached_point(state, p)
    }
}

//   Draw one cached line only when it belongs to the lower geometry layer.
draw_cached_line_low :: #force_inline proc(
    state: ^Euclid_General_State, l: ^shapemodel.Shapes_Line_Draw) {
    draw_cached_line(state, l, false)
}

//   Draw one cached line only when it belongs to the merged higher layer.
draw_cached_line_high :: #force_inline proc(
    state: ^Euclid_General_State, l: ^shapemodel.Shapes_Line_Draw) {
    draw_cached_line(state, l, true)
}

//   Draw one cached circle only when it belongs to the lower geometry layer.
draw_cached_circle_low :: #force_inline proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Circle_Draw) {
    if !draw_cached_circle_is_elevated(c) {
        draw_cached_circle(state, c)
    }
}

//   Draw one cached circle only when it belongs to the merged higher layer.
draw_cached_circle_high :: #force_inline proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Circle_Draw) {
    if draw_cached_circle_is_elevated(c) {
        draw_cached_circle(state, c)
    }
}

//   Draw one cached filled circle only when it belongs to the lower geometry layer.
draw_cached_filledcircle_low :: #force_inline proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Filled_Circle_Draw) {
    if !draw_cached_filledcircle_is_elevated(c) {
        draw_cached_filledcircle(state, c)
    }
}

//   Draw one cached filled circle only when it belongs to the merged higher layer.
draw_cached_filledcircle_high :: #force_inline proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Filled_Circle_Draw) {
    if draw_cached_filledcircle_is_elevated(c) {
        draw_cached_filledcircle(state, c)
    }
}

// Draw one cached curve only when all of it belongs to the lower geometry layer.
draw_cached_curve_low :: #force_inline proc(
    state: ^Euclid_General_State, curve: ^shapemodel.Shapes_Curve_Draw) {
    if !draw_cached_curve_is_elevated(state, curve) {
        draw_cached_curve(state, curve, false)
    }
}

// Draw one cached curve in the higher layer when any vertex is elevated.
draw_cached_curve_high :: #force_inline proc(
    state: ^Euclid_General_State, curve: ^shapemodel.Shapes_Curve_Draw) {
    if draw_cached_curve_is_elevated(state, curve) {
        draw_cached_curve(state, curve, true)
    }
}

//   Draw one cached polygon only when it belongs to the lower geometry layer.
draw_cached_polygon_low :: #force_inline proc(
    state: ^Euclid_General_State, poly: ^shapemodel.Shapes_Polygon_Draw) {
    if !draw_cached_polygon_is_elevated(state, poly) {
        draw_cached_polygon(state, poly)
    }
}

//   Draw one cached polygon only when it belongs to the merged higher layer.
draw_cached_polygon_high :: #force_inline proc(
    state: ^Euclid_General_State, poly: ^shapemodel.Shapes_Polygon_Draw) {
    if draw_cached_polygon_is_elevated(state, poly) {
        draw_cached_polygon(state, poly)
    }
}

//   Render one full cached pen item for the merged higher layer.
draw_cached_pen_full :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    compass_caster: ^shapemodel.Shapes_Compass_Draw) {
    draw_cached_pen_active_dot(state, pen)
    begin_tool_brush_mode(state)
    draw_cached_pen(state, pen, compass_caster)
    end_tool_brush_mode(state)
}

//   Render one full cached compass item for the merged higher layer.
draw_cached_compass_full :: proc(
    state: ^Euclid_General_State,
    comp: ^shapemodel.Shapes_Compass_Draw,
    pen_caster: ^shapemodel.Shapes_Pen_Draw) {
    draw_cached_compass_active_dot(state, comp)
    begin_tool_brush_mode(state)
    draw_cached_compass(state, comp, pen_caster)
    end_tool_brush_mode(state)
}

// Return one planar world-space point on a guide ring.
trochoid_tool_ring_point :: #force_inline proc(
    center: Vector3, radius, angle: f32) -> Vector3 {
    return {center.x + math.cos(angle) * radius,
        center.y + math.sin(angle) * radius, center.z}
}

// Build one closed guide ring as a welded projected strip.
build_trochoid_tool_ring_samples :: proc(
    state: ^Euclid_General_State,
    center: Vector3,
    radius, coverage_radius: f32,
    samples: ^Trochoid_Tool_Ring_Samples) -> bool {
    for index in 0..=TROCHOID_TOOL_RING_SEGMENTS {
        parameter := f32(index) / f32(TROCHOID_TOOL_RING_SEGMENTS)
        angle := 2 * math.PI * parameter
        center3d := trochoid_tool_ring_point(center, radius, angle)
        tangent3d := Vector3{-math.sin(angle), math.cos(angle), 0}
        projected := view_core.iso_to_cartesian(center3d, state^.iso_scale^)
        tangent_point := view_core.iso_to_cartesian(
            center3d + tangent3d, state^.iso_scale^)
        tangent := tangent_point - projected
        tangent_length := linalg.length(tangent)
        if tangent_length <= 0.0001 {return false}
        tangent /= tangent_length
        perpendicular := Vector2{-tangent.y, tangent.x}
        samples^.tangents_view[index] =
            linalg.normalize(tool_brush_light_to_view(tangent3d))
        samples^.left[index] = projected - perpendicular * coverage_radius
        samples^.right[index] = projected + perpendicular * coverage_radius
        samples^.auxiliary[index] = Vector2{
            tool_brush_view_depth(center3d), parameter}
    }
    return true
}

// Emit one closed guide ring's connected strip triangles.
emit_trochoid_tool_ring_strip :: proc(samples: ^Trochoid_Tool_Ring_Samples) {
    for index in 0..<TROCHOID_TOOL_RING_SEGMENTS {
        emit_tool_brush_strip_vertex(samples^.left[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 0)
        emit_tool_brush_strip_vertex(samples^.right[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 255)
        emit_tool_brush_strip_vertex(samples^.left[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 0)
        emit_tool_brush_strip_vertex(samples^.right[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 255)
        emit_tool_brush_strip_vertex(samples^.right[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 255)
        emit_tool_brush_strip_vertex(samples^.left[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 0)
    }
}

// Draw one guide ring through the unshaded line fallback.
draw_trochoid_tool_ring_fallback :: proc(
    state: ^Euclid_General_State,
    center: Vector3,
    radius, brush_size: f32,
    color: rl.Color) {
    previous := trochoid_tool_ring_point(center, radius, 0)
    for index in 1..=TROCHOID_TOOL_RING_SEGMENTS {
        angle := 2 * math.PI * f32(index) / f32(TROCHOID_TOOL_RING_SEGMENTS)
        current := trochoid_tool_ring_point(center, radius, angle)
        first := view_core.iso_to_cartesian(previous, state^.iso_scale^)
        second := view_core.iso_to_cartesian(current, state^.iso_scale^)
        rl.DrawLineEx(first, second, brush_size, color)
        previous = current
    }
}

// Draw one closed guide ring as one continuous shader-lit strip.
draw_trochoid_tool_ring_shader :: proc(
    state: ^Euclid_General_State,
    center: Vector3,
    radius, brush_size: f32,
    color: rl.Color) {
    scale := get_tool_brush_render_scale()
    min_scale := math.max(math.min(scale.x, scale.y), 0.0001)
    brush_radius := brush_size * 0.5
    coverage_radius := brush_radius + 1.0 / min_scale
    side_extent := coverage_radius / math.max(brush_radius, 0.0001)
    samples := Trochoid_Tool_Ring_Samples{}
    if !build_trochoid_tool_ring_samples(
        state, center, radius, coverage_radius, &samples) {return}

    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    shader := &state^.stroke_3d
    set_tool_brush_uniform_float(state, shader^.loc_stroke_mode, 1.0)
    set_tool_brush_uniform_float(
        state, shader^.loc_strip_alpha, f32(color.a) / 255.0)
    set_tool_brush_uniform_vec3(state, shader^.loc_strip_color, Vector3{
        f32(color.r) / 255.0, f32(color.g) / 255.0, f32(color.b) / 255.0})
    set_tool_brush_uniform_float(state, shader^.loc_strip_side_extent, side_extent)
    set_tool_brush_uniform_float(state, shader^.loc_arc_intersections_enabled, 0.0)

    _ = rlgl.CheckRenderBatchLimit(TROCHOID_TOOL_RING_SEGMENTS * 6)
    rlgl.SetTexture(rlgl.GetTextureIdDefault())
    rlgl.DisableBackfaceCulling()
    rlgl.Begin(rlgl.TRIANGLES)
    emit_trochoid_tool_ring_strip(&samples)
    rlgl.End()
    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    rlgl.EnableBackfaceCulling()
    set_tool_brush_uniform_float(state, shader^.loc_stroke_mode, 0.0)
}

// Select the available renderer for one closed guide ring.
draw_trochoid_tool_ring :: proc(
    state: ^Euclid_General_State,
    center: Vector3,
    radius, brush_size: f32,
    color: rl.Color) {
    if !state^.stroke_3d.ready {
        draw_trochoid_tool_ring_fallback(state, center, radius, brush_size, color)
        return
    }
    draw_trochoid_tool_ring_shader(state, center, radius, brush_size, color)
}

// Render the two-ring guide and its inward orientation handle in one shader binding.
draw_cached_trochoid_tool_full :: proc(
    state: ^Euclid_General_State,
    tool: ^shapemodel.Shapes_Trochoid_Tool_Draw) {
    begin_tool_brush_mode(state)
    draw_trochoid_tool_ring(state, tool^.fixed_center,
        tool^.fixed_radius, tool^.brush_size, render_raylib.color(tool^.color))
    draw_trochoid_tool_ring(state, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, render_raylib.color(tool^.color))
    first := view_core.iso_to_cartesian(tool^.handle_start, state^.iso_scale^)
    second := view_core.iso_to_cartesian(tool^.handle_finish, state^.iso_scale^)
    draw_tool_brush_segment(
        state, first, second, tool^.brush_size, render_raylib.color(tool^.color))
    end_tool_brush_mode(state)
}

// Render the exact endpoint rail, rolling ring, and orientation handle together.
draw_cached_cycloid_tool_full :: proc(
    state: ^Euclid_General_State,
    tool: ^shapemodel.Shapes_Cycloid_Tool_Draw) {
    begin_tool_brush_mode(state)
    baseline_start := view_core.iso_to_cartesian(
        tool^.baseline_start, state^.iso_scale^)
    baseline_finish := view_core.iso_to_cartesian(
        tool^.baseline_finish, state^.iso_scale^)
    draw_tool_brush_segment(state, baseline_start, baseline_finish,
        tool^.brush_size, render_raylib.color(tool^.color))
    draw_trochoid_tool_ring(state, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, render_raylib.color(tool^.color))
    handle_start := view_core.iso_to_cartesian(
        tool^.handle_start, state^.iso_scale^)
    handle_finish := view_core.iso_to_cartesian(
        tool^.handle_finish, state^.iso_scale^)
    draw_tool_brush_segment(state, handle_start, handle_finish,
        tool^.brush_size, render_raylib.color(tool^.color))
    end_tool_brush_mode(state)
}






//   Set a float uniform on the tool_brush shader when location is valid.
set_tool_brush_uniform_float :: #force_inline proc(
    state: ^Euclid_General_State, location: i32, value: f32) {
    if location < 0 {
        return
    }
    shader, found := render_raylib.resource_tables_resolve_shader(
        &state^.render_resources, state^.stroke_3d.shader)
    if !found { return }
    local_value := value
    rl.SetShaderValue(shader, location, &local_value, .FLOAT)
}


//   Set a vec2 uniform on the tool_brush shader when location is valid.
set_tool_brush_uniform_vec2 :: #force_inline proc(
    state: ^Euclid_General_State, location: i32, value: Vector2) {
    if location < 0 {
        return
    }
    shader, found := render_raylib.resource_tables_resolve_shader(
        &state^.render_resources, state^.stroke_3d.shader)
    if !found { return }
    vec_data := [2]f32{value.x, value.y}
    rl.SetShaderValue(shader, location, &vec_data[0], .VEC2)
}


//   Set one vec3 tool_brush shader uniform when its location is valid.
set_tool_brush_uniform_vec3 :: #force_inline proc(
    state: ^Euclid_General_State, location: i32, value: Vector3) {
    if location < 0 {
        return
    }
    shader, found := render_raylib.resource_tables_resolve_shader(
        &state^.render_resources, state^.stroke_3d.shader)
    if !found { return }
    vec_data := [3]f32{value.x, value.y, value.z}
    rl.SetShaderValue(shader, location, &vec_data[0], .VEC3)
}


//   Compute render-to-screen scale factors for shader-space thickness correction.
get_tool_brush_render_scale :: #force_inline proc() -> Vector2 {
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


//   Update tool_brush segment uniforms for endpoints and stroke radius.
set_tool_brush_segment :: #force_inline proc(
    state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32) {
    s := &state^.stroke_3d
    scale := get_tool_brush_render_scale()
    p0_scaled := Vector2{p0.x * scale.x, p0.y * scale.y}
    p1_scaled := Vector2{p1.x * scale.x, p1.y * scale.y}
    avg_scale := (scale.x + scale.y) * 0.5

    set_tool_brush_uniform_vec2(state, s^.loc_p0, p0_scaled)
    set_tool_brush_uniform_vec2(state, s^.loc_p1, p1_scaled)
    set_tool_brush_uniform_float(state, s^.loc_radius, thickness * 0.5 * avg_scale)
}


//   Upload bounded screen-space capsule occluders for one receiving segment.
set_tool_brush_occluders :: proc(
    state: ^Euclid_General_State, occluders: ^Tool_Brush_Occluder_Context) {
    s := &state^.stroke_3d
    if !s^.ready {
        return
    }

    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    scale := get_tool_brush_render_scale()
    avg_scale := (scale.x + scale.y) * 0.5

    for i in 0..<occluders^.count {
        occluder := &occluders^.occluders[i]
        p0_scaled := Vector2{occluder^.p0.x * scale.x, occluder^.p0.y * scale.y}
        p1_scaled := Vector2{occluder^.p1.x * scale.x, occluder^.p1.y * scale.y}
        set_tool_brush_uniform_vec2(state, s^.loc_occluder_p0[i], p0_scaled)
        set_tool_brush_uniform_vec2(state, s^.loc_occluder_p1[i], p1_scaled)
        set_tool_brush_uniform_float(state, s^.loc_occluder_radius[i],
            occluder^.thickness * 0.5 * avg_scale)
        set_tool_brush_uniform_float(
            state, s^.loc_occluder_depth0[i], occluder^.depth0)
        set_tool_brush_uniform_float(
            state, s^.loc_occluder_depth1[i], occluder^.depth1)
        set_tool_brush_uniform_vec3(
            state, s^.loc_occluder_tangent[i], occluder^.tangent)
    }
    set_tool_brush_uniform_float(state, s^.loc_occluder_count, f32(occluders^.count))
}


//   Disable tool-stroke occlusion after its receiver has been submitted.
clear_tool_brush_occluder :: #force_inline proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d
    if !s^.ready {
        return
    }

    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    set_tool_brush_uniform_float(state, s^.loc_occluder_count, 0.0)
}


//   Draw conservative capsule coverage for one shader-lit tool segment.
draw_tool_brush_capsule :: #force_inline proc(
    state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32, color: rl.Color) {
    delta := p1 - p0
    length := linalg.length(delta)
    if length <= 0 || thickness <= 0 {
        return
    }

    direction := delta / length
    perpendicular := Vector2{-direction.y, direction.x}
    scale := get_tool_brush_render_scale()
    min_scale := math.max(math.min(scale.x, scale.y), 0.0001)
    coverage_radius := thickness * 0.5 + 1.0 / min_scale
    start := p0 - direction * coverage_radius
    finish := p1 + direction * coverage_radius
    offset := perpendicular * coverage_radius
    vertices := [4]Vector2{
        start - offset,
        start + offset,
        finish - offset,
        finish + offset,
    }
    rl.DrawTriangleStrip(&vertices[0], len(vertices), color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}


//   Draw one segment with tool_brush lighting when available, else standard line draw.
draw_tool_brush_segment :: #force_inline proc(
    state: ^Euclid_General_State, p0, p1: Vector2, thickness: f32, color: rl.Color) {
    s := &state^.stroke_3d
    if s^.ready {
        rlgl.DrawRenderBatchActive()
        rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
        set_tool_brush_segment(state, p0, p1, thickness)
        draw_tool_brush_capsule(state, p0, p1, thickness, color)
        return
    }
    rl.DrawLineEx(p0, p1, thickness, color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}


//   Decide if joint1->pivot should be drawn last to preserve hinge-side layering.
//
// Notes:
//   - Uses projected hinge winding as primary rule.
//   - Falls back to world-depth ordering near collinear poses.
compass_draw_joint1_leg_last :: #force_inline proc(
    comp: ^shapemodel.Shapes_Compass_Draw, c0, c1, c2: Vector2) -> bool {
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


//   Transform one world-space direction into the orthonormal isometric view basis.
//
// Returns:
//   - direction: Light direction expressed as view right, up, and forward components.
tool_brush_light_to_view :: #force_inline proc(light: Vector3) -> Vector3 {
    return {
        linalg.dot(light, STROKE3D_VIEW_RIGHT),
        linalg.dot(light, STROKE3D_VIEW_UP),
        linalg.dot(light, STROKE3D_VIEW_FORWARD),
    }
}


//   Bind tool_brush shader and upload per-frame lighting/render uniforms.
//
// Notes:
//   - Must be paired with end_tool_brush_mode in the same draw pass.
begin_tool_brush_mode :: proc(state: ^Euclid_General_State) {
    s := &state^.stroke_3d

    if !s^.ready {
        return
    }
    shader, found := render_raylib.resource_tables_resolve_shader(
        &state^.render_resources, s^.shader)
    if !found {
        s^.ready = false
        return
    }

    light := -state^.iso_scale^.main_light_dir
    light = linalg.normalize(light)
    light = tool_brush_light_to_view(light)

    light_dir_data := [3]f32{light.x, light.y, light.z}
    if s^.loc_light_dir >= 0 {
        rl.SetShaderValue(shader, s^.loc_light_dir, &light_dir_data[0], .VEC3)
    }

    set_tool_brush_uniform_float(state, s^.loc_ambient, STROKE3D_AMBIENT)
    set_tool_brush_uniform_float(state, s^.loc_diffuse, STROKE3D_DIFFUSE)
    material := STROKE3D_TITANIUM_MATERIAL
    set_tool_brush_uniform_float(state, s^.loc_material_roughness, material.roughness)
    set_tool_brush_uniform_float(state, s^.loc_material_fresnel_0, material.fresnel_0)
    set_tool_brush_uniform_float(
        state, s^.loc_material_specular_tint, material.specular_tint)
    set_tool_brush_uniform_float(
        state, s^.loc_material_shadow_limit, material.shadow_limit)
    set_tool_brush_uniform_float(state,
        s^.loc_viewport_height, f32(rl.GetRenderHeight()))
    set_tool_brush_uniform_float(state, s^.loc_stroke_mode, 0.0)
    set_tool_brush_uniform_float(state, s^.loc_arc_intersections_enabled, 0.0)
    set_tool_brush_uniform_float(state, s^.loc_occluder_count, 0.0)

    rl.BeginShaderMode(shader)
    rendermetrics.record(&state^.render_metrics, .Shader_Changes)
}


//   Flush pending batch and unbind tool_brush shader mode.
//
// Notes:
//   - Completes the begin_tool_brush_mode/end_tool_brush_mode pair.
end_tool_brush_mode :: proc(state: ^Euclid_General_State) {
    if !state^.stroke_3d.ready {
        return
    }
    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    rl.EndShaderMode()
    rendermetrics.record(&state^.render_metrics, .Shader_Changes)
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
make_shadow_color :: proc(
    source: colormodel.Color_RGBA8, avg_height: f32) -> rl.Color {
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
z_split_lower_fragment_color :: #force_inline proc(
    color: colormodel.Color_RGBA8) -> colormodel.Color_RGBA8 {
    attenuated := u8(math.clamp(
        int(f32(color.alpha) * Z_SPLIT_ALPHA_FACTOR + 0.5), 0, 255))
    return {color.red, color.green, color.blue, attenuated}
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

//   Validate that one polygon triangle's local indices are in range.
polygon_triangle_indices_valid :: #force_inline proc(
    tri: shapemodel.Shapes_Polygon_Triangle, vertex_count: int) -> bool {

    return tri.a >= 0 && tri.a < vertex_count &&
        tri.b >= 0 && tri.b < vertex_count &&
        tri.c >= 0 && tri.c < vertex_count
}

//   Resolve one stable polygon plane from cached polygon triangles.
polygon_plane :: proc(
    state: ^Euclid_General_State,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    plane_point, plane_normal: ^Vector3) -> bool {

    if polygon^.vertex_count < 3 || polygon^.triangle_count <= 0 {
        return false
    }

    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        polygon^.first_vertex:polygon^.first_vertex + polygon^.vertex_count]
    triangles := cache^.polygon_triangles[
        polygon^.first_triangle:polygon^.first_triangle + polygon^.triangle_count]

    for tri in triangles {
        local_a := tri.a - polygon^.first_vertex
        local_b := tri.b - polygon^.first_vertex
        local_c := tri.c - polygon^.first_vertex
        if !polygon_triangle_indices_valid(
            shapemodel.Shapes_Polygon_Triangle{local_a, local_b, local_c},
            polygon^.vertex_count) {
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
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    point: Vector3) -> bool {

    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        polygon^.first_vertex:polygon^.first_vertex + polygon^.vertex_count]
    triangles := cache^.polygon_triangles[
        polygon^.first_triangle:polygon^.first_triangle + polygon^.triangle_count]

    for tri in triangles {
        local_a := tri.a - polygon^.first_vertex
        local_b := tri.b - polygon^.first_vertex
        local_c := tri.c - polygon^.first_vertex
        if !polygon_triangle_indices_valid(
            shapemodel.Shapes_Polygon_Triangle{local_a, local_b, local_c},
            polygon^.vertex_count) {
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
    pen: ^shapemodel.Shapes_Pen_Draw,
    point0, point1: Vector3) {

    c0 := view_core.iso_to_cartesian(point0, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(point1, state^.iso_scale^)
    draw_tool_brush_segment(
        state, c0, c1, pen^.brush_size, render_raylib.color(pen^.color))
}

//   Build the z=0-clipped segment and oriented polygon plane for one crossing test.
//
// Parameters:
//   - ctx: Destination populated when ok.
//
// Returns:
//   - ok: true when the segment clips against z=0 and the polygon plane resolves.
pen_polygon_clip_context :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    ctx: ^Pen_Polygon_Clip_Context) -> bool {

    if !z_split_clip_segment_halfspace(
        pen^.joint1,
        pen^.joint2,
        true,
        &ctx^.stage0_start,
        &ctx^.stage0_end) {
        return false
    }

    if !polygon_plane(state, polygon, &ctx^.plane_point, &ctx^.plane_normal) {
        return false
    }

    // Keep front/back classification stable regardless of polygon triangle winding.
    if linalg.dot(ctx^.plane_normal, PEN_CLIP_FRONT_DIRECTION) < 0 {
        ctx^.plane_normal *= -1.0
    }

    pen_polygon_apply_bottom_bias(pen, ctx)
    pen_polygon_measure_sides(ctx)
    return true
}

//   Bias the nearer clip endpoint downward to stabilize front/back ordering.
pen_polygon_apply_bottom_bias :: proc(
    pen: ^shapemodel.Shapes_Pen_Draw, ctx: ^Pen_Polygon_Clip_Context) {

    ctx^.clip_start = ctx^.stage0_start
    ctx^.clip_end = ctx^.stage0_end
    start_d := ctx^.stage0_start - pen^.joint1
    end_d := ctx^.stage0_end - pen^.joint1
    if linalg.dot(start_d, start_d) <= linalg.dot(end_d, end_d) {
        ctx^.clip_start += PEN_BOTTOM_CLIP_BIAS
    } else {
        ctx^.clip_end += PEN_BOTTOM_CLIP_BIAS
    }
}

//   Measure signed distances and plane-side classification for both endpoints.
pen_polygon_measure_sides :: proc(ctx: ^Pen_Polygon_Clip_Context) {
    ctx^.raw_distance0 = plane_signed_distance(
        ctx^.stage0_start, ctx^.plane_point, ctx^.plane_normal)
    ctx^.raw_distance1 = plane_signed_distance(
        ctx^.stage0_end, ctx^.plane_point, ctx^.plane_normal)
    ctx^.side0 = tool_plane_side(
        plane_signed_distance(ctx^.clip_start, ctx^.plane_point, ctx^.plane_normal))
    ctx^.side1 = tool_plane_side(
        plane_signed_distance(ctx^.clip_end, ctx^.plane_point, ctx^.plane_normal))
    ctx^.on_plane0 = math.abs(ctx^.raw_distance0) <= TOOL_POLYGON_CLIP_EPSILON
    ctx^.on_plane1 = math.abs(ctx^.raw_distance1) <= TOOL_POLYGON_CLIP_EPSILON
}

//   Record the whole segment as front or back when both ends share one side.
//
// Returns:
//   - ok: true when the contact point is inside the polygon.
pen_polygon_same_side_part :: proc(
    state: ^Euclid_General_State,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    ctx: ^Pen_Polygon_Clip_Context,
    crossing: ^Pen_Polygon_Crossing) -> bool {

    if !(ctx^.on_plane0 || ctx^.on_plane1) {
        return false
    }

    contact_point := ctx^.stage0_start
    if !ctx^.on_plane0 && ctx^.on_plane1 {
        contact_point = ctx^.stage0_end
    }
    if !point_inside_polygon(state, polygon, contact_point) {
        return false
    }

    if ctx^.side0 > 0 {
        crossing^.front0 = ctx^.stage0_start
        crossing^.front1 = ctx^.stage0_end
        crossing^.has_front = segment_has_length(crossing^.front0, crossing^.front1)
        return crossing^.has_front
    }

    crossing^.back0 = ctx^.stage0_start
    crossing^.back1 = ctx^.stage0_end
    crossing^.has_back = segment_has_length(crossing^.back0, crossing^.back1)
    return crossing^.has_back
}

//   Resolve the unbiased plane-crossing point along the original segment.
//
// Returns:
//   - ok: true when the intersection is computable and inside the polygon.
pen_polygon_resolve_crossing_point :: proc(
    state: ^Euclid_General_State,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    ctx: ^Pen_Polygon_Clip_Context,
    out: ^Vector3) -> bool {

    intersection := Vector3{}
    if !segment_plane_intersection(
        ctx^.clip_start,
        ctx^.clip_end,
        ctx^.plane_point,
        ctx^.plane_normal,
        &intersection) {
        return false
    }
    if !point_inside_polygon(state, polygon, intersection) {
        return false
    }

    clip_direction := ctx^.clip_end - ctx^.clip_start
    clip_len_sq := linalg.dot(clip_direction, clip_direction)
    if clip_len_sq <= TOOL_POLYGON_SEGMENT_EPSILON {
        return false
    }
    t := linalg.dot(intersection-ctx^.clip_start, clip_direction) / clip_len_sq
    t = math.clamp(t, 0, 1)
    out^ = linalg.lerp(ctx^.stage0_start, ctx^.stage0_end, t)
    return true
}

//   Split the segment at its plane intersection into back and front parts.
//
// Returns:
//   - ok: true when the split point lies inside the polygon.
pen_polygon_split_part :: proc(
    state: ^Euclid_General_State,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    ctx: ^Pen_Polygon_Clip_Context,
    crossing: ^Pen_Polygon_Crossing) -> bool {

    intersection_unbiased := Vector3{}
    if !pen_polygon_resolve_crossing_point(
        state, polygon, ctx, &intersection_unbiased) {
        return false
    }

    if ctx^.side0 < ctx^.side1 {
        crossing^.back0 = ctx^.stage0_start
        crossing^.back1 = intersection_unbiased
        crossing^.front0 = intersection_unbiased
        crossing^.front1 = ctx^.stage0_end
    } else {
        crossing^.back0 = ctx^.stage0_end
        crossing^.back1 = intersection_unbiased
        crossing^.front0 = intersection_unbiased
        crossing^.front1 = ctx^.stage0_start
    }

    crossing^.has_back = segment_has_length(crossing^.back0, crossing^.back1)
    crossing^.has_front = segment_has_length(crossing^.front0, crossing^.front1)
    return crossing^.has_back || crossing^.has_front
}

//   Build one pen/polygon crossing event using z=0 clipping as stage one.
build_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    polygon: ^shapemodel.Shapes_Polygon_Draw,
    crossing: ^Pen_Polygon_Crossing) -> bool {

    ctx: Pen_Polygon_Clip_Context
    if !pen_polygon_clip_context(state, pen, polygon, &ctx) {
        return false
    }

    crossing^.has_back = false
    crossing^.has_front = false

    if ctx.side0 == ctx.side1 {
        return pen_polygon_same_side_part(state, polygon, &ctx, crossing)
    }

    return pen_polygon_split_part(state, polygon, &ctx, crossing)
}

//   Find the first cached pen draw item in the merged cache.
//
// Returns:
//   - pen: The pen draw item when found.
//   - pen_index: Cache index of the pen item, or -1.
find_cached_pen_item :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache) -> (shapemodel.Shapes_Pen_Draw, int) {

    pen := shapemodel.Shapes_Pen_Draw{}
    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case shapemodel.Shapes_Pen_Draw:
            return item_typed, i
        case shapemodel.Shapes_Label_Draw,
            shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw,
            shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw,
            shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Polygon_Draw,
            shapemodel.Shapes_Trochoid_Tool_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw,
            shapemodel.Shapes_Compass_Draw:
        }
    }
    return pen, -1
}

// Find the first cached trochoid-guide draw item in the merged cache.
find_cached_trochoid_tool_item :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache) -> (
        shapemodel.Shapes_Trochoid_Tool_Draw, int) {
    tool := shapemodel.Shapes_Trochoid_Tool_Draw{}
    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case shapemodel.Shapes_Trochoid_Tool_Draw:
            return item_typed, i
        case shapemodel.Shapes_Label_Draw,
            shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw,
            shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw,
            shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Polygon_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw,
            shapemodel.Shapes_Pen_Draw,
            shapemodel.Shapes_Compass_Draw:
        }
    }
    return tool, -1
}

//   Find the first cached compass draw item in the merged cache.
find_cached_compass_item :: proc(
    cache: ^shapemodel.Shapes_Draw_Cache) -> (shapemodel.Shapes_Compass_Draw, int) {
    compass := shapemodel.Shapes_Compass_Draw{}
    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case shapemodel.Shapes_Compass_Draw:
            return item_typed, i
        case shapemodel.Shapes_Label_Draw,
            shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw,
            shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw,
            shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Polygon_Draw,
            shapemodel.Shapes_Trochoid_Tool_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw,
            shapemodel.Shapes_Pen_Draw:
        }
    }
    return compass, -1
}

//   Find one elevated polygon that crosses the given pen segment.
find_pen_crossing_polygon :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    pen_index: int,
    out_crossing: ^Pen_Polygon_Crossing) -> bool {

    cache := &state^.shape_world^.draw_cache
    for i in 0..<cache^.item_count {
        switch &item_typed in &cache^.items[i] {
        case shapemodel.Shapes_Polygon_Draw:
            if !draw_cached_polygon_is_elevated(state, &item_typed) {
                continue
            }

            trial := Pen_Polygon_Crossing{}
            if !build_pen_polygon_crossing(state, pen, &item_typed, &trial) {
                continue
            }

            trial.pen_index = pen_index
            trial.polygon_index = i
            trial.pen = pen^
            trial.polygon = item_typed
            out_crossing^ = trial
            return true
        case shapemodel.Shapes_Label_Draw,
            shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw,
            shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw,
            shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Trochoid_Tool_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw,
            shapemodel.Shapes_Pen_Draw,
            shapemodel.Shapes_Compass_Draw:
        }
    }
    return false
}

//   Find one pen/polygon crossing pair in current high merged cache items.
find_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    out_crossing: ^Pen_Polygon_Crossing) -> bool {

    cache := &state^.shape_world^.draw_cache
    pen, pen_index := find_cached_pen_item(cache)
    if pen_index < 0 {
        return false
    }

    return find_pen_crossing_polygon(state, &pen, pen_index, out_crossing)
}

//   Draw interleaving for one crossing pen/polygon pair.
draw_pen_polygon_crossing :: proc(
    state: ^Euclid_General_State,
    crossing: ^Pen_Polygon_Crossing,
    compass_caster: ^shapemodel.Shapes_Compass_Draw) {

    draw_cached_pen_active_dot(state, &crossing^.pen)

    begin_tool_brush_mode(state)
    if crossing^.has_back {
        set_pen_compass_occluders(state, &crossing^.pen, compass_caster)
        draw_pen_segment_fragment(
            state, &crossing^.pen, crossing^.back0, crossing^.back1)
        clear_tool_brush_occluder(state)
    }
    end_tool_brush_mode(state)

    draw_cached_polygon(state, &crossing^.polygon)

    begin_tool_brush_mode(state)
    if crossing^.has_front {
        set_pen_compass_occluders(state, &crossing^.pen, compass_caster)
        draw_pen_segment_fragment(state, &crossing^.pen,
            crossing^.front0, crossing^.front1)
        clear_tool_brush_occluder(state)
    }
    end_tool_brush_mode(state)
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

//   Package direct canonical arc parameters for shared sampling passes.
circle_arc_geometry :: #force_inline proc(
    center: Vector3, radius, start_theta, sweep_theta: f32) -> Circle_Arc_Geometry {
    return Circle_Arc_Geometry{
        center = center,
        sweep_delta = sweep_theta,
        radius = radius,
        start_theta = start_theta,
    }
}

//   Sample the world-space arc points from start through the sweep.
circle_arc_sample_world :: proc(
    geom: ^Circle_Arc_Geometry,
    arc_world: []Vector3) {
    seg_count := f32(len(arc_world) - 1)
    for i in 0..<len(arc_world) {
        t := f32(i) / seg_count
        theta := geom^.start_theta + geom^.sweep_delta * t
        arc_world[i] = Vector3{
            geom^.center.x + f32(math.cos(theta)) * geom^.radius,
            geom^.center.y + f32(math.sin(theta)) * geom^.radius,
            geom^.center.z,
        }
    }
}

//   Batch-project world points by first decomposing into x/y/z SoA component slices.
//
// Parameters:
//   - state: Global app state providing the iso scale and SIMD flag.
//   - params: Grouped world points plus SoA scratch and output slices.
//
// Returns:
//   - count: Number of points projected.
project_iso_points_batch_with_components :: proc(
    state: ^Euclid_General_State,
    params: Iso_Batch_Project_Params) -> int {
    count := len(params.world_points)
    if len(params.xs) < count {
        count = len(params.xs)
    }
    if len(params.ys) < count {
        count = len(params.ys)
    }
    if len(params.zs) < count {
        count = len(params.zs)
    }
    if len(params.out) < count {
        count = len(params.out)
    }

    for i in 0..<count {
        p := params.world_points[i]
        params.xs[i] = p.x
        params.ys[i] = p.y
        params.zs[i] = p.z
    }

    projected_count := view_core.iso_to_cartesian_components_batch_selected({
        params.xs[:count],
        params.ys[:count],
        params.zs[:count],
        params.out[:count],
        state^.iso_scale^,
    }, state^.ui_runtime.use_simd_batch_projection)
    rendermetrics.record(
        &state^.render_metrics, .Projected_Vertices, u64(projected_count))
    rendermetrics.record(
        &state^.render_metrics, .Generated_Vertices, u64(projected_count))
    return projected_count
}




//   Render one cached label draw item.
draw_cached_label :: proc(
    state: ^Euclid_General_State, p: ^shapemodel.Shapes_Label_Draw) {
    label := shapemodel.Shape_Label{mime = p.mime, byte_offset = p.source_offset,
        byte_count = p.source_count, revision = p.source_revision}
    source, found :=
        shapemodel.shape_label_source(&state.shape_world.label_store, label)
    if !found {
        return
    }
    c := view_core.iso_to_cartesian(p^.point1, state^.iso_scale^)
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    regular_font := font.cache_borrow(&state.font_cache, .Regular)
    view_core.ui_text_unshaped_paged({
        resolver = resolver,
        key = .Regular,
        text = source,
        position = c,
        color = render_raylib.color(p^.color),
        font = {font = regular_font, font_size = p.brush_size},
    })
}


//   Render one cached point floor shadow.
draw_cached_point_shadow :: proc(
    state: ^Euclid_General_State, p: ^shapemodel.Shapes_Point_Draw) {
    if !shadow_point_is_elevated(p^.point1) {
        return
    }

    shadow := shadow_to_screen(p^.point1, state)
    shadow_color := make_shadow_color(p^.color, p^.point1.z)
    rl.DrawCircleV(shadow, p^.brush_size, shadow_color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}


//   Render one cached line floor shadow.
draw_cached_line_shadow :: proc(
    state: ^Euclid_General_State, l: ^shapemodel.Shapes_Line_Draw) {
    line_points := [2]Vector3{l^.point1, l^.point2}
    if !has_any_elevated_shadow_point(line_points[:]) {
        return
    }

    // Shadow pass keeps only the visible-above-plane fragment for split lines.
    clipped0 := Vector3{}
    clipped1 := Vector3{}
    if !z_split_clip_segment_halfspace(
        l^.point1, l^.point2, true, &clipped0, &clipped1) {
        return
    }

    s0 := shadow_to_screen(clipped0, state)
    s1 := shadow_to_screen(clipped1, state)
    clipped_points := [2]Vector3{clipped0, clipped1}
    avg_height := average_shadow_height(clipped_points[:])
    shadow_color := make_shadow_color(l^.color, avg_height)
    thickness := math.max(l^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    rl.DrawLineEx(s0, s1, thickness, shadow_color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}

// Draw one elevated guide ring as ordinary segmented floor shadows.
draw_trochoid_tool_ring_shadow :: proc(
    state: ^Euclid_General_State,
    center: Vector3,
    radius, brush_size: f32,
    color: colormodel.Color_RGBA8) {
    previous := trochoid_tool_ring_point(center, radius, 0)
    for index in 1..=TROCHOID_TOOL_RING_SEGMENTS {
        angle := 2 * math.PI * f32(index) / f32(TROCHOID_TOOL_RING_SEGMENTS)
        current := trochoid_tool_ring_point(center, radius, angle)
        line := shapemodel.Shapes_Line_Draw{
            base = {brush_size = brush_size, color = color},
            point1 = previous, point2 = current}
        draw_cached_line_shadow(state, &line)
        previous = current
    }
}

// Render elevated floor shadows for both guide rings and the orientation handle.
draw_cached_trochoid_tool_shadow :: proc(
    state: ^Euclid_General_State,
    tool: ^shapemodel.Shapes_Trochoid_Tool_Draw) {
    if !shadow_point_is_elevated(tool^.fixed_center) &&
        !shadow_point_is_elevated(tool^.rolling_center) {
        return
    }
    draw_trochoid_tool_ring_shadow(state, tool^.fixed_center,
        tool^.fixed_radius, tool^.brush_size, tool^.color)
    draw_trochoid_tool_ring_shadow(state, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, tool^.color)
    handle := shapemodel.Shapes_Line_Draw{tool^.base,
        tool^.handle_start, tool^.handle_finish}
    draw_cached_line_shadow(state, &handle)
}

// Render floor shadows for the exact rail, rolling ring, and orientation handle.
draw_cached_cycloid_tool_shadow :: proc(
    state: ^Euclid_General_State,
    tool: ^shapemodel.Shapes_Cycloid_Tool_Draw) {
    baseline := shapemodel.Shapes_Line_Draw{tool^.base,
        tool^.baseline_start, tool^.baseline_finish}
    draw_cached_line_shadow(state, &baseline)
    draw_trochoid_tool_ring_shadow(state, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, tool^.color)
    handle := shapemodel.Shapes_Line_Draw{tool^.base,
        tool^.handle_start, tool^.handle_finish}
    draw_cached_line_shadow(state, &handle)
}

// Render floor shadows for every segment in one explicated curve packet.
draw_cached_curve_shadow :: proc(
    state: ^Euclid_General_State, curve: ^shapemodel.Shapes_Curve_Draw) {
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.curve_vertices[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    for index in 1..<len(vertices) {
        line := shapemodel.Shapes_Line_Draw{
            curve^.base, vertices[index - 1], vertices[index]}
        draw_cached_line_shadow(state, &line)
    }
}


//   Render one cached circle/arc floor shadow.
draw_cached_circle_shadow :: proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Circle_Draw) {
    if !shadow_point_is_elevated(c^.center) {
        return
    }

    geom := circle_arc_geometry(
        c^.center, c^.radius, c^.start_theta, c^.sweep_theta)
    thickness := math.max(c^.brush_size * 0.8, SHADOW_MIN_THICKNESS)

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geom, arc_world[:])

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
        rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
    }
}


//   Render one cached filled-circle floor shadow.
draw_cached_filledcircle_shadow :: proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Filled_Circle_Draw) {
    if !shadow_point_is_elevated(c^.center) {
        return
    }

    geom := circle_arc_geometry(
        c^.center, c^.radius, c^.start_theta, c^.sweep_theta)
    shadow_color := make_shadow_color(c^.color, c^.center.z)

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geom, arc_world[:])

    points: [CIRCLE_ARC_SEGMENTS + 2]rl.Vector2
    points[0] = shadow_to_screen(geom.center, state)
    for i in 0..<len(arc_world) {
        points[i + 1] = shadow_to_screen(arc_world[i], state)
    }

    rl.DrawTriangleFan(&points[0], len(points), shadow_color)
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
    rendermetrics.record(
        &state^.render_metrics, .Generated_Indices, u64(CIRCLE_ARC_SEGMENTS * 3))
}


//   Render one cached point draw item.
draw_cached_point :: proc(
    state: ^Euclid_General_State, p: ^shapemodel.Shapes_Point_Draw) {
    c := view_core.iso_to_cartesian(p^.point1, state^.iso_scale^)
    rl.DrawCircleV(c, p^.brush_size, render_raylib.color(p^.color))
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}


//   Render one cached line draw item.
draw_cached_line :: proc(
    state: ^Euclid_General_State, l: ^shapemodel.Shapes_Line_Draw, keep_above: bool) {
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
    rl.DrawLineEx(c0, c1, l^.brush_size, render_raylib.color(color))
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
}

// Render every segment in one explicated curve using ordinary line styling.
draw_cached_curve :: proc(
    state: ^Euclid_General_State,
    curve: ^shapemodel.Shapes_Curve_Draw,
    keep_above: bool) {
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.curve_vertices[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    for index in 1..<len(vertices) {
        line := shapemodel.Shapes_Line_Draw{
            curve^.base, vertices[index - 1], vertices[index]}
        draw_cached_line(state, &line, keep_above)
    }
}


//   Render one cached circle/arc draw item.
draw_cached_circle :: proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Circle_Draw) {
    geom := circle_arc_geometry(
        c^.center, c^.radius, c^.start_theta, c^.sweep_theta)

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geom, arc_world[:])

    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    arc_screen: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(
        state,
        Iso_Batch_Project_Params{
            world_points = arc_world[:],
            xs = xs[:],
            ys = ys[:],
            zs = zs[:],
            out = arc_screen[:],
        })

    for i in 1..=CIRCLE_ARC_SEGMENTS {
            rl.DrawLineEx(
                arc_screen[i - 1], arc_screen[i], c^.brush_size,
                render_raylib.color(c^.color))
            rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
    }
}

//   Render one cached filled-circle draw item.
draw_cached_filledcircle :: proc(
    state: ^Euclid_General_State, c: ^shapemodel.Shapes_Filled_Circle_Draw) {
    geom := circle_arc_geometry(
        c^.center, c^.radius, c^.start_theta, c^.sweep_theta)
    isocenter := view_core.iso_to_cartesian(geom.center, state^.iso_scale^)

    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geom, arc_world[:])

    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    arc_screen: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(
        state,
        Iso_Batch_Project_Params{
            world_points = arc_world[:],
            xs = xs[:],
            ys = ys[:],
            zs = zs[:],
            out = arc_screen[:],
        })

    points: [CIRCLE_ARC_SEGMENTS + 2]rl.Vector2
    points[0] = isocenter
    for i in 0..<len(arc_screen) {
        points[i + 1] = arc_screen[i]
    }

    rl.DrawTriangleFan(&points[0], len(points), render_raylib.color(c^.color))
    rendermetrics.record(&state^.render_metrics, .Primitive_Submissions)
    rendermetrics.record(
        &state^.render_metrics, .Generated_Indices, u64(CIRCLE_ARC_SEGMENTS * 3))
}


//   Batch-project cached polygon vertices into screen space.
project_cached_polygon_vertices :: #force_inline proc(
    state: ^Euclid_General_State,
    poly: ^shapemodel.Shapes_Polygon_Draw,
    projected: []Vector2) -> bool {

    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    xs, ys, zs: [shapemodel.MAX_DRAW_CACHE_POLYGON_VERTICES]f32

    _ = project_iso_points_batch_with_components(
        state,
        Iso_Batch_Project_Params{
            world_points = vertices,
            xs = xs[:],
            ys = ys[:],
            zs = zs[:],
            out = projected,
        })

    return true
}

//   Draw all cached triangles for a polygon using projected vertex positions.
draw_cached_polygon_triangles :: #force_inline proc(
    metrics: ^rendermetrics.State,
    cache: ^shapemodel.Shapes_Draw_Cache,
    poly: ^shapemodel.Shapes_Polygon_Draw,
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
    rendermetrics.record(metrics, .Primitive_Submissions)
    rendermetrics.record(metrics, .Generated_Indices, 3)
    }
}


//   Render one cached polygon floor shadow.
draw_cached_polygon_shadow :: proc(
    state: ^Euclid_General_State, poly: ^shapemodel.Shapes_Polygon_Draw) {
    if poly^.vertex_count < 3 || poly^.triangle_count <= 0 {
        return
    }

    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    if !has_any_elevated_shadow_point(vertices) {
        return
    }

    projected: [shapemodel.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    for i in 0..<poly^.vertex_count {
        projected[i] = shadow_to_screen(vertices[i], state)
    }

    shadow_color := make_shadow_color(poly^.color, average_shadow_height(vertices))
    draw_cached_polygon_triangles(
        &state^.render_metrics, cache, poly, projected[:], shadow_color)
}

//   Render one cached polygon draw item.
draw_cached_polygon :: proc(
    state: ^Euclid_General_State, poly: ^shapemodel.Shapes_Polygon_Draw) {
    if poly^.vertex_count < 3 || poly^.triangle_count <= 0 {
        return
    }

    projected: [shapemodel.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    if !project_cached_polygon_vertices(state, poly, projected[:]) {
        return
    }

    cache := &state^.shape_world^.draw_cache
    draw_cached_polygon_triangles(
        &state^.render_metrics, cache, poly, projected[:],
        render_raylib.color(poly^.color))
}


//   Upload relevant compass legs as casters for one pen receiver.
set_pen_compass_occluders :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    compass: ^shapemodel.Shapes_Compass_Draw) {
    ctx := Tool_Brush_Occluder_Context{}
    if compass != nil {
        receiver := make_tool_brush_occluder(
            state, pen^.joint1, pen^.joint2, pen^.brush_size)
        leg1 := make_tool_brush_occluder(
            state, compass^.joint1, compass^.pivot, compass^.brush_size)
        leg2 := make_tool_brush_occluder(
            state, compass^.pivot, compass^.joint2, compass^.brush_size)
        append_tool_brush_occluder(&ctx, receiver, leg1)
        append_tool_brush_occluder(&ctx, receiver, leg2)
    }
    set_tool_brush_occluders(state, &ctx)
}


//   Render one cached pen tool draw item.
draw_cached_pen :: proc(
    state: ^Euclid_General_State,
    pen: ^shapemodel.Shapes_Pen_Draw,
    compass_caster: ^shapemodel.Shapes_Compass_Draw) {
    c0 := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)

    set_pen_compass_occluders(state, pen, compass_caster)
    draw_tool_brush_segment(
        state, c0, c1, pen^.brush_size, render_raylib.color(pen^.color))
    clear_tool_brush_occluder(state)
}


//   Render active-end indicator for cached pen tool.
draw_cached_pen_active_dot :: proc(
    state: ^Euclid_General_State, pen: ^shapemodel.Shapes_Pen_Draw) {
    c0 := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    c1 := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)

    if pen^.active_child == 1 {
        active := pen^.color
        if pen^.has_active_color {
            active = pen^.active_color
        }
        rl.DrawCircleV(c0, pen^.brush_size, render_raylib.color(active))
    } else if pen^.active_child == 2 {
        active := pen^.color
        if pen^.has_active_color {
            active = pen^.active_color
        }
        rl.DrawCircleV(c1, pen^.brush_size, render_raylib.color(active))
    }
}

//   Compute the orthonormal arc basis, radius, and outside sweep for a compass.
//
// Returns:
//   - basis: Populated basis when ok.
//   - ok: true when the leg vectors are non-degenerate and radius is positive.
compass_top_circle_basis :: proc(
    p0, p1, p2: Vector3) -> (Compass_Top_Circle_Basis, bool) {
    basis := Compass_Top_Circle_Basis{}

    a := p0 - p1
    b := p2 - p1
    a_len := linalg.length(a)
    b_len := linalg.length(b)
    if a_len <= 0.00001 || b_len <= 0.00001 {
        return basis, false
    }

    an := a / a_len
    bn := b / b_len
    n := linalg.cross(an, bn)
    n_len := linalg.length(n)
    if n_len <= 0.00001 {
        return basis, false
    }
    n /= n_len

    dot_ab := math.clamp(linalg.dot(an, bn), -1, 1)
    cross_ab := linalg.cross(an, bn)
    theta_short := math.atan2(linalg.dot(n, cross_ab), dot_ab)

    sign := f32(1.0)
    if theta_short < 0 {
        sign = -1.0
    }
    basis.theta_out = theta_short - 2.0 * math.PI * sign
    basis.u = an
    basis.v = linalg.normalize(linalg.cross(n, basis.u))
    basis.radius = math.min(a_len, b_len) * COMPASS_TOPCIRCLE_RADIUS
    if basis.radius <= 0 {
        return basis, false
    }
    return basis, true
}

//   Return the normalized arc extent occupied by one welded attachment.
compass_arc_attachment_extent :: #force_inline proc(
    brush_size, arc_radius, sweep, half_scale: f32) -> f32 {
    arc_length_pixels := math.abs(sweep) * arc_radius * math.max(half_scale, 0.0001)
    return math.clamp(brush_size * 1.5 / math.max(arc_length_pixels, brush_size),
        1.0 / f32(COMPASS_TOPCIRCLE_SEGMENTS), 0.18)
}

//   Return the normalized parameter for one fixed compass arc sample.
compass_arc_parameter :: #force_inline proc(index: int) -> f32 {
    return f32(index) / f32(COMPASS_TOPCIRCLE_SEGMENTS)
}

//   Build fixed strip samples with exact centerline depth and arc parameter.
build_compass_arc_samples :: proc(
    center: Vector3,
    basis: Compass_Top_Circle_Basis,
    draw: Compass_Arc_Draw,
    coverage_radius: f32,
    samples: ^Compass_Arc_Samples) -> bool {
    step := basis.theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)
    for i in 0..=COMPASS_TOPCIRCLE_SEGMENTS {
        parameter := compass_arc_parameter(i)
        angle := step * f32(i)
        direction := basis.u * math.cos(angle) + basis.v * math.sin(angle)
        tangent3d := -basis.u * math.sin(angle) + basis.v * math.cos(angle)
        center3d := center + direction * basis.radius
        projected := view_core.iso_to_cartesian(center3d, draw.state^.iso_scale^)
        tangent_point := view_core.iso_to_cartesian(
            center3d + tangent3d, draw.state^.iso_scale^)
        tangent := tangent_point - projected
        tangent_length := linalg.length(tangent)
        if tangent_length <= 0.0001 {
            return false
        }
        tangent /= tangent_length
        perpendicular := Vector2{-tangent.y, tangent.x}
        samples^.tangents_view[i] =
            linalg.normalize(tool_brush_light_to_view(tangent3d))
        samples^.left[i] = projected - perpendicular * coverage_radius
        samples^.right[i] = projected + perpendicular * coverage_radius
        samples^.auxiliary[i] = Vector2{tool_brush_view_depth(center3d), parameter}
    }
    return true
}

//   Emit one encoded strip vertex carrying tangent, side, depth, and parameter.
emit_tool_brush_strip_vertex :: #force_inline proc(
    position, auxiliary: Vector2, tangent_view: Vector3, side: u8) {
    red := u8(math.clamp((tangent_view.x * 0.5 + 0.5) * 255.0, 0.0, 255.0))
    green := u8(math.clamp((tangent_view.y * 0.5 + 0.5) * 255.0, 0.0, 255.0))
    blue := u8(math.clamp((tangent_view.z * 0.5 + 0.5) * 255.0, 0.0, 255.0))
    rlgl.TexCoord2f(auxiliary.x, auxiliary.y)
    rlgl.Color4ub(red, green, blue, side)
    rlgl.Vertex2f(position.x, position.y)
}

//   Upload shader parameters for one lit compass outside-arc strip.
set_compass_arc_shader_uniforms :: proc(
    draw: Compass_Arc_Draw,
    basis: Compass_Top_Circle_Basis,
    side_extent: f32) {

    state := draw.state
    shader := &state^.stroke_3d
    set_tool_brush_uniform_float(state, shader^.loc_stroke_mode, 1.0)
    set_tool_brush_uniform_float(
        state, shader^.loc_strip_alpha, f32(draw.color.a) / 255.0)
    set_tool_brush_uniform_vec3(state, shader^.loc_strip_color, Vector3{
        f32(draw.color.r) / 255.0,
        f32(draw.color.g) / 255.0,
        f32(draw.color.b) / 255.0,
    })
    set_tool_brush_uniform_float(state, shader^.loc_strip_side_extent, side_extent)
    depth_width := draw.brush_size /
        math.max(state^.iso_scale^.half_scale, 0.0001)
    attachment_extent := compass_arc_attachment_extent(
        draw.brush_size, basis.radius, basis.theta_out,
        state^.iso_scale^.half_scale)
    set_tool_brush_uniform_float(
        state, shader^.loc_intersection_depth_width, depth_width)
    set_tool_brush_uniform_float(
        state, shader^.loc_attachment_extent, attachment_extent)
    set_tool_brush_uniform_float(state, shader^.loc_arc_intersections_enabled, 1.0)
}

//   Emit the triangles for one sampled compass outside-arc strip.
emit_compass_arc_strip :: proc(samples: ^Compass_Arc_Samples) {
    for i in 0..<COMPASS_TOPCIRCLE_SEGMENTS {
        emit_tool_brush_strip_vertex(
            samples^.left[i], samples^.auxiliary[i], samples^.tangents_view[i], 0)
        emit_tool_brush_strip_vertex(
            samples^.right[i], samples^.auxiliary[i], samples^.tangents_view[i], 255)
        emit_tool_brush_strip_vertex(samples^.left[i + 1], samples^.auxiliary[i + 1],
            samples^.tangents_view[i + 1], 0)
        emit_tool_brush_strip_vertex(
            samples^.right[i], samples^.auxiliary[i], samples^.tangents_view[i], 255)
        emit_tool_brush_strip_vertex(samples^.right[i + 1], samples^.auxiliary[i + 1],
            samples^.tangents_view[i + 1], 255)
        emit_tool_brush_strip_vertex(samples^.left[i + 1], samples^.auxiliary[i + 1],
            samples^.tangents_view[i + 1], 0)
    }
}


//   Draw the compass outside arc without the tool shader.
draw_outside_arc_compass_fallback :: proc(
    center: Vector3, basis: Compass_Top_Circle_Basis, draw: Compass_Arc_Draw) {
    step := basis.theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)
    prev3d := center + basis.u * basis.radius
    prev := view_core.iso_to_cartesian(prev3d, draw.state^.iso_scale^)
    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := basis.u * math.cos(t) + basis.v * math.sin(t)
        curr3d := center + dir * basis.radius
        curr := view_core.iso_to_cartesian(curr3d, draw.state^.iso_scale^)
        rl.DrawLineEx(prev, curr, draw.brush_size, draw.color)
        prev = curr
    }
}


//   Emit one continuous shader-lit strip for the compass arc outside the swing angle.
draw_outside_arc_compass_cached :: proc(
    p0, p1, p2: Vector3, draw: Compass_Arc_Draw) {
    basis, ok := compass_top_circle_basis(p0, p1, p2)
    if !ok {
        return
    }

    state := draw.state
    if !state^.stroke_3d.ready {
        draw_outside_arc_compass_fallback(p1, basis, draw)
        return
    }

    scale := get_tool_brush_render_scale()
    min_scale := math.max(math.min(scale.x, scale.y), 0.0001)
    radius := draw.brush_size * 0.5
    coverage_radius := radius + 1.0 / min_scale
    side_extent := coverage_radius / math.max(radius, 0.0001)
    samples := Compass_Arc_Samples{}
    if !build_compass_arc_samples(p1, basis, draw, coverage_radius, &samples) {
        return
    }

    rlgl.DrawRenderBatchActive()
    rendermetrics.record(&state^.render_metrics, .Rlgl_Batches)
    set_compass_arc_shader_uniforms(draw, basis, side_extent)

    _ = rlgl.CheckRenderBatchLimit(COMPASS_TOPCIRCLE_SEGMENTS * 6)
    rlgl.SetTexture(rlgl.GetTextureIdDefault())
    rlgl.DisableBackfaceCulling()
    rlgl.Begin(rlgl.TRIANGLES)
    emit_compass_arc_strip(&samples)
    rlgl.End()

    rlgl.DrawRenderBatchActive()
    rlgl.EnableBackfaceCulling()
    set_tool_brush_uniform_float(
        state, state^.stroke_3d.loc_arc_intersections_enabled, 0.0)
    set_tool_brush_uniform_float(state, state^.stroke_3d.loc_stroke_mode, 0.0)
}

//   Draw one compass leg with its sibling and optional pen occluders.
draw_cached_compass_leg :: proc(
    ctx: ^Compass_Leg_Draw_Context,
    joint1_leg: bool,
    sibling_occludes: bool) {

    start, finish := ctx^.c1, ctx^.c2
    receiver, sibling := ctx^.leg2, ctx^.leg1
    if joint1_leg {
        start, finish = ctx^.c0, ctx^.c1
        receiver, sibling = ctx^.leg1, ctx^.leg2
    }

    occluders := Tool_Brush_Occluder_Context{}
    if sibling_occludes {
        append_tool_brush_occluder(&occluders, receiver, sibling)
    }
    if ctx^.has_pen_occluder {
        append_tool_brush_occluder(&occluders, receiver, ctx^.pen_occluder)
    }
    set_tool_brush_occluders(ctx^.state, &occluders)
    draw_tool_brush_segment(ctx^.state, start, finish,
        ctx^.comp^.brush_size, render_raylib.color(ctx^.comp^.color))
}


//   Render one cached compass tool draw item.
draw_cached_compass :: proc(
    state: ^Euclid_General_State,
    comp: ^shapemodel.Shapes_Compass_Draw,
    pen_caster: ^shapemodel.Shapes_Pen_Draw) {
    ctx := Compass_Leg_Draw_Context{
        state = state,
        comp = comp,
        c0 = view_core.iso_to_cartesian(comp^.joint1, state^.iso_scale^),
        c1 = view_core.iso_to_cartesian(comp^.pivot, state^.iso_scale^),
        c2 = view_core.iso_to_cartesian(comp^.joint2, state^.iso_scale^),
        leg1 = make_tool_brush_occluder(
            state, comp^.joint1, comp^.pivot, comp^.brush_size),
        leg2 = make_tool_brush_occluder(
            state, comp^.pivot, comp^.joint2, comp^.brush_size),
        has_pen_occluder = pen_caster != nil,
    }
    if ctx.has_pen_occluder {
        ctx.pen_occluder = make_tool_brush_occluder(
            state, pen_caster^.joint1, pen_caster^.joint2, pen_caster^.brush_size)
    }

    draw_joint1_last := compass_draw_joint1_leg_last(comp, ctx.c0, ctx.c1, ctx.c2)
    if draw_joint1_last {
        draw_cached_compass_leg(&ctx, false, true)
        draw_cached_compass_leg(&ctx, true, false)
    } else {
        draw_cached_compass_leg(&ctx, true, true)
        draw_cached_compass_leg(&ctx, false, false)
    }

    arc_occluders := make_compass_arc_occluders(ctx.leg1, ctx.leg2)
    set_tool_brush_occluders(state, &arc_occluders)
    draw_outside_arc_compass_cached(comp^.joint1, comp^.pivot, comp^.joint2,
        Compass_Arc_Draw{state, comp^.brush_size, render_raylib.color(comp^.color)})
    clear_tool_brush_occluder(state)
}


//   Render active-end indicator for cached compass tool.
draw_cached_compass_active_dot :: proc(
    state: ^Euclid_General_State, comp: ^shapemodel.Shapes_Compass_Draw) {
    c0 := view_core.iso_to_cartesian(comp^.joint1, state^.iso_scale^)
    c2 := view_core.iso_to_cartesian(comp^.joint2, state^.iso_scale^)

    if comp^.active_child == 1 {
        active := comp^.color
        if comp^.has_active_color {
            active = comp^.active_color
        }
        rl.DrawCircleV(c0, comp^.brush_size, render_raylib.color(active))
    } else if comp^.active_child == 3 {
        active := comp^.color
        if comp^.has_active_color {
            active = comp^.active_color
        }
        rl.DrawCircleV(c2, comp^.brush_size, render_raylib.color(active))
    }
}


//   Render floor shadow for cached pen tool geometry.
draw_cached_pen_shadow :: proc(
    state: ^Euclid_General_State, pen: ^shapemodel.Shapes_Pen_Draw) {
    s0 := shadow_to_screen(pen^.joint1, state)
    s1 := shadow_to_screen(pen^.joint2, state)

    avg_height := (pen^.joint1.z + pen^.joint2.z) * 0.5
    shadow_color := make_shadow_color(pen^.color, avg_height)
    thickness := math.max(pen^.brush_size * 0.8, SHADOW_MIN_THICKNESS)

    rl.DrawLineEx(s0, s1, thickness, shadow_color)
}


//   Render floor-shadow arc segment outside the compass swing angle.
draw_outside_arc_compass_shadow_cached :: proc(
    p0, p1, p2: Vector3, draw: Compass_Arc_Draw) {
    if draw.brush_size <= 0 {
        return
    }

    basis, ok := compass_top_circle_basis(p0, p1, p2)
    if !ok {
        return
    }

    state := draw.state
    step := basis.theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)
    prev3d := p1 + basis.u * basis.radius
    prev := shadow_to_screen(prev3d, state)

    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := basis.u * math.cos(t) + basis.v * math.sin(t)
        curr3d := p1 + dir * basis.radius
        curr := shadow_to_screen(curr3d, state)

        rl.DrawLineEx(prev, curr, draw.brush_size, draw.color)
        prev = curr
    }
}


//   Render floor shadow for cached compass tool geometry.
draw_cached_compass_shadow :: proc(
    state: ^Euclid_General_State, comp: ^shapemodel.Shapes_Compass_Draw) {
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

    draw_outside_arc_compass_shadow_cached(comp^.joint1, comp^.pivot, comp^.joint2,
        Compass_Arc_Draw{state, thickness, shadow_color})
}
