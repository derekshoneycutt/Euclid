package dynview_math

import dynviewmodel "../model"

import fontmodel "../../view/font/model"

import storage "../../core/storage"

import "base:runtime"
import "core:mem"
import "core:testing"

//   Verify builders admit both exact logical maxima and reject further records.
@(test)
dynview_shaped_builder_enforces_exact_limits :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    testing.expect(t, storage.arena_owner_init(&arena))
    defer storage.arena_owner_destroy(&arena)
    builder: Dynview_Shaped_Builder
    testing.expect_value(t, shaped_builder_init(&builder, &arena, 7),
        storage.Bounded_Builder_Status.Ok)
    glyphs := []fontmodel.Shaped_Glyph{{glyph_id = 1}}
    for index in 0..<dynviewmodel.DYNVIEW_MAX_SHAPED_RUNS {
        testing.expect_value(t, shaped_builder_append(
            &builder, {index, .Primary, 0, 1, glyphs, {}}),
            storage.Bounded_Builder_Status.Ok)
    }
    testing.expect_value(t, shaped_builder_append(
        &builder, {0, .Primary, 0, 1, glyphs, {}}),
        storage.Bounded_Builder_Status.Limit_Exceeded)

    cache := new(dynviewmodel.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    testing.expect_value(t, shaped_builder_seal(
        &builder, cache, 1, dynviewmodel.DYNVIEW_MAX_SHAPED_RUNS, 7),
        storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(cache^.shaped_runs), dynviewmodel.DYNVIEW_MAX_SHAPED_RUNS)
    testing.expect_value(t, len(cache^.shaped_glyphs),
        fontmodel.FONT_SHAPED_GLYPH_CAPACITY)
    testing.expect_value(t, shaped_builder_seal(
        &builder, cache, 1, dynviewmodel.DYNVIEW_MAX_SHAPED_RUNS, 7),
        storage.Bounded_Builder_Status.Sealed)
    testing.expect_value(t, len(cache^.shaped_runs), 0)
}

//   Verify invalid spans and stale generations publish no shaped aliases.
@(test)
dynview_shaped_builder_rejects_invalid_spans_and_generation :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    testing.expect(t, storage.arena_owner_init(&arena))
    defer storage.arena_owner_destroy(&arena)
    cache := new(dynviewmodel.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    glyph := []fontmodel.Shaped_Glyph{{glyph_id = 1}}

    builder: Dynview_Shaped_Builder
    testing.expect_value(t, shaped_builder_init(&builder, &arena, 7),
        storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_append(
        &builder, {0, .Primary, 1, 1, glyph, {}}), storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_seal(
        &builder, cache, 1, 1, 7), storage.Bounded_Builder_Status.Invalid_Argument)
    testing.expect_value(t, len(cache^.shaped_runs), 0)

    storage.arena_owner_reset(&arena)
    testing.expect_value(t, shaped_builder_init(&builder, &arena, 8),
        storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_append(
        &builder, {0, .Primary, 0, 1, glyph, {}}), storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_seal(
        &builder, cache, 1, 1, 9), storage.Bounded_Builder_Status.Invalid_Argument)
    testing.expect_value(t, len(cache^.shaped_glyphs), 0)
}

//   Verify sealing rejects command and glyph spans outside their populated bounds.
@(test)
dynview_shaped_builder_rejects_layout_and_glyph_spans :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    testing.expect(t, storage.arena_owner_init(&arena))
    defer storage.arena_owner_destroy(&arena)
    cache := new(dynviewmodel.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    glyph := []fontmodel.Shaped_Glyph{{glyph_id = 1}}
    builder: Dynview_Shaped_Builder
    testing.expect_value(t, shaped_builder_init(&builder, &arena, 4),
        storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_append(
        &builder, {0, .Primary, 0, 1, glyph, {}}),
        storage.Bounded_Builder_Status.Ok)
    builder.runs.storage[0].math_command_index = 1
    testing.expect_value(t, shaped_builder_seal(&builder, cache, 1, 1, 4),
        storage.Bounded_Builder_Status.Invalid_Argument)

    storage.arena_owner_reset(&arena)
    testing.expect_value(t, shaped_builder_init(&builder, &arena, 4),
        storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_append(
        &builder, {0, .Primary, 0, 1, glyph, {}}),
        storage.Bounded_Builder_Status.Ok)
    builder.runs.storage[0].glyph_count = 2
    testing.expect_value(t, shaped_builder_seal(&builder, cache, 1, 1, 4),
        storage.Bounded_Builder_Status.Invalid_Argument)
    testing.expect_value(t, len(cache^.shaped_runs), 0)
}

//   Verify allocation failure retains fallback layout state without partial publication.
@(test)
dynview_shaped_builder_allocation_failure_preserves_fallback :: proc(t: ^testing.T) {
    cache := new(dynviewmodel.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    remaining_allocations := 0
    allocator := shaped_builder_test_allocator(&remaining_allocations)
    builder: Dynview_Shaped_Builder
    testing.expect_value(t, shaped_builder_init_with_allocator(
        &builder, allocator, 3), storage.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shaped_builder_append(&builder,
        {0, .Primary, 0, 1, []fontmodel.Shaped_Glyph{{glyph_id = 1}}, {}}),
        storage.Bounded_Builder_Status.Allocation_Failed)
    testing.expect_value(t, len(cache^.shaped_runs), 0)
    testing.expect_value(t, len(cache^.shaped_glyphs), 0)
}

//   Create an allocator controlled by a remaining-allocation counter.
shaped_builder_test_allocator :: proc(remaining_allocations: ^int) -> mem.Allocator {
    return mem.Allocator{
        procedure = shaped_builder_test_allocator_proc,
        data = remaining_allocations,
    }
}

//   Fail allocation requests after the test-owned counter reaches zero.
shaped_builder_test_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
    ([]byte, mem.Allocator_Error) {

    remaining := cast(^int)allocator_data
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        if remaining^ <= 0 {
            return nil, .Out_Of_Memory
        }
        remaining^ -= 1
    }
    return runtime.default_allocator_proc(
        nil, mode, size, alignment, old_memory, old_size, location)
}