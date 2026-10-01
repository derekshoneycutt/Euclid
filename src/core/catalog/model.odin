package catalog_model

import viewmodel "../../view/model"

import "core:encoding/uuid"
import "core:mem"
import tlsf "core:mem/tlsf"
import "core:sync/chan"
import "core:thread"

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

// Persisted catalogue node classification, independent of runtime ownership.
Catalog_Node_Kind :: enum u8 {
    Category = 1,
    Leaf = 2,
    Terminal = 3,
}

// Bounded static catalogue value copied while SQLite owns the source columns.
Catalog_Record :: struct {
    stable_id: uuid.Identifier,
    parent_stable_id: uuid.Identifier,
    has_parent: bool,
    node_kind: Catalog_Node_Kind,
    sibling_order: i32,
    catalog_order: i32,
    display_name_length: u16,
    display_name: [CATALOG_NAME_BYTE_CAPACITY]u8,
    implementation_path_length: u16,
    implementation_path: [CATALOG_PATH_BYTE_CAPACITY]u8,
}

// Immutable generation-scoped catalogue snapshot with fixed storage bounds.
Catalog_Snapshot :: struct {
    generation: u64,
    record_count: u16,
    records: [CATALOG_RECORD_CAPACITY]Catalog_Record,
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

// Dedicated catalogue service storage with worker-owned database behavior.
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
    snapshot: ^Catalog_Snapshot,
    staged_snapshot: ^Catalog_Snapshot,
    candidate_state: Catalog_Candidate_State,
    running: bool,
}
