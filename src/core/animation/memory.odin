package animation

import storage "../storage"

import "base:runtime"
import "core:mem"

ANIMATION_MEMORY_ARENA_RESERVATION :: uint(mem.Megabyte)

// Report shared animation-memory lifecycle outcomes.
Animation_Memory_Status :: enum {
    Ok,
    Invalid_Argument,
    Illegal_State,
    Allocation_Failed,
}

// Own generation-scoped storage shared by native animation subsystems.
Animation_Memory :: struct {
    arena_owner: storage.Arena_Owner,
    generation: u64,
    initialized: bool,
}

//   Initialize shared animation storage without publishing partial state.
animation_memory_init :: proc(memory: ^Animation_Memory) -> bool {
    if memory == nil || memory.initialized {
        return false
    }
    memory^ = {}
    if !storage.arena_owner_init(
        &memory.arena_owner, ANIMATION_MEMORY_ARENA_RESERVATION) {
        return false
    }
    memory.initialized = true
    return true
}

//   Publish the allocator borrowed by generation-scoped animation stores.
animation_memory_allocator :: proc(
    memory: ^Animation_Memory) -> runtime.Allocator {
    if memory == nil || !memory.initialized {
        return {}
    }
    return storage.arena_owner_allocator(&memory.arena_owner)
}

//   Retire shared allocations and publish one nonzero animation generation.
animation_memory_begin_generation :: proc(
    memory: ^Animation_Memory,
    generation: u64) -> Animation_Memory_Status {
    if memory == nil || !memory.initialized {
        return .Illegal_State
    }
    if generation == 0 {
        return .Invalid_Argument
    }
    storage.arena_owner_reset(&memory.arena_owner)
    memory.generation = generation
    return .Ok
}

//   Release shared animation storage after all borrowers are quiescent.
animation_memory_destroy :: proc(memory: ^Animation_Memory) {
    if memory == nil || !memory.initialized {
        return
    }
    storage.arena_owner_destroy(&memory.arena_owner)
    memory.generation = 0
    memory.initialized = false
}

//   Snapshot the production animation arena without exposing mutable storage.
animation_memory_diagnostics :: proc(
    memory: ^Animation_Memory) -> storage.Arena_Owner_Diagnostics {
    if memory == nil {
        return {}
    }
    return storage.arena_owner_diagnostics(&memory.arena_owner)
}