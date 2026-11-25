#+test
package julia_host

import bridgemodel "../model"
import animationmodel "../../core/animation"
import particles "../../particles"
import "core:testing"

// Each admitted slot freezes authored time independently of unscaled maintenance.
@(test)
animation_speed_freezes_exact_ratios_and_progress :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    defer animation_value_test_state_destroy(state)
    interface: bridgemodel.Euclid_Julia_Interface
    state.julia_interface = &interface
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    service.animation_generation = 4
    slot := new(bridgemodel.Animation_Tick_Slot, context.allocator)
    defer free(slot, context.allocator)
    for rate in animationmodel.Playback_Rate {
        scale := animationmodel.playback_rate_multiplier(rate)
        service.animation_progress = 1
        service.animation_tick_pending = true
        service.animation_accumulated_dt = 0
        service.animation_accumulated_authored_dt = 0
        service.animation_accumulated_accelerated = false
        service.animation_accumulated_interval_count = 0
        state.ui_runtime.playback.rate = rate
        testing.expect(t, !try_request_animation_tick(state, 0.03125))
        fill_animation_tick_slot(state, slot, service.animation_accumulated_dt,
            service.animation_accumulated_authored_dt,
            service.animation_accumulated_accelerated)
        testing.expect_value(t, slot.maintenance_dt, f32(0.03125))
        testing.expect_value(t, slot.dt, f32(0.03125)*scale)
        testing.expect_value(t, slot.effective_progress, 1 + f64(slot.dt))
        state.ui_runtime.playback.rate = animationmodel.playback_rate_next(rate)
        testing.expect_value(t, slot.dt, f32(0.03125)*scale)
        testing.expect_value(t, service.animation_progress, f64(1))
    }
}

// Pending GIF intent forces actual tick admission to 1x without replacing the selected rate.
@(test)
animation_speed_capture_overrides_admitted_time :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    defer animation_value_test_state_destroy(state)
    interface: bridgemodel.Euclid_Julia_Interface
    state.julia_interface = &interface
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    service.animation_tick_pending = true
    state.ui_runtime.playback.rate = .Quadruple
    state.gif_capture_status.save_gif_requested = true
    testing.expect(t, !try_request_animation_tick(state, 0.03125))
    testing.expect_value(t, service.animation_accumulated_dt, f32(0.03125))
    testing.expect_value(t, service.animation_accumulated_authored_dt, f32(0.03125))
    testing.expect(t, !service.animation_accumulated_accelerated)
    testing.expect_value(t, state.ui_runtime.playback.rate,
        animationmodel.Playback_Rate.Quadruple)
}

// Coalescing preserves intervals at their original rates, caps them, and rolls back both clocks.
@(test)
animation_speed_backlog_retains_mixed_rates_and_rollback :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    defer animation_value_test_state_destroy(state)
    interface: bridgemodel.Euclid_Julia_Interface
    state.julia_interface = &interface
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    service.animation_generation = 4
    slot := new(bridgemodel.Animation_Tick_Slot, context.allocator)
    defer free(slot, context.allocator)
    coalesce_animation_tick(service, 0.03125, 0.125, true, 1)
    coalesce_animation_tick(service, 0.03125, 0.03125, false, 2)
    testing.expect_value(t, service.animation_accumulated_dt, f32(0.0625))
    testing.expect_value(t, service.animation_accumulated_authored_dt, f32(0.15625))
    fill_animation_tick_slot(state, slot, service.animation_accumulated_dt,
        service.animation_accumulated_authored_dt,
        service.animation_accumulated_accelerated)
    testing.expect_value(t, slot.formation_interval_count, 2)
    service.animation_accumulated_interval_count = 0
    rollback_animation_tick_slot(service, slot, slot.maintenance_dt)
    testing.expect_value(t, service.animation_accumulated_authored_dt, f32(0.15625))
    testing.expect_value(t, service.animation_accumulated_interval_count, 2)
    testing.expect_value(t,
        service.animation_accumulated_intervals[1].authored_seconds, f64(0.03125))
    testing.expect(t, !bridgemodel.animation_capture_rate_ready(service))
    coalesce_animation_tick(service, 0.2, 0.8, true)
    testing.expect_value(t,
        service.animation_accumulated_dt, MAX_ACCUMULATED_ANIMATION_DT)
    testing.expect_value(t, service.animation_accumulated_authored_dt,
        MAX_ACCUMULATED_ANIMATION_DT)
}

// Pause drops queued Julia time but preserves coverage for an already accepted native step.
@(test)
animation_pause_discards_only_unsubmitted_interval_time :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    defer animation_value_test_state_destroy(state)
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    service.animation_generation = 7
    particles.formation_reset_generation(&state.particle_system, 7)
    coalesce_animation_tick(service, 0.1, 0.1, false, 1)
    testing.expect_value(t, service.animation_accumulated_interval_count, 1)
    testing.expect_value(t, particles.formation_accept_native_interval(
        &state.particle_system, 7, 1, 0.1),
        particles.Formation_Time_Status.Accepted)
    clear_animation_accumulated_time(service)
    testing.expect_value(t, service.animation_accumulated_interval_count, 0)
    intervals: [1]particles.Formation_Time_Interval = {
        {
            step = 1,
            generation = 7,
            authored_seconds = 0.1,
        },
    }
    progress, valid := particles.formation_reconcile_julia_intervals(
        &state.particle_system, 7, intervals[:])
    testing.expect(t, valid)
    testing.expect_value(t, progress, f64(0.1))
}

// Recording must wait until accelerated backlog, reservations, and last publication retire.
@(test)
animation_speed_capture_waits_for_clean_publication :: proc(t: ^testing.T) {
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    testing.expect(t, bridgemodel.animation_capture_rate_ready(service))
    service.animation_tick_slots[0].state = .Pending
    service.animation_tick_slots[0].accelerated = true
    testing.expect(t, !bridgemodel.animation_capture_rate_ready(service))
    service.animation_tick_slots[0].state = .Free
    service.animation_last_commit_accelerated = true
    testing.expect(t, !bridgemodel.animation_capture_rate_ready(service))
    service.animation_last_commit_accelerated = false
    testing.expect(t, bridgemodel.animation_capture_rate_ready(service))
}
