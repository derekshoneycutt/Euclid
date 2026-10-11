package telemetrymodel

// Runtime retains display-owned renderer observations and rolling FPS buckets.
Runtime :: struct {
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
