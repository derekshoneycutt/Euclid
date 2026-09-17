package rendermetrics

import "core:testing"

// Verify frame reset preserves cumulative and high-water renderer evidence.
@(test)
metrics_accumulate_and_reset_frame_values :: proc(t: ^testing.T) {
    state: State
    record(&state, .Shape_Items, 3)
    record(&state, .Shape_Items, 2)
    end_frame(&state)

    testing.expect_value(t, value(&state.frame, .Shape_Items), u64(5))
    testing.expect_value(t, value(&state.cumulative, .Shape_Items), u64(5))
    testing.expect_value(t, value(&state.high_water, .Shape_Items), u64(5))
    testing.expect_value(t, state.completed_frame_count, u64(1))

    begin_frame(&state)
    record(&state, .Shape_Items, 2)
    end_frame(&state)
    testing.expect_value(t, value(&state.frame, .Shape_Items), u64(2))
    testing.expect_value(t, value(&state.cumulative, .Shape_Items), u64(7))
    testing.expect_value(t, value(&state.high_water, .Shape_Items), u64(5))
}

// Verify overflow saturates counters and classified failures remain observable.
@(test)
metrics_report_overflow_and_failures :: proc(t: ^testing.T) {
    state: State
    record(&state, .Upload_Bytes, max(u64))
    record(&state, .Upload_Bytes)
    record_failure(&state, .Encoding_Failures)

    testing.expect_value(t, value(&state.frame, .Upload_Bytes), max(u64))
    testing.expect_value(t, value(&state.cumulative, .Upload_Bytes), max(u64))
    testing.expect_value(t, state.overflow_count, u64(2))
    testing.expect_value(t, state.failure_count, u64(1))
    testing.expect_value(t, value(&state.frame, .Encoding_Failures), u64(1))
}