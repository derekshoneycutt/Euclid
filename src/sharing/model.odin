package sharing

import syntax "./syntax"
import uuid "core:encoding/uuid"
import "core:mem"

NOTE_MIME_MAX_BYTES :: 32
STAGED_DIAGNOSTIC_CAPACITY :: 64
SHARING_MAX_NAME_BYTES :: 256
SHARING_MAX_NOTE_BYTES :: 4096
SHARING_MAX_SCOPE_DEPTH :: 3

Sharing_Limits :: struct {
    document_bytes: int,
    record_bytes: int,
    record_count: int,
    collection_count: int,
    entries_per_collection: int,
    entries_per_document: int,
    note_bytes: int,
    name_bytes: int,
    scope_depth: int,
    diagnostic_count: int,
}

DEFAULT_SHARING_LIMITS :: Sharing_Limits{
    document_bytes = 4 * 1024 * 1024,
    record_bytes = 64 * 1024,
    record_count = 65_536,
    collection_count = 256,
    entries_per_collection = 4_096,
    entries_per_document = 16_384,
    note_bytes = SHARING_MAX_NOTE_BYTES,
    name_bytes = SHARING_MAX_NAME_BYTES,
    scope_depth = SHARING_MAX_SCOPE_DEPTH,
    diagnostic_count = STAGED_DIAGNOSTIC_CAPACITY,
}

Note_Mime :: enum u8 {
    None,
    Latex,
    Plain,
}

Collection_Reason :: enum u8 {
    None,
    Empty,
    Invalid_Name,
    Duplicate_Animation,
    Invalid_Notes,
    Note_Too_Large,
}

Sharing_Rule :: enum u16 {
    None,
    Invalid_Utf8,
    Byte_Order_Mark,
    Carriage_Return,
    Missing_Final_Lf,
    Missing_Header,
    Invalid_Json,
    Duplicate_Object_Key,
    Record_Not_Object,
    Record_Too_Large,
    Record_Too_Complex,
    Document_Too_Large,
    Too_Many_Records,
    Too_Many_Scopes,
    Invalid_Scope,
    Mismatched_Scope_End,
    Unclosed_Scope,
    Invalid_Block_Descriptor,
    Invalid_Block_Length,
    Block_Too_Large,
    Block_Destination_Too_Small,
    Missing_Block_Terminator,
    Invalid_Block_Framing_Lf,
    Invalid_Header,
    Unsupported_Framing,
    Unsupported_Schema,
    Unknown_Requirement,
    Invalid_Timestamp,
    Invalid_Record,
    Invalid_Collection,
    Invalid_Entry,
    Invalid_Animation_Id,
    Duplicate_Document_Id,
    Duplicate_Animation,
    Unsupported_Hierarchy,
    Invalid_Notes,
    Note_Too_Large,
    Name_Too_Large,
    Too_Many_Collections,
    Too_Many_Entries,
    Too_Many_Diagnostics,
    Unsupported_Content,
    Invalid_Failure_Scope,
    Staged_Capacity_Exceeded,
}

Staged_Entry :: struct {
    animation_id: uuid.Identifier,
    parent: int,
    name: string,
    note: string,
    note_mime: Note_Mime,
    has_note: bool,
    notes_on_top: bool,
    line: int,
}

Staged_Collection :: struct {
    name: string,
    entries: []Staged_Entry,
    entry_count: int,
    importable: bool,
    reason: Collection_Reason,
    line: int,
}

Staged_Diagnostic :: struct {
    line: int,
    rule: Sharing_Rule,
    scope_id: [32]u8,
    scope_id_length: u8,
    detail: [64]u8,
    detail_length: u8,
}

// Staged_Document retains only values copied into its owner's allocator.
Staged_Document :: struct {
    allocator: mem.Allocator,
    limits: Sharing_Limits,
    collections: []Staged_Collection,
    collection_count: int,
    entries_storage: []Staged_Entry,
    entry_total: int,
    seen_ids: []string,
    seen_id_count: int,
    diagnostics: [STAGED_DIAGNOSTIC_CAPACITY]Staged_Diagnostic,
    diagnostic_count: int,
    diagnostic_overflow: int,
    skipped_optional: int,
    valid: bool,
    initialized: bool,
}

// Staging_Workspace borrows fixed input, JSON, and one-block destination buffers.
Staging_Workspace :: struct {
    line_buffer: []u8,
    json_scratch: []u8,
    block_buffer: []u8,
}

// Initialize bounded staging arrays from the caller's lifetime-owned allocator.
staged_document_init :: proc(
    document: ^Staged_Document, allocator: mem.Allocator,
    limits := DEFAULT_SHARING_LIMITS) -> Sharing_Rule {
    if document == nil || limits.document_bytes < 1 ||
        limits.record_bytes < 1 || limits.record_count < 1 ||
        limits.collection_count < 1 || limits.entries_per_collection < 1 ||
        limits.entries_per_document < 1 || limits.note_bytes < 0 ||
        limits.name_bytes < 1 || limits.name_bytes > SHARING_MAX_NAME_BYTES ||
        limits.scope_depth < 1 ||
        limits.diagnostic_count < 1 ||
        limits.diagnostic_count > STAGED_DIAGNOSTIC_CAPACITY {
        return .Staged_Capacity_Exceeded
    }
    document^ = {
        allocator = allocator,
        limits = limits,
    }
    collections, collection_error := make(
        []Staged_Collection, limits.collection_count, allocator)
    if collection_error != nil {
        return .Staged_Capacity_Exceeded
    }
    entries, entry_error := make(
        []Staged_Entry, limits.entries_per_document, allocator)
    if entry_error != nil {
        return .Staged_Capacity_Exceeded
    }
    ids, id_error := make([]string, limits.record_count, allocator)
    if id_error != nil {
        return .Staged_Capacity_Exceeded
    }
    document.collections = collections
    document.entries_storage = entries
    document.seen_ids = ids
    document.initialized = true
    return .None
}

// Retain a diagnostic in fixed storage and count any overflow.
staged_diagnostic_add :: proc(
    document: ^Staged_Document, line: int, rule: Sharing_Rule,
    scope_id := "", detail := "") {
    if document == nil {
        return
    }
    if document.diagnostic_count >= document.limits.diagnostic_count {
        document.diagnostic_overflow += 1
        return
    }
    length := min(len(scope_id), len(document.diagnostics[0].scope_id))
    diagnostic: Staged_Diagnostic = {
        line = line,
        rule = rule,
        scope_id_length = u8(length),
        detail_length = u8(min(len(detail), 64)),
    }
    copy(diagnostic.scope_id[:], transmute([]u8)scope_id[:length])
    copy(diagnostic.detail[:], transmute([]u8)detail[:diagnostic.detail_length])
    document.diagnostics[document.diagnostic_count] = diagnostic
    document.diagnostic_count += 1
}

// Map syntax diagnostics to the public collections-reader rule vocabulary.
sharing_rule_from_syntax :: proc(rule: syntax.Rule) -> Sharing_Rule {
    switch rule {
    case .None:
        return .None
    case .Invalid_Utf8:
        return .Invalid_Utf8
    case .Byte_Order_Mark:
        return .Byte_Order_Mark
    case .Carriage_Return:
        return .Carriage_Return
    case .Missing_Final_Lf:
        return .Missing_Final_Lf
    case .Missing_Header, .Empty_Header:
        return .Missing_Header
    case .Invalid_Json:
        return .Invalid_Json
    case .Duplicate_Object_Key:
        return .Duplicate_Object_Key
    case .Record_Not_Object:
        return .Record_Not_Object
    case .Record_Too_Large:
        return .Record_Too_Large
    case .Record_Too_Complex:
        return .Record_Too_Complex
    case .Document_Too_Large:
        return .Document_Too_Large
    case .Too_Many_Records:
        return .Too_Many_Records
    case .Too_Many_Scopes:
        return .Too_Many_Scopes
    case .Scope_Too_Deep:
        return .Too_Many_Scopes
    case .Invalid_Scope:
        return .Invalid_Scope
    case .Mismatched_Scope_End:
        return .Mismatched_Scope_End
    case .Unclosed_Scope:
        return .Unclosed_Scope
    case .Invalid_Block_Descriptor:
        return .Invalid_Block_Descriptor
    case .Invalid_Block_Length:
        return .Invalid_Block_Length
    case .Block_Too_Large:
        return .Block_Too_Large
    case .Block_Terminator_Too_Large:
        return .Block_Too_Large
    case .Block_Destination_Too_Small,
         .Block_Too_Large_For_Destination:
        return .Block_Destination_Too_Small
    case .Missing_Block_Terminator:
        return .Missing_Block_Terminator
    case .Invalid_Block_Framing_Lf:
        return .Invalid_Block_Framing_Lf
    case .Whitespace_Record,
         .Block_Action_Missing,
         .Invalid_Block_Terminator,
         .Feed_After_End:
        return .Invalid_Record
    case:
        return .Invalid_Record
    }
}
