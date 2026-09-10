package viewgraphics

import termattachment "../../terminal/attachment"

PLAYBACK_TRANSITION_LIMIT :: 64

// Display-owned shared playback state for one exact attachment generation.
Playback_Entry :: struct {
    attachment_id: termattachment.Attachment_Id,
    frame_index: int,
    completed_cycles: u64,
    deadline_ns: u64,
    remaining_ns: u64,
    visible_epoch: u64,
    active: bool,
    paused: bool,
    stopped: bool,
    loading: bool,
    completed: bool,
}

// Transactional frame-selection result committed only after texture upload.
Playback_Plan :: struct {
    candidate: Playback_Entry,
    transition_count: int,
    frame_changed: bool,
    valid: bool,
}

// Add one frame duration to display time without wrapping.
playback_deadline :: proc(now_ns, duration_ns: u64) -> u64 {
    if duration_ns > max(u64) - now_ns { return max(u64) }
    return now_ns + duration_ns
}

// Initialize playback at frame zero for one published immutable timeline.
playback_begin :: proc(
    id: termattachment.Attachment_Id, animation: termattachment.Animation_View,
    now_ns: u64) -> (Playback_Entry, bool) {
    if id.generation == 0 || len(animation.frames) == 0 ||
        animation.timeline.frame_count != len(animation.frames) {
        return {}, false
    }
    return {
        attachment_id = id,
        deadline_ns = playback_deadline(now_ns, animation.frames[0].duration_ns),
        active = true,
    }, true
}

// Plan bounded due transitions without mutating the committed playback entry.
playback_entry_valid :: proc(
    entry: Playback_Entry, animation: termattachment.Animation_View) -> bool {
    return entry.active && entry.attachment_id.generation != 0 && !entry.paused &&
        !entry.stopped && !entry.completed && len(animation.frames) > 0 &&
        entry.frame_index >= 0 && entry.frame_index < len(animation.frames) &&
        animation.timeline.frame_count == len(animation.frames)
}

// Plan bounded due transitions without mutating the committed playback entry.
//
// Returns:
//   - A valid candidate, including finite completion at the retained final frame.
//   - `frame_changed` only when texture pixels must be uploaded before commit.
playback_plan :: proc(
    entry: Playback_Entry, animation: termattachment.Animation_View,
    now_ns: u64) -> Playback_Plan {
    if !playback_entry_valid(entry, animation) {
        return {candidate = entry, valid = entry.active}
    }
    candidate := entry
    original_frame := entry.frame_index
    transition_count := 0
    for _ in 0..<PLAYBACK_TRANSITION_LIMIT {
        if now_ns < candidate.deadline_ns { break }
        if candidate.frame_index + 1 < len(animation.frames) {
            candidate.frame_index += 1
        } else if candidate.loading {
            break
        } else if !animation.timeline.infinite &&
            candidate.completed_cycles >= u64(animation.timeline.repeat_count) {
            candidate.completed = true
            break
        } else {
            candidate.frame_index = 0
            candidate.completed_cycles += 1
        }
        candidate.deadline_ns = playback_deadline(
            candidate.deadline_ns,
            animation.frames[candidate.frame_index].duration_ns)
        transition_count += 1
    }
    return {
        candidate = candidate,
        transition_count = transition_count,
        frame_changed = candidate.frame_index != original_frame,
        valid = true,
    }
}

// Freeze one timeline while retaining its exact remaining frame duration.
playback_pause :: proc(entry: ^Playback_Entry, now_ns: u64) {
    if entry == nil || !entry.active || entry.paused || entry.completed { return }
    entry.remaining_ns = entry.deadline_ns - now_ns if now_ns < entry.deadline_ns else 0
    entry.paused = true
}

// Resume one frozen timeline without applying elapsed wall-clock catch-up.
playback_resume :: proc(entry: ^Playback_Entry, now_ns: u64) {
    if entry == nil || !entry.active || !entry.paused || entry.completed { return }
    entry.deadline_ns = playback_deadline(now_ns, entry.remaining_ns)
    entry.remaining_ns = 0
    entry.paused = false
}

// Apply one completed draw epoch without charging hidden wall-clock time.
playback_visibility_commit :: proc(
    entry: ^Playback_Entry, completed_epoch, now_ns: u64) {
    if entry == nil || !entry.active { return }
    if entry.visible_epoch == completed_epoch {
        playback_resume(entry, now_ns)
    } else {
        playback_pause(entry, now_ns)
    }
}