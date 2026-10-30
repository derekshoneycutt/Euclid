package viewmodel

import storage "../../../core/storage"
import geometry "../../../core/geometry"
import uuid "core:encoding/uuid"
import runtime "base:runtime"
import collections "../../../collections"

// Popup state owns reusable ordering only; names and membership remain in accepted collections.
Ui_Collection_Membership_State :: struct {
    allocator: storage.Tlsf_Owner,
    order: []int,
    count: int,
    revision: u64,
    active: bool,
    animation_id: uuid.Identifier,
    generation: u64,
    serial: u64,
    focused: uuid.Identifier,
    pressed: uuid.Identifier,
    pending: uuid.Identifier,
    pending_placement: collections.Placement_Identity,
    pending_checked: bool,
    pending_valid: bool,
    anchor: geometry.Rectangle,
    viewport: geometry.Rectangle,
    window: Ui_Window_Metrics,
    bounds: geometry.Rectangle,
    clip: geometry.Rectangle,
    scroll_y: f32,
    row_height: f32,
    header_height: f32,
    text_size_percent: int,
    control_size_percent: int,
    dragging: bool,
    drag_offset: f32,
    press_owner: Ui_Press_Owner_State,
    captured_buttons: u8,
    swallowed_keys: u8,
}

// Grow atomically in the display popup lifetime, preserving usable capacity on failure.
ui_membership_reserve :: proc(
    menu: ^Ui_Collection_Membership_State, count: int) -> bool {
    if count <= len(menu.order) {
        return true
    }
    if !menu.allocator.initialized {
        heap: runtime.Allocator = {
            procedure = runtime.heap_allocator_proc,
        }
        if storage.tlsf_owner_init(&menu.allocator, heap) != .Ok {
            return false
        }
    }
    capacity, ok := ui_tree_projection_grow_capacity(len(menu.order), 16, count)
    if !ok {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&menu.allocator)
    grown := make([]int, capacity, allocator)
    if len(grown) != capacity {
        return false
    }
    copy(grown, menu.order)
    delete(menu.order, allocator)
    menu.order = grown
    return true
}

// Release reusable popup capacity at the display owner's final teardown.
ui_membership_destroy :: proc(menu: ^Ui_Collection_Membership_State) {
    if menu.allocator.initialized {
        delete(menu.order, storage.tlsf_owner_allocator(&menu.allocator))
        storage.tlsf_owner_destroy(&menu.allocator)
    }
    menu^ = {}
}
