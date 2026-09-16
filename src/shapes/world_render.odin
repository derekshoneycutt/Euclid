package shapes

import shapemodel "model"

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

// Dispatch one visible direct geometry payload into the existing draw union.
world_cache_push_geometry :: proc(
    world: ^shapemodel.Shape_World,
    source: World_Draw_Source,
    geometry: shapemodel.Shape_Geometry,
    alpha: f32) {
    switch geometry.kind {
    case .Point:
        world_cache_push_point(world, source, alpha)
    case .Line:
        world_cache_push_line(world, source, geometry.payload.line, alpha)
    case .Arc, .Filled_Arc:
        world_cache_push_arc(world, source, geometry.payload.arc, geometry.kind, alpha)
    case .Polygon:
        world_cache_push_polygon(world, source, geometry.payload.polygon, alpha)
    case .Pen:
        world_cache_push_pen(world, source, geometry.payload.pen, alpha)
    case .Compass:
        world_cache_push_compass(world, source, geometry.payload.compass, alpha)
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