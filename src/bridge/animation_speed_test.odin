#+test
package bridge

import bridgemodel "model"
import animationmodel "../core/animation"
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
    slot := new(bridgemodel.Animation_Tick_Slot, context.allocator)
    defer free(slot, context.allocator)
    for rate in animationmodel.Playback_Rate {
        scale := animationmodel.playback_rate_multiplier(rate)
        service.animation_progress = 1
        service.animation_tick_pending = true
        service.animation_accumulated_dt = 0
        service.animation_accumulated_authored_dt = 0
        service.animation_accumulated_accelerated = false
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
    slot := new(bridgemodel.Animation_Tick_Slot, context.allocator)
    defer free(slot, context.allocator)
    coalesce_animation_tick(service, 0.03125, 0.125, true)
    coalesce_animation_tick(service, 0.03125, 0.03125, false)
    testing.expect_value(t, service.animation_accumulated_dt, f32(0.0625))
    testing.expect_value(t, service.animation_accumulated_authored_dt, f32(0.15625))
    fill_animation_tick_slot(state, slot, service.animation_accumulated_dt,
        service.animation_accumulated_authored_dt,
        service.animation_accumulated_accelerated)
    rollback_animation_tick_slot(service, slot, slot.maintenance_dt)
    testing.expect_value(t, service.animation_accumulated_authored_dt, f32(0.15625))
    testing.expect(t, !bridgemodel.animation_capture_rate_ready(service))
    coalesce_animation_tick(service, 0.2, 0.8, true)
    testing.expect_value(t,
        service.animation_accumulated_dt, MAX_ACCUMULATED_ANIMATION_DT)
    testing.expect_value(t, service.animation_accumulated_authored_dt,
        MAX_ACCUMULATED_ANIMATION_DT)
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
