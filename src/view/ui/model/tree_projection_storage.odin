package viewmodel

import runtime "base:runtime"
import storage "../../../core/storage"
import uuid "core:encoding/uuid"

UI_TREE_NO_ITEM :: -1

// Initialize the projection's lifetime-bound TLSF storage and lookup tables.
ui_tree_projection_init :: proc(projection: ^Ui_Tree_Projection) -> bool {
    if projection == nil {
        return false
    }
    if projection.allocator.initialized {
        return len(projection.items) > 0 && len(projection.index) > 0
    }
    projection^ = {}
    heap_allocator := runtime.Allocator{procedure = runtime.heap_allocator_proc}
    if storage.tlsf_owner_init(&projection.allocator, heap_allocator) != .Ok {
        return false
    }
    projection.first_root = UI_TREE_NO_ITEM
    projection.last_root = UI_TREE_NO_ITEM
    if !ui_tree_projection_reserve(projection, 1) {
        ui_tree_projection_destroy(projection)
        return false
    }
    return true
}

// Release node records, indexes, staging allocations, and the projection owner.
ui_tree_projection_destroy :: proc(projection: ^Ui_Tree_Projection) {
    if projection == nil || !projection.allocator.initialized {
        return
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    ui_tree_projection_abort_mutation(projection)
    for item in projection.items[:projection.count] {
        ui_tree_projection_free_node(item, allocator)
    }
    delete(projection.items, allocator)
    delete(projection.index, allocator)
    delete(projection.order_workspace, allocator)
    delete(projection.frame_rows, allocator)
    delete(projection.scratch_rows, allocator)
    delete(projection.motion_branches, allocator)
    delete(projection.reorder_rows, allocator)
    delete(projection.traversal_frames, allocator)
    storage.tlsf_owner_destroy(&projection.allocator)
    projection^ = {}
}

// Grow the projection-owned prepared-row buffer selected by the frame boundary.
ui_tree_projection_reserve_prepared_rows :: proc(
    projection: ^Ui_Tree_Projection,
    scratch: bool, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    rows := &projection.frame_rows
    if scratch {
        rows = &projection.scratch_rows
    }
    if required <= len(rows^) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(len(rows^), 16, required)
    if !valid {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    grown := make([]Ui_Tree_Prepared_Row, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, rows^)
    delete(rows^, allocator)
    rows^ = grown
    return true
}

// Grow branch-motion storage without discarding the prior live workspace on failure.
ui_tree_projection_reserve_motion :: proc(
    projection: ^Ui_Tree_Projection, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    if required <= len(projection.motion_branches) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(
        len(projection.motion_branches), 16, required)
    if !valid {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    grown := make([]Ui_Tree_Branch_Motion, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, projection.motion_branches)
    delete(projection.motion_branches, allocator)
    projection.motion_branches = grown
    return true
}

// Grow reorder-motion storage transactionally with the tree projection.
ui_tree_projection_reserve_reorder :: proc(
    projection: ^Ui_Tree_Projection, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    if required <= len(projection.reorder_rows) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(
        len(projection.reorder_rows), 16, required)
    if !valid {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    grown := make([]Ui_Tree_Reorder_Row, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, projection.reorder_rows)
    delete(projection.reorder_rows, allocator)
    projection.reorder_rows = grown
    return true
}

// Grow reusable traversal frames without disturbing prepared frame rows.
ui_tree_projection_reserve_traversal :: proc(
    projection: ^Ui_Tree_Projection, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    if required <= len(projection.traversal_frames) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(
        len(projection.traversal_frames), 16, required)
    if !valid {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    grown := make([]Ui_Tree_Traversal_Frame, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, projection.traversal_frames)
    delete(projection.traversal_frames, allocator)
    projection.traversal_frames = grown
    return true
}

// Resolve a stable UUID to its current dense topology index.
ui_tree_projection_find :: proc(
    projection: ^Ui_Tree_Projection, key: uuid.Identifier) -> int {
    if projection == nil || len(projection.index) == 0 {
        return UI_TREE_NO_ITEM
    }
    mask := len(projection.index) - 1
    slot := int(ui_tree_projection_hash(key) & uint(mask))
    for _ in 0..<len(projection.index) {
        entry := projection.index[slot]
        if !entry.occupied {
            return UI_TREE_NO_ITEM
        }
        if entry.key == key {
            return entry.item_index
        }
        slot = (slot + 1) & mask
    }
    return UI_TREE_NO_ITEM
}

// Grow the owner-backed ordering workspace used for collection reconciliation.
ui_tree_projection_reserve_order_workspace :: proc(
    projection: ^Ui_Tree_Projection, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    if required <= len(projection.order_workspace) {
        return true
    }
    capacity := max(len(projection.order_workspace), 16)
    for capacity < required {
        if capacity > max(int)/2 {
            return false
        }
        capacity *= 2
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    workspace := make([]int, capacity, allocator)
    if len(workspace) != capacity {
        return false
    }
    delete(projection.order_workspace, allocator)
    projection.order_workspace = workspace
    return true
}

// Append one independently allocated stable node and index its UUID.
ui_tree_projection_add_node :: proc(
    projection: ^Ui_Tree_Projection,
    item: Ui_Tree_Item,
    canonical_name: string) -> int {
    if projection == nil || !projection.allocator.initialized ||
        ui_tree_projection_find(projection, item.key) != UI_TREE_NO_ITEM ||
        !ui_tree_projection_reserve(projection, projection.count + 1) {
        return UI_TREE_NO_ITEM
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    node, ok := ui_tree_projection_make_node(item, canonical_name, allocator)
    if !ok {
        return UI_TREE_NO_ITEM
    }
    item_index := projection.count
    projection.items[item_index] = node
    if !ui_tree_projection_index_insert(projection, item.key, item_index) {
        ui_tree_projection_free_node(node, allocator)
        return UI_TREE_NO_ITEM
    }
    projection.count += 1
    return item_index
}

// Reserve both dense node slots and the open-addressed UUID table atomically.
ui_tree_projection_reserve :: proc(
    projection: ^Ui_Tree_Projection, required: int) -> bool {
    if projection == nil || !projection.allocator.initialized || required < 0 {
        return false
    }
    item_capacity, item_ok := ui_tree_projection_grow_capacity(
        len(projection.items), 16, required)
    if !item_ok || item_capacity > max(int)/2 {
        return false
    }
    index_capacity, index_ok := ui_tree_projection_grow_capacity(
        len(projection.index), 32, item_capacity * 2)
    if !index_ok {
        return false
    }
    if item_capacity == len(projection.items) &&
        index_capacity == len(projection.index) {
        projection.capacity = item_capacity
        return true
    }
    return ui_tree_projection_resize_tables(
        projection, item_capacity, index_capacity)
}

// Replace the pointer table and UUID index while preserving live stable nodes.
ui_tree_projection_resize_tables :: proc(
    projection: ^Ui_Tree_Projection,
    item_capacity, index_capacity: int) -> bool {
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    items := make([]^Ui_Tree_Item, item_capacity, allocator)
    if len(items) != item_capacity {
        return false
    }
    index := make([]Ui_Tree_Index_Slot, index_capacity, allocator)
    if len(index) != index_capacity {
        delete(items, allocator)
        return false
    }
    copy(items, projection.items[:projection.count])
    old_items := projection.items
    old_index := projection.index
    projection.items = items
    projection.index = index
    for item_index in 0..<projection.count {
        if !ui_tree_projection_index_insert(
            projection, projection.items[item_index].key, item_index) {
            projection.items = old_items
            projection.index = old_index
            delete(items, allocator)
            delete(index, allocator)
            return false
        }
    }
    delete(old_items, allocator)
    delete(old_index, allocator)
    projection.capacity = item_capacity
    return true
}

// Grow one table capacity to its required minimum without integer overflow.
ui_tree_projection_grow_capacity :: proc(
    current, minimum, required: int) -> (int, bool) {
    capacity := max(current, minimum)
    for capacity < required {
        if capacity > max(int)/2 {
            return 0, false
        }
        capacity *= 2
    }
    return capacity, true
}

// Transfer a staged projection into the live slot, then release the former owner.
ui_tree_projection_replace :: proc(
    destination, staged: ^Ui_Tree_Projection) {
    old := destination^
    destination^ = staged^
    staged^ = old
    ui_tree_projection_destroy(staged)
}

// Allocate a node and its canonical label from the projection's TLSF owner.
ui_tree_projection_make_node :: proc(
    item: Ui_Tree_Item,
    canonical_name: string,
    allocator: runtime.Allocator) -> (^Ui_Tree_Item, bool) {
    node := new(Ui_Tree_Item, allocator)
    if node == nil {
        return nil, false
    }
    node^ = item
    node.canonical_name = make([]u8, len(canonical_name), allocator)
    if len(node.canonical_name) != len(canonical_name) {
        runtime.mem_free_with_size(node, size_of(Ui_Tree_Item), allocator)
        return nil, false
    }
    copy(node.canonical_name, canonical_name)
    node.canonical_name_length = len(canonical_name)
    return node, true
}

// Release one node and its independently owned label.
ui_tree_projection_free_node :: proc(
    item: ^Ui_Tree_Item, allocator: runtime.Allocator) {
    if item == nil {
        return
    }
    delete(item.canonical_name, allocator)
    runtime.mem_free_with_size(item, size_of(Ui_Tree_Item), allocator)
}

// Insert a previously absent key into the reserved projection index.
ui_tree_projection_index_insert :: proc(
    projection: ^Ui_Tree_Projection,
    key: uuid.Identifier,
    item_index: int) -> bool {
    if len(projection.index) == 0 {
        return false
    }
    mask := len(projection.index) - 1
    slot := int(ui_tree_projection_hash(key) & uint(mask))
    for _ in 0..<len(projection.index) {
        if !projection.index[slot].occupied {
            projection.index[slot] = {key, item_index, true}
            return true
        }
        if projection.index[slot].key == key {
            return false
        }
        slot = (slot + 1) & mask
    }
    return false
}

// Hash every UUID byte into a stable, table-size-independent probe seed.
ui_tree_projection_hash :: proc(key: uuid.Identifier) -> uint {
    hash: u64 = 0x9e3779b97f4a7c15
    for octet in key {
        hash = (hash << 7) | (hash >> 57)
        hash ~= u64(octet)
    }
    return uint(hash)
}
