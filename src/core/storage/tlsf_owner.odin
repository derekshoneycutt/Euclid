package storage

import "base:runtime"
import "core:mem"
import tlsf "core:mem/tlsf"

TLSF_OWNER_DEFAULT_POOL_CAPACITY :: 64 * mem.Kilobyte
TLSF_OWNER_DEFAULT_GROWTH_QUANTUM :: 64 * mem.Kilobyte

Tlsf_Owner_Status :: enum u8 {
    Ok,
    Invalid_Owner,
    Invalid_Capacity,
    Allocation_Failed,
    Pool_Initialization_Failed,
}

Tlsf_Owner_Pool :: struct {
    allocator: tlsf.Allocator,
    backing: []u8,
    next: ^Tlsf_Owner_Pool,
}

Tlsf_Owner_Request :: struct {
    mode: runtime.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location,
}

Tlsf_Owner_Diagnostics :: struct {
    initialized: bool,
    current_live_bytes: uint,
    retained_bytes: uint,
    live_allocation_count: uint,
    pool_count: uint,
    peak_live_bytes: uint,
    peak_allocation_count: uint,
    growth_failure_count: uint,
    destroy_count: uint,
}

// Own stable TLSF controls and caller-backed pools for one reusable allocation domain.
Tlsf_Owner :: struct {
    first_pool: ^Tlsf_Owner_Pool,
    last_pool: ^Tlsf_Owner_Pool,
    backing_allocator: runtime.Allocator,
    growth_quantum: uint,
    current_live_bytes: uint,
    retained_bytes: uint,
    live_allocation_count: uint,
    pool_count: uint,
    peak_live_bytes: uint,
    peak_allocation_count: uint,
    growth_failure_count: uint,
    destroy_count: uint,
    initialized: bool,
}

// Initialize one pool from a real allocator domain owned for this store's lifetime.
tlsf_owner_init :: proc(
    owner: ^Tlsf_Owner,
    backing_allocator: runtime.Allocator,
    initial_capacity := uint(TLSF_OWNER_DEFAULT_POOL_CAPACITY),
    growth_quantum := uint(TLSF_OWNER_DEFAULT_GROWTH_QUANTUM)) -> Tlsf_Owner_Status {
    if owner == nil || owner.initialized || owner.first_pool != nil ||
        backing_allocator.procedure == nil {
        return .Invalid_Owner
    }
    if initial_capacity == 0 || growth_quantum == 0 ||
        initial_capacity > uint(max_pool_capacity()) ||
        growth_quantum > uint(max_pool_capacity()) {
        return .Invalid_Capacity
    }
    owner^ = {}
    owner.backing_allocator = backing_allocator
    owner.growth_quantum = growth_quantum
    pool, status := tlsf_owner_create_pool(owner, initial_capacity)
    if status != .Ok {
        owner^ = {}
        return status
    }
    owner.first_pool = pool
    owner.last_pool = pool
    owner.pool_count = 1
    owner.retained_bytes = uint(len(pool.backing))
    owner.initialized = true
    return .Ok
}

// Return the allocator adapter only while the owner is live.
tlsf_owner_allocator :: proc(owner: ^Tlsf_Owner) -> runtime.Allocator {
    if owner == nil || !owner.initialized {
        return {}
    }
    return {
        procedure = tlsf_owner_allocator_proc,
        data = owner,
    }
}

// Release every pool and its tracking node while retaining terminal diagnostics.
tlsf_owner_destroy :: proc(owner: ^Tlsf_Owner) {
    if owner == nil || !owner.initialized {
        return
    }
    pool := owner.first_pool
    for pool != nil {
        next := pool.next
        tlsf.destroy(&pool.allocator)
        delete(pool.backing, owner.backing_allocator)
        free(pool, owner.backing_allocator)
        pool = next
    }
    owner.first_pool = nil
    owner.last_pool = nil
    owner.backing_allocator = {}
    owner.current_live_bytes = 0
    owner.retained_bytes = 0
    owner.live_allocation_count = 0
    owner.pool_count = 0
    owner.initialized = false
    owner.destroy_count += 1
}

// Observe current ownership and reuse counters without exposing allocator state.
tlsf_owner_diagnostics :: proc(owner: ^Tlsf_Owner) -> Tlsf_Owner_Diagnostics {
    if owner == nil {
        return {}
    }
    return Tlsf_Owner_Diagnostics{
        initialized = owner.initialized,
        current_live_bytes = owner.current_live_bytes,
        retained_bytes = owner.retained_bytes,
        live_allocation_count = owner.live_allocation_count,
        pool_count = owner.pool_count,
        peak_live_bytes = owner.peak_live_bytes,
        peak_allocation_count = owner.peak_allocation_count,
        growth_failure_count = owner.growth_failure_count,
        destroy_count = owner.destroy_count,
    }
}

// Route allocator calls through the owning TLSF pool and preserve failed resizes.
tlsf_owner_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) -> (
        []byte, runtime.Allocator_Error) {
    owner := cast(^Tlsf_Owner)allocator_data
    if owner == nil || !owner.initialized {
        return nil, .Invalid_Argument
    }
    request: Tlsf_Owner_Request = {mode, size, alignment, old_memory, old_size, location}
    return tlsf_owner_dispatch(owner, request)
}

// Dispatch one operation after validating the owner exactly once.
tlsf_owner_dispatch :: proc(
    owner: ^Tlsf_Owner,
    request: Tlsf_Owner_Request) -> ([]byte, runtime.Allocator_Error) {
    switch request.mode {
    case .Alloc, .Alloc_Non_Zeroed:
        return tlsf_owner_allocate(
            owner, request.size, request.alignment, request.mode, request.location)
    case .Free:
        pool := tlsf_owner_find_pool(owner, request.old_memory)
        if pool == nil || request.old_memory == nil || request.old_size < 0 {
            return nil, .Invalid_Argument
        }
        return tlsf_owner_free(owner, pool, request)
    case .Resize, .Resize_Non_Zeroed:
        return tlsf_owner_resize(owner, request)
    case .Query_Features:
        return tlsf_owner_query_features(request.old_memory)
    case .Free_All, .Query_Info:
        return nil, .Mode_Not_Implemented
    }
    return nil, .Invalid_Argument
}

// Free one allocation through the TLSF pool that owns its address.
tlsf_owner_free :: proc(
    owner: ^Tlsf_Owner, pool: ^Tlsf_Owner_Pool,
    request: Tlsf_Owner_Request) -> ([]byte, runtime.Allocator_Error) {
    allocator := tlsf.allocator(&pool.allocator)
    _, err := allocator.procedure(
        allocator.data,
        .Free,
        0,
        request.alignment,
        request.old_memory,
        request.old_size,
        request.location)
    if err == nil {
        tlsf_owner_record_free(owner, uint(request.old_size))
    }
    return nil, err
}

// Advertise only allocator operations implemented by this reusable owner.
tlsf_owner_query_features :: proc(
    old_memory: rawptr) -> ([]byte, runtime.Allocator_Error) {
    features := cast(^runtime.Allocator_Mode_Set)old_memory
    if features != nil {
        features^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed}
    }
    return nil, nil
}

// Reuse existing pools before transactionally admitting one sized for this request.
tlsf_owner_allocate :: proc(
    owner: ^Tlsf_Owner,
    size, alignment: int,
    mode: runtime.Allocator_Mode,
    location: runtime.Source_Code_Location) -> ([]byte, runtime.Allocator_Error) {
    if size < 0 || !tlsf_owner_alignment_valid(alignment) {
        return nil, .Invalid_Argument
    }
    if size == 0 {
        return nil, nil
    }
    result, err := tlsf_owner_allocate_from_pools(owner, size, alignment, mode, location)
    if err == nil {
        tlsf_owner_record_allocation(owner, uint(size))
        return result, nil
    }
    if err != .Out_Of_Memory {
        return nil, err
    }
    return tlsf_owner_allocate_new_pool(owner, size, alignment, mode, location)
}

// Try every admitted TLSF control before allocating another pool.
tlsf_owner_allocate_from_pools :: proc(
    owner: ^Tlsf_Owner,
    size, alignment: int,
    mode: runtime.Allocator_Mode,
    location: runtime.Source_Code_Location) -> ([]byte, runtime.Allocator_Error) {
    for pool := owner.first_pool; pool != nil; pool = pool.next {
        result, err := tlsf_owner_pool_allocate(pool, size, alignment, mode, location)
        if err == nil || err != .Out_Of_Memory {
            return result, err
        }
    }
    return nil, .Out_Of_Memory
}

// Admit a request-sized pool only after it satisfies the triggering allocation.
tlsf_owner_allocate_new_pool :: proc(
    owner: ^Tlsf_Owner,
    size, alignment: int,
    mode: runtime.Allocator_Mode,
    location: runtime.Source_Code_Location) -> ([]byte, runtime.Allocator_Error) {
    payload_capacity, ok := tlsf_owner_growth_capacity(
        owner, uint(size), uint(alignment))
    if !ok {
        owner.growth_failure_count += 1
        return nil, .Out_Of_Memory
    }
    pool, status := tlsf_owner_create_pool(owner, payload_capacity)
    if status != .Ok {
        owner.growth_failure_count += 1
        return nil, .Out_Of_Memory
    }
    result, err := tlsf_owner_pool_allocate(pool, size, alignment, mode, location)
    if err != nil {
        tlsf.destroy(&pool.allocator)
        delete(pool.backing, owner.backing_allocator)
        free(pool, owner.backing_allocator)
        owner.growth_failure_count += 1
        return nil, err
    }
    owner.last_pool.next = pool
    owner.last_pool = pool
    owner.pool_count += 1
    owner.retained_bytes += uint(len(pool.backing))
    tlsf_owner_record_allocation(owner, uint(size))
    return result, nil
}

// Preserve the old allocation unless a replacement has been fully acquired.
tlsf_owner_resize :: proc(
    owner: ^Tlsf_Owner,
    request: Tlsf_Owner_Request) -> ([]byte, runtime.Allocator_Error) {
    if !tlsf_owner_request_is_valid(request) {
        return nil, .Invalid_Argument
    }
    if request.old_memory == nil {
        allocation_mode: runtime.Allocator_Mode
        allocation_mode = .Alloc if request.mode == .Resize else .Alloc_Non_Zeroed
        return tlsf_owner_allocate(
            owner, request.size, request.alignment, allocation_mode, request.location)
    }
    old_pool := tlsf_owner_find_pool(owner, request.old_memory)
    if old_pool == nil {
        return nil, .Invalid_Argument
    }
    if request.size == 0 {
        return tlsf_owner_resize_to_zero(owner, old_pool, request)
    }
    allocator := tlsf.allocator(&old_pool.allocator)
    result, err := allocator.procedure(
        allocator.data,
        request.mode,
        request.size,
        request.alignment,
        request.old_memory,
        request.old_size,
        request.location)
    if err == nil {
        tlsf_owner_record_resize(owner, uint(request.old_size), uint(request.size))
        return result, nil
    }
    if err != .Out_Of_Memory {
        return nil, err
    }
    return tlsf_owner_resize_by_replacement(owner, old_pool, request)
}

// Reject negative sizes or unsupported alignment before calling TLSF.
tlsf_owner_request_is_valid :: proc(request: Tlsf_Owner_Request) -> bool {
    return request.size >= 0 && request.old_size >= 0 &&
        tlsf_owner_alignment_valid(request.alignment)
}

// Reclaim an allocation resized to zero and update its owner diagnostics.
tlsf_owner_resize_to_zero :: proc(
    owner: ^Tlsf_Owner,
    pool: ^Tlsf_Owner_Pool,
    request: Tlsf_Owner_Request) -> ([]byte, runtime.Allocator_Error) {
    allocator := tlsf.allocator(&pool.allocator)
    _, err := allocator.procedure(
        allocator.data,
        request.mode,
        0,
        request.alignment,
        request.old_memory,
        request.old_size,
        request.location)
    if err == nil {
        tlsf_owner_record_free(owner, uint(request.old_size))
    }
    return nil, err
}

// Move storage only after a replacement has been successfully allocated.
tlsf_owner_resize_by_replacement :: proc(
    owner: ^Tlsf_Owner,
    old_pool: ^Tlsf_Owner_Pool,
    request: Tlsf_Owner_Request) -> ([]byte, runtime.Allocator_Error) {
    allocation_mode: runtime.Allocator_Mode
    allocation_mode = .Alloc if request.mode == .Resize else .Alloc_Non_Zeroed
    replacement, replacement_error := tlsf_owner_allocate(
        owner,
        request.size,
        request.alignment,
        allocation_mode,
        request.location)
    if replacement_error != nil {
        return nil, replacement_error
    }
    copy_count := min(request.old_size, request.size)
    copy(replacement[:copy_count], ([^]u8)(request.old_memory)[:copy_count])
    allocator := tlsf.allocator(&old_pool.allocator)
    _, free_error := allocator.procedure(
        allocator.data,
        .Free,
        0,
        request.alignment,
        request.old_memory,
        request.old_size,
        request.location)
    if free_error != nil {
        tlsf_owner_release_new_allocation(
            owner, replacement, request.size, request.alignment, request.location)
        return nil, free_error
    }
    tlsf_owner_record_free(owner, uint(request.old_size))
    return replacement, nil
}

// Allocate pool metadata before backing so failed bookkeeping cannot admit a pool.
tlsf_owner_create_pool :: proc(
    owner: ^Tlsf_Owner,
    payload_capacity: uint) -> (^Tlsf_Owner_Pool, Tlsf_Owner_Status) {
    pool_bytes, size_ok := tlsf_owner_pool_size(payload_capacity)
    if !size_ok {
        return nil, .Invalid_Capacity
    }
    metadata, metadata_error := owner.backing_allocator.procedure(
        owner.backing_allocator.data,
        .Alloc,
        size_of(Tlsf_Owner_Pool),
        align_of(Tlsf_Owner_Pool),
        nil,
        0)
    if metadata_error != nil {
        return nil, .Allocation_Failed
    }
    pool := cast(^Tlsf_Owner_Pool)raw_data(metadata)
    pool^ = {}
    backing, backing_error := runtime.make_aligned(
        []u8, pool_bytes, int(tlsf.ALIGN_SIZE), owner.backing_allocator)
    if backing_error != nil {
        free(pool, owner.backing_allocator)
        return nil, .Allocation_Failed
    }
    if tlsf.init_from_buffer(&pool.allocator, backing) != .None {
        delete(backing, owner.backing_allocator)
        free(pool, owner.backing_allocator)
        return nil, .Pool_Initialization_Failed
    }
    pool.backing = backing
    return pool, .Ok
}

// Compute checked, quantum-rounded payload capacity within TLSF's supported range.
tlsf_owner_growth_capacity :: proc(
    owner: ^Tlsf_Owner,
    size, alignment: uint) -> (uint, bool) {
    maximum := uint(max_pool_capacity())
    if size > maximum || alignment > maximum-size {
        return 0, false
    }
    required := size + alignment
    mapping_slack := size / uint(tlsf.SL_INDEX_COUNT)
    if required > maximum-mapping_slack-64 {
        return 0, false
    }
    requested := required + mapping_slack + 64
    quantum := owner.growth_quantum
    capacity := max(requested, quantum)
    if capacity > maximum-(quantum-1) {
        return 0, false
    }
    capacity = ((capacity + quantum - 1) / quantum) * quantum
    _, size_ok := tlsf_owner_pool_size(capacity)
    return capacity, size_ok
}

// Size one caller-backed pool for its payload plus TLSF bookkeeping.
tlsf_owner_pool_size :: proc(payload_capacity: uint) -> (int, bool) {
    maximum := uint(max_pool_capacity())
    if payload_capacity == 0 || payload_capacity > maximum-64 {
        return 0, false
    }
    pool_bytes := tlsf.estimate_pool_size(
        1, int(payload_capacity), int(tlsf.ALIGN_SIZE))
    if pool_bytes <= 0 || uint(pool_bytes) > maximum+64 {
        return 0, false
    }
    return pool_bytes, true
}

// Find the owning TLSF control by checking stable backing ranges.
tlsf_owner_find_pool :: proc(
    owner: ^Tlsf_Owner, pointer: rawptr) -> ^Tlsf_Owner_Pool {
    if pointer == nil {
        return nil
    }
    address := uintptr(pointer)
    for pool := owner.first_pool; pool != nil; pool = pool.next {
        start := uintptr(raw_data(pool.backing))
        if address >= start && address < start+uintptr(len(pool.backing)) {
            return pool
        }
    }
    return nil
}

// Invoke one pool allocator without changing owner-wide accounting.
tlsf_owner_pool_allocate :: proc(
    pool: ^Tlsf_Owner_Pool,
    size, alignment: int,
    mode: runtime.Allocator_Mode,
    location: runtime.Source_Code_Location) -> ([]byte, runtime.Allocator_Error) {
    allocator := tlsf.allocator(&pool.allocator)
    return allocator.procedure(
        allocator.data, mode, size, alignment, nil, 0, location)
}

// Free a provisional replacement if the original allocation cannot be retired.
tlsf_owner_release_new_allocation :: proc(
    owner: ^Tlsf_Owner,
    allocation: []u8,
    size, alignment: int,
    location: runtime.Source_Code_Location) {
    pool := tlsf_owner_find_pool(owner, raw_data(allocation))
    if pool == nil {
        return
    }
    allocator := tlsf.allocator(&pool.allocator)
    _, _ = allocator.procedure(
        allocator.data, .Free, 0, alignment, raw_data(allocation), size, location)
    tlsf_owner_record_free(owner, uint(size))
}

// Record a newly live allocation and update its diagnostic high-water marks.
tlsf_owner_record_allocation :: proc(owner: ^Tlsf_Owner, size: uint) {
    owner.current_live_bytes += size
    owner.live_allocation_count += 1
    owner.peak_live_bytes = max(owner.peak_live_bytes, owner.current_live_bytes)
    owner.peak_allocation_count = max(
        owner.peak_allocation_count, owner.live_allocation_count)
}

// Update live bytes after an in-place resize without changing allocation count.
tlsf_owner_record_resize :: proc(owner: ^Tlsf_Owner, old_size, new_size: uint) {
    if new_size >= old_size {
        owner.current_live_bytes += new_size-old_size
    } else {
        owner.current_live_bytes -= min(owner.current_live_bytes, old_size-new_size)
    }
    owner.peak_live_bytes = max(owner.peak_live_bytes, owner.current_live_bytes)
}

// Retire accounting for one allocation returned to TLSF.
tlsf_owner_record_free :: proc(owner: ^Tlsf_Owner, size: uint) {
    owner.current_live_bytes -= min(owner.current_live_bytes, size)
    owner.live_allocation_count -= min(owner.live_allocation_count, 1)
}

// Validate power-of-two alignment before passing it into TLSF.
tlsf_owner_alignment_valid :: proc(alignment: int) -> bool {
    return alignment > 0 && (alignment & (alignment-1)) == 0
}

// Reserve headroom for TLSF pool overhead before asking the library estimator.
max_pool_capacity :: proc() -> int {
    return int(tlsf.BLOCK_SIZE_MAX)
}
