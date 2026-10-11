package capturemodel

// Gif_Capture_Status owns display capture intent, policy progress and bounded feedback.
Gif_Capture_Status :: struct {
    save_gif_requested: bool,
    gif_downsample_factor: int,
    gif_frame_step: int,
    gif_timing_mode: Gif_Capture_Timing_Mode,
    gif_capture_phase: Gif_Capture_Phase,
    gif_capture_frame_counter: int,
    gif_captured_frames: int,
    gif_status_note: [260]u8,
    gif_status_note_len: int,
    last_gif_path: [GIF_PATH_CAPACITY]u8,
    last_gif_path_len: int,
    last_gif_path_revision: u64,
    last_gif_path_truncated: bool,
}

// Gif_Capture_View is the small immutable capture projection used by UI routing.
Gif_Capture_View :: struct {
    phase: Gif_Capture_Phase,
    requested: bool,
    path_available: bool,
}

// Copy capture routing facts without borrowing path buffers or mutable policy storage.
gif_capture_view :: proc(status: ^Gif_Capture_Status) -> Gif_Capture_View {
    return {
        phase = status^.gif_capture_phase,
        requested = status^.save_gif_requested,
        path_available = status^.last_gif_path_len > 0,
    }
}
