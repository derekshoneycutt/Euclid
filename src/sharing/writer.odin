package sharing

import syntax "./syntax"
import uuid "core:encoding/uuid"
import "core:unicode/utf8"

Export_Row_Kind :: enum u8 {
    Collection,
    Entry,
}

// Export_Row is one streamed collection or animation entry.
Export_Row :: struct {
    kind: Export_Row_Kind,
    animation_id: uuid.Identifier,
    depth: int,
    name: [SHARING_MAX_NAME_BYTES]u8,
    name_length: int,
    note: [SHARING_MAX_NOTE_BYTES]u8,
    note_length: int,
    has_note: bool,
    notes_on_top: bool,
    entry_count: int,
}

// Export_Sink receives complete chunks and owns no document memory.
Export_Sink :: syntax.Output_Sink
Export_Writer_Error :: syntax.Writer_Error

Export_Scope_Kind :: enum u8 {
    Collection,
    Entry,
}

Export_Scope :: struct {
    kind: Export_Scope_Kind,
    id: [32]u8,
    id_length: int,
}

// Export_Writer owns only fixed scope state and borrows its output sink.
Export_Writer :: struct {
    syntax_writer: syntax.Writer,
    limits: Sharing_Limits,
    scopes: [SHARING_MAX_SCOPE_DEPTH]Export_Scope,
    scope_count: int,
    collection_count: int,
    collection_entries_expected: int,
    collection_entries_written: int,
    entry_count: int,
    document_entry_count: int,
    finished: bool,
    error: Export_Writer_Error,
}

// Initialize a non-allocating file writer and emit its schema-1 header.
export_writer_init :: proc(
    writer: ^Export_Writer, sink: ^Export_Sink,
    limits := DEFAULT_SHARING_LIMITS) -> Export_Writer_Error {
    if writer == nil || limits.document_bytes < 1 ||
        limits.record_bytes < 1 || limits.record_count < 1 ||
        limits.collection_count < 1 || limits.entries_per_collection < 1 ||
        limits.entries_per_document < 1 ||
        limits.note_bytes < 0 || limits.name_bytes < 1 ||
        limits.name_bytes > SHARING_MAX_NAME_BYTES ||
        limits.scope_depth < 2 || limits.scope_depth > SHARING_MAX_SCOPE_DEPTH {
        return .Invalid_Sink
    }
    writer^ = {
        limits = limits,
    }
    if rule := syntax.syntax_writer_init(
        &writer.syntax_writer, sink, limits.document_bytes,
        limits.record_bytes, limits.record_count); rule != .None {
        return export_writer_fail(writer, rule)
    }
    if rule := export_writer_header(&writer.syntax_writer); rule != .None {
        return export_writer_fail(writer, rule)
    }
    return .None
}

// Write one collection or depth-first entry row without retaining it.
export_writer_row :: proc(
    writer: ^Export_Writer, row: Export_Row) -> Export_Writer_Error {
    if !export_writer_ready(writer) {
        return export_writer_fail(writer, .Invalid_State)
    }
    if row.kind == .Collection {
        return export_writer_collection(writer, row)
    }
    if row.kind == .Entry {
        return export_writer_entry(writer, row)
    }
    return export_writer_fail(writer, .Invalid_Record)
}

// Close all scopes, verify row counts, and flush the sink's final chunk.
export_writer_finish :: proc(writer: ^Export_Writer) -> Export_Writer_Error {
    if !export_writer_ready(writer) {
        return export_writer_fail(writer, .Invalid_State)
    }
    if writer.collection_count == 0 {
        return export_writer_fail(writer, .Invalid_Record)
    }
    if rule := export_writer_close_collection(writer); rule != .None {
        return export_writer_fail(writer, rule)
    }
    if writer.scope_count != 0 {
        return export_writer_fail(writer, .Invalid_State)
    }
    if rule := syntax.syntax_writer_finish(&writer.syntax_writer); rule != .None {
        return export_writer_fail(writer, rule)
    }
    writer.finished = true
    return .None
}

// Emit the versioned schema header and declare the supported hierarchy capability.
export_writer_header :: proc(writer: ^syntax.Writer) -> Export_Writer_Error {
    if rule := syntax.syntax_writer_record_begin(writer); rule != .None {
        return rule
    }
    header_prefix := "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[\"entry_hierarchy\"],\"created-on\":"
    if rule := syntax.syntax_writer_record_text(writer, header_prefix);
        rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_timestamp(writer); rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_record_bytes(writer, {'}'}); rule != .None {
        return rule
    }
    return syntax.syntax_writer_record_end(writer)
}

// Start a collection and retain its expected entry count.
export_writer_collection :: proc(
    writer: ^Export_Writer, row: Export_Row) -> Export_Writer_Error {
    name := row.name
    if rule := export_writer_close_collection(writer); rule != .None {
        return export_writer_fail(writer, rule)
    }
    if row.name_length < 1 || row.name_length > len(name) ||
        !sharing_name_valid(string(name[:row.name_length]), writer.limits.name_bytes) ||
        row.entry_count < 0 ||
        row.entry_count > writer.limits.entries_per_collection ||
        writer.collection_count >= writer.limits.collection_count {
        return export_writer_fail(writer, .Invalid_Record)
    }
    writer.collection_count += 1
    writer.collection_entries_expected = row.entry_count
    writer.collection_entries_written = 0
    writer.entry_count = 0
    scope := export_writer_collection_scope(writer.collection_count)
    if rule := export_writer_collection_record(
        &writer.syntax_writer, export_scope_id(&scope),
        string(name[:row.name_length]), row.entry_count > 0); rule != .None {
        return export_writer_fail(writer, rule)
    }
    if row.entry_count > 0 {
        writer.scopes[0] = scope
        writer.scope_count = 1
    }
    return .None
}

// Serialize one collection record, opening a scope only for nonempty collections.
export_writer_collection_record :: proc(
    writer: ^syntax.Writer, id, name: string, open_scope: bool) -> Export_Writer_Error {
    if rule := export_writer_begin_record(writer); rule != .None {
        return rule
    }
    if rule := export_writer_record_text(writer, "{\"type\":\"collection\",\"id\":");
       rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_json_string(writer, id); rule != .None {
        return rule
    }
    if rule := export_writer_string_member(writer, ",\"name\":", name); rule != .None {
        return rule
    }
    if open_scope {
        if rule := export_writer_record_text(writer, ",\"begin\":true"); rule != .None {
            return rule
        }
    }
    if rule := syntax.syntax_writer_record_bytes(writer, {'}'}); rule != .None {
        return rule
    }
    return syntax.syntax_writer_record_end(writer)
}

// Close prior entry scopes to the requested parent depth before writing a row.
export_writer_entry :: proc(
    writer: ^Export_Writer, row: Export_Row) -> Export_Writer_Error {
    name := row.name
    note := row.note
    if rule := export_writer_entry_validate(writer, row, &name, &note); rule != .None {
        return export_writer_fail(writer, rule)
    }
    if rule := export_writer_entry_position(writer, row.depth); rule != .None {
        return export_writer_fail(writer, rule)
    }
    writer.entry_count += 1
    if writer.entry_count > writer.limits.entries_per_collection {
        return export_writer_fail(writer, .Output_Too_Large)
    }
    scope := export_writer_entry_scope(writer.collection_count, writer.entry_count)
    if rule := export_writer_entry_record(&writer.syntax_writer, row, &scope);
       rule != .None {
        return export_writer_fail(writer, rule)
    }
    if row.has_note {
        if rule := export_writer_note(writer, row, &scope); rule != .None {
            return export_writer_fail(writer, rule)
        }
    }
    writer.scopes[writer.scope_count] = scope
    writer.scope_count += 1
    writer.collection_entries_written += 1
    writer.document_entry_count += 1

    return .None
}

// Validate one row against its collection, text, identity, and output limits.
export_writer_entry_validate :: proc(
    writer: ^Export_Writer, row: Export_Row,
    name: ^[SHARING_MAX_NAME_BYTES]u8,
    note: ^[SHARING_MAX_NOTE_BYTES]u8) -> Export_Writer_Error {
    if writer.collection_count == 0 ||
        writer.collection_entries_expected == 0 ||
        row.name_length < 0 || row.name_length > len(name) ||
        row.note_length < 0 || row.note_length > len(note) ||
        writer.collection_entries_written >= writer.collection_entries_expected ||
        writer.document_entry_count >= writer.limits.entries_per_document ||
        row.animation_id == (uuid.Identifier{}) {
        return .Invalid_Record
    }
    if row.depth < 0 || row.depth + 1 >= writer.limits.scope_depth {
        return .Invalid_Scope
    }
    if row.name_length > 0 &&
        !sharing_name_valid(string(name^[:row.name_length]), writer.limits.name_bytes) {
        return .Invalid_Text
    }
    if row.has_note &&
        (row.note_length > writer.limits.note_bytes ||
         !utf8.valid_string(string(note^[:row.note_length])) ||
         bytes_have_carriage_return(note^[:row.note_length])) {
        return .Invalid_Text
    }
    return .None
}

// Close sibling and child scopes until the requested parent scope is current.
export_writer_entry_position :: proc(
    writer: ^Export_Writer, depth: int) -> Export_Writer_Error {
    target_scope_count := depth + 1
    for writer.scope_count > target_scope_count {
        if rule := export_writer_end_scope(writer); rule != .None {
            return rule
        }
    }
    if writer.scope_count != target_scope_count {
        return .Invalid_Scope
    }
    return .None
}

// Serialize an animation entry with a stable readable document-local ID.
export_writer_entry_record :: proc(
    writer: ^syntax.Writer, row: Export_Row,
    scope: ^Export_Scope) -> Export_Writer_Error {
    name := row.name
    if rule := export_writer_begin_record(writer); rule != .None {
        return rule
    }
    if rule := export_writer_record_text(writer, "{\"type\":\"entry\",\"id\":");
       rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_json_string(
        writer, export_scope_id(scope)); rule != .None {
        return rule
    }
    uuid_buffer: [36]u8
    animation_id := uuid.to_string(row.animation_id, uuid_buffer[:])
    if rule := export_writer_string_member(
        writer, ",\"animation_id\":", animation_id); rule != .None {
        return rule
    }
    if row.name_length > 0 {
        if rule := export_writer_string_member(
            writer, ",\"name\":", string(name[:row.name_length])); rule != .None {
            return rule
        }
    }
    if rule := export_writer_record_text(writer, ",\"begin\":true"); rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_record_bytes(writer, {'}'}); rule != .None {
        return rule
    }
    return syntax.syntax_writer_record_end(writer)
}

// Write a JSON string member after its serialized key prefix.
export_writer_string_member :: proc(
    writer: ^syntax.Writer, prefix, value: string) -> Export_Writer_Error {
    if rule := export_writer_record_text(writer, prefix); rule != .None {
        return rule
    }
    return syntax.syntax_writer_json_string(writer, value)
}

// Serialize one exact LaTeX note block with a collision-free readable delimiter.
export_writer_note :: proc(
    writer: ^Export_Writer, row: Export_Row,
    scope: ^Export_Scope) -> Export_Writer_Error {
    note := row.note
    terminator: [64]u8
    terminator_length := 0
    suffix := 0
    for {
        terminator_length = export_writer_note_terminator(
            terminator[:], scope^, suffix)
        if !export_note_delimiter_collides(
            note[:row.note_length],
            string(terminator[:terminator_length])) {
            break
        }
        suffix += 1
        if suffix > writer.limits.entries_per_collection {
            return .Invalid_Block
        }
    }
    prefix := "{\"type\":\"notes\",\"mime\":\"text/latex\",\"notes_on_top\":false"
    if row.notes_on_top {
        prefix = "{\"type\":\"notes\",\"mime\":\"text/latex\",\"notes_on_top\":true"
    }
    return syntax.syntax_writer_delimited_block(
        &writer.syntax_writer,
        prefix,
        note[:row.note_length],
        string(terminator[:terminator_length]))
}

// Construct a readable note terminator from the entry ID and optional collision suffix.
export_writer_note_terminator :: proc(
    destination: []u8, scope: Export_Scope, suffix: int) -> int {
    scope_id := scope.id
    prefix := "::end-"
    copy(destination[:len(prefix)], transmute([]u8)prefix)
    offset := len(prefix)
    copy(destination[offset:], scope_id[:scope.id_length])
    offset += scope.id_length
    if suffix > 0 {
        destination[offset] = '-'
        offset += 1
        offset += export_append_unsigned(destination[offset:], suffix)
    }
    copy(destination[offset:offset+2], "::")
    return offset + 2
}

// Return the UTF-8 document-local ID of a fixed export scope.
export_scope_id :: proc(scope: ^Export_Scope) -> string {
    return string(scope^.id[:scope^.id_length])
}

// Append one nonnegative decimal integer into fixed caller storage.
export_append_unsigned :: proc(destination: []u8, value: int) -> int {
    reversed: [20]u8
    count := 0
    remaining := u64(value)
    for {
        reversed[count] = u8(remaining % 10) + '0'
        count += 1
        remaining /= 10
        if remaining == 0 {
            break
        }
    }
    for index in 0..<count {
        destination[index] = reversed[count - index - 1]
    }
    return count
}

// Construct the collection scope ID cN in fixed storage.
export_writer_collection_scope :: proc(collection_number: int) -> Export_Scope {
    scope: Export_Scope
    scope.kind = .Collection
    scope.id[0] = 'c'
    scope.id_length = 1 + export_append_unsigned(scope.id[1:], collection_number)
    return scope
}

// Construct a collection-qualified entry scope ID cN-eN in fixed storage.
export_writer_entry_scope :: proc(
    collection_number, entry_number: int) -> Export_Scope {
    scope := export_writer_collection_scope(collection_number)
    scope.kind = .Entry
    scope.id[scope.id_length] = '-'
    scope.id[scope.id_length+1] = 'e'
    scope.id_length += 2
    scope.id_length += export_append_unsigned(
        scope.id[scope.id_length:], entry_number)
    return scope
}

// Close the current collection after checking the cursor's declared row count.
export_writer_close_collection :: proc(writer: ^Export_Writer) -> Export_Writer_Error {
    if writer.collection_count == 0 {
        return .None
    }
    for writer.scope_count > 1 {
        if rule := export_writer_end_scope(writer); rule != .None {
            return rule
        }
    }
    if writer.collection_entries_written != writer.collection_entries_expected {
        return .Invalid_Record
    }
    if writer.collection_entries_expected > 0 {
        return export_writer_end_scope(writer)
    }
    return .None
}

// Emit the matching end record and pop the scope stack.
export_writer_end_scope :: proc(writer: ^Export_Writer) -> Export_Writer_Error {
    if writer.scope_count < 1 {
        return .Invalid_State
    }
    scope := writer.scopes[writer.scope_count - 1]
    if rule := export_writer_begin_record(&writer.syntax_writer); rule != .None {
        return rule
    }
    if rule := export_writer_record_text(&writer.syntax_writer, "{\"end\":");
       rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_json_string(
        &writer.syntax_writer, string(scope.id[:scope.id_length])); rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_record_bytes(&writer.syntax_writer, {'}'});
       rule != .None {
        return rule
    }
    if rule := syntax.syntax_writer_record_end(&writer.syntax_writer); rule != .None {
        return rule
    }
    writer.scope_count -= 1
    return .None
}

// Begin one record and write a static JSON fragment.
export_writer_begin_record :: proc(writer: ^syntax.Writer) -> Export_Writer_Error {
    return syntax.syntax_writer_record_begin(writer)
}

// Write a static JSON fragment into the open record.
export_writer_record_text :: proc(
    writer: ^syntax.Writer, value: string) -> Export_Writer_Error {
    return syntax.syntax_writer_record_bytes(writer, transmute([]u8)value)
}

// Test delimiter collisions using exact, unnormalized whole lines.
export_note_delimiter_collides :: proc(payload: []u8, terminator: string) -> bool {
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

// Detect carriage returns that cannot be represented by this delimiter writer.
bytes_have_carriage_return :: proc(value: []u8) -> bool {
    for byte in value {
        if byte == '\r' {
            return true
        }
    }
    return false
}

// Return whether a non-failed, unfinished writer can accept another row.
export_writer_ready :: proc(writer: ^Export_Writer) -> bool {
    return writer != nil && writer.error == .None && !writer.finished
}

// Preserve the first failure across writer layers.
export_writer_fail :: proc(
    writer: ^Export_Writer, failure: Export_Writer_Error) -> Export_Writer_Error {
    if writer != nil && writer.error == .None {
        writer.error = failure
    }
    return failure
}
