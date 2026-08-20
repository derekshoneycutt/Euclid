package audio

import "../core"

import "core:math/rand"
import "core:strings"

import rl "vendor:raylib"

CHALK_SAMPLE_RATE :: 44100
CHALK_BUFFER_SIZE :: 512
CHALK_MAX_BUFFERS_PER_FRAME :: 8
CHALK_DRAW_GAIN :: 1.4
CHALK_HIT_GAIN :: 1.0
CHALK_DRAW_ATTACK :: 0.035
CHALK_DRAW_RELEASE :: 0.008

// Keep lower and upper turnarounds in separate portions of the steady scrape.
// Choosing a new point after each pass varies the traversal length without
// jumping between unrelated samples in the middle of a pass.
CHALK_LOWER_TURN_MIN_PERCENT :: 24
CHALK_LOWER_TURN_MAX_PERCENT :: 40
CHALK_UPPER_TURN_MIN_PERCENT :: 54
CHALK_UPPER_TURN_MAX_PERCENT :: 78
CHALK_TURN_SEARCH_SAMPLES :: 512
CHALK_HIT_DURATION_SAMPLES :: 6174

Chalk_Audio_Runtime :: core.Chalk_Audio_Runtime
Vector3 :: core.Vector3

//   Choose a quiet sample near a random point in one turnaround band.
//
// Notes:
//   - Reversing close to a zero crossing reduces the click at the direction
//     change while preserving continuous, adjacent playback within each pass.
choose_chalk_turnaround :: proc(
    runtime: ^Chalk_Audio_Runtime, minimum_percent, maximum_percent: int) -> int {
    minimum := runtime^.texture_sample_count * minimum_percent / 100
    maximum := runtime^.texture_sample_count * maximum_percent / 100
    candidate := rand.int_range(minimum, maximum - CHALK_TURN_SEARCH_SAMPLES)
    best := candidate
    best_magnitude := runtime^.texture_samples[best]
    if best_magnitude < 0 {
        best_magnitude = -best_magnitude
    }

    for index in candidate + 1..<candidate + CHALK_TURN_SEARCH_SAMPLES {
        magnitude := runtime^.texture_samples[index]
        if magnitude < 0 {
            magnitude = -magnitude
        }
        if magnitude < best_magnitude {
            best = index
            best_magnitude = magnitude
        }
    }
    return best
}

//   Load the chalk reference, initialize its stream, and start playback.
//
// Notes:
//   - Raylib converts the source to mono 44.1 kHz samples owned by the runtime.
//   - Dragging traverses the steady center in alternating directions, while the
//     beginning of the recording remains available as a one-shot contact hit.
init_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime, texture_path: string) {
    if runtime^.initialized {
        return
    }

    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)
    texture_wave := rl.LoadWave(texture_file)
    if texture_wave.data != nil {
        rl.WaveFormat(&texture_wave, CHALK_SAMPLE_RATE, 32, 1)
        runtime^.texture_samples = rl.LoadWaveSamples(texture_wave)
        runtime^.texture_sample_count = int(texture_wave.frameCount)
        runtime^.texture_lower_turn = choose_chalk_turnaround(
            runtime, CHALK_LOWER_TURN_MIN_PERCENT, CHALK_LOWER_TURN_MAX_PERCENT)
        runtime^.texture_upper_turn = choose_chalk_turnaround(
            runtime, CHALK_UPPER_TURN_MIN_PERCENT, CHALK_UPPER_TURN_MAX_PERCENT)
        runtime^.texture_cursor = runtime^.texture_lower_turn
        runtime^.texture_direction = 1
        rl.UnloadWave(texture_wave)
    }

    rl.SetAudioStreamBufferSizeDefault(CHALK_BUFFER_SIZE)
    runtime^.stream = rl.LoadAudioStream(CHALK_SAMPLE_RATE, 32, 1)
    rl.PlayAudioStream(runtime^.stream)
    runtime^.initialized = true
}

//   Tear down the chalk stream and clear its initialized state.
//
// Notes:
//   - Unloading the stream makes the runtime safe to restart later without
//     leaving an active audio handle behind.
//   - Wave samples returned by Raylib have independent ownership and must be
//     released separately from the audio stream.
shutdown_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }

    if runtime^.texture_samples != nil {
        rl.UnloadWaveSamples(runtime^.texture_samples)
        runtime^.texture_samples = nil
    }
    rl.UnloadAudioStream(runtime^.stream)
    runtime^.initialized = false
}

//   Record whether the pen tip is touching the drawing plane.
//
// Notes:
//   - Contact gates a steady chalk texture; movement speed does not affect it.
register_pen_tip_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    _ = pos
    _ = dt
    register_tip_contact(runtime, is_floor_contact)
}

//   Record whether the first compass tip is touching the drawing plane.
//
// Notes:
//   - Either compass tip can sustain the shared chalk texture.
register_compass_tip1_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    _ = pos
    _ = dt
    register_tip_contact(runtime, is_floor_contact)
}

//   Record whether the second compass tip is touching the drawing plane.
//
// Notes:
//   - Either compass tip can sustain the shared chalk texture.
register_compass_tip2_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    _ = pos
    _ = dt
    register_tip_contact(runtime, is_floor_contact)
}

//   Start the reference recording's chalk-contact transient.
//
// Notes:
//   - Re-triggering restarts the transient from the beginning of the clip.
trigger_hit_sound :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized || runtime^.texture_samples == nil {
        return
    }

    runtime^.hit_sample_cursor = 0
    runtime^.hit_active = true
}

//   Mark drawing contact for the current frame.
//
// Notes:
//   - Any active tool tip sustains the same reference-calibrated texture.
register_tip_contact :: #force_inline proc(
    runtime: ^Chalk_Audio_Runtime, is_floor_contact: bool) {
    if !runtime^.initialized {
        return
    }

    if is_floor_contact {
        runtime^.has_contact_this_frame = true
    }
}

//   Read the next adjacent drag sample and advance the wandering playback head.
//
// Notes:
//   - The head reverses at each boundary instead of wrapping, avoiding an
//     end-to-start waveform splice.
//   - Each completed pass chooses the opposite boundary again, making the next
//     traversal a different length without introducing a mid-stream jump.
advance_chalk_texture :: #force_inline proc(runtime: ^Chalk_Audio_Runtime) -> f32 {
    if runtime^.texture_samples == nil {
        return 0
    }

    sample := runtime^.texture_samples[runtime^.texture_cursor]
    runtime^.texture_cursor += runtime^.texture_direction
    if runtime^.texture_cursor >= runtime^.texture_upper_turn {
        runtime^.texture_cursor = runtime^.texture_upper_turn - 1
        runtime^.texture_direction = -1
        runtime^.texture_lower_turn = choose_chalk_turnaround(
            runtime, CHALK_LOWER_TURN_MIN_PERCENT, CHALK_LOWER_TURN_MAX_PERCENT)
    } else if runtime^.texture_cursor <= runtime^.texture_lower_turn {
        runtime^.texture_cursor = runtime^.texture_lower_turn + 1
        runtime^.texture_direction = 1
        runtime^.texture_upper_turn = choose_chalk_turnaround(
            runtime, CHALK_UPPER_TURN_MIN_PERCENT, CHALK_UPPER_TURN_MAX_PERCENT)
    }
    return sample
}

//   Read the next sample from the recording's contact transient.
//
// Notes:
//   - Hit playback is independent of the sustained drag head and stops before
//     reaching the portion used for the continuous scrape.
advance_chalk_hit :: #force_inline proc(runtime: ^Chalk_Audio_Runtime) -> f32 {
    if !runtime^.hit_active || runtime^.texture_samples == nil {
        return 0
    }

    sample := runtime^.texture_samples[runtime^.hit_sample_cursor]
    runtime^.hit_sample_cursor += 1
    if runtime^.hit_sample_cursor >= CHALK_HIT_DURATION_SAMPLES ||
        runtime^.hit_sample_cursor >= runtime^.texture_sample_count {
        runtime^.hit_active = false
    }
    return sample * CHALK_HIT_GAIN
}

//   Drain processed audio buffers and write the next chalk synth frame.
//
// Notes:
//   - Contact gates continuous playback of the reference's stable center.
//   - Separate attack and release smoothing suppress clicks when contact starts
//     or ends; hit samples are mixed independently so a tap remains audible.
update_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }
    processed_count := 0
    for rl.IsAudioStreamProcessed(runtime^.stream) {
        target_draw_level: f32 = 0
        if runtime^.has_contact_this_frame {
            target_draw_level = CHALK_DRAW_GAIN
        }

        for i := 0; i < CHALK_BUFFER_SIZE; i += 1 {
            texture_sample := advance_chalk_texture(runtime)

            draw_alpha: f32 = CHALK_DRAW_RELEASE
            if target_draw_level > runtime^.draw_level {
                draw_alpha = CHALK_DRAW_ATTACK
            }
            runtime^.draw_level +=
                (target_draw_level - runtime^.draw_level) * draw_alpha

            runtime^.sample_buffer[i] =
                texture_sample * runtime^.draw_level + advance_chalk_hit(runtime)
        }

        rl.UpdateAudioStream(runtime^.stream, &runtime^.sample_buffer, CHALK_BUFFER_SIZE)

        processed_count += 1
        if processed_count >= CHALK_MAX_BUFFERS_PER_FRAME {
            break
        }
    }

    runtime^.has_contact_this_frame = false
}