package dynview_compile

import dynviewmodel "../model"

import storage "../../core/storage"

import dyncore "../core"

import "core:mem"
import "core:testing"

//   Initialize caller-owned display-cache arena storage without copying its allocator.
compiled_bytes_test_arena_init :: proc(
    t: ^testing.T,
    arena: ^storage.Arena_Owner) {

    testing.expect(t, storage.arena_owner_init(arena, 256*uint(mem.Kilobyte)))
}

// Verify semantic compilation skips command layout while standalone streams retain it.
@(test)
semantic_documents_publish_without_command_layout :: proc(t: ^testing.T) {
    runtime_arena, cache_arena: storage.Arena_Owner
    compiled_bytes_test_arena_init(t, &runtime_arena)
    defer storage.arena_owner_destroy(&runtime_arena)
    compiled_bytes_test_arena_init(t, &cache_arena)
    defer storage.arena_owner_destroy(&cache_arena)
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    documents := [1]dynviewmodel.Dynview_Document{{}}
    runtime^.content.documents = documents[:]

    semantic_status := compile_derived_views(runtime, &cache_arena, {}, {})

    testing.expect_value(t, semantic_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, runtime^.compile_cache.document_layout_is_valid)
    testing.expect(t, !runtime^.compile_cache.layout_is_valid)
    testing.expect_value(t, len(runtime^.compile_cache.layout_lines), 0)
    testing.expect_value(t, len(runtime^.compile_cache.layout_items), 0)

    runtime^.content.documents = nil
    storage.arena_owner_reset(&cache_arena)
    standalone_status := compile_derived_views(runtime, &cache_arena, {}, {})

    testing.expect_value(t, standalone_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, runtime^.compile_cache.layout_is_valid)
}

//   Verify compilation seals command text.
@(test)
compiled_bytes_publish_sealed_plain_text :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer storage.arena_owner_destroy(&arena)
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    buffer := &runtime^.command_buffer
    copy(buffer^.text_bytes[:], "draw")
    buffer^.text_bytes_len = 4
    buffer^.command_count = 3
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 7}
    buffer^.commands[1] = {kind = .Text_Run, text_offset = 0, text_len = 4}
    buffer^.commands[2] = {kind = .End_Block}

    status := rebuild_compiled_plain_text(runtime, &arena)

    cache := &runtime^.compile_cache
    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.compiled_plain_text_len, 4)
    testing.expect_value(t, string(cache^.compiled_plain_text), "draw")
}

//   Verify an incomplete command stream publishes no compiled byte aliases.
@(test)
compiled_bytes_reject_incomplete_stream_without_publication :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer storage.arena_owner_destroy(&arena)
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.command_buffer.command_count = 1
    runtime^.command_buffer.commands[0] = {kind = .Begin_Block, block_id = 1}

    status := rebuild_compiled_plain_text(runtime, &arena)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_ILLEGAL_STATE)
    testing.expect_value(t, len(runtime^.compile_cache.compiled_plain_text), 0)
}

//   Verify published immutable views override conflicting fixed staging records.
@(test)
compiled_bytes_consume_published_content_views :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer storage.arena_owner_destroy(&arena)
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    buffer := &runtime^.command_buffer
    buffer^.command_count = 1
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 99}
    commands := [3]dynviewmodel.Dynview_Command{
        {kind = .Begin_Block, block_id = 7},
        {kind = .Text_Run, block_id = 7, text_len = 4},
        {kind = .End_Block, block_id = 7},
    }
    text: string = "view"
    buffer^.command_view = commands[:]
    buffer^.text_view = transmute([]u8)text

    status := rebuild_compiled_plain_text(runtime, &arena)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, string(runtime^.compile_cache.compiled_plain_text), text)
    testing.expect_value(t, raw_data(dyncore.command_buffer_commands(buffer)),
        raw_data(buffer^.command_view))
    testing.expect_value(t, raw_data(dyncore.command_buffer_text(buffer)),
        raw_data(buffer^.text_view))
}

//   Verify compiled plain text cannot grow beyond its hard admission limit.
@(test)
compiled_bytes_reject_plain_text_overflow_without_publication :: proc(t: ^testing.T) {
    arena: storage.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer storage.arena_owner_destroy(&arena)
    cache := new(dynviewmodel.Dynview_Compile_Cache, context.allocator)
    defer free(cache, context.allocator)
    state := Dynview_Compile_State{}
    testing.expect_value(t, storage.bounded_byte_builder_init(
        &state.plain_text_builder, dynviewmodel.DYNVIEW_MAX_TEXT_BYTES, &arena),
        storage.Bounded_Builder_Status.Ok)
    state.plain_text_builder.count = dynviewmodel.DYNVIEW_MAX_TEXT_BYTES

    status := append_compiled_byte(cache, &state, 'x')

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, cache^.compiled_plain_text_len, 0)
    testing.expect_value(t, len(cache^.compiled_plain_text), 0)
}
