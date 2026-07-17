package kine

// The major system calls for the shape system are for creating the immediate draw cache.
// This just builds the cache into the existing point system.

import "../core"
import "../particles"

import "core:math/linalg"

import rl "vendor:raylib"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
MAX_KINECONSTRAINTS :: core.MAX_KINECONSTRAINTS

Vector3 :: core.Vector3
Kine_Shape_Point_Type :: core.Kine_Shape_Point_Type
Kine_Shape_Point :: core.Kine_Shape_Point

Kine_Constraint_Kind :: core.Kine_Constraint_Kind
Kine_Constraint :: core.Kine_Constraint
Kine_Point_System :: core.Kine_Point_System

Kine_Shape_Compass :: core.Kine_Shape_Compass
Kine_Shape_Pen :: core.Kine_Shape_Pen
Kine_Shape_Line :: core.Kine_Shape_Line
Kine_Shape_Circle :: core.Kine_Shape_Circle
Kine_Shape_Filled_Circle :: core.Kine_Shape_Filled_Circle
Kine_Shape_Triangle :: core.Kine_Shape_Triangle
Kine_Shape_Square :: core.Kine_Shape_Square
Kine_Shape_Pentagon :: core.Kine_Shape_Pentagon

Kine_Draw_Base :: core.Kine_Draw_Base
Kine_Label_Draw :: core.Kine_Label_Draw
Kine_Point_Draw :: core.Kine_Point_Draw
Kine_Line_Draw :: core.Kine_Line_Draw
Kine_Circle_Draw :: core.Kine_Circle_Draw
Kine_Filled_Circle_Draw :: core.Kine_Filled_Circle_Draw
Kine_Polygon_Draw :: core.Kine_Polygon_Draw
Kine_Polygon_Ring_Node :: core.Kine_Polygon_Ring_Node
Kine_Polygon_Triangle :: core.Kine_Polygon_Triangle
Kine_Pen_Draw :: core.Kine_Pen_Draw
Kine_Compass_Draw :: core.Kine_Compass_Draw
Kine_Draw_Cache_Item :: core.Kine_Draw_Cache_Item

//   Snapshot current point positions into per-point previous_position for interpolation.
//
// Parameters:
//   - point_system: Point system whose current positions are cached.
//
// Returns:
//   - none.
kine_update_last_cache_vectors :: proc(
    point_system: ^Kine_Point_System) {

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
kine_freeze_system_indices :: proc(
    point_system: ^Kine_Point_System) {

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
kine_clear_animation_data :: proc(
    point_system: ^Kine_Point_System,
    particle_system: ^core.Particle_System) {

    particles.emit_kine_clear_burst(particle_system, point_system)

    for i in point_system^.anim_points_start..<MAX_KINEPOINTS {
        point_system^.points[i] = {}
        point_system^.points[i].do_draw = false
    }
    for i in point_system^.anim_constraints_start..<MAX_KINECONSTRAINTS {
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
build_kine_draw_cache :: proc(
    point_system: ^Kine_Point_System,
    alpha: f32) {

    kine_draw_cache_reset(point_system)

    for index in 0..<point_system^.next_point_index {
        src := &point_system^.points[index]
        if !src^.do_draw {
            continue
        }

        switch src^.kind {
        case .Label:
            cache_push_label(point_system, index, src, alpha)
        case .Point:
            cache_push_point(point_system, index, src, alpha)
        case .Line:
            cache_push_line(point_system, index, src, alpha)
        case .Circle:
            cache_push_circle(point_system, index, src, alpha)
        case .FilledCircle:
            cache_push_filledcircle(point_system, index, src, alpha)
        case .Triangle:
            cache_push_polygon(point_system, index, src, alpha)
        case .Square:
            cache_push_polygon(point_system, index, src, alpha)
        case .Pentagon:
            cache_push_polygon(point_system, index, src, alpha)
        case .Pen:
            cache_push_pen(point_system, index, src, alpha)
        case .Compass:
            cache_push_compass(point_system, index, src, alpha)
        }
    }
}



//   Reset draw-cache counters and tool draw flags before cache rebuild.
kine_draw_cache_reset :: proc(
    point_system: ^Kine_Point_System) {

    point_system^.draw_cache.item_count = 0
    point_system^.draw_cache.polygon_vertex_count = 0
    point_system^.draw_cache.polygon_triangle_count = 0
    point_system^.draw_cache.draw_pen = false
    point_system^.draw_cache.draw_compass = false
}

//   Compute interpolated point position between previous and current vectors.
//
// Notes:
//   - Falls back to current position when previous vector is unavailable.
lerped_point_position :: proc(
    point_system: ^Kine_Point_System,
    index: int,
    alpha: f32) -> (Vector3, bool) {

    if index < 0 || index >= MAX_KINEPOINTS {
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
    point_system: ^Kine_Point_System,
    src: ^Kine_Shape_Point,
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
            if child_index < 0 || child_index >= MAX_KINEPOINTS {
                return false
            }
            child_index = point_system^.points[child_index].next_child_point
        }
    }

    return true
}

//   Reserve and return the next draw-cache item slot.
draw_cache_next_item_slot :: #force_inline proc(
    point_system: ^Kine_Point_System) -> (^Kine_Draw_Cache_Item, bool) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return nil, false
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point_system^.draw_cache.item_count += 1
    return slot, true
}

//   Reserve a contiguous polygon vertex range in the draw-cache pool.
draw_cache_reserve_polygon_vertices :: #force_inline proc(
    point_system: ^Kine_Point_System,
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
    point_system: ^Kine_Point_System,
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
    src: ^Kine_Shape_Point) -> Kine_Draw_Base {

    color := src^.color.? or_else rl.WHITE
    active_color, has_active_color := src^.active_color.?

    return Kine_Draw_Base{
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
    point_system: ^Kine_Point_System,
    triangle_start: int,
    triangle_count: ^int,
    base_vertex: int,
    a, b, c: int) {

    write_index := triangle_start + triangle_count^
    point_system^.draw_cache.polygon_triangles[write_index] = Kine_Polygon_Triangle{
        base_vertex + a,
        base_vertex + b,
        base_vertex + c,
    }
    triangle_count^ += 1
}

//   Initialize an active doubly-linked ring over count polygon vertices.
init_polygon_ring_nodes :: #force_inline proc(
    ring: []Kine_Polygon_Ring_Node,
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

        ring[i] = Kine_Polygon_Ring_Node{ prev, next, true }
    }
}

//   Return true when node is a valid ear candidate under current winding.
is_polygon_ear_node :: #force_inline proc(
    ring: []Kine_Polygon_Ring_Node,
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
    point_system: ^Kine_Point_System,
    ring: []Kine_Polygon_Ring_Node,
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
    point_system: ^Kine_Point_System,
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
    point_system: ^Kine_Point_System,
    ring: []Kine_Polygon_Ring_Node,
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
            emit_polygon_triangle(point_system, triangle_start, triangle_count, base_vertex, prev, node, next)
        } else {
            emit_polygon_triangle(point_system, triangle_start, triangle_count, base_vertex, next, node, prev)
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
    point_system: ^Kine_Point_System,
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
    point_system: ^Kine_Point_System,
    vertex_count: int) -> (int, int, int, bool) {

    first_vertex, has_vertex_space := draw_cache_reserve_polygon_vertices(
        point_system,
        vertex_count)
    if !has_vertex_space {
        return 0, 0, 0, false
    }

    max_triangle_count := vertex_count - 2
    first_triangle, has_triangle_space := draw_cache_reserve_polygon_triangles(
        point_system,
        max_triangle_count)
    if !has_triangle_space {
        point_system^.draw_cache.polygon_vertex_count -= vertex_count
        return 0, 0, 0, false
    }

    return first_vertex, first_triangle, max_triangle_count, true
}

//   Roll back previously reserved polygon cache ranges.
rollback_polygon_cache_ranges :: #force_inline proc(
    point_system: ^Kine_Point_System,
    vertex_count: int,
    reserved_triangle_count: int) {

    point_system^.draw_cache.polygon_vertex_count -= vertex_count
    point_system^.draw_cache.polygon_triangle_count -= reserved_triangle_count
}

//   Shrink reserved triangle range to the actual emitted triangle count.
finalize_polygon_triangle_reservation :: #force_inline proc(
    point_system: ^Kine_Point_System,
    first_triangle: int,
    triangle_count: int) {

    point_system^.draw_cache.polygon_triangle_count = first_triangle + triangle_count
}


//   Push a cached label draw item into the draw-cache item list.
cache_push_label :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
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

    point := Kine_Label_Draw{ make_draw_base(source_index, src), p0, label, src^.decoration_kind }
    slot^ = point
}

//   Push a cached point draw item into the draw-cache item list.
cache_push_point :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    p0, ok := lerped_point_position(point_system, source_index, alpha)
    if !ok {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Kine_Point_Draw{ make_draw_base(source_index, src), p0 }
    slot^ = point
}

//   Push a cached line draw item into the draw-cache item list.
cache_push_line :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Kine_Line_Draw{ make_draw_base(source_index, src), child_points[0], child_points[1] }
    slot^ = point
}

//   Push a cached circle draw item into the draw-cache item list.
//
// Notes:
//   - Honors active_child orientation by swapping start/end when required.
cache_push_circle :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
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

    point := Kine_Circle_Draw{ make_draw_base(source_index, src), center, start, end, src^.offset }
    slot^ = point
}

//   Push a cached filled-circle draw item into the draw-cache item list.
//
// Notes:
//   - Honors active_child orientation by swapping start/end when required.
cache_push_filledcircle :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
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

    point := Kine_Filled_Circle_Draw{ make_draw_base(source_index, src), center, start, end }
    slot^ = point
}

//   Push a cached polygon draw item into the draw-cache item list.
cache_push_polygon :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    vertex_count := src^.child_count
    if vertex_count < 3 {
        return
    }

    first_vertex, first_triangle, max_triangle_count, ok := reserve_polygon_cache_ranges(
        point_system,
        vertex_count)
    if !ok {
        return
    }

    vertices := point_system^.draw_cache.polygon_vertices[first_vertex:first_vertex + vertex_count]
    if !lerped_child_positions(point_system, src, alpha, vertices) {
        rollback_polygon_cache_ranges(point_system, vertex_count, max_triangle_count)
        return
    }

    triangle_count := triangulate_polygon_ear_clip(
        point_system,
        first_vertex,
        vertices,
        first_triangle)

    finalize_polygon_triangle_reservation(point_system, first_triangle, triangle_count)

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        rollback_polygon_cache_ranges(point_system, vertex_count, triangle_count)
        return
    }

    point := Kine_Polygon_Draw{
        make_draw_base(source_index, src),
        first_vertex,
        vertex_count,
        first_triangle,
        triangle_count,
    }
    slot^ = point
}

//   Update cached pen tool draw data and pen draw-enable flag.
cache_push_pen :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [2]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    point_system^.draw_cache.pen.base = make_draw_base(source_index, src)
    point_system^.draw_cache.pen.joint1 = child_points[0]
    point_system^.draw_cache.pen.joint2 = child_points[1]
    point_system^.draw_cache.draw_pen = src^.do_draw
}

//   Update cached compass tool draw data and compass draw-enable flag.
cache_push_compass :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [3]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    point_system^.draw_cache.compass.base = make_draw_base(source_index, src)
    point_system^.draw_cache.compass.joint1 = child_points[0]
    point_system^.draw_cache.compass.pivot = child_points[1]
    point_system^.draw_cache.compass.joint2 = child_points[2]
    point_system^.draw_cache.draw_compass = src^.do_draw
}
