package termhistsearch

import "core:c"
import pcre2 "../../../pcre2"
import protocol "../../../core/protocol"

HISTORY_SEARCH_QUERY_MAX_BYTES :: 1024
HISTORY_SEARCH_CONDITION_MAX :: 64
HISTORY_SEARCH_PATTERN_MAX_BYTES :: 8192
HISTORY_SEARCH_RANGE_MAX :: 256

Condition_Kind :: enum u8 {
    Exact,
    Negative,
    Regex,
    Mode,
    Skipped_Regex,
}

Search_Error :: enum u8 {
    None,
    Invalid_State,
    Invalid_Query,
    Invalid_Source,
    Capacity,
    Out_Of_Memory,
    Pattern_Engine,
    Match_Engine,
    Cancelled,
}

Search_Condition :: struct {
    kind: Condition_Kind,
    text_offset: int,
    text_length: int,
    regex_index: int,
    mode: protocol.Evaluation_Mode,
    mode_known: bool,
    compile_error_code: c.int,
    compile_error_offset: uintptr,
}

Search_Range :: struct {
    start_byte: int,
    end_byte: int,
}

// Search_Plan owns immutable conditions and their bounded UTF-8 query storage.
Search_Plan :: struct {
    storage: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8,
    storage_length: int,
    conditions: [HISTORY_SEARCH_CONDITION_MAX]Search_Condition,
    condition_count: int,
    parsed_condition_count: int,
    effective_condition_count: int,
    mode_count: int,
    skipped_regex_count: int,
    pattern_count: int,
    generated_pattern_bytes: int,
    initialized: bool,
}

// Search_Workspace owns reusable PCRE2 match storage for one plan.
Search_Workspace :: struct {
    patterns: [HISTORY_SEARCH_CONDITION_MAX]pcre2.Compiled,
    pattern_count: int,
    initialized: bool,
}

// Search_Result distinguishes a match from resource and cancellation failures.
Search_Result :: struct {
    matched: bool,
    error: Search_Error,
    engine_error: int,
}

// Range_Result publishes ranges only when the complete bounded result fits.
Range_Result :: struct {
    count: int,
    error: Search_Error,
    engine_error: int,
}

// Range_Output borrows bounded destination storage for one range collection.
Range_Output :: struct {
    ranges: []Search_Range,
    count: int,
}

// Progress and native failure details for a regex range scan.
Regex_Progress_Result :: struct {
    next_offset: int,
    error: Search_Error,
    engine_error: int,
}

// Julia history mode names map to the four modes admitted by Euclid.
search_mode_from_name :: proc(name: string) -> (protocol.Evaluation_Mode, bool) {
    if name == "julia" {
        return .Normal, true
    }
    if name == "help" {
        return .Help, true
    }
    if name == "pkg" {
        return .Pkg, true
    }
    if name == "shell" {
        return .Shell, true
    }
    return .Normal, false
}

// Search plans and workspaces are released only after all matching borrowers join.
history_search_destroy :: proc(plan: ^Search_Plan, workspace: ^Search_Workspace) {
    if workspace != nil {
        for &pattern in workspace.patterns[:workspace.pattern_count] {
            pcre2.release(&pattern)
        }
        workspace^ = {}
    }
    if plan != nil {
        plan^ = {}
    }
}
