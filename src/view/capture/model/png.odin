package capturemodel

// Png_Capture_Phase describes one bounded, display-owned current-frame request.
Png_Capture_Phase :: enum {
    Idle,
    Pending,
    Saved,
    Error,
}

// Png_Capture_Status retains the last published path independently of current work.
Png_Capture_Status :: struct {
    phase: Png_Capture_Phase,
    last_path: [GIF_PATH_CAPACITY]u8,
    path_len: int,
    path_revision: u64,
    width: int,
    height: int,
}

// png_capture_available excludes pending PNG work and all active GIF capture intent.
png_capture_available :: proc(
    status: ^Png_Capture_Status, gif: Gif_Capture_View) -> bool {
    return status != nil && status.phase != .Pending &&
        !gif_capture_locks_playback_rate(gif.phase, gif.requested)
}

// png_capture_request admits one frame without changing any playback state.
png_capture_request :: proc(
    status: ^Png_Capture_Status, gif: Gif_Capture_View) -> bool {
    if !png_capture_available(status, gif) {
        return false
    }
    status.phase = .Pending
    return true
}

// png_capture_path borrows the last successful path until its next publication.
png_capture_path :: proc(status: ^Png_Capture_Status) -> string {
    return string(status.last_path[:status.path_len])
}
