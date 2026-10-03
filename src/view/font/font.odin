package font

import "../../files"
import geometry "../../core/geometry"
import fontmodel "model"

import "core:mem"
import tlsf "core:mem/tlsf"
import vmem "core:mem/virtual"
import "core:log"
import "core:os"
import "core:path/filepath"

// Maximum runes in either required startup seed policy.
FONT_SEED_CODEPOINT_CAPACITY :: fontmodel.FONT_SEED_CODEPOINT_CAPACITY

// Maximum face glyphs admitted to one prepared atlas page.
FONT_GLYPH_PAGE_REQUEST_CAPACITY :: 256

// Number of indexed font variants through the final `Font_Key` value.
FONT_KEY_COUNT :: fontmodel.FONT_KEY_COUNT

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
    "NewCMSansMath-Regular.otf",
}

Font_Key :: fontmodel.Font_Key
Font_Load_State :: fontmodel.Font_Load_State
Font_Cache_Entry :: fontmodel.Font_Cache_Entry
Font_Cache :: fontmodel.Font_Cache
Font_Shaping_Telemetry :: fontmodel.Font_Shaping_Telemetry
Font_Raster_Request :: fontmodel.Font_Raster_Request
Font_Glyph_State :: fontmodel.Font_Glyph_State
Font_Glyph_Record :: fontmodel.Font_Glyph_Record
Font_Raster_Instance :: fontmodel.Font_Raster_Instance
Font_Glyph_Page :: fontmodel.Font_Glyph_Page
Font_Texture :: fontmodel.Font_Texture
Font_Face :: fontmodel.Font_Face
Font_Texture_Operations :: fontmodel.Font_Texture_Operations
Font_Texture_Upload_Request :: fontmodel.Font_Texture_Upload_Request
Font_Texture_Completion_Handler :: fontmodel.Font_Texture_Completion_Handler
Font_Raster_Budget :: fontmodel.Font_Raster_Budget
Font_Raster_Frame_Pin :: fontmodel.Font_Raster_Frame_Pin

// Borrowed display-thread glyph data normalized across seed and paged textures.
Resolved_Glyph :: struct {
    glyph_id: u32,
    texture: Font_Texture,
    source: geometry.Rectangle,
    offset_x: i32,
    offset_y: i32,
    advance_x: i32,
    canonical_advance_x: i32,
    raster_pixel_height: i32,
    raster_ascent: f32,
    canonical_pixel_height: u32,
    canonical_raster_ascent: f32,
    raster_slot_index: i32,
    raster_slot_incarnation: u64,
}

// Exact raster identity selected for one complete glyph run.
Font_Raster_Selection :: struct {
    slot_index: i32,
    slot_incarnation: u64,
    pixel_height: u32,
}

Font_Glyph_Resolve_Status :: enum {
    Resident,
    Pending,
    Unsupported,
    Capacity_Exhausted,
}


// Inclusive Unicode interval included in the JuliaMono loading policy.
Font_Codepoint_Range :: struct {
    first: rune,
    last: rune,
}

// Fixed flat rune set passed to the seed-loading path.
Font_Seed_Codepoint_Set :: struct {
    values: [FONT_SEED_CODEPOINT_CAPACITY]rune,
    count: i32,
}

// Startup and unshaped fallback coverage retained by every resident face.
FONT_SEED_CODEPOINT_RANGES :: [?]Font_Codepoint_Range {
    {0x0020, 0x007e},
    {0xfffd, 0xfffd},
}

// Required NewCM coverage for ordinary operators and projected math variables.
MATH_SEED_CODEPOINT_RANGES :: [?]Font_Codepoint_Range {
    {0x0020, 0x007e},
    {0x0391, 0x03a1},
    {0x03a3, 0x03a9},
    {0x210e, 0x210e},
    {0x2202, 0x2202},
    {0x220f, 0x2211},
    {0x2212, 0x2212},
    {0x221a, 0x221a},
    {0x221e, 0x221e},
    {0x222b, 0x222b},
    {0x2248, 0x2248},
    {0x2260, 0x2260},
    {0x2264, 0x2265},
    {0x2102, 0x2134},
    {0x1d400, 0x1d433},
    {0x1d434, 0x1d467},
    {0x1d49c, 0x1d4b5},
    {0x1d538, 0x1d56b},
    {0x1d6fc, 0x1d71b},
    {0x1d7ce, 0x1d7e1},
}

// Resolve one cache-owned font handle for the requested semantic variant.
Font_Resolve_Handler :: proc(user_data: rawptr, key: Font_Key) -> Font_Face

// Resolve one shaped face glyph to immutable display-owned page data.
Font_Resolve_Glyph_Handler :: proc(
    user_data: rawptr, key: Font_Key,
    glyph_id: u32,
    request: fontmodel.Font_Raster_Request) -> (Resolved_Glyph, bool)

// Select one resident raster containing every glyph in a shaped run.
Font_Select_Glyph_Raster_Handler :: proc(
    user_data: rawptr, key: Font_Key, glyph_ids: []u32,
    request: fontmodel.Font_Raster_Request) -> (Font_Raster_Selection, bool)

// Resolve one glyph only from the exact raster selected for its complete run.
Font_Resolve_Selected_Glyph_Handler :: proc(
    user_data: rawptr, key: Font_Key, glyph_id: u32,
    request: fontmodel.Font_Raster_Request,
    selection: Font_Raster_Selection) -> (Resolved_Glyph, bool)

// Resolve one Unicode scalar through the effective face cmap and glyph pages.
Font_Resolve_Codepoint_Handler :: proc(
    user_data: rawptr, key: Font_Key,
    codepoint: rune,
    request: fontmodel.Font_Raster_Request) ->
    (Resolved_Glyph, Font_Glyph_Resolve_Status)

// Build a generation-exact raster request from logical size and scene scale.
Font_Raster_Request_Handler :: proc(
    user_data: rawptr, key: Font_Key,
    logical_size, scene_pixels_per_logical_unit: f32) ->
    (fontmodel.Font_Raster_Request, bool)

// Shape one borrowed UTF-8 run into caller-owned bounded glyph storage.
Font_Shape_Handler :: proc(
    user_data: rawptr, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool)

Shape_Fallback_Reason :: enum {
    Workspace_Overflow,
    Invalid_Result,
    Invalid_Cluster,
    Pending_Glyph,
}

// Record one bounded shaped-presentation fallback without retaining source text.
Font_Shape_Fallback_Handler :: proc(
    user_data: rawptr, reason: Shape_Fallback_Reason)

// Borrowing capability drawing to resolve semantic font keys.
Font_Resolver :: struct {
    user_data: rawptr,
    resolve: Font_Resolve_Handler,
    request_raster: Font_Raster_Request_Handler,
    resolve_glyph: Font_Resolve_Glyph_Handler,
    select_glyph_raster: Font_Select_Glyph_Raster_Handler,
    resolve_selected_glyph: Font_Resolve_Selected_Glyph_Handler,
    resolve_codepoint: Font_Resolve_Codepoint_Handler,
    shape: Font_Shape_Handler,
    record_shape_fallback: Font_Shape_Fallback_Handler,
    workspace: []Shaped_Glyph,
}

//   Baseline inputs for placing bitmap coverage from a selected raster.
Font_Raster_Bitmap_Placement :: struct {
    line_top: f32,
    logical_size: f32,
    canonical_pixel_height: u32,
    canonical_ascent: f32,
    bitmap_offset_y: i32,
    raster_pixel_height: u32,
    raster_ascent: f32,
}

Font_Raster_Fallback_Candidate :: struct {
    glyph: Resolved_Glyph,
    distance: u32,
    height: u32,
}

// Admit one optional instance slot independently from its atlas storage.
font_raster_budget_reserve_instance :: proc(
    budget: ^Font_Raster_Budget) -> bool {

    if budget == nil || budget.optional_instance_count >=
        u32(fontmodel.FONT_OPTIONAL_RASTER_INSTANCE_CAPACITY) {
        return false
    }
    budget.optional_instance_count += 1
    return true
}

// Release an optional instance slot after candidate rollback or retirement.
font_raster_budget_release_instance :: proc(budget: ^Font_Raster_Budget) -> bool {
    if budget == nil || budget.optional_instance_count == 0 {
        return false
    }
    budget.optional_instance_count -= 1
    return true
}

// Reserve conservative atlas bytes before CPU pixels or a native texture exist.
font_raster_budget_reserve_bytes :: proc(
    budget: ^Font_Raster_Budget, byte_count: u64) -> bool {

    if budget == nil || byte_count == 0 ||
        byte_count > u64(fontmodel.FONT_RASTER_RGBA_BYTE_BUDGET) {
        return false
    }
    charged_bytes := budget.resident_bytes + budget.candidate_bytes +
        budget.pending_retirement_bytes
    if charged_bytes > u64(fontmodel.FONT_RASTER_RGBA_BYTE_BUDGET) - byte_count {
        return false
    }
    budget.candidate_bytes += byte_count
    return true
}

// Commit one candidate's charge after its atlas publication succeeds.
font_raster_budget_publish :: proc(
    budget: ^Font_Raster_Budget, byte_count: u64) -> bool {

    if budget == nil || byte_count == 0 || budget.candidate_bytes < byte_count {
        return false
    }
    budget.candidate_bytes -= byte_count
    budget.resident_bytes += byte_count
    return true
}

// Shrink a conservative candidate charge to its measured atlas allocation.
font_raster_budget_shrink_candidate :: proc(
    budget: ^Font_Raster_Budget, reserved_bytes, actual_bytes: u64) -> bool {

    if budget == nil || actual_bytes == 0 || actual_bytes > reserved_bytes ||
        budget.candidate_bytes < reserved_bytes {
        return false
    }
    budget.candidate_bytes -= reserved_bytes - actual_bytes
    return true
}

// Keep retired bytes charged until the display owner releases their textures.
font_raster_budget_begin_retirement :: proc(
    budget: ^Font_Raster_Budget, byte_count: u64) -> bool {

    if budget == nil || byte_count == 0 || budget.resident_bytes < byte_count {
        return false
    }
    budget.resident_bytes -= byte_count
    budget.pending_retirement_bytes += byte_count
    return true
}

// Release one completed candidate or retirement charge and its optional slot.
font_raster_budget_release_bytes :: proc(
    budget: ^Font_Raster_Budget, byte_count: u64, retiring: bool) -> bool {

    if budget == nil || byte_count == 0 {
        return false
    }
    charged := &budget.candidate_bytes if !retiring else
        &budget.pending_retirement_bytes
    if charged^ < byte_count {
        return false
    }
    charged^ -= byte_count
    return true
}

// Allocate one exact face-indexed glyph table for a raster instance.
font_raster_instance_glyphs_init :: proc(
    raster: ^Font_Raster_Instance, glyph_count: int,
    allocator: mem.Allocator) -> (u64, bool) {

    if raster == nil || glyph_count <= 0 ||
        glyph_count > fontmodel.FONT_RASTER_GLYPH_RECORD_CAPACITY ||
        raster.glyphs != nil {
        return 0, false
    }
    metadata_bytes := u64(glyph_count) * u64(size_of(Font_Glyph_Record))
    glyphs, allocation_error := make([]Font_Glyph_Record, glyph_count, allocator)
    if allocation_error != nil {
        return 0, false
    }
    raster.glyphs = glyphs
    raster.glyph_allocator = allocator
    return metadata_bytes, true
}

// Reserve one reusable cache-owned allocator for optional raster glyph records.
cache_raster_metadata_allocator_init :: proc(cache: ^Font_Cache) -> bool {

    if cache == nil {
        return false
    }
    if cache.raster_metadata_allocator_initialized {
        return true
    }
    capacity := uint(fontmodel.FONT_OPTIONAL_GLYPH_METADATA_BYTE_BUDGET +
        fontmodel.FONT_OPTIONAL_GLYPH_METADATA_POOL_OVERHEAD)
    backing, allocation_error := vmem.reserve_and_commit(capacity)
    if allocation_error != nil {
        return false
    }
    if tlsf.init_from_buffer(&cache.raster_metadata_allocator, backing) != .None {
        vmem.release(raw_data(backing), uint(len(backing)))
        return false
    }
    cache.raster_metadata_backing = backing
    cache.raster_metadata_allocator_initialized = true
    return true
}

// Destroy reusable metadata storage after every optional raster has been released.
cache_raster_metadata_allocator_destroy :: proc(cache: ^Font_Cache) {

    if cache == nil || !cache.raster_metadata_allocator_initialized {
        return
    }
    assert(cache.raster_budget.optional_glyph_metadata_bytes == 0)
    tlsf.destroy(&cache.raster_metadata_allocator)
    vmem.release(
        raw_data(cache.raster_metadata_backing),
        uint(len(cache.raster_metadata_backing)))
    cache.raster_metadata_backing = nil
    cache.raster_metadata_allocator_initialized = false
}

// Destroy one optional raster and release all owned atlas textures and records.
cache_optional_raster_destroy :: proc(
    cache: ^Font_Cache, raster: ^Font_Raster_Instance) -> bool {

    if cache == nil || raster == nil || raster.state == .Vacant {
        return false
    }
    if raster.frame_pin_count > 0 || cache_preparation_owns_raster(cache, raster) {
        return false
    }
    if raster.charged_rgba_bytes > 0 &&
        !font_raster_budget_begin_retirement(
            &cache.raster_budget, raster.charged_rgba_bytes) {
        return false
    }
    raster.state = .Retiring
    for page_index in 0..<int(raster.page_count) {
        texture := raster.pages[page_index].texture
        if texture.handle != nil && cache.texture_operations.release != nil {
            cache.texture_operations.release(
                cache.texture_operations.user_data, texture)
        }
    }
    metadata_bytes := u64(len(raster.glyphs)) * u64(size_of(Font_Glyph_Record))
    if raster.charged_rgba_bytes > 0 {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, raster.charged_rgba_bytes, true)
    }
    if raster.glyphs != nil {
        delete(raster.glyphs, raster.glyph_allocator)
    }
    _ = font_raster_budget_release_instance(&cache.raster_budget)
    cache.raster_budget.optional_glyph_metadata_bytes -= metadata_bytes
    raster^ = {}
    return true
}

// Release the least-recently-used optional instance that has no live frame or task use.
cache_optional_raster_retire_lru :: proc(
    cache: ^Font_Cache, excluded_slot_index := i32(-1)) -> bool {

    if cache == nil {
        return false
    }
    candidate_index := i32(-1)
    candidate_tick := max(u64)
    for raster, raster_index in cache.optional_rasters {
        if i32(raster_index) == excluded_slot_index ||
            raster.state != .Resident || raster.frame_pin_count > 0 ||
            raster.pending_glyph_count > 0 || raster.queued_demand_count > 0 ||
            cache_preparation_owns_raster(
                cache, &cache.optional_rasters[raster_index]) {
            continue
        }
        if raster.last_used_tick < candidate_tick {
            candidate_index = i32(raster_index)
            candidate_tick = raster.last_used_tick
        }
    }
    if candidate_index < 0 {
        return false
    }
    return cache_optional_raster_destroy(
        cache, &cache.optional_rasters[candidate_index])
}

// Reserve candidate bytes, retiring unused optional instances until the bound fits.
cache_raster_budget_reserve_with_retirement :: proc(
    cache: ^Font_Cache, byte_count: u64,
    excluded_slot_index := i32(-1)) -> bool {

    if cache == nil || byte_count == 0 ||
        byte_count > u64(fontmodel.FONT_RASTER_RGBA_BYTE_BUDGET) {
        return false
    }
    for {
        if font_raster_budget_reserve_bytes(&cache.raster_budget, byte_count) {
            return true
        }
        if !cache_optional_raster_retire_lru(cache, excluded_slot_index) {
            return false
        }
    }
}

// Report whether the serialized task still owns one exact optional slot.
cache_preparation_owns_raster :: proc(
    cache: ^Font_Cache, raster: ^Font_Raster_Instance) -> bool {

    if cache == nil || raster == nil || cache.preparation.state == .Idle ||
        cache.preparation.task.kind != .Glyph_Page {
        return false
    }
    task := &cache.preparation.task
    return task.raster_slot_index >= 0 &&
        task.raster_slot_index < len(cache.optional_rasters) &&
        &cache.optional_rasters[task.raster_slot_index] == raster &&
        task.raster_slot_incarnation == raster.identity.slot_incarnation
}

// Pin one resolved optional raster until all commands in this frame are submitted.
cache_frame_pin_glyph :: proc(
    cache: ^Font_Cache, resolved: Resolved_Glyph) -> bool {

    if cache == nil || resolved.raster_slot_index < 0 {
        return true
    }
    slot_index := resolved.raster_slot_index
    if slot_index >= len(cache.optional_rasters) {
        return false
    }
    raster := &cache.optional_rasters[slot_index]
    if raster.state != .Resident ||
        raster.identity.slot_incarnation != resolved.raster_slot_incarnation {
        return false
    }
    raster.last_used_tick = cache.raster_request_clock
    if !cache.frame_active {
        return true
    }
    for pin in cache.frame_pins[:cache.frame_pin_count] {
        if pin.slot_index == slot_index &&
            pin.slot_incarnation == resolved.raster_slot_incarnation {
            return true
        }
    }
    if cache.frame_pin_count >= len(cache.frame_pins) {
        return false
    }
    cache.frame_pins[cache.frame_pin_count] = {
        slot_index = slot_index,
        slot_incarnation = resolved.raster_slot_incarnation,
    }
    cache.frame_pin_count += 1
    raster.frame_pin_count += 1
    return true
}

// Begin one display frame's bounded optional-raster pin collection.
cache_frame_begin :: proc(cache: ^Font_Cache) {
    if cache == nil {
        return
    }
    assert(!cache.frame_active && cache.frame_pin_count == 0)
    cache.frame_active = true
}

// Release every optional-raster pin after frame encoding and submission return.
cache_frame_end :: proc(cache: ^Font_Cache) {
    if cache == nil || !cache.frame_active {
        return
    }
    for pin in cache.frame_pins[:cache.frame_pin_count] {
        if pin.slot_index < 0 || pin.slot_index >= len(cache.optional_rasters) {
            continue
        }
        raster := &cache.optional_rasters[pin.slot_index]
        if raster.identity.slot_incarnation == pin.slot_incarnation {
            assert(raster.frame_pin_count > 0)
            raster.frame_pin_count -= 1
        }
    }
    cache.frame_pins = {}
    cache.frame_pin_count = 0
    cache.frame_active = false
}

// Reclaim every optional instance invalidated by one source-generation commit.
cache_destroy_stale_optional_rasters :: proc(
    cache: ^Font_Cache, key: Font_Key, generation: u64) {

    if cache == nil {
        return
    }
    for raster, index in &cache.optional_rasters {
        task_owns_slot := cache.preparation.task.kind == .Glyph_Page &&
            cache.preparation.task.raster_slot_index == i32(index) &&
            cache.preparation.task.raster_slot_incarnation ==
                raster.identity.slot_incarnation &&
            cache.preparation.state != .Idle
        if raster.identity.key == key &&
            raster.identity.source_generation != generation && !task_owns_slot {
            cache_optional_raster_destroy(cache, &cache.optional_rasters[index])
        }
    }
}

// Find or admit one exact optional height for an already resident face.
cache_optional_raster_admit :: proc(
    cache: ^Font_Cache, request: fontmodel.Font_Raster_Request) -> (i32, bool) {

    if cache == nil || !cache_raster_request_is_current(cache, request) ||
        request.pixel_height == JULIA_MONO_FONT_SIZE {
        return -1, false
    }
    existing := cache_find_optional_raster(cache, request)
    if existing >= 0 {
        cache.raster_request_clock += 1
        cache.optional_rasters[existing].last_used_tick =
            cache.raster_request_clock
        return existing, true
    }
    glyph_count := len(cache.entries[int(request.key)].canonical_raster.glyphs)
    slot_index := cache_optional_raster_reserve_slot(cache, glyph_count)
    if slot_index < 0 {
        return -1, false
    }
    if !cache_optional_raster_initialize(
        cache, request, slot_index, glyph_count) {
        cache.raster_budget.optional_glyph_metadata_bytes -=
            u64(glyph_count) * u64(size_of(Font_Glyph_Record))
        _ = font_raster_budget_release_instance(&cache.raster_budget)
        return -1, false
    }
    return slot_index, true
}

// Find an already admitted exact raster identity.
cache_find_optional_raster :: proc(
    cache: ^Font_Cache, request: fontmodel.Font_Raster_Request) -> i32 {

    for raster, index in cache.optional_rasters {
        if raster.state != .Vacant && raster.identity.key == request.key &&
            raster.identity.source_generation == request.source_generation &&
            raster.identity.pixel_height == request.pixel_height &&
            raster.identity.policy == request.policy {
            return i32(index)
        }
    }
    return -1
}

// Find one vacant slot, retiring its least-recently-used resident when necessary.
cache_optional_raster_vacant_slot :: proc(cache: ^Font_Cache) -> i32 {
    if cache == nil {
        return -1
    }
    slot_index := -1
    for raster, index in cache.optional_rasters {
        if raster.state == .Vacant {
            slot_index = index
            break
        }
    }
    if slot_index < 0 && cache_optional_raster_retire_lru(cache) {
        for raster, index in cache.optional_rasters {
            if raster.state == .Vacant {
                return i32(index)
            }
        }
    }
    return i32(slot_index)
}

// Reserve bounded dense glyph metadata, retiring unused instances as needed.
cache_optional_raster_reserve_metadata :: proc(
    cache: ^Font_Cache, byte_count: u64) -> bool {

    budget := u64(fontmodel.FONT_OPTIONAL_GLYPH_METADATA_BYTE_BUDGET)
    if cache == nil || byte_count > budget {
        return false
    }
    for cache.raster_budget.optional_glyph_metadata_bytes > budget - byte_count {
        if !cache_optional_raster_retire_lru(cache) {
            return false
        }
    }
    cache.raster_budget.optional_glyph_metadata_bytes += byte_count
    return true
}

// Reserve one optional slot and charge its dense face-indexed glyph metadata.
cache_optional_raster_reserve_slot :: proc(
    cache: ^Font_Cache, glyph_count: int) -> i32 {

    if cache == nil || glyph_count <= 0 ||
        glyph_count > fontmodel.FONT_RASTER_GLYPH_RECORD_CAPACITY {
        return -1
    }
    slot_index := cache_optional_raster_vacant_slot(cache)
    if slot_index < 0 {
        return -1
    }
    if !font_raster_budget_reserve_instance(&cache.raster_budget) {
        if !cache_optional_raster_retire_lru(cache) ||
            !font_raster_budget_reserve_instance(&cache.raster_budget) {
            return -1
        }
    }
    metadata_bytes := u64(glyph_count) * u64(size_of(Font_Glyph_Record))
    if !cache_optional_raster_reserve_metadata(cache, metadata_bytes) {
        _ = font_raster_budget_release_instance(&cache.raster_budget)
        return -1
    }
    return i32(slot_index)
}

// Initialize one reserved slot with the request identity and bounded glyph table.
cache_optional_raster_initialize :: proc(
    cache: ^Font_Cache, request: fontmodel.Font_Raster_Request,
    slot_index: i32, glyph_count: int) -> bool {

    cache.next_raster_slot_incarnation += 1
    if cache.next_raster_slot_incarnation == 0 {
        cache.next_raster_slot_incarnation = 1
    }
    raster := &cache.optional_rasters[slot_index]
    raster^ = {
        identity = {
            key = request.key,
            source_generation = request.source_generation,
            pixel_height = request.pixel_height,
            policy = request.policy,
            slot_incarnation = cache.next_raster_slot_incarnation,
        },
        state = .Reserved,
    }
    if !cache_raster_metadata_allocator_init(cache) {
        raster^ = {}
        return false
    }
    _, initialized := font_raster_instance_glyphs_init(
        raster, glyph_count, tlsf.allocator(&cache.raster_metadata_allocator))
    if !initialized {
        raster^ = {}
        return false
    }
    raster.state = .Preparing
    cache.raster_request_clock += 1
    raster.last_used_tick = cache.raster_request_clock
    return true
}

// Request optional glyph coverage, falling back to canonical demand on pressure.
cache_request_raster_glyph :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    request: fontmodel.Font_Raster_Request, glyph_id: u32) -> bool {

    slot_index, admitted := cache_optional_raster_admit(cache, request)
    raster := &entry.canonical_raster
    if admitted {
        raster = &cache.optional_rasters[int(slot_index)]
        if raster.first_pending_demand_tick == 0 {
            raster.first_pending_demand_tick = cache.raster_request_clock
        }
    }
    if raster != &entry.canonical_raster &&
        glyph_id < u32(len(entry.canonical_raster.glyphs)) &&
        entry.canonical_raster.glyphs[glyph_id].state == .Missing {
        _ = font_raster_request_glyph(
            entry, &entry.canonical_raster, glyph_id)
    }
    requested := font_raster_request_glyph(entry, raster, glyph_id)
    if !requested && raster != &entry.canonical_raster {
        return font_raster_request_glyph(
            entry, &entry.canonical_raster, glyph_id)
    }
    return requested
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

//   Build the compatibility seed in the rasterizer's required flat form.
//
// Returns:
//   - Fixed storage containing every rune from `FONT_SEED_CODEPOINT_RANGES`.
seed_codepoint_set_from_ranges :: proc(
    ranges: []Font_Codepoint_Range) -> Font_Seed_Codepoint_Set {

    result: Font_Seed_Codepoint_Set
    for codepoint_range in ranges {
        for codepoint := codepoint_range.first;
            codepoint <= codepoint_range.last;
            codepoint += 1 {

            assert(result.count < FONT_SEED_CODEPOINT_CAPACITY)
            result.values[result.count] = codepoint
            result.count += 1
        }
    }
    return result
}

//   Build the JuliaMono compatibility seed in the rasterizer's required flat form.
seed_codepoint_set :: proc() -> Font_Seed_Codepoint_Set {
    ranges := FONT_SEED_CODEPOINT_RANGES
    return seed_codepoint_set_from_ranges(ranges[:])
}

//   Build the required NewCM math seed in the rasterizer's required flat form.
math_seed_codepoint_set :: proc() -> Font_Seed_Codepoint_Set {
    ranges := MATH_SEED_CODEPOINT_RANGES
    return seed_codepoint_set_from_ranges(ranges[:])
}

//   Release one generation's shaping handles and native source copy.
font_shaping_destroy :: proc(resource: ^Font_Shaping_Resource) {
    harfbuzz_shaper_destroy(resource)
}

//   Allocate one directly indexed glyph-state table for a candidate generation.
//
// Returns:
//   - True after exact-size metadata allocation; false without changing the entry.
font_generation_glyphs_init :: proc(
    entry: ^Font_Cache_Entry, glyph_count: int,
    allocator: mem.Allocator) -> bool {

    if entry == nil || glyph_count <= 0 ||
        entry.canonical_raster.glyphs != nil {
        return false
    }
    glyphs, allocation_error := make(
        []Font_Glyph_Record, glyph_count, allocator)
    if allocation_error != nil {
        return false
    }
    entry.canonical_raster.glyphs = glyphs
    entry.canonical_raster.glyph_allocator = allocator
    return true
}

//   Release generation metadata after every page texture has been retired.
font_generation_glyphs_destroy :: proc(entry: ^Font_Cache_Entry) {
    if entry == nil {
        return
    }
    raster := &entry.canonical_raster
    if raster.glyphs != nil {
        delete(raster.glyphs, raster.glyph_allocator)
    }
    raster.glyphs = nil
    raster.glyph_allocator = {}
    raster.page_count = 0
    raster.pending_glyph_count = 0
    raster.queued_demand_count = 0
}

// Calculate bounded page capacity for one independent raster instance.
font_raster_required_page_count :: proc(
    raster: ^Font_Raster_Instance, additional_demand: i32) -> i32 {

    if raster == nil {
        return max(i32)
    }
    queued_page_count := i32(0)
    if raster.queued_demand_count > 0 {
        queued_page_count = 1
    }
    unqueued_count := raster.pending_glyph_count - raster.queued_demand_count +
        additional_demand
    unqueued_page_count := (unqueued_count + FONT_GLYPH_PAGE_REQUEST_CAPACITY - 1)/
        FONT_GLYPH_PAGE_REQUEST_CAPACITY
    return raster.page_count + queued_page_count + unqueued_page_count
}

//   Mark one unresolved glyph ID as pending without duplicate queue storage.
//
// Returns:
//   - True only when this call creates new bounded demand.
font_generation_request_glyph :: proc(
    entry: ^Font_Cache_Entry, glyph_id: u32) -> bool {

    return font_raster_request_glyph(entry, &entry.canonical_raster, glyph_id)
}

// Mark one unresolved glyph in a selected raster without duplicate demand.
font_raster_request_glyph :: proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    glyph_id: u32) -> bool {

    if entry == nil || raster == nil || glyph_id >= u32(len(raster.glyphs)) {
        return false
    }
    glyph := &raster.glyphs[glyph_id]
    if glyph.state != .Missing {
        return false
    }
    if font_raster_required_page_count(raster, 1) >
        fontmodel.FONT_GLYPH_PAGE_CAPACITY {
        if raster != &entry.canonical_raster {
            entry.capacity_rejection_count += 1
            return false
        }
        glyph.state = .Capacity_Blocked
        entry.capacity_rejection_count += 1
        return false
    }
    glyph.state = .Pending
    raster.pending_glyph_count += 1
    return true
}

//   Copy one prepared seed's metrics into exact-size generation storage.
//
// Returns:
//   - True when every prepared glyph maps uniquely inside the face glyph table.
font_generation_seed_records_init :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font,
    allocator: mem.Allocator) -> bool {

    if entry == nil || prepared == nil || prepared.face_glyph_count <= 0 ||
        !font_generation_glyphs_init(
            entry, int(prepared.face_glyph_count), allocator) {
        return false
    }
    for glyph, index in prepared.glyphs {
        if glyph.glyph_id >= u32(len(entry.canonical_raster.glyphs)) {
            font_generation_glyphs_destroy(entry)
            return false
        }
        rectangle := prepared.rectangles[index]
        entry.canonical_raster.glyphs[glyph.glyph_id] = {
            rectangle = {
                x = f32(rectangle.x),
                y = f32(rectangle.y),
                width = f32(rectangle.width),
                height = f32(rectangle.height),
            },
            offset_x = glyph.offset_x,
            offset_y = glyph.offset_y,
            advance_x = glyph.advance_x,
            state = .Resident,
        }
    }
    return true
}

//   Destroy every display and native resource owned by one font generation.
font_generation_destroy :: proc(
    entry: ^Font_Cache_Entry, operations: Font_Texture_Operations = {}) {
    if entry == nil {
        return
    }
    raster := &entry.canonical_raster
    for page_index in 0..<int(raster.page_count) {
        texture := raster.pages[page_index].texture
        if texture.handle != nil && operations.release != nil {
            operations.release(operations.user_data, texture)
        }
    }
    if raster.texture.handle != nil && operations.release != nil {
        operations.release(operations.user_data, raster.texture)
    }
    font_shaping_destroy(&entry.shaping)
    font_generation_glyphs_destroy(entry)
}

//   Read transient source through the preparation arena and acquire a native shaper.
font_shaping_create :: proc(
    cache: ^Font_Cache, key: Font_Key, path: string,
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
    if !harfbuzz_shaper_init(source, JULIA_MONO_FONT_SIZE, resource) {
        return false
    }
    if key == .Math_Regular && !harfbuzz_face_has_math_table(resource) {
        font_shaping_destroy(resource)
        return false
    }
    return true
}

//   Finalize and publish one synchronous required seed candidate.
cache_publish_required_seed :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    prepared: ^Prepared_Font, shaping: ^Font_Shaping_Resource,
    rgba_bytes: u64) -> bool {

    candidate, finalized := cache_finalize_required_seed(
        cache, entry, prepared, shaping, rgba_bytes)
    if !finalized {
        return false
    }
    raster_ascent := prepared^.raster_ascent
    entry.font = candidate
    entry.canonical_raster = {
        identity = {
            key = prepared^.key,
            source_generation = prepared^.generation,
            pixel_height = u32(prepared^.base_size),
            policy = FONT_FREETYPE_RASTER_POLICY,
            slot_incarnation = fontmodel.FONT_CANONICAL_RASTER_SLOT_INCARNATION,
        },
        state = .Resident,
        raster_ascent = raster_ascent,
        texture = candidate.texture,
        charged_rgba_bytes = rgba_bytes,
        glyphs = entry.canonical_raster.glyphs,
        glyph_allocator = entry.canonical_raster.glyph_allocator,
    }
    entry.shaping = shaping^
    entry.raster_ascent = raster_ascent
    return true
}

// Finalize a required seed and account for its texture before entry publication.
cache_finalize_required_seed :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    prepared: ^Prepared_Font, shaping: ^Font_Shaping_Resource,
    rgba_bytes: u64) -> (Font_Face, bool) {

    if !font_generation_seed_records_init(entry, prepared, context.allocator) {
        font_shaping_destroy(shaping)
        return {}, false
    }
    candidate, finalized := finalize_face(prepared, cache.texture_operations,
        u64(prepared.key) + 1, prepared.generation)
    if !finalized {
        font_shaping_destroy(shaping)
        font_generation_glyphs_destroy(entry)
        return {}, false
    }
    if !font_raster_budget_publish(&cache.raster_budget, rgba_bytes) {
        cache.texture_operations.release(
            cache.texture_operations.user_data, candidate.texture)
        font_shaping_destroy(shaping)
        font_generation_glyphs_destroy(entry)
        return {}, false
    }
    return candidate, true
}

//   Return the bounded startup seed policy for one required font key.
required_seed_codepoints :: proc(key: Font_Key) -> Font_Seed_Codepoint_Set {
    return math_seed_codepoint_set() if key == .Math_Regular else
        seed_codepoint_set()
}

// Prepare one required face seed using the cache's serialized preparation arena.
cache_prepare_required_seed :: proc(
    cache: ^Font_Cache, key: Font_Key, prepared: ^Prepared_Font) -> bool {

    codepoints := required_seed_codepoints(key)
    return prepare({
        key = key,
        generation = 1,
        path = cache_source_path(cache, key),
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
    }, prepared, vmem.arena_allocator(&cache.preparation_arena), .Arena)
}

//   Prepare and finalize one synchronous required font generation.
cache_load_required :: proc(cache: ^Font_Cache, key: Font_Key) -> bool {
    if key != .Regular && key != .Math_Regular {
        return false
    }
    if !cache_preparation_arena_init(cache) {
        return false
    }
    defer cache_preparation_arena_reset(cache)
    reservation_bytes := u64(fontmodel.FONT_RASTER_PAGE_RESERVATION_RGBA_BYTES)
    if !cache_raster_budget_reserve_with_retirement(
        cache, reservation_bytes) {
        return false
    }
    reservation_active := true
    defer if reservation_active {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, reservation_bytes, false)
    }
    prepared: Prepared_Font
    defer prepare_destroy(&prepared)
    shaping: Font_Shaping_Resource
    if !cache_prepare_required_candidate(
        cache, key, &reservation_bytes, &prepared, &shaping) {
        return false
    }
    entry := &cache.entries[int(key)]
    published := cache_publish_required_seed(
        cache, entry, &prepared, &shaping, reservation_bytes)
    reservation_active = !published
    return published
}

// Prepare one bounded seed and its matching shaper under an active reservation.
cache_prepare_required_candidate :: proc(
    cache: ^Font_Cache, key: Font_Key, reservation_bytes: ^u64,
    prepared: ^Prepared_Font, shaping: ^Font_Shaping_Resource) -> bool {

    if !cache_prepare_required_seed(cache, key, prepared) {
        return false
    }
    actual_bytes := u64(prepared.atlas_width) * u64(prepared.atlas_height) * 4
    if !font_raster_budget_shrink_candidate(
        &cache.raster_budget, reservation_bytes^, actual_bytes) {
        return false
    }
    reservation_bytes^ = actual_bytes
    return font_shaping_create(
        cache, key, cache_source_path(cache, key), shaping)
}

//   Load permanent text and math faces at startup.
//
// Parameters:
//   - cache: Zero-valued display-thread-owned cache.
//
// Side effects:
//   - Loads required GPU fonts synchronously and records source-file baselines.
//   - Rolls back all cache ownership if any required generation fails.
cache_init :: proc(
    cache: ^Font_Cache, operations: Font_Texture_Operations) -> bool {
    assert(cache != nil)
    cache^ = {}
    cache.texture_operations = operations
    cache_source_paths_init(cache)
    required_keys := [?]Font_Key{.Regular, .Math_Regular}
    ready := true
    for key in required_keys {
        entry := &cache.entries[int(key)]
        entry.requested_generation = 1
        entry.resident = cache_load_required(cache, key)
        entry.generation = 1 if entry.resident else 0
        entry.state = entry.resident ? .Ready : .Failed
        if entry.resident {
            log.infof("required_font_ready key=%d", int(key))
        } else {
            log.errorf("required_font_failed key=%d", int(key))
        }
        ready = ready && entry.resident
    }
    if !ready {
        cache_destroy(cache)
        return false
    }
    source_monitor_init(cache, source_monitor_now_ns())
    return true
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
    assert(cache.preparation.state == .Idle)
    assert(!cache.frame_active && cache.frame_pin_count == 0)
    for entry_index in 0..<FONT_KEY_COUNT {
        entry := &cache.entries[entry_index]
        font_generation_destroy(entry, cache.texture_operations)
    }
    for _, raster_index in cache.optional_rasters {
        cache_optional_raster_destroy(
            cache, &cache.optional_rasters[raster_index])
    }
    cache_raster_metadata_allocator_destroy(cache)
    cache_preparation_arena_destroy(cache)
    cache^ = {}
}

//   Build and atomically install one resident math-font shaping candidate.
math_shaping_replace :: proc(
    cache: ^Font_Cache,
    entry: ^Font_Cache_Entry,
    capability: ^Font_Math_Shaping_Capability) -> bool {
    path := cache_source_path(cache, .Math_Regular)
    source, read_error := os.read_entire_file(path, context.allocator)
    if read_error != nil {
        capability.failed_generation = entry.generation
        return false
    }
    defer delete(source)
    candidate := Font_Math_Shaping_Capability{
        generation = entry.generation,
        raster_ascent = entry.raster_ascent,
    }
    if !harfbuzz_shaper_init(source, JULIA_MONO_FONT_SIZE, &candidate.resource) ||
        !harfbuzz_face_has_math_table(&candidate.resource) ||
        !harfbuzz_math_constants_capture(&candidate.resource, candidate.generation,
            f32(JULIA_MONO_FONT_SIZE), &candidate.constants,
            harfbuzz_text_match_scale(
                &cache.entries[int(Font_Key.Regular)].shaping,
                &candidate.resource)) {
        math_shaping_destroy(&candidate)
        capability.failed_generation = entry.generation
        return false
    }
    previous := capability^
    capability^ = candidate
    math_shaping_destroy(&previous)
    return true
}

//   Synchronize a separate Dynview math shaper to the resident NewCM generation.
//
// Returns:
//   - True when the existing capability is current or a complete candidate replaces it.
//   - False while no resident math generation exists or candidate construction fails.
//
// Side effects:
//   - Reads source bytes into temporary display-thread storage, atomically replaces
//     `runtime.math_shaping` on success, and preserves the prior capability on failure.
math_shaping_sync :: proc(
    cache: ^Font_Cache,
    capability: ^Font_Math_Shaping_Capability) -> bool {

    if cache == nil || capability == nil {
        return false
    }
    entry := &cache.entries[int(Font_Key.Math_Regular)]
    if !entry.resident || entry.generation == 0 {
        return false
    }
    if math_shaping_generation_matches(capability, entry.generation) {
        return true
    }
    if capability.failed_generation == entry.generation {
        return false
    }
    return math_shaping_replace(cache, entry, capability)
}

//   Borrow a resident font or Regular without recording new demand.
//
// Returns:
//   - The requested resident GPU handle, otherwise the permanent Regular fallback.
//
// Notes:
//   - The returned handle remains cache-owned and may be invalidated by reload/destroy.
cache_borrow :: proc(cache: ^Font_Cache, key: Font_Key) -> Font_Face {
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
cache_resolve :: proc(cache: ^Font_Cache, key: Font_Key) -> Font_Face {
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
cache_terminal_resolve :: proc(user_data: rawptr, key: Font_Key) -> Font_Face {
    return cache_resolve(cast(^Font_Cache)user_data, key)
}

//   Select the same resident generation used by shaping and glyph resolution.
cache_effective_entry :: proc(
    cache: ^Font_Cache, key: Font_Key) -> ^Font_Cache_Entry {

    if cache == nil {
        return nil
    }
    entry := &cache.entries[int(key)]
    if entry.resident {
        return entry
    }
    return &cache.entries[int(Font_Key.Regular)]
}

//   Report whether one exact font generation is resident for cached drawing.
cache_generation_is_resident :: #force_inline proc(
    cache: ^Font_Cache, key: Font_Key, generation: u64) -> bool {

    if cache == nil || generation == 0 {
        return false
    }
    entry := &cache^.entries[int(key)]
    return entry^.resident && entry^.generation == generation
}

//   Return one glyph advance in the canonical raster's metric units.
font_generation_canonical_advance :: #force_inline proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    glyph_id: u32, raster_advance: i32) -> i32 {

    if entry != nil && glyph_id < u32(len(entry.canonical_raster.glyphs)) {
        canonical := entry.canonical_raster.glyphs[glyph_id]
        if canonical.state == .Resident {
            return canonical.advance_x
        }
    }
    if raster == nil || raster.identity.pixel_height == 0 {
        return raster_advance
    }
    scaled := i64(raster_advance) * i64(JULIA_MONO_FONT_SIZE)
    return i32((scaled + i64(raster.identity.pixel_height)/2) /
        i64(raster.identity.pixel_height))
}

//   Normalize one resident glyph record to borrowed draw data.
font_generation_resolve_glyph :: proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    glyph_id: u32, raster_slot_index := i32(-1)) -> (Resolved_Glyph, bool) {

    if entry == nil || raster == nil || glyph_id >= u32(len(raster.glyphs)) ||
        raster.glyphs[glyph_id].state != .Resident {
        return {}, false
    }
    glyph := raster.glyphs[glyph_id]
    texture := raster.texture
    if glyph.page_index > 0 {
        page_index := int(glyph.page_index) - 1
        if page_index >= int(raster.page_count) {
            return {}, false
        }
        texture = raster.pages[page_index].texture
    }
    return {
        texture = texture,
        source = glyph.rectangle,
        offset_x = glyph.offset_x,
        offset_y = glyph.offset_y,
        advance_x = glyph.advance_x,
        glyph_id = glyph_id,
        canonical_advance_x = font_generation_canonical_advance(
            entry, raster, glyph_id, glyph.advance_x),
        raster_pixel_height = i32(raster.identity.pixel_height),
        raster_ascent = raster.raster_ascent,
        canonical_pixel_height = u32(JULIA_MONO_FONT_SIZE),
        canonical_raster_ascent = entry.raster_ascent,
        raster_slot_index = raster_slot_index,
        raster_slot_incarnation = raster.identity.slot_incarnation,
    }, true
}

// Confirm a draw request still names the exact currently resident face generation.
cache_raster_request_is_current :: proc(
    cache: ^Font_Cache, request: fontmodel.Font_Raster_Request) -> bool {
    if cache == nil || request.source_generation == 0 || request.pixel_height == 0 ||
        request.policy != FONT_FREETYPE_RASTER_POLICY {
        return false
    }
    entry := cache_effective_entry(cache, request.key)
    return entry != nil && entry.resident &&
        entry.generation == request.source_generation
}

// Match a request to the effective face selected for a semantic font key.
cache_raster_request_matches_key :: proc(
    cache: ^Font_Cache, key: Font_Key,
    request: fontmodel.Font_Raster_Request) -> bool {
    entry := cache_effective_entry(cache, key)
    effective_key := key
    if cache != nil && entry == &cache.entries[int(Font_Key.Regular)] {
        effective_key = .Regular
    }
    return entry != nil && request.key == effective_key &&
        cache_raster_request_is_current(cache, request)
}

//   Resolve one shaped glyph from the effective resident generation.
//
// Returns:
//   - Borrowed draw data and true when resident; otherwise zero and false.
cache_terminal_resolve_glyph :: proc(
    user_data: rawptr, key: Font_Key,
    glyph_id: u32,
    request: fontmodel.Font_Raster_Request) -> (Resolved_Glyph, bool) {

    cache := cast(^Font_Cache)user_data
    if !cache_raster_request_matches_key(cache, key, request) {
        return {}, false
    }
    entry := cache_effective_entry(cache, key)
    target_index, target_found := cache_optional_raster_admit(cache, request)
    target := &entry.canonical_raster
    if target_found {
        target = &cache.optional_rasters[int(target_index)]
    }
    resolved, resident := font_generation_resolve_glyph(
        entry, target, glyph_id, target_index)
    if resident {
        if !cache_frame_pin_glyph(cache, resolved) {
            return {}, false
        }
        return resolved, true
    }
    _ = cache_request_raster_glyph(cache, entry, request, glyph_id)
    fallback := cache_raster_fallback(cache, entry, request, glyph_id)
    if fallback.texture.handle != nil && !cache_frame_pin_glyph(cache, fallback) {
        return {}, false
    }
    return fallback, fallback.texture.handle != nil
}

// Test whether one resident raster contains every glyph in a run.
cache_raster_contains_glyphs :: proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    glyph_ids: []u32) -> bool {

    if entry == nil || raster == nil || len(glyph_ids) == 0 ||
        raster.state != .Resident {
        return false
    }
    for glyph_id in glyph_ids {
        if glyph_id >= u32(len(raster.glyphs)) ||
            raster.glyphs[glyph_id].state != .Resident {
            return false
        }
    }
    return true
}

// Choose the nearest resident raster that contains the complete glyph run.
cache_raster_select_closest_complete :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry, glyph_ids: []u32,
    request: fontmodel.Font_Raster_Request) -> Font_Raster_Selection {

    selected := Font_Raster_Selection{}
    best_distance := max(u32)
    best_height := u32(0)
    canonical := &entry.canonical_raster
    if cache_raster_contains_glyphs(entry, canonical, glyph_ids) {
        selected = font_raster_selection(canonical, -1)
        best_height = canonical.identity.pixel_height
        best_distance = font_raster_height_distance(
            best_height, request.pixel_height)
    }
    for _, raster_index in cache.optional_rasters {
        raster := &cache.optional_rasters[raster_index]
        if raster.identity.key != request.key ||
            raster.identity.source_generation != request.source_generation ||
            !cache_raster_contains_glyphs(entry, raster, glyph_ids) {
            continue
        }
        height := raster.identity.pixel_height
        distance := font_raster_height_distance(height, request.pixel_height)
        if distance < best_distance ||
            distance == best_distance && height > best_height {
            selected = font_raster_selection(raster, i32(raster_index))
            best_distance = distance
            best_height = height
        }
    }
    return selected
}

// Select and pin the closest complete same-face raster for one glyph run.
cache_terminal_select_glyph_raster :: proc(
    user_data: rawptr, key: Font_Key, glyph_ids: []u32,
    request: fontmodel.Font_Raster_Request) -> (Font_Raster_Selection, bool) {

    cache := cast(^Font_Cache)user_data
    if len(glyph_ids) == 0 ||
        !cache_raster_request_matches_key(cache, key, request) {
        return {}, false
    }
    entry := cache_effective_entry(cache, key)
    target_index, target_found := cache_optional_raster_admit(cache, request)
    target := &entry.canonical_raster
    if target_found {
        target = &cache.optional_rasters[int(target_index)]
    }
    for glyph_id in glyph_ids {
        _ = cache_request_raster_glyph(cache, entry, request, glyph_id)
    }
    selected := Font_Raster_Selection{}
    if cache_raster_contains_glyphs(entry, target, glyph_ids) {
        selected = font_raster_selection(target, target_index)
    } else {
        selected = cache_raster_select_closest_complete(
            cache, entry, glyph_ids, request)
    }
    if selected.pixel_height == 0 {
        return {}, false
    }
    first, resident := cache_terminal_resolve_selected_glyph(
        user_data, key, glyph_ids[0], request, selected)
    return selected, resident && first.texture.handle != nil
}

// Resolve one glyph from a run's exact raster selection.
cache_terminal_resolve_selected_glyph :: proc(
    user_data: rawptr, key: Font_Key, glyph_id: u32,
    request: fontmodel.Font_Raster_Request,
    selection: Font_Raster_Selection) -> (Resolved_Glyph, bool) {

    cache := cast(^Font_Cache)user_data
    if !cache_raster_request_matches_key(cache, key, request) ||
        selection.pixel_height == 0 {
        return {}, false
    }
    entry := cache_effective_entry(cache, key)
    raster := &entry.canonical_raster
    if selection.slot_index >= 0 {
        if selection.slot_index >= len(cache.optional_rasters) {
            return {}, false
        }
        raster = &cache.optional_rasters[selection.slot_index]
    } else if selection.slot_index != -1 {
        return {}, false
    }
    if raster.state != .Resident || raster.identity.key != request.key ||
        raster.identity.slot_incarnation != selection.slot_incarnation ||
        raster.identity.pixel_height != selection.pixel_height ||
        raster.identity.source_generation != request.source_generation {
        return {}, false
    }
    resolved, resident := font_generation_resolve_glyph(
        entry, raster, glyph_id, selection.slot_index)
    if !resident || !cache_frame_pin_glyph(cache, resolved) {
        return {}, false
    }
    return resolved, true
}

// Build the exact selection descriptor for one resident raster.
font_raster_selection :: #force_inline proc(
    raster: ^Font_Raster_Instance, slot_index: i32) -> Font_Raster_Selection {

    return {
        slot_index = slot_index,
        slot_incarnation = raster.identity.slot_incarnation,
        pixel_height = raster.identity.pixel_height,
    }
}

// Return the absolute difference between requested and resident raster heights.
font_raster_height_distance :: #force_inline proc(first, second: u32) -> u32 {
    return first - second if first > second else second - first
}

// Resolve a direct construction probe against the canonical resident raster.
cache_terminal_resolve_glyph_canonical :: proc(
    user_data: rawptr, key: Font_Key,
    glyph_id: u32) -> (Resolved_Glyph, bool) {

    request, valid := cache_raster_request(
        cast(^Font_Cache)user_data, key, f32(JULIA_MONO_FONT_SIZE), 1)
    if !valid {
        return {}, false
    }
    return cache_terminal_resolve_glyph(user_data, key, glyph_id, request)
}

//   Resolve one codepoint through the effective cmap and page state.
cache_terminal_resolve_codepoint :: proc(
    user_data: rawptr, key: Font_Key,
    codepoint: rune,
    request: fontmodel.Font_Raster_Request) ->
    (Resolved_Glyph, Font_Glyph_Resolve_Status) {

    cache := cast(^Font_Cache)user_data
    if !cache_raster_request_matches_key(cache, key, request) {
        return {}, .Unsupported
    }
    entry := cache_effective_entry(cache, key)
    if entry == nil {
        return {}, .Unsupported
    }
    glyph_id, supported := harfbuzz_nominal_glyph(&entry.shaping, codepoint)
    if !supported || glyph_id >= u32(len(entry.canonical_raster.glyphs)) {
        entry.unsupported_codepoint_count += 1
        return {}, .Unsupported
    }
    return cache_terminal_resolve_codepoint_glyph(
        cache, entry, request, glyph_id)
}

// Resolve raster demand, fallback, and status for one already mapped glyph ID.
cache_terminal_resolve_codepoint_glyph :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    request: fontmodel.Font_Raster_Request,
    glyph_id: u32) -> (Resolved_Glyph, Font_Glyph_Resolve_Status) {

    target_index, target_found := cache_optional_raster_admit(cache, request)
    target := &entry.canonical_raster
    if target_found {
        target = &cache.optional_rasters[int(target_index)]
    }
    resolved, resident := font_generation_resolve_glyph(
        entry, target, glyph_id, target_index)
    if resident {
        if !cache_frame_pin_glyph(cache, resolved) {
            return {}, .Pending
        }
        return resolved, .Resident
    }
    _ = cache_request_raster_glyph(cache, entry, request, glyph_id)
    if target.glyphs[glyph_id].state == .Capacity_Blocked {
        return {}, .Capacity_Exhausted
    }
    entry.pending_codepoint_count += 1
    fallback := cache_raster_fallback(cache, entry, request, glyph_id)
    if fallback.texture.handle != nil {
        if !cache_frame_pin_glyph(cache, fallback) {
            return {}, .Pending
        }
        return fallback, .Resident
    }
    return {}, .Pending
}

// Select the closest resident same-face raster, preferring larger-height ties.
cache_raster_fallback :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    request: fontmodel.Font_Raster_Request, glyph_id: u32) -> Resolved_Glyph {

    if cache == nil || entry == nil {
        return {}
    }
    best := Resolved_Glyph{}
    best_distance := max(u32)
    best_height := u32(0)
    canonical, canonical_ready := font_generation_resolve_glyph(
        entry, &entry.canonical_raster, glyph_id)
    if canonical_ready {
        best = canonical
        height := u32(canonical.raster_pixel_height)
        best_distance = font_raster_height_distance(height, request.pixel_height)
        best_height = height
    }
    fallback := Font_Raster_Fallback_Candidate{best, best_distance, best_height}
    return cache_raster_fallback_optional(
        cache, entry, request, glyph_id, &fallback).glyph
}

// Compare eligible optional images against the canonical fallback candidate.
cache_raster_fallback_optional :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    request: fontmodel.Font_Raster_Request, glyph_id: u32,
    candidate: ^Font_Raster_Fallback_Candidate) -> Font_Raster_Fallback_Candidate {

    for _, raster_index in cache.optional_rasters {
        raster := &cache.optional_rasters[raster_index]
        if raster.state != .Resident || raster.identity.key != request.key ||
            raster.identity.source_generation != request.source_generation {
            continue
        }
        glyph, ready := font_generation_resolve_glyph(
            entry, raster, glyph_id, i32(raster_index))
        if !ready {
            continue
        }
        height := raster.identity.pixel_height
        distance := font_raster_height_distance(height, request.pixel_height)
        if distance < candidate.distance ||
            distance == candidate.distance && height > candidate.height {
            candidate^ = {glyph, distance, height}
        }
    }
    return candidate^
}

// Resolve one preparation task's raster only while its incarnation still matches.
cache_preparation_raster :: proc(
    cache: ^Font_Cache, task: ^Font_Prepare_Task) -> ^Font_Raster_Instance {

    if cache == nil || task == nil {
        return nil
    }
    entry := &cache.entries[int(task.key)]
    if task.raster_slot_index < 0 {
        return &entry.canonical_raster
    }
    if task.raster_slot_index >= len(cache.optional_rasters) {
        return nil
    }
    raster := &cache.optional_rasters[task.raster_slot_index]
    if raster.identity.slot_incarnation != task.raster_slot_incarnation ||
        raster.identity.key != task.key ||
        raster.identity.source_generation != task.generation {
        return nil
    }
    return raster
}

//   Validate one completed page against current generation and queued demand.
//
// Returns:
//   - True when every compact glyph record can publish without partial mutation.
cache_glyph_page_can_publish :: proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    prepared: ^Prepared_Font) -> bool {

    if entry == nil || prepared == nil ||
        raster == nil ||
        prepared.generation != entry.generation ||
        entry.generation != entry.requested_generation ||
        raster.page_count >= fontmodel.FONT_GLYPH_PAGE_CAPACITY {
        return false
    }
    for glyph in prepared.glyphs {
        if glyph.glyph_id >= u32(len(raster.glyphs)) ||
            raster.glyphs[glyph.glyph_id].state != .Queued {
            return false
        }
    }
    return true
}

//   Report whether a prepared page exactly matches its submitted glyph-ID batch.
//
// Returns:
//   - True when count and ordered face glyph IDs are unchanged by preparation.
cache_glyph_page_matches_task :: proc(
    prepared: ^Prepared_Font, task: ^Font_Prepare_Task) -> bool {

    if prepared == nil || task == nil ||
        prepared.glyph_count != task.glyph_id_count {
        return false
    }
    for glyph, index in prepared.glyphs {
        if glyph.glyph_id != task.glyph_ids[index] {
            return false
        }
    }
    return true
}

//   Publish page-local glyph records and resolve demanded counters.
cache_publish_glyph_records :: proc(
    raster: ^Font_Raster_Instance, prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task, page_index: i32) {

    for glyph, index in prepared.glyphs {
        rectangle := prepared.rectangles[index]
        raster.glyphs[glyph.glyph_id] = {
            rectangle = {
                x = f32(rectangle.x), y = f32(rectangle.y),
                width = f32(rectangle.width), height = f32(rectangle.height),
            },
            offset_x = glyph.offset_x,
            offset_y = glyph.offset_y,
            advance_x = glyph.advance_x,
            page_index = u16(page_index + 1),
            state = .Resident,
        }
        if i32(index) < task.demanded_glyph_count {
            raster.pending_glyph_count -= 1
        }
    }
}

//   Commit one immutable page descriptor and its publication telemetry.
cache_commit_glyph_page :: proc(
    entry: ^Font_Cache_Entry, raster: ^Font_Raster_Instance,
    prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task, texture: Font_Texture) {

    page_index := raster.page_count
    raster.pages[page_index] = {
        texture = texture,
        generation = prepared.generation,
        glyph_count = prepared.glyph_count,
    }
    raster.page_count += 1
    entry.page_publication_count += 1
    entry.prefetched_glyph_count += u64(
        task.glyph_id_count - task.demanded_glyph_count)
    raster.queued_demand_count = 0
}

// cache_publish_glyph_page_texture commits one successfully uploaded page.
cache_publish_glyph_page_texture :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task, texture: Font_Texture) -> bool {
    if cache == nil || prepared == nil || texture.handle == nil {
        return false
    }
    entry := &cache.entries[int(prepared.key)]
    raster := cache_preparation_raster(cache, task)
    if !cache_glyph_page_matches_task(prepared, task) ||
        !cache_glyph_page_can_publish(entry, raster, prepared) {
        return false
    }
    if !font_raster_budget_publish(
        &cache.raster_budget, task.rgba_reservation_bytes) {
        return false
    }
    raster.charged_rgba_bytes += task.rgba_reservation_bytes
    page_index := raster.page_count
    cache_publish_glyph_records(raster, prepared, task, page_index)
    cache_commit_glyph_page(entry, raster, prepared, task, texture)
    if task.raster_slot_index >= 0 {
        raster.raster_ascent = prepared.raster_ascent
        raster.state = .Resident
        raster.last_used_tick = cache.raster_request_clock
    }
    prepare_destroy(prepared)
    return true
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
    case .Pending_Glyph:
        cache.shaping_telemetry.pending_glyph_runs += 1
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
        request_raster = cache_terminal_make_raster_request,
        resolve_glyph = cache_terminal_resolve_glyph,
        select_glyph_raster = cache_terminal_select_glyph_raster,
        resolve_selected_glyph = cache_terminal_resolve_selected_glyph,
        resolve_codepoint = cache_terminal_resolve_codepoint,
        shape = cache_terminal_shape,
        record_shape_fallback = cache_terminal_record_shape_fallback,
        workspace = cache.shaped_glyphs[:],
    }
}

// Adapt raster request selection to the cache-backed frame resolver.
cache_terminal_make_raster_request :: proc(
    user_data: rawptr, key: Font_Key,
    logical_size, scene_pixels_per_logical_unit: f32) ->
    (fontmodel.Font_Raster_Request, bool) {

    return cache_raster_request(
        cast(^Font_Cache)user_data, key,
        logical_size, scene_pixels_per_logical_unit)
}

//   Convert dynview's weight and italic flags to one indexed cache key.
font_key_from_flags :: proc(flags: fontmodel.Font_Variant_Flags) -> Font_Key {
    return fontmodel.font_key_from_flags(flags)
}

//   Build generation-owned shaping and GPU candidates from one prepared font.
cache_publication_candidates :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    texture: Font_Texture, candidate: ^Font_Cache_Entry) -> bool {

    path := cache_source_path(cache, prepared.key)
    if !font_shaping_create(
        cache, prepared.key, path, &candidate.shaping) {
        return false
    }
    candidate.raster_ascent = prepared.raster_ascent
    if !font_generation_seed_records_init(
        candidate, prepared, context.allocator) {
        font_generation_destroy(candidate, cache.texture_operations)
        return false
    }
    finalized, valid := prepared_face(prepared, texture)
    if !valid {
        font_generation_destroy(candidate, cache.texture_operations)
        return false
    }
    candidate.font = finalized
    candidate.canonical_raster.identity = {
        key = prepared.key,
        source_generation = prepared.generation,
        pixel_height = u32(prepared.base_size),
        policy = FONT_FREETYPE_RASTER_POLICY,
        slot_incarnation = fontmodel.FONT_CANONICAL_RASTER_SLOT_INCARNATION,
    }
    candidate.canonical_raster.state = .Resident
    candidate.canonical_raster.raster_ascent = prepared.raster_ascent
    candidate.canonical_raster.texture = texture
    candidate.resident = true
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

    rgba_bytes := u64(prepared.atlas_width) * u64(prepared.atlas_height) * 4
    if !cache_raster_budget_reserve_with_retirement(cache, rgba_bytes) {
        return false
    }
    texture, uploaded := finalize_texture(
        prepared, cache.texture_operations, {
            identity = u64(prepared.key) + 1,
            generation = prepared.generation,
        })
    if !uploaded {
       _ = font_raster_budget_release_bytes(
            &cache.raster_budget, rgba_bytes, false)
       return false
    }
    if !cache_publish_texture(cache, prepared, texture, rgba_bytes) {
        cache.texture_operations.release(
            cache.texture_operations.user_data, texture)
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, rgba_bytes, false)
        return false
    }
    return true
}

// cache_publish_texture atomically installs one successfully uploaded seed.
cache_publish_texture :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    texture: Font_Texture, rgba_bytes: u64) -> bool {
    entry := &cache.entries[int(prepared.key)]
    generation := prepared.generation
    if generation != entry.requested_generation {
       return false
    }
    candidate: Font_Cache_Entry
    if !cache_publication_candidates(cache, prepared, texture, &candidate) {
        return false
    }
    return cache_publish_texture_commit(
        cache, entry, prepared, rgba_bytes, &candidate)
}

// Commit a candidate generation and retire its previous texture ownership.
cache_publish_texture_commit :: proc(
    cache: ^Font_Cache, entry: ^Font_Cache_Entry,
    prepared: ^Prepared_Font, rgba_bytes: u64,
    candidate: ^Font_Cache_Entry) -> bool {

    generation := prepared.generation
    if !font_raster_budget_publish(&cache.raster_budget, rgba_bytes) {
        candidate^.canonical_raster.texture = {}
        font_generation_destroy(candidate, cache.texture_operations)
        return false
    }
    candidate^.canonical_raster.charged_rgba_bytes = rgba_bytes
    previous := entry^
    published := Font_Cache_Entry{
        font = candidate^.font,
        shaping = candidate^.shaping,
        raster_ascent = candidate^.raster_ascent,
        generation = prepared.generation,
        requested_generation = entry.requested_generation,
        resident = true,
        state = .Ready,
        request_count = entry.request_count,
        coalesced_request_count = entry.coalesced_request_count,
        fallback_resolution_count = entry.fallback_resolution_count,
        canonical_raster = candidate^.canonical_raster,
    }
    retired_bytes := previous.canonical_raster.charged_rgba_bytes
    entry^ = published
    cache_retire_published_generation(cache, &previous, retired_bytes)
    cache_destroy_stale_optional_rasters(cache, prepared.key, generation)
    return true
}

// Release a replaced generation after the new generation is committed.
cache_retire_published_generation :: proc(
    cache: ^Font_Cache, previous: ^Font_Cache_Entry, retired_bytes: u64) {

    if retired_bytes > 0 {
        assert(font_raster_budget_begin_retirement(
            &cache.raster_budget, retired_bytes))
    }
    font_generation_destroy(previous, cache.texture_operations)
    if retired_bytes > 0 {
        _ = font_raster_budget_release_bytes(
            &cache.raster_budget, retired_bytes, true)
    }
}

//   Shape one run through a resident variant's generation-owned native state.
cache_shape :: proc(
    cache: ^Font_Cache, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool) {

    if cache == nil {
        return 0, false
    }
    cache.shaping_telemetry.shape_calls += 1
    entry := cache_effective_entry(cache, key)
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

// Select a clamped integer raster height from logical size and scene transform.
font_raster_height_select :: proc(
    logical_size: f32,
    scene_pixels_per_logical_unit: f32) -> fontmodel.Font_Raster_Height_Selection {

    if !(logical_size > 0) || !(scene_pixels_per_logical_unit > 0) {
        return {}
    }
    requested := logical_size*scene_pixels_per_logical_unit
    if requested < f32(fontmodel.FONT_RASTER_MIN_PIXEL_HEIGHT) {
        return {
            pixel_height = fontmodel.FONT_RASTER_MIN_PIXEL_HEIGHT,
            quality_limited = true,
            valid = true,
        }
    }
    if requested >= f32(fontmodel.FONT_RASTER_MAX_PIXEL_HEIGHT) {
        return {
            pixel_height = fontmodel.FONT_RASTER_MAX_PIXEL_HEIGHT,
            quality_limited = requested > f32(fontmodel.FONT_RASTER_MAX_PIXEL_HEIGHT),
            valid = true,
        }
    }
    pixel_height := u32(requested)
    if f32(pixel_height) < requested {
        pixel_height += 1
    }
    return {pixel_height = pixel_height, valid = true}
}

// Convert one raster-pixel metric to logical units using that raster's height.
font_raster_metric_to_logical :: #force_inline proc(
    metric: f32, logical_size: f32,
    raster_pixel_height: u32) -> (f32, bool) {

    if !(logical_size > 0) || raster_pixel_height == 0 {
        return 0, false
    }
    return metric*logical_size/f32(raster_pixel_height), true
}

// Place raster bitmap coverage relative to the unchanged canonical baseline.
font_raster_bitmap_top_logical :: #force_inline proc(
    placement: Font_Raster_Bitmap_Placement) -> (f32, bool) {

    if !(placement.logical_size > 0) || placement.canonical_pixel_height == 0 ||
        placement.raster_pixel_height == 0 || placement.canonical_ascent <= 0 ||
        placement.raster_ascent <= 0 {
        return 0, false
    }
    baseline := placement.line_top + placement.canonical_ascent*
        placement.logical_size/f32(placement.canonical_pixel_height)
    top_from_baseline := f32(placement.bitmap_offset_y)-placement.raster_ascent
    return baseline + top_from_baseline*placement.logical_size/
        f32(placement.raster_pixel_height), true
}

// Build a generation-exact raster request from a resident face and scene transform.
cache_raster_request :: proc(
    cache: ^Font_Cache, requested_key: Font_Key,
    logical_size: f32,
    scene_pixels_per_logical_unit: f32) -> (fontmodel.Font_Raster_Request, bool) {

    if cache == nil {
        return {}, false
    }
    entry := cache_effective_entry(cache, requested_key)
    if entry == nil || !entry^.resident || entry^.generation == 0 {
        return {}, false
    }
    selection := font_raster_height_select(
        logical_size, scene_pixels_per_logical_unit)
    if !selection.valid {
        return {}, false
    }
    effective_key := requested_key
    if entry == &cache^.entries[int(Font_Key.Regular)] {
        effective_key = .Regular
    }
    return {
        key = effective_key,
        source_generation = entry^.generation,
        logical_size = logical_size,
        scene_pixels_per_logical_unit = scene_pixels_per_logical_unit,
        pixel_height = selection.pixel_height,
        policy = FONT_FREETYPE_RASTER_POLICY,
        quality_limited = selection.quality_limited,
    }, true
}

// Describe the resident image identity independently from face shaping identity.
cache_raster_identity :: proc(
    cache: ^Font_Cache,
    requested_key: Font_Key) -> (fontmodel.Font_Raster_Identity, bool) {

    if cache == nil {
        return {}, false
    }
    entry := cache_effective_entry(cache, requested_key)
    if entry == nil || !entry^.resident || entry^.generation == 0 ||
        entry^.font.base_size <= 0 {
        return {}, false
    }
    effective_key := requested_key
    if entry == &cache^.entries[int(Font_Key.Regular)] {
        effective_key = .Regular
    }
    return {
        key = effective_key,
        source_generation = entry^.generation,
        pixel_height = u32(entry^.font.base_size),
        policy = FONT_FREETYPE_RASTER_POLICY,
        slot_incarnation = fontmodel.FONT_CANONICAL_RASTER_SLOT_INCARNATION,
    }, true
}

// Describe baseline metrics for the pinned canonical raster of one resident face.
cache_canonical_raster_metrics :: proc(
    cache: ^Font_Cache,
    requested_key: Font_Key) -> (fontmodel.Font_Raster_Metrics, bool) {

    if cache == nil {
        return {}, false
    }
    entry := cache_effective_entry(cache, requested_key)
    if entry == nil || !entry^.resident || entry^.generation == 0 ||
        entry^.font.base_size <= 0 || entry^.raster_ascent <= 0 {
        return {}, false
    }
    return {
        pixel_height = u32(entry^.font.base_size),
        ascent = entry^.raster_ascent,
    }, true
}

// Describe the resident face that currently satisfies one requested JuliaMono key.
cache_shaping_identity :: proc(
    cache: ^Font_Cache,
    requested_key: Font_Key) -> (fontmodel.Font_Shaping_Identity, bool) {

    if cache == nil || requested_key == .Math_Regular {
        return {}, false
    }
    entry := cache_effective_entry(cache, requested_key)
    if entry == nil || !entry^.resident || entry^.generation == 0 ||
        entry^.shaping.font == nil || entry^.shaping.buffer == nil {
        return {}, false
    }
    effective_key := requested_key
    if entry == &cache^.entries[int(Font_Key.Regular)] {
        effective_key = .Regular
    }
    return {
        effective_key,
        entry^.generation,
        f32(JULIA_MONO_FONT_SIZE),
    }, true
}

// Shape through one exact resident face generation without fallback substitution.
cache_shape_generation :: proc(
    cache: ^Font_Cache, key: Font_Key, generation: u64,
    text: string, output: []Shaped_Glyph) -> (int, bool) {

    if !cache_generation_is_resident(cache, key, generation) {
        return 0, false
    }
    return harfbuzz_shape(&cache^.entries[int(key)].shaping, text, true, output)
}

// Query one glyph through one exact resident face generation.
cache_glyph_extents_generation :: proc(
    cache: ^Font_Cache, key: Font_Key, generation: u64,
    glyph_id: u32) -> (fontmodel.Font_Glyph_Extents, bool) {

    if !cache_generation_is_resident(cache, key, generation) {
        return {}, false
    }
    return harfbuzz_glyph_extents(
        &cache^.entries[int(key)].shaping, glyph_id)
}

