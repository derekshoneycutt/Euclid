package shapes

import shapemodel "model"

import "core:testing"

import test_helpers "../test_helpers"

// Mark one constructed entity visible in the canonical render-style set.
world_render_test_show :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) {
    style, found := shapemodel.shape_component_get_mut(
        &world.render_styles, &world.registry, entity)
    assert(found)
    style.visible = true
}

// Resolve one mutable transform used by render interpolation tests.
world_render_test_transform :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity) -> ^shapemodel.Shape_Transform {
    transform, found := shapemodel.shape_component_get_mut(
        &world.transforms, &world.registry, entity)
    assert(found)
    return transform
}

// Verify dense transform snapshots feed packet interpolation without topology scans.
@(test)
world_render_snapshots_dense_transforms_for_interpolation :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    point, status := world_create_point(world, {2, 0, 0}, Shape_Style{})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, point.entity)
    shape_world_update_previous_values(world)
    world_render_test_transform(world, point.entity).position = {6, 0, 0}

    build_shape_world_draw_cache(world, 0.25)

    testing.expect_value(t, world.draw_cache.item_count, 1)
    item := world.draw_cache.items[0]
    #partial switch typed in item {
    case Shapes_Point_Draw:
        test_helpers.expect_vec3_close(t, typed.point1, {3, 0, 0},
            "world point should interpolate previous and current transforms")
    case:
        testing.expect(t, false, "expected point draw item")
    }
}

// Verify fixed-arity geometry resolves direct entities into the existing draw union.
@(test)
world_render_builds_direct_line_and_arc_items :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    line, line_status := world_create_line(
        world, {0, 0, 0}, {2, 0, 0}, Shape_Style{})
    arc, arc_status := world_create_arc(world, {
        center = {4, 0, 0}, radius = 2, start_theta = 0,
        sweep_theta = 1, style = Shape_Style{}})
    testing.expect_value(t, line_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, arc_status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, line.shape)
    world_render_test_show(world, arc.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 2)
    line_found := false
    arc_found := false
    for item in world.draw_cache.items[:world.draw_cache.item_count] {
        #partial switch typed in item {
        case Shapes_Line_Draw:
            line_found = typed.point1 == Vector3{} && typed.point2 == Vector3{2, 0, 0}
        case Shapes_Circle_Draw:
            arc_found = typed.center == Vector3{4, 0, 0}
        case:
        }
    }
    testing.expect(t, line_found)
    testing.expect(t, arc_found)
}

// Verify a revealed trochoid compiles once into the dedicated curve vertex pool.
@(test)
world_render_builds_trochoid_curve_packet :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    trochoid, status := world_create_trochoid(world, {center = {1, 2, 0},
        mode = .External, fixed_radius = 0.2, rolling_radius = 0.2,
        tracer_distance = 0.2, parameter_start = 0, parameter_finish = 6.28,
        draw_parameter = 3.14, style = Shape_Style{}})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, trochoid.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 1)
    testing.expect(t, world.draw_cache.curve_vertex_count > 1)
    item := world.draw_cache.items[0]
    #partial switch typed in item {
    case Shapes_Curve_Draw:
        testing.expect_value(t, typed.first_vertex, 0)
        testing.expect_value(t, typed.vertex_count, world.draw_cache.curve_vertex_count)
        testing.expect_value(t, typed.topology, shapemodel.Curve_Topology.Open)
        kinds := world.draw_cache.curve_vertex_kinds[
            typed.first_vertex:typed.first_vertex + typed.vertex_count]
        testing.expect_value(t, kinds[0], shapemodel.Curve_Point_Kind.Cusp)
    case:
        testing.expect(t, false, "expected curve draw item")
    }
}

// Verify curve storage rollback leaves one aligned frontier for points and kinds.
@(test)
world_render_curve_storage_rollback_preserves_alignment :: proc(t: ^testing.T) {
    cache: shapemodel.Shapes_Draw_Cache
    first, reserved := draw_cache_reserve_curve_vertices_storage(&cache, 4)
    testing.expect(t, reserved)
    cache.curve_vertices[first] = {1, 2, 3}
    cache.curve_vertex_kinds[first] = .Cusp
    draw_cache_finalize_curve_vertices_storage(&cache, first, 4, 1)
    testing.expect_value(t, cache.curve_vertex_count, 1)

    draw_cache_rollback_curve_vertices_storage(&cache, first, 1)
    testing.expect_value(t, cache.curve_vertex_count, 0)
}

// Verify the guide packet derives its rolling center and inward orientation handle.
@(test)
world_render_builds_trochoid_tool_packet :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    tool, status := world_create_trochoid_tool(world, {center = {1, 2, 0},
        mode = .External, fixed_radius = 2, rolling_radius = 1,
        style = Shape_Style{}})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, tool.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect(t, world.draw_cache.draw_trochoid_tool)
    draw := world.draw_cache.trochoid_tool
    test_helpers.expect_vec3_close(t, draw.fixed_center, {1, 2, 0},
        "guide fixed center should follow its host transform")
    test_helpers.expect_vec3_close(t, draw.rolling_center, {4, 2, 0},
        "external rolling center should use the summed radii")
    test_helpers.expect_vec3_close(t, draw.handle_start, {3, 2, 0},
        "orientation handle should begin on the contact-facing rolling rim")
    test_helpers.expect_vec3_close(t, draw.handle_finish, {3.3, 2, 0},
        "orientation handle should extend inward from the rolling rim")
}

// Verify filled arcs and direct-reference tools publish existing draw variants and flags.
@(test)
world_render_builds_filled_arc_pen_and_compass_items :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    filled, filled_status := world_create_filled_arc(world, {
        center = {0, 0, 0}, radius = 1, start_theta = 0,
        sweep_theta = 1, style = Shape_Style{}})
    pen, pen_status := world_create_pen(world, {
        joint1 = {2, 0, 0}, joint2 = {3, 0, 0}, length = 1,
        style = Shape_Style{}})
    compass, compass_status := world_create_compass(world, {
        joint1 = {4, 0, 0}, pivot = {5, 0, 0}, joint2 = {6, 0, 0},
        limb_length = 1, style = Shape_Style{}})
    testing.expect_value(t, filled_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, compass_status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, filled.shape)
    world_render_test_show(world, pen.shape)
    world_render_test_show(world, compass.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 3)
    testing.expect(t, world.draw_cache.draw_pen)
    testing.expect(t, world.draw_cache.draw_compass)
    testing.expect_value(t, world.draw_cache.pen.joint1, Vector3{2, 0, 0})
    testing.expect_value(t, world.draw_cache.compass.pivot, Vector3{5, 0, 0})
    filled_found := false
    for item in world.draw_cache.items[:world.draw_cache.item_count] {
        #partial switch typed in item {
        case Shapes_Filled_Circle_Draw:
            filled_found = typed.center == Vector3{}
        case:
        }
    }
    testing.expect(t, filled_found)
}

// Verify ordered world polygon references feed shared packet triangulation storage.
@(test)
world_render_triangulates_ordered_polygon_references :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    positions := [4]Vector3{{0, 0, 0}, {2, 0, 0}, {2, 2, 0}, {0, 2, 0}}
    square, status := world_create_square(world, positions, Shape_Style{})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, square.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 1)
    testing.expect_value(t, world.draw_cache.polygon_vertex_count, 4)
    testing.expect_value(t, world.draw_cache.polygon_triangle_count, 2)
    for position, index in positions {
        testing.expect_value(t, world.draw_cache.polygon_vertices[index], position)
    }
}

// Verify Lens and Lune analytic boundaries compile into triangulated polygon packets.
@(test)
world_render_triangulates_circle_regions :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    input := Circle_Region_Input{first_center = {0, 0, 0},
        second_center = {1, 0, 0}, first_radius = 1, second_radius = 1}
    lens, lens_status := world_create_lens(world, input)
    lune, lune_status := world_create_lune(world, input)
    testing.expect_value(t, lens_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, lune_status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, lens.shape)
    world_render_test_show(world, lune.shape)

    build_shape_world_draw_cache(world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 2)
    testing.expect_value(t, world.draw_cache.polygon_vertex_count,
        CIRCLE_REGION_VERTEX_COUNT * 2)
    testing.expect(t, world.draw_cache.polygon_triangle_count > 0)
    lens_found := false
    lune_found := false
    for item in world.draw_cache.items[:world.draw_cache.item_count] {
        #partial switch typed in item {
        case Shapes_Polygon_Draw:
            lens_found = lens_found || typed.kind == .Lens
            lune_found = lune_found || typed.kind == .Lune
        case:
        }
    }
    testing.expect(t, lens_found && lune_found)
}

// Verify Unicode label metadata resolves immutable source while the packet is live.
@(test)
world_render_resolves_unicode_label_source_metadata :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    label, status := world_create_label(world, {
        source = "∠A′", mime = .Text_Plain, position = {1, 2, 0},
        style = Shape_Style{}})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, label.entity)

    build_shape_world_draw_cache(world, 1)

    item := world.draw_cache.items[0]
    #partial switch typed in item {
    case Shapes_Label_Draw:
        source, found := shape_world_draw_label_source(world, typed)
        testing.expect(t, found)
        testing.expect_value(t, source, "∠A′")
        testing.expect_value(t, typed.mime, shapemodel.Shape_Text_Mime.Text_Plain)
        testing.expect_value(t, typed.source_revision, u32(1))
    case:
        testing.expect(t, false, "expected label draw item")
    }
}

// Verify world packet sorting retains the existing representative-depth strategy.
@(test)
world_render_sorts_nonflat_items_by_visual_depth :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    lower, _ := world_create_point(world, {0, 0, 2}, Shape_Style{})
    higher, _ := world_create_point(world, {4, 0, 1}, Shape_Style{})
    world_render_test_show(world, lower.entity)
    world_render_test_show(world, higher.entity)

    build_shape_world_draw_cache(world, 1)

    first := world.draw_cache.items[0]
    #partial switch typed in first {
    case Shapes_Point_Draw:
        testing.expect_value(t, typed.source_index, int(higher.entity.slot) - 1)
    case:
        testing.expect(t, false, "expected sorted point draw item")
    }
}

// Verify canonical suffix rewind invalidates all packet-owned derived state first.
@(test)
world_render_packet_does_not_survive_animation_rewind :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        world), shapemodel.Shape_World_Status.Ok)
    label, status := world_create_label(world, {
        source = "α", mime = .Text_Plain, style = Shape_Style{}})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    world_render_test_show(world, label.entity)
    build_shape_world_draw_cache(world, 1)
    testing.expect_value(t, world.draw_cache.item_count, 1)
    testing.expect_value(t, world.draw_cache.label_byte_count, u16(0))

    testing.expect_value(t, shapemodel.shape_world_rewind_animation(
        world), shapemodel.Shape_World_Status.Ok)

    testing.expect_value(t, world.draw_cache.item_count, 0)
    testing.expect_value(t, world.draw_cache.label_byte_count, u16(0))
    testing.expect_value(t, world.draw_cache.polygon_vertex_count, 0)
}