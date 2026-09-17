package renderresource

import "core:testing"

@(test)
// Zero-value typed display resource handles are invalid.
zero_value_resource_handles_are_invalid :: proc(t: ^testing.T) {
    testing.expect(t, !texture_handle_valid({}))
    testing.expect(t, !shader_handle_valid({}))
    testing.expect(t, !font_handle_valid({}))
    testing.expect(t, !buffer_handle_valid({}))
    testing.expect(t, !vertex_array_handle_valid({}))
}

@(test)
// Each typed handle accepts the same nonzero generational identity.
typed_resource_handles_accept_live_identity :: proc(t: ^testing.T) {
    identity := Resource_Identity{slot = 3, generation = 7}
    testing.expect(t, texture_handle_valid(Texture_Handle(identity)))
    testing.expect(t, shader_handle_valid(Shader_Handle(identity)))
    testing.expect(t, font_handle_valid(Font_Handle(identity)))
    testing.expect(t, buffer_handle_valid(Buffer_Handle(identity)))
    testing.expect(t, vertex_array_handle_valid(Vertex_Array_Handle(identity)))
}

@(test)
// Resource generations skip the reserved invalid generation after wrap.
resource_generation_never_returns_zero :: proc(t: ^testing.T) {
    testing.expect_value(t, resource_next_generation(0), u32(1))
    testing.expect_value(t, resource_next_generation(41), u32(42))
    testing.expect_value(t, resource_next_generation(max(u32)), u32(1))
}