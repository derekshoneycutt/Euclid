#+build linux
#+test

package native

import "core:testing"

// Sdl_Contrast_Test_Variant models borrowed GVariant shape without native allocations.
Sdl_Contrast_Test_Variant :: struct {
    type_name: cstring,
    child: rawptr,
    value: u32,
    extractions: int,
    releases: int,
}

// sdl_contrast_test_variant_type exposes only the injected variant's type.
sdl_contrast_test_variant_type :: proc "c" (value: rawptr) -> cstring {
    variant := cast(^Sdl_Contrast_Test_Variant)value
    return variant^.type_name
}

// sdl_contrast_test_variant_child records extraction after a validated container.
sdl_contrast_test_variant_child :: proc "c" (
    value: rawptr, _: uintptr) -> rawptr {
    variant := cast(^Sdl_Contrast_Test_Variant)value
    variant^.extractions += 1
    return variant^.child
}

// sdl_contrast_test_variant_unwrap records extraction of the variant payload.
sdl_contrast_test_variant_unwrap :: proc "c" (value: rawptr) -> rawptr {
    variant := cast(^Sdl_Contrast_Test_Variant)value
    variant^.extractions += 1
    return variant^.child
}

// sdl_contrast_test_variant_uint32 supplies a payload only after type validation.
sdl_contrast_test_variant_uint32 :: proc "c" (value: rawptr) -> u32 {
    variant := cast(^Sdl_Contrast_Test_Variant)value
    variant^.extractions += 1
    return variant^.value
}

// sdl_contrast_test_variant_unref observes release of extracted owned references.
sdl_contrast_test_variant_unref :: proc "c" (value: rawptr) {
    variant := cast(^Sdl_Contrast_Test_Variant)value
    variant^.releases += 1
}

// sdl_contrast_test_decode_symbols provides an allocation-free response seam.
sdl_contrast_test_decode_symbols :: proc() -> Sdl_Contrast_Gio {
    return {
        g_variant_get_type_string = sdl_contrast_test_variant_type,
        g_variant_get_child_value = sdl_contrast_test_variant_child,
        g_variant_get_variant = sdl_contrast_test_variant_unwrap,
        g_variant_get_uint32 = sdl_contrast_test_variant_uint32,
        g_variant_unref = sdl_contrast_test_variant_unref,
    }
}

// Portal uint32 policy distinguishes higher contrast from normal and unknown values.
@(test)
sdl_contrast_portal_decodes_standard_and_unknown_values :: proc(t: ^testing.T) {
    gio := sdl_contrast_test_decode_symbols()
    values: [4]u32 = {0, 1, 2, 0xffff_ffff}
    for value in values {
        payload: Sdl_Contrast_Test_Variant = {
            type_name = "u",
            value = value,
        }
        wrapper: Sdl_Contrast_Test_Variant = {
            type_name = "v",
            child = &payload,
        }
        reply: Sdl_Contrast_Test_Variant = {
            type_name = "(v)",
            child = &wrapper,
        }
        requested, status := sdl_contrast_portal_decode_reply(gio, &reply)
        testing.expect_value(t, status, Sdl_Contrast_Status.Supported)
        testing.expect_value(t, requested, value == 1)
        testing.expect_value(t, wrapper.releases, 1)
        testing.expect_value(t, payload.releases, 1)
    }
}

// Invalid tuple and payload shapes fail without invoking unsafe GVariant getters.
@(test)
sdl_contrast_portal_rejects_malformed_response :: proc(t: ^testing.T) {
    gio := sdl_contrast_test_decode_symbols()
    payload: Sdl_Contrast_Test_Variant = {
        type_name = "s",
    }
    wrapper: Sdl_Contrast_Test_Variant = {
        type_name = "v",
        child = &payload,
    }
    reply: Sdl_Contrast_Test_Variant = {
        type_name = "()",
        child = &wrapper,
    }
    _, status := sdl_contrast_portal_decode_reply(gio, &reply)
    testing.expect_value(t, status, Sdl_Contrast_Status.Failed)
    testing.expect_value(t, reply.extractions, 0)
    reply.type_name = "(v)"
    _, status = sdl_contrast_portal_decode_reply(gio, &reply)
    testing.expect_value(t, status, Sdl_Contrast_Status.Failed)
    testing.expect_value(t, payload.extractions, 0)
    testing.expect_value(t, wrapper.releases, 1)
    testing.expect_value(t, payload.releases, 1)
    wrapper.child = nil
    _, status = sdl_contrast_portal_decode_reply(gio, &reply)
    testing.expect_value(t, status, Sdl_Contrast_Status.Failed)
    testing.expect_value(t, wrapper.releases, 2)
    _, status = sdl_contrast_portal_decode_reply(gio, nil)
    testing.expect_value(t, status, Sdl_Contrast_Status.Failed)
}
