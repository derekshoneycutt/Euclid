package audio

import "core:testing"

// Verify supported builds retain no native audio state.
@(test)
disabled_audio_runtime_has_no_native_state :: proc(t: ^testing.T) {
    testing.expect(t, !EXPERIMENTAL_AUDIO_ENABLED)
    testing.expect(t, size_of(Chalk_Audio_Runtime) == 0)
}

// Verify disabled lifecycle and bridge-facing operations remain harmless.
@(test)
disabled_audio_operations_are_no_ops :: proc(t: ^testing.T) {
    runtime: Chalk_Audio_Runtime
    init_chalk_runtime(&runtime, "unused.wav")
    register_drawing_contact(&runtime)
    update_chalk_runtime(&runtime)
    shutdown_chalk_runtime(&runtime)
    testing.expect(t, size_of(runtime) == 0)
}