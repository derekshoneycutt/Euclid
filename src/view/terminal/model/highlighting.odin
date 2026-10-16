package viewterminalmodel

import protocol "../../../core/protocol"
import termmodel "../../../terminal/model"

TERMINAL_HIGHLIGHT_HISTORY_CAPACITY :: 1280
TERMINAL_HIGHLIGHT_CACHE_CAPACITY :: 8
TERMINAL_HIGHLIGHT_LINE_CAPACITY :: 256
TERMINAL_HIGHLIGHT_PENDING_CAPACITY :: 4
TERMINAL_HIGHLIGHT_DEBOUNCE_SECONDS :: f64(0.12)

// A submitted hard line anchors source bytes to geometry-independent output provenance.
Terminal_Highlight_Line :: struct {
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    source_start: int,
    source_end: int,
}

// One retained hard-line anchor; source remains authoritative in identified termhist storage.
Terminal_Highlight_History :: struct {
    id: u64,
    history_index: int,
    line: Terminal_Highlight_Line,
    visible_epoch: u64,
}

Terminal_Highlight_Phase :: enum {Empty, Scheduled, Pending, Ready, Failed}

// Display-owned result slot; no slice into a bridge envelope survives publication.
Terminal_Highlight_Slot :: struct {
    identity: protocol.Highlight_Identity,
    phase: Terminal_Highlight_Phase,
    source_length: int,
    run_count: int,
    due: f64,
    visible_epoch: u64,
    source: [protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES]u8,
    runs: [protocol.TERMINAL_HIGHLIGHT_RUN_CAPACITY]protocol.Highlight_Run,
}

// Fixed generation-owned storage, including cancelled work still occupying the bridge.
Terminal_Highlighting :: struct {
    live: Terminal_Highlight_Slot,
    cache: [TERMINAL_HIGHLIGHT_CACHE_CAPACITY]Terminal_Highlight_Slot,
    history: [TERMINAL_HIGHLIGHT_HISTORY_CAPACITY]Terminal_Highlight_History,
    pending: [TERMINAL_HIGHLIGHT_PENDING_CAPACITY]protocol.Highlight_Identity,
    next_request_id: protocol.Request_Id,
    next_history_anchor: int,
    face_generation: u64,
    epoch: u64,
    observed_revision: u64,
    observed_mode: protocol.Evaluation_Mode,
    observed_editable: bool,
    recording: bool,
    recording_lines: [TERMINAL_HIGHLIGHT_LINE_CAPACITY]Terminal_Highlight_Line,
    recording_line_count: int,
    recording_offset: int,
    rejected_count: u64,
    stale_count: u64,
    failure_count: u64,
    eviction_count: u64,
    cache_saturated: bool,
}
