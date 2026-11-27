package viewsimulation

import core "../../core"
import geometry "../../core/geometry"
import shapemodel "../../shapes/model"
import testing "core:testing"

// Preview only the matching generation-qualified point in the joined draw packet.
@(test)
builder_preview_changes_only_frame_local_point :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    entity: shapemodel.Shape_Entity = {
        slot = 2,
        generation = 3,
    }
    state^.builder.point_count = 1
    state^.builder.points[0] = {
        entity = shapemodel.shape_entity_pack(entity),
        position = {0.2, 0.3, 0},
        preview_active = true,
        preview_position = {0.4, 0.5, 0},
    }
    cache := &state^.shape_world.draw_cache
    cache^.item_count = 2
    cache^.items[0] = shapemodel.Shapes_Point_Draw{
        base = {
            source_index = 1,
            source_generation = 3,
        },
        point1 = {0.2, 0.3, 0},
    }
    cache^.items[1] = shapemodel.Shapes_Point_Draw{
        base = {
            source_index = 1,
            source_generation = 4,
        },
        point1 = {0.1, 0.1, 0},
    }
    builder_apply_point_previews(state)
    first, first_ok := cache^.items[0].(shapemodel.Shapes_Point_Draw)
    second, second_ok := cache^.items[1].(shapemodel.Shapes_Point_Draw)
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, first.point1, state^.builder.points[0].preview_position)
    testing.expect_value(t, second.point1, geometry.Vector3{0.1, 0.1, 0})
    testing.expect_value(t, state^.builder.points[0].position,
        geometry.Vector3{0.2, 0.3, 0})
}
