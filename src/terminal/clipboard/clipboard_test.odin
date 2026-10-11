#+test
package termclipboard

import "core:testing"

// Verify OSC 52 decoding accepts canonical text and rejects unsafe payloads.
@(test)
clipboard_test_payload_validation :: proc(t: ^testing.T) {
    destination: [CLIPBOARD_TEXT_BYTE_CAPACITY]u8
    canonical := "c;SGVsbG8="
    count, valid := clipboard_decode_payload(
        transmute([]u8)canonical, destination[:])

    testing.expect(t, valid)
    testing.expect_value(t, string(destination[:count]), "Hello")
    noncanonical := "c;SGVsbG9="
    _, noncanonical_valid := clipboard_decode_payload(
        transmute([]u8)noncanonical, destination[:])
    testing.expect(t, !noncanonical_valid)
    control := "c;AA=="
    _, control_valid := clipboard_decode_payload(
        transmute([]u8)control, destination[:])
    testing.expect(t, !control_valid)
}