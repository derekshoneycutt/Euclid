package operations

import modifier "../animation"
import geometry "../core/geometry"
import math "core:math"

ACTIVE_OPERATION_SLOT_COUNT :: 16
ACTIVE_OPERATION_PAYLOAD_BYTES :: 64
ACTIVE_OPERATION_TARGET_BYTES :: 64
ACTIVE_OPERATION_SCRATCH_BYTES :: 512
ACTIVE_OPERATION_CLAIMS_PER_SLOT :: 24
ACTIVE_OPERATION_SUBMISSIONS_PER_BATCH :: 8
ACTIVE_OPERATION_GROUP_TARGET_CAPACITY :: 16
ACTIVE_OPERATION_POLYGON_TRACE_VERTEX_CAPACITY :: 5
ACTIVE_OPERATION_KIND_MODIFIER :: 1
ACTIVE_OPERATION_KIND_GROUP_TRANSFORM :: 2
ACTIVE_OPERATION_KIND_POLYGON_TRACE :: 3
ACTIVE_OPERATION_CLAIM_ENTITY :: u16(1)

Active_Operation_Status :: enum u8 {
    Ok,
    Invalid_Argument,
    Invalid_Handle,
    Not_Reserved,
    Execution_Full,
    Payload_Full,
    Target_Full,
    Claim_Full,
    Control_Full,
    Outcome_Full,
    Identity_Exhausted,
    Conflict,
    Admission_Rejected,
}

Active_Operation_State :: enum u8 {
    Free,
    Reserved,
    Live,
}

Active_Operation_Outcome_State :: enum u8 {
    None,
    Committed,
    Rejected,
    Cancelled,
}

Active_Operation_Payload :: struct {
    kind: u16,
    bytes: [ACTIVE_OPERATION_PAYLOAD_BYTES]u8,
    modifier_request: modifier.Modifier_Request,
}

// One activation-time point captured by a bounded rigid-transform operation.
Active_Operation_Group_Target :: struct {
    entity: u64,
    start_position: geometry.Vector3,
}

// Immutable group inputs copied from Julia into one atomic active operation.
Active_Operation_Group_Transform :: struct {
    count: int,
    targets: [ACTIVE_OPERATION_GROUP_TARGET_CAPACITY]Active_Operation_Group_Target,
    orientation_entity: u64,
    orientation: [4]f32,
    oriented: bool,
}

// Immutable ordered polygon points copied into the native operation owner.
Active_Operation_Polygon_Trace :: modifier.Polygon_Trace

Active_Operation_Target :: struct {
    kind: u16,
    bytes: [ACTIVE_OPERATION_TARGET_BYTES]u8,
    group_transform: Active_Operation_Group_Transform,
    polygon_trace: Active_Operation_Polygon_Trace,
}

Active_Operation_Claim :: struct {
    kind: u16,
    identity: u64,
}

// Fixed-capacity input for one atomic copied modifier admission.
Active_Operation_Submission_Request :: struct {
    kind: u16,
    request_id: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    modifier_request: modifier.Modifier_Request,
    group_transform: Active_Operation_Group_Transform,
    polygon_trace: Active_Operation_Polygon_Trace,
    claim_count: int,
    claims: [ACTIVE_OPERATION_CLAIMS_PER_SLOT]Active_Operation_Claim,
}

// Accepted execution progress and its copied immutable modifier recipe.
Active_Operation_Progress :: struct {
    modifier_request: modifier.Modifier_Request,
    group_transform: Active_Operation_Group_Transform,
    polygon_trace: Active_Operation_Polygon_Trace,
    elapsed: f64,
    duration: f64,
}

Active_Operation_Handle :: struct {
    index: u16,
    generation: u64,
}

Active_Operation_Outcome_Handle :: struct {
    index: u16,
    generation: u64,
}

Active_Operation_Outcome_Identity :: struct {
    request_id: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    outcome_generation: u64,
}

Active_Operation_Reservation :: struct {
    execution: Active_Operation_Handle,
    outcome: Active_Operation_Outcome_Handle,
}

Active_Operation_Reservation_Locators :: struct {
    execution_index: int,
    payload_index: int,
    target_index: int,
    claim_index: int,
    control_index: int,
}

Active_Operation_Reservation_Request :: struct {
    kind: u16,
    request_id: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    modifier_request: modifier.Modifier_Request,
    group_transform: Active_Operation_Group_Transform,
    polygon_trace: Active_Operation_Polygon_Trace,
    claim_count: int,
    claims: [ACTIVE_OPERATION_CLAIMS_PER_SLOT]Active_Operation_Claim,
    outcome_handle: Active_Operation_Outcome_Handle,
}

Active_Operation_Execution_Slot :: struct {
    state: Active_Operation_State,
    generation: u64,
    kind: u16,
    elapsed: f64,
    duration: f64,
    progress_dirty: bool,
    payload_index: u16,
    target_index: u16,
    claim_index: u16,
    control_index: u16,
}

Active_Operation_Payload_Slot :: struct {
    occupied: bool,
    generation: u64,
    payload: Active_Operation_Payload,
}

Active_Operation_Target_Slot :: struct {
    occupied: bool,
    generation: u64,
    target: Active_Operation_Target,
}

Active_Operation_Claim_Slot :: struct {
    occupied: bool,
    generation: u64,
    count: int,
    claims: [ACTIVE_OPERATION_CLAIMS_PER_SLOT]Active_Operation_Claim,
}

Active_Operation_Control_Slot :: struct {
    occupied: bool,
    generation: u64,
    request_id: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    outcome_handle: Active_Operation_Outcome_Handle,
    lifecycle: u16,
}

Active_Operation_Outcome_Slot :: struct {
    occupied: bool,
    generation: u64,
    correlation: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    state: Active_Operation_Outcome_State,
    delivered: bool,
}

Active_Operation_Outcome :: struct {
    handle: Active_Operation_Outcome_Handle,
    request_id: u64,
    session_generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    state: Active_Operation_Outcome_State,
}

Active_Operation_Diagnostics :: struct {
    initialized: bool,
    execution_live: int,
    execution_reserved: int,
    payload_used: int,
    target_used: int,
    claim_used: int,
    control_used: int,
    outcome_used: int,
}

// Fixed display-owned storage for bounded native active operations.
Active_Operation_Storage :: struct {
    execution_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Execution_Slot,
    payload_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Payload_Slot,
    target_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Target_Slot,
    claim_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Claim_Slot,
    control_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Control_Slot,
    outcome_slots: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Outcome_Slot,
    scratch: [ACTIVE_OPERATION_SCRATCH_BYTES]u8,
    initialized: bool,
}

// Initialize the fixed storage in place without allocating backing memory.
active_operation_storage_init :: proc(
    storage: ^Active_Operation_Storage) -> bool {
    if storage == nil {
        return false
    }
    storage^ = {
        initialized = true,
    }
    return true
}

// Release logical records and fixed storage metadata while retaining no live generation.
active_operation_storage_destroy :: proc(storage: ^Active_Operation_Storage) {
    if storage == nil {
        return
    }
    storage^ = {}
}

// Return a bounded snapshot of live, reserved, and cold occupied slots.
active_operation_storage_diagnostics :: proc(
    storage: ^Active_Operation_Storage) -> Active_Operation_Diagnostics {
    if storage == nil || !storage.initialized {
        return {}
    }
    diagnostics: Active_Operation_Diagnostics
    diagnostics.initialized = true
    count_execution_diagnostics(storage, &diagnostics)
    count_payload_diagnostics(storage, &diagnostics)
    count_target_diagnostics(storage, &diagnostics)
    count_claim_diagnostics(storage, &diagnostics)
    count_control_diagnostics(storage, &diagnostics)
    count_outcome_diagnostics(storage, &diagnostics)
    return diagnostics
}

// Advance the execution counts in a bounded diagnostics snapshot.
count_execution_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.execution_slots {
        if slot.state == .Live {
            diagnostics.execution_live += 1
        }
        if slot.state == .Reserved {
            diagnostics.execution_reserved += 1
        }
    }
}

// Count occupied cold payload slots for one bounded diagnostics snapshot.
count_payload_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.payload_slots {
        if slot.occupied {
            diagnostics.payload_used += 1
        }
    }
}

// Count occupied target slots for one bounded diagnostics snapshot.
count_target_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.target_slots {
        if slot.occupied {
            diagnostics.target_used += 1
        }
    }
}

// Count occupied claim slots for one bounded diagnostics snapshot.
count_claim_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.claim_slots {
        if slot.occupied {
            diagnostics.claim_used += 1
        }
    }
}

// Count occupied control slots for one bounded diagnostics snapshot.
count_control_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.control_slots {
        if slot.occupied {
            diagnostics.control_used += 1
        }
    }
}

// Count occupied outcome slots for one bounded diagnostics snapshot.
count_outcome_diagnostics :: proc(
    storage: ^Active_Operation_Storage,
    diagnostics: ^Active_Operation_Diagnostics) {
    for slot in storage.outcome_slots {
        if slot.occupied {
            diagnostics.outcome_used += 1
        }
    }
}

// Increment a slot generation without permitting the zero sentinel.
next_slot_generation :: proc(generation: u64) -> u64 {
    assert(generation < max(u64))
    return generation + 1
}

// Find the first free execution slot by ascending stable index.
find_free_execution :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.execution_slots {
        if slot.state == .Free && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Find the first free payload slot by ascending stable index.
find_free_payload :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.payload_slots {
        if !slot.occupied && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Find the first free target slot by ascending stable index.
find_free_target :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.target_slots {
        if !slot.occupied && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Find the first free claim slot by ascending stable index.
find_free_claim :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.claim_slots {
        if !slot.occupied && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Find the first free control slot by ascending stable index.
find_free_control :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.control_slots {
        if !slot.occupied && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Find the first free outcome slot by ascending stable index.
find_free_outcome :: proc(
    storage: ^Active_Operation_Storage) -> (int, bool) {
    for slot, index in storage.outcome_slots {
        if !slot.occupied && slot.generation < max(u64) {
            return index, true
        }
    }
    return 0, false
}

// Reserve a correlated outcome slot independently of execution-slot reuse.
active_operation_reserve_outcome :: proc(
    storage: ^Active_Operation_Storage,
    correlation: u64) -> (Active_Operation_Outcome_Handle, Active_Operation_Status) {
    if storage == nil || !storage.initialized {
        return {}, .Invalid_Argument
    }
    index, found := find_free_outcome(storage)
    if !found {
        return {}, .Identity_Exhausted if has_exhausted_free_outcome(storage) else
            .Outcome_Full
    }

    slot := &storage.outcome_slots[index]
    slot^ = {
        occupied = true,
        generation = next_slot_generation(slot.generation),
        correlation = correlation,
        state = .None,
        delivered = false,
    }
    return {
        index = u16(index),
        generation = slot.generation,
    }, .Ok
}

// Distinguish exhausted outcome identities from ordinary capacity pressure.
has_exhausted_free_outcome :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.outcome_slots {
        if !slot.occupied && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Reserve each cold region in one bounded admission transaction.
active_operation_reserve_locators :: proc(
    storage: ^Active_Operation_Storage,
    locators: ^Active_Operation_Reservation_Locators) -> Active_Operation_Status {
    if storage == nil || !storage.initialized {
        return .Invalid_Argument
    }
    execution_index, found := find_free_execution(storage)
    if !found {
        return .Identity_Exhausted if has_exhausted_free_execution(storage) else
            .Execution_Full
    }
    payload_index, payload_found := find_free_payload(storage)
    if !payload_found {
        return .Identity_Exhausted if has_exhausted_free_payload(storage) else
            .Payload_Full
    }
    target_index, target_found := find_free_target(storage)
    if !target_found {
        return .Identity_Exhausted if has_exhausted_free_target(storage) else .Target_Full
    }
    claim_index, claim_found := find_free_claim(storage)
    if !claim_found {
        return .Identity_Exhausted if has_exhausted_free_claim(storage) else .Claim_Full
    }
    control_index, control_found := find_free_control(storage)
    if !control_found {
        return .Identity_Exhausted if has_exhausted_free_control(storage) else
            .Control_Full
    }
    locators^ = {
        execution_index = execution_index,
        payload_index = payload_index,
        target_index = target_index,
        claim_index = claim_index,
        control_index = control_index,
    }
    return .Ok
}

// Detect exhausted execution identities when no reusable slot remains.
has_exhausted_free_execution :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.execution_slots {
        if slot.state == .Free && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Detect exhausted payload identities when no reusable slot remains.
has_exhausted_free_payload :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.payload_slots {
        if !slot.occupied && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Detect exhausted target identities when no reusable slot remains.
has_exhausted_free_target :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.target_slots {
        if !slot.occupied && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Detect exhausted claim identities when no reusable slot remains.
has_exhausted_free_claim :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.claim_slots {
        if !slot.occupied && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Detect exhausted control identities when no reusable slot remains.
has_exhausted_free_control :: proc(storage: ^Active_Operation_Storage) -> bool {
    for slot in storage.control_slots {
        if !slot.occupied && slot.generation == max(u64) {
            return true
        }
    }
    return false
}

// Populate all previously checked reservation slots and return their handles.
active_operation_initialize_reservation :: proc(
    storage: ^Active_Operation_Storage,
    locators: Active_Operation_Reservation_Locators,
    request: Active_Operation_Reservation_Request) -> Active_Operation_Reservation {
    execution_index := locators.execution_index
    execution := &storage.execution_slots[execution_index]
    execution^ = {
        state = .Reserved,
        generation = next_slot_generation(execution.generation),
        kind = request.kind,
        duration = f64(request.modifier_request.duration),
        payload_index = u16(locators.payload_index),
        target_index = u16(locators.target_index),
        claim_index = u16(locators.claim_index),
        control_index = u16(locators.control_index),
    }
    active_operation_initialize_cold_slots(storage, locators, request)
    active_operation_initialize_control_slot(storage, locators, request)
    return {
        execution = {
            index = u16(execution_index),
            generation = execution.generation,
        },
        outcome = request.outcome_handle,
    }
}

// Initialize reusable payload, target, and claim records from checked locators.
active_operation_initialize_cold_slots :: proc(
    storage: ^Active_Operation_Storage,
    locators: Active_Operation_Reservation_Locators,
    request: Active_Operation_Reservation_Request) {
    payload := &storage.payload_slots[locators.payload_index]
    payload^ = {
        occupied = true,
        generation = next_slot_generation(payload.generation),
    }
    target := &storage.target_slots[locators.target_index]
    target^ = {
        occupied = true,
        generation = next_slot_generation(target.generation),
        target = {
            group_transform = request.group_transform,
            polygon_trace = request.polygon_trace,
        },
    }
    claim := &storage.claim_slots[locators.claim_index]
    claim^ = {
        occupied = true,
        generation = next_slot_generation(claim.generation),
        count = request.claim_count,
        claims = request.claims,
    }
}

// Initialize correlated lifecycle controls for one reserved execution.
active_operation_initialize_control_slot :: proc(
    storage: ^Active_Operation_Storage,
    locators: Active_Operation_Reservation_Locators,
    request: Active_Operation_Reservation_Request) {
    control := &storage.control_slots[locators.control_index]
    control^ = {
        occupied = true,
        generation = next_slot_generation(control.generation),
        request_id = request.request_id,
        session_generation = request.session_generation,
        runtime_generation = request.runtime_generation,
        animation_generation = request.animation_generation,
        outcome_handle = request.outcome_handle,
    }
    storage.payload_slots[locators.payload_index].payload = {
        kind = request.kind,
        modifier_request = request.modifier_request,
    }
}

// Reserve execution, cold records, controls, and outcome in one transaction.
active_operation_reserve :: proc(
    storage: ^Active_Operation_Storage,
    kind: u16,
    request_id: u64,
    session_generation: u64) -> (Active_Operation_Reservation, Active_Operation_Status) {
    locators: Active_Operation_Reservation_Locators
    locator_status :=
        active_operation_reserve_locators(storage, &locators)
    if locator_status != .Ok {
        return {}, locator_status
    }
    outcome_handle, outcome_status :=
        active_operation_reserve_outcome(storage, request_id)
    if outcome_status != .Ok {
        return {}, outcome_status
    }
    reservation := active_operation_initialize_reservation(
        storage, locators, {
            kind = kind,
            request_id = request_id,
            session_generation = session_generation,
            outcome_handle = outcome_handle,
        })
    return reservation, .Ok
}

// Reserve copied modifier inputs, claims, execution, and outcome as one operation.
active_operation_reserve_modifier :: proc(
    storage: ^Active_Operation_Storage,
    submission: Active_Operation_Submission_Request) -> (
        Active_Operation_Reservation, Active_Operation_Status) {
    if !active_operation_modifier_request_valid(storage, submission) {
        return {}, .Invalid_Argument
    }
    if !active_operation_request_identity_unique(storage, submission.request_id) {
        return {}, .Conflict
    }
    locators: Active_Operation_Reservation_Locators
    locator_status := active_operation_reserve_locators(storage, &locators)
    if locator_status != .Ok {
        return {}, locator_status
    }
    outcome_handle, outcome_status := active_operation_reserve_outcome(
        storage, submission.request_id)
    if outcome_status != .Ok {
        return {}, outcome_status
    }
    return active_operation_initialize_modifier_reservation(
        storage, locators, outcome_handle, submission), .Ok
}

// Validate typed input and all external identity fields before reservation.
active_operation_modifier_request_valid :: proc(
    storage: ^Active_Operation_Storage,
    submission: Active_Operation_Submission_Request) -> bool {
    if storage == nil || !storage.initialized || submission.kind == 0 ||
        submission.request_id == 0 || submission.session_generation == 0 ||
        submission.runtime_generation == 0 || submission.animation_generation == 0 ||
        submission.claim_count <= 0 ||
        submission.claim_count > ACTIVE_OPERATION_CLAIMS_PER_SLOT {
        return false
    }
    claim_values := submission.claims
    claims := claim_values[:submission.claim_count]
    return active_operation_submission_payload_valid(submission, claims)
}

// Validate the typed operation payload against the copied claim set.
active_operation_submission_payload_valid :: proc(
    submission: Active_Operation_Submission_Request,
    claims: []Active_Operation_Claim) -> bool {
    if submission.kind == ACTIVE_OPERATION_KIND_GROUP_TRANSFORM {
        return modifier.modifier_request_valid(submission.modifier_request) &&
            active_operation_group_transform_valid(
                submission.group_transform, submission.modifier_request) &&
            active_operation_claim_set_valid(claims) &&
            active_operation_group_claims_covered(submission.group_transform, claims)
    }
    if submission.kind == ACTIVE_OPERATION_KIND_POLYGON_TRACE {
        return modifier.modifier_request_valid(submission.modifier_request) &&
            submission.modifier_request.kind == .Identity &&
            submission.modifier_request.entity != 0 &&
            submission.modifier_request.duration > 0 &&
            submission.group_transform.count == 0 &&
            active_operation_polygon_trace_valid(submission.polygon_trace) &&
            active_operation_claim_set_valid(claims) &&
            active_operation_polygon_claims_covered(
                submission.modifier_request.entity, submission.polygon_trace, claims)
    }
    if submission.kind != ACTIVE_OPERATION_KIND_MODIFIER ||
        submission.group_transform.count != 0 || submission.polygon_trace.count != 0 {
        return false
    }
    return modifier.modifier_request_valid(submission.modifier_request) &&
        active_operation_claim_set_valid(claims) &&
        active_operation_claims_cover_modifier(submission.modifier_request, claims)
}

// Validate the ordered, bounded polygon targets retained by a native trace.
active_operation_polygon_trace_valid :: proc(
    trace: Active_Operation_Polygon_Trace) -> bool {
    if trace.count < 3 || trace.count > ACTIVE_OPERATION_POLYGON_TRACE_VERTEX_CAPACITY {
        return false
    }
    z := trace.vertices[0].position.z
    twice_area := f64(0)
    for index in 0..<trace.count {
        current := trace.vertices[index]
        next := trace.vertices[(index + 1) % trace.count]
        if current.entity == 0 || !active_operation_position_finite(current.position) ||
            current.position.z != z {
            return false
        }
        for earlier in 0..<index {
            previous := trace.vertices[earlier]
            if previous.entity == current.entity ||
                previous.position == current.position {
                return false
            }
        }
        twice_area += f64(current.position.x) * f64(next.position.y) -
            f64(next.position.x) * f64(current.position.y)
    }
    return twice_area != 0
}

// Require a claim for the polygon host and every ordered defining point.
active_operation_polygon_claims_covered :: proc(
    host: u64, trace: Active_Operation_Polygon_Trace,
    claims: []Active_Operation_Claim) -> bool {
    if !active_operation_claim_set_contains(claims, host) {
        return false
    }
    vertices := trace.vertices
    for vertex in vertices[:trace.count] {
        if !active_operation_claim_set_contains(claims, vertex.entity) {
            return false
        }
    }
    return true
}

// Validate the bounded activation snapshot and optional analytic orientation.
active_operation_group_transform_valid :: proc(
    group: Active_Operation_Group_Transform,
    request: modifier.Modifier_Request) -> bool {
    if group.count <= 0 || group.count > ACTIVE_OPERATION_GROUP_TARGET_CAPACITY ||
        (request.kind != .Translate_Point && request.kind != .Rotate_Point &&
         request.kind != .Reflect_Point_Xy_Above &&
         request.kind != .Reflect_Point_Xy_Below) {
        return false
    }
    if group.targets[0].entity != request.entity ||
        group.targets[0].start_position != request.start_position {
        return false
    }
    for index in 0..<group.count {
        target := group.targets[index]
        if target.entity == 0 ||
            !active_operation_position_finite(target.start_position) {
            return false
        }
        for earlier in 0..<index {
            if group.targets[earlier].entity == target.entity {
                return false
            }
        }
    }
    return active_operation_group_orientation_valid(group)
}

// Require a normalized analytic orientation only when the host rotates with the group.
active_operation_group_orientation_valid :: proc(
    group: Active_Operation_Group_Transform) -> bool {
    if !group.oriented {
        return group.orientation_entity == 0
    }
    if group.orientation_entity == 0 {
        return false
    }
    length_squared := f32(0)
    for component in group.orientation {
        if math.is_nan(component) || math.is_inf(component) {
            return false
        }
        length_squared += component * component
    }
    return math.abs(length_squared - 1) <= 1e-3
}

// Reject non-finite activation positions before they reach native scene commands.
active_operation_position_finite :: proc(position: geometry.Vector3) -> bool {
    for component in position {
        if math.is_nan(component) || math.is_inf(component) {
            return false
        }
    }
    return true
}

// Require claims for every target and the optional analytic host.
active_operation_group_claims_covered :: proc(
    group: Active_Operation_Group_Transform,
    claims: []Active_Operation_Claim) -> bool {
    for index in 0..<group.count {
        target := group.targets[index]
        if !active_operation_claim_set_contains(claims, target.entity) {
            return false
        }
    }
    return active_operation_claim_set_contains(claims, group.orientation_entity)
}

// Expand one copied rigid transform into an ordered atomic scene sample.
active_operation_group_sample_requests :: proc(
    group: Active_Operation_Group_Transform,
    template: modifier.Modifier_Request, elapsed: f32,
    requests: ^[ACTIVE_OPERATION_GROUP_TARGET_CAPACITY + 1]modifier.Modifier_Request,
    request_count: ^int) -> bool {
    if requests == nil || request_count == nil ||
        group.count <= 0 || group.count > ACTIVE_OPERATION_GROUP_TARGET_CAPACITY {
        return false
    }
    request_count^ = 0
    for index in 0..<group.count {
        target := group.targets[index]
        request := template
        request.entity = target.entity
        request.start_position = target.start_position
        request.elapsed = elapsed
        requests[request_count^] = request
        request_count^ += 1
    }
    if group.oriented {
        orientation := template
        orientation.kind = .Rotate_Shape_Orientation
        orientation.entity = group.orientation_entity
        orientation.displacement = {
            group.orientation[0],
            group.orientation[1],
            group.orientation[2],
        }
        orientation.scalar = group.orientation[3]
        orientation.elapsed = elapsed
        requests[request_count^] = orientation
        request_count^ += 1
    }
    return true
}

// Require claims for modifier entities and resolved compass joints.
active_operation_claims_cover_modifier :: proc(
    request: modifier.Modifier_Request,
    claims: []Active_Operation_Claim) -> bool {
    if request.kind == .Pen_Highlight {
        return len(claims) >= 2
    }
    if request.kind == .Compass_Highlight_Sequence {
        return len(claims) >= 2
    }
    if request.kind == .Construct_Circle ||
        request.kind == .Construct_Filled_Circle {
        // Circle endpoint values are tool sentinels; the caller claims both joints.
        return active_operation_claim_set_contains(claims, request.entity) &&
            len(claims) >= 3
    }
    return active_operation_claim_set_contains(claims, request.entity) &&
        active_operation_claim_set_contains(claims, request.second_entity) &&
        active_operation_claim_set_contains(claims, request.third_entity)
}

// Find one nonzero modifier entity in its bounded claim set.
active_operation_claim_set_contains :: proc(
    claims: []Active_Operation_Claim, entity: u64) -> bool {
    if entity == 0 {
        return true
    }
    for claim in claims {
        if claim.identity == entity {
            return true
        }
    }
    return false
}

// Copy the recipe and claims into previously checked slots without further failure.
active_operation_initialize_modifier_reservation :: proc(
    storage: ^Active_Operation_Storage,
    locators: Active_Operation_Reservation_Locators,
    outcome_handle: Active_Operation_Outcome_Handle,
    submission: Active_Operation_Submission_Request) -> Active_Operation_Reservation {
    claim_values: [ACTIVE_OPERATION_CLAIMS_PER_SLOT]Active_Operation_Claim
    submitted_claims := submission.claims
    copy(claim_values[:], submitted_claims[:submission.claim_count])
    reservation := active_operation_initialize_reservation(
        storage, locators, {
            kind = submission.kind,
            request_id = submission.request_id,
            session_generation = submission.session_generation,
            runtime_generation = submission.runtime_generation,
            animation_generation = submission.animation_generation,
            modifier_request = submission.modifier_request,
            group_transform = submission.group_transform,
            polygon_trace = submission.polygon_trace,
            claim_count = submission.claim_count,
            claims = claim_values,
            outcome_handle = outcome_handle,
        })
    outcome := &storage.outcome_slots[outcome_handle.index]
    outcome^.session_generation = submission.session_generation
    outcome^.runtime_generation = submission.runtime_generation
    outcome^.animation_generation = submission.animation_generation
    return reservation
}

// Validate a copied bounded claim set and reject duplicate or empty identities.
active_operation_claim_set_valid :: proc(
    claims: []Active_Operation_Claim) -> bool {
    for claim, index in claims {
        if claim.kind == 0 || claim.identity == 0 {
            return false
        }
        for earlier in 0..<index {
            if claims[earlier] == claim {
                return false
            }
        }
    }
    return true
}

// Reject duplicate external correlations while any execution or outcome remains live.
active_operation_request_identity_unique :: proc(
    storage: ^Active_Operation_Storage,
    request_id: u64) -> bool {
    for slot in storage.control_slots {
        if slot.occupied && slot.request_id == request_id {
            return false
        }
    }
    for slot in storage.outcome_slots {
        if slot.occupied && slot.correlation == request_id {
            return false
        }
    }
    return true
}

// Test a proposed claim set against every live or reserved operation.
active_operation_claims_conflict :: proc(
    storage: ^Active_Operation_Storage,
    claims: []Active_Operation_Claim,
    excluded: Active_Operation_Handle = {}) -> bool {
    if storage == nil || !storage.initialized {
        return false
    }
    for execution, index in storage.execution_slots {
        if execution.state == .Free ||
            (u16(index) == excluded.index &&
             execution.generation == excluded.generation) {
            continue
        }
        claim_slot := &storage.claim_slots[execution.claim_index]
        if claim_slot.count < 0 ||
            claim_slot.count > ACTIVE_OPERATION_CLAIMS_PER_SLOT {
            return true
        }
        for requested in claims {
            for existing in claim_slot.claims[:claim_slot.count] {
                if requested.kind == existing.kind &&
                    requested.identity == existing.identity {
                    return true
                }
            }
        }
    }
    return false
}

// Check whether one authoritative entity is currently claimed by an operation.
active_operation_entity_claim_conflicts :: proc(
    storage: ^Active_Operation_Storage, entity: u64) -> bool {
    if entity == 0 || storage == nil || !storage.initialized {
        return false
    }
    for execution in storage.execution_slots {
        if execution.state == .Free {
            continue
        }
        claim_slot := &storage.claim_slots[execution.claim_index]
        if claim_slot.count < 0 ||
            claim_slot.count > ACTIVE_OPERATION_CLAIMS_PER_SLOT {
            return true
        }
        for claim in claim_slot.claims[:claim_slot.count] {
            if claim.identity == entity {
                return true
            }
        }
    }
    return false
}

// Return accepted progress and recipe metadata for one current operation handle.
active_operation_observe :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle) -> (Active_Operation_Progress, bool) {
    slot := valid_execution_handle(storage, handle)
    if slot == nil {
        return {}, false
    }
    payload := &storage.payload_slots[slot.payload_index].payload
    target := &storage.target_slots[slot.target_index].target
    return {
        modifier_request = payload.modifier_request,
        group_transform = target.group_transform,
        polygon_trace = target.polygon_trace,
        elapsed = slot.elapsed,
        duration = slot.duration,
    }, true
}

// Accept candidate elapsed time only after its scene transaction has committed.
active_operation_accept_progress :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle,
    elapsed: f64) -> Active_Operation_Status {
    slot := valid_execution_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    if slot.state != .Live || math.is_nan(elapsed) || math.is_inf(elapsed) ||
        elapsed < slot.elapsed ||
        elapsed > slot.duration {
        return .Invalid_Argument
    }
    slot.elapsed = elapsed
    slot.progress_dirty = true
    return .Ok
}

// Copy one terminal outcome without releasing its delivery reservation.
active_operation_read_outcome :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle) -> (
        Active_Operation_Outcome, Active_Operation_Status) {
    slot := valid_outcome_handle(storage, handle)
    if slot == nil {
        return {}, .Invalid_Handle
    }
    if slot.state == .None {
        return {}, .Invalid_Argument
    }
    return {
        handle = handle,
        request_id = slot.correlation,
        session_generation = slot.session_generation,
        runtime_generation = slot.runtime_generation,
        animation_generation = slot.animation_generation,
        state = slot.state,
    }, .Ok
}

// Cancel a live operation, releasing claims but preserving its correlated outcome.
active_operation_cancel :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle) -> Active_Operation_Status {
    slot := valid_execution_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    outcome_handle := storage.control_slots[slot.control_index].outcome_handle
    status := active_operation_publish_outcome(storage, outcome_handle, .Cancelled)
    if status != .Ok {
        return status
    }
    return active_operation_release_execution(storage, handle)
}

// Retire a generation only after its lifecycle transaction has committed.
active_operation_retire_animation_generation :: proc(
    storage: ^Active_Operation_Storage, animation_generation: u64) {
    if storage == nil || !storage.initialized || animation_generation == 0 {
        return
    }
    for slot, index in storage.execution_slots {
        if slot.state == .Free ||
            storage.control_slots[slot.control_index].animation_generation !=
                animation_generation {
            continue
        }
        _ = active_operation_cancel(storage, {
            index = u16(index),
            generation = slot.generation,
        })
    }
}

// Retire one Terminal session's operations after the close boundary commits.
active_operation_retire_session :: proc(
    storage: ^Active_Operation_Storage, session_generation: u64) {
    if storage == nil || !storage.initialized || session_generation == 0 {
        return
    }
    for slot, index in storage.execution_slots {
        if slot.state == .Free ||
            storage.control_slots[slot.control_index].session_generation !=
                session_generation {
            continue
        }
        _ = active_operation_cancel(storage, {
            index = u16(index),
            generation = slot.generation,
        })
    }
}

// Resolve a live execution handle without accepting stale generations.
valid_execution_handle :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle) -> ^Active_Operation_Execution_Slot {
    if storage == nil || !storage.initialized ||
        int(handle.index) >= ACTIVE_OPERATION_SLOT_COUNT {
        return nil
    }
    slot := &storage.execution_slots[handle.index]
    if slot.state == .Free || slot.generation != handle.generation {
        return nil
    }
    return slot
}

// Mark a reserved execution slot live after admission.
active_operation_admit :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle) -> Active_Operation_Status {
    slot := valid_execution_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    if slot.state != .Reserved {
        return .Not_Reserved
    }
    slot.state = .Live
    slot.progress_dirty = true
    return .Ok
}

// Release execution and cold control slots without discarding a live outcome.
active_operation_release_execution :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Handle) -> Active_Operation_Status {
    slot := valid_execution_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    if !active_operation_clear_execution_sidecars(storage, slot) {
        return .Invalid_Handle
    }
    slot^ = {
        state = .Free,
        generation = slot.generation,
    }
    return .Ok
}

// Release cold records while preserving each independent slot generation.
active_operation_clear_execution_sidecars :: proc(
    storage: ^Active_Operation_Storage,
    slot: ^Active_Operation_Execution_Slot) -> bool {
    payload_index := int(slot.payload_index)
    target_index := int(slot.target_index)
    claim_index := int(slot.claim_index)
    control_index := int(slot.control_index)
    if payload_index >= ACTIVE_OPERATION_SLOT_COUNT ||
        target_index >= ACTIVE_OPERATION_SLOT_COUNT ||
        claim_index >= ACTIVE_OPERATION_SLOT_COUNT ||
        control_index >= ACTIVE_OPERATION_SLOT_COUNT {
        return false
    }
    if !storage.payload_slots[payload_index].occupied ||
        !storage.target_slots[target_index].occupied ||
        !storage.claim_slots[claim_index].occupied ||
        !storage.control_slots[control_index].occupied {
        return false
    }
    payload_generation := storage.payload_slots[payload_index].generation
    target_generation := storage.target_slots[target_index].generation
    claim_generation := storage.claim_slots[claim_index].generation
    control_generation := storage.control_slots[control_index].generation
    storage.payload_slots[payload_index] = {
        generation = payload_generation,
    }
    storage.target_slots[target_index] = {
        generation = target_generation,
    }
    storage.claim_slots[claim_index] = {
        generation = claim_generation,
    }
    storage.control_slots[control_index] = {
        generation = control_generation,
    }
    return true
}

// Resolve an occupied outcome handle without accepting stale generations.
valid_outcome_handle :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle) -> ^Active_Operation_Outcome_Slot {
    if storage == nil || !storage.initialized ||
        int(handle.index) >= ACTIVE_OPERATION_SLOT_COUNT {
        return nil
    }
    slot := &storage.outcome_slots[handle.index]
    if !slot.occupied || slot.generation != handle.generation {
        return nil
    }
    return slot
}

// Publish a terminal outcome and preserve it until explicit consumer delivery.
active_operation_publish_outcome :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle,
    outcome: Active_Operation_Outcome_State) -> Active_Operation_Status {
    slot := valid_outcome_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    if outcome == .None {
        return .Invalid_Argument
    }
    if slot.state != .None {
        return .Conflict
    }
    slot.state = outcome
    return .Ok
}

// Mark one published outcome in flight without releasing its independent slot.
active_operation_mark_outcome_sent :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle) -> Active_Operation_Status {
    slot := valid_outcome_handle(storage, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    if slot.state == .None {
        return .Invalid_Argument
    }
    slot.delivered = true
    return .Ok
}

// Release one in-flight outcome only after its consumer acknowledges receipt.
active_operation_acknowledge_outcome :: proc(
    storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle) -> Active_Operation_Status {
    slot := valid_outcome_handle(storage, handle)
    if slot == nil || !slot.delivered {
        return .Invalid_Handle
    }
    slot^ = {
        occupied = false,
        generation = slot.generation,
    }
    return .Ok
}

// Resolve a receipt by its full copied correlation identity, not its reused slot.
active_operation_acknowledge_outcome_identity :: proc(
    storage: ^Active_Operation_Storage,
    identity: Active_Operation_Outcome_Identity) -> Active_Operation_Status {
    if storage == nil || !storage.initialized || identity.request_id == 0 ||
        identity.session_generation == 0 || identity.runtime_generation == 0 ||
        identity.animation_generation == 0 || identity.outcome_generation == 0 {
        return .Invalid_Argument
    }
    for slot, index in storage.outcome_slots {
        if !slot.occupied || slot.correlation != identity.request_id ||
            slot.session_generation != identity.session_generation ||
            slot.runtime_generation != identity.runtime_generation ||
            slot.animation_generation != identity.animation_generation ||
            slot.generation != identity.outcome_generation {
            continue
        }
        return active_operation_acknowledge_outcome(storage, {
            index = u16(index),
            generation = slot.generation,
        })
    }
    return .Invalid_Handle
}
