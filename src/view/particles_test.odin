package view

import native "native"

import "core:testing"

// Verify native dust records retain the reflected two-slot ABI.
@(test)
particles_test_native_dust_abi :: proc(t: ^testing.T) {
    instance: native.Dust_Instance
    base := uintptr(&instance)
    testing.expect_value(t, size_of(instance), 32)
    testing.expect_value(t, uintptr(&instance.center_diameter) - base, uintptr(0))
    testing.expect_value(t, uintptr(&instance.color) - base, uintptr(12))
    testing.expect_value(t, uintptr(&instance.sprite_index) - base, uintptr(28))
}

// Verify every generated atlas contour is normalized and complete.
@(test)
particles_test_hypocycloid_atlas_contours :: proc(t: ^testing.T) {
    points: [DUST_HYPOCYCLOID_SAMPLE_COUNT]Vector2
    for variant in 1..<DUST_ATLAS_VARIANT_COUNT {
        count := sample_dust_hypocycloid_points(points[:], variant + 2)
        testing.expect_value(t, count, DUST_HYPOCYCLOID_SAMPLE_COUNT)
        for point in points {
            testing.expect(t, point.x * point.x + point.y * point.y <= 0.83 * 0.83)
        }
    }
}

// Verify atlas generation produces transparent-white masks with fine edge coverage.
@(test)
particles_test_native_dust_atlas_pixels :: proc(t: ^testing.T) {
    invalid: [1]u8
    testing.expect(t, !build_native_dust_atlas(invalid[:]))
    pixels := make([]u8, DUST_ATLAS_PIXEL_BYTES, context.allocator)
    defer delete(pixels, context.allocator)
    testing.expect(t, build_native_dust_atlas(pixels))
    has_transparent: [DUST_ATLAS_VARIANT_COUNT]bool
    has_covered: [DUST_ATLAS_VARIANT_COUNT]bool
    has_fine_coverage := false
    for y in 0..<DUST_ATLAS_SIZE {
        for x in 0..<DUST_ATLAS_SIZE {
            offset := (y * DUST_ATLAS_SIZE + x) * 4
            testing.expect_value(t, pixels[offset], u8(255))
            testing.expect_value(t, pixels[offset + 1], u8(255))
            testing.expect_value(t, pixels[offset + 2], u8(255))
            alpha := pixels[offset + 3]
            variant := y / DUST_TEXTURE_SIZE * DUST_ATLAS_COLUMNS +
                x / DUST_TEXTURE_SIZE
            has_transparent[variant] ||= alpha == 0
            has_covered[variant] ||= alpha > 0
            has_fine_coverage ||= alpha > 0 && alpha < 255 &&
                alpha != 63 && alpha != 127 && alpha != 191
        }
    }
    for variant in 0..<DUST_ATLAS_VARIANT_COUNT {
        testing.expect(t, has_transparent[variant])
        testing.expect(t, has_covered[variant])
    }
    testing.expect(t, has_fine_coverage)
}

// Verify low-dust opacity preserves the lifetime fade and authored alpha contract.
@(test)
particles_test_low_dust_opacity :: proc(t: ^testing.T) {
    peak := f32(DUST_PEAK_ALPHA) / 255
    testing.expect_value(t, low_dust_opacity(-1, 255), peak)
    testing.expect_value(t, low_dust_opacity(0, 255), peak)
    testing.expect_value(t, low_dust_opacity(0.5, 255), f32(0.5) * peak)
    testing.expect_value(t, low_dust_opacity(1, 255), f32(0))
    testing.expect_value(t, low_dust_opacity(2, 255), f32(0))
    testing.expect_value(t, low_dust_opacity(0, 0), f32(0))
    testing.expect_value(t, low_dust_opacity(0, 127),
        peak * f32(127) / 255)
    testing.expect_value(t, low_dust_opacity(0.5, 127),
        f32(0.5) * peak * f32(127) / 255)
}
