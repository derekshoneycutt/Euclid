package dynviewmodel

import storage "../../core/storage"
import animation_model "../../core/animation"

import "core:mem"
import "base:runtime"

DYNVIEW_DOCUMENT_ENTRY_CAPACITY :: 256
DYNVIEW_DOCUMENT_TOTAL_BLOB_BYTES :: 16*int(mem.Megabyte)

// Identify one owner-local immutable document within an animation generation.
Dynview_Document_Handle :: struct {
    generation: u64,
    index: u32,
}

// Retain one type-neutral immutable document index entry in shared core state.
Dynview_Document_Entry :: struct {
    source_hash: u64,
    source_length: u32,
    grammar_revision: u32,
    semantic_profile: u32,
    parse_mode: u8,
    root_style: u8,
    parse_status: i32,
    blob: []u64,
    blob_byte_count: int,
    text_offset: int,
    text_count: int,
    ops_offset: int,
    op_count: int,
    programs_offset: int,
    program_count: int,
    tables_offset: int,
    table_count: int,
    blocks_offset: int,
    block_count: int,
    inlines_offset: int,
    inline_count: int,
    display_rows_offset: int,
    display_row_count: int,
    root_program: int,
    plain_text_offset: int,
    plain_text_length: int,
    error_offset: int,
    recoverable: bool,
    occupied: bool,
}

// Report bounded document-store use and generation-local cache behavior.
Dynview_Document_Store_Diagnostics :: struct {
    initialized: bool,
    generation: u64,
    entry_count: int,
    blob_bytes: int,
    peak_entry_count: int,
    peak_blob_bytes: int,
    intern_hits: u64,
    negative_cache_hits: u64,
    collision_count: u64,
    quota_rejections: u64,
    allocation_failures: u64,
    generation_resets: u64,
    arena: storage.Arena_Owner_Diagnostics,
}

// Retain POD lifecycle and index state for the native document store.
Dynview_Document_Store :: struct {
    memory: ^animation_model.Animation_Memory,
    allocator: runtime.Allocator,
    entries: [DYNVIEW_DOCUMENT_ENTRY_CAPACITY]Dynview_Document_Entry,
    generation: u64,
    entry_count: int,
    blob_bytes: int,
    byte_quota: int,
    peak_entry_count: int,
    peak_blob_bytes: int,
    intern_hits: u64,
    negative_cache_hits: u64,
    collision_count: u64,
    quota_rejections: u64,
    allocation_failures: u64,
    generation_resets: u64,
    initialized: bool,
}

//   Bind the document-store state to initialized shared animation memory.
dynview_document_store_init :: proc(
    store: ^Dynview_Document_Store,
    memory: ^animation_model.Animation_Memory) -> bool {
    if store == nil || store.initialized || memory == nil || !memory.initialized {
        return false
    }
    store^ = {
        memory = memory,
        allocator = animation_model.animation_memory_allocator(memory),
        byte_quota = DYNVIEW_DOCUMENT_TOTAL_BLOB_BYTES,
        initialized = true,
    }
    return store.allocator != (runtime.Allocator{})
}

//   Clear generation identity before the owner retires shared allocations.
dynview_document_store_clear_generation :: proc(
    store: ^Dynview_Document_Store) {
    if store == nil || !store.initialized {
        return
    }
    for index in 0..<len(store.entries) {
        store.entries[index] = {}
    }
    store.generation = 0
    store.entry_count = 0
    store.blob_bytes = 0
}

//   Publish one owner-validated generation to the document-store state.
dynview_document_store_publish_generation :: proc(
    store: ^Dynview_Document_Store,
    memory: ^animation_model.Animation_Memory,
    generation: u64) {
    if store == nil || memory == nil || !store.initialized ||
        store.memory != memory || memory.generation != generation {
        return
    }
    store.generation = generation
    store.generation_resets += 1
}

//   Detach document-store state without changing shared animation memory.
dynview_document_store_destroy :: proc(store: ^Dynview_Document_Store) {
    if store == nil || !store.initialized {
        return
    }
    dynview_document_store_clear_generation(store)
    store.memory = nil
    store.allocator = {}
    store.byte_quota = 0
    store.initialized = false
}
