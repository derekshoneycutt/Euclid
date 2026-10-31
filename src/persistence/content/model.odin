package contentstore

import sqlite "../../sqlite"
import contentdata "../../core/content"

SEARCH_SPELLFIX_CANDIDATE_CAPACITY :: 8

// One bounded correction candidate copied out of SQLite-owned column storage.
Search_Correction_Candidate :: struct {
    item_index: u8,
    byte_count: u16,
    bytes: [contentdata.SEARCH_QUERY_ITEM_BYTE_CAPACITY]u8,
    distance: i32,
    rank: i32,
}

// Internal execution outcome paired with a fully initialized result message.
Search_Execution :: struct {
    result: contentdata.Search_Query_Result,
    ok: bool,
}

// Fixed statement set and connection exclusively owned by the catalogue worker.
Content_Database :: struct {
    connection: sqlite.Connection,
    statements: Content_Statements,
    index_generation: u64,
    expected_table_counts: [12]u16,
    expected_record_count: u32,
}

