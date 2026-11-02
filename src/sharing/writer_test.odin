#+test
package sharing

import syntax "./syntax"
import uuid "core:encoding/uuid"
import "core:strings"
import "core:testing"

Sharing_Writer_Test_Output :: struct {
    bytes: []u8,
    length: int,
    fail: bool,
}

// Collect one complete writer chunk into caller-owned test storage.
sharing_writer_test_flush :: proc(sink: ^Export_Sink) -> bool {
    output := transmute(^Sharing_Writer_Test_Output)sink^.user
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

// Serialize rows through the public sink contract with bounded buffers.
sharing_writer_test_write :: proc(
    destination, buffer: []u8, rows: []Export_Row,
    fail_flush := false) -> (int, Export_Writer_Error) {
    output: Sharing_Writer_Test_Output = {
        bytes = destination,
        fail = fail_flush,
    }
    sink: Export_Sink = {
        buffer = buffer,
        flush = sharing_writer_test_flush,
        user = rawptr(&output),
    }
    writer: Export_Writer
    if rule := export_writer_init(&writer, &sink, SHARING_TEST_LIMITS);
       rule != .None {
        return output.length, rule
    }
    for row in rows {
        if rule := export_writer_row(&writer, row); rule != .None {
            return output.length, rule
        }
    }
    if rule := export_writer_finish(&writer); rule != .None {
        return output.length, rule
    }
    return output.length, .None
}

// Construct a distinct stable animation identity for writer fixtures.
sharing_writer_test_animation_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Build a small flat Unicode fixture with both explicit note placements.
sharing_writer_test_round_trip_rows :: proc() -> [3]Export_Row {
    rows: [3]Export_Row
    collection_name := "Café"
    rows[0] = {
        kind = .Collection,
        name_length = len(collection_name),
        entry_count = 2,
    }
    copy(rows[0].name[:], transmute([]u8)collection_name)
    root_name := "Root 🌱"
    root_note := "Start\n::end-c1-e1::\nλ"
    rows[1] = {
        kind = .Entry,
        animation_id = sharing_writer_test_animation_id(1),
        name_length = len(root_name),
        has_note = true,
        notes_on_top = true,
        note_length = len(root_note),
    }
    copy(rows[1].name[:], transmute([]u8)root_name)
    copy(rows[1].note[:], transmute([]u8)root_note)
    child_name := "Comparaison"
    child_note := "\\alpha + \\beta"
    rows[2] = {
        kind = .Entry,
        animation_id = sharing_writer_test_animation_id(2),
        name_length = len(child_name),
        has_note = true,
        note_length = len(child_note),
    }
    copy(rows[2].name[:], transmute([]u8)child_name)
    copy(rows[2].note[:], transmute([]u8)child_note)
    return rows
}

// Assert every exported field survives the schema reader unchanged.
sharing_writer_test_expect_round_trip :: proc(
    t: ^testing.T, document: ^Staged_Document, rows: []Export_Row) {
    testing.expect(t, document^.valid)
    testing.expect_value(t, document^.collection_count, 1)
    collection := document^.collections[0]
    testing.expect_value(t, collection.name,
        string(rows[0].name[:rows[0].name_length]))
    testing.expect(t, collection.importable)
    testing.expect_value(t, collection.entry_count, 2)
    for index in 0..<2 {
        row := rows[index + 1]
        entry := collection.entries[index]
        testing.expect_value(t, entry.animation_id, row.animation_id)
        testing.expect_value(t, entry.name, string(row.name[:row.name_length]))
        testing.expect_value(t, entry.note, string(row.note[:row.note_length]))
        testing.expect_value(t, entry.notes_on_top, row.notes_on_top)
    }
}

// Stream a collection with Unicode and a delimiter collision, then round-trip it.
@(test)
sharing_writer_round_trips_notes_names_and_delimiter_collisions :: proc(t: ^testing.T) {
    rows := sharing_writer_test_round_trip_rows()
    destination, destination_error := make(
        []u8, SHARING_TEST_LIMITS.document_bytes, context.allocator)
    buffer, buffer_error := make([]u8, 64 * 1024, context.allocator)
    if destination_error != nil || buffer_error != nil {
        delete(destination)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(destination)
    defer delete(buffer)
    length, rule := sharing_writer_test_write(destination, buffer, rows[:])
    testing.expect_value(t, rule, Export_Writer_Error.None)
    testing.expect(t, strings.contains(
        string(destination[:length]), "\"block_end\":\"::end-c1-e1-1::\""))

    parsed := sharing_test_parse(string(destination[:length]), 13)
    defer delete(parsed.backing)
    testing.expect_value(t, parsed.rule, Sharing_Rule.None)
    sharing_writer_test_expect_round_trip(t, &parsed.document, rows[:])
}

// Small and large sink buffers must produce identical document bytes.
@(test)
sharing_writer_output_is_independent_of_sink_capacity :: proc(t: ^testing.T) {
    rows: [3]Export_Row
    rows[0] = {
        kind = .Collection,
        name_length = 1,
        entry_count = 2,
    }
    rows[0].name[0] = 'C'
    for index in 1..=2 {
        rows[index] = {
            kind = .Entry,
            animation_id = sharing_writer_test_animation_id(u8(index)),
        }
    }
    small_output: [1024]u8
    large_output: [1024]u8
    small_buffer: [16]u8
    large_buffer: [64 * 1024]u8
    small_length, small_rule := sharing_writer_test_write(
        small_output[:], small_buffer[:], rows[:])
    large_length, large_rule := sharing_writer_test_write(
        large_output[:], large_buffer[:], rows[:])
    testing.expect_value(t, small_rule, Export_Writer_Error.None)
    testing.expect_value(t, large_rule, Export_Writer_Error.None)
    testing.expect_value(t, small_length, large_length)
    for index in 0..<min(small_length, large_length) {
        testing.expect_value(t, small_output[index], large_output[index])
    }
}

// Nested rows emit balanced scopes that the phase-two syntax reader accepts.
@(test)
sharing_writer_emits_nested_entry_scopes :: proc(t: ^testing.T) {
    rows: [3]Export_Row
    rows[0] = {
        kind = .Collection,
        name_length = 1,
        entry_count = 2,
    }
    rows[0].name[0] = 'C'
    rows[1] = {
        kind = .Entry,
        animation_id = sharing_writer_test_animation_id(1),
        depth = 0,
    }
    rows[2] = {
        kind = .Entry,
        animation_id = sharing_writer_test_animation_id(2),
        depth = 1,
    }
    destination, destination_error := make(
        []u8, SHARING_TEST_LIMITS.document_bytes, context.allocator)
    buffer, buffer_error := make([]u8, 64, context.allocator)
    if destination_error != nil || buffer_error != nil {
        delete(destination)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(destination)
    defer delete(buffer)
    length, rule := sharing_writer_test_write(destination, buffer, rows[:])
    testing.expect_value(t, rule, Export_Writer_Error.None)
    syntax_result := syntax.syntax_test_run_vector(
        string(destination[:length]), length)
    testing.expect_value(t, syntax_result.rule, syntax.Rule.None)
}

// An empty collection is emitted as a self-contained record without a scope.
@(test)
sharing_writer_emits_empty_collections_without_begin :: proc(t: ^testing.T) {
    row: Export_Row = {
        kind = .Collection,
        name_length = 5,
    }
    empty_name := "Empty"
    copy(row.name[:], transmute([]u8)empty_name)
    destination, destination_error := make(
        []u8, SHARING_TEST_LIMITS.document_bytes, context.allocator)
    buffer, buffer_error := make([]u8, 16, context.allocator)
    if destination_error != nil || buffer_error != nil {
        delete(destination)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(destination)
    defer delete(buffer)
    length, rule := sharing_writer_test_write(
        destination, buffer, []Export_Row{row})
    testing.expect_value(t, rule, Export_Writer_Error.None)
    text := string(destination[:length])
    testing.expect(t, strings.contains(
        text, "{\"type\":\"collection\",\"id\":\"c1\",\"name\":\"Empty\"}\n"))
    parsed := sharing_test_parse(text, 5)
    defer delete(parsed.backing)
    testing.expect_value(t, parsed.rule, Sharing_Rule.None)
    testing.expect(t, parsed.document.valid)
    testing.expect_value(
        t, parsed.document.collections[0].reason, Collection_Reason.Empty)
}

// A sink callback failure is surfaced by initialization before a row is accepted.
@(test)
sharing_writer_reports_sink_flush_failure :: proc(t: ^testing.T) {
    destination, destination_error := make(
        []u8, SHARING_TEST_LIMITS.document_bytes, context.allocator)
    buffer, buffer_error := make([]u8, 16, context.allocator)
    if destination_error != nil || buffer_error != nil {
        delete(destination)
        delete(buffer)
        testing.expect(t, false)
        return
    }
    defer delete(destination)
    defer delete(buffer)
    length, rule := sharing_writer_test_write(
        destination, buffer, nil, true)
    testing.expect_value(t, length, 0)
    testing.expect_value(t, rule, Export_Writer_Error.Output_Failed)
}
