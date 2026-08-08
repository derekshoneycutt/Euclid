package view_tests

import app_core "../../src/core"
import app_view "../../src/view"

import "core:testing"
import "core:thread"

@(test)
parallel_simulation_step_joins_particle_and_constraint_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)

    particles := state^.particle_system
    particles^.use_max_dust_particles = 1
    particles^.low_particles.alive[0] = true
    particles^.low_particles.life[0] = 10
    particles^.low_particles.vel_x[0] = 0.25

    points := state^.point_system
    points^.points[0].position = app_core.Vector3{0, 0, -1}
    points^.constraints[0] = app_core.Shapes_Constraint{
        kind = .Floor,
        on_point = 0,
        restriction = app_core.Vector3{0, 0, 0},
        do_apply = true,
    }

    executor := app_view.create_simulation_executor(state)
    defer app_view.destroy_simulation_executor(executor)
    app_view.run_parallel_simulation_step(executor, 0.01)
    first_batch_x := particles^.low_particles.pos_x[0]
    app_view.run_parallel_simulation_step(executor, 0.01)

    testing.expect_value(t, first_batch_x, f32(0.25))
    testing.expect(t, particles^.low_particles.pos_x[0] > first_batch_x)
    position := points^.points[0].position.? or_else app_core.Vector3{}
    testing.expect_value(t, position.z, f32(0))
}

@(test)
parallel_frame_preparation_joins_shape_and_dynview_cache_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.point_system^.next_point_index = 1
    state^.point_system^.points[0].kind = .Point
    state^.point_system^.points[0].do_draw = true
    state^.point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    state^.dynview.enabled = true

    executor := app_view.create_simulation_executor(state)
    state^.simulation_executor = executor
    defer app_view.destroy_simulation_executor(executor)

    app_view.run_parallel_frame_preparation(state, 0.25)
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect(t, state^.dynview.compile_cache.is_valid)
    testing.expect(t, state^.dynview.compile_cache.layout_is_valid)
    testing.expect(t, thread.pool_is_empty(&executor^.pool))

    app_view.run_parallel_frame_preparation(state, 0.75)
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect(t, thread.pool_is_empty(&executor^.pool))
}