package shapemodel

import rl "vendor:raylib"

MAX_SHAPESPOINTS :: 256
MAX_SHAPESCONSTRAINTS :: 256
MAX_DRAW_CACHE_POLYGON_VERTICES :: MAX_SHAPESPOINTS
MAX_DRAW_CACHE_POLYGON_TRIANGLES :: MAX_SHAPESPOINTS
MAX_DRAW_CACHE_CURVE_VERTICES :: 2048

// Group radius and arc angle bounds for one circle bridge operation.
Bridge_Arc_Geometry :: struct {
    radius:      f32,
    start_theta: f32,
    sweep_theta: f32,
}

// Group one complete mutable trochoid description for bridge operations.
Bridge_Trochoid_Geometry :: struct {
    mode: i32,
    fixed_radius: f32,
    rolling_radius: f32,
    tracer_distance: f32,
    tracer_phase: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
}

// Group one complete mutable permanent-guide description for bridge operations.
Bridge_Trochoid_Tool_Geometry :: struct {
    mode: i32,
    fixed_radius: f32,
    rolling_radius: f32,
    parameter: f32,
    rotation: f32,
    orientation_phase: f32,
}

// Group four vertices for one square bridge operation.
Bridge_Square_Vertices :: struct {
    vertices: [4]Vector3,
}

// Group five vertices for one pentagon bridge operation.
Bridge_Pentagon_Vertices :: struct {
    vertices: [5]Vector3,
}

// Hold pointer-free canonical shape projections for one asynchronous query window.
Shape_Query_Snapshot :: struct {
    registry: Shape_Registry,
    transforms: Shape_Component_Set(Shape_Transform),
    arcs: Shape_Component_Set(Shape_Arc),
    trochoids: Shape_Component_Set(Shape_Trochoid),
    trochoid_tools: Shape_Component_Set(Shape_Trochoid_Tool),
    render_styles: Shape_Component_Set(Shape_Render_Style),
    active_features: Shape_Component_Set(Shape_Active_Feature),
    geometries: Shape_Component_Set(Shape_Geometry),
    labels: Shape_Component_Set(Shape_Label),
    label_store: Shape_Label_Store,
}

Shapes_Point_Type :: enum {
    Label,
    Point,
    Line,
    Circle,
    Filled_Circle,
    Curve,
    Triangle,
    Square,
    Pentagon,
    Trochoid_Tool,
    Pen,
    Compass,
}

Shapes_Draw_Base :: struct {
    kind: Shapes_Point_Type,
    source_index: int,
    brush_size: f32,
    color: rl.Color,
    active_color: rl.Color,
    has_active_color: bool,
    active_child: int,
}

Shapes_Label_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
    mime: Shape_Text_Mime,
    source_offset: u16,
    source_count: u16,
    source_revision: u32,
}

Shapes_Point_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
}

Shapes_Line_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
    point2: Vector3,
}

Shapes_Circle_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    radius: f32,
    start_theta: f32,
    sweep_theta: f32,
}

Shapes_Filled_Circle_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    radius: f32,
    start_theta: f32,
    sweep_theta: f32,
}

// Locate one explicated analytic curve in the frame-local vertex pool.
Shapes_Curve_Draw :: struct {
    using base: Shapes_Draw_Base,
    first_vertex: int,
    vertex_count: int,
    capacity_limited: bool,
}

Shapes_Polygon_Ring_Node :: struct {
    prev: int,
    next: int,
    active: bool,
}

Shapes_Polygon_Triangle :: struct {
    a: int,
    b: int,
    c: int,
}

Shapes_Polygon_Draw :: struct {
    using base: Shapes_Draw_Base,
    first_vertex: int,
    vertex_count: int,
    first_triangle: int,
    triangle_count: int,
}

Shapes_Pen_Draw :: struct {
    using base: Shapes_Draw_Base,
    joint1: Vector3,
    joint2: Vector3,
}

Shapes_Compass_Draw :: struct {
    using base: Shapes_Draw_Base,
    joint1: Vector3,
    pivot: Vector3,
    joint2: Vector3,
}

// Hold resolved two-ring guide geometry and its inward orientation handle.
Shapes_Trochoid_Tool_Draw :: struct {
    using base: Shapes_Draw_Base,
    fixed_center: Vector3,
    rolling_center: Vector3,
    fixed_radius: f32,
    rolling_radius: f32,
    handle_start: Vector3,
    handle_finish: Vector3,
}

Shapes_Draw_Cache_Item :: union {
    Shapes_Label_Draw,
    Shapes_Point_Draw,
    Shapes_Line_Draw,
    Shapes_Circle_Draw,
    Shapes_Filled_Circle_Draw,
    Shapes_Curve_Draw,
    Shapes_Polygon_Draw,
    Shapes_Trochoid_Tool_Draw,
    Shapes_Pen_Draw,
    Shapes_Compass_Draw,
}

Shapes_Draw_Cache :: struct {
    items: [MAX_SHAPESPOINTS]Shapes_Draw_Cache_Item,
    item_count: int,

    label_bytes: [MAX_SHAPE_LABEL_TOTAL_BYTES]u8,
    label_byte_count: u16,

    polygon_vertices: [MAX_DRAW_CACHE_POLYGON_VERTICES]Vector3,
    polygon_vertex_count: int,
    polygon_triangles: [MAX_DRAW_CACHE_POLYGON_TRIANGLES]Shapes_Polygon_Triangle,
    polygon_triangle_count: int,
    polygon_ring_nodes: [MAX_DRAW_CACHE_POLYGON_VERTICES]Shapes_Polygon_Ring_Node,

    curve_vertices: [MAX_DRAW_CACHE_CURVE_VERTICES]Vector3,
    curve_vertex_count: int,

    trochoid_tool: Shapes_Trochoid_Tool_Draw,
    draw_trochoid_tool: bool,
    pen: Shapes_Pen_Draw,
    draw_pen: bool,
    compass: Shapes_Compass_Draw,
    draw_compass: bool,
}
