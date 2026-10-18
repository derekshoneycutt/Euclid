package viewmodel

import runtime "base:runtime"
import storage "../../../core/storage"
import uuid "core:encoding/uuid"

// library_search_reserve_ids grows active or staged results without losing either.
library_search_reserve_ids :: proc(
    search: ^Library_Search_State, staged: bool, required: int) -> bool {
    if search == nil || required < 0 {
        return false
    }
    if !search.visible_id_allocator.initialized {
        heap_allocator := runtime.Allocator{procedure = runtime.heap_allocator_proc}
        if storage.tlsf_owner_init(
            &search.visible_id_allocator, heap_allocator) != .Ok {
            return false
        }
    }
    ids := &search.visible_ids
    used := search.visible_id_count
    if staged {
        ids = &search.staged_visible_ids
        used = search.staged_visible_id_count
    }
    if required <= len(ids^) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(len(ids^), 16, required)
    if !valid || used > len(ids^) {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&search.visible_id_allocator)
    grown := make([]uuid.Identifier, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, ids^[:used])
    delete(ids^, allocator)
    ids^ = grown
    return true
}

// library_search_destroy releases accepted and staged visibility storage.
library_search_destroy :: proc(search: ^Library_Search_State) {
    if search == nil {
        return
    }
    if search.visible_id_allocator.initialized {
        allocator := storage.tlsf_owner_allocator(&search.visible_id_allocator)
        delete(search.visible_ids, allocator)
        delete(search.staged_visible_ids, allocator)
        storage.tlsf_owner_destroy(&search.visible_id_allocator)
    }
    search^ = {}
}
