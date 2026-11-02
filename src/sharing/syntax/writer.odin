package syntax

import "core:time"
import "core:unicode/utf8"

Writer_Error :: enum u8 {
    None,
    Invalid_Sink,
    Invalid_State,
    Invalid_Record,
    Invalid_Scope,
    Invalid_Block,
    Invalid_Text,
    Record_Too_Large,
    Too_Many_Records,
    Output_Failed,
    Output_Too_Large,
}

Output_Sink :: struct {
    buffer: []u8,
    used: int,
    flush: proc(sink: ^Output_Sink) -> bool,
    user: rawptr,
}

Writer :: struct {
    sink: ^Output_Sink,
    output_bytes: int,
    maximum_bytes: int,
    maximum_record_bytes: int,
    maximum_records: int,
    record_bytes: int,
    record_count: int,
    error: Writer_Error,
    record_open: bool,
    finished: bool,
}

// Initialize a non-allocating writer over a caller-owned output sink.
syntax_writer_init :: proc(
    writer: ^Writer, sink: ^Output_Sink, maximum_bytes: int,
    maximum_record_bytes := SYNTAX_DEFAULT_RECORD_BYTES,
    maximum_records := SYNTAX_DEFAULT_RECORD_COUNT) -> Writer_Error {
    if writer == nil || sink == nil || len(sink.buffer) == 0 ||
        sink.used != 0 || sink.flush == nil || maximum_bytes < 1 ||
        maximum_record_bytes < 1 || maximum_records < 1 {
        return .Invalid_Sink
    }
    writer^ = {
        sink = sink,
        maximum_bytes = maximum_bytes,
        maximum_record_bytes = maximum_record_bytes,
        maximum_records = maximum_records,
    }
    return .None
}

// Begin one compact JSON record and stream its fields through bounded storage.
syntax_writer_record_begin :: proc(writer: ^Writer) -> Writer_Error {
    if !syntax_writer_ready(writer) || writer.record_open {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if writer.record_count >= writer.maximum_records {
        return syntax_writer_fail(writer, .Too_Many_Records)
    }
    writer.record_count += 1
    writer.record_bytes = 0
    writer.record_open = true
    return .None
}

// Write bytes inside the current JSON record without adding a line ending.
syntax_writer_record_bytes :: proc(
    writer: ^Writer, bytes: []u8) -> Writer_Error {
    if !syntax_writer_ready(writer) || !writer.record_open {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if len(bytes) > writer.maximum_record_bytes-writer.record_bytes {
        return syntax_writer_fail(writer, .Record_Too_Large)
    }
    for byte in bytes {
        if byte == '\n' || byte == '\r' {
            return syntax_writer_fail(writer, .Invalid_Record)
        }
    }
    if rule := syntax_writer_emit(writer, bytes); rule != .None {
        return rule
    }
    writer.record_bytes += len(bytes)
    return .None
}

// Write a UTF-8 record fragment without adding a line ending.
syntax_writer_record_text :: proc(
    writer: ^Writer, value: string) -> Writer_Error {
    return syntax_writer_record_bytes(writer, transmute([]u8)value)
}

// Emit a UTF-8 string using JSON escapes without allocating a temporary string.
syntax_writer_json_string :: proc(
    writer: ^Writer, value: string) -> Writer_Error {
    if !utf8.valid_string(value) {
        return syntax_writer_fail(writer, .Invalid_Text)
    }
    if rule := syntax_writer_record_text(writer, "\""); rule != .None {
        return rule
    }
    for byte in transmute([]u8)value {
        if rule := syntax_writer_json_byte(writer, byte); rule != .None {
            return rule
        }
    }
    return syntax_writer_record_text(writer, "\"")
}

// Escape one JSON string byte without constructing a temporary allocation.
syntax_writer_json_byte :: proc(writer: ^Writer, byte: u8) -> Writer_Error {
    switch byte {
    case '"':
        return syntax_writer_record_text(writer, "\\\"")
    case '\\':
        return syntax_writer_record_text(writer, "\\\\")
    case '\b':
        return syntax_writer_record_text(writer, "\\b")
    case '\f':
        return syntax_writer_record_text(writer, "\\f")
    case '\n':
        return syntax_writer_record_text(writer, "\\n")
    case '\r':
        return syntax_writer_record_text(writer, "\\r")
    case '\t':
        return syntax_writer_record_text(writer, "\\t")
    case:
        if byte >= 0x20 {
            return syntax_writer_record_bytes(writer, {byte})
        }
        hex := "0123456789abcdef"
        escaped: [6]u8 = {'\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0x0F]}
        return syntax_writer_record_bytes(writer, escaped[:])
    }
}

// Finish the current JSON record with the required LF.
syntax_writer_record_end :: proc(writer: ^Writer) -> Writer_Error {
    if !syntax_writer_ready(writer) || !writer.record_open {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if rule := syntax_writer_emit(writer, {'\n'}); rule != .None {
        return rule
    }
    writer.record_open = false
    return .None
}

// Emit a raw complete JSON object followed by LF.
syntax_writer_record :: proc(
    writer: ^Writer, record: []u8) -> Writer_Error {
    if !syntax_writer_ready(writer) {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if len(record) > writer.maximum_record_bytes {
        return syntax_writer_fail(writer, .Record_Too_Large)
    }
    if len(record) < 2 || record[0] != '{' ||
        record[len(record) - 1] != '}' ||
        !utf8.valid_string(string(record)) {
        return syntax_writer_fail(writer, .Invalid_Record)
    }
    if writer.record_count >= writer.maximum_records {
        return syntax_writer_fail(writer, .Too_Many_Records)
    }
    for byte in record {
        if byte == '\n' || byte == '\r' {
            return syntax_writer_fail(writer, .Invalid_Record)
        }
    }
    writer.record_count += 1
    if rule := syntax_writer_emit(writer, record); rule != .None {
        return rule
    }
    return syntax_writer_emit(writer, {'\n'})
}

// Emit a delimiter block with an escaped descriptor and exact payload bytes.
syntax_writer_delimited_block :: proc(
    writer: ^Writer, record_prefix: string,
    payload: []u8, terminator: string) -> Writer_Error {
    if !syntax_writer_delimiter_valid(record_prefix, payload, terminator) {
        return syntax_writer_fail(writer, .Invalid_Block)
    }
    if rule := syntax_writer_record_begin(writer); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_text(writer, record_prefix); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_text(
        writer, ",\"block_end\":"); rule != .None {
        return rule
    }
    if rule := syntax_writer_json_string(writer, terminator); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_bytes(writer, {'}'}); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_end(writer); rule != .None {
        return rule
    }
    return syntax_writer_delimited_payload(writer, payload, terminator)
}

// Emit a validated delimiter payload and its exact terminator framing.
syntax_writer_delimited_payload :: proc(
    writer: ^Writer, payload: []u8, terminator: string) -> Writer_Error {
    if rule := syntax_writer_emit(writer, payload); rule != .None {
        return rule
    }
    if rule := syntax_writer_emit(writer, {'\n'}); rule != .None {
        return rule
    }
    if rule := syntax_writer_emit(writer, transmute([]u8)terminator); rule != .None {
        return rule
    }
    return syntax_writer_emit(writer, {'\n'})
}

// Validate delimiter framing and text requirements before emitting any bytes.
syntax_writer_delimiter_valid :: proc(
    prefix: string, payload: []u8, terminator: string) -> bool {
    return syntax_block_prefix_valid(prefix) &&
        len(terminator) > 0 && utf8.valid_string(terminator) &&
        !strings_contains_line_break(terminator) &&
        utf8.valid_string(string(payload)) &&
        !bytes_contain(payload, '\r') &&
        !delimiter_collides(payload, terminator)
}

// Emit a byte-counted block with an exact decimal payload length.
syntax_writer_counted_block :: proc(
    writer: ^Writer, record_prefix: string, payload: []u8) -> Writer_Error {
    if !syntax_block_prefix_valid(record_prefix) {
        return syntax_writer_fail(writer, .Invalid_Block)
    }
    if rule := syntax_writer_record_begin(writer); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_text(writer, record_prefix); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_text(
        writer, ",\"block_bytes\":"); rule != .None {
        return rule
    }
    if rule := syntax_writer_unsigned(writer, len(payload)); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_bytes(writer, {'}'}); rule != .None {
        return rule
    }
    if rule := syntax_writer_record_end(writer); rule != .None {
        return rule
    }
    if rule := syntax_writer_emit(writer, payload); rule != .None {
        return rule
    }
    return syntax_writer_emit(writer, {'\n'})
}

// Flush the last partial chunk and prevent further writes.
syntax_writer_finish :: proc(writer: ^Writer) -> Writer_Error {
    if !syntax_writer_ready(writer) || writer.record_open {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if writer.sink^.used > 0 && !syntax_writer_flush(writer) {
        return writer.error
    }
    writer.finished = true
    return .None
}

// Write a nonnegative decimal integer without scratch allocation.
syntax_writer_unsigned :: proc(writer: ^Writer, value: int) -> Writer_Error {
    if value < 0 {
        return syntax_writer_fail(writer, .Invalid_Record)
    }
    digits: [20]u8
    count := 0
    remaining := u64(value)
    for {
        digits[count] = u8(remaining % 10) + '0'
        count += 1
        remaining /= 10
        if remaining == 0 {
            break
        }
    }
    for index in 0..<count / 2 {
        first := digits[index]
        digits[index] = digits[count - 1 - index]
        digits[count - 1 - index] = first
    }
    return syntax_writer_record_bytes(writer, digits[:count])
}

// Format the current UTC time as an RFC 3339 timestamp in caller-owned storage.
syntax_writer_timestamp :: proc(writer: ^Writer) -> Writer_Error {
    now := time.now()
    year := time.year(now)
    month := int(time.month(now))
    day := time.day(now)
    hour, minute, second := time.clock(now)
    timestamp: [20]u8
    timestamp[0] = u8(year / 1000) + '0'
    timestamp[1] = u8(year / 100 % 10) + '0'
    timestamp[2] = u8(year / 10 % 10) + '0'
    timestamp[3] = u8(year % 10) + '0'
    timestamp[4] = '-'
    syntax_write_two_digits(timestamp[5:7], month)
    timestamp[7] = '-'
    syntax_write_two_digits(timestamp[8:10], day)
    timestamp[10] = 'T'
    syntax_write_two_digits(timestamp[11:13], hour)
    timestamp[13] = ':'
    syntax_write_two_digits(timestamp[14:16], minute)
    timestamp[16] = ':'
    syntax_write_two_digits(timestamp[17:19], second)
    timestamp[19] = 'Z'
    return syntax_writer_json_string(writer, string(timestamp[:]))
}

// Write a fixed-width two-digit decimal field.
syntax_write_two_digits :: proc(destination: []u8, value: int) {
    destination[0] = u8(value / 10) + '0'
    destination[1] = u8(value % 10) + '0'
}

// Validate a reusable JSON prefix before appending one block descriptor member.
syntax_block_prefix_valid :: proc(prefix: string) -> bool {
    bytes := transmute([]u8)prefix
    if len(bytes) < 1 || bytes[0] != '{' ||
        bytes[len(bytes) - 1] == '}' ||
        !utf8.valid_string(prefix) {
        return false
    }
    for byte in bytes {
        if byte == '\n' || byte == '\r' {
            return false
        }
    }
    return true
}

// Return whether a delimiter appears as a complete payload line.
delimiter_collides :: proc(payload: []u8, terminator: string) -> bool {
    line_start := 0
    for index in 0..<len(payload) {
        if payload[index] == '\n' {
            if string(payload[line_start:index]) == terminator {
                return true
            }
            line_start = index + 1
        }
    }
    return string(payload[line_start:]) == terminator
}

// Return whether a string includes either forbidden line-ending byte.
strings_contains_line_break :: proc(value: string) -> bool {
    for byte in transmute([]u8)value {
        if byte == '\n' || byte == '\r' {
            return true
        }
    }
    return false
}

// Return whether a byte slice contains the requested byte.
bytes_contain :: proc(value: []u8, target: u8) -> bool {
    for byte in value {
        if byte == target {
            return true
        }
    }
    return false
}

// Reject writer-state errors and preserve the first failure.
syntax_writer_ready :: proc(writer: ^Writer) -> bool {
    return writer != nil && writer.sink != nil &&
        writer.error == .None && !writer.finished
}

// Store the first writer failure and return its stable error code.
syntax_writer_fail :: proc(
    writer: ^Writer, failure: Writer_Error) -> Writer_Error {
    if writer != nil && writer.error == .None {
        writer.error = failure
    }
    return failure
}

// Copy output in bounded chunks and flush only when the sink is full.
syntax_writer_emit :: proc(writer: ^Writer, bytes: []u8) -> Writer_Error {
    if !syntax_writer_ready(writer) {
        return syntax_writer_fail(writer, .Invalid_State)
    }
    if len(bytes) > writer.maximum_bytes-writer.output_bytes {
        return syntax_writer_fail(writer, .Output_Too_Large)
    }
    offset := 0
    for offset < len(bytes) {
        remaining := len(writer.sink^.buffer) - writer.sink^.used
        if remaining == 0 {
            if !syntax_writer_flush(writer) {
                return writer.error
            }
            remaining = len(writer.sink^.buffer)
        }
        copied := min(remaining, len(bytes)-offset)
        copy(
            writer.sink^.buffer[writer.sink^.used:writer.sink^.used+copied],
            bytes[offset:offset+copied])
        writer.sink^.used += copied
        writer.output_bytes += copied
        offset += copied
    }
    return .None
}

// Flush a full or final partial output chunk and require the sink to consume it.
syntax_writer_flush :: proc(writer: ^Writer) -> bool {
    sink := writer.sink
    previous_used := sink^.used
    if !sink^.flush(sink) {
        _ = syntax_writer_fail(writer, .Output_Failed)
        return false
    }
    if sink^.used != 0 || sink^.used >= previous_used {
        _ = syntax_writer_fail(writer, .Output_Failed)
        return false
    }
    return true
}
