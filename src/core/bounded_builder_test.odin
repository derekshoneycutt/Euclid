package core

import "base:runtime"
import "core:mem"
import "core:testing"

//   Verify byte builders admit the exact limit and reject one byte beyond it.
@(test)
core_test_bounded_byte_builder_enforces_exact_limit :: proc(t: ^testing.T) {
    owner: Arena_Owner
    testing.expect(t, arena_owner_init(&owner, 64*uint(mem.Kilobyte)))
    defer arena_owner_destroy(&owner)
    builder: Bounded_Byte_Builder
    testing.expect_value(t, bounded_byte_builder_init(
        &builder, 5, &owner), Bounded_Builder_Status.Ok)

    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{1, 2, 3, 4, 5}), Bounded_Builder_Status.Ok)
    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{6}), Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, builder.count, 5)
}

//   Verify failed growth preserves all previously admitted byte state.
@(test)
core_test_bounded_byte_builder_preserves_state_on_failed_growth :: proc(
    t: ^testing.T) {
    builder: Bounded_Byte_Builder
    remaining_allocations := 1
    allocator := bounded_builder_test_allocator(&remaining_allocations)
    testing.expect_value(t, bounded_byte_builder_init_with_allocator(
        &builder, 8, allocator), Bounded_Builder_Status.Ok)
    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{1, 2}), Bounded_Builder_Status.Ok)
    previous_storage := raw_data(builder.storage)

    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{3}), Bounded_Builder_Status.Allocation_Failed)
    testing.expect_value(t, raw_data(builder.storage), previous_storage)
    testing.expect_value(t, builder.count, 2)
    testing.expect(t, mem.compare(
        builder.storage[:builder.count], []u8{1, 2}) == 0)
    delete(builder.storage, allocator)
}

//   Verify sealing publishes the populated prefix and rejects every later mutation.
@(test)
core_test_bounded_byte_builder_seals_once :: proc(t: ^testing.T) {
    owner: Arena_Owner
    testing.expect(t, arena_owner_init(&owner, 64*uint(mem.Kilobyte)))
    defer arena_owner_destroy(&owner)
    builder: Bounded_Byte_Builder
    testing.expect_value(t, bounded_byte_builder_init(
        &builder, 8, &owner), Bounded_Builder_Status.Ok)
    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{4, 5}), Bounded_Builder_Status.Ok)

    sealed, status := bounded_byte_builder_seal(&builder)
    testing.expect_value(t, status, Bounded_Builder_Status.Ok)
    testing.expect(t, mem.compare(sealed, []u8{4, 5}) == 0)
    testing.expect_value(t, bounded_byte_builder_append(
        &builder, []u8{6}), Bounded_Builder_Status.Sealed)
    _, second_status := bounded_byte_builder_seal(&builder)
    testing.expect_value(t, second_status, Bounded_Builder_Status.Sealed)
}

//   Verify typed builders preserve values and bound abandoned geometric capacity.
@(test)
core_test_bounded_element_builder_bounds_geometric_waste :: proc(t: ^testing.T) {
    owner: Arena_Owner
    testing.expect(t, arena_owner_init(&owner, 64*uint(mem.Kilobyte)))
    defer arena_owner_destroy(&owner)
    builder: Bounded_Element_Builder(u32)
    testing.expect_value(t, bounded_element_builder_init(
        &builder, 10, &owner), Bounded_Builder_Status.Ok)

    values := []u32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
    for value in values {
        testing.expect_value(t, bounded_element_builder_append(
            &builder, []u32{value}), Bounded_Builder_Status.Ok)
    }
    testing.expect_value(t, bounded_element_builder_append(
        &builder, []u32{11}), Bounded_Builder_Status.Limit_Exceeded)
    abandoned := builder.allocated_capacity-len(builder.storage)
    testing.expect(t, abandoned < 2*len(builder.storage))
    sealed, status := bounded_element_builder_seal(&builder)
    testing.expect_value(t, status, Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(sealed), len(values))
    for value, index in sealed {
        testing.expect_value(t, value, values[index])
    }
    testing.expect_value(t, bounded_element_builder_append(
        &builder, []u32{11}), Bounded_Builder_Status.Sealed)
}

//   Create an allocator using a test-owned allocation-request counter.
bounded_builder_test_allocator :: proc(
    remaining_allocations: ^int) -> mem.Allocator {
    return mem.Allocator{
        procedure = bounded_builder_test_allocator_proc,
        data = remaining_allocations,
    }
}

//   Fail allocation requests after the configured test limit is exhausted.
bounded_builder_test_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
    ([]byte, mem.Allocator_Error) {
    remaining := (^int)(allocator_data)
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        if remaining^ <= 0 {
            return nil, mem.Allocator_Error.Out_Of_Memory
        }
        remaining^ -= 1
    }
    return runtime.heap_allocator_proc(
        nil, mode, size, alignment, old_memory, old_size, location)
}