package dynview_core

import "base:runtime"
import "core:mem"
import "core:testing"
import "core:thread"
import app_core "../../core"
import dynparse "../parse"

Dynview_Parse_Test_Task :: struct {
    source: string,
    key: Dynview_Document_Key,
    generation: u64,
    result: ^Dynview_Parse_Result,
    status: Dynview_Document_Status,
}

//   Build one isolated parser fixture on a test-owned worker thread.
document_parse_test_worker :: proc(thread_handle: ^thread.Thread) {
    task := (^Dynview_Parse_Test_Task)(thread_handle.data)
    task.status = dynview_parse_build_keyed(
        task.source, task.key, task.generation, task.result)
}

//   Run both isolated parse fixtures concurrently and join before inspection.
document_parse_test_run_concurrently :: proc(tasks: ^[2]Dynview_Parse_Test_Task) {
    threads: [2]^thread.Thread
    for index in 0..<len(threads) {
        threads[index] = thread.create(document_parse_test_worker)
        threads[index].data = &tasks[index]
        threads[index].init_context = context
        thread.start(threads[index])
    }
    for worker in threads {
        thread.join(worker)
        thread.destroy(worker)
    }
}

//   Initialize one document store and shared arena for focused tests.
document_store_test_init :: proc(
    memory: ^app_core.Animation_Memory,
    store: ^app_core.Dynview_Document_Store,
    generation: u64) -> bool {
    return app_core.animation_memory_init(memory) &&
        app_core.dynview_document_store_init(store, memory) &&
        app_core.animation_memory_begin_generation(memory, generation) == .Ok &&
        document_store_test_publish(store, memory, generation)
}

//   Publish a test generation through the shared-core lifecycle contract.
document_store_test_publish :: proc(
    store: ^app_core.Dynview_Document_Store,
    memory: ^app_core.Animation_Memory,
    generation: u64) -> bool {
    app_core.dynview_document_store_publish_generation(store, memory, generation)
    return store.generation == generation
}

//   Destroy one focused store fixture in borrower-before-owner order.
document_store_test_destroy :: proc(
    memory: ^app_core.Animation_Memory,
    store: ^app_core.Dynview_Document_Store) {
    app_core.dynview_document_store_destroy(store)
    app_core.animation_memory_destroy(memory)
}

//   Verify concurrent parse builds mutate only their independent result records.
@(test)
document_parse_builds_are_isolated_from_store_state :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 31))
    defer document_store_test_destroy(&memory, &store)
    math_result := new(Dynview_Parse_Result, context.temp_allocator)
    document_result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(math_result, context.temp_allocator)
    defer free(document_result, context.temp_allocator)
    math_source := "x^2"
    document_source := "first $x$\n\nsecond"
    tasks := [2]Dynview_Parse_Test_Task{
        {source = math_source, generation = 31, result = math_result,
            key = document_store_key(math_source, 1, .Math, .Display,
                document_store_source_hash(math_source))},
        {source = document_source, generation = 31, result = document_result,
            key = document_store_key(document_source, 1, .Document, .Display,
                document_store_source_hash(document_source))},
    }
    before := document_store_diagnostics(&store)
    document_parse_test_run_concurrently(&tasks)

    testing.expect_value(t, tasks[0].status, Dynview_Document_Status.Ok)
    testing.expect_value(t, tasks[1].status, Dynview_Document_Status.Ok)
    testing.expect(t, math_result.ready && document_result.ready)
    testing.expect_value(t, math_result.generation, u64(31))
    testing.expect_value(t, document_result.generation, u64(31))
    testing.expect_value(t, document_store_diagnostics(&store), before)
    _, math_lookup := document_store_lookup(&store, math_source, .Math, .Display)
    _, document_lookup := document_store_lookup(
        &store, document_source, .Document, .Display)
    testing.expect_value(t, math_lookup, Dynview_Document_Status.Not_Found)
    testing.expect_value(t, document_lookup, Dynview_Document_Status.Not_Found)
}

//   Verify owner commit publishes the same immutable bytes as legacy interning.
@(test)
document_parse_commit_matches_legacy_intern :: proc(t: ^testing.T) {
    direct_memory, split_memory: app_core.Animation_Memory
    direct_store, split_store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&direct_memory, &direct_store, 32))
    defer document_store_test_destroy(&direct_memory, &direct_store)
    testing.expect(t, document_store_test_init(&split_memory, &split_store, 32))
    defer document_store_test_destroy(&split_memory, &split_store)
    source := "first $x^2$\n\nsecond"
    direct, direct_status := document_store_intern(
        &direct_store, source, .Document, .Display)
    result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(result, context.temp_allocator)
    build_status := dynview_parse_build_document(source, 1, 32, result)
    split, split_status := document_store_commit(&split_store, source, result)

    testing.expect_value(t, build_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, split_status, direct_status)
    direct_entry := &direct_store.entries[direct.index]
    split_entry := &split_store.entries[split.index]
    testing.expect_value(t, split_entry.blob_byte_count, direct_entry.blob_byte_count)
    testing.expect(t, mem.compare(document_store_blob_bytes(split_entry),
        document_store_blob_bytes(direct_entry)) == 0)
}

//   Verify a committed rejected parse remains an exact negative-cache entry.
@(test)
document_parse_commit_preserves_negative_cache :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 33))
    defer document_store_test_destroy(&memory, &store)
    source := "\\textbf{x"
    result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(result, context.temp_allocator)
    build_status := dynview_parse_build_document(source, 1, 33, result)
    first, first_status := document_store_commit(&store, source, result)
    second, second_status := document_store_commit(&store, source, result)

    testing.expect_value(t, build_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, first_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, second_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, second, first)
    testing.expect_value(t,
        document_store_diagnostics(&store).negative_cache_hits, u64(1))
}

//   Verify a result built for a retired generation cannot mutate the new store.
@(test)
document_parse_commit_rejects_retired_generation :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 34))
    defer document_store_test_destroy(&memory, &store)
    result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(result, context.temp_allocator)
    testing.expect_value(t, dynview_parse_build_math(
        "x", .Display, 1, 34, result), Dynview_Document_Status.Ok)
    app_core.dynview_document_store_clear_generation(&store)
    testing.expect_value(t, app_core.animation_memory_begin_generation(
        &memory, 35), app_core.Animation_Memory_Status.Ok)
    testing.expect(t, document_store_test_publish(&store, &memory, 35))
    before := document_store_diagnostics(&store)
    handle, status := document_store_commit(&store, "x", result)

    testing.expect_value(t, status, Dynview_Document_Status.Illegal_State)
    testing.expect_value(t, handle, app_core.Dynview_Document_Handle{})
    testing.expect_value(t, document_store_diagnostics(&store), before)
}

//   Verify invalid rebuilds and failed owner allocation publish no partial entry.
@(test)
document_parse_split_path_fails_atomically :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 36))
    defer document_store_test_destroy(&memory, &store)
    result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(result, context.temp_allocator)
    testing.expect_value(t, dynview_parse_build_math(
        "x", .Display, 1, 36, result), Dynview_Document_Status.Ok)
    invalid_key := result.key
    invalid_key.source_length += 1
    testing.expect_value(t, dynview_parse_build_keyed(
        "x", invalid_key, 36, result), Dynview_Document_Status.Invalid_Argument)
    testing.expect(t, !result.ready)
    testing.expect_value(t, dynview_parse_build_math(
        "x", .Display, 1, 36, result), Dynview_Document_Status.Ok)
    _, mismatch_status := document_store_commit(&store, "y", result)
    testing.expect_value(t, mismatch_status, Dynview_Document_Status.Invalid_Argument)
    testing.expect_value(t, store.entry_count, 0)
    remaining_allocations := 0
    store.allocator = document_store_test_allocator(&remaining_allocations)
    before := document_store_diagnostics(&store)
    handle, status := document_store_commit(&store, "x", result)
    after := document_store_diagnostics(&store)

    testing.expect_value(t, status, Dynview_Document_Status.Allocation_Failed)
    testing.expect_value(t, handle, app_core.Dynview_Document_Handle{})
    testing.expect_value(t, after.entry_count, before.entry_count)
    testing.expect_value(t, after.blob_bytes, before.blob_bytes)
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)
    testing.expect_value(t, after.allocation_failures, before.allocation_failures + 1)
}

//   Verify unsupported keyed parse modes commit as deterministic rejections.
@(test)
document_parse_commit_preserves_dispatch_rejection :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 37))
    defer document_store_test_destroy(&memory, &store)
    result := new(Dynview_Parse_Result, context.temp_allocator)
    defer free(result, context.temp_allocator)
    key := document_store_key("x", 1, .Math, .Display,
        document_store_source_hash("x"))
    key.parse_mode = dynparse.Tex_Source_Mode(255)
    build_status := dynview_parse_build_keyed("x", key, 37, result)
    handle, commit_status := document_store_commit(&store, "x", result)
    document, resolve_status := document_store_resolve(&store, handle)

    testing.expect_value(t, build_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, commit_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, resolve_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t,
        document.parse_status, dynparse.Tex_Parse_Status.Unexpected_Token)
}

//   Verify identical parse requests allocate once and resolve immutable semantics.
@(test)
document_store_deduplicates_and_resolves :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 11))
    defer document_store_test_destroy(&memory, &store)

    first, first_status := document_store_intern(
        &store, "x^2", .Math, .Display)
    before := document_store_diagnostics(&store)
    second, second_status := document_store_intern(
        &store, "x^2", .Math, .Display)
    after := document_store_diagnostics(&store)
    testing.expect_value(t, first_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, second_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, second, first)
    testing.expect_value(t, after.entry_count, 1)
    testing.expect_value(t, after.intern_hits, u64(1))
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)

    document, resolve_status := document_store_resolve(&store, first)
    testing.expect_value(t, resolve_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, document.source, "x^2")
    testing.expect_value(t, document.parse_status, dynparse.Tex_Parse_Status.Ok)
    testing.expect_value(t, document_store_text(
        &document, document.plain_text), "{x}^{2}")
    testing.expect_value(t, uintptr(raw_data(document.ops)) %
        uintptr(align_of(dynparse.Tex_Math_Op)), uintptr(0))
    testing.expect_value(t, uintptr(raw_data(document.programs)) %
        uintptr(align_of(dynparse.Tex_Math_Program)), uintptr(0))
}

//   Verify semantic document blocks resolve from immutable aligned storage.
@(test)
document_store_resolves_semantic_document_blocks :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 21))
    defer document_store_test_destroy(&memory, &store)
    source := "first $x$\n\nsecond\n\\[y\\]\nthird"

    handle, status := document_store_intern(
        &store, source, .Document, .Display)
    testing.expect_value(t, status, Dynview_Document_Status.Ok)
    document, resolve_status := document_store_resolve(&store, handle)
    testing.expect_value(t, resolve_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, len(document.document_blocks), 4)
    testing.expect_value(t, document.document_blocks[2].kind,
        dynparse.Tex_Document_Block_Kind.Display)
    display := document.document_blocks[2]
    testing.expect_value(t, document.document_inlines[
        display.inline_start].kind, dynparse.Tex_Document_Inline_Kind.Math)
    testing.expect_value(t, uintptr(raw_data(document.document_blocks)) %
        uintptr(align_of(dynparse.Tex_Document_Block)), uintptr(0))
    testing.expect_value(t, uintptr(raw_data(document.document_inlines)) %
        uintptr(align_of(dynparse.Tex_Document_Inline)), uintptr(0))
}

// Verify technical display rows resolve from aligned generation-owned storage.
@(test)
document_store_resolves_technical_display_rows :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 22))
    defer document_store_test_destroy(&memory, &store)
    source := "\\begin{align}a&=b\\\\c&=d\\notag\\end{align}"

    handle, status := document_store_intern(
        &store, source, .Document, .Display)
    testing.expect_value(t, status, Dynview_Document_Status.Ok)
    document, resolve_status := document_store_resolve(&store, handle)

    testing.expect_value(t, resolve_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, len(document.document_display_rows), 2)
    testing.expect(t, document.document_display_rows[0].secondary_program >= 0)
    testing.expect(t, document.document_display_rows[1].suppress_number)
    testing.expect_value(t, uintptr(raw_data(document.document_display_rows)) %
        uintptr(align_of(dynparse.Tex_Document_Display_Row)), uintptr(0))
}

//   Verify equal hashes continue probing and compare exact retained source bytes.
@(test)
document_store_resolves_forced_hash_collisions :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 12))
    defer document_store_test_destroy(&memory, &store)

    first_key := document_store_key("x", 1, .Math, .Display, 17)
    second_key := document_store_key("y", 1, .Math, .Display, 17)
    first, first_status := document_store_intern_keyed(&store, "x", first_key)
    second, second_status := document_store_intern_keyed(&store, "y", second_key)
    testing.expect_value(t, first_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, second_status, Dynview_Document_Status.Ok)
    testing.expect(t, first.index != second.index)
    diagnostics := document_store_diagnostics(&store)
    testing.expect_value(t, diagnostics.collision_count, u64(1))

    first_document, _ := document_store_resolve(&store, first)
    second_document, _ := document_store_resolve(&store, second)
    testing.expect_value(t, first_document.source, "x")
    testing.expect_value(t, second_document.source, "y")
}

//   Verify profile, parse mode, and root style remain distinct identity fields.
@(test)
document_store_keys_every_semantic_input :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 13))
    defer document_store_test_destroy(&memory, &store)
    source_hash := document_store_source_hash("x")

    display_key := document_store_key("x", 1, .Math, .Display, source_hash)
    text_key := document_store_key("x", 1, .Math, .Text, source_hash)
    profile_key := document_store_key("x", 2, .Math, .Display, source_hash)
    document_key := document_store_key("x", 1, .Document, .Display, source_hash)
    revision_key := display_key
    revision_key.grammar_revision += 1
    display, _ := document_store_intern_keyed(&store, "x", display_key)
    text, _ := document_store_intern_keyed(&store, "x", text_key)
    profile, _ := document_store_intern_keyed(&store, "x", profile_key)
    document, _ := document_store_intern_keyed(&store, "x", document_key)
    revision, _ := document_store_intern_keyed(&store, "x", revision_key)
    testing.expect(t, display.index != text.index)
    testing.expect(t, display.index != profile.index)
    testing.expect(t, display.index != document.index)
    testing.expect(t, display.index != revision.index)
    testing.expect_value(t, document_store_diagnostics(&store).entry_count, 5)
}

//   Verify the fixed index admits exactly its capacity and rejects one more key.
@(test)
document_store_enforces_exact_entry_capacity :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 20))
    defer document_store_test_destroy(&memory, &store)
    source_hash := document_store_source_hash("x")
    for index in 0..<app_core.DYNVIEW_DOCUMENT_ENTRY_CAPACITY {
        key := document_store_key(
            "x", u32(index + 1), .Math, .Display, source_hash)
        _, status := document_store_intern_keyed(&store, "x", key)
        testing.expect_value(t, status, Dynview_Document_Status.Ok)
    }
    before := document_store_diagnostics(&store)
    excess_key := document_store_key("x",
        u32(app_core.DYNVIEW_DOCUMENT_ENTRY_CAPACITY + 1),
        .Math, .Display, source_hash)
    _, excess_status := document_store_intern_keyed(&store, "x", excess_key)
    after := document_store_diagnostics(&store)
    testing.expect_value(t, excess_status, Dynview_Document_Status.Out_Of_Capacity)
    testing.expect_value(
        t, after.entry_count, app_core.DYNVIEW_DOCUMENT_ENTRY_CAPACITY)
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)
}

//   Verify deterministic parser rejection is cached without semantic allocation.
@(test)
document_store_caches_rejected_documents :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 14))
    defer document_store_test_destroy(&memory, &store)

    first, first_status := document_store_intern(
        &store, "\\textbf{x", .Document, .Display)
    before := document_store_diagnostics(&store)
    second, second_status := document_store_intern(
        &store, "\\textbf{x", .Document, .Display)
    after := document_store_diagnostics(&store)
    testing.expect_value(t, first_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, second_status, Dynview_Document_Status.Rejected)
    testing.expect_value(t, second, first)
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)
    testing.expect_value(t, after.negative_cache_hits, u64(1))

    rejected, resolve_status := document_store_resolve(&store, first)
    testing.expect_value(t, resolve_status, Dynview_Document_Status.Rejected)
    testing.expect_value(
        t, rejected.parse_status, dynparse.Tex_Parse_Status.Unclosed_Group)
    testing.expect_value(t, len(rejected.ops), 0)
}

//   Verify the logical byte quota admits its measured bound and rejects one more blob.
@(test)
document_store_enforces_exact_byte_quota :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 15))
    defer document_store_test_destroy(&memory, &store)
    _, status := document_store_intern(&store, "x", .Math, .Display)
    testing.expect_value(t, status, Dynview_Document_Status.Ok)
    exact_bytes := store.blob_bytes

    app_core.dynview_document_store_clear_generation(&store)
    testing.expect_value(t, app_core.animation_memory_begin_generation(
        &memory, 16), app_core.Animation_Memory_Status.Ok)
    testing.expect(t, document_store_test_publish(&store, &memory, 16))
    store.byte_quota = exact_bytes
    _, exact_status := document_store_intern(&store, "x", .Math, .Display)
    before := document_store_diagnostics(&store)
    _, excess_status := document_store_intern(&store, "y", .Math, .Display)
    after := document_store_diagnostics(&store)
    testing.expect_value(t, exact_status, Dynview_Document_Status.Ok)
    testing.expect_value(t, excess_status, Dynview_Document_Status.Out_Of_Capacity)
    testing.expect_value(t, after.entry_count, 1)
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)
}

//   Verify failed final allocation publishes neither an entry nor a handle.
@(test)
document_store_rolls_back_allocation_failure :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 17))
    defer document_store_test_destroy(&memory, &store)
    remaining_allocations := 0
    store.allocator = document_store_test_allocator(&remaining_allocations)

    handle, status := document_store_intern(&store, "x", .Math, .Display)
    testing.expect_value(t, status, Dynview_Document_Status.Allocation_Failed)
    testing.expect_value(t, handle, app_core.Dynview_Document_Handle{})
    testing.expect_value(t, store.entry_count, 0)
    testing.expect_value(t, store.blob_bytes, 0)
    testing.expect_value(t, store.allocation_failures, u64(1))
}

//   Verify generation transition invalidates every previously issued handle.
@(test)
document_store_rejects_stale_handles :: proc(t: ^testing.T) {
    memory: app_core.Animation_Memory
    store: app_core.Dynview_Document_Store
    testing.expect(t, document_store_test_init(&memory, &store, 18))
    defer document_store_test_destroy(&memory, &store)
    handle, status := document_store_intern(&store, "x", .Math, .Display)
    testing.expect_value(t, status, Dynview_Document_Status.Ok)

    app_core.dynview_document_store_clear_generation(&store)
    testing.expect_value(t, app_core.animation_memory_begin_generation(
        &memory, 19), app_core.Animation_Memory_Status.Ok)
    testing.expect(t, document_store_test_publish(&store, &memory, 19))
    _, resolve_status := document_store_resolve(&store, handle)
    diagnostics := document_store_diagnostics(&store)
    testing.expect_value(t, resolve_status, Dynview_Document_Status.Illegal_State)
    testing.expect_value(t, diagnostics.entry_count, 0)
    testing.expect_value(t, diagnostics.generation, u64(19))
    testing.expect_value(t, diagnostics.generation_resets, u64(2))
}

//   Build a deterministic allocator that fails after its test-owned allowance.
document_store_test_allocator :: proc(remaining: ^int) -> mem.Allocator {
    return {procedure = document_store_test_allocator_proc, data = remaining}
}

//   Reject exhausted allocations while forwarding cleanup to the heap allocator.
document_store_test_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
    ([]byte, mem.Allocator_Error) {
    remaining := (^int)(allocator_data)
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        if remaining^ <= 0 {
            return nil, mem.Allocator_Error.Out_Of_Memory
        }
        remaining^ -= 1
    }
    return runtime.heap_allocator_proc(
        nil, mode, size, alignment, old_memory, old_size, location)
}