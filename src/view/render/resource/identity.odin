// Package renderresource owns backend-independent display resource identities.
package renderresource

// Resource_Identity names one generation of a fixed display resource slot.
Resource_Identity :: struct {
    slot: u16,
    generation: u32,
}

// Texture_Handle names one display-owned texture generation.
Texture_Handle :: distinct Resource_Identity

// Shader_Handle names one display-owned shader generation.
Shader_Handle :: distinct Resource_Identity

// Font_Handle names one display-owned Raylib font generation.
Font_Handle :: distinct Resource_Identity

// Buffer_Handle names one display-owned vertex buffer generation.
Buffer_Handle :: distinct Resource_Identity

// Vertex_Array_Handle names one display-owned vertex array generation.
Vertex_Array_Handle :: distinct Resource_Identity

// resource_identity_valid reports whether an identity can name a live slot.
resource_identity_valid :: proc(identity: Resource_Identity) -> bool {
    return identity.generation != 0
}

// resource_next_generation returns a nonzero generation after reuse or wrap.
resource_next_generation :: proc(generation: u32) -> u32 {
    if generation == max(u32) {
        return 1
    }
    return generation + 1
}

// texture_handle_valid reports whether a texture handle can name a live slot.
texture_handle_valid :: proc(handle: Texture_Handle) -> bool {
    return resource_identity_valid(Resource_Identity(handle))
}

// shader_handle_valid reports whether a shader handle can name a live slot.
shader_handle_valid :: proc(handle: Shader_Handle) -> bool {
    return resource_identity_valid(Resource_Identity(handle))
}

// font_handle_valid reports whether a font handle can name a live slot.
font_handle_valid :: proc(handle: Font_Handle) -> bool {
    return resource_identity_valid(Resource_Identity(handle))
}

// buffer_handle_valid reports whether a buffer handle can name a live slot.
buffer_handle_valid :: proc(handle: Buffer_Handle) -> bool {
    return resource_identity_valid(Resource_Identity(handle))
}

// vertex_array_handle_valid reports whether a vertex array can name a live slot.
vertex_array_handle_valid :: proc(handle: Vertex_Array_Handle) -> bool {
    return resource_identity_valid(Resource_Identity(handle))
}