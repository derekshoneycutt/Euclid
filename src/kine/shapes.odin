package kine

// We only create the shapes and their constraints here. It is pretty simple at that.

import "core:math"

import rl "vendor:raylib"

// Summary:
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
init_kineshape_label :: proc(
    system: ^Kine_Point_System,
    label: rune,
    pos : Vector3,
    color: rl.Color,
    brush_size: f32) -> (^Kine_Shape_Point, int) {

    point_id := system^.next_point_index
    system^.points[point_id] =
        Kine_Shape_Point{ .Label, pos, color, nil, brush_size, 0, label, 0, 0, 0, 0, false }
    system^.next_point_index += 1

    return &system^.points[point_id], point_id
}

// Summary:
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
init_kineshape_point :: proc(
    system: ^Kine_Point_System,
    pos : Vector3,
    color: rl.Color,
    brush_size: f32) -> (^Kine_Shape_Point, int) {

    point_id := system^.next_point_index
    system^.points[point_id] =
        Kine_Shape_Point{ .Point, pos, color, nil, brush_size, 0, nil, 0, 0, 0, 0, false }
    system^.next_point_index += 1

    return &system^.points[point_id], point_id
}

// Summary:
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
init_kineshape_line :: proc(
    system: ^Kine_Point_System,
    point1_pos, point2_pos : Vector3,
    color: rl.Color,
    brush_size: f32) -> Kine_Shape_Line {

    host_point := Kine_Shape_Point{ .Line, nil, color, nil, brush_size, 0, nil, 0, 2, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, point1_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, point2_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id
    system^.next_point_index = point2_id + 1

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2

    return Kine_Shape_Line{ host_id, point1_id, point2_id }
}

// Summary:
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
init_kineshape_circle :: proc(
    system: ^Kine_Point_System,
    center_pos: Vector3,
    radius: f32,
    start_theta, end_theta: f32,
    color: rl.Color,
    brush_size: f32) -> Kine_Shape_Circle {

    start_pos := Vector3{
        center_pos.x + radius * f32(math.cos(start_theta)),
        center_pos.y + radius * f32(math.sin(start_theta)),
        center_pos.z,
    }

    end_pos := Vector3{
        center_pos.x + radius * f32(math.cos(end_theta)),
        center_pos.y + radius * f32(math.sin(end_theta)),
        center_pos.z,
    }

    host_point := Kine_Shape_Point{ .Circle, center_pos, color, nil, brush_size, 0, nil, 1, 2, 0, 0, false }
    start_point := Kine_Shape_Point{ .Point, start_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    end_point := Kine_Shape_Point{ .Point, end_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    start_id := host_id + 1
    end_id := host_id + 2
    system^.next_point_index = end_id + 1

    host_point.child_point_head = start_id
    start_point.next_child_point = end_id

    system^.points[host_id] = host_point
    system^.points[start_id] = start_point
    system^.points[end_id] = end_point

    return Kine_Shape_Circle{
        host_id, start_id, end_id }
}

// Summary:
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
init_kineshape_filledcircle :: proc(
    system: ^Kine_Point_System,
    center_pos: Vector3,
    radius: f32,
    start_theta, end_theta: f32,
    color: rl.Color,
    brush_size: f32) -> Kine_Shape_Filled_Circle {

    start_pos := Vector3{
        center_pos.x + radius * f32(math.cos(start_theta)),
        center_pos.y + radius * f32(math.sin(start_theta)),
        center_pos.z,
    }

    end_pos := Vector3{
        center_pos.x + radius * f32(math.cos(end_theta)),
        center_pos.y + radius * f32(math.sin(end_theta)),
        center_pos.z,
    }

    host_point := Kine_Shape_Point{ .FilledCircle, center_pos, color, nil, brush_size, 0, nil, 1, 2, 0, 0, false }
    start_point := Kine_Shape_Point{ .Point, start_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false, }
    end_point := Kine_Shape_Point{ .Point, end_pos, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

    host_id := system^.next_point_index
    start_id := host_id + 1
    end_id := host_id + 2
    system^.next_point_index = end_id + 1

    host_point.child_point_head = start_id
    start_point.next_child_point = end_id

    system^.points[host_id] = host_point
    system^.points[start_id] = start_point
    system^.points[end_id] = end_point

    return Kine_Shape_Filled_Circle{
        host_id, start_id, end_id }
}

// Summary:
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
init_kineshape_triangle :: proc(
    system: ^Kine_Point_System,
    point1, point2, point3: Vector3,
    color: rl.Color) -> Kine_Shape_Triangle {

    host_point := Kine_Shape_Point{ .Triangle, nil, color, nil, 0, 0, nil, 0, 3, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, point1, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, point2, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point3 := Kine_Shape_Point{ .Point, point3, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

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

    return Kine_Shape_Triangle{ host_id, point1_id, point2_id, point3_id }
}

// Summary:
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
init_kineshape_square :: proc(
    system: ^Kine_Point_System,
    point1, point2, point3, point4: Vector3,
    color: rl.Color) -> Kine_Shape_Square {

    host_point := Kine_Shape_Point{ .Square, nil, color, nil, 0, 0, nil, 0, 4, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, point1, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, point2, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point3 := Kine_Shape_Point{ .Point, point3, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point4 := Kine_Shape_Point{ .Point, point4, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

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

    return Kine_Shape_Square{ host_id, point1_id, point2_id, point3_id, point4_id }
}

// Summary:
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
init_kineshape_pentagon :: proc(
    system: ^Kine_Point_System,
    point1, point2, point3, point4, point5: Vector3,
    color: rl.Color) -> Kine_Shape_Pentagon {

    host_point := Kine_Shape_Point{ .Pentagon, nil, color, nil, 0, 0, nil, 0, 5, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, point1, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, point2, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point3 := Kine_Shape_Point{ .Point, point3, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point4 := Kine_Shape_Point{ .Point, point4, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point5 := Kine_Shape_Point{ .Point, point5, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

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

    return Kine_Shape_Pentagon{ host_id, point1_id, point2_id, point3_id, point4_id, point5_id }
}

// Summary:
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
init_kineshape_pen :: proc(
    system: ^Kine_Point_System,
    length_value: f32,
    color: rl.Color,
    brush_size: f32) -> Kine_Shape_Pen {

    host_point := Kine_Shape_Point{ .Pen, nil, color, nil, brush_size, 0, nil, 0, 2, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

    host_id := system.next_point_index
    point1_id := host_id + 1
    point2_id := host_id + 2
    system^.next_point_index = point2_id + 1
    host_point.child_point_head = point1_id
    point1.next_child_point = point2_id

    length_constraint := Kine_Constraint{ .Distance, host_id, { length_value, 0, 0 }, 0, 0, 0, 0, true }

    point1_floor := Kine_Constraint{ .Floor, point1_id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2_floor := Kine_Constraint{ .Floor, point2_id, { 0, 0, 0 }, 0, 0, 0, 0, true }

    lock_point1 := Kine_Constraint{ .SnapPoint, point1_id, { 0, 0, 0 }, 0, 0, 0, nil, false }
    lock_point2 := Kine_Constraint{ .SnapPoint, point2_id, { 0, 0, 0 }, 0, 0, 0, nil, false }

    length_id := system^.next_constraint_index
    system^.next_constraint_index += 5

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[point2_id] = point2

    system^.constraints[length_id] = length_constraint
    system^.constraints[length_id + 1] = point1_floor
    system^.constraints[length_id + 2] = point2_floor
    system^.constraints[length_id + 3] = lock_point1
    system^.constraints[length_id + 4] = lock_point2

    return Kine_Shape_Pen{ host_id, point1_id, point2_id,
        length_id, length_id + 1, length_id + 2, length_id + 3, length_id + 4 }
}

// Summary:
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
init_kineshape_compass :: proc(
    system: ^Kine_Point_System,
    limb_length: f32,
    color: rl.Color,
    brush_size: f32) -> Kine_Shape_Compass {

    host_point := Kine_Shape_Point{ .Compass, nil, color, nil, brush_size, 0, nil, 0, 3, 0, 0, false }
    point1 := Kine_Shape_Point{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    pivot := Kine_Shape_Point{ .Point, Vector3{0.01, 0.01, 0.01}, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }
    point2 := Kine_Shape_Point{ .Point, Vector3{0.02, 0.02, 0}, nil, nil, 0, 0, nil, 0, 0, 0, 0, false }

    host_id := system.next_point_index
    point1_id := host_id + 1
    pivot_id := host_id + 2
    point2_id := host_id + 3
    system^.next_point_index = point2_id + 1
    host_point.child_point_head = host_id + 1
    point1.next_child_point = host_id + 2
    pivot.next_child_point = host_id + 3

    center_pivot := Kine_Constraint{ .CenterPivot, host_id, { 0, 0, 0 }, 0.01, 0, 0, 0, true }

    limb1_length := Kine_Constraint{ .Distance, host_id, { limb_length, 0, 0 }, 0, 0, 0, 0, true }
    limb2_length := Kine_Constraint{ .Distance, host_id, { limb_length, 0, 0 }, 0, 0, 0, 1, true }

    point1_floor := Kine_Constraint{ .Floor, point1_id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    pivot_floor := Kine_Constraint{ .Floor, pivot_id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2_floor := Kine_Constraint{ .Floor, point2_id, { 0, 0, 0 }, 0, 0, 0, 0, true }

    lock_point1 := Kine_Constraint{ .SnapPoint, point1_id, { 0, 0, 0 }, 0, 0, 0, nil, false }
    lock_point2 := Kine_Constraint{ .SnapPoint, point2_id, { 0, 0, 0 }, 0, 0, 0, nil, false }

    center_pivot_id := system^.next_constraint_index
    system^.next_constraint_index += 8

    system^.points[host_id] = host_point
    system^.points[point1_id] = point1
    system^.points[pivot_id] = pivot
    system^.points[point2_id] = point2

    system^.constraints[center_pivot_id] = center_pivot
    system^.constraints[center_pivot_id + 1] = limb1_length
    system^.constraints[center_pivot_id + 2] = limb2_length
    system^.constraints[center_pivot_id + 3] = point1_floor
    system^.constraints[center_pivot_id + 4] = pivot_floor
    system^.constraints[center_pivot_id + 5] = point2_floor
    system^.constraints[center_pivot_id + 6] = lock_point1
    system^.constraints[center_pivot_id + 7] = lock_point2

    return Kine_Shape_Compass{ host_id, point1_id, pivot_id, point2_id,
        center_pivot_id, center_pivot_id + 1, center_pivot_id + 2, center_pivot_id + 3,
        center_pivot_id + 4, center_pivot_id + 5, center_pivot_id + 6, center_pivot_id + 7 }
}
