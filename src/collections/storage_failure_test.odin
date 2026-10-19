#+test
package collections

import "base:runtime"
import storage "../core/storage"
import "core:testing"

// Reject new backing while allowing admitted pools to serve and reclaim existing data.
collections_test_reject_backing :: proc(
    data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int,
    old_memory: rawptr, old_size: int,
    location: runtime.Source_Code_Location = #caller_location) -> (
        []byte, runtime.Allocator_Error) {
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        return nil, .Out_Of_Memory
    }
    backing := cast(^runtime.Allocator)data
    return backing.procedure(
        backing.data, mode, size, alignment, old_memory, old_size, location)
}

// Record/index/text failures keep accepted identities, arrays and labels authoritative.
@(test)
collections_rejected_storage_admission_preserves_accepted_state :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(91)
    testing.expect_value(t,
        favorites_add(set, entry_id, collections_test_id(92)), Policy_Error.None)
    identity, failure := placement_identity_for_entry(set, entry_id)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t,
        placement_canonical_name_set(set, identity, "Accepted"), Policy_Error.None)
    backing := set^.allocator.backing_allocator
    set^.allocator.backing_allocator = {
        procedure = collections_test_reject_backing,
        data = &backing,
    }
    defer set^.allocator.backing_allocator = backing
    before := storage.tlsf_owner_diagnostics(&set^.allocator)
    collections_test_reject_tables(t, set)
    collections_test_reject_label_import(t, set, identity)
    after := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, after.retained_bytes, before.retained_bytes)
    testing.expect_value(t, find_entry(set, entry_id), 0)
    testing.expect_value(t, set^.entry_count, 1)
    testing.expect_value(t, string(set^.entries[0].canonical_name), "Accepted")
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Force record and UUID-index replacements to require rejected backing admission.
collections_test_reject_tables :: proc(t: ^testing.T, set: ^Set) {
    entries := raw_data(set^.entries)
    index := raw_data(set^.entry_index)
    collection_records := raw_data(set^.collections)
    collection_index := raw_data(set^.collection_index)
    testing.expect(t, !entries_ensure_capacity(set, 1 << 20))
    testing.expect(t, !entry_index_ensure_capacity(set, 1 << 20))
    testing.expect(t, !collections_ensure_capacity(set, 1 << 20))
    testing.expect(t, !collection_index_ensure_capacity(set, 1 << 20))
    testing.expect_value(t, raw_data(set^.entries), entries)
    testing.expect_value(t, raw_data(set^.entry_index), index)
    testing.expect_value(t, raw_data(set^.collections), collection_records)
    testing.expect_value(t, raw_data(set^.collection_index), collection_index)
}

// Reject a copied label and reclaim a partially copied placement import.
collections_test_reject_label_import :: proc(
    t: ^testing.T, set: ^Set, identity: Placement_Identity) {
    label := make([]u8, 1024 * 1024, context.allocator)
    defer delete(label, context.allocator)
    for &value in label {
        value = 'x'
    }
    testing.expect_value(t, placement_canonical_name_set(
        set, identity, string(label)), Policy_Error.Allocation_Failed)
    custom := "Copied before rejected canonical text"
    entry := set^.entries[0]
    entry.id = collections_test_id(93)
    entry.animation_id = collections_test_id(94)
    entry.sibling_order = 1
    entry.custom_name = transmute([]u8)custom
    entry.custom_name_length = len(custom)
    entry.canonical_name = label
    entry.canonical_name_length = len(label)
    testing.expect_value(t, append_entry(set, entry), Policy_Error.Allocation_Failed)
    testing.expect_value(t, find_entry(set, entry.id), -1)
}

// A copied creation never publishes a head if its owned name cannot be admitted.
@(test)
collections_create_allocation_failure_preserves_state_and_retries :: proc(
    t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    name: [COLLECTION_NAME_MAX_BYTES]u8
    for &value in name {
        value = 'a'
    }
    mutation, failure := make_collection_create_mutation(
        set, collections_test_id(100), string(name[:]))
    testing.expect_value(t, failure, Policy_Error.None)
    backing := set^.allocator.backing_allocator
    set^.allocator.backing_allocator = {
        procedure = collections_test_reject_backing,
        data = &backing,
    }
    ballast: [512][]u8
    count := collections_test_exhaust_name_storage(set, ballast[:])
    before := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t,
        apply_mutation(set, mutation), Mutation_Error.Allocation_Failed)
    after := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, set^.collection_count, 1)
    testing.expect_value(t, find_collection(set, mutation.collection_id), -1)
    testing.expect_value(t, validate(set), Validation_Error.None)
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    for block in ballast[:count] {
        delete(block, allocator)
    }
    set^.allocator.backing_allocator = backing
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    testing.expect_value(t, set^.collections[1].order, i64(1))
}

// Consume all same-sized name slots while the fixture's backing allocator rejects growth.
collections_test_exhaust_name_storage :: proc(set: ^Set, blocks: [][]u8) -> int {
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    for index in 0..<len(blocks) {
        block, failure := make([]u8, COLLECTION_NAME_MAX_BYTES, allocator)
        if failure != nil {
            return index
        }
        blocks[index] = block
    }
    panic("collection fixture ballast did not exhaust its initial pool")
}

// A creation requiring record growth cannot displace accepted heads on allocation failure.
@(test)
collections_create_table_growth_failure_preserves_existing_heads :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    for index in 1..<len(set^.collections) {
        mutation, failure := make_collection_create_mutation(
            set, collections_test_id(u8(index)), "Name")
        testing.expect_value(t, failure, Policy_Error.None)
        testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    }
    mutation, failure := make_collection_create_mutation(
        set, collections_test_id(100), "Name")
    testing.expect_value(t, failure, Policy_Error.None)
    backing := set^.allocator.backing_allocator
    set^.allocator.backing_allocator = {
        procedure = collections_test_reject_backing,
        data = &backing,
    }
    ballast: [512][]u8
    count := collections_test_exhaust_name_storage(set, ballast[:])
    records := raw_data(set^.collections)
    before := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t,
        apply_mutation(set, mutation), Mutation_Error.Allocation_Failed)
    after := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t, raw_data(set^.collections), records)
    testing.expect_value(t, set^.collection_count, 4)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, validate(set), Validation_Error.None)
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    for block in ballast[:count] {
        delete(block, allocator)
    }
    set^.allocator.backing_allocator = backing
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
}
