package main

import json "core:encoding/json"

// Reject missing and unknown protocol fields instead of silently defaulting decoded structs.
has_fields :: proc(value: json.Value, names: []string) -> bool {
    object, ok := value.(json.Object)
    if !ok || len(object) != len(names) {
        return false
    }
    for name in names {
        if _, found := object[name]; !found {
            return false
        }
    }
    return true
}

// Validate the presence and integral coordinates of one lexical bind token.
token_shape :: proc(value: json.Value) -> bool {
    if !has_fields(value, []string{"first_byte", "after_last_byte", "text"}) {
        return false
    }
    object := value.(json.Object)
    _, first_ok := object["first_byte"].(json.Integer)
    _, after_ok := object["after_last_byte"].(json.Integer)
    _, text_ok := object["text"].(string)
    return first_ok && after_ok && text_ok
}

// Validate required binding fields before typed decoding can conflate missing values and NULL.
bind_shape :: proc(value: json.Value) -> bool {
    if !has_fields(value, []string{"slot", "type", "value"}) {
        return false
    }
    object := value.(json.Object)
    _, slot_ok := object["slot"].(json.Integer)
    _, type_ok := object["type"].(string)
    return slot_ok && type_ok
}

// Validate each required step container and its nonnullable protocol fields.
step_shape :: proc(value: json.Value) -> bool {
    names: []string = {
        "id", "role", "mode", "source_id", "source", "digest", "binds", "bind_tokens",
    }
    if !has_fields(value, names) {
        return false
    }
    object := value.(json.Object)
    for name in names[:6] {
        if _, ok := object[name].(string); !ok {
            return false
        }
    }
    binds, binds_ok := object["binds"].(json.Array)
    tokens, tokens_ok := object["bind_tokens"].(json.Array)
    if !binds_ok || !tokens_ok || len(binds) > MAX_BINDS {
        return false
    }
    for bind in binds {
        if !bind_shape(bind) {
            return false
        }
    }
    for token in tokens {
        if !token_shape(token) {
            return false
        }
    }
    return true
}

// Check the complete JSON-v1 envelope with strict JSON syntax and integer coordinates.
request_shape :: proc(execution: ^Case_Execution, data: []u8) -> bool {
    value: json.Value
    if json.unmarshal(
        data, &value, spec = .JSON, allocator = execution.allocator) != nil ||
        !has_fields(
            value, []string{"protocol_version", "case_id", "requirements", "steps"}) {
        return false
    }
    object := value.(json.Object)
    _, version_ok := object["protocol_version"].(json.Integer)
    _, case_ok := object["case_id"].(string)
    requirements, requirements_ok := object["requirements"].(json.Array)
    steps, steps_ok := object["steps"].(json.Array)
    if !version_ok || !case_ok || !requirements_ok || !steps_ok ||
        len(steps) > MAX_STEPS || len(requirements) > 64 {
        return false
    }
    for requirement in requirements {
        if _, ok := requirement.(string); !ok {
            return false
        }
    }
    for step in steps {
        if !step_shape(step) {
            return false
        }
    }
    return true
}
