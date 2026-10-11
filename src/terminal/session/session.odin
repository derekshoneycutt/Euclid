package termsession

import protocol "../../core/protocol"
import "core:log"

// Generational identity of the actor supervising a foreground terminal session.
Session_Owner :: struct {
    id: u64,
    generation: u64,
}

// Generational handle for one admitted foreground operation.
//
// The current manager has one slot; generation prevents stale control requests from
// targeting a later operation that reuses it.
Terminal_Session_Operation_Id :: struct {
    slot: u32,
    generation: u64,
}

// Destination selected for user terminal input at the service boundary.
Terminal_Input_Target :: enum u8 {
    Julia_Repl,
    Terminal_Session,
}

// Foreground operation lifecycle held by the session manager.
Terminal_Session_State :: enum u8 {
    Inactive,
    Running,
    Cancelling,
}

// Escalation phase for bounded foreground-process reconciliation.
Terminal_Process_Close_Phase :: enum u8 {
    None,
    Graceful_Requested,
    Force_Requested,
    Reaping,
    Transferred,
    Complete,
}

// Default graceful and final reconciliation windows in monotonic nanoseconds.
TERMINAL_PROCESS_CLOSE_GRACE_NS :: u64(2_000_000_000)
TERMINAL_PROCESS_CLOSE_FINAL_NS :: u64(4_000_000_000)

// Display-driven state for one bounded process close attempt.
Terminal_Process_Close_Coordinator :: struct {
    phase: Terminal_Process_Close_Phase,
    generation: u64,
    graceful_deadline_ns: u64,
    final_deadline_ns: u64,
}

// Generation and fakeable monotonic timing for one bounded close request.
Terminal_Process_Close_Request :: struct {
    generation: u64,
    now_ns: u64,
    graceful_ns: u64,
    final_ns: u64,
}

// Stable semantic reason a session request was not applied.
Terminal_Session_Rejection :: enum u8 {
    None,
    Invalid_Request,
    Stale_Owner,
    Foreground_Busy,
    Invalid_Plan,
    Executable_Not_Found,
    Resource_Unavailable,
    Backend_Failure,
    Stale_Operation,
    Unsupported,
}

// Owned request to admit one direct foreground pseudoterminal process.
Terminal_Session_Begin_Request :: struct {
    request_id: protocol.Request_Id,
    owner: Session_Owner,
    plan: Process_Plan,
    dimensions: Terminal_Dimensions,
    geometry_generation: u64,
}

// Correlated begin outcome; operation identity is meaningful only when accepted.
Terminal_Session_Begin_Result :: struct {
    request_id: protocol.Request_Id,
    operation_id: Terminal_Session_Operation_Id,
    rejection: Terminal_Session_Rejection,
    accepted: bool,
}

// Owner- and operation-bound bounded input submission.
Terminal_Session_Input_Request :: struct {
    owner: Session_Owner,
    operation_id: Terminal_Session_Operation_Id,
    bytes: [TERMINAL_SESSION_INPUT_MAX_BYTES]u8,
    byte_count: int,
}

// Owner- and operation-bound accepted geometry publication.
Terminal_Session_Resize_Request :: struct {
    owner: Session_Owner,
    operation_id: Terminal_Session_Operation_Id,
    geometry_generation: u64,
    dimensions: Terminal_Dimensions,
}

// Control action requested for the active foreground process group.
Terminal_Session_Signal :: enum u8 {
    Interrupt,
    Terminate,
    Force_Terminate,
}

// Owner- and operation-bound process-control request.
Terminal_Session_Signal_Request :: struct {
    owner: Session_Owner,
    operation_id: Terminal_Session_Operation_Id,
    signal: Terminal_Session_Signal,
}

// Owner-visible classification of one completed foreground operation.
Terminal_Session_Completion_Kind :: enum u8 {
    Exited,
    Signalled,
    Cancelled,
    Infrastructure_Failure,
}

// Final correlated operation outcome emitted exactly once by the manager.
Terminal_Session_Completion :: struct {
    request_id: protocol.Request_Id,
    owner: Session_Owner,
    operation_id: Terminal_Session_Operation_Id,
    kind: Terminal_Session_Completion_Kind,
    status: i32,
}

// One bounded service update containing independently optional output and completion.
Terminal_Session_Update :: struct {
    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8,
    output_count: int,
    completion: Terminal_Session_Completion,
    completion_available: bool,
    process_exited: bool,
    output_drained: bool,
}

// Active operation identity and lifecycle state.
Terminal_Session_Operation :: struct {
    // Lifecycle and original request correlation.
    state: Terminal_Session_State,
    request_id: protocol.Request_Id,

    // Owner-scoped generational identity.
    owner: Session_Owner,
    id: Terminal_Session_Operation_Id,

    // Sticky cancellation intent used to classify eventual backend exit.
    cancellation_requested: bool,
    applied_geometry_generation: u64,
    applied_dimensions: Terminal_Dimensions,
}

// Single-owner registry for at most one foreground terminal operation.
//
// Calls are serialized by the owning service thread. A successful begin routes input
// to the terminal until update emits completion or destroy tears the operation down.
Terminal_Session_Manager :: struct {
    // Current supervising actor identity and monotonic operation generation source.
    owner: Session_Owner,
    next_generation: u64,

    // Current input route and active-operation state machine.
    input_target: Terminal_Input_Target,
    operation: Terminal_Session_Operation,

    // Borrowed backend table whose user state outlives the manager.
    backend: Terminal_Process_Backend,
}

//   Initialize one foreground-session registry for a current actor owner.
//
// Parameters:
//   - manager: Destination manager state.
//   - owner: Nonzero current actor identity.
//   - backend: Complete mechanism table with longer-lived user state.
//
// Returns:
//   - True after initialization; false for nil, invalid owner, or incomplete backend.
//
// Side effects:
//   - Resets the manager to inactive with input routed to Julia.
terminal_session_init :: proc(
    manager: ^Terminal_Session_Manager, owner: Session_Owner,
    backend: Terminal_Process_Backend) -> bool {
    if manager == nil || owner.id == 0 || owner.generation == 0 ||
       !terminal_process_backend_valid(backend) {
        return false
    }
    manager^ = {
        owner = owner,
        input_target = .Julia_Repl,
        backend = backend,
    }
    log.debugf("terminal session manager initialized owner_id=%d owner_generation=%d",
        owner.id, owner.generation)
    return true
}

//   Return whether one request addresses the registered actor generation.
//
// Parameters:
//   - manager: Session registry to inspect.
//   - owner: Candidate generational actor identity.
//
// Returns:
//   - True only for an exact identity match on a non-nil manager.
terminal_session_owner_current :: proc(
    manager: ^Terminal_Session_Manager, owner: Session_Owner) -> bool {
    return manager != nil && owner == manager.owner
}

//   Perform all admission checks before allocating backend resources.
//
// Parameters:
//   - manager: Initialized session registry.
//   - request: Candidate begin request.
//
// Returns:
//   - `.None` when correlation, owner, availability, dimensions, and plan are valid;
//     otherwise the first stable rejection reason.
terminal_session_admission_rejection :: proc(
    manager: ^Terminal_Session_Manager,
    request: ^Terminal_Session_Begin_Request) -> Terminal_Session_Rejection {
    if manager == nil || request == nil || request.request_id == 0 ||
       request.dimensions.columns == 0 || request.dimensions.rows == 0 {
        return .Invalid_Request
    }
    if !terminal_session_owner_current(manager, request.owner) {
        return .Stale_Owner
    }
    if manager.operation.state != .Inactive {
        return .Foreground_Busy
    }
    if process_plan_validate(&request.plan) != .None {
        return .Invalid_Plan
    }
    return .None
}

//   Translate one backend start status into a stable admission rejection.
//
// Parameters:
//   - status: Mechanism-level start result.
//
// Returns:
//   - `.None` for `.Started`; otherwise the corresponding public rejection.
terminal_session_start_rejection :: proc(
    status: Backend_Start_Status) -> Terminal_Session_Rejection {
    switch status {
    case .Executable_Not_Found:
        return .Executable_Not_Found
    case .Resource_Unavailable:
        return .Resource_Unavailable
    case .Internal_Failure:
        return .Backend_Failure
    case .Started:
        return .None
    }
    return .Backend_Failure
}

//   Record one rejected admission without dereferencing an absent request.
terminal_session_log_admission_rejection :: proc(
    request: ^Terminal_Session_Begin_Request,
    rejection: Terminal_Session_Rejection) {
    if request == nil {
        log.warnf("terminal session rejected reason=%v", rejection)
        return
    }
    log.warnf(
        "terminal session rejected request_id=%d owner_id=%d owner_generation=%d reason=%v",
        request.request_id, request.owner.id, request.owner.generation, rejection)
}

//   Record one backend start rejection at recoverable or failed-operation severity.
terminal_session_log_start_rejection :: proc(
    request: ^Terminal_Session_Begin_Request,
    rejection: Terminal_Session_Rejection) {
    if rejection == .Executable_Not_Found {
        log.warnf(
            "terminal session start rejected request_id=%d owner_id=%d owner_generation=%d reason=%v",
            request.request_id, request.owner.id, request.owner.generation,
            rejection)
        return
    }
    log.errorf(
        "terminal session start failed request_id=%d owner_id=%d owner_generation=%d reason=%v",
        request.request_id, request.owner.id, request.owner.generation, rejection)
}

//   Record one accepted foreground operation and its authoritative dimensions.
terminal_session_log_started :: proc(
    request: ^Terminal_Session_Begin_Request,
    operation_id: Terminal_Session_Operation_Id) {
    log.infof(
        "terminal session started request_id=%d owner_id=%d owner_generation=%d operation_slot=%d operation_generation=%d columns=%d rows=%d",
        request.request_id, request.owner.id, request.owner.generation,
        operation_id.slot, operation_id.generation,
        request.dimensions.columns, request.dimensions.rows)
}

//   Begin one directly launched foreground operation after canonical validation.
//
// Parameters:
//   - manager: Initialized inactive session registry.
//   - request: Owned begin request valid for the current owner.
//
// Returns:
//   - Correlated accepted operation identity, or a rejection without active state.
//
// Side effects:
//   - On success, starts the backend, advances the nonzero operation generation,
//     records `.Running` state, and routes input to the terminal session.
terminal_session_begin :: proc(
    manager: ^Terminal_Session_Manager,
    request: ^Terminal_Session_Begin_Request) -> Terminal_Session_Begin_Result {
    result: Terminal_Session_Begin_Result
    rejection := terminal_session_admission_rejection(manager, request)
    if rejection != .None {
        result.rejection = rejection
        terminal_session_log_admission_rejection(request, rejection)
        return result
    }
    result.request_id = request.request_id
    start_status := manager.backend.start(
        manager.backend.user_data, &request.plan, request.dimensions)
    if rejection = terminal_session_start_rejection(start_status);
       rejection != .None {
        result.rejection = rejection
        terminal_session_log_start_rejection(request, rejection)
        return result
    }
    manager.next_generation += 1
    if manager.next_generation == 0 {
        manager.next_generation = 1
    }
    manager.operation = {
        state = .Running,
        request_id = request.request_id,
        owner = request.owner,
        id = {slot = 1, generation = manager.next_generation},
        applied_geometry_generation = request.geometry_generation,
        applied_dimensions = request.dimensions,
    }
    manager.input_target = .Terminal_Session
    result.operation_id = manager.operation.id
    result.accepted = true
    terminal_session_log_started(request, result.operation_id)
    return result
}

//   Apply one newer accepted geometry to the correlated active operation.
terminal_session_resize :: proc(
    manager: ^Terminal_Session_Manager,
    request: Terminal_Session_Resize_Request) -> Terminal_Session_Rejection {
    if request.geometry_generation == 0 || request.dimensions.columns == 0 ||
        request.dimensions.rows == 0 {
        return .Invalid_Request
    }
    if !terminal_session_operation_current(
        manager, request.owner, request.operation_id) {
        return .Stale_Operation
    }
    if request.geometry_generation <= manager.operation.applied_geometry_generation {
        return .None
    }
    if !manager.backend.resize(manager.backend.user_data, request.dimensions) {
        log.errorf(
            "terminal session resize failed request_id=%d operation_slot=%d operation_generation=%d geometry_generation=%d columns=%d rows=%d",
            manager.operation.request_id, request.operation_id.slot,
            request.operation_id.generation, request.geometry_generation,
            request.dimensions.columns, request.dimensions.rows)
        return .Backend_Failure
    }
    manager.operation.applied_geometry_generation = request.geometry_generation
    manager.operation.applied_dimensions = request.dimensions
    return .None
}

//   Return whether a control request addresses the active owner-bound operation.
//
// Parameters:
//   - manager: Session registry to inspect.
//   - owner: Candidate supervising actor identity.
//   - operation_id: Candidate generational operation handle.
//
// Returns:
//   - True only when both identities match the non-inactive operation.
terminal_session_operation_current :: proc(
    manager: ^Terminal_Session_Manager, owner: Session_Owner,
    operation_id: Terminal_Session_Operation_Id) -> bool {
    return manager != nil && manager.operation.state != .Inactive &&
        owner == manager.operation.owner && operation_id == manager.operation.id
}

//   Forward bounded input only to the active foreground operation.
//
// Parameters:
//   - manager: Session registry currently routing input.
//   - request: Owner-bound input and its explicit byte count.
//
// Returns:
//   - `.None` after backend acceptance, otherwise invalid, stale, or backend failure.
//
// Side effects:
//   - Passes a synchronous slice of request-owned bytes to the backend.
terminal_session_write_input :: proc(
    manager: ^Terminal_Session_Manager,
    request: ^Terminal_Session_Input_Request) -> Terminal_Session_Rejection {
    if manager == nil || request == nil || request.byte_count <= 0 ||
       request.byte_count > len(request.bytes) {
        return .Invalid_Request
    }
    if !terminal_session_operation_current(
        manager, request.owner, request.operation_id) {
        return .Stale_Operation
    }
    if manager.input_target != .Terminal_Session ||
       !manager.backend.write_input(
           manager.backend.user_data, request.bytes[:request.byte_count]) {
        log.errorf(
            "terminal session input failed owner_id=%d owner_generation=%d operation_slot=%d operation_generation=%d byte_count=%d",
            request.owner.id, request.owner.generation,
            request.operation_id.slot, request.operation_id.generation,
            request.byte_count)
        return .Backend_Failure
    }
    return .None
}

//   Record one rejected or failed operation signal without terminal payload data.
terminal_session_log_signal_failure :: proc(
    manager: ^Terminal_Session_Manager,
    request: Terminal_Session_Signal_Request,
    rejection: Terminal_Session_Rejection) {
    if rejection == .Stale_Operation {
        log.warnf(
            "terminal session signal rejected owner_id=%d owner_generation=%d operation_slot=%d operation_generation=%d signal=%v reason=%v",
            request.owner.id, request.owner.generation,
            request.operation_id.slot, request.operation_id.generation,
            request.signal, rejection)
        return
    }
    log.errorf(
        "terminal session signal failed request_id=%d operation_slot=%d operation_generation=%d signal=%v",
        manager.operation.request_id, request.operation_id.slot,
        request.operation_id.generation, request.signal)
}

//   Record the first accepted transition into cancelling state.
terminal_session_log_cancellation :: proc(
    manager: ^Terminal_Session_Manager,
    request: Terminal_Session_Signal_Request) {
    log.infof(
        "terminal session cancellation requested request_id=%d operation_slot=%d operation_generation=%d signal=%v",
        manager.operation.request_id, request.operation_id.slot,
        request.operation_id.generation, request.signal)
}

//   Apply interrupt or cancellation policy to the active operation.
//
// Parameters:
//   - manager: Session registry containing the target operation.
//   - request: Owner-bound signal request.
//
// Returns:
//   - `.None` after acceptance, including repeated graceful termination; otherwise
//     stale-operation or backend failure.
//
// Side effects:
//   - Interrupt preserves `.Running`; terminate variants set sticky cancellation and
//     transition to `.Cancelling` after backend acceptance.
terminal_session_signal :: proc(
    manager: ^Terminal_Session_Manager,
    request: Terminal_Session_Signal_Request) -> Terminal_Session_Rejection {
    if !terminal_session_operation_current(
        manager, request.owner, request.operation_id) {
        terminal_session_log_signal_failure(manager, request, .Stale_Operation)
        return .Stale_Operation
    }
    switch request.signal {
    case .Interrupt:
        if !manager.backend.request_interrupt(manager.backend.user_data) {
            terminal_session_log_signal_failure(manager, request, .Backend_Failure)
            return .Backend_Failure
        }
    case .Terminate:
        if manager.operation.cancellation_requested {
            return .None
        }
        if !manager.backend.request_terminate(manager.backend.user_data) {
            terminal_session_log_signal_failure(manager, request, .Backend_Failure)
            return .Backend_Failure
        }
        manager.operation.cancellation_requested = true
        manager.operation.state = .Cancelling
        terminal_session_log_cancellation(manager, request)
    case .Force_Terminate:
        if !manager.backend.force_terminate(manager.backend.user_data) {
            terminal_session_log_signal_failure(manager, request, .Backend_Failure)
            return .Backend_Failure
        }
        manager.operation.cancellation_requested = true
        manager.operation.state = .Cancelling
        terminal_session_log_cancellation(manager, request)
    }
    return .None
}

//   Request graceful cancellation when the supervising actor stops.
//
// Parameters:
//   - manager: Session registry that may hold the owner's operation.
//   - owner: Stopped actor generation.
//
// Returns:
//   - True when cancellation is active or was accepted; false when no matching
//     operation exists or the backend rejects termination.
terminal_session_owner_stopped :: proc(
    manager: ^Terminal_Session_Manager, owner: Session_Owner) -> bool {
    if manager == nil || manager.operation.state == .Inactive ||
       owner != manager.operation.owner {
        return false
    }
    rejection := terminal_session_signal(manager, {
        owner = owner,
        operation_id = manager.operation.id,
        signal = .Terminate,
    })
    return rejection == .None
}

//   Reject ownership transfer until a safe protocol is defined.
//
// Returns:
//   - Always `.Unsupported`; manager state is unchanged.
terminal_session_transfer_owner :: proc(
    _: ^Terminal_Session_Manager, _: Session_Owner,
    _: Session_Owner) -> Terminal_Session_Rejection {
    return .Unsupported
}

//   Reject detached operation lifetime under the owner-bound policy.
//
// Returns:
//   - Always `.Unsupported`; manager state is unchanged.
terminal_session_detach :: proc(
    _: ^Terminal_Session_Manager,
    _: Terminal_Session_Operation_Id) -> Terminal_Session_Rejection {
    return .Unsupported
}

//   Translate one backend exit into the stable owner-visible completion outcome.
//
// Parameters:
//   - operation: Completed operation carrying sticky cancellation intent.
//   - exit: Reconciled mechanism-level exit.
//
// Returns:
//   - `.Cancelled` when cancellation was requested; otherwise the backend exit class.
terminal_session_completion_kind :: proc(
    operation: ^Terminal_Session_Operation,
    exit: Backend_Exit) -> Terminal_Session_Completion_Kind {
    if operation.cancellation_requested {
        return .Cancelled
    }
    switch exit.kind {
    case .Exited:
        return .Exited
    case .Signalled:
        return .Signalled
    case .Infrastructure_Failure:
        return .Infrastructure_Failure
    }
    return .Infrastructure_Failure
}

//   Record one owner-visible terminal-session completion at outcome severity.
terminal_session_log_completion :: proc(completion: Terminal_Session_Completion) {
    format := "terminal session completed request_id=%d owner_id=%d owner_generation=%d operation_slot=%d operation_generation=%d kind=%v status=%d"
    switch completion.kind {
    case .Exited:
        log.infof(format, completion.request_id, completion.owner.id,
            completion.owner.generation, completion.operation_id.slot,
            completion.operation_id.generation, completion.kind, completion.status)
    case .Signalled, .Cancelled:
        log.warnf(format, completion.request_id, completion.owner.id,
            completion.owner.generation, completion.operation_id.slot,
            completion.operation_id.generation, completion.kind, completion.status)
    case .Infrastructure_Failure:
        log.errorf(format, completion.request_id, completion.owner.id,
            completion.owner.generation, completion.operation_id.slot,
            completion.operation_id.generation, completion.kind, completion.status)
    }
}

//   Poll bounded output and reconcile backend completion exactly once.
//
// Parameters:
//   - manager: Session registry to service; nil/inactive produces an empty update.
//
// Returns:
//   - One bounded output fragment and, when ready, the sole correlated completion.
//
// Side effects:
//   - Polls output before exit, closes a completed backend exactly once, clears active
//     operation state, and routes subsequent input back to Julia.
terminal_session_update :: proc(
    manager: ^Terminal_Session_Manager) -> Terminal_Session_Update {
    update: Terminal_Session_Update
    if manager == nil || manager.operation.state == .Inactive {
        return update
    }
    update.output_count = manager.backend.poll_output(
        manager.backend.user_data, update.output[:])
    update.output_count = clamp(update.output_count, 0, len(update.output))
    progress := manager.backend.poll_exit(manager.backend.user_data)
    update.process_exited = progress.process_exited
    update.output_drained = progress.output_drained
    if !progress.process_exited || !progress.output_drained {
        return update
    }
    operation := manager.operation
    manager.backend.close(manager.backend.user_data)
    update.completion = {
        request_id = operation.request_id,
        owner = operation.owner,
        operation_id = operation.id,
        kind = terminal_session_completion_kind(&operation, progress.exit),
        status = progress.exit.status,
    }
    update.completion_available = true
    terminal_session_log_completion(update.completion)
    manager.operation = {}
    manager.input_target = .Julia_Repl
    return update
}

//   Add a duration to monotonic time without integer wraparound.
terminal_process_close_deadline :: proc(now_ns, duration_ns: u64) -> u64 {
    if duration_ns > max(u64) - now_ns {
        return max(u64)
    }
    return now_ns + duration_ns
}

// Escalate a failed graceful request and transfer if forced signaling also fails.
terminal_process_close_begin_fallback :: proc(
    coordinator: ^Terminal_Process_Close_Coordinator,
    manager: ^Terminal_Session_Manager,
    registry: ^Process_Cleanup_Registry) {
    force_rejection := terminal_session_signal(manager, {
        owner = manager.operation.owner,
        operation_id = manager.operation.id,
        signal = .Force_Terminate,
    })
    coordinator.phase = .Force_Requested
    if force_rejection != .None && manager.backend.transfer(
        manager.backend.user_data, registry, coordinator.generation) {
        manager.operation = {}
        manager.input_target = .Julia_Repl
        coordinator.phase = .Transferred
    }
}

//   Begin graceful bounded close for the manager's current operation.
//
// Returns:
//   - True after starting or completing close; false for invalid arguments or signal
//     failure that could not transfer backend ownership.
terminal_process_close_begin :: proc(
    coordinator: ^Terminal_Process_Close_Coordinator,
    manager: ^Terminal_Session_Manager,
    registry: ^Process_Cleanup_Registry,
    request: Terminal_Process_Close_Request) -> bool {
    if coordinator == nil || manager == nil || registry == nil ||
       request.generation == 0 || coordinator.phase != .None ||
       request.final_ns < request.graceful_ns {
        return false
    }
    coordinator^ = {
        phase = .Complete,
        generation = request.generation,
        graceful_deadline_ns = terminal_process_close_deadline(
            request.now_ns, request.graceful_ns),
        final_deadline_ns = terminal_process_close_deadline(
            request.now_ns, request.final_ns),
    }
    if manager.operation.state == .Inactive {
        return true
    }
    rejection := terminal_session_signal(manager, {
        owner = manager.operation.owner,
        operation_id = manager.operation.id,
        signal = .Terminate,
    })
    if rejection == .None {
        coordinator.phase = .Graceful_Requested
        return true
    }
    terminal_process_close_begin_fallback(coordinator, manager, registry)
    return true
}

// Request forced termination and transfer immediately on backend failure.
terminal_process_close_force :: proc(
    coordinator: ^Terminal_Process_Close_Coordinator,
    manager: ^Terminal_Session_Manager,
    registry: ^Process_Cleanup_Registry) -> Terminal_Session_Update {
    rejection := terminal_session_signal(manager, {
        owner = manager.operation.owner,
        operation_id = manager.operation.id,
        signal = .Force_Terminate,
    })
    coordinator.phase = .Force_Requested
    if rejection == .None {
        return {}
    }
    update := terminal_process_close_transfer_update(
        manager, registry, coordinator)
    if coordinator.phase != .Transferred {
        coordinator.phase = .Force_Requested
    }
    return update
}

//   Emit one infrastructure completion after exceptional backend transfer.
terminal_process_close_transfer_update :: proc(
    manager: ^Terminal_Session_Manager,
    registry: ^Process_Cleanup_Registry,
    coordinator: ^Terminal_Process_Close_Coordinator) -> Terminal_Session_Update {
    update: Terminal_Session_Update
    operation := manager.operation
    if !manager.backend.transfer(
        manager.backend.user_data, registry, coordinator.generation) {
        return update
    }
    update.completion = {
        request_id = operation.request_id,
        owner = operation.owner,
        operation_id = operation.id,
        kind = .Infrastructure_Failure,
    }
    update.completion_available = true
    manager.operation = {}
    manager.input_target = .Julia_Repl
    coordinator.phase = .Transferred
    return update
}

//   Advance one close step using caller-supplied monotonic time.
//
// Returns:
//   - Bounded output and at most one final completion from this close attempt.
terminal_process_close_advance :: proc(
    coordinator: ^Terminal_Process_Close_Coordinator,
    manager: ^Terminal_Session_Manager,
    registry: ^Process_Cleanup_Registry,
    now_ns: u64) -> Terminal_Session_Update {
    if coordinator == nil || manager == nil || registry == nil ||
       coordinator.phase == .None || coordinator.phase == .Complete ||
       coordinator.phase == .Transferred {
        return {}
    }
    update := terminal_session_update(manager)
    if update.completion_available {
        coordinator.phase = .Complete
        return update
    }
    if update.process_exited && !update.output_drained {
        coordinator.phase = .Reaping
    }
    if now_ns >= coordinator.final_deadline_ns {
        transferred := terminal_process_close_transfer_update(
            manager, registry, coordinator)
        transferred.output = update.output
        transferred.output_count = update.output_count
        return transferred
    }
    if coordinator.phase == .Graceful_Requested &&
       now_ns >= coordinator.graceful_deadline_ns {
        forced := terminal_process_close_force(coordinator, manager, registry)
        forced.output = update.output
        forced.output_count = update.output_count
        return forced
    }
    return update
}

//   Close an active backend during application teardown.
//
// Parameters:
//   - manager: Session registry to tear down; nil/inactive is a no-op.
//
// Side effects:
//   - Closes backend resources without emitting completion, clears the operation, and
//     routes input back to Julia. The registered owner and generation source remain.
terminal_session_destroy :: proc(manager: ^Terminal_Session_Manager) {
    if manager == nil || manager.operation.state == .Inactive {
        return
    }
    log.warnf(
        "terminal session closed during teardown request_id=%d owner_id=%d owner_generation=%d operation_slot=%d operation_generation=%d state=%v",
        manager.operation.request_id, manager.operation.owner.id,
        manager.operation.owner.generation, manager.operation.id.slot,
        manager.operation.id.generation, manager.operation.state)
    manager.backend.close(manager.backend.user_data)
    manager.operation = {}
    manager.input_target = .Julia_Repl
}