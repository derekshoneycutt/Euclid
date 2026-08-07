package audio

import "../core"

import "core:math"
import "core:math/linalg"
import "core:math/rand"

import rl "vendor:raylib"

// Stream format and pacing constants.
CHALK_SAMPLE_RATE :: 44100
CHALK_BUFFER_SIZE :: 512

// Motion-to-audio mapping constants.
CHALK_SPEED_FOR_MAX :: 50.0
CHALK_RESONANCE_FREQ :: 250.0
CHALK_MOUSE_EQUIV_SCALE :: 900.0
CHALK_MAX_BUFFERS_PER_FRAME :: 8

// Tone/noise blend constants.
CHALK_RESONANCE_MIX :: 0.18
CHALK_NOISE_MIX :: 0.82
CHALK_DRAW_GAIN :: 1.2

// Keep the noise filter bright so it reads as chalk hiss.
CHALK_FILTER_ALPHA_BASE :: 0.08
CHALK_FILTER_ALPHA_RANGE :: 0.32

// Grain envelope: a fast random-walk "hold and slide" that fakes the
// irregularity real friction (or human hand jitter) would otherwise provide.
CHALK_GRAIN_MIN_LEVEL :: 0.25
CHALK_GRAIN_SNAP_ALPHA :: 0.35
CHALK_GRAIN_HOLD_MIN_SAMPLES :: 90.0
CHALK_GRAIN_HOLD_MAX_SAMPLES :: 380.0
CHALK_RESONANCE_OFFSET_HZ :: 18.0

// One-shot floor-hit transient tuning.
CHALK_HIT_ENVELOPE_GAIN :: 0.8
CHALK_HIT_ENVELOPE_DECAY :: 0.988
CHALK_HIT_MIX :: 0.32

Chalk_Audio_Runtime :: core.Chalk_Audio_Runtime
Vector3 :: core.Vector3

// Create and start the chalk audio stream.
init_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if runtime^.initialized {
        return
    }

    rl.SetAudioStreamBufferSizeDefault(CHALK_BUFFER_SIZE)
    runtime^.stream = rl.LoadAudioStream(CHALK_SAMPLE_RATE, 32, 1)
    rl.PlayAudioStream(runtime^.stream)
    runtime^.initialized = true
}

// Stop and unload the chalk audio stream.
shutdown_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }

    rl.UnloadAudioStream(runtime^.stream)
    runtime^.initialized = false
}

// Register pen-tip motion for one simulation step.
register_pen_tip_motion :: proc(runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
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

// Register compass joint1 motion for one simulation step.
register_compass_tip1_motion :: proc(runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
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

// Register compass joint2 motion for one simulation step.
register_compass_tip2_motion :: proc(runtime: ^Chalk_Audio_Runtime, pos: Vector3, is_floor_contact: bool, dt: f32) {
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

// Trigger a short impact transient when a tool tip hits z=0.
trigger_hit_sound :: proc(runtime: ^Chalk_Audio_Runtime) {
    if !runtime^.initialized {
        return
    }

    runtime^.hit_envelope += CHALK_HIT_ENVELOPE_GAIN
    if runtime^.hit_envelope > 1.5 {
        runtime^.hit_envelope = 1.5
    }
}

// Accumulate peak contact speed from one tool tip stream.
register_tip_motion :: #force_inline proc(
    runtime: ^Chalk_Audio_Runtime,
    previous_pos: ^Vector3,
    has_previous: ^bool,
    previous_contact: ^bool,
    pos: Vector3,
    is_floor_contact: bool,
    dt: f32,
) {
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

// Fill all pending stream buffers using the latest accumulated motion state.
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
        phase_step := (2.0 * math.PI * (CHALK_RESONANCE_FREQ + runtime^.resonance_freq_offset)) / f32(CHALK_SAMPLE_RATE)

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
            runtime^.grain_level += (runtime^.grain_target - runtime^.grain_level) * CHALK_GRAIN_SNAP_ALPHA

            raw_noise := rand.float32_range(-1.0, 1.0)

            runtime^.phase += phase_step
            if runtime^.phase > 2.0 * math.PI do runtime^.phase -= 2.0 * math.PI
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