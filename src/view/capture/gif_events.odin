package viewcapture

import core "../../core"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import capturemodel "model"

//   Record a required semantic event when GIF capture changes lifecycle phase.
record_gif_capture_transition :: proc(
    state: ^core.Euclid_General_State,
    previous, current: capturemodel.Gif_Capture_Phase) {
    if state == nil || previous == current {
        return
    }
    kind := evidence_trace.Kind.Unknown
    flags: evidence_trace.Flags = {.Required}
    if previous == .Armed && current == .Recording {
        kind = .Gif_Started
    } else if previous == .Recording && current == .Saved {
        kind = .Gif_Completed
    } else if current == .Error &&
        (previous == .Armed || previous == .Recording || previous == .Finalizing) {
        kind = .Gif_Failed
        flags += {.Failure}
    } else {
        return
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = kind,
            correlation_kind = .Capture,
            correlation = state^.fixed_step,
            tick = state^.fixed_step,
            flags = flags,
        })
}
