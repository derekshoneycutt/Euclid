package bridge_animation

import bridgemodel "../model"
import vmem "core:mem/virtual"

// Ensure one interface generation owns a ready registry arena allocator.
ensure_julia_interface_instance_registry_arena :: proc(
    iface: ^bridgemodel.Euclid_Julia_Interface) -> bool {
    if iface == nil {
        return false
    }
    if iface^.animation_registry_arena_initialized {
        return true
    }

    err := vmem.arena_init_growing(&iface^.animation_registry_arena)
    if err != nil {
        iface^.animation_registry_allocator = {}
        iface^.animation_registry_arena_initialized = false
        return false
    }

    iface^.animation_registry_allocator =
        vmem.arena_allocator(&iface^.animation_registry_arena)
    iface^.animation_registry_arena_initialized = true
    return true
}

// Clear one interface registry while retaining its arena for reuse.
clean_julia_interface_instance :: proc(iface: ^bridgemodel.Euclid_Julia_Interface) {
    if iface == nil {
        return
    }

    if iface^.animation_registry_arena_initialized {
        vmem.arena_free_all(&iface^.animation_registry_arena)
    }

    iface^.animation_head = nil
    iface^.animation_tail = nil
    iface^.animation_count = 0
    iface^.animation_lookup_entries = nil
    iface^.animation_lookup_capacity = 0
    iface^.animation_lookup_count = 0
    iface^.content_generation = 0
    iface^.selected_animation = nil
    iface^.current_animation = &iface^.null_animation
}
