package accessibility

import "core:math"
import "core:sync"
import "core:unicode/utf8"

STATIC_LABEL_CAPACITY :: 64
SYNTHETIC_ROOT_ID :: u64(1)
STATIC_CHILD_ID :: u64(2)

// Publication_Status identifies one rejected static native-tree fact.
Publication_Status :: enum u8 {
    Ok,
    Invalid_Id,
    Duplicate_Id,
    Missing_Parent,
    Cycle,
    Unreachable_Node,
    Invalid_Utf8,
    Invalid_Bounds,
    Capacity,
}

// Bounds stores one finite non-inverted rectangle in logical window coordinates.
Bounds :: struct {
    x0, y0, x1, y1: f64,
}

// Static_Publication owns every fact exposed by the Phase 1 native tree.
Static_Publication :: struct {
    generation: u64,
    root_id: u64,
    child_id: u64,
    child_parent_id: u64,
    root_bounds: Bounds,
    child_bounds: Bounds,
    label: [STATIC_LABEL_CAPACITY]u8,
    label_length: int,
    focused: bool,
}

// Protected_Publication serializes callback snapshots with display-owned updates.
Protected_Publication :: struct {
    mutex: sync.Mutex,
    current: Static_Publication,
    closing: bool,
}

// bounds_are_valid accepts only finite rectangles with nonnegative extents.
bounds_are_valid :: proc(bounds: Bounds) -> bool {
    finite := !math.is_nan(bounds.x0) && !math.is_inf(bounds.x0) &&
        !math.is_nan(bounds.y0) && !math.is_inf(bounds.y0) &&
        !math.is_nan(bounds.x1) && !math.is_inf(bounds.x1) &&
        !math.is_nan(bounds.y1) && !math.is_inf(bounds.y1)
    return finite && bounds.x0 <= bounds.x1 && bounds.y0 <= bounds.y1
}

// publication_validate proves the complete two-node rooted-tree contract.
publication_validate :: proc(value: ^Static_Publication) -> Publication_Status {
    if value == nil || value^.root_id == 0 || value^.child_id == 0 {
        return .Invalid_Id
    }
    if value^.root_id == value^.child_id {return .Duplicate_Id}
    if value^.child_parent_id == value^.child_id {return .Cycle}
    if value^.child_parent_id == 0 {return .Missing_Parent}
    if value^.child_parent_id != value^.root_id {return .Unreachable_Node}
    if value^.label_length < 0 || value^.label_length > len(value^.label) {
        return .Capacity
    }
    if !utf8.valid_string(string(value^.label[:value^.label_length])) {
        return .Invalid_Utf8
    }
    if !bounds_are_valid(value^.root_bounds) ||
       !bounds_are_valid(value^.child_bounds) {
        return .Invalid_Bounds
    }
    return .Ok
}

// publication_build creates one complete Phase 1 root and static child.
publication_build :: proc(
    destination: ^Static_Publication, width, height: f64,
    focused: bool) -> Publication_Status {
    if destination == nil {return .Invalid_Id}
    next_generation := destination^.generation + 1
    candidate := Static_Publication{
        generation = next_generation,
        root_id = SYNTHETIC_ROOT_ID,
        child_id = STATIC_CHILD_ID,
        child_parent_id = SYNTHETIC_ROOT_ID,
        root_bounds = {0, 0, width, height},
        child_bounds = {0, 0, width, height},
        focused = focused,
    }
    label := "Euclid workspace"
    copy(candidate.label[:], transmute([]u8)label)
    candidate.label_length = len(label)
    status := publication_validate(&candidate)
    if status == .Ok {destination^ = candidate}
    return status
}

// protected_publish atomically replaces the last good publication.
protected_publish :: proc(
    protected: ^Protected_Publication, width, height: f64,
    focused: bool) -> Publication_Status {
    if protected == nil {return .Invalid_Id}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return .Invalid_Id}
    current := &protected^.current
    if publication_validate(current) == .Ok &&
       current^.root_bounds.x1 == width && current^.root_bounds.y1 == height &&
       current^.focused == focused {
        return .Ok
    }
    return publication_build(&protected^.current, width, height, focused)
}

// protected_snapshot copies one immutable callback view while admission remains open.
protected_snapshot :: proc(
    protected: ^Protected_Publication,
    destination: ^Static_Publication) -> bool {
    if protected == nil || destination == nil {return false}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return false}
    destination^ = protected^.current
    return publication_validate(destination) == .Ok
}

// protected_close prevents callbacks from observing publication storage as current.
protected_close :: proc(protected: ^Protected_Publication) {
    if protected == nil {return}
    sync.mutex_lock(&protected^.mutex)
    protected^.closing = true
    sync.mutex_unlock(&protected^.mutex)
}