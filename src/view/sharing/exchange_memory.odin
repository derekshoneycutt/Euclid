package viewsharing

import sharingmodel "../../view/sharing/model"
import sharing "../../sharing"
import storage "../../core/storage"

// Allocate all parse and resolution storage from the exchange lifetime arena.
exchange_memory_prepare_import :: proc(
    runtime: ^sharingmodel.Exchange_Runtime) -> bool {
    if runtime == nil || runtime.arena.initialized || runtime.task_active ||
        !storage.arena_owner_init(&runtime.arena) {
        return false
    }
    allocator := storage.arena_owner_allocator(&runtime.arena)
    limits := sharing.DEFAULT_SHARING_LIMITS
    document := new(sharing.Staged_Document, allocator)
    line_buffer, line_error := make([]u8, limits.record_bytes, allocator)
    json_scratch, json_error := make([]u8, 4*limits.record_bytes, allocator)
    block_buffer, block_error := make([]u8, limits.note_bytes, allocator)
    collections, collection_error := make(
        []sharingmodel.Exchange_Resolved_Collection,
        limits.collection_count, allocator)
    entries, entry_error := make(
        []sharingmodel.Exchange_Resolved_Entry,
        limits.entries_per_document, allocator)
    entry_map, map_error := make([]int, limits.entries_per_document, allocator)
    if document == nil || line_error != nil || json_error != nil ||
        block_error != nil || collection_error != nil || entry_error != nil ||
        map_error != nil {
        storage.arena_owner_destroy(&runtime.arena)
        return false
    }
    if sharing.staged_document_init(document, allocator) != .None {
        storage.arena_owner_destroy(&runtime.arena)
        return false
    }
    runtime.payload.staged = document
    runtime.payload.workspace = {
        line_buffer = line_buffer,
        json_scratch = json_scratch,
        block_buffer = block_buffer,
    }
    runtime.resolved_collections = collections
    runtime.resolved_entries = entries
    runtime.resolved_entry_to_plan = entry_map
    return true
}

// Retire parse storage only after the exchange worker has been joined.
exchange_memory_destroy :: proc(runtime: ^sharingmodel.Exchange_Runtime) -> bool {
    if runtime == nil || runtime.task_active {
        return false
    }
    storage.arena_owner_destroy(&runtime.arena)
    runtime.payload.staged = nil
    runtime.payload.plan = nil
    runtime.payload.workspace = {}
    runtime.resolved_collections = nil
    runtime.resolved_entries = nil
    runtime.resolved_entry_to_plan = nil
    runtime.resolved_collection_count = 0
    runtime.resolved_entry_count = 0
    runtime.left_out_entry_count = 0
    runtime.selected_import_collections = {}
    runtime.selected_import_count = 0
    return true
}
