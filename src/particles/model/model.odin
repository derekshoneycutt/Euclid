package particlemodel

import rand "core:math/rand"

import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 65536
MAX_PARTICLES :: 2048
DUST_ATLAS_VARIANT_COUNT :: 9

DUST_GRID_CELL_SIZE :: 0.02
DUST_GRID_DIM :: 50
DUST_GRID_DIM_SQUARED :: DUST_GRID_DIM * DUST_GRID_DIM
DUST_COLLISION_CELL_SAMPLE_CAP :: 128
DUST_COLLISION_MIN_SEPARATION :: 0.004
DUST_COLLISION_GRID_CELL_SIZE :: DUST_COLLISION_MIN_SEPARATION
DUST_COLLISION_GRID_DIM :: 250
DUST_COLLISION_GRID_CELL_COUNT :: DUST_COLLISION_GRID_DIM * DUST_COLLISION_GRID_DIM
DUST_FIELD_DIM :: DUST_COLLISION_GRID_DIM + 1
DUST_FIELD_NODE_COUNT :: DUST_FIELD_DIM * DUST_FIELD_DIM
DUST_FIELD_ACTIVE_WORD_COUNT :: (DUST_FIELD_NODE_COUNT + 63) / 64
DUST_FIELD_STENCIL_CAP :: 9
DUST_COLLISION_PAIR_CAP :: MAX_LOW_PARTICLES * 16
DUST_TOOL_CONTACT_CAP :: 64
DUST_CONTACT_CANDIDATE_WORD_COUNT :: (MAX_LOW_PARTICLES + 63) / 64
DUST_RELAXATION_LEAVES_PER_PARENT :: 16
DUST_RELAXATION_LEAF_COUNT ::
    DUST_GRID_DIM_SQUARED * DUST_RELAXATION_LEAVES_PER_PARENT
SCENARIO_DUST_EMISSION_REQUEST_CAP :: 16

// Store one fixed scalar plane over the global dust-field topology.
Dust_Field_Scalar :: [DUST_FIELD_NODE_COUNT]f32

// Describe normalized field nodes influencing one board-space position.
Dust_Field_Stencil :: struct {
    indices: [DUST_FIELD_STENCIL_CAP]i32,
    weights: [DUST_FIELD_STENCIL_CAP]f32,
    count: int,
}

// Own bounded CPU planes and sparse activity metadata for the aggregate dust field.
Dust_Field_State :: struct {
    candidate_density: Dust_Field_Scalar,
    density: Dust_Field_Scalar,
    momentum_x: Dust_Field_Scalar,
    momentum_y: Dust_Field_Scalar,
    velocity_x: Dust_Field_Scalar,
    velocity_y: Dust_Field_Scalar,
    next_velocity_x: Dust_Field_Scalar,
    next_velocity_y: Dust_Field_Scalar,
    color_r: Dust_Field_Scalar,
    color_g: Dust_Field_Scalar,
    color_b: Dust_Field_Scalar,
    coverage: Dust_Field_Scalar,
    active_bits: [DUST_FIELD_ACTIVE_WORD_COUNT]u64,
    active_nodes: [DUST_FIELD_NODE_COUNT]i32,
    active_count: int,
}

// Spatial layout for one deterministic diagnostic dust emission.
Dust_Emission_Distribution :: enum u8 {
    Point,
    Disc,
    Grid,
}

// Describe one bounded worker-owned diagnostic dust emission request.
Scenario_Dust_Emission_Request :: struct {
    distribution: Dust_Emission_Distribution,
    count: u32,
    x, y, radius: f32,
    seed: u64,
    correlation: u64,
    generation: u64,
}

// Fixed display-to-particle handoff storage for scenario dust requests.
Dust_Emission_Request_Queue :: struct {
    items: [SCENARIO_DUST_EMISSION_REQUEST_CAP]Scenario_Dust_Emission_Request,
    count: int,
}

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

    dust_buckets: [MAX_LOW_PARTICLES]i32,
    dust_counts: [DUST_COLLISION_GRID_CELL_COUNT]i32,
    dust_seen_counts: [DUST_COLLISION_GRID_CELL_COUNT]i32,
    dust_collision_offsets: [DUST_COLLISION_GRID_CELL_COUNT + 1]i32,
    dust_collision_active_cells: [DUST_COLLISION_GRID_CELL_COUNT]i32,
    dust_collision_active_cell_count: int,
    dust_collision_candidate_count: u64,
    dust_pair_a: [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_b: [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_count: int,
    dust_pair_dropped_count: int,
    dust_collision_frame: u64,
    dust_collision_correction_count: int,
    dust_collision_max_correction: f32,
    dust_collision_rest_contact_count: int,
    dust_floor_rest_count: int,
    dust_collision_refined_cell_count: int,

    dust_field: Dust_Field_State,
    dust_aggregate: [MAX_LOW_PARTICLES]bool,
    dust_field_quiet_frames: [MAX_LOW_PARTICLES]u16,
    dust_aggregate_count: int,
    dust_field_pressure_node_count: int,
    dust_field_suppressed_pair_count: u64,
    dust_field_peak_density: f32,
    dust_field_peak_speed: f32,
    dust_field_kinetic_measure: f32,
    dust_field_sleep_transition_count: u64,
    dust_field_wake_transition_count: u64,

    dust_relaxation_parent_counts: [DUST_GRID_DIM_SQUARED]i32,
    dust_relaxation_parent_levels: [DUST_GRID_DIM_SQUARED]u8,
    dust_relaxation_leaf_counts: [DUST_RELAXATION_LEAF_COUNT]i32,
    dust_relaxation_leaf_momentum_x: [DUST_RELAXATION_LEAF_COUNT]f32,
    dust_relaxation_leaf_momentum_y: [DUST_RELAXATION_LEAF_COUNT]f32,
    dust_relaxation_leaf_residual_energy: [DUST_RELAXATION_LEAF_COUNT]f32,
    dust_relaxation_leaf_max_impulse: [DUST_RELAXATION_LEAF_COUNT]f32,
    dust_relaxation_leaf_max_correction: [DUST_RELAXATION_LEAF_COUNT]f32,
    dust_relaxation_leaf_quiet_frames: [DUST_RELAXATION_LEAF_COUNT]u16,
    dust_relaxation_leaf_last_seen: [DUST_RELAXATION_LEAF_COUNT]u64,
    dust_relaxation_leaf_indices: [MAX_LOW_PARTICLES]i32,
    dust_relaxation_active_leaves: [DUST_RELAXATION_LEAF_COUNT]i32,
    dust_relaxation_active_leaf_count: int,
    dust_relaxation_dense_leaf_count: int,
    dust_relaxation_energy_removed: f32,
    dust_activity_frames: [MAX_LOW_PARTICLES]u8,
    dust_contact_impulse: [MAX_LOW_PARTICLES]f32,
    dust_contact_correction: [MAX_LOW_PARTICLES]f32,
    dust_sleep_quiet_frames: [MAX_LOW_PARTICLES]u16,
    dust_sleeping: [MAX_LOW_PARTICLES]bool,
    dust_sleeping_count: int,
    dust_sleep_transition_count: u64,
    dust_wake_transition_count: u64,
    dust_sleeping_pair_skip_count: u64,
    dust_relaxation_frame: u64,

    next_index: int,
    spawn_timer: f32,
    rng_state: rand.Xoshiro256_Random_State,

    last_render_low: int,
    last_render_mid: int,
    last_render_high: int,

    use_max_dust_particles: int,
}
