package rendermetrics

// Metric identifies one stable renderer workload, submission, or failure counter.
Metric :: enum u8 {
    Shape_Items,
    Curve_Vertices,
    Polygon_Vertices,
    Polygon_Triangles,
    Projected_Vertices,
    Generated_Vertices,
    Generated_Indices,
    Primitive_Submissions,
    Rlgl_Batches,
    Draw_Calls,
    Clip_Changes,
    Shader_Changes,
    Texture_Changes,
    Blend_Changes,
    Dust_Instances,
    Dust_Fallback_Quads,
    Upload_Bytes,
    Fallback_Selections,
    Readback_Bytes,
    Readback_Failures,
    Normalization_Bytes,
    Normalization_Failures,
    Encoded_Frames,
    Encoding_Failures,
}

METRIC_COUNT :: int(Metric.Encoding_Failures) + 1

METRIC_NAMES_JSON ::
    `["shape_items","curve_vertices","polygon_vertices","polygon_triangles",` +
    `"projected_vertices","generated_vertices","generated_indices",` +
    `"primitive_submissions","rlgl_batches","draw_calls","clip_changes",` +
    `"shader_changes","texture_changes","blend_changes","dust_instances",` +
    `"dust_fallback_quads","upload_bytes","fallback_selections",` +
    `"readback_bytes","readback_failures","normalization_bytes",` +
    `"normalization_failures","encoded_frames","encoding_failures"]`

// Snapshot stores fixed renderer counters for one aggregation interval.
Snapshot :: struct {
    values: [METRIC_COUNT]u64,
}

// State retains current-frame, cumulative, and frame-high-water renderer evidence.
State :: struct {
    frame: Snapshot,
    cumulative: Snapshot,
    high_water: Snapshot,
    overflow_count: u64,
    failure_count: u64,
    completed_frame_count: u64,
}

// begin_frame clears transient values while preserving session evidence.
begin_frame :: proc(state: ^State) {
    state^.frame = {}
}

// record adds one value with saturation and records arithmetic pressure explicitly.
record :: proc(state: ^State, metric: Metric, amount: u64 = 1) {
    index := int(metric)
    frame_value, frame_overflowed := saturating_add(
        state^.frame.values[index], amount)
    state^.frame.values[index] = frame_value
    if frame_overflowed {
        state^.overflow_count += 1
    }
    cumulative_value, cumulative_overflowed := saturating_add(
        state^.cumulative.values[index], amount)
    state^.cumulative.values[index] = cumulative_value
    if cumulative_overflowed {
        state^.overflow_count += 1
    }
}

// record_failure adds a classified failure and the aggregate failure count.
record_failure :: proc(state: ^State, metric: Metric) {
    record(state, metric)
    state^.failure_count, _ = saturating_add(state^.failure_count, 1)
}

// end_frame publishes per-metric high waters and advances the completed-frame count.
end_frame :: proc(state: ^State) {
    for value, index in state^.frame.values {
        state^.high_water.values[index] = max(
            state^.high_water.values[index], value)
    }
    state^.completed_frame_count, _ = saturating_add(
        state^.completed_frame_count, 1)
}

// value returns one metric from a borrowed snapshot.
value :: proc(snapshot: ^Snapshot, metric: Metric) -> u64 {
    return snapshot^.values[int(metric)]
}

// saturating_add preserves monotonic evidence when a counter exceeds u64 capacity.
saturating_add :: proc(left, right: u64) -> (u64, bool) {
    if right > max(u64) - left {
        return max(u64), true
    }
    return left + right, false
}