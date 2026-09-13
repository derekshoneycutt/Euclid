package audiomodel

import rl "vendor:raylib"

// Own streamed chalk-audio resources and synthesis cursors for one application runtime.
Chalk_Audio_Runtime :: struct {
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
