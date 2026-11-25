package julia_host

import bridge_animation "../animation"

import transport "../transport"
import presentation_source "../../view/presentation/source"
import bridgemodel "../model"
import dynviewmodel "../../dynview/model"
import "base:runtime"
import "../../core"
import protocol "../../core/protocol"
import dyncore "../../dynview/core"
import julialib "../../../libs/julia/bindings"
import "../../files"
import evidence_profile "../../evidence/profile"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"

// Julia_Runtime_Service is a single-owner command processor around the embedded Julia
// runtime. The display thread submits bounded requests and consumes typed events; only
// the persistent worker may call Julia. Snapshot and tick slots retain payloads outside
// the inboxes so event draining never determines whether completed data survives.

JULIA_INBOX_MESSAGE_CAPACITY :: bridgemodel.JULIA_INBOX_MESSAGE_CAPACITY
DISPLAY_INBOX_MESSAGE_CAPACITY :: bridgemodel.DISPLAY_INBOX_MESSAGE_CAPACITY
JULIA_INBOX_INITIAL_BYTES :: bridgemodel.JULIA_INBOX_INITIAL_BYTES
DISPLAY_INBOX_INITIAL_BYTES :: bridgemodel.DISPLAY_INBOX_INITIAL_BYTES
JULIA_EVIDENCE_HANDOFF_CAPACITY :: bridgemodel.JULIA_EVIDENCE_HANDOFF_CAPACITY
VIEW_SNAPSHOT_SLOT_COUNT :: bridgemodel.VIEW_SNAPSHOT_SLOT_COUNT
VIEW_SNAPSHOT_TEXT_CAPACITY :: bridgemodel.VIEW_SNAPSHOT_TEXT_CAPACITY
ANIMATION_TICK_SLOT_COUNT :: bridgemodel.ANIMATION_TICK_SLOT_COUNT
MAX_ACCUMULATED_ANIMATION_DT :: f32(0.25)
Julia_Mailboxes_Init_Proc :: #type proc(
    service: ^Julia_Runtime_Service) -> runtime.Allocator_Error
Julia_Runtime_Worker_Start_Proc :: #type proc(data: rawptr) -> ^thread.Thread

// Stack-local Julia host handle retained by the worker's persistent GC frame.
Julia_Runtime_Host :: struct {
    runtime: ^julialib.jl_value_t,
    native_state: ^core.Euclid_General_State,
    terminal_startup_banner: ^julialib.jl_value_t,
    terminal_start_session: ^julialib.jl_value_t,
    terminal_close_session: ^julialib.jl_value_t,
    terminal_ingest_evaluation: ^julialib.jl_value_t,
    active_operation_outcome_ingest: ^julialib.jl_value_t,
    active_operation_outcome_type: ^julialib.jl_value_t,
    active_operation_progress_ingest: ^julialib.jl_value_t,
    active_operation_progress_type: ^julialib.jl_value_t,
    terminal_ingest_interactive_input: ^julialib.jl_value_t,
    terminal_ingest_geometry: ^julialib.jl_value_t,
    terminal_ingest_capabilities: ^julialib.jl_value_t,
    terminal_ingest_completion_preview: ^julialib.jl_value_t,
    terminal_ingest_completion_candidates: ^julialib.jl_value_t,
    terminal_pump: ^julialib.jl_value_t,
    idle_wait: time.Duration,
    terminal_shutdown: ^julialib.jl_value_t,
    terminal_take_evaluation: ^julialib.jl_value_t,
    terminal_take_completion: ^julialib.jl_value_t,
    terminal_ingest_highlight: ^julialib.jl_value_t,
    terminal_take_highlight: ^julialib.jl_value_t,
    terminal_highlight_identity_type: ^julialib.jl_value_t,
    terminal_take_session_lifecycle: ^julialib.jl_value_t,
    terminal_ingest_tick_configuration: ^julialib.jl_value_t,
    terminal_ingest_tick_pulse: ^julialib.jl_value_t,
    terminal_take_tick_stream: ^julialib.jl_value_t,
    animation_tick: ^julialib.jl_value_t,
    animation_tick_payload_type: ^julialib.jl_value_t,
    animation_lifecycle: ^julialib.jl_value_t,
    animation_lifecycle_acknowledge_reset: ^julialib.jl_value_t,
    animation_lifecycle_payload_type: ^julialib.jl_value_t,
    terminal_request_id: protocol.Request_Id,
    terminal_generation: u64,
}

// One-root Julia GC frame installed for the complete initialized worker lifetime.
Julia_Runtime_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    root: rawptr,
}

// Seven-root Julia GC frame used while constructing one Terminal ingress call.
Julia_Terminal_Request_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    roots: [7]^julialib.jl_value_t,
}

// One-root Julia GC frame retaining a primitive host command during field boxing.
Julia_Terminal_Command_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    command: ^julialib.jl_value_t,
}

// Three-root Julia GC frame used for one actor-owned animation tick.
Julia_Animation_Tick_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    roots: [3]^julialib.jl_value_t,
}

// Three-root Julia GC frame used for one actor-owned animation lifecycle call.
Julia_Animation_Lifecycle_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    roots: [3]^julialib.jl_value_t,
}

// Mirror Julia's primitive-only NativeAnimationTickPayload isbits layout.
Native_Animation_Tick_Payload :: struct {
    request_id: u64,
    runtime_generation: u64,
    animation_generation: u64,
    sequence: u64,
    slot_index: i32,
    reservation_generation: u64,
    dt: f32,
    operation: i32,
}

#assert(size_of(Native_Animation_Tick_Payload) == 56)

// Mirror Julia's primitive-only NativeAnimationLifecyclePayload isbits layout.
Native_Animation_Lifecycle_Payload :: struct {
    request_id: u64,
    runtime_generation: u64,
    animation_generation: u64,
    operation: i32,
}

#assert(size_of(Native_Animation_Lifecycle_Payload) == 32)

// Result of processing one serialized Julia worker request.
Julia_Worker_Request_Result :: struct {
    event: Julia_Event,
    shutting_down: bool,
    accepted: bool,
}

Julia_Control_Protocol :: enum u8 {
    Runtime_Initialize,
    Runtime_Content_Initialize,
    Animation_Tick,
    Animation_Lifecycle,
    Harness_Scenario,
    Runtime_Shutdown,
}

Julia_Decoded_Control :: struct {
    protocol: Julia_Control_Protocol,
    request_kind: Julia_Request_Kind,
    request_id: u64,
    slot_index: i32,
    tick_handle: bridgemodel.Animation_Tick_Slot_Handle,
    lifecycle_handle: bridgemodel.Animation_Lifecycle_Slot_Handle,
    runtime_generation: u64,
    animation_generation: u64,
    sequence: u64,
}

Julia_Worker_Run_Result :: struct {
    shutdown_request: Julia_Decoded_Control,
    shutdown_event: Julia_Event,
    shutting_down: bool,
}

Julia_Animation_Tick_Submission :: struct {
    handle: bridgemodel.Animation_Tick_Slot_Handle,
    animation_generation: u64,
    sequence: u64,
}

Julia_Worker_State :: struct {
    host: Julia_Runtime_Host,
    frame: Julia_Runtime_Gc_Frame,
    initialized: bool,
}

// Result of attempting to route one checked animation completion envelope.
Animation_Egress_Route_Result :: struct {
    event: Julia_Event,
    accepted: bool,
    handled: bool,
}

// Completion retained by value while the accepted egress batch is exhausted.
Julia_Egress_Batch_Result :: struct {
    count: int,
    event: Julia_Event,
    matched: bool,
}

Julia_Event_Handler :: #type proc(service: ^Julia_Runtime_Service, event: Julia_Event)

//   Dispatch table mapping each Julia event kind to its completion handler.
//   Initialized and Invoke_Complete need no handler and map to nil.
JULIA_EVENT_HANDLERS :: [Julia_Event_Kind]Julia_Event_Handler{
    .Initialized = nil,
    .Invoke_Complete = nil,
    .Animation_Tick_Complete = julia_event_on_animation_tick,
    .Shutdown_Complete = julia_event_on_shutdown,
}

// Core owns service storage because Euclid_General_State holds a concrete service pointer.
// This package owns queue policy, worker behavior, publication, and lifecycle transitions.
Julia_Request_Kind :: bridgemodel.Julia_Request_Kind
Julia_Event_Kind :: bridgemodel.Julia_Event_Kind
Animation_Tick_Slot_State :: bridgemodel.Animation_Tick_Slot_State
Animation_Tick_Slot :: bridgemodel.Animation_Tick_Slot

View_Snapshot_Slot_State :: bridgemodel.View_Snapshot_Slot_State
View_Snapshot :: bridgemodel.View_Snapshot

View_Snapshot_Record_Payloads :: struct {
    commands: []dynviewmodel.Dynview_Command,
    math_programs: []dynviewmodel.Dynview_Math_Program,
    math_commands: []dynviewmodel.Dynview_Command,
    math_nodes: []dynviewmodel.Dynview_Math_Node,
    math_table_descriptors: []dynviewmodel.Dynview_Math_Table_Descriptor,
    document_text: []u8,
    documents: []dynviewmodel.Dynview_Document,
    document_blocks: []dynviewmodel.Dynview_Document_Block,
    document_inlines: []dynviewmodel.Dynview_Document_Inline,
    document_display_rows: []dynviewmodel.Dynview_Document_Display_Row,
}

View_Snapshot_Sealed_Records :: struct {
    commands: []dynviewmodel.Dynview_Command,
    programs: []dynviewmodel.Dynview_Math_Program,
    descriptors: []dynviewmodel.Dynview_Math_Table_Descriptor,
    math_commands: []dynviewmodel.Dynview_Command,
    nodes: []dynviewmodel.Dynview_Math_Node,
    document_text: []u8,
    documents: []dynviewmodel.Dynview_Document,
    document_blocks: []dynviewmodel.Dynview_Document_Block,
    document_inlines: []dynviewmodel.Dynview_Document_Inline,
    document_display_rows: []dynviewmodel.Dynview_Document_Display_Row,
}

// Presentation_Snapshot_Request groups one current canonical materialization request.
Presentation_Snapshot_Request :: struct {
    content: bridgemodel.View_Content_Ready,
    source: string,
    mode: presentation_source.Presentation_Source_Mode,
    document: ^dyncore.Dynview_Document,
    bodies: []Presentation_Snapshot_Body,
}

// One independently interpreted body in a native reading composition.
Presentation_Snapshot_Body :: struct {
    source: string,
    document: ^dyncore.Dynview_Document,
}

Julia_Lifecycle_State :: bridgemodel.Julia_Lifecycle_State
Julia_Reload_State :: bridgemodel.Julia_Reload_State
Julia_Event :: bridgemodel.Julia_Event
Julia_Runtime_Service :: bridgemodel.Julia_Runtime_Service

// Display-safe service diagnostics contain copied scalar state only. They never expose
// worker-owned Julia handles or require a Julia call to inspect service health.
Julia_Runtime_Diagnostics :: struct {
    lifecycle: Julia_Lifecycle_State,
    active_request_id: u64,
    active_request_kind: Julia_Request_Kind,
    failed_request_count: u64,
    last_failed_request_id: u64,
    last_failed_request_kind: Julia_Request_Kind,
    request_saturation_count: u64,
    reload_state: Julia_Reload_State,
    runtime_generation: u64,
}

// Decoded scalar fields from one Julia-owned Terminal lifecycle command.
Julia_Terminal_Lifecycle_Command :: struct {
    kind: i32,
    generation: u64,
    valid: bool,
}

//   Borrow the asset-root selection retained for the Julia service lifetime.
julia_service_asset_config :: proc(
    service: ^Julia_Runtime_Service) -> files.Asset_Root_Config {
    if service == nil {
        return {}
    }
    return {
        asset_root_override = service^.asset_root_override,
    }
}

//   Return display-owned lifecycle, failure, and backpressure diagnostics.
// This is a scalar snapshot and does not synchronize with or invoke the Julia owner thread.
julia_runtime_diagnostics :: proc(
    service: ^Julia_Runtime_Service) -> Julia_Runtime_Diagnostics {
    if service == nil {
        return {}
    }
    return Julia_Runtime_Diagnostics{
        lifecycle = service^.lifecycle,
        active_request_id = service^.active_request_id,
        active_request_kind = service^.active_request_kind,
        failed_request_count = service^.failed_request_count,
        last_failed_request_id = service^.last_failed_request_id,
        last_failed_request_kind = service^.last_failed_request_kind,
        request_saturation_count = service^.request_saturation_count,
        reload_state = service^.reload_state,
        runtime_generation = service^.runtime_generation,
    }
}

// Initialize both consumer-owned inboxes before publishing either thread endpoint.
init_julia_runtime_mailboxes :: proc(
    service: ^Julia_Runtime_Service) -> runtime.Allocator_Error {
    return init_julia_runtime_mailboxes_with(
        service, julia_runtime_mailboxes_initialize)
}

// Initialize the inbox set through an injectable startup primitive with complete unwind.
init_julia_runtime_mailboxes_with :: proc(
    service: ^Julia_Runtime_Service,
    mailboxes_init: Julia_Mailboxes_Init_Proc) -> runtime.Allocator_Error {
    if service == nil || service.julia_inbox.initialized ||
        service.display_inbox.initialized || mailboxes_init == nil {
        return .Invalid_Argument
    }
    mailboxes_error := mailboxes_init(service)
    if mailboxes_error != .None {
        destroy_julia_runtime_mailboxes(service)
        return mailboxes_error
    }
    return .None
}

// Establish one growing arena per direction with logical message-byte admission bounds.
julia_runtime_mailboxes_initialize :: proc(
    service: ^Julia_Runtime_Service) -> runtime.Allocator_Error {
    request_error := transport.consumer_mailbox_init(
        &service.julia_inbox, JULIA_INBOX_INITIAL_BYTES,
        bridgemodel.JULIA_INBOX_BYTE_LIMIT, JULIA_INBOX_MESSAGE_CAPACITY)
    if request_error != .None {
        return request_error
    }
    event_err := transport.consumer_mailbox_init(
        &service.display_inbox, DISPLAY_INBOX_INITIAL_BYTES,
        bridgemodel.DISPLAY_INBOX_BYTE_LIMIT, DISPLAY_INBOX_MESSAGE_CAPACITY)
    if event_err != .None {
        transport.consumer_mailbox_destroy(&service.julia_inbox)
        return event_err
    }
    return .None
}

//   Start the persistent Julia owner worker with its service payload.
julia_runtime_worker_start :: proc(data: rawptr) -> ^thread.Thread {
    return thread.create_and_start_with_data(data, julia_runtime_worker)
}

// Destroy consumer storage after both owners and all native payload borrowers stop.
destroy_julia_runtime_mailboxes :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    transport.consumer_mailbox_destroy(&service.display_inbox)
    transport.consumer_mailbox_destroy(&service.julia_inbox)
}

//   Initialize display-independent state before starting the Julia owner worker.
initialize_julia_runtime_state :: proc(
    service: ^Julia_Runtime_Service,
    profile_path: string,
    asset_config: ^files.Asset_Root_Config) -> bool {
    service^.next_request_id = 1
    service^.lifecycle = .Not_Started
    service^.published_view_snapshot_index = -1
    if asset_config != nil && len(asset_config^.asset_root_override) > 0 {
        service^.asset_root_override = strings.clone(
            asset_config^.asset_root_override,
            service^.bootstrap_allocator)
        if len(service^.asset_root_override) == 0 {
            return false
        }
    }
    if len(profile_path) > 0 &&
        !evidence_profile.init_spall(&service^.profile, profile_path) {
        fmt.eprintln("Failed to initialize Julia worker profile output.")
        log.warn("julia_worker_profile_init_failed")
    }
    return true
}

//   Create bounded consumer inboxes, staging storage, and the persistent Julia owner worker.
// On partial failure, resources are released in reverse construction order. The caller owns
// the returned service and must stop Julia before destroy_julia_runtime_service.
create_julia_runtime_service :: proc(
    allocator: mem.Allocator,
    profile_path: string = "",
    asset_config: ^files.Asset_Root_Config = nil) -> (
    ^Julia_Runtime_Service, runtime.Allocator_Error) {
    return create_julia_runtime_service_with_worker(
        allocator, profile_path, asset_config, julia_runtime_worker_start)
}

//   Create and unwind the service using an injectable worker-start operation.
create_julia_runtime_service_with_worker :: proc(
    allocator: mem.Allocator,
    profile_path: string,
    asset_config: ^files.Asset_Root_Config,
    worker_start: Julia_Runtime_Worker_Start_Proc) -> (
    ^Julia_Runtime_Service, runtime.Allocator_Error) {
    if worker_start == nil {
        return nil, .Invalid_Argument
    }
    service := new(Julia_Runtime_Service, allocator)
    if service == nil {
        return nil, .Out_Of_Memory
    }
    service^.bootstrap_allocator = allocator
    evidence_trace.ring_init(&service^.evidence_ring, .Julia_Host)
    storage_error := initialize_julia_runtime_service_storage(
        service, profile_path, asset_config)
    if storage_error != .None {
        free(service, allocator)
        return nil, storage_error
    }
    service^.worker = worker_start(rawptr(service))
    if service^.worker == nil {
        destroy_unstarted_julia_runtime_service(service)
        return nil, .Out_Of_Memory
    }

    log.infof("julia_service_created request_capacity=%d event_capacity=%d",
        JULIA_INBOX_MESSAGE_CAPACITY, DISPLAY_INBOX_MESSAGE_CAPACITY)
    return service, .None
}

//   Initialize all non-worker storage, unwinding each completed stage on failure.
initialize_julia_runtime_service_storage :: proc(
    service: ^Julia_Runtime_Service,
    profile_path: string,
    asset_config: ^files.Asset_Root_Config) -> runtime.Allocator_Error {
    mailbox_error := init_julia_runtime_mailboxes(service)
    if mailbox_error != .None {
        return mailbox_error
    }
    if !view_snapshot_slots_init(service) {
        destroy_julia_runtime_mailboxes(service)
        return .Out_Of_Memory
    }
    if !initialize_julia_runtime_state(service, profile_path, asset_config) {
        view_snapshot_slots_destroy(service)
        destroy_julia_runtime_mailboxes(service)
        delete(service^.asset_root_override, service^.bootstrap_allocator)
        return .Out_Of_Memory
    }
    return .None
}

//   Release initialized service storage before a worker has started.
destroy_unstarted_julia_runtime_service :: proc(service: ^Julia_Runtime_Service) {
    evidence_profile.destroy(&service^.profile)
    view_snapshot_slots_destroy(service)
    destroy_julia_runtime_mailboxes(service)
    delete(service^.asset_root_override, service^.bootstrap_allocator)
    free(service, service^.bootstrap_allocator)
}

//   Report whether one cumulative occurrence count is a power of two.
// This bounds repeated diagnostics while retaining increasing pressure visibility.
diagnostic_occurrence_should_log :: proc(count: u64) -> bool {
    return count > 0 && count & (count - 1) == 0
}

//   Apply one worker event to display-owned lifecycle and completion metadata.
// View and animation events release their single-pending submission guards while
// payload slots retain the completed data.
accept_julia_event :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    if event.request_id != service^.active_request_id ||
        event.request_kind != service^.active_request_kind {
        log.warnf(
            "julia_completion_mismatch request_id=%d request_kind=%d active_id=%d active_kind=%d",
            event.request_id, int(event.request_kind), service^.active_request_id,
            int(service^.active_request_kind))
        return
    }
    if service^.evidence_session != nil {
        for evidence_index in 0..<event.evidence_count {
            evidence_session.session_accept_event(
                service^.evidence_session, event.evidence[evidence_index])
        }
    }
    if !event.succeeded {
        record_julia_event_failure(service, event)
    }
    service^.active_request_id = 0

    handlers := JULIA_EVENT_HANDLERS
    handler := handlers[event.kind]
    if handler != nil {
        handler(service, event)
    }
}

//   Mark the service stopped when a shutdown completes successfully.
julia_event_on_shutdown :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    if event.succeeded {
        service^.lifecycle = .Stopped
        log.infof("julia_service_stopped request_id=%d generation=%d",
            event.request_id, service^.runtime_generation)
    }
}

//   Clear the animation-tick pending flag.
julia_event_on_animation_tick :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.animation_tick_pending = false
}

//   Record a failed Julia event and fail the lifecycle on terminal events.
record_julia_event_failure :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.failed_request_count += 1
    service^.last_failed_request_id = event.request_id
    service^.last_failed_request_kind = event.request_kind
    log.errorf(
        "julia_request_failed request_id=%d request_kind=%d event_kind=%d generation=%d count=%d",
        event.request_id, int(event.request_kind), int(event.kind),
        service^.runtime_generation, service^.failed_request_count)
    if event.kind == .Initialized || event.kind == .Shutdown_Complete {
        service^.lifecycle = .Failed
    }
}

//   Publish readiness after startup registration and priming have completed.
// Initialization alone is insufficient: the display may submit normal work only after this.
mark_julia_runtime_ready :: proc(service: ^Julia_Runtime_Service) {
    assert(service != nil && service^.lifecycle == .Starting)
    service^.lifecycle = .Ready
    log.infof("julia_service_ready generation=%d", service^.runtime_generation)
}

//   Assert that Julia work is executing on the persistent owner thread.
// Call this at externally reachable task boundaries before invoking Julia or Julia-backed helpers.
assert_julia_runtime_owner :: proc(state: ^core.Euclid_General_State) {
    assert(state != nil && state^.julia_runtime_service != nil)
    service := state^.julia_runtime_service
    assert(os.get_current_thread_id() == service^.owner_thread_id,
        "Julia C API operation executed outside the Julia owner thread")
}

//   Reserve the single bounded lifecycle slot and advance its incarnation.
reserve_animation_lifecycle_slot :: proc(
    service: ^Julia_Runtime_Service) -> (
        bridgemodel.Animation_Lifecycle_Slot_Handle, bool) {
    slot := &service^.animation_lifecycle_slot
    if slot^.state != .Free {
        return {}, false
    }
    slot^.reservation_generation += 1
    if slot^.reservation_generation == 0 {
        slot^.reservation_generation = 1
    }
    slot^.state = .Pending
    return bridgemodel.Animation_Lifecycle_Slot_Handle{
        index = 0,
        reservation_generation = slot^.reservation_generation,
    }, true
}

//   Snapshot display-owned lifecycle intent into one reserved transaction slot.
prepare_animation_lifecycle_slot :: proc(
    state: ^core.Euclid_General_State,
    handle: bridgemodel.Animation_Lifecycle_Slot_Handle) {
    service := state^.julia_runtime_service
    selected := state^.julia_interface^.selected_animation
    if selected == nil {
        selected = &state^.julia_interface^.null_animation
    }
    service^.animation_lifecycle_slot = {
        state = .Pending,
        request_id = service^.next_request_id,
        reservation_generation = handle.reservation_generation,
        runtime_generation = service^.runtime_generation,
        animation_generation = service^.animation_generation,
        selected_stable_id = selected^.stable_id,
        reset_requested = state^.julia_interface^.pending_animation_reset,
        reload_requested = service^.reload_requested,
        host_state = state,
    }
}

//   Route egress until the correlated lifecycle transaction completes.
wait_animation_lifecycle_completion :: proc(
    service: ^Julia_Runtime_Service,
    request_id: u64) -> bool {
    for {
        event, matched := try_route_julia_egress(
            service, request_id, .Invoke_Complete, true)
        if matched {
            return event.succeeded
        }
        if transport.consumer_mailbox_finished(&service.display_inbox) {
            return false
        }
        transport.consumer_mailbox_wait(&service.display_inbox, time.Millisecond)
    }
}

//   Submit one prepared lifecycle transaction and synchronously route its completion.
invoke_animation_lifecycle_transaction :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    handle, reserved := reserve_animation_lifecycle_slot(service)
    if !reserved {
        return false
    }
    prepare_animation_lifecycle_slot(state, handle)
    slot := &service^.animation_lifecycle_slot
    request_id, sent := try_submit_animation_lifecycle(
        service, handle, slot^.runtime_generation, slot^.animation_generation)
    if !sent {
        slot^.state = .Free
        return false
    }
    return wait_animation_lifecycle_completion(service, request_id)
}

when core.HARNESS_ENABLED {
    //   Run one typed harness request synchronously while routing unrelated egress.
    invoke_harness_transaction :: proc(
        state: ^core.Euclid_General_State, scenario_name: string,
        step_count: i64) -> bool {
        if state == nil || state^.julia_runtime_service == nil {
            return false
        }
        service := state^.julia_runtime_service
        if os.get_current_thread_id() == service^.owner_thread_id {
            return false
        }
        request_id, sent := try_submit_harness_scenario(
            service, scenario_name, step_count)
        if !sent {
            return false
        }
        for {
            event, matched := try_route_julia_egress(
                service, request_id, .Invoke_Complete)
            if matched {
                return event.succeeded
            }
            if transport.consumer_mailbox_finished(&service.display_inbox) {
                return false
            }
            transport.consumer_mailbox_wait(&service.display_inbox, time.Millisecond)
        }
    }
}

//   Join the stopped worker and release receiver inboxes and service staging storage.
// The shutdown request must already have completed; destroying a live worker would violate
// Julia ownership and may leave queued payloads unprocessed.
destroy_julia_runtime_service :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    if service^.worker != nil {
        thread.destroy(service^.worker)
    }
    log_julia_mailbox_diagnostics("julia", &service.julia_inbox)
    log_julia_mailbox_diagnostics("display", &service.display_inbox)
    evidence_profile.destroy(&service^.profile)
    view_snapshot_slots_destroy(service)
    owned_view_content_clear(&service.display_pending_view_storage)
    owned_view_content_clear(&service.pending_view_storage)
    destroy_julia_runtime_mailboxes(service)
    allocator := service^.bootstrap_allocator
    delete(service^.asset_root_override, allocator)
    free(service, allocator)
}

// Report bounded native pressure and measured publication costs after the worker has joined.
log_julia_mailbox_diagnostics :: proc(
    direction: string, mailbox: ^bridgemodel.Consumer_Mailbox($T)) {
    d := transport.consumer_mailbox_diagnostics(mailbox)
    log.infof(
        "julia_mailbox_transport direction=%s accepted_bytes=%d byte_limit=%d outstanding=%d peak=%d peak_bytes=%d publications=%d publication_ns=%d lock_wait_ns=%d copy_ns=%d",
        direction, d.accepted_bytes, d.byte_limit, d.outstanding, d.peak_outstanding,
        d.peak_bytes, d.publication_count, i64(d.publication_time),
        i64(d.lock_wait_time), i64(d.copy_time))
}

//   Resolve Julia callbacks and register content into unpublished host state.
// This owner-thread task publishes no Ready lifecycle state; startup priming controls that step.
initialize_julia_state :: proc(state: ^core.Euclid_General_State) -> bool {
    assert_julia_runtime_owner(state)
    state^.saved_context = context
    if !prepare_julia_interface_content(state^.julia_interface) {
        log.error("julia_content_interface_handles_invalid")
        bridge_animation.clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    if !init_euclid_scripts(state) {
        log.error("julia_content_registration_failed")
        bridge_animation.clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    return true
}

//   Construct the Julia-defined runtime host after the stable script is loaded.
//
// Returns:
//   - The unrooted host value, which the caller must root before another Julia allocation.
create_julia_runtime_host :: proc(
    state: ^core.Euclid_General_State,
    asset_config: ^files.Asset_Root_Config = nil) -> ^julialib.jl_value_t {

    if state == nil {
        return nil
    }
    constructor := julialib.jl_get_function(
        julialib.julia_main_module(), "create_euclid_runtime_host")
    if constructor == nil {
        return nil
    }
    content_path, content_ok := resolve_packaged_julia_content_path(
        false, asset_config)
    if !content_ok {
        return nil
    }
    content_cstr := strings.clone_to_cstring(
        content_path, context.temp_allocator)
    content_value := julialib.jl_cstr_to_string(content_cstr)
    host := julialib.jl_call2(
        constructor, julialib.jl_box_voidpointer(state), content_value)
    if host == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("create_euclid_runtime_host")
        return nil
    }
    return host
}

//   Initialize Julia and install an empty worker-lifetime runtime-host root.
initialize_julia_worker_host :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    frame: ^Julia_Runtime_Gc_Frame) -> bool {

    asset_config := julia_service_asset_config(service)
    if !initiate_julia(&asset_config) {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame^ = Julia_Runtime_Gc_Frame{
        encoded_root_count = (1 << 2) | 1,
        previous = gc_stack^,
        root = rawptr(&host^.runtime),
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(frame)
    return true
}

//   Construct and validate the rooted runtime host after native state exists.
initialize_julia_runtime_host :: proc(
    service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host,
    state: ^core.Euclid_General_State) -> bool {

    if service == nil || host == nil || state == nil || host^.runtime != nil {
        return false
    }
    asset_config := julia_service_asset_config(service)
    host^.runtime = create_julia_runtime_host(state, &asset_config)
    if host^.runtime == nil {
        print_julia_exception("create_euclid_runtime_host")
        fmt.eprintln("Julia startup: failed to create runtime host")
        return false
    }
    julialib.jl_gc_collect(.JL_GC_FULL)
    validator := julialib.jl_get_function(
        julialib.julia_main_module(), "is_euclid_runtime_host")
    valid_host := validator != nil &&
        julialib.jl_unbox_bool(julialib.jl_call1(validator, host^.runtime)) != 0 &&
        julialib.jl_exception_occurred() == nil
    if !valid_host {
        print_julia_exception("is_euclid_runtime_host")
        host^.runtime = nil
        return false
    }
    if !bind_julia_terminal_callbacks(host) {
        report_missing_julia_terminal_callbacks(host)
        host^.runtime = nil
        return false
    }
    service^.runtime_host = host^.runtime
    return true
}

//   Remove the worker host root before shutting down Julia.
finalize_julia_worker_host :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    frame: ^Julia_Runtime_Gc_Frame) {

    service^.runtime_host = nil
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack != nil {
        gc_stack^ = frame^.previous
    }
    host^.runtime = nil
}

//   Initialize content and install the sole lifetime-stable native host binding.
initialize_julia_content_control :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: bridgemodel.Runtime_Content_Initialize_Requested) -> bool {
    native_state := cast(^core.Euclid_General_State)request.native_state
    if native_state == nil {
        return false
    }
    if host^.runtime == nil {
        host^.native_state = native_state
        if !initialize_julia_runtime_host(service, host, host^.native_state) {
            return false
        }
    }
    return host^.native_state == native_state && initialize_julia_state(native_state)
}

//   Initialize the Julia worker host and publish its resulting state.
execute_julia_runtime_initialize :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    event: ^Julia_Event) {
    event^.kind = .Initialized
    event^.succeeded = !state^.initialized &&
        initialize_julia_worker_host(service, &state^.host, &state^.frame)
    state^.initialized = event^.succeeded
}

//   Dispatch one typed control to its concrete owner-thread handler.
execute_julia_control_handler :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    message: ^bridgemodel.Julia_Host_Ingress, event: ^Julia_Event) -> bool {
    shutting_down := false
    #partial switch request in message^ {
    case bridgemodel.Runtime_Initialize_Requested:
        execute_julia_runtime_initialize(service, state, event)
    case bridgemodel.Runtime_Content_Initialize_Requested:
        event^.kind = .Invoke_Complete
        event^.succeeded = state^.initialized &&
            initialize_julia_content_control(service, &state^.host, request)
    case bridgemodel.Animation_Tick_Requested:
        event^.kind = .Animation_Tick_Complete
        event^.succeeded = state^.host.runtime != nil &&
            generate_animation_tick(service, &state^.host, request)
    case bridgemodel.Animation_Lifecycle_Requested:
        event^.kind = .Invoke_Complete
        event^.succeeded = state^.host.runtime != nil &&
            update_animation_lifecycle(service, &state^.host, request)
    case bridgemodel.Harness_Scenario_Requested:
        when core.HARNESS_ENABLED {
            event^.kind = .Invoke_Complete
            event^.succeeded = state^.host.runtime != nil &&
                run_harness_scenario(&state^.host, request)
        } else {
            event^.succeeded = false
        }
    case bridgemodel.Runtime_Shutdown_Requested:
        assert(os.get_current_thread_id() == service^.owner_thread_id)
        event^.kind = .Shutdown_Complete
        shutting_down = true
    case:
        event^.succeeded = false
    }
    return shutting_down
}

//   Execute one typed control while borrowing its Julia-inbox envelope.
execute_julia_control :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    message: ^bridgemodel.Julia_Host_Ingress,
    decoded: Julia_Decoded_Control) -> (Julia_Event, bool) {
    event: Julia_Event = {
        request_kind = decoded.request_kind,
        request_id = decoded.request_id,
        slot_index = decoded.slot_index,
        succeeded = true,
    }
    evidence_profile.zone_begin(&service^.profile, "julia_request")
    shutting_down := execute_julia_control_handler(service, state, message, &event)
    evidence_profile.zone_end(&service^.profile)
    return event, shutting_down
}

//   Convert shared worker completion storage into its typed transport fields.
julia_completion_from_event :: proc(event: Julia_Event) -> bridgemodel.Julia_Completion {
    return {
        request_id = event.request_id,
        succeeded = event.succeeded,
        evidence = event.evidence,
        evidence_count = event.evidence_count,
    }
}

//   Normalize one typed completion for existing lifecycle and evidence handlers.
julia_event_from_completion :: proc(
    completion: bridgemodel.Julia_Completion,
    request_kind: Julia_Request_Kind,
    event_kind: Julia_Event_Kind) -> Julia_Event {
    return {
        kind = event_kind,
        request_kind = request_kind,
        request_id = completion.request_id,
        slot_index = -1,
        succeeded = completion.succeeded,
        evidence = completion.evidence,
        evidence_count = completion.evidence_count,
    }
}

//   Encode one animation lifecycle completion with its repeated generation identity.
encode_animation_lifecycle_completion :: proc(
    message: ^bridgemodel.Julia_Host_Egress,
    decoded: Julia_Decoded_Control,
    completion: bridgemodel.Julia_Completion) {
    message^ = bridgemodel.Julia_Host_Egress(
        bridgemodel.Animation_Lifecycle_Completed{
            completion = completion,
            handle = decoded.lifecycle_handle,
            runtime_generation = decoded.runtime_generation,
            animation_generation = decoded.animation_generation,
        })
}

//   Encode one typed completion with repeated request and slot identity.
encode_typed_julia_completion :: proc(
    message: ^bridgemodel.Julia_Host_Egress, decoded: Julia_Decoded_Control,
    event: Julia_Event) {
    completion := julia_completion_from_event(event)
    switch decoded.protocol {
    case .Runtime_Initialize:
        message^ = bridgemodel.Julia_Host_Egress(bridgemodel.Runtime_Initialized{
            completion = completion,
        })
    case .Runtime_Content_Initialize:
        message^ = bridgemodel.Julia_Host_Egress(bridgemodel.Runtime_Content_Initialized{
            completion = completion,
        })
    case .Animation_Tick:
        message^ = bridgemodel.Julia_Host_Egress(bridgemodel.Animation_Tick_Completed{
            completion = completion,
            handle = decoded.tick_handle,
            animation_generation = decoded.animation_generation,
            sequence = decoded.sequence,
        })
    case .Animation_Lifecycle:
        encode_animation_lifecycle_completion(message, decoded, completion)
    case .Harness_Scenario:
        message^ = bridgemodel.Julia_Host_Egress(bridgemodel.Harness_Scenario_Completed{
            completion = completion,
        })
    case .Runtime_Shutdown:
        message^ = bridgemodel.Julia_Host_Egress(bridgemodel.Runtime_Shutdown_Completed{
            completion = completion,
        })
    }
}

//   Publish one matching typed completion into the display-owned inbox.
send_typed_julia_completion :: proc(
    service: ^Julia_Runtime_Service,
    decoded: Julia_Decoded_Control,
    event: Julia_Event) -> bridgemodel.Communication_Send_Outcome {
    pending_outcome := flush_pending_view_content(service)
    if pending_outcome != .Sent {
        return pending_outcome
    }
    message: bridgemodel.Julia_Host_Egress
    encode_typed_julia_completion(&message, decoded, event)
    return transport.consumer_mailbox_send(&service.display_inbox, message)
}

//   Decode one animation control into a bridge-private compatibility request.
decode_julia_animation_control :: proc(
    message: ^bridgemodel.Julia_Host_Ingress) -> (Julia_Decoded_Control, bool) {
    #partial switch request in message^ {
    case bridgemodel.Animation_Tick_Requested:
        return {
            protocol = .Animation_Tick,
            request_kind = .Animation_Tick,
            request_id = request.request_id,
            slot_index = request.handle.index,
            tick_handle = request.handle,
            animation_generation = request.animation_generation,
            sequence = request.sequence,
        }, true
    case bridgemodel.Animation_Lifecycle_Requested:
        return {
            protocol = .Animation_Lifecycle,
            request_kind = .Invoke,
            request_id = request.request_id,
            slot_index = request.handle.index,
            lifecycle_handle = request.handle,
            runtime_generation = request.runtime_generation,
            animation_generation = request.animation_generation,
        }, true
    }
    return {}, false
}

//   Decode one runtime or harness control into a bridge-private execution record.
decode_julia_control :: proc(
    message: ^bridgemodel.Julia_Host_Ingress) -> (Julia_Decoded_Control, bool) {
    if decoded, ok := decode_julia_animation_control(message); ok {
        return decoded, true
    }
    #partial switch request in message^ {
    case bridgemodel.Runtime_Initialize_Requested:
        return {
            protocol = .Runtime_Initialize,
            request_kind = .Initialize,
            request_id = request.request_id,
            slot_index = -1,
        }, true
    case bridgemodel.Runtime_Content_Initialize_Requested:
        return {
            protocol = .Runtime_Content_Initialize,
            request_kind = .Invoke,
            request_id = request.request_id,
            slot_index = -1,
        }, true
    case bridgemodel.Harness_Scenario_Requested:
        when core.HARNESS_ENABLED {
            return {
                protocol = .Harness_Scenario,
                request_kind = .Invoke,
                request_id = request.request_id,
                slot_index = -1,
            }, true
        } else {
            return {}, false
        }
    case bridgemodel.Runtime_Shutdown_Requested:
        return {
            protocol = .Runtime_Shutdown,
            request_kind = .Shutdown,
            request_id = request.request_id,
            slot_index = -1,
        }, true
    }
    return {}, false
}

// Retire unprocessed ingress only after a fatal failure or accepted terminal shutdown.
retire_stopped_julia_ingress :: proc(service: ^Julia_Runtime_Service) {
    transport.consumer_mailbox_close(&service.julia_inbox)
    remaining := transport.consumer_mailbox_batch_count(&service.julia_inbox)
    if remaining > 0 {
        log.warnf("julia_worker_retiring_pending_requests count=%d", remaining)
    }
    for _ in 0..<remaining {
        message, received := transport.consumer_mailbox_try_recv(&service.julia_inbox)
        assert(received)
        transport.consumer_mailbox_release(&service.julia_inbox, message)
    }
}

// Dispatch the entire accepted ingress batch before pumping ordinary Julia actor work.
drain_julia_worker_ingress :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    count: int) -> (Julia_Worker_Run_Result, bool) {
    for _ in 0..<count {
        message, received := transport.consumer_mailbox_try_recv(&service.julia_inbox)
        assert(received)
        result, accepted := process_julia_worker_ingress(service, state, message)
        if result.shutting_down || !accepted {
            retire_stopped_julia_ingress(service)
            return result, accepted
        }
    }
    return {}, true
}

//   Own the rooted Julia host stack frame and serialized requests until shutdown.
shutdown_julia_runtime_host :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    frame: ^Julia_Runtime_Gc_Frame, decoded: Julia_Decoded_Control,
    event: ^Julia_Event) {
    if host^.runtime != nil && host^.terminal_shutdown != nil {
        result := julialib.jl_call1(host^.terminal_shutdown, host^.runtime)
        event^.succeeded = event^.succeeded && result != nil &&
            julialib.jl_exception_occurred() == nil &&
            julialib.jl_unbox_bool(result) != 0
        if !event^.succeeded {
            print_julia_exception("terminal_host_shutdown")
        }
    }
    attach_julia_control_evidence(service, decoded, event)
    finalize_julia_worker_host(service, host, frame)
    end_julia()
}

//   Execute one typed control and attach its bounded completion evidence.
process_julia_worker_control :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    message: ^bridgemodel.Julia_Host_Ingress,
    decoded: Julia_Decoded_Control) -> Julia_Worker_Request_Result {
    event, shutting_down := execute_julia_control(
        service, state, message, decoded)
    if shutting_down {
        shutdown_julia_runtime_host(
            service, &state^.host, &state^.frame, decoded, &event)
        return {
            event = event,
            shutting_down = true,
            accepted = true,
        }
    }
    attach_julia_control_evidence(service, decoded, &event)
    return {
        event = event,
        accepted = true,
    }
}

//   Dispatch one Terminal ingress envelope and release its Julia-inbox borrow.
process_julia_terminal_ingress :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    message: ^bridgemodel.Julia_Host_Ingress) -> bool {
    accepted := host^.runtime != nil &&
        julia_terminal_dispatch_ingress(service, host, message)
    transport.consumer_mailbox_release(&service^.julia_inbox, message)
    if !accepted {
        fmt.eprintln("Julia worker: Terminal ingress rejected")
    }
    return accepted
}

//   Process one borrowed worker ingress envelope and report whether the loop may continue.
process_julia_worker_ingress :: proc(
    service: ^Julia_Runtime_Service, state: ^Julia_Worker_State,
    message: ^bridgemodel.Julia_Host_Ingress) -> (Julia_Worker_Run_Result, bool) {
    if request, is_content := message^.(bridgemodel.Scenario_View_Content_Requested);
       is_content {
        current := state^.host.native_state != nil &&
            state^.host.native_state^.julia_interface != nil &&
            request.runtime_generation == service^.runtime_generation &&
            request.animation_generation == service^.animation_generation &&
            request.animation ==
                state^.host.native_state^.julia_interface^.current_animation
        outcome := bridgemodel.Communication_Send_Outcome.Runtime_Stopping
        if current {
            outcome = send_scenario_presented_text(service, request)
        }
        transport.consumer_mailbox_release(&service^.julia_inbox, message)
        return {}, outcome == .Sent || outcome == .Queue_Full || outcome == .Storage_Full
    }
    decoded, is_control := decode_julia_control(message)
    if !is_control {
        return {}, process_julia_terminal_ingress(service, &state^.host, message)
    }
    result := process_julia_worker_control(service, state, message, decoded)
    transport.consumer_mailbox_release(&service^.julia_inbox, message)
    if result.shutting_down {
        return {
            shutdown_request = decoded,
            shutdown_event = result.event,
            shutting_down = true,
        }, true
    }
    accepted := result.accepted &&
        send_typed_julia_completion(service, decoded, result.event) == .Sent
    return {}, accepted
}

//   Own the rooted Julia host stack frame and serialized requests until shutdown.
// The returned shutdown event is published only after this stack frame is gone.
julia_runtime_worker_run_host :: proc(
    service: ^Julia_Runtime_Service) -> Julia_Worker_Run_Result {

    worker_context := context
    state: Julia_Worker_State
    for {
        count := transport.consumer_mailbox_batch_count(&service.julia_inbox)
        if count == 0 && transport.consumer_mailbox_finished(&service.julia_inbox) {
            return {}
        }
        result, accepted := drain_julia_worker_ingress(service, &state, count)
        if result.shutting_down || !accepted {
            return result
        }
        if state.host.runtime != nil &&
            !julia_terminal_service(service, &state.host) {
            fmt.eprintln("Julia worker: Terminal service failed")
            retire_stopped_julia_ingress(service)
            return {}
        }

        // We have a thread-local dedicated temp_allocator in the Julia thread context,
        // so we free it on each iteration of the loop
        // This acts separately and in conjunction with the display loop doing the same,
        // but it has its own thread-local temp_allocator as well.
        context = worker_context
        free_all(context.temp_allocator)
        if count == 0 {
            wait := time.Millisecond
            if state.host.runtime != nil {
                wait = state.host.idle_wait
            }
            transport.consumer_mailbox_wait(&service.julia_inbox, wait)
        }
    }
}

//   Own Julia lifecycle and publish termination only after the rooted host frame is gone.
julia_runtime_worker :: proc(data: rawptr) {
    service := cast(^Julia_Runtime_Service)data
    defer transport.consumer_mailbox_close(&service.julia_inbox)
    defer transport.consumer_mailbox_close(&service.display_inbox)
    service^.owner_thread_id = os.get_current_thread_id()
    evidence_profile.thread_name(&service^.profile, "julia-worker")
    log.info("julia_worker_started")
    result := julia_runtime_worker_run_host(service)
    if !result.shutting_down {
        log.error("julia_worker_requests_closed_before_shutdown")
        return
    }
    if send_typed_julia_completion(
        service, result.shutdown_request, result.shutdown_event) != .Sent {
        log.error("julia_worker_shutdown_event_send_failed")
        return
    }
    log.info("julia_worker_stopped")
}

//   Build one animation-tick completion event for the Julia channel handoff.
animation_tick_request_evidence :: proc(
    service: ^Julia_Runtime_Service, decoded: Julia_Decoded_Control,
    event: ^Julia_Event) -> evidence_trace.Event {
    kind := evidence_trace.Kind.Animation_Tick_Accepted if event.succeeded else
        .Animation_Tick_Rejected
    if decoded.slot_index >= 0 &&
        decoded.slot_index < len(service^.animation_tick_slots) &&
        service^.animation_tick_slots[decoded.slot_index].show_completed {
        kind = .Animation_Completed_Accepted if event.succeeded else
            .Animation_Completed_Rejected
    }
    return {
        lane = .Transport,
        kind = kind,
        correlation_kind = .Runtime_Request,
        correlation = decoded.request_id,
        generation = service.animation_generation,
        flags = event.succeeded ? {} : {.Failure},
        payload = {
            request = {
                status = event.succeeded ? 1 : 0,
                slot = u32(max(decoded.slot_index, 0)),
            },
        },
    }
}

//   Attach one owner-recorded Julia completion event to its channel handoff.
attach_julia_control_evidence :: proc(
    service: ^Julia_Runtime_Service, decoded: Julia_Decoded_Control,
    event: ^Julia_Event) {
    if service == nil || event == nil || service.evidence_session == nil {
        return
    }
    evidence: evidence_trace.Event
    record_completion := true
    switch decoded.protocol {
    case .Animation_Tick:
        evidence = animation_tick_request_evidence(service, decoded, event)
    case .Runtime_Shutdown:
        evidence = {
            lane = .Lifecycle,
            kind = .Runtime_Shutdown_Complete,
            correlation_kind = .Runtime_Request,
            correlation = decoded.request_id,
            generation = service.runtime_generation,
            flags = {.Required},
        }
    case .Runtime_Content_Initialize, .Animation_Lifecycle, .Harness_Scenario:
        record_completion = false
    case .Runtime_Initialize:
        return
    }
    if !record_completion || evidence_session.session_record(
        service.evidence_session, &service.evidence_ring, evidence) {
        event.evidence_count = evidence_trace.ring_drain(
            &service.evidence_ring, event.evidence[:])
    }
    if service.evidence_ring.count > 0 {
        evidence_session.session_mark_incomplete(service.evidence_session)
    }
}
