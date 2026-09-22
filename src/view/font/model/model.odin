package fontmodel

import "base:runtime"
import vmem "core:mem/virtual"

import geometry "../../../core/geometry"
import "../../../taskpool"

import rl "vendor:raylib"

// Number of indexed font variants through the final `Font_Key` value.
FONT_KEY_COUNT :: int(Font_Key.Math_Regular) + 1

// Maximum bytes retained for one display-owned font source path.
FONT_SOURCE_PATH_CAPACITY :: 1024

// Maximum concurrently resident glyph-atlas pages per font generation.
FONT_GLYPH_PAGE_CAPACITY :: 32

// Maximum runes in either required startup seed policy.
FONT_SEED_CODEPOINT_CAPACITY :: 512

// Maximum glyphs retained by one bounded shaping workspace.
FONT_SHAPED_GLYPH_CAPACITY :: 4096

Font_Weight :: enum {
    Light,
    Regular,
    Medium,
    Semibold,
    Bold,
    Extrabold,
    Black,
}

Font_Variant_Flags :: enum u32 {
    None = 0,
    Italic = 1 << 0,
    Light = 1 << 1,
    Regular = 1 << 2,
    Medium = 1 << 3,
    Semibold = 1 << 4,
    Bold = 1 << 5,
    Extrabold = 1 << 6,
    Black = 1 << 7,
}

Font_Key :: enum {
    Regular,
    Regular_Italic,
    Light,
    Light_Italic,
    Medium,
    Medium_Italic,
    Semi_Bold,
    Semi_Bold_Italic,
    Bold,
    Bold_Italic,
    Extra_Bold,
    Extra_Bold_Italic,
    Black,
    Black_Italic,
    Math_Regular,
}

Font_Load_State :: enum {
    Unrequested,
    Requested,
    Preparing,
    Ready,
    Failed,
}

Shaped_Glyph :: struct {
    glyph_id: u32,
    cluster: u32,
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
}

Font_Shaping_Resource :: struct {
    blob: rawptr,
    face: rawptr,
    font: rawptr,
    buffer: rawptr,
}

FONT_MATH_CONSTANT_COUNT :: 56
FONT_MATH_GLYPH_VARIANT_CAPACITY :: 16
FONT_MATH_GLYPH_PART_CAPACITY :: 16
FONT_MATH_KERN_ENTRY_CAPACITY :: 16

// Font_Math_Constants is one immutable generation's complete OpenType MATH table.
Font_Math_Constants :: struct {
    valid: bool,
    generation: u64,
    base_pixel_size: f32,
    values: [FONT_MATH_CONSTANT_COUNT]i32,
    text_match_scale: f32,
}

Font_Math_Glyph_Variant :: struct {
    glyph_id: u32,
    advance: i32,
    extents: Font_Glyph_Extents,
    italic_correction: i32,
    top_accent_attachment: i32,
}

Font_Math_Glyph_Variants :: struct {
    valid: bool,
    generation: u64,
    base_glyph_id: u32,
    extended_shape: bool,
    count: int,
    values: [FONT_MATH_GLYPH_VARIANT_CAPACITY]Font_Math_Glyph_Variant,
}

Font_Math_Glyph_Part :: struct {
    glyph_id: u32,
    start_connector_length: i32,
    end_connector_length: i32,
    full_advance: i32,
    extender: bool,
    extents: Font_Glyph_Extents,
}

Font_Math_Glyph_Assembly :: struct {
    valid: bool,
    generation: u64,
    base_glyph_id: u32,
    min_connector_overlap: i32,
    italic_correction: i32,
    count: int,
    values: [FONT_MATH_GLYPH_PART_CAPACITY]Font_Math_Glyph_Part,
}

Font_Math_Kern_Entry :: struct {
    max_correction_height: i32,
    kern_value: i32,
}

Font_Math_Kern_Table :: struct {
    valid: bool,
    generation: u64,
    glyph_id: u32,
    corner: u8,
    count: int,
    entries: [FONT_MATH_KERN_ENTRY_CAPACITY]Font_Math_Kern_Entry,
}

Font_Math_Stretch_Part :: struct {
    glyph_id: u32,
    advance_offset: f32,
    extents: Font_Glyph_Extents,
}

Font_Math_Stretch_Construction :: struct {
    valid: bool,
    assembled: bool,
    generation: u64,
    base_glyph_id: u32,
    advance: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
    count: int,
    parts: [FONT_MATH_GLYPH_PART_CAPACITY]Font_Math_Stretch_Part,
}

Font_Math_Stretch_Source :: struct {
    raster_ascent: f32,
    variants: Font_Math_Glyph_Variants,
    assembly: Font_Math_Glyph_Assembly,
}

Font_Math_Shaping_Capability :: struct {
    resource: Font_Shaping_Resource,
    constants: Font_Math_Constants,
    generation: u64,
    failed_generation: u64,
    raster_ascent: f32,
}

Font_Shaping_Identity :: struct {
    key: Font_Key,
    generation: u64,
    raster_ascent: f32,
}

Font_Glyph_Extents :: struct {
    x_bearing: i32,
    y_bearing: i32,
    width: i32,
    height: i32,
}

Font_Shaping_Telemetry :: struct {
    shape_calls: u64,
    shaped_runs: u64,
    shaped_glyphs: u64,
    native_failures: u64,
    workspace_overflows: u64,
    invalid_results: u64,
    invalid_clusters: u64,
    pending_glyph_runs: u64,
}

Font_Glyph_State :: enum u8 {
    Missing,
    Pending,
    Queued,
    Resident,
    Capacity_Blocked,
}

Font_Glyph_Record :: struct {
    rectangle: geometry.Rectangle,
    offset_x: i32,
    offset_y: i32,
    advance_x: i32,
    page_index: u16,
    state: Font_Glyph_State,
}

Font_Glyph_Page :: struct {
    texture: rl.Texture2D,
    generation: u64,
    glyph_count: i32,
}

Font_Cache_Entry :: struct {
    font: rl.Font,
    shaping: Font_Shaping_Resource,
    raster_ascent: f32,
    generation: u64,
    requested_generation: u64,
    resident: bool,
    state: Font_Load_State,
    request_count: u64,
    coalesced_request_count: u64,
    fallback_resolution_count: u64,
    glyphs: []Font_Glyph_Record,
    glyph_allocator: runtime.Allocator,
    pages: [FONT_GLYPH_PAGE_CAPACITY]Font_Glyph_Page,
    page_count: i32,
    pending_glyph_count: i32,
    queued_demand_count: i32,
    page_publication_count: u64,
    prefetched_glyph_count: u64,
    pending_codepoint_count: u64,
    unsupported_codepoint_count: u64,
    capacity_rejection_count: u64,
}

Prepared_Font_Allocation_Mode :: enum {
    Individual,
    Arena,
}

Prepared_Glyph :: struct {
    value: rune,
    glyph_id: u32,
    offset_x: i32,
    offset_y: i32,
    advance_x: i32,
    bitmap_width: i32,
    bitmap_height: i32,
}

Prepared_Rectangle :: struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

Prepared_Font :: struct {
    key: Font_Key,
    generation: u64,
    base_size: i32,
    raster_ascent: f32,
    glyph_count: i32,
    face_glyph_count: i32,
    padding: i32,
    atlas_width: i32,
    atlas_height: i32,
    atlas_pixels: []u8,
    glyphs: []Prepared_Glyph,
    rectangles: []Prepared_Rectangle,
    allocator: runtime.Allocator,
    allocation_mode: Prepared_Font_Allocation_Mode,
    complete_face: bool,
}

Font_Prepare_Operation_State :: enum {
    Idle,
    Retry,
    Queued,
}

Font_Prepare_Operation_Kind :: enum {
    Seed,
    Glyph_Page,
}

Font_Prepare_Task :: struct {
    kind: Font_Prepare_Operation_Kind,
    key: Font_Key,
    generation: u64,
    path_storage: [1024]u8,
    path_length: int,
    pixel_size: i32,
    codepoints: [FONT_SEED_CODEPOINT_CAPACITY]rune,
    codepoint_count: i32,
    glyph_ids: [256]u32,
    glyph_id_count: i32,
    demanded_glyph_count: i32,
    prepared: Prepared_Font,
    allocator: runtime.Allocator,
}

Font_Prepare_Operation :: struct {
    state: Font_Prepare_Operation_State,
    task: Font_Prepare_Task,
    handle: taskpool.Task_Handle,
    queue_full_count: u64,
    pending_poll_count: u64,
    failure_count: u64,
    publication_count: u64,
    stale_completion_count: u64,
    cancellation_request_count: u64,
    cancellation_completion_count: u64,
}

Font_Source_Signature :: struct {
    modification_ns: i64,
    size: i64,
    present: bool,
}

Font_Source_Monitor_Entry :: struct {
    observed: Font_Source_Signature,
    pending: Font_Source_Signature,
    reload_due_ns: i64,
    pending_change: bool,
}

Font_Source_Monitor :: struct {
    entries: [FONT_KEY_COUNT]Font_Source_Monitor_Entry,
    next_poll_ns: i64,
    change_count: u64,
    reload_count: u64,
    initialized: bool,
}

Font_Source_Path :: struct {
    storage: [FONT_SOURCE_PATH_CAPACITY]u8,
    length: int,
}

Font_Cache :: struct {
    entries: [FONT_KEY_COUNT]Font_Cache_Entry,
    source_paths: [FONT_KEY_COUNT]Font_Source_Path,
    preparation: Font_Prepare_Operation,
    preparation_arena: vmem.Arena,
    preparation_arena_initialized: bool,
    source_monitor: Font_Source_Monitor,
    shutting_down: bool,
    shaping_telemetry: Font_Shaping_Telemetry,
    shaped_glyphs: [FONT_SHAPED_GLYPH_CAPACITY]Shaped_Glyph,
}
