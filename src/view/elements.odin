package view

import native "native"

import viewmodel "model"

import shapemodel "../shapes/model"
import color "../core/color"
import geometry "../core/geometry"

// We draw the basic surface and all the shapes and tools here

// Only the tools are drawn with shaders. Everything else is the ordinary 2D tools,
// drawn with an isometric projection

import view_core "core"

import "core:math"
import "core:math/linalg"

Tool_Brush_Material :: struct {
    roughness:     f32,
    fresnel_0:     f32,
    specular_tint: f32,
    shadow_limit:  f32,
}

Tool_Segment_Draw :: struct {
    first, second: Vector2,
    thickness: f32,
    color: color.Color_RGBA8,
    occluders: ^Tool_Brush_Occluder_Context,
}

Tool_Ring_Draw :: struct {
    center: Vector3,
    radius, thickness: f32,
    color: color.Color_RGBA8,
}

Tool_Shadow_Line_Draw :: struct {
    first, second: Vector3,
    thickness, average_height: f32,
}

Compass_Arc_Submission :: struct {
    compass: ^shapemodel.Shapes_Compass_Draw,
    basis: Compass_Top_Circle_Basis,
    samples: ^Compass_Arc_Samples,
    coverage_radius: f32,
    occluders: ^Tool_Brush_Occluder_Context,
}

Pen_Fragment_Draw :: struct {
    pen: ^shapemodel.Shapes_Pen_Draw,
    first, second: Vector2,
    compass: ^shapemodel.Shapes_Compass_Draw,
}

CIRCLE_ARC_SEGMENTS :: 96
CIRCLE_CLOSED_SWEEP_EPSILON :: 0.0001
MAX_CURVE_VISIBLE_POINTS :: (shapemodel.MAX_DRAW_CACHE_CURVE_VERTICES - 1) * 2
MAX_CURVE_VISIBLE_RUNS :: shapemodel.MAX_DRAW_CACHE_CURVE_VERTICES

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
COLORED_STROKE_MITER_LIMIT :: 4.0

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

// Locate one contiguous projected curve run in caller-owned bounded storage.
Curve_Visible_Run :: struct {
    first_point: int,
    point_count: int,
    topology: shapemodel.Curve_Topology,
}

// Group caller-owned outputs used to build clipped projected curve runs.
Curve_Visible_Run_Buffers :: struct {
    points: []Vector2,
    kinds: []shapemodel.Curve_Point_Kind,
    runs: []Curve_Visible_Run,
}

// Report the initialized output prefixes from one visible-run build.
Curve_Visible_Run_Result :: struct {
    point_count: int,
    run_count: int,
    ok: bool,
}

// Define logical-pixel error limits for deterministic projected reduction.
Curve_Reduction_Budget :: struct {
    center_error: f32,
    stroke_error: f32,
    miter_limit: f32,
}

// Report bounded candidate and retained counts after projected reduction.
Curve_Reduction_Result :: struct {
    candidate_count: int,
    retained_count: int,
    ok: bool,
}

Curve_Reduction_Run_Summary :: struct {
    retained_count: int,
    second_index: int,
    before_last_index: int,
    last_index: int,
}

// Hold exact visible-run capacity requirements before output mutation.
Curve_Visible_Run_Counts :: struct {
    point_count: int,
    run_count: int,
    unchanged: bool,
}

// Group source geometry and projection policy for one visible-run build.
Curve_Visible_Run_Input :: struct {
    scale: viewmodel.Iso_Scale,
    points: []Vector3,
    kinds: []shapemodel.Curve_Point_Kind,
    topology: shapemodel.Curve_Topology,
    keep_above: bool,
    shadow: bool,
}

Curve_Visible_Edge_Kind :: enum u8 {
    Hidden,
    Inside,
    Exit,
    Entry,
}

// Hold bounded write state while contiguous visible runs are assembled.
Curve_Visible_Run_Writer :: struct {
    input: Curve_Visible_Run_Input,
    buffers: Curve_Visible_Run_Buffers,
    point_count: int,
    run_count: int,
    run_start: int,
    active: bool,
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


//   Render the base isometric drawing plane and its border triangles.
//
// Parameters:
//   - state: Global app state providing surface geometry and iso projection scale.
//
// Returns:
//   - none.

// draw_encoded_drawing_surface encodes the projected plane and border triangles.
draw_encoded_drawing_surface :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder) {
    room := state^.draw_surface
    edge_size := room.edge_size
    world_points := [8]Vector3{room.zeros, room.right_up, room.left_down,
        room.right_down, room^.zeros + {edge_size, edge_size, 0},
        room^.right_up + {-edge_size, edge_size, 0},
        room^.left_down + {edge_size, -edge_size, 0},
        room^.right_down + {-edge_size, -edge_size, 0}}
    xs, ys, zs: [8]f32
    projected: [8]Vector2
    _ = project_iso_points_batch_with_components(state, {
        world_points = world_points[:], xs = xs[:], ys = ys[:],
        zs = zs[:], out = projected[:]})
    edge_color := room.edge_color
    surface_color := room.color
    _ = native.draw_encoder_triangle(encoder, geometry.Vector2(projected[0]),
        geometry.Vector2(projected[1]), geometry.Vector2(projected[2]), edge_color)
    _ = native.draw_encoder_triangle(encoder, geometry.Vector2(projected[3]),
        geometry.Vector2(projected[2]), geometry.Vector2(projected[1]), edge_color)
    _ = native.draw_encoder_triangle(encoder, geometry.Vector2(projected[4]),
        geometry.Vector2(projected[5]), geometry.Vector2(projected[6]), surface_color)
    _ = native.draw_encoder_triangle(encoder, geometry.Vector2(projected[7]),
        geometry.Vector2(projected[6]), geometry.Vector2(projected[5]), surface_color)
}

//   Render cached low-layer geometry items (labels, primitives, and polygons).
//
// Parameters:
//   - state: Global app state containing the draw cache to render.
//
// Returns:
//   - none.

draw_encoded_basic_point :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Point_Draw, high: bool) {
    if draw_cached_point_is_elevated(item) == high {
        draw_encoded_cached_point(state, encoder, item)
    }
}

// draw_encoded_basic_circle encodes one circle in its matching depth layer.
draw_encoded_basic_circle :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Circle_Draw, high: bool) {
    if draw_cached_circle_is_elevated(item) == high {
        draw_encoded_cached_circle(state, encoder, item)
    }
}

// draw_encoded_basic_filled_circle encodes one filled circle in its matching layer.
draw_encoded_basic_filled_circle :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Filled_Circle_Draw, high: bool) {
    if draw_cached_filledcircle_is_elevated(item) == high {
        draw_encoded_cached_filled_circle(state, encoder, item)
    }
}

// draw_encoded_basic_curve encodes one curve in its matching depth layer.
draw_encoded_basic_curve :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Curve_Draw, high: bool) {
    if draw_cached_curve_is_elevated(state, item) == high {
        draw_encoded_cached_curve(state, encoder, item, high)
    }
}

// draw_encoded_basic_polygon encodes one polygon in its matching depth layer.
draw_encoded_basic_polygon :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Polygon_Draw, high: bool) {
    if draw_cached_polygon_is_elevated(state, item) == high {
        draw_encoded_cached_polygon(state, encoder, item)
    }
}

// draw_encoded_cached_basic_item dispatches one item in a depth layer.
draw_encoded_cached_basic_item :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Draw_Cache_Item, high: bool) {
    switch &typed in item {
    case shapemodel.Shapes_Point_Draw:
        draw_encoded_basic_point(state, encoder, &typed, high)
    case shapemodel.Shapes_Line_Draw:
        draw_encoded_cached_line(state, encoder, &typed, high)
    case shapemodel.Shapes_Circle_Draw:
        draw_encoded_basic_circle(state, encoder, &typed, high)
    case shapemodel.Shapes_Filled_Circle_Draw:
        draw_encoded_basic_filled_circle(state, encoder, &typed, high)
    case shapemodel.Shapes_Curve_Draw:
        draw_encoded_basic_curve(state, encoder, &typed, high)
    case shapemodel.Shapes_Polygon_Draw:
        draw_encoded_basic_polygon(state, encoder, &typed, high)
    case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Trochoid_Tool_Draw,
        shapemodel.Shapes_Cycloid_Tool_Draw, shapemodel.Shapes_Pen_Draw,
        shapemodel.Shapes_Compass_Draw:
    }
}

// draw_encoded_cached_basic_pass encodes points and lines in one depth layer.
draw_encoded_cached_basic_pass :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder, high: bool) {
    cache := &state^.shape_world^.draw_cache
    for index in 0..<cache^.item_count {
        draw_encoded_cached_basic_item(
            state, encoder, &cache^.items[index], high)
    }
}

// encoded_stroke_vertex_uniforms builds the logical-pixel clip transform.
encoded_stroke_vertex_uniforms :: proc(
    encoder: ^native.Draw_Encoder) -> native.Stroke_Vertex_Uniforms {
    uniforms: native.Stroke_Vertex_Uniforms
    uniforms.clip_from_model[0] = 2 / encoder^.logical_extent.x
    uniforms.clip_from_model[5] = -2 / encoder^.logical_extent.y
    uniforms.clip_from_model[10] = 1
    uniforms.clip_from_model[12] = -1
    uniforms.clip_from_model[13] = 1
    uniforms.clip_from_model[15] = 1
    return uniforms
}

// encoded_stroke_fragment_uniforms builds one lit capsule's physical parameters.
encoded_stroke_fragment_uniforms :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    p0, p1: Vector2, thickness: f32) -> native.Stroke_Fragment_Uniforms {
    scale_x := f32(encoder^.physical_extent.x) / encoder^.logical_extent.x
    scale_y := f32(encoder^.physical_extent.y) / encoder^.logical_extent.y
    average_scale := (scale_x + scale_y) * 0.5
    light := linalg.normalize(-state^.iso_scale^.main_light_dir)
    light = tool_brush_light_to_view(light)
    material := STROKE3D_TITANIUM_MATERIAL
    return {
        light_direction_view = {light.x, light.y, light.z},
        ambient = STROKE3D_AMBIENT,
        diffuse = STROKE3D_DIFFUSE,
        material_roughness = material.roughness,
        material_fresnel_0 = material.fresnel_0,
        material_specular_tint = material.specular_tint,
        material_shadow_limit = material.shadow_limit,
        radius = thickness * 0.5 * average_scale,
        segment_p0 = {p0.x * scale_x, p0.y * scale_y},
        segment_p1 = {p1.x * scale_x, p1.y * scale_y},
    }
}

// encoded_stroke_vertex packs one capsule coverage vertex for stroke3d.vert.
encoded_stroke_vertex :: #force_inline proc(
    position: Vector2, draw_color: color.Color_RGBA8) -> native.Stroke_Vertex {
    inverse_byte := f32(1.0 / 255.0)
    return {
        position = {position.x, position.y, 0},
        color = {f32(draw_color.r) * inverse_byte,
            f32(draw_color.g) * inverse_byte,
            f32(draw_color.b) * inverse_byte,
            f32(draw_color.a) * inverse_byte},
    }
}

// encoded_tool_segment_vertices builds the coverage quad for one tool segment.
encoded_tool_segment_vertices :: proc(
    encoder: ^native.Draw_Encoder, draw: Tool_Segment_Draw) -> [6]native.Stroke_Vertex {
    delta := draw.second - draw.first
    segment_length := linalg.length(delta)
    direction := delta / segment_length
    perpendicular := Vector2{-direction.y, direction.x}
    scale_x := f32(encoder^.physical_extent.x) / encoder^.logical_extent.x
    scale_y := f32(encoder^.physical_extent.y) / encoder^.logical_extent.y
    coverage_radius := draw.thickness * 0.5 + 1 / min(scale_x, scale_y)
    start := draw.first - direction * coverage_radius
    finish := draw.second + direction * coverage_radius
    offset := perpendicular * coverage_radius
    corners := [4]Vector2{start - offset, start + offset,
        finish - offset, finish + offset}
    return {
        encoded_stroke_vertex(corners[0], draw.color),
        encoded_stroke_vertex(corners[1], draw.color),
        encoded_stroke_vertex(corners[2], draw.color),
        encoded_stroke_vertex(corners[2], draw.color),
        encoded_stroke_vertex(corners[1], draw.color),
        encoded_stroke_vertex(corners[3], draw.color),
    }
}

// draw_encoded_tool_segment emits one lit capsule or its native 2D fallback.
draw_encoded_tool_segment :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    draw: Tool_Segment_Draw) {
    p0, p1 := draw.first, draw.second
    thickness, draw_color := draw.thickness, draw.color
    delta := p1 - p0
    segment_length := linalg.length(delta)
    if segment_length <= 0 || thickness <= 0 {return}
    if !encoder^.strokes_enabled {
        points := [2]geometry.Vector2{geometry.Vector2(p0), geometry.Vector2(p1)}
        style := native.Draw_Polyline_Style{width = thickness,
            miter_limit = COLORED_STROKE_MITER_LIMIT, color = draw_color,
            topology = .Open, start_cap = .Round, finish_cap = .Round}
        _ = native.draw_encoder_polyline(encoder, points[:], nil, style)
        return
    }
    vertices := encoded_tool_segment_vertices(encoder, draw)
    fragment_uniforms := encoded_stroke_fragment_uniforms(
        state, encoder, p0, p1, thickness)
    encoded_stroke_pack_occluders(
        &fragment_uniforms, encoder, draw.occluders)
    appended := native.draw_encoder_append_stroke(encoder, vertices[:],
        encoded_stroke_vertex_uniforms(encoder), fragment_uniforms)
    if !appended {
        points := [2]geometry.Vector2{geometry.Vector2(p0), geometry.Vector2(p1)}
        style := native.Draw_Polyline_Style{width = thickness,
            miter_limit = COLORED_STROKE_MITER_LIMIT, color = draw_color,
            topology = .Open, start_cap = .Round, finish_cap = .Round}
        _ = native.draw_encoder_polyline(encoder, points[:], nil, style)
    }
}

// draw_encoded_cached_pen restores one cached pen and its active-end indicator.
draw_encoded_cached_pen :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    pen: ^shapemodel.Shapes_Pen_Draw,
    compass_caster: ^shapemodel.Shapes_Compass_Draw = nil) {
    first := view_core.iso_to_cartesian(pen^.joint1, state^.iso_scale^)
    second := view_core.iso_to_cartesian(pen^.joint2, state^.iso_scale^)
    if pen^.active_child == 1 || pen^.active_child == 2 {
        active := pen^.color
        if pen^.has_active_color {active = pen^.active_color}
        center := first
        if pen^.active_child == 2 {center = second}
        _ = native.draw_encoder_circle(
            encoder, geometry.Vector2(center), pen^.brush_size, active)
    }
    occluders := Tool_Brush_Occluder_Context{}
    if compass_caster != nil {
        receiver := make_tool_brush_occluder(
            state, pen^.joint1, pen^.joint2, pen^.brush_size)
        first_leg := make_tool_brush_occluder(state, compass_caster^.joint1,
            compass_caster^.pivot, compass_caster^.brush_size)
        second_leg := make_tool_brush_occluder(state, compass_caster^.pivot,
            compass_caster^.joint2, compass_caster^.brush_size)
        append_tool_brush_occluder(&occluders, receiver, first_leg)
        append_tool_brush_occluder(&occluders, receiver, second_leg)
    }
    draw_encoded_tool_segment(state, encoder, {
        first = first, second = second, thickness = pen^.brush_size,
        color = pen^.color, occluders = &occluders})
}

// draw_encoded_cached_shadow_pass encodes ordinary floor shadows in cache order.
draw_encoded_cached_shadow_pass :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder) {
    cache := &state^.shape_world^.draw_cache
    for index in 0..<cache^.item_count {
        switch &item in &cache^.items[index] {
        case shapemodel.Shapes_Point_Draw:
            draw_encoded_cached_point_shadow(state, encoder, &item)
        case shapemodel.Shapes_Line_Draw:
            draw_encoded_cached_line_shadow(state, encoder, &item)
        case shapemodel.Shapes_Circle_Draw:
            draw_encoded_cached_circle_shadow(state, encoder, &item)
        case shapemodel.Shapes_Filled_Circle_Draw:
            draw_encoded_cached_filled_circle_shadow(state, encoder, &item)
        case shapemodel.Shapes_Curve_Draw:
            draw_encoded_cached_curve_shadow(state, encoder, &item)
        case shapemodel.Shapes_Polygon_Draw:
            draw_encoded_cached_polygon_shadow(state, encoder, &item)
        case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Trochoid_Tool_Draw,
            shapemodel.Shapes_Cycloid_Tool_Draw, shapemodel.Shapes_Pen_Draw,
            shapemodel.Shapes_Compass_Draw:
        }
    }
}

//   Render cached shadow overlays for pen and compass tool geometry.
//
// Parameters:
//   - state: Global app state containing tool shadow draw-cache entries.
//
// Returns:
//   - none.

//   Render floor shadows for cached low-layer geometry when any defining point is above the surface.
//
// Notes:
//   - Flat and below-surface geometry draws no shadow.
//   - Labels are intentionally excluded from the shape-shadow pass.

//   Draw one cached item only when it belongs to the lower geometry layer.

//   Draw one cached item's floor shadow when that item can cast one.

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

//   Draw one cached point only when it belongs to the merged higher layer.

//   Draw one cached line only when it belongs to the lower geometry layer.

//   Draw one cached line only when it belongs to the merged higher layer.

//   Draw one cached circle only when it belongs to the lower geometry layer.

//   Draw one cached circle only when it belongs to the merged higher layer.

//   Draw one cached filled circle only when it belongs to the lower geometry layer.

//   Draw one cached filled circle only when it belongs to the merged higher layer.

// Draw one cached curve only when all of it belongs to the lower geometry layer.

// Draw one cached curve in the higher layer when any vertex is elevated.

//   Draw one cached polygon only when it belongs to the lower geometry layer.

//   Draw one cached polygon only when it belongs to the merged higher layer.

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

// Classify one source edge by its selected halfspace transition.
curve_visible_edge_kind :: #force_inline proc(
    first_in, second_in: bool) -> Curve_Visible_Edge_Kind {
    if first_in && second_in {return .Inside}
    if first_in {return .Exit}
    if second_in {return .Entry}
    return .Hidden
}

// Add one classified edge's exact storage cost to preflight state.
curve_visible_count_edge :: #force_inline proc(counts: ^Curve_Visible_Run_Counts,
    edge: Curve_Visible_Edge_Kind, active: ^bool) {
    switch edge {
    case .Inside:
        if active^ {
            counts.point_count += 1
        } else {
            counts.run_count += 1
            counts.point_count += 2
            active^ = true
        }
    case .Exit:
        counts.point_count += 1
        if !active^ {
            counts.run_count += 1
            counts.point_count += 1
        }
        active^ = false
    case .Entry:
        counts.run_count += 1
        counts.point_count += 2
        active^ = true
    case .Hidden:
        active^ = false
    }
}

// Count clipped curve points and contiguous runs without mutating output storage.
curve_visible_run_counts :: proc(
    points: []Vector3, keep_above: bool) -> Curve_Visible_Run_Counts {
    counts := Curve_Visible_Run_Counts{unchanged = true}
    active := false
    for index in 1..<len(points) {
        first_in := z_split_point_in_halfspace(points[index - 1], keep_above)
        second_in := z_split_point_in_halfspace(points[index], keep_above)
        counts.unchanged = counts.unchanged && first_in && second_in
        edge := curve_visible_edge_kind(first_in, second_in)
        curve_visible_count_edge(&counts, edge, &active)
    }
    return counts
}

// Append one projected point and its semantic kind to preflighted output storage.
curve_visible_append_point :: #force_inline proc(input: Curve_Visible_Run_Input,
    buffers: Curve_Visible_Run_Buffers, point: Vector3,
    kind: shapemodel.Curve_Point_Kind, point_count: ^int) {
    projected := point
    if input.shadow {projected = project_to_floor_shadow(point, input.scale)}
    buffers.points[point_count^] = view_core.iso_to_cartesian(projected, input.scale)
    buffers.kinds[point_count^] = kind
    point_count^ += 1
}

// Store one completed run with closure retained only for an untouched whole path.
curve_visible_finish_run :: #force_inline proc(buffers: Curve_Visible_Run_Buffers,
    first_point, point_count: int, topology: shapemodel.Curve_Topology,
    run_count: ^int) {
    buffers.runs[run_count^] = {first_point, point_count - first_point, topology}
    run_count^ += 1
}

// Begin one visible run with its first projected point and semantic kind.
curve_visible_begin_run :: #force_inline proc(writer: ^Curve_Visible_Run_Writer,
    point: Vector3, kind: shapemodel.Curve_Point_Kind) {
    writer.run_start = writer.point_count
    curve_visible_append_point(
        writer.input, writer.buffers, point, kind, &writer.point_count)
    writer.active = true
}

// Emit one classified source edge into preflighted projected run storage.
curve_visible_write_edge :: proc(
    writer: ^Curve_Visible_Run_Writer, index: int, edge: Curve_Visible_Edge_Kind) {
    first := writer.input.points[index - 1]
    second := writer.input.points[index]
    if edge == .Inside {
        if !writer.active {
            curve_visible_begin_run(writer, first, writer.input.kinds[index - 1])
        }
        curve_visible_append_point(writer.input, writer.buffers,
            second, writer.input.kinds[index], &writer.point_count)
    } else if edge == .Exit {
        if !writer.active {
            curve_visible_begin_run(writer, first, writer.input.kinds[index - 1])
        }
        intersection := z_split_intersection_with_plane(first, second)
        curve_visible_append_point(writer.input, writer.buffers,
            intersection, .Ordinary, &writer.point_count)
        curve_visible_finish_run(writer.buffers, writer.run_start,
            writer.point_count, .Open, &writer.run_count)
        writer.active = false
    } else if edge == .Entry {
        intersection := z_split_intersection_with_plane(first, second)
        curve_visible_begin_run(writer, intersection, .Ordinary)
        curve_visible_append_point(writer.input, writer.buffers,
            second, writer.input.kinds[index], &writer.point_count)
    }
}

// Clip world-space curve edges and assemble contiguous projected visible runs.
build_projected_curve_visible_runs :: proc(input: Curve_Visible_Run_Input,
    buffers: Curve_Visible_Run_Buffers) -> Curve_Visible_Run_Result {
    if len(input.points) < 2 || len(input.kinds) < len(input.points) {return {}}
    counts := curve_visible_run_counts(input.points, input.keep_above)
    if counts.point_count > len(buffers.points) ||
        counts.point_count > len(buffers.kinds) || counts.run_count > len(buffers.runs) {
        return {}
    }
    output_topology := shapemodel.Curve_Topology.Open
    if counts.unchanged && counts.run_count == 1 {output_topology = input.topology}
    writer := Curve_Visible_Run_Writer{input = input, buffers = buffers}
    for index in 1..<len(input.points) {
        first_in := z_split_point_in_halfspace(input.points[index - 1], input.keep_above)
        second_in := z_split_point_in_halfspace(input.points[index], input.keep_above)
        edge := curve_visible_edge_kind(first_in, second_in)
        curve_visible_write_edge(&writer, index, edge)
    }
    if writer.active {
        curve_visible_finish_run(buffers, writer.run_start,
            writer.point_count, output_topology, &writer.run_count)
    }
    return {writer.point_count, writer.run_count, true}
}

// curve_reduction_budget selects one stable logical-pixel quality tier.
curve_reduction_budget :: #force_inline proc(
    half_scale: f32) -> Curve_Reduction_Budget {
    if half_scale < 240 {return {0.20, 0.12, COLORED_STROKE_MITER_LIMIT}}
    if half_scale < 480 {return {0.30, 0.18, COLORED_STROKE_MITER_LIMIT}}
    return {0.40, 0.24, COLORED_STROKE_MITER_LIMIT}
}

// curve_reduction_distance_to_chord measures distance to one finite segment.
curve_reduction_distance_to_chord :: proc(
    point, first, last: Vector2) -> f32 {
    chord := last - first
    length_squared := linalg.dot(chord, chord)
    if length_squared <= 0 {return linalg.length(point - first)}
    parameter := math.clamp(linalg.dot(point - first, chord) / length_squared, 0, 1)
    return linalg.length(point - (first + chord * parameter))
}

// curve_reduction_span_passes enforces finite-chord centerline error.
curve_reduction_span_passes :: proc(
    points: []Vector2, first, last: int, budget: Curve_Reduction_Budget) -> bool {
    for index in first + 1..<last {
        if curve_reduction_distance_to_chord(
            points[index], points[first], points[last]) > budget.center_error {
            return false
        }
    }
    return true
}

// curve_reduction_join_passes bounds ordinary retained-join extrusion.
curve_reduction_join_passes :: proc(
    previous, current, next: Vector2, width: f32,
    budget: Curve_Reduction_Budget) -> bool {
    incoming := current - previous
    outgoing := next - current
    incoming_length := linalg.length(incoming)
    outgoing_length := linalg.length(outgoing)
    if incoming_length <= 0 || outgoing_length <= 0 {return false}
    cosine := math.clamp(linalg.dot(
        incoming / incoming_length, outgoing / outgoing_length), -1, 1)
    denominator := math.sqrt(max((1 + cosine) * 0.5, 0))
    if denominator <= native.DRAW_POLYLINE_MITER_EPSILON {return false}
    ratio := 1 / denominator
    return ratio <= budget.miter_limit &&
        width * 0.5 * (ratio - 1) <= budget.stroke_error
}

// curve_reduction_mandatory reports semantic or existing sharp boundaries.
curve_reduction_mandatory :: #force_inline proc(
    points: []Vector2, kinds: []shapemodel.Curve_Point_Kind,
    index: int, width: f32, budget: Curve_Reduction_Budget) -> bool {
    if kinds[index] == .Cusp {return true}
    return !curve_reduction_join_passes(
        points[index - 1], points[index], points[index + 1], width, budget)
}

// curve_reduction_next_index finds the longest admissible deterministic span.
curve_reduction_next_index :: proc(
    points: []Vector2, kinds: []shapemodel.Curve_Point_Kind,
    cursor: [2]int, width: f32,
    budget: Curve_Reduction_Budget) -> int {
    previous, anchor, last := cursor[0], cursor[1], len(points) - 1
    best := anchor + 1
    for candidate in anchor + 1..=last {
        if candidate > anchor + 1 && curve_reduction_mandatory(
            points, kinds, candidate - 1, width, budget) {break}
        if !curve_reduction_span_passes(points, anchor, candidate, budget) {break}
        if previous >= 0 && kinds[anchor] != .Cusp &&
            !curve_reduction_join_passes(points[previous], points[anchor],
                points[candidate], width, budget) {break}
        best = candidate
    }
    return best
}

// curve_reduction_summarize_run computes retained anchors without mutation.
curve_reduction_summarize_run :: proc(
    points: []Vector2, kinds: []shapemodel.Curve_Point_Kind,
    width: f32, budget: Curve_Reduction_Budget) -> Curve_Reduction_Run_Summary {
    summary := Curve_Reduction_Run_Summary{retained_count = 1}
    previous, anchor, last := -1, 0, len(points) - 1
    for anchor < last {
        next := curve_reduction_next_index(
            points, kinds, {previous, anchor}, width, budget)
        summary.retained_count += 1
        if summary.retained_count == 2 {summary.second_index = next}
        summary.before_last_index = summary.last_index
        summary.last_index = next
        previous, anchor = anchor, next
    }
    return summary
}

// curve_reduction_closed_passes validates joins across the canonical seam.
curve_reduction_closed_passes :: proc(
    points: []Vector2, kinds: []shapemodel.Curve_Point_Kind,
    summary: Curve_Reduction_Run_Summary, width: f32,
    budget: Curve_Reduction_Budget) -> bool {
    if summary.retained_count < 4 || kinds[0] == .Cusp {return true}
    seam_previous := summary.before_last_index
    return curve_reduction_join_passes(points[seam_previous], points[0],
        points[summary.second_index], width, budget)
}

// curve_reduction_write_run compacts one preflighted run into earlier storage.
curve_reduction_write_run :: proc(
    buffers: Curve_Visible_Run_Buffers, run: Curve_Visible_Run,
    destination: int, width: f32, budget: Curve_Reduction_Budget) -> int {
    points := buffers.points[run.first_point:run.first_point + run.point_count]
    kinds := buffers.kinds[run.first_point:run.first_point + run.point_count]
    previous, anchor, last := -1, 0, len(points) - 1
    buffers.points[destination] = points[0]
    buffers.kinds[destination] = kinds[0]
    written := 1
    for anchor < last {
        next := curve_reduction_next_index(
            points, kinds, {previous, anchor}, width, budget)
        buffers.points[destination + written] = points[next]
        buffers.kinds[destination + written] = kinds[next]
        written += 1
        previous, anchor = anchor, next
    }
    return written
}

// curve_reduction_input_valid preflights all bounded slices before mutation.
curve_reduction_input_valid :: proc(
    buffers: Curve_Visible_Run_Buffers, visible: Curve_Visible_Run_Result,
    width: f32, budget: Curve_Reduction_Budget) -> bool {
    if !visible.ok || width <= 0 || math.is_nan(width) || math.is_inf(width) ||
        budget.center_error < 0 || budget.stroke_error < 0 ||
        budget.miter_limit <= 1 || math.is_nan(budget.center_error) ||
        math.is_nan(budget.stroke_error) || math.is_nan(budget.miter_limit) ||
        math.is_inf(budget.center_error) || math.is_inf(budget.stroke_error) ||
        math.is_inf(budget.miter_limit) {return false}
    if visible.point_count > len(buffers.points) ||
        visible.point_count > len(buffers.kinds) ||
        visible.run_count > len(buffers.runs) {return false}
    for run in buffers.runs[:visible.run_count] {
        if run.first_point < 0 || run.point_count < 2 ||
            run.first_point + run.point_count > visible.point_count {return false}
    }
    return true
}

// curve_reduction_apply_run preflights and compacts one validated run.
curve_reduction_apply_run :: proc(
    buffers: Curve_Visible_Run_Buffers, run: Curve_Visible_Run,
    destination: int, width: f32, budget: Curve_Reduction_Budget) -> int {
    points := buffers.points[run.first_point:run.first_point + run.point_count]
    kinds := buffers.kinds[run.first_point:run.first_point + run.point_count]
    summary := curve_reduction_summarize_run(points, kinds, width, budget)
    if run.topology != .Open && !curve_reduction_closed_passes(
        points, kinds, summary, width, budget) {summary.retained_count = run.point_count}
    if summary.retained_count != run.point_count {
        return curve_reduction_write_run(buffers, run, destination, width, budget)
    }
    copy(buffers.points[destination:], points)
    copy(buffers.kinds[destination:], kinds)
    return run.point_count
}

// reduce_projected_curve_visible_runs compacts every run without allocation.
reduce_projected_curve_visible_runs :: proc(
    buffers: Curve_Visible_Run_Buffers, visible: Curve_Visible_Run_Result,
    width: f32, budget: Curve_Reduction_Budget) -> Curve_Reduction_Result {
    if !curve_reduction_input_valid(buffers, visible, width, budget) {
        return {visible.point_count, 0, false}
    }
    destination := 0
    for run_index in 0..<visible.run_count {
        run := buffers.runs[run_index]
        first := destination
        destination += curve_reduction_apply_run(
            buffers, run, destination, width, budget)
        buffers.runs[run_index] = {first, destination - first, run.topology}
    }
    return {visible.point_count, destination, true}
}

//   Apply 0.25x alpha attenuation for lower z-split fragments.
z_split_lower_fragment_color :: #force_inline proc(
    draw_color: color.Color_RGBA8) -> color.Color_RGBA8 {
    attenuated := u8(math.clamp(
        int(f32(draw_color.a) * Z_SPLIT_ALPHA_FACTOR + 0.5), 0, 255))
    return {draw_color.r, draw_color.g, draw_color.b, attenuated}
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

    return view_core.iso_to_cartesian_components_batch_selected({
        params.xs[:count],
        params.ys[:count],
        params.zs[:count],
        params.out[:count],
        state^.iso_scale^,
    }, state^.ui_runtime.use_simd_batch_projection)
}




//   Render one cached label draw item.


//   Render one cached point floor shadow.


//   Render one cached line floor shadow.

// Draw one elevated guide ring as ordinary segmented floor shadows.

// Render elevated floor shadows for both guide rings and the orientation handle.

// Render floor shadows for the exact rail, rolling ring, and orientation handle.

// Render floor shadows for every segment in one explicated curve packet.


//   Render one cached circle/arc floor shadow.


//   Render one cached filled-circle floor shadow.


//   Render one cached point draw item.

// draw_encoded_cached_point encodes one projected cached point.
draw_encoded_cached_point :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    point: ^shapemodel.Shapes_Point_Draw) {
    screen := view_core.iso_to_cartesian(point^.point1, state^.iso_scale^)
    _ = native.draw_encoder_circle(encoder, geometry.Vector2(screen),
        point^.brush_size, color.Color_RGBA8(point^.color))
}


//   Render one cached line draw item.

// draw_encoded_cached_line encodes one visible z-clipped cached line fragment.
draw_encoded_cached_line :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    line: ^shapemodel.Shapes_Line_Draw, keep_above: bool) {
    clipped0, clipped1: Vector3
    if !z_split_clip_segment_halfspace(
        line^.point1, line^.point2, keep_above, &clipped0, &clipped1) {return}
    draw_color := line^.color
    if !keep_above &&
        (z_split_sign(clipped0.z) < 0 || z_split_sign(clipped1.z) < 0) {
        faded := z_split_lower_fragment_color(color.Color_RGBA8(draw_color))
        draw_color = shapemodel.Color(faded)
    }
    first := view_core.iso_to_cartesian(clipped0, state^.iso_scale^)
    second := view_core.iso_to_cartesian(clipped1, state^.iso_scale^)
    points := [2]geometry.Vector2{geometry.Vector2(first), geometry.Vector2(second)}
    style := native.Draw_Polyline_Style{width = line^.brush_size,
        miter_limit = COLORED_STROKE_MITER_LIMIT,
        color = color.Color_RGBA8(draw_color), topology = .Open,
        start_cap = .Round, finish_cap = .Round}
    _ = native.draw_encoder_polyline(encoder, points[:], nil, style)
}

// draw_encoded_curve_visible_runs submits topology-aware projected curve runs.
draw_encoded_curve_visible_runs :: proc(
    encoder: ^native.Draw_Encoder, buffers: Curve_Visible_Run_Buffers,
    result: Curve_Visible_Run_Result, width: f32, draw_color: color.Color_RGBA8) {
    #assert(size_of(shapemodel.Curve_Point_Kind) ==
        size_of(native.Draw_Polyline_Point_Kind))
    for run in buffers.runs[:result.run_count] {
        points := buffers.points[run.first_point:run.first_point + run.point_count]
        model_kinds := buffers.kinds[run.first_point:run.first_point + run.point_count]
        kinds := transmute([]native.Draw_Polyline_Point_Kind)model_kinds
        topology := native.Draw_Polyline_Topology.Open
        if run.topology != .Open {topology = .Closed}
        style := native.Draw_Polyline_Style{width = width,
            miter_limit = COLORED_STROKE_MITER_LIMIT, color = draw_color,
            topology = topology, start_cap = .Round, finish_cap = .Round}
        _ = native.draw_encoder_polyline(encoder, points, kinds, style)
    }
}

// draw_encoded_cached_curve encodes every z-clipped explicated curve run.
draw_encoded_cached_curve :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    curve: ^shapemodel.Shapes_Curve_Draw, keep_above: bool) {
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.curve_vertices[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    kinds := cache^.curve_vertex_kinds[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    projected: [MAX_CURVE_VISIBLE_POINTS]Vector2
    projected_kinds: [MAX_CURVE_VISIBLE_POINTS]shapemodel.Curve_Point_Kind
    runs: [MAX_CURVE_VISIBLE_RUNS]Curve_Visible_Run
    buffers := Curve_Visible_Run_Buffers{projected[:], projected_kinds[:], runs[:]}
    result := build_projected_curve_visible_runs({state^.iso_scale^,
        vertices, kinds, curve^.topology, keep_above, false}, buffers)
    if !result.ok {return}
    reduction := reduce_projected_curve_visible_runs(buffers, result,
        curve^.brush_size, curve_reduction_budget(state^.iso_scale^.half_scale))
    if !reduction.ok {return}
    native.draw_encoder_record_curve_reduction(
        encoder, reduction.candidate_count, reduction.retained_count)
    result.point_count = reduction.retained_count
    draw_color := color.Color_RGBA8(curve^.color)
    if !keep_above {
        for point in vertices {
            if z_split_sign(point.z) < 0 {
                draw_color = z_split_lower_fragment_color(draw_color)
                break
            }
        }
    }
    draw_encoded_curve_visible_runs(
        encoder, buffers, result, curve^.brush_size, draw_color)
}

// circle_arc_polyline_topology closes only complete sampled circumferences.
circle_arc_polyline_topology :: #force_inline proc(
    sweep_theta: f32) -> native.Draw_Polyline_Topology {
    if math.abs(math.abs(sweep_theta) - 2 * math.PI) <= CIRCLE_CLOSED_SWEEP_EPSILON {
        return .Closed
    }
    return .Open
}

// draw_encoded_cached_circle encodes one sampled projected circle or arc.
draw_encoded_cached_circle :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    circle: ^shapemodel.Shapes_Circle_Draw) {
    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    geometry_value := circle_arc_geometry(circle^.center, circle^.radius,
        circle^.start_theta, circle^.sweep_theta)
    circle_arc_sample_world(&geometry_value, arc_world[:])
    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    projected: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(state, {
        world_points = arc_world[:], xs = xs[:], ys = ys[:],
        zs = zs[:], out = projected[:]})
    topology := circle_arc_polyline_topology(circle^.sweep_theta)
    style := native.Draw_Polyline_Style{width = circle^.brush_size,
        miter_limit = COLORED_STROKE_MITER_LIMIT,
        color = color.Color_RGBA8(circle^.color), topology = topology,
        start_cap = .Round, finish_cap = .Round}
    _ = native.draw_encoder_polyline(encoder, projected[:], nil, style)
}

// draw_encoded_cached_filled_circle encodes one projected filled sector.
draw_encoded_cached_filled_circle :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    circle: ^shapemodel.Shapes_Filled_Circle_Draw) {
    arc_world: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    geometry_value := circle_arc_geometry(circle^.center, circle^.radius,
        circle^.start_theta, circle^.sweep_theta)
    circle_arc_sample_world(&geometry_value, arc_world[:])
    xs, ys, zs: [CIRCLE_ARC_SEGMENTS + 1]f32
    projected: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    _ = project_iso_points_batch_with_components(state, {
        world_points = arc_world[:], xs = xs[:], ys = ys[:],
        zs = zs[:], out = projected[:]})
    center := geometry.Vector2(
        view_core.iso_to_cartesian(geometry_value.center, state^.iso_scale^))
    for index in 1..<len(projected) {
        _ = native.draw_encoder_triangle(encoder, center,
            geometry.Vector2(projected[index - 1]),
            geometry.Vector2(projected[index]), color.Color_RGBA8(circle^.color))
    }
}

// draw_encoded_cached_polygon encodes authoritative cached polygon triangles.
draw_encoded_cached_polygon :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    polygon: ^shapemodel.Shapes_Polygon_Draw) {
    if polygon^.vertex_count < 3 || polygon^.triangle_count <= 0 {return}
    projected: [shapemodel.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    if !project_cached_polygon_vertices(state, polygon, projected[:]) {return}
    cache := &state^.shape_world^.draw_cache
    triangles := cache^.polygon_triangles[polygon^.first_triangle:
        polygon^.first_triangle + polygon^.triangle_count]
    for triangle in triangles {
        first := triangle.a - polygon^.first_vertex
        second := triangle.b - polygon^.first_vertex
        third := triangle.c - polygon^.first_vertex
        if first < 0 || first >= polygon^.vertex_count || second < 0 ||
            second >= polygon^.vertex_count || third < 0 ||
            third >= polygon^.vertex_count {continue}
        _ = native.draw_encoder_triangle(encoder,
            geometry.Vector2(projected[first]), geometry.Vector2(projected[second]),
            geometry.Vector2(projected[third]), color.Color_RGBA8(polygon^.color))
    }
}

// draw_encoded_cached_point_shadow encodes one elevated point floor shadow.
draw_encoded_cached_point_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    point: ^shapemodel.Shapes_Point_Draw) {
    if !shadow_point_is_elevated(point^.point1) {return}
    screen := shadow_to_screen(point^.point1, state)
    draw_color := encoded_shadow_color(point^.point1.z)
    _ = native.draw_encoder_circle(encoder, geometry.Vector2(screen),
        point^.brush_size, draw_color)
}

// draw_encoded_cached_line_shadow encodes one elevated line floor shadow.
draw_encoded_cached_line_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    line: ^shapemodel.Shapes_Line_Draw) {
    points := [2]Vector3{line^.point1, line^.point2}
    if !has_any_elevated_shadow_point(points[:]) {return}
    clipped0, clipped1: Vector3
    if !z_split_clip_segment_halfspace(
        line^.point1, line^.point2, true, &clipped0, &clipped1) {return}
    clipped := [2]Vector3{clipped0, clipped1}
    draw_color := encoded_shadow_color(average_shadow_height(clipped[:]))
    projected := [2]geometry.Vector2{
        geometry.Vector2(shadow_to_screen(clipped0, state)),
        geometry.Vector2(shadow_to_screen(clipped1, state))}
    style := native.Draw_Polyline_Style{
        width = math.max(line^.brush_size * 0.8, SHADOW_MIN_THICKNESS),
        miter_limit = COLORED_STROKE_MITER_LIMIT, color = draw_color,
        topology = .Open, start_cap = .Round, finish_cap = .Round}
    _ = native.draw_encoder_polyline(encoder, projected[:], nil, style)
}

// draw_encoded_cached_curve_shadow encodes clipped curve shadows as visible runs.
draw_encoded_cached_curve_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    curve: ^shapemodel.Shapes_Curve_Draw) {
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.curve_vertices[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    if !has_any_elevated_shadow_point(vertices) {return}
    kinds := cache^.curve_vertex_kinds[
        curve^.first_vertex:curve^.first_vertex + curve^.vertex_count]
    projected: [MAX_CURVE_VISIBLE_POINTS]Vector2
    projected_kinds: [MAX_CURVE_VISIBLE_POINTS]shapemodel.Curve_Point_Kind
    runs: [MAX_CURVE_VISIBLE_RUNS]Curve_Visible_Run
    buffers := Curve_Visible_Run_Buffers{projected[:], projected_kinds[:], runs[:]}
    result := build_projected_curve_visible_runs({state^.iso_scale^,
        vertices, kinds, curve^.topology, true, true}, buffers)
    if !result.ok {return}
    thickness := math.max(curve^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    reduction := reduce_projected_curve_visible_runs(buffers, result, thickness,
        curve_reduction_budget(state^.iso_scale^.half_scale))
    if !reduction.ok {return}
    native.draw_encoder_record_curve_reduction(
        encoder, reduction.candidate_count, reduction.retained_count)
    result.point_count = reduction.retained_count
    draw_encoded_curve_visible_runs(encoder, buffers, result, thickness,
        encoded_shadow_color(average_shadow_height(vertices)))
}

// draw_encoded_cached_circle_shadow encodes sampled elevated arc shadows.
draw_encoded_cached_circle_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    circle: ^shapemodel.Shapes_Circle_Draw) {
    if !shadow_point_is_elevated(circle^.center) {return}
    geometry_value := circle_arc_geometry(circle^.center, circle^.radius,
        circle^.start_theta, circle^.sweep_theta)
    points: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geometry_value, points[:])
    projected: [CIRCLE_ARC_SEGMENTS + 1]Vector2
    for point, index in points {
        projected[index] = shadow_to_screen(point, state)
    }
    topology := circle_arc_polyline_topology(circle^.sweep_theta)
    style := native.Draw_Polyline_Style{
        width = math.max(circle^.brush_size * 0.8, SHADOW_MIN_THICKNESS),
        miter_limit = COLORED_STROKE_MITER_LIMIT,
        color = encoded_shadow_color(circle^.center.z), topology = topology,
        start_cap = .Round, finish_cap = .Round}
    _ = native.draw_encoder_polyline(encoder, projected[:], nil, style)
}

// draw_encoded_cached_filled_circle_shadow encodes a projected filled shadow fan.
draw_encoded_cached_filled_circle_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    circle: ^shapemodel.Shapes_Filled_Circle_Draw) {
    if !shadow_point_is_elevated(circle^.center) {return}
    geometry_value := circle_arc_geometry(circle^.center, circle^.radius,
        circle^.start_theta, circle^.sweep_theta)
    points: [CIRCLE_ARC_SEGMENTS + 1]Vector3
    circle_arc_sample_world(&geometry_value, points[:])
    center := geometry.Vector2(shadow_to_screen(geometry_value.center, state))
    draw_color := encoded_shadow_color(circle^.center.z)
    for index in 1..<len(points) {
        _ = native.draw_encoder_triangle(encoder, center,
            geometry.Vector2(shadow_to_screen(points[index - 1], state)),
            geometry.Vector2(shadow_to_screen(points[index], state)), draw_color)
    }
}

// draw_encoded_cached_polygon_shadow encodes cached triangles at floor projection.
draw_encoded_cached_polygon_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    polygon: ^shapemodel.Shapes_Polygon_Draw) {
    if polygon^.vertex_count < 3 || polygon^.triangle_count <= 0 {return}
    cache := &state^.shape_world^.draw_cache
    vertices := cache^.polygon_vertices[
        polygon^.first_vertex:polygon^.first_vertex + polygon^.vertex_count]
    if !has_any_elevated_shadow_point(vertices) {return}
    projected: [shapemodel.MAX_DRAW_CACHE_POLYGON_VERTICES]Vector2
    for index in 0..<polygon^.vertex_count {
        projected[index] = shadow_to_screen(vertices[index], state)
    }
    draw_color := encoded_shadow_color(average_shadow_height(vertices))
    triangles := cache^.polygon_triangles[polygon^.first_triangle:
        polygon^.first_triangle + polygon^.triangle_count]
    for triangle in triangles {
        first := triangle.a - polygon^.first_vertex
        second := triangle.b - polygon^.first_vertex
        third := triangle.c - polygon^.first_vertex
        if first < 0 || first >= polygon^.vertex_count || second < 0 ||
            second >= polygon^.vertex_count || third < 0 ||
            third >= polygon^.vertex_count {continue}
        _ = native.draw_encoder_triangle(encoder,
            geometry.Vector2(projected[first]), geometry.Vector2(projected[second]),
            geometry.Vector2(projected[third]), draw_color)
    }
}

// Render every segment in one explicated curve using ordinary line styling.


//   Render one cached circle/arc draw item.

//   Render one cached filled-circle draw item.


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


//   Render one cached polygon floor shadow.

//   Render one cached polygon draw item.


//   Render active-end indicator for cached pen tool.

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

//   Render active-end indicator for cached compass tool.


//   Render floor shadow for cached pen tool geometry.


//   Render floor-shadow arc segment outside the compass swing angle.


//   Render floor shadow for cached compass tool geometry.
