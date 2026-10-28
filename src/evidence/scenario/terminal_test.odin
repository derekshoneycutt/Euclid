#+test
package scenario

import protocol "../../core/protocol"
import "core:fmt"
import "core:testing"

// Exact read-only observations accept empty drafts and preserve source/mode byte facts.
@(test)
scenario_terminal_editor_observation_parses_exact_payload :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"assert_terminal_editor\":{\"source\":\"x\\nα\",\"mode\":\"help\"," +
        "\"cursor\":4,\"anchor\":0,\"evaluation_requests\":2}}\n" +
        "{\"wait_terminal_explorer\":\"ready\",\"timeout_ms\":10000}\n" +
        "{\"assert_terminal_preview\":\"x\\nα\"}\n" +
        "{\"assert_terminal_editor\":{\"source\":\"\",\"mode\":\"julia\"," +
        "\"cursor\":0,\"anchor\":0,\"evaluation_requests\":0}}\n", &program),
        Parse_Error.None)
    testing.expect_value(t, program.count, 4)
    command := &program.commands[0]
    testing.expect_value(t, command^.kind, Command_Kind.Assert_Terminal_Editor)
    testing.expect_value(t, text_string(&command^.text), "x\nα")
    testing.expect_value(t, command^.terminal_editor.mode, protocol.Evaluation_Mode.Help)
    testing.expect_value(t, command^.terminal_editor.cursor, 4)
    testing.expect_value(t, command^.terminal_editor.anchor, 0)
    testing.expect_value(t, command^.terminal_editor.evaluation_requests, u64(2))
    testing.expect_value(t, program.commands[1].timeout_ms, u32(10000))
    testing.expect(t, command_kind_ends_frame(.Wait_Terminal_Explorer))
    testing.expect(t, command_kind_ends_frame(.Set_Setting))
}

// Malformed observation payloads fail rather than becoming a successful partial assertion.
@(test)
scenario_terminal_editor_observation_rejects_invalid_shapes :: proc(t: ^testing.T) {
    payloads := [?]string{
        "{\"source\":\"\",\"mode\":\"unknown\",\"cursor\":0,\"anchor\":0,\"evaluation_requests\":0}",
        "{\"source\":\"\",\"mode\":\"julia\",\"cursor\":-1,\"anchor\":0,\"evaluation_requests\":0}",
        "{\"source\":\"\",\"mode\":\"julia\",\"cursor\":1,\"anchor\":0,\"evaluation_requests\":0}",
        "{\"source\":\"\",\"mode\":\"julia\",\"cursor\":0,\"anchor\":0}",
        "{\"source\":\"\",\"mode\":\"julia\",\"cursor\":0,\"anchor\":0,\"evaluation_requests\":0,\"extra\":1}",
    }
    for payload in payloads {
        program: Program
        failure := parse(
            fmt.tprintf("{\"assert_terminal_editor\":%s}\n", payload), &program)
        testing.expect(t, failure == .Invalid_Command || failure == .Invalid_Json)
    }
    program: Program
    testing.expect_value(t, parse(
        "{\"assert_terminal_editor\":{\"source\":\"\",\"mode\":\"julia\"," +
        "\"cursor\":0.5,\"anchor\":0,\"evaluation_requests\":0}}\n", &program),
        Parse_Error.Invalid_Command)
}
