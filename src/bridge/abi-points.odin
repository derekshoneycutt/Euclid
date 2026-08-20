package bridge

import "../core"
import "../particles"
import "../shapes"

import rl "vendor:raylib"

Child_Chain_Walk :: struct {
    tail:   int,
    count:  int,
    status: i32,
}

//   Create a new label shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - label: Rune glyph used by label point shapes.
//   - pos: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Snapshot struct for the newly created label host with resolved draw/style/child fields.
@(export)
create_new_label :: proc "c" (
    state: ^core.Euclid_General_State,
    label: rune, pos: core.Vector3,
    color: Bridge_Color, brush_size: f32) -> Bridge_Point_View {

    return create_new_label_decorated(
        state,
        core.Bridge_Label_Glyph{
            label = label,
            decoration_kind = i32(core.Shapes_Label_Decoration_Kind.None),
        },
        pos, color, brush_size)
}

//   Create a new label shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - glyph: Label rune and decoration kind.
//   - pos: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Snapshot struct for the newly created label host with resolved draw/style/child fields.
@(export)
create_new_label_decorated :: proc "c" (
    state: ^core.Euclid_General_State,
    glyph: core.Bridge_Label_Glyph,
    pos: core.Vector3,
    color: Bridge_Color,
    brush_size: f32) -> Bridge_Point_View {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    use_decoration_kind := label_decoration_kind_from_i32(glyph.decoration_kind)
    point, index := shapes.init_label(
        state^.point_system,
        {glyph.label, use_decoration_kind, pos, {rl_color, brush_size}})

    view := point_view_from_point(point^, index)
    view.point_type = 1
    view.offset = point^.offset
    return view
}

//   Create a new point shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Snapshot struct for the newly created point host with resolved draw/style/child fields.
@(export)
create_new_point :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: core.Vector3, color: Bridge_Color, brush_size: f32) -> Bridge_Point_View {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    point, index := shapes.init_point(
        state^.point_system, pos, rl_color, brush_size)

    use_pos, has_pos := point^.position.?
    color, has_color := point^.color.?
    active_color, has_active_color := point^.active_color.?
    label, has_label := point^.label.?

    return Bridge_Point_View{
        valid = true,
        index = index,

        point_type = 2,
        do_draw = point^.do_draw,
        brush_size = point^.brush_size,
        offset = point^.offset,

        has_position = has_pos,
        position = use_pos,

        has_color = has_color,
        color = Bridge_Color{ color.r, color.g, color.b, color.a },

        has_active_color = has_active_color,
        active_color = Bridge_Color{ active_color.r, active_color.g,
            active_color.b, active_color.a },

        has_label = has_label,
        label = label,
        decoration_kind = i32(point^.decoration_kind),

        active_child = point^.active_child,
        child_count = point^.child_count,
        child_point_head = point^.child_point_head,
        next_child_point = point^.next_child_point,
    }
}

//   Create a new line shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created line host and endpoint points.
@(export)
create_new_line :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2: core.Vector3,
    color: Bridge_Color, brush_size: f32) -> core.Shapes_Line {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    line := shapes.init_line(
        state^.point_system, point1, point2, rl_color, brush_size)

    return line
}

//   Create a new circle shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - center: 3D position used for shape/tool placement in world space.
//   - arc: Radius and arc angle bounds in radians.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created circle host, center, and perimeter points.
@(export)
create_new_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3, arc: core.Bridge_Arc_Geometry,
    color: Bridge_Color, brush_size: f32) -> core.Shapes_Circle {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    circle := shapes.init_circle(state^.point_system,
        {center, arc.radius, arc.start_theta, arc.end_theta, {rl_color, brush_size}})

    return circle
}

//   Create a new filledcircle shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - center: 3D position used for shape/tool placement in world space.
//   - arc: Radius and arc angle bounds in radians.
//   - color: RGBA color payload in bridge format.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created filled circle host, center, and perimeter points.
@(export)
create_new_filledcircle :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3, arc: core.Bridge_Arc_Geometry,
    color: Bridge_Color, brush_size: f32) -> core.Shapes_Filled_Circle {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    circle := shapes.init_filledcircle(state^.point_system,
        {center, arc.radius, arc.start_theta, arc.end_theta, {rl_color, brush_size}})

    return circle
}

//   Create a new triangle shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - point3: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created triangle host and its three vertices.
@(export)
create_new_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2, point3: core.Vector3, color: Bridge_Color) -> core.Shapes_Triangle {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    line := shapes.init_triangle(
        state^.point_system, point1, point2, point3, rl_color)

    return line
}

//   Create a new square shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - vertices: Four 3D vertex positions for the square corners.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created square host and its four vertices.
@(export)
create_new_square :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: core.Bridge_Square_Vertices,
    color: Bridge_Color) -> core.Shapes_Square {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    line := shapes.init_square(
        state^.point_system, {vertices.vertices, rl_color})

    return line
}

//   Create a new pentagon shape in the shapes system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - vertices: Five 3D vertex positions for the pentagon corners.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created pentagon host and its five vertices.
@(export)
create_new_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: core.Bridge_Pentagon_Vertices,
    color: Bridge_Color) -> core.Shapes_Pentagon {

    context = state^.saved_context
    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    line := shapes.init_pentagon(
        state^.point_system, {vertices.vertices, rl_color})

    return line
}

//   Map a point kind to its bridge point-type code.
point_kind_to_type :: proc(kind: core.Shapes_Point_Type) -> int {
    table := [?]int{ 1, 2, 3, 4, 5, 6, 7, 8, 100, 150 }
    ordinal := int(kind)
    if ordinal < 0 || ordinal >= len(table) {
        return 0
    }
    return table[ordinal]
}

//   Build a bridge point view payload from a resolved point and index.
point_view_from_point :: proc(point: core.Shapes_Point, index: int) -> Bridge_Point_View {
    pos, has_pos := point.position.?
    color, has_color := point.color.?
    active_color, has_active_color := point.active_color.?
    label, has_label := point.label.?

    return Bridge_Point_View{
        valid = true,
        index = index,
        point_type = 0,
        do_draw = point.do_draw,
        brush_size = point.brush_size,
        has_position = has_pos,
        position = pos,
        has_color = has_color,
        color = Bridge_Color{ color.r, color.g, color.b, color.a },
        has_active_color = has_active_color,
        active_color = Bridge_Color{ active_color.r, active_color.g,
            active_color.b, active_color.a },
        has_label = has_label,
        label = label,
        decoration_kind = i32(point.decoration_kind),
        active_child = point.active_child,
        child_count = point.child_count,
        child_point_head = point.child_point_head,
        next_child_point = point.next_child_point,
    }
}

//   Build a bridge-safe snapshot of a point entry and its optional fields.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Snapshot struct with valid=false and sentinel fields when index lookup fails.
@(export)
get_point_view :: proc "c" (
    state: ^core.Euclid_General_State,
    index_abi: i32) -> Bridge_Point_View {

    context = state^.saved_context
    index := int(index_abi)
    if index >= 0 && index < MAX_SHAPESPOINTS {
        point := state^.point_system^.points[index]
        query_snapshot := active_animation_query_snapshot(state)
        if query_snapshot != nil {
            point = query_snapshot^.points[index]
        }

        view := point_view_from_point(point, index)
        view.point_type = point_kind_to_type(point.kind)
        return view
    }

    return Bridge_Point_View{
        valid = false,
        index = -1,
        
        point_type = -1,
        do_draw = false,
        brush_size = 0,

        has_position = false,
        position = {0, 0, 0},

        has_color = false,
        color = Bridge_Color{ 0, 0, 0, 0 },

        has_active_color = false,
        active_color = Bridge_Color{ 0, 0, 0, 0 },

        has_label = false,
        label = 0,
        decoration_kind = i32(core.Shapes_Label_Decoration_Kind.None),

        active_child = 0,
        child_count = 0,
        child_point_head = 0,
        next_child_point = 0,
    }
}


//   Enable drawing for a point host index when the index is in range.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
@(export)
show_point :: proc "c" (state: ^core.Euclid_General_State, index_abi: i32) {
    index := int(index_abi)
    if capture_point_command(state, .Show_Point, index) {
        return
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        context = state^.saved_context
        point := &state^.point_system^.points[index]
        point^.do_draw = true
        emit_label_show_dust_push(state, point)
    }
}

//   Update point draw visibility and emit related visual effects where applicable.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
@(export)
hide_point :: proc "c" (state: ^core.Euclid_General_State, index_abi: i32) {
    index := int(index_abi)
    if capture_point_command(state, .Hide_Point, index) {
        return
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        context = state^.saved_context
        particles.emit_shapes_hide_burst(
            state^.particle_system,
            state^.point_system,
            index,
            true,
            state^.iso_scale)
        state^.point_system^.points[index].do_draw = false
    }
}

//   Update point draw visibility and emit related visual effects where applicable.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - indices: Pointer to index array consumed by this batch operation.
//   - count: Number of entries available in the provided array.
@(export)
hide_point_batch :: proc "c" (
    state: ^core.Euclid_General_State, indices: [^]i32, count: i32) {
    if capture_hide_point_batch_command(state, indices, count) {
        return
    }
    if count <= 0 {
        return
    }
    context = state^.saved_context
    particles.kick_existing_dust(state^.particle_system, state^.iso_scale)
    for i in 0..<int(count) {
        index := int(indices[i])
        if index >= 0 && index < MAX_SHAPESPOINTS {
            particles.emit_shapes_hide_burst(
                state^.particle_system,
                state^.point_system,
                index,
                false,
                state^.iso_scale)
            state^.point_system^.points[index].do_draw = false
        }
    }
}

//   Set one point position when index is in bounds.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
set_point_position :: proc "c" (
    state: ^core.Euclid_General_State, index_abi: i32, pos: core.Vector3) {
    index := int(index_abi)
    context = state^.saved_context
    if capture_point_position_command(state, index, pos) {
        return
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        set_point_position_with_floor_crossing_dust(state, index, pos)
    }
}

//   Set one point brush size when index is in bounds.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - brush_size: Stroke thickness for rendered point/shape geometry.
@(export)
set_point_brush :: proc "c" (
    state: ^core.Euclid_General_State, index_abi: i32, brush_size: f32) {
    index := int(index_abi)
    if capture_point_brush_command(state, index, brush_size) {
        return
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        state^.point_system^.points[index].brush_size = brush_size
    }
}

//   Set one point base color when index is in bounds.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
@(export)
set_point_color :: proc "c" (
    state: ^core.Euclid_General_State, index_abi: i32, color: Bridge_Color) {
    index := int(index_abi)
    if capture_point_color_command(state, index, color) {
        return
    }
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rl_color := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].color = rl_color
    }
}

//   Set one point active-highlight color when index is in bounds.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
@(export)
set_point_active_color :: proc "c" (
    state: ^core.Euclid_General_State, index_abi: i32, color: Bridge_Color) {
    index := int(index_abi)
    if index >= 0 && index < MAX_SHAPESPOINTS {
        rl_color := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rl_color
    }
}

//   Return maximum point capacity exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_point_capacity :: proc "c" () -> i32 {
    return i32(MAX_SHAPESPOINTS)
}

//   Return the next point allocation index from runtime state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_point_next_index :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.next_point_index)
}

//   Return whether a point index is within valid runtime bounds.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - 1 when true, 0 when false for C ABI compatibility.
@(export)
is_point_index_in_range :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> u8 {
    context = state^.saved_context
    _ = state
    return to_u8(is_point_index_in_bounds(int(index)))
}

//   Set point do_draw from a C ABI flag and emit label dust when enabling draw.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - enabled: Non-zero to enable drawing; zero to disable drawing.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_draw_enabled :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, enabled: u8) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    point := &state^.point_system^.points[point_index]
    point^.do_draw = enabled != 0
    if point^.do_draw {
        emit_label_show_dust_push(state, point)
    }
    return BRIDGE_STATUS_OK
}

//   Set a point position with floor-crossing dust effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - pos: New world-space position.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_position_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, pos: core.Vector3) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if capture_point_position_command(state, point_index, pos) {
        return BRIDGE_STATUS_OK
    }

    set_point_position_with_floor_crossing_dust(state, point_index, pos)
    return BRIDGE_STATUS_OK
}

//   Clear the optional position field on a point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
clear_point_position :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[point_index].position = nil
    return BRIDGE_STATUS_OK
}

//   Set the optional base color on a point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_color_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, color: Bridge_Color) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    state^.point_system^.points[point_index].color = rl_color
    return BRIDGE_STATUS_OK
}

//   Clear the optional base color on a point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
clear_point_color :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[point_index].color = nil
    return BRIDGE_STATUS_OK
}

//   Set the optional active-highlight color on a point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_active_color_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, color: Bridge_Color) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rl_color := rl.Color{ color.r, color.g, color.b, color.a }
    state^.point_system^.points[point_index].active_color = rl_color
    return BRIDGE_STATUS_OK
}

//   Clear the optional active-highlight color on a point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
clear_point_active_color :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[point_index].active_color = nil
    return BRIDGE_STATUS_OK
}

//   Set point brush size.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - brush: New brush size.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_brush_size :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, brush: f32) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[point_index].brush_size = brush
    return BRIDGE_STATUS_OK
}

//   Set point render offset.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Point index to update.
//   - offset: New point offset value.
//
// Returns:
//   - BRIDGE_STATUS_OK on success or BRIDGE_STATUS_INVALID_INDEX when index is out of bounds.
@(export)
set_point_offset :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, offset: f32) -> i32 {

    context = state^.saved_context

    point_index := int(index)
    if !is_point_index_in_bounds(point_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if capture_point_scalar_command(state, .Set_Point_Offset, point_index, offset) {
        return BRIDGE_STATUS_OK
    }

    state^.point_system^.points[point_index].offset = offset
    return BRIDGE_STATUS_OK
}

//   Attach a child point to the end of a parent's child chain.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parent_index: Parent point index.
//   - child_index: Child point index to append.
//
// Returns:
//   - BRIDGE_STATUS_OK on success.
//   - BRIDGE_STATUS_INVALID_INDEX when either index is out of bounds.
//   - BRIDGE_STATUS_INVALID_GRAPH for self-links, duplicate links, invalid chains, or pre-linked child nodes.
@(export)
attach_child_point :: proc "c" (
    state: ^core.Euclid_General_State, parent_index, child_index: i32) -> i32 {

    context = state^.saved_context

    parent := int(parent_index)
    child := int(child_index)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if parent == child {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    parent_point := &state^.point_system^.points[parent]
    child_point := &state^.point_system^.points[child]

    if child_point^.next_child_point >= 0 {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parent_point^.child_point_head < 0 {
        parent_point^.child_point_head = child
        parent_point^.child_count = 1
        return BRIDGE_STATUS_OK
    }

    walk := child_chain_tail(state, parent_point^.child_point_head, child)
    if walk.status != BRIDGE_STATUS_OK {
        return walk.status
    }

    state^.point_system^.points[walk.tail].next_child_point = child
    parent_point^.child_count = walk.count + 1
    return BRIDGE_STATUS_OK
}

//   Walk a child chain to its tail, rejecting cycles, bad indices, and the child.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - head: Index of the first child in the chain.
//   - child: Child index that must not already appear in the chain.
//
// Returns:
//   - Walk result with the tail index, current child count, and a status that is
//     BRIDGE_STATUS_OK on a clean walk, otherwise BRIDGE_STATUS_INVALID_GRAPH.
child_chain_tail :: proc(
    state: ^core.Euclid_General_State, head: int, child: int) -> Child_Chain_Walk {

    visited: [MAX_SHAPESPOINTS]bool
    current := head
    tail := current
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) || visited[current] || current == child {
            return Child_Chain_Walk{ tail, count, BRIDGE_STATUS_INVALID_GRAPH }
        }
        visited[current] = true

        tail = current
        count += 1
        next := state^.point_system^.points[current].next_child_point
        if next < 0 {
            break
        }
        current = next
    }
    return Child_Chain_Walk{ tail, count, BRIDGE_STATUS_OK }
}

//   Detach a child point from a parent's child chain.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parent_index: Parent point index.
//   - child_index: Child point index to remove.
//
// Returns:
//   - BRIDGE_STATUS_OK on success.
//   - BRIDGE_STATUS_INVALID_INDEX when either index is out of bounds.
//   - BRIDGE_STATUS_INVALID_GRAPH when the chain is invalid or the child is not present.
@(export)
detach_child_point :: proc "c" (
    state: ^core.Euclid_General_State, parent_index, child_index: i32) -> i32 {

    context = state^.saved_context

    parent := int(parent_index)
    child := int(child_index)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parent_point := &state^.point_system^.points[parent]
    if parent_point^.child_point_head < 0 {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if !remove_from_child_chain(state, parent_point, child) {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    _ = rebuild_child_count(state, parent_index)
    return BRIDGE_STATUS_OK
}

//   Unlink a child from a parent's child chain, reporting whether it was removed.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parent_point: Parent point owning the child chain.
//   - child: Child index to remove from the chain.
//
// Returns:
//   - true when the child was found and unlinked from a clean, acyclic chain.
remove_from_child_chain :: proc(
    state: ^core.Euclid_General_State, parent_point: ^core.Shapes_Point,
    child: int) -> bool {

    visited: [MAX_SHAPESPOINTS]bool
    current := parent_point^.child_point_head
    prev := -1
    for current >= 0 {
        if !is_point_index_in_bounds(current) || visited[current] {
            return false
        }
        visited[current] = true

        next := state^.point_system^.points[current].next_child_point
        if current == child {
            if prev < 0 {
                parent_point^.child_point_head = next
            } else {
                state^.point_system^.points[prev].next_child_point = next
            }
            state^.point_system^.points[current].next_child_point = -1
            return true
        }

        prev = current
        current = next
    }
    return false
}

//   Recompute and store a parent's child_count by walking its child chain.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parent_index: Parent point index.
//
// Returns:
//   - BRIDGE_STATUS_OK on success.
//   - BRIDGE_STATUS_INVALID_INDEX when parent_index is out of bounds.
//   - BRIDGE_STATUS_INVALID_GRAPH when the child chain contains invalid indices or cycles.
@(export)
rebuild_child_count :: proc "c" (
    state: ^core.Euclid_General_State, parent_index: i32) -> i32 {
    context = state^.saved_context
    parent := int(parent_index)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parent_point := &state^.point_system^.points[parent]
    if parent_point^.child_point_head < 0 {
        parent_point^.child_count = 0
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_SHAPESPOINTS]bool
    current := parent_point^.child_point_head
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true
        count += 1
        current = state^.point_system^.points[current].next_child_point
    }

    parent_point^.child_count = count
    return BRIDGE_STATUS_OK
}

//   Validate a parent's child chain structure and metadata consistency.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parent_index: Parent point index.
//
// Returns:
//   - BRIDGE_STATUS_OK when chain indices, cycle checks, child_count, and active_child are consistent.
//   - BRIDGE_STATUS_INVALID_INDEX when parent_index is out of bounds.
//   - BRIDGE_STATUS_INVALID_GRAPH when chain or metadata invariants are broken.
@(export)
validate_parent_child_chain :: proc "c" (
    state: ^core.Euclid_General_State, parent_index: i32) -> i32 {

    context = state^.saved_context

    parent := int(parent_index)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parent_point := &state^.point_system^.points[parent]
    if parent_point^.child_point_head < 0 {
        if parent_point^.child_count != 0 {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_SHAPESPOINTS]bool
    current := parent_point^.child_point_head
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true
        count += 1
        current = state^.point_system^.points[current].next_child_point
    }

    if parent_point^.child_count != count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parent_point^.active_child < -1 || parent_point^.active_child >= count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    return BRIDGE_STATUS_OK
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_line_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Line {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Line{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Line {
        return core.Shapes_Line{ -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Shapes_Line{ -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Shapes_Line{ -1, -1, -1 }
    }

    return core.Shapes_Line{ host, p1, p2 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_circle_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Circle {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Circle{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Circle {
        return core.Shapes_Circle{ -1, -1, -1 }
    }

    start := point.child_point_head
    if !is_point_index_in_bounds(start) {
        return core.Shapes_Circle{ -1, -1, -1 }
    }
    finish := state^.point_system^.points[start].next_child_point
    if !is_point_index_in_bounds(finish) {
        return core.Shapes_Circle{ -1, -1, -1 }
    }

    return core.Shapes_Circle{ host, start, finish }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_filledcircle_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Filled_Circle {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Filled_Circle{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Filled_Circle {
        return core.Shapes_Filled_Circle{ -1, -1, -1 }
    }

    start := point.child_point_head
    if !is_point_index_in_bounds(start) {
        return core.Shapes_Filled_Circle{ -1, -1, -1 }
    }
    finish := state^.point_system^.points[start].next_child_point
    if !is_point_index_in_bounds(finish) {
        return core.Shapes_Filled_Circle{ -1, -1, -1 }
    }

    return core.Shapes_Filled_Circle{ host, start, finish }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_triangle_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Triangle {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Triangle{ -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Triangle {
        return core.Shapes_Triangle{ -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Shapes_Triangle{ -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Shapes_Triangle{ -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Shapes_Triangle{ -1, -1, -1, -1 }
    }

    return core.Shapes_Triangle{ host, p1, p2, p3 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_square_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Square {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Square {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }
    p4 := state^.point_system^.points[p3].next_child_point
    if !is_point_index_in_bounds(p4) {
        return core.Shapes_Square{ -1, -1, -1, -1, -1 }
    }

    return core.Shapes_Square{ host, p1, p2, p3, p4 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - host_id: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_pentagon_view :: proc "c" (
    state: ^core.Euclid_General_State, host_id: i32) -> core.Shapes_Pentagon {

    context = state^.saved_context
    host := int(host_id)
    if !is_point_index_in_bounds(host) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Pentagon {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p4 := state^.point_system^.points[p3].next_child_point
    if !is_point_index_in_bounds(p4) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p5 := state^.point_system^.points[p4].next_child_point
    if !is_point_index_in_bounds(p5) {
        return core.Shapes_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    return core.Shapes_Pentagon{ host, p1, p2, p3, p4, p5 }
}

