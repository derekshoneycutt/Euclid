package audio

import "../core"

import "core:math"
import "core:math/linalg"
import "core:math/rand"

import rl "vendor:raylib"

CHALK_SAMPLE_RATE :: 44100
CHALK_BUFFER_SIZE :: 512
CHALK_SPEED_FOR_MAX :: 50.0
CHALK_RESONANCE_FREQ :: 250.0
CHALK_MOUSE_EQUIV_SCALE :: 900.0
CHALK_MAX_BUFFERS_PER_FRAME :: 8
CHALK_RESONANCE_MIX :: 0.18
CHALK_NOISE_MIX :: 0.82
CHALK_DRAW_GAIN :: 1.2
CHALK_FILTER_ALPHA_BASE :: 0.08
CHALK_FILTER_ALPHA_RANGE :: 0.32
CHALK_GRAIN_MIN_LEVEL :: 0.25
CHALK_GRAIN_SNAP_ALPHA :: 0.35
CHALK_GRAIN_HOLD_MIN_SAMPLES :: 90.0
CHALK_GRAIN_HOLD_MAX_SAMPLES :: 380.0
CHALK_RESONANCE_OFFSET_HZ :: 18.0
CHALK_HIT_ENVELOPE_GAIN :: 0.8
CHALK_HIT_ENVELOPE_DECAY :: 0.988
CHALK_HIT_MIX :: 0.32

Chalk_Audio_Runtime :: core.Chalk_Audio_Runtime
Vector3 :: core.Vector3

//   Initialize the chalk stream and start playback.
//
// Notes:
//   - The stream is created once and immediately started so later updates can
//     push fresh audio buffers without waiting for a separate setup step.
init_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if runtime^.initialized {
        return
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
shutdown_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }

    rl.UnloadAudioStream(runtime^.stream)
    runtime^.initialized = false
}

//   Record the pen tip's latest position for the next audio update.
//
// Notes:
//   - The pen motion is folded into the shared motion tracker so the synth can
//     convert stroke movement into audible energy.
register_pen_tip_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    register_tip_motion(
        runtime,
        &runtime^.pen_prev_pos,
        &runtime^.pen_has_prev,
        &runtime^.pen_prev_contact,
        pos,
        is_floor_contact,
        dt,
    )
}

//   Record the first compass tip's latest position for the next audio update.
//
// Notes:
//   - The compass motion is tracked separately so the synth can react to its
//     movement across the drawing plane.
register_compass_tip1_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    register_tip_motion(
        runtime,
        &runtime^.compass_tip1_prev_pos,
        &runtime^.compass_tip1_has_prev,
        &runtime^.compass_tip1_prev_contact,
        pos,
        is_floor_contact,
        dt,
    )
}

//   Record the second compass tip's latest position for the next audio update.
//
// Notes:
//   - The compass motion is tracked separately so the synth can react to its
//     movement across the drawing plane.
register_compass_tip2_motion :: proc(
    runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
    register_tip_motion(
        runtime,
        &runtime^.compass_tip2_prev_pos,
        &runtime^.compass_tip2_has_prev,
        &runtime^.compass_tip2_prev_contact,
        pos,
        is_floor_contact,
        dt,
    )
}

//   Raise a brief hit envelope when a tool tip touches the floor plane.
//
// Notes:
//   - The envelope makes the next audio buffer carry a short contact-like pop.
trigger_hit_sound :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }

    runtime^.hit_envelope += CHALK_HIT_ENVELOPE_GAIN
    if runtime^.hit_envelope > 1.5 {
        runtime^.hit_envelope = 1.5
    }
}

//   Track the largest contact speed seen from one tool tip stream.
//
// Notes:
//   - The peak speed is used to scale the chalk synth's loudness while the tip is
//     in contact with the floor.
register_tip_motion :: #force_inline proc(
    runtime: ^Chalk_Audio_Runtime,
    previous_pos: ^Vector3,
    has_previous: ^bool,
    previous_contact: ^bool,
    pos: Vector3,
    is_floor_contact: bool,
    dt: f32) {
    if !runtime^.initialized {
        return
    }
    _ = dt

    if has_previous^ && previous_contact^ && is_floor_contact {
        delta := pos - previous_pos^
        speed := linalg.length(delta) * CHALK_MOUSE_EQUIV_SCALE
        if speed > runtime^.accum_speed {
            runtime^.accum_speed = speed
        }
    }

    if is_floor_contact {
        runtime^.has_contact_this_frame = true
    }

    previous_pos^ = pos
    has_previous^ = true
    previous_contact^ = is_floor_contact
}

//   Drain processed audio buffers and write the next chalk synth frame.
//
// Notes:
//   - The runtime uses the current contact speed, grain state, and hit envelope to
//     fill each pending buffer with fresh synthetic samples.
update_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }
    processed_count := 0
    for rl.IsAudioStreamProcessed(runtime^.stream) {
        normalized_speed := math.clamp(runtime^.accum_speed / CHALK_SPEED_FOR_MAX, 0.0, 1.0)
        if !runtime^.has_contact_this_frame {
            normalized_speed = 0
        }

        volume := normalized_speed * CHALK_DRAW_GAIN
        filter_alpha := CHALK_FILTER_ALPHA_BASE + (normalized_speed * CHALK_FILTER_ALPHA_RANGE)
        phase_step := (2.0 * math.PI *
            (CHALK_RESONANCE_FREQ + runtime^.resonance_freq_offset)) / f32(CHALK_SAMPLE_RATE)

        for i := 0; i < CHALK_BUFFER_SIZE; i += 1 {
            // Advance the stick-slip grain envelope: hold a random level for a
            // short random duration, then slide toward the next one. This is
            // what keeps constant-speed scripted motion from sounding like a
            // steady, engine-like drone.
            runtime^.grain_hold_remaining -= 1
            if runtime^.grain_hold_remaining <= 0 {
                runtime^.grain_target = rand.float32_range(CHALK_GRAIN_MIN_LEVEL, 1.0)
                runtime^.grain_hold_remaining =
                    rand.float32_range(CHALK_GRAIN_HOLD_MIN_SAMPLES, CHALK_GRAIN_HOLD_MAX_SAMPLES)
                runtime^.resonance_freq_offset =
                    rand.float32_range(-CHALK_RESONANCE_OFFSET_HZ, CHALK_RESONANCE_OFFSET_HZ)
            }
            runtime^.grain_level +=
                (runtime^.grain_target - runtime^.grain_level) * CHALK_GRAIN_SNAP_ALPHA

            raw_noise := rand.float32_range(-1.0, 1.0)

            runtime^.phase += phase_step
            if runtime^.phase > 2.0 * math.PI {
                runtime^.phase -= 2.0 * math.PI
            }
            sine_tone := math.sin(runtime^.phase)

            modulated_resonance := sine_tone * math.abs(raw_noise) * runtime^.grain_level
            runtime^.prev_out = runtime^.prev_out + filter_alpha * (raw_noise - runtime^.prev_out)
            hiss := runtime^.prev_out * runtime^.grain_level

            hit_component: f32 = 0
            if runtime^.hit_envelope > 0.0001 {
                hit_component = rand.float32_range(-1.0, 1.0) * runtime^.hit_envelope
                runtime^.hit_envelope *= CHALK_HIT_ENVELOPE_DECAY
            }

            combined_signal :=
                (modulated_resonance * CHALK_RESONANCE_MIX) +
                (hiss * CHALK_NOISE_MIX)
            runtime^.sample_buffer[i] = (combined_signal * volume) + (hit_component * CHALK_HIT_MIX)
        }

        rl.UpdateAudioStream(runtime^.stream, &runtime^.sample_buffer, CHALK_BUFFER_SIZE)

        processed_count += 1
        if processed_count >= CHALK_MAX_BUFFERS_PER_FRAME {
            break
        }
    }

    runtime^.accum_speed = 0
    runtime^.has_contact_this_frame = false
}