package syntax

import json "core:encoding/json"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

Event_Kind :: enum u8 {
    Need_More,
    Record,
    Block_Begin,
    Block_End,
    Scope_End,
    End,
    Error,
}

Event :: struct {
    kind: Event_Kind,
    line: int,
    record: json.Object,
    delivered_bytes: int,
    block_bytes: int,
    block_overflowed: bool,
    scope_id: string,
}

Syntax_Event_Kind :: Event_Kind
Syntax_Event :: Event

Block_Mode :: enum u8 {
    None,
    Await_Action,
    Counted_Data,
    Counted_Framing,
    Delimiter_Data,
}

Byte_Status :: enum u8 {
    Continue,
    Event,
    Not_Consumed,
    Failed,
}

// Reader owns no memory; input, line storage, JSON scratch, and block output are borrowed.
Reader :: struct {
    line_buffer: []u8,
    json_scratch: []u8,
    json_arena: mem.Arena,
    limits: Limits,
    diagnostic: Diagnostic,
    pending_event: Event,
    event_ready: bool,
    failed: bool,
    finished: bool,
    header_seen: bool,
    document_bytes: int,
    record_count: int,
    line_number: int,
    line_length: int,
    scope_ids: [SYNTAX_DEFAULT_SCOPE_DEPTH][SYNTAX_SCOPE_ID_BYTES]u8,
    scope_lengths: [SYNTAX_DEFAULT_SCOPE_DEPTH]int,
    scope_depth: int,
    block_mode: Block_Mode,
    block_destination: []u8,
    block_deliver: bool,
    block_overflow_is_event: bool,
    block_overflowed: bool,
    block_length: int,
    block_seen: int,
    block_written: int,
    block_line_pending: bool,
    block_pending_length: int,
    block_terminator: [SYNTAX_TERMINATOR_BYTES]u8,
    block_terminator_length: int,
    block_descriptor_line: int,
}

Block_Descriptor :: struct {
    length: int,
    rule: Rule,
}

Syntax_Feed_Check :: struct {
    stop: bool,
    consumed: int,
    diagnostic: Diagnostic,
}

Scope_End_Result :: struct {
    event: bool,
    handled: bool,
    failed: bool,
}

Syntax_Reader :: Reader

// Initialize a reader over caller-owned record and JSON scratch buffers.
syntax_reader_init :: proc(
    reader: ^Reader,
    line_buffer, json_scratch: []u8,
    limits := DEFAULT_LIMITS) -> bool {
    if reader == nil || len(line_buffer) < 1 ||
        limits.document_bytes < 1 || limits.record_bytes < 1 ||
        limits.record_bytes > max(int) / 4 ||
        len(line_buffer) < limits.record_bytes ||
        len(json_scratch) < 4 * limits.record_bytes ||
        limits.record_count < 1 || limits.scope_depth < 1 ||
        limits.scope_depth > SYNTAX_DEFAULT_SCOPE_DEPTH ||
        limits.block_bytes < 0 {
        return false
    }
    reader^ = {
        line_buffer = line_buffer[:limits.record_bytes],
        json_scratch = json_scratch[:4 * limits.record_bytes],
        limits = limits,
        line_number = 1,
    }
    mem.arena_init(&reader.json_arena, reader.json_scratch)
    return true
}

// Consume bytes through the next event; the return count leaves later bytes to the caller.
syntax_feed :: proc(
    reader: ^Reader, bytes: []u8,
    is_final: bool) -> (consumed: int, diagnostic: Diagnostic) {
    check := syntax_feed_preflight(reader, len(bytes))
    if check.stop {
        return check.consumed, check.diagnostic
    }
    for index in 0..<len(bytes) {
        status, failure := syntax_consume_byte(reader, bytes[index])
        if failure.rule != .None {
            if status == .Failed {
                return index + 1, failure
            }
            return index, failure
        }
        if status == .Event {
            return index + 1, {}
        }
    }
    if is_final {
        if finish_diagnostic := syntax_finish(reader);
            finish_diagnostic.rule != .None {
            return len(bytes), finish_diagnostic
        }
    }
    return len(bytes), {}
}

// Reject invalid reader states before syntax_feed starts consuming a chunk.
syntax_feed_preflight :: proc(
    reader: ^Reader, byte_count: int) -> Syntax_Feed_Check {
    if reader == nil {
        return {
            stop = true,
            diagnostic = {
                rule = .Invalid_Json,
            },
        }
    }
    if reader.failed {
        return {
            stop = true,
            diagnostic = reader.diagnostic,
        }
    }
    if reader.finished || reader.event_ready {
        if reader.finished && byte_count > 0 {
            consumed, diagnostic := syntax_fail(
                reader, .Feed_After_End, reader.line_number)
            return {
                stop = true,
                consumed = consumed,
                diagnostic = diagnostic,
            }
        }
        return {
            stop = true,
        }
    }
    if reader.block_mode == .Await_Action {
        consumed, diagnostic := syntax_fail(
            reader, .Block_Action_Missing, reader.block_descriptor_line)
        return {
            stop = true,
            consumed = consumed,
            diagnostic = diagnostic,
        }
    }
    return {}
}

// Consume one byte and report whether it completed an event or failed.
syntax_consume_byte :: proc(
    reader: ^Reader, byte: u8) -> (status: Byte_Status, diagnostic: Diagnostic) {
    if reader.document_bytes >= reader.limits.document_bytes {
        return .Not_Consumed, syntax_fail_value(
            reader, .Document_Too_Large, reader.line_number)
    }
    reader.document_bytes += 1
    switch reader.block_mode {
    case .Counted_Data:
        if reader.block_deliver {
            if reader.block_written < len(reader.block_destination) {
                reader.block_destination[reader.block_written] = byte
                reader.block_written += 1
            } else {
                reader.block_overflowed = true
            }
        }
        reader.block_seen += 1
        if reader.block_seen == reader.block_length {
            reader.block_mode = .Counted_Framing
        }
        return .Continue, {}
    case .Counted_Framing:
        return syntax_consume_counted_framing(reader, byte)
    case .Delimiter_Data:
        return syntax_consume_delimiter_byte(reader, byte)
    case .None, .Await_Action:
        if reader.block_mode == .Await_Action {
            return .Failed, syntax_fail_value(
                reader, .Block_Action_Missing, reader.block_descriptor_line)
        }
        return syntax_consume_record_byte(reader, byte)
    }
    return .Continue, {}
}

// Consume the exact LF separating counted payload bytes from the next record.
syntax_consume_counted_framing :: proc(
    reader: ^Reader, byte: u8) -> (Byte_Status, Diagnostic) {
    if byte != '\n' {
        return .Failed, syntax_fail_value(
            reader, .Invalid_Block_Framing_Lf, reader.block_descriptor_line)
    }
    reader.block_mode = .None
    syntax_queue_block_end(reader)
    return .Event, {}
}

// Consume delimiter payload bytes and publish completed block lines.
syntax_consume_delimiter_byte :: proc(
    reader: ^Reader, byte: u8) -> (Byte_Status, Diagnostic) {
    if byte == '\r' {
        return .Failed, syntax_fail_value(
            reader, .Carriage_Return, reader.block_descriptor_line)
    }
    if byte == '\n' {
        event, failed := syntax_delimiter_line(reader)
        if failed {
            return .Failed, reader.diagnostic
        }
        reader.line_number += 1
        if event {
            return .Event, {}
        }
        return .Continue, {}
    }
    if !syntax_line_append(reader, byte) {
        return .Failed, reader.diagnostic
    }
    return .Continue, {}
}

// Consume record bytes and parse a completed LF-terminated line.
syntax_consume_record_byte :: proc(
    reader: ^Reader, byte: u8) -> (Byte_Status, Diagnostic) {
    if byte == '\r' {
        return .Failed, syntax_fail_value(reader, .Carriage_Return, reader.line_number)
    }
    if byte == '\n' {
        event, failed := syntax_record_line(reader)
        if failed {
            return .Failed, reader.diagnostic
        }
        reader.line_number += 1
        if event {
            return .Event, {}
        }
        return .Continue, {}
    }
    if !syntax_line_append(reader, byte) {
        return .Failed, reader.diagnostic
    }
    return .Continue, {}
}

// Validate end-of-input after the final caller chunk has been consumed.
syntax_finish :: proc(reader: ^Reader) -> Diagnostic {
    if reader.block_mode != .None {
        rule := Rule.Missing_Block_Terminator
        if reader.block_mode == .Counted_Framing {
            rule = .Invalid_Block_Framing_Lf
        }
        return syntax_fail_value(reader, rule, reader.block_descriptor_line)
    }
    if reader.line_length != 0 {
        return syntax_fail_value(reader, .Missing_Final_Lf, reader.line_number)
    }
    if !reader.header_seen {
        return syntax_fail_value(reader, .Missing_Header, reader.line_number)
    }
    if reader.scope_depth != 0 {
        return syntax_fail_value(reader, .Unclosed_Scope, reader.line_number)
    }
    reader.finished = true
    return {}
}

// Return the next event; record data remains valid until the following pull.
syntax_next :: proc(reader: ^Reader) -> Event {
    if reader == nil {
        return {
            kind = .Error,
        }
    }
    if reader.event_ready {
        event := reader.pending_event
        reader.pending_event = {}
        reader.event_ready = false
        return event
    }
    if reader.failed {
        return {
            kind = .Error,
            line = reader.diagnostic.line,
        }
    }
    if reader.finished {
        return {
            kind = .End,
        }
    }
    return {
        kind = .Need_More,
    }
}

// Select a caller-owned destination, optionally reporting overflow at block end.
syntax_block_deliver :: proc(
    reader: ^Reader, destination: []u8,
    overflow_is_event := false) -> Diagnostic {
    if reader == nil {
        return {
            rule = .Block_Action_Missing,
        }
    }
    if reader.block_mode != .Await_Action || reader.block_deliver {
        return syntax_fail_value(
            reader, .Block_Action_Missing, reader.block_descriptor_line)
    }
    if reader.block_length >= 0 && reader.block_length > len(destination) &&
        !overflow_is_event {
        return syntax_fail_value(
            reader, .Block_Destination_Too_Small, reader.block_descriptor_line)
    }
    reader.block_destination = destination
    reader.block_deliver = true
    reader.block_overflow_is_event = overflow_is_event
    reader.block_overflowed = false
    reader.block_mode = syntax_block_active_mode(reader)
    return {}
}

// Select discard mode for a pending literal block without retaining its payload.
syntax_block_skip :: proc(reader: ^Reader) -> Diagnostic {
    if reader == nil {
        return {
            rule = .Block_Action_Missing,
        }
    }
    if reader.block_mode != .Await_Action || reader.block_deliver {
        return syntax_fail_value(
            reader, .Block_Action_Missing, reader.block_descriptor_line)
    }
    reader.block_deliver = false
    reader.block_destination = nil
    reader.block_mode = syntax_block_active_mode(reader)
    return {}
}

// Select the consuming state implied by the pending block descriptor.
syntax_block_active_mode :: proc(reader: ^Reader) -> Block_Mode {
    if reader.block_length >= 0 {
        if reader.block_length == 0 {
            return .Counted_Framing
        }
        return .Counted_Data
    }
    return .Delimiter_Data
}

// Append one record or delimiter byte without growing the caller's buffer.
syntax_line_append :: proc(reader: ^Reader, byte: u8) -> bool {
    if reader.line_length >= len(reader.line_buffer) {
        _ = syntax_fail_value(reader, .Record_Too_Large, reader.line_number)
        return false
    }
    reader.line_buffer[reader.line_length] = byte
    reader.line_length += 1
    return true
}

// Parse one complete record line and publish its syntax event.
syntax_record_line :: proc(reader: ^Reader) -> (event: bool, failed: bool) {
    defer reader.line_length = 0
    if !reader.header_seen && reader.line_number == 1 && reader.line_length == 0 {
        _ = syntax_fail_value(reader, .Empty_Header, reader.line_number)
        return false, true
    }
    if reader.line_length == 0 {
        return false, false
    }
    line := reader.line_buffer[:reader.line_length]
    record, valid := syntax_parse_record(reader, line)
    if !valid {
        return false, true
    }
    if reader.header_seen {
        return syntax_record_event(reader, record)
    }
    reader.header_seen = true
    reader.record_count += 1
    reader.pending_event = {
        kind = .Record,
        line = reader.line_number,
        record = record,
    }
    reader.event_ready = true
    return true, false
}

// Validate a JSON line and parse it entirely within the borrowed scratch arena.
syntax_parse_record :: proc(
    reader: ^Reader, line: []u8) -> (json.Object, bool) {
    if syntax_whitespace_only(line) {
        _ = syntax_fail_value(reader, .Whitespace_Record, reader.line_number)
        return {}, false
    }
    if !utf8.valid_string(string(line)) {
        _ = syntax_fail_value(reader, .Invalid_Utf8, reader.line_number)
        return {}, false
    }
    if !reader.header_seen && len(line) >= 3 &&
        line[0] == 0xEF && line[1] == 0xBB && line[2] == 0xBF {
        _ = syntax_fail_value(reader, .Byte_Order_Mark, reader.line_number)
        return {}, false
    }
    if reader.record_count >= reader.limits.record_count {
        _ = syntax_fail_value(reader, .Too_Many_Records, reader.line_number)
        return {}, false
    }
    return syntax_parse_json_record(reader, line)
}

// Parse one record using only the reusable JSON scratch arena.
syntax_parse_json_record :: proc(
    reader: ^Reader, line: []u8) -> (json.Object, bool) {
    mem.arena_init(&reader.json_arena, reader.json_scratch)
    value, parse_error := json.parse_string(
        string(line), .JSON, true, mem.arena_allocator(&reader.json_arena))
    if parse_error == .Duplicate_Object_Key {
        _ = syntax_fail_value(reader, .Duplicate_Object_Key, reader.line_number)
        return {}, false
    }
    if parse_error != .None {
        rule := Rule.Invalid_Json
        if parse_error == .Out_Of_Memory {
            rule = .Record_Too_Complex
        }
        _ = syntax_fail_value(reader, rule, reader.line_number)
        return {}, false
    }
    record, object_ok := value.(json.Object)
    if !object_ok {
        _ = syntax_fail_value(reader, .Record_Not_Object, reader.line_number)
        return {}, false
    }
    return record, true
}

// Interpret scope and block framing members before publishing a record event.
syntax_record_event :: proc(
    reader: ^Reader, record: json.Object) -> (event: bool, failed: bool) {
    scope_end := syntax_scope_end_record(reader, record)
    if scope_end.handled {
        return scope_end.event, scope_end.failed
    }
    has_end_block := false
    has_count_block := false
    if _, ok := record["block_end"]; ok {
        has_end_block = true
    }
    if _, ok := record["block_bytes"]; ok {
        has_count_block = true
    }
    if has_end_block && has_count_block {
        _ = syntax_fail_value(reader, .Invalid_Block_Descriptor, reader.line_number)
        return false, true
    }
    if block_event, block_failed := syntax_block_begin(
        reader, record, has_end_block, has_count_block);
        block_event || block_failed {
        return block_event, block_failed
    }
    if scope_failed := syntax_scope_begin_record(reader, record); scope_failed {
        return false, true
    }
    reader.record_count += 1
    reader.pending_event = {
        kind = .Record,
        line = reader.line_number,
        record = record,
    }
    reader.event_ready = true
    return true, false
}

// Validate and publish a matching innermost scope end.
syntax_scope_end_record :: proc(
    reader: ^Reader, record: json.Object) -> Scope_End_Result {
    end_value, has_end := record["end"]
    if !has_end {
        return {}
    }
    scope_id, valid := end_value.(string)
    if !valid || len(scope_id) == 0 || len(record) != 1 {
        _ = syntax_fail_value(reader, .Invalid_Scope, reader.line_number)
        return {
            handled = true,
            failed = true,
        }
    }
    if reader.scope_depth == 0 {
        _ = syntax_fail_value(reader, .Mismatched_Scope_End, reader.line_number)
        return {
            handled = true,
            failed = true,
        }
    }
    scope_length := reader.scope_lengths[reader.scope_depth - 1]
    if scope_id != string(reader.scope_ids[reader.scope_depth - 1][:scope_length]) {
        _ = syntax_fail_value(reader, .Mismatched_Scope_End, reader.line_number)
        return {
            handled = true,
            failed = true,
        }
    }
    reader.scope_depth -= 1
    reader.record_count += 1
    scope_length = reader.scope_lengths[reader.scope_depth]
    reader.pending_event = {
        kind = .Scope_End,
        line = reader.line_number,
        scope_id = string(reader.scope_ids[reader.scope_depth][:scope_length]),
    }
    reader.event_ready = true
    return {
        event = true,
        handled = true,
    }
}

// Validate and push the scope opened by a record's begin member.
syntax_scope_begin_record :: proc(reader: ^Reader, record: json.Object) -> bool {
    begin_value, has_begin := record["begin"]
    if !has_begin {
        return false
    }
    begin, valid := begin_value.(bool)
    if !valid {
        _ = syntax_fail_value(reader, .Invalid_Scope, reader.line_number)
        return true
    }
    if !begin {
        return false
    }
    id_value, has_id := record["id"]
    id, id_ok := id_value.(string)
    if !has_id || !id_ok || len(id) == 0 || len(id) > SYNTAX_SCOPE_ID_BYTES {
        _ = syntax_fail_value(reader, .Invalid_Scope, reader.line_number)
        return true
    }
    if reader.scope_depth >= reader.limits.scope_depth {
        _ = syntax_fail_value(reader, .Scope_Too_Deep, reader.line_number)
        return true
    }
    copy(reader.scope_ids[reader.scope_depth][:], transmute([]u8)id)
    reader.scope_lengths[reader.scope_depth] = len(id)
    reader.scope_depth += 1
    return false
}

// Validate a literal-block descriptor and suspend for the caller's action.
syntax_block_begin :: proc(
    reader: ^Reader, record: json.Object,
    has_end_block, has_count_block: bool) -> (event: bool, failed: bool) {
    if !has_end_block && !has_count_block {
        return false, false
    }
    begin_value, has_begin := record["begin"]
    begin, begin_ok := begin_value.(bool)
    if has_begin && (!begin_ok || begin) {
        _ = syntax_fail_value(reader, .Invalid_Block_Descriptor, reader.line_number)
        return false, true
    }
    descriptor := syntax_block_descriptor(reader, record, has_count_block)
    if descriptor.rule != .None {
        _ = syntax_fail_value(reader, descriptor.rule, reader.line_number)
        return false, true
    }
    reader.block_length = descriptor.length
    reader.block_seen = 0
    reader.block_written = 0
    reader.block_overflow_is_event = false
    reader.block_overflowed = false
    reader.block_line_pending = false
    reader.block_descriptor_line = reader.line_number
    reader.block_mode = .Await_Action
    reader.record_count += 1
    reader.pending_event = {
        kind = .Block_Begin,
        line = reader.line_number,
        record = record,
    }
    reader.event_ready = true
    return true, false
}

// Validate the selected block-length or delimiter descriptor.
syntax_block_descriptor :: proc(
    reader: ^Reader, record: json.Object, has_count_block: bool) -> Block_Descriptor {
    if !has_count_block {
        value, valid := record["block_end"].(string)
        if !valid || len(value) == 0 || len(value) > SYNTAX_TERMINATOR_BYTES ||
            !utf8.valid_string(value) {
            rule := Rule.Invalid_Block_Terminator
            if valid && len(value) > SYNTAX_TERMINATOR_BYTES {
                rule = .Block_Terminator_Too_Large
            }
            return {
                rule = rule,
            }
        }
        if strings.contains(value, "\n") || strings.contains(value, "\r") {
            return {
                rule = .Invalid_Block_Terminator,
            }
        }
        copy(reader.block_terminator[:], transmute([]u8)value)
        reader.block_terminator_length = len(value)
        return {
            length = -1,
        }
    }
    value, valid := record["block_bytes"].(json.Integer)
    if !valid || value < 0 || value > json.Integer(reader.limits.block_bytes) {
        rule := Rule.Invalid_Block_Length
        if valid && value > json.Integer(reader.limits.block_bytes) {
            rule = .Block_Too_Large
        }
        return {
            rule = rule,
        }
    }
    return {
        length = int(value),
    }
}

// Compare one complete delimiter line and preserve payload line feeds exactly.
syntax_delimiter_line :: proc(reader: ^Reader) -> (event: bool, failed: bool) {
    line := reader.line_buffer[:reader.line_length]
    if !utf8.valid_string(string(line)) {
        _ = syntax_fail_value(reader, .Invalid_Utf8, reader.block_descriptor_line)
        return false, true
    }
    terminator := reader.block_terminator[:reader.block_terminator_length]
    if len(line) == len(terminator) && string(line) == string(terminator) {
        if reader.block_line_pending &&
            !syntax_block_append(
                reader, reader.json_scratch[:reader.block_pending_length], false) {
            return false, true
        }
        reader.block_mode = .None
        syntax_queue_block_end(reader)
        reader.line_length = 0
        return true, false
    }
    if reader.block_line_pending &&
        !syntax_block_append(
            reader, reader.json_scratch[:reader.block_pending_length], true) {
        return false, true
    }
    copy(reader.json_scratch[:], line)
    reader.block_pending_length = len(line)
    reader.block_line_pending = true
    reader.line_length = 0
    return false, false
}

// Retain block bytes only when delivery was selected, enforcing its fixed capacity.
syntax_block_append :: proc(reader: ^Reader, bytes: []u8, with_lf: bool) -> bool {
    extra := len(bytes)
    if with_lf {
        extra += 1
    }
    if extra > reader.limits.block_bytes-reader.block_seen {
        _ = syntax_fail_value(
            reader, .Block_Too_Large, reader.block_descriptor_line)
        return false
    }
    reader.block_seen += extra
    remaining := len(reader.block_destination) - reader.block_written
    overflowed := extra > remaining
    if reader.block_deliver && extra > remaining &&
        !reader.block_overflow_is_event {
        _ = syntax_fail_value(
            reader, .Block_Too_Large_For_Destination, reader.block_descriptor_line)
        return false
    }
    if reader.block_deliver {
        syntax_block_write(reader, bytes, with_lf, remaining, overflowed)
    }
    return true
}

// Copy the bounded block prefix and track whether delivery omitted any bytes.
syntax_block_write :: proc(
    reader: ^Reader, bytes: []u8, with_lf: bool,
    remaining: int, overflowed: bool) {
    copied := min(len(bytes), remaining)
    use_remaining := remaining
    if copied > 0 {
        copy(
            reader.block_destination[reader.block_written:],
            bytes[:copied])
        reader.block_written += copied
        use_remaining -= copied
    }
    if with_lf && use_remaining > 0 {
        reader.block_destination[reader.block_written] = '\n'
        reader.block_written += 1
    }
    if overflowed {
        reader.block_overflowed = true
    }
}

// Publish block completion and release the borrowed destination.
syntax_queue_block_end :: proc(reader: ^Reader) {
    reader.pending_event = {
        kind = .Block_End,
        line = reader.block_descriptor_line,
        delivered_bytes = reader.block_written,
        block_bytes = reader.block_seen,
        block_overflowed = reader.block_overflowed,
    }
    reader.event_ready = true
    reader.block_destination = nil
    reader.block_deliver = false
    reader.block_overflow_is_event = false
    reader.block_line_pending = false
}

// Identify record lines containing only framing whitespace.
syntax_whitespace_only :: proc(line: []u8) -> bool {
    for byte in line {
        if byte != ' ' && byte != '\t' {
            return false
        }
    }
    return true
}

// Record a fatal parser error and return it through the feed API.
syntax_fail :: proc(
    reader: ^Reader, rule: Rule, line: int) -> (int, Diagnostic) {
    return 0, syntax_fail_value(reader, rule, line)
}

// Capture the current scope identity and make the parser terminally failed.
syntax_fail_value :: proc(
    reader: ^Reader, rule: Rule, line: int) -> Diagnostic {
    diagnostic: Diagnostic = {
        line = line,
        rule = rule,
    }
    if reader == nil {
        return diagnostic
    }
    if reader.scope_depth > 0 {
        scope_length := reader.scope_lengths[reader.scope_depth - 1]
        id := reader.scope_ids[reader.scope_depth - 1][:scope_length]
        copied := min(len(id), len(diagnostic.scope_id))
        copy(diagnostic.scope_id[:], id[:copied])
        diagnostic.scope_id_length = u8(copied)
    }
    reader.failed = true
    reader.diagnostic = diagnostic
    reader.pending_event = {}
    reader.event_ready = false
    return diagnostic
}
