package modifier

import testing "core:testing"
import math "core:math"

// Build a bounded point recipe with the same pen and point styling as REPL.
recipe_test_point :: proc(kind: Modifier_Kind = .Construct_Point) -> Modifier_Request {
    return {
        kind = kind,
        entity = 7,
        duration = 1,
        start_position = {0.25, 0.3, 0},
        radius = 0.35,
        brush = 0.08,
        color_packed = 0x123456ff,
    }
}

// Build a directed line recipe with stable host and endpoint identities.
recipe_test_line :: proc() -> Modifier_Request {
    return {
        kind = .Construct_Line,
        entity = 8,
        second_entity = 9,
        third_entity = 10,
        duration = 1,
        start_position = {0.2, 0.3, 0},
        second_position = {0.8, 0.7, 0},
        radius = 0.35,
        brush = 0.04,
        color_packed = 0xabcdef12,
    }
}

// Build a circle or sector recipe with explicit compass-joint identities.
recipe_test_circle :: proc(kind: Modifier_Kind) -> Modifier_Request {
    return {
        kind = kind,
        entity = 11,
        second_entity = 12,
        third_entity = 13,
        duration = 1,
        start_position = {0.4, 0.5, 0},
        second_position = {0.6, 0.5, 0},
        angle = f32(math.PI * 1.5),
        radius = 0.2,
        brush = 0.03,
        color_packed = 0x345678ff,
        flag = true,
    }
}

// Find one output of a requested kind and entity in a bounded recipe sample.
recipe_test_output :: proc(
    output: ^Modifier_Output_Buffer, kind: Modifier_Output_Kind,
    entity: u64) -> (Modifier_Output, bool) {
    for value in output^.outputs[:output^.count] {
        if value.kind == kind && value.entity == entity {
            return value, true
        }
    }
    return {}, false
}

// Preserve outer REPL timing, pen length, appearance, contact and final point state.
@(test)
native_point_recipe_preserves_repl_phases_and_final_geometry :: proc(t: ^testing.T) {
    request := recipe_test_point()
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 3)
    testing.expect_value(t, output.outputs[0].position.z, f32(REPL_TOOL_TRAVEL_TOP_Z))
    testing.expect(t, math.abs(output.outputs[1].position.z -
        f32(REPL_TOOL_TRAVEL_TOP_Z + request.radius)) < 1e-6)

    request.elapsed = REPL_DESCEND_SHARE
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].kind, Modifier_Output_Kind.Set_Tool_Lock)
    testing.expect(t, math.abs(output.outputs[1].position.x -
        request.start_position.x) < 1e-6)
    testing.expect(t, math.abs(output.outputs[1].position.y -
        request.start_position.y) < 1e-6)
    testing.expect(t, math.abs(output.outputs[1].position.z - request.radius) < 1e-6)

    request.elapsed = 0.3
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    _, point_visible := recipe_test_output(&output, .Set_Point_Visible, request.entity)
    _, particle := recipe_test_output(&output, .Emit_Trailing_Particle, 0)
    testing.expect(t, point_visible && particle)
    active, active_found := recipe_test_output(&output, .Set_Tool_Style, 0)
    testing.expect(t, active_found && active.integer == 1)

    request.elapsed = 1
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    point, found := recipe_test_output(&output, .Set_Point_Position, request.entity)
    testing.expect(t, found)
    testing.expect_value(t, point.position, request.start_position)
    tool, tool_found := recipe_test_output(&output, .Set_Tool_Visible, 0)
    testing.expect(t, tool_found && !tool.flag)
    testing.expect(t, output.count <= MODIFIER_OUTPUT_CAPACITY)
}

// Preserve directed line geometry and pen contact through skipped draw phases.
@(test)
native_line_recipe_preserves_contacts_and_skipped_final_geometry :: proc(t: ^testing.T) {
    request := recipe_test_line()
    output: Modifier_Output_Buffer
    request.elapsed = 0.3
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    first, first_found := recipe_test_output(&output, .Set_Point_Position,
        request.second_entity)
    second, second_found := recipe_test_output(&output, .Set_Point_Position,
        request.third_entity)
    testing.expect(t, first_found && second_found)
    testing.expect_value(t, first.position, request.start_position)
    expected_tip := request.start_position +
        (request.second_position - request.start_position) * f32(0.01 / 0.42)
    testing.expect(t, math.abs(second.position.x - expected_tip.x) < 1e-6)
    testing.expect(t, math.abs(second.position.y - expected_tip.y) < 1e-6)
    _, particle := recipe_test_output(&output, .Emit_Trailing_Particle, 0)
    testing.expect(t, particle)

    request.elapsed = request.duration
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    second, second_found = recipe_test_output(&output, .Set_Point_Position,
        request.third_entity)
    testing.expect(t, second_found)
    testing.expect_value(t, second.position, request.second_position)
    tool, tool_found := recipe_test_output(&output, .Set_Tool_Visible, 0)
    testing.expect(t, tool_found && !tool.flag)

    request.duration = 0
    request.elapsed = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    second, second_found = recipe_test_output(&output, .Set_Point_Position,
        request.third_entity)
    testing.expect(t, second_found)
    testing.expect_value(t, second.position, request.second_position)
}

// Keep filled-sector reveal one-shot on draw entry, including skipped phase boundaries.
@(test)
native_filled_circle_recipe_preserves_reveal_and_radius_trail_modes :: proc(
    t: ^testing.T) {
    request := recipe_test_circle(.Construct_Filled_Circle)
    output: Modifier_Output_Buffer
    flags := construction_transition_flags(request.kind, 0, 0.2, 1)
    testing.expect_value(t, flags, CONSTRUCTION_DRAW_ENTRY_FLAG)
    request.elapsed = 0.2
    request.integer = flags
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    _, reveal := recipe_test_output(&output, .Reveal_Sweep, request.entity)
    testing.expect(t, reveal)
    tracer, tracer_found := recipe_test_output(&output, .Set_Tool_Lock,
        request.third_entity)
    testing.expect(t, tracer_found && tracer.integer == 1)

    flags = construction_transition_flags(request.kind, 0, 0.95, 1)
    testing.expect_value(t, flags, CONSTRUCTION_DRAW_ENTRY_FLAG)
    request.elapsed = 0.95
    request.integer = flags
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    _, reveal = recipe_test_output(&output, .Reveal_Sweep, request.entity)
    arc, arc_found := recipe_test_output(&output, .Set_Shape_Arc, request.entity)
    testing.expect(t, reveal && arc_found)
    testing.expect_value(t, arc.arc_sweep, request.angle)
    rise_pivot := output.outputs[output.count - 3]
    testing.expect_value(t, rise_pivot.kind, Modifier_Output_Kind.Set_Tool_Lock)
    testing.expect_value(t, rise_pivot.entity, request.second_entity)
    testing.expect(t, math.abs(rise_pivot.position.z -
        f32(REPL_TOOL_TRAVEL_TOP_Z * 0.75)) < 1e-6)
    rise_tracer := output.outputs[output.count - 2]
    testing.expect_value(t, rise_tracer.entity, request.third_entity)
    testing.expect(t, math.abs(rise_tracer.position.x -
        request.start_position.x) < 1e-6)
    testing.expect(t, math.abs(rise_tracer.position.y -
        (request.start_position.y - request.radius)) < 1e-6)
}

// Preserve the alternative radius-trail effect when sector formation is disabled.
@(test)
native_filled_circle_recipe_preserves_radius_trail_mode :: proc(t: ^testing.T) {
    request := recipe_test_circle(.Construct_Filled_Circle)
    request.flag = false
    request.elapsed = REPL_DESCEND_SHARE
    request.integer = CONSTRUCTION_DRAW_ENTRY_FLAG
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    _, reveal := recipe_test_output(&output, .Reveal_Sweep, request.entity)
    _, radial := recipe_test_output(&output, .Emit_Radial_Trail, 0)
    testing.expect(t, !reveal && radial)
}

// Validate one-shot phase flags for every typed construction recipe.
@(test)
native_construction_transition_flags_are_bounded_and_transactional :: proc(
    t: ^testing.T) {
    kinds: [4]Modifier_Kind = {
        .Construct_Point, .Construct_Line,
        .Construct_Circle, .Construct_Filled_Circle,
    }
    for kind in kinds {
        testing.expect_value(t, construction_transition_flags(kind, 0, 0.2, 1),
            CONSTRUCTION_DRAW_ENTRY_FLAG)
        testing.expect_value(t, construction_transition_flags(kind, 0.79, 1, 1),
            0)
        testing.expect_value(t, construction_transition_flags(kind, 0, 1, 1),
            CONSTRUCTION_DRAW_ENTRY_FLAG)
    }
    testing.expect_value(t, construction_transition_flags(.Draw_Point, 0, 1, 1), 0)
    testing.expect_value(t, construction_transition_flags(
        .Construct_Filled_Circle, 0, 0, 0),
        CONSTRUCTION_DRAW_ENTRY_FLAG)
}

// Keep ordinary circle geometry and compass pose consistent in the draw phase.
@(test)
native_circle_recipe_preserves_sweep_brush_color_and_tool_pose :: proc(t: ^testing.T) {
    request := recipe_test_circle(.Construct_Circle)
    request.elapsed = 0.5
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    arc, found := recipe_test_output(&output, .Set_Shape_Arc, request.entity)
    testing.expect(t, found)
    testing.expect_value(t, arc.arc_sweep, request.angle * 0.5)
    color, color_found := recipe_test_output(&output, .Set_Point_Color, request.entity)
    testing.expect(t, color_found)
    testing.expect_value(t, color.color_packed, request.color_packed)
    request.elapsed = 1
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    tool, tool_found := recipe_test_output(&output, .Set_Tool_Visible, 2)
    testing.expect(t, tool_found && !tool.flag)
    testing.expect(t, output.count <= MODIFIER_OUTPUT_CAPACITY)
}
