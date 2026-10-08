package view

import font "font"
import native "native"
import core "../core"
import files "../files"
import log "core:log"
import world "world"

// Sdl_Font_Texture_Context binds font policy to display-owned native resources.
Sdl_Font_Texture_Context :: struct {
    platform: ^native.Sdl_Platform,
    runtime: ^native.Sdl_Draw_Runtime,
    submit_immediately: bool,
}

//   Run full app lifecycle loop: init state/window, fixed updates, frame draw, cleanup.
//
// Notes:
// Resolve packaged native shader artifacts for the display-owned 2D renderer.
sdl_draw_shader_paths :: proc() -> native.Sdl_Draw_Shader_Paths {
    return {
        colored_vertex = files.packaged_asset_path(
            "shaders/draw2d_colored.vert" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
        colored_fragment = files.packaged_asset_path(
            "shaders/draw2d_colored.frag" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
        textured_vertex = files.packaged_asset_path(
            "shaders/draw2d_textured.vert" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
        textured_fragment = files.packaged_asset_path(
            "shaders/draw2d_textured.frag" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
    }
}

// Resolve packaged native shaders for the optional geometry-tool pipeline.
sdl_stroke_shader_paths :: proc() -> native.Sdl_Stroke_Shader_Paths {
    return {
        vertex = files.packaged_asset_path(
            "shaders/stroke3d.vert" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
        fragment = files.packaged_asset_path(
            "shaders/stroke3d.frag" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
    }
}

// Resolve packaged native shaders for the optional instanced dust pipeline.
sdl_dust_shader_paths :: proc() -> native.Sdl_Dust_Shader_Paths {
    return {
        vertex = files.packaged_asset_path(
            "shaders/dust_instanced.vert" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
        fragment = files.packaged_asset_path(
            "shaders/dust_instanced.frag" + native.SDL_GPU_SHADER_SUFFIX,
            context.temp_allocator),
    }
}

// initialize_sdl_render_resources publishes required font and dust GPU resources.
initialize_sdl_render_resources :: proc(
    settings: ^core.Euclid_Run_Settings, state: ^core.Euclid_General_State,
    font_owner: ^Sdl_Font_Texture_Context,
    platform: ^native.Sdl_Platform, draw_runtime: ^native.Sdl_Draw_Runtime) -> bool {
    state^.ui_runtime.gpu_dust_instancing_available = draw_runtime^.dust_ready
    state^.ui_runtime.use_gpu_dust_instancing =
        settings^.use_gpu_dust_instancing && draw_runtime^.dust_ready
    if !initialize_sdl_font_resources(state, font_owner) {
        log.error("display_font_start_failed")
        return false
    }
    if !world.initialize_native_dust_atlas(platform, draw_runtime) {
        log.error("display_dust_atlas_start_failed")
        return false
    }
    return true
}

// Bind one display-local drawing-audio owner to a copied display context.
bind_sdl_chalk_audio :: proc(
    display: Display_Loop_Context, runtime: ^native.Sdl_Chalk_Audio_Runtime) ->
        Display_Loop_Context {
    drawing_audio_path := files.packaged_asset_path(
        "drawing-looped.wav", context.temp_allocator)
    _ = native.sdl_chalk_audio_create(runtime, drawing_audio_path)
    result := display
    result.chalk_audio = runtime
    return result
}

// Build the texture owner used while native render resources are admitted.
sdl_font_texture_context :: proc(display: Display_Loop_Context) ->
    Sdl_Font_Texture_Context {
    return {
        platform = display.platform,
        runtime = display.draw_runtime,
        submit_immediately = true,
    }
}

// run_sdl_platform_session owns draw, input, and Euclid state on one platform.
admit_optional_draw_pipelines :: proc(
    runtime: ^native.Sdl_Draw_Runtime, platform: ^native.Sdl_Platform) {
    if !native.sdl_stroke_runtime_admit(
        runtime, platform^.device, sdl_stroke_shader_paths(),
        platform^.sample_count) {
        log.warn("sdl_stroke_runtime_unavailable")
    }
    if !native.sdl_dust_runtime_admit(
        runtime, platform^.device, sdl_dust_shader_paths(),
        platform^.sample_count) {
        log.warn("sdl_dust_runtime_unavailable")
    }
}

// sdl_font_texture_create creates one display-owned atlas candidate.
sdl_font_texture_create :: proc(
    user_data: rawptr, width, height: u32) -> font.Font_Texture {
    owner := cast(^Sdl_Font_Texture_Context)user_data
    if owner == nil {
        return {}
    }
    texture := native.sdl_sampled_texture_create(owner.platform, width, height)
    return {
        texture.handle,
        texture.width,
        texture.height,
    }
}

// sdl_font_texture_upload queues one gray-alpha atlas upload.
sdl_font_texture_upload :: proc(
    user_data: rawptr, request: font.Font_Texture_Upload_Request) -> bool {
    owner := cast(^Sdl_Font_Texture_Context)user_data
    if owner == nil || owner.runtime == nil {
        return false
    }
    texture := request.texture
    sampled := native.Sampled_Texture{texture.handle, texture.width, texture.height}
    queued := native.texture_operation_enqueue_upload(
        &owner.runtime^.texture_operations, {
            kind = .Create,
            texture = sampled,
            format = .Gray_Alpha8,
            source = request.pixels,
            identity = request.identity,
            generation = request.generation,
            callback = {
                native.Texture_Operation_Completion(request.completion),
                request.completion_data,
            },
        })
    if !queued || !owner.submit_immediately {
        return queued
    }
    return native.sdl_draw_submit_texture_operations(
        owner.platform, owner.runtime)
}

// sdl_font_texture_release releases one resident display-owned atlas.
sdl_font_texture_release :: proc(
    user_data: rawptr, texture: font.Font_Texture) {
    owner := cast(^Sdl_Font_Texture_Context)user_data
    if owner == nil {
        return
    }
    sampled := native.Sampled_Texture{
        texture.handle,
        texture.width,
        texture.height,
    }
    native.sdl_sampled_texture_release(owner.platform, &sampled)
}

// sdl_font_texture_operations exposes the native atlas lifecycle to font policy.
sdl_font_texture_operations :: proc(
    owner: ^Sdl_Font_Texture_Context) -> font.Font_Texture_Operations {
    return {
        user_data = owner,
        create = sdl_font_texture_create,
        upload = sdl_font_texture_upload,
        release = sdl_font_texture_release,
    }
}

// initialize_sdl_font_resources admits required atlases and shaping state.
initialize_sdl_font_resources :: proc(
    state: ^core.Euclid_General_State, owner: ^Sdl_Font_Texture_Context) -> bool {
    if state == nil || owner == nil {
        return false
    }
    if !font.cache_init(
        &state^.font_cache, sdl_font_texture_operations(owner)) {
        return false
    }
    if !font.math_shaping_sync(
        &state^.font_cache, &state^.dynview.math_shaping) {
        font.cache_destroy(&state^.font_cache)
        return false
    }
    _ = font.cache_request(&state^.font_cache, .Bold)
    _ = font.cache_request(&state^.font_cache, .Regular_Italic)
    return true
}
