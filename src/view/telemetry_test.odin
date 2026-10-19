package view

import testing "core:testing"
import viewtelemetry "telemetry"
import telemetrymodel "telemetry/model"

// Keep startup at zero and publish independent peaks only at the exact boundary.
@(test)
particle_counts_publish_completed_interval_peaks :: proc(t: ^testing.T) {
    intervals: telemetrymodel.Particle_Count_Intervals
    period := telemetrymodel.PARTICLE_COUNT_INTERVAL_NS
    start := u64(123)
    viewtelemetry.collect_particle_counts(&intervals, start, {9, 1, 3})
    viewtelemetry.collect_particle_counts(&intervals, start + period - 1,
        {4, 8, 6})
    testing.expect_value(t, intervals.published, telemetrymodel.Particle_Counts{})
    viewtelemetry.collect_particle_counts(&intervals, start + period,
        {100, 200, 400})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{9, 8, 6})
    testing.expect_value(t, intervals.collecting,
        telemetrymodel.Particle_Counts{100, 200, 400})
    viewtelemetry.collect_particle_counts(&intervals, start + period + 1, {})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{9, 8, 6})
    viewtelemetry.collect_particle_counts(&intervals, start + 2 * period, {})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{100, 200, 400})
    viewtelemetry.collect_particle_counts(&intervals, start + 3 * period, {})
    testing.expect_value(t, intervals.published, telemetrymodel.Particle_Counts{})
}

// Late display frames preserve fixed boundaries rather than restarting the timer.
@(test)
particle_counts_preserve_interval_cadence :: proc(t: ^testing.T) {
    intervals: telemetrymodel.Particle_Count_Intervals
    period := telemetrymodel.PARTICLE_COUNT_INTERVAL_NS
    viewtelemetry.collect_particle_counts(&intervals, 0, {10, 20, 40})
    viewtelemetry.collect_particle_counts(&intervals, period + period / 4,
        {4, 3, 1})
    testing.expect_value(t, intervals.started_at, period)
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{10, 20, 40})
    viewtelemetry.collect_particle_counts(&intervals, 2 * period - 1, {})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{10, 20, 40})
    viewtelemetry.collect_particle_counts(&intervals, 2 * period, {})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{4, 3, 1})
}

// A display stall cannot carry stale observations into unsampled completed intervals.
@(test)
particle_counts_expire_unsampled_intervals :: proc(t: ^testing.T) {
    intervals: telemetrymodel.Particle_Count_Intervals
    period := telemetrymodel.PARTICLE_COUNT_INTERVAL_NS
    viewtelemetry.collect_particle_counts(&intervals, 0, {100, 200, 400})
    viewtelemetry.collect_particle_counts(&intervals, 3 * period + period / 2,
        {1, 2, 4})
    testing.expect_value(t, intervals.published, telemetrymodel.Particle_Counts{})
    testing.expect_value(t, intervals.started_at, 3 * period)
    viewtelemetry.collect_particle_counts(&intervals, 4 * period, {})
    testing.expect_value(t, intervals.published,
        telemetrymodel.Particle_Counts{1, 2, 4})
}
