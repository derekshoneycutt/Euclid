#+test
package native

import "core:testing"

Texture_Completion_Test_State :: struct {
    identity: u64,
    generation: u64,
    succeeded: bool,
    calls: int,
}

// texture_completion_test records one operation result for pure callback tests.
texture_completion_test :: proc(
    user_data: rawptr, identity, generation: u64, succeeded: bool) {
    state := cast(^Texture_Completion_Test_State)user_data
    state^.identity = identity
    state^.generation = generation
    state^.succeeded = succeeded
    state^.calls += 1
}

// Verify gray-alpha font pixels expand to tintable RGBA coverage.
@(test)
texture_operations_test_normalizes_gray_alpha :: proc(t: ^testing.T) {
    source := [4]u8{255, 0, 128, 64}
    destination: [8]u8
    testing.expect(t, texture_normalize_rgba8(
        destination[:], source[:], .Gray_Alpha8))
    testing.expect_value(t, destination,
        [8]u8{255, 255, 255, 0, 128, 128, 128, 64})
}

// Verify RGB and RGBA payloads normalize without changing visible channels.
@(test)
texture_operations_test_normalizes_terminal_pixels :: proc(t: ^testing.T) {
    rgb := [3]u8{10, 20, 30}
    rgba := [4]u8{40, 50, 60, 70}
    rgb_destination: [4]u8
    rgba_destination: [4]u8
    testing.expect(t, texture_normalize_rgba8(
        rgb_destination[:], rgb[:], .Rgb8))
    testing.expect(t, texture_normalize_rgba8(
        rgba_destination[:], rgba[:], .Rgba8))
    testing.expect_value(t, rgb_destination, [4]u8{10, 20, 30, 255})
    testing.expect_value(t, rgba_destination, rgba)
}

// Verify malformed pixels and overflowing dimensions are rejected.
@(test)
texture_operations_test_rejects_invalid_storage :: proc(t: ^testing.T) {
    source := [3]u8{1, 2, 3}
    destination: [3]u8
    testing.expect(t, !texture_normalize_rgba8(
        destination[:], source[:], .Rgb8))
    _, valid := texture_rgba8_byte_count(max(u32), 2)
    testing.expect(t, !valid)
}

// Verify queue capacity rejection leaves all publication counts unchanged.
@(test)
texture_operations_test_queue_overflow_is_atomic :: proc(t: ^testing.T) {
    queue: Texture_Operation_Queue
    operation := Texture_Operation{
        kind = .Create,
        texture = rawptr(uintptr(1)),
        width = 1,
        height = 1,
        format = .Rgba8,
        source = []u8{1, 2, 3, 4},
        generation = 1,
    }
    for _ in 0..<TEXTURE_OPERATION_CAPACITY {
        testing.expect(t, texture_operation_enqueue(&queue, operation))
    }
    testing.expect(t, !texture_operation_enqueue(&queue, operation))
    testing.expect_value(t, queue.count, TEXTURE_OPERATION_CAPACITY)
    testing.expect_value(t, queue.byte_count,
        u32(TEXTURE_OPERATION_CAPACITY * 4))
    testing.expect_value(t, queue.overflow_count, u32(1))
}

// Verify typed helpers preserve identity and normalized upload accounting.
@(test)
texture_operations_test_typed_upload_and_retire :: proc(t: ^testing.T) {
    queue: Texture_Operation_Queue
    completion: Texture_Completion_Test_State
    texture := Sampled_Texture{rawptr(uintptr(1)), 2, 1}
    source := [6]u8{1, 2, 3, 4, 5, 6}
    testing.expect(t, texture_operation_enqueue_upload(
        &queue, .Create, texture, .Rgb8, source[:], 7, 9,
        {texture_completion_test, &completion}))
    testing.expect(t, texture_operation_enqueue_retire(&queue, texture, 7, 9))
    testing.expect_value(t, queue.count, 2)
    testing.expect_value(t, queue.byte_count, u32(8))
    testing.expect_value(t, queue.operations[0].identity, u64(7))
    testing.expect_value(t, queue.operations[0].generation, u64(9))
    testing.expect_value(t, queue.operations[0].user_data, rawptr(&completion))
    testing.expect_value(t, queue.operations[1].kind, Texture_Operation_Kind.Retire)
}