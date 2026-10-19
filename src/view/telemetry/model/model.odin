package telemetrymodel

PARTICLE_COUNT_INTERVAL_NS :: u64(5_000_000_000)

// Particle_Counts holds independent world-render and live UI-dust observations.
Particle_Counts :: struct {
    dust: int,
    trail: int,
    ui_dust: int,
}

// Particle_Count_Intervals publishes only completed five-second peak observations.
Particle_Count_Intervals :: struct {
    initialized: bool,
    started_at: u64,
    collecting: Particle_Counts,
    published: Particle_Counts,
}

// Runtime retains display-owned renderer observations and rolling FPS buckets.
Runtime :: struct {
    particle_counts: Particle_Count_Intervals,
    colored_vertex_count: u32,
    colored_index_count: u32,
    curve_candidate_point_count: u32,
    curve_retained_point_count: u32,
    curve_retention_ratio: f32,
    colored_primitive_overflow_count: u32,
    fps_avg_bucket_seconds: [60]f32,
    fps_avg_bucket_frames: [60]int,
    fps_avg_bucket_cursor: int,
    fps_avg_bucket_elapsed: f32,
    fps_avg_rolling_seconds: f32,
    fps_avg_rolling_frames: int,
    fps_avg_live: f32,
}
