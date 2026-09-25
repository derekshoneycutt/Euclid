package bridgemodel

import protocol "../../core/protocol"
import evidence_profile "../../evidence/profile"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import presentationmodel "../presentation"
import "../../julialib"

import "core:encoding/uuid"
import "core:mem"
import "core:mem/tlsf"
import "core:sync/chan"
import "core:thread"
import "core:time"

JULIA_REQUEST_CAPACITY :: 16
JULIA_EVENT_CAPACITY :: 16
JULIA_REQUEST_LINK_POOL_CAPACITY :: 64 * 1024
JULIA_EVENT_LINK_POOL_CAPACITY :: 640 * 1024
JULIA_EVIDENCE_HANDOFF_CAPACITY :: 32
HARNESS_SCENARIO_NAME_CAPACITY :: 256
ANIMATION_TICK_SLOT_COUNT :: 2
JULIA_INTERFACE_GENERATION_SLOT_COUNT :: 2

// Julia_Request_Kind identifies legacy display-to-owner control requests.
Julia_Request_Kind :: enum {
    Initialize,
    Invoke,
    Animation_Tick,
    Shutdown,
}

// Julia_Event_Kind identifies legacy owner-to-display completion events.
Julia_Event_Kind :: enum {
    Initialized,
    Invoke_Complete,
    Animation_Tick_Complete,
    Shutdown_Complete,
}

// Animation_Tick_Slot_State tracks ownership of one bounded tick slot.
Animation_Tick_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
    Accepted,
}

// Animation_Tick_Slot owns one immutable query and transactional result batch.
Animation_Tick_Slot :: struct {
    state: Animation_Tick_Slot_State,
    request_id: u64,
    reservation_generation: u64,
    generation: u64,
    sequence: u64,
    host_state: rawptr,
    animation: ^Euclid_Julia_Animation_Interface,
    dt: f32,
    submitted_at: time.Tick,
    query_snapshot: Animation_Query_Snapshot,
    scene_batch: Scene_Command_Batch,
}

// Julia_Lifecycle_State tracks the embedded runtime service lifecycle.
Julia_Lifecycle_State :: enum {
    Not_Started,
    Starting,
    Ready,
    Shutdown_Requested,
    Failed,
    Stopped,
}

// Julia_Reload_State tracks one transactional runtime reload.
Julia_Reload_State :: enum {
    Idle,
    Quiescing,
    Including,
    Registering,
    Publishing,
    Failed,
}

// Julia_Reload_Failure_Injection selects one scenario-only reload failure site.
Julia_Reload_Failure_Injection :: enum u8 {
    None,
    Candidate_Load,
    Animation_Enter,
}

// Animation_Tick_Slot_Handle identifies one reservation generation.
Animation_Tick_Slot_Handle :: struct {
    index: i32,
    reservation_generation: u64,
}

// Animation_Lifecycle_Slot_Handle identifies one lifecycle reservation generation.
Animation_Lifecycle_Slot_Handle :: struct {
    index: i32,
    reservation_generation: u64,
}

// Animation_Lifecycle_Slot_State tracks ownership of the lifecycle slot.
Animation_Lifecycle_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
}

// Animation_Lifecycle_Outcome records transactional lifecycle completion.
Animation_Lifecycle_Outcome :: enum u8 {
    None,
    Committed,
    Rolled_Back,
}

// Animation_Lifecycle_Slot owns one checked lifecycle transaction.
Animation_Lifecycle_Slot :: struct {
    state: Animation_Lifecycle_Slot_State,
    outcome: Animation_Lifecycle_Outcome,
    request_id: u64,
    reservation_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    selected_stable_id: uuid.Identifier,
    reset_requested: bool,
    reload_requested: bool,
    host_state: rawptr,
}

Runtime_Initialize_Requested :: struct { request_id: u64 }
Runtime_Content_Initialize_Requested :: struct {
    request_id: u64,
    native_state: rawptr,
}
Animation_Tick_Requested :: struct {
    request_id: u64,
    handle: Animation_Tick_Slot_Handle,
    animation_generation: u64,
    sequence: u64,
}
Animation_Lifecycle_Requested :: struct {
    request_id: u64,
    handle: Animation_Lifecycle_Slot_Handle,
    runtime_generation: u64,
    animation_generation: u64,
}
Harness_Scenario_Requested :: struct {
    request_id: u64,
    scenario_name: string,
    step_count: i64,
}

// Scenario_View_Content_Requested carries display-owned source to the Julia owner.
Scenario_View_Content_Requested :: struct {
    origin: evidence_trace.Identity,
    request_id: u64,
    runtime_generation: u64,
    animation_generation: u64,
    animation: ^Euclid_Julia_Animation_Interface,
    mime: presentationmodel.Presentation_Mime,
    source: []u8,
}

Runtime_Shutdown_Requested :: struct { request_id: u64 }

// Julia_Completion carries bounded evidence with one owner-thread completion.
Julia_Completion :: struct {
    request_id: u64,
    succeeded: bool,
    evidence: [JULIA_EVIDENCE_HANDOFF_CAPACITY]evidence_trace.Event,
    evidence_count: int,
}

Runtime_Initialized :: struct { completion: Julia_Completion }
Runtime_Content_Initialized :: struct { completion: Julia_Completion }
Animation_Tick_Completed :: struct {
    completion: Julia_Completion,
    handle: Animation_Tick_Slot_Handle,
    animation_generation: u64,
    sequence: u64,
}
Animation_Lifecycle_Completed :: struct {
    completion: Julia_Completion,
    handle: Animation_Lifecycle_Slot_Handle,
    runtime_generation: u64,
    animation_generation: u64,
}
Harness_Scenario_Completed :: struct { completion: Julia_Completion }
Runtime_Shutdown_Completed :: struct { completion: Julia_Completion }

// Julia_Event is the scalar legacy event representation used by diagnostics and tests.
Julia_Event :: struct {
    kind: Julia_Event_Kind,
    request_kind: Julia_Request_Kind,
    request_id: u64,
    slot_index: i32,
    succeeded: bool,
    evidence: [JULIA_EVIDENCE_HANDOFF_CAPACITY]evidence_trace.Event,
    evidence_count: int,
}

// View_Content_Ready carries independently replaceable presentation source.
View_Content_Ready :: struct {
    origin: evidence_trace.Identity,
    request_id: u64,
    runtime_generation: u64,
    animation_generation: u64,
    presentation_generation: u64,
    animation: ^Euclid_Julia_Animation_Interface,
    content: presentationmodel.Presented_Text,
}

// Communication_Send_Outcome distinguishes pressure, allocation, and closure failures.
Communication_Send_Outcome :: enum u8 {
    Sent,
    Queue_Full,
    Allocation_Failed,
    Runtime_Stopping,
    Channel_Closed,
}

// Julia_Host_Ingress contains display-produced messages borrowed by the Julia owner.
Julia_Host_Ingress :: union {
    Runtime_Initialize_Requested,
    Runtime_Content_Initialize_Requested,
    Animation_Tick_Requested,
    Animation_Lifecycle_Requested,
    Harness_Scenario_Requested,
    Scenario_View_Content_Requested,
    Runtime_Shutdown_Requested,
    protocol.Terminal_Session_Started,
    protocol.Terminal_Session_Closed,
    protocol.Evaluation_Requested,
    protocol.Completion_Requested,
    protocol.Terminal_Interactive_Input,
    protocol.Terminal_Geometry_Accepted,
    protocol.Terminal_Capabilities_Accepted,
    protocol.Tick_Stream_Configuration_Acknowledged,
    protocol.Tick_Pulse,
}

// Julia_Host_Egress contains Julia-produced messages borrowed by the display owner.
Julia_Host_Egress :: union {
    Runtime_Initialized,
    Runtime_Content_Initialized,
    Animation_Tick_Completed,
    Animation_Lifecycle_Completed,
    Harness_Scenario_Completed,
    Runtime_Shutdown_Completed,
    View_Content_Ready,
    protocol.Terminal_Output_Batch,
    protocol.Evaluation_Incomplete,
    protocol.Evaluation_Completed,
    protocol.Completion_Result,
    protocol.Completion_Failed,
    protocol.Terminal_Input_Acquired,
    protocol.Terminal_Input_Released,
    protocol.Terminal_Geometry_Observed,
    protocol.Terminal_Capabilities_Observed,
    protocol.Terminal_Session_Ready,
    protocol.Terminal_Session_Stopped,
    protocol.Tick_Stream_Configure_Requested,
    protocol.Tick_Stream_Stop_Requested,
}

// Julia_Egress_Dispatch_Proc routes one non-event envelope on the display thread.
Julia_Egress_Dispatch_Proc :: #type proc(
    user_data: rawptr, message: ^Julia_Host_Egress) -> bool

// Communication_Link owns bounded channels and producer-side envelope storage.
Communication_Link :: struct($T: typeid) {
    outbound: chan.Chan(^T),
    returns: chan.Chan(^T),
    pool: tlsf.Allocator,
    backing: []byte,
    backing_allocator: mem.Allocator,
}

// Julia_Runtime_Service owns bridge queues, checked slots, and lifecycle bookkeeping.
Julia_Runtime_Service :: struct {
    evidence_ring: evidence_trace.Ring,
    evidence_session: ^evidence_session.Session,
    profile: evidence_profile.State,
    runtime_host: ^julialib.jl_value_t,
    worker: ^thread.Thread,
    request_link: Communication_Link(Julia_Host_Ingress),
    event_link: Communication_Link(Julia_Host_Egress),
    pending_view_content: ^Julia_Host_Egress,
    display_egress_dispatch: Julia_Egress_Dispatch_Proc,
    display_egress_user_data: rawptr,
    display_pending_view_content: ^Julia_Host_Egress,
    presentation_generation: u64,
    presentation_animation_generation_override: u64,
    presentation_animation_override: ^Euclid_Julia_Animation_Interface,
    next_request_id: u64,
    owner_thread_id: int,
    lifecycle: Julia_Lifecycle_State,
    active_request_id: u64,
    active_request_kind: Julia_Request_Kind,
    failed_request_count: u64,
    last_failed_request_id: u64,
    last_failed_request_kind: Julia_Request_Kind,
    request_saturation_count: u64,
    reload_state: Julia_Reload_State,
    reload_requested: bool,
    reload_failure_injection: Julia_Reload_Failure_Injection,
    runtime_generation: u64,
    reload_failed_package_identity: [32]byte,
    reload_failed_package_identity_valid: bool,
    view_snapshots: [VIEW_SNAPSHOT_SLOT_COUNT]View_Snapshot,
    view_snapshot_generation: u64,
    published_view_snapshot_index: int,
    animation_tick_slots: [ANIMATION_TICK_SLOT_COUNT]Animation_Tick_Slot,
    animation_lifecycle_slot: Animation_Lifecycle_Slot,
    animation_generation: u64,
    animation_tick_sequence: u64,
    animation_last_committed_sequence: u64,
    animation_tick_pending: bool,
    animation_accumulated_dt: f32,
    animation_ticks_submitted: u64,
    animation_ticks_committed: u64,
    animation_ticks_coalesced: u64,
    animation_ticks_stale: u64,
    animation_ticks_dropped: u64,
    animation_queue_high_water: u64,
    animation_last_latency_ms: f64,
    animation_max_latency_ms: f64,
}