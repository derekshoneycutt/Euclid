package particlemodel

import rand "core:math/rand"

import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 65536
MAX_PARTICLES :: 2048
DUST_ATLAS_VARIANT_COUNT :: 9

DUST_GRID_CELL_SIZE :: 0.02
DUST_GRID_DIM :: 50
DUST_GRID_DIM_SQUARED :: DUST_GRID_DIM * DUST_GRID_DIM
DUST_GRID_BUCKET_CAP :: 128
DUST_GRID_BUCKET_COUNT :: DUST_GRID_DIM_SQUARED * DUST_GRID_BUCKET_CAP
DUST_COLLISION_PAIR_CAP :: MAX_LOW_PARTICLES * 16
DUST_TOOL_CONTACT_CAP :: 64
DUST_CONTACT_CANDIDATE_WORD_COUNT :: (MAX_LOW_PARTICLES + 63) / 64

// Describe one ordered endpoint push with an optional sampled compass sweep.
Dust_Tool_Contact :: struct {
    endpoint: rl.Vector3,
    segment_first: rl.Vector3,
    segment_second: rl.Vector3,
    max_spawn_sequence: u64,
    sample_count: i32,
    has_sweep: bool,
}

// Store one particle's simulation and rendering state.
Particle :: struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vel_x: f32,
    vel_y: f32,
    vel_z: f32,

    age: f32,
    life: f32,
    size: f32,
    ember_size_start: f32,
    ember_size_end: f32,
    ember_white_at_birth: f32,
    color: rl.Color,
    dust_sprite_index: u8,
    alive: bool,
    lit_frames: i16,
}

// Own the bounded three-layer particle simulation storage and deterministic random state.
Particle_System :: struct {
    low_particles: #soa[MAX_LOW_PARTICLES]Particle,
    low_particle_screens: [MAX_LOW_PARTICLES]rl.Vector2,
    particles: #soa[MAX_PARTICLES]Particle,
    high_particles: #soa[MAX_PARTICLES]Particle,

    dust_exact_indices: [MAX_LOW_PARTICLES]i32,
    dust_exact_counts: [DUST_GRID_DIM_SQUARED]i32,
    dust_exact_offsets: [DUST_GRID_DIM_SQUARED + 1]i32,
    dust_exact_cursors: [DUST_GRID_DIM_SQUARED]i32,
    dust_active_cells: [DUST_GRID_DIM_SQUARED]i32,
    dust_active_cell_count: int,

    dust_tool_contacts: [DUST_TOOL_CONTACT_CAP]Dust_Tool_Contact,
    dust_tool_contact_count: int,
    dust_tool_contact_overflow_count: int,
    dust_contact_candidate_bits: [DUST_CONTACT_CANDIDATE_WORD_COUNT]u64,
    dust_contact_candidates: [MAX_LOW_PARTICLES]i32,
    dust_contact_candidate_count: int,
    dust_slot_spawn_sequences: [MAX_LOW_PARTICLES]u64,
    dust_spawn_sequence: u64,

    dust_buckets: [DUST_GRID_BUCKET_COUNT]i32,
    dust_counts: [DUST_GRID_DIM_SQUARED]i32,
    dust_seen_counts: [DUST_GRID_DIM_SQUARED]i32,
    dust_pair_a: [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_b: [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_count: int,
    dust_pair_dropped_count: int,
    dust_collision_frame: u64,

    next_index: int,
    spawn_timer: f32,
    rng_state: rand.Xoshiro256_Random_State,

    last_render_low: int,
    last_render_mid: int,
    last_render_high: int,

    use_max_dust_particles: int,
}
