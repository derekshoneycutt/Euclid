package catalog_model

import viewmodel "../../view/model"

import "core:encoding/uuid"
import "core:mem"
import "core:strings"
import tlsf "core:mem/tlsf"
import "core:sync/chan"
import "core:thread"
import storage_pkg "../storage"
import "core:unicode/utf8"

SEARCH_QUERY_BYTE_CAPACITY :: viewmodel.LIBRARY_SEARCH_QUERY_BYTE_CAPACITY
SEARCH_QUERY_ITEM_CAPACITY :: 16
SEARCH_QUERY_ITEM_BYTE_CAPACITY :: 256
SEARCH_MATCH_BYTE_CAPACITY :: 1024
SEARCH_RESULT_WINDOW_CAPACITY :: viewmodel.LIBRARY_SEARCH_RESULT_CAPACITY
SEARCH_DOCUMENT_ID_BYTE_COUNT :: 36
CATALOG_RECORD_CAPACITY :: 138
CATALOG_NAME_BYTE_CAPACITY :: 256
CATALOG_PATH_BYTE_CAPACITY :: 2 * 1024
CATALOG_DATABASE_PATH_CAPACITY :: 4096
SEARCH_FINGERPRINT_BYTE_COUNT :: 64
CATALOG_TEXT_BYTE_CAPACITY :: CATALOG_RECORD_CAPACITY *
    (CATALOG_NAME_BYTE_CAPACITY + CATALOG_PATH_BYTE_CAPACITY)

// Persisted catalogue node classification, independent of runtime ownership.
Catalog_Node_Kind :: enum u8 {
    Category = 1,
    Leaf = 2,
    Terminal = 3,
}

// Bounded offset/length view into one immutable generation's packed text bytes.
Catalog_Text_Ref :: struct {
    offset: u32,
    length: u32,
}

// Compact catalogue record stored in an arena-backed materialized generation.
Catalog_Record :: struct {
    stable_id: uuid.Identifier,
    parent_stable_id: uuid.Identifier,
    has_parent: bool,
    node_kind: Catalog_Node_Kind,
    sibling_order: i32,
    catalog_order: i32,
    display_name: Catalog_Text_Ref,
    implementation_path: Catalog_Text_Ref,
}

Catalog_Generation_Record :: Catalog_Record

// Result of a bounded generation operation or lifecycle transition.
Catalog_Generation_Status :: enum {
    Ok,
    Invalid_State,
    Invalid_Text,
    Invalid_Record,
    Invalid_Topology,
    Invalid_Reference,
    Capacity,
    Allocation_Failed,
    Sealed,
}

// Stable owner for one bounded, sealed catalogue projection.
// The initialized arena owner must not be copied or moved.
Catalog_Generation :: struct {
    arena_owner: storage_pkg.Arena_Owner,
    text_builder: storage_pkg.Bounded_Byte_Builder,
    text_bytes: []u8,
    generation: u64,
    record_count: u16,
    records: [CATALOG_RECORD_CAPACITY]Catalog_Record,
    initialized: bool,
    sealed: bool,
}

// Logical source identity carried through search without selecting storage or SQL.
Search_Source_Namespace :: enum u8 {
    Invalid,
    Builtin,
}

// Stable source-local identity for one searchable document.
Search_Document_Id :: struct {
    bytes: [SEARCH_DOCUMENT_ID_BYTE_COUNT]u8,
}

// Source-aware identity resolved by the display only after result acceptance.
Search_Document_Key :: struct {
    source_namespace: Search_Source_Namespace,
    document_id: Search_Document_Id,
}

// Bounded display-to-worker query value with no borrowed storage.
Search_Query_Request :: struct {
    generation: u64,
    result_offset: u32,
    query_length: u16,
    query_bytes: [SEARCH_QUERY_BYTE_CAPACITY]u8,
}

// Worker outcome suitable for stale-generation rejection at display commit.
Search_Query_Status :: enum u8 {
    Unavailable,
    Ready,
    Invalid_Query,
    Query_Failed,
    Candidate_Ready,
    Candidate_Committed,
    Candidate_Discarded,
    Candidate_Finalized,
    Stopped,
}

// Bounded worker-to-display result window with no cross-thread pointers.
Search_Query_Result :: struct {
    generation: u64,
    index_generation: u64,
    status: Search_Query_Status,
    total_match_count: u32,
    result_offset: u32,
    returned_count: u16,
    more_available: bool,
    document_keys: [SEARCH_RESULT_WINDOW_CAPACITY]Search_Document_Key,
    suggestion_length: u16,
    suggestion_bytes: [SEARCH_QUERY_BYTE_CAPACITY]u8,
}

// Worker-to-coordinator acknowledgement for one catalogue transaction command.
Catalog_Control_Result :: struct {
    status: Search_Query_Status,
    index_generation: u64,
}

// Control discriminator for the bounded display-to-worker channel.
Search_Worker_Request_Kind :: enum u8 {
    Query,
    Stage,
    Commit,
    Discard,
    Finalize,
    Shutdown,
}

// Worker control envelope kept pointer-free for channel transfer.
Search_Worker_Request :: struct {
    kind: Search_Worker_Request_Kind,
    query: Search_Query_Request,
    database_path_length: u16,
    database_path: [CATALOG_DATABASE_PATH_CAPACITY]u8,
    expected_fingerprint: [SEARCH_FINGERPRINT_BYTE_COUNT]u8,
}

// Reason a display-side commit accepted or rejected one worker result.
Search_Result_Acceptance :: enum u8 {
    Accepted,
    Not_Ready,
    Stale_Query_Generation,
    Stale_Index_Generation,
}

// Display-visible phase of the worker-owned candidate transaction.
Catalog_Candidate_State :: enum u8 {
    None,
    Staged,
    Committed,
}

// Coordinator storage for one worker and its two stable catalogue generations.
Catalog_Service :: struct {
    requests: chan.Chan(Search_Worker_Request),
    results: chan.Chan(Search_Query_Result),
    control_results: chan.Chan(Catalog_Control_Result),
    worker: ^thread.Thread,
    backing: []byte,
    allocator_state: tlsf.Allocator,
    synchronized_allocator: mem.Mutex_Allocator,
    database_path_length: u16,
    database_path: [CATALOG_DATABASE_PATH_CAPACITY]u8,
    expected_fingerprint: [SEARCH_FINGERPRINT_BYTE_COUNT]u8,
    index_generation: u64,
    active_generation: ^Catalog_Generation,
    staged_generation: ^Catalog_Generation,
    candidate_state: Catalog_Candidate_State,
    running: bool,
}

// Initialize one stable generation owner and its bounded text builder.
catalog_generation_init :: proc(
    generation: ^Catalog_Generation,
    reservation := 64 * uint(mem.Kilobyte)) -> Catalog_Generation_Status {
    if generation == nil || generation.initialized || reservation == 0 {
        return .Invalid_State
    }
    generation^ = {}
    if !storage_pkg.arena_owner_init(&generation.arena_owner, reservation) {
        generation^ = {}
        return .Allocation_Failed
    }
    status := storage_pkg.bounded_byte_builder_init(
        &generation.text_builder, CATALOG_TEXT_BYTE_CAPACITY, &generation.arena_owner)
    if status != .Ok {
        storage_pkg.arena_owner_destroy(&generation.arena_owner)
        generation^ = {}
        return .Allocation_Failed
    }
    generation.initialized = true
    return .Ok
}

// Begin a new empty generation with a nonzero database identity.
catalog_generation_begin :: proc(
    generation: ^Catalog_Generation, identity: u64) -> Catalog_Generation_Status {
    if generation == nil || !generation.initialized || generation.sealed {
        return .Invalid_State
    }
    if identity == 0 || generation.generation != 0 || generation.record_count != 0 ||
       generation.text_builder.count != 0 {
        return .Invalid_State
    }
    generation.generation = identity
    return .Ok
}

// Append validated UTF-8 bytes and return a stable offset/length reference.
catalog_generation_append_text :: proc(
    generation: ^Catalog_Generation, text: string, field_capacity: int,
    reference: ^Catalog_Text_Ref) -> Catalog_Generation_Status {
    if generation == nil || !generation.initialized || generation.sealed ||
       reference == nil || generation.generation == 0 {
        return .Invalid_State
    }
    if field_capacity < 0 || len(text) > field_capacity ||
       len(text) > int(max(u32)) || generation.text_builder.count > int(max(u32)) {
        return .Capacity
    }
    if !utf8.valid_string(text) || catalog_text_contains_nul(text) {
        return .Invalid_Text
    }
    offset := generation.text_builder.count
    status := storage_pkg.bounded_byte_builder_append(
        &generation.text_builder, transmute([]u8)text)
    if status == .Limit_Exceeded {
        return .Capacity
    }
    if status != .Ok {
        return .Allocation_Failed
    }
    reference^ = Catalog_Text_Ref{offset = u32(offset), length = u32(len(text))}
    return .Ok
}

// Append one compact record while preserving its caller-supplied source metadata.
catalog_generation_append_record :: proc(
    generation: ^Catalog_Generation,
    record: Catalog_Generation_Record) -> Catalog_Generation_Status {
    if generation == nil || !generation.initialized || generation.sealed ||
       generation.generation == 0 {
        return .Invalid_State
    }
    if generation.record_count >= CATALOG_RECORD_CAPACITY {
        return .Capacity
    }
    generation.records[generation.record_count] = record
    generation.record_count += 1
    return .Ok
}

// Validate and seal all records and packed text for immutable publication.
catalog_generation_seal :: proc(
    generation: ^Catalog_Generation) -> Catalog_Generation_Status {
    if generation == nil || !generation.initialized || generation.sealed ||
       generation.generation == 0 || generation.record_count == 0 {
        return .Invalid_State
    }
    for index in 0..<int(generation.record_count) {
        record := &generation.records[index]
        if !catalog_generation_reference_is_valid(generation, record.display_name) ||
           !catalog_generation_reference_is_valid(
               generation, record.implementation_path) {
            return .Invalid_Reference
        }
    }
    if !catalog_generation_topology_is_valid(generation) {
        return .Invalid_Topology
    }
    text_bytes, builder_status := storage_pkg.bounded_byte_builder_seal(
        &generation.text_builder)
    if builder_status != .Ok {
        return .Invalid_State
    }
    generation.text_bytes = text_bytes
    generation.sealed = true
    return .Ok
}

// Resolve a validated reference only after the generation has been sealed.
catalog_generation_text :: proc(
    generation: ^Catalog_Generation,
    reference: Catalog_Text_Ref) -> (string, Catalog_Generation_Status) {
    if generation == nil || !generation.initialized || !generation.sealed {
        return "", .Invalid_State
    }
    offset := uint(reference.offset)
    length := uint(reference.length)
    if offset > uint(len(generation.text_bytes)) ||
       length > uint(len(generation.text_bytes)) - offset {
        return "", .Invalid_Reference
    }
    return string(generation.text_bytes[offset:offset + length]), .Ok
}

// Reset an inactive generation and invalidate its prior records and text views.
catalog_generation_reset :: proc(
    generation: ^Catalog_Generation) -> Catalog_Generation_Status {
    if generation == nil || !generation.initialized {
        return .Invalid_State
    }
    storage_pkg.arena_owner_reset(&generation.arena_owner)
    generation.text_builder = {}
    status := storage_pkg.bounded_byte_builder_init(
        &generation.text_builder, CATALOG_TEXT_BYTE_CAPACITY, &generation.arena_owner)
    if status != .Ok {
        return .Allocation_Failed
    }
    generation.text_bytes = nil
    generation.generation = 0
    generation.record_count = 0
    generation.records = {}
    generation.sealed = false
    return .Ok
}

// Destroy one initialized generation after all readers have retired.
catalog_generation_destroy :: proc(generation: ^Catalog_Generation) {
    if generation == nil || !generation.initialized {
        return
    }
    storage_pkg.arena_owner_destroy(&generation.arena_owner)
    generation.text_builder = {}
    generation.text_bytes = nil
    generation.generation = 0
    generation.record_count = 0
    generation.records = {}
    generation.sealed = false
    generation.initialized = false
}

// Validate one reference against the current unsealed builder bounds.
catalog_generation_reference_is_valid :: proc(
    generation: ^Catalog_Generation, reference: Catalog_Text_Ref) -> bool {
    offset := uint(reference.offset)
    length := uint(reference.length)
    byte_count := uint(generation.text_builder.count)
    return offset <= byte_count && length <= byte_count - offset
}

// Validate every record's text and topology before generation publication.
catalog_generation_topology_is_valid :: proc(
    generation: ^Catalog_Generation) -> bool {
    terminal_count := 0
    for index in 0..<int(generation.record_count) {
        record := &generation.records[index]
        if record.node_kind == .Terminal {
            terminal_count += 1
        }
        if !catalog_generation_record_is_valid(generation, index) {
            return false
        }
    }
    return terminal_count == 1
}

// Validate one record's references, ordering, uniqueness, and ancestor chain.
catalog_generation_record_is_valid :: proc(
    generation: ^Catalog_Generation, index: int) -> bool {
    record := &generation.records[index]
    if record.stable_id == (uuid.Identifier{}) || record.catalog_order != i32(index) ||
       record.sibling_order < 0 ||
       !catalog_generation_reference_is_valid(generation, record.display_name) ||
       !catalog_generation_reference_is_valid(generation, record.implementation_path) {
        return false
    }
    name := catalog_generation_builder_text(generation, record.display_name)
    path := catalog_generation_builder_text(generation, record.implementation_path)
    if len(name) == 0 || len(name) > CATALOG_NAME_BYTE_CAPACITY ||
       !utf8.valid_string(name) || catalog_text_contains_nul(name) {
        return false
    }
    if !catalog_generation_path_is_valid(record.node_kind, record, path) ||
       !catalog_generation_record_is_unique(generation, index) {
        return false
    }
    return catalog_generation_ancestor_chain_is_valid(generation, index)
}

// Read builder-owned bytes for validation before sealing.
catalog_generation_builder_text :: proc(
    generation: ^Catalog_Generation, reference: Catalog_Text_Ref) -> string {
    offset := int(reference.offset)
    length := int(reference.length)
    return string(generation.text_builder.storage[offset:offset + length])
}

// Enforce node-kind-specific path presence, capacity, UTF-8, and package safety.
catalog_generation_path_is_valid :: proc(
    kind: Catalog_Node_Kind, record: ^Catalog_Record,
    path: string) -> bool {
    if kind == .Terminal {
        return !record.has_parent && len(path) == 0
    }
    return (kind == .Category || kind == .Leaf) &&
        len(path) > 0 && len(path) <= CATALOG_PATH_BYTE_CAPACITY &&
        utf8.valid_string(path) && !catalog_text_contains_nul(path) &&
        catalog_generation_path_is_safe(path)
}

// Reject absolute, noncanonical, or package-escaping implementation paths.
catalog_generation_path_is_safe :: proc(path: string) -> bool {
    if len(path) == 0 || path[0] == '/' || strings.contains(path, "\\") ||
       strings.contains(path, ":") {
        return false
    }
    component_start := 0
    for index in 0..=len(path) {
        if index < len(path) && path[index] != '/' {
            continue
        }
        component := path[component_start:index]
        if len(component) == 0 || component == "." || component == ".." {
            return false
        }
        component_start = index + 1
    }
    return true
}

// Reject duplicate stable identities and sibling orders within one parent.
catalog_generation_record_is_unique :: proc(
    generation: ^Catalog_Generation, index: int) -> bool {
    record := &generation.records[index]
    for prior_index in 0..<index {
        prior := &generation.records[prior_index]
        same_parent := record.has_parent == prior.has_parent &&
            (!record.has_parent || record.parent_stable_id == prior.parent_stable_id)
        if record.stable_id == prior.stable_id ||
           (same_parent && record.sibling_order == prior.sibling_order) {
            return false
        }
    }
    return true
}

// Verify parent existence and reject self-parenting or cyclic ancestry.
catalog_generation_ancestor_chain_is_valid :: proc(
    generation: ^Catalog_Generation, index: int) -> bool {
    record := &generation.records[index]
    current := record
    hops := 0
    for current.has_parent {
        parent_index := catalog_generation_find(generation, current.parent_stable_id)
        if parent_index < 0 || parent_index == index {
            return false
        }
        current = &generation.records[parent_index]
        hops += 1
        if hops > int(generation.record_count) {
            return false
        }
    }
    return true
}

// Find a stable identity among the bounded records without allocating an index.
catalog_generation_find :: proc(
    generation: ^Catalog_Generation, stable_id: uuid.Identifier) -> int {
    for index in 0..<int(generation.record_count) {
        if generation.records[index].stable_id == stable_id {
            return index
        }
    }
    return -1
}

// Reject embedded NUL bytes in retained UTF-8 text.
catalog_text_contains_nul :: proc(text: string) -> bool {
    for byte in transmute([]u8)text {
        if byte == 0 {
            return true
        }
    }
    return false
}

