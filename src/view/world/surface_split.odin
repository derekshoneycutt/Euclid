package world

import "../../core"
import geometry "../../core/geometry"
import color "../../core/color"
import "../native"
import projection "projection"
import shapemodel "../../shapes/model"

// Describe one sampled outline's topology, depth pass, and ink or shadow treatment.
Surface_Curve_Draw_Params :: struct {
    topology: shapemodel.Curve_Topology,
    keep_above: bool,
    width: f32,
    color: color.Color_RGBA8,
    shadow: bool,
}

// Split a triangle into a bounded convex polygon in one z=0 halfspace.
surface_split_triangle :: proc(
    first, second, third: geometry.Vector3, keep_above: bool,
    output: ^[4]geometry.Vector3) -> int {
    input := [?]geometry.Vector3{first, second, third}
    count := 0
    previous := input[2]
    previous_inside := z_split_point_in_halfspace(previous, keep_above)
    for current in input {
        inside := z_split_point_in_halfspace(current, keep_above)
        if inside != previous_inside {
            output[count] = z_split_intersection_with_plane(previous, current)
            count += 1
        }
        if inside {
            output[count] = current
            count += 1
        }
        previous = current
        previous_inside = inside
    }
    return count
}

// Draw a filled triangle's selected half with the established lower-fragment attenuation.
draw_encoded_split_triangle :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    triangle: [3]geometry.Vector3,
    keep_above: bool, draw_color: color.Color_RGBA8) {
    clipped: [4]geometry.Vector3
    count := surface_split_triangle(
        triangle[0], triangle[1], triangle[2], keep_above, &clipped)
    if count < 3 {
        return
    }
    tint := draw_color
    if !keep_above && (z_split_sign(triangle[0].z) < 0 ||
        z_split_sign(triangle[1].z) < 0 || z_split_sign(triangle[2].z) < 0) {
        tint = z_split_lower_fragment_color(tint)
    }
    anchor := projection.iso_to_cartesian(clipped[0], state.iso_scale)
    for index in 1..<count - 1 {
        second_screen := projection.iso_to_cartesian(clipped[index], state.iso_scale)
        third_screen := projection.iso_to_cartesian(clipped[index + 1], state.iso_scale)
        _ = native.draw_encoder_triangle(
            encoder, anchor, second_screen, third_screen, tint)
    }
}

// Submit one sampled analytic outline through surface splitting before simplification.
draw_sampled_surface_curve :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    vertices: []geometry.Vector3, params: Surface_Curve_Draw_Params) {
    kinds: [CIRCLE_ARC_SEGMENTS + 1]shapemodel.Curve_Point_Kind
    projected: [MAX_CURVE_VISIBLE_POINTS]geometry.Vector2
    projected_kinds: [MAX_CURVE_VISIBLE_POINTS]shapemodel.Curve_Point_Kind
    runs: [MAX_CURVE_VISIBLE_RUNS]Curve_Visible_Run
    buffers: Curve_Visible_Run_Buffers = {projected[:], projected_kinds[:], runs[:]}
    result := build_projected_curve_visible_runs({state.iso_scale,
        vertices, kinds[:len(vertices)], params.topology,
        params.keep_above, params.shadow}, buffers)
    assert(result.ok)
    reduction := reduce_projected_curve_visible_runs(buffers, result, params.width,
        curve_reduction_budget(state.iso_scale.half_scale))
    assert(reduction.ok)
    result.point_count = reduction.retained_count
    native.draw_encoder_record_curve_reduction(
        encoder, reduction.candidate_count, reduction.retained_count)
    tint := params.color
    if !params.keep_above {
        for point in vertices {
            if z_split_sign(point.z) < 0 {
                tint = z_split_lower_fragment_color(tint)
                break
            }
        }
    }
    if !params.shadow {
        tint = resolve_animation_authored_ink(state, tint)
    }
    draw_encoded_curve_visible_runs(encoder, buffers, result, params.width, tint)
}

// Project only an elevated filled triangle's surface-split shadow fragments.
draw_encoded_split_triangle_shadow :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    first, second, third: geometry.Vector3) {
    clipped: [4]geometry.Vector3
    count := surface_split_triangle(first, second, third, true, &clipped)
    if count < 3 {
        return
    }
    tint := encoded_shadow_color(average_shadow_height(clipped[:count]))
    anchor := shadow_to_screen(clipped[0], state)
    for index in 1..<count - 1 {
        _ = native.draw_encoder_triangle(encoder, anchor,
            shadow_to_screen(clipped[index], state),
            shadow_to_screen(clipped[index + 1], state), tint)
    }
}
