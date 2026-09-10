#+test
package termhyperlink

import "core:testing"

// Verify hyperlink policy accepts supported absolute URIs and rejects unsafe forms.
@(test)
hyperlink_test_uri_policy :: proc(t: ^testing.T) {
    testing.expect(t, hyperlink_uri_valid("https://example.com/docs?q=terminal"))
    testing.expect(t, hyperlink_uri_valid("file:///tmp/euclid.txt"))
    testing.expect(t, hyperlink_uri_valid("mailto:user@example.com"))
    testing.expect(t, !hyperlink_uri_valid("relative/path"))
    testing.expect(t, !hyperlink_uri_valid("https://user@example.com/private"))
    testing.expect(t, !hyperlink_uri_valid("file:///tmp/../secret"))
}