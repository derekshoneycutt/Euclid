package native

import audio "../../audio"

import sdl "vendor:sdl3"

import "core:log"
import "core:strings"

SDL_CHALK_QUEUE_SECONDS :: 0.25

// Sdl_Chalk_Audio_Runtime owns one authored loop and its default-device stream.
Sdl_Chalk_Audio_Runtime :: struct {
    initialized: bool,
    audio_subsystem_owned: bool,
    stream: ^sdl.AudioStream,
    wav_spec: sdl.AudioSpec,
    wav_buffer: [^]u8,
    wav_length: u32,
    wav_cursor: u32,
    queue_target_bytes: int,
    stream_paused: bool,
}

// Return the low-latency queue watermark for one source format.
sdl_chalk_audio_queue_target :: proc(spec: sdl.AudioSpec) -> int {
    bytes_per_second := int(spec.freq) * int(sdl.AUDIO_FRAMESIZE(spec))
    return max(1, int(f64(bytes_per_second) * SDL_CHALK_QUEUE_SECONDS))
}

// Queue authored samples until the stream reaches its low-latency watermark.
sdl_chalk_audio_refill :: proc(runtime: ^Sdl_Chalk_Audio_Runtime) -> bool {
    if runtime == nil || runtime^.stream == nil || runtime^.wav_buffer == nil ||
        runtime^.wav_length == 0 {
        return false
    }
    queued := int(sdl.GetAudioStreamQueued(runtime^.stream))
    if queued < 0 {
        return false
    }
    for queued < runtime^.queue_target_bytes {
        requested := u32(runtime^.queue_target_bytes - queued)
        segment := audio.chalk_loop_segment(
            runtime^.wav_cursor, runtime^.wav_length, requested)
        if segment.count == 0 || !sdl.PutAudioStreamData(runtime^.stream,
            &runtime^.wav_buffer[segment.offset], i32(segment.count)) {
            return false
        }
        runtime^.wav_cursor = segment.next
        queued += int(segment.count)
    }
    return true
}

// Release a complete or partially admitted drawing-audio runtime.
sdl_chalk_audio_destroy :: proc(runtime: ^Sdl_Chalk_Audio_Runtime) {
    if runtime == nil {
        return
    }
    if runtime^.stream != nil {
        sdl.DestroyAudioStream(runtime^.stream)
    }
    if runtime^.wav_buffer != nil {
        sdl.free(runtime^.wav_buffer)
    }
    if runtime^.audio_subsystem_owned {
        sdl.QuitSubSystem({.AUDIO})
    }
    runtime^ = {}
}

// Load one seamless WAV and admit a paused callback-free playback stream.
sdl_chalk_audio_create :: proc(
    runtime: ^Sdl_Chalk_Audio_Runtime, texture_path: string) -> bool {
    if runtime == nil || runtime^.initialized {
        return runtime != nil && runtime^.initialized
    }
    if !sdl.InitSubSystem({.AUDIO}) {
        log.warnf("drawing_audio_unavailable phase=audio_subsystem error=%s", sdl.GetError())
        return false
    }
    runtime^.audio_subsystem_owned = true

    path := strings.clone_to_cstring(texture_path, context.temp_allocator)
    if !sdl.LoadWAV(path, &runtime^.wav_spec,
        &runtime^.wav_buffer, &runtime^.wav_length) || runtime^.wav_length == 0 {
        log.warnf("drawing_audio_unavailable phase=wav_load error=%s", sdl.GetError())
        sdl_chalk_audio_destroy(runtime)
        return false
    }
    runtime^.stream = sdl.OpenAudioDeviceStream(
        sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &runtime^.wav_spec, nil, nil)
    if runtime^.stream == nil {
        log.warnf("drawing_audio_unavailable phase=stream_open error=%s", sdl.GetError())
        sdl_chalk_audio_destroy(runtime)
        return false
    }

    runtime^.queue_target_bytes = sdl_chalk_audio_queue_target(runtime^.wav_spec)
    runtime^.stream_paused = true
    if !sdl.SetAudioStreamGain(runtime^.stream, 0) ||
        !sdl_chalk_audio_refill(runtime) {
        log.warnf("drawing_audio_unavailable phase=stream_seed error=%s", sdl.GetError())
        sdl_chalk_audio_destroy(runtime)
        return false
    }
    runtime^.initialized = true
    return true
}

// Service queueing and apply the display-independent policy envelope.
sdl_chalk_audio_update :: proc(
    native_runtime: ^Sdl_Chalk_Audio_Runtime,
    policy: ^audio.Chalk_Audio_Runtime,
    enabled, paused: bool, dt: f32) {
    if native_runtime == nil || !native_runtime^.initialized {
        return
    }
    gain := audio.update_chalk_policy(policy, enabled, paused, dt)
    should_sound := enabled && !paused && policy != nil && policy^.drawing_active
    if should_sound && native_runtime^.stream_paused {
        if !sdl.ResumeAudioStreamDevice(native_runtime^.stream) {
            log.warnf("drawing_audio_resume_failed error=%s", sdl.GetError())
            return
        }
        native_runtime^.stream_paused = false
    }
    if !sdl_chalk_audio_refill(native_runtime) {
        log.warnf("drawing_audio_queue_failed error=%s", sdl.GetError())
    }
    if !sdl.SetAudioStreamGain(native_runtime^.stream, gain) {
        log.warnf("drawing_audio_gain_failed error=%s", sdl.GetError())
        return
    }
    if !should_sound && gain == 0 && !native_runtime^.stream_paused {
        if sdl.PauseAudioStreamDevice(native_runtime^.stream) {
            native_runtime^.stream_paused = true
        } else {
            log.warnf("drawing_audio_pause_failed error=%s", sdl.GetError())
        }
    }
}