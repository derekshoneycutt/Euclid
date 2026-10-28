package scenario

import protocol "../../core/protocol"
import "core:encoding/json"

// Exact read-only editor expectation; evaluation count proves recall did not submit.
Terminal_Editor_Expectation :: struct {
    mode: protocol.Evaluation_Mode,
    cursor: int,
    anchor: int,
    evaluation_requests: u64,
}

// Decode public mode names without coupling scenario payloads to enum ordinals.
terminal_editor_mode :: proc(name: string) -> (protocol.Evaluation_Mode, bool) {
    switch name {
    case "julia":
        return .Normal, true
    case "help":
        return .Help, true
    case "pkg":
        return .Pkg, true
    case "shell":
        return .Shell, true
    }
    return {}, false
}

// Read one nonnegative integral observation without accepting lossy numeric casts.
terminal_editor_integer :: proc(
    payload: json.Object, key: string) -> (int, bool) {
    value, present := payload[key]
    number, valid := value.(json.Integer)
    if !present || !valid || number < 0 || number > json.Integer(max(int)) {
        return 0, false
    }
    return int(number), true
}

// Copy an exact editor assertion into bounded command storage; never mutate an editor.
scenario_terminal_editor_select :: proc(
    root: json.Object, command: ^Command) -> (int, bool) {
    value, present := root["assert_terminal_editor"]
    if !present {
        return 0, true
    }
    payload, object_ok := value.(json.Object)
    if !object_ok || len(payload) != 5 {
        return 0, false
    }
    source, source_ok := payload["source"].(string)
    name, name_ok := payload["mode"].(string)
    cursor, cursor_ok := terminal_editor_integer(payload, "cursor")
    anchor, anchor_ok := terminal_editor_integer(payload, "anchor")
    requests, requests_ok := terminal_editor_integer(payload, "evaluation_requests")
    mode, mode_ok := terminal_editor_mode(name)
    text, text_ok := text_copy(source)
    if !source_ok || !name_ok || !mode_ok || !text_ok ||
       !cursor_ok || !anchor_ok || !requests_ok ||
       cursor > len(source) || anchor > len(source) {
        return 0, false
    }
    command^.kind = .Assert_Terminal_Editor
    command^.text = text
    command^.terminal_editor = {mode, cursor, anchor, u64(requests)}
    return 1, true
}
