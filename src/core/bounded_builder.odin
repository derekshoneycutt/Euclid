package core

import "base:runtime"

// Report the result of a bounded builder mutation or lifecycle request.
Bounded_Builder_Status :: enum {
    Ok,
    Invalid_Argument,
    Limit_Exceeded,
    Allocation_Failed,
    Sealed,
}

// Build a bounded byte sequence in allocator-owned storage.
//
// Notes:
//   - Growth abandons prior allocations for bulk reclamation by the allocator owner.
//   - Abandoned capacity remains below twice the live allocation capacity.
//   - A successful seal permanently rejects further mutation.
Bounded_Byte_Builder :: struct {
    // Allocator ownership and hard logical admission limit.
    allocator : runtime.Allocator,
    max_count : int,

    // Current allocation, populated prefix, and cumulative allocated byte capacity.
    storage : []u8,
    count : int,
    allocated_capacity : int,

    // One-way lifecycle state.
    sealed : bool,
}

// Build a bounded sequence of plain values in allocator-owned storage.
//
// Notes:
//   - `Element` must be plain data with no destructor or independently owned storage.
//   - Growth abandons prior allocations for bulk reclamation by the allocator owner.
//   - Abandoned capacity remains below twice the live allocation capacity.
//   - A successful seal permanently rejects further mutation.
Bounded_Element_Builder :: struct($Element: typeid) {
    // Allocator ownership and hard logical element limit.
    allocator : runtime.Allocator,
    max_count : int,

    // Current allocation, populated prefix, and cumulative allocated element capacity.
    storage : []Element,
    count : int,
    allocated_capacity : int,

    // One-way lifecycle state.
    sealed : bool,
}

//   Initialize an empty bounded byte builder without allocating storage.
//
// Parameters:
//   - builder: Zero or discarded builder state to initialize.
//   - max_count: Positive hard limit for admitted bytes.
//   - owner: Live arena owner that reclaims all growth allocations in bulk.
//
// Returns:
//   - `Ok` on success, or `Invalid_Argument` without changing `builder`.
bounded_byte_builder_init :: proc(
    builder: ^Bounded_Byte_Builder,
    max_count: int,
    owner: ^Arena_Owner) -> Bounded_Builder_Status {
    return bounded_byte_builder_init_with_allocator(
        builder, max_count, arena_owner_allocator(owner))
}

//   Initialize a byte builder through a supplied allocator for failure testing.
bounded_byte_builder_init_with_allocator :: proc(
    builder: ^Bounded_Byte_Builder,
    max_count: int,
    allocator: runtime.Allocator) -> Bounded_Builder_Status {
    if builder == nil || max_count <= 0 || allocator.procedure == nil {
        return .Invalid_Argument
    }
    builder^ = {allocator = allocator, max_count = max_count}
    return .Ok
}

//   Append bytes transactionally while enforcing the logical limit.
//
// Parameters:
//   - builder: Initialized, unsealed destination builder.
//   - values: Bytes copied into the populated prefix.
//
// Returns:
//   - Explicit status; any failure leaves storage, count, and contents unchanged.
bounded_byte_builder_append :: proc(
    builder: ^Bounded_Byte_Builder,
    values: []u8) -> Bounded_Builder_Status {
    status := bounded_byte_builder_reserve(builder, len(values))
    if status != .Ok {
        return status
    }
    copy(builder.storage[builder.count:], values)
    builder.count += len(values)
    return .Ok
}

//   Seal a byte builder and return its populated storage.
//
// Parameters:
//   - builder: Initialized builder to seal exactly once.
//
// Returns:
//   - Populated bytes and `Ok`, or nil with an explicit rejection status.
//
// Side effects:
//   - Permanently rejects subsequent append and seal requests.
bounded_byte_builder_seal :: proc(
    builder: ^Bounded_Byte_Builder) -> ([]u8, Bounded_Builder_Status) {
    if builder == nil || builder.max_count <= 0 {
        return nil, .Invalid_Argument
    }
    if builder.sealed {
        return nil, .Sealed
    }
    builder.sealed = true
    return builder.storage[:builder.count], .Ok
}

//   Initialize an empty bounded plain-element builder without allocating storage.
//
// Parameters:
//   - builder: Zero or discarded typed builder state to initialize.
//   - max_count: Positive hard limit for admitted elements.
//   - owner: Live arena owner that reclaims all growth allocations in bulk.
//
// Returns:
//   - `Ok` on success, or `Invalid_Argument` without changing `builder`.
bounded_element_builder_init :: proc(
    builder: ^$Builder/Bounded_Element_Builder($Element),
    max_count: int,
    owner: ^Arena_Owner) -> Bounded_Builder_Status {
    return bounded_element_builder_init_with_allocator(
        builder, max_count, arena_owner_allocator(owner))
}

//   Initialize a typed builder through a supplied allocator for failure testing.
bounded_element_builder_init_with_allocator :: proc(
    builder: ^$Builder/Bounded_Element_Builder($Element),
    max_count: int,
    allocator: runtime.Allocator) -> Bounded_Builder_Status {
    if builder == nil || max_count <= 0 || allocator.procedure == nil {
        return .Invalid_Argument
    }
    builder^ = {allocator = allocator, max_count = max_count}
    return .Ok
}

//   Append plain elements transactionally while enforcing the logical limit.
//
// Parameters:
//   - builder: Initialized, unsealed typed destination builder.
//   - values: Plain values copied into the populated prefix.
//
// Returns:
//   - Explicit status; any failure leaves storage, count, and contents unchanged.
bounded_element_builder_append :: proc(
    builder: ^$Builder/Bounded_Element_Builder($Element),
    values: []Element) -> Bounded_Builder_Status {
    status := bounded_element_builder_reserve(builder, len(values))
    if status != .Ok {
        return status
    }
    copy(builder.storage[builder.count:], values)
    builder.count += len(values)
    return .Ok
}

//   Seal a typed builder and return its populated storage.
//
// Parameters:
//   - builder: Initialized typed builder to seal exactly once.
//
// Returns:
//   - Populated elements and `Ok`, or nil with an explicit rejection status.
//
// Side effects:
//   - Permanently rejects subsequent append and seal requests.
bounded_element_builder_seal :: proc(
    builder: ^$Builder/Bounded_Element_Builder($Element)) ->
    ([]Element, Bounded_Builder_Status) {
    if builder == nil || builder.max_count <= 0 {
        return nil, .Invalid_Argument
    }
    if builder.sealed {
        return nil, .Sealed
    }
    builder.sealed = true
    return builder.storage[:builder.count], .Ok
}

//   Ensure one byte builder can admit an additional populated count.
bounded_byte_builder_reserve :: proc(
    builder: ^Bounded_Byte_Builder,
    additional_count: int) -> Bounded_Builder_Status {
    if builder == nil || builder.max_count <= 0 || additional_count < 0 {
        return .Invalid_Argument
    }
    if builder.sealed {
        return .Sealed
    }
    required, status := bounded_builder_required_count(
        builder.count, additional_count, builder.max_count)
    if status != .Ok || required <= len(builder.storage) {
        return status
    }
    capacity := bounded_builder_growth_capacity(
        len(builder.storage), required, builder.max_count)
    replacement, allocation_error := make([]u8, capacity, builder.allocator)
    if allocation_error != nil {
        return .Allocation_Failed
    }
    copy(replacement, builder.storage[:builder.count])
    builder.storage = replacement
    builder.allocated_capacity += capacity
    return .Ok
}

//   Ensure one typed builder can admit an additional populated count.
bounded_element_builder_reserve :: proc(
    builder: ^$Builder/Bounded_Element_Builder($Element),
    additional_count: int) -> Bounded_Builder_Status {
    if builder == nil || builder.max_count <= 0 || additional_count < 0 {
        return .Invalid_Argument
    }
    if builder.sealed {
        return .Sealed
    }
    required, status := bounded_builder_required_count(
        builder.count, additional_count, builder.max_count)
    if status != .Ok || required <= len(builder.storage) {
        return status
    }
    capacity := bounded_builder_growth_capacity(
        len(builder.storage), required, builder.max_count)
    replacement, allocation_error := make([]Element, capacity, builder.allocator)
    if allocation_error != nil {
        return .Allocation_Failed
    }
    copy(replacement, builder.storage[:builder.count])
    builder.storage = replacement
    builder.allocated_capacity += capacity
    return .Ok
}

//   Validate checked addition against one hard logical maximum.
bounded_builder_required_count :: proc(
    count, additional_count, max_count: int) ->
    (int, Bounded_Builder_Status) {
    if count < 0 || additional_count < 0 || max_count <= 0 {
        return 0, .Invalid_Argument
    }
    if additional_count > max_count-count {
        return 0, .Limit_Exceeded
    }
    return count + additional_count, .Ok
}

//   Select the smallest doubled capacity that admits `required` within `maximum`.
bounded_builder_growth_capacity :: proc(
    current, required, maximum: int) -> int {
    capacity := max(current, 1)
    for capacity < required {
        if capacity > maximum-capacity {
            return maximum
        }
        capacity *= 2
    }
    return min(capacity, maximum)
}