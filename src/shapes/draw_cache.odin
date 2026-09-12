package shapes

// This file owns the derived draw-cache packet: item/vertex/triangle storage,
// depth-based sorting, and polygon ear-clipping triangulation used by any
// canonical shape source that builds a Shapes_Draw_Cache.

import "../core"

DRAW_CACHE_SORT_FLAT_EPSILON :: 1e-5

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS

Vector3 :: core.Vector3
Shapes_Point_Type :: core.Shapes_Point_Type

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
    first_vertex : int,
    first_triangle : int,
    max_triangle_count : int,
    ok : bool,
}

Polygon_Triangulation :: struct {
    cache : ^core.Shapes_Draw_Cache,
    ring : []Shapes_Polygon_Ring_Node,
    vertices : []Vector3,
    count : int,
    want_ccw : bool,
    triangle_start : int,
    triangle_count : ^int,
    base_vertex : int,
}

//   Reset one derived packet before rebuilding it from any canonical source.
draw_cache_reset_storage :: proc(cache: ^core.Shapes_Draw_Cache) {

    cache.item_count = 0
    cache.label_byte_count = 0
    cache.polygon_vertex_count = 0
    cache.polygon_triangle_count = 0
    cache.draw_pen = false
    cache.draw_compass = false
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
    cache: ^core.Shapes_Draw_Cache,
    poly: ^Shapes_Polygon_Draw) -> (Vector3, bool) {

    if poly^.vertex_count <= 0 {
        return {}, false
    }

    vertices := cache.polygon_vertices[
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
    cache: ^core.Shapes_Draw_Cache,
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
        centroid, flat := draw_cache_polygon_centroid_and_flatness(cache, &typed)
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

//   Stable-sort one derived packet by representative visual depth.
//
// Notes:
//   - Applies only whole-primitive painter ordering; it does not split
//     primitives or solve exact visibility.
//   - Fully flat `z = 0` items keep their authored creation order.
sort_draw_cache_storage :: proc(cache: ^core.Shapes_Draw_Cache) {
    item_count := cache.item_count
    if item_count <= 1 {
        return
    }

    depths: [MAX_SHAPESPOINTS]f32
    flats: [MAX_SHAPESPOINTS]bool

    for i in 0..<item_count {
        depths[i], flats[i] = draw_cache_item_depth_and_flatness(
            cache,
            &cache.items[i])
    }

    for i in 1..<item_count {
        item := cache.items[i]
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

            cache.items[j] = cache.items[prev_index]
            depths[j] = depths[prev_index]
            flats[j] = flats[prev_index]
            j = prev_index
        }

        cache.items[j] = item
        depths[j] = item_depth
        flats[j] = item_flat
    }
}

//   Reserve the next item slot in one derived packet.
draw_cache_next_item_slot_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache) -> (^Shapes_Draw_Cache_Item, bool) {

    if cache.item_count >= len(cache.items) {
        return nil, false
    }

    slot := &cache.items[cache.item_count]
    cache.item_count += 1
    return slot, true
}

//   Reserve a contiguous polygon vertex range in one derived packet.
draw_cache_reserve_polygon_vertices_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache,
    count: int) -> (int, bool) {

    if count <= 0 {
        return 0, false
    }

    next := cache.polygon_vertex_count
    if next + count > len(cache.polygon_vertices) {
        return 0, false
    }

    cache.polygon_vertex_count = next + count
    return next, true
}

//   Reserve a contiguous polygon triangle range in one derived packet.
draw_cache_reserve_polygon_triangles_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache,
    count: int) -> (int, bool) {

    if count <= 0 {
        return 0, false
    }

    next := cache.polygon_triangle_count
    if next + count > len(cache.polygon_triangles) {
        return 0, false
    }

    cache.polygon_triangle_count = next + count
    return next, true
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
    triangulation: Polygon_Triangulation,
    a, b, c: int) {

    write_index := triangulation.triangle_start + triangulation.triangle_count^
    triangulation.cache.polygon_triangles[write_index] =
        Shapes_Polygon_Triangle{
        triangulation.base_vertex + a,
        triangulation.base_vertex + b,
        triangulation.base_vertex + c,
    }
    triangulation.triangle_count^ += 1
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
    triangulation: Polygon_Triangulation,
    node, prev, next: int) -> bool {

    a := triangulation.vertices[prev]
    b := triangulation.vertices[node]
    c := triangulation.vertices[next]

    cross := cross2_xy(a, b, c)
    if triangulation.want_ccw {
        if cross <= 0 {
            return false
        }
    } else {
        if cross >= 0 {
            return false
        }
    }

    scan := triangulation.ring[next].next
    for scan != prev {
        if triangulation.ring[scan].active &&
            point_in_triangle_xy(triangulation.vertices[scan], a, b, c) {
            return false
        }
        scan = triangulation.ring[scan].next
    }

    return true
}

//   Emit the final triangle from the remaining active 3-node ring.
emit_polygon_last_ring_triangle :: #force_inline proc(
    triangulation: Polygon_Triangulation,
    node: int) {

    first := node
    if !triangulation.ring[first].active {
        for i in 0..<triangulation.count {
            if triangulation.ring[i].active {
                first = i
                break
            }
        }
    }

    second := triangulation.ring[first].next
    third := triangulation.ring[second].next
    if triangulation.want_ccw {
        emit_polygon_triangle(triangulation, first, second, third)
    } else {
        emit_polygon_triangle(triangulation, third, second, first)
    }
}

//   Emit fallback fan triangulation for degenerate/non-ear-clippable polygons.
emit_polygon_fallback_fan :: #force_inline proc(
    triangulation: Polygon_Triangulation) {

    for i in 1..<triangulation.count - 1 {
        if triangulation.want_ccw {
            emit_polygon_triangle(triangulation, 0, i, i + 1)
        } else {
            emit_polygon_triangle(triangulation, 0, i + 1, i)
        }
    }
}

//   Run the main ear-removal loop and return remaining active ring node count.
triangulate_polygon_ear_loop :: #force_inline proc(
    triangulation: Polygon_Triangulation) -> int {

    remaining := triangulation.count
    node := 0
    guard := triangulation.count * triangulation.count

    for remaining > 3 && guard > 0 {
        guard -= 1

        if !triangulation.ring[node].active {
            node = triangulation.ring[node].next
            continue
        }

        prev := triangulation.ring[node].prev
        next := triangulation.ring[node].next
        if !is_polygon_ear_node(triangulation, node, prev, next) {
            node = next
            continue
        }

        if triangulation.want_ccw {
            emit_polygon_triangle(triangulation, prev, node, next)
        } else {
            emit_polygon_triangle(triangulation, next, node, prev)
        }

        triangulation.ring[prev].next = next
        triangulation.ring[next].prev = prev
        triangulation.ring[node].active = false
        remaining -= 1
        node = next
    }

    return remaining
}

//   Triangulate one polygon into cache-owned workspace and triangle storage.
triangulate_polygon_ear_clip_storage :: proc(
    cache: ^core.Shapes_Draw_Cache,
    base_vertex: int,
    vertices: []Vector3,
    triangle_start: int) -> int {

    count := len(vertices)
    if count < 3 {
        return 0
    }

    ring := cache.polygon_ring_nodes[:count]
    init_polygon_ring_nodes(ring, count)

    area := polygon_signed_area_xy(vertices)
    want_ccw := area >= 0
    triangle_count := 0
    triangulation := Polygon_Triangulation{
        cache, ring, vertices, count, want_ccw, triangle_start,
        &triangle_count, base_vertex,
    }
    remaining := triangulate_polygon_ear_loop(triangulation)

    if remaining == 3 {
        emit_polygon_last_ring_triangle(triangulation, 0)
        return triangle_count
    }

    emit_polygon_fallback_fan(triangulation)

    return triangle_count
}

//   Reserve all packet ranges required by one polygon.
reserve_polygon_cache_ranges_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache,
    vertex_count: int) -> Polygon_Cache_Range_Reservation {

    first_vertex, has_vertex_space := draw_cache_reserve_polygon_vertices_storage(
        cache, vertex_count)
    if !has_vertex_space {
        return Polygon_Cache_Range_Reservation{0, 0, 0, false}
    }

    max_triangle_count := vertex_count - 2
    first_triangle, has_triangle_space := draw_cache_reserve_polygon_triangles_storage(
        cache, max_triangle_count)
    if !has_triangle_space {
        cache.polygon_vertex_count -= vertex_count
        return Polygon_Cache_Range_Reservation{0, 0, 0, false}
    }

    return Polygon_Cache_Range_Reservation{
        first_vertex,
        first_triangle,
        max_triangle_count,
        true,
    }
}

//   Roll back one failed polygon reservation in a derived packet.
rollback_polygon_cache_ranges_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache,
    vertex_count: int,
    reserved_triangle_count: int) {

    cache.polygon_vertex_count -= vertex_count
    cache.polygon_triangle_count -= reserved_triangle_count
}

//   Shrink one packet triangle reservation to its emitted count.
finalize_polygon_triangle_reservation_storage :: #force_inline proc(
    cache: ^core.Shapes_Draw_Cache,
    first_triangle: int,
    triangle_count: int) {

    cache.polygon_triangle_count = first_triangle + triangle_count
}
