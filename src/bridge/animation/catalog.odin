package bridge_animation

import bridgemodel "../model"
import content "../../view/content"
import contentdata "../../core/content"
import uuid "core:encoding/uuid"
import fmt "core:fmt"
import strings "core:strings"
import utf8 "core:unicode/utf8"

ANIMATION_LOOKUP_INITIAL_RESERVE :: 512
ANIMATION_LOOKUP_LOAD_FACTOR_NUMERATOR :: 7
ANIMATION_LOOKUP_LOAD_FACTOR_DENOMINATOR :: 10

//   Parse a bridge-provided animation stable UUID string into typed identity.
parse_animation_stable_id :: proc(stable_id, name: cstring) -> (uuid.Identifier, bool) {
    if stable_id == nil {
        fmt.eprintln("add animation interface failed: nil stable_id for ", string(name))
        return {}, false
    }

    stable_id_text := string(stable_id)
    id, read_error := uuid.read(stable_id_text)
    if read_error != .None {
        fmt.eprintln(
            "add animation interface failed: invalid stable_id '",
            stable_id_text,
            "' for ",
            string(name))
        return {}, false
    }

    return id, true
}

//   Create a forward-only iterator over the animation registry list.
animation_iterator_begin :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface) ->
        bridgemodel.Euclid_Julia_Animation_Iterator {

    if ji == nil {
        return {}
    }

    return bridgemodel.Euclid_Julia_Animation_Iterator{
        current = ji^.animation_head,
    }
}

//   Return the current iterator node and advance to the next registry entry.
animation_iterator_next :: proc(
    it: ^bridgemodel.Euclid_Julia_Animation_Iterator) ->
        ^bridgemodel.Euclid_Julia_Animation_Interface {

    if it == nil || it^.current == nil {
        return nil
    }

    current := it^.current
    it^.current = current^.next_in_registry
    return current
}

//   Attach a child animation to its parent while preserving sibling order.
animation_link_child :: proc(
    parent, child: ^bridgemodel.Euclid_Julia_Animation_Interface) {

    if parent == nil || child == nil {
        return
    }

    child^.parent = parent
    if parent^.first_child == nil {
        parent^.first_child = child
        parent^.last_child = child
        return
    }

    sibling := parent^.last_child
    sibling^.next_sibling = child
    child^.prev_sibling = sibling
    parent^.last_child = child
}

//   Insert one child by its validated sibling order without disturbing tree links.
animation_link_child_ordered :: proc(
    parent, child: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    if parent == nil || child == nil {
        return false
    }
    for sibling := parent^.first_child; sibling != nil; sibling = sibling^.next_sibling {
        if sibling^.sibling_order == child^.sibling_order {
            return false
        }
        if sibling^.sibling_order > child^.sibling_order {
            child^.parent = parent
            child^.next_sibling = sibling
            child^.prev_sibling = sibling^.prev_sibling
            if sibling^.prev_sibling == nil {
                parent^.first_child = child
            } else {
                sibling^.prev_sibling^.next_sibling = child
            }
            sibling^.prev_sibling = child
            return true
        }
    }
    animation_link_child(parent, child)
    return true
}

//   Materialize a validated catalogue generation into an empty native registry.
content_generation_materialize :: proc(
    iface: ^bridgemodel.Euclid_Julia_Interface,
    snapshot: ^content.Content_Generation) -> bool {
    if !content_generation_shape_is_valid(snapshot) || iface == nil ||
       iface^.animation_count != 0 || iface^.animation_lookup_count != 0 ||
       !ensure_julia_interface_instance_registry_arena(iface) {
        return false
    }
    iface^.content_generation = snapshot^.generation
        if !content_generation_allocate_nodes(iface, snapshot) ||
             !content_generation_link_parents(iface, snapshot) {
        clean_julia_interface_instance(iface)
        return false
    }
    return iface^.animation_count == int(snapshot^.record_count)
}

//   Validate generation bounds, identity uniqueness, paths, and parent topology.
content_generation_shape_is_valid :: proc(snapshot: ^content.Content_Generation) -> bool {
    if snapshot == nil || snapshot^.generation == 0 ||
       !snapshot^.sealed ||
       snapshot^.record_count == 0 ||
       snapshot^.record_count > content.CATALOG_RECORD_CAPACITY {
        return false
    }
    terminal_count := 0
    builder_count := 0
    for index in 0..<int(snapshot^.record_count) {
        if snapshot^.records[index].node_kind == .Terminal {
            terminal_count += 1
        } else if snapshot^.records[index].node_kind == .Builder {
            builder_count += 1
        }
        if !content_generation_record_is_valid(snapshot, index) {
            return false
        }
    }
    return terminal_count == 1 && builder_count == 1
}

//   Validate one bounded row and its ancestor chain before registry allocation.
content_generation_record_is_valid :: proc(
    snapshot: ^content.Content_Generation, index: int) -> bool {
    record := &snapshot^.records[index]
    if record.stable_id == (uuid.Identifier{}) || record.catalog_order != i32(index) ||
       record.sibling_order < 0 ||
    !content_generation_record_text_is_valid(snapshot, record) ||
    !content_generation_record_is_unique(snapshot, index) {
        return false
    }
    return content_generation_ancestor_chain_is_valid(snapshot, index)
}

//   Validate bounded generation strings and their node-kind-specific path contract.
content_generation_record_text_is_valid :: proc(
    snapshot: ^content.Content_Generation, record: ^content.Catalog_Record) -> bool {
    name, name_status := contentdata.content_generation_text(
        snapshot, record.display_name)
    path, path_status := contentdata.content_generation_text(
        snapshot, record.implementation_path)
    if name_status != .Ok || path_status != .Ok || len(name) == 0 ||
       len(name) > content.CATALOG_NAME_BYTE_CAPACITY ||
       len(path) > content.CATALOG_PATH_BYTE_CAPACITY {
        return false
    }
    if !utf8.valid_string(name) || strings.contains(name, "\x00") {
        return false
    }
    if record.node_kind == .Terminal || record.node_kind == .Builder {
        if record.has_parent || len(path) != 0 {
            return false
        }
    } else if record.node_kind == .Animation {
        if !catalog_path_bytes_are_safe(transmute([]u8)path) {
            return false
        }
    } else {
        return false
    }
    return true
}

//   Reject duplicate identities or sibling positions under the same parent.
content_generation_record_is_unique :: proc(
    snapshot: ^content.Content_Generation, index: int) -> bool {
    record := &snapshot^.records[index]
    for prior_index in 0..<index {
        prior := &snapshot^.records[prior_index]
        same_parent := prior.has_parent == record.has_parent &&
            (!record.has_parent || prior.parent_stable_id == record.parent_stable_id)
        if prior.stable_id == record.stable_id ||
           (same_parent && prior.sibling_order == record.sibling_order) {
            return false
        }
    }
    return true
}

//   Verify every parent exists and the row's ancestor chain is acyclic.
content_generation_ancestor_chain_is_valid :: proc(
    snapshot: ^content.Content_Generation, index: int) -> bool {
    record := &snapshot^.records[index]
    if !record.has_parent {
        return true
    }
    current_id := record.parent_stable_id
    for _ in 0..<int(snapshot^.record_count) {
        if current_id == record.stable_id {
            return false
        }
        parent_index := content_generation_record_index(snapshot, current_id)
        if parent_index < 0 {
            return false
        }
        parent := &snapshot^.records[parent_index]
        if !parent.has_parent {
            return true
        }
        current_id = parent.parent_stable_id
    }
    return false
}

//   Find one stable identity in fixed generation storage.
content_generation_record_index :: proc(
    snapshot: ^content.Content_Generation, stable_id: uuid.Identifier) -> int {
    for index in 0..<int(snapshot^.record_count) {
        if snapshot^.records[index].stable_id == stable_id {
            return index
        }
    }
    return -1
}

//   Reject paths that are absolute, noncanonical, or escape package content.
catalog_path_bytes_are_safe :: proc(path: []u8) -> bool {
    if len(path) == 0 || path[0] == '/' {
        return false
    }
    component_start := 0
    for index in 0..=len(path) {
        if index < len(path) && path[index] != '/' {
            if path[index] == '\\' || path[index] == ':' {
                return false
            }
            continue
        }
        component := string(path[component_start:index])
        if len(component) == 0 || component == "." || component == ".." {
            return false
        }
        component_start = index + 1
    }
    return true
}

// Allocate registry-owned names and paths; prepared UI draws retain these beyond
// the SQLite read and content borrow. Interface retirement releases the copies.
content_generation_allocate_nodes :: proc(
    iface: ^bridgemodel.Euclid_Julia_Interface,
    snapshot: ^content.Content_Generation) -> bool {
    for index in 0..<int(snapshot^.record_count) {
        record := &snapshot^.records[index]
        node := new(bridgemodel.Euclid_Julia_Animation_Interface,
            iface^.animation_registry_allocator)
        if node == nil {
            return false
        }
        node^.stable_id = record.stable_id
        node^.node_kind = bridgemodel.Animation_Node_Kind(record.node_kind)
        node^.sibling_order = record.sibling_order
        node^.catalog_order = record.catalog_order
        name, name_status := contentdata.content_generation_text(
            snapshot, record.display_name)
        path, path_status := contentdata.content_generation_text(
            snapshot, record.implementation_path)
        if name_status != .Ok || path_status != .Ok {
            return false
        }
        node^.name = strings.clone(name, iface^.animation_registry_allocator)
        if len(path) > 0 {
            node^.implementation_path = strings.clone(
                path, iface^.animation_registry_allocator)
        }
        animation_append_to_registry(iface, node)
        if !animation_lookup_insert(iface, node^.stable_id, node) {
            return false
        }
    }
    return true
}

//   Resolve parent UUIDs only after all nodes and lookup entries exist.
content_generation_link_parents :: proc(
    iface: ^bridgemodel.Euclid_Julia_Interface,
    snapshot: ^content.Content_Generation) -> bool {
    for index in 0..<int(snapshot^.record_count) {
        record := &snapshot^.records[index]
        if !record.has_parent {
            continue
        }
        child := animation_lookup_find(iface, record.stable_id)
        parent := animation_lookup_find(iface, record.parent_stable_id)
        if child == nil || !animation_link_child_ordered(parent, child) {
            return false
        }
    }
    return true
}

//   Append a new node to the registry's arena-backed insertion order list.
animation_append_to_registry :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) {

    if ji == nil || node == nil {
        return
    }

    if ji^.animation_head == nil {
        ji^.animation_head = node
        ji^.animation_tail = node
    } else {
        node^.prev_in_registry = ji^.animation_tail
        ji^.animation_tail^.next_in_registry = node
        ji^.animation_tail = node
    }

    ji^.animation_count += 1
}

//  Generate the hash for a stable UUID value
animation_hash_stable_id :: proc(stable_id: uuid.Identifier) -> u64 {
    bytes := stable_id
    hash: u64 = 1469598103934665603
    for b in bytes {
        hash = (hash ~ u64(b)) * 1099511628211
    }

    if hash == 0 {
        return 1
    }

    return hash
}

//   Probe the UUID lookup table for an occupied match or an insertion slot.
animation_lookup_probe :: proc(
    entries: []bridgemodel.Euclid_Julia_Animation_Lookup_Entry,
    capacity: int,
    stable_id: uuid.Identifier,
    for_insert: bool) -> (int, bool) {

    if capacity <= 0 || len(entries) < capacity {
        return -1, false
    }

    mask := capacity - 1
    index := int(animation_hash_stable_id(stable_id) & u64(mask))
    for _ in 0..<capacity {
        entry := entries[index]
        if !entry.is_occupied {
            if for_insert {
                return index, false
            }
            return -1, false
        }

        if entry.stable_id == stable_id {
            return index, true
        }

        index = (index + 1) & mask
    }

    return -1, false
}

//   Allocate a lookup table buffer from the registry arena.
animation_lookup_allocate :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    new_capacity: int) -> []bridgemodel.Euclid_Julia_Animation_Lookup_Entry {

    if ji == nil || new_capacity <= 0 || (new_capacity & (new_capacity - 1)) != 0 {
        return nil
    }

    new_entries := make([]bridgemodel.Euclid_Julia_Animation_Lookup_Entry,
        new_capacity, ji^.animation_registry_allocator)
    if len(new_entries) != new_capacity {
        return nil
    }

    return new_entries
}

//   Grow and rehash the UUID lookup table into a larger arena allocation.
animation_lookup_grow :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    new_capacity: int) -> bool {

    if ji == nil || new_capacity <= 0 {
        return false
    }

    new_entries := animation_lookup_allocate(ji, new_capacity)
    if len(new_entries) != new_capacity {
        return false
    }

    old_entries := ji^.animation_lookup_entries
    old_capacity := ji^.animation_lookup_capacity

    ji^.animation_lookup_entries = new_entries
    ji^.animation_lookup_capacity = new_capacity
    ji^.animation_lookup_count = 0

    if old_capacity <= 0 {
        return true
    }

    return rehash_animation_lookup(ji, old_entries, old_capacity)
}

//   Reinsert every occupied entry from the old lookup table into the grown one.
//
// Returns:
//   - true when all occupied entries rehash without collision or overflow.
rehash_animation_lookup :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    old_entries: []bridgemodel.Euclid_Julia_Animation_Lookup_Entry,
    old_capacity: int) -> bool {

    for i in 0..<old_capacity {
        entry := old_entries[i]
        if !entry.is_occupied || entry.animation == nil {
            continue
        }

        insert_index, found := animation_lookup_probe(
            ji^.animation_lookup_entries,
            ji^.animation_lookup_capacity,
            entry.stable_id,
            true)
        if insert_index < 0 || found {
            return false
        }

        ji^.animation_lookup_entries[insert_index] =
            bridgemodel.Euclid_Julia_Animation_Lookup_Entry{
                is_occupied = true,
                stable_id = entry.stable_id,
                animation = entry.animation,
            }
        ji^.animation_lookup_count += 1
    }

    return true
}

//   Ensure the lookup table has enough free space for another inserted animation.
animation_lookup_ensure_capacity :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface) -> bool {
    if ji == nil {
        return false
    }

    if ji^.animation_lookup_capacity == 0 {
        return animation_lookup_grow(ji, ANIMATION_LOOKUP_INITIAL_RESERVE)
    }

    next_count := ji^.animation_lookup_count + 1
    if next_count * ANIMATION_LOOKUP_LOAD_FACTOR_DENOMINATOR <
        ji^.animation_lookup_capacity * ANIMATION_LOOKUP_LOAD_FACTOR_NUMERATOR {
        return true
    }

    return animation_lookup_grow(ji, ji^.animation_lookup_capacity * 2)
}

//   Insert a stable UUID to animation pointer mapping into the lookup table.
animation_lookup_insert :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    stable_id: uuid.Identifier,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {

    if ji == nil || node == nil {
        return false
    }

    if !animation_lookup_ensure_capacity(ji) {
        return false
    }

    insert_index, found := animation_lookup_probe(
        ji^.animation_lookup_entries,
        ji^.animation_lookup_capacity,
        stable_id,
        true)
    if insert_index < 0 || found {
        return false
    }

    ji^.animation_lookup_entries[insert_index] =
        bridgemodel.Euclid_Julia_Animation_Lookup_Entry{
            is_occupied = true,
            stable_id = stable_id,
            animation = node,
        }
    ji^.animation_lookup_count += 1
    return true
}

//   Resolve a stable UUID to a registry node pointer.
animation_lookup_find :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    stable_id: uuid.Identifier) -> ^bridgemodel.Euclid_Julia_Animation_Interface {

    if ji == nil || ji^.animation_lookup_capacity <= 0 {
        return nil
    }

    index, found := animation_lookup_probe(
        ji^.animation_lookup_entries,
        ji^.animation_lookup_capacity,
        stable_id,
        false)
    if !found || index < 0 {
        return nil
    }

    return ji^.animation_lookup_entries[index].animation
}
