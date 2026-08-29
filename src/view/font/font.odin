package font

import "../../core"
import "../../files"

import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:path/filepath"

import rl "vendor:raylib"

// Maximum runes in the flattened JuliaMono loading policy.
FONT_CODEPOINT_CAPACITY :: 8192

// Number of indexed font variants through the final `Font_Key` value.
FONT_KEY_COUNT :: core.FONT_KEY_COUNT

// Pixel height used for synchronous and asynchronously prepared JuliaMono fonts.
JULIA_MONO_FONT_SIZE :: 32

// Virtual address-space reservation shared by serialized font preparations.
FONT_PREPARATION_ARENA_RESERVE_SIZE :: 96 * mem.Megabyte

// Physical pages committed eagerly when the preparation arena is created.
FONT_PREPARATION_ARENA_INITIAL_COMMIT_SIZE :: 1 * mem.Megabyte

// JuliaMono asset filename indexed exactly by `Font_Key`.
FONT_FILENAMES :: [FONT_KEY_COUNT]string{
    "JuliaMono-Regular.ttf",
    "JuliaMono-RegularItalic.ttf",
    "JuliaMono-Light.ttf",
    "JuliaMono-LightItalic.ttf",
    "JuliaMono-Medium.ttf",
    "JuliaMono-MediumItalic.ttf",
    "JuliaMono-SemiBold.ttf",
    "JuliaMono-SemiBoldItalic.ttf",
    "JuliaMono-Bold.ttf",
    "JuliaMono-BoldItalic.ttf",
    "JuliaMono-ExtraBold.ttf",
    "JuliaMono-ExtraBoldItalic.ttf",
    "JuliaMono-Black.ttf",
    "JuliaMono-BlackItalic.ttf",
}

Font_Key :: core.Font_Key
Font_Load_State :: core.Font_Load_State
Font_Cache_Entry :: core.Font_Cache_Entry
Font_Cache :: core.Font_Cache
Font_Shaping_Telemetry :: core.Font_Shaping_Telemetry

// Inclusive Unicode interval included in the JuliaMono loading policy.
Font_Codepoint_Range :: struct {
    first: rune,
    last: rune,
}

// Fixed flat rune set passed to raylib/stb font loading APIs.
Font_Codepoint_Set :: struct {
    values: [FONT_CODEPOINT_CAPACITY]rune,
    count: i32,
}

// Broad language/math coverage excluding terminal-only box/block glyphs and large
// unassigned holes; intervals are inclusive and flattened by `codepoint_set`.
FONT_CODEPOINT_RANGES :: [?]Font_Codepoint_Range {
    {0x0020, 0x007e},
    {0x00a0, 0x00ac},
    {0x00ae, 0x0377},
    {0x037a, 0x052f},
    {0x0531, 0x058f},
    {0x0591, 0x05f4},
    {0x0600, 0x06ff},
    {0x10a0, 0x10ff},
    {0x1ab0, 0x1aff},
    {0x1c80, 0x1cbf},
    {0x1d00, 0x1fff},
    {0x2000, 0x24ff},
    {0x2500, 0x2500},
    {0x25a0, 0x2bff},
    {0x2c60, 0x2c7f},
    {0x2d00, 0x2d2d},
    {0xa640, 0xa69f},
    {0xa708, 0xa7ff},
    {0xab30, 0xab6f},
    {0xfe20, 0xfe2f},
    {0xfffd, 0xfffd},
    {0x1d400, 0x1d7ff},
    {0x1ee00, 0x1ee0b},
}


// Resolve one cache-owned font handle for the requested semantic variant.
Font_Resolve_Handler :: proc(user_data: rawptr, key: Font_Key) -> rl.Font

// Shape one borrowed UTF-8 run into caller-owned bounded glyph storage.
Font_Shape_Handler :: proc(
    user_data: rawptr, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool)

Shape_Fallback_Reason :: enum {
    Workspace_Overflow,
    Invalid_Result,
    Invalid_Cluster,
}

// Record one bounded shaped-presentation fallback without retaining source text.
Font_Shape_Fallback_Handler :: proc(
    user_data: rawptr, reason: Shape_Fallback_Reason)

// Borrowing capability drawing to resolve semantic font keys.
Font_Resolver :: struct {
    user_data: rawptr,
    resolve: Font_Resolve_Handler,
    shape: Font_Shape_Handler,
    record_shape_fallback: Font_Shape_Fallback_Handler,
    workspace: []Shaped_Glyph,
}

//   Resolve one font source from packaged assets or the source-tree fallback.
font_asset_path :: proc(filename: string) -> string {
    path := files.packaged_asset_path(filename, context.temp_allocator)
    if len(path) > 0 {
        return path
    }
    fallback, path_error := filepath.join(
        []string{"assets", filename}, context.temp_allocator)
    if path_error != nil || !os.exists(fallback) {
        return ""
    }
    return fallback
}

//   Resolve and retain every configured source path for this cache lifetime.
cache_source_paths_init :: proc(cache: ^Font_Cache) {
    filenames := FONT_FILENAMES
    for key_index in 0..<FONT_KEY_COUNT {
        path := font_asset_path(filenames[key_index])
        destination := &cache.source_paths[key_index]
        if len(path) == 0 || len(path) > len(destination.storage) {
            continue
        }
        copy(destination.storage[:], transmute([]u8)path)
        destination.length = len(path)
    }
}

//   Borrow one cache-owned source path, resolving it lazily for zero-valued tests.
cache_source_path :: proc(cache: ^Font_Cache, key: Font_Key) -> string {
    source := &cache.source_paths[int(key)]
    if source.length == 0 {
        filenames := FONT_FILENAMES
        path := font_asset_path(filenames[int(key)])
        if len(path) == 0 || len(path) > len(source.storage) {
            return ""
        }
        copy(source.storage[:], transmute([]u8)path)
        source.length = len(path)
    }
    return string(source.storage[:source.length])
}

//   Build the immutable JuliaMono codepoint policy in raylib's required flat form.
//
// Returns:
//   - Fixed storage containing every rune from `FONT_CODEPOINT_RANGES` in order.
codepoint_set :: proc() -> Font_Codepoint_Set {
    result: Font_Codepoint_Set
    for codepoint_range in FONT_CODEPOINT_RANGES {
        for codepoint := codepoint_range.first;
            codepoint <= codepoint_range.last;
            codepoint += 1 {

            assert(result.count < FONT_CODEPOINT_CAPACITY)
            result.values[result.count] = codepoint
            result.count += 1
        }
    }
    return result
}

//   Report whether one codepoint belongs to the JuliaMono loading policy.
//
// Returns:
//   - True when the rune falls in any configured inclusive range.
codepoint_is_supported :: proc(codepoint: rune) -> bool {
    for codepoint_range in FONT_CODEPOINT_RANGES {
        if codepoint >= codepoint_range.first && codepoint <= codepoint_range.last {
            return true
        }
    }
    return false
}

//   Suppress raylib's expected oversized-glyph and sparse-range messages during rasterization.
//
// Side effects:
//   - Sets raylib's process-global trace threshold to errors.
rasterization_begin :: proc() {
    rl.SetTraceLogLevel(.ERROR)
}

//   Restore normal raylib diagnostics immediately after font rasterization.
//
// Side effects:
//   - Sets raylib's process-global trace threshold to informational messages.
rasterization_end :: proc() {
    rl.SetTraceLogLevel(.INFO)
}

//   Release one generation's shaping handles and native source copy.
font_shaping_destroy :: proc(resource: ^Font_Shaping_Resource) {
    harfbuzz_shaper_destroy(resource)
}

//   Read transient source through the preparation arena and acquire a native shaper.
font_shaping_create :: proc(
    cache: ^Font_Cache, path: string,
    resource: ^Font_Shaping_Resource) -> bool {

    if cache == nil || resource == nil || len(path) == 0 ||
        !cache_preparation_arena_init(cache) {
        return false
    }
    resource^ = {}
    source, read_error := os.read_entire_file(
        path, vmem.arena_allocator(&cache.preparation_arena))
    if read_error != nil {
        return false
    }
    return harfbuzz_shaper_init(source, JULIA_MONO_FONT_SIZE, resource)
}

//   Prepare and finalize the synchronous Regular complete-face generation.
cache_load_regular :: proc(cache: ^Font_Cache) -> bool {
    if !cache_preparation_arena_init(cache) {
        return false
    }
    defer cache_preparation_arena_reset(cache)
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    codepoints := codepoint_set()
    path := cache_source_path(cache, .Regular)
    prepared: Prepared_Font
    if !prepare({
        key = .Regular,
        path = path,
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
        complete_face = true,
    }, &prepared, allocator, .Arena) {
        return false
    }
    defer prepare_destroy(&prepared)
    shaping: Font_Shaping_Resource
    if !font_shaping_create(cache, path, &shaping) {
        return false
    }
    candidate: rl.Font
    if !finalize(&prepared, &candidate) {
        font_shaping_destroy(&shaping)
        return false
    }
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.font = candidate
    entry.shaping = shaping
    return true
}

//   Load only the permanent Regular fallback during synchronous startup.
//
// Parameters:
//   - cache: Zero-valued display-thread-owned cache.
//
// Side effects:
//   - Loads the Regular GPU font synchronously, marks it resident/ready, and records
//     source-file baselines without generating reload requests.
cache_init :: proc(cache: ^Font_Cache) {
    assert(cache != nil)
    cache^ = {}
    cache_source_paths_init(cache)
    rasterization_begin()
    regular := &cache.entries[int(Font_Key.Regular)]
    regular.resident = cache_load_regular(cache)
    regular.state = regular.resident ? .Ready : .Failed
    rasterization_end()
    assert(regular.resident)
    source_monitor_init(cache, source_monitor_now_ns())
}

//   Unload every resident font owned by the cache.
//
// Parameters:
//   - cache: Cache with no queued preparation; nil is a no-op.
//
// Side effects:
//   - Unloads all resident GPU resources, releases the preparation arena, and resets state.
cache_destroy :: proc(cache: ^Font_Cache) {
    if cache == nil {
        return
    }
    for entry_index in 0..<FONT_KEY_COUNT {
        entry := &cache.entries[entry_index]
        if entry.resident {
            rl.UnloadFont(entry.font)
        }
        font_shaping_destroy(&entry.shaping)
    }
    cache_preparation_arena_destroy(cache)
    cache^ = {}
}

//   Borrow a resident font or Regular without recording new demand.
//
// Returns:
//   - The requested resident GPU handle, otherwise the permanent Regular fallback.
//
// Notes:
//   - The returned handle remains cache-owned and may be invalidated by reload/destroy.
cache_borrow :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
    assert(cache != nil)
    entry := cache.entries[int(key)]
    if entry.resident {
        return entry.font
    }
    return cache.entries[int(Font_Key.Regular)].font
}

//   Record optional demand and borrow its resident font or Regular immediately.
//
// Returns:
//   - The requested resident GPU handle, or Regular while asynchronous work is pending.
//
// Side effects:
//   - Records first demand and increments fallback-resolution telemetry when needed.
cache_resolve :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
    assert(cache != nil)
    entry := &cache.entries[int(key)]
    if entry.resident {
        return entry.font
    }
    cache_request(cache, key)
    entry.fallback_resolution_count += 1
    return cache_borrow(cache, .Regular)
}

//   Adapt cache resolution to the terminal's borrowing capability.
//
// Returns:
//   - The result of `cache_resolve` for the cache borrowed through `user_data`.
cache_terminal_resolve :: proc(user_data: rawptr, key: Font_Key) -> rl.Font {
    return cache_resolve(cast(^Font_Cache)user_data, key)
}

//   Adapt cache shaping to a frame-local resolver capability.
cache_terminal_shape :: proc(
    user_data: rawptr, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool) {

    return cache_shape(cast(^Font_Cache)user_data, key, text, output)
}

//   Record one shaped-presentation rejection in aggregate cache telemetry.
cache_terminal_record_shape_fallback :: proc(
    user_data: rawptr, reason: Shape_Fallback_Reason) {

    cache := cast(^Font_Cache)user_data
    if cache == nil {
        return
    }
    switch reason {
    case .Workspace_Overflow:
        cache.shaping_telemetry.workspace_overflows += 1
    case .Invalid_Result:
        cache.shaping_telemetry.invalid_results += 1
    case .Invalid_Cluster:
        cache.shaping_telemetry.invalid_clusters += 1
    }
}

//   Create a frame-local terminal resolver borrowing from the cache.
//
// Returns:
//   - Callback capability whose `user_data` remains valid only while `cache` does.
cache_terminal_resolver :: proc(cache: ^Font_Cache) -> Font_Resolver {
    return {
        user_data = cache,
        resolve = cache_terminal_resolve,
        shape = cache_terminal_shape,
        record_shape_fallback = cache_terminal_record_shape_fallback,
        workspace = cache.shaped_glyphs[:],
    }
}

//   Convert dynview's weight and italic flags to one indexed cache key.
font_key_from_flags :: proc(flags: core.Font_Variant_Flags) -> Font_Key {
    italic := core.font_has_flag(flags, .Italic)
    switch core.font_resolve_weight_from_flags(flags) {
    case .Light:
        return italic ? .Light_Italic : .Light
    case .Medium:
        return italic ? .Medium_Italic : .Medium
    case .Semibold:
        return italic ? .Semi_Bold_Italic : .Semi_Bold
    case .Bold:
        return italic ? .Bold_Italic : .Bold
    case .Extrabold:
        return italic ? .Extra_Bold_Italic : .Extra_Bold
    case .Black:
        return italic ? .Black_Italic : .Black
    case .Regular:
        return italic ? .Regular_Italic : .Regular
    }
    return .Regular
}

//   Build generation-owned shaping and GPU candidates from one prepared font.
cache_publication_candidates :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    shaping: ^Font_Shaping_Resource, candidate: ^rl.Font) -> bool {

    path := cache_source_path(cache, prepared.key)
    if !font_shaping_create(cache, path, shaping) {
        return false
    }
    if !finalize(prepared, candidate) {
        font_shaping_destroy(shaping)
        return false
    }
    return true
}

//   Finalize and atomically publish a prepared font on the display thread.
//
// Returns:
//   - True after current-generation GPU publication; false for invalid, stale, or
//     finalization failure while preserving any prior resident font.
//
// Side effects:
//   - On success, consumes prepared CPU storage and unloads the previous GPU resource.
cache_publish :: proc(cache: ^Font_Cache, prepared: ^Prepared_Font) -> bool {
    if cache == nil || prepared == nil {
        return false
    }
    entry := &cache.entries[int(prepared.key)]
    generation := prepared.generation
    if generation != entry.requested_generation {
        return false
    }

    candidate: rl.Font
    shaping: Font_Shaping_Resource
    if !cache_publication_candidates(
        cache, prepared, &shaping, &candidate) {
        return false
    }
    previous := entry.font
    previous_shaping := entry.shaping
    previous_resident := entry.resident
    entry^ = {
        font = candidate,
        shaping = shaping,
        generation = generation,
        requested_generation = entry.requested_generation,
        resident = true,
        state = .Ready,
        request_count = entry.request_count,
        coalesced_request_count = entry.coalesced_request_count,
        fallback_resolution_count = entry.fallback_resolution_count,
    }
    if previous_resident {
        rl.UnloadFont(previous)
    }
    font_shaping_destroy(&previous_shaping)
    return true
}

//   Shape one run through a resident variant's generation-owned native state.
cache_shape :: proc(
    cache: ^Font_Cache, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool) {

    if cache == nil {
        return 0, false
    }
    cache.shaping_telemetry.shape_calls += 1
    entry := &cache.entries[int(key)]
    if !entry.resident || entry.shaping.font == nil {
        entry = &cache.entries[int(Font_Key.Regular)]
    }
    if !entry.resident || entry.shaping.font == nil {
        cache.shaping_telemetry.native_failures += 1
        return 0, false
    }
    glyph_count, shaped := harfbuzz_shape(
        &entry.shaping, text, true, output)
    if !shaped {
        cache.shaping_telemetry.native_failures += 1
        return 0, false
    }
    cache.shaping_telemetry.shaped_runs += 1
    cache.shaping_telemetry.shaped_glyphs += u64(glyph_count)
    return glyph_count, true
}

