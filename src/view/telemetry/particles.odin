package viewtelemetry

import telemetrymodel "model"

// collect_particle_counts holds completed interval peaks until the next boundary.
// Boundary samples belong to the new interval; unsampled completed intervals are zero.
collect_particle_counts :: proc(
    intervals: ^telemetrymodel.Particle_Count_Intervals,
    now: u64, counts: telemetrymodel.Particle_Counts) {
    if !intervals^.initialized {
        intervals^.initialized = true
        intervals^.started_at = now
    }
    elapsed := now - intervals^.started_at
    period := telemetrymodel.PARTICLE_COUNT_INTERVAL_NS
    if elapsed >= period {
        intervals^.published = intervals^.collecting
        if elapsed / period > 1 {
            intervals^.published = {}
        }
        intervals^.collecting = {}
        intervals^.started_at += (elapsed / period) * period
    }
    peaks := &intervals^.collecting
    peaks^.dust = max(peaks^.dust, counts.dust)
    peaks^.trail = max(peaks^.trail, counts.trail)
    peaks^.ui_dust = max(peaks^.ui_dust, counts.ui_dust)
}
