package bridge

import bridgemodel "model"
import core "../core"
import contentdata "../core/content"

import "core:sync"

// Exercise_Query_Row is the exact pointer-free Julia copy-out ABI for one page row.
Exercise_Query_Row :: struct {
    identity: [36]u8,
    animation_id: [36]u8,
    reference: [16]u8,
    title: [256]u8,
    node_kind: u32,
}

// Exercise_Query_Metadata describes completed rows and the exact instruction byte count.
Exercise_Query_Metadata :: struct {
    status: u32,
    count: u32,
    total: u32,
    more: u32,
    text_count: u32,
}

#assert(size_of(Exercise_Query_Row) == 348)
#assert(size_of(Exercise_Query_Metadata) == 20)

// Borrowed query arguments copied into owned intent storage before admission returns.
Exercise_Query_Input :: struct {
    source: ^u8,
    byte_count: u32,
    kind: u32,
    offset: u32,
    limit: u16,
    load: bool,
}

// Julia-owned bounded destinations borrowed only for the synchronous poll call.
Exercise_Query_Buffers :: struct {
    rows: ^Exercise_Query_Row,
    text: ^u8,
    row_capacity: u32,
    text_capacity: u32,
}

#assert(size_of(Exercise_Query_Input) == 24)
#assert(offset_of(Exercise_Query_Input, load) == 22)
#assert(size_of(Exercise_Query_Buffers) == 24)
#assert(offset_of(Exercise_Query_Buffers, row_capacity) == 16)

// Queue one validated operation; the display owner alone submits work to SQLite.
@(export)
begin_exercise_query :: proc "c" (
    state: ^core.Euclid_General_State, input: ^Exercise_Query_Input,
    token: ^u64) -> i32 {
    if state == nil || state.julia_runtime_service == nil ||
       token == nil || input == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if input.kind > u32(contentdata.Exercise_Query_Kind.Children) ||
        input.byte_count > contentdata.EXERCISE_UUID_BYTE_COUNT ||
        (input.byte_count > 0 && input.source == nil) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state.saved_context
    value := string((cast([^]u8)input.source)[:input.byte_count])
    query_kind := contentdata.Exercise_Query_Kind(input.kind)
    animation_id, reference := "", value
    if query_kind == .List || query_kind == .Children {
        animation_id, reference = value, ""
    }
    query, valid := contentdata.exercise_query_request_make(
        0, query_kind, animation_id, reference, {input.offset, input.limit})
    if !valid ||
       (input.load && query_kind != .Resolve_Alias && query_kind != .Resolve_Uuid) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    return enqueue_exercise_query(state, query, input.load, token)
}

// Reserve the sole reply slot and transfer a small intent through Julia's owned pool.
enqueue_exercise_query :: proc(
    state: ^core.Euclid_General_State, query: contentdata.Exercise_Query_Request,
    load: bool, token: ^u64) -> i32 {
    service := state.julia_runtime_service
    operation := &service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if (operation.state != .Idle && !load) ||
       service.host_exercise_header_animation_generation == 0 {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    _ = drain_julia_egress_returns(service)
    message, failure := communication_link_alloc(&service.event_link)
    if failure != .None {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    operation.next_token += 1
    intent: bridgemodel.Exercise_Query_Intent = {
        token = operation.next_token,
        animation_generation = service.host_exercise_header_animation_generation,
        load = load,
        query = query,
    }
    intent.query.generation = intent.token
    if load {
        intent.header_request_id = bridgemodel.exercise_header_request_next(
            &service.exercise_header_request_sequence)
    }
    message^ = bridgemodel.Julia_Host_Egress(intent)
    if !communication_link_try_send(&service.event_link, message) {
        communication_link_free(&service.event_link, message)
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    operation.intent = intent
    operation.state = .Queued
    token^ = intent.token
    return BRIDGE_STATUS_OK
}

// Copy a completed reply into Julia-owned buffers, or report that it remains pending.
@(export)
poll_exercise_query :: proc "c" (
    state: ^core.Euclid_General_State, token: u64,
    metadata: ^Exercise_Query_Metadata, buffers: ^Exercise_Query_Buffers) -> i32 {
    if state == nil || state.julia_runtime_service == nil || metadata == nil ||
        buffers == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if buffers.rows == nil || buffers.text == nil ||
        buffers.row_capacity != contentdata.EXERCISE_LIST_PAGE_CAPACITY ||
        buffers.text_capacity != contentdata.EXERCISE_INSTRUCTIONS_BYTE_CAPACITY {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state.saved_context
    operation := &state.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state == .Idle || operation.intent.token != token {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    if operation.state != .Ready {
        return -1
    }
    copy_exercise_query_reply(&operation.result, metadata,
        (cast([^]Exercise_Query_Row)buffers.rows)[:buffers.row_capacity],
        (cast([^]u8)buffers.text)[:buffers.text_capacity])
    operation.state = .Idle
    return BRIDGE_STATUS_OK
}

// Convert only the completed bounded rows; text is copied once into caller-owned bytes.
copy_exercise_query_reply :: proc(
    result: ^contentdata.Exercise_Query_Result, metadata: ^Exercise_Query_Metadata,
    rows: []Exercise_Query_Row, text: []u8) {
    count := u32(result.returned_count)
    if result.kind != .List && result.kind != .Children && result.status == .Ready {
        count = 1
    }
    metadata^ = {u32(result.status), count, result.total_count,
        u32(result.more_available), u32(result.instructions_length)}
    for index in 0..<int(count) {
        rows[index] = {}
        if result.kind == .Children {
            child := &result.children[index]
            rows[index].identity = child.animation_id
            rows[index].title = child.name
            rows[index].node_kind = u32(child.kind)
        } else {
            summary := &result.exercise
            if result.kind == .List {
                summary = &result.exercises[index]
            }
            rows[index].identity = summary.exercise_id
            rows[index].animation_id = summary.animation_id
            rows[index].reference = summary.reference
            rows[index].title = summary.title
        }
    }
    copy(text, result.instructions[:result.instructions_length])
}

// Abandon only the named operation; late worker replies remain harmless and drain normally.
@(export)
cancel_exercise_query :: proc "c" (
    state: ^core.Euclid_General_State, token: u64) {
    if state == nil || state.julia_runtime_service == nil {
        return
    }
    context = state.saved_context
    operation := &state.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.intent.token == token {
        operation.state = .Idle
    }
}
