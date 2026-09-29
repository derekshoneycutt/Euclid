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

// Adapter_Diagnostics records content-free callback and owner lifecycle counts.
Adapter_Diagnostics :: struct {
    activations: u64,
    rejected_callbacks: u64,
    actions: u64,
    deactivations: u64,
    updates: u64,
    destroys: u64,
}

// Adapter owns one platform handle and its callback-visible publication.
Adapter :: struct {
    native: rawptr,
    publication: portable.Protected_Publication,
    native_ids: portable.Native_Id_Registry,
    actions: portable.Action_Queue,
    delivered_generation: u64,
    diagnostics_mutex: sync.Mutex,
    diagnostics: Adapter_Diagnostics,
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