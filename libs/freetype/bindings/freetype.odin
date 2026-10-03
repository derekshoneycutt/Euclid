package freetype

import "core:c"

Freetype_Status :: enum c.int {
    Ok = 0,
    Invalid_Argument = 1,
    Out_Of_Memory = 2,
    Memory_Limit = 3,
    Freetype_Error = 4,
    Range_Error = 5,
    Unsupported = 6,
}

Freetype_Raster_Policy :: enum c.int {
    Unhinted = 0,
    Light_Hinted = 1,
}

Freetype_Face :: struct {}

Freetype_Info :: struct {
    glyph_count: u32,
    units_per_em: u32,
    hhea_ascender: i32,
    hhea_descender: i32,
}

Freetype_Bitmap :: struct {
    pixels: [^]u8,
    byte_length: u64,
    width: u32,
    rows: u32,
    pitch: i32,
    bitmap_left: i32,
    bitmap_top: i32,
    pixel_mode: u32,
}

Freetype_Memory_Stats :: struct {
    current_bytes: u64,
    peak_bytes: u64,
    limit_bytes: u64,
    allocation_count: u64,
    limit_reached: u32,
}

when ODIN_OS == .Linux {
    foreign import euclid_freetype "system:euclid_freetype"

    foreign euclid_freetype {
        euclid_ft_open :: proc(
            source: [^]u8, source_length: u64, allocation_limit: u64,
            out_face: ^^Freetype_Face, out_info: ^Freetype_Info) -> Freetype_Status ---
        euclid_ft_close :: proc(face: ^Freetype_Face) ---
        euclid_ft_glyph_index :: proc(
            face: ^Freetype_Face, codepoint: u32, out_glyph: ^u32) -> Freetype_Status ---
        euclid_ft_glyph_metrics :: proc(
            face: ^Freetype_Face, glyph: u32, out_advance: ^i32,
            out_bearing_x: ^i32) -> Freetype_Status ---
        euclid_ft_set_em_size_26_6 :: proc(
            face: ^Freetype_Face, em_size_26_6: u32) -> Freetype_Status ---
        euclid_ft_render_gray :: proc(
            face: ^Freetype_Face, glyph: u32, policy: Freetype_Raster_Policy,
            out_bitmap: ^Freetype_Bitmap) -> Freetype_Status ---
        euclid_ft_copy_bitmap :: proc(
            face: ^Freetype_Face, destination: [^]u8, capacity: u64,
            out_copied: ^u64) -> Freetype_Status ---
        euclid_ft_memory_stats :: proc(
            face: ^Freetype_Face,
            out_stats: ^Freetype_Memory_Stats) -> Freetype_Status ---
    }
}