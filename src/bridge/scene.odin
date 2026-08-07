package bridge

import "../core"
import "../audio"
import "../particles"

import "core:math"

LABEL_DUST_X_OFFSET :: -0.01
LABEL_DUST_Y_OFFSET :: -0.03

//   Return whether a point index is within runtime point capacity bounds.
is_point_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINEPOINTS
}

//   Return whether a constraint index is within runtime constraint capacity bounds.
is_constraint_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINECONSTRAINTS
}

//   Validate that a constraint kind integer maps to a supported single kind value.
is_valid_constraint_kind_value :: #force_inline proc(kind: i32) -> bool {
    return kind >= KINE_CONSTRAINT_KIND_MIN && kind <= KINE_CONSTRAINT_KIND_MAX
}

//   Convert a boolean value to C-ABI friendly u8 representation.
to_u8 :: #force_inline proc(v: bool) -> u8 {
    if v {
        return 1
    }
    return 0
}

//   Build an invalid/sentinel constraint view result for failed lookups.
constraint_view_invalid :: #force_inline proc() -> Bridge_Constraint_View {
    return Bridge_Constraint_View{
        valid = 0,
        index = -1,
        traits = 0,
        on_point = -1,
        restriction = {0, 0, 0},
        bounce = 0,
        allowance = 0,
        depend_on = -1,
        has_child_offset = 0,
        child_offset = 0,
        do_apply = 0,
    }
}

//   Emit floor-contact dust when a point is close to the drawing plane.
push_dust_if_floor_contact :: proc(state: ^core.Euclid_General_State, pos: core.Vector3) {
    if f32(math.abs(f64(pos.z))) <= FLOOR_CONTACT_Z_EPSILON {
        particles.push_dust_away_from_xy(state^.particle_system, pos.x, pos.y)
    }
}

//   Emit sampled floor-contact dust along the active compass segment.
//
// Notes:
//   - No-op unless both compass joints are valid and near floor height.
push_dust_for_compass_segment_if_floor_contact :: proc(state: ^core.Euclid_General_State) {
    pointIndex1 := state^.compass.joint1_id
    pointIndex2 := state^.compass.joint2_id
    if pointIndex1 < 0 || pointIndex1 >= MAX_KINEPOINTS ||
        pointIndex2 < 0 || pointIndex2 >= MAX_KINEPOINTS {
        return
    }

    point1 := state^.point_system^.points[pointIndex1].position.? or_else {0, 0, 0}
    point2 := state^.point_system^.points[pointIndex2].position.? or_else {0, 0, 0}

    if f32(math.abs(f64(point1.z))) > FLOOR_CONTACT_Z_EPSILON ||
        f32(math.abs(f64(point2.z))) > FLOOR_CONTACT_Z_EPSILON {
        return
    }

    samples := COMPASS_LINE_DUST_SAMPLES
    inv_samples := f32(1.0) / f32(samples)
    for i in 0..<samples {
        t := f32(i) * inv_samples
        x := math.lerp(point1.x, point2.x, t)
        y := math.lerp(point1.y, point2.y, t)
        particles.push_dust_away_from_xy(state^.particle_system, x, y)
    }
}

//   Emit dust for line segments connected to a point when a crossing/touch event occurs.
//
// Notes:
//   - If a connected line lies on z=0, emit sampled pushes along the segment.
//   - If a connected line straddles z=0, emit one push at the segment crossing point.
push_dust_for_connected_lines_on_floor_event :: proc(
    state: ^core.Euclid_General_State,
    point_index: int) {

    next_index := state^.point_system^.next_point_index
    if point_index < 0 || point_index >= next_index {
        return
    }

    for host_index in 0..<next_index {
        host := state^.point_system^.points[host_index]
        if host.kind != .Line {
            continue
        }

        p1 := host.child_point_head
        if p1 < 0 || p1 >= next_index {
            continue
        }

        p2 := state^.point_system^.points[p1].next_child_point
        if p2 < 0 || p2 >= next_index {
            continue
        }

        if p1 != point_index && p2 != point_index {
            continue
        }

        pos1, has_pos1 := state^.point_system^.points[p1].position.?
        pos2, has_pos2 := state^.point_system^.points[p2].position.?
        if !has_pos1 || !has_pos2 {
            continue
        }

        sign1 := floor_contact_sign(pos1.z)
        sign2 := floor_contact_sign(pos2.z)

        if sign1 == 0 && sign2 == 0 {
            samples := COMPASS_LINE_DUST_SAMPLES
            inv_samples := f32(1.0) / f32(samples)
            for i in 0..<samples {
                t := f32(i) * inv_samples
                x := math.lerp(pos1.x, pos2.x, t)
                y := math.lerp(pos1.y, pos2.y, t)
                particles.push_dust_away_from_xy(state^.particle_system, x, y)
            }
            continue
        }

        if sign1 * sign2 >= 0 {
            continue
        }

        dz := pos2.z - pos1.z
        if math.abs(dz) <= FLOOR_CONTACT_Z_EPSILON {
            continue
        }

        t := -pos1.z / dz
        t = math.clamp(t, 0, 1)

        x := math.lerp(pos1.x, pos2.x, t)
        y := math.lerp(pos1.y, pos2.y, t)
        particles.push_dust_away_from_xy(state^.particle_system, x, y)
    }
}

//   Classify one z value relative to floor contact dead-zone.
floor_contact_sign :: #force_inline proc(z: f32) -> int {
    if z > FLOOR_CONTACT_Z_EPSILON {
        return 1
    }
    if z < -FLOOR_CONTACT_Z_EPSILON {
        return -1
    }
    return 0
}

//   Emit one dust push only when a point newly reaches or crosses z=0.
//
// Notes:
//   - Remaining on the floor plane emits no repeated pushes.
//   - Leaving the floor plane emits no push.
push_dust_if_floor_crossing :: proc(
    state: ^core.Euclid_General_State,
    previous_pos, current_pos: core.Vector3,
    has_previous: bool) -> bool {

    if !has_previous {
        return false
    }

    previous_sign := floor_contact_sign(previous_pos.z)
    current_sign := floor_contact_sign(current_pos.z)

    if previous_sign == 0 && current_sign == 0 {
        return false
    }

    if previous_sign != 0 && current_sign == 0 {
        particles.push_dust_away_from_xy(state^.particle_system, current_pos.x, current_pos.y)
        return true
    }

    if previous_sign == 0 && current_sign != 0 {
        return false
    }

    if previous_sign * current_sign >= 0 {
        return false
    }

    dz := current_pos.z - previous_pos.z
    if math.abs(dz) <= FLOOR_CONTACT_Z_EPSILON {
        return false
    }

    t := -previous_pos.z / dz
    t = math.clamp(t, 0, 1)

    x := math.lerp(previous_pos.x, current_pos.x, t)
    y := math.lerp(previous_pos.y, current_pos.y, t)
    particles.push_dust_away_from_xy(state^.particle_system, x, y)
    return true
}

//   Emit a dust push when a label point becomes visible.
//
// Notes:
//   - Applies a single large push for consistent label-show behavior.
emit_label_show_dust_push :: #force_inline proc(
    state: ^core.Euclid_General_State, point: ^core.Kine_Shape_Point) {
    pos, has_pos := point^.position.?
    if !has_pos || point^.kind != .Label || pos.z > 0.05 {
        return
    }

    particles.push_dust_away_from_xy_large(state^.particle_system,
        pos.x + LABEL_DUST_X_OFFSET, pos.y + LABEL_DUST_Y_OFFSET)
}

//   Update one point position and emit floor-crossing dust only.
set_point_position_with_floor_crossing_dust :: #force_inline proc(
    state: ^core.Euclid_General_State,
    index: int,
    pos: core.Vector3) {

    previous_pos, has_previous := state^.point_system^.points[index].position.?
    state^.point_system^.points[index].position = pos
    if push_dust_if_floor_crossing(state, previous_pos, pos, has_previous) {
        if state^.drawing_sound_enabled {
            if index == state^.pen.joint1_id || index == state^.pen.joint2_id ||
                index == state^.compass.joint1_id || index == state^.compass.joint2_id {
                audio.trigger_hit_sound(&state^.chalk_audio)
            }
        }
        push_dust_for_connected_lines_on_floor_event(state, index)
    }
}

//   Update one point position and emit floor-contact plus crossing dust effects.
set_point_position_with_floor_dust_effects :: #force_inline proc(
    state: ^core.Euclid_General_State,
    index: int,
    pos: core.Vector3) {

    set_point_position_with_floor_crossing_dust(state, index, pos)
    push_dust_if_floor_contact(state, pos)

    is_floor_contact :=
        state^.drawing_sound_enabled &&
        pos.z <= FLOOR_CONTACT_Z_EPSILON && pos.z >= -FLOOR_CONTACT_Z_EPSILON
    dt := state^.current_delta_time

    pen_active_child := -1
    if state^.pen.host_id >= 0 && state^.pen.host_id < MAX_KINEPOINTS {
        pen_active_child = state^.point_system^.points[state^.pen.host_id].active_child
    }

    compass_active_child := -1
    if state^.compass.host_id >= 0 && state^.compass.host_id < MAX_KINEPOINTS {
        compass_active_child = state^.point_system^.points[state^.compass.host_id].active_child
    }

    if index == state^.pen.joint1_id {
        audio.register_pen_tip_motion(&state^.chalk_audio, pos,
            is_floor_contact && pen_active_child == 1, dt)
    } else if index == state^.compass.joint1_id {
        audio.register_compass_tip1_motion(&state^.chalk_audio, pos,
            is_floor_contact && compass_active_child == 1, dt)
    } else if index == state^.compass.joint2_id {
        audio.register_compass_tip2_motion(&state^.chalk_audio, pos,
            is_floor_contact && compass_active_child == 3, dt)
    }
}