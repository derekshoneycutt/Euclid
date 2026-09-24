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
