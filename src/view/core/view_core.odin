package view_core

import "../../core"
import "../../files"

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

ISO_SCALE_VALUE :: 800
ISO_X_OFFSET :: 450
ISO_Y_OFFSET :: 450

LIMIT_FPS :: 60
FIXED_DT :: 1.0 / LIMIT_FPS
MAX_FRAME_DT :: 0.25
MAX_STEPS_PER_FRAME :: 6
FPS_AVERAGE_BUCKET_COUNT :: 60

ALLOWED_CONSTRAINT_ERROR :: 0.0001

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280

VIEW_HEIGHT :: 500
BOTTOM_BAR_HEIGHT :: WINDOW_HEIGHT - VIEW_HEIGHT
VIEW_WIDTH :: 900
RIGHT_BAR_WIDTH :: WINDOW_WIDTH - VIEW_WIDTH

WINDOW_TITLE :: "Euclid's Elements"

JULIA_MONO_FONT_LOAD_SIZE :: 64

BACKGROUND_COLOR :: rl.Color{36, 5, 16, 255}
TOOL_COLOR :: rl.Color{96, 72, 82, 255}

UI_BACK_COLOR :: rl.Color{66, 35, 46, 255}
UI_BORDER_COLOR :: rl.Color{86, 55, 66, 255}
UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

UI_COMPONENT_BACKGROUND_COLOR :: rl.Color{25, 25, 25, 255}

SURFACE_COLOR :: rl.Color{25, 25, 25, 255}
SURFACE_EDGE_SIZE :: 0.05
SURFACE_EDGE_COLOR :: rl.Color{96, 65, 76, 255}


TREE_FONT_SIZE :: 16

FONT_CODEPOINT_CAPACITY :: 8192
BASELINE_FONT_VARIANT_COUNT :: 3
FONT_GLYPH_PADDING :: 4

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Shapes_Point_Type :: core.Shapes_Point_Type
Shapes_Point :: core.Shapes_Point
Shapes_Constraint :: core.Shapes_Constraint
Shapes_Point_System :: core.Shapes_Point_System
Particle :: core.Particle
Particle_System :: core.Particle_System
Euclid_Drawing_Surface :: core.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings

//   Static JuliaMono filenames indexed by weight and italic style.
FONT_VARIANT_FILENAMES :: [core.Font_Weight][2]string{
    .Light = {"JuliaMono-Light.ttf", "JuliaMono-LightItalic.ttf"},
    .Regular = {"JuliaMono-Regular.ttf", "JuliaMono-RegularItalic.ttf"},
    .Medium = {"JuliaMono-Medium.ttf", "JuliaMono-MediumItalic.ttf"},
    .Semibold = {"JuliaMono-SemiBold.ttf", "JuliaMono-SemiBoldItalic.ttf"},
    .Bold = {"JuliaMono-Bold.ttf", "JuliaMono-BoldItalic.ttf"},
    .Extrabold = {"JuliaMono-ExtraBold.ttf", "JuliaMono-ExtraBoldItalic.ttf"},
    .Black = {"JuliaMono-Black.ttf", "JuliaMono-BlackItalic.ttf"},
}

Font_Codepoint_Range :: struct {
    first: rune,
    last: rune,
}

Font_Codepoint_Set :: struct {
    values: [FONT_CODEPOINT_CAPACITY]rune,
    count: i32,
}

Prepared_Font :: struct {
    font: rl.Font,
    atlas: rl.Image,
    ready: bool,
}

Baseline_Font_Preparation :: struct {
    variants: [BASELINE_FONT_VARIANT_COUNT]Prepared_Font,
}

// Keep broad language and mathematical coverage while avoiding terminal-only
// box/block glyphs and the unassigned holes in one giant Unicode interval.
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

//   Build the immutable JuliaMono codepoint policy in raylib's required flat form.
font_codepoint_set :: proc() -> Font_Codepoint_Set {
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
font_codepoint_is_supported :: proc(codepoint: rune) -> bool {
    for codepoint_range in FONT_CODEPOINT_RANGES {
        if codepoint >= codepoint_range.first && codepoint <= codepoint_range.last {
            return true
        }
    }
    return false
}

//   Suppress raylib's expected oversized-glyph and sparse-range messages during rasterization.
font_rasterization_begin :: proc() {
    rl.SetTraceLogLevel(.ERROR)
}

//   Restore normal raylib diagnostics immediately after font rasterization.
font_rasterization_end :: proc() {
    rl.SetTraceLogLevel(.INFO)
}

//   Resolve one static JuliaMono filename from weight and italic style.
font_variant_filename :: #force_inline proc(
    weight: core.Font_Weight, italic: bool) -> string {
    filenames := FONT_VARIANT_FILENAMES
    return filenames[weight][italic ? 1 : 0]
}

//   Return packed slot index for one weight/italic pair.
font_variant_slot_index :: #force_inline proc(
    weight: core.Font_Weight, italic: bool) -> int {
    base := 0
    switch weight {
    case .Light:
        base = 0
    case .Regular:
        base = 2
    case .Medium:
        base = 4
    case .Semibold:
        base = 6
    case .Bold:
        base = 8
    case .Extrabold:
        base = 10
    case .Black:
        base = 12
    }

    if italic {
        return base + 1
    }
    return base
}

//   Decode baseline JuliaMono glyphs and build their CPU-side atlases.
//
// Notes:
//   - Safe to call before GPU finalization; preparation owns all returned memory.
//   - Pair with font_runtime_init_from_preparation to transfer or release that memory.
font_runtime_prepare_baseline :: proc(
    preparation: ^Baseline_Font_Preparation, font_size: i32) {
    font_prepare_variant(&preparation^.variants[0], .Regular, false, font_size)
    font_prepare_variant(&preparation^.variants[1], .Bold, false, font_size)
    font_prepare_variant(&preparation^.variants[2], .Regular, true, font_size)
}

//   Upload prepared baseline atlases and install fonts into runtime slots.
//
// Notes:
//   - Must run on the display thread with an active graphics context.
//   - Missing prepared variants fall back to the existing synchronous loader.
font_runtime_init_from_preparation :: proc(
    state: ^core.Euclid_General_State, preparation: ^Baseline_Font_Preparation,
    font_size: i32) -> bool {
    regular_slot := font_variant_slot_index(.Regular, false)
    bold_slot := font_variant_slot_index(.Bold, false)
    italic_slot := font_variant_slot_index(.Regular, true)

    font_finalize_variant(state, &preparation^.variants[0], regular_slot)
    font_finalize_variant(state, &preparation^.variants[1], bold_slot)
    font_finalize_variant(state, &preparation^.variants[2], italic_slot)
    return font_runtime_init_with_regular(state, font_size)
}

//   Decode one JuliaMono variant and retain all RAM needed for later GPU upload.
font_prepare_variant :: proc(
    prepared: ^Prepared_Font, weight: core.Font_Weight,
    italic: bool, font_size: i32) {
    filename := font_variant_filename(weight, italic)
    font_path := files.packaged_asset_path(filename, context.temp_allocator)
    if len(font_path) == 0 {
        return
    }

    font_file := strings.clone_to_cstring(font_path, context.temp_allocator)
    data_size: i32
    font_data := rl.LoadFileData(font_file, &data_size)
    if font_data == nil {
        return
    }
    defer rl.UnloadFileData(font_data)

    codepoints := font_codepoint_set()
    font := rl.Font{baseSize = font_size, glyphPadding = FONT_GLYPH_PADDING}
    font_rasterization_begin()
    font.glyphs = rl.LoadFontData(
        rawptr(font_data), data_size, font_size, &codepoints.values[0], codepoints.count,
        .DEFAULT, &font.glyphCount)
    font_rasterization_end()
    if font.glyphs == nil || font.glyphCount == 0 {
        font_discard_prepared_data(font, rl.Image{})
        return
    }

    atlas, atlas_ok := font_build_glyph_atlas(&font)
    if !atlas_ok {
        font_discard_prepared_data(font, atlas)
        return
    }
    prepared^ = Prepared_Font{font = font, atlas = atlas, ready = true}
}

//   Build the glyph atlas for one decoded font and extract per-glyph images.
//
// Parameters:
//   - font: Decoded font whose glyph images are replaced with atlas sub-images.
//
// Returns:
//   - atlas: Atlas image owned by the caller; empty image on failure.
//   - ok: true when the atlas was generated and glyph images were extracted.
font_build_glyph_atlas :: proc(font: ^rl.Font) -> (rl.Image, bool) {
    atlas := rl.GenImageFontAtlas(
        font^.glyphs, &font^.recs, font^.glyphCount, font^.baseSize,
        font^.glyphPadding, 0)
    if atlas.data == nil {
        return rl.Image{}, false
    }

    for index in 0..<font^.glyphCount {
        rl.UnloadImage(font^.glyphs[index].image)
        font^.glyphs[index].image = rl.ImageFromImage(atlas, font^.recs[index])
    }
    return atlas, true
}

//   Upload one prepared atlas and transfer its RAM ownership to the runtime font slot.
font_finalize_variant :: proc(
    state: ^core.Euclid_General_State, prepared: ^Prepared_Font,
    slot_index: int) {
    if !prepared^.ready {
        return
    }

    prepared^.font.texture = rl.LoadTextureFromImage(prepared^.atlas)
    rl.UnloadImage(prepared^.atlas)
    prepared^.atlas = rl.Image{}
    if prepared^.font.texture.id == 0 {
        font_discard_prepared_data(prepared^.font, prepared^.atlas)
        prepared^ = Prepared_Font{}
        return
    }

    rl.SetTextureFilter(prepared^.font.texture, .POINT)
    slot := &state^.font_runtime.variants[slot_index]
    slot^.font = prepared^.font
    slot^.loaded = true
    prepared^ = Prepared_Font{}
}

//   Release prepared font RAM that was not transferred to a runtime font slot.
font_discard_prepared_data :: proc(font: rl.Font, atlas: rl.Image) {
    if atlas.data != nil {
        rl.UnloadImage(atlas)
    }
    if font.glyphs != nil {
        rl.UnloadFontData(font.glyphs, font.glyphCount)
    }
    if font.recs != nil {
        rl.MemFree(rawptr(font.recs))
    }
}

//   Emit a one-time fallback warning for a font variant slot.
//
// Parameters:
//   - slot: Font variant slot tracking warning state.
//   - reason: Warning message prefix.
//   - filename: Font asset filename that failed.
font_warn_missing_variant :: proc(
    slot: ^core.Euclid_Font_Variant_Slot, reason, filename: string) {
    if slot^.missing_warned {
        return
    }
    slot^.missing_warned = true
    fmt.eprintln(reason, filename)
}

//   Load one variant and return true when raylib reports a valid texture handle.
font_load_variant :: proc(
    state: ^core.Euclid_General_State, slot_index: int,
    weight: core.Font_Weight, italic: bool, font_size: i32) -> bool {
    if state == nil {
        return false
    }

    if slot_index < 0 || slot_index >= len(state^.font_runtime.variants) {
        return false
    }

    slot := &state^.font_runtime.variants[slot_index]
    if slot^.loaded {
        return true
    }

    filename := font_variant_filename(weight, italic)
    font_path := files.packaged_asset_path(filename, context.temp_allocator)
    if len(font_path) == 0 {
        font_warn_missing_variant(
            slot, "font load fallback: unable to resolve asset path for ", filename)
        return false
    }

    font_file := strings.clone_to_cstring(font_path, context.temp_allocator)
    codepoints := font_codepoint_set()
    font_rasterization_begin()
    font := rl.LoadFontEx(font_file, font_size, &codepoints.values[0], codepoints.count)
    font_rasterization_end()
    if font.texture.id == 0 {
        font_warn_missing_variant(slot, "font load fallback: failed to load ", filename)
        return false
    }

    slot^.font = font
    slot^.loaded = true
    return true
}

//   Resolve or load a requested variant from flags, with fallback to Regular.
font_runtime_resolve :: proc(
    state: ^core.Euclid_General_State, flags: core.Font_Variant_Flags,
    font_size: i32) -> rl.Font {
    if state == nil {
        return rl.Font{}
    }

    requested_weight := core.font_resolve_weight_from_flags(flags)
    requested_italic := core.font_has_flag(flags, .Italic)
    requested_slot := font_variant_slot_index(requested_weight, requested_italic)

    if font_load_variant(
        state, requested_slot, requested_weight, requested_italic, font_size) {
        return state^.font_runtime.variants[requested_slot].font
    }

    regular_slot := state^.font_runtime.regular_slot_index
    if regular_slot < 0 || regular_slot >= len(state^.font_runtime.variants) {
        regular_slot = font_variant_slot_index(.Regular, false)
        state^.font_runtime.regular_slot_index = regular_slot
    }

    if font_load_variant(state, regular_slot, .Regular, false, font_size) {
        state^.font = state^.font_runtime.variants[regular_slot].font
        return state^.font_runtime.variants[regular_slot].font
    }

    return state^.font
}

//   Preload baseline JuliaMono variants during startup.
//
// Notes:
//   - Baseline startup set is Regular, Bold, and RegularItalic.
//   - Other variants still load lazily when requested.
font_runtime_init_with_regular :: proc(
    state: ^core.Euclid_General_State, font_size: i32) -> bool {
    if state == nil {
        return false
    }

    regular_slot := font_variant_slot_index(.Regular, false)
    bold_slot := font_variant_slot_index(.Bold, false)
    italic_slot := font_variant_slot_index(.Regular, true)

    state^.font_runtime.regular_slot_index = regular_slot
    loaded_regular := font_load_variant(state, regular_slot, .Regular, false, font_size)
    if loaded_regular {
        state^.font = state^.font_runtime.variants[regular_slot].font
    }

    _ = font_load_variant(state, bold_slot, .Bold, false, font_size)
    _ = font_load_variant(state, italic_slot, .Regular, true, font_size)

    return loaded_regular
}

//   Unload all lazily loaded variants and reset runtime tracking.
font_runtime_unload_all :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }

    for i in 0..<len(state^.font_runtime.variants) {
        slot := &state^.font_runtime.variants[i]
        if !slot^.loaded {
            continue
        }

        rl.UnloadFont(slot^.font)
        slot^.font = rl.Font{}
        slot^.loaded = false
    }

    state^.font = rl.Font{}
}

//   Build flags for simple bold/italic requests using Regular as default weight.
font_flags_from_bold_italic :: #force_inline proc(
    bold, italic: bool) -> core.Font_Variant_Flags {
    flags := core.Font_Variant_Flags.Regular
    if bold {
        flags = core.Font_Variant_Flags.Bold
    }
    if italic {
        flags = core.Font_Variant_Flags(u32(flags) | u32(core.Font_Variant_Flags.Italic))
    }
    return flags
}
