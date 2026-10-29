package termhistsearch

import "core:unicode/utf8"
import pcre2 "../../../pcre2"
import raw "../../../../libs/pcre2"
import protocol "../../../core/protocol"

// Match one source using only the admitted plan and its exclusive workspace.
history_search_matches :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    source: string, mode: protocol.Evaluation_Mode,
    cancel: ^pcre2.Cancel_Token = nil) -> Search_Result {
    failure := history_search_validate_source(plan, workspace, source)
    if failure != .None {
        return {
            error = failure,
        }
    }
    if plan^.mode_count > 0 && !history_search_mode_matches(plan, mode) {
        return {}
    }
    for condition in plan^.conditions[:plan^.condition_count] {
        if condition.kind == .Skipped_Regex {
            continue
        }
        condition_result := history_search_condition_matches(
            plan, workspace, condition, source, cancel)
        if condition_result.error != .None {
            return {
                error = condition_result.error,
                engine_error = condition_result.engine_error,
            }
        }
        if condition.kind != .Mode &&
           (condition.kind == .Negative && condition_result.matched ||
            condition.kind != .Negative && !condition_result.matched) {
            return {}
        }
    }
    return {
        matched = true,
    }
}

// Collect all positive exact and regex ranges into a bounded caller-owned slice.
history_search_match_ranges :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    source: string, ranges: []Search_Range,
    cancel: ^pcre2.Cancel_Token = nil) -> Range_Result {
    failure := history_search_validate_source(plan, workspace, source)
    if failure != .None {
        return {
            error = failure,
        }
    }
    output: Range_Output = {
        ranges = ranges[:min(len(ranges), HISTORY_SEARCH_RANGE_MAX)],
    }
    for condition in plan^.conditions[:plan^.condition_count] {
        failure = .None
        engine_error := 0
        if condition.kind == .Exact {
            failure = history_search_collect_literal(
                plan, condition, source, output.ranges, &output.count)
        } else if condition.kind == .Regex {
            failure, engine_error = history_search_collect_regex(
                &workspace^.patterns[condition.regex_index], source, &output, cancel)
        }
        if failure != .None {
            return {
                error = failure,
                engine_error = engine_error,
            }
        }
    }
    count := history_search_sort_and_merge(source, output.ranges[:output.count])
    return {
        count = count,
    }
}

// Reject invalid owner state or malformed source before either matching API runs.
history_search_validate_source :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    source: string) -> Search_Error {
    if !history_search_ready(plan, workspace) {
        return .Invalid_State
    }
    if !utf8.valid_string(source) {
        return .Invalid_Source
    }
    return .None
}

// Validate the initialized plan/workspace pair and its compiled-pattern count.
history_search_ready :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace) -> bool {
    return plan != nil && workspace != nil &&
        plan^.initialized && workspace^.initialized &&
        plan^.pattern_count == workspace^.pattern_count
}

// Match one mode condition, treating multiple admitted modes as alternatives.
history_search_mode_matches :: proc(
    plan: ^Search_Plan, mode: protocol.Evaluation_Mode) -> bool {
    for condition in plan^.conditions[:plan^.condition_count] {
        if condition.kind == .Mode && condition.mode_known && condition.mode == mode {
            return true
        }
    }
    return false
}

// Evaluate one literal, exclusion, regex, or mode condition without swallowing errors.
history_search_condition_matches :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    condition: Search_Condition, source: string,
    cancel: ^pcre2.Cancel_Token) -> Search_Result {
    if condition.kind == .Mode || condition.kind == .Skipped_Regex {
        return {
            matched = true,
        }
    }
    if condition.kind == .Exact || condition.kind == .Negative {
        value := history_search_condition_text(plan, condition)
        return {
            matched = history_search_contains(source, value),
        }
    }
    result := pcre2.match(
        &workspace^.patterns[condition.regex_index], transmute([]u8)source, cancel)
    if result.status == .Matched {
        return {
            matched = true,
        }
    }
    if result.status == .No_Match {
        return {}
    }
    failure := history_search_match_error(result.status)
    return {
        error = failure,
        engine_error = int(result.error_code),
    }
}

// Return the source-backed literal for one exact or negative condition.
history_search_condition_text :: proc(
    plan: ^Search_Plan, condition: Search_Condition) -> string {
    return string(plan^.storage[
        condition.text_offset:condition.text_offset + condition.text_length])
}

// Search for a byte-exact UTF-8 substring, as Julia's exact filters do.
history_search_contains :: proc(source, value: string) -> bool {
    if len(value) == 0 {
        return true
    }
    if len(value) > len(source) {
        return false
    }
    for start in 0 ..= len(source) - len(value) {
        if source[start:start + len(value)] == value {
            return true
        }
    }
    return false
}

// Add every non-overlapping exact occurrence or fail without publishing ranges.
history_search_collect_literal :: proc(
    plan: ^Search_Plan, condition: Search_Condition, source: string,
    ranges: []Search_Range, count: ^int) -> Search_Error {
    value := history_search_condition_text(plan, condition)
    if len(value) == 0 {
        return .None
    }
    for offset := 0; offset + len(value) <= len(source); {
        if source[offset:offset + len(value)] == value {
            if !history_search_append_range(ranges, count, offset, offset + len(value)) {
                return .Capacity
            }
            offset += len(value)
        } else {
            offset += 1
        }
    }
    return .None
}

// Iterate PCRE2 global matches, including the anchored retry after zero-width hits.
history_search_collect_regex :: proc(
    compiled: ^pcre2.Compiled, source: string, output: ^Range_Output,
    cancel: ^pcre2.Cancel_Token) -> (Search_Error, int) {
    offset := 0
    for offset <= len(source) {
        result := pcre2.match_from_with_options(
            compiled, transmute([]u8)source, offset, 0, cancel)
        if result.status == .No_Match {
            return .None, 0
        }
        if result.status != .Matched {
            return history_search_match_error(result.status), int(result.error_code)
        }
        if result.end > result.start {
            if !history_search_append_range(
                output.ranges, &output.count, int(result.start), int(result.end)) {
                return .Capacity, 0
            }
            offset = int(result.end)
            continue
        }
        progress := history_search_retry_after_empty(
            compiled, source, int(result.start), output, cancel)
        if progress.error != .None {
            return progress.error, progress.engine_error
        }
        if progress.next_offset < 0 {
            return .None, 0
        }
        offset = progress.next_offset
    }
    return .None, 0
}

// Retry a non-empty alternative at the zero-width match position before advancing.
history_search_retry_after_empty :: proc(
    compiled: ^pcre2.Compiled, source: string, offset: int,
    output: ^Range_Output,
    cancel: ^pcre2.Cancel_Token) -> Regex_Progress_Result {
    retry := pcre2.match_from_with_options(compiled, transmute([]u8)source,
        offset, raw.MATCH_ANCHORED | raw.MATCH_NOTEMPTY_ATSTART, cancel)
    if retry.status == .Matched {
        if !history_search_append_range(
            output.ranges, &output.count, int(retry.start), int(retry.end)) {
            return {-1, .Capacity, 0}
        }
        return {int(retry.end), .None, 0}
    }
    if retry.status != .No_Match {
        return {
            -1,
            history_search_match_error(retry.status),
            int(retry.error_code),
        }
    }
    if offset >= len(source) {
        return {-1, .None, 0}
    }
    _, width := utf8.decode_rune_in_string(source[offset:])
    return {offset + width, .None, 0}
}

// Append one range only within both public and caller-provided capacity.
history_search_append_range :: proc(
    ranges: []Search_Range, count: ^int, start, end: int) -> bool {
    if count^ >= len(ranges) || count^ >= HISTORY_SEARCH_RANGE_MAX {
        return false
    }
    ranges[count^] = {start, end}
    count^ += 1
    return true
}

// Sort ranges by start, then longest-first, and merge single-space neighbors.
history_search_sort_and_merge :: proc(
    source: string, ranges: []Search_Range) -> int {
    for index in 1 ..< len(ranges) {
        value := ranges[index]
        position := index
        for position > 0 &&
            (ranges[position - 1].start_byte > value.start_byte ||
             ranges[position - 1].start_byte == value.start_byte &&
                ranges[position - 1].end_byte < value.end_byte) {
            ranges[position] = ranges[position - 1]
            position -= 1
        }
        ranges[position] = value
    }
    for index := 0; index + 1 < len(ranges); index += 1 {
        current := &ranges[index]
        next := &ranges[index + 1]
        if next^.start_byte == current^.end_byte + 1 &&
           current^.end_byte < len(source) && source[current^.end_byte] == ' ' {
            current^.end_byte = next^.end_byte
            next^ = {next^.end_byte, next^.end_byte}
        }
    }
    output := 0
    for range in ranges {
        if range.end_byte > range.start_byte {
            ranges[output] = range
            output += 1
        }
    }
    return output
}

// Preserve native cancellation, allocation, and execution failures.
history_search_match_error :: proc(status: pcre2.Match_Status) -> Search_Error {
    switch status {
    case .Cancelled:
        return .Cancelled
    case .Out_Of_Memory:
        return .Out_Of_Memory
    case .Match_Limit, .Depth_Limit, .Heap_Limit, .Engine_Error:
        return .Match_Engine
    case .Invalid_State:
        return .Invalid_State
    case .Matched, .No_Match:
        return .None
    }
    return .Match_Engine
}
