package bridge

import "base:runtime"
import "../core"
import "core:os"
import "core:sync/chan"
import "core:thread"
import "core:time"

JULIA_REQUEST_CAPACITY :: 16
JULIA_EVENT_CAPACITY :: 16
SCRATCHPAD_ASYNC_SLOT_COUNT :: 16
SCRATCHPAD_ASYNC_TEXT_CAPACITY :: 4096
VIEW_SNAPSHOT_SLOT_COUNT :: 2
VIEW_SNAPSHOT_TEXT_CAPACITY :: core.DYNVIEW__MAX_TEXT_BYTES
ANIMATION_TICK_SLOT_COUNT :: 2
MAX_ACCUMULATED_ANIMATION_DT :: f32(0.25)

Julia_Request_Kind :: enum {
    Initialize,
    Invoke,
    Scratchpad,
    View_Snapshot,
    Animation_Tick,
    Shutdown,
}

Julia_Event_Kind :: enum {
    Initialized,
    Invoke_Complete,
    Scratchpad_Complete,
    View_Snapshot_Complete,
    Animation_Tick_Complete,
    Shutdown_Complete,
}

Animation_Tick_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
}

Animation_Tick_Slot :: struct {
    state: Animation_Tick_Slot_State,
    request_id: u64,
    generation: u64,
    sequence: u64,
    host_state: ^core.Euclid_General_State,
    animation: ^core.Euclid_Julia_Animation_Interface,
    dt: f32,
    submitted_at: time.Tick,
    query_snapshot: Animation_Query_Snapshot,
    scene_batch: Scene_Command_Batch,
}

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

View_Snapshot_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
    Published,
}

View_Snapshot :: struct {
    state: View_Snapshot_Slot_State,
    request_id: u64,
    generation: u64,
    host_state: ^core.Euclid_General_State,
    animation: ^core.Euclid_Julia_Animation_Interface,
    fallback_text_len: int,
    fallback_text: [VIEW_SNAPSHOT_TEXT_CAPACITY]u8,
    command_buffer: core.Dynview_Command_Buffer,
    math_program_count: int,
    math_command_count: int,
    math_node_count: int,
    math_programs: [core.DYNVIEW__MAX_MATH_PROGRAMS]core.Dynview_Math_Program,
    math_commands: [core.DYNVIEW__MAX_MATH_COMMANDS]core.Dynview_Command,
    math_nodes: [core.DYNVIEW__MAX_MATH_NODES]core.Dynview_Math_Node,
}

Scratchpad_Async_Kind :: enum {
    Submit,
    Complete,
    History_Previous,
    History_Next,
    History_Reset,
    Save_History,
}

Scratchpad_Async_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
}

Scratchpad_Async_Slot :: struct {
    state: Scratchpad_Async_Slot_State,
    kind: Scratchpad_Async_Kind,
    request_id: u64,
    input_generation: u64,
    host_state: ^core.Euclid_General_State,
    caret_byte: int,
    input_len: int,
    input: [SCRATCHPAD_ASYNC_TEXT_CAPACITY]u8,
    result_len: int,
    result: [SCRATCHPAD_ASYNC_TEXT_CAPACITY]u8,
    parse_result: i32,
    succeeded: bool,
}

Julia_Lifecycle_State :: enum {
    Not_Started,
    Starting,
    Ready,
    Shutdown_Requested,
    Failed,
    Stopped,
}

Julia_Reload_State :: enum {
    Idle,
    Quiescing,
    Including,
    Registering,
    Publishing,
    Failed,
}

Julia_Task_Proc :: #type proc(data: rawptr) -> bool

Julia_Request :: struct {
    kind: Julia_Request_Kind,
    request_id: u64,
    task: Julia_Task_Proc,
    data: rawptr,
    slot_index: i32,
}

Julia_Event :: struct {
    kind: Julia_Event_Kind,
    request_kind: Julia_Request_Kind,
    request_id: u64,
    slot_index: i32,
    succeeded: bool,
}

Julia_Runtime_Service :: struct {
    worker: ^thread.Thread,
    requests: chan.Chan(Julia_Request),
    events: chan.Chan(Julia_Event),
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
    runtime_generation: u64,
    reload_failed_mtime_unix_nano: i64,
    scratchpad_slots: [SCRATCHPAD_ASYNC_SLOT_COUNT]Scratchpad_Async_Slot,
    completed_scratchpad_slots: [SCRATCHPAD_ASYNC_SLOT_COUNT]i32,
    completed_scratchpad_head: int,
    completed_scratchpad_count: int,
    dynview_staging: ^core.Dynview_System,
    view_snapshots: [VIEW_SNAPSHOT_SLOT_COUNT]View_Snapshot,
    view_snapshot_generation: u64,
    view_snapshot_pending: bool,
    published_view_snapshot_index: int,
    animation_tick_slots: [ANIMATION_TICK_SLOT_COUNT]Animation_Tick_Slot,
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
animation_tick_diagnostics :: proc(
    state: ^core.Euclid_General_State) -> Animation_Tick_Diagnostics {

    if state == nil || state^.julia_runtime_service == nil {
        return {}
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
coalesce_animation_tick :: proc(service: ^Julia_Runtime_Service, dt: f32) {
    service^.animation_accumulated_dt = min(
        service^.animation_accumulated_dt + dt, MAX_ACCUMULATED_ANIMATION_DT)
    service^.animation_ticks_coalesced += 1
}

//   Submit one bounded animation tick without blocking the display thread.
try_request_animation_tick :: proc(state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.julia_runtime_service == nil || state^.julia_interface == nil {
        return false
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
publish_available_animation_tick :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil || state^.julia_interface == nil {
        return false
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
    committed := animation_tick_matches_current(state, service, slot) &&
        commit_scene_command_batch(state, &slot^.scene_batch)
    if committed {
        service^.animation_ticks_committed += 1
        service^.animation_last_committed_sequence = slot^.sequence
        latency_ms := time.duration_seconds(time.tick_since(slot^.submitted_at)) * 1000
        service^.animation_last_latency_ms = latency_ms
        service^.animation_max_latency_ms = max(service^.animation_max_latency_ms, latency_ms)
    } else {
        service^.animation_ticks_stale += 1
    }
    release_completed_animation_ticks(service)
    return committed
}

//   Match one result against current lifecycle generation and selection identity.
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
reserve_animation_tick_slot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Find the newest worker completion without relying on event payload retention.
newest_completed_animation_tick_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_sequence: u64
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Complete && (newest_index < 0 || slot.sequence > newest_sequence) {
            newest_index = slot_index
            newest_sequence = slot.sequence
        }
    }
    return newest_index
}

//   Release all consumed or superseded animation completion slots.
release_completed_animation_ticks :: proc(service: ^Julia_Runtime_Service) {
    for &slot in service^.animation_tick_slots {
        if slot.state == .Complete {
            slot.state = .Free
        }
    }
}

//   Submit one replaceable view generation request without blocking display.
try_request_view_snapshot :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
publish_available_view_snapshot :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
    if state^.julia_interface == nil ||
        slot^.animation != state^.julia_interface^.current_animation ||
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

//   Find the newest completed slot without relying on lossy event metadata.
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
release_superseded_completed_view_snapshots :: proc(
    service: ^Julia_Runtime_Service, newest_index: int) {

    for &slot, slot_index in service^.view_snapshots {
        if slot_index != newest_index && slot.state == .Complete {
            slot.state = .Free
        }
    }
}

//   Keep previous semantic commands from appearing under a new selection.
clear_stale_published_view :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service) {

    published_index := service^.published_view_snapshot_index
    if published_index < 0 || state^.julia_interface == nil {
        return
    }
    published := &service^.view_snapshots[published_index]
    if published^.animation == state^.julia_interface^.current_animation {
        return
    }
    published^.state = .Free
    service^.published_view_snapshot_index = -1
    reset_view_snapshot_staging(&state^.dynview)
}

//   Validate all semantic bounds and require a closed, error-free command stream.
view_snapshot_is_valid :: proc(slot: ^View_Snapshot) -> bool {
    return slot^.fallback_text_len >= 0 &&
        slot^.fallback_text_len <= len(slot^.fallback_text) &&
        slot^.command_buffer.command_count >= 0 &&
        slot^.command_buffer.command_count <= core.DYNVIEW__MAX_COMMANDS &&
        slot^.command_buffer.text_bytes_len >= 0 &&
        slot^.command_buffer.text_bytes_len <= core.DYNVIEW__MAX_TEXT_BYTES &&
        slot^.math_program_count >= 0 &&
        slot^.math_program_count <= core.DYNVIEW__MAX_MATH_PROGRAMS &&
        slot^.math_command_count >= 0 &&
        slot^.math_command_count <= core.DYNVIEW__MAX_MATH_COMMANDS &&
        slot^.math_node_count >= 0 &&
        slot^.math_node_count <= core.DYNVIEW__MAX_MATH_NODES &&
        !slot^.command_buffer.has_stream_error &&
        !slot^.command_buffer.stream_open_block
}

//   Return fallback text only when it belongs to the active animation.
current_view_snapshot_text :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_runtime_service == nil || state^.julia_interface == nil {
        return ""
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
    slot_index := service^.published_view_snapshot_index
    if slot_index < 0 {
        return ""
    }
    slot := &service^.view_snapshots[slot_index]
    if slot^.animation != state^.julia_interface^.current_animation {
        return ""
    }
    return string(slot^.fallback_text[:slot^.fallback_text_len])
}

//   Return a free snapshot slot that is neither pending nor displayed.
reserve_view_snapshot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.view_snapshots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Generate fallback and semantic dynview data into worker staging.
generate_view_snapshot_task :: proc(data: rawptr) -> bool {
    slot := cast(^View_Snapshot)data
    state := slot^.host_state
    assert_julia_runtime_owner(state)
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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
    copy(slot^.math_nodes[:slot^.math_node_count], cache^.math_nodes[:slot^.math_node_count])
    slot^.state = .Complete
    return true
}

//   Reset worker-only semantic emission storage for one generation.
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
    copy(cache^.math_nodes[:slot^.math_node_count], slot^.math_nodes[:slot^.math_node_count])
    cache^.is_valid = false
    cache^.layout_is_valid = false
    cache^.copy_hit_target_count = 0
    runtime^.pending_invalidation_mask |= 1
}

//   Return display-owned lifecycle, failure, and backpressure diagnostics.
julia_runtime_diagnostics :: proc(service: ^Julia_Runtime_Service) -> Julia_Runtime_Diagnostics {
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

//   Create the bounded channels and persistent worker that own Julia work.
create_julia_runtime_service :: proc() -> (^Julia_Runtime_Service, runtime.Allocator_Error) {
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
    service^.worker = thread.create_and_start_with_data(rawptr(service), julia_runtime_worker)
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

//   Apply one worker event to display-owned lifecycle metadata.
accept_julia_event :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    if !event.succeeded {
        service^.failed_request_count += 1
        service^.last_failed_request_id = event.request_id
        service^.last_failed_request_kind = event.request_kind
        if event.kind == .Initialized || event.kind == .Shutdown_Complete {
            service^.lifecycle = .Failed
        }
    }
    if event.request_id == service^.active_request_id {
        service^.active_request_id = 0
    }
    switch event.kind {
    case .Initialized:
    case .Shutdown_Complete:
        if event.succeeded {
            service^.lifecycle = .Stopped
        }
    case .Scratchpad_Complete:
        completed_index := (service^.completed_scratchpad_head +
            service^.completed_scratchpad_count) % SCRATCHPAD_ASYNC_SLOT_COUNT
        assert(service^.completed_scratchpad_count < SCRATCHPAD_ASYNC_SLOT_COUNT)
        service^.completed_scratchpad_slots[completed_index] = event.slot_index
        service^.completed_scratchpad_count += 1
    case .View_Snapshot_Complete:
        service^.view_snapshot_pending = false
    case .Animation_Tick_Complete:
        service^.animation_tick_pending = false
    case .Invoke_Complete:
    }
}

//   Publish readiness after startup registration and priming have completed.
mark_julia_runtime_ready :: proc(service: ^Julia_Runtime_Service) {
    assert(service != nil && service^.lifecycle == .Starting)
    service^.lifecycle = .Ready
}

//   Assert that Julia work is executing on the persistent owner thread.
assert_julia_runtime_owner :: proc(state: ^core.Euclid_General_State) {
    assert(state != nil && state^.julia_runtime_service != nil)
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
    assert(os.get_current_thread_id() == service^.owner_thread_id,
        "Julia C API operation executed outside the Julia owner thread")
}

//   Run one temporary serialized bridge operation on the Julia owner thread.
invoke_julia_compatibility_task :: proc(
    state: ^core.Euclid_General_State, task: Julia_Task_Proc, data: rawptr) -> bool {

    if state == nil || state^.julia_runtime_service == nil || task == nil {
        return false
    }
    service := cast(^Julia_Runtime_Service)state^.julia_runtime_service
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

//   Join the stopped worker and release service-owned channels and storage.
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
initialize_julia_state_task :: proc(data: rawptr) -> bool {
    state := cast(^core.Euclid_General_State)data
    assert_julia_runtime_owner(state)
    state^.saved_context = context
    state^.julia_interface = retrieve_interface()
    if !julia_interface_handles_valid(state^.julia_interface) {
        return false
    }
    return init_euclid_scripts(state)
}

//   Own Julia lifecycle and compatibility task execution until shutdown.
julia_runtime_worker :: proc(data: rawptr) {
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