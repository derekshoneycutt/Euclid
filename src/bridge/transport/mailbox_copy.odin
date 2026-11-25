package transport

import bridgemodel "../model"
import protocol "../../core/protocol"

// Mailbox_Copy_Cursor measures or writes nested bytes into a supplied aligned destination.
Mailbox_Copy_Cursor :: struct {
    bytes: []u8,
    used: int,
}

// Measure or copy one typed slice; the cursor has no authority to grow destination storage.
mailbox_copy_slice :: proc(cursor: ^Mailbox_Copy_Cursor, source: []$T) -> []T {
    start := mailbox_align(cursor.used, align_of(T))
    cursor.used = start + len(source) * size_of(T)
    if cursor.bytes == nil {
        return source
    }
    assert(cursor.used <= len(cursor.bytes))
    destination := (cast([^]T)raw_data(cursor.bytes[start:]))[0:len(source)]
    copy(destination, source)
    return destination
}

// Preserve exact string bytes including embedded NUL without Julia or native allocation.
mailbox_copy_string :: proc(cursor: ^Mailbox_Copy_Cursor, source: string) -> string {
    return string(mailbox_copy_slice(cursor, transmute([]u8)source))
}

// Dispatch the native protocol's nested-copy contract; inline and checked-slot values stay inline.
mailbox_copy_value :: proc(value: $T, bytes: []u8) -> (T, int) {
    cursor: Mailbox_Copy_Cursor = {
        bytes = bytes,
    }
    result := value
    when T == bridgemodel.Julia_Host_Ingress {
        mailbox_copy_ingress(&result, &cursor)
    } else when T == bridgemodel.Julia_Host_Egress {
        mailbox_copy_egress(&result, &cursor)
    }
    return result, cursor.used
}

// Copy each ingress variant with dynamic native payloads; all other variants are inline.
mailbox_copy_ingress :: proc(
    value: ^bridgemodel.Julia_Host_Ingress, cursor: ^Mailbox_Copy_Cursor) {
    switch message in value^ {
    case protocol.Evaluation_Requested:
        mailbox_copy_evaluation(value, message, cursor)
    case protocol.Completion_Requested:
        mailbox_copy_completion_request(value, message, cursor)
    case protocol.Highlight_Requested:
        mailbox_copy_highlight_request(value, message, cursor)
    case bridgemodel.Harness_Scenario_Requested:
        mailbox_copy_harness(value, message, cursor)
    case bridgemodel.Scenario_View_Content_Requested:
        mailbox_copy_scenario(value, message, cursor)
    case bridgemodel.Runtime_Initialize_Requested,
         bridgemodel.Runtime_Content_Initialize_Requested,
         bridgemodel.Animation_Tick_Requested, bridgemodel.Animation_Lifecycle_Requested,
         bridgemodel.Runtime_Shutdown_Requested, protocol.Terminal_Session_Started,
         protocol.Terminal_Session_Closed, protocol.Terminal_Interactive_Input,
         protocol.Terminal_Geometry_Accepted, protocol.Terminal_Capabilities_Accepted,
         protocol.Tick_Stream_Configuration_Acknowledged, protocol.Tick_Pulse,
         bridgemodel.Active_Operation_Progress_Ready,
         bridgemodel.Active_Operation_Outcome_Ready:
        return
    }
}

// Copy each egress variant with dynamic native payloads; all other variants are inline.
mailbox_copy_egress :: proc(
    value: ^bridgemodel.Julia_Host_Egress, cursor: ^Mailbox_Copy_Cursor) {
    switch message in value^ {
    case bridgemodel.View_Content_Ready:
        mailbox_copy_content(value, message, cursor)
    case bridgemodel.Exercise_Header_Update:
        mailbox_copy_header(value, message, cursor)
    case protocol.Terminal_Output_Batch:
        mailbox_copy_output(value, message, cursor)
    case protocol.Completion_Result:
        mailbox_copy_completion_result(value, message, cursor)
    case protocol.Highlight_Result:
        mailbox_copy_highlight_result(value, message, cursor)
    case protocol.Terminal_Session_Ready:
        mailbox_copy_banner(value, message, cursor)
    case bridgemodel.Runtime_Initialized, bridgemodel.Runtime_Content_Initialized,
         bridgemodel.Animation_Tick_Completed, bridgemodel.Animation_Lifecycle_Completed,
         bridgemodel.Harness_Scenario_Completed, bridgemodel.Runtime_Shutdown_Completed,
         bridgemodel.Exercise_Query_Intent, bridgemodel.User_Exercise_Intent,
         protocol.Evaluation_Incomplete, protocol.Evaluation_Completed,
         protocol.Completion_Failed, protocol.Highlight_Failed,
         protocol.Terminal_Input_Acquired, protocol.Terminal_Input_Released,
         protocol.Terminal_Geometry_Observed, protocol.Terminal_Capabilities_Observed,
         protocol.Terminal_Session_Stopped, protocol.Tick_Stream_Configure_Requested,
         protocol.Tick_Stream_Stop_Requested,
         bridgemodel.Active_Operation_Outcome_Acknowledged:
        return
    }
}

// Rebind evaluation source to native inbox bytes before publication.
mailbox_copy_evaluation :: proc(
    value: ^bridgemodel.Julia_Host_Ingress, message: protocol.Evaluation_Requested,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.code = mailbox_copy_string(cursor, message.code)
    value^ = message
}

// Rebind completion source to native inbox bytes before publication.
mailbox_copy_completion_request :: proc(
    value: ^bridgemodel.Julia_Host_Ingress, message: protocol.Completion_Requested,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.code = mailbox_copy_string(cursor, message.code)
    value^ = message
}

// Rebind highlighting source to native inbox bytes before publication.
mailbox_copy_highlight_request :: proc(
    value: ^bridgemodel.Julia_Host_Ingress, message: protocol.Highlight_Requested,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.source = mailbox_copy_string(cursor, message.source)
    value^ = message
}

// Preserve harness source until Julia creates its own managed value.
mailbox_copy_harness :: proc(
    value: ^bridgemodel.Julia_Host_Ingress,
    message: bridgemodel.Harness_Scenario_Requested,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.scenario_name = mailbox_copy_string(cursor, message.scenario_name)
    value^ = message
}

// Copy exact debug presentation source without changing its correlation.
mailbox_copy_scenario :: proc(
    value: ^bridgemodel.Julia_Host_Ingress,
    message: bridgemodel.Scenario_View_Content_Requested,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.source = mailbox_copy_slice(cursor, message.source)
    value^ = message
}

// Rebind exact MIME source while preserving generation and owner-controlled commit identity.
mailbox_copy_content :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: bridgemodel.View_Content_Ready,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.content.bytes = mailbox_copy_slice(cursor, message.content.bytes)
    value^ = message
}

// Copy bounded exercise header text into the display inbox.
mailbox_copy_header :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: bridgemodel.Exercise_Header_Update,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.text = mailbox_copy_slice(cursor, message.text)
    value^ = message
}

// Copy ordered Terminal bytes without interpreting or coalescing their stream.
mailbox_copy_output :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: protocol.Terminal_Output_Batch,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.bytes = mailbox_copy_string(cursor, message.bytes)
    value^ = message
}

// Copy insertion bytes before the rooted Julia result can be reclaimed.
mailbox_copy_completion_result :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: protocol.Completion_Result,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.insertion = mailbox_copy_string(cursor, message.insertion)
    value^ = message
}

// Copy both highlighting allocations with typed run alignment and exact source bytes.
mailbox_copy_highlight_result :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: protocol.Highlight_Result,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.source = mailbox_copy_string(cursor, message.source)
    message.runs = mailbox_copy_slice(cursor, message.runs)
    value^ = message
}

// Copy startup banner bytes before the native envelope outlives Julia's rooted call.
mailbox_copy_banner :: proc(
    value: ^bridgemodel.Julia_Host_Egress, message: protocol.Terminal_Session_Ready,
    cursor: ^Mailbox_Copy_Cursor) {
    message := message
    message.banner = mailbox_copy_string(cursor, message.banner)
    value^ = message
}
