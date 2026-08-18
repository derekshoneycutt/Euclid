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

//   One CLI category token mapped to its trace category.
Trace_Category_Token :: struct {
    name:     string,
    category: core.Trace_Category,
}

//   CLI category tokens accepted in the comma-separated selection list.
TRACE_CATEGORY_TOKENS :: []Trace_Category_Token{
    {"runtime", .Runtime},
    {"animation", .Animation},
    {"geometry", .Geometry},
    {"tools", .Tools},
    {"particles", .Particles},
    {"view", .View},
}

JSON_ESCAPE_SHORT :: [0x20]string{
    '\b' = "\\b",
    '\f' = "\\f",
    '\n' = "\\n",
    '\r' = "\\r",
    '\t' = "\\t",
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

//   Append one JSON string body with escaping, without surrounding quotes.
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
        if ch == '"' {
            escaped = "\\\""
        } else if ch == '\\' {
            escaped = "\\\\"
        } else if ch >= 0x20 {
            if length^ >= len(buffer) {
                return false
            }
            buffer[length^] = u8(ch)
            length^ += 1
            continue
        } else {
            short := JSON_ESCAPE_SHORT
            escaped = short[ch]
            if len(escaped) == 0 {
                escaped = fmt.tprintf("\\u%04x", int(ch))
            }
        }

        if !append_builder_text(buffer, length, escaped) {
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
    if !append_json_comma_field(out_buffer, &out_len,
            fmt.tprintf("\"strict\":%s", state^.strict ? "true" : "false")) ||
        !append_json_comma_field(out_buffer, &out_len,
            fmt.tprintf("\"category_mask\":%d",
                trace_category_mask(state^.categories))) {
        return 0, false
    }

    if state^.output_path_len > 0 {
        output_path := string(state^.output_path[:state^.output_path_len])
        if !append_json_comma_field(out_buffer, &out_len,
            fmt.tprintf("\"output_path\":%s", json_quote(output_path))) {
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

//   Look up one CLI category token, returning false when unrecognized.
trace_category_for_token :: proc(token: string) -> (core.Trace_Category, bool) {
    tokens := TRACE_CATEGORY_TOKENS
    for entry in tokens {
        if entry.name == token {
            return entry.category, true
        }
    }
    return .Trace, false
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
        category, found := trace_category_for_token(token)
        if !found {
            return {}, false
        }
        categories += {category}
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
    if settings^.semantic_trace_sink {
        state^.output_mode = .Sink
    }
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
        !append_builder_text(payload_buffer, &payload_len,
            fmt.tprintf("\"animation_generation\":%d", animation_generation)) {
        return false
    }

    // Optional fields, emitted only when present.
    optional_bodies: [3]string
    optional_count := 0
    if animation_tick > 0 {
        optional_bodies[optional_count] =
            fmt.tprintf("\"animation_tick\":%d", animation_tick)
        optional_count += 1
    }
    if len(animation_id) > 0 {
        optional_bodies[optional_count] =
            fmt.tprintf("\"animation_id\":%s", json_quote(animation_id))
        optional_count += 1
    }
    if len(reason) > 0 {
        optional_bodies[optional_count] =
            fmt.tprintf("\"reason\":%s", json_quote(reason))
        optional_count += 1
    }
    for index in 0..<optional_count {
        if !append_json_comma_field(
            payload_buffer, &payload_len, optional_bodies[index]) {
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
        !append_builder_text(buffer, length, ":[") {
        return false
    }

    channels := [4]u8{value.r, value.g, value.b, value.a}
    for channel, index in channels {
        if index > 0 && !append_builder_text(buffer, length, ",") {
            return false
        }
        if !append_builder_text(buffer, length, fmt.tprintf("%d", channel)) {
            return false
        }
    }
    return append_builder_text(buffer, length, "]")
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
//   Optional fields for one committed point state transition. Each Maybe field
//   is emitted only when set, so unrelated events leave them nil.
Trace_Point_Event_Fields :: struct {
    from_position: Maybe(core.Vector3),
    to_position:   Maybe(core.Vector3),
    visible:       Maybe(bool),
    brush_size:    Maybe(f32),
    offset:        Maybe(f32),
    color:         Maybe(core.Bridge_Color),
}

//   Append optional point-event fields to one payload buffer.
//
// Parameters:
//   - payload_buffer: Destination payload buffer.
//   - payload_len: Current payload length, updated on success.
//   - fields: Optional point-event field values.
//
// Returns:
//   - ok: true when all present optional fields were appended.
append_point_event_optional_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    fields: Trace_Point_Event_Fields) -> bool {

    return append_optional_vector_field(payload_buffer, payload_len,
            "from", fields.from_position) &&
        append_optional_vector_field(payload_buffer, payload_len,
            "to", fields.to_position) &&
        append_optional_bool_field(payload_buffer, payload_len,
            "visible", fields.visible) &&
        append_optional_float_field(payload_buffer, payload_len,
            "brush_size", fields.brush_size) &&
        append_optional_float_field(payload_buffer, payload_len,
            "offset", fields.offset) &&
        append_optional_color_field(payload_buffer, payload_len,
            "color", fields.color)
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
    fields: Trace_Point_Event_Fields) -> bool {

    payload_len := 0
    payload_buffer := state^.serialize_buffer[:]
    if !append_builder_text(payload_buffer, &payload_len, "{\"kind\":\"point\",") ||
        !append_json_number_field(payload_buffer, &payload_len, "index", u64(index)) ||
        !append_point_event_optional_fields(
            payload_buffer,
            &payload_len,
            fields) ||
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
        !append_json_comma_field(payload_buffer, &payload_len,
            fmt.tprintf("\"layer\":%s", json_quote(layer))) ||
        !append_json_comma_field(payload_buffer, &payload_len,
            fmt.tprintf("\"count\":%d", count)) ||
        !append_json_comma_field(payload_buffer, &payload_len,
            fmt.tprintf("\"source\":[%g,%g,%g]", source.x, source.y, source.z)) ||
        !append_json_comma_field(payload_buffer, &payload_len,
            fmt.tprintf("\"color\":[%d,%d,%d,%d]",
                color.r, color.g, color.b, color.a)) ||
        !append_builder_text(payload_buffer, &payload_len, "}") {
        return false
    }

    return record_event(
        state, .Particles, "particles.emitted", string(payload_buffer[:payload_len]))
}

//   Render a string as a JSON-quoted value (with surrounding quotes).
json_quote :: proc(text: string) -> string {
    buffer: [512]u8
    length := 0
    if !append_json_string(buffer[:], &length, text) {
        return "\"\""
    }
    return fmt.tprintf("%s", string(buffer[:length]))
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

//   Append one checkpoint point record to the payload.
append_checkpoint_point :: proc(
    payload_buffer: []u8, payload_len: ^int,
    point: ^core.Trace_Checkpoint_Point) -> bool {

    // Pre-render each field body; position is optional and appended when present.
    bodies: [7]string
    body_count := 0
    bodies[body_count] = fmt.tprintf("\"index\":%d", point^.index)
    body_count += 1
    bodies[body_count] = fmt.tprintf("\"kind\":%d", point^.kind)
    body_count += 1
    bodies[body_count] = fmt.tprintf("\"visible\":%v", point^.do_draw)
    body_count += 1
    bodies[body_count] = fmt.tprintf("\"active_child\":%d", point^.active_child)
    body_count += 1
    if point^.has_position {
        bodies[body_count] = fmt.tprintf("\"position\":[%g,%g,%g]",
            point^.position.x, point^.position.y, point^.position.z)
        body_count += 1
    }
    bodies[body_count] = fmt.tprintf("\"brush_size\":%g", point^.brush_size)
    body_count += 1
    bodies[body_count] = fmt.tprintf("\"offset\":%g", point^.offset)
    body_count += 1

    if !append_builder_text(payload_buffer, payload_len, "{") {
        return false
    }
    for body, index in bodies[:body_count] {
        if index > 0 && !append_builder_text(payload_buffer, payload_len, ",") {
            return false
        }
        if !append_builder_text(payload_buffer, payload_len, body) {
            return false
        }
    }
    return append_builder_text(payload_buffer, payload_len, "}")
}

//   Append one pre-rendered field body with a leading comma separator.
append_json_comma_field :: proc(
    payload_buffer: []u8, payload_len: ^int, body: string) -> bool {
    return append_builder_text(payload_buffer, payload_len, ",") &&
        append_builder_text(payload_buffer, payload_len, body)
}

//   Append checkpoint identity fields to the payload.
append_checkpoint_identity_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    if !append_builder_text(payload_buffer, payload_len,
            fmt.tprintf("\"checkpoint_id\":%d", snapshot^.checkpoint_id)) {
        return false
    }

    bodies := [6]string{
        fmt.tprintf("\"fixed_step\":%d", snapshot^.fixed_step),
        fmt.tprintf("\"simulation_time\":%g", snapshot^.simulation_time),
        fmt.tprintf("\"runtime_generation\":%d", snapshot^.runtime_generation),
        fmt.tprintf("\"animation_generation\":%d", snapshot^.animation_generation),
        fmt.tprintf("\"animation_tick\":%d", snapshot^.animation_tick_sequence),
        "",
    }
    for index in 0..<5 {
        if !append_json_comma_field(payload_buffer, payload_len, bodies[index]) {
            return false
        }
    }

    return append_builder_text(payload_buffer, payload_len, ",") &&
        append_json_string_field(payload_buffer, payload_len, "animation_id",
            string(snapshot^.animation_name[:snapshot^.animation_name_len]))
}

//   Append checkpoint lifecycle and counters to the payload.
append_checkpoint_counter_fields :: proc(
    payload_buffer: []u8,
    payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {

    if !append_builder_text(payload_buffer, payload_len,
            fmt.tprintf("\"next_point_index\":%d", snapshot^.next_point_index)) {
        return false
    }

    bodies := [5]string{
        fmt.tprintf("\"next_constraint_index\":%d", snapshot^.next_constraint_index),
        fmt.tprintf("\"active_constraints\":%d", snapshot^.active_constraint_count),
        fmt.tprintf("\"rejected_ticks\":%d", snapshot^.rejected_tick_count),
        fmt.tprintf("\"failed_requests\":%d", snapshot^.failed_request_count),
        fmt.tprintf("\"dropped_records\":%d", snapshot^.dropped_record_count),
    }
    for body in bodies {
        if !append_json_comma_field(payload_buffer, payload_len, body) {
            return false
        }
    }
    return true
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

//   Append the pen tool summary section of the checkpoint payload.
append_checkpoint_pen_summary :: proc(
    payload_buffer: []u8, payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {
    return append_checkpoint_tool_summary(payload_buffer, payload_len, "pen",
        snapshot^.pen_host_index, snapshot^.pen_visible, snapshot^.pen_active_child)
}

//   Append the compass tool summary section of the checkpoint payload.
append_checkpoint_compass_summary :: proc(
    payload_buffer: []u8, payload_len: ^int,
    snapshot: ^core.Trace_Checkpoint_Snapshot) -> bool {
    return append_checkpoint_tool_summary(payload_buffer, payload_len, "compass",
        snapshot^.compass_host_index, snapshot^.compass_visible,
        snapshot^.compass_active_child)
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
    if !append_builder_text(payload_buffer, &payload_len, "{") {
        return false
    }

    // Each section is a comma-separated fragment; the first omits the comma.
    sections := [5]proc([]u8, ^int, ^core.Trace_Checkpoint_Snapshot) -> bool{
        append_checkpoint_identity_fields,
        append_checkpoint_counter_fields,
        append_checkpoint_pen_summary,
        append_checkpoint_compass_summary,
        append_checkpoint_points,
    }
    for section, index in sections {
        if index > 0 && !append_builder_text(payload_buffer, &payload_len, ",") {
            return false
        }
        if !section(payload_buffer, &payload_len, snapshot) {
            return false
        }
    }
    if !append_builder_text(payload_buffer, &payload_len, "}") {
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
