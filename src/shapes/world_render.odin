package shapes

import shapemodel "model"
import curve "curve"

import "core:math"
import "core:math/linalg"


// Group one world renderable's identity, style, and optional active feature.
World_Draw_Source :: struct {
    entity: shapemodel.Shape_Entity,
    style: shapemodel.Shape_Render_Style,
    active_child: int,
}

// Hold one interpolated arc center and its mutable geometry.
World_Lerped_Arc :: struct {
    center: Vector3,
    arc: shapemodel.Shape_Arc,
}

// Hold two interpolated circle centers and their immutable region description.
World_Lerped_Circle_Region :: struct {
    first_center, second_center: Vector3,
    value: shapemodel.Shape_Circle_Region,
}

CIRCLE_REGION_ARC_SEGMENTS :: 48
CIRCLE_REGION_VERTEX_COUNT :: CIRCLE_REGION_ARC_SEGMENTS * 2

// Hold one interpolated trochoid center and its mutable analytic description.
World_Lerped_Trochoid :: struct {
    center: Vector3,
    value: shapemodel.Shape_Trochoid,
}

// Hold one interpolated guide center and mutable analytic description.
World_Lerped_Trochoid_Tool :: struct {
    center: Vector3,
    value: shapemodel.Shape_Trochoid_Tool,
}

// Hold one interpolated cycloid rail and mutable analytic description.
World_Lerped_Cycloid :: struct {
    first: Vector3,
    second: Vector3,
    value: shapemodel.Shape_Cycloid,
}

// Hold one interpolated cycloid-guide rail and mutable analytic description.
World_Lerped_Cycloid_Tool :: struct {
    first: Vector3,
    second: Vector3,
    value: shapemodel.Shape_Cycloid_Tool,
}

// Snapshot Cycloid scalar state before the next fixed-step mutation.
shape_world_update_previous_cycloid_values :: proc(world: ^shapemodel.Shape_World) {
    for index in 0..<world.cycloids.count {
        value := &world.cycloids.values[index]
        value.previous_rolling_radius = value.rolling_radius
        value.previous_tracer_distance = value.tracer_distance
        value.previous_tracer_phase = value.tracer_phase
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_draw_parameter = value.draw_parameter
    }
    for index in 0..<world.cycloid_tools.count {
        value := &world.cycloid_tools.values[index]
        value.previous_rolling_radius = value.rolling_radius
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_parameter = value.parameter
        value.previous_orientation_phase = value.orientation_phase
    }
}

// Snapshot every interpolated shape value before the next fixed-step mutation.
shape_world_update_previous_values :: proc(world: ^shapemodel.Shape_World) {
    if world == nil {
        return
    }
    for index in 0..<world.transforms.count {
        world.transforms.values[index].previous_position =
            world.transforms.values[index].position
    }
    for index in 0..<world.arcs.count {
        arc := &world.arcs.values[index]
        arc.previous_radius = arc.radius
        arc.previous_start_theta = arc.start_theta
        arc.previous_sweep_theta = arc.sweep_theta
    }
    for index in 0..<world.trochoids.count {
        value := &world.trochoids.values[index]
        value.previous_fixed_radius = value.fixed_radius
        value.previous_rolling_radius = value.rolling_radius
        value.previous_tracer_distance = value.tracer_distance
        value.previous_tracer_phase = value.tracer_phase
        value.previous_rotation = value.rotation
        value.previous_parameter_start = value.parameter_start
        value.previous_parameter_finish = value.parameter_finish
        value.previous_draw_parameter = value.draw_parameter
    }
    for index in 0..<world.trochoid_tools.count {
        value := &world.trochoid_tools.values[index]
        value.previous_fixed_radius = value.fixed_radius
        value.previous_rolling_radius = value.rolling_radius
        value.previous_parameter = value.parameter
        value.previous_rotation = value.rotation
        value.previous_orientation_phase = value.orientation_phase
    }
    shape_world_update_previous_cycloid_values(world)
}

// Resolve one live transform and interpolate its previous and current positions.
shape_world_lerped_position :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (Vector3, bool) {
    transform, found := shapemodel.shape_component_get(
        &world.transforms, &world.registry, entity)
    if !found {
        return {}, false
    }
    return linalg.lerp(
        transform.previous_position, transform.position, alpha), true
}

// Convert canonical world presentation into the existing draw-union base.
world_make_draw_base :: proc(
    source: World_Draw_Source,
    kind: Shapes_Point_Type) -> Shapes_Draw_Base {
    active_color, has_active_color := source.style.active_color.?
    return {
        kind = kind,
        source_index = int(source.entity.slot) - 1,
        brush_size = source.style.brush_size,
        color = source.style.color,
        active_color = active_color,
        has_active_color = has_active_color,
        active_child = source.active_child,
    }
}

// Resolve optional active-feature state for one visible renderable entity.
world_draw_source :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    style: shapemodel.Shape_Render_Style) -> World_Draw_Source {
    active_child := 0
    feature, found := shapemodel.shape_component_get(
        &world.active_features, &world.registry, entity)
    if found {
        active_child = int(feature.index)
    }
    return {entity = entity, style = style, active_child = active_child}
}

// Push one visible label with immutable canonical source metadata.
world_cache_push_label :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    label: shapemodel.Shape_Label,
    alpha: f32) {
    if label.mime != .Text_Plain {
        return
    }
    position, position_ok := shape_world_lerped_position(
        world, source.entity, alpha)
    _, text_ok := shapemodel.shape_label_source(&world.label_store, label)
    if !position_ok || !text_ok {
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        return
    }
    slot^ = Shapes_Label_Draw{world_make_draw_base(source, .Label),
        position, label.mime, label.byte_offset, label.byte_count, label.revision}
}

// Resolve one world label packet item while its joined canonical generation is live.
shape_world_draw_label_source :: proc(
    world: ^shapemodel.Shape_World,
    draw: Shapes_Label_Draw) -> (string, bool) {
    if world == nil || draw.mime != .Text_Plain || draw.source_revision == 0 {
        return "", false
    }
    label := shapemodel.Shape_Label{mime = draw.mime, byte_offset = draw.source_offset,
        byte_count = draw.source_count, revision = draw.source_revision}
    return shapemodel.shape_label_source(&world.label_store, label)
}

// Push one visible transform-backed point into the world packet.
world_cache_push_point :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    alpha: f32) {
    position, found := shape_world_lerped_position(world, source.entity, alpha)
    if !found {
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = Shapes_Point_Draw{world_make_draw_base(source, .Point), position}
    }
}

// Push one visible line after resolving both direct endpoint transforms.
world_cache_push_line :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Line_Geometry,
    alpha: f32) {
    first, first_ok := shape_world_lerped_position(world, geometry.first, alpha)
    second, second_ok := shape_world_lerped_position(world, geometry.second, alpha)
    if !first_ok || !second_ok {
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = Shapes_Line_Draw{world_make_draw_base(source, .Line), first, second}
    }
}

// Resolve and interpolate one host's center and mutable arc parameters.
world_lerped_arc :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Arc, bool) {
    center, center_ok := shape_world_lerped_position(world, entity, alpha)
    arc, arc_ok := shapemodel.shape_component_get(
        &world.arcs, &world.registry, entity)
    if !center_ok || !arc_ok {
        return {}, false
    }
    interpolated := shapemodel.Shape_Arc{
        radius = math.lerp(arc.previous_radius, arc.radius, alpha),
        start_theta = math.lerp(arc.previous_start_theta, arc.start_theta, alpha),
        sweep_theta = math.lerp(arc.previous_sweep_theta, arc.sweep_theta, alpha),
    }
    return {center, interpolated}, true
}

// Push one visible outlined or filled arc into the world packet.
world_cache_push_arc :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Arc_Geometry,
    kind: shapemodel.Shape_Geometry_Kind,
    alpha: f32) {
    lerped, found := world_lerped_arc(world, source.entity, alpha)
    if !found {
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        return
    }
    if kind == .Arc {
        slot^ = Shapes_Circle_Draw{world_make_draw_base(source, .Circle),
            lerped.center, lerped.arc.radius, lerped.arc.start_theta,
            lerped.arc.sweep_theta}
    } else {
        slot^ = Shapes_Filled_Circle_Draw{
            world_make_draw_base(source, .Filled_Circle),
            lerped.center, lerped.arc.radius, lerped.arc.start_theta,
            lerped.arc.sweep_theta}
    }
}

// Resolve one region's direct centers and immutable operation and radii.
world_lerped_circle_region :: proc(
    world: ^shapemodel.Shape_World,
    geometry: shapemodel.Shape_Circle_Region_Geometry,
    alpha: f32) -> (World_Lerped_Circle_Region, bool) {
    first, first_ok := shape_world_lerped_position(world, geometry.first_center, alpha)
    second, second_ok := shape_world_lerped_position(
        world, geometry.second_center, alpha)
    if !first_ok || !second_ok {
        return {}, false
    }
    return {first, second, geometry.value},
        shapemodel.shape_circle_region_is_valid(geometry.value)
}

// Write one directed circle arc without duplicating its terminal endpoint.
world_sample_region_arc :: proc(
    vertices: []Vector3,
    center: Vector3,
    radius, start, sweep: f32) {
    for index in 0..<len(vertices) {
        parameter := f32(index) / f32(len(vertices))
        angle := start + sweep * parameter
        vertices[index] = {center.x + radius * math.cos(angle),
            center.y + radius * math.sin(angle), center.z}
    }
}

// Explicate one proper two-circle region into a closed ordered boundary ring.
world_sample_circle_region :: proc(
    region: World_Lerped_Circle_Region,
    vertices: []Vector3) -> bool {
    if len(vertices) != CIRCLE_REGION_VERTEX_COUNT {
        return false
    }
    delta := region.second_center - region.first_center
    distance := f32(math.sqrt(delta.x * delta.x + delta.y * delta.y))
    first_radius := region.value.first_radius
    second_radius := region.value.second_radius
    if distance <= math.abs(first_radius - second_radius) ||
        distance >= first_radius + second_radius {
        return false
    }
    base := math.atan2(delta.y, delta.x)
    first_half := math.acos(math.clamp((first_radius * first_radius +
        distance * distance - second_radius * second_radius) /
        (2 * first_radius * distance), -1, 1))
    second_half := math.acos(math.clamp((second_radius * second_radius +
        distance * distance - first_radius * first_radius) /
        (2 * second_radius * distance), -1, 1))
    first_vertices := vertices[:CIRCLE_REGION_ARC_SEGMENTS]
    second_vertices := vertices[CIRCLE_REGION_ARC_SEGMENTS:]
    if region.value.operation == .Intersection {
        world_sample_region_arc(first_vertices, region.first_center, first_radius,
            base - first_half, 2 * first_half)
        world_sample_region_arc(second_vertices, region.second_center, second_radius,
            base + math.PI - second_half, 2 * second_half)
    } else {
        world_sample_region_arc(first_vertices, region.first_center, first_radius,
            base + first_half, 2 * math.PI - 2 * first_half)
        world_sample_region_arc(second_vertices, region.second_center, second_radius,
            base + math.PI + second_half, -2 * second_half)
    }
    return true
}

// Push one analytic circle region through shared polygon packet triangulation.
world_cache_push_circle_region :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Circle_Region_Geometry,
    alpha: f32) {
    region, found := world_lerped_circle_region(world, geometry, alpha)
    if !found {return}
    reservation := reserve_polygon_cache_ranges_storage(
        &world.draw_cache, CIRCLE_REGION_VERTEX_COUNT)
    if !reservation.ok {return}
    vertices := world.draw_cache.polygon_vertices[
        reservation.first_vertex:reservation.first_vertex + CIRCLE_REGION_VERTEX_COUNT]
    if !world_sample_circle_region(region, vertices) {
        rollback_polygon_cache_ranges_storage(&world.draw_cache,
            CIRCLE_REGION_VERTEX_COUNT, reservation.max_triangle_count)
        return
    }
    triangle_count := triangulate_polygon_ear_clip_storage(&world.draw_cache,
        reservation.first_vertex, vertices, reservation.first_triangle)
    finalize_polygon_triangle_reservation_storage(
        &world.draw_cache, reservation.first_triangle, triangle_count)
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        rollback_polygon_cache_ranges_storage(
            &world.draw_cache, CIRCLE_REGION_VERTEX_COUNT, triangle_count)
        return
    }
    kind := Shapes_Point_Type.Lens
    if region.value.operation == .Difference {kind = .Lune}
    slot^ = Shapes_Polygon_Draw{world_make_draw_base(source, kind),
        reservation.first_vertex, CIRCLE_REGION_VERTEX_COUNT,
        reservation.first_triangle, triangle_count}
}

// Resolve and interpolate one host's trochoid description.
world_lerped_trochoid :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Trochoid, bool) {
    center, center_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.trochoids, &world.registry, entity)
    if !center_ok || !value_ok {
        return {}, false
    }
    value := shapemodel.Shape_Trochoid{mode = current.mode,
        fixed_radius = math.lerp(
            current.previous_fixed_radius, current.fixed_radius, alpha),
        rolling_radius = math.lerp(
            current.previous_rolling_radius, current.rolling_radius, alpha),
        tracer_distance = math.lerp(
            current.previous_tracer_distance, current.tracer_distance, alpha),
        tracer_phase = math.lerp(
            current.previous_tracer_phase, current.tracer_phase, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        parameter_start = math.lerp(
            current.previous_parameter_start, current.parameter_start, alpha),
        parameter_finish = math.lerp(
            current.previous_parameter_finish, current.parameter_finish, alpha),
        draw_parameter = math.lerp(
            current.previous_draw_parameter, current.draw_parameter, alpha)}
    return {center, value}, shapemodel.shape_trochoid_is_valid(value)
}

// Push one visible trochoid as a bounded frame-local curve packet.
world_cache_push_trochoid :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    alpha: f32) {
    lerped, found := world_lerped_trochoid(world, source.entity, alpha)
    if !found {
        return
    }
    first, reserved := draw_cache_reserve_curve_vertices_storage(
        &world.draw_cache, curve.TROCHOID_MAX_VERTICES)
    if !reserved {
        return
    }
    vertices := world.draw_cache.curve_vertices[
        first:first + curve.TROCHOID_MAX_VERTICES]
    kinds := world.draw_cache.curve_vertex_kinds[
        first:first + curve.TROCHOID_MAX_VERTICES]
    result := curve.trochoid_explicate_marked(
        lerped.center, lerped.value, vertices, kinds)
    draw_cache_finalize_curve_vertices_storage(&world.draw_cache,
        first, curve.TROCHOID_MAX_VERTICES, result.vertex_count)
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
    slot^ = Shapes_Curve_Draw{base = world_make_draw_base(source, .Curve),
        first_vertex = first, vertex_count = result.vertex_count,
        capacity_limited = result.status == .Capacity_Limited,
        topology = result.topology}
}

// Resolve and interpolate the permanent trochoid guide description.
world_lerped_trochoid_tool :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    alpha: f32) -> (World_Lerped_Trochoid_Tool, bool) {
    center, center_ok := shape_world_lerped_position(world, entity, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.trochoid_tools, &world.registry, entity)
    if !center_ok || !value_ok {
        return {}, false
    }
    value := shapemodel.Shape_Trochoid_Tool{mode = current.mode,
        fixed_radius = math.lerp(
            current.previous_fixed_radius, current.fixed_radius, alpha),
        rolling_radius = math.lerp(
            current.previous_rolling_radius, current.rolling_radius, alpha),
        parameter = math.lerp(current.previous_parameter, current.parameter, alpha),
        rotation = math.lerp(current.previous_rotation, current.rotation, alpha),
        orientation_phase = math.lerp(current.previous_orientation_phase,
            current.orientation_phase, alpha)}
    return {center, value}, shapemodel.shape_trochoid_tool_is_valid(value)
}

// Push the permanent guide as one resolved high-layer tool packet.
world_cache_push_trochoid_tool :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    alpha: f32) {
    lerped, found := world_lerped_trochoid_tool(world, source.entity, alpha)
    if !found {
        return
    }
    pose := curve.trochoid_tool_pose(lerped.center, lerped.value)
    handle_direction := Vector3{math.cos(pose.rolling_orientation),
        math.sin(pose.rolling_orientation), 0}
    handle_start := pose.rolling_center + handle_direction * lerped.value.rolling_radius
    handle_finish := handle_start - handle_direction * lerped.value.rolling_radius * 0.30
    draw := Shapes_Trochoid_Tool_Draw{world_make_draw_base(source, .Trochoid_Tool),
        pose.fixed_center, pose.rolling_center, lerped.value.fixed_radius,
        lerped.value.rolling_radius, handle_start, handle_finish}
    world.draw_cache.trochoid_tool = draw
    world.draw_cache.draw_trochoid_tool = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}

// Resolve and interpolate one literal-line cycloid description.
world_lerped_cycloid :: proc(world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Cycloid_Geometry,
    alpha: f32) -> (World_Lerped_Cycloid, bool) {
    first, first_ok := shape_world_lerped_position(world, geometry.first, alpha)
    second, second_ok := shape_world_lerped_position(world, geometry.second, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.cycloids, &world.registry, entity)
    if !first_ok || !second_ok || !value_ok {
        return {}, false
    }
    value := shapemodel.Shape_Cycloid{
        rolling_radius = math.lerp(current.previous_rolling_radius,
            current.rolling_radius, alpha),
        tracer_distance = math.lerp(current.previous_tracer_distance,
            current.tracer_distance, alpha),
        tracer_phase = math.lerp(current.previous_tracer_phase,
            current.tracer_phase, alpha),
        parameter_start = math.lerp(current.previous_parameter_start,
            current.parameter_start, alpha),
        parameter_finish = math.lerp(current.previous_parameter_finish,
            current.parameter_finish, alpha),
        draw_parameter = math.lerp(current.previous_draw_parameter,
            current.draw_parameter, alpha)}
    valid := shapemodel.shape_cycloid_is_valid(value) &&
        shapemodel.shape_cycloid_line_is_valid(first, second,
            value.rolling_radius, value.parameter_start, value.parameter_finish)
    return {first, second, value}, valid
}

// Push one visible cycloid as a bounded frame-local curve packet.
world_cache_push_cycloid :: proc(world: ^shapemodel.Shape_World,
    source: World_Draw_Source, geometry: shapemodel.Shape_Cycloid_Geometry,
    alpha: f32) {
    lerped, found := world_lerped_cycloid(world, source.entity, geometry, alpha)
    if !found {
        return
    }
    first_vertex, reserved := draw_cache_reserve_curve_vertices_storage(
        &world.draw_cache, curve.CYCLOID_MAX_VERTICES)
    if !reserved {
        return
    }
    vertices := world.draw_cache.curve_vertices[
        first_vertex:first_vertex + curve.CYCLOID_MAX_VERTICES]
    kinds := world.draw_cache.curve_vertex_kinds[
        first_vertex:first_vertex + curve.CYCLOID_MAX_VERTICES]
    result := curve.cycloid_explicate_marked(
        lerped.first, lerped.second, lerped.value, vertices, kinds)
    draw_cache_finalize_curve_vertices_storage(&world.draw_cache,
        first_vertex, curve.CYCLOID_MAX_VERTICES, result.vertex_count)
    if result.status == .Invalid_Input || result.vertex_count < 2 {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first_vertex, result.vertex_count)
        return
    }
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        draw_cache_rollback_curve_vertices_storage(
            &world.draw_cache, first_vertex, result.vertex_count)
        return
    }
    slot^ = Shapes_Curve_Draw{base = world_make_draw_base(source, .Curve),
        first_vertex = first_vertex, vertex_count = result.vertex_count,
        capacity_limited = result.status == .Capacity_Limited,
        topology = result.topology}
}

// Resolve and interpolate the permanent literal-line cycloid guide.
world_lerped_cycloid_tool :: proc(world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    geometry: shapemodel.Shape_Cycloid_Tool_Geometry,
    alpha: f32) -> (World_Lerped_Cycloid_Tool, bool) {
    first, first_ok := shape_world_lerped_position(world, geometry.first, alpha)
    second, second_ok := shape_world_lerped_position(world, geometry.second, alpha)
    current, value_ok := shapemodel.shape_component_get(
        &world.cycloid_tools, &world.registry, entity)
    if !first_ok || !second_ok || !value_ok {
        return {}, false
    }
    value := shapemodel.Shape_Cycloid_Tool{
        rolling_radius = math.lerp(current.previous_rolling_radius,
            current.rolling_radius, alpha),
        parameter_start = math.lerp(current.previous_parameter_start,
            current.parameter_start, alpha),
        parameter_finish = math.lerp(current.previous_parameter_finish,
            current.parameter_finish, alpha),
        parameter = math.lerp(current.previous_parameter, current.parameter, alpha),
        orientation_phase = math.lerp(current.previous_orientation_phase,
            current.orientation_phase, alpha)}
    valid := shapemodel.shape_cycloid_tool_is_valid(value) &&
        shapemodel.shape_cycloid_line_is_valid(first, second,
            value.rolling_radius, value.parameter_start, value.parameter_finish)
    return {first, second, value}, valid
}

// Push the permanent cycloid guide as one resolved high-layer tool packet.
world_cache_push_cycloid_tool :: proc(world: ^shapemodel.Shape_World,
    source: World_Draw_Source, geometry: shapemodel.Shape_Cycloid_Tool_Geometry,
    alpha: f32) {
    lerped, found := world_lerped_cycloid_tool(
        world, source.entity, geometry, alpha)
    if !found {
        return
    }
    pose := curve.cycloid_tool_pose(lerped.first, lerped.second, lerped.value)
    handle_direction := Vector3{math.cos(pose.rolling_orientation),
        math.sin(pose.rolling_orientation), 0}
    handle_start := pose.rolling_center +
        handle_direction * lerped.value.rolling_radius
    handle_finish := handle_start -
        handle_direction * lerped.value.rolling_radius * 0.30
    draw := Shapes_Cycloid_Tool_Draw{world_make_draw_base(source, .Cycloid_Tool),
        pose.baseline_start, pose.baseline_finish, pose.rolling_center,
        lerped.value.rolling_radius, handle_start, handle_finish}
    world.draw_cache.cycloid_tool = draw
    world.draw_cache.draw_cycloid_tool = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}

// Resolve ordered polygon entities into one reserved packet vertex span.
world_cache_polygon_vertices :: proc(
    world: ^shapemodel.Shape_World,
    entities: []shapemodel.Shape_Entity,
    alpha: f32,
    vertices: []Vector3) -> bool {
    if len(entities) != len(vertices) {
        return false
    }
    for entity, index in entities {
        position, found := shape_world_lerped_position(world, entity, alpha)
        if !found {
            return false
        }
        vertices[index] = position
    }
    return true
}

// Push one visible polygon through the shared packet ear-clipping workspace.
world_cache_push_polygon :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Polygon_Geometry,
    alpha: f32) {
    entities, found := shapemodel.shape_polygon_vertices(world, geometry)
    if !found {
        return
    }
    reservation := reserve_polygon_cache_ranges_storage(
        &world.draw_cache, len(entities))
    if !reservation.ok {
        return
    }
    vertices := world.draw_cache.polygon_vertices[
        reservation.first_vertex:reservation.first_vertex + len(entities)]
    if !world_cache_polygon_vertices(world, entities, alpha, vertices) {
        rollback_polygon_cache_ranges_storage(&world.draw_cache,
            len(entities), reservation.max_triangle_count)
        return
    }
    triangle_count := triangulate_polygon_ear_clip_storage(&world.draw_cache,
        reservation.first_vertex, vertices, reservation.first_triangle)
    finalize_polygon_triangle_reservation_storage(
        &world.draw_cache, reservation.first_triangle, triangle_count)
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if !has_slot {
        rollback_polygon_cache_ranges_storage(
            &world.draw_cache, len(entities), triangle_count)
        return
    }
    slot^ = Shapes_Polygon_Draw{world_make_draw_base(source, .Triangle),
        reservation.first_vertex, len(entities),
        reservation.first_triangle, triangle_count}
}

// Push one visible pen using its direct joint references.
world_cache_push_pen :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Pen_Geometry,
    alpha: f32) {
    first, first_ok := shape_world_lerped_position(world, geometry.joint1, alpha)
    second, second_ok := shape_world_lerped_position(world, geometry.joint2, alpha)
    if !first_ok || !second_ok {
        return
    }
    draw := Shapes_Pen_Draw{
        world_make_draw_base(source, .Pen), first, second}
    world.draw_cache.pen = draw
    world.draw_cache.draw_pen = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}

// Push one visible compass using its three direct joint references.
world_cache_push_compass :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Compass_Geometry,
    alpha: f32) {
    joint1, first_ok := shape_world_lerped_position(world, geometry.joint1, alpha)
    pivot, pivot_ok := shape_world_lerped_position(world, geometry.pivot, alpha)
    joint2, second_ok := shape_world_lerped_position(world, geometry.joint2, alpha)
    if !first_ok || !pivot_ok || !second_ok {
        return
    }
    draw := Shapes_Compass_Draw{
        world_make_draw_base(source, .Compass), joint1, pivot, joint2}
    world.draw_cache.compass = draw
    world.draw_cache.draw_compass = true
    slot, has_slot := draw_cache_next_item_slot_storage(&world.draw_cache)
    if has_slot {
        slot^ = draw
    }
}

// Push one visible instrument geometry and report whether it was handled.
world_cache_push_instrument :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Geometry,
    alpha: f32) -> bool {
    switch geometry.kind {
    case .Trochoid_Tool:
        world_cache_push_trochoid_tool(world, source, alpha)
    case .Cycloid_Tool:
        world_cache_push_cycloid_tool(
            world, source, geometry.payload.cycloid_tool, alpha)
    case .Pen:
        world_cache_push_pen(world, source, geometry.payload.pen, alpha)
    case .Compass:
        world_cache_push_compass(world, source, geometry.payload.compass, alpha)
    case .Point, .Line, .Arc, .Filled_Arc, .Circle_Region, .Trochoid,
        .Cycloid, .Polygon:
        return false
    }
    return true
}

// Dispatch one visible direct geometry payload into the existing draw union.
world_cache_push_geometry :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Geometry,
    alpha: f32) {
    if world_cache_push_instrument(world, source, geometry, alpha) {return}
    switch geometry.kind {
    case .Point: world_cache_push_point(world, source, alpha)
    case .Line: world_cache_push_line(world, source, geometry.payload.line, alpha)
    case .Arc, .Filled_Arc:
        world_cache_push_arc(world, source, geometry.payload.arc, geometry.kind, alpha)
    case .Circle_Region:
        world_cache_push_circle_region(
            world, source, geometry.payload.circle_region, alpha)
    case .Trochoid: world_cache_push_trochoid(world, source, alpha)
    case .Cycloid:
        world_cache_push_cycloid(world, source, geometry.payload.cycloid, alpha)
    case .Polygon:
        world_cache_push_polygon(world, source, geometry.payload.polygon, alpha)
    case .Trochoid_Tool, .Cycloid_Tool, .Pen, .Compass:
        return
    }
}

// Build one pointer-free render packet from visible world component membership.
build_shape_world_draw_cache :: proc(
    world: ^shapemodel.Shape_World,
    alpha: f32) {
    if world == nil {
        return
    }
    draw_cache_reset_storage(&world.draw_cache)
    for index in 0..<world.render_styles.count {
        entity := world.render_styles.entities[index]
        style := world.render_styles.values[index]
        if !style.visible ||
           !shapemodel.shape_registry_resolves(&world.registry, entity) {
            continue
        }
        source := world_draw_source(world, entity, style)
        label, has_label := shapemodel.shape_component_get(
            &world.labels, &world.registry, entity)
        if has_label {
            world_cache_push_label(world, source, label^, alpha)
            continue
        }
        geometry, has_geometry := shapemodel.shape_component_get(
            &world.geometries, &world.registry, entity)
        if has_geometry {
            world_cache_push_geometry(world, source, geometry^, alpha)
        }
    }
    sort_draw_cache_storage(&world.draw_cache)
}