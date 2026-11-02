package sharing

import syntax "./syntax"
import json "core:encoding/json"
import uuid "core:encoding/uuid"
import "core:strings"
import "core:unicode/utf8"

Schema_Frame_Kind :: enum u8 {
    Collection,
    Entry,
    Skipped,
}

Schema_Frame :: struct {
    kind: Schema_Frame_Kind,
    collection_index: int,
    entry_index: int,
    entry_start: int,
    scope_id: string,
}

// Reader validates schema 1 while the syntax layer incrementally emits records.
Reader :: struct {
    syntax_reader: syntax.Reader,
    workspace: Staging_Workspace,
    document: ^Staged_Document,
    limits: Sharing_Limits,
    frames: [SHARING_MAX_SCOPE_DEPTH]Schema_Frame,
    frame_count: int,
    header_seen: bool,
    block_note_pending: bool,
    block_note_entry: int,
    block_note_mime: Note_Mime,
    block_notes_on_top: bool,
    header_detail: [64]u8,
    header_detail_length: int,
    failed: bool,
    finished: bool,
    failure: Sharing_Rule,
}

Reader_Feed_Step :: struct {
    consumed: int,
    event: syntax.Event,
    failure: Sharing_Rule,
    needs_more: bool,
}

Entry_Values :: struct {
    animation_id: uuid.Identifier,
    id: string,
    name: string,
    name_rule: Sharing_Rule,
    failure: Sharing_Rule,
}

Collection_Name :: struct {
    value: string,
    rule: Sharing_Rule,
}

Note_Options :: struct {
    mime: Note_Mime,
    on_top: bool,
    rejected: bool,
    failure: Sharing_Rule,
}

Note_Validation_Result :: struct {
    rejected: bool,
    failure: Sharing_Rule,
}

Unknown_Scope_Result :: struct {
    opened: bool,
    failure: Sharing_Rule,
}

// Retain a collection-local diagnostic while allowing other collections to stage.
Collection_Failure :: struct {
    reason: Collection_Reason,
    rule: Sharing_Rule,
    line: int,
    scope_id: string,
    detail: string,
}

// Initialize schema validation over owner-provided staging and parser memory.
reader_init :: proc(
    reader: ^Reader, workspace: Staging_Workspace,
    document: ^Staged_Document, limits := DEFAULT_SHARING_LIMITS) -> Sharing_Rule {
    if reader == nil || document == nil || !document.initialized ||
        document.collection_count != 0 || document.entry_total != 0 ||
        document.seen_id_count != 0 || document.diagnostic_count != 0 ||
        limits.document_bytes < 1 || limits.record_bytes < 1 ||
        limits.record_bytes > max(int) / 4 ||
        limits.record_count < 1 || limits.collection_count < 1 ||
        limits.entries_per_collection < 1 || limits.entries_per_document < 1 ||
        limits.note_bytes < 0 || limits.name_bytes < 1 ||
        limits.name_bytes > SHARING_MAX_NAME_BYTES ||
        limits.scope_depth < 1 ||
        limits.scope_depth > SHARING_MAX_SCOPE_DEPTH ||
        limits.diagnostic_count < 1 ||
        len(document.collections) < limits.collection_count ||
        len(document.entries_storage) < limits.entries_per_document ||
        len(document.seen_ids) < limits.record_count ||
        document.limits.diagnostic_count < limits.diagnostic_count ||
        len(workspace.line_buffer) < limits.record_bytes ||
        len(workspace.json_scratch) < 4 * limits.record_bytes ||
        len(workspace.block_buffer) < limits.note_bytes {
        return .Staged_Capacity_Exceeded
    }
    syntax_limits: syntax.Limits = {
        document_bytes = limits.document_bytes,
        record_bytes = limits.record_bytes,
        record_count = limits.record_count,
        scope_depth = limits.scope_depth,
        block_bytes = limits.document_bytes,
    }
    if !syntax.syntax_reader_init(
        &reader.syntax_reader,
        workspace.line_buffer,
        workspace.json_scratch,
        syntax_limits) {
        return .Staged_Capacity_Exceeded
    }
    reader^ = {
        syntax_reader = reader.syntax_reader,
        workspace = workspace,
        document = document,
        limits = limits,
    }
    return .None
}

// Feed arbitrary input chunks until all bytes are consumed or the parser needs more.
reader_feed :: proc(
    reader: ^Reader, bytes: []u8,
    is_final: bool) -> (consumed: int, failure: Sharing_Rule) {
    if reader == nil || reader.document == nil {
        return 0, .Invalid_Record
    }
    if reader.failed {
        return 0, reader.failure
    }
    if reader.finished {
        return 0, .Invalid_Record
    }
    offset := 0
    for {
        step := sharing_reader_next_event(reader, bytes[offset:], is_final)
        offset += step.consumed
        if step.failure != .None {
            return offset, step.failure
        }
        if step.needs_more {
            return offset, .None
        }
        rule := sharing_reader_event(reader, step.event)
        if rule != .None {
            return offset, rule
        }
        if step.event.kind == .End {
            reader.finished = true
            reader.document^.valid = true
            return offset, .None
        }
        if offset == len(bytes) && !is_final {
            return offset, .None
        }
    }
}

// Pull a queued syntax event or feed bytes until the next event is available.
sharing_reader_next_event :: proc(
    reader: ^Reader, bytes: []u8, is_final: bool) -> Reader_Feed_Step {
    event := syntax.syntax_next(&reader.syntax_reader)
    if event.kind != .Need_More {
        return {
            event = event,
        }
    }
    consumed, diagnostic := syntax.syntax_feed(
        &reader.syntax_reader, bytes, is_final)
    if diagnostic.rule != .None {
        rule := sharing_rule_from_syntax(diagnostic.rule)
        if diagnostic.rule == .Block_Too_Large_For_Destination &&
            reader.block_note_pending {
            rule = .Note_Too_Large
        }
        return {
            consumed = consumed,
            failure = sharing_reader_fail(
                reader, rule, diagnostic.line,
                string(diagnostic.scope_id[:diagnostic.scope_id_length])),
        }
    }
    event = syntax.syntax_next(&reader.syntax_reader)
    return {
        consumed = consumed,
        event = event,
        needs_more = event.kind == .Need_More,
    }
}

// Dispatch syntax events to the schema state machine and finalize valid input.
sharing_reader_event :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    switch event.kind {
    case .Record:
        return sharing_record(reader, event)
    case .Block_Begin:
        return sharing_block_begin(reader, event)
    case .Block_End:
        return sharing_block_end(reader, event)
    case .Scope_End:
        return sharing_scope_end(reader, event)
    case .End:
        if !reader.header_seen || reader.document^.collection_count == 0 {
            return sharing_reader_fail(reader, .Invalid_Header, event.line, "")
        }
    case .Need_More:
        return .None
    case .Error:
        return sharing_reader_fail(reader, .Invalid_Record, event.line, "")
    case:
    }
    return .None
}

// Validate the schema header once, then route later records by their type.
sharing_record :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if !reader.header_seen {
        reader.header_detail_length = 0
        rule := sharing_header_validate(reader, event.record)
        if rule != .None {
            detail := string(reader.header_detail[:reader.header_detail_length])
            return sharing_reader_fail(reader, rule, event.line, "", detail)
        }
        reader.header_seen = true
        return .None
    }
    if sharing_inside_skipped_scope(reader) {
        return sharing_skip_open_scope(reader, event)
    }
    if rule := sharing_reserved_members_validate(event.record); rule != .None {
        return sharing_reader_fail(reader, rule, event.line, "")
    }
    kind, present := sharing_record_type(event.record)
    if !present || len(kind) == 0 {
        return sharing_reader_fail(reader, .Invalid_Record, event.line, "")
    }
    switch kind {
    case "collection":
        return sharing_collection_record(reader, event)
    case "entry":
        return sharing_entry_record(reader, event)
    case "notes":
        return sharing_reader_fail(reader, .Invalid_Notes, event.line, "")
    case:
        return sharing_unknown_record(reader, event, kind)
    }
}

// Stage a root collection and open its optional scope.
sharing_collection_record :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    document := reader.document
    record := event.record
    if reader.frame_count != 0 {
        return sharing_reader_fail(reader, .Invalid_Collection, event.line, "")
    }
    if document^.collection_count >= reader.limits.collection_count {
        return sharing_reader_fail(reader, .Too_Many_Collections, event.line, "")
    }
    if _, has_animation_id := record["animation_id"]; has_animation_id {
        return sharing_reader_fail(reader, .Invalid_Collection, event.line, "")
    }
    name := sharing_collection_name_validate(reader, record)
    id, id_ok := sharing_record_string(record, "id")
    if !id_ok {
        return sharing_reader_fail(reader, .Invalid_Collection, event.line, "")
    }
    if rule := sharing_document_id_add(reader, id); rule != .None {
        return sharing_reader_fail(reader, rule, event.line, id)
    }
    return sharing_collection_stage(reader, event, id, name)
}

// Validate the optional collection name and select its local rejection rule.
sharing_collection_name_validate :: proc(
    reader: ^Reader, record: json.Object) -> Collection_Name {
    name_value, has_name := record["name"]
    name, name_ok := name_value.(string)
    if !has_name || !name_ok {
        return {
            rule = .Invalid_Collection,
        }
    }
    if sharing_name_valid(name, reader.limits.name_bytes) {
        return {
            value = name,
            rule = .None,
        }
    }
    rule := Sharing_Rule.Invalid_Collection
    if len(name) > reader.limits.name_bytes {
        rule = .Name_Too_Large
    }
    return {
        rule = rule,
    }
}

// Retain the collection and record invalid names as collection-local diagnostics.
sharing_collection_stage :: proc(
    reader: ^Reader, event: syntax.Event, id: string,
    name: Collection_Name) -> Sharing_Rule {
    document := reader.document
    record := event.record
    copied_name := ""
    if len(name.value) > 0 {
        cloned_name, alloc_error := strings.clone(name.value, document^.allocator)
        if alloc_error != nil {
            return sharing_reader_fail(
                reader, .Staged_Capacity_Exceeded, event.line, id)
        }
        copied_name = cloned_name
    }
    index := document^.collection_count
    document^.collections[index] = {
        name = copied_name,
        line = event.line,
    }
    document^.collection_count += 1
    if name.rule != .None {
        _ = sharing_collection_reject(
            reader, index, {
                reason = .Invalid_Name,
                rule = name.rule,
                line = event.line,
                scope_id = id,
            })
    }
    begin := sharing_record_begin(record)
    if begin {
        return sharing_frame_push(reader, .Collection, index, -1, id)
    }
    sharing_collection_close(reader, index, document^.entry_total)
    return .None
}

// Enforce collection-local entry ordering and document bounds.
sharing_entry_record :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if reader.frame_count == 0 ||
        reader.frames[reader.frame_count - 1].kind == .Skipped {
        return sharing_reader_fail(reader, .Invalid_Entry, event.line, "")
    }
    parent_frame := reader.frames[reader.frame_count - 1]
    if parent_frame.kind == .Entry {
        return sharing_reader_fail(
            reader, .Unsupported_Hierarchy, event.line,
            parent_frame.scope_id, "entry_hierarchy")
    }
    document := reader.document
    if document^.entry_total >= reader.limits.entries_per_document {
        return sharing_reader_fail(
            reader, .Too_Many_Entries, event.line, parent_frame.scope_id)
    }
    collection := &document^.collections[parent_frame.collection_index]
    if collection^.entry_count >= reader.limits.entries_per_collection {
        return sharing_reader_fail(
            reader, .Too_Many_Entries, event.line, parent_frame.scope_id)
    }
    return sharing_entry_append(reader, event, parent_frame.collection_index)
}

// Validate and retain an entry before exposing it through the staged collection.
sharing_entry_append :: proc(
    reader: ^Reader, event: syntax.Event, collection_index: int) -> Sharing_Rule {
    document := reader.document
    record := event.record
    values := sharing_entry_validate(reader, event)
    if values.failure != .None {
        return values.failure
    }
    if rule := sharing_document_id_add(reader, values.id); rule != .None {
        return sharing_reader_fail(reader, rule, event.line, values.id)
    }
    start := sharing_collection_entry_start(reader, collection_index)
    if sharing_entry_is_duplicate(
        reader, start, document^.entry_total, values.animation_id) {
        _ = sharing_collection_reject(
            reader, collection_index, {
                reason = .Duplicate_Animation,
                rule = .Duplicate_Animation,
                line = event.line,
                scope_id = values.id,
            })
        if sharing_record_begin(record) {
            return sharing_frame_push(
                reader, .Skipped, collection_index, -1, values.id)
        }
        return .None
    }
    return sharing_entry_commit(reader, event, collection_index, values)
}

// Retain the validated entry and update its owning collection.
sharing_entry_commit :: proc(
    reader: ^Reader, event: syntax.Event,
    collection_index: int, values: Entry_Values) -> Sharing_Rule {
    document := reader.document
    record := event.record
    copied_name := ""
    if len(values.name) > 0 {
        cloned_name, alloc_error := strings.clone(values.name, document^.allocator)
        if alloc_error != nil {
            return sharing_reader_fail(
                reader, .Staged_Capacity_Exceeded, event.line, values.id)
        }
        copied_name = cloned_name
    }
    index := document^.entry_total
    document^.entries_storage[index] = {
        animation_id = values.animation_id,
        parent = -1,
        name = copied_name,
        line = event.line,
    }
    document^.entry_total += 1
    document^.collections[collection_index].entry_count += 1
    if values.name_rule != .None {
        _ = sharing_collection_reject(
            reader, collection_index, {
                reason = .Invalid_Name,
                rule = values.name_rule,
                line = event.line,
                scope_id = values.id,
            })
    }
    if sharing_record_begin(record) {
        return sharing_frame_push(reader, .Entry, collection_index, index, values.id)
    }
    sharing_collection_close_entries(reader, collection_index)
    return .None
}

// Validate an entry's UUID, optional name, and required document ID.
sharing_entry_validate :: proc(
    reader: ^Reader, event: syntax.Event) -> Entry_Values {
    record := event.record
    animation_text, animation_present := sharing_record_string(record, "animation_id")
    animation_id, id_error := uuid.read(animation_text)
    if !animation_present || id_error != .None || animation_id == (uuid.Identifier{}) {
        return {
            failure = sharing_reader_fail(
                reader, .Invalid_Animation_Id, event.line, ""),
        }
    }
    name, name_rule := sharing_entry_name(record, reader.limits.name_bytes)
    entry_id, entry_id_present := sharing_record_string(record, "id")
    if !entry_id_present {
        return {
            failure = sharing_reader_fail(reader, .Invalid_Entry, event.line, ""),
        }
    }
    return {
        animation_id = animation_id,
        id = entry_id,
        name = name,
        name_rule = name_rule,
    }
}

// Validate an optional entry name and return its local diagnostic rule.
sharing_entry_name :: proc(
    record: json.Object, maximum: int) -> (string, Sharing_Rule) {
    value, present := record["name"]
    if !present {
        return "", .None
    }
    name, valid := value.(string)
    if !valid || !sharing_name_valid(name, maximum) {
        if valid && len(name) > maximum {
            return "", .Name_Too_Large
        }
        return "", .Invalid_Entry
    }
    return name, .None
}

// Detect duplicate animation IDs within the current collection range.
sharing_entry_is_duplicate :: proc(
    reader: ^Reader, start, end: int, animation_id: uuid.Identifier) -> bool {
    for index in start..<end {
        if reader.document^.entries_storage[index].animation_id == animation_id {
            return true
        }
    }
    return false
}

// Choose bounded note delivery or discard for an emitted block descriptor.
sharing_block_begin :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if sharing_inside_skipped_scope(reader) {
        rule := syntax.syntax_block_skip(&reader.syntax_reader)
        return sharing_syntax_action_result(reader, rule, event.line)
    }
    kind, present := sharing_record_type(event.record)
    if present && kind == "notes" {
        if rule := sharing_note_prepare(reader, event); rule != .None {
            return rule
        }
        if !reader.block_note_pending {
            diagnostic := syntax.syntax_block_skip(&reader.syntax_reader)
            return sharing_syntax_action_result(reader, diagnostic, event.line)
        }
        diagnostic := syntax.syntax_block_deliver(
            &reader.syntax_reader,
            reader.workspace.block_buffer[:reader.limits.note_bytes],
            true)
        return sharing_syntax_action_result(reader, diagnostic, event.line)
    }
    if !present {
        return sharing_reader_fail(reader, .Invalid_Record, event.line, "")
    }
    if rule := sharing_unknown_content(reader, event.record, kind, event.line, true);
       rule != .None {
        return rule
    }
    diagnostic := syntax.syntax_block_skip(&reader.syntax_reader)
    return sharing_syntax_action_result(reader, diagnostic, event.line)
}

// Validate note metadata and reserve the current entry for one block.
sharing_note_prepare :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if reader.frame_count == 0 ||
        reader.frames[reader.frame_count - 1].kind != .Entry ||
        reader.block_note_pending {
        return sharing_reader_fail(reader, .Invalid_Notes, event.line, "")
    }
    options := sharing_note_options(reader, event)
    if options.rejected {
        return options.failure
    }
    entry_index := reader.frames[reader.frame_count - 1].entry_index
    validation := sharing_note_capacity_validate(reader, event, entry_index)
    if validation.rejected {
        return validation.failure
    }
    reader.block_note_pending = true
    reader.block_note_entry = entry_index
    reader.block_note_mime = options.mime
    reader.block_notes_on_top = options.on_top
    return .None
}

// Validate the note MIME and optional placement flag.
sharing_note_options :: proc(
    reader: ^Reader, event: syntax.Event) -> Note_Options {
    record := event.record
    mime, mime_ok := sharing_record_string(record, "mime")
    note_mime := Note_Mime.None
    if mime == "text/latex" {
        note_mime = .Latex
    } else if mime == "text/plain" {
        note_mime = .Plain
    }
    if !mime_ok || note_mime == .None {
        return {
            rejected = true,
            failure = sharing_note_reject(
                reader, event, .Invalid_Notes, .Invalid_Notes),
        }
    }
    top := false
    if value, present := record["notes_on_top"]; present {
        parsed, valid := value.(bool)
        if !valid {
            return {
                rejected = true,
                failure = sharing_note_reject(
                    reader, event, .Invalid_Notes, .Invalid_Notes),
            }
        }
        top = parsed
    }
    return {
        mime = note_mime,
        on_top = top,
    }
}

// Reject duplicate or oversized note blocks before consuming their payloads.
sharing_note_capacity_validate :: proc(
    reader: ^Reader, event: syntax.Event,
    entry_index: int) -> Note_Validation_Result {
    record := event.record
    if reader.document^.entries_storage[entry_index].has_note {
        return {
            rejected = true,
            failure = sharing_note_reject(
                reader, event, .Invalid_Notes, .Invalid_Notes),
        }
    }
    if value, present := record["block_bytes"]; present {
        length, integer := value.(json.Integer)
        if !integer || length < 0 {
            return {
                rejected = true,
                failure = sharing_note_reject(
                    reader, event, .Invalid_Notes, .Invalid_Notes),
            }
        }
        if length > json.Integer(reader.limits.note_bytes) {
            return {
                rejected = true,
                failure = sharing_note_reject(
                    reader, event, .Note_Too_Large, .Note_Too_Large),
            }
        }
    }
    return {}
}

// Mark note-local schema failures on the owning collection without aborting staging.
sharing_note_reject :: proc(
    reader: ^Reader, event: syntax.Event,
    reason: Collection_Reason, rule: Sharing_Rule) -> Sharing_Rule {
    frame := reader.frames[reader.frame_count - 1]
    return sharing_collection_reject(
        reader, frame.collection_index, {
            reason = reason,
            rule = rule,
            line = event.line,
            scope_id = frame.scope_id,
        })
}

// Validate and copy completed note bytes into the document allocator.
sharing_block_end :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if !reader.block_note_pending {
        return .None
    }
    if event.block_overflowed || event.block_bytes > reader.limits.note_bytes {
        reader.block_note_pending = false
        frame := reader.frames[reader.frame_count - 1]
        return sharing_collection_reject(
            reader, frame.collection_index, {
                reason = .Note_Too_Large,
                rule = .Note_Too_Large,
                line = event.line,
                scope_id = frame.scope_id,
            })
    }
    bytes := reader.workspace.block_buffer[:event.delivered_bytes]
    if !utf8.valid_string(string(bytes)) {
        reader.block_note_pending = false
        frame := reader.frames[reader.frame_count - 1]
        return sharing_collection_reject(
            reader, frame.collection_index, {
                reason = .Invalid_Notes,
                rule = .Invalid_Utf8,
                line = event.line,
                scope_id = frame.scope_id,
            })
    }
    note, alloc_error := strings.clone(string(bytes), reader.document^.allocator)
    if alloc_error != nil {
        return sharing_reader_fail(reader, .Staged_Capacity_Exceeded, event.line, "")
    }
    entry := &reader.document^.entries_storage[reader.block_note_entry]
    entry^.note = note
    entry^.note_mime = reader.block_note_mime
    entry^.notes_on_top = reader.block_notes_on_top
    entry^.has_note = true
    reader.block_note_pending = false
    return .None
}

// Close the matching schema scope and publish the collection's entry slice.
sharing_scope_end :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if reader.frame_count == 0 {
        return sharing_reader_fail(reader, .Invalid_Scope, event.line, event.scope_id)
    }
    frame := reader.frames[reader.frame_count - 1]
    if frame.scope_id != event.scope_id {
        return sharing_reader_fail(
            reader, .Mismatched_Scope_End, event.line, event.scope_id)
    }
    reader.frame_count -= 1
    if frame.kind == .Collection {
        sharing_collection_close(reader, frame.collection_index, frame.entry_start)
    }
    return .None
}

// Apply optional-content policy to an unknown record and its scope.
sharing_unknown_record :: proc(
    reader: ^Reader, event: syntax.Event, kind: string) -> Sharing_Rule {
    record := event.record
    optional := false
    if value, present := record["optional"]; present {
        parsed, valid := value.(bool)
        if !valid {
            return sharing_reader_fail(reader, .Invalid_Record, event.line, "")
        }
        optional = parsed
    }
    if optional {
        reader.document^.skipped_optional += 1
        staged_diagnostic_add(reader.document, event.line, .Unsupported_Content)
        if sharing_record_begin(record) {
            id, present := sharing_record_string(record, "id")
            if !present {
                return sharing_reader_fail(reader, .Invalid_Scope, event.line, "")
            }
            if rule := sharing_document_id_add(reader, id); rule != .None {
                return sharing_reader_fail(reader, rule, event.line, id)
            }
            return sharing_frame_push(reader, .Skipped, -1, -1, id)
        }
        return .None
    }
    return sharing_unknown_content(reader, record, kind, event.line, false)
}

// Apply failure-scope policy to unsupported records and literal blocks.
sharing_unknown_content :: proc(
    reader: ^Reader, record: json.Object, kind: string,
    line: int, block: bool) -> Sharing_Rule {
    optional := false
    if value, present := record["optional"]; present {
        parsed, valid := value.(bool)
        if !valid {
            return sharing_reader_fail(reader, .Invalid_Record, line, "")
        }
        optional = parsed
    }
    if optional {
        reader.document^.skipped_optional += 1
        staged_diagnostic_add(reader.document, line, .Unsupported_Content)
        return .None
    }
    return sharing_unknown_failure_scope(reader, record, kind, line, block)
}

// Apply failure-scope policy after optional-content handling.
sharing_unknown_failure_scope :: proc(
    reader: ^Reader, record: json.Object, kind: string,
    line: int, block: bool) -> Sharing_Rule {
    scope := "document"
    if value, present := record["failure_scope"]; present {
        parsed, valid := value.(string)
        if !valid || (parsed != "document" && parsed != "entry" && parsed != "record") {
            return sharing_reader_fail(reader, .Invalid_Failure_Scope, line, "")
        }
        scope = parsed
    }
    if scope == "entry" {
        if rule := sharing_omit_current_entry(reader, line); rule != .None {
            return rule
        }
        return sharing_unknown_scope_open(reader, record, line, block).failure
    }
    if scope == "record" {
        result := sharing_unknown_scope_open(reader, record, line, block)
        if result.failure != .None {
            return result.failure
        }
        if result.opened {
            return .None
        }
        staged_diagnostic_add(reader.document, line, .Unsupported_Content)
        return .None
    }
    return sharing_reader_fail(reader, .Unsupported_Content, line, "", kind)
}

// Push a skipped scope when unsupported content is explicitly scoped.
sharing_unknown_scope_open :: proc(
    reader: ^Reader, record: json.Object,
    line: int, block: bool) -> Unknown_Scope_Result {
    if block || !sharing_record_begin(record) {
        return {}
    }
    id, present := sharing_record_string(record, "id")
    if !present {
        return {
            failure = sharing_reader_fail(reader, .Invalid_Scope, line, ""),
        }
    }
    if rule := sharing_document_id_add(reader, id); rule != .None {
        return {
            failure = sharing_reader_fail(reader, rule, line, id),
        }
    }
    rule := sharing_frame_push(reader, .Skipped, -1, -1, id)
    return {
        opened = rule == .None,
        failure = rule,
    }
}

// Omit the current entry when unsupported content is scoped to that entry.
sharing_omit_current_entry :: proc(reader: ^Reader, line: int) -> Sharing_Rule {
    if reader.frame_count == 0 ||
        reader.frames[reader.frame_count - 1].kind != .Entry {
        return sharing_reader_fail(reader, .Invalid_Failure_Scope, line, "")
    }
    frame := &reader.frames[reader.frame_count - 1]
    collection := &reader.document^.collections[frame^.collection_index]
    if frame^.entry_index != reader.document^.entry_total - 1 {
        return sharing_reader_fail(reader, .Unsupported_Content, line, frame^.scope_id)
    }
    reader.document^.entry_total -= 1
    collection^.entry_count -= 1
    frame^.kind = .Skipped
    staged_diagnostic_add(
        reader.document, line, .Unsupported_Content, frame^.scope_id)
    return .None
}

// Consume descendants of an ignored scope without promoting their contents.
sharing_skip_open_scope :: proc(reader: ^Reader, event: syntax.Event) -> Sharing_Rule {
    if event.kind == .Block_Begin {
        diagnostic := syntax.syntax_block_skip(&reader.syntax_reader)
        return sharing_syntax_action_result(reader, diagnostic, event.line)
    }
    if event.kind == .Record && sharing_record_begin(event.record) {
        id, present := sharing_record_string(event.record, "id")
        if !present {
            return sharing_reader_fail(reader, .Invalid_Scope, event.line, "")
        }
        if rule := sharing_document_id_add(reader, id); rule != .None {
            return sharing_reader_fail(reader, rule, event.line, id)
        }
        return sharing_frame_push(reader, .Skipped, -1, -1, id)
    }
    if event.kind == .Scope_End {
        return sharing_scope_end(reader, event)
    }
    return .None
}

// Validate reserved forward-compatibility fields wherever a record uses them.
sharing_reserved_members_validate :: proc(record: json.Object) -> Sharing_Rule {
    if value, present := record["failure_scope"]; present {
        scope, valid := value.(string)
        if !valid || (scope != "document" && scope != "entry" && scope != "record") {
            return .Invalid_Failure_Scope
        }
    }
    if value, present := record["preserve"]; present {
        preserve, valid := value.(string)
        if !valid ||
           (preserve != "always" && preserve != "unmodified" && preserve != "never") {
            return .Invalid_Record
        }
    }
    if value, present := record["optional"]; present {
        if _, valid := value.(bool); !valid {
            return .Invalid_Record
        }
    }
    return .None
}

// Validate the schema version, required capabilities, and optional timestamp.
sharing_header_validate :: proc(reader: ^Reader, record: json.Object) -> Sharing_Rule {
    format, format_ok := sharing_record_string(record, "format")
    framing, framing_ok := sharing_record_integer(record, "framing_version")
    schema, schema_ok := sharing_record_integer(record, "schema_version")
    if !format_ok || format != "euclid-collections" ||
        !framing_ok || framing != 1 {
        return .Unsupported_Framing
    }
    if !schema_ok || schema < 1 {
        return .Unsupported_Schema
    }
    if rule := sharing_header_minimum_schema(record, schema); rule != .None {
        return rule
    }
    if rule := sharing_header_capabilities(reader, record); rule != .None {
        return rule
    }
    return sharing_header_timestamp(record)
}

// Validate an optional minimum compatible schema version.
sharing_header_minimum_schema :: proc(
    record: json.Object, schema: int) -> Sharing_Rule {
    minimum_value, has_minimum := record["minimum_reader_schema_version"]
    minimum, minimum_valid := minimum_value.(json.Integer)
    minimum_present := has_minimum && minimum_valid &&
        minimum >= 0 && minimum <= json.Integer(max(int))
    if has_minimum && !minimum_present {
        return .Unsupported_Schema
    }
    if schema > 1 && (!minimum_present || minimum > 1) {
        return .Unsupported_Schema
    }
    if minimum_present && (minimum < 1 || minimum > json.Integer(schema)) {
        return .Unsupported_Schema
    }
    return .None
}

// Validate supported and duplicate required capabilities, preserving unknown names.
sharing_header_capabilities :: proc(
    reader: ^Reader, record: json.Object) -> Sharing_Rule {
    requires, present := record["requires"]
    capabilities, valid := requires.(json.Array)
    if !present || !valid {
        return .Invalid_Header
    }
    for value, index in capabilities {
        capability, is_string := value.(string)
        if !is_string {
            return .Invalid_Header
        }
        if capability != "entry_hierarchy" {
            reader.header_detail_length = min(len(capability), len(reader.header_detail))
            copy(
                reader.header_detail[:],
                transmute([]u8)capability[:reader.header_detail_length])
            return .Unknown_Requirement
        }
        for earlier in 0..<index {
            prior, prior_ok := capabilities[earlier].(string)
            if prior_ok && prior == capability {
                return .Invalid_Header
            }
        }
    }
    return .None
}

// Validate the optional creation timestamp without coercing other JSON types.
sharing_header_timestamp :: proc(record: json.Object) -> Sharing_Rule {
    if value, present := record["created-on"]; present {
        timestamp, valid := value.(string)
        if !valid || !sharing_timestamp_valid(timestamp) {
            return .Invalid_Timestamp
        }
    }
    return .None
}

// Validate the calendar date, clock, fractional seconds, and RFC 3339 zone.
sharing_timestamp_valid :: proc(value: string) -> bool {
    if len(value) < 20 || value[4] != '-' || value[7] != '-' ||
        (value[10] != 'T' && value[10] != 't') ||
        value[13] != ':' || value[16] != ':' {
        return false
    }
    if !sharing_timestamp_digits_valid(value) {
        return false
    }
    year := sharing_two_digits(value[0:2])*100 +
        sharing_two_digits(value[2:4])
    month := sharing_two_digits(value[5:7])
    day := sharing_two_digits(value[8:10])
    hour := sharing_two_digits(value[11:13])
    minute := sharing_two_digits(value[14:16])
    second := sharing_two_digits(value[17:19])
    if month < 1 || month > 12 || day < 1 ||
        day > sharing_month_days(year, month) ||
        hour > 23 || minute > 59 || second > 60 {
        return false
    }
    return sharing_timestamp_suffix_valid(value[19:])
}

// Validate numeric timestamp fields while skipping RFC 3339 separators.
sharing_timestamp_digits_valid :: proc(value: string) -> bool {
    for index in 0..<19 {
        if index == 4 || index == 7 || index == 10 || index == 13 || index == 16 {
            continue
        }
        if value[index] < '0' || value[index] > '9' {
            return false
        }
    }
    return true
}

// Validate fractional seconds and the trailing UTC offset.
sharing_timestamp_suffix_valid :: proc(suffix: string) -> bool {
    zone := suffix
    if len(suffix) > 0 && suffix[0] == '.' {
        fraction_end := 1
        for fraction_end < len(suffix) &&
            suffix[fraction_end] >= '0' && suffix[fraction_end] <= '9' {
            fraction_end += 1
        }
        if fraction_end == 1 {
            return false
        }
        zone = suffix[fraction_end:]
    }
    if zone == "Z" || zone == "z" {
        return true
    }
    if len(zone) < 6 || (zone[0] != '+' && zone[0] != '-') ||
        zone[3] != ':' || zone[1] < '0' || zone[1] > '9' ||
        zone[2] < '0' || zone[2] > '9' ||
        zone[4] < '0' || zone[4] > '9' ||
        zone[5] < '0' || zone[5] > '9' {
        return false
    }
    hours := int(zone[1]-'0')*10 + int(zone[2]-'0')
    minutes := int(zone[4]-'0')*10 + int(zone[5]-'0')
    return len(zone) == 6 && hours <= 23 && minutes <= 59
}

// Convert a validated pair of decimal digits into its integer value.
sharing_two_digits :: proc(value: string) -> int {
    return int(value[0]-'0')*10 + int(value[1]-'0')
}

// Return the number of calendar days in a validated month.
sharing_month_days :: proc(year, month: int) -> int {
    switch month {
    case 2:
        leap := year%4 == 0 && (year%100 != 0 || year%400 == 0)
        if leap {
            return 29
        }
        return 28
    case 4, 6, 9, 11:
        return 30
    case:
        return 31
    }
}

// Push a scope only after its document-local structural ID is retained.
sharing_frame_push :: proc(
    reader: ^Reader, kind: Schema_Frame_Kind,
    collection_index, entry_index: int, id: string) -> Sharing_Rule {
    if reader.frame_count >= len(reader.frames) {
        return sharing_reader_fail(reader, .Too_Many_Scopes, 0, id)
    }
    copied_id := ""
    for index in 0..<reader.document^.seen_id_count {
        if reader.document^.seen_ids[index] == id {
            copied_id = reader.document^.seen_ids[index]
            break
        }
    }
    if len(copied_id) == 0 {
        return sharing_reader_fail(reader, .Invalid_Scope, 0, id)
    }
    frame: Schema_Frame = {
        kind = kind,
        collection_index = collection_index,
        entry_index = entry_index,
        entry_start = reader.document^.entry_total,
        scope_id = copied_id,
    }
    reader.frames[reader.frame_count] = frame
    reader.frame_count += 1
    return .None
}

// Finalize a collection's entry slice and its empty/importable state.
sharing_collection_close :: proc(
    reader: ^Reader, collection_index, entry_start: int) {
    document := reader.document
    sharing_collection_close_entries(reader, collection_index)
    collection := &document^.collections[collection_index]
    collection^.entries = document^.entries_storage[entry_start:document^.entry_total]
    if collection^.reason != .None && collection^.reason != .Empty {
        collection^.importable = false
        return
    }
    collection^.importable = collection^.entry_count > 0
    if !collection^.importable {
        collection^.reason = .Empty
    }
}

// Refresh the collection's importability after entry-level changes.
sharing_collection_close_entries :: proc(reader: ^Reader, collection_index: int) {
    if collection_index < 0 ||
        collection_index >= reader.document^.collection_count {
        return
    }
    collection := &reader.document^.collections[collection_index]
    if collection^.reason != .None && collection^.reason != .Empty {
        collection^.importable = false
        return
    }
    if collection^.entry_count == 0 {
        collection^.reason = .Empty
        collection^.importable = false
    } else {
        collection^.importable = true
        collection^.reason = .None
    }
}

// Retain a collection-local diagnostic while allowing other collections to stage.
sharing_collection_reject :: proc(
    reader: ^Reader, collection_index: int,
    failure: Collection_Failure) -> Sharing_Rule {
    if reader == nil || reader.document == nil ||
        collection_index < 0 ||
        collection_index >= reader.document^.collection_count {
        return sharing_reader_fail(
            reader, failure.rule, failure.line, failure.scope_id, failure.detail)
    }
    collection := &reader.document^.collections[collection_index]
    if collection^.reason == .None || collection^.reason == .Empty {
        collection^.reason = failure.reason
    }
    collection^.importable = false
    staged_diagnostic_add(
        reader.document, failure.line, failure.rule,
        failure.scope_id, failure.detail)
    return .None
}

// Find the entry range start used for collection-local duplicate checks.
sharing_collection_entry_start :: proc(reader: ^Reader, index: int) -> int {
    for frame_index in 0..<reader.frame_count {
        frame := reader.frames[frame_index]
        if frame.kind == .Collection && frame.collection_index == index {
            return frame.entry_start
        }
    }
    return 0
}

// Retain a unique document ID in the staging allocator.
sharing_document_id_add :: proc(reader: ^Reader, id: string) -> Sharing_Rule {
    document := reader.document
    if len(id) == 0 {
        return .Invalid_Scope
    }
    for index in 0..<document^.seen_id_count {
        if document^.seen_ids[index] == id {
            return .Duplicate_Document_Id
        }
    }
    if document^.seen_id_count >= len(document^.seen_ids) {
        return .Staged_Capacity_Exceeded
    }
    copied, alloc_error := strings.clone(id, document^.allocator)
    if alloc_error != nil {
        return .Staged_Capacity_Exceeded
    }
    document^.seen_ids[document^.seen_id_count] = copied
    document^.seen_id_count += 1
    return .None
}

// Read the optional record type without coercing JSON values.
sharing_record_type :: proc(record: json.Object) -> (string, bool) {
    return sharing_record_string(record, "type")
}

// Read a string member only when it is present and has the correct JSON type.
sharing_record_string :: proc(
    record: json.Object, key: string) -> (string, bool) {
    value, present := record[key]
    if !present {
        return "", false
    }
    return value.(string)
}

// Read a nonnegative integer member representable by the host int type.
sharing_record_integer :: proc(
    record: json.Object, key: string) -> (int, bool) {
    value, present := record[key]
    number, valid := value.(json.Integer)
    if !present || !valid || number < 0 || number > json.Integer(max(int)) {
        return 0, false
    }
    return int(number), true
}

// Return whether a record explicitly opens a scope.
sharing_record_begin :: proc(record: json.Object) -> bool {
    value, present := record["begin"]
    if !present {
        return false
    }
    begin, valid := value.(bool)
    return valid && begin
}

// Enforce the byte limit, valid UTF-8, and NUL-free names.
sharing_name_valid :: proc(value: string, maximum: int) -> bool {
    if len(value) == 0 || len(value) > maximum ||
        !utf8.valid_string(value) {
        return false
    }
    for byte in transmute([]u8)value {
        if byte == 0 {
            return false
        }
    }
    return true
}

// Report whether the current scope suppresses all descendant content.
sharing_inside_skipped_scope :: proc(reader: ^Reader) -> bool {
    return reader.frame_count > 0 &&
        reader.frames[reader.frame_count - 1].kind == .Skipped
}

// Convert a failed syntax block action into a schema-level diagnostic.
sharing_syntax_action_result :: proc(
    reader: ^Reader, diagnostic: syntax.Diagnostic, line: int) -> Sharing_Rule {
    if diagnostic.rule == .None {
        return .None
    }
    return sharing_reader_fail(
        reader, sharing_rule_from_syntax(diagnostic.rule), line, "")
}

// Mark staged content non-importable and retain a bounded failure diagnostic.
sharing_reader_fail :: proc(
    reader: ^Reader, rule: Sharing_Rule, line: int,
    scope_id: string, detail := "") -> Sharing_Rule {
    if reader != nil {
        reader.failed = true
        reader.failure = rule
        if reader.document != nil {
            reader.document^.valid = false
            for index in 0..<reader.document^.collection_count {
                reader.document^.collections[index].importable = false
            }
            staged_diagnostic_add(reader.document, line, rule, scope_id, detail)
        }
    }
    return rule
}
