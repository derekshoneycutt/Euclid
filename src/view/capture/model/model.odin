package capturemodel

import time "core:time"

GIF_PATH_CAPACITY :: 4096

// Gif_Capture_Phase tracks display-owned GIF capture policy.
Gif_Capture_Phase :: enum {
    Idle,
    Armed,
    Recording,
    Finalizing,
    Saved,
    Error,
}

// Gif_Capture_Timing_Mode selects authored or observed playback timing.
Gif_Capture_Timing_Mode :: enum u8 {
    Animation,
    Recorded,
}

// Gif_Capture_Frame borrows one RGBA8 frame until the encoder stages its own copy.
Gif_Capture_Frame :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
}

// Gif_Capture_Operations supplies display-owned streaming encoder calls to policy.
Gif_Capture_Operations :: struct {
    user_data: rawptr,
    begin: proc(user_data: rawptr, width, height: int) -> bool,
    stage_frame: proc(user_data: rawptr, frame: Gif_Capture_Frame) -> bool,
    commit_frame: proc(user_data: rawptr, duration_ms: u64) -> bool,
    close: proc(user_data: rawptr) -> bool,
    abort: proc(user_data: rawptr),
    published_path: proc(user_data: rawptr) -> string,
}

// Gif_Capture_Session combines portable capture policy and encoder operations.
Gif_Capture_Session :: struct {
    operations: Gif_Capture_Operations,
    active: bool,
    source_width: int,
    source_height: int,
    output_width: int,
    output_height: int,
    started_at: time.Tick,
    active_downsample_factor: int,
    active_frame_step: int,
    active_timing_mode: Gif_Capture_Timing_Mode,
    staged: bool,
    staged_fixed_step: u64,
    staged_at: time.Tick,
    last_duration_ms: u64,
    frame_materialization_ms: f64,
    materialized_frames: u64,
    recording_presentations: u64,
    paused_presentations: u64,
}

// Bind a complete display-owned streaming encoder capability to one portable session.
gif_capture_bind_operations :: proc(
    session: ^Gif_Capture_Session, operations: Gif_Capture_Operations) -> bool {
    if session == nil || operations.begin == nil ||
       operations.stage_frame == nil || operations.commit_frame == nil ||
       operations.close == nil || operations.abort == nil ||
       operations.published_path == nil {
        return false
    }
    session.operations = operations
    return true
}
