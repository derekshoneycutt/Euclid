package render_raylib

import renderresource "../resource"

import "core:testing"
import rl "vendor:raylib"

@(test)
// Shader slots reject overflow and invalidate stale generations after reuse.
shader_resource_capacity_and_staleness_are_enforced :: proc(t: ^testing.T) {
    tables: Resource_Tables
    handles: [SHADER_RESOURCE_CAPACITY]renderresource.Shader_Handle
    for index in 0..<SHADER_RESOURCE_CAPACITY {
        native := rl.Shader{id = u32(index + 1)}
        handle, stored := resource_tables_store_shader(&tables, native)
        testing.expect(t, stored)
        handles[index] = handle
    }
    _, overflow_stored := resource_tables_store_shader(&tables, rl.Shader{id = 100})
    testing.expect(t, !overflow_stored)
    testing.expect_value(t, tables.capacity_rejections, u64(1))

    native, released := resource_tables_take_shader(&tables, handles[0])
    testing.expect_value(t, released, Release_Result.Released)
    testing.expect_value(t, native.id, u32(1))
    replacement, stored := resource_tables_store_shader(&tables, rl.Shader{id = 101})
    testing.expect(t, stored)
    _, old_found := resource_tables_resolve_shader(&tables, handles[0])
    replacement_native, replacement_found :=
        resource_tables_resolve_shader(&tables, replacement)
    testing.expect(t, !old_found)
    testing.expect(t, replacement_found)
    testing.expect_value(t, replacement_native.id, u32(101))
}

@(test)
// Taking the same texture twice reports a stale double release without native calls.
texture_resource_double_release_is_rejected :: proc(t: ^testing.T) {
    tables: Resource_Tables
    handle, stored := resource_tables_store_texture(&tables, rl.Texture2D{id = 9})
    testing.expect(t, stored)
    native, first := resource_tables_take_texture(&tables, handle)
    testing.expect_value(t, first, Release_Result.Released)
    testing.expect_value(t, native.id, u32(9))
    _, second := resource_tables_take_texture(&tables, handle)
    testing.expect_value(t, second, Release_Result.Stale)
    testing.expect_value(t, tables.double_releases, u64(1))
}

@(test)
// Font slots expose a typed borrowing identity without leaking native ownership.
font_resources_are_generation_checked :: proc(t: ^testing.T) {
    tables: Resource_Tables
    native := rl.Font{baseSize = 32, texture = {id = 5, width = 16, height = 16}}
    handle, stored := resource_tables_store_font(&tables, native)
    testing.expect(t, stored)
    resolved, found := resource_tables_resolve_font(&tables, handle)
    testing.expect(t, found)
    testing.expect_value(t, resolved.baseSize, i32(32))
    _, released := resource_tables_take_font(&tables, handle)
    testing.expect_value(t, released, Release_Result.Released)
    _, stale := resource_tables_resolve_font(&tables, handle)
    testing.expect(t, !stale)
}

@(test)
// Buffer and vertex-array tables preserve type-specific generational lookup.
buffer_and_vertex_array_resources_are_typed :: proc(t: ^testing.T) {
    tables: Resource_Tables
    buffer, buffer_stored := resource_tables_store_buffer(&tables, 17)
    vertex_array, vertex_array_stored := resource_tables_store_vertex_array(&tables, 23)
    testing.expect(t, buffer_stored && vertex_array_stored)
    buffer_id, buffer_found := resource_tables_resolve_buffer(&tables, buffer)
    vertex_array_id, vertex_array_found :=
        resource_tables_resolve_vertex_array(&tables, vertex_array)
    testing.expect(t, buffer_found && vertex_array_found)
    testing.expect_value(t, buffer_id, u32(17))
    testing.expect_value(t, vertex_array_id, u32(23))
}