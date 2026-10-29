package protocol

import "core:unicode/utf8"

TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES :: 64 * 1024
TERMINAL_HIGHLIGHT_RUN_CAPACITY :: 4096
TERMINAL_HIGHLIGHT_MAILBOX_CAPACITY :: 8

// Stable source surface identity, independent of completion and evaluation.
Highlight_Target :: enum i32 {
    Live_Input,
    History_Entry,
    Persistent_History_Entry,
}

// Pointer-free identity mirrored by Julia's HighlightIdentity, including rejected modes.
Highlight_Identity :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    target_id: u64,
    source_revision: u64,
    face_generation: u64,
    target_kind: Highlight_Target,
    mode: i32,
}

// Source snapshot borrowed until its display-produced ingress envelope returns.
Highlight_Requested :: struct {
    identity: Highlight_Identity,
    source: string,
}

// Native interpretation of default, display-palette, and exact RGB colors.
Highlight_Color_Kind :: enum u8 {Default, Ansi, Rgb}

// Supported native weight and underline vocabularies, mirrored by Julia.
Highlight_Weight :: enum u8 {Normal, Bold, Dim}
Highlight_Underline :: enum u8 {None, Straight, Double, Curly, Dotted, Dashed}

// Pointer-free 28-byte run layout; offsets are zero-based, half-open UTF-8 bytes.
Highlight_Run :: struct {
    start_byte: u32,
    end_byte: u32,
    foreground: u32,
    background: u32,
    underline_color: u32,
    foreground_kind: Highlight_Color_Kind,
    background_kind: Highlight_Color_Kind,
    underline_color_kind: Highlight_Color_Kind,
    weight: Highlight_Weight,
    italic: u8,
    underline: Highlight_Underline,
    strikethrough: u8,
    inverse: u8,
}

// Complete source and runs borrowed until their Julia-produced envelope returns.
Highlight_Result :: struct {
    identity: Highlight_Identity,
    source: string,
    runs: []Highlight_Run,
}

// Stable terminal failures mirrored by Julia; no partial success is published.
Highlight_Failure_Reason :: enum i32 {
    Mailbox_Full = 1,
    Actor_Stopped,
    Runtime_Stopped,
    Internal_Failure,
    Duplicate_Request,
    Invalid_Request,
    Transport_Capacity,
}

// Rejection retains the original identity, never the host's current generation.
Highlight_Failed :: struct {
    identity: Highlight_Identity,
    reason: Highlight_Failure_Reason,
}

// Validate source identity and Normal mode at the typed request boundary.
highlight_request_valid :: proc(request: Highlight_Requested) -> bool {
    id := request.identity
    target_valid := id.target_kind == .Live_Input && id.target_id == 0 ||
        (id.target_kind == .History_Entry ||
         id.target_kind == .Persistent_History_Entry) && id.target_id > 0
    return id.request_id != 0 && id.animation_generation > 0 &&
        id.source_revision > 0 && id.face_generation > 0 &&
        id.mode == i32(Evaluation_Mode.Normal) && target_valid &&
        len(request.source) <= TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES &&
        utf8.valid_string(request.source)
}

// Validate one native color without admitting unknown kinds or oversized values.
highlight_color_valid :: proc(kind: Highlight_Color_Kind, value: u32) -> bool {
    switch kind {
    case .Default:
        return value == 0
    case .Ansi:
        return value <= 15
    case .Rgb:
        return value <= 0xffffff
    }
    return false
}

// Validate bounded appearance values independently of the renderer's capabilities.
highlight_run_style_valid :: proc(run: Highlight_Run) -> bool {
    return highlight_color_valid(run.foreground_kind, run.foreground) &&
        highlight_color_valid(run.background_kind, run.background) &&
        highlight_color_valid(run.underline_color_kind, run.underline_color) &&
        u8(run.weight) <= u8(Highlight_Weight.Dim) &&
        u8(run.underline) <= u8(Highlight_Underline.Dashed) &&
        run.italic <= 1 && run.strikethrough <= 1 && run.inverse <= 1
}

// Reject partial coverage, split codepoints, malformed values, or oversized results.
highlight_result_valid :: proc(result: Highlight_Result) -> bool {
    if !highlight_request_valid({
        identity = result.identity,
        source = result.source,
    }) || len(result.runs) > TERMINAL_HIGHLIGHT_RUN_CAPACITY {
        return false
    }
    offset := u32(0)
    for run in result.runs {
        if run.start_byte != offset || run.end_byte <= offset ||
            int(run.end_byte) > len(result.source) || !highlight_run_style_valid(run) {
            return false
        }
        if int(run.end_byte) < len(result.source) &&
            result.source[run.end_byte] & 0xc0 == 0x80 {
            return false
        }
        offset = run.end_byte
    }
    return int(offset) == len(result.source)
}
