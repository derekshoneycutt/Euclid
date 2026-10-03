#include "euclid_freetype.h"

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MODULE_H
#include FT_SYSTEM_H
#include FT_TRUETYPE_TABLES_H

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define EUCLID_FT_MAX_BITMAP_DIMENSION 32768U
#define EUCLID_FT_MAX_BITMAP_BYTES (64U * 1024U * 1024U)

typedef union EuclidFTAllocation {
    struct {
        size_t size;
    } value;
    max_align_t alignment;
} EuclidFTAllocation;

struct EuclidFTFace {
    struct FT_MemoryRec_ memory;
    FT_Library library;
    FT_Face ft_face;
    uint64_t current_bytes;
    uint64_t peak_bytes;
    uint64_t limit_bytes;
    uint64_t allocation_count;
    uint32_t limit_reached;
    uint32_t allocation_failed;
};

static void *euclid_ft_alloc(FT_Memory memory, long size) {
    EuclidFTFace *owner = (EuclidFTFace *)memory->user;
    EuclidFTAllocation *allocation;
    uint64_t requested;
    uint64_t accounted_size;

    if (size <= 0) {
        return NULL;
    }
    requested = (uint64_t)size;
    if (requested > (uint64_t)SIZE_MAX - sizeof(*allocation)) {
        owner->limit_reached = 1;
        return NULL;
    }
    accounted_size = requested + sizeof(*allocation);
    if (accounted_size > owner->limit_bytes - owner->current_bytes) {
        owner->limit_reached = 1;
        return NULL;
    }
    allocation = (EuclidFTAllocation *)malloc((size_t)accounted_size);
    if (allocation == NULL) {
        owner->allocation_failed = 1;
        return NULL;
    }
    allocation->value.size = (size_t)accounted_size;
    owner->current_bytes += accounted_size;
    owner->allocation_count += 1;
    if (owner->current_bytes > owner->peak_bytes) {
        owner->peak_bytes = owner->current_bytes;
    }
    return allocation + 1;
}

static void euclid_ft_free(FT_Memory memory, void *block) {
    EuclidFTFace *owner = (EuclidFTFace *)memory->user;
    EuclidFTAllocation *allocation;

    if (block == NULL) {
        return;
    }
    allocation = (EuclidFTAllocation *)block - 1;
    owner->current_bytes -= allocation->value.size;
    free(allocation);
}

static void *euclid_ft_realloc(
    FT_Memory memory, long current_size, long new_size, void *block) {
    EuclidFTFace *owner = (EuclidFTFace *)memory->user;
    EuclidFTAllocation *allocation;
    EuclidFTAllocation *resized;
    uint64_t old_size;
    uint64_t requested;
    uint64_t accounted_size;

    (void)current_size;
    if (block == NULL) {
        return euclid_ft_alloc(memory, new_size);
    }
    if (new_size <= 0) {
        euclid_ft_free(memory, block);
        return NULL;
    }
    allocation = (EuclidFTAllocation *)block - 1;
    old_size = allocation->value.size;
    requested = (uint64_t)new_size;
    if (requested > (uint64_t)SIZE_MAX - sizeof(*allocation)) {
        owner->limit_reached = 1;
        return NULL;
    }
    accounted_size = requested + sizeof(*allocation);
    if (accounted_size >
        owner->limit_bytes - (owner->current_bytes - old_size)) {
        owner->limit_reached = 1;
        return NULL;
    }
    resized = (EuclidFTAllocation *)realloc(
        allocation, (size_t)accounted_size);
    if (resized == NULL) {
        owner->allocation_failed = 1;
        return NULL;
    }
    resized->value.size = (size_t)accounted_size;
    owner->current_bytes = owner->current_bytes - old_size + accounted_size;
    owner->allocation_count += 1;
    if (owner->current_bytes > owner->peak_bytes) {
        owner->peak_bytes = owner->current_bytes;
    }
    return resized + 1;
}

static EuclidFTStatus euclid_ft_failure(const EuclidFTFace *owner) {
    if (owner->limit_reached) {
        return EUCLID_FT_MEMORY_LIMIT;
    }
    return owner->allocation_failed ? EUCLID_FT_OUT_OF_MEMORY :
        EUCLID_FT_FREETYPE_ERROR;
}

static EuclidFTStatus euclid_ft_close_partial(EuclidFTFace *owner, EuclidFTStatus status) {
    if (owner->ft_face != NULL) {
        FT_Done_Face(owner->ft_face);
    }
    if (owner->library != NULL) {
        FT_Done_Library(owner->library);
    }
    free(owner);
    return status;
}

EuclidFTStatus euclid_ft_open(
    const uint8_t *source,
    uint64_t source_length,
    uint64_t allocation_limit,
    EuclidFTFace **out_face,
    EuclidFTInfo *out_info) {
    EuclidFTFace *owner;
    FT_Error error;
    TT_HoriHeader *hhea;

    if (source == NULL || source_length == 0 || allocation_limit == 0 ||
        out_face == NULL || out_info == NULL || source_length > LONG_MAX) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    *out_face = NULL;
    memset(out_info, 0, sizeof(*out_info));
    owner = (EuclidFTFace *)calloc(1, sizeof(*owner));
    if (owner == NULL) {
        return EUCLID_FT_OUT_OF_MEMORY;
    }
    owner->limit_bytes = allocation_limit;
    owner->memory.user = owner;
    owner->memory.alloc = euclid_ft_alloc;
    owner->memory.free = euclid_ft_free;
    owner->memory.realloc = euclid_ft_realloc;

    error = FT_New_Library(&owner->memory, &owner->library);
    if (error != 0) {
        return euclid_ft_close_partial(owner, euclid_ft_failure(owner));
    }
    FT_Add_Default_Modules(owner->library);
    error = FT_New_Memory_Face(owner->library, source, (FT_Long)source_length,
        0, &owner->ft_face);
    if (error != 0) {
        return euclid_ft_close_partial(owner, euclid_ft_failure(owner));
    }
    hhea = (TT_HoriHeader *)FT_Get_Sfnt_Table(owner->ft_face, ft_sfnt_hhea);
    if (hhea == NULL || owner->ft_face->num_glyphs < 0 ||
        (uint64_t)owner->ft_face->num_glyphs > UINT32_MAX ||
        owner->ft_face->units_per_EM == 0) {
        return euclid_ft_close_partial(owner, EUCLID_FT_UNSUPPORTED);
    }
    out_info->glyph_count = (uint32_t)owner->ft_face->num_glyphs;
    out_info->units_per_em = owner->ft_face->units_per_EM;
    out_info->hhea_ascender = hhea->Ascender;
    out_info->hhea_descender = hhea->Descender;
    *out_face = owner;
    return EUCLID_FT_OK;
}

void euclid_ft_close(EuclidFTFace *face) {
    if (face != NULL) {
        (void)euclid_ft_close_partial(face, EUCLID_FT_OK);
    }
}

EuclidFTStatus euclid_ft_glyph_index(
    EuclidFTFace *face, uint32_t codepoint, uint32_t *out_glyph) {
    if (face == NULL || out_glyph == NULL) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    *out_glyph = FT_Get_Char_Index(face->ft_face, (FT_ULong)codepoint);
    return EUCLID_FT_OK;
}

EuclidFTStatus euclid_ft_glyph_metrics(
    EuclidFTFace *face, uint32_t glyph, int32_t *out_advance,
    int32_t *out_bearing_x) {
    FT_Error error;
    FT_Pos advance;
    FT_Pos bearing;

    if (face == NULL || out_advance == NULL || out_bearing_x == NULL ||
        glyph >= (uint32_t)face->ft_face->num_glyphs) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    error = FT_Load_Glyph(face->ft_face, glyph,
        FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP);
    if (error != 0) {
        return euclid_ft_failure(face);
    }
    advance = face->ft_face->glyph->metrics.horiAdvance;
    bearing = face->ft_face->glyph->metrics.horiBearingX;
    if (advance < INT32_MIN || advance > INT32_MAX ||
        bearing < INT32_MIN || bearing > INT32_MAX) {
        return EUCLID_FT_RANGE_ERROR;
    }
    *out_advance = (int32_t)advance;
    *out_bearing_x = (int32_t)bearing;
    return EUCLID_FT_OK;
}

EuclidFTStatus euclid_ft_set_em_size_26_6(
    EuclidFTFace *face, uint32_t em_size_26_6) {
    if (face == NULL || em_size_26_6 == 0) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
#if LONG_MAX < UINT32_MAX
    if (em_size_26_6 > (uint32_t)LONG_MAX) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
#endif
    return FT_Set_Char_Size(face->ft_face, 0, (FT_F26Dot6)em_size_26_6, 72, 72) == 0 ?
        EUCLID_FT_OK : euclid_ft_failure(face);
}

EuclidFTStatus euclid_ft_render_gray(
    EuclidFTFace *face, uint32_t glyph, EuclidFTBitmap *out_bitmap) {
    FT_Bitmap *bitmap;
    uint64_t pitch;
    uint64_t bytes;
    FT_Error error;

    if (face == NULL || out_bitmap == NULL ||
        glyph >= (uint32_t)face->ft_face->num_glyphs) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    error = FT_Load_Glyph(face->ft_face, glyph,
        FT_LOAD_TARGET_LIGHT | FT_LOAD_NO_BITMAP);
    if (error != 0) {
        return euclid_ft_failure(face);
    }
    error = FT_Render_Glyph(face->ft_face->glyph, FT_RENDER_MODE_NORMAL);
    if (error != 0) {
        return euclid_ft_failure(face);
    }
    bitmap = &face->ft_face->glyph->bitmap;
    if (bitmap->pixel_mode != FT_PIXEL_MODE_GRAY || bitmap->num_grays < 2 ||
        bitmap->width > EUCLID_FT_MAX_BITMAP_DIMENSION ||
        bitmap->rows > EUCLID_FT_MAX_BITMAP_DIMENSION ||
        face->ft_face->glyph->bitmap_left < INT32_MIN ||
        face->ft_face->glyph->bitmap_left > INT32_MAX ||
        face->ft_face->glyph->bitmap_top < INT32_MIN ||
        face->ft_face->glyph->bitmap_top > INT32_MAX) {
        return EUCLID_FT_UNSUPPORTED;
    }
    pitch = bitmap->pitch < 0 ? (uint64_t)(-(int64_t)bitmap->pitch) :
        (uint64_t)bitmap->pitch;
    if (pitch < bitmap->width ||
        (bitmap->rows != 0 && pitch > UINT64_MAX / bitmap->rows)) {
        return EUCLID_FT_RANGE_ERROR;
    }
    bytes = pitch * bitmap->rows;
    if (bytes > EUCLID_FT_MAX_BITMAP_BYTES ||
        (bytes != 0 && bitmap->buffer == NULL)) {
        return EUCLID_FT_RANGE_ERROR;
    }
    out_bitmap->pixels = bitmap->buffer;
    out_bitmap->byte_length = bytes;
    out_bitmap->width = bitmap->width;
    out_bitmap->rows = bitmap->rows;
    out_bitmap->pitch = bitmap->pitch;
    out_bitmap->bitmap_left = (int32_t)face->ft_face->glyph->bitmap_left;
    out_bitmap->bitmap_top = (int32_t)face->ft_face->glyph->bitmap_top;
    out_bitmap->pixel_mode = 1;
    return EUCLID_FT_OK;
}

EuclidFTStatus euclid_ft_copy_bitmap(
    EuclidFTFace *face, uint8_t *destination, uint64_t capacity,
    uint64_t *out_copied) {
    const FT_Bitmap *bitmap;
    uint64_t length;

    if (face == NULL || out_copied == NULL) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    bitmap = &face->ft_face->glyph->bitmap;
    length = bitmap->pitch < 0 ? (uint64_t)(-(int64_t)bitmap->pitch) :
        (uint64_t)bitmap->pitch;
    if (bitmap->rows != 0 && length > UINT64_MAX / bitmap->rows) {
        return EUCLID_FT_RANGE_ERROR;
    }
    length *= bitmap->rows;
    if (length > capacity || (length != 0 && destination == NULL) ||
        (length != 0 && bitmap->buffer == NULL)) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    if (length != 0) {
        memcpy(destination, bitmap->buffer, (size_t)length);
    }
    *out_copied = length;
    return EUCLID_FT_OK;
}

EuclidFTStatus euclid_ft_memory_stats(
    EuclidFTFace *face, EuclidFTMemoryStats *out_stats) {
    if (face == NULL || out_stats == NULL) {
        return EUCLID_FT_INVALID_ARGUMENT;
    }
    out_stats->current_bytes = face->current_bytes;
    out_stats->peak_bytes = face->peak_bytes;
    out_stats->limit_bytes = face->limit_bytes;
    out_stats->allocation_count = face->allocation_count;
    out_stats->limit_reached = face->limit_reached;
    return EUCLID_FT_OK;
}