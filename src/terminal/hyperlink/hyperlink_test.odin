#+test
package termhyperlink

import "core:testing"

// Verify hyperlink policy accepts supported absolute URIs and rejects unsafe forms.
@(test)
hyperlink_test_uri_policy :: proc(t: ^testing.T) {
    testing.expect(t, hyperlink_uri_valid("https://example.com/docs?q=terminal"))
    testing.expect(t, hyperlink_uri_valid("file:///tmp/euclid.txt"))
    testing.expect(t, hyperlink_uri_valid("mailto:user@example.com"))
    testing.expect(t, hyperlink_uri_valid(
        "euclid:exercise/builtin/elements-i-1"))
    testing.expect(t, hyperlink_uri_valid(
        "euclid:exercise/user/uuid/a9237c51-c9f6-4d54-8bf5-f8c651906e1c"))
    testing.expect(t, !hyperlink_uri_valid("relative/path"))
    testing.expect(t, !hyperlink_uri_valid("https://user@example.com/private"))
    testing.expect(t, !hyperlink_uri_valid("file:///tmp/../secret"))
    testing.expect(t, !hyperlink_uri_valid("euclid:exercise/unknown/name"))
    testing.expect(t, !hyperlink_uri_valid("euclid:exercise/builtin/uuid/not-a-uuid"))
    testing.expect(t, !hyperlink_uri_valid("euclid:exercise/builtin/Bad-Alias"))
    testing.expect(t, !hyperlink_uri_valid(
        "euclid:exercise/builtin/elements-i-1?fallback=external"))
}

// Keep namespace, target kind, and bounded identity separate from database availability.
@(test)
hyperlink_test_exercise_target_parse :: proc(t: ^testing.T) {
    alias, alias_valid := hyperlink_exercise_target_parse(
        "euclid:exercise/builtin/elements-i-1")
    testing.expect(t, alias_valid)
    testing.expect(t, !alias.user_namespace)
    testing.expect(t, !alias.uuid_identity)
    testing.expect_value(t, alias.identity_byte_count, 12)
    testing.expect_value(t, string(alias.identity[:alias.identity_byte_count]),
        "elements-i-1")
    identity, uuid_valid := hyperlink_exercise_target_parse(
        "euclid:exercise/user/uuid/a9237c51-c9f6-4d54-8bf5-f8c651906e1c")
    testing.expect(t, uuid_valid)
    testing.expect(t, identity.user_namespace)
    testing.expect(t, identity.uuid_identity)
}