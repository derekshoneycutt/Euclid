package view

import viewmodel "model"

import particlemodel "../particles/model"
import color "../core/color"

import "core:c"
import "core:testing"

import rl "vendor:raylib"

// Dust_Instancing_Test_State controls staged allocation failure and records cleanup.
Dust_Instancing_Test_State :: struct {
    missing_name: string,
    vao_id: u32,
    enable_vao_succeeds: bool,
    fail_vbo_call: int,
    load_vbo_count: int,
    disable_vao_count: int,
    unloaded_vbos: [3]u32,
    unloaded_vbo_count: int,
    unloaded_vao: u32,
    unloaded_shader: u32,
    attribute_locations: [5]u32,
    attribute_components: [5]u32,
    attribute_strides: [5]int,
    attribute_offsets: [5]int,
    attribute_count: int,
}

// Dust_Texture_Test_State controls texture validity and records native releases.
Dust_Texture_Test_State :: struct {
    loaded_texture: rl.Texture2D,
    texture_valid: bool,
    unloaded_image_count: int,
    unloaded_texture_id: u32,
}

// Verify the interleaved record matches the shader attribute stride and offsets.
@(test)
dust_instance_layout_matches_shader_attributes :: proc(t: ^testing.T) {
    instance: viewmodel.Dust_Instance
    base := uintptr(&instance)

    testing.expect_value(t, size_of(instance), 8 * size_of(f32))
    testing.expect_value(t, uintptr(&instance.screen_x) - base,
        uintptr(DUST_INSTANCE_GEOMETRY_OFFSET))
    testing.expect_value(t, uintptr(&instance.red) - base,
        uintptr(DUST_INSTANCE_COLOR_OFFSET))
    testing.expect_value(t, uintptr(&instance.sprite_index) - base,
        uintptr(DUST_INSTANCE_VARIANT_OFFSET))
}

// Return the configured texture candidate without entering Raylib.
dust_texture_test_load :: proc(
    user_data: rawptr, _: rl.Image) -> rl.Texture2D {
    return (^Dust_Texture_Test_State)(user_data)^.loaded_texture
}

// Return the configured texture validation result.
dust_texture_test_valid :: proc(
    user_data: rawptr, _: rl.Texture2D) -> bool {
    return (^Dust_Texture_Test_State)(user_data)^.texture_valid
}

// Record CPU image release without entering Raylib.
dust_texture_test_unload_image :: proc(user_data: rawptr, _: rl.Image) {
    state := (^Dust_Texture_Test_State)(user_data)
    state^.unloaded_image_count += 1
}

// Record texture release without entering Raylib.
dust_texture_test_unload_texture :: proc(
    user_data: rawptr, texture: rl.Texture2D) {
    state := (^Dust_Texture_Test_State)(user_data)
    state^.unloaded_texture_id = texture.id
}

// Build deterministic native operations for dust atlas tests.
dust_texture_test_operations :: proc(
    state: ^Dust_Texture_Test_State) -> Dust_Texture_Operations {
    return {
        user_data = rawptr(state),
        load = dust_texture_test_load,
        valid = dust_texture_test_valid,
        unload_image = dust_texture_test_unload_image,
        unload_texture = dust_texture_test_unload_texture,
    }
}

// Return a valid location except for the configured missing uniform.
dust_test_get_location :: proc(
    user_data: rawptr, _: rl.Shader, name: cstring) -> i32 {
    state := (^Dust_Instancing_Test_State)(user_data)
    if string(name) == state^.missing_name {
        return -1
    }
    return 1
}

// Record shader release without entering Raylib.
dust_test_unload_shader :: proc(user_data: rawptr, shader: rl.Shader) {
    state := (^Dust_Instancing_Test_State)(user_data)
    state^.unloaded_shader = shader.id
}

// Return one deterministic VAO identity.
dust_test_load_vao :: proc(user_data: rawptr) -> u32 {
    state := (^Dust_Instancing_Test_State)(user_data)
    return state^.vao_id
}

// Accept the deterministic test VAO.
dust_test_enable_vao :: proc(user_data: rawptr, _: u32) -> bool {
    state := (^Dust_Instancing_Test_State)(user_data)
    return state^.enable_vao_succeeds
}

// Record restoration of the prior VAO binding state.
dust_test_disable_vao :: proc(user_data: rawptr) {
    state := (^Dust_Instancing_Test_State)(user_data)
    state^.disable_vao_count += 1
}

// Record VAO release without entering rlgl.
dust_test_unload_vao :: proc(user_data: rawptr, id: u32) {
    state := (^Dust_Instancing_Test_State)(user_data)
    state^.unloaded_vao = id
}

// Return sequential VBO identities except at the configured failure call.
dust_test_load_vbo :: proc(
    user_data: rawptr, _: rawptr, _: c.int, _: bool) -> u32 {
    state := (^Dust_Instancing_Test_State)(user_data)
    state^.load_vbo_count += 1
    if state^.load_vbo_count == state^.fail_vbo_call {
        return 0
    }
    return u32(20 + state^.load_vbo_count)
}

// Record reverse-order VBO release without entering rlgl.
dust_test_unload_vbo :: proc(user_data: rawptr, id: u32) {
    state := (^Dust_Instancing_Test_State)(user_data)
    state^.unloaded_vbos[state^.unloaded_vbo_count] = id
    state^.unloaded_vbo_count += 1
}

// Record attribute configuration without entering rlgl.
dust_test_configure_attribute :: proc(
    user_data: rawptr, location, components: u32, stride, offset: int) {
    state := (^Dust_Instancing_Test_State)(user_data)
    index := state^.attribute_count
    state^.attribute_locations[index] = location
    state^.attribute_components[index] = components
    state^.attribute_strides[index] = stride
    state^.attribute_offsets[index] = offset
    state^.attribute_count += 1
}

// Build deterministic native operations for dust resource tests.
dust_test_operations :: proc(
    state: ^Dust_Instancing_Test_State) -> Dust_Instancing_Operations {
    return {
        user_data = rawptr(state),
        get_location = dust_test_get_location,
        unload_shader = dust_test_unload_shader,
        load_vao = dust_test_load_vao,
        enable_vao = dust_test_enable_vao,
        disable_vao = dust_test_disable_vao,
        unload_vao = dust_test_unload_vao,
        load_vbo = dust_test_load_vbo,
        unload_vbo = dust_test_unload_vbo,
        configure_attribute = dust_test_configure_attribute,
    }
}

// Verify an instance-buffer failure restores binding and releases prior resources.
@(test)
dust_instancing_partial_failure_releases_in_reverse_order :: proc(t: ^testing.T) {
    test_state := Dust_Instancing_Test_State{
        vao_id = 10, enable_vao_succeeds = true, fail_vbo_call = 3}
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)
    render_state^.shader = {id = 7}
    operations := dust_test_operations(&test_state)

    testing.expect(t, !load_dust_instancing_buffers(render_state, operations))
    testing.expect_value(t, test_state.disable_vao_count, 1)
    release_dust_instancing_resources(render_state, operations)

    testing.expect_value(t, test_state.unloaded_vbo_count, 2)
    testing.expect_value(t, test_state.unloaded_vbos[0], u32(22))
    testing.expect_value(t, test_state.unloaded_vbos[1], u32(21))
    testing.expect_value(t, test_state.unloaded_vao, u32(10))
    testing.expect_value(t, test_state.unloaded_shader, u32(7))

    release_dust_instancing_resources(render_state, operations)
    testing.expect_value(t, test_state.unloaded_vbo_count, 2)
}

// Verify missing dust uniforms reject the loaded shader before publication.
@(test)
dust_shader_admission_rejects_missing_uniform :: proc(t: ^testing.T) {
    test_state := Dust_Instancing_Test_State{missing_name = "uViewport"}
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)
    render_state^.shader = {id = 9}

    testing.expect(t,
        !dust_instancing_uniforms_valid(render_state, dust_test_operations(&test_state)))
}

// Verify VAO creation and enablement failures do not create vertex buffers.
@(test)
dust_instancing_rejects_invalid_vertex_array :: proc(t: ^testing.T) {
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)

    no_vao: Dust_Instancing_Test_State
    testing.expect(t,
        !load_dust_instancing_buffers(render_state, dust_test_operations(&no_vao)))
    testing.expect_value(t, no_vao.load_vbo_count, 0)

    disabled := Dust_Instancing_Test_State{vao_id = 10}
    testing.expect(t,
        !load_dust_instancing_buffers(render_state, dust_test_operations(&disabled)))
    testing.expect_value(t, disabled.load_vbo_count, 0)
}

// Verify each failed VBO stage stops before configuring invalid buffer state.
@(test)
dust_instancing_stops_at_each_failed_vertex_buffer :: proc(t: ^testing.T) {
    for failed_call in 1..=3 {
        test_state := Dust_Instancing_Test_State{
            vao_id = 10, enable_vao_succeeds = true, fail_vbo_call = failed_call}
        render_state := new(viewmodel.Dust_Render_State, context.allocator)
        defer free(render_state)

        operations := dust_test_operations(&test_state)
        testing.expect(t, !load_dust_instancing_buffers(render_state, operations))
        testing.expect_value(t, test_state.load_vbo_count, failed_call)
        expected_attributes := failed_call == 1 ? 0 : failed_call - 1
        testing.expect_value(t, test_state.attribute_count, expected_attributes)
    }
}

// Verify successful setup configures the complete static and instance ABI.
@(test)
dust_instancing_configures_complete_attribute_contract :: proc(t: ^testing.T) {
    test_state := Dust_Instancing_Test_State{
        vao_id = 10, enable_vao_succeeds = true}
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)

    testing.expect(t,
        load_dust_instancing_buffers(render_state, dust_test_operations(&test_state)))
    testing.expect_value(t, test_state.attribute_locations,
        [5]u32{0, 1, 2, 3, 4})
    testing.expect_value(t, test_state.attribute_components,
        [5]u32{2, 2, 3, 4, 1})
    stride := int(size_of(viewmodel.Dust_Instance))
    testing.expect_value(t, test_state.attribute_strides,
        [5]int{0, 0, stride, stride, stride})
    testing.expect_value(t, test_state.attribute_offsets,
        [5]int{0, 0, 0, DUST_INSTANCE_COLOR_OFFSET,
            DUST_INSTANCE_VARIANT_OFFSET})
}

// Verify dust draw-path selection requires both policy and complete resources.
@(test)
dust_instancing_selection_requires_enabled_and_ready :: proc(t: ^testing.T) {
    testing.expect(t, dust_instancing_selected(true, true))
    testing.expect(t, !dust_instancing_selected(true, false))
    testing.expect(t, !dust_instancing_selected(false, true))
}

// Verify failed atlas upload releases both the CPU image and partial texture.
@(test)
dust_texture_failure_releases_partial_resources :: proc(t: ^testing.T) {
    test_state := Dust_Texture_Test_State{
        loaded_texture = {id = 81}, texture_valid = false}
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)
    pixel: u8
    image := rl.Image{data = rawptr(&pixel)}

    testing.expect(t, !publish_dust_texture(
        render_state, image, dust_texture_test_operations(&test_state)))
    testing.expect(t, !render_state.ready)
    testing.expect_value(t, render_state.texture.id, u32(0))
    testing.expect_value(t, test_state.unloaded_image_count, 1)
    testing.expect_value(t, test_state.unloaded_texture_id, u32(81))
}

// Verify successful atlas upload publishes until idempotent handle-based release.
@(test)
dust_texture_success_publishes_and_releases_once :: proc(t: ^testing.T) {
    test_state := Dust_Texture_Test_State{
        loaded_texture = {id = 92}, texture_valid = true}
    render_state := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(render_state)
    pixel: u8
    operations := dust_texture_test_operations(&test_state)

    testing.expect(t, publish_dust_texture(
        render_state, rl.Image{data = rawptr(&pixel)}, operations))
    testing.expect(t, render_state.ready)
    testing.expect_value(t, test_state.unloaded_image_count, 1)

    release_dust_texture(render_state, operations)
    release_dust_texture(render_state, operations)
    testing.expect_value(t, test_state.unloaded_texture_id, u32(92))
}

// Populate live, dead, faded, and clamped low-dust staging cases.
setup_low_particle_staging_fixture :: proc(particles: ^particlemodel.Particle_System) {
    particles^.use_max_dust_particles = 4
    particles^.low_particles.alive[0] = true
    particles^.low_particles.age[0] = 1
    particles^.low_particles.life[0] = 4
    particles^.low_particles.size[0] = 0.25
    particles^.low_particles.color[0] = color.Color_RGBA8{255, 128, 0, 255}
    particles^.low_particles.dust_sprite_index[0] = 2
    particles^.low_particles.alive[2] = true
    particles^.low_particles.age[2] = 3
    particles^.low_particles.life[2] = 2
    particles^.low_particles.size[2] = 0.1
    particles^.low_particles.color[2] = color.Color_RGBA8{0, 64, 255, 255}
    particles^.low_particles.dust_sprite_index[2] = 5
    particles^.low_particles.alive[3] = true
    particles^.low_particles.age[3] = -1
    particles^.low_particles.life[3] = 10
    particles^.low_particles.size[3] = 2
    particles^.low_particles.color[3] = color.Color_RGBA8{17, 34, 51, 255}
    particles^.low_particles.dust_sprite_index[3] = 8
}

// Verify staging compacts live slots without changing per-instance values or order.
@(test)
stage_low_particle_instances_interleaves_live_slots :: proc(t: ^testing.T) {
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles)
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    setup_low_particle_staging_fixture(particles)
    screens := [4]Vector2{{10, 20}, {30, 40}, {50, 60}, {70, 80}}

    count := stage_low_particle_instances(particles, state, screens[:])

    testing.expect_value(t, count, 3)
    testing.expect_value(t, state^.dust_render.instances[0], viewmodel.Dust_Instance{
        screen_x = 10, screen_y = 20, diameter = 1,
        red = 1, green = f32(128) / 255, blue = 0,
        alpha = f32(0.75 * 210.0 / 255.0), sprite_index = 2})
    testing.expect_value(t, state^.dust_render.instances[1], viewmodel.Dust_Instance{
        screen_x = 50, screen_y = 60, diameter = 1,
        red = 0, green = f32(64) / 255, blue = 1,
        alpha = 0, sprite_index = 5})
    testing.expect_value(t, state^.dust_render.instances[2], viewmodel.Dust_Instance{
        screen_x = 70, screen_y = 80, diameter = 4,
        red = f32(17) / 255, green = f32(34) / 255, blue = f32(51) / 255,
        alpha = f32(210) / 255, sprite_index = 8})
}