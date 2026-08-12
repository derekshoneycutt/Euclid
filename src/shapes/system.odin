package shapes

// The major system calls for the shape system are for creating the immediate draw cache.
// This just builds the cache into the existing point system.

import "../core"
import "../particles"

import "core:math/linalg"

import rl "vendor:raylib"

DRAW_CACHE_SORT_FLAT_EPSILON :: 1e-5

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
MAX_SHAPESCONSTRAINTS :: core.MAX_SHAPESCONSTRAINTS

Vector3 :: core.Vector3
Shapes_Point_Type :: core.Shapes_Point_Type
Shapes_Point :: core.Shapes_Point

Shapes_Constraint_Kind :: core.Shapes_Constraint_Kind
Shapes_Constraint :: core.Shapes_Constraint
Shapes_Point_System :: core.Shapes_Point_System

Shapes_Compass :: core.Shapes_Compass
Shapes_Pen :: core.Shapes_Pen
Shapes_Line :: core.Shapes_Line
Shapes_Circle :: core.Shapes_Circle
Shapes_Filled_Circle :: core.Shapes_Filled_Circle
Shapes_Triangle :: core.Shapes_Triangle
Shapes_Square :: core.Shapes_Square
Shapes_Pentagon :: core.Shapes_Pentagon

Shapes_Draw_Base :: core.Shapes_Draw_Base
Shapes_Label_Draw :: core.Shapes_Label_Draw
Shapes_Point_Draw :: core.Shapes_Point_Draw
Shapes_Line_Draw :: core.Shapes_Line_Draw
Shapes_Circle_Draw :: core.Shapes_Circle_Draw
Shapes_Filled_Circle_Draw :: core.Shapes_Filled_Circle_Draw
Shapes_Polygon_Draw :: core.Shapes_Polygon_Draw
Shapes_Polygon_Ring_Node :: core.Shapes_Polygon_Ring_Node
Shapes_Polygon_Triangle :: core.Shapes_Polygon_Triangle
Shapes_Pen_Draw :: core.Shapes_Pen_Draw
Shapes_Compass_Draw :: core.Shapes_Compass_Draw
Shapes_Draw_Cache_Item :: core.Shapes_Draw_Cache_Item


Polygon_Cache_Range_Reservation :: struct {
    first_vertex:       int,
    first_triangle:     int,
    max_triangle_count: int,
    ok:                 bool,
}

//   Snapshot current point positions into per-point previous_position for interpolation.
//
// Parameters:
//   - point_system: Point system whose current positions are cached.
//
// Returns:
//   - none.
update_last_cache_vectors :: proc(
    point_system: ^Shapes_Point_System) {

    for i in 0..<point_system^.next_point_index {
        point_system^.points[i].previous_position = point_system^.points[i].position
    }
}

//   Freeze animation insertion starts at current point/constraint indices.
//
// Parameters:
//   - point_system: Point system to mark with animation start indices.
//
// Returns:
//   - none.
freeze_system_indices :: proc(
    point_system: ^Shapes_Point_System) {

    point_system^.anim_points_start = point_system^.next_point_index
    point_system^.anim_constraints_start = point_system^.next_constraint_index
}

//   Clear animation-owned points and constraints while preserving baseline tool setup.
//
// Parameters:
//   - point_system: Point system containing animation and baseline data.
//   - particle_system: Particle system used to emit clear-burst effects.
//
// Returns:
//   - none.
clear_animation_data :: proc(
    point_system: ^Shapes_Point_System,
    particle_system: ^core.Particle_System,
    iso_scale: ^core.Iso_Scale = nil) {

    particles.emit_shapes_clear_burst(particle_system, point_system, iso_scale)

    for i in point_system^.anim_points_start..<MAX_SHAPESPOINTS {
        point_system^.points[i] = {}
        point_system^.points[i].do_draw = false
    }
    for i in point_system^.anim_constraints_start..<MAX_SHAPESCONSTRAINTS {
        point_system^.constraints[i] = {}
        point_system^.constraints[i].do_apply = false
    }

    point_system^.next_point_index = point_system^.anim_points_start
    point_system^.next_constraint_index = point_system^.anim_constraints_start
}

//   Build the draw cache from current point-system state using interpolation alpha.
//
// Parameters:
//   - point_system: Point system source for cached draw items.
//   - alpha: Interpolation factor in [0, 1] between previous and current vectors.
//
// Returns:
//   - none.
build_draw_cache :: proc(
    point_system: ^Shapes_Point_System,
    alpha: f32) {

    draw_cache_reset(point_system)

    for index in 0..<point_system^.next_point_index {
        src := &point_system^.points[index]
        if !src^.do_draw {
            continue
        }

        cache_push_draw_item(point_system, index, src, alpha)
    }

    sort_draw_cache_low(point_system)
}



//   Reset draw-cache counters and tool draw flags before cache rebuild.
draw_cache_reset :: proc(
    point_system: ^Shapes_Point_System) {

    point_system^.draw_cache.item_count = 0
    point_system^.draw_cache.polygon_vertex_count = 0
    point_system^.draw_cache.polygon_triangle_count = 0
    point_system^.draw_cache.draw_pen = false
    point_system^.draw_cache.draw_compass = false
}

//   Return true when one z coordinate should count as on-surface for cache sorting.
draw_cache_coord_is_flat :: #force_inline proc(value: f32) -> bool {
    return value >= -DRAW_CACHE_SORT_FLAT_EPSILON && value <= DRAW_CACHE_SORT_FLAT_EPSILON
}

//   Return true when one cached point lies on the drawing surface within epsilon.
draw_cache_point_is_flat :: #force_inline proc(point: Vector3) -> bool {
    return draw_cache_coord_is_flat(point.z)
}

//   Compute one visual depth scalar matching the isometric layering heuristic.
draw_cache_visual_depth :: #force_inline proc(point: Vector3) -> f32 {
    return point.x + point.y - point.z
}

//   Compute one polygon centroid and whether all cached polygon vertices are flat.
draw_cache_polygon_centroid_and_flatness :: proc(
    point_system: ^Shapes_Point_System,
    poly: ^Shapes_Polygon_Draw) -> (Vector3, bool) {

    if poly^.vertex_count <= 0 {
        return {}, false
    }

    vertices := point_system^.draw_cache.polygon_vertices[
        poly^.first_vertex:poly^.first_vertex + poly^.vertex_count]
    sum := Vector3{}
    flat := true

    for vertex in vertices {
        sum += vertex
        if !draw_cache_point_is_flat(vertex) {
            flat = false
        }
    }

    inv_count := 1.0 / f32(poly^.vertex_count)
    return sum * inv_count, flat
}

//   Return representative depth and flatness for one cached line item.
draw_cache_line_depth_and_flatness :: #force_inline proc(
    line: Shapes_Line_Draw) -> (f32, bool) {
    midpoint := (line.point1 + line.point2) * 0.5
    flat := draw_cache_point_is_flat(line.point1) && draw_cache_point_is_flat(line.point2)
    return draw_cache_visual_depth(midpoint), flat
}

//   Return representative depth and flatness for one cached circle item.
draw_cache_circle_depth_and_flatness :: #force_inline proc(
    circle: Shapes_Circle_Draw) -> (f32, bool) {
    flat := draw_cache_point_is_flat(circle.center) &&
        draw_cache_point_is_flat(circle.start) &&
        draw_cache_point_is_flat(circle.end)
    return draw_cache_visual_depth(circle.center), flat
}

//   Return representative depth and flatness for one cached filled-circle item.
draw_cache_filledcircle_depth_and_flatness :: #force_inline proc(
    circle: Shapes_Filled_Circle_Draw) -> (f32, bool) {
    flat := draw_cache_point_is_flat(circle.center) &&
        draw_cache_point_is_flat(circle.start) &&
        draw_cache_point_is_flat(circle.end)
    return draw_cache_visual_depth(circle.center), flat
}

//   Return representative depth and flatness for one cached pen item.
draw_cache_pen_depth_and_flatness :: #force_inline proc(
    pen: Shapes_Pen_Draw) -> (f32, bool) {
    midpoint := (pen.joint1 + pen.joint2) * 0.5
    flat := draw_cache_point_is_flat(pen.joint1) && draw_cache_point_is_flat(pen.joint2)
    return draw_cache_visual_depth(midpoint), flat
}

//   Return representative depth and flatness for one cached compass item.
draw_cache_compass_depth_and_flatness :: #force_inline proc(
    compass: Shapes_Compass_Draw) -> (f32, bool) {
    centroid := (compass.joint1 + compass.pivot + compass.joint2) / 3.0
    flat := draw_cache_point_is_flat(compass.joint1) &&
        draw_cache_point_is_flat(compass.pivot) &&
        draw_cache_point_is_flat(compass.joint2)
    return draw_cache_visual_depth(centroid), flat
}

//   Return representative depth and flatness for one cached low-geometry item.
//
// Notes:
//   - Flat items are later kept in authored creation order when compared to
//     other flat items.
draw_cache_item_depth_and_flatness :: proc(
    point_system: ^Shapes_Point_System,
    item: ^Shapes_Draw_Cache_Item) -> (f32, bool) {

    switch &typed in item {
    case Shapes_Label_Draw:
        return draw_cache_visual_depth(typed.point1),
            draw_cache_point_is_flat(typed.point1)
    case Shapes_Point_Draw:
        return draw_cache_visual_depth(typed.point1),
            draw_cache_point_is_flat(typed.point1)
    case Shapes_Line_Draw: return draw_cache_line_depth_and_flatness(typed)
    case Shapes_Circle_Draw: return draw_cache_circle_depth_and_flatness(typed)
    case Shapes_Filled_Circle_Draw:
        return draw_cache_filledcircle_depth_and_flatness(typed)
    case Shapes_Polygon_Draw:
        centroid, flat := draw_cache_polygon_centroid_and_flatness(point_system, &typed)
        return draw_cache_visual_depth(centroid), flat
    case Shapes_Pen_Draw: return draw_cache_pen_depth_and_flatness(typed)
    case Shapes_Compass_Draw: return draw_cache_compass_depth_and_flatness(typed)
    case:
        return 0, false
    }
}

//   Return true when lhs should be drawn earlier than rhs in the low-cache pass.
//
// Notes:
//   - Two fully flat items preserve authored order and do not reorder by x/y.
//   - Near-equal depth also preserves authored order for stable playback.
draw_cache_item_should_precede :: #force_inline proc(
    lhs_depth: f32,
    lhs_flat: bool,
    rhs_depth: f32,
    rhs_flat: bool) -> bool {

    if lhs_flat && rhs_flat {
        return false
    }

    depth_delta := lhs_depth - rhs_depth
    if depth_delta >= -DRAW_CACHE_SORT_FLAT_EPSILON &&
        depth_delta <= DRAW_CACHE_SORT_FLAT_EPSILON {
        return false
    }

    return lhs_depth > rhs_depth
}

//   Stable-sort low cached geometry items by representative visual depth.
//
// Notes:
//   - Applies only whole-primitive painter ordering; it does not split
//     primitives or solve exact visibility.
//   - Fully flat `z = 0` items keep their authored creation order.
sort_draw_cache_low :: proc(point_system: ^Shapes_Point_System) {
    item_count := point_system^.draw_cache.item_count
    if item_count <= 1 {
        return
    }

    depths: [MAX_SHAPESPOINTS]f32
    flats: [MAX_SHAPESPOINTS]bool

    for i in 0..<item_count {
        depths[i], flats[i] = draw_cache_item_depth_and_flatness(
            point_system,
            &point_system^.draw_cache.items[i])
    }

    for i in 1..<item_count {
        item := point_system^.draw_cache.items[i]
        item_depth := depths[i]
        item_flat := flats[i]
        j := i

        for j > 0 {
            prev_index := j - 1
            if !draw_cache_item_should_precede(
                item_depth,
                item_flat,
                depths[prev_index],
                flats[prev_index]) {
                break
            }

            point_system^.draw_cache.items[j] = point_system^.draw_cache.items[prev_index]
            depths[j] = depths[prev_index]
            flats[j] = flats[prev_index]
            j = prev_index
        }

        point_system^.draw_cache.items[j] = item
        depths[j] = item_depth
        flats[j] = item_flat
    }
}

//   Compute interpolated point position between previous and current vectors.
//
// Notes:
//   - Falls back to current position when previous vector is unavailable.
lerped_point_position :: proc(
    point_system: ^Shapes_Point_System,
    index: int,
    alpha: f32) -> (Vector3, bool) {

    if index < 0 || index >= MAX_SHAPESPOINTS {
        return {}, false
    }

    curr := point_system^.points[index]
    curr_pos, has_curr := curr.position.?
    if !has_curr {
        return {}, false
    }

    prev := curr.previous_position.? or_else curr_pos
    return linalg.lerp(prev, curr_pos, alpha), true
}

//   Interpolate a contiguous child-point chain into out in child-link order.
//
// Notes:
//   - src.child_point_head is used as the first child index.
lerped_child_positions :: proc(
    point_system: ^Shapes_Point_System,
    src: ^Shapes_Point,
    alpha: f32,
    out: []Vector3) -> bool {

    if len(out) <= 0 {
        return false
    }

    child_index := src^.child_point_head
    for i in 0..<len(out) {
        point, ok := lerped_point_position(point_system, child_index, alpha)
        if !ok {
            return false
        }
        out[i] = point

        if i + 1 < len(out) {
            if child_index < 0 || child_index >= MAX_SHAPESPOINTS {
                return false
            }
            child_index = point_system^.points[child_index].next_child_point
        }
    }

    return true
}

//   Reserve and return the next draw-cache item slot.
draw_cache_next_item_slot :: #force_inline proc(
    point_system: ^Shapes_Point_System) -> (^Shapes_Draw_Cache_Item, bool) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return nil, false
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point_system^.draw_cache.item_count += 1
    return slot, true
}

//   Reserve a contiguous polygon vertex range in the draw-cache pool.
draw_cache_reserve_polygon_vertices :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    count: int) -> (int, bool) {

    if count <= 0 {
        return 0, false
    }

    next := point_system^.draw_cache.polygon_vertex_count
    if next + count > len(point_system^.draw_cache.polygon_vertices) {
        return 0, false
    }

    point_system^.draw_cache.polygon_vertex_count = next + count
    return next, true
}

//   Reserve a contiguous polygon triangle range in the draw-cache pool.
draw_cache_reserve_polygon_triangles :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    count: int) -> (int, bool) {

    if count <= 0 {
        return 0, false
    }

    next := point_system^.draw_cache.polygon_triangle_count
    if next + count > len(point_system^.draw_cache.polygon_triangles) {
        return 0, false
    }

    point_system^.draw_cache.polygon_triangle_count = next + count
    return next, true
}

//   Build the common draw-base metadata shared by cached draw item variants.
make_draw_base :: #force_inline proc(
    source_index: int,
    src: ^Shapes_Point) -> Shapes_Draw_Base {

    color := src^.color.? or_else rl.WHITE
    active_color, has_active_color := src^.active_color.?

    return Shapes_Draw_Base{
        kind = src^.kind,
        source_index = source_index,
        brush_size = src^.brush_size,
        color = color,
        active_color = active_color,
        has_active_color = has_active_color,
        active_child = src^.active_child,
    }
}

//   Compute signed polygon area on the XY plane.
polygon_signed_area_xy :: #force_inline proc(vertices: []Vector3) -> f32 {
    if len(vertices) < 3 {
        return 0
    }

    area: f32 = 0
    for i in 0..<len(vertices) {
        j := i + 1
        if j >= len(vertices) {
            j = 0
        }
        area += vertices[i].x * vertices[j].y - vertices[j].x * vertices[i].y
    }

    return area * 0.5
}

//   Compute signed XY cross product of edges AB and AC.
cross2_xy :: #force_inline proc(a, b, c: Vector3) -> f32 {
    abx := b.x - a.x
    aby := b.y - a.y
    acx := c.x - a.x
    acy := c.y - a.y
    return abx * acy - aby * acx
}

//   Test whether p lies inside or on the boundary of triangle ABC in XY.
point_in_triangle_xy :: #force_inline proc(p, a, b, c: Vector3) -> bool {
    d1 := cross2_xy(a, b, p)
    d2 := cross2_xy(b, c, p)
    d3 := cross2_xy(c, a, p)

    has_neg := d1 < 0 || d2 < 0 || d3 < 0
    has_pos := d1 > 0 || d2 > 0 || d3 > 0
    return !(has_neg && has_pos)
}

//   Append one triangle into the cached polygon triangle index pool.
emit_polygon_triangle :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    triangle_start: int,
    triangle_count: ^int,
    base_vertex: int,
    a, b, c: int) {

    write_index := triangle_start + triangle_count^
    point_system^.draw_cache.polygon_triangles[write_index] = Shapes_Polygon_Triangle{
        base_vertex + a,
        base_vertex + b,
        base_vertex + c,
    }
    triangle_count^ += 1
}

//   Initialize an active doubly-linked ring over count polygon vertices.
init_polygon_ring_nodes :: #force_inline proc(
    ring: []Shapes_Polygon_Ring_Node,
    count: int) {

    for i in 0..<count {
        prev := i - 1
        if prev < 0 {
            prev = count - 1
        }

        next := i + 1
        if next >= count {
            next = 0
        }

        ring[i] = Shapes_Polygon_Ring_Node{ prev, next, true }
    }
}

//   Return true when node is a valid ear candidate under current winding.
is_polygon_ear_node :: #force_inline proc(
    ring: []Shapes_Polygon_Ring_Node,
    vertices: []Vector3,
    node, prev, next: int,
    want_ccw: bool) -> bool {

    a := vertices[prev]
    b := vertices[node]
    c := vertices[next]

    cross := cross2_xy(a, b, c)
    if want_ccw {
        if cross <= 0 {
            return false
        }
    } else {
        if cross >= 0 {
            return false
        }
    }

    scan := ring[next].next
    for scan != prev {
        if ring[scan].active && point_in_triangle_xy(vertices[scan], a, b, c) {
            return false
        }
        scan = ring[scan].next
    }

    return true
}

//   Emit the final triangle from the remaining active 3-node ring.
emit_polygon_last_ring_triangle :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    ring: []Shapes_Polygon_Ring_Node,
    count: int,
    node: int,
    want_ccw: bool,
    triangle_start: int,
    triangle_count: ^int,
    base_vertex: int) {

    first := node
    if !ring[first].active {
        for i in 0..<count {
            if ring[i].active {
                first = i
                break
            }
        }
    }

    second := ring[first].next
    third := ring[second].next
    if want_ccw {
        emit_polygon_triangle(
            point_system,
            triangle_start,
            triangle_count,
            base_vertex,
            first,
            second,
            third)
    } else {
        emit_polygon_triangle(
            point_system,
            triangle_start,
            triangle_count,
            base_vertex,
            third,
            second,
            first)
    }
}

//   Emit fallback fan triangulation for degenerate/non-ear-clippable polygons.
emit_polygon_fallback_fan :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    count: int,
    want_ccw: bool,
    triangle_start: int,
    triangle_count: ^int,
    base_vertex: int) {

    for i in 1..<count - 1 {
        if want_ccw {
            emit_polygon_triangle(
                point_system,
                triangle_start,
                triangle_count,
                base_vertex,
                0,
                i,
                i + 1)
        } else {
            emit_polygon_triangle(
                point_system,
                triangle_start,
                triangle_count,
                base_vertex,
                0,
                i + 1,
                i)
        }
    }
}

//   Run the main ear-removal loop and return remaining active ring node count.
triangulate_polygon_ear_loop :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    ring: []Shapes_Polygon_Ring_Node,
    vertices: []Vector3,
    count: int,
    want_ccw: bool,
    triangle_start: int,
    triangle_count: ^int,
    base_vertex: int) -> int {

    remaining := count
    node := 0
    guard := count * count

    for remaining > 3 && guard > 0 {
        guard -= 1

        if !ring[node].active {
            node = ring[node].next
            continue
        }

        prev := ring[node].prev
        next := ring[node].next
        if !is_polygon_ear_node(ring, vertices, node, prev, next, want_ccw) {
            node = next
            continue
        }

        if want_ccw {
            emit_polygon_triangle(point_system, triangle_start, triangle_count,
                base_vertex, prev, node, next)
        } else {
            emit_polygon_triangle(point_system, triangle_start, triangle_count,
                base_vertex, next, node, prev)
        }

        ring[prev].next = next
        ring[next].prev = prev
        ring[node].active = false
        remaining -= 1
        node = next
    }

    return remaining
}

//   Triangulate a polygon into cached triangle indices using ear clipping.
triangulate_polygon_ear_clip :: proc(
    point_system: ^Shapes_Point_System,
    base_vertex: int,
    vertices: []Vector3,
    triangle_start: int) -> int {

    count := len(vertices)
    if count < 3 {
        return 0
    }

    ring := point_system^.draw_cache.polygon_ring_nodes[:count]
    init_polygon_ring_nodes(ring, count)

    area := polygon_signed_area_xy(vertices)
    want_ccw := area >= 0
    triangle_count := 0
    remaining := triangulate_polygon_ear_loop(
        point_system,
        ring,
        vertices,
        count,
        want_ccw,
        triangle_start,
        &triangle_count,
        base_vertex)

    if remaining == 3 {
        emit_polygon_last_ring_triangle(
            point_system,
            ring,
            count,
            0,
            want_ccw,
            triangle_start,
            &triangle_count,
            base_vertex)
        return triangle_count
    }

    emit_polygon_fallback_fan(
        point_system,
        count,
        want_ccw,
        triangle_start,
        &triangle_count,
        base_vertex)

    return triangle_count
}

//   Reserve vertex and triangle cache ranges for one polygon draw item.
reserve_polygon_cache_ranges :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    vertex_count: int) -> Polygon_Cache_Range_Reservation {

    first_vertex, has_vertex_space := draw_cache_reserve_polygon_vertices(
        point_system,
        vertex_count)
    if !has_vertex_space {
        return Polygon_Cache_Range_Reservation{0, 0, 0, false}
    }

    max_triangle_count := vertex_count - 2
    first_triangle, has_triangle_space := draw_cache_reserve_polygon_triangles(
        point_system,
        max_triangle_count)
    if !has_triangle_space {
        point_system^.draw_cache.polygon_vertex_count -= vertex_count
        return Polygon_Cache_Range_Reservation{0, 0, 0, false}
    }

    return Polygon_Cache_Range_Reservation{
        first_vertex,
        first_triangle,
        max_triangle_count,
        true,
    }
}

//   Roll back previously reserved polygon cache ranges.
rollback_polygon_cache_ranges :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    vertex_count: int,
    reserved_triangle_count: int) {

    point_system^.draw_cache.polygon_vertex_count -= vertex_count
    point_system^.draw_cache.polygon_triangle_count -= reserved_triangle_count
}

//   Shrink reserved triangle range to the actual emitted triangle count.
finalize_polygon_triangle_reservation :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    first_triangle: int,
    triangle_count: int) {

    point_system^.draw_cache.polygon_triangle_count = first_triangle + triangle_count
}


//   Dispatch one visible point-system shape into its cached draw-item representation.
cache_push_draw_item :: #force_inline proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    switch src^.kind {
    case .Label: cache_push_label(point_system, source_index, src, alpha)
    case .Point: cache_push_point(point_system, source_index, src, alpha)
    case .Line: cache_push_line(point_system, source_index, src, alpha)
    case .Circle: cache_push_circle(point_system, source_index, src, alpha)
    case .FilledCircle: cache_push_filledcircle(point_system, source_index, src, alpha)
    case .Triangle,
        .Square,
        .Pentagon:
        cache_push_polygon(point_system, source_index, src, alpha)
    case .Pen: cache_push_pen(point_system, source_index, src, alpha)
    case .Compass: cache_push_compass(point_system, source_index, src, alpha)
    }
}


//   Push a cached label draw item into the draw-cache item list.
cache_push_label :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    p0, has_position := lerped_point_position(point_system, source_index, alpha)
    if !has_position {
        return
    }

    label, ok := src^.label.?
    if !ok {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Shapes_Label_Draw{ make_draw_base(source_index, src),
        p0, label, src^.decoration_kind }
    slot^ = point
}

//   Push a cached point draw item into the draw-cache item list.
cache_push_point :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    p0, ok := lerped_point_position(point_system, source_index, alpha)
    if !ok {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Shapes_Point_Draw{ make_draw_base(source_index, src), p0 }
    slot^ = point
}

//   Push a cached line draw item into the draw-cache item list.
cache_push_line :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Shapes_Line_Draw{ make_draw_base(source_index, src),
        child_points[0], child_points[1] }
    slot^ = point
}

//   Push a cached circle draw item into the draw-cache item list.
//
// Notes:
//   - Honors active_child orientation by swapping start/end when required.
cache_push_circle :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    center, ok := lerped_point_position(point_system, source_index, alpha)
    if !ok {
        return
    }

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    start := child_points[0]
    end := child_points[1]

    if src^.active_child > 1 {
        start, end = end, start
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Shapes_Circle_Draw{ make_draw_base(source_index, src), center, start, end,
        src^.offset }
    slot^ = point
}

//   Push a cached filled-circle draw item into the draw-cache item list.
//
// Notes:
//   - Honors active_child orientation by swapping start/end when required.
cache_push_filledcircle :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    center, ok := lerped_point_position(point_system, source_index, alpha)
    if !ok {
        return
    }

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    start := child_points[0]
    end := child_points[1]

    if src^.active_child > 1 {
        start, end = end, start
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Shapes_Filled_Circle_Draw{ make_draw_base(source_index, src), center,
        start, end, src^.offset }
    slot^ = point
}

//   Push a cached polygon draw item into the draw-cache item list.
cache_push_polygon :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    vertex_count := src^.child_count
    if vertex_count < 3 {
        return
    }

    reservation := reserve_polygon_cache_ranges(point_system, vertex_count)
    if !reservation.ok {
        return
    }

    vertices := point_system^.draw_cache.polygon_vertices[
        reservation.first_vertex:reservation.first_vertex + vertex_count]
    if !lerped_child_positions(point_system, src, alpha, vertices) {
        rollback_polygon_cache_ranges(
            point_system,
            vertex_count,
            reservation.max_triangle_count)
        return
    }

    triangle_count := triangulate_polygon_ear_clip(
        point_system,
        reservation.first_vertex,
        vertices,
        reservation.first_triangle)

    finalize_polygon_triangle_reservation(
        point_system,
        reservation.first_triangle,
        triangle_count)

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        rollback_polygon_cache_ranges(point_system, vertex_count, triangle_count)
        return
    }

    point := Shapes_Polygon_Draw{
        make_draw_base(source_index, src),
        reservation.first_vertex,
        vertex_count,
        reservation.first_triangle,
        triangle_count,
    }
    slot^ = point
}

//   Update cached pen tool draw data and pen draw-enable flag.
cache_push_pen :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    point := Shapes_Pen_Draw{
        make_draw_base(source_index, src), child_points[0], child_points[1] }
    point_system^.draw_cache.pen = point
    point_system^.draw_cache.draw_pen = src^.do_draw

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    slot^ = point
}

//   Update cached compass tool draw data and compass draw-enable flag.
cache_push_compass :: proc(
    point_system: ^Shapes_Point_System,
    source_index: int,
    src: ^Shapes_Point,
    alpha: f32) {

    child_points: [3]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    point := Shapes_Compass_Draw{
        make_draw_base(source_index, src),
        child_points[0],
        child_points[1],
        child_points[2],
    }
    point_system^.draw_cache.compass = point
    point_system^.draw_cache.draw_compass = src^.do_draw

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    slot^ = point
}
