package view

import "../core"
import "../core/protocol"
import "core:testing"

// Verify the public default period maps to one Euclid fixed simulation step.
@(test)
terminal_tick_default_period_is_one_fixed_step :: proc(t: ^testing.T) {
    testing.expect_value(t, terminal_tick_interval_steps(16_666_666), u64(1))
    testing.expect_value(t, terminal_tick_interval_steps(16_666_667), u64(2))
}

// Verify tick configuration is scoped to the active Terminal generation.
@(test)
terminal_tick_configure_rejects_stale_generation :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal.initialized = true
    state^.terminal.animation_generation = 7

    testing.expect(t, !terminal_tick_configure(state, {
        animation_generation = 6,
        stream_generation = 1,
        requested_period_ns = 1,
    }))
    testing.expect(t, terminal_tick_configure(state, {
        animation_generation = 7,
        stream_generation = 1,
        requested_period_ns = 1,
    }))
    testing.expect_value(t, state^.terminal_tick_publisher.interval_steps, u64(1))
    testing.expect(t, state^.terminal_tick_publisher.acknowledgement_pending)
}

// Verify fixed steps coalesce into one bounded pulse after acknowledgement.
@(test)
terminal_tick_record_step_coalesces_one_pending_pulse :: proc(t: ^testing.T) {
    publisher := core.Terminal_Tick_Publisher{
        animation_generation = 9,
        stream_generation = 2,
        interval_steps = 2,
        active = true,
    }

    terminal_tick_record_step(&publisher, 11)
    terminal_tick_record_step(&publisher, 12)
    testing.expect(t, publisher.pulse_pending)
    testing.expect_value(t, publisher.pulse.first_simulation_tick, u64(11))
    testing.expect_value(t, publisher.pulse.last_simulation_tick, u64(12))
    testing.expect_value(t, publisher.pulse.step_count, u64(2))

    terminal_tick_record_step(&publisher, 13)
    testing.expect_value(t, publisher.pulse.last_simulation_tick, u64(13))
    testing.expect_value(t, publisher.pulse.step_count, u64(3))
}

// Verify stopping requires the exact stream and retains its final acknowledgement.
@(test)
terminal_tick_stop_retains_exact_stream_acknowledgement :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal_tick_publisher = {
        animation_generation = 12,
        stream_generation = 4,
        interval_steps = 1,
        active = true,
        pulse_pending = true,
    }

    testing.expect(t, !terminal_tick_stop(state,
        protocol.Tick_Stream_Stop_Requested{
            animation_generation = 12,
            stream_generation = 3,
        }))
    testing.expect(t, terminal_tick_stop(state,
        protocol.Tick_Stream_Stop_Requested{
            animation_generation = 12,
            stream_generation = 4,
        }))
    testing.expect(t, !state^.terminal_tick_publisher.active)
    testing.expect(t, !state^.terminal_tick_publisher.pulse_pending)
    testing.expect(t, state^.terminal_tick_publisher.acknowledgement_pending)
    testing.expect(t, !state^.terminal_tick_publisher.acknowledgement.active)
}
