package viewsharing

import sharingmodel "../../view/sharing/model"
import userdata "../../persistence/userdata"
import sharing "../../sharing"
import "core:os"
import "core:sync"
import taskpool "../../taskpool"

Exchange_File_Sink_State :: struct {
    file: ^os.File,
    cancel_requested: ^i32,
    failed: bool,
}

Exchange_File_Work_State :: struct {
    temporary_path: [sharingmodel.EXCHANGE_PATH_CAPACITY]u8,
    sink_state: Exchange_File_Sink_State,
    sink: sharing.Export_Sink,
    writer: sharing.Export_Writer,
}

// Run exactly one exchange task using only its payload and the staged allocator.
exchange_task_run :: proc(
    raw_payload: rawptr,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    payload := cast(^sharingmodel.Exchange_Task_Payload)raw_payload
    if payload == nil {
        return .Failed
    }
    if exchange_task_cancelled(payload, token) {
        payload.result.kind = .Cancelled
        return .Cancelled
    }
    switch payload.kind {
    case .Export:
        return exchange_task_export(payload, token)
    case .Parse_Import:
        return exchange_task_parse(payload, token)
    case .Commit_Import:
        return exchange_task_commit(payload, token)
    case .None:
        payload.result.kind = .Persistence_Failed
        return .Failed
    case:
        payload.result.kind = .Persistence_Failed
        return .Failed
    }
}

// Export selected persistence rows into an atomic sibling temporary file.
exchange_task_export :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    if payload.store == nil || payload.selected_count < 1 ||
        payload.selected_count > len(payload.selected_ids) ||
        !exchange_task_path_valid(payload.path_length) {
        payload.result.kind = .Write_Failed
        return .Failed
    }
    cursor: userdata.Collection_Export_Cursor
    failure := userdata.store_export_begin(
        payload.store, payload.selected_ids[:payload.selected_count], &cursor)
    if !userdata.store_error_is_clear(failure) {
        payload.result = {
            kind = .Persistence_Failed,
            store_error = failure,
        }
        return .Failed
    }
    task_result := exchange_task_write_export_rows(&cursor, payload, token)
    if cursor.in_transaction {
        end_error := userdata.store_export_end(&cursor)
        if !userdata.store_error_is_clear(end_error) {
            if payload.result.kind == .Succeeded ||
                payload.result.kind == .None {
                payload.result = {
                    kind = .Persistence_Failed,
                    store_error = end_error,
                }
            } else {
                payload.result.store_error.cleanup_error =
                    end_error.sqlite_error
            }
            task_result = .Failed
        }
    }
    if task_result != .Succeeded {
        exchange_task_remove_temporary(payload)
        return task_result
    }
    return .Succeeded
}

// Stream each persistence row through the bounded codec sink.
exchange_task_write_export_rows :: proc(
    cursor: ^userdata.Collection_Export_Cursor,
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    work: Exchange_File_Work_State
    if !exchange_task_temporary_path(payload, work.temporary_path[:]) {
        payload.result.kind = .Write_Failed
        return .Failed
    }
    file, open_error := os.open(
        string(work.temporary_path[:payload.path_length+4]),
        {.Write, .Create, .Trunc})
    if open_error != nil {
        payload.result.kind = .Write_Failed
        return .Failed
    }
    work.sink_state = {
        file = file,
        cancel_requested = &payload.cancel_requested,
    }
    work.sink = {
        buffer = payload.chunk[:],
        flush = exchange_task_flush_file_sink,
        user = &work.sink_state,
    }
    writer_error := sharing.export_writer_init(&work.writer, &work.sink)
    if writer_error != .None {
        _ = os.close(file)
        exchange_task_remove_temporary(payload)
        payload.result.kind = .Write_Failed
        return .Failed
    }
    task_result := exchange_task_write_cursor(&work.writer, cursor, payload, token)
    return exchange_task_finish_export_file(&work, payload, token, task_result)
}

// Flush, close, and atomically publish a completed export file.
exchange_task_finish_export_file :: proc(
    work: ^Exchange_File_Work_State,
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token,
    task_result: taskpool.Task_Result) -> taskpool.Task_Result {
    result := exchange_task_close_export_file(work, payload, token, task_result)
    if result != .Succeeded {
        return result
    }
    return exchange_task_publish_export_file(work, payload)
}

// Complete codec and file synchronization before closing the temporary file.
exchange_task_close_export_file :: proc(
    work: ^Exchange_File_Work_State,
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token,
    task_result: taskpool.Task_Result) -> taskpool.Task_Result {
    result := task_result
    if result == .Succeeded &&
        sharing.export_writer_finish(&work^.writer) != .None {
        result = .Failed
    }
    if result == .Succeeded &&
        (os.flush(work^.sink_state.file) != nil ||
            os.sync(work^.sink_state.file) != nil) {
        result = .Failed
    }
    close_error := os.close(work^.sink_state.file)
    if work^.sink_state.failed || close_error != nil {
        result = .Failed
    }
    if result == .Succeeded {
        return result
    }
    if exchange_task_cancelled(payload, token) {
        payload.result.kind = .Cancelled
        result = .Cancelled
    } else {
        payload.result.kind = .Write_Failed
        result = .Failed
    }
    exchange_task_remove_temporary(payload)
    return result
}

// Atomically rename the complete sibling file into its requested destination.
exchange_task_publish_export_file :: proc(
    work: ^Exchange_File_Work_State,
    payload: ^sharingmodel.Exchange_Task_Payload) -> taskpool.Task_Result {
    if os.rename(
        string(work^.temporary_path[:payload.path_length+4]),
        string(payload.path[:payload.path_length])) != nil {
        payload.result.kind = .Write_Failed
        exchange_task_remove_temporary(payload)
        return .Failed
    }
    payload.result.kind = .Succeeded
    return .Succeeded
}

// Encode cursor rows until exhaustion, cancellation, or the first failure.
exchange_task_write_cursor :: proc(
    writer: ^sharing.Export_Writer,
    cursor: ^userdata.Collection_Export_Cursor,
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    for {
        if exchange_task_cancelled(payload, token) {
            payload.result.kind = .Cancelled
            return .Cancelled
        }
        has_row, failure := userdata.store_export_next(
            cursor, &payload.persistence_row)
        if !userdata.store_error_is_clear(failure) {
            payload.result = {
                kind = .Persistence_Failed,
                store_error = failure,
            }
            return .Failed
        }
        if !has_row {
            return .Succeeded
        }
        if !exchange_task_convert_export_row(payload) ||
            sharing.export_writer_row(writer, payload.writer_row) != .None {
            payload.result.kind = .Write_Failed
            return .Failed
        }
        payload.result.bytes_processed += 1
    }
}

// Copy one fixed persistence row into the codec-owned row shape.
exchange_task_convert_export_row :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload) -> bool {
    source := &payload.persistence_row
    if source.name_length < 0 || source.name_length > len(source.name) ||
        source.note_length < 0 || source.note_length > len(source.note) {
        return false
    }
    kind := sharing.Export_Row_Kind.Collection
    if source.kind == .Entry {
        kind = .Entry
    }
    payload.writer_row = {
        kind = kind,
        animation_id = source.animation_id,
        depth = source.depth,
        name = source.name,
        name_length = source.name_length,
        note = source.note,
        note_length = source.note_length,
        has_note = source.has_note,
        notes_on_top = source.notes_on_top,
        entry_count = source.entry_count,
    }
    return true
}

// Read and parse a bounded document through the reusable input chunk.
exchange_task_parse :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    if payload.staged == nil || !exchange_task_path_valid(payload.path_length) {
        payload.result.kind = .Invalid_Document
        return .Failed
    }
    file, open_error := os.open(string(payload.path[:payload.path_length]))
    if open_error != nil {
        payload.result.kind = .Read_Failed
        return .Failed
    }
    reader: sharing.Reader
    rule := sharing.reader_init(&reader, payload.workspace, payload.staged)
    if rule != .None {
        _ = os.close(file)
        payload.result = {
            kind = .Allocation_Failed,
            sharing_rule = rule,
        }
        return .Failed
    }
    task_result := exchange_task_read_document(&reader, file, payload, token)
    close_error := os.close(file)
    if close_error != nil && task_result == .Succeeded {
        task_result = .Failed
        payload.result.kind = .Read_Failed
    }
    if task_result == .Succeeded && !payload.staged^.valid {
        task_result = .Failed
        payload.result.kind = .Invalid_Document
    }
    return task_result
}

// Feed complete file chunks and finalize the incremental reader at EOF.
exchange_task_read_document :: proc(
    reader: ^sharing.Reader, file: ^os.File,
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    for {
        if exchange_task_cancelled(payload, token) {
            payload.result.kind = .Cancelled
            return .Cancelled
        }
        count, read_error := os.read(file, payload.chunk[:])
        if count > 0 {
            _, rule := sharing.reader_feed(reader, payload.chunk[:count], false)
            payload.result.bytes_processed += count
            if rule != .None {
                payload.result = {
                    kind = .Invalid_Document,
                    sharing_rule = rule,
                    bytes_processed = payload.result.bytes_processed,
                }
                return .Failed
            }
        }
        if read_error == .EOF {
            _, rule := sharing.reader_feed(reader, nil, true)
            if rule != .None {
                payload.result = {
                    kind = .Invalid_Document,
                    sharing_rule = rule,
                    bytes_processed = payload.result.bytes_processed,
                }
                return .Failed
            }
            payload.result.kind = .Succeeded
            return .Succeeded
        }
        if read_error != nil {
            payload.result.kind = .Read_Failed
            return .Failed
        }
    }
}

// Commit the immutable plan atomically after cancellation can no longer publish it.
exchange_task_commit :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    if payload.store == nil || payload.plan == nil {
        payload.result.kind = .Persistence_Failed
        return .Failed
    }
    if exchange_task_cancelled(payload, token) {
        payload.result.kind = .Cancelled
        return .Cancelled
    }
    failure := userdata.store_import_collections(payload.store, payload.plan)
    if !userdata.store_error_is_clear(failure) {
        payload.result = {
            kind = .Persistence_Failed,
            store_error = failure,
        }
        return .Failed
    }
    payload.result.kind = .Succeeded
    return .Succeeded
}

// Flush one codec chunk to disk without allocating or retaining file data.
exchange_task_flush_file_sink :: proc(sink: ^sharing.Export_Sink) -> bool {
    state := cast(^Exchange_File_Sink_State)sink.user
    if state == nil || state.file == nil ||
        sync.atomic_load_explicit(state.cancel_requested, .Acquire) != 0 {
        return false
    }
    _, failure := os.write(state.file, sink.buffer[:sink.used])
    if failure != nil {
        state.failed = true
        return false
    }
    sink.used = 0
    return true
}

// Construct a sibling temporary path without truncating the user's destination.
exchange_task_temporary_path :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload, destination: []u8) -> bool {
    if payload.path_length + 4 >= len(destination) {
        return false
    }
    copy(destination[:payload.path_length], payload.path[:payload.path_length])
    copy(destination[payload.path_length:payload.path_length+4], ".tmp")
    destination[payload.path_length+4] = 0
    return true
}

// Remove a failed export's temporary sibling while preserving its final path.
exchange_task_remove_temporary :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload) {
    temporary_path: [sharingmodel.EXCHANGE_PATH_CAPACITY]u8
    if exchange_task_temporary_path(payload, temporary_path[:]) {
        _ = os.remove(string(temporary_path[:payload.path_length+4]))
    }
}

// Reject empty and out-of-capacity paths before any task accesses the filesystem.
exchange_task_path_valid :: proc(path_length: int) -> bool {
    return path_length > 0 && path_length < sharingmodel.EXCHANGE_PATH_CAPACITY
}

// Observe the exchange-owned cancellation flag between file chunks.
exchange_task_cancelled :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload,
    token: taskpool.Task_Cancellation_Token) -> bool {
    return sync.atomic_load_explicit(&payload.cancel_requested, .Acquire) != 0 ||
        (token.requested != nil &&
            sync.atomic_load_explicit(token.requested, .Acquire))
}
