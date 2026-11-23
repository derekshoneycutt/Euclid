package bridge_exercise

import transport "../transport"

import bridgemodel "../model"
import core "../../core"
import contentdata "../../core/content"
import userdata "../../persistence/userdata"
import uuid "core:encoding/uuid"
import "core:sync"

// User_Exercise_Input is the pointer-and-length ABI for one bounded store task.
User_Exercise_Input :: struct {
    operation: u32,
    identity_source: ^u8,
    identity_byte_count: u32,
    animation_source: ^u8,
    animation_byte_count: u32,
    reference_source: ^u8,
    reference_byte_count: u32,
    title_source: ^u8,
    title_byte_count: u32,
    instructions_source: ^u8,
    instructions_byte_count: u32,
    result_offset: u32,
    page_limit: u16,
    load: bool,
}

#assert(size_of(User_Exercise_Input) == 96)
#assert(offset_of(User_Exercise_Input, identity_source) == 8)
#assert(offset_of(User_Exercise_Input, instructions_source) == 72)
#assert(offset_of(User_Exercise_Input, result_offset) == 84)
#assert(offset_of(User_Exercise_Input, load) == 90)

// Queue one copied user-store operation for display-owner worker admission.
begin_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State, input: ^User_Exercise_Input,
    token: ^u64) -> i32 {
    if state == nil || state.julia_runtime_service == nil {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state.saved_context
    if input == nil || token == nil || !user_exercise_input_is_well_formed(input^) {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    task, valid := user_exercise_task_from_input(input^)
    if !valid {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    return enqueue_user_exercise_operation(state, task, input.load, token)
}

// Copy and validate all borrowed source fields before reserving operation storage.
user_exercise_task_from_input :: proc(
    input: User_Exercise_Input) -> (userdata.User_Exercise_Task, bool) {
    task: userdata.User_Exercise_Task = {
        operation = userdata.User_Exercise_Operation(input.operation),
        result_offset = input.result_offset,
        page_limit = input.page_limit,
    }
    if !user_exercise_task_identity(&task, input) ||
       !user_exercise_task_draft(&task, input) ||
       !user_exercise_task_reference(&task, input) {
        return {}, false
    }
    if input.load &&
       task.operation != .Read_Identity && task.operation != .Read_Reference {
        return {}, false
    }
    return task, userdata.store_user_exercise_task_is_valid(task)
}

// Read the stable or associated identity permitted by this operation kind.
user_exercise_task_identity :: proc(
    task: ^userdata.User_Exercise_Task, input: User_Exercise_Input) -> bool {
    needs_identity := task^.operation == .Read_Identity ||
        task^.operation == .Update || task^.operation == .Delete
    needs_animation := task^.operation == .Create || task^.operation == .List
    if !needs_identity && !needs_animation {
        return input.identity_byte_count == 0
    }
    if needs_animation && input.identity_byte_count != 0 {
        return false
    }
    source, byte_count := input.identity_source, input.identity_byte_count
    if needs_animation {
        source, byte_count = input.animation_source, input.animation_byte_count
    }
    if task^.operation == .List && byte_count == 0 {
        return true
    }
    identity, valid := user_exercise_input_uuid(source, byte_count)
    if !valid {
        return false
    }
    if needs_animation {
        if task^.operation == .List {
            task^.identity = identity
        } else {
            task^.draft_animation_id = identity
        }
    } else {
        task^.identity = identity
    }
    return true
}

// Parse one exact canonical UUID from Julia-owned input bytes.
user_exercise_input_uuid :: proc(
    source: ^u8, byte_count: u32) -> (uuid.Identifier, bool) {
    if source == nil || byte_count != contentdata.EXERCISE_UUID_BYTE_COUNT {
        return {}, false
    }
    value := string((cast([^]u8)source)[:byte_count])
    if !contentdata.exercise_uuid_is_valid(value) {
        return {}, false
    }
    identity, failure := uuid.read(value)
    return identity, failure == .None
}

// Copy a draft only for create/update; other operations must carry no draft fields.
user_exercise_task_draft :: proc(
    task: ^userdata.User_Exercise_Task, input: User_Exercise_Input) -> bool {
    if task^.operation != .Create && task^.operation != .Update {
        return input.title_byte_count == 0 && input.instructions_byte_count == 0 &&
            (task^.operation == .List || input.animation_byte_count == 0)
    }
    if input.operation == u32(userdata.User_Exercise_Operation.Update) {
        animation, valid := user_exercise_input_uuid(
            input.animation_source, input.animation_byte_count)
        if !valid {
            return false
        }
        task^.draft_animation_id = animation
    }
    if input.title_byte_count > len(task^.draft_title) ||
       input.instructions_byte_count > len(task^.draft_instructions) {
        return false
    }
    task^.draft_title_length = u16(input.title_byte_count)
    task^.draft_instructions_length = input.instructions_byte_count
    copy(task^.draft_title[:], user_exercise_input_bytes(
        input.title_source, input.title_byte_count))
    copy(task^.draft_instructions[:], user_exercise_input_bytes(
        input.instructions_source, input.instructions_byte_count))
    return true
}

// Copy a friendly reference for reads and writes while rejecting stray fields.
user_exercise_task_reference :: proc(
    task: ^userdata.User_Exercise_Task, input: User_Exercise_Input) -> bool {
    reads_reference := task^.operation == .Read_Reference
    writes_draft := task^.operation == .Create || task^.operation == .Update
    if !reads_reference && !writes_draft {
        return input.reference_byte_count == 0
    }
    if input.reference_byte_count > len(task^.draft_reference) {
        return false
    }
    if reads_reference {
        task^.reference_length = u8(input.reference_byte_count)
        copy(task^.reference[:], user_exercise_input_bytes(
            input.reference_source, input.reference_byte_count))
    } else {
        task^.draft_reference_length = u8(input.reference_byte_count)
        copy(task^.draft_reference[:], user_exercise_input_bytes(
            input.reference_source, input.reference_byte_count))
    }
    return true
}

// Return the exact borrowed bytes after the caller validates pointer and length.
user_exercise_input_bytes :: proc(source: ^u8, byte_count: u32) -> []u8 {
    if byte_count == 0 {
        return nil
    }
    return (cast([^]u8)source)[:byte_count]
}

// Reject null pointers for nonempty fields and unexpected operation discriminators.
user_exercise_input_is_well_formed :: proc(input: User_Exercise_Input) -> bool {
    if input.operation == 0 ||
       input.operation > u32(userdata.User_Exercise_Operation.Delete) {
        return false
    }
    return (input.identity_byte_count == 0 || input.identity_source != nil) &&
        (input.animation_byte_count == 0 || input.animation_source != nil) &&
        (input.reference_byte_count == 0 || input.reference_source != nil) &&
        (input.title_byte_count == 0 || input.title_source != nil) &&
        (input.instructions_byte_count == 0 || input.instructions_source != nil)
}

// Reserve the Julia-owned reply slot before transferring a copied task to display.
enqueue_user_exercise_operation :: proc(
    state: ^core.Euclid_General_State, task: userdata.User_Exercise_Task,
    load: bool, token: ^u64) -> i32 {
    service := state.julia_runtime_service
    operation := &service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Idle ||
       service.host_exercise_header_animation_generation == 0 {
        return bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE
    }
    operation.next_request_id += 1
    copied_task := task
    copied_task.request_id = operation.next_request_id
    intent: bridgemodel.User_Exercise_Intent = {
        request_id = operation.next_request_id,
        animation_generation = service.host_exercise_header_animation_generation,
        load = load,
    }
    if load {
        intent.header_request_id = bridgemodel.exercise_header_request_next(
            &service.exercise_header_request_sequence)
    }
    operation.intent = intent
    operation.task = copied_task
    if transport.consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(intent)) != .Sent {
        operation.intent = {}
        operation.task = {}
        return bridgemodel.BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    operation.state = .Queued
    token^ = intent.request_id
    return bridgemodel.BRIDGE_STATUS_OK
}

// Copy a completed user-store result into caller-owned bounded buffers.
poll_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State, token: u64,
    metadata: ^Exercise_Query_Metadata, buffers: ^Exercise_Query_Buffers) -> i32 {
    if state == nil || state.julia_runtime_service == nil {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state.saved_context
    if metadata == nil || buffers == nil ||
       !exercise_query_buffers_are_valid(buffers^) {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    operation := &state.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state == .Idle || operation.intent.request_id != token {
        return bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE
    }
    if operation.state != .Ready {
        return -1
    }
    copy_user_exercise_reply(operation, metadata,
        (cast([^]Exercise_Query_Row)buffers.rows)[:buffers.row_capacity],
        (cast([^]u8)buffers.text)[:buffers.text_capacity])
    operation.state = .Idle
    return bridgemodel.BRIDGE_STATUS_OK
}

// Validate the shared fixed-capacity row and instruction destinations.
exercise_query_buffers_are_valid :: proc(buffers: Exercise_Query_Buffers) -> bool {
    return buffers.rows != nil && buffers.text != nil &&
        buffers.row_capacity == contentdata.EXERCISE_LIST_PAGE_CAPACITY &&
        buffers.text_capacity == contentdata.EXERCISE_INSTRUCTIONS_BYTE_CAPACITY
}

// Copy summary rows and include instruction bytes only for an accepted load.
copy_user_exercise_reply :: proc(
    operation: ^bridgemodel.User_Exercise_Operation,
    metadata: ^Exercise_Query_Metadata, rows: []Exercise_Query_Row, text: []u8) {
    task := &operation.result
    count := u32(0)
    if operation.status == .Ready {
        count = user_exercise_result_count(task)
    }
    metadata^ = {
        u32(operation.status), count, task.page.total_count,
        u32(task.page.more_available), 0,
    }
    if task.operation == .List {
        copy_user_exercise_page_rows(operation, rows)
    } else if count == 1 {
        copy_user_exercise_record_row(
            &task.result, operation.animation_available, &rows[0])
    }
    if operation.intent.load && operation.status == .Ready {
        count := int(task.result.instructions_length)
        copy(text[:count], task.result.instructions[:count])
        metadata^.text_count = u32(count)
    }
}

// Select page count or the one-record result count from the operation kind.
user_exercise_result_count :: proc(task: ^userdata.User_Exercise_Task) -> u32 {
    if task^.operation == .List {
        return u32(task^.page.returned_count)
    }
    if task^.operation == .Delete {
        return 0
    }
    return 1 if operation_has_record(task^.operation) else 0
}

// Identify tasks whose successful result contains one exercise record.
operation_has_record :: proc(operation: userdata.User_Exercise_Operation) -> bool {
    return operation == .Create || operation == .Read_Identity ||
        operation == .Read_Reference || operation == .Update
}

// Copy all ordered list summaries without instruction text.
copy_user_exercise_page_rows :: proc(
    operation: ^bridgemodel.User_Exercise_Operation,
    rows: []Exercise_Query_Row) {
    task := &operation.result
    for index in 0..<int(task^.page.returned_count) {
        summary := &task^.page.exercises[index]
        row := &rows[index]
        row^ = {}
        _ = uuid.to_string(summary.id, row.identity[:])
        _ = uuid.to_string(summary.animation_id, row.animation_id[:])
        copy(row.reference[:], summary.reference[:summary.reference_length])
        copy(row.title[:], summary.title[:summary.title_length])
        row.node_kind = 1 if operation.page_animation_available[index] else 0
    }
}

// Copy one identity summary into the existing row ABI.
copy_user_exercise_record_row :: proc(
    record: ^userdata.User_Exercise_Record, animation_available: bool,
    row: ^Exercise_Query_Row) {
    row^ = {}
    _ = uuid.to_string(record.id, row.identity[:])
    _ = uuid.to_string(record.animation_id, row.animation_id[:])
    copy(row.reference[:], record.reference[:record.reference_length])
    copy(row.title[:], record.title[:record.title_length])
    row.node_kind = 1 if animation_available else 0
}

// Abandon only the named operation; worker completion is still drained by the display.
cancel_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State, token: u64) {
    if state == nil || state.julia_runtime_service == nil {
        return
    }
    operation := &state.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.intent.request_id == token {
        operation.state = .Idle
    }
}
