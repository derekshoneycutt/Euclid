package audiomodel

import rl "vendor:raylib"

// Compile the retained Raylib audio experiment only when explicitly requested.
EXPERIMENTAL_AUDIO_ENABLED :: #config(EUCLID_EXPERIMENTAL_AUDIO, false)

// Own streamed chalk-audio resources and synthesis cursors for an experimental build.
Experimental_Chalk_Audio_Runtime :: struct {
    stream: rl.AudioStream,
    sample_buffer: [512]f32,
    draw_level: f32,
    has_contact_this_frame: bool,
    initialized: bool,

    texture_samples: [^]f32,
    texture_sample_count: int,
    texture_lower_turn: int,
    texture_upper_turn: int,
    texture_cursor: int,
    texture_direction: int,
    hit_sample_cursor: int,
    hit_active: bool,
}

// Exclude native audio state from the supported application configuration.
when EXPERIMENTAL_AUDIO_ENABLED {
    Chalk_Audio_Runtime :: Experimental_Chalk_Audio_Runtime
} else {
    Chalk_Audio_Runtime :: struct {}
}
