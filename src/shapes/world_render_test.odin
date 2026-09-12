package shapes

import "core:testing"

import "../core"
import test_helpers "../test_helpers"

// Mark one constructed entity visible in the canonical render-style set.
world_render_test_show :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity) {
    style, found := core.shape_component_get_mut(
        &world.render_styles, &world.registry, entity)
    assert(found)
    style.visible = true
}

// Resolve one mutable transform used by render interpolation tests.
world_render_test_transform :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity) -> ^core.Shape_Transform {
    transform, found := core.shape_component_get_mut(
        &world.transforms, &world.registry, entity)
    assert(found)
    return transform
}

// Verify dense transform snapshots feed packet interpolation without topology scans.
@(test)
world_render_snapshots_dense_transforms_for_interpolation :: proc(t: ^testing.T) {
    world: core.Shape_World
    point, status := world_create_point(&world, {2, 0, 0}, Shape_Style{})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, point.entity)
    shape_world_update_previous_positions(&world)
    world_render_test_transform(&world, point.entity).position = {6, 0, 0}

    build_shape_world_draw_cache(&world, 0.25)

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
    world: core.Shape_World
    line, line_status := world_create_line(
        &world, {0, 0, 0}, {2, 0, 0}, Shape_Style{})
    arc, arc_status := world_create_arc(&world, {
        center = {4, 0, 0}, radius = 2, start_theta = 0,
        end_theta = 1, style = Shape_Style{}})
    testing.expect_value(t, line_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, arc_status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, line.shape)
    world_render_test_show(&world, arc.shape)

    build_shape_world_draw_cache(&world, 1)

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

// Verify filled arcs and direct-reference tools publish existing draw variants and flags.
@(test)
world_render_builds_filled_arc_pen_and_compass_items :: proc(t: ^testing.T) {
    world: core.Shape_World
    filled, filled_status := world_create_filled_arc(&world, {
        center = {0, 0, 0}, radius = 1, start_theta = 0,
        end_theta = 1, style = Shape_Style{}})
    pen, pen_status := world_create_pen(&world, {
        joint1 = {2, 0, 0}, joint2 = {3, 0, 0}, length = 1,
        style = Shape_Style{}})
    compass, compass_status := world_create_compass(&world, {
        joint1 = {4, 0, 0}, pivot = {5, 0, 0}, joint2 = {6, 0, 0},
        limb_length = 1, style = Shape_Style{}})
    testing.expect_value(t, filled_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, pen_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, compass_status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, filled.shape)
    world_render_test_show(&world, pen.shape)
    world_render_test_show(&world, compass.shape)

    build_shape_world_draw_cache(&world, 1)

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
    world: core.Shape_World
    positions := [4]Vector3{{0, 0, 0}, {2, 0, 0}, {2, 2, 0}, {0, 2, 0}}
    square, status := world_create_square(&world, positions, Shape_Style{})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, square.shape)

    build_shape_world_draw_cache(&world, 1)

    testing.expect_value(t, world.draw_cache.item_count, 1)
    testing.expect_value(t, world.draw_cache.polygon_vertex_count, 4)
    testing.expect_value(t, world.draw_cache.polygon_triangle_count, 2)
    for position, index in positions {
        testing.expect_value(t, world.draw_cache.polygon_vertices[index], position)
    }
}

// Verify Unicode label metadata resolves immutable source while the packet is live.
@(test)
world_render_resolves_unicode_label_source_metadata :: proc(t: ^testing.T) {
    world: core.Shape_World
    label, status := world_create_label(&world, {
        source = "∠A′", mime = .Text_Plain, position = {1, 2, 0},
        style = Shape_Style{}})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, label.entity)

    build_shape_world_draw_cache(&world, 1)

    item := world.draw_cache.items[0]
    #partial switch typed in item {
    case Shapes_Label_Draw:
        source, found := shape_world_draw_label_source(&world, typed)
        testing.expect(t, found)
        testing.expect_value(t, source, "∠A′")
        testing.expect_value(t, typed.mime, core.Shape_Text_Mime.Text_Plain)
        testing.expect_value(t, typed.source_revision, u32(1))
    case:
        testing.expect(t, false, "expected label draw item")
    }
}

// Verify world packet sorting retains the existing representative-depth strategy.
@(test)
world_render_sorts_nonflat_items_by_visual_depth :: proc(t: ^testing.T) {
    world: core.Shape_World
    lower, _ := world_create_point(&world, {0, 0, 2}, Shape_Style{})
    higher, _ := world_create_point(&world, {4, 0, 1}, Shape_Style{})
    world_render_test_show(&world, lower.entity)
    world_render_test_show(&world, higher.entity)

    build_shape_world_draw_cache(&world, 1)

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
    world: core.Shape_World
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    label, status := world_create_label(&world, {
        source = "α", mime = .Text_Plain, style = Shape_Style{}})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_render_test_show(&world, label.entity)
    build_shape_world_draw_cache(&world, 1)
    testing.expect_value(t, world.draw_cache.item_count, 1)
    testing.expect_value(t, world.draw_cache.label_byte_count, u16(0))

    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)

    testing.expect_value(t, world.draw_cache.item_count, 0)
    testing.expect_value(t, world.draw_cache.label_byte_count, u16(0))
    testing.expect_value(t, world.draw_cache.polygon_vertex_count, 0)
}