package animation

import "base:runtime"
import "core:testing"

//   Verify initialization publishes one usable shared allocator.
@(test)
animation_model_test_animation_memory_initializes :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)

    testing.expect(t, memory.initialized)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect(t, animation_memory_allocator(&memory) != runtime.Allocator{})
}

//   Verify valid generation transitions reset shared storage exactly once.
@(test)
animation_model_test_animation_memory_advances_generation :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)
    allocator := animation_memory_allocator(&memory)
    bytes := make([]u8, 64, allocator)
    bytes[0] = 1

    testing.expect_value(t, animation_memory_begin_generation(
        &memory, 7), Animation_Memory_Status.Ok)
    diagnostics := animation_memory_diagnostics(&memory)
    testing.expect_value(t, memory.generation, u64(7))
    testing.expect_value(t, diagnostics.current_used, uint(0))
    testing.expect_value(t, diagnostics.reset_count, u64(1))
}

//   Verify an invalid generation cannot mutate memory or reset diagnostics.
@(test)
animation_model_test_animation_memory_rejects_invalid_generation :: proc(
    t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)
    before := animation_memory_diagnostics(&memory)

    testing.expect_value(t, animation_memory_begin_generation(
        &memory, 0), Animation_Memory_Status.Invalid_Argument)
    after := animation_memory_diagnostics(&memory)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect_value(t, after.reset_count, before.reset_count)
}

//   Verify destruction releases storage while retaining terminal diagnostics.
@(test)
animation_model_test_animation_memory_destroy_preserves_diagnostics :: proc(
    t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    allocator := animation_memory_allocator(&memory)
    bytes := make([]u8, 64, allocator)
    bytes[0] = 1
    before := animation_memory_diagnostics(&memory)

    animation_memory_destroy(&memory)
    after := animation_memory_diagnostics(&memory)
    testing.expect(t, !memory.initialized)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect_value(t, after.current_reserved, uint(0))
    testing.expect_value(t, after.peak_used, before.peak_used)
    testing.expect_value(t, after.destroy_count, u64(1))
}