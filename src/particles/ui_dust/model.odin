package ui_dust

import color "../../core/color"
import geometry "../../core/geometry"
import particlemodel "../model"
import rand "core:math/rand"

UI_DUST_MAX_DEPARTURE_SAMPLES :: 2048
UI_DUST_SPRITE_VARIANT_COUNT :: particlemodel.DUST_ATLAS_VARIANT_COUNT
UI_DUST_RANDOM_SEED :: u64(0x9e3779b97f4a7c15)
UI_DUST_FADE_DURATION :: f32(0.20)
UI_DUST_REST_LIFE_MIN :: f32(0.85)
UI_DUST_REST_LIFE_MAX :: f32(1.15)
UI_DUST_DEPARTURE_DURATION :: f32(0.30)
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
UI_DUST_TOTAL_PARTICLES :: 4096
UI_DUST_MATCH_GRID :: 16
UI_DUST_MATCH_CANDIDATES :: 64
UI_DUST_RECLAIM_MIN_DURATION :: f32(0.04)
#assert(UI_DUST_MAX_DEPARTURE_SAMPLES <= UI_DUST_TOTAL_PARTICLES)
#assert(UI_DUST_MAX_ARRIVAL_PARTICLES <= UI_DUST_TOTAL_PARTICLES)
UI_DUST_ARRIVAL_RANDOM_SEED :: u64(0xd1b54a32d192ed03)
UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT :: f32(0.25)
UI_DUST_ARRIVAL_DELAY_MAX :: f32(0.03)
UI_DUST_ARRIVAL_FALL_MIN :: f32(0.16)
UI_DUST_ARRIVAL_FALL_MAX :: f32(0.21)
UI_DUST_ARRIVAL_DROP_MIN :: f32(14)
UI_DUST_ARRIVAL_DROP_MAX :: f32(30)
UI_DUST_ARRIVAL_LATERAL_MAX :: f32(5)
UI_DUST_ARRIVAL_APPEAR_FRACTION :: f32(0.25)
UI_DUST_ARRIVAL_HANDOFF_START :: f32(0.24)
UI_DUST_ARRIVAL_HANDOFF_END :: f32(0.30)
#assert(UI_DUST_ARRIVAL_DELAY_MAX + UI_DUST_ARRIVAL_FALL_MAX <=
    UI_DUST_ARRIVAL_HANDOFF_START)
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

// Ui_Dust_Phase gives each shared slot exactly one live material owner.
Ui_Dust_Phase :: enum u8 {
    Free,
    Airborne_Departure,
    Resting_Departure,
    Fresh_Arrival,
    Reclaimed_Arrival,
}

// Ui_Dust_Transition keeps Independent available for internal comparisons.
Ui_Dust_Transition :: enum u8 {
    Reclaim,
    Independent,
}

// Ui_Dust_Target retains one bounded sampled destination and its generation-safe claim.
Ui_Dust_Target :: struct {
    position: geometry.Vector2,
    ink: [4]u8,
    coverage: u8,
    claim: Ui_Dust_Slot_Ref,
}

// Ui_Dust_Match_Link supports constant-time removal from spatial and fallback chains.
Ui_Dust_Match_Link :: struct {
    previous: int,
    next: int,
    older: int,
    newer: int,
    bin: int,
}

// Ui_Dust_Match_Search bounds candidate work for one deterministic target search.
Ui_Dust_Match_Search :: struct {
    tested: int,
    best: int,
    distance: f32,
}

// Ui_Dust_Slot_Ref rejects borrowers after retirement or reuse of a physical slot.
Ui_Dust_Slot_Ref :: struct {
    index: int,
    generation: u64,
}

// Ui_Dust_Slot_Order links original emissions independently of phase changes.
// Links store index + 1, with zero meaning none; free slots use only `next`.
Ui_Dust_Slot_Order :: struct {
    generation: u64,
    previous: int,
    next: int,
}

// Ui_Dust_Particle owns one pane-space fragment and any assigned arrival target.
// `age` counts seconds since emission; `flight_elapsed` is the departure clock,
// independent of original age. `life` is the fade duration after resting.
Ui_Dust_Particle :: struct {
    phase: Ui_Dust_Phase,
    pos_x: f32,
    pos_y: f32,
    vel_x: f32,
    vel_y: f32,
    start_x: f32,
    start_y: f32,
    start_velocity_x: f32,
    start_velocity_y: f32,
    flight_elapsed: f32,

    age: f32,
    rest_age: f32,
    life: f32,
    size: f32,
    sway_amplitude: f32,
    sway_frequency: f32,
    sway_phase: f32,
    target_color: color.Color_RGBA8,
    color: color.Color_RGBA8,
    dust_sprite_index: u8,
    target_x: f32,
    target_y: f32,
    drop: f32,
    lateral: f32,
    delay: f32,
    duration: f32,
    captured: bool,
    captured_alpha: f32,
    target_size: f32,
}

// Ui_Dust_Appearance is a copied visible state for drawing and future transfers.
Ui_Dust_Appearance :: struct {
    position: geometry.Vector2,
    velocity: geometry.Vector2,
    tint: color.Color_RGBA8,
    alpha: f32,
    size: f32,
    sprite_index: u8,
}

// Ui_Dust_Visual_Context identifies one valid visible presentation viewport.
Ui_Dust_Visual_Context :: struct {
    visible: bool,
    reduced_motion: bool,
    viewport: geometry.Rectangle,
    scroll_y: f32,
    visual_signature: u64,
}

// Ui_Dust_System owns a shared fixed pool and one arrival effect. Live slots are
// linked in original emission order; holes are reused before oldest-live eviction.
// `particle_count` counts departures, `arrival_count` arrivals, and `live_count` both.
Ui_Dust_System :: struct {
    transition: Ui_Dust_Transition,
    particles: #soa[UI_DUST_TOTAL_PARTICLES]Ui_Dust_Particle,
    order: [UI_DUST_TOTAL_PARTICLES]Ui_Dust_Slot_Order,
    initialized_slots: int,
    free_head: int,
    live_head: int,
    live_tail: int,
    live_count: int,
    eviction_count: u64,
    formation_reclaimed: int,
    formation_fresh: int,
    arrival_completed_count: u64,
    arrival_cancelled_count: u64,
    arrival_completed_duration: f32,
    particle_count: int,
    rng_state: rand.Xoshiro256_Random_State,

    arrival_count: int,
    arrival_emitted: int,
    arrival_rng_state: rand.Xoshiro256_Random_State,
    targets: [UI_DUST_MAX_ARRIVAL_PARTICLES]Ui_Dust_Target,
    target_count: int,
    match_bins: [UI_DUST_MATCH_GRID * UI_DUST_MATCH_GRID]int,
    match_links: [UI_DUST_TOTAL_PARTICLES]Ui_Dust_Match_Link,
    match_head: int,

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
