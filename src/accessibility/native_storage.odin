package accessibility

import "core:sync"

NATIVE_ID_CAPACITY :: 4096
ACTION_QUEUE_CAPACITY :: 64
ACTION_PAYLOAD_CAPACITY :: 512
SYNTHETIC_NATIVE_ID :: u64(1)

// Identity_Domain distinguishes semantic identity owners in native lookup keys.
Identity_Domain :: enum u8 {
    Synthetic,
    Ui,
    Dynview,
    Presentation,
    Terminal,
}

// Qualified_Identity preserves every fact required to reject stale native targets.
Qualified_Identity :: struct {
    domain: Identity_Domain,
    owner_domain: u16,
    local_id: u64,
    stable_uuid: [16]u8,
    generation: u64,
}

// Native_Id_Entry retains one live or retired session-local mapping.
Native_Id_Entry :: struct {
    identity: Qualified_Identity,
    native_id: u64,
    active: bool,
}

// Native_Id_Diagnostics records bounded allocation and retirement pressure.
Native_Id_Diagnostics :: struct {
    allocated: u64,
    retired: u64,
    peak_active: int,
    exhaustion: u64,
}

// Native_Id_Registry owns monotonic mappings for one native window session.
Native_Id_Registry :: struct {
    entries: [NATIVE_ID_CAPACITY]Native_Id_Entry,
    count: int,
    active_count: int,
    next_id: u64,
    diagnostics: Native_Id_Diagnostics,
}

// Queued_Action stores one callback-copied request without native pointers.
Queued_Action :: struct {
    kind: u16,
    target_native_id: u64,
    publication_generation: u64,
    numeric_value: f64,
    has_numeric_value: bool,
    replace_entire_text: bool,
    payload: [ACTION_PAYLOAD_CAPACITY]u8,
    payload_length: int,
    selection_anchor: u16,
    selection_focus: u16,
}

// Action_Queue_Status identifies one bounded action-ingress outcome.
Action_Queue_Status :: enum u8 {
    Ok,
    Closing,
    Full,
    Invalid_Target,
    Payload_Overflow,
}

// Action_Queue_Diagnostics records accepted and rejected ingress pressure.
Action_Queue_Diagnostics :: struct {
    accepted: u64,
    drained: u64,
    closing_rejections: u64,
    overflows: u64,
    invalid_requests: u64,
    peak_count: int,
}

// Action_Queue owns synchronized fixed-capacity callback ingress storage.
Action_Queue :: struct {
    mutex: sync.Mutex,
    entries: [ACTION_QUEUE_CAPACITY]Queued_Action,
    read_index: int,
    write_index: int,
    count: int,
    closing: bool,
    diagnostics: Action_Queue_Diagnostics,
}

// native_id_registry_init reserves the synthetic root ID for one window session.
native_id_registry_init :: proc(registry: ^Native_Id_Registry) {
    if registry == nil {
        return
    }
    registry^ = {}
    registry^.entries[0] = {
        identity = {domain = .Synthetic, local_id = SYNTHETIC_ROOT_ID},
        native_id = SYNTHETIC_NATIVE_ID,
        active = true,
    }
    registry^.count = 1
    registry^.active_count = 1
    registry^.next_id = SYNTHETIC_NATIVE_ID + 1
    registry^.diagnostics.allocated = 1
    registry^.diagnostics.peak_active = 1
}

// native_id_resolve returns an existing mapping or allocates one monotonically.
native_id_resolve :: proc(
    registry: ^Native_Id_Registry, identity: Qualified_Identity) -> (u64, bool) {
    if registry == nil ||
       (identity.local_id == 0 && identity.stable_uuid == ([16]u8{}) &&
        (identity.domain != .Ui || identity.owner_domain == 0)) {
        return 0, false
    }
    for index in 0..<registry^.count {
        entry := &registry^.entries[index]
        if entry^.identity == identity && entry^.active {
            return entry^.native_id, true
        }
    }
    if registry^.count >= len(registry^.entries) || registry^.next_id == 0 {
        registry^.diagnostics.exhaustion += 1
        return 0, false
    }
    native_id := registry^.next_id
    registry^.next_id += 1
    registry^.entries[registry^.count] = {identity, native_id, true}
    registry^.count += 1
    registry^.active_count += 1
    registry^.diagnostics.allocated += 1
    registry^.diagnostics.peak_active = max(
        registry^.diagnostics.peak_active, registry^.active_count)
    return native_id, true
}

// native_id_lookup resolves one active native ID back to its qualified identity.
native_id_lookup :: proc(
    registry: ^Native_Id_Registry, native_id: u64) -> (Qualified_Identity, bool) {
    if registry == nil || native_id == 0 {
        return {}, false
    }
    for index in 0..<registry^.count {
        entry := registry^.entries[index]
        if entry.native_id == native_id && entry.active {
            return entry.identity, true
        }
    }
    return {}, false
}

// native_id_retire invalidates one mapping without making its ID reusable.
native_id_retire :: proc(registry: ^Native_Id_Registry, native_id: u64) -> bool {
    if registry == nil || native_id == SYNTHETIC_NATIVE_ID {
        return false
    }
    for index in 0..<registry^.count {
        entry := &registry^.entries[index]
        if entry^.native_id != native_id || !entry^.active {
            continue
        }
        entry^.active = false
        registry^.active_count -= 1
        registry^.diagnostics.retired += 1
        return true
    }
    return false
}

// action_queue_push copies one validated pointer-free request into bounded storage.
action_queue_push :: proc(
    queue: ^Action_Queue, request: ^Queued_Action) -> Action_Queue_Status {
    if queue == nil || request == nil || request^.target_native_id == 0 {
        return .Invalid_Target
    }
    sync.mutex_lock(&queue^.mutex)
    defer sync.mutex_unlock(&queue^.mutex)
    if queue^.closing {
        queue^.diagnostics.closing_rejections += 1
        return .Closing
    }
    if request^.payload_length < 0 ||
       request^.payload_length > len(request^.payload) {
        queue^.diagnostics.invalid_requests += 1
        return .Payload_Overflow
    }
    if queue^.count == len(queue^.entries) {
        queue^.diagnostics.overflows += 1
        return .Full
    }
    queue^.entries[queue^.write_index] = request^
    queue^.write_index = (queue^.write_index + 1) % len(queue^.entries)
    queue^.count += 1
    queue^.diagnostics.accepted += 1
    queue^.diagnostics.peak_count = max(
        queue^.diagnostics.peak_count, queue^.count)
    return .Ok
}

// action_queue_pop removes one copied request at the display-thread boundary.
action_queue_pop :: proc(queue: ^Action_Queue, destination: ^Queued_Action) -> bool {
    if queue == nil || destination == nil {
        return false
    }
    sync.mutex_lock(&queue^.mutex)
    defer sync.mutex_unlock(&queue^.mutex)
    if queue^.count == 0 {
        return false
    }
    destination^ = queue^.entries[queue^.read_index]
    queue^.entries[queue^.read_index] = {}
    queue^.read_index = (queue^.read_index + 1) % len(queue^.entries)
    queue^.count -= 1
    queue^.diagnostics.drained += 1
    return true
}

// action_queue_close rejects new callbacks while preserving accepted drainable work.
action_queue_close :: proc(queue: ^Action_Queue) {
    if queue == nil {
        return
    }
    sync.mutex_lock(&queue^.mutex)
    queue^.closing = true
    sync.mutex_unlock(&queue^.mutex)
}

// action_queue_diagnostics_snapshot returns synchronized queue pressure counters.
action_queue_diagnostics_snapshot :: proc(
    queue: ^Action_Queue) -> Action_Queue_Diagnostics {
    if queue == nil {
        return {}
    }
    sync.mutex_lock(&queue^.mutex)
    defer sync.mutex_unlock(&queue^.mutex)
    return queue^.diagnostics
}
