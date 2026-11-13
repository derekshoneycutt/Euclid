package exerciseheader

import "core:testing"

// Verify bounded replacement, Unicode validation, and dismissal revision behavior.
@(test)
exercise_header_update_is_bounded_and_transactional :: proc(t: ^testing.T) {
    state: State
    valid: [3]u8 = "old"
    testing.expect(t, show(&state, valid[:]))
    testing.expect_value(t, string(state.text[:state.count]), "old")
    revision := state.revision

    blank: [3]u8 = {' ', '\t', '\n'}
    invalid_utf8: [2]u8 = {0xc3, 0x28}
    oversized: [EXERCISE_HEADER_MAX_TEXT_BYTES + 1]u8
    testing.expect(t, !show(&state, blank[:]))
    testing.expect(t, !show(&state, invalid_utf8[:]))
    testing.expect(t, !show(&state, oversized[:]))
    testing.expect_value(t, string(state.text[:state.count]), "old")
    testing.expect_value(t, state.revision, revision)

    exact_capacity: [EXERCISE_HEADER_MAX_TEXT_BYTES]u8
    for index in 0..<len(exact_capacity) {
        exact_capacity[index] = 'x'
    }
    testing.expect(t, show(&state, exact_capacity[:]))
    testing.expect_value(t, state.count, EXERCISE_HEADER_MAX_TEXT_BYTES)
    testing.expect_value(t, state.text[0], u8('x'))
    testing.expect_value(t, state.text[len(state.text)-1], u8('x'))
    testing.expect(t, state.revision != revision)

    hide(&state)
    testing.expect(t, !state.visible)
    testing.expect_value(t, state.count, 0)
    testing.expect(t, state.revision != revision)
}
