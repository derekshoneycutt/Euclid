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
Kine_Triangle_Draw :: core.Kine_Triangle_Draw
Kine_Square_Draw :: core.Kine_Square_Draw
Kine_Pentagon_Draw :: core.Kine_Pentagon_Draw
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

//   Push a cached triangle draw item into the draw-cache item list.
cache_push_triangle :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [3]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Kine_Triangle_Draw{
        make_draw_base(source_index, src),
        child_points[0],
        child_points[1],
        child_points[2],
    }
    slot^ = point
}

//   Push a cached square draw item into the draw-cache item list.
cache_push_square :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [4]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Kine_Square_Draw{
        make_draw_base(source_index, src),
        child_points[0],
        child_points[1],
        child_points[2],
        child_points[3],
    }
    slot^ = point
}

//   Push a cached pentagon draw item into the draw-cache item list.
cache_push_pentagon :: proc(
    point_system: ^Kine_Point_System,
    source_index: int,
    src: ^Kine_Shape_Point,
    alpha: f32) {

    child_points: [5]Vector3
    if !lerped_child_positions(point_system, src, alpha, child_points[:]) {
        return
    }

    slot, has_slot := draw_cache_next_item_slot(point_system)
    if !has_slot {
        return
    }

    point := Kine_Pentagon_Draw{
        make_draw_base(source_index, src),
        child_points[0],
        child_points[1],
        child_points[2],
        child_points[3],
        child_points[4],
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
