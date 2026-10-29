package main

import raw "../../libs/sqlite3"
import sqlite "../../src/sqlite"

import "core:c"
import json "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:strings"

Case_Execution :: struct {
    allocator: mem.Allocator,
    database: ^raw.Database,
    finalized: bool,
    cleanup_failure: ^Failure,
}

Native_Preparation :: struct {
    statement: ^raw.Statement,
    after: int,
    failure: ^Failure,
}

// Keep bounded copied diagnostics on complete UTF-8 boundaries.
diagnostic_copy :: proc(execution: ^Case_Execution, message: string) -> string {
    end := min(len(message), 2048)
    if end < len(message) {
        for end > 0 && message[end] & 0xc0 == 0x80 {
            end -= 1
        }
    }
    return strings.clone(message[:end], execution.allocator)
}

// Convert an internal optional pointer to a JSON-compatible nullable value.
failure_value :: proc(failure: ^Failure) -> Optional_Failure {
    if failure == nil {
        return nil
    }
    return failure^
}

// Allocate a copied failure whose diagnostic survives native cleanup calls.
make_failure :: proc(
    execution: ^Case_Execution, phase: string,
    code: raw.Result, message: string) -> ^Failure {
    allocator := execution.allocator
    failure := new(Failure, allocator)
    failure^ = {
        phase = phase,
        primary_code = int(code) & 255,
        extended_code = int(code),
        offset = json.Null(nil),
        message = diagnostic_copy(execution, message),
    }
    return failure
}

// Snapshot SQLite diagnostics before finalize, rollback, or close can overwrite them.
native_failure :: proc(
    execution: ^Case_Execution, phase: string, code: raw.Result, base: int) -> ^Failure {
    db := execution.database
    failure := make_failure(execution, phase, code, string(raw.sqlite3_errmsg(db)))
    failure.extended_code = int(raw.sqlite3_extended_errcode(db))
    if failure.extended_code & 255 != failure.primary_code {
        failure.extended_code = int(code)
    }
    offset := int(raw.sqlite3_error_offset(db))
    if base >= 0 && offset >= 0 {
        failure.offset = base + offset + 1
    }
    return failure
}

// Prepare, bind, optionally drain, and finalize a single native statement.
run_statement :: proc(
    execution: ^Case_Execution, statement: ^raw.Statement, step: Step,
    span: Native_Range, used: ^map[int]bool) -> ^Failure {
    failure := bind_statement(execution, statement, step, span, used)
    if failure == nil && step.mode == "execute" {
        for {
            result := raw.sqlite3_step(statement)
            if result == .Done {
                break
            }
            if result != .Row {
                failure = native_failure(execution, "step", result, -1)
                break
            }
        }
    }
    if result := raw.sqlite3_finalize(statement); result != .Ok {
        execution.finalized = false
        execution.cleanup_failure = native_failure(
            execution, "finalize", result, -1)
        if failure == nil {
            failure = execution.cleanup_failure
        }
    }
    return failure
}

// Prepare one native tail and retain ownership until execution or explicit failed-prepare cleanup.
prepare_next :: proc(
    execution: ^Case_Execution, source: cstring,
    length, offset: int) -> Native_Preparation {
    statement: ^raw.Statement
    tail: cstring
    first := cstring(rawptr(uintptr(rawptr(source)) + uintptr(offset)))
    code := raw.sqlite3_prepare_v3(
        execution.database, first, c.int(length - offset), 0, &statement, &tail)
    after := int(uintptr(rawptr(tail)) - uintptr(rawptr(source)))
    failure: ^Failure
    if code != .Ok {
        failure = native_failure(execution, "prepare", code, offset)
    } else if after <= offset || after > length {
        failure = make_failure(
            execution, "prepare", .Internal, "native tail made invalid progress")
    }
    if failure != nil && statement != nil {
        if result := raw.sqlite3_finalize(statement); result != .Ok {
            execution.finalized = false
            execution.cleanup_failure = native_failure(
                execution, "finalize", result, -1)
        }
    }
    return {statement, after, failure}
}

// Process native tails, including null statements and comments, without SQL splitting.
run_step :: proc(execution: ^Case_Execution, step: Step, output: ^Step_Result) {
    output.attempted = true
    output.status = "failed"
    source := strings.clone_to_cstring(step.source, execution.allocator)
    allocator := execution.allocator
    used := make(map[int]bool, allocator)
    offset := 0
    for offset < len(step.source) {
        prepared := prepare_next(execution, source, len(step.source), offset)
        if prepared.failure != nil {
            output.failure = failure_value(prepared.failure)
            return
        }
        if prepared.statement != nil {
            output.statement_count += 1
            output.failure = failure_value(run_statement(
                execution, prepared.statement, step, {offset, prepared.after}, &used))
            if output.failure != nil {
                return
            }
        }
        offset = prepared.after
        output.processed_bytes = offset
    }
    for bind in step.binds {
        if !used[bind.slot] {
            output.failure = failure_value(make_failure(
                execution, "bind", .Range, "extra binding unused by the complete step"))
            return
        }
    }
    output.status = "passed"
    output.prepared = true
    output.executed = step.mode == "execute"
}

// Preserve the first failure and expose transaction completion before cleanup rollback.
finish_case :: proc(
    execution: ^Case_Execution, connection: ^sqlite.Connection, output: ^Result) {
    output.transaction_complete = raw.sqlite3_get_autocommit(connection.handle) != 0
    if !output.transaction_complete {
        if output.failure == nil {
            output.failure = failure_value(make_failure(
                execution, "transaction", .Error, "case left a transaction open"))
        }
        sqlite.connection_exec(connection, "ROLLBACK")
    }
    if failure := sqlite.connection_close(connection); failure.result != .Ok {
        output.failure = failure_value(native_failure(
            execution, "close", failure.result, -1))
    } else {
        output.cleanup.closed = true
    }
    if output.failure == nil && output.cleanup.finalized &&
        output.cleanup.closed && output.transaction_complete {
        output.status = "passed"
    }
}

// Snapshot actual provider capabilities and initialize exact identity echoes for every declared step.
initial_result :: proc(execution: ^Case_Execution, request: Request) -> Result {
    allocator := execution.allocator
    capabilities := make([]string, 3, allocator)
    count := 0
    if raw.sqlite3_compileoption_used("ENABLE_FTS5") != 0 {
        capabilities[count] = "fts5"
        count += 1
    }
    capabilities[count] = "spellfix1"
    count += 1
    capabilities[count] = "history_matches"
    count += 1
    output: Result = {
        protocol_version = 1,
        case_id = request.case_id,
        status = "failed",
        completed = true,
        provider = {
            identity = strings.clone(string(raw.sqlite3_sourceid()), allocator),
            version = strings.clone(string(raw.sqlite3_libversion()), allocator),
            capabilities = capabilities[:count],
        },
        steps = make([]Step_Result, len(request.steps), allocator),
    }
    output.cleanup.finalized = true
    for step, index in request.steps {
        output.steps[index] = {
            id = step.id,
            source_id = step.source_id,
            digest = step.digest,
            mode = step.mode,
            status = "skipped",
        }
    }
    return output
}

// Run exactly one disposable case with explicit module admission and real cleanup evidence.
run_case :: proc(execution: ^Case_Execution, request: Request) -> Result {
    output := initial_result(execution, request)
    connection: sqlite.Connection
    opened := sqlite.connection_open(
        &connection, ":memory:", .Readwrite_Create, execution.allocator)
    if opened.result != .Ok {
        output.failure = failure_value(make_failure(
            execution, "capability", opened.result, "could not open in-memory provider"))
        output.cleanup.closed = connection.handle == nil
        return output
    }
    guard: Guard
    execution.database = connection.handle
    execution.finalized = true
    output.failure = failure_value(register_requirements(
        execution, &connection, request.requirements, &guard))
    if output.failure == nil {
        if code := configure_connection(&connection, &guard); code != .Ok {
            output.failure = failure_value(native_failure(
                execution, "capability", code, -1))
        }
    }
    for step, index in request.steps {
        if output.failure != nil {
            break
        }
        run_step(execution, step, &output.steps[index])
        output.failure = output.steps[index].failure
        if execution.cleanup_failure != nil {
            output.failure = failure_value(execution.cleanup_failure)
        }
    }
    output.cleanup.finalized = execution.finalized
    finish_case(execution, &connection, &output)
    return output
}

// Read bounded stdin before decoding; stdout is reserved for one protocol response.
read_request :: proc(execution: ^Case_Execution) -> ([]u8, bool) {
    allocator := execution.allocator
    data := make([]u8, MAX_REQUEST_BYTES + 1, allocator)
    count := 0
    for count < len(data) {
        size, error := os.read(os.stdin, data[count:])
        count += size
        if error == .EOF || (error == nil && size == 0) {
            return data[:count], count <= MAX_REQUEST_BYTES
        }
        if error != nil {
            return nil, false
        }
    }
    return nil, false
}

// Execute the versioned single-case stdin/stdout protocol within the caller's owned arena.
run_protocol :: proc(execution: ^Case_Execution) -> int {
    data, read_ok := read_request(execution)
    request: Request
    if !read_ok || !request_shape(execution, data) ||
        json.unmarshal(
            data, &request, spec = .JSON, allocator = execution.allocator) != nil ||
        !valid_request(execution, request) {
        fmt.eprintln("sqlite-validator: invalid protocol v1 request, digest, or limit")
        return 2
    }
    result := run_case(execution, request)
    encoded, error := json.marshal(result, allocator = execution.allocator)
    if error != nil || len(encoded) > MAX_RESULT_BYTES {
        fmt.eprintln(
            "sqlite-validator: result encoding failed or output limit exceeded", error)
        return 3
    }
    fmt.println(string(encoded))
    return 0
}

// Keep request snapshots, copied diagnostics, and output alive until serialization completes.
main :: proc() {
    arena: virtual.Arena
    if virtual.arena_init_growing(&arena) != nil {
        fmt.eprintln("sqlite-validator: could not initialize request arena")
        os.exit(3)
    }
    execution: Case_Execution = {
        allocator = virtual.arena_allocator(&arena),
    }
    code := run_protocol(&execution)
    virtual.arena_destroy(&arena)
    os.exit(code)
}
