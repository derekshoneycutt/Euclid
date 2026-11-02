#+test
package syntax

import "core:testing"

Syntax_Writer_Test_Output :: struct {
    bytes: []u8,
    length: int,
    fail: bool,
}

// Collect a complete bounded chunk into caller-owned test storage.
syntax_writer_test_flush :: proc(sink: ^Output_Sink) -> bool {
    output := transmute(^Syntax_Writer_Test_Output)sink^.user
    if output == nil || output^.fail ||
        sink^.used > len(output^.bytes)-output^.length {
        return false
    }
    copy(
        output^.bytes[output^.length:output^.length+sink^.used],
        sink^.buffer[:sink^.used])
    output^.length += sink^.used
    sink^.used = 0
    return true
}

// Parse a generated block document while delivering its exact payload bytes.
syntax_writer_test_parse_block :: proc(
    source, payload: []u8) -> (int, Rule) {
    line: [512]u8
    scratch: [2048]u8
    reader: Reader
    if !syntax_reader_init(&reader, line[:], scratch[:], SYNTAX_TEST_LIMITS) {
        return 0, .Record_Too_Complex
    }
    offset := 0
    for {
        event := syntax_next(&reader)
        if event.kind == .Block_Begin {
            if diagnostic := syntax_block_deliver(&reader, payload);
               diagnostic.rule != .None {
                return 0, diagnostic.rule
            }
        } else if event.kind == .Error {
            return 0, reader.diagnostic.rule
        } else if event.kind == .End {
            return reader.block_written, .None
        }
        input := source[offset:]
        consumed, diagnostic := syntax_feed(&reader, input, true)
        offset += consumed
        if diagnostic.rule != .None {
            return 0, diagnostic.rule
        }
        if consumed == 0 && offset < len(source) {
            return 0, .Invalid_Json
        }
    }
}

// Stream JSON escaping across tiny sink chunks without changing Unicode text.
@(test)
syntax_writer_escapes_json_strings_across_chunks :: proc(t: ^testing.T) {
    output_bytes, output_error := make([]u8, 1024, context.allocator)
    buffer, buffer_error := make([]u8, 7, context.allocator)
    if output_error != nil || buffer_error != nil {
        delete(output_bytes)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(output_bytes)
    defer delete(buffer)
    output: Syntax_Writer_Test_Output = {
        bytes = output_bytes,
    }
    sink: Output_Sink = {
        buffer = buffer,
        flush = syntax_writer_test_flush,
        user = rawptr(&output),
    }
    writer: Writer
    testing.expect_value(
        t, syntax_writer_init(&writer, &sink, 1024), Writer_Error.None)
    testing.expect_value(
        t, syntax_writer_record_begin(&writer), Writer_Error.None)
    prefix := "{\"value\":"
    testing.expect_value(t,
        syntax_writer_record_bytes(&writer, transmute([]u8)prefix), Writer_Error.None)
    testing.expect_value(t,
        syntax_writer_json_string(&writer, "café\n\"x\"\\\t"), Writer_Error.None)
    testing.expect_value(t,
        syntax_writer_record_bytes(&writer, {'}'}), Writer_Error.None)
    testing.expect_value(t, syntax_writer_record_end(&writer), Writer_Error.None)
    testing.expect_value(t, syntax_writer_finish(&writer), Writer_Error.None)
    testing.expect_value(t,
        string(output.bytes[:output.length]),
        "{\"value\":\"café\\n\\\"x\\\"\\\\\\t\"}\n")
}

// Counted blocks preserve opaque payload bytes and parse back without changes.
@(test)
syntax_writer_counted_blocks_round_trip_opaque_bytes :: proc(t: ^testing.T) {
    payload: [12]u8 = {'x', 0, '\n', ':', ':', 'e', 'n', 'd', ':', ':', '\n', 'y'}
    output_bytes, output_error := make([]u8, 1024, context.allocator)
    buffer, buffer_error := make([]u8, 9, context.allocator)
    parsed_payload: [32]u8
    if output_error != nil || buffer_error != nil {
        delete(output_bytes)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(output_bytes)
    defer delete(buffer)
    output: Syntax_Writer_Test_Output = {
        bytes = output_bytes,
    }
    sink: Output_Sink = {
        buffer = buffer,
        flush = syntax_writer_test_flush,
        user = rawptr(&output),
    }
    writer: Writer
    testing.expect_value(
        t, syntax_writer_init(&writer, &sink, 1024), Writer_Error.None)
    header := "{\"format\":\"euclid-collections\",\"framing_version\":1}"
    testing.expect_value(t,
        syntax_writer_record(&writer, transmute([]u8)header), Writer_Error.None)
    prefix := "{\"type\":\"future\""
    testing.expect_value(t, syntax_writer_counted_block(
        &writer, prefix, payload[:]), Writer_Error.None)
    testing.expect_value(t, syntax_writer_finish(&writer), Writer_Error.None)
    written, rule := syntax_writer_test_parse_block(
        output.bytes[:output.length], parsed_payload[:])
    testing.expect_value(t, rule, Rule.None)
    testing.expect_value(t, written, len(payload))
    for index in 0..<len(payload) {
        testing.expect_value(t, parsed_payload[index], payload[index])
    }
}

// Output limits and failed sink callbacks stop the writer with explicit errors.
@(test)
syntax_writer_reports_output_limits_and_flush_failures :: proc(t: ^testing.T) {
    output_bytes: [128]u8
    small_buffer: [4]u8
    output: Syntax_Writer_Test_Output = {
        bytes = output_bytes[:],
    }
    sink: Output_Sink = {
        buffer = small_buffer[:],
        flush = syntax_writer_test_flush,
        user = rawptr(&output),
    }
    writer: Writer
    testing.expect_value(
        t, syntax_writer_init(&writer, &sink, 3), Writer_Error.None)
    testing.expect_value(t, syntax_writer_record_begin(&writer), Writer_Error.None)
    too_large_record := "four"
    testing.expect_value(t,
        syntax_writer_record_bytes(&writer, transmute([]u8)too_large_record),
        Writer_Error.Output_Too_Large)

    failed_output: Syntax_Writer_Test_Output = {
        bytes = output_bytes[:],
        fail = true,
    }
    failed_sink: Output_Sink = {
        buffer = small_buffer[:],
        flush = syntax_writer_test_flush,
        user = rawptr(&failed_output),
    }
    failed_writer: Writer
    testing.expect_value(
        t, syntax_writer_init(&failed_writer, &failed_sink, 128), Writer_Error.None)
    raw_record := "{\"a\":1}"
    testing.expect_value(t,
        syntax_writer_record(&failed_writer, transmute([]u8)raw_record),
        Writer_Error.Output_Failed)
}

// Record byte and count limits fail before writing an out-of-contract record.
@(test)
syntax_writer_enforces_record_limits :: proc(t: ^testing.T) {
    output_bytes: [128]u8
    buffer: [32]u8
    output: Syntax_Writer_Test_Output = {
        bytes = output_bytes[:],
    }
    sink: Output_Sink = {
        buffer = buffer[:],
        flush = syntax_writer_test_flush,
        user = rawptr(&output),
    }
    byte_limited_writer: Writer
    testing.expect_value(t,
        syntax_writer_init(&byte_limited_writer, &sink, 128, 3, 2),
        Writer_Error.None)
    testing.expect_value(t,
        syntax_writer_record_begin(&byte_limited_writer), Writer_Error.None)
    record_text := "four"
    testing.expect_value(t,
        syntax_writer_record_text(&byte_limited_writer, record_text),
        Writer_Error.Record_Too_Large)

    record_limited_writer: Writer
    testing.expect_value(t,
        syntax_writer_init(&record_limited_writer, &sink, 128, 32, 1),
        Writer_Error.None)
    first_record := "{}"
    testing.expect_value(t,
        syntax_writer_record(
            &record_limited_writer, transmute([]u8)first_record),
        Writer_Error.None)
    testing.expect_value(t,
        syntax_writer_record_begin(&record_limited_writer),
        Writer_Error.Too_Many_Records)
}

// Delimiter blocks reject a terminator appearing as a complete payload line.
@(test)
syntax_writer_rejects_delimiter_collisions :: proc(t: ^testing.T) {
    output_bytes: [256]u8
    buffer: [32]u8
    output: Syntax_Writer_Test_Output = {
        bytes = output_bytes[:],
    }
    sink: Output_Sink = {
        buffer = buffer[:],
        flush = syntax_writer_test_flush,
        user = rawptr(&output),
    }
    writer: Writer
    testing.expect_value(
        t, syntax_writer_init(&writer, &sink, 256), Writer_Error.None)
    prefix := "{\"type\":\"notes\",\"mime\":\"text/plain\""
    payload := "before\n::end::\nafter"
    testing.expect_value(t, syntax_writer_delimited_block(
        &writer,
        prefix,
        transmute([]u8)payload,
        "::end::"), Writer_Error.Invalid_Block)
}
