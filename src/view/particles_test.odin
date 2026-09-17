package view

import colormodel "../color/model"
import viewmodel "model"
import rendershader "render/shader"

import particlemodel "../particles/model"

import "core:testing"

// Verify the interleaved record matches the shader attribute stride and offsets.
@(test)
dust_instance_layout_matches_shader_attributes :: proc(t: ^testing.T) {
    instance: viewmodel.Dust_Instance
    base := uintptr(&instance)
    contract := rendershader.DUST_INSTANCED_CONTRACT
    geometry, geometry_ok := rendershader.attribute(&contract, .Instance_Geometry)
    color, color_ok := rendershader.attribute(&contract, .Color)
    variant, variant_ok := rendershader.attribute(&contract, .Instance_Variant)

    testing.expect(t, geometry_ok && color_ok && variant_ok)
    testing.expect_value(t, size_of(instance), int(geometry.stride_bytes))
    testing.expect_value(t, uintptr(&instance.screen_x) - base,
        uintptr(geometry.offset_bytes))
    testing.expect_value(t, uintptr(&instance.red) - base,
        uintptr(color.offset_bytes))
    testing.expect_value(t, uintptr(&instance.sprite_index) - base,
        uintptr(variant.offset_bytes))
}

// Verify cleanup planning and handle clearing support partially initialized state.
@(test)
dust_partial_instancing_resources_are_cleaned :: proc(t: ^testing.T) {
    dust_render := new(viewmodel.Dust_Render_State, context.allocator)
    defer free(dust_render)
    dust_render^ = {
        shader = {id = 7},
        quad_positions_vbo_id = 11,
        instance_vbo_id = 13,
        instancing_ready = true,
    }

    plan := dust_instancing_cleanup_plan(dust_render)
    testing.expect(t, plan.shader)
    testing.expect(t, plan.position_buffer)
    testing.expect(t, plan.instance_buffer)
    testing.expect(t, !plan.texcoord_buffer)
    testing.expect(t, !plan.vertex_array)

    clear_dust_instancing_resource_handles(dust_render)
    testing.expect_value(t, dust_render^.shader.id, u32(0))
    testing.expect_value(t, dust_render^.quad_positions_vbo_id, u32(0))
    testing.expect_value(t, dust_render^.instance_vbo_id, u32(0))
    testing.expect(t, !dust_render^.instancing_ready)
}

// Populate live, dead, faded, and clamped low-dust staging cases.
setup_low_particle_staging_fixture :: proc(particles: ^particlemodel.Particle_System) {
    particles^.use_max_dust_particles = 4
    particles^.low_particles.alive[0] = true
    particles^.low_particles.age[0] = 1
    particles^.low_particles.life[0] = 4
    particles^.low_particles.size[0] = 0.25
    particles^.low_particles.color[0] = colormodel.Color_RGBA8{255, 128, 0, 255}
    particles^.low_particles.dust_sprite_index[0] = 2
    particles^.low_particles.alive[2] = true
    particles^.low_particles.age[2] = 3
    particles^.low_particles.life[2] = 2
    particles^.low_particles.size[2] = 0.1
    particles^.low_particles.color[2] = colormodel.Color_RGBA8{0, 64, 255, 255}
    particles^.low_particles.dust_sprite_index[2] = 5
    particles^.low_particles.alive[3] = true
    particles^.low_particles.age[3] = -1
    particles^.low_particles.life[3] = 10
    particles^.low_particles.size[3] = 2
    particles^.low_particles.color[3] = colormodel.Color_RGBA8{17, 34, 51, 255}
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