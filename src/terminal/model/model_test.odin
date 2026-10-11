#+test
package termmodel

import "core:testing"

// Verify producer identities retain their source and lifetime correlation.
@(test)
terminal_model_test_producer_identity :: proc(t: ^testing.T) {
    producer := Terminal_Producer{
        kind = .Julia_Evaluation,
        id = 41,
        generation = 7,
    }

    testing.expect_value(t, producer.kind, Terminal_Producer_Kind.Julia_Evaluation)
    testing.expect_value(t, producer.id, u64(41))
    testing.expect_value(t, producer.generation, u64(7))
}