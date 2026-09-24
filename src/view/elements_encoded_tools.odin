package view

import native "native"

import color "../core/color"
import geometry "../core/geometry"
import shapemodel "../shapes/model"
import view_core "core"

import "core:math"

// encoded_stroke_pack_occluders copies bounded physical-pixel caster records.
encoded_stroke_pack_occluders :: proc(
    uniforms: ^native.Stroke_Fragment_Uniforms,
    encoder: ^native.Draw_Encoder,
    ctx: ^Tool_Brush_Occluder_Context) {
    if ctx == nil {return}
    scale_x := f32(encoder^.physical_extent.x) / encoder^.logical_extent.x
    scale_y := f32(encoder^.physical_extent.y) / encoder^.logical_extent.y
    average_scale := (scale_x + scale_y) * 0.5
    count := min(ctx^.count, len(uniforms^.occluder_p0_p1))
    uniforms^.occluder_count = u32(count)
    for index in 0..<count {
        caster := ctx^.occluders[index]
        uniforms^.occluder_p0_p1[index] = {caster.p0.x * scale_x,
            caster.p0.y * scale_y, caster.p1.x * scale_x,
            caster.p1.y * scale_y}
        uniforms^.occluder_radius_depths[index] = {
            caster.thickness * 0.5 * average_scale,
            caster.depth0, caster.depth1, 0}
        uniforms^.occluder_tangent[index] = {
            caster.tangent.x, caster.tangent.y, caster.tangent.z, 0}
    }
}

// encoded_stroke_strip_vertex packs tangent, side, depth, and parameter data.
encoded_stroke_strip_vertex :: #force_inline proc(
    position, auxiliary: Vector2,
    tangent: Vector3, side: f32) -> native.Stroke_Vertex {
    return {
        position = {position.x, position.y, 0},
        auxiliary = {auxiliary.x, auxiliary.y},
        color = {tangent.x * 0.5 + 0.5, tangent.y * 0.5 + 0.5,
            tangent.z * 0.5 + 0.5, side},
    }
}

// encoded_strip_color sets the normalized strip material color and alpha.
encoded_strip_color :: #force_inline proc(
    uniforms: ^native.Stroke_Fragment_Uniforms,
    draw_color: color.Color_RGBA8) {
    inverse_byte := f32(1.0 / 255.0)
    uniforms^.strip_color = {f32(draw_color.r) * inverse_byte,
        f32(draw_color.g) * inverse_byte, f32(draw_color.b) * inverse_byte}
    uniforms^.strip_alpha = f32(draw_color.a) * inverse_byte
}

// encoded_ring_fallback draws one projected ring with ordinary native lines.
encoded_ring_fallback :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    center: Vector3, radius, thickness: f32, draw_color: color.Color_RGBA8) {
    previous := trochoid_tool_ring_point(center, radius, 0)
    for index in 1..=TROCHOID_TOOL_RING_SEGMENTS {
        angle := 2 * math.PI * f32(index) / f32(TROCHOID_TOOL_RING_SEGMENTS)
        current := trochoid_tool_ring_point(center, radius, angle)
        first := view_core.iso_to_cartesian(previous, state^.iso_scale^)
        second := view_core.iso_to_cartesian(current, state^.iso_scale^)
        _ = native.draw_encoder_line(encoder, geometry.Vector2(first),
            geometry.Vector2(second), thickness, draw_color)
        previous = current
    }
}

// encoded_ring_vertices expands fixed projected samples into triangle vertices.
encoded_ring_vertices :: proc(
    samples: ^Trochoid_Tool_Ring_Samples,
    vertices: []native.Stroke_Vertex) {
    for index in 0..<TROCHOID_TOOL_RING_SEGMENTS {
        base := index * 6
        vertices[base + 0] = encoded_stroke_strip_vertex(samples^.left[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 0)
        vertices[base + 1] = encoded_stroke_strip_vertex(samples^.right[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 1)
        vertices[base + 2] = encoded_stroke_strip_vertex(samples^.left[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 0)
        vertices[base + 3] = vertices[base + 1]
        vertices[base + 4] = encoded_stroke_strip_vertex(samples^.right[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 1)
        vertices[base + 5] = vertices[base + 2]
    }
}

// draw_encoded_tool_ring emits one shader-lit closed strip or line fallback.
draw_encoded_tool_ring :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    center: Vector3, radius, thickness: f32, draw_color: color.Color_RGBA8) {
    scale_x := f32(encoder^.physical_extent.x) / encoder^.logical_extent.x
    scale_y := f32(encoder^.physical_extent.y) / encoder^.logical_extent.y
    coverage_radius := thickness * 0.5 + 1 / min(scale_x, scale_y)
    samples: Trochoid_Tool_Ring_Samples
    if !encoder^.strokes_enabled || !build_trochoid_tool_ring_samples(
        state, center, radius, coverage_radius, &samples) {
        encoded_ring_fallback(
            state, encoder, center, radius, thickness, draw_color)
        return
    }
    vertices: [TROCHOID_TOOL_RING_SEGMENTS * 6]native.Stroke_Vertex
    encoded_ring_vertices(&samples, vertices[:])
    uniforms := encoded_stroke_fragment_uniforms(
        state, encoder, {}, {}, thickness)
    uniforms.stroke_mode = 1
    uniforms.strip_side_extent = coverage_radius / max(thickness * 0.5, 0.0001)
    encoded_strip_color(&uniforms, draw_color)
    if !native.draw_encoder_append_stroke(encoder, vertices[:],
        encoded_stroke_vertex_uniforms(encoder), uniforms) {
        encoded_ring_fallback(
            state, encoder, center, radius, thickness, draw_color)
    }
}

// draw_encoded_trochoid_tool emits both rings and the orientation handle.
draw_encoded_trochoid_tool :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    tool: ^shapemodel.Shapes_Trochoid_Tool_Draw) {
    draw_encoded_tool_ring(state, encoder, tool^.fixed_center,
        tool^.fixed_radius, tool^.brush_size, tool^.color)
    draw_encoded_tool_ring(state, encoder, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, tool^.color)
    first := view_core.iso_to_cartesian(tool^.handle_start, state^.iso_scale^)
    second := view_core.iso_to_cartesian(tool^.handle_finish, state^.iso_scale^)
    draw_encoded_tool_segment(
        state, encoder, first, second, tool^.brush_size, tool^.color)
}

// draw_encoded_cycloid_tool emits its rail, rolling ring, and orientation handle.
draw_encoded_cycloid_tool :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    tool: ^shapemodel.Shapes_Cycloid_Tool_Draw) {
    baseline_start := view_core.iso_to_cartesian(
        tool^.baseline_start, state^.iso_scale^)
    baseline_finish := view_core.iso_to_cartesian(
        tool^.baseline_finish, state^.iso_scale^)
    draw_encoded_tool_segment(state, encoder, baseline_start,
        baseline_finish, tool^.brush_size, tool^.color)
    draw_encoded_tool_ring(state, encoder, tool^.rolling_center,
        tool^.rolling_radius, tool^.brush_size, tool^.color)
    handle_start := view_core.iso_to_cartesian(
        tool^.handle_start, state^.iso_scale^)
    handle_finish := view_core.iso_to_cartesian(
        tool^.handle_finish, state^.iso_scale^)
    draw_encoded_tool_segment(state, encoder, handle_start,
        handle_finish, tool^.brush_size, tool^.color)
}

// encoded_compass_arc_fallback draws one sampled outside arc as native lines.
encoded_compass_arc_fallback :: proc(
    encoder: ^native.Draw_Encoder, center: Vector3,
    basis: Compass_Top_Circle_Basis, draw: Compass_Arc_Draw,
    draw_color: color.Color_RGBA8) {
    previous3d := center + basis.u * basis.radius
    previous := view_core.iso_to_cartesian(previous3d, draw.state^.iso_scale^)
    step := basis.theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)
    for index in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        angle := step * f32(index)
        direction := basis.u * math.cos(angle) + basis.v * math.sin(angle)
        current := view_core.iso_to_cartesian(
            center + direction * basis.radius, draw.state^.iso_scale^)
        _ = native.draw_encoder_line(encoder, geometry.Vector2(previous),
            geometry.Vector2(current), draw.brush_size, draw_color)
        previous = current
    }
}

// encoded_compass_arc_vertices expands fixed arc samples into strip triangles.
encoded_compass_arc_vertices :: proc(
    samples: ^Compass_Arc_Samples, vertices: []native.Stroke_Vertex) {
    for index in 0..<COMPASS_TOPCIRCLE_SEGMENTS {
        base := index * 6
        vertices[base + 0] = encoded_stroke_strip_vertex(samples^.left[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 0)
        vertices[base + 1] = encoded_stroke_strip_vertex(samples^.right[index],
            samples^.auxiliary[index], samples^.tangents_view[index], 1)
        vertices[base + 2] = encoded_stroke_strip_vertex(samples^.left[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 0)
        vertices[base + 3] = vertices[base + 1]
        vertices[base + 4] = encoded_stroke_strip_vertex(samples^.right[index + 1],
            samples^.auxiliary[index + 1], samples^.tangents_view[index + 1], 1)
        vertices[base + 5] = vertices[base + 2]
    }
}

// draw_encoded_compass_arc emits the welded outside arc and leg intersections.
draw_encoded_compass_arc :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw,
    occluders: ^Tool_Brush_Occluder_Context) {
    basis, ok := compass_top_circle_basis(
        compass^.joint1, compass^.pivot, compass^.joint2)
    if !ok {return}
    draw := Compass_Arc_Draw{state, compass^.brush_size,
        native.to_raylib_color(compass^.color)}
    scale_x := f32(encoder^.physical_extent.x) / encoder^.logical_extent.x
    scale_y := f32(encoder^.physical_extent.y) / encoder^.logical_extent.y
    radius := compass^.brush_size * 0.5
    coverage_radius := radius + 1 / min(scale_x, scale_y)
    samples: Compass_Arc_Samples
    if !encoder^.strokes_enabled || !build_compass_arc_samples(
        compass^.pivot, basis, draw, coverage_radius, &samples) {
        encoded_compass_arc_fallback(
            encoder, compass^.pivot, basis, draw, compass^.color)
        return
    }
    encoded_compass_arc_submit(
        state, encoder, compass, basis, &samples, coverage_radius, occluders)
}

// encoded_compass_arc_submit records one complete arc or its atomic fallback.
encoded_compass_arc_submit :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw, basis: Compass_Top_Circle_Basis,
    samples: ^Compass_Arc_Samples, coverage_radius: f32,
    occluders: ^Tool_Brush_Occluder_Context) {
    vertices: [COMPASS_TOPCIRCLE_SEGMENTS * 6]native.Stroke_Vertex
    encoded_compass_arc_vertices(samples, vertices[:])
    uniforms := encoded_stroke_fragment_uniforms(
        state, encoder, {}, {}, compass^.brush_size)
    uniforms.stroke_mode = 1
    uniforms.strip_side_extent = coverage_radius /
        max(compass^.brush_size * 0.5, 0.0001)
    uniforms.arc_intersections_enabled = 1
    uniforms.intersection_depth_width = compass^.brush_size /
        max(state^.iso_scale^.half_scale, 0.0001)
    uniforms.attachment_extent = compass_arc_attachment_extent(
        compass^.brush_size, basis.radius, basis.theta_out,
        state^.iso_scale^.half_scale)
    encoded_strip_color(&uniforms, compass^.color)
    encoded_stroke_pack_occluders(&uniforms, encoder, occluders)
    if !native.draw_encoder_append_stroke(encoder, vertices[:],
        encoded_stroke_vertex_uniforms(encoder), uniforms) {
        draw := Compass_Arc_Draw{state, compass^.brush_size,
            native.to_raylib_color(compass^.color)}
        encoded_compass_arc_fallback(
            encoder, compass^.pivot, basis, draw, compass^.color)
    }
}

// encoded_compass_active_dot emits the selected endpoint indicator.
encoded_compass_active_dot :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw) {
    if compass^.active_child != 1 && compass^.active_child != 3 {return}
    active := compass^.color
    if compass^.has_active_color {active = compass^.active_color}
    point := compass^.joint1
    if compass^.active_child == 3 {point = compass^.joint2}
    center := view_core.iso_to_cartesian(point, state^.iso_scale^)
    _ = native.draw_encoder_circle(
        encoder, geometry.Vector2(center), compass^.brush_size, active)
}

// encoded_compass_leg emits one ordered leg with relevant bounded casters.
encoded_compass_leg :: proc(
    encoder: ^native.Draw_Encoder, ctx: ^Compass_Leg_Draw_Context,
    joint1_leg, sibling_occludes: bool) {
    start, finish := ctx^.c1, ctx^.c2
    receiver, sibling := ctx^.leg2, ctx^.leg1
    if joint1_leg {
        start, finish = ctx^.c0, ctx^.c1
        receiver, sibling = ctx^.leg1, ctx^.leg2
    }
    occluders: Tool_Brush_Occluder_Context
    if sibling_occludes {
        append_tool_brush_occluder(&occluders, receiver, sibling)
    }
    if ctx^.has_pen_occluder {
        append_tool_brush_occluder(
            &occluders, receiver, ctx^.pen_occluder)
    }
    draw_encoded_tool_segment(ctx^.state, encoder, start, finish,
        ctx^.comp^.brush_size, ctx^.comp^.color, &occluders)
}

// encoded_compass_context builds projected legs and the optional pen caster.
encoded_compass_context :: proc(
    state: ^Euclid_General_State, compass: ^shapemodel.Shapes_Compass_Draw,
    pen_caster: ^shapemodel.Shapes_Pen_Draw) -> Compass_Leg_Draw_Context {
    result := Compass_Leg_Draw_Context{state = state, comp = compass,
        c0 = view_core.iso_to_cartesian(compass^.joint1, state^.iso_scale^),
        c1 = view_core.iso_to_cartesian(compass^.pivot, state^.iso_scale^),
        c2 = view_core.iso_to_cartesian(compass^.joint2, state^.iso_scale^),
        leg1 = make_tool_brush_occluder(state, compass^.joint1,
            compass^.pivot, compass^.brush_size),
        leg2 = make_tool_brush_occluder(state, compass^.pivot,
            compass^.joint2, compass^.brush_size),
        has_pen_occluder = pen_caster != nil}
    if pen_caster != nil {
        result.pen_occluder = make_tool_brush_occluder(state,
            pen_caster^.joint1, pen_caster^.joint2, pen_caster^.brush_size)
    }
    return result
}

// draw_encoded_compass emits active dot, ordered legs, and welded outside arc.
draw_encoded_compass :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw,
    pen_caster: ^shapemodel.Shapes_Pen_Draw = nil) {
    encoded_compass_active_dot(state, encoder, compass)
    ctx := encoded_compass_context(state, compass, pen_caster)
    joint1_last := compass_draw_joint1_leg_last(
        compass, ctx.c0, ctx.c1, ctx.c2)
    if joint1_last {
        encoded_compass_leg(encoder, &ctx, false, true)
        encoded_compass_leg(encoder, &ctx, true, false)
    } else {
        encoded_compass_leg(encoder, &ctx, true, true)
        encoded_compass_leg(encoder, &ctx, false, false)
    }
    arc_occluders := make_compass_arc_occluders(ctx.leg1, ctx.leg2)
    draw_encoded_compass_arc(state, encoder, compass, &arc_occluders)
}

// draw_encoded_pen_crossing preserves back, polygon, and front painter order.
draw_encoded_pen_crossing :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    crossing: ^Pen_Polygon_Crossing,
    compass_caster: ^shapemodel.Shapes_Compass_Draw) {
    pen := &crossing^.pen
    if crossing^.has_back {
        first := view_core.iso_to_cartesian(crossing^.back0, state^.iso_scale^)
        second := view_core.iso_to_cartesian(crossing^.back1, state^.iso_scale^)
        draw_encoded_pen_fragment(
            state, encoder, pen, first, second, compass_caster)
    }
    draw_encoded_cached_polygon(state, encoder, &crossing^.polygon)
    if crossing^.has_front {
        first := view_core.iso_to_cartesian(crossing^.front0, state^.iso_scale^)
        second := view_core.iso_to_cartesian(crossing^.front1, state^.iso_scale^)
        draw_encoded_pen_fragment(
            state, encoder, pen, first, second, compass_caster)
    }
}

// draw_encoded_pen_fragment emits one crossing fragment with compass casters.
draw_encoded_pen_fragment :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    pen: ^shapemodel.Shapes_Pen_Draw, first, second: Vector2,
    compass: ^shapemodel.Shapes_Compass_Draw) {
    occluders: Tool_Brush_Occluder_Context
    if compass != nil {
        receiver := make_tool_brush_occluder(
            state, pen^.joint1, pen^.joint2, pen^.brush_size)
        leg1 := make_tool_brush_occluder(
            state, compass^.joint1, compass^.pivot, compass^.brush_size)
        leg2 := make_tool_brush_occluder(
            state, compass^.pivot, compass^.joint2, compass^.brush_size)
        append_tool_brush_occluder(&occluders, receiver, leg1)
        append_tool_brush_occluder(&occluders, receiver, leg2)
    }
    draw_encoded_tool_segment(state, encoder, first, second,
        pen^.brush_size, pen^.color, &occluders)
}

// draw_encoded_high_regular emits one non-tool item in the elevated layer.
draw_encoded_high_regular :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Draw_Cache_Item) {
    switch &typed in item {
    case shapemodel.Shapes_Point_Draw:
        if draw_cached_point_is_elevated(&typed) {
            draw_encoded_cached_point(state, encoder, &typed)
        }
    case shapemodel.Shapes_Line_Draw:
        draw_encoded_cached_line(state, encoder, &typed, true)
    case shapemodel.Shapes_Circle_Draw:
        if draw_cached_circle_is_elevated(&typed) {
            draw_encoded_cached_circle(state, encoder, &typed)
        }
    case shapemodel.Shapes_Filled_Circle_Draw:
        if draw_cached_filledcircle_is_elevated(&typed) {
            draw_encoded_cached_filled_circle(state, encoder, &typed)
        }
    case shapemodel.Shapes_Curve_Draw:
        if draw_cached_curve_is_elevated(state, &typed) {
            draw_encoded_cached_curve(state, encoder, &typed, true)
        }
    case shapemodel.Shapes_Polygon_Draw:
        if draw_cached_polygon_is_elevated(state, &typed) {
            draw_encoded_cached_polygon(state, encoder, &typed)
        }
    case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Trochoid_Tool_Draw,
        shapemodel.Shapes_Cycloid_Tool_Draw, shapemodel.Shapes_Pen_Draw,
        shapemodel.Shapes_Compass_Draw:
    }
}

// draw_encoded_high_instrument emits one tool with resolved interaction casters.
draw_encoded_high_instrument :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    item: ^shapemodel.Shapes_Draw_Cache_Item,
    pen_receives_compass, compass_receives_pen: bool) -> bool {
    cache := &state^.shape_world^.draw_cache
    switch &typed in item {
    case shapemodel.Shapes_Trochoid_Tool_Draw:
        draw_encoded_trochoid_tool(state, encoder, &typed)
    case shapemodel.Shapes_Cycloid_Tool_Draw:
        draw_encoded_cycloid_tool(state, encoder, &typed)
    case shapemodel.Shapes_Pen_Draw:
        caster: ^shapemodel.Shapes_Compass_Draw
        if pen_receives_compass {caster = &cache^.compass}
        draw_encoded_cached_pen(state, encoder, &typed, caster)
    case shapemodel.Shapes_Compass_Draw:
        caster: ^shapemodel.Shapes_Pen_Draw
        if compass_receives_pen {caster = &cache^.pen}
        draw_encoded_compass(state, encoder, &typed, caster)
    case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Point_Draw,
        shapemodel.Shapes_Line_Draw, shapemodel.Shapes_Circle_Draw,
        shapemodel.Shapes_Filled_Circle_Draw, shapemodel.Shapes_Curve_Draw,
        shapemodel.Shapes_Polygon_Draw:
        return false
    }
    return true
}

// draw_encoded_high_merged_item resolves guide deferral and polygon crossing.
draw_encoded_high_merged_item :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    cache: ^shapemodel.Shapes_Draw_Cache, index: int,
    ctx: ^High_Merged_Draw_Context) {
    if ctx^.defer_guide && index == ctx^.guide_index {return}
    if ctx^.defer_guide && index == ctx^.compass_index {
        draw_encoded_trochoid_tool(state, encoder, &cache^.trochoid_tool)
    }
    if ctx^.has_crossing && index == ctx^.crossing.polygon_index {
        caster: ^shapemodel.Shapes_Compass_Draw
        if ctx^.pen_receives_compass {caster = &cache^.compass}
        draw_encoded_pen_crossing(
            state, encoder, &ctx^.crossing, caster)
        return
    }
    if ctx^.has_crossing && index == ctx^.crossing.pen_index {return}
    if !draw_encoded_high_instrument(state, encoder, &cache^.items[index],
        ctx^.pen_receives_compass, ctx^.compass_receives_pen) {
        draw_encoded_high_regular(state, encoder, &cache^.items[index])
    }
}

// draw_encoded_shapes_high_merged_cached preserves legacy elevated painter order.
draw_encoded_shapes_high_merged_cached :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder) {
    ctx := High_Merged_Draw_Context{}
    ctx.crossing.pen_index = -1
    ctx.crossing.polygon_index = -1
    ctx.has_crossing = find_pen_polygon_crossing(state, &ctx.crossing)
    cache := &state^.shape_world^.draw_cache
    _, pen_index := find_cached_pen_item(cache)
    _, compass_index := find_cached_compass_item(cache)
    _, guide_index := find_cached_trochoid_tool_item(cache)
    pen_draw_index := pen_index
    if ctx.has_crossing {pen_draw_index = ctx.crossing.polygon_index}
    ctx.pen_receives_compass, ctx.compass_receives_pen =
        tool_brush_interaction_receivers(pen_draw_index, compass_index)
    ctx.defer_guide = trochoid_tool_defers_to_compass(
        guide_index, compass_index)
    ctx.guide_index = guide_index
    ctx.compass_index = compass_index
    for index in 0..<cache^.item_count {
        draw_encoded_high_merged_item(
            state, encoder, cache, index, &ctx)
    }
}

// encoded_shadow_color returns legacy height-attenuated black.
encoded_shadow_color :: #force_inline proc(avg_height: f32) -> color.Color_RGBA8 {
    return {0, 0, 0, shadow_alpha_from_height(avg_height)}
}

// draw_encoded_tool_shadow_line emits one projected floor-shadow segment.
draw_encoded_tool_shadow_line :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    first, second: Vector3, thickness: f32, avg_height: f32) {
    screen_first := shadow_to_screen(first, state)
    screen_second := shadow_to_screen(second, state)
    _ = native.draw_encoder_line(encoder, geometry.Vector2(screen_first),
        geometry.Vector2(screen_second), thickness,
        encoded_shadow_color(avg_height))
}

// draw_encoded_ring_shadow emits one segmented projected guide shadow.
draw_encoded_ring_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    center: Vector3, radius, thickness: f32) {
    previous := trochoid_tool_ring_point(center, radius, 0)
    for index in 1..=TROCHOID_TOOL_RING_SEGMENTS {
        angle := 2 * math.PI * f32(index) / f32(TROCHOID_TOOL_RING_SEGMENTS)
        current := trochoid_tool_ring_point(center, radius, angle)
        draw_encoded_tool_shadow_line(
            state, encoder, previous, current, thickness, center.z)
        previous = current
    }
}

// draw_encoded_pen_shadow emits the pen's ordinary floor shadow.
draw_encoded_pen_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    pen: ^shapemodel.Shapes_Pen_Draw) {
    height := (pen^.joint1.z + pen^.joint2.z) * 0.5
    thickness := max(pen^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    draw_encoded_tool_shadow_line(
        state, encoder, pen^.joint1, pen^.joint2, thickness, height)
}

// draw_encoded_compass_shadow_arc emits the sampled outside-arc shadow.
draw_encoded_compass_shadow_arc :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw, thickness, height: f32) {
    basis, ok := compass_top_circle_basis(
        compass^.joint1, compass^.pivot, compass^.joint2)
    if !ok {return}
    previous := compass^.pivot + basis.u * basis.radius
    step := basis.theta_out / f32(COMPASS_TOPCIRCLE_SEGMENTS)
    for index in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        angle := step * f32(index)
        direction := basis.u * math.cos(angle) + basis.v * math.sin(angle)
        current := compass^.pivot + direction * basis.radius
        draw_encoded_tool_shadow_line(
            state, encoder, previous, current, thickness, height)
        previous = current
    }
}

// draw_encoded_compass_shadow preserves hinge ordering and outside-arc shadow.
draw_encoded_compass_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    compass: ^shapemodel.Shapes_Compass_Draw) {
    first := shadow_to_screen(compass^.joint1, state)
    pivot := shadow_to_screen(compass^.pivot, state)
    second := shadow_to_screen(compass^.joint2, state)
    height := (compass^.joint1.z + compass^.pivot.z + compass^.joint2.z) / 3
    thickness := max(compass^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    if compass_draw_joint1_leg_last(compass, first, pivot, second) {
        draw_encoded_tool_shadow_line(state, encoder,
            compass^.pivot, compass^.joint2, thickness, height)
        draw_encoded_tool_shadow_line(state, encoder,
            compass^.joint1, compass^.pivot, thickness, height)
    } else {
        draw_encoded_tool_shadow_line(state, encoder,
            compass^.joint1, compass^.pivot, thickness, height)
        draw_encoded_tool_shadow_line(state, encoder,
            compass^.pivot, compass^.joint2, thickness, height)
    }
    draw_encoded_compass_shadow_arc(
        state, encoder, compass, thickness, height)
}

// draw_encoded_trochoid_shadow emits both rings and handle shadows.
draw_encoded_trochoid_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    tool: ^shapemodel.Shapes_Trochoid_Tool_Draw) {
    thickness := max(tool^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    draw_encoded_ring_shadow(
        state, encoder, tool^.fixed_center, tool^.fixed_radius, thickness)
    draw_encoded_ring_shadow(
        state, encoder, tool^.rolling_center, tool^.rolling_radius, thickness)
    height := (tool^.handle_start.z + tool^.handle_finish.z) * 0.5
    draw_encoded_tool_shadow_line(state, encoder,
        tool^.handle_start, tool^.handle_finish, thickness, height)
}

// draw_encoded_cycloid_shadow emits rail, ring, and handle shadows.
draw_encoded_cycloid_shadow :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder,
    tool: ^shapemodel.Shapes_Cycloid_Tool_Draw) {
    thickness := max(tool^.brush_size * 0.8, SHADOW_MIN_THICKNESS)
    rail_height := (tool^.baseline_start.z + tool^.baseline_finish.z) * 0.5
    draw_encoded_tool_shadow_line(state, encoder, tool^.baseline_start,
        tool^.baseline_finish, thickness, rail_height)
    draw_encoded_ring_shadow(
        state, encoder, tool^.rolling_center, tool^.rolling_radius, thickness)
    handle_height := (tool^.handle_start.z + tool^.handle_finish.z) * 0.5
    draw_encoded_tool_shadow_line(state, encoder, tool^.handle_start,
        tool^.handle_finish, thickness, handle_height)
}

// draw_encoded_cached_tool_shadow_pass restores tool shadows in cache order.
draw_encoded_cached_tool_shadow_pass :: proc(
    state: ^Euclid_General_State, encoder: ^native.Draw_Encoder) {
    cache := &state^.shape_world^.draw_cache
    for index in 0..<cache^.item_count {
        switch &typed in &cache^.items[index] {
        case shapemodel.Shapes_Trochoid_Tool_Draw:
            draw_encoded_trochoid_shadow(state, encoder, &typed)
        case shapemodel.Shapes_Cycloid_Tool_Draw:
            draw_encoded_cycloid_shadow(state, encoder, &typed)
        case shapemodel.Shapes_Pen_Draw:
            draw_encoded_pen_shadow(state, encoder, &typed)
        case shapemodel.Shapes_Compass_Draw:
            draw_encoded_compass_shadow(state, encoder, &typed)
        case shapemodel.Shapes_Label_Draw, shapemodel.Shapes_Point_Draw,
            shapemodel.Shapes_Line_Draw, shapemodel.Shapes_Circle_Draw,
            shapemodel.Shapes_Filled_Circle_Draw, shapemodel.Shapes_Curve_Draw,
            shapemodel.Shapes_Polygon_Draw:
        }
    }
}