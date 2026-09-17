package render_raylib

import renderresource "../resource"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

SHADER_RESOURCE_CAPACITY :: 8
TEXTURE_RESOURCE_CAPACITY :: 768
FONT_RESOURCE_CAPACITY :: 16
BUFFER_RESOURCE_CAPACITY :: 16
VERTEX_ARRAY_RESOURCE_CAPACITY :: 8

Shader_Slot :: struct {
    native: rl.Shader,
    generation: u32,
    occupied: bool,
}

Texture_Slot :: struct {
    native: rl.Texture2D,
    generation: u32,
    occupied: bool,
}

Font_Slot :: struct {
    native: rl.Font,
    generation: u32,
    occupied: bool,
}

Buffer_Slot :: struct {
    native: u32,
    generation: u32,
    occupied: bool,
}

Vertex_Array_Slot :: struct {
    native: u32,
    generation: u32,
    occupied: bool,
}

// Resource_Tables owns fixed display-thread storage for native GPU resources.
Resource_Tables :: struct {
    shaders: [SHADER_RESOURCE_CAPACITY]Shader_Slot,
    textures: [TEXTURE_RESOURCE_CAPACITY]Texture_Slot,
    fonts: [FONT_RESOURCE_CAPACITY]Font_Slot,
    buffers: [BUFFER_RESOURCE_CAPACITY]Buffer_Slot,
    vertex_arrays: [VERTEX_ARRAY_RESOURCE_CAPACITY]Vertex_Array_Slot,
    capacity_rejections: u64,
    stale_lookups: u64,
    double_releases: u64,
}

// Resource_Release_Result distinguishes successful release from invalid ownership.
Release_Result :: enum u8 {
    Released,
    Invalid,
    Stale,
}

// resource_tables_store_shader admits one valid shader into a free fixed slot.
resource_tables_store_shader :: proc(
    tables: ^Resource_Tables, native: rl.Shader) -> (renderresource.Shader_Handle, bool) {
    if tables == nil || native.id == 0 { return {}, false }
    for &slot, index in tables.shaders {
        if slot.occupied { continue }
        slot.generation = renderresource.resource_next_generation(slot.generation)
        slot.native = native
        slot.occupied = true
        identity := renderresource.Resource_Identity{u16(index), slot.generation}
        return renderresource.Shader_Handle(identity), true
    }
    tables.capacity_rejections += 1
    return {}, false
}

// resource_tables_resolve_shader borrows a native shader for one live generation.
resource_tables_resolve_shader :: proc(
    tables: ^Resource_Tables, handle: renderresource.Shader_Handle) -> (rl.Shader, bool) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.shaders) {
        return {}, false
    }
    slot := &tables.shaders[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.stale_lookups += 1
        return {}, false
    }
    return slot.native, true
}

// resource_tables_take_shader invalidates one live shader and returns its native value.
resource_tables_take_shader :: proc(
    tables: ^Resource_Tables, handle: renderresource.Shader_Handle) ->
    (rl.Shader, Release_Result) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.shaders) {
        return {}, .Invalid
    }
    slot := &tables.shaders[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.double_releases += 1
        return {}, .Stale
    }
    native := slot.native
    slot.native = {}
    slot.occupied = false
    return native, .Released
}

// resource_tables_store_texture admits one valid texture into a free fixed slot.
resource_tables_store_texture :: proc(
    tables: ^Resource_Tables, native: rl.Texture2D) ->
    (renderresource.Texture_Handle, bool) {
    if tables == nil || native.id == 0 { return {}, false }
    for &slot, index in tables.textures {
        if slot.occupied { continue }
        slot.generation = renderresource.resource_next_generation(slot.generation)
        slot.native = native
        slot.occupied = true
        identity := renderresource.Resource_Identity{u16(index), slot.generation}
        return renderresource.Texture_Handle(identity), true
    }
    tables.capacity_rejections += 1
    return {}, false
}

// resource_tables_resolve_texture borrows a native texture for one live generation.
resource_tables_resolve_texture :: proc(
    tables: ^Resource_Tables, handle: renderresource.Texture_Handle) ->
    (rl.Texture2D, bool) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.textures) {
        return {}, false
    }
    slot := &tables.textures[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.stale_lookups += 1
        return {}, false
    }
    return slot.native, true
}

// resource_tables_take_texture invalidates one live texture and returns its native value.
resource_tables_take_texture :: proc(
    tables: ^Resource_Tables, handle: renderresource.Texture_Handle) ->
    (rl.Texture2D, Release_Result) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.textures) {
        return {}, .Invalid
    }
    slot := &tables.textures[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.double_releases += 1
        return {}, .Stale
    }
    native := slot.native
    slot.native = {}
    slot.occupied = false
    return native, .Released
}

// resource_tables_store_font admits one valid Raylib font into a free fixed slot.
resource_tables_store_font :: proc(
    tables: ^Resource_Tables, native: rl.Font) -> (renderresource.Font_Handle, bool) {
    if tables == nil || native.texture.id == 0 { return {}, false }
    for &slot, index in tables.fonts {
        if slot.occupied { continue }
        slot.generation = renderresource.resource_next_generation(slot.generation)
        slot.native = native
        slot.occupied = true
        identity := renderresource.Resource_Identity{u16(index), slot.generation}
        return renderresource.Font_Handle(identity), true
    }
    tables.capacity_rejections += 1
    return {}, false
}

// resource_tables_resolve_font borrows a native font for one live generation.
resource_tables_resolve_font :: proc(
    tables: ^Resource_Tables, handle: renderresource.Font_Handle) -> (rl.Font, bool) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.fonts) {
        return {}, false
    }
    slot := &tables.fonts[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.stale_lookups += 1
        return {}, false
    }
    return slot.native, true
}

// resource_tables_take_font invalidates one live font and returns its native value.
resource_tables_take_font :: proc(
    tables: ^Resource_Tables, handle: renderresource.Font_Handle) ->
    (rl.Font, Release_Result) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.fonts) {
        return {}, .Invalid
    }
    slot := &tables.fonts[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.double_releases += 1
        return {}, .Stale
    }
    native := slot.native
    slot.native = {}
    slot.occupied = false
    return native, .Released
}

// resource_tables_store_buffer admits one nonzero rlgl buffer into a free fixed slot.
resource_tables_store_buffer :: proc(
    tables: ^Resource_Tables, native: u32) -> (renderresource.Buffer_Handle, bool) {
    if tables == nil || native == 0 { return {}, false }
    for &slot, index in tables.buffers {
        if slot.occupied { continue }
        slot.generation = renderresource.resource_next_generation(slot.generation)
        slot.native = native
        slot.occupied = true
        identity := renderresource.Resource_Identity{u16(index), slot.generation}
        return renderresource.Buffer_Handle(identity), true
    }
    tables.capacity_rejections += 1
    return {}, false
}

// resource_tables_resolve_buffer borrows one rlgl buffer for a live generation.
resource_tables_resolve_buffer :: proc(
    tables: ^Resource_Tables, handle: renderresource.Buffer_Handle) -> (u32, bool) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.buffers) {
        return 0, false
    }
    slot := &tables.buffers[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.stale_lookups += 1
        return 0, false
    }
    return slot.native, true
}

// resource_tables_take_buffer invalidates one live buffer and returns its rlgl ID.
resource_tables_take_buffer :: proc(
    tables: ^Resource_Tables, handle: renderresource.Buffer_Handle) ->
    (u32, Release_Result) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.buffers) {
        return 0, .Invalid
    }
    slot := &tables.buffers[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.double_releases += 1
        return 0, .Stale
    }
    native := slot.native
    slot.native = 0
    slot.occupied = false
    return native, .Released
}

// resource_tables_store_vertex_array admits one nonzero VAO into a free fixed slot.
resource_tables_store_vertex_array :: proc(
    tables: ^Resource_Tables, native: u32) ->
    (renderresource.Vertex_Array_Handle, bool) {
    if tables == nil || native == 0 { return {}, false }
    for &slot, index in tables.vertex_arrays {
        if slot.occupied { continue }
        slot.generation = renderresource.resource_next_generation(slot.generation)
        slot.native = native
        slot.occupied = true
        identity := renderresource.Resource_Identity{u16(index), slot.generation}
        return renderresource.Vertex_Array_Handle(identity), true
    }
    tables.capacity_rejections += 1
    return {}, false
}

// resource_tables_resolve_vertex_array borrows one VAO for a live generation.
resource_tables_resolve_vertex_array :: proc(
    tables: ^Resource_Tables, handle: renderresource.Vertex_Array_Handle) -> (u32, bool) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.vertex_arrays) {
        return 0, false
    }
    slot := &tables.vertex_arrays[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.stale_lookups += 1
        return 0, false
    }
    return slot.native, true
}

// resource_tables_take_vertex_array invalidates one live VAO and returns its ID.
resource_tables_take_vertex_array :: proc(
    tables: ^Resource_Tables, handle: renderresource.Vertex_Array_Handle) ->
    (u32, Release_Result) {
    identity := renderresource.Resource_Identity(handle)
    if tables == nil || !renderresource.resource_identity_valid(identity) ||
        int(identity.slot) >= len(tables.vertex_arrays) {
        return 0, .Invalid
    }
    slot := &tables.vertex_arrays[identity.slot]
    if !slot.occupied || slot.generation != identity.generation {
        tables.double_releases += 1
        return 0, .Stale
    }
    native := slot.native
    slot.native = 0
    slot.occupied = false
    return native, .Released
}

// resource_tables_release_shader destroys one live shader through Raylib.
resource_tables_release_shader :: proc(
    tables: ^Resource_Tables,
    handle: renderresource.Shader_Handle) -> Release_Result {
    native, result := resource_tables_take_shader(tables, handle)
    if result == .Released { rl.UnloadShader(native) }
    return result
}

// resource_tables_release_texture destroys one live texture through Raylib.
resource_tables_release_texture :: proc(
    tables: ^Resource_Tables,
    handle: renderresource.Texture_Handle) -> Release_Result {
    native, result := resource_tables_take_texture(tables, handle)
    if result == .Released { rl.UnloadTexture(native) }
    return result
}

// resource_tables_release_font destroys one live font through Raylib.
resource_tables_release_font :: proc(
    tables: ^Resource_Tables,
    handle: renderresource.Font_Handle) -> Release_Result {
    native, result := resource_tables_take_font(tables, handle)
    if result == .Released { rl.UnloadFont(native) }
    return result
}

// resource_tables_release_buffer destroys one live vertex buffer through rlgl.
resource_tables_release_buffer :: proc(
    tables: ^Resource_Tables,
    handle: renderresource.Buffer_Handle) -> Release_Result {
    native, result := resource_tables_take_buffer(tables, handle)
    if result == .Released { rlgl.UnloadVertexBuffer(native) }
    return result
}

// resource_tables_release_vertex_array destroys one live VAO through rlgl.
resource_tables_release_vertex_array :: proc(
    tables: ^Resource_Tables,
    handle: renderresource.Vertex_Array_Handle) -> Release_Result {
    native, result := resource_tables_take_vertex_array(tables, handle)
    if result == .Released { rlgl.UnloadVertexArray(native) }
    return result
}

// resource_tables_shutdown_arrays destroys every live rlgl array or buffer.
resource_tables_shutdown_arrays :: proc(tables: ^Resource_Tables) {
    for &slot in tables.vertex_arrays {
        if slot.occupied { rlgl.UnloadVertexArray(slot.native) }
        slot.native = 0
        slot.occupied = false
    }
    for &slot in tables.buffers {
        if slot.occupied { rlgl.UnloadVertexBuffer(slot.native) }
        slot.native = 0
        slot.occupied = false
    }
}

// resource_tables_shutdown_objects destroys every live Raylib object.
resource_tables_shutdown_objects :: proc(tables: ^Resource_Tables) {
    for &slot in tables.shaders {
        if slot.occupied { rl.UnloadShader(slot.native) }
        slot.native = {}
        slot.occupied = false
    }
    for &slot in tables.fonts {
        if slot.occupied { rl.UnloadFont(slot.native) }
        slot.native = {}
        slot.occupied = false
    }
    for &slot in tables.textures {
        if slot.occupied { rl.UnloadTexture(slot.native) }
        slot.native = {}
        slot.occupied = false
    }
}

// resource_tables_shutdown destroys every native object still owned by the tables.
resource_tables_shutdown :: proc(tables: ^Resource_Tables) {
    if tables == nil { return }
    resource_tables_shutdown_arrays(tables)
    resource_tables_shutdown_objects(tables)
}