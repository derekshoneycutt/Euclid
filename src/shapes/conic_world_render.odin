package shapes

import shapemodel "model"
import curve "curve"

import "core:math"

// Snapshot analytic curve parameters at the fixed-step boundary before mutation.
shape_world_update_previous_conic_values :: proc(world: ^shapemodel.Shape_World) {
    for index in 0..<world.parabolas.count {
        value := &world.parabolas.values[index]
        value.previous_focal_distance = value.focal_distance
        value.previous_rotation = value.rotation
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_draw_parameter = value.draw_parameter
    }
    for index in 0..<world.hyperbolas.count {
        value := &world.hyperbolas.values[index]
        value.previous_semimajor = value.semimajor
        value.previous_semiminor = value.semiminor
        value.previous_rotation = value.rotation
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_draw_parameter = value.draw_parameter
    }
}

// Snapshot instrument parameters together so interpolation recomputes coherent joints.
shape_world_update_previous_conic_tool_values :: proc(world: ^shapemodel.Shape_World) {
    for index in 0..<world.parabola_tools.count {
        value := &world.parabola_tools.values[index]
        value.previous_focal_distance = value.focal_distance
        value.previous_link_length = value.link_length
        value.previous_rotation = value.rotation
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_parameter = value.parameter
    }
    for index in 0..<world.hyperbola_tools.count {
        value := &world.hyperbola_tools.values[index]
        value.previous_semimajor = value.semimajor
        value.previous_semiminor = value.semiminor
        value.previous_rotation = value.rotation
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_parameter = value.parameter
        value.previous_rail_half_length = value.rail_half_length
    }
}

// Interpolate every parabola parameter from one fixed-step sample.
world_lerped_parabola :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Parabola, bool) {
    vertex, position_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.parabolas, &world.registry, entity)
    if !position_ok || !value_ok {
        return {}, false
    }
    value: shapemodel.Shape_Parabola = {
        focal_distance = math.lerp(
            current.previous_focal_distance, current.focal_distance, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        parameter_start = math.lerp(
            current.previous_parameter_start, current.parameter_start, alpha),
        parameter_finish = math.lerp(
            current.previous_parameter_finish, current.parameter_finish, alpha),
        draw_parameter = math.lerp(
            current.previous_draw_parameter, current.draw_parameter, alpha),
    }
    return {vertex, value}, shapemodel.shape_parabola_is_valid(value)
}

// Interpolate the common parameters of both hyperbola branches once.
world_lerped_hyperbola :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Hyperbola, bool) {
    center, position_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.hyperbolas, &world.registry, entity)
    if !position_ok || !value_ok {
        return {}, false
    }
    value: shapemodel.Shape_Hyperbola = {
        branches = current.branches,
        semimajor = math.lerp(current.previous_semimajor, current.semimajor, alpha),
        semiminor = math.lerp(current.previous_semiminor, current.semiminor, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        parameter_start = math.lerp(
            current.previous_parameter_start, current.parameter_start, alpha),
        parameter_finish = math.lerp(
            current.previous_parameter_finish, current.parameter_finish, alpha),
        draw_parameter = math.lerp(
            current.previous_draw_parameter, current.draw_parameter, alpha),
    }
    return {center, value}, shapemodel.shape_hyperbola_is_valid(value)
}

// Cache one parabola as an open bounded curve with an exact frontier vertex.
world_cache_push_parabola :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source, alpha: f32) {
    lerped, found := world_lerped_parabola(world, source.entity, alpha)
    if !found {
        return
    }
    first, reserved := draw_cache_reserve_curve_vertices_storage(
        &world.draw_cache, curve.CONIC_MAX_VERTICES)
    if !reserved {
        return
    }
    vertices := world.draw_cache.curve_vertices[first:first + curve.CONIC_MAX_VERTICES]
    result := curve.parabola_explicate(lerped.vertex, lerped.value, vertices)
    world_pose_curve_vertices(
        world, source.entity, alpha, lerped.vertex, vertices[:result.vertex_count])
    draw_cache_finalize_curve_vertices_storage(
        &world.draw_cache, first, curve.CONIC_MAX_VERTICES, result.vertex_count)
    if result.status == .Invalid_Input || result.vertex_count < 2 {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first, result.vertex_count)
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first, result.vertex_count)
        return
    }
    slot^ = Shapes_Curve_Draw{
        base = world_make_draw_base(source, .Curve),
        first_vertex = first,
        vertex_count = result.vertex_count,
        capacity_limited = result.status == .Capacity_Limited,
        topology = .Open,
    }
}

// Append one derived branch packet; the caller owns two-branch rollback.
world_cache_append_hyperbola_branch :: proc(
    world: ^shapemodel.Shape_World, source: World_Draw_Source,
    lerped: World_Lerped_Hyperbola, branch: i32) -> bool {
    first, reserved := draw_cache_reserve_curve_vertices_storage(
        &world.draw_cache, curve.CONIC_MAX_VERTICES)
    if !reserved {
        return false
    }
    vertices := world.draw_cache.curve_vertices[first:first + curve.CONIC_MAX_VERTICES]
    result := curve.hyperbola_explicate(lerped.center, lerped.value, vertices, branch)
    draw_cache_finalize_curve_vertices_storage(
        &world.draw_cache, first, curve.CONIC_MAX_VERTICES, result.vertex_count)
    if result.status == .Invalid_Input || result.vertex_count < 2 {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first, result.vertex_count)
        return result.status != .Invalid_Input
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first, result.vertex_count)
        return false
    }
    slot^ = Shapes_Curve_Draw{
        base = world_make_draw_base(source, .Curve),
        first_vertex = first,
        vertex_count = result.vertex_count,
        capacity_limited = result.status == .Capacity_Limited,
        topology = .Open,
    }
    return true
}

// Publish all selected strokes from one host, or roll back the whole preparation.
world_cache_push_hyperbola :: proc(
    world: ^shapemodel.Shape_World, source: World_Draw_Source, alpha: f32) {
    lerped, found := world_lerped_hyperbola(world, source.entity, alpha)
    if !found {
        return
    }
    first_item := world.draw_cache.item_count
    first_vertex := world.draw_cache.curve_vertex_count
    branches := [?]i32{1, -1}
    for branch in branches {
        if !shapemodel.hyperbola_branch_is_selected(lerped.value.branches, branch) {
            continue
        }
        if !world_cache_append_hyperbola_branch(world, source, lerped, branch) {
            world.draw_cache.item_count = first_item
            world.draw_cache.curve_vertex_count = first_vertex
            return
        }
    }
    world_pose_curve_vertices(world, source.entity, alpha, lerped.center,
        world.draw_cache.curve_vertices[first_vertex:world.draw_cache.curve_vertex_count])
}

// Interpolate the permanent parabola tool from its analytic parameter.
world_lerped_parabola_tool :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Parabola_Tool, bool) {
    vertex, position_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.parabola_tools, &world.registry, entity)
    if !position_ok || !value_ok {
        return {}, false
    }
    value: shapemodel.Shape_Parabola_Tool = {
        focal_distance = math.lerp(
            current.previous_focal_distance, current.focal_distance, alpha),
        link_length = math.lerp(
            current.previous_link_length, current.link_length, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        parameter_start = math.lerp(
            current.previous_parameter_start, current.parameter_start, alpha),
        parameter_finish = math.lerp(
            current.previous_parameter_finish, current.parameter_finish, alpha),
        parameter = math.lerp(current.previous_parameter, current.parameter, alpha),
        active = current.active,
    }
    return {vertex, value}, shapemodel.shape_parabola_tool_is_valid(value)
}

// Cache the parabola's directrix rail, diamond, single guide, and tracing nib.
world_cache_push_parabola_tool :: proc(
    world: ^shapemodel.Shape_World, source: World_Draw_Source, alpha: f32) {
    lerped, found := world_lerped_parabola_tool(world, source.entity, alpha)
    if !found {
        return
    }
    pose := curve.parabola_tool_pose(lerped.vertex, lerped.value)
    f, t, angle :=
        lerped.value.focal_distance, lerped.value.parameter, lerped.value.rotation
    first_local: Vector3 = {-f, 2 * f * lerped.value.parameter_start, 0}
    finish_local: Vector3 = {-f, 2 * f * lerped.value.parameter_finish, 0}
    directrix_start := lerped.vertex + curve.rotate_planar(first_local, angle)
    directrix_finish := lerped.vertex + curve.rotate_planar(finish_local, angle)
    norm := math.sqrt(1 + t * t)
    extent := max(math.abs(lerped.value.parameter_start),
        math.abs(lerped.value.parameter_finish))
    guide_half := max(lerped.value.link_length,
        f * extent * math.sqrt(1 + extent * extent)) + 0.02
    guide_center := (pose.focus + pose.directrix_contact) * 0.5
    guide_axis := curve.rotate_planar({t / norm, 1 / norm, 0}, angle)
    draw: Shapes_Parabola_Tool_Draw = {
        base = world_make_draw_base(source, .Parabola_Tool),
        vertex = pose.vertex,
        focus = pose.focus,
        directrix_contact = pose.directrix_contact,
        directrix_rail_start = directrix_start,
        directrix_rail_finish = directrix_finish,
        diamond_first = pose.diamond_first,
        diamond_second = pose.diamond_second,
        guide_start = guide_center - guide_axis * guide_half,
        guide_finish = guide_center + guide_axis * guide_half,
        nib = pose.vertex,
        active = lerped.value.active,
    }
    world.draw_cache.parabola_tool = draw
    world.draw_cache.draw_parabola_tool = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}

// Interpolate the permanent hyperbola guide from the shared paired-tracer parameter.
world_lerped_hyperbola_tool :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Hyperbola_Tool, bool) {
    center, position_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.hyperbola_tools, &world.registry, entity)
    if !position_ok || !value_ok {
        return {}, false
    }
    value: shapemodel.Shape_Hyperbola_Tool = {
        semimajor = math.lerp(current.previous_semimajor, current.semimajor, alpha),
        semiminor = math.lerp(current.previous_semiminor, current.semiminor, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        parameter_start = math.lerp(
            current.previous_parameter_start, current.parameter_start, alpha),
        parameter_finish = math.lerp(
            current.previous_parameter_finish, current.parameter_finish, alpha),
        parameter = math.lerp(current.previous_parameter, current.parameter, alpha),
        rail_half_length = math.lerp(
            current.previous_rail_half_length, current.rail_half_length, alpha),
        active_branches = current.active_branches,
    }
    return {center, value}, shapemodel.shape_hyperbola_tool_is_valid(value)
}

// Cache the asymptote X, pivot rail, minimum-radius ticks, and paired carriages.
world_cache_push_hyperbola_tool :: proc(
    world: ^shapemodel.Shape_World, source: World_Draw_Source, alpha: f32) {
    lerped, found := world_lerped_hyperbola_tool(world, source.entity, alpha)
    if !found {
        return
    }
    pose := curve.hyperbola_tool_pose(lerped.center, lerped.value)
    draw: Shapes_Hyperbola_Tool_Draw = {
        base = world_make_draw_base(source, .Hyperbola_Tool),
        center = pose.center,
        asymptote_first_start = pose.asymptote_first_start,
        asymptote_first_finish = pose.asymptote_first_finish,
        asymptote_second_start = pose.asymptote_second_start,
        asymptote_second_finish = pose.asymptote_second_finish,
        moving_rail_start = pose.moving_rail_start,
        moving_rail_finish = pose.moving_rail_finish,
        tick_first_start = pose.tick_first_start,
        tick_first_finish = pose.tick_first_finish,
        tick_second_start = pose.tick_second_start,
        tick_second_finish = pose.tick_second_finish,
        carriage_positive = pose.carriage_positive,
        carriage_negative = pose.carriage_negative,
        active_branches = lerped.value.active_branches,
    }
    world.draw_cache.hyperbola_tool = draw
    world.draw_cache.draw_hyperbola_tool = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}
