package view

import "../core"
import "../dynview"
import "../particles"
import "../shapes"
import "./ui"

import "core:os"
import "core:thread"

SIMULATION_TASK_COUNT :: 2

Simulation_Task_Data :: core.Simulation_Task_Data
Frame_Preparation_Task_Data :: core.Frame_Preparation_Task_Data
Simulation_Executor :: core.Simulation_Executor

//   Create and start the persistent fixed-step worker pool.
create_simulation_executor :: proc(
    state: ^Euclid_General_State) -> ^Simulation_Executor {

    executor := new(Simulation_Executor)
    executor^.particle_task.state = state
    executor^.constraint_task.state = state
    executor^.shape_cache_task.state = state
    executor^.dynview_task.state = state
    worker_count := max(os.get_processor_core_count(), 1)
    thread.pool_init(&executor^.pool, os.heap_allocator(), worker_count)
    reserve(&executor^.pool.tasks_done, SIMULATION_TASK_COUNT)
    thread.pool_start(&executor^.pool)
    return executor
}

//   Finish queued simulation work and release persistent worker resources.
destroy_simulation_executor :: proc(executor: ^Simulation_Executor) {
    if executor == nil {
        return
    }
    thread.pool_join(&executor^.pool)
    thread.pool_destroy(&executor^.pool)
    free(executor)
}

//   Run one particle-system fixed step on a simulation worker.
update_particles_task :: proc(task: thread.Task) {
    data := cast(^Simulation_Task_Data)task.data
    particles.update_particles(data^.state^.particle_system, data^.dt)
}

//   Solve point-system constraints on a simulation worker.
solve_constraints_task :: proc(task: thread.Task) {
    data := cast(^Simulation_Task_Data)task.data
    shapes.apply_all_constraints_to_error(
        data^.state^.point_system, ALLOWED_CONSTRAINT_ERROR)
}

//   Build interpolated shape draw data on a frame-preparation worker.
build_shape_cache_task :: proc(task: thread.Task) {
    data := cast(^Frame_Preparation_Task_Data)task.data
    shapes.build_draw_cache(data^.state^.point_system, data^.interpolation_alpha)
}

//   Compile invalidated Dynview text and layout caches on a frame-preparation worker.
compile_dynview_task :: proc(task: thread.Task) {
    data := cast(^Frame_Preparation_Task_Data)task.data
    dynview.compile_if_needed(&data^.state^.dynview)
}

//   Wait for every task in the current batch and drain its completion record.
join_simulation_tasks :: proc(executor: ^Simulation_Executor, task_count: int) {
    completed := 0
    for completed < task_count {
        if _, ok := thread.pool_pop_done(&executor^.pool); ok {
            completed += 1
        } else {
            thread.yield()
        }
    }
}

//   Submit independent fixed-step systems and wait for the complete batch.
run_parallel_simulation_step :: proc(executor: ^Simulation_Executor, dt: f32) {
    assert(executor != nil)
    executor^.particle_task.dt = dt
    executor^.constraint_task.dt = dt
    allocator := os.heap_allocator()
    thread.pool_add_task(&executor^.pool, allocator, update_particles_task,
        rawptr(&executor^.particle_task))
    thread.pool_add_task(&executor^.pool, allocator, solve_constraints_task,
        rawptr(&executor^.constraint_task))
    join_simulation_tasks(executor, SIMULATION_TASK_COUNT)
}

//   Prepare frame-owned shape and text caches concurrently before rendering.
run_parallel_frame_preparation :: proc(state: ^core.Euclid_General_State, alpha: f32) {
    assert(state != nil && state^.simulation_executor != nil)
    executor := state^.simulation_executor
    executor^.shape_cache_task.interpolation_alpha = alpha
    allocator := os.heap_allocator()

    thread.pool_add_task(&executor^.pool, allocator, build_shape_cache_task,
        rawptr(&executor^.shape_cache_task))
    task_count := 1
    if ui.prepare_ui_frame(state) {
        thread.pool_add_task(&executor^.pool, allocator, compile_dynview_task,
            rawptr(&executor^.dynview_task))
        task_count += 1
    }

    join_simulation_tasks(executor, task_count)
}