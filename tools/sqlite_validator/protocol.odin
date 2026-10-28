package main

import "core:crypto/sha2"
import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

MAX_REQUEST_BYTES :: 8 * 1024 * 1024
MAX_SOURCE_BYTES :: 1024 * 1024
MAX_RESULT_BYTES :: 2 * 1024 * 1024
MAX_STEPS :: 256
MAX_BINDS :: 32766

Bind :: struct {
    slot: int,
    type: string,
    value: json.Value,
}

Bind_Token :: struct {
    first_byte: int,
    after_last_byte: int,
    text: string,
}

Step :: struct {
    id: string,
    role: string,
    mode: string,
    source_id: string,
    source: string,
    digest: string,
    binds: []Bind,
    bind_tokens: []Bind_Token,
}

Request :: struct {
    protocol_version: int,
    case_id: string,
    requirements: []string,
    steps: []Step,
}

Failure :: struct {
    phase: string,
    primary_code: int,
    extended_code: int,
    offset: union {json.Null, int},
    message: string,
}

Optional_Failure :: union {Failure}

Step_Result :: struct {
    id: string,
    source_id: string,
    digest: string,
    mode: string,
    status: string,
    attempted: bool,
    prepared: bool,
    executed: bool,
    processed_bytes: int,
    statement_count: int,
    failure: Optional_Failure,
}

Provider :: struct {
    identity: string,
    version: string,
    capabilities: []string,
}

Result :: struct {
    protocol_version: int,
    case_id: string,
    provider: Provider,
    status: string,
    completed: bool,
    transaction_complete: bool,
    cleanup: struct {finalized, closed: bool},
    steps: []Step_Result,
    failure: Optional_Failure,
}

// Check the lowercase digest against the exact UTF-8 snapshot before opening SQLite.
valid_digest :: proc(source, expected: string) -> bool {
    if len(expected) != 64 {
        return false
    }
    hash: sha2.Context_256
    sha2.init_256(&hash)
    sha2.update(&hash, transmute([]u8)source)
    digest: [32]u8
    sha2.final(&hash, digest[:])
    digits := "0123456789abcdef"
    for byte, index in digest {
        if expected[index * 2] != digits[byte >> 4] ||
            expected[index * 2 + 1] != digits[byte & 15] {
            return false
        }
    }
    return true
}

// Accept normalized repository identities or explicit case-local fixture identities.
valid_source_id :: proc(
    execution: ^Case_Execution, value, case_id, step_id: string) -> bool {
    if strings.has_prefix(value, "fixture:") {
        expected := fmt.aprintf(
            "fixture:%s:%s", case_id, step_id, allocator = execution.allocator)
        return value == expected
    }
    if len(value) == 0 || value[0] == '/' || strings.contains_any(value, "\\:\x00") {
        return false
    }
    for part in strings.split(value, "/", execution.allocator) {
        if part == "" || part == "." || part == ".." {
            return false
        }
    }
    return true
}

// Validate an unambiguous decimal Int64 without floating-point numeric transport.
integer_value :: proc(value: string) -> (i64, bool) {
    if len(value) == 0 {
        return 0, false
    }
    start := 0
    if value[0] == '-' {
        start = 1
    }
    if start == len(value) {
        return 0, false
    }
    magnitude: u64
    limit := u64(9223372036854775807)
    if start == 1 {
        limit += 1
    }
    for byte in transmute([]u8)value[start:] {
        if byte < '0' || byte > '9' {
            return 0, false
        }
        digit := u64(byte - '0')
        if magnitude > (limit - digit) / 10 {
            return 0, false
        }
        magnitude = magnitude * 10 + digit
    }
    if start == 1 {
        if magnitude == 9223372036854775808 {
            return -9223372036854775808, true
        }
        return -i64(magnitude), true
    }
    return i64(magnitude), true
}

// Recognize lowercase wire-format hexadecimal without treating empty blobs as NULL.
valid_hex :: proc(value: string) -> bool {
    if len(value) % 2 != 0 {
        return false
    }
    for byte in transmute([]u8)value {
        if !(byte >= '0' && byte <= '9') && !(byte >= 'a' && byte <= 'f') {
            return false
        }
    }
    return true
}

// Reject invalid type/value pairs before SQL execution, including nonfinite reals.
valid_bind :: proc(bind: Bind) -> bool {
    if bind.slot <= 0 || bind.slot > MAX_BINDS {
        return false
    }
    switch bind.type {
    case "null":
        _, ok := bind.value.(json.Null)
        return ok
    case "integer":
        value, ok := bind.value.(string)
        _, numeric := integer_value(value)
        return ok && numeric
    case "real":
        #partial switch value in bind.value {
        case json.Integer:
            return true
        case json.Float:
            return !math.is_nan(value) && !math.is_inf(value)
        }
    case "text":
        value, ok := bind.value.(string)
        return ok && utf8.valid_string(value)
    case "blob":
        value, ok := bind.value.(string)
        return ok && valid_hex(value)
    }
    return false
}

// Check lexical byte evidence against the exact source, preserving native tail ownership.
valid_tokens :: proc(step: Step) -> bool {
    last := 1
    for token in step.bind_tokens {
        if token.first_byte < last || token.after_last_byte <= token.first_byte ||
            token.after_last_byte > len(step.source) + 1 {
            return false
        }
        if !utf8.valid_string(token.text) ||
            token.text != step.source[token.first_byte - 1:token.after_last_byte - 1] ||
            !strings.contains_any(token.text[:1], ":@$?") {
            return false
        }
        last = token.after_last_byte
    }
    return true
}

// Validate bounded source identities, digests, modes, and typed bindings as protocol input.
valid_request :: proc(execution: ^Case_Execution, request: Request) -> bool {
    if request.protocol_version != 1 || len(request.case_id) == 0 ||
        len(request.case_id) > 1024 || len(request.steps) > MAX_STEPS ||
        len(request.requirements) > 64 {
        return false
    }
    allocator := execution.allocator
    ids := make(map[string]bool, allocator)
    for step in request.steps {
        if len(step.id) == 0 || len(step.id) > 1024 || ids[step.id] ||
            (step.role != "setup" && step.role != "operation") ||
            (step.mode != "prepare" && step.mode != "execute") ||
            !valid_source_id(execution, step.source_id, request.case_id, step.id) ||
            len(step.source_id) > 2048 ||
            len(step.source) > MAX_SOURCE_BYTES || !utf8.valid_string(step.source) ||
            !valid_digest(step.source, step.digest) ||
            len(step.binds) > MAX_BINDS || !valid_tokens(step) {
            return false
        }
        ids[step.id] = true
        slots := make(map[int]bool, allocator)
        for bind in step.binds {
            if slots[bind.slot] || !valid_bind(bind) {
                return false
            }
            slots[bind.slot] = true
        }
    }
    return true
}
