package search

import viewmodel "../model"

SEARCH_QUERY_BYTE_CAPACITY :: viewmodel.LIBRARY_SEARCH_QUERY_BYTE_CAPACITY
SEARCH_QUERY_ITEM_CAPACITY :: 16
SEARCH_QUERY_ITEM_BYTE_CAPACITY :: 256
SEARCH_MATCH_BYTE_CAPACITY :: 1024
SEARCH_RESULT_WINDOW_CAPACITY :: viewmodel.LIBRARY_SEARCH_RESULT_CAPACITY
SEARCH_DOCUMENT_ID_BYTE_COUNT :: 36

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

// Control discriminator for the bounded display-to-worker channel.
Search_Worker_Request_Kind :: enum u8 {
    Query,
    Shutdown,
}

// Worker control envelope kept pointer-free for channel transfer.
Search_Worker_Request :: struct {
    kind: Search_Worker_Request_Kind,
    query: Search_Query_Request,
}

// Reason a display-side commit accepted or rejected one worker result.
Search_Result_Acceptance :: enum u8 {
    Accepted,
    Not_Ready,
    Stale_Query_Generation,
    Stale_Index_Generation,
}

// Validate both asynchronous generations before display-owned state replacement.
search_result_acceptance :: proc(
    result: ^Search_Query_Result, query_generation,
    index_generation: u64) -> Search_Result_Acceptance {
    if result == nil || result.status != .Ready {return .Not_Ready}
    if result.generation != query_generation {return .Stale_Query_Generation}
    if result.index_generation != index_generation {return .Stale_Index_Generation}
    return .Accepted
}