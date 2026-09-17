#+test
package viewcapture

import "core:testing"

// Mark a synthetic frame release for ownership tests.
capture_test_release :: proc(frame: ^Owned_Frame) {
    frame.pixels = nil
}

// Verify capture requests reject partial dimensions and unknown pixel layouts.
@(test)
capture_request_validation_requires_complete_dimensions :: proc(t: ^testing.T) {
    request := Request{target = .Gif_Frame, format = .Rgba8}
    testing.expect(t, request_valid(request))

    request.region.width = 10
    testing.expect(t, !request_valid(request))
    request.region.height = 10
    testing.expect(t, request_valid(request))

    request.output.width = 5
    testing.expect(t, !request_valid(request))
    request.output.height = 5
    testing.expect(t, request_valid(request))
}

// Verify release invalidates an owned frame and remains safe when repeated.
@(test)
capture_owned_frame_release_is_idempotent :: proc(t: ^testing.T) {
    pixels: [16]u8
    frame := Owned_Frame{
        pixels = pixels[:],
        width = 2,
        height = 2,
        pitch = 8,
        format = .Rgba8,
        release = capture_test_release,
    }
    testing.expect(t, frame_valid(&frame))

    frame_release(&frame)
    testing.expect(t, !frame_valid(&frame))
    frame_release(&frame)
}

// Verify frame validation rejects undersized rows and incomplete pixel storage.
@(test)
capture_owned_frame_validation_checks_storage_bounds :: proc(t: ^testing.T) {
    pixels: [16]u8
    frame := Owned_Frame{
        pixels = pixels[:],
        width = 2,
        height = 2,
        pitch = 7,
        format = .Rgba8,
    }
    testing.expect(t, !frame_valid(&frame))

    frame.pitch = 8
    frame.pixels = pixels[:15]
    testing.expect(t, !frame_valid(&frame))
}
