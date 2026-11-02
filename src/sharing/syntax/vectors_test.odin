#+test
package syntax

import "core:testing"

SYNTAX_TEST_LIMITS :: Limits{
    document_bytes = 4096,
    record_bytes = 512,
    record_count = 64,
    scope_depth = 3,
    block_bytes = 1024,
}

Syntax_Test_Result :: struct {
    events: [16]Event_Kind,
    count: int,
    rule: Rule,
    line: int,
}

// Run one syntax vector with caller-selected chunk size and retain its event trace.
syntax_test_run_vector :: proc(
    source: string, chunk_size: int,
    limits := SYNTAX_TEST_LIMITS) -> Syntax_Test_Result {
    result: Syntax_Test_Result
    line_buffer, line_error := make([]u8, 512, context.allocator)
    scratch, scratch_error := make([]u8, 2048, context.allocator)
    if line_error != nil || scratch_error != nil {
        result.rule = .Record_Too_Complex
        return result
    }
    defer delete(line_buffer)
    defer delete(scratch)
    reader: Reader
    if !syntax_reader_init(&reader, line_buffer, scratch, limits) {
        result.rule = .Record_Too_Complex
        return result
    }
    if !syntax_test_feed_loop(&reader, source, chunk_size, &result) {
        return result
    }
    event := syntax_next(&reader)
    if event.kind == .End {
        result.events[result.count] = event.kind
        result.count += 1
    }
    return result
}

// Feed chunks until the reader reaches its final state or reports a diagnostic.
syntax_test_feed_loop :: proc(
    reader: ^Reader, source: string, chunk_size: int,
    result: ^Syntax_Test_Result) -> bool {
    bytes := transmute([]u8)source
    offset := 0
    for offset < len(bytes) || !reader^.finished {
        size := min(chunk_size, len(bytes) - offset)
        input := bytes[offset:offset + size]
        final := offset + size == len(bytes)
        consumed, diagnostic := syntax_feed(reader, input, final)
        offset += consumed
        if diagnostic.rule != .None {
            result^.rule = diagnostic.rule
            result^.line = diagnostic.line
            return false
        }
        if !syntax_test_drain_events(reader, result) {
            return false
        }
        if consumed == 0 && !reader^.finished && len(input) > 0 {
            result^.rule = .Invalid_Json
            return false
        }
        if offset == len(bytes) && !reader^.finished {
            _, diagnostic = syntax_feed(reader, nil, true)
            if diagnostic.rule != .None {
                result^.rule = diagnostic.rule
                result^.line = diagnostic.line
                return false
            }
        }
    }
    return true
}

// Drain completed events and skip payloads in conformance-vector runs.
syntax_test_drain_events :: proc(
    reader: ^Reader, result: ^Syntax_Test_Result) -> bool {
    for {
        event := syntax_next(reader)
        if event.kind == .Need_More {
            return true
        }
        if event.kind == .Error {
            result^.rule = reader^.diagnostic.rule
            result^.line = reader^.diagnostic.line
            return false
        }
        result^.events[result^.count] = event.kind
        result^.count += 1
        if event.kind == .Block_Begin {
            diagnostic := syntax_block_skip(reader)
            if diagnostic.rule != .None {
                result^.rule = diagnostic.rule
                result^.line = diagnostic.line
                return false
            }
        }
    }
}

// Whole-input and one-byte feeds must emit the same syntax event sequence.
@(test)
syntax_vectors_are_chunk_independent :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"x\"}\n" +
        "{\"end\":\"c\"}\n"
    whole := syntax_test_run_vector(source, len(source))
    bytes := syntax_test_run_vector(source, 1)
    testing.expect_value(t, whole.rule, Rule.None)
    testing.expect_value(t, bytes.rule, Rule.None)
    testing.expect_value(t, bytes.count, whole.count)
    for index in 0..<whole.count {
        testing.expect_value(t, bytes.events[index], whole.events[index])
    }
}

// Duplicate object members are rejected with a stable syntax diagnostic.
@(test)
syntax_duplicate_keys_are_rejected :: proc(t: ^testing.T) {
    result := syntax_test_run_vector(
        "{\"format\":\"a\",\"format\":\"b\"}\n", 1)
    testing.expect_value(t, result.rule, Rule.Duplicate_Object_Key)
    testing.expect_value(t, result.line, 1)
}

// A counted block consumes opaque bytes and requires its framing LF.
@(test)
syntax_counted_block_requires_framing_lf :: proc(t: ^testing.T) {
    result := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\n" +
        "{\"type\":\"future\",\"block_bytes\":1}\nxX", 2)
    testing.expect_value(t, result.rule, Rule.Invalid_Block_Framing_Lf)
    testing.expect_value(t, result.line, 2)
}

// Every delimiter block is recognized by an exact whole-line terminator.
@(test)
syntax_delimiter_blocks_are_skipped_incrementally :: proc(t: ^testing.T) {
    result := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\n" +
        "{\"type\":\"notes\",\"block_end\":\"::end::\"}\n" +
        "{\"end\":\"fake\"}\n::end::\n", 1)
    testing.expect_value(t, result.rule, Rule.None)
    testing.expect_value(t, result.events[1], Event_Kind.Block_Begin)
    testing.expect_value(t, result.events[2], Event_Kind.Block_End)
}

// Files require the final record-terminating line feed.
@(test)
syntax_requires_final_lf :: proc(t: ^testing.T) {
    result := syntax_test_run_vector("{\"format\":\"euclid-collections\"}", 8)
    testing.expect_value(t, result.rule, Rule.Missing_Final_Lf)
}

// BOM, CRLF, and invalid scope endings have distinct structural diagnostics.
@(test)
syntax_rejects_bom_crlf_and_unopened_scope_end :: proc(t: ^testing.T) {
    bom := syntax_test_run_vector(
        "\xEF\xBB\xBF{\"format\":\"euclid-collections\"}\n", 1)
    crlf := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\r\n", 2)
    end := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\n{\"end\":\"missing\"}\n", 3)
    testing.expect_value(t, bom.rule, Rule.Byte_Order_Mark)
    testing.expect_value(t, crlf.rule, Rule.Carriage_Return)
    testing.expect_value(t, end.rule, Rule.Mismatched_Scope_End)
}

// The syntax scope stack enforces its configured depth before writing a frame.
@(test)
syntax_rejects_excess_scope_depth :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\"}\n" +
        "{\"id\":\"a\",\"begin\":true}\n" +
        "{\"id\":\"b\",\"begin\":true}\n" +
        "{\"id\":\"c\",\"begin\":true}\n" +
        "{\"id\":\"d\",\"begin\":true}\n"
    result := syntax_test_run_vector(source, 1)
    testing.expect_value(t, result.rule, Rule.Scope_Too_Deep)
    testing.expect_value(t, result.line, 5)
}

// Document, record, record-count, and delimiter-payload limits are enforced.
@(test)
syntax_enforces_configured_limits :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\"}\n"
    document_limits := SYNTAX_TEST_LIMITS
    document_limits.document_bytes = len(source) - 1
    document := syntax_test_run_vector(source, 1, document_limits)
    record_limits := SYNTAX_TEST_LIMITS
    record_limits.record_bytes = 8
    record := syntax_test_run_vector(source, 1, record_limits)
    record_count_limits := SYNTAX_TEST_LIMITS
    record_count_limits.record_count = 1
    record_count := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\n{\"type\":\"second\"}\n",
        1, record_count_limits)
    block_limits := SYNTAX_TEST_LIMITS
    block_limits.block_bytes = 2
    block := syntax_test_run_vector(
        "{\"format\":\"euclid-collections\"}\n" +
        "{\"type\":\"future\",\"block_end\":\"::end::\"}\n" +
        "a\nb\n::end::\n", 1, block_limits)
    testing.expect_value(t, document.rule, Rule.Document_Too_Large)
    testing.expect_value(t, record.rule, Rule.Record_Too_Large)
    testing.expect_value(t, record_count.rule, Rule.Too_Many_Records)
    testing.expect_value(t, block.rule, Rule.Block_Too_Large)
    testing.expect_value(t, block.line, 2)
}

// A caller-selected destination receives exactly the counted block payload.
@(test)
syntax_delivers_counted_block_bytes :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\"}\n" +
        "{\"type\":\"future\",\"block_bytes\":5}\nHello\n"
    line_buffer, line_error := make([]u8, 512, context.allocator)
    scratch, scratch_error := make([]u8, 2048, context.allocator)
    destination, destination_error := make([]u8, 8, context.allocator)
    if line_error != nil || scratch_error != nil || destination_error != nil {
        testing.expect(t, false)
        return
    }
    defer delete(line_buffer)
    defer delete(scratch)
    defer delete(destination)
    reader: Reader
    limits: Limits = {
        document_bytes = 4096,
        record_bytes = 512,
        record_count = 64,
        scope_depth = 3,
        block_bytes = 1024,
    }
    if !syntax_reader_init(&reader, line_buffer, scratch, limits) {
        testing.expect(t, false)
        return
    }
    delivered := syntax_test_deliver(&reader, source, destination)
    testing.expect(t, delivered)
}

// Deliver a counted payload while checking every syntax transition.
syntax_test_deliver :: proc(
    reader: ^Reader, source: string, destination: []u8) -> bool {
    bytes := transmute([]u8)source
    offset := 0
    delivered := false
    for offset < len(bytes) || !reader^.finished {
        consumed, diagnostic := syntax_feed(
            reader, bytes[offset:], offset == len(bytes))
        offset += consumed
        if diagnostic.rule != .None {
            return false
        }
        event := syntax_next(reader)
        if event.kind == .Block_Begin {
            diagnostic = syntax_block_deliver(reader, destination)
            if diagnostic.rule != .None {
                return false
            }
        } else if event.kind == .Block_End {
            delivered = event.delivered_bytes == 5 &&
                string(destination[:event.delivered_bytes]) == "Hello"
        } else if event.kind == .Error {
            return false
        }
        if consumed == 0 && offset < len(bytes) {
            return false
        }
    }
    return delivered
}

// JSON scratch exhaustion is reported without an alternate allocation path.
@(test)
syntax_reports_json_scratch_exhaustion :: proc(t: ^testing.T) {
    line_buffer, line_error := make([]u8, 512, context.allocator)
    scratch, scratch_error := make([]u8, 2048, context.allocator)
    input, input_error := make([]u8, 512, context.allocator)
    if line_error != nil || scratch_error != nil || input_error != nil {
        testing.expect(t, false)
        return
    }
    defer delete(line_buffer)
    defer delete(scratch)
    defer delete(input)
    reader: Reader
    limits: Limits = {
        document_bytes = 4096,
        record_bytes = 512,
        record_count = 64,
        scope_depth = 3,
        block_bytes = 1024,
    }
    if !syntax_reader_init(&reader, line_buffer, scratch, limits) {
        testing.expect(t, false)
        return
    }
    header := "{\"format\":\"euclid-collections\"}\n"
    consumed, diagnostic := syntax_feed(
        &reader, transmute([]u8)header, false)
    testing.expect_value(t, diagnostic.rule, Rule.None)
    testing.expect_value(t, consumed, len(header))
    testing.expect_value(t, syntax_next(&reader).kind, Event_Kind.Record)
    offset := syntax_test_json_overflow_input(input)
    _, diagnostic = syntax_feed(&reader, input[:offset], true)
    testing.expect_value(t, diagnostic.rule, Rule.Record_Too_Complex)
}

// Construct a bounded JSON record that exceeds the supplied scratch arena.
syntax_test_json_overflow_input :: proc(input: []u8) -> int {
    prefix := "{\"items\":["
    suffix := "]}\n"
    offset := len(prefix)
    copy(input[:offset], transmute([]u8)prefix)
    for index in 0..<220 {
        input[offset] = '0'
        offset += 1
        if index < 219 {
            input[offset] = ','
            offset += 1
        }
    }
    copy(input[offset:offset + len(suffix)], transmute([]u8)suffix)
    return offset + len(suffix)
}
