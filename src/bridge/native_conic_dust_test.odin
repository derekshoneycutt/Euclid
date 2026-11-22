package bridge

import modifier "../animation"
import particles "../particles"
import curve "../shapes/curve"
import "core:testing"

// Prove ordinary contact impulses push existing dust outward from the nib, not the vertex.
@(test)
native_parabola_nib_pushes_grounded_dust :: proc(t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    _ = set_parabola_tool_geometry(state, {0.1, 0.2, 0, -1, 1, 0})
    host := shape_create_parabola(state, {0.4, 0.4, 0},
        {0.1, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    request: modifier.Modifier_Request = {
        kind = .Parabola_Draw,
        entity = host.shape,
        start_position = {0.4, 0.4, 0},
        third_position = {-1, 0, 1},
        radius = 0.1,
        elapsed = 1,
        duration = 1,
    }
    ps := &state.particle_system
    left := 150 * particles.DUST_FIELD_DIM + 124
    right := left + 2
    ps.dust_field.density[left], ps.dust_field.density[right] = 1, 1
    ps.dust_field.support_bounds = {124, 150, 126, 150, true}
    native_conic_test_sample(t, state, request)
    testing.expect_value(t, ps.dust_tool_contact_count, 1)
    testing.expect_value(t, ps.dust_tool_contacts[0].endpoint,
        curve.parabola_point(request.start_position, {
            focal_distance = 0.1,
        }, 1))
    particles.apply_dust_tool_contacts_to_field(ps)
    testing.expect(t, ps.dust_field.momentum_x[left] < 0)
    testing.expect(t, ps.dust_field.momentum_x[right] > 0)
    testing.expect_value(t, ps.dust_tool_contact_overflow_count, 0)
}

// Reject a full contact queue before changing the apparatus or analytic frontier.
@(test)
native_parabola_contact_admission_is_transactional :: proc(t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    host := shape_create_parabola(state, {0.4, 0.5, 0},
        {0.075, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    command, captured := append_scene_command(state, .Apply_Native_Modifier)
    testing.expect(t, captured)
    command.modifier = {
        kind = .Parabola_Draw,
        entity = host.shape,
        start_position = {0.4, 0.5, 0},
        third_position = {-1, 0, 1},
        radius = 0.075,
        elapsed = 1,
        duration = 1,
    }
    end_scene_command_batch(state)
    testing.expect_value(t, scene_command_batch_tool_contact_count(&batch), 1)
    state.particle_system.dust_tool_contact_count = particles.DUST_TOOL_CONTACT_CAP
    before := state.shape_world.parabola_tools.values[0]
    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t, state.shape_world.parabola_tools.values[0], before)
    testing.expect_value(t,
        shape_get_parabola(state, host.shape).geometry.draw_parameter, f32(-1))
    testing.expect_value(t, state.particle_system.dust_tool_contact_overflow_count, 0)
}

// Contact follows only selected floor nibs; elevated drawing and all travel stay contact-free.
@(test)
native_conic_contact_count_respects_branches_and_elevation :: proc(t: ^testing.T) {
    request: modifier.Modifier_Request = {
        kind = .Hyperbola_Draw,
        entity = 1,
        radius = 0.12,
        displacement = {0.1, 0, 0},
        third_position = {-1, 0, 1},
        duration = 1,
        elapsed = 0.5,
    }
    for selection in 0..<3 {
        request.integer = selection
        expected := selection == 0 ? 2 : 1
        testing.expect_value(t, native_modifier_tool_contact_count(request), expected)
    }
    request.start_position.z = 0.1
    testing.expect_value(t, native_modifier_tool_contact_count(request), 0)
    request.start_position.z = 0
    kinds := [?]modifier.Modifier_Kind{
        .Parabola_Place, .Parabola_Descend, .Parabola_Rise,
        .Hyperbola_Place, .Hyperbola_Descend, .Hyperbola_Rise,
    }
    for kind in kinds {
        request.kind = kind
        testing.expect_value(t, native_modifier_tool_contact_count(request), 0)
    }
}
