#+test
package font

import app_core "../../core"
import "../../taskpool"

import "core:mem"
import "core:testing"
import "core:thread"
import vmem "core:mem/virtual"

// Complete one pool slot without touching shared application state.
test_task_succeed :: proc(payload: rawptr) -> taskpool.Task_Result {
    return .Succeeded
}

// Verify the flattened codepoint set matches the declared range policy.
@(test)
view_test_codepoint_set :: proc(t: ^testing.T) {
    codepoints := codepoint_set()

    expected_count := i32(0)
    for codepoint_range in FONT_CODEPOINT_RANGES {
        expected_count += i32(codepoint_range.last - codepoint_range.first) + 1
    }

    testing.expect_value(t, codepoints.count, expected_count)
    testing.expect_value(t, codepoints.values[0], rune(0x0020))
}

// Verify codepoint support checks match the declared range policy.
@(test)
view_test_codepoint_is_supported :: proc(t: ^testing.T) {
    testing.expect(t, codepoint_is_supported(rune(0x0041)))
    testing.expect(t, codepoint_is_supported(rune(0x2500)))
    testing.expect(t, !codepoint_is_supported(rune(0x3000)))
}

// Verify representative language, diacritic, and mathematical glyphs remain loaded.
@(test)
view_test_codepoint_policy_coverage :: proc(t: ^testing.T) {
    supported := []rune{
        'ä', 0x0308, 0x1eb0, 'α', 'Ж', 'Ա', 'א', 'ش', 'ა',
        '∞', '∫', '⌈', '⟨', 0x27f6, 0x2a0c, 0x1d6fc, 0x1ee00,
    }
    for codepoint in supported {
        testing.expect(t, codepoint_is_supported(codepoint))
    }

    codepoints := codepoint_set()
    testing.expect(t, codepoints.count > 7000)
    testing.expect(t, codepoints.count < FONT_CODEPOINT_CAPACITY)
    testing.expect(t, !codepoint_is_supported(rune(0x2502)))
    testing.expect(t, !codepoint_is_supported('漢'))
}

// Verify every existing dynview weight and italic combination maps to its cache key.
@(test)
view_test_font_flags_map_to_cache_keys :: proc(t: ^testing.T) {
    cases := [?]struct {
        flags: app_core.Font_Variant_Flags,
        key: Font_Key,
    }{
        {.Regular, .Regular},
        {.Light, .Light},
        {.Medium, .Medium},
        {.Semibold, .Semi_Bold},
        {.Bold, .Bold},
        {.Extrabold, .Extra_Bold},
        {.Black, .Black},
    }
    for test_case in cases {
        testing.expect_value(t, font_key_from_flags(test_case.flags), test_case.key)
        italic_flags := app_core.Font_Variant_Flags(
            u32(test_case.flags) | u32(app_core.Font_Variant_Flags.Italic))
        testing.expect_value(t, int(font_key_from_flags(italic_flags)),
            int(test_case.key) + 1)
    }
}

// Verify CPU preparation reproduces the established Regular atlas contract.
@(test)
view_test_prepare_regular :: proc(t: ^testing.T) {
    codepoint_set := codepoint_set()
    codepoints := codepoint_set.values[:codepoint_set.count]
    prepared: Prepared_Font
    success := prepare({
        key = .Regular,
        generation = 7,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints,
    }, &prepared, context.allocator)

    testing.expect(t, success)
    testing.expect_value(t, prepared.key, Font_Key.Regular)
    testing.expect_value(t, prepared.generation, u64(7))
    testing.expect_value(t, prepared.base_size, i32(32))
    testing.expect_value(t, prepared.glyph_count, i32(6795))
    testing.expect_value(t, prepared.padding, i32(4))
    testing.expect_value(t, prepared.atlas_width, i32(4096))
    testing.expect_value(t, prepared.atlas_height, i32(2048))
    testing.expect_value(t, len(prepared.glyphs), 6795)
    testing.expect_value(t, len(prepared.rectangles), 6795)
    testing.expect_value(t, len(prepared.atlas_pixels), 4096*2048*2)
    testing.expect_value(t, prepared.glyphs[0].value, rune(' '))
    testing.expect_value(t, prepared.glyphs[0].advance_x, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_width, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_height, i32(32))

    prepare_destroy(&prepared)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify the cache reuses committed preparation pages until explicit destruction.
@(test)
view_test_preparation_arena_reuses_committed_pages :: proc(t: ^testing.T) {
    cache: Font_Cache
    testing.expect(t, cache_preparation_arena_init(&cache))
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    first, first_error := make([]u8, 2*mem.Megabyte, allocator)
    testing.expect(t, first_error == nil)
    first_pointer := raw_data(first)
    committed := cache.preparation_arena.curr_block.committed
    testing.expect(t, committed >= 2*mem.Megabyte)

    cache_preparation_arena_reset(&cache)
    testing.expect_value(t, cache.preparation_arena.total_used, uint(0))
    testing.expect_value(
        t, cache.preparation_arena.curr_block.committed, committed)
    second, second_error := make([]u8, 2*mem.Megabyte, allocator)
    testing.expect(t, second_error == nil)
    testing.expect(t, raw_data(second) == first_pointer)

    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    testing.expect(t, !cache.preparation_arena_initialized)
    testing.expect(t, cache.preparation_arena.curr_block == nil)
}

// Verify arena-owned prepared slices remain allocated until the cache resets them.
@(test)
view_test_prepared_font_uses_bulk_arena_release :: proc(t: ^testing.T) {
    cache: Font_Cache
    testing.expect(t, cache_preparation_arena_init(&cache))
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    codepoints := [1]rune{'A'}
    prepared: Prepared_Font
    testing.expect(t, prepare({
        key = .Bold,
        generation = 1,
        path = "assets/JuliaMono-Bold.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints[:],
    }, &prepared, allocator, .Arena))
    used := cache.preparation_arena.total_used
    testing.expect(t, used > 0)

    prepare_destroy(&prepared)
    testing.expect_value(t, cache.preparation_arena.total_used, used)
    cache_preparation_arena_reset(&cache)
    testing.expect_value(t, cache.preparation_arena.total_used, uint(0))

    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
}

// Verify incomplete prepared results are rejected before display finalization.
@(test)
view_test_prepared_validation :: proc(t: ^testing.T) {
    prepared := Prepared_Font{
        base_size = 64,
        glyph_count = 1,
        atlas_width = 8,
        atlas_height = 8,
    }
    testing.expect(t, !prepared_is_valid(&prepared))

    glyphs: [1]Prepared_Glyph
    rectangles: [1]Prepared_Rectangle
    atlas_pixels: [8*8*2]u8
    prepared.glyphs = glyphs[:]
    prepared.rectangles = rectangles[:]
    prepared.atlas_pixels = atlas_pixels[:]
    testing.expect(t, prepared_is_valid(&prepared))
}

// Verify stale generations preserve the active font and prepared ownership.
@(test)
view_test_cache_rejects_stale_publication :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 5,
        requested_generation = 5,
        resident = true,
    }
    prepared := Prepared_Font{
        key = .Bold,
        generation = 4,
        glyph_count = 1,
    }

    testing.expect(t, !cache_publish(&cache, &prepared))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(5))
    testing.expect_value(t, prepared.glyph_count, i32(1))
}

// Verify a rapid replacement supersedes active work before GPU finalization.
@(test)
view_test_cache_reload_supersedes_active_generation :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 5,
        requested_generation = 5,
        resident = true,
        state = .Ready,
    }
    testing.expect(t, cache_reload(&cache, .Bold))
    testing.expect_value(t, cache.preparation.task.generation, u64(6))
    testing.expect(t, cache_reload(&cache, .Bold))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].requested_generation, u64(7))

    prepared := Prepared_Font{key = .Bold, generation = 6, glyph_count = 1}
    testing.expect(t, !cache_publish(&cache, &prepared))
    testing.expect_value(t, prepared.glyph_count, i32(1))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(5))
}

// Verify a matching reload failure leaves the previous resident generation drawable.
@(test)
view_test_cache_reload_failure_preserves_resident :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 64},
        generation = 3,
        requested_generation = 3,
        resident = true,
        state = .Ready,
    }
    testing.expect(t, cache_reload(&cache, .Regular))
    cache_fail_preparation(&cache)

    entry := cache.entries[int(Font_Key.Regular)]
    testing.expect_value(t, entry.state, Font_Load_State.Failed)
    testing.expect(t, entry.resident)
    testing.expect_value(t, entry.generation, u64(3))
    testing.expect_value(t, entry.font.baseSize, i32(64))
}

// Verify rapid source edits collapse into one newest replacement generation.
@(test)
view_test_source_monitor_debounces_rapid_changes :: proc(t: ^testing.T) {
    cache: Font_Cache
    key := Font_Key.Bold
    cache.entries[int(key)] = {
        font = {baseSize = 55},
        generation = 2,
        requested_generation = 2,
        resident = true,
        state = .Ready,
    }
    cache.source_monitor.initialized = true
    cache.source_monitor.entries[int(key)].observed = {
        modification_ns = 10, size = 100, present = true,
    }

    source_monitor_observe(
        &cache, key, {modification_ns = 20, size = 110, present = true}, 100)
    source_monitor_observe(
        &cache, key, {modification_ns = 30, size = 120, present = true}, 200)
    source_monitor_commit(&cache, 200 + FONT_SOURCE_DEBOUNCE_NS - 1)
    testing.expect_value(
        t, cache.entries[int(key)].requested_generation, u64(2))

    source_monitor_commit(&cache, 200 + FONT_SOURCE_DEBOUNCE_NS)
    testing.expect_value(
        t, cache.entries[int(key)].requested_generation, u64(3))
    testing.expect_value(t, cache.preparation.task.generation, u64(3))
    testing.expect_value(t, cache.source_monitor.change_count, u64(1))
    testing.expect_value(t, cache.source_monitor.reload_count, u64(1))
    testing.expect_value(
        t, cache.source_monitor.entries[int(key)].observed.modification_ns,
        i64(30))
}

// Verify changes to unused optional sources do not create demand.
@(test)
view_test_source_monitor_ignores_unused_variant :: proc(t: ^testing.T) {
    cache: Font_Cache
    key := Font_Key.Black_Italic
    cache.source_monitor.entries[int(key)].observed = {
        modification_ns = 10, present = true,
    }
    source_monitor_observe(
        &cache, key, {modification_ns = 20, present = true}, 100)
    source_monitor_commit(&cache, 100 + FONT_SOURCE_DEBOUNCE_NS)

    testing.expect_value(
        t, cache.entries[int(key)].state, Font_Load_State.Unrequested)
    testing.expect_value(t, cache.source_monitor.change_count, u64(1))
    testing.expect_value(t, cache.source_monitor.reload_count, u64(0))
}

// Verify the service joins and discards stale successful work without publication.
@(test)
view_test_cache_service_discards_stale_completion :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    handle, outcome := taskpool.task_pool_submit(
        &pool, test_task_succeed, nil)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)

    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 4,
        requested_generation = 6,
        resident = true,
        state = .Requested,
    }
    cache.preparation.state = .Queued
    cache.preparation.handle = handle
    cache.preparation.task = {
        key = .Bold,
        generation = 5,
        prepared = {key = .Bold, generation = 5, glyph_count = 1},
    }
    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }

    testing.expect_value(t, cache.preparation.stale_completion_count, u64(1))
    testing.expect_value(t, cache.preparation.publication_count, u64(0))
    testing.expect_value(t, cache.preparation.failure_count, u64(0))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(4))
}

// Verify queue saturation retries and terminal task failure preserves residency.
@(test)
view_test_cache_retries_queue_full :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    occupied, _ := taskpool.task_pool_submit(
        &pool, test_task_succeed, nil)
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55}, resident = true,
    }
    testing.expect(t, cache_request(&cache, .Bold))
    testing.expect(t, prepare_task_set_path(
        &cache.preparation.task, "assets/missing-font.ttf"))

    cache_service(&cache, &pool)
    testing.expect_value(t, cache.preparation.state, Font_Prepare_Operation_State.Retry)
    testing.expect_value(t, cache.preparation.queue_full_count, u64(1))

    taskpool.task_pool_wait(&pool, occupied)
    cache_service(&cache, &pool)
    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }
    testing.expect_value(t, cache.preparation.failure_count, u64(1))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
}

// Verify shutdown cleans both retry-only and accepted task ownership states.
@(test)
view_test_cache_shutdown_task_states :: proc(t: ^testing.T) {
    retry_pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&retry_pool, 1, 1))
    retry_cache: Font_Cache
    testing.expect(t, cache_request(&retry_cache, .Bold))
    cache_shutdown_service(&retry_cache, &retry_pool)
    testing.expect(t, cache_preparation_idle(&retry_cache))
    testing.expect_value(t, retry_cache.preparation.failure_count, u64(1))
    taskpool.task_pool_destroy(&retry_pool)

    queued_pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&queued_pool, 1, 1))
    queued_cache: Font_Cache
    testing.expect(t, cache_request(&queued_cache, .Bold))
    testing.expect(t, prepare_task_set_path(
        &queued_cache.preparation.task, "assets/missing-font.ttf"))
    cache_service(&queued_cache, &queued_pool)
    testing.expect_value(
        t, queued_cache.preparation.state, Font_Prepare_Operation_State.Queued)
    cache_shutdown_service(&queued_cache, &queued_pool)
    testing.expect(t, cache_preparation_idle(&queued_cache))
    testing.expect_value(t, queued_cache.preparation.failure_count, u64(1))
    taskpool.task_pool_destroy(&queued_pool)
}

// Verify cache resolution borrows resident variants and falls back to Regular.
@(test)
view_test_cache_resolution :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 11},
        resident = true,
    }
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 22},
        resident = true,
        state = .Ready,
    }

    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 22)
    testing.expect_value(
        t, cache_resolve(&cache, .Black_Italic).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].request_count, u64(1))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].state,
        Font_Load_State.Preparing)
    testing.expect(t, !cache_request(&cache, .Black_Italic))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].coalesced_request_count,
        u64(1))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].fallback_resolution_count,
        u64(1))

    resolver := cache_terminal_resolver(&cache)
    testing.expect_value(
        t, resolver.resolve(resolver.user_data, .Bold).baseSize, 22)
}

// Verify distinct demand is serialized and failed variants remain on fallback.
@(test)
view_test_cache_serializes_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 11}, resident = true, state = .Ready,
    }

    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 11)
    testing.expect_value(t, cache_resolve(&cache, .Black).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].state,
        Font_Load_State.Preparing)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black)].state,
        Font_Load_State.Requested)

    cache.entries[int(Font_Key.Bold)].state = .Failed
    cache_finish_preparation(&cache)
    cache_begin_next_request(&cache)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black)].state,
        Font_Load_State.Preparing)
    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].state, Font_Load_State.Failed)
}
