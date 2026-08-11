package bridge

import "base:runtime"
import "../core"
import "../trace"
import "core:os"
import "core:sync/chan"
import "core:thread"
import "core:time"

// Julia_Runtime_Service is a single-owner command processor around the embedded Julia
// runtime. The display thread submits bounded requests and consumes typed events; only
// the persistent worker may call Julia. Snapshot and tick slots retain payloads outside
// the channels so event draining never determines whether completed data survives.

JULIA_REQUEST_CAPACITY :: core.JULIA_REQUEST_CAPACITY
JULIA_EVENT_CAPACITY :: core.JULIA_EVENT_CAPACITY
SCRATCHPAD_ASYNC_SLOT_COUNT :: core.SCRATCHPAD_ASYNC_SLOT_COUNT
SCRATCHPAD_ASYNC_TEXT_CAPACITY :: core.SCRATCHPAD_ASYNC_TEXT_CAPACITY
VIEW_SNAPSHOT_SLOT_COUNT :: core.VIEW_SNAPSHOT_SLOT_COUNT
VIEW_SNAPSHOT_TEXT_CAPACITY :: core.VIEW_SNAPSHOT_TEXT_CAPACITY
ANIMATION_TICK_SLOT_COUNT :: core.ANIMATION_TICK_SLOT_COUNT
MAX_ACCUMULATED_ANIMATION_DT :: f32(0.25)

// Core owns service storage because Euclid_General_State holds a concrete service pointer.
// This package owns queue policy, worker behavior, publication, and lifecycle transitions.
Julia_Request_Kind :: core.Julia_Request_Kind
Julia_Event_Kind :: core.Julia_Event_Kind
Animation_Tick_Slot_State :: core.Animation_Tick_Slot_State
Animation_Tick_Slot :: core.Animation_Tick_Slot

View_Snapshot_Slot_State :: core.View_Snapshot_Slot_State
View_Snapshot :: core.View_Snapshot
Scratchpad_Async_Kind :: core.Scratchpad_Async_Kind
Scratchpad_Async_Slot_State :: core.Scratchpad_Async_Slot_State
Scratchpad_Async_Slot :: core.Scratchpad_Async_Slot
Scratchpad_Input_Mode :: core.Scratchpad_Input_Mode
Julia_Lifecycle_State :: core.Julia_Lifecycle_State
Julia_Reload_State :: core.Julia_Reload_State
Julia_Task_Proc :: core.Julia_Task_Proc
Julia_Request :: core.Julia_Request
Julia_Event :: core.Julia_Event
Julia_Runtime_Service :: core.Julia_Runtime_Service

Animation_Tick_Diagnostics :: struct {
    queue_depth: u64,
    queue_high_water: u64,
    submitted: u64,
    committed: u64,
    coalesced: u64,
    stale: u64,
    dropped: u64,
    last_committed_sequence: u64,
    last_latency_ms: f64,
    max_latency_ms: f64,
}

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

//   Return display-safe asynchronous animation pacing diagnostics.
// Queue depth is represented by the single replaceable in-flight tick; accumulated time
// and fixed slot contents remain implementation details of the service.
animation_tick_diagnostics :: proc(
    state: ^core.Euclid_General_State) -> Animation_Tick_Diagnostics {

    if state == nil || state^.julia_runtime_service == nil {
        return {}
    }
    service := state^.julia_runtime_service
    return Animation_Tick_Diagnostics{
        queue_depth = u64(service^.animation_tick_pending ? 1 : 0),
        queue_high_water = service^.animation_queue_high_water,
        submitted = service^.animation_ticks_submitted,
        committed = service^.animation_ticks_committed,
        coalesced = service^.animation_ticks_coalesced,
        stale = service^.animation_ticks_stale,
        dropped = service^.animation_ticks_dropped,
        last_committed_sequence = service^.animation_last_committed_sequence,
        last_latency_ms = service^.animation_last_latency_ms,
        max_latency_ms = service^.animation_max_latency_ms,
    }
}

//   Preserve bounded elapsed time while one replaceable tick is in flight.
// The cap prevents a delayed worker from replaying an unbounded simulation interval when
// it next accepts a tick.
coalesce_animation_tick :: proc(service: ^Julia_Runtime_Service, dt: f32) {
    service^.animation_accumulated_dt = min(
        service^.animation_accumulated_dt + dt, MAX_ACCUMULATED_ANIMATION_DT)
    service^.animation_ticks_coalesced += 1
}

//   Submit one bounded animation tick without blocking the display thread.
// The display thread snapshots query state before submission. On saturation, the slot is
// recycled and elapsed time is retained for the next request instead of partially lost.
try_request_animation_tick :: proc(state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    if service^.animation_tick_pending {
        coalesce_animation_tick(service, dt)
        return false
    }
    slot_index := reserve_animation_tick_slot(service)
    if slot_index < 0 {
        service^.animation_ticks_dropped += 1
        return false
    }

    total_dt := min(dt + service^.animation_accumulated_dt, MAX_ACCUMULATED_ANIMATION_DT)
    service^.animation_accumulated_dt = 0
    service^.animation_tick_sequence += 1
    slot := &service^.animation_tick_slots[slot_index]
    slot^ = Animation_Tick_Slot{
        state = .Pending,
        request_id = service^.next_request_id,
        generation = service^.animation_generation,
        sequence = service^.animation_tick_sequence,
        host_state = state,
        animation = state^.julia_interface^.current_animation,
        dt = total_dt,
        submitted_at = time.tick_now(),
    }
    capture_animation_query_snapshot(state, &slot^.query_snapshot)
    request_id, sent := try_submit_julia_request(
        service, .Animation_Tick, generate_animation_tick_task,
        rawptr(slot), i32(slot_index))
    if !sent {
        slot^.state = .Free
        service^.animation_accumulated_dt = total_dt
        service^.animation_ticks_dropped += 1
        return false
    }
    assert(slot^.request_id == request_id)
    service^.animation_tick_pending = true
    service^.animation_ticks_submitted += 1
    service^.animation_queue_high_water = max(service^.animation_queue_high_water, u64(1))
    return true
}

//   Commit one completed generation-matched animation batch at a frame boundary.
// Event draining updates service metadata, while completed slot storage remains authoritative.
// Every completed slot is recycled after selecting and attempting the newest valid batch.
publish_available_animation_tick :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    for {
        _, ok := try_receive_julia_event(service)
        if !ok {
            break
        }
    }
    slot_index := newest_completed_animation_tick_index(service)
    if slot_index < 0 {
        return false
    }
    slot := &service^.animation_tick_slots[slot_index]
    matches_current := animation_tick_matches_current(state, service, slot)
    committed := false
    reject_reason := ""
    if !matches_current {
        reject_reason = animation_tick_reject_reason(state, service, slot)
    } else if !commit_scene_command_batch(state, &slot^.scene_batch) {
        reject_reason = "invalid_command_batch"
    } else {
        committed = true
    }
    if committed {
        service^.animation_ticks_committed += 1
        service^.animation_last_committed_sequence = slot^.sequence
        latency_ms := time.duration_seconds(time.tick_since(slot^.submitted_at)) * 1000
        service^.animation_last_latency_ms = latency_ms
        service^.animation_max_latency_ms =
            max(service^.animation_max_latency_ms, latency_ms)
        _ = trace.record_animation_event_ex(
            &state^.trace_state,
            "animation.tick_committed",
            service^.animation_generation,
            slot^.sequence,
            "",
            "")
    } else {
        service^.animation_ticks_stale += 1
        _ = trace.record_animation_event_ex(
            &state^.trace_state,
            "animation.tick_rejected",
            service^.animation_generation,
            slot^.sequence,
            "",
            reject_reason)
    }
    release_completed_animation_ticks(service)
    return committed
}

//   Classify why one completed tick was not committed against canonical state.
//
// Parameters:
//   - state: Global runtime state containing current animation selection.
//   - service: Julia runtime service with lifecycle counters.
//   - slot: Completed animation tick slot under evaluation.
//
// Returns:
//   - reason: Stable rejection reason token for trace payload.
animation_tick_reject_reason :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> string {

    if slot == nil || state == nil || state^.julia_interface == nil {
        return "invalid_command_batch"
    }
    if slot^.generation != service^.animation_generation {
        return "stale_generation"
    }
    if slot^.sequence <= service^.animation_last_committed_sequence {
        return "stale_sequence"
    }
    if state^.julia_interface^.pending_animation_reset {
        return "reset_pending"
    }
    if slot^.animation != state^.julia_interface^.current_animation ||
        slot^.animation != state^.julia_interface^.selected_animation {
        return "selection_mismatch"
    }
    return "invalid_command_batch"
}

//   Match one result against current lifecycle generation and selection identity.
// This prevents callbacks started before reset, reload, or selection changes from mutating
// the newly active canonical scene.
animation_tick_matches_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> bool {

    return slot^.generation == service^.animation_generation &&
        slot^.sequence > service^.animation_last_committed_sequence &&
        !state^.julia_interface^.pending_animation_reset &&
        slot^.animation == state^.julia_interface^.current_animation &&
        slot^.animation == state^.julia_interface^.selected_animation
}

//   Reserve free fixed storage for one worker-produced animation result.
// Slots are service-owned and recycled in place; no animation-tick allocation is permitted.
reserve_animation_tick_slot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Find the newest worker completion without relying on event payload retention.
// Older completed sequences may be superseded because only the latest canonical intent is
// useful at the next fixed-step publication boundary.
newest_completed_animation_tick_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_sequence: u64
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Complete && (newest_index < 0 ||
            slot.sequence > newest_sequence) {
            newest_index = slot_index
            newest_sequence = slot.sequence
        }
    }
    return newest_index
}

//   Release all consumed or superseded animation completion slots.
// Pending slots remain worker-owned and must not be recycled by the display thread.
release_completed_animation_ticks :: proc(service: ^Julia_Runtime_Service) {
    for &slot in service^.animation_tick_slots {
        if slot.state == .Complete {
            slot.state = .Free
        }
    }
}

//   Submit one replaceable view generation request without blocking display.
// A published slot remains reserved until a newer valid generation replaces it, while a
// pending request suppresses duplicate work.
try_request_view_snapshot :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := state^.julia_runtime_service
    if service^.view_snapshot_pending {
        return false
    }

    slot_index := reserve_view_snapshot(service)
    if slot_index < 0 {
        return false
    }
    service^.view_snapshot_generation += 1
    slot := &service^.view_snapshots[slot_index]
    slot^ = View_Snapshot{
        state = .Pending,
        request_id = service^.next_request_id,
        generation = service^.view_snapshot_generation,
        runtime_generation = service^.runtime_generation,
        host_state = state,
    }
    request_id, sent := try_submit_julia_request(
        service, .View_Snapshot, generate_view_snapshot_task,
        rawptr(slot), i32(slot_index))
    if !sent {
        slot^.state = .Free
        return false
    }
    assert(slot^.request_id == request_id)
    service^.view_snapshot_pending = true
    return true
}

//   Publish the latest complete semantic snapshot into display-owned dynview.
// Publication copies validated semantic spans, then recycles the previous published slot.
// Invalid or stale generations clear selection-incompatible display content.
publish_available_view_snapshot :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := state^.julia_runtime_service
    for {
        _, ok := try_receive_julia_event(service)
        if !ok {
            break
        }
    }
    slot_index := newest_completed_view_snapshot_index(service)
    if slot_index < 0 {
        clear_stale_published_view(state, service)
        return false
    }

    slot := &service^.view_snapshots[slot_index]
    assert(slot^.state == .Complete)
    release_superseded_completed_view_snapshots(service, slot_index)
    if !view_snapshot_matches_current(state, service, slot) ||
        !view_snapshot_is_valid(slot) {
        slot^.state = .Free
        clear_stale_published_view(state, service)
        return false
    }
    copy_view_snapshot_to_runtime(slot, &state^.dynview)
    if service^.published_view_snapshot_index >= 0 {
        previous := &service^.view_snapshots[service^.published_view_snapshot_index]
        previous^.state = .Free
    }
    slot^.state = .Published
    service^.published_view_snapshot_index = slot_index
    return true
}

//   Find the newest completed slot without relying on event ordering or retention.
// Slot generation is authoritative because completion events only trigger display metadata.
newest_completed_view_snapshot_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_generation: u64
    for &slot, slot_index in service^.view_snapshots {
        if slot.state != .Complete {
            continue
        }
        if newest_index < 0 || slot.generation > newest_generation {
            newest_index = slot_index
            newest_generation = slot.generation
        }
    }
    return newest_index
}

//   Release older complete generations after selecting the newest publication.
// Pending and currently published slots retain their ownership states unchanged.
release_superseded_completed_view_snapshots :: proc(
    service: ^Julia_Runtime_Service, newest_index: int) {

    for &slot, slot_index in service^.view_snapshots {
        if slot_index != newest_index && slot.state == .Complete {
            slot.state = .Free
        }
    }
}

//   Keep previous semantic commands from appearing under a new selection.
// The old slot and display staging are released together so fallback and semantic content
// cannot refer to different animations.
clear_stale_published_view :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service) {

    published_index := service^.published_view_snapshot_index
    if published_index < 0 || state^.julia_interface == nil {
        return
    }
    published := &service^.view_snapshots[published_index]
    if view_snapshot_matches_current(state, service, published) {
        return
    }
    published^.state = .Free
    service^.published_view_snapshot_index = -1
    reset_view_snapshot_staging(&state^.dynview)
}

//   Match one view snapshot against the active interface generation and animation.
// Runtime generation prevents recycled double-buffer addresses from validating stale work.
view_snapshot_matches_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^View_Snapshot) -> bool {

    return state != nil && service != nil && slot != nil &&
        state^.julia_interface != nil && 
        slot^.runtime_generation == service^.runtime_generation &&
        slot^.animation == state^.julia_interface^.current_animation
}

//   Validate all semantic bounds and require a closed, error-free command stream.
// Counts are checked before any slice construction or copy into display-owned storage.
view_snapshot_is_valid :: proc(slot: ^View_Snapshot) -> bool {
    bounds := [5][2]int{
        {slot^.fallback_text_len, len(slot^.fallback_text)},
        {slot^.command_buffer.command_count, core.DYNVIEW__MAX_COMMANDS},
        {slot^.command_buffer.text_bytes_len, core.DYNVIEW__MAX_TEXT_BYTES},
        {slot^.math_program_count, core.DYNVIEW__MAX_MATH_PROGRAMS},
        {slot^.math_command_count, core.DYNVIEW__MAX_MATH_COMMANDS},
    }
    for bound in bounds {
        if bound[0] < 0 || bound[0] > bound[1] {
            return false
        }
    }
    if slot^.math_node_count < 0 ||
        slot^.math_node_count > core.DYNVIEW__MAX_MATH_NODES {
        return false
    }
    return !slot^.command_buffer.has_stream_error &&
        !slot^.command_buffer.stream_open_block
}

//   Return fallback text only when it belongs to the active animation.
// The returned string aliases service-owned published slot storage until replacement.
current_view_snapshot_text :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return ""
    }
    service := state^.julia_runtime_service
    slot_index := service^.published_view_snapshot_index
    if slot_index < 0 {
        return ""
    }
    slot := &service^.view_snapshots[slot_index]
    if !view_snapshot_matches_current(state, service, slot) {
        return ""
    }
    return string(slot^.fallback_text[:slot^.fallback_text_len])
}

//   Return a free snapshot slot that is neither pending nor displayed.
// Published slots are intentionally unavailable even after their semantic data is copied,
// because fallback text still aliases the slot.
reserve_view_snapshot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.view_snapshots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Generate fallback and semantic dynview data into worker staging.
// Runs only on the Julia owner thread. The completed slot contains self-owned copies of all
// populated spans and can be published without consulting Julia.
generate_view_snapshot_task :: proc(data: rawptr) -> bool {
    slot := cast(^View_Snapshot)data
    state := slot^.host_state
    assert_julia_runtime_owner(state)
    service := state^.julia_runtime_service
    staging := service^.dynview_staging
    reset_view_snapshot_staging(staging)

    state^.dynview_emit_target = staging
    fallback := call_current_animation_get_view_text_direct(state)
    state^.dynview_emit_target = nil

    slot^.animation = state^.julia_interface^.current_animation
    slot^.fallback_text_len = min(len(fallback), len(slot^.fallback_text))
    copy(slot^.fallback_text[:slot^.fallback_text_len],
        transmute([]u8)fallback[:slot^.fallback_text_len])
    slot^.command_buffer = staging^.command_buffer
    cache := &staging^.compile_cache
    slot^.math_program_count = cache^.math_program_count
    slot^.math_command_count = cache^.math_command_count
    slot^.math_node_count = cache^.math_node_count
    copy(slot^.math_programs[:slot^.math_program_count],
        cache^.math_programs[:slot^.math_program_count])
    copy(slot^.math_commands[:slot^.math_command_count],
        cache^.math_commands[:slot^.math_command_count])
    copy(slot^.math_nodes[:slot^.math_node_count],
        cache^.math_nodes[:slot^.math_node_count])
    slot^.state = .Complete
    return true
}

//   Reset worker-only semantic emission storage for one generation.
// Capacity remains allocated; only populated lengths, errors, and cache validity are reset.
reset_view_snapshot_staging :: proc(staging: ^core.Dynview_System) {
    staging^.command_buffer.command_count = 0
    staging^.command_buffer.text_bytes_len = 0
    staging^.command_buffer.has_stream_error = false
    staging^.command_buffer.stream_open_block = false
    staging^.command_buffer.stream_open_block_id = -1
    staging^.command_buffer.revision += 1
    staging^.compile_cache.math_program_count = 0
    staging^.compile_cache.math_command_count = 0
    staging^.compile_cache.math_node_count = 0
    staging^.compile_cache.last_error_code = 0
    staging^.compile_cache.is_valid = false
}

//   Install populated semantic spans and invalidate display compilation caches.
// The display thread recompiles and lays out the imported revision before drawing it.
copy_view_snapshot_to_runtime :: proc(
    slot: ^View_Snapshot, runtime: ^core.Dynview_System) {

    runtime^.command_buffer = slot^.command_buffer
    cache := &runtime^.compile_cache
    cache^.math_program_count = slot^.math_program_count
    cache^.math_command_count = slot^.math_command_count
    cache^.math_node_count = slot^.math_node_count
    copy(cache^.math_programs[:slot^.math_program_count],
        slot^.math_programs[:slot^.math_program_count])
    copy(cache^.math_commands[:slot^.math_command_count],
        slot^.math_commands[:slot^.math_command_count])
    copy(cache^.math_nodes[:slot^.math_node_count],
        slot^.math_nodes[:slot^.math_node_count])
    cache^.is_valid = false
    cache^.layout_is_valid = false
    cache^.copy_hit_target_count = 0
    runtime^.pending_invalidation_mask |= 1
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

//   Create the bounded channels, staging storage, and persistent Julia owner worker.
// On partial failure, resources are released in reverse construction order. The caller owns
// the returned service and must stop Julia before destroy_julia_runtime_service.
create_julia_runtime_service :: proc() -> (
    ^Julia_Runtime_Service, runtime.Allocator_Error) {
    service := new(Julia_Runtime_Service)
    requests, request_err := chan.create(
        chan.Chan(Julia_Request), JULIA_REQUEST_CAPACITY, context.allocator)
    if request_err != .None {
        free(service)
        return nil, request_err
    }

    events, event_err := chan.create(
        chan.Chan(Julia_Event), JULIA_EVENT_CAPACITY, context.allocator)
    if event_err != .None {
        _ = chan.destroy(requests)
        free(service)
        return nil, event_err
    }

    service^.requests = requests
    service^.events = events
    service^.next_request_id = 1
    service^.lifecycle = .Not_Started
    service^.dynview_staging = new(core.Dynview_System)
    service^.dynview_staging^.enabled = true
    service^.published_view_snapshot_index = -1
    service^.worker =
        thread.create_and_start_with_data(rawptr(service), julia_runtime_worker)
    if service^.worker == nil {
        free(service^.dynview_staging)
        _ = chan.destroy(events)
        _ = chan.destroy(requests)
        free(service)
        return nil, .Out_Of_Memory
    }

    return service, .None
}

//   Receive one available worker event without blocking the display thread.
// Successful receives also apply lifecycle and slot-completion metadata exactly once.
try_receive_julia_event :: proc(service: ^Julia_Runtime_Service) -> (Julia_Event, bool) {
    if service == nil {
        return {}, false
    }
    event, ok := chan.try_recv(service^.events)
    if ok {
        accept_julia_event(service, event)
    }
    return event, ok
}

//   Submit one lifecycle or compatibility request without blocking the caller.
// Request IDs advance only after successful queue insertion. Saturation is observable through
// diagnostics and leaves caller-owned task payloads untouched for retry or cleanup.
try_submit_julia_request :: proc(
    service: ^Julia_Runtime_Service, kind: Julia_Request_Kind,
    task: Julia_Task_Proc = nil, data: rawptr = nil,
    slot_index: i32 = -1) -> (u64, bool) {

    if service == nil {
        return 0, false
    }

    request_id := service^.next_request_id
    request := Julia_Request{
        kind = kind,
        request_id = request_id,
        task = task,
        data = data,
        slot_index = slot_index,
    }
    if !chan.try_send(service^.requests, request) {
        service^.request_saturation_count += 1
        return 0, false
    }

    service^.next_request_id += 1
    service^.active_request_id = request_id
    service^.active_request_kind = kind
    switch kind {
    case .Initialize:
        service^.lifecycle = .Starting
    case .Shutdown:
        service^.lifecycle = .Shutdown_Requested
    case .Invoke, .Scratchpad, .View_Snapshot, .Animation_Tick:
    }
    return request_id, true
}

//   Apply one worker event to display-owned lifecycle and completion metadata.
// Scratchpad completions enter a bounded FIFO; view and animation events release their
// single-pending submission guards while payload slots retain the completed data.
accept_julia_event :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    if !event.succeeded {
        record_julia_event_failure(service, event)
    }
    if event.request_id == service^.active_request_id {
        service^.active_request_id = 0
    }

    handlers := JULIA_EVENT_HANDLERS
    handler := handlers[event.kind]
    if handler != nil {
        handler(service, event)
    }
}

//   Mark the service stopped when a shutdown completes successfully.
julia_event_on_shutdown :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    if event.succeeded {
        service^.lifecycle = .Stopped
    }
}

//   Record a completed scratchpad slot for the polling consumer.
julia_event_on_scratchpad :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    record_completed_scratchpad_slot(service, event.slot_index)
}

//   Clear the view-snapshot pending flag.
julia_event_on_view_snapshot :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.view_snapshot_pending = false
}

//   Clear the animation-tick pending flag.
julia_event_on_animation_tick :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.animation_tick_pending = false
}

//   Dispatch table mapping each Julia event kind to its completion handler.
//   Initialized and Invoke_Complete need no handler and map to nil.
JULIA_EVENT_HANDLERS ::
    [Julia_Event_Kind]proc(service: ^Julia_Runtime_Service, event: Julia_Event){
    .Initialized = nil,
    .Invoke_Complete = nil,
    .Scratchpad_Complete = julia_event_on_scratchpad,
    .View_Snapshot_Complete = julia_event_on_view_snapshot,
    .Animation_Tick_Complete = julia_event_on_animation_tick,
    .Shutdown_Complete = julia_event_on_shutdown,
}

//   Record a failed Julia event and fail the lifecycle on terminal events.
record_julia_event_failure :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.failed_request_count += 1
    service^.last_failed_request_id = event.request_id
    service^.last_failed_request_kind = event.request_kind
    if event.kind == .Initialized || event.kind == .Shutdown_Complete {
        service^.lifecycle = .Failed
    }
}

//   Enqueue one completed scratchpad slot for the polling consumer.
record_completed_scratchpad_slot :: proc(
    service: ^Julia_Runtime_Service, slot_index: i32) {
    completed_index := (service^.completed_scratchpad_head +
        service^.completed_scratchpad_count) % SCRATCHPAD_ASYNC_SLOT_COUNT
    assert(service^.completed_scratchpad_count < SCRATCHPAD_ASYNC_SLOT_COUNT)
    service^.completed_scratchpad_slots[completed_index] = slot_index
    service^.completed_scratchpad_count += 1
}

//   Publish readiness after startup registration and priming have completed.
// Initialization alone is insufficient: the display may submit normal work only after this.
mark_julia_runtime_ready :: proc(service: ^Julia_Runtime_Service) {
    assert(service != nil && service^.lifecycle == .Starting)
    service^.lifecycle = .Ready
}

//   Assert that Julia work is executing on the persistent owner thread.
// Call this at externally reachable task boundaries before invoking Julia or Julia-backed helpers.
assert_julia_runtime_owner :: proc(state: ^core.Euclid_General_State) {
    assert(state != nil && state^.julia_runtime_service != nil)
    service := state^.julia_runtime_service
    assert(os.get_current_thread_id() == service^.owner_thread_id,
        "Julia C API operation executed outside the Julia owner thread")
}

//   Run one temporary serialized bridge operation on the Julia owner thread.
// Calls made by the owner execute directly; all others block while consuming events until the
// correlated completion arrives. Unrelated events are still accepted during that wait.
invoke_julia_compatibility_task :: proc(
    state: ^core.Euclid_General_State, task: Julia_Task_Proc, data: rawptr) -> bool {

    if state == nil || state^.julia_runtime_service == nil || task == nil {
        return false
    }
    service := state^.julia_runtime_service
    if os.get_current_thread_id() == service^.owner_thread_id {
        return task(data)
    }

    request_id, sent := try_submit_julia_request(service, .Invoke, task, data)
    if !sent {
        return false
    }
    for {
        event, ok := chan.recv(service^.events)
        if !ok {
            return false
        }
        accept_julia_event(service, event)
        if event.kind == .Invoke_Complete && event.request_id == request_id {
            return event.succeeded
        }
    }
}

//   Join the stopped worker and release service-owned channels and staging storage.
// The shutdown request must already have completed; destroying a live worker would violate
// Julia ownership and may leave queued payloads unprocessed.
destroy_julia_runtime_service :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    if service^.worker != nil {
        thread.destroy(service^.worker)
    }
    free(service^.dynview_staging)
    _ = chan.destroy(service^.events)
    _ = chan.destroy(service^.requests)
    free(service)
}

//   Resolve Julia callbacks and register content into unpublished host state.
// This owner-thread task publishes no Ready lifecycle state; startup priming controls that step.
initialize_julia_state_task :: proc(data: rawptr) -> bool {
    state := cast(^core.Euclid_General_State)data
    assert_julia_runtime_owner(state)
    state^.saved_context = context
    prepare_julia_interface_generation(state^.julia_interface)
    if !julia_interface_handles_valid(state^.julia_interface) {
        clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    if !init_euclid_scripts(state) {
        clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    return true
}

//   Own Julia lifecycle and serialized task execution until shutdown.
// Every request produces one correlated event. After each non-shutdown request, the worker
// restores its saved Odin context and clears temporary allocations before receiving more work.
julia_runtime_worker :: proc(data: rawptr) {
    // #vet forgives(cyclomatic_complexity) — single-owner serializing event loop.
    // The switch drives the Julia thread lifecycle; a dispatch table would need a
    // shared-state side channel to carry success/kind back to the loop, which is a
    // worse design for this hot correctness-critical path.
    service := cast(^Julia_Runtime_Service)data
    worker_context := context
    service^.owner_thread_id = os.get_current_thread_id()
    for {
        request, ok := chan.recv(service^.requests)
        if !ok {
            return
        }

        event := Julia_Event{
            request_kind = request.kind,
            request_id = request.request_id,
            slot_index = request.slot_index,
            succeeded = true,
        }
        switch request.kind {
        case .Initialize:
            assert(os.get_current_thread_id() == service^.owner_thread_id)
            event.succeeded = initiate_julia()
            event.kind = .Initialized
        case .Invoke:
            if request.task != nil {
                event.succeeded = request.task(request.data)
            }
            event.kind = .Invoke_Complete
        case .Scratchpad:
            if request.task != nil {
                event.succeeded = request.task(request.data)
            }
            event.kind = .Scratchpad_Complete
        case .View_Snapshot:
            if request.task != nil {
                event.succeeded = request.task(request.data)
            }
            event.kind = .View_Snapshot_Complete
        case .Animation_Tick:
            if request.task != nil {
                event.succeeded = request.task(request.data)
            }
            event.kind = .Animation_Tick_Complete
        case .Shutdown:
            assert(os.get_current_thread_id() == service^.owner_thread_id)
            end_julia()
            event.kind = .Shutdown_Complete
            _ = chan.send(service^.events, event)
            return
        }
        _ = chan.send(service^.events, event)
        context = worker_context
        free_all(context.temp_allocator)
    }
}