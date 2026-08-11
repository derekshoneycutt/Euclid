package trace

// Semantic trace foundation for bounded JSONL diagnostics.
// This module owns trace configuration validation, fixed-capacity record buffering,
// structured JSON serialization, file lifecycle, and overflow policy.
// It is intentionally disabled by default and must remain inert when disabled.

import "../core"

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

TRACE_SCHEMA_NAME :: "euclid.semantic-trace"
TRACE_SCHEMA_VERSION :: 1
TRACE_RUN_ID_TEXT_CAPACITY :: core.TRACE_RUN_ID_CAPACITY
TRACE_OUTPUT_PATH_CAPACITY :: core.TRACE_OUTPUT_PATH_CAPACITY

Trace_Output_Mode :: core.Trace_Output_Mode
Trace_Category :: core.Trace_Category
Trace_Category_Set :: core.Trace_Category_Set
Trace_Event_Record :: core.Trace_Event_Record

Trace_Configuration :: struct {
    output_path_len: int,
    output_path: [TRACE_OUTPUT_PATH_CAPACITY]u8,
}

//   Report whether trace collection is currently enabled and available.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - enabled: true when trace events should be recorded.
is_enabled :: proc(state: ^core.Trace_State) -> bool {
    return state != nil && state^.enabled && !state^.invalid
}

//   Report whether strict trace validity has been lost.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - invalid: true when strict mode detected trace-invalidating loss or failure.
is_invalid :: proc(state: ^core.Trace_State) -> bool {
    return state != nil && state^.invalid
}

//   Report whether trace state is present and currently valid.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - valid: true when the trace state exists and has not been invalidated.
state_is_valid :: proc(state: ^core.Trace_State) -> bool {
    return state != nil && !state^.invalid
}

//   Copy bounded text into one fixed-capacity trace field.
//
// Parameters:
//   - destination: Fixed-capacity byte destination.
//   - text: Source text to copy.
//
// Returns:
//   - length: Number of copied bytes.
copy_trace_text :: proc(destination: []u8, text: string) -> int {
    text_bytes := transmute([]u8)text
    copy_len := min(len(destination), len(text_bytes))
    if copy_len > 0 {
        copy(destination[:copy_len], text_bytes[:copy_len])
    }
    return copy_len
}

//   Assign a bounded output path into trace configuration.
//
// Parameters:
//   - config: Trace configuration to update.
//   - output_path: Candidate output path text.
//
// Returns:
//   - ok: true when the path was accepted into bounded storage.
set_output_path :: proc(config: ^Trace_Configuration, output_path: string) -> bool {
    if config == nil || len(output_path) > len(config^.output_path) {
        return false
    }

    config^.output_path_len = copy_trace_text(config^.output_path[:], output_path)
    return true
}

//   Return the configured output path text, or empty when unset.
//
// Parameters:
//   - config: Trace configuration to inspect.
//
// Returns:
//   - output_path: Current configured path text.
configured_output_path :: proc(config: ^Trace_Configuration) -> string {
    if config == nil || config^.output_path_len <= 0 {
        return ""
    }

    return string(config^.output_path[:config^.output_path_len])
}

//   Report whether one category is enabled for publication.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - category: Event category to test.
//
// Returns:
//   - allowed: true when the category passes filtering.
category_enabled :: proc(state: ^core.Trace_State, category: Trace_Category) -> bool {
    if !is_enabled(state) {
        return false
    }

    return category in state^.categories
}

//   Append a text fragment to one bounded output builder.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - text: Text to append.
//
// Returns:
//   - ok: true when the fragment fit and was appended.
append_builder_text :: proc(buffer: []u8, length: ^int, text: string) -> bool {
    if length == nil || length^ < 0 || length^ > len(buffer) {
        return false
    }

    text_bytes := transmute([]u8)text
    if len(text_bytes) > len(buffer) - length^ {
        return false
    }

    copy(buffer[length^:length^ + len(text_bytes)], text_bytes)
    length^ += len(text_bytes)
    return true
}

//   Append one JSON-escaped string body without surrounding quotes.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - text: Source text to escape and append.
//
// Returns:
//   - ok: true when the escaped body fit and was appended.
append_json_escaped_body :: proc(buffer: []u8, length: ^int, text: string) -> bool {
    for ch in text {
        escaped := ""
        escaped_len := 0
        switch ch {
        case '"':
            escaped = "\\\""
            escaped_len = 2
        case '\\':
            escaped = "\\\\"
            escaped_len = 2
        case '\b':
            escaped = "\\b"
            escaped_len = 2
        case '\f':
            escaped = "\\f"
            escaped_len = 2
        case '\n':
            escaped = "\\n"
            escaped_len = 2
        case '\r':
            escaped = "\\r"
            escaped_len = 2
        case '\t':
            escaped = "\\t"
            escaped_len = 2
        case:
            if ch < 0x20 {
                escaped = fmt.tprintf("\\u%04x", int(ch))
                escaped_len = len(escaped)
            } else {
                if length^ >= len(buffer) {
                    return false
                }
                buffer[length^] = u8(ch)
                length^ += 1
                continue
            }
        }

        if !append_builder_text(buffer, length, escaped[:escaped_len]) {
            return false
        }
    }

    return true
}

//   Append one complete JSON string value with quotes and escaping.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - text: Source string value.
//
// Returns:
//   - ok: true when the JSON string fit and was appended.
append_json_string :: proc(buffer: []u8, length: ^int, text: string) -> bool {
    if !append_builder_text(buffer, length, "\"") {
        return false
    }
    if !append_json_escaped_body(buffer, length, text) {
        return false
    }
    return append_builder_text(buffer, length, "\"")
}

//   Append one JSON boolean field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - name: Field name.
//   - value: Boolean value.
//
// Returns:
//   - ok: true when the field fit and was appended.
append_json_bool_field :: proc(
    buffer: []u8, length: ^int, name: string, value: bool) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":") {
        return false
    }
    return append_builder_text(buffer, length, value ? "true" : "false")
}

//   Append one signed integer JSON field.
append_json_signed_field :: proc(
    buffer: []u8, length: ^int, name: string, value: int) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":") {
        return false
    }
    return append_builder_text(buffer, length, fmt.tprintf("%d", value))
}

//   Append one JSON numeric field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - name: Field name.
//   - value: Numeric value.
//
// Returns:
//   - ok: true when the field fit and was appended.
append_json_number_field :: proc(
    buffer: []u8, length: ^int, name: string, value: u64) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":") {
        return false
    }
    return append_builder_text(buffer, length, fmt.tprintf("%d", value))
}

//   Append one JSON string field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - name: Field name.
//   - value: String value.
//
// Returns:
//   - ok: true when the field fit and was appended.
append_json_string_field :: proc(
    buffer: []u8, length: ^int, name: string, value: string) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":") {
        return false
    }
    return append_json_string(buffer, length, value)
}

//   Append a comma when this is not the first JSON field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - first_field: true before writing the first field.
//
// Returns:
//   - ok: true when any separator was appended successfully.
append_json_separator :: proc(buffer: []u8, length: ^int, first_field: bool) -> bool {
    if first_field {
        return true
    }

    return append_builder_text(buffer, length, ",")
}

//   Serialize one trace event envelope and payload into JSONL bytes.
//
// Parameters:
//   - state: Trace state containing run identity.
//   - record: Event record to serialize.
//   - out_buffer: Destination byte buffer.
//
// Returns:
//   - out_len: Number of bytes written.
//   - ok: true when serialization succeeded and fit in capacity.
serialize_event_record :: proc(
    state: ^core.Trace_State,
    record: ^Trace_Event_Record,
    out_buffer: []u8) -> (int, bool) {

    if state == nil || record == nil {
        return 0, false
    }

    out_len := 0
    if !append_builder_text(out_buffer, &out_len, "{") {
        return 0, false
    }

    if !append_json_string_field(out_buffer, &out_len, "schema", TRACE_SCHEMA_NAME) ||
        !append_builder_text(out_buffer, &out_len, ",") ||
        !append_json_number_field(out_buffer, &out_len, "version", TRACE_SCHEMA_VERSION) {
        return 0, false
    }

    if !append_event_identity_fields(state, record, out_buffer, &out_len) ||
        !append_event_payload_field(record, out_buffer, &out_len) {
        return 0, false
    }

    if !append_builder_text(out_buffer, &out_len, "}\n") {
        return 0, false
    }

    return out_len, true
}

//   Append event identity fields shared by all trace records.
//
// Parameters:
//   - state: Trace state containing run identity.
//   - record: Event record to serialize.
//   - out_buffer: Destination byte buffer.
//   - out_len: Current output length, updated on success.
//
// Returns:
//   - ok: true when identity fields were appended.
append_event_identity_fields :: proc(
    state: ^core.Trace_State,
    record: ^Trace_Event_Record,
    out_buffer: []u8,
    out_len: ^int) -> bool {

    event_text := string(record^.event[:record^.event_len])
    if !append_builder_text(out_buffer, out_len, ",") ||
        !append_json_string_field(out_buffer, out_len, "event", event_text) ||
        !append_builder_text(out_buffer, out_len, ",") ||
        !append_json_number_field(out_buffer, out_len, "seq", record^.sequence) {
        return false
    }

    if state^.run_id_len <= 0 {
        return true
    }

    run_id_text := string(state^.run_id[:state^.run_id_len])
    return append_builder_text(out_buffer, out_len, ",") &&
        append_json_string_field(out_buffer, out_len, "run_id", run_id_text)
}

//   Append an optional payload field for one trace event.
//
// Parameters:
//   - record: Event record to serialize.
//   - out_buffer: Destination byte buffer.
//   - out_len: Current output length, updated on success.
//
// Returns:
//   - ok: true when the payload field was appended or omitted.
append_event_payload_field :: proc(
    record: ^Trace_Event_Record,
    out_buffer: []u8,
    out_len: ^int) -> bool {

    if record^.payload_len <= 0 {
        return true
    }

    payload_text := string(record^.payload[:record^.payload_len])
    return append_builder_text(out_buffer, out_len, ",") &&
        append_json_string(out_buffer, out_len, "payload") &&
        append_builder_text(out_buffer, out_len, ":") &&
        append_builder_text(out_buffer, out_len, payload_text)
}

//   Build the standard trace.configuration payload body.
//
// Parameters:
//   - state: Trace state containing active configuration.
//   - out_buffer: Destination payload buffer.
//
// Returns:
//   - out_len: Number of bytes written.
//   - ok: true when payload serialization succeeded.
build_configuration_payload :: proc(
    state: ^core.Trace_State, out_buffer: []u8) -> (int, bool) {

    if state == nil {
        return 0, false
    }

    out_len := 0
    if !append_builder_text(out_buffer, &out_len, "{") {
        return 0, false
    }

    if !append_json_string_field(
        out_buffer, &out_len, "output_mode", output_mode_name(state^.output_mode)) {
        return 0, false
    }
    if !append_builder_text(out_buffer, &out_len, ",") ||
        !append_json_string_field(
            out_buffer, &out_len, "strict", state^.strict ? "true" : "false") {
        return 0, false
    }
    if !append_builder_text(out_buffer, &out_len, ",") ||
        !append_json_number_field(out_buffer, &out_len, "category_mask",
            trace_category_mask(state^.categories)) {
        return 0, false
    }

    output_path := string(state^.output_path[:state^.output_path_len])
    if state^.output_path_len > 0 {
        if !append_builder_text(out_buffer, &out_len, ",") ||
            !append_json_string_field(out_buffer, &out_len, "output_path", output_path) {
            return 0, false
        }
    }

    if !append_builder_text(out_buffer, &out_len, "}") {
        return 0, false
    }

    return out_len, true
}

//   Convert trace output mode to a stable string token.
//
// Parameters:
//   - mode: Output mode enum.
//
// Returns:
//   - name: Stable lowercase output mode token.
output_mode_name :: proc(mode: Trace_Output_Mode) -> string {
    switch mode {
    case .Disabled:
        return "disabled"
    case .Stdout:
        return "stdout"
    case .File:
        return "file"
    case .Sink:
        return "sink"
    }
    return "unknown"
}

//   Convert the active category set into a stable integer mask for diagnostics.
//
// Parameters:
//   - categories: Active category filter set.
//
// Returns:
//   - mask: Integer mask with one bit per enabled category.
trace_category_mask :: proc(categories: Trace_Category_Set) -> u64 {
    mask: u64 = 0
    if .Trace in categories {
        mask |= 1 << 0
    }
    if .Runtime in categories {
        mask |= 1 << 1
    }
    if .Animation in categories {
        mask |= 1 << 2
    }
    if .Geometry in categories {
        mask |= 1 << 3
    }
    if .Tools in categories {
        mask |= 1 << 4
    }
    if .Particles in categories {
        mask |= 1 << 5
    }
    if .View in categories {
        mask |= 1 << 6
    }
    return mask
}

//   Reset trace runtime counters and buffers without changing configuration.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - none.
reset_runtime_state :: proc(state: ^core.Trace_State) {
    if state == nil {
        return
    }

    state^.records_head = 0
    state^.records_count = 0
    state^.next_sequence = 1
    state^.emitted_count = 0
    state^.dropped_count = 0
    state^.overflow_reported = false
    state^.invalid = false
    state^.finished = false
}

//   Generate a stable per-run identity string for trace correlation.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when run id was assigned.
assign_run_id :: proc(state: ^core.Trace_State) -> bool {
    if state == nil {
        return false
    }

    timestamp := time.time_to_unix_nano(time.now())
    pid := os.get_pid()
    state^.run_id_len = copy_trace_text(
        state^.run_id[:], fmt.tprintf("run-%d-%d", pid, timestamp))
    return state^.run_id_len > 0
}

//   Resolve effective category set from optional CLI selection text.
//
// Parameters:
//   - categories_text: Optional comma-separated category list.
//
// Returns:
//   - categories: Parsed category set.
//   - ok: true when text was valid.
resolve_categories :: proc(categories_text: string) -> (Trace_Category_Set, bool) {
    if len(categories_text) == 0 {
        return Trace_Category_Set{
            .Trace,
            .Runtime,
            .Animation,
            .Geometry,
            .Tools,
            .Particles,
            .View,
        }, true
    }

    categories := Trace_Category_Set{.Trace}
    start := 0
    for i in 0..=len(categories_text) {
        if i < len(categories_text) && categories_text[i] != ',' {
            continue
        }

        token := categories_text[start:i]
        switch token {
        case "runtime":
            categories += {.Runtime}
        case "animation":
            categories += {.Animation}
        case "geometry":
            categories += {.Geometry}
        case "tools":
            categories += {.Tools}
        case "particles":
            categories += {.Particles}
        case "view":
            categories += {.View}
        case:
            return {}, false
        }
        start = i + 1
    }

    return categories, true
}

//   Configure trace state from validated command-line settings.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - settings: Parsed application run settings.
//
// Returns:
//   - ok: true when trace configuration is valid and applied.
configure_from_settings :: proc(
    state: ^core.Trace_State, settings: ^core.Euclid_Run_Settings) -> bool {

    if state == nil || settings == nil {
        return false
    }

    state^ = {}
    state^.enabled = settings^.semantic_trace_enabled
    state^.strict = settings^.semantic_trace_strict
    state^.output_mode = .Disabled
    state^.categories = Trace_Category_Set{.Trace}

    if !state^.enabled {
        reset_runtime_state(state)
        return true
    }

    categories, ok := resolve_categories(settings^.semantic_trace_events)
    if !ok {
        fmt.eprintln("Invalid --semantic-trace-events value: ",
            settings^.semantic_trace_events)
        state^.enabled = false
        state^.invalid = true
        return false
    }

    state^.categories = categories
    state^.output_mode = .Stdout
    if len(settings^.semantic_trace_output) > 0 {
        if len(settings^.semantic_trace_output) > len(state^.output_path) {
            fmt.eprintln("Invalid --semantic-trace-output value: path exceeds capacity.")
            state^.enabled = false
            state^.invalid = true
            return false
        }
        state^.output_path_len = copy_trace_text(
            state^.output_path[:], settings^.semantic_trace_output)
        state^.output_mode = .File
    }

    reset_runtime_state(state)
    return assign_run_id(state)
}

//   Open the trace destination and write startup lifecycle records.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when tracing was successfully started or is disabled.
begin_trace :: proc(state: ^core.Trace_State) -> bool {
    if state == nil || !state^.enabled {
        return true
    }

    if state^.output_mode == .File {
        output_path := string(state^.output_path[:state^.output_path_len])
        handle, err := os.open(output_path, {.Create, .Write, .Trunc})
        if err != nil {
            fmt.eprintln("Failed to open semantic trace output: ", output_path)
            state^.invalid = true
            return false
        }
        state^.output_handle = handle
        state^.output_open = true
    }

    if !record_event(state, .Trace, "trace.started", "") {
        return false
    }

    payload_len, payload_ok :=
        build_configuration_payload(state, state^.serialize_buffer[:])
    if !payload_ok {
        state^.invalid = true
        return false
    }

    return record_event(
        state,
        .Trace,
        "trace.configuration",
        string(state^.serialize_buffer[:payload_len]))
}

//   Reserve and enqueue one trace event record.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - category: Event category.
//   - event_name: Stable dotted event name.
//   - payload_json: Optional payload JSON object text.
//
// Returns:
//   - ok: true when the record was queued.
record_event :: proc(
    state: ^core.Trace_State,
    category: Trace_Category,
    event_name: string,
    payload_json: string) -> bool {

    if !is_enabled(state) || !category_enabled(state, category) {
        return state == nil || !state^.invalid
    }

    if len(event_name) > len(state^.records[0].event) ||
        len(payload_json) > len(state^.records[0].payload) {
        handle_overflow(state)
        return !state^.invalid
    }

    if state^.records_count >= len(state^.records) {
        handle_overflow(state)
        return !state^.invalid
    }

    record_index := (state^.records_head + state^.records_count) % len(state^.records)
    record := &state^.records[record_index]
    record^ = {}
    record^.sequence = state^.next_sequence
    state^.next_sequence += 1
    record^.category = category
    record^.event_len = copy_trace_text(record^.event[:], event_name)
    record^.payload_len = copy_trace_text(record^.payload[:], payload_json)
    state^.records_count += 1
    return true
}

//   Handle record overflow according to strict/diagnostic policy.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - none.
handle_overflow :: proc(state: ^core.Trace_State) {
    if state == nil || !state^.enabled {
        return
    }

    state^.dropped_count += 1
    if state^.strict {
        state^.invalid = true
    }
}

//   Emit one overflow summary record when capacity becomes available.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when no overflow summary is pending.
flush_overflow_notice :: proc(state: ^core.Trace_State) -> bool {
    if !is_enabled(state) || state^.overflow_reported || state^.dropped_count == 0 {
        return true
    }
    if state^.records_count >= len(state^.records) {
        return true
    }

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{\"dropped_count\":") ||
        !append_builder_text(
            payload_buffer, &payload_len, fmt.tprintf("%d", state^.dropped_count)) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        state^.invalid = true
        return false
    }

    if !record_event(state, .Trace, "trace.overflow",
        string(payload_buffer[:payload_len])) {
        return false
    }
    state^.overflow_reported = true
    return true
}

//   Write one serialized JSONL line to the configured trace destination.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - line: Serialized JSONL bytes.
//
// Returns:
//   - ok: true when the line was fully written.
write_trace_line :: proc(state: ^core.Trace_State, line: []u8) -> bool {
    if state == nil || !state^.enabled {
        return true
    }

    if state^.output_mode == .Stdout {
        fmt.println(string(line))
        return true
    }
    if state^.output_mode == .Sink {
        return true
    }

    if !state^.output_open {
        state^.invalid = true
        return false
    }

    written := 0
    for written < len(line) {
        n, err := os.write(state^.output_handle, line[written:])
        if err != nil || n <= 0 {
            state^.invalid = true
            return false
        }
        written += n
    }

    return true
}

//   Drain queued trace records in monotonic sequence order.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when all available records drained successfully.
drain_trace :: proc(state: ^core.Trace_State) -> bool {
    if !is_enabled(state) {
        return state == nil || !state^.invalid
    }

    if !flush_overflow_notice(state) {
        return false
    }

    for state^.records_count > 0 {
        record := &state^.records[state^.records_head]
        line_len, ok := serialize_event_record(state, record, state^.serialize_buffer[:])
        if !ok {
            state^.invalid = true
            return false
        }
        if !write_trace_line(state, state^.serialize_buffer[:line_len]) {
            return false
        }

        state^.records_head = (state^.records_head + 1) % len(state^.records)
        state^.records_count -= 1
        state^.emitted_count += 1
    }

    if state^.dropped_count > 0 && state^.records_count == 0 && state^.overflow_reported {
        state^.overflow_reported = false
    }

    return true
}

//   Flush any pending trace records and destination buffers.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when flush completed or tracing is disabled.
flush_trace :: proc(state: ^core.Trace_State) -> bool {
    if state == nil || !state^.enabled {
        return true
    }

    if !drain_trace(state) {
        return false
    }

    if state^.output_mode == .File && state^.output_open {
        if os.flush(state^.output_handle) != nil {
            state^.invalid = true
            return false
        }
    }

    return true
}

//   Finish trace output, emit summary when possible, and close destination.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when shutdown finished without invalid trace state.
finish_trace :: proc(state: ^core.Trace_State) -> bool {
    if state == nil || !state^.enabled {
        return true
    }

    if !state^.finished {
        if !record_finish_summary(state) {
            state^.invalid = true
        }
        state^.finished = true
    }

    ok := flush_trace(state)
    if state^.output_mode == .File && state^.output_open {
        if os.close(state^.output_handle) != nil {
            state^.invalid = true
            ok = false
        }
        state^.output_open = false
    }

    return ok && !state^.invalid
}

//   Build and enqueue the terminal trace.finished summary event.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - ok: true when the summary payload was built and queued.
record_finish_summary :: proc(state: ^core.Trace_State) -> bool {
    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{\"emitted_count\":") ||
        !append_builder_text(
            payload_buffer, &payload_len, fmt.tprintf("%d", state^.emitted_count)) ||
        !append_builder_text(payload_buffer, &payload_len, ",\"dropped_count\":") ||
        !append_builder_text(
            payload_buffer, &payload_len, fmt.tprintf("%d", state^.dropped_count)) ||
        !append_builder_text(payload_buffer, &payload_len, ",\"invalid\":") ||
        !append_builder_text(
            payload_buffer, &payload_len, state^.invalid ? "true" : "false") ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(
        state,
        .Trace,
        "trace.finished",
        string(payload_buffer[:payload_len]))
}

//   Validate and apply CLI-provided semantic trace options.
//
// Parameters:
//   - settings: Parsed application settings to update.
//   - arg: Full command-line argument.
//
// Returns:
//   - handled: true when the argument was recognized as semantic trace config.
//   - ok: true when recognized arguments were valid.
parse_semantic_trace_argument :: proc(
    settings: ^core.Euclid_Run_Settings, arg: string) -> (bool, bool) {

    if settings == nil {
        return false, false
    }

    if arg == "--semantic-trace" {
        settings^.semantic_trace_enabled = true
        return true, true
    }
    if arg == "--semantic-trace-strict" {
        settings^.semantic_trace_strict = true
        settings^.semantic_trace_enabled = true
        return true, true
    }

    output_prefix := "--semantic-trace-output="
    events_prefix := "--semantic-trace-events="
    if strings.has_prefix(arg, output_prefix) {
        settings^.semantic_trace_output = arg[len(output_prefix):]
        settings^.semantic_trace_enabled = true
        return true, len(settings^.semantic_trace_output) > 0
    }
    if strings.has_prefix(arg, events_prefix) {
        settings^.semantic_trace_events = arg[len(events_prefix):]
        settings^.semantic_trace_enabled = true
        _, ok := resolve_categories(settings^.semantic_trace_events)
        return true, ok
    }

    return false, false
}

//   Report whether strict-mode invalid state should fail the process.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - should_fail: true when strict trace validity was lost.
should_fail_process :: proc(state: ^core.Trace_State) -> bool {
    return state != nil && state^.enabled && state^.strict && state^.invalid
}

//   Free temporary allocations accumulated while parsing trace configuration.
//
// Parameters:
//   - none.
//
// Returns:
//   - none.
release_trace_temp_allocations :: proc() {
    free_all(context.temp_allocator)
}

//   Report trace state counters for diagnostics.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - counters: Snapshot of emitted and dropped counts.
trace_counters :: proc(state: ^core.Trace_State) -> core.Trace_Counters {
    if state == nil {
        return {}
    }

    return core.Trace_Counters{
        emitted_count = state^.emitted_count,
        dropped_count = state^.dropped_count,
        invalid = state^.invalid,
    }
}

//   Record one runtime lifecycle event.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Runtime event name.
//
// Returns:
//   - ok: true when event was queued or tracing disabled.
record_runtime_event :: proc(state: ^core.Trace_State, event_name: string) -> bool {
    return record_event(state, .Runtime, event_name, "")
}

//   Record one animation lifecycle event.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Animation event name.
//
// Returns:
//   - ok: true when event was queued or tracing disabled.
record_animation_event :: proc(state: ^core.Trace_State, event_name: string) -> bool {
    return record_event(state, .Animation, event_name, "")
}

//   Record one runtime lifecycle event with structured payload fields.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Runtime event name.
//   - runtime_generation: Published runtime generation.
//   - reload_state: Numeric reload state value.
//   - request_id: Correlated request identity when available.
//
// Returns:
//   - ok: true when the event was queued.
record_runtime_event_ex :: proc(
    state: ^core.Trace_State,
    event_name: string,
    runtime_generation: u64,
    reload_state: int,
    request_id: u64) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_json_number_field(
            payload_buffer, &payload_len, "runtime_generation", runtime_generation) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_number_field(
            payload_buffer, &payload_len, "reload_state", u64(reload_state)) {
        return false
    }
    if request_id > 0 {
        if !append_builder_text(payload_buffer, &payload_len, ",") ||
            !append_json_number_field(payload_buffer,
                &payload_len, "request_id", request_id) {
            return false
        }
    }
    if !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(state, .Runtime, event_name, string(payload_buffer[:payload_len]))
}

//   Record one animation lifecycle event with structured payload fields.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Animation event name.
//   - animation_generation: Active animation lifecycle generation.
//   - animation_tick: Tick sequence associated with the event when available.
//   - animation_id: Stable animation UUID text when available.
//   - reason: Optional rejection reason token.
//
// Returns:
//   - ok: true when the event was queued.
record_animation_event_ex :: proc(
    state: ^core.Trace_State,
    event_name: string,
    animation_generation: u64,
    animation_tick: u64,
    animation_id: string,
    reason: string) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_json_number_field(
            payload_buffer, &payload_len, "animation_generation", animation_generation) {
        return false
    }
    if animation_tick > 0 {
        if !append_builder_text(payload_buffer, &payload_len, ",") ||
            !append_json_number_field(
                payload_buffer, &payload_len, "animation_tick", animation_tick) {
            return false
        }
    }
    if len(animation_id) > 0 {
        if !append_builder_text(payload_buffer, &payload_len, ",") ||
            !append_json_string_field(payload_buffer,
                &payload_len, "animation_id", animation_id) {
            return false
        }
    }
    if len(reason) > 0 {
        if !append_builder_text(payload_buffer, &payload_len, ",") ||
            !append_json_string_field(payload_buffer, &payload_len, "reason", reason) {
            return false
        }
    }
    if !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(state, .Animation, event_name,
        string(payload_buffer[:payload_len]))
}

//   Append one JSON vector3 array field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - name: Field name.
//   - value: Vector value to encode.
//
// Returns:
//   - ok: true when the field fit and was appended.
append_json_vector3_field :: proc(
    buffer: []u8, length: ^int, name: string, value: core.Vector3) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":[") ||
        !append_builder_text(buffer, length, fmt.tprintf("%g", value.x)) ||
        !append_builder_text(buffer, length, ",") ||
        !append_builder_text(buffer, length, fmt.tprintf("%g", value.y)) ||
        !append_builder_text(buffer, length, ",") ||
        !append_builder_text(buffer, length, fmt.tprintf("%g", value.z)) ||
        !append_builder_text(buffer, length, "]") {
        return false
    }
    return true
}

//   Append one JSON color array field.
//
// Parameters:
//   - buffer: Destination byte buffer.
//   - length: Current valid length, updated on success.
//   - name: Field name.
//   - value: Color value to encode.
//
// Returns:
//   - ok: true when the field fit and was appended.
append_json_color_field :: proc(
    buffer: []u8, length: ^int, name: string, value: core.Bridge_Color) -> bool {

    if !append_json_string(buffer, length, name) ||
        !append_builder_text(buffer, length, ":[") ||
        !append_builder_text(buffer, length, fmt.tprintf("%d", value.r)) ||
        !append_builder_text(buffer, length, ",") ||
        !append_builder_text(buffer, length, fmt.tprintf("%d", value.g)) ||
        !append_builder_text(buffer, length, ",") ||
        !append_builder_text(buffer, length, fmt.tprintf("%d", value.b)) ||
        !append_builder_text(buffer, length, ",") ||
        !append_builder_text(buffer, length, fmt.tprintf("%d", value.a)) ||
        !append_builder_text(buffer, length, "]") {
        return false
    }
    return true
}

//   Append one optional JSON field separator and marker when present.
append_optional_separator :: proc(
    payload_buffer: []u8, payload_len: ^int, present: bool) -> bool {

    if !present {
        return true
    }
    return append_builder_text(payload_buffer, payload_len, ",")
}

//   Append optional vector fields used by point and tool events.
append_optional_vector_field :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    value: Maybe(core.Vector3)) -> bool {

    if value == nil {
        return true
    }
    return append_optional_separator(payload_buffer, payload_len, true) &&
        append_json_vector3_field(payload_buffer, payload_len, name, value.?)
}

//   Append one optional boolean JSON field.
append_optional_bool_field :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    value: Maybe(bool)) -> bool {

    if value == nil {
        return true
    }
    return append_optional_separator(payload_buffer, payload_len, true) &&
        append_json_bool_field(payload_buffer, payload_len, name, value.?)
}

//   Append one optional integer JSON field.
append_optional_int_field :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    value: Maybe(int)) -> bool {

    if value == nil {
        return true
    }
    return append_optional_separator(payload_buffer, payload_len, true) &&
        append_json_number_field(payload_buffer, payload_len, name, u64(value.?))
}

//   Append one optional float JSON field using compact numeric formatting.
append_optional_float_field :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    value: Maybe(f32)) -> bool {

    if value == nil {
        return true
    }
    return append_optional_separator(payload_buffer, payload_len, true) &&
        append_json_string(payload_buffer, payload_len, name) &&
        append_builder_text(payload_buffer, payload_len, ":") &&
        append_builder_text(payload_buffer, payload_len, fmt.tprintf("%g", value.?))
}

//   Append one optional color JSON field.
append_optional_color_field :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    value: Maybe(core.Bridge_Color)) -> bool {

    if value == nil {
        return true
    }
    return append_optional_separator(payload_buffer, payload_len, true) &&
        append_json_color_field(payload_buffer, payload_len, name, value.?)
}

//   Append optional point-event fields to one payload buffer.
//
// Parameters:
//   - payload_buffer: Destination payload buffer.
//   - payload_len: Current payload length, updated on success.
//   - from_position: Optional prior position.
//   - to_position: Optional committed position.
//   - visible: Optional committed visibility state.
//   - brush_size: Optional committed brush size.
//   - offset: Optional committed offset.
//   - color: Optional committed color.
//
// Returns:
//   - ok: true when all present optional fields were appended.
append_point_event_optional_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    from_position: Maybe(core.Vector3),
    to_position: Maybe(core.Vector3),
    visible: Maybe(bool),
    brush_size: Maybe(f32),
    offset: Maybe(f32),
    color: Maybe(core.Bridge_Color)) -> bool {

    return append_optional_vector_field(payload_buffer, payload_len,
            "from", from_position) &&
        append_optional_vector_field(payload_buffer, payload_len,
            "to", to_position) &&
        append_optional_bool_field(payload_buffer, payload_len,
            "visible", visible) &&
        append_optional_float_field(payload_buffer, payload_len,
            "brush_size", brush_size) &&
        append_optional_float_field(payload_buffer, payload_len,
            "offset", offset) &&
        append_optional_color_field(payload_buffer, payload_len,
            "color", color)
}

//   Record one committed point state transition.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Point event name.
//   - index: Canonical point index.
//   - from_position: Optional prior position for movement events.
//   - to_position: Optional committed position for movement events.
//   - visible: Optional committed visibility state.
//   - brush_size: Optional committed brush size.
//   - offset: Optional committed offset.
//   - color: Optional committed color.
//
// Returns:
//   - ok: true when the event was queued.
record_point_event :: proc(
    state: ^core.Trace_State,
    event_name: string,
    index: int,
    from_position: Maybe(core.Vector3),
    to_position: Maybe(core.Vector3),
    visible: Maybe(bool),
    brush_size: Maybe(f32),
    offset: Maybe(f32),
    color: Maybe(core.Bridge_Color)) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{\"kind\":\"point\",") ||
        !append_json_number_field(payload_buffer, &payload_len, "index", u64(index)) ||
        !append_point_event_optional_fields(
            payload_buffer,
            &payload_len,
            from_position,
            to_position,
            visible,
            brush_size,
            offset,
            color) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(state, .Geometry, event_name,
        string(payload_buffer[:payload_len]))
}

//   Append optional tool-event fields to one payload buffer.
//
// Parameters:
//   - payload_buffer: Destination payload buffer.
//   - payload_len: Current payload length, updated on success.
//   - joint_name: Optional joint token.
//   - position: Optional committed position.
//   - visible: Optional committed visibility state.
//   - active: Optional committed active marker.
//
// Returns:
//   - ok: true when all present optional fields were appended.
append_tool_event_optional_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    joint_name: string,
    position: Maybe(core.Vector3),
    visible: Maybe(bool),
    active: Maybe(int)) -> bool {

    if len(joint_name) > 0 &&
        (!append_builder_text(payload_buffer, payload_len, ",") ||
            !append_json_string_field(payload_buffer, payload_len, "joint", joint_name)) {
        return false
    }

    return append_optional_vector_field(payload_buffer, payload_len,
            "position", position) &&
        append_optional_bool_field(payload_buffer, payload_len,
            "visible", visible) &&
        append_optional_int_field(payload_buffer, payload_len,
            "active", active)
}

//   Record one committed tool state transition.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - event_name: Tool event name.
//   - tool_name: Stable tool token (`pen` or `compass`).
//   - joint_name: Optional joint token.
//   - position: Optional committed position.
//   - visible: Optional committed visibility state.
//   - active: Optional committed active marker.
//
// Returns:
//   - ok: true when the event was queued.
record_tool_event :: proc(
    state: ^core.Trace_State,
    event_name: string,
    tool_name: string,
    joint_name: string,
    position: Maybe(core.Vector3),
    visible: Maybe(bool),
    active: Maybe(int)) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_json_string_field(payload_buffer, &payload_len, "tool", tool_name) ||
        !append_tool_event_optional_fields(
            payload_buffer,
            &payload_len,
            joint_name,
            position,
            visible,
            active) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(state, .Tools, event_name, string(payload_buffer[:payload_len]))
}

//   Record one summarized particle emission event.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - kind: Particle kind token.
//   - layer: Particle layer token.
//   - count: Emitted particle count.
//   - source: Source world position.
//   - color: Source color.
//
// Returns:
//   - ok: true when the event was queued.
record_particles_emitted :: proc(
    state: ^core.Trace_State,
    kind: string,
    layer: string,
    count: int,
    source: core.Vector3,
    color: core.Bridge_Color) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_json_string_field(payload_buffer, &payload_len, "kind", kind) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_string_field(payload_buffer, &payload_len, "layer", layer) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_number_field(payload_buffer, &payload_len, "count", u64(count)) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_vector3_field(payload_buffer, &payload_len, "source", source) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_color_field(payload_buffer, &payload_len, "color", color) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(
        state, .Particles, "particles.emitted", string(payload_buffer[:payload_len]))
}

//   Record one post-solve constraint summary at a stable fixed-step boundary.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - fixed_step: Display-owned fixed-step sequence.
//   - simulation_time: Accumulated deterministic simulation time.
//   - active_constraints: Number of active constraint slots.
//   - next_constraint_index: Next constraint allocation index.
//
// Returns:
//   - ok: true when the event was queued.
record_constraint_solve_summary :: proc(
    state: ^core.Trace_State,
    fixed_step: u64,
    simulation_time: f32,
    active_constraints: int,
    next_constraint_index: int) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_json_number_field(payload_buffer, &payload_len,
            "fixed_step", fixed_step) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_builder_text(
            payload_buffer, &payload_len,
            fmt.tprintf("\"simulation_time\":%g", simulation_time)) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_number_field(payload_buffer, &payload_len, "active_constraints",
            u64(active_constraints)) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_json_number_field(payload_buffer, &payload_len, "next_constraint_index",
            u64(next_constraint_index)) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(
        state,
        .Geometry,
        "constraint.solve_summary",
        string(payload_buffer[:payload_len]))
}

//   Append one optional checkpoint point position field.
append_checkpoint_point_position :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    point: ^core.Trace_Checkpoint_Point) -> bool {

    if !point^.has_position {
        return true
    }
    return append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_vector3_field(payload_buffer, payload_len,
            "position", point^.position)
}

//   Append one checkpoint point record to the payload.
append_checkpoint_point :: proc(
    payload_buffer: []u8, payload_len: ^int,
    point: ^core.Trace_Checkpoint_Point) -> bool {

    return append_builder_text(payload_buffer, payload_len, "{") &&
        append_json_number_field(payload_buffer, payload_len,
            "index", u64(point^.index)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len,
            "kind", u64(point^.kind)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_bool_field(payload_buffer, payload_len, 
            "visible", point^.do_draw) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(
            payload_buffer, payload_len, "active_child", u64(point^.active_child)) &&
        append_checkpoint_point_position(payload_buffer, payload_len, point) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_builder_text(
            payload_buffer, payload_len, fmt.tprintf("\"brush_size\":%g",
            point^.brush_size)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_builder_text(
            payload_buffer, payload_len, fmt.tprintf("\"offset\":%g", point^.offset)) &&
        append_builder_text(payload_buffer, payload_len, "}")
}

//   Append checkpoint identity fields to the payload.
append_checkpoint_identity_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    if !append_json_number_field(
        payload_buffer, payload_len, "checkpoint_id", snapshot^.checkpoint_id) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_json_number_field(
            payload_buffer, payload_len, "fixed_step", snapshot^.fixed_step) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_builder_text(
            payload_buffer, payload_len,
            fmt.tprintf("\"simulation_time\":%g", snapshot^.simulation_time)) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_json_number_field(payload_buffer, payload_len, "runtime_generation",
            snapshot^.runtime_generation) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_json_number_field(payload_buffer, payload_len, "animation_generation",
            snapshot^.animation_generation) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_json_number_field(payload_buffer, payload_len, "animation_tick",
            snapshot^.animation_tick_sequence) ||
        !append_builder_text(payload_buffer, payload_len, ",") ||
        !append_json_string_field(
            payload_buffer,
            payload_len,
            "animation_id",
            string(snapshot^.animation_name[:snapshot^.animation_name_len])) {
        return false
    }
    return true
}

//   Append checkpoint lifecycle and counters to the payload.
append_checkpoint_counter_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    return append_json_number_field(payload_buffer, payload_len, "next_point_index",
            u64(snapshot^.next_point_index)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len, "next_constraint_index",
            u64(snapshot^.next_constraint_index)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len, "active_constraints",
            u64(snapshot^.active_constraint_count)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len, "rejected_ticks",
            snapshot^.rejected_tick_count) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len, "failed_requests",
            snapshot^.failed_request_count) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_number_field(payload_buffer, payload_len, "dropped_records",
            snapshot^.dropped_record_count)
}

//   Append one tool summary object to the checkpoint payload.
append_checkpoint_tool_summary :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    name: string,
    host_index: int,
    visible: bool,
    active_child: int) -> bool {

    return append_json_string(payload_buffer, payload_len, name) &&
        append_builder_text(payload_buffer, payload_len, ":{") &&
        append_json_number_field(payload_buffer, payload_len, "host_index",
            u64(host_index)) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_bool_field(payload_buffer, payload_len, "visible", visible) &&
        append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_signed_field(payload_buffer, payload_len, "active_child",
            active_child) &&
        append_builder_text(payload_buffer, payload_len, "}")
}

//   Append all checkpoint point records to the payload array.
append_checkpoint_points :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    if !append_builder_text(payload_buffer, payload_len, "\"points\":[") {
        return false
    }
    for point_index in 0..<snapshot^.point_count {
        if point_index > 0 && !append_builder_text(payload_buffer, payload_len, ",") {
            return false
        }
        if !append_checkpoint_point(
            payload_buffer, payload_len, &snapshot^.points[point_index]) {
            return false
        }
    }
    return append_builder_text(payload_buffer, payload_len, "]")
}

//   Record one canonical checkpoint snapshot captured after the deterministic worker join.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - snapshot: Bounded post-join checkpoint snapshot.
//
// Returns:
//   - ok: true when the checkpoint event was queued.
record_checkpoint_snapshot :: proc(
    state: ^core.Trace_State,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    if state == nil || snapshot == nil {
        return false
    }

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{") ||
        !append_checkpoint_identity_fields(payload_buffer, &payload_len, snapshot) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_checkpoint_counter_fields(payload_buffer, &payload_len, snapshot) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_checkpoint_tool_summary(
            payload_buffer,
            &payload_len,
            "pen",
            snapshot^.pen_host_index,
            snapshot^.pen_visible,
            snapshot^.pen_active_child) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_checkpoint_tool_summary(
            payload_buffer,
            &payload_len,
            "compass",
            snapshot^.compass_host_index,
            snapshot^.compass_visible,
            snapshot^.compass_active_child) ||
        !append_builder_text(payload_buffer, &payload_len, ",") ||
        !append_checkpoint_points(payload_buffer, &payload_len, snapshot) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(
        state, .Trace, "trace.checkpoint", string(payload_buffer[:payload_len]))
}

//   Build one trace module instance from application settings.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//   - settings: Parsed run settings.
//
// Returns:
//   - ok: true when trace state is ready for startup.
initialize_trace_state :: proc(
    state: ^core.Trace_State, settings: ^core.Euclid_Run_Settings) -> bool {

    return configure_from_settings(state, settings)
}

//   Ensure trace shutdown and strict failure are reported before process exit.
//
// Parameters:
//   - state: Trace state block owned by Euclid_General_State.
//
// Returns:
//   - exit_code: 0 for success, 1 for strict trace failure.
shutdown_trace_and_exit_code :: proc(state: ^core.Trace_State) -> int {
    if state == nil {
        return 0
    }

    if !finish_trace(state) || should_fail_process(state) {
        return 1
    }

    return 0
}
