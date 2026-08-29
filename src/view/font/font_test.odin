#+test
package font

import app_core "../../core"
import "../../taskpool"

import "core:mem"
import "core:os"
import "core:testing"
import "core:thread"
import vmem "core:mem/virtual"

Codepoint_Resolver_Test_Result :: struct {
    ascii : Font_Glyph_Resolve_Status,
    math : Font_Glyph_Resolve_Status,
    unsupported : Font_Glyph_Resolve_Status,
    capacity : Font_Glyph_Resolve_Status,
    pending_count : i32,
}

// Complete one pool slot without touching shared application state.
test_task_succeed :: proc(payload: rawptr) -> taskpool.Task_Result {
    return .Succeeded
}

// Verify direct resolver statuses and telemetry remain mutually consistent.
view_expect_codepoint_resolver_result :: proc(
    t: ^testing.T, entry: ^Font_Cache_Entry,
    result: Codepoint_Resolver_Test_Result) {

    testing.expect_value(t, result.ascii, Font_Glyph_Resolve_Status.Resident)
    testing.expect_value(t, result.math, Font_Glyph_Resolve_Status.Pending)
    testing.expect_value(
        t, result.unsupported, Font_Glyph_Resolve_Status.Unsupported)
    testing.expect_value(
        t, result.capacity, Font_Glyph_Resolve_Status.Capacity_Exhausted)
    testing.expect_value(t, result.pending_count, i32(1))
    testing.expect_value(t, entry.pending_glyph_count, result.pending_count)
    testing.expect_value(t, entry.pending_codepoint_count, u64(1))
    testing.expect_value(t, entry.unsupported_codepoint_count, u64(1))
    testing.expect_value(t, entry.capacity_rejection_count, u64(1))
}

// Verify the production compatibility seed is bounded and prepares independently.
@(test)
view_test_seed_codepoint_set :: proc(t: ^testing.T) {
    codepoints := seed_codepoint_set()
    testing.expect_value(t, codepoints.count, i32(96))
    testing.expect_value(t, codepoints.values[0], rune(0x0020))
    testing.expect_value(t, codepoints.values[94], rune(0x007e))
    testing.expect_value(t, codepoints.values[95], rune(0xfffd))

    prepared: Prepared_Font
    testing.expect(t, prepare({
        key = .Regular,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
    }, &prepared, context.allocator))
    testing.expect_value(t, prepared.glyph_count, i32(96))
    testing.expect(t, prepared.atlas_width <= 1024)
    testing.expect(t, prepared.atlas_height <= 1024)
    prepare_destroy(&prepared)
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

// Verify CPU preparation reproduces the production Regular seed contract.
@(test)
view_test_prepare_regular :: proc(t: ^testing.T) {
    codepoint_set := seed_codepoint_set()
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
    testing.expect_value(t, prepared.glyph_count, i32(96))
    testing.expect_value(t, prepared.padding, i32(4))
    testing.expect(t, prepared.atlas_width <= 1024)
    testing.expect(t, prepared.atlas_height <= 1024)
    testing.expect_value(t, len(prepared.glyphs), 96)
    testing.expect_value(t, len(prepared.rectangles), 96)
    testing.expect_value(t, prepared.glyphs[0].value, rune(' '))
    testing.expect(t, prepared.glyphs[0].glyph_id > 0)
    testing.expect_value(t, prepared.glyphs[0].advance_x, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_width, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_height, i32(32))

    prepare_destroy(&prepared)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify complete preparation includes every Regular face glyph in ID order.
@(test)
view_test_prepare_complete_regular :: proc(t: ^testing.T) {
    codepoints := seed_codepoint_set()
    prepared: Prepared_Font
    success := prepare({
        key = .Regular,
        generation = 9,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
        complete_face = true,
    }, &prepared, context.allocator)

    testing.expect(t, success)
    testing.expect(t, prepared.glyph_count > 0)
    testing.expect_value(t, prepared.glyphs[0].glyph_id, u32(0))
    last_index := len(prepared.glyphs) - 1
    testing.expect_value(t, prepared.glyphs[last_index].glyph_id, u32(last_index))
    testing.expect(t, prepared.atlas_width > 0)
    testing.expect(t, prepared.atlas_height > 0)

    prepare_destroy(&prepared)
}

// Verify bounded subset preparation preserves face glyph IDs and deterministic packing.
@(test)
view_test_prepare_glyph_page :: proc(t: ^testing.T) {
    glyph_ids := [3]u32{0, 17, 4000}
    request := Font_Glyph_Page_Request{
        key = .Regular,
        generation = 11,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        glyph_ids = glyph_ids[:],
    }
    first, second: Prepared_Font
    testing.expect(t, prepare_glyph_page(request, &first, context.allocator))
    testing.expect(t, prepare_glyph_page(request, &second, context.allocator))
    testing.expect_value(t, first.glyph_count, i32(len(glyph_ids)))
    testing.expect_value(t, first.atlas_width, second.atlas_width)
    testing.expect_value(t, first.atlas_height, second.atlas_height)
    for glyph, index in first.glyphs {
        testing.expect_value(t, glyph.glyph_id, glyph_ids[index])
        testing.expect_value(t, first.rectangles[index], second.rectangles[index])
    }
    prepare_destroy(&first)
    prepare_destroy(&second)
}

// Verify page preparation rejects duplicate and out-of-range face glyph IDs.
@(test)
view_test_prepare_glyph_page_rejects_invalid_ids :: proc(t: ^testing.T) {
    duplicate_ids := [2]u32{17, 17}
    out_of_range_ids := [1]u32{65535}
    prepared: Prepared_Font
    request := Font_Glyph_Page_Request{
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        glyph_ids = duplicate_ids[:],
    }
    testing.expect(t, !prepare_glyph_page(request, &prepared, context.allocator))
    testing.expect_value(t, len(prepared.glyphs), 0)
    request.glyph_ids = out_of_range_ids[:]
    testing.expect(t, !prepare_glyph_page(request, &prepared, context.allocator))
    testing.expect_value(t, len(prepared.glyphs), 0)
}

// Verify generation glyph metadata is exact-size, deduplicated, and reclaimed whole.
@(test)
view_test_font_generation_glyph_demand_lifecycle :: proc(t: ^testing.T) {
    entry: Font_Cache_Entry
    testing.expect(t, font_generation_glyphs_init(
        &entry, 6795, context.allocator))
    testing.expect_value(t, len(entry.glyphs), 6795)
    testing.expect(t, font_generation_request_glyph(&entry, 4000))
    testing.expect(t, !font_generation_request_glyph(&entry, 4000))
    testing.expect(t, !font_generation_request_glyph(&entry, 6795))
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    testing.expect_value(t, entry.glyphs[4000].state, Font_Glyph_State.Pending)

    font_generation_glyphs_destroy(&entry)
    testing.expect_value(t, len(entry.glyphs), 0)
    testing.expect_value(t, entry.pending_glyph_count, i32(0))
    font_generation_glyphs_destroy(&entry)
}

// Verify glyph resolution records one missing face glyph without duplicate demand.
@(test)
view_test_glyph_resolver_records_missing_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    testing.expect(t, font_generation_glyphs_init(
        entry, 32, context.allocator))

    _, first_resident := cache_terminal_resolve_glyph(
        &cache, .Regular, 17)
    _, second_resident := cache_terminal_resolve_glyph(
        &cache, .Regular, 17)
    testing.expect(t, !first_resident && !second_resident)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    font_generation_glyphs_destroy(entry)
}

// Verify one page task takes a deterministic bounded batch and marks it queued.
@(test)
view_test_page_task_batches_pending_glyphs :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 3
    entry.requested_generation = 3
    testing.expect(t, font_generation_glyphs_init(
        entry, 300, context.allocator))
    for glyph_id in 0..<300 {
        testing.expect(t, font_generation_request_glyph(entry, u32(glyph_id)))
    }
    testing.expect(t, cache_preparation_arena_init(&cache))
    task: Font_Prepare_Task
    testing.expect(t, cache_prepare_page_task(&cache, .Regular, &task))
    testing.expect_value(
        t, task.glyph_id_count, i32(FONT_GLYPH_PAGE_REQUEST_CAPACITY))
    testing.expect_value(
        t, task.demanded_glyph_count, i32(FONT_GLYPH_PAGE_REQUEST_CAPACITY))
    testing.expect_value(t, task.glyph_ids[0], u32(0))
    testing.expect_value(t, task.glyph_ids[255], u32(255))
    testing.expect_value(t, entry.glyphs[255].state, Font_Glyph_State.Queued)
    testing.expect_value(t, entry.glyphs[256].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.queued_demand_count, i32(256))

    cache.preparation.task = task
    cache_fail_preparation(&cache)
    testing.expect_value(t, entry.glyphs[0].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.queued_demand_count, i32(0))
    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    font_generation_glyphs_destroy(entry)
}

// Verify one sparse demand fills the remaining page with deterministic glyph IDs.
@(test)
view_test_page_task_fills_sparse_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 3
    entry.requested_generation = 3
    testing.expect(t, font_generation_glyphs_init(
        entry, 300, context.allocator))
    testing.expect(t, font_generation_request_glyph(entry, 17))
    testing.expect(t, cache_preparation_arena_init(&cache))
    task: Font_Prepare_Task
    testing.expect(t, cache_prepare_page_task(&cache, .Regular, &task))
    testing.expect_value(t, task.demanded_glyph_count, i32(1))
    testing.expect_value(t, task.glyph_id_count, i32(256))
    testing.expect_value(t, task.glyph_ids[0], u32(17))
    testing.expect_value(t, task.glyph_ids[1], u32(0))
    testing.expect_value(t, task.glyph_ids[18], u32(18))

    cache.preparation.task = task
    cache_restore_page_demand(&cache)
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.glyphs[0].state, Font_Glyph_State.Missing)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    font_generation_glyphs_destroy(entry)
}

// Verify a full page table rejects demand without leaving unschedulable work.
@(test)
view_test_page_capacity_blocks_scheduling :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY
    testing.expect(t, font_generation_glyphs_init(
        entry, 2, context.allocator))
    testing.expect(t, !font_generation_request_glyph(entry, 1))
    testing.expect_value(
        t, entry.glyphs[1].state, Font_Glyph_State.Capacity_Blocked)
    testing.expect_value(t, entry.pending_glyph_count, i32(0))
    _, found := cache_next_page_key(&cache)
    testing.expect(t, !found)
    font_generation_glyphs_destroy(entry)
}

// Verify a queued final page reserves capacity against newly arriving demand.
@(test)
view_test_final_queued_page_blocks_new_demand :: proc(t: ^testing.T) {
    entry: Font_Cache_Entry
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY - 1
    entry.pending_glyph_count = 1
    entry.queued_demand_count = 1
    testing.expect(t, font_generation_glyphs_init(
        &entry, 4, context.allocator))
    entry.glyphs[0].state = .Queued

    testing.expect(t, !font_generation_request_glyph(&entry, 1))
    testing.expect_value(
        t, entry.glyphs[1].state, Font_Glyph_State.Capacity_Blocked)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    font_generation_glyphs_destroy(&entry)
}

// Verify superseded page work remains requestable while its old generation survives.
@(test)
view_test_stale_page_restores_old_generation_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.generation = 4
    entry.requested_generation = 5
    testing.expect(t, font_generation_glyphs_init(
        entry, 32, context.allocator))
    testing.expect(t, font_generation_request_glyph(entry, 17))
    entry.glyphs[17].state = .Queued
    cache.preparation.task = {
        kind = .Glyph_Page,
        key = .Regular,
        generation = 4,
        glyph_id_count = 1,
        demanded_glyph_count = 1,
    }
    cache.preparation.task.glyph_ids[0] = 17

    cache_restore_page_demand(&cache)
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    font_generation_glyphs_destroy(entry)
}

// Verify contextual alternates are repeatable and differ from disabled shaping.
@(test)
view_test_harfbuzz_contextual_alternates :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    defer harfbuzz_shaper_destroy(&shaping)

    enabled, repeated, disabled: [8]Shaped_Glyph
    enabled_count, enabled_ok := harfbuzz_shape(
        &shaping, "=>", true, enabled[:])
    repeated_count, repeated_ok := harfbuzz_shape(
        &shaping, "=>", true, repeated[:])
    disabled_count, disabled_ok := harfbuzz_shape(
        &shaping, "=>", false, disabled[:])

    testing.expect(t, enabled_ok && repeated_ok && disabled_ok)
    testing.expect_value(t, enabled_count, repeated_count)
    testing.expect_value(t, enabled_count, disabled_count)
    differs := false
    for index in 0..<enabled_count {
        testing.expect_value(t, enabled[index], repeated[index])
        differs = differs || enabled[index].glyph_id != disabled[index].glyph_id
    }
    testing.expect(t, differs)
}

// Verify the resident HarfBuzz cmap defines Unicode support without a range policy.
@(test)
view_test_harfbuzz_nominal_glyph :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    defer harfbuzz_shaper_destroy(&shaping)

    ascii_glyph, ascii_found := harfbuzz_nominal_glyph(&shaping, 'A')
    math_glyph, math_found := harfbuzz_nominal_glyph(&shaping, '∫')
    _, unsupported_found := harfbuzz_nominal_glyph(&shaping, rune(0x10ffff))
    _, surrogate_found := harfbuzz_nominal_glyph(&shaping, rune(0xd800))
    testing.expect(t, ascii_found && ascii_glyph > 0)
    testing.expect(t, math_found && math_glyph > 0)
    testing.expect(t, !unsupported_found)
    testing.expect(t, !surrogate_found)
}

// Verify direct codepoint resolution reports residency, demand, and hard bounds.
@(test)
view_test_codepoint_resolver_status :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &entry.shaping))
    testing.expect(t, font_generation_glyphs_init(
        entry, 10000, context.allocator))

    ascii_id, _ := harfbuzz_nominal_glyph(&entry.shaping, 'A')
    entry.glyphs[ascii_id].state = .Resident
    _, ascii_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, 'A')
    _, math_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, '∫')
    pending_count := entry.pending_glyph_count
    _, unsupported_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, rune(0x10ffff))
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY
    _, capacity_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, 'α')

    view_expect_codepoint_resolver_result(t, entry, {
        ascii = ascii_status,
        math = math_status,
        unsupported = unsupported_status,
        capacity = capacity_status,
        pending_count = pending_count,
    })

    harfbuzz_shaper_destroy(&entry.shaping)
    font_generation_glyphs_destroy(entry)
}

// Verify native source ownership survives arena release and output remains bounded.
@(test)
view_test_harfbuzz_owns_source_and_bounds_output :: proc(t: ^testing.T) {
    arena: vmem.Arena
    arena_error := vmem.arena_init_static(
        &arena, 16*mem.Megabyte, mem.Megabyte)
    testing.expect(t, arena_error == nil)
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", vmem.arena_allocator(&arena))
    testing.expect(t, read_error == nil)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    vmem.arena_destroy(&arena)

    output: [8]Shaped_Glyph
    glyph_count, shaped := harfbuzz_shape(
        &shaping, "=>", true, output[:])
    testing.expect(t, shaped)
    testing.expect(t, glyph_count > 0)

    bounded: [1]Shaped_Glyph
    _, bounded_ok := harfbuzz_shape(
        &shaping, "abcdef", true, bounded[:])
    testing.expect(t, !bounded_ok)

    harfbuzz_shaper_destroy(&shaping)
    harfbuzz_shaper_destroy(&shaping)
    testing.expect(t, shaping.font == nil)
    testing.expect(t, shaping.buffer == nil)
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
