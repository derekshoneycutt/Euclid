package treeviewmodel

import geometry "../../../../../core/geometry"
import uuid "core:encoding/uuid"

NODE_CAPACITY :: 512
NO_NODE :: -1

// Item_Key is opaque to the widget and stable across frame-local topology indices.
Item_Key :: uuid.Identifier

// Reveal_Reason distinguishes navigation from caller-requested topology replacement.
Reveal_Reason :: enum {
    Programmatic,
    Navigation,
}

// Branch_Motion retains sampled descendant geometry without borrowed node storage.
Branch_Motion :: struct {
    key: Item_Key,
    expanded: bool,
    running: bool,
    start_seconds: f64,
    start_height: f32,
    height: f32,
    full_height: f32,
}

// Motion owns bounded branch transitions and one stable-key scroll anchor.
Motion :: struct {
    initialized: bool,
    generation: u64,
    topology_revision: u64,
    panel: geometry.Rectangle,
    count: int,
    visual_height: f32,
    branches: [NODE_CAPACITY]Branch_Motion,
    anchor_key: Item_Key,
    anchor_view_y: f32,
    anchored: bool,
}

// State is per-instance interaction storage; it never retains node or label borrows.
State :: struct {
    active_key: Item_Key,
    scroll_y: f32,
    dragging_thumb: bool,
    drag_offset_y: f32,
    reveal_pending: bool,
    reveal_key: Item_Key,
    reveal_reason: Reveal_Reason,
    motion: Motion,
}
