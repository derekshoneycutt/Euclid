#ifndef EUCLID_FREETYPE_H
#define EUCLID_FREETYPE_H

#include <stdint.h>

typedef struct EuclidFTFace EuclidFTFace;

typedef enum EuclidFTStatus {
    EUCLID_FT_OK = 0,
    EUCLID_FT_INVALID_ARGUMENT = 1,
    EUCLID_FT_OUT_OF_MEMORY = 2,
    EUCLID_FT_MEMORY_LIMIT = 3,
    EUCLID_FT_FREETYPE_ERROR = 4,
    EUCLID_FT_RANGE_ERROR = 5,
    EUCLID_FT_UNSUPPORTED = 6
} EuclidFTStatus;

typedef struct EuclidFTInfo {
    uint32_t glyph_count;
    uint32_t units_per_em;
    int32_t hhea_ascender;
    int32_t hhea_descender;
} EuclidFTInfo;

typedef struct EuclidFTBitmap {
    const uint8_t *pixels;
    uint64_t byte_length;
    uint32_t width;
    uint32_t rows;
    int32_t pitch;
    int32_t bitmap_left;
    int32_t bitmap_top;
    uint32_t pixel_mode;
} EuclidFTBitmap;

typedef struct EuclidFTMemoryStats {
    uint64_t current_bytes;
    uint64_t peak_bytes;
    uint64_t limit_bytes;
    uint64_t allocation_count;
    uint32_t limit_reached;
} EuclidFTMemoryStats;

/* Source bytes are borrowed until close. The native allocation limit covers
    FreeType allocations and their callback bookkeeping, not the face wrapper or
    caller-owned source bytes. */
EuclidFTStatus euclid_ft_open(
    const uint8_t *source,
    uint64_t source_length,
    uint64_t allocation_limit,
    EuclidFTFace **out_face,
    EuclidFTInfo *out_info);
void euclid_ft_close(EuclidFTFace *face);
EuclidFTStatus euclid_ft_glyph_index(
    EuclidFTFace *face, uint32_t codepoint, uint32_t *out_glyph);
EuclidFTStatus euclid_ft_glyph_metrics(
    EuclidFTFace *face, uint32_t glyph, int32_t *out_advance,
    int32_t *out_bearing_x);
EuclidFTStatus euclid_ft_set_em_size_26_6(
    EuclidFTFace *face, uint32_t em_size_26_6);
/* Bitmap pixels are borrowed until the next glyph load, size change, render,
   or close. Copy preserves the bitmap's signed-pitch byte layout. */
EuclidFTStatus euclid_ft_render_gray(
    EuclidFTFace *face, uint32_t glyph, EuclidFTBitmap *out_bitmap);
EuclidFTStatus euclid_ft_copy_bitmap(
    EuclidFTFace *face, uint8_t *destination, uint64_t capacity,
    uint64_t *out_copied);
EuclidFTStatus euclid_ft_memory_stats(
    EuclidFTFace *face, EuclidFTMemoryStats *out_stats);

#endif