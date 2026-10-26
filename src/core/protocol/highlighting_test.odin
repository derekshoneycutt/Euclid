package protocol

import "core:testing"

// Build a complete live-input identity for bounded protocol fixtures.
highlight_test_identity :: proc() -> Highlight_Identity {
    return {
        request_id = 7,
        animation_generation = 3,
        source_revision = 2,
        face_generation = 1,
    }
}

// Verify pointer-free layouts agree with Julia's isbits transport records.
@(test)
highlight_transport_layout_matches_julia :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(Highlight_Identity), 48)
    testing.expect_value(t, offset_of(Highlight_Identity, target_kind), 40)
    testing.expect_value(t, offset_of(Highlight_Identity, mode), 44)
    testing.expect_value(t, size_of(Highlight_Run), 28)
    testing.expect_value(t, offset_of(Highlight_Run, foreground_kind), 20)
    testing.expect_value(t, offset_of(Highlight_Run, inverse), 27)
    testing.expect_value(t, TERMINAL_HIGHLIGHT_MAILBOX_CAPACITY, 8)
}

// Verify complete coverage, color bounds, UTF-8 alignment, and explicit modes.
@(test)
highlight_protocol_rejects_partial_or_invalid_results :: proc(t: ^testing.T) {
    runs: [2]Highlight_Run = {
        {
            start_byte = 0,
            end_byte = 2,
            foreground_kind = .Ansi,
            foreground = 1,
        },
        {
            start_byte = 2,
            end_byte = 3,
            foreground_kind = .Rgb,
            foreground = 0x123456,
        },
    }
    result: Highlight_Result = {
        identity = highlight_test_identity(),
        source = "αx",
        runs = runs[:],
    }
    testing.expect(t, highlight_result_valid(result))
    runs[0].end_byte = 1
    testing.expect(t, !highlight_result_valid(result))
    runs[0].end_byte = 2
    runs[1].start_byte = 1
    testing.expect(t, !highlight_result_valid(result))
    runs[1].start_byte = 2
    runs[1].foreground = 0x1000000
    testing.expect(t, !highlight_result_valid(result))
    runs[1].foreground = 0x123456
    runs[1].inverse = 2
    testing.expect(t, !highlight_result_valid(result))
    runs[1].inverse = 0
    result.identity.mode = i32(Evaluation_Mode.Shell)
    testing.expect(t, !highlight_result_valid(result))
    result.identity.mode = 0
    result.source = "\xffxx"
    testing.expect(t, !highlight_result_valid(result))
    testing.expect(t, highlight_result_valid({
        identity = highlight_test_identity(),
        source = "",
        runs = nil,
    }))
}

// Verify malformed targets and unsupported native style values cannot be published.
@(test)
highlight_protocol_validates_identity_and_style_vocabulary :: proc(t: ^testing.T) {
    request: Highlight_Requested = {
        identity = highlight_test_identity(),
        source = "x",
    }
    testing.expect(t, highlight_request_valid(request))
    request.identity.target_kind = .History_Entry
    testing.expect(t, !highlight_request_valid(request))
    request.identity.target_id = 19
    testing.expect(t, highlight_request_valid(request))
    request.identity.face_generation = 0
    testing.expect(t, !highlight_request_valid(request))
    testing.expect(t, !highlight_run_style_valid({
        weight = Highlight_Weight(255),
    }))
    testing.expect(t, !highlight_run_style_valid({
        underline = Highlight_Underline(255),
    }))
    testing.expect(t, !highlight_run_style_valid({
        foreground_kind = Highlight_Color_Kind(255),
    }))
    testing.expect(t, !highlight_color_valid(.Ansi, 16))
    testing.expect(t, !highlight_color_valid(.Default, 1))
}
