package shapes

// We only create the shapes and their constraints here. It is pretty simple at that.

import "core:math"

import "../core"

import rl "vendor:raylib"

Shape_Style :: struct {
    color: rl.Color,
    brush_size: f32,
}

Label_Input :: struct {
    label: rune,
    decoration_kind: core.Shapes_Label_Decoration_Kind,
    position: Vector3,
    style: Shape_Style,
}

Arc_Input :: struct {
    center: Vector3,
    radius, start_theta, end_theta: f32,
    style: Shape_Style,
}

Square_Input :: struct {
    vertices: [4]Vector3,
    color: rl.Color,
}

Pentagon_Input :: struct {
    vertices: [5]Vector3,
    color: rl.Color,
}

Compass_Constraint_Targets :: struct {
    host_id, point1_id, pivot_id, point2_id: int,
}

//   Construct one distance constraint owned by a tool host.
tool_distance_constraint :: #force_inline proc(
    host_id: int, length: f32, depend_on: int) -> Shapes_Constraint {
    return {.Distance, host_id, {length, 0, 0}, 0, 0, 0, i32(depend_on), true}
}

//   Construct one floor constraint for a tool point.
tool_floor_constraint :: #force_inline proc(point_id: int) -> Shapes_Constraint {
    return {.Floor, point_id, {0, 0, 0}, 0, 0, 0, 0, true}
}

//   Construct one disabled point lock constraint for a tool point.
tool_lock_constraint :: #force_inline proc(point_id: int) -> Shapes_Constraint {
    return {.Snap_Point, point_id, {0, 0, 0}, 0, 0, 0, nil, false}
}

//   Create a drawable label point and append it to the point system.
//
// Parameters:
//   - system: Target point system receiving the new point.
//   - label: Rune rendered for this label point.
//   - pos: World position for the label.
//   - color: Label color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - point: Pointer to the inserted point.
//   - point_id: Index of the inserted point.
init_label :: proc(
    system: ^Shapes_Point_System,
    input: Label_Input) -> (^Shapes_Point, int) {

    point_id := system^.next_point_index
    system^.points[point_id] =
        Shapes_Point{ .Label, input.position, nil, input.style.color, nil,
            input.style.brush_size, 0, input.label,
            .None, 0, 0, 0, 0, false }
    system^.points[point_id].decoration_kind = input.decoration_kind
    system^.next_point_index += 1

    return &system^.points[point_id], point_id
}

//   Create a drawable point and append it to the point system.
//
// Parameters:
//   - system: Target point system receiving the new point.
//   - pos: World position for the point.
//   - color: Point color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - point: Pointer to the inserted point.
//   - point_id: Index of the inserted point.
init_point :: proc(
    system: ^Shapes_Point_System,
    pos : Vector3,
    color: rl.Color,
    brush_size: f32) -> (^Shapes_Point, int) {

    point_id := system^.next_point_index
    system^.points[point_id] =
        Shapes_Point{ .Point, pos, nil, color, nil, brush_size, 0, nil,
            .None, 0, 0, 0, 0, false }
    system^.next_point_index += 1

    return &system^.points[point_id], point_id
}

//   Create a line shape host plus two endpoint child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - point1_pos: Position of the first endpoint.
//   - point2_pos: Position of the second endpoint.
//   - color: Line color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - line: Line shape indices for host and child points.
init_line :: proc(
    system: ^Shapes_Point_System,
    point1_pos, point2_pos : Vector3,
    color: rl.Color,
    brush_size: f32) -> Shapes_Line {

    host_point := Shapes_Point{ .Line, nil, nil, color, nil, brush_size, 0, nil,
        .None, 0, 2, 0, 0, false }
    point1 := Shapes_Point{ .Point, point1_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, point2_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id
    system^.next_point_index = point2_id + 1

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2

    return Shapes_Line{ host_id, point1_id, point2_id }
}

//   Create a circle shape host with start/end arc child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - center_pos: Circle center position.
//   - radius: Circle radius.
//   - start_theta: Arc start angle in radians.
//   - end_theta: Arc end angle in radians.
//   - color: Circle color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - circle: Circle shape indices for host and child points.
init_circle :: proc(
    system: ^Shapes_Point_System,
    input: Arc_Input) -> Shapes_Circle {

    start_pos := Vector3{
        input.center.x + input.radius * f32(math.cos(input.start_theta)),
        input.center.y + input.radius * f32(math.sin(input.start_theta)),
        input.center.z,
    }

    end_pos := Vector3{
        input.center.x + input.radius * f32(math.cos(input.end_theta)),
        input.center.y + input.radius * f32(math.sin(input.end_theta)),
        input.center.z,
    }

    host_point := Shapes_Point{ .Circle, input.center, nil, input.style.color, nil,
        input.style.brush_size, 0, nil,
        .None, 1, 2, 0, 0, false }
    start_point := Shapes_Point{ .Point, start_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    end_point := Shapes_Point{ .Point, end_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    start_id := host_id + 1
    end_id := host_id + 2
    system^.next_point_index = end_id + 1

    host_point.child_point_head = start_id
    start_point.next_child_point = end_id

    system^.points[host_id] = host_point
    system^.points[start_id] = start_point
    system^.points[end_id] = end_point

    return Shapes_Circle{
        host_id, start_id, end_id }
}

//   Create a filled-circle shape host with start/end arc child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - center_pos: Circle center position.
//   - radius: Circle radius.
//   - start_theta: Arc start angle in radians.
//   - end_theta: Arc end angle in radians.
//   - color: Shape color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - filled_circle: Filled-circle shape indices for host and child points.
init_filledcircle :: proc(
    system: ^Shapes_Point_System,
    input: Arc_Input) -> Shapes_Filled_Circle {

    start_pos := Vector3{
        input.center.x + input.radius * f32(math.cos(input.start_theta)),
        input.center.y + input.radius * f32(math.sin(input.start_theta)),
        input.center.z,
    }

    end_pos := Vector3{
        input.center.x + input.radius * f32(math.cos(input.end_theta)),
        input.center.y + input.radius * f32(math.sin(input.end_theta)),
        input.center.z,
    }

    host_point := Shapes_Point{ .Filled_Circle, input.center, nil, input.style.color, nil,
        input.style.brush_size, 0, nil, .None, 1, 2, 0, 0, false }
    start_point := Shapes_Point{ .Point, start_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    end_point := Shapes_Point{ .Point, end_pos, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    start_id := host_id + 1
    end_id := host_id + 2
    system^.next_point_index = end_id + 1

    host_point.child_point_head = start_id
    start_point.next_child_point = end_id

    system^.points[host_id] = host_point
    system^.points[start_id] = start_point
    system^.points[end_id] = end_point

    return Shapes_Filled_Circle{
        host_id, start_id, end_id }
}

//   Create a triangle shape host plus three child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - point1: First triangle vertex.
//   - point2: Second triangle vertex.
//   - point3: Third triangle vertex.
//   - color: Shape color.
//
// Returns:
//   - triangle: Triangle shape indices for host and child points.
init_triangle :: proc(
    system: ^Shapes_Point_System,
    point1, point2, point3: Vector3,
    color: rl.Color) -> Shapes_Triangle {

    host_point := Shapes_Point{ .Triangle, nil, nil, color, nil, 0, 0, nil,
        .None, 0, 3, 0, 0, false }
    point1 := Shapes_Point{ .Point, point1, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, point2, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point3 := Shapes_Point{ .Point, point3, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    point3_id := host_id + 3
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id
    point2.next_child_point = point3_id
    system^.next_point_index = point3_id + 1

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2
    system^.points[point3_id] = point3

    return Shapes_Triangle{ host_id, point1_id, point2_id, point3_id }
}

//   Create a square shape host plus four child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - point1: First square vertex.
//   - point2: Second square vertex.
//   - point3: Third square vertex.
//   - point4: Fourth square vertex.
//   - color: Shape color.
//
// Returns:
//   - square: Square shape indices for host and child points.
init_square :: proc(
    system: ^Shapes_Point_System,
    input: Square_Input) -> Shapes_Square {

    host_point := Shapes_Point{ .Square, nil, nil, input.color, nil, 0, 0, nil,
        .None, 0, 4, 0, 0, false }
    point1 := Shapes_Point{ .Point, input.vertices[0], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, input.vertices[1], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point3 := Shapes_Point{ .Point, input.vertices[2], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point4 := Shapes_Point{ .Point, input.vertices[3], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    point3_id := host_id + 3
    point4_id := host_id + 4
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id
    point2.next_child_point = point3_id
    point3.next_child_point = point4_id
    system^.next_point_index = point4_id + 1

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2
    system^.points[point3_id] = point3
    system^.points[point4_id] = point4

    return Shapes_Square{ host_id, point1_id, point2_id, point3_id, point4_id }
}

//   Create a pentagon shape host plus five child points.
//
// Parameters:
//   - system: Target point system receiving new points.
//   - point1: First pentagon vertex.
//   - point2: Second pentagon vertex.
//   - point3: Third pentagon vertex.
//   - point4: Fourth pentagon vertex.
//   - point5: Fifth pentagon vertex.
//   - color: Shape color.
//
// Returns:
//   - pentagon: Pentagon shape indices for host and child points.
init_pentagon :: proc(
    system: ^Shapes_Point_System,
    input: Pentagon_Input) -> Shapes_Pentagon {

    host_point := Shapes_Point{ .Pentagon, nil, nil, input.color, nil, 0, 0, nil,
        .None, 0, 5, 0, 0, false }
    point1 := Shapes_Point{ .Point, input.vertices[0], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, input.vertices[1], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point3 := Shapes_Point{ .Point, input.vertices[2], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point4 := Shapes_Point{ .Point, input.vertices[3], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point5 := Shapes_Point{ .Point, input.vertices[4], nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    point3_id := host_id + 3
    point4_id := host_id + 4
    point5_id := host_id + 5
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id
    point2.next_child_point = point3_id
    point3.next_child_point = point4_id
    point4.next_child_point = point5_id
    system^.next_point_index = point5_id + 1

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2
    system^.points[point3_id] = point3
    system^.points[point4_id] = point4
    system^.points[point5_id] = point5

    return Shapes_Pentagon{ host_id, point1_id, point2_id,
        point3_id, point4_id, point5_id }
}

//   Create a pen tool shape with floor and lock constraints.
//
// Parameters:
//   - system: Target point system receiving points and constraints.
//   - length_value: Desired pen length used by the distance constraint.
//   - color: Tool color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - pen: Pen shape indices for points and related constraints.
install_pen_constraints :: proc(
    system: ^Shapes_Point_System,
    host_id, point1_id, point2_id: int,
    length_value: f32) -> int {

    first := system^.next_constraint_index
    system^.next_constraint_index += 5
    system^.constraints[first] = Shapes_Constraint{.Distance, host_id,
        {length_value, 0, 0}, 0, 0, 0, 0, true}
    system^.constraints[first + 1] = Shapes_Constraint{.Floor, point1_id,
        {0, 0, 0}, 0, 0, 0, 0, true}
    system^.constraints[first + 2] = Shapes_Constraint{.Floor, point2_id,
        {0, 0, 0}, 0, 0, 0, 0, true}
    system^.constraints[first + 3] = Shapes_Constraint{.Snap_Point, point1_id,
        {0, 0, 0}, 0, 0, 0, nil, false}
    system^.constraints[first + 4] = Shapes_Constraint{.Snap_Point, point2_id,
        {0, 0, 0}, 0, 0, 0, nil, false}
    return first
}

//   Create a pen tool shape with floor and lock constraints.
init_pen :: proc(
    system: ^Shapes_Point_System,
    length_value: f32,
    color: rl.Color,
    brush_size: f32) -> Shapes_Pen {

    host_point := Shapes_Point{ .Pen, nil, nil, color, nil, brush_size, 0, nil,
        .None, 0, 2, 0, 0, false }
    point1 := Shapes_Point{ .Point, Vector3{0, 0, 0}, nil, nil, nil, 0, 0, nil,
    .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, Vector3{0, 0, 0}, nil, nil, nil, 0, 0, nil,
    .None, 0, 0, 0, 0, false }

    host_id := system.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    system^.next_point_index = point2_id + 1
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id

    length_id := install_pen_constraints(
        system, host_id, point1_id, point2_id, length_value)

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2


    return Shapes_Pen{ host_id, point1_id, point2_id,
        length_id, length_id + 1, length_id + 2, length_id + 3, length_id + 4 }
}

//   Create a compass tool shape with limb, floor, center-pivot, and lock constraints.
//
// Parameters:
//   - system: Target point system receiving points and constraints.
//   - limb_length: Desired limb length for each compass side.
//   - color: Tool color.
//   - brush_size: Brush size metadata used by rendering.
//
// Returns:
//   - compass: Compass shape indices for points and related constraints.
install_compass_constraints :: proc(
    system: ^Shapes_Point_System,
    targets: Compass_Constraint_Targets,
    limb_length: f32) -> int {

    first := system^.next_constraint_index
    system^.next_constraint_index += 8
    system^.constraints[first] = {.Center_Pivot, targets.host_id,
        {0, 0, 0}, 0.01, 0, 0, 0, true}
    system^.constraints[first + 1] =
        tool_distance_constraint(targets.host_id, limb_length, 0)
    system^.constraints[first + 2] =
        tool_distance_constraint(targets.host_id, limb_length, 1)
    system^.constraints[first + 3] = tool_floor_constraint(targets.point1_id)
    system^.constraints[first + 4] = tool_floor_constraint(targets.pivot_id)
    system^.constraints[first + 5] = tool_floor_constraint(targets.point2_id)
    system^.constraints[first + 6] = tool_lock_constraint(targets.point1_id)
    system^.constraints[first + 7] = tool_lock_constraint(targets.point2_id)
    return first
}

//   Create a compass tool shape with limb, floor, center-pivot, and lock constraints.
init_compass :: proc(
    system: ^Shapes_Point_System,
    limb_length: f32,
    color: rl.Color,
    brush_size: f32) -> Shapes_Compass {

    host_point := Shapes_Point{ .Compass, nil, nil, color, nil, brush_size, 0, nil,
        .None, 0, 3, 0, 0, false }
    point1 := Shapes_Point{ .Point, Vector3{0, 0, 0}, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    pivot := Shapes_Point{ .Point, Vector3{0.01, 0.01, 0.01}, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }
    point2 := Shapes_Point{ .Point, Vector3{0.02, 0.02, 0}, nil, nil, nil, 0, 0, nil,
        .None, 0, 0, 0, 0, false }

    host_id := system.next_point_index
    point1_id := host_id + 1
    pivot_id := host_id + 2
    point2_id := host_id + 3
    system^.next_point_index = point2_id + 1
    host_point.child_point_head = host_id + 1
    point1.next_child_point = host_id + 2
    pivot.next_child_point = host_id + 3

    center_pivot_id := install_compass_constraints(
        system, {host_id, point1_id, pivot_id, point2_id}, limb_length)

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[pivot_id] = pivot
    system^.points[point2_id] = point2


    return Shapes_Compass{ host_id, point1_id, pivot_id, point2_id,
        center_pivot_id, center_pivot_id + 1,
        center_pivot_id + 2, center_pivot_id + 3,
        center_pivot_id + 4, center_pivot_id + 5,
        center_pivot_id + 6, center_pivot_id + 7 }
}
