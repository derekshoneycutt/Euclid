package main

import raw "../../libs/sqlite3"

import "core:c"
import json "core:encoding/json"
import "core:strings"

Native_Range :: struct {
    first, after: int,
}

// Decode one already validated blob using a nonnil allocation even for empty bytes.
decode_blob :: proc(execution: ^Case_Execution, value: string) -> []u8 {
    allocator := execution.allocator
    data := make([]u8, max(1, len(value) / 2), allocator)
    digits := "0123456789abcdef"
    for index in 0..<len(value) / 2 {
        data[index] = u8(strings.index_byte(digits, value[index * 2]) * 16 +
            strings.index_byte(digits, value[index * 2 + 1]))
    }
    return data[:len(value) / 2]
}

// Bind one explicitly typed wire value without conflating empty bytes and SQLite NULL.
bind_value :: proc(
    execution: ^Case_Execution, statement: ^raw.Statement, bind: Bind) -> raw.Result {
    slot := c.int(bind.slot)
    switch bind.type {
    case "null":
        return raw.sqlite3_bind_null(statement, slot)
    case "integer":
        value, _ := integer_value(bind.value.(string))
        return raw.sqlite3_bind_int64(statement, slot, c.longlong(value))
    case "real":
        value: f64
        #partial switch number in bind.value {
        case json.Integer:
            value = f64(number)
        case json.Float:
            value = number
        }
        return raw.sqlite3_bind_double(statement, slot, value)
    case "text":
        value := bind.value.(string)
        return raw.sqlite3_bind_text(statement, slot,
            strings.clone_to_cstring(value, execution.allocator), c.int(len(value)),
            raw.transient_destructor())
    case "blob":
        value := decode_blob(execution, bind.value.(string))
        return raw.sqlite3_bind_blob(statement, slot, raw_data(value), c.int(len(value)),
            raw.transient_destructor())
    }
    return .Misuse
}

// Recover one native slot, ignoring lexical virtual-module arguments absent from metadata.
token_slot :: proc(
    execution: ^Case_Execution, statement: ^raw.Statement,
    token: Bind_Token, highest: int) -> (int, bool) {
    count := int(raw.sqlite3_bind_parameter_count(statement))
    if count == 0 {
        return 0, true
    }
    if token.text == "?" {
        slot := highest + 1
        return slot, slot <= count
    }
    name := strings.clone_to_cstring(token.text, execution.allocator)
    slot := int(raw.sqlite3_bind_parameter_index(statement, name))
    if token.text[0] == '?' {
        number, ok := integer_value(token.text[1:])
        if !ok || number <= 0 || number > i64(count) {
            return 0, false
        }
        slot = int(number)
    }
    return slot, slot > 0
}

// Reconcile lexical tokens within the native source range against actual parameter metadata.
statement_slots :: proc(
    execution: ^Case_Execution, statement: ^raw.Statement, tokens: []Bind_Token,
    span: Native_Range) -> (map[int]bool, ^Failure) {
    allocator := execution.allocator
    used := make(map[int]bool, allocator)
    highest := 0
    for token in tokens {
        if token.first_byte < span.first + 1 || token.first_byte >= span.after + 1 {
            continue
        }
        slot, valid := token_slot(execution, statement, token, highest)
        if !valid {
            return nil, make_failure(execution,
                "bind", .Range, "bind evidence disagrees with native metadata")
        }
        if slot > 0 {
            used[slot] = true
            highest = max(highest, slot)
        }
    }
    count := int(raw.sqlite3_bind_parameter_count(statement))
    if highest != count {
        return nil, make_failure(execution,
            "bind", .Range, "lexical bind evidence does not reach native slot count")
    }
    for slot in 1..=count {
        if raw.sqlite3_bind_parameter_name(statement, c.int(slot)) != nil && !used[slot] {
            return nil, make_failure(execution,
                "bind", .Range, "missing lexical native parameter evidence")
        }
    }
    return used, nil
}

// Require every used native slot and accumulate provided-slot usage across the whole step.
bind_statement :: proc(
    execution: ^Case_Execution, statement: ^raw.Statement, step: Step,
    span: Native_Range, all_used: ^map[int]bool) -> ^Failure {
    used, failure := statement_slots(execution, statement, step.bind_tokens, span)
    if failure != nil {
        return failure
    }
    for slot in used {
        all_used[slot] = true
        found := false
        for bind in step.binds {
            if bind.slot == slot {
                found = true
                if result := bind_value(execution, statement, bind); result != .Ok {
                    return native_failure(execution, "bind", result, -1)
                }
                break
            }
        }
        if !found {
            return make_failure(
                execution, "bind", .Range, "missing explicit binding for used slot")
        }
    }
    return nil
}
