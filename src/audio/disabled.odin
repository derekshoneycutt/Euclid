package audio

import audiomodel "model"

when !audiomodel.EXPERIMENTAL_AUDIO_ENABLED {
// Leave the supported runtime unchanged because native audio is compiled out.
init_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime, texture_path: string) {
    _ = runtime
    _ = texture_path
}

// Keep disabled audio teardown idempotent and free of native work.
shutdown_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    _ = runtime
}

// Keep the frame call compatible while the experimental mixer is absent.
update_chalk_runtime :: proc(runtime: ^Chalk_Audio_Runtime) {
    _ = runtime
}

// Accept bridge sound commands as deterministic no-ops.
register_drawing_contact :: proc "contextless" (runtime: ^Chalk_Audio_Runtime) {
    _ = runtime
}
}