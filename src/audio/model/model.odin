package audiomodel

NATIVE_DRAWING_SOURCE_CAPACITY :: 64

// Chalk_Drawing_Source tracks one native producer independently of Julia activity.
Chalk_Drawing_Source :: struct {
    identity: u64,
    active: bool,
}

// Chalk_Audio_Runtime retains display-independent drawing-audio policy state.
Chalk_Audio_Runtime :: struct {
    drawing_active: bool,
    julia_drawing_active: bool,
    native_drawing_sources: [NATIVE_DRAWING_SOURCE_CAPACITY]Chalk_Drawing_Source,
    gain: f32,
}
