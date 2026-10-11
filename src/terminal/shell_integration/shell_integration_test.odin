#+test
package termshellintegration

import "core:testing"
import termmodel "../model"

// Verify a complete shell-marker lifecycle commits one correlated command block.
@(test)
shell_integration_test_command_lifecycle :: proc(t: ^testing.T) {
    state: Shell_Integration_State
    testing.expect(t, shell_integration_init(&state, 2, context.allocator))
    defer shell_integration_destroy(&state)

    prompt := termmodel.Terminal_Semantic_Position{logical_line_id = 1}
    finished := termmodel.Terminal_Semantic_Position{logical_line_id = 2}
    shell_command_admit_marker(&state, {
        kind = .Prompt,
        valid = true,
    }, prompt)
    shell_command_admit_marker(&state, {
        kind = .Finished,
        status = 3,
        status_present = true,
        valid = true,
    }, finished)

    testing.expect_value(t, shell_command_block_count(&state), 1)
    block, present := shell_command_block(&state, 0)
    testing.expect(t, present)
    testing.expect(t, .Prompt in block.present)
    testing.expect(t, .Finished in block.present)
    testing.expect_value(t, block.status, i32(3))
}