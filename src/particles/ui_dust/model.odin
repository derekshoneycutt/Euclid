package ui_dust

import color "../../core/color"
import geometry "../../core/geometry"
import particlemodel "../model"
import rand "core:math/rand"

UI_DUST_MAX_PARTICLES :: 2048
UI_DUST_SPRITE_VARIANT_COUNT :: particlemodel.DUST_ATLAS_VARIANT_COUNT
UI_DUST_RANDOM_SEED :: u64(0x9e3779b97f4a7c15)
UI_DUST_FADE_DURATION :: f32(0.20)
UI_DUST_REST_LIFE_MIN :: f32(0.85)
UI_DUST_REST_LIFE_MAX :: f32(1.15)
UI_DUST_DOWNWARD_ACCELERATION :: f32(90)
UI_DUST_VX_MIN :: f32(-6)
UI_DUST_VX_MAX :: f32(6)
UI_DUST_VY_MIN :: f32(24)
UI_DUST_VY_MAX :: f32(44)
UI_DUST_SWAY_AMPLITUDE_MIN :: f32(1.5)
UI_DUST_SWAY_AMPLITUDE_MAX :: f32(5)
UI_DUST_SWAY_FREQUENCY_MIN :: f32(5)
UI_DUST_SWAY_FREQUENCY_MAX :: f32(10)
UI_DUST_SIZE_MIN :: f32(1)
UI_DUST_SIZE_COVERAGE_SCALE :: f32(1.4)

UI_DUST_MAX_ARRIVAL_PARTICLES :: 2048
// Outgoing and incoming populations share this explicit total pane budget.
UI_DUST_TOTAL_PARTICLES :: UI_DUST_MAX_PARTICLES + UI_DUST_MAX_ARRIVAL_PARTICLES
UI_DUST_ARRIVAL_RANDOM_SEED :: u64(0xd1b54a32d192ed03)
UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT :: f32(0.25)
UI_DUST_ARRIVAL_DELAY_MAX :: f32(0.12)
UI_DUST_ARRIVAL_FALL_MIN :: f32(0.34)
UI_DUST_ARRIVAL_FALL_MAX :: f32(0.46)
UI_DUST_ARRIVAL_DROP_MIN :: f32(14)
UI_DUST_ARRIVAL_DROP_MAX :: f32(30)
UI_DUST_ARRIVAL_LATERAL_MAX :: f32(5)
UI_DUST_ARRIVAL_APPEAR_FRACTION :: f32(0.25)
UI_DUST_ARRIVAL_HANDOFF_START :: f32(0.42)
UI_DUST_ARRIVAL_HANDOFF_END :: f32(0.66)
#assert(UI_DUST_ARRIVAL_DELAY_MAX + UI_DUST_ARRIVAL_FALL_MAX <=
    UI_DUST_ARRIVAL_HANDOFF_END)
#assert(UI_DUST_ARRIVAL_HANDOFF_START < UI_DUST_ARRIVAL_HANDOFF_END)

// Draw-in derives ink rows from fixed vertical occupancy bins over the viewport.
UI_DUST_DRAW_IN_MAX_ROWS :: 64
UI_DUST_DRAW_IN_ROW_BINS :: 1024
UI_DUST_DRAW_IN_BIN_HEIGHT_MIN :: f32(2)
UI_DUST_DRAW_IN_ROW_GAP :: f32(2)
UI_DUST_DRAW_IN_DURATION :: f32(0.70)
UI_DUST_DRAW_IN_ROW_SWEEP :: f32(0.34)
UI_DUST_DRAW_IN_ROW_SWEEP_MIN_FRACTION :: f32(0.35)
UI_DUST_DRAW_IN_ROW_STAGGER_MAX :: f32(0.07)
UI_DUST_DRAW_IN_FEATHER :: f32(10)
UI_DUST_DRAW_IN_FEATHER_STEPS :: 4
UI_DUST_DRAW_IN_ACCENT_MAX :: 384
UI_DUST_DRAW_IN_ACCENT_SETTLE :: f32(0.10)
UI_DUST_DRAW_IN_ACCENT_LIFE :: f32(0.32)
UI_DUST_DRAW_IN_ACCENT_DROP_MIN :: f32(2)
UI_DUST_DRAW_IN_ACCENT_DROP_MAX :: f32(6)
UI_DUST_DRAW_IN_ACCENT_LATERAL_MAX :: f32(3)
#assert(UI_DUST_DRAW_IN_ROW_SWEEP < UI_DUST_DRAW_IN_DURATION)
#assert(UI_DUST_DRAW_IN_ACCENT_MAX <= UI_DUST_MAX_ARRIVAL_PARTICLES)

// Ui_Dust_Arrival_Style selects how newly published structured content appears.
Ui_Dust_Arrival_Style :: enum u8 {
    Immediate,
    Fade,
    Falling_Ink,
    Draw_In,
}

// UI_DUST_ARRIVAL_STYLE is the fixed product arrival style. The other policies stay
// implemented and tested for comparison; debug scenarios may override the style for
// one presentation runtime, but no preference or persisted setting selects it.
UI_DUST_ARRIVAL_STYLE : Ui_Dust_Arrival_Style : .Falling_Ink

// Ui_Dust_Reveal_Bin accumulates the horizontal ink extent of one vertical bin.
// A bin is empty while `left > right`.
Ui_Dust_Reveal_Bin :: struct {
    left: f32,
    right: f32,
}

// Ui_Dust_Reveal_Row is one staggered draw-in band. `top` and `bottom` tile the
// viewport; `left` and `right` bound the row's sampled ink.
Ui_Dust_Reveal_Row :: struct {
    top: f32,
    bottom: f32,
    left: f32,
    right: f32,
    start: f32,
    sweep: f32,
}

// Ui_Dust_Arrival_Particle descends from a short local offset onto one fixed ink
// target. Its position is a closed-form function of arrival time, so it lands
// exactly on the target regardless of frame timing.
Ui_Dust_Arrival_Particle :: struct {
    target_x: f32,
    target_y: f32,
    drop: f32,
    lateral: f32,
    delay: f32,
    duration: f32,
    size: f32,
    sway_amplitude: f32,
    sway_frequency: f32,
    sway_phase: f32,
    color: color.Color_RGBA8,
    dust_sprite_index: u8,
}

// Ui_Dust_Particle stores one pane-space fragment in the standard particle shape.
// `age` counts seconds since emission; `life` is the fade duration after resting.
Ui_Dust_Particle :: struct {
    pos_x: f32,
    pos_y: f32,
    vel_x: f32,
    vel_y: f32,

    age: f32,
    rest_age: f32,
    life: f32,
    size: f32,
    sway_amplitude: f32,
    sway_frequency: f32,
    sway_phase: f32,
    color: color.Color_RGBA8,
    dust_sprite_index: u8,
    resting: bool,
}

// Ui_Dust_Visual_Context identifies one valid visible presentation viewport.
Ui_Dust_Visual_Context :: struct {
    visible: bool,
    reduced_motion: bool,
    viewport: geometry.Rectangle,
    scroll_y: f32,
    visual_signature: u64,
}

// Ui_Dust_System owns fixed presentation dust storage and the arrival effect.
// Live outgoing particles occupy `particles[:particle_count]`; incoming formation
// particles and draw-in accents occupy `arrivals[:arrival_count]`; draw-in bands
// occupy `reveal_rows[:reveal_row_count]`.
Ui_Dust_System :: struct {
    particles: #soa[UI_DUST_MAX_PARTICLES]Ui_Dust_Particle,
    particle_count: int,
    rng_state: rand.Xoshiro256_Random_State,

    arrivals: #soa[UI_DUST_MAX_ARRIVAL_PARTICLES]Ui_Dust_Arrival_Particle,
    arrival_count: int,
    arrival_rng_state: rand.Xoshiro256_Random_State,

    reveal_bins: [UI_DUST_DRAW_IN_ROW_BINS]Ui_Dust_Reveal_Bin,
    reveal_rows: [UI_DUST_DRAW_IN_MAX_ROWS]Ui_Dust_Reveal_Row,
    reveal_row_count: int,

    incoming_active: bool,
    incoming_style: Ui_Dust_Arrival_Style,
    incoming_awaiting_targets: bool,
    incoming_wait: f32,
    incoming_elapsed: f32,
    incoming_generation: u64,

    viewport: geometry.Rectangle,
    scroll_y: f32,
    visual_signature: u64,
    viewport_initialized: bool,
    departure_context_pending: bool,
}
