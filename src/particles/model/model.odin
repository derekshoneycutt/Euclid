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
