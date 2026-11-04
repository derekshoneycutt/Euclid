package shapemodel

MAX_SHAPESPOINTS :: 256
MAX_SHAPESCONSTRAINTS :: 256
MAX_DRAW_CACHE_POLYGON_VERTICES :: MAX_SHAPESPOINTS
MAX_DRAW_CACHE_POLYGON_TRIANGLES :: MAX_SHAPESPOINTS
MAX_DRAW_CACHE_CURVE_VERTICES :: 2560

// Group radius and arc angle bounds for one circle bridge operation.
Bridge_Arc_Geometry :: struct {
    radius: f32,
    start_theta: f32,
    sweep_theta: f32,
}

// Group one two-circle region operation and its radii for bridge construction.
Bridge_Circle_Region_Geometry :: struct {
    operation: i32,
    first_radius: f32,
    second_radius: f32,
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

// Group one complete mutable literal-line cycloid description for bridge operations.
Bridge_Cycloid_Geometry :: struct {
    rolling_radius: f32,
    tracer_distance: f32,
    tracer_phase: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
}

// Group one complete mutable permanent cycloid-guide description.
Bridge_Cycloid_Tool_Geometry :: struct {
    rolling_radius: f32,
    parameter_start: f32,
    parameter_finish: f32,
    parameter: f32,
    orientation_phase: f32,
}

// Group one complete mutable parabola description for bridge operations.
Bridge_Parabola_Geometry :: struct {
    focal_distance: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
}

// Group one complete hyperbola description for bridge operations.
Bridge_Hyperbola_Geometry :: struct {
    semimajor: f32,
    semiminor: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
}

// Group complete mutable geometry for the permanent parabola instrument.
Bridge_Parabola_Tool_Geometry :: struct {
    focal_distance: f32,
    link_length: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    parameter: f32,
}

// Group complete mutable geometry for the permanent hyperbola instrument.
Bridge_Hyperbola_Tool_Geometry :: struct {
    semimajor: f32,
    semiminor: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    parameter: f32,
    rail_half_length: f32,
}

#assert(size_of(Bridge_Parabola_Geometry) == 5 * size_of(f32))
#assert(size_of(Bridge_Hyperbola_Geometry) == 6 * size_of(f32))
#assert(size_of(Bridge_Parabola_Tool_Geometry) == 6 * size_of(f32))
#assert(size_of(Bridge_Hyperbola_Tool_Geometry) == 7 * size_of(f32))

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
    orientations: Shape_Component_Set(Shape_Orientation),
    arcs: Shape_Component_Set(Shape_Arc),
    trochoids: Shape_Component_Set(Shape_Trochoid),
    trochoid_tools: Shape_Component_Set(Shape_Trochoid_Tool),
    cycloids: Shape_Component_Set(Shape_Cycloid),
    cycloid_tools: Shape_Component_Set(Shape_Cycloid_Tool),
    parabolas: Shape_Component_Set(Shape_Parabola),
    hyperbolas: Shape_Component_Set(Shape_Hyperbola),
    parabola_tools: Shape_Component_Set(Shape_Parabola_Tool),
    hyperbola_tools: Shape_Component_Set(Shape_Hyperbola_Tool),
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
    Lens,
    Lune,
    Curve,
    Triangle,
    Square,
    Pentagon,
    Trochoid_Tool,
    Cycloid_Tool,
    Parabola_Tool,
    Hyperbola_Tool,
    Pen,
    Compass,
}

Shapes_Draw_Base :: struct {
    kind: Shapes_Point_Type,
    source_index: int,
    source_generation: u32,
    brush_size: f32,
    color: Color,
    active_color: Color,
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
    orientation: quaternion128,
}

Shapes_Filled_Circle_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    radius: f32,
    start_theta: f32,
    sweep_theta: f32,
    orientation: quaternion128,
}

// Identify whether one frame-local curve point is ordinary or an analytic cusp.
Curve_Point_Kind :: enum u8 {
    Ordinary,
    Cusp,
}

// Describe whether one frame-local curve is open or closes at an ordinary or cusp point.
Curve_Topology :: enum u8 {
    Open,
    Closed,
    Cusp_Closed,
}

// Locate one explicated analytic curve in the frame-local vertex pool.
Shapes_Curve_Draw :: struct {
    using base: Shapes_Draw_Base,
    first_vertex: int,
    vertex_count: int,
    capacity_limited: bool,
    topology: Curve_Topology,
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

// Hold one resolved literal rail, rolling ring, and orientation handle.
Shapes_Cycloid_Tool_Draw :: struct {
    using base: Shapes_Draw_Base,
    baseline_start: Vector3,
    baseline_finish: Vector3,
    rolling_center: Vector3,
    rolling_radius: f32,
    handle_start: Vector3,
    handle_finish: Vector3,
}

// Resolve an Inwards-inspired articulated diamond and integrated tracing nib.
Shapes_Parabola_Tool_Draw :: struct {
    using base: Shapes_Draw_Base,
    vertex: Vector3,
    focus: Vector3,
    directrix_contact: Vector3,
    directrix_rail_start: Vector3,
    directrix_rail_finish: Vector3,
    diamond_first: Vector3,
    diamond_second: Vector3,
    guide_start: Vector3,
    guide_finish: Vector3,
    nib: Vector3,
    active: bool,
}

// Resolve separate asymptote rails, pivot rail, and symmetric tracing carriages.
Shapes_Hyperbola_Tool_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    asymptote_first_start: Vector3,
    asymptote_first_finish: Vector3,
    asymptote_second_start: Vector3,
    asymptote_second_finish: Vector3,
    moving_rail_start: Vector3,
    moving_rail_finish: Vector3,
    tick_first_start: Vector3,
    tick_first_finish: Vector3,
    tick_second_start: Vector3,
    tick_second_finish: Vector3,
    carriage_positive: Vector3,
    carriage_negative: Vector3,
    active_branches: Hyperbola_Branches,
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
    Shapes_Cycloid_Tool_Draw,
    Shapes_Parabola_Tool_Draw,
    Shapes_Hyperbola_Tool_Draw,
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
    curve_vertex_kinds: [MAX_DRAW_CACHE_CURVE_VERTICES]Curve_Point_Kind,
    curve_vertex_count: int,

    trochoid_tool: Shapes_Trochoid_Tool_Draw,
    draw_trochoid_tool: bool,
    cycloid_tool: Shapes_Cycloid_Tool_Draw,
    draw_cycloid_tool: bool,
    parabola_tool: Shapes_Parabola_Tool_Draw,
    draw_parabola_tool: bool,
    hyperbola_tool: Shapes_Hyperbola_Tool_Draw,
    draw_hyperbola_tool: bool,
    pen: Shapes_Pen_Draw,
    draw_pen: bool,
    compass: Shapes_Compass_Draw,
    draw_compass: bool,
}
