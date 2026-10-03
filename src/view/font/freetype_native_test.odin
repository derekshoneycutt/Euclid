#+test
package font

import freetype "../../../libs/freetype/bindings"

import "core:os"
import "core:testing"

when ODIN_OS == .Linux {
    // Verify glyph queries, bitmap copying, and native memory statistics.
    freetype_test_native_render :: proc(t: ^testing.T, face: ^freetype.Freetype_Face) {
        glyph: u32
        testing.expect_value(t,
            freetype.euclid_ft_glyph_index(face, 0x41, &glyph),
            freetype.Freetype_Status.Ok)
        testing.expect_value(t, glyph, u32(4))
        advance, bearing: i32
        testing.expect_value(t,
            freetype.euclid_ft_glyph_metrics(face, glyph, &advance, &bearing),
            freetype.Freetype_Status.Ok)
        testing.expect(t, advance > 0)
        testing.expect_value(t,
            freetype.euclid_ft_set_em_size_26_6(face, 24 * 64),
            freetype.Freetype_Status.Ok)
        bitmap: freetype.Freetype_Bitmap
        testing.expect_value(t, freetype.euclid_ft_render_gray(
            face, glyph, freetype.Freetype_Raster_Policy.Unhinted, &bitmap),
            freetype.Freetype_Status.Ok)
        testing.expect(t, bitmap.width > 0 && bitmap.rows > 0)
        testing.expect_value(t, bitmap.pixel_mode, u32(1))
        copied: u64
        testing.expect_value(t, freetype.euclid_ft_copy_bitmap(
            face, nil, 0, &copied), freetype.Freetype_Status.Invalid_Argument)
        pixels := make([]u8, int(bitmap.byte_length), context.allocator)
        defer delete(pixels)
        testing.expect_value(t, freetype.euclid_ft_copy_bitmap(
            face, &pixels[0], u64(len(pixels)), &copied), freetype.Freetype_Status.Ok)
        testing.expect_value(t, copied, bitmap.byte_length)
        stats: freetype.Freetype_Memory_Stats
        testing.expect_value(t,
            freetype.euclid_ft_memory_stats(face, &stats), freetype.Freetype_Status.Ok)
        testing.expect(t, stats.current_bytes <= stats.peak_bytes)
        testing.expect(t, stats.peak_bytes <= stats.limit_bytes)
        testing.expect(t, stats.allocation_count > 0)
    }

    // Verify a space glyph is a valid empty bitmap rather than a failed render.
    freetype_test_native_empty_glyph :: proc(
        t: ^testing.T, face: ^freetype.Freetype_Face) {
        glyph: u32
        testing.expect_value(t,
            freetype.euclid_ft_glyph_index(face, 0x20, &glyph),
            freetype.Freetype_Status.Ok)
        bitmap: freetype.Freetype_Bitmap
        testing.expect_value(t, freetype.euclid_ft_render_gray(
            face, glyph, freetype.Freetype_Raster_Policy.Unhinted, &bitmap),
            freetype.Freetype_Status.Ok)
        testing.expect_value(t, bitmap.byte_length, u64(0))
        copied: u64
        testing.expect_value(t, freetype.euclid_ft_copy_bitmap(
            face, nil, 0, &copied), freetype.Freetype_Status.Ok)
        testing.expect_value(t, copied, u64(0))
    }

    // Verify a bounded real-font open, canonical queries, raster copy, and teardown.
    @(test)
    view_test_freetype_native_roundtrip :: proc(t: ^testing.T) {
        source, read_error := os.read_entire_file(
            "assets/JuliaMono-Regular.ttf", context.allocator)
        testing.expect(t, read_error == nil)
        defer delete(source)
        face: ^freetype.Freetype_Face
        info: freetype.Freetype_Info
        status := freetype.euclid_ft_open(
            &source[0], u64(len(source)), 64 * 1024 * 1024, &face, &info)
        testing.expect_value(t, status, freetype.Freetype_Status.Ok)
        defer freetype.euclid_ft_close(face)
        testing.expect_value(t, info.glyph_count, u32(12337))
        freetype_test_native_render(t, face)
        freetype_test_native_empty_glyph(t, face)
    }

    // Reject malformed sources and bounded-allocation exhaustion without publishing a face.
    @(test)
    view_test_freetype_native_failure_cleanup :: proc(t: ^testing.T) {
        invalid: [8]u8
        face: ^freetype.Freetype_Face
        info: freetype.Freetype_Info
        status := freetype.euclid_ft_open(
            &invalid[0], u64(len(invalid)), 1024, &face, &info)
        testing.expect(t, status != .Ok)
        testing.expect_value(t, face, (^freetype.Freetype_Face)(nil))
        source, read_error := os.read_entire_file(
            "assets/JuliaMono-Regular.ttf", context.allocator)
        testing.expect(t, read_error == nil)
        defer delete(source)
        status = freetype.euclid_ft_open(
            &source[0], u64(len(source)), 1, &face, &info)
        testing.expect_value(t, status, freetype.Freetype_Status.Memory_Limit)
        testing.expect_value(t, face, (^freetype.Freetype_Face)(nil))
    }
}