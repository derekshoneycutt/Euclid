package native_accessibility

import portable "../../../accessibility"
import "core:sync"

ADAPTER_NATIVE_CLASS_CAPACITY :: 16

// Adapter_Create_Failure selects one test-only owner construction boundary.
Adapter_Create_Failure :: enum u8 {
    None,
    After_Publication,
}

// Macos_Failure_Stage identifies one future Cocoa adapter failure boundary.
Macos_Failure_Stage :: enum u8 {
    None,
    Cocoa_Property_Lookup,
    Window_Class_Discovery,
    Focus_Forwarder_Installation,
    Adapter_Creation,
    Update,
    Focus_Update,
    Queued_Event_Raise,
    Teardown,
}

Macos_Failure_Diagnostics :: struct {
    last_stage: Macos_Failure_Stage,
    count: u64,
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
    Toggle,
    Increment,
    Decrement,
    Set_Value,
    Replace_Selected_Text,
    Replace_Text,
    Set_Text_Selection,
    Select,
    Expand,
    Collapse,
    Scroll,
    Set_Scroll_Value,
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
    Invalid_Value,
}

// Adapter_Action carries one validated native request without platform pointers.
Adapter_Action :: struct {
    kind: Adapter_Action_Kind,
    identity: portable.Qualified_Identity,
    numeric_value: f64,
    payload: [portable.ACTION_PAYLOAD_CAPACITY]u8,
    payload_length: int,
    selection_anchor: u16,
    selection_focus: u16,
}

// Adapter_Control_Input pairs one complete portable record with semantic identity.
Adapter_Control_Input :: struct {
    identity: portable.Qualified_Identity,
    parent_identity: portable.Qualified_Identity,
    active_descendant_identity: portable.Qualified_Identity,
    controls_identity: portable.Qualified_Identity,
    control: portable.Control_Publication_Input,
}

// Adapter_Tree_Input borrows one complete display-owned ordinary-control projection.
Adapter_Tree_Input :: struct {
    root_bounds: portable.Bounds,
    bounds_scale: f64,
    window_focused: bool,
    controls: []Adapter_Control_Input,
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
    macos_failures: Macos_Failure_Diagnostics,
}

// Adapter_Process_State retains irreversible native class setup across a session.
Adapter_Process_State :: struct {
    mutex: sync.Mutex,
    native_classes: [ADAPTER_NATIVE_CLASS_CAPACITY]rawptr,
    native_class_count: int,
}

// Adapter owns one platform handle and its callback-visible publication.
Adapter :: struct {
    native: rawptr,
    publication: portable.Protected_Publication,
    control_publication: portable.Protected_Control_Publication,
    native_ids: portable.Native_Id_Registry,
    actions: portable.Action_Queue,
    child_identity: portable.Qualified_Identity,
    child_native_id: u64,
    child_present: bool,
    control_native_ids: [portable.CONTROL_NODE_CAPACITY]u64,
    control_count: int,
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

// adapter_record_macos_failure retains one content-free Cocoa failure stage.
adapter_record_macos_failure :: proc(
    owner: ^Adapter, stage: Macos_Failure_Stage) {
    if owner == nil || stage == .None {return}
    sync.mutex_lock(&owner^.diagnostics_mutex)
    owner^.diagnostics.macos_failures.last_stage = stage
    owner^.diagnostics.macos_failures.count += 1
    sync.mutex_unlock(&owner^.diagnostics_mutex)
}

// adapter_macos_failures_snapshot returns one synchronized failure observation.
adapter_macos_failures_snapshot :: proc(owner: ^Adapter) -> Macos_Failure_Diagnostics {
    if owner == nil {return {}}
    sync.mutex_lock(&owner^.diagnostics_mutex)
    defer sync.mutex_unlock(&owner^.diagnostics_mutex)
    return owner^.diagnostics.macos_failures
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