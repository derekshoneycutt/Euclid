#+test
package content_model

import "core:testing"

// Verify exercise aliases, UUIDs, and pages are validated before crossing the worker.
@(test)
exercise_query_requests_are_typed_and_bounded :: proc(t: ^testing.T) {
    animation_id := "00000000-0000-0000-0000-000000000001"
    exercise_id := "10000000-0000-0000-0000-000000000001"
    list, list_ok := exercise_query_request_make(
        1, .List, animation_id, "", {0, u16(EXERCISE_LIST_PAGE_CAPACITY)})
    testing.expect(t, list_ok)
    testing.expect_value(t, list.animation_id_length, u16(EXERCISE_UUID_BYTE_COUNT))
    _, oversized_page := exercise_query_request_make(
        1, .List, animation_id, "", {0, u16(EXERCISE_LIST_PAGE_CAPACITY + 1)})
    testing.expect(t, !oversized_page)
    alias, alias_ok := exercise_query_request_make(
        2, .Resolve_Alias, "", "test-exercise", {})
    testing.expect(t, alias_ok)
    testing.expect_value(t, string(alias.reference[:alias.reference_length]),
        "test-exercise")
    _, invalid_alias := exercise_query_request_make(
        2, .Resolve_Alias, "", "Test-Exercise", {})
    testing.expect(t, !invalid_alias)
    resolved, uuid_ok := exercise_query_request_make(
        3, .Resolve_Uuid, "", exercise_id, {})
    testing.expect(t, uuid_ok)
    testing.expect_value(t, string(resolved.reference[:resolved.reference_length]),
        exercise_id)
    _, invalid_uuid := exercise_query_request_make(
        3, .Read_Uuid, "", "not-an-exercise-id", {})
    testing.expect(t, !invalid_uuid)
}
