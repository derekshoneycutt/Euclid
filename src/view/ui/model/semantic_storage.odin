package viewmodel

import runtime "base:runtime"
import storage "../../../core/storage"

// Hash every identity component; indexes never identify nodes by reusable addresses.
ui_semantic_identity_hash :: proc(id: Ui_Node_Id) -> u64 {
    hash := u64(14695981039346656037)
    for value in id.stable_id {
        hash = (hash ~ u64(value)) * 1099511628211
    }
    components: [3]u64 = {u64(id.domain), id.local_id, id.generation}
    for value in components {
        for shift in 0..<8 {
            hash = (hash ~ ((value >> uint(shift * 8)) & 0xff)) * 1099511628211
        }
    }
    return hash
}

// Resolve a complete identity in the snapshot's open-addressed index.
ui_semantic_snapshot_find :: proc(
    snapshot: ^Ui_Semantic_Snapshot, id: Ui_Node_Id) -> int {
    if snapshot == nil || len(snapshot.identity_index) == 0 {
        return -1
    }
    mask := len(snapshot.identity_index) - 1
    slot := int(ui_semantic_identity_hash(id) & u64(mask))
    for _ in 0..<len(snapshot.identity_index) {
        snapshot.lookup_probes += 1
        entry := snapshot.identity_index[slot]
        if entry == 0 {
            return -1
        }
        if snapshot.nodes[entry - 1].id == id {
            return entry - 1
        }
        slot = (slot + 1) & mask
    }
    return -1
}

// Insert one admitted node into a sufficiently sized identity index.
ui_semantic_snapshot_index_node :: proc(
    snapshot: ^Ui_Semantic_Snapshot, index: int) {
    mask := len(snapshot.identity_index) - 1
    slot := int(ui_semantic_identity_hash(snapshot.nodes[index].id) & u64(mask))
    for snapshot.identity_index[slot] != 0 {
        slot = (slot + 1) & mask
    }
    snapshot.identity_index[slot] = index + 1
}

// Lazily establish one snapshot's display-owned storage domain.
ui_semantic_snapshot_init :: proc(snapshot: ^Ui_Semantic_Snapshot) -> bool {
    if snapshot.allocator.initialized {
        return true
    }
    heap_allocator: runtime.Allocator = {
        procedure = runtime.heap_allocator_proc,
    }
    return storage.tlsf_owner_init(
        &snapshot.allocator, heap_allocator) == .Ok
}

// Reserve node and lookup storage transactionally before accepting a registration.
ui_semantic_snapshot_reserve_nodes :: proc(
    snapshot: ^Ui_Semantic_Snapshot, required: int) -> bool {
    if required <= len(snapshot.nodes) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(
        len(snapshot.nodes), 32, required)
    if !valid || capacity > max(int)/2 {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&snapshot.allocator)
    nodes := make([]Ui_Semantic_Node, capacity, allocator)
    identities := make([]int, capacity * 2, allocator)
    traversal := make([]int, capacity * 2, allocator)
    if len(nodes) != capacity || len(identities) != capacity * 2 ||
        len(traversal) != capacity * 2 {
        delete(nodes, allocator)
        delete(identities, allocator)
        delete(traversal, allocator)
        return false
    }
    copy(nodes, snapshot.nodes[:snapshot.node_count])
    delete(snapshot.nodes, allocator)
    delete(snapshot.identity_index, allocator)
    delete(snapshot.traversal_index, allocator)
    snapshot.nodes = nodes
    snapshot.identity_index = identities
    snapshot.traversal_index = traversal
    for index in 0..<snapshot.node_count {
        ui_semantic_snapshot_index_node(snapshot, index)
    }
    return true
}

// Grow aggregate UTF-8 storage without modifying accepted text on failure.
ui_semantic_snapshot_reserve_text :: proc(
    snapshot: ^Ui_Semantic_Snapshot, required: int) -> bool {
    if required <= len(snapshot.text) {
        return true
    }
    capacity, valid := ui_tree_projection_grow_capacity(
        len(snapshot.text), 256, required)
    if !valid {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&snapshot.allocator)
    text := make([]u8, capacity, allocator)
    if len(text) != capacity {
        return false
    }
    copy(text, snapshot.text[:snapshot.text_count])
    delete(snapshot.text, allocator)
    snapshot.text = text
    return true
}

// Release both display snapshots after frame and native-copy consumers finish.
ui_semantic_focus_destroy :: proc(state: ^Ui_Semantic_Focus_State) {
    if state == nil {
        return
    }
    for &snapshot in state.snapshots {
        if !snapshot.allocator.initialized {
            continue
        }
        allocator := storage.tlsf_owner_allocator(&snapshot.allocator)
        delete(snapshot.nodes, allocator)
        delete(snapshot.text, allocator)
        delete(snapshot.identity_index, allocator)
        delete(snapshot.traversal_index, allocator)
        storage.tlsf_owner_destroy(&snapshot.allocator)
    }
    state^ = {}
}
