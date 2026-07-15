package kine

// The major system calls for the shape system are for creating the immediate draw cache.
// This just builds the cache into the existing point system.

// TODO: Currently not caching items that are not drawn, resulting in using a separate
// previous_vectors cache that kinda doubles up. The previous_vectors preceded the draw_cache,
// but consider more if we should just move it to the draw_cache entirely?

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
Kine_Triangle_Draw :: core.Kine_Triangle_Draw
Kine_Square_Draw :: core.Kine_Square_Draw
Kine_Pentagon_Draw :: core.Kine_Pentagon_Draw
Kine_Pen_Draw :: core.Kine_Pen_Draw
Kine_Compass_Draw :: core.Kine_Compass_Draw

//   Snapshot current point positions into previous_vectors for interpolation.
//
// Parameters:
//   - point_system: Point system whose current positions are cached.
//
// Returns:
//   - none.
kine_update_last_cache_vectors :: proc(
    point_system: ^Kine_Point_System) {

    for i in 0..<MAX_KINEPOINTS {
        point_system^.previous_vectors[i] = point_system^.points[i].position
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

    for index in 0..<len(point_system^.points) {
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
            cache_push_triangle(point_system, index, src, alpha)
        case .Square:
            cache_push_square(point_system, index, src, alpha)
        case .Pentagon:
            cache_push_pentagon(point_system, index, src, alpha)
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
    alpha: f32,
    out: ^Vector3) -> bool {

    if index < 0 || index >= MAX_KINEPOINTS {
        return false
    }

    curr := point_system^.points[index]
    curr_pos, has_curr := curr.position.?
    if !has_curr {
        return false
    }

    prev := point_system^.previous_vectors[index].? or_else curr_pos
    out^ = linalg.lerp(prev, curr_pos, alpha)
    return true
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


//   Push a cached label draw item into the draw-cache item list.
cache_push_label :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    p0: Vector3
    if !lerped_point_position(point_system, source_index, alpha, &p0) {
        return
    }

    label, ok := src^.label.?
    if !ok {
        return
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point := Kine_Label_Draw{ make_draw_base(source_index, src), p0, label, src^.decoration_kind }
    slot^ = point
    point_system^.draw_cache.item_count += 1
}

//   Push a cached point draw item into the draw-cache item list.
cache_push_point :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    p0: Vector3
    if !lerped_point_position(point_system, source_index, alpha, &p0) {
        return
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point := Kine_Point_Draw{ make_draw_base(source_index, src), p0 }
    slot^ = point
    point_system^.draw_cache.item_count += 1
}

//   Push a cached line draw item into the draw-cache item list.
cache_push_line :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    child0 := src^.child_point_head
    point1: Vector3
    if !lerped_point_position(point_system, child0, alpha, &point1) {
        return
    }

    next := point_system.points[child0].next_child_point
    point2: Vector3
    if !lerped_point_position(point_system, next, alpha, &point2) {
        return
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point := Kine_Line_Draw{ make_draw_base(source_index, src), point1, point2 }
    slot^ = point
    point_system^.draw_cache.item_count += 1
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

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    center, has_center := src^.position.?
    if !has_center {
        return
    }

    child0 := src^.child_point_head
    start: Vector3
    if !lerped_point_position(point_system, child0, alpha, &start) {
        return
    }

    next := point_system.points[child0].next_child_point
    end: Vector3
    if !lerped_point_position(point_system, next, alpha, &end) {
        return
    }

    if src^.active_child > 1 {
        start, end = end, start
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point := Kine_Circle_Draw{ make_draw_base(source_index, src), center, start, end, src^.offset }
    slot^ = point
    point_system^.draw_cache.item_count += 1
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

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    center, has_center := src^.position.?
    if !has_center {
        return
    }

    child0 := src^.child_point_head
    start: Vector3
    if !lerped_point_position(point_system, child0, alpha, &start) {
        return
    }

    next := point_system.points[child0].next_child_point
    end: Vector3
    if !lerped_point_position(point_system, next, alpha, &end) {
        return
    }

    if src^.active_child > 1 {
        start, end = end, start
    }

    slot := &point_system^.draw_cache.items[point_system^.draw_cache.item_count]
    point := Kine_Filled_Circle_Draw{ make_draw_base(source_index, src), center, start, end }
    slot^ = point
    point_system^.draw_cache.item_count += 1
}

//   Push a cached triangle draw item into the draw-cache item list.
cache_push_triangle :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    child0 := src^.child_point_head
    point1: Vector3
    if !lerped_point_position(point_system, child0, alpha, &point1) {
        return
    }

    next := point_system.points[child0].next_child_point
    point2: Vector3
    if !lerped_point_position(point_system, next, alpha, &point2) {
        return
    }

    next = point_system.points[next].next_child_point
    point3: Vector3
    if !lerped_point_position(point_system, next, alpha, &point3) {
        return
    }

    point := Kine_Triangle_Draw{ make_draw_base(source_index, src), point1, point2, point3 }
    point_system^.draw_cache.items[point_system^.draw_cache.item_count] = point
    point_system^.draw_cache.item_count += 1
}

//   Push a cached square draw item into the draw-cache item list.
cache_push_square :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    child0 := src^.child_point_head
    point1: Vector3
    if !lerped_point_position(point_system, child0, alpha, &point1) {
        return
    }

    next := point_system.points[child0].next_child_point
    point2: Vector3
    if !lerped_point_position(point_system, next, alpha, &point2) {
        return
    }

    next = point_system.points[next].next_child_point
    point3: Vector3
    if !lerped_point_position(point_system, next, alpha, &point3) {
        return
    }

    next = point_system.points[next].next_child_point
    point4: Vector3
    if !lerped_point_position(point_system, next, alpha, &point4) {
        return
    }

    point := Kine_Square_Draw{ make_draw_base(source_index, src), point1, point2, point3, point4 }
    point_system^.draw_cache.items[point_system^.draw_cache.item_count] = point
    point_system^.draw_cache.item_count += 1
}

//   Push a cached pentagon draw item into the draw-cache item list.
cache_push_pentagon :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    if point_system^.draw_cache.item_count >= len(point_system^.draw_cache.items) {
        return
    }

    child0 := src^.child_point_head
    point1: Vector3
    if !lerped_point_position(point_system, child0, alpha, &point1) {
        return
    }

    next := point_system.points[child0].next_child_point
    point2: Vector3
    if !lerped_point_position(point_system, next, alpha, &point2) {
        return
    }

    next = point_system.points[next].next_child_point
    point3: Vector3
    if !lerped_point_position(point_system, next, alpha, &point3) {
        return
    }

    next = point_system.points[next].next_child_point
    point4: Vector3
    if !lerped_point_position(point_system, next, alpha, &point4) {
        return
    }

    next = point_system.points[next].next_child_point
    point5: Vector3
    if !lerped_point_position(point_system, next, alpha, &point5) {
        return
    }

    point := Kine_Pentagon_Draw{ make_draw_base(source_index, src), point1, point2, point3, point4, point5 }
    point_system^.draw_cache.items[point_system^.draw_cache.item_count] = point
    point_system^.draw_cache.item_count += 1
}

//   Update cached pen tool draw data and pen draw-enable flag.
cache_push_pen :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child0 := src^.child_point_head
    j1: Vector3
    if !lerped_point_position(point_system, child0, alpha, &j1) {
        return
    }

    next := point_system.points[child0].next_child_point
    j2: Vector3
    if !lerped_point_position(point_system, next, alpha, &j2) {
        return
    }

    point_system^.draw_cache.pen.base = make_draw_base(source_index, src)
    point_system^.draw_cache.pen.joint1 = j1
    point_system^.draw_cache.pen.joint2 = j2
    point_system^.draw_cache.draw_pen = src^.do_draw
}

//   Update cached compass tool draw data and compass draw-enable flag.
cache_push_compass :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child0 := src^.child_point_head
    p0: Vector3
    if !lerped_point_position(point_system, child0, alpha, &p0) {
        return
    }

    child1 := point_system.points[child0].next_child_point
    p1: Vector3
    if !lerped_point_position(point_system, child1, alpha, &p1) {
        return
    }

    child2 := point_system.points[child1].next_child_point
    p2: Vector3
    if !lerped_point_position(point_system, child2, alpha, &p2) {
        return
    }

    point_system^.draw_cache.compass.base = make_draw_base(source_index, src)
    point_system^.draw_cache.compass.joint1 = p0
    point_system^.draw_cache.compass.pivot = p1
    point_system^.draw_cache.compass.joint2 = p2
    point_system^.draw_cache.draw_compass = src^.do_draw
}
