package native_accessibility

import portable "../../../accessibility"
import "core:sync"

// Adapter_Create_Failure selects one test-only owner construction boundary.
Adapter_Create_Failure :: enum u8 {
    None,
    After_Publication,
}

// Adapter_Diagnostic_Event identifies one bounded native lifecycle observation.
Adapter_Diagnostic_Event :: enum u8 {
    Activation,
    Rejected_Callback,
    Action,
    Deactivation,
    Update,
    Destroy,
}

// Adapter_Action_Kind identifies one validated native action for the display owner.
Adapter_Action_Kind :: enum u8 {
    Focus,
    Activate,
}

// Adapter_Action_Status identifies one display-thread drain or rejection outcome.
Adapter_Action_Status :: enum u8 {
    Ok,
    Empty,
    Closing,
    Unknown_Target,
    Stale_Generation,
    Removed_Target,
    Unsupported_Action,
    Disabled_Target,
}

// Adapter_Action carries one validated native request without platform pointers.
Adapter_Action :: struct {
    kind: Adapter_Action_Kind,
    identity: portable.Qualified_Identity,
}

// Adapter_Diagnostics records content-free callback and owner lifecycle counts.
Adapter_Diagnostics :: struct {
    activations: u64,
    rejected_callbacks: u64,
    actions: u64,
    deactivations: u64,
    updates: u64,
    destroys: u64,
    rejected_actions: u64,
    last_action_status: Adapter_Action_Status,
}

// Adapter owns one platform handle and its callback-visible publication.
Adapter :: struct {
    native: rawptr,
    publication: portable.Protected_Publication,
    native_ids: portable.Native_Id_Registry,
    actions: portable.Action_Queue,
    child_identity: portable.Qualified_Identity,
    child_native_id: u64,
    child_present: bool,
    delivered_generation: u64,
    diagnostics_mutex: sync.Mutex,
    diagnostics: Adapter_Diagnostics,
}

// adapter_record_action_rejection retains one typed display-thread rejection.
adapter_record_action_rejection :: proc(
    owner: ^Adapter, status: Adapter_Action_Status) {
    if owner == nil || status == .Ok || status == .Empty {return}
    sync.mutex_lock(&owner^.diagnostics_mutex)
    owner^.diagnostics.rejected_actions += 1
    owner^.diagnostics.last_action_status = status
    sync.mutex_unlock(&owner^.diagnostics_mutex)
}

// adapter_record_diagnostic increments one bounded content-free lifecycle counter.
adapter_record_diagnostic :: proc(
    owner: ^Adapter, event: Adapter_Diagnostic_Event) {
    if owner == nil {return}
    sync.mutex_lock(&owner^.diagnostics_mutex)
    defer sync.mutex_unlock(&owner^.diagnostics_mutex)
    switch event {
    case .Activation: owner^.diagnostics.activations += 1
    case .Rejected_Callback: owner^.diagnostics.rejected_callbacks += 1
    case .Action: owner^.diagnostics.actions += 1
    case .Deactivation: owner^.diagnostics.deactivations += 1
    case .Update: owner^.diagnostics.updates += 1
    case .Destroy: owner^.diagnostics.destroys += 1
    }
}

// adapter_diagnostics_snapshot returns one synchronized lifecycle observation.
adapter_diagnostics_snapshot :: proc(owner: ^Adapter) -> Adapter_Diagnostics {
    if owner == nil {return {}}
    sync.mutex_lock(&owner^.diagnostics_mutex)
    defer sync.mutex_unlock(&owner^.diagnostics_mutex)
    return owner^.diagnostics
}