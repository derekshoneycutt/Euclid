package audiomodel


// Own streamed chalk-audio resources and synthesis cursors for an experimental build.
// Native audio is unavailable while bridge sound commands remain ABI-compatible no-ops.
EXPERIMENTAL_AUDIO_ENABLED :: false

// Chalk_Audio_Runtime retains no native state in the supported application.
Chalk_Audio_Runtime :: struct {}
