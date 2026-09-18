package particlemodel

import rand "core:math/rand"

import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 65536
MAX_PARTICLES :: 2048
DUST_ATLAS_VARIANT_COUNT :: 9

DUST_FIELD_DIM :: 251
DUST_FIELD_NODE_COUNT :: DUST_FIELD_DIM * DUST_FIELD_DIM
DUST_FIELD_STENCIL_CAP :: 4
DUST_SETTLED_SPEED_SQ :: f32(1e-8)
DUST_TOOL_CONTACT_CAP :: 64
SCENARIO_DUST_EMISSION_REQUEST_CAP :: 16

// Store one fixed scalar plane over the global dust-field topology.
Dust_Field_Scalar :: [DUST_FIELD_NODE_COUNT]f32

// Describe the four field nodes influencing one board-space position.
Dust_Field_Stencil :: struct {
    indices: [DUST_FIELD_STENCIL_CAP]i32,
    weights: [DUST_FIELD_STENCIL_CAP]f32,
}

// Cache one grounded particle's compact bilinear transfer coordinates.
Dust_Transfer :: struct {
    particle_index: i32,
    base_node: i32,
    fraction_x, fraction_y: f32,
}

// Describe one inclusive rectangular region of the vector-dust field.
Dust_Field_Bounds :: struct {
    min_x, min_y: i32,
    max_x, max_y: i32,
    valid: bool,
}

// Own the fixed physics planes for the field-only grounded-dust experiment.
Dust_Field_State :: struct {
    density: Dust_Field_Scalar,
    momentum_x: Dust_Field_Scalar,
    momentum_y: Dust_Field_Scalar,
    solved_velocity_x: Dust_Field_Scalar,
    solved_velocity_y: Dust_Field_Scalar,
    support_bounds: Dust_Field_Bounds,
    previous_solve_bounds: Dust_Field_Bounds,
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

// Identify the owner semantics used to coalesce adjacent tool contacts.
Dust_Tool_Contact_Source :: enum u8 {
    Point,
    Compass_Filled_Sweep,
    Scenario,
}

// Describe one ordered point push or compound filled-compass sweep.
Dust_Tool_Contact :: struct {
    endpoint: rl.Vector3,
    previous_segment_first: rl.Vector3,
    previous_segment_second: rl.Vector3,
    segment_first: rl.Vector3,
    segment_second: rl.Vector3,
    max_spawn_sequence: u64,
    has_sweep: bool,
    source: Dust_Tool_Contact_Source,
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

    dust_tool_contacts: [DUST_TOOL_CONTACT_CAP]Dust_Tool_Contact,
    dust_tool_contact_count: int,
    dust_tool_contact_overflow_count: int,
    dust_tool_contact_coalesced_count: u64,
    dust_tool_contact_sample_count: u64,
    dust_tool_contact_field_node_visit_count: u64,
    dust_slot_spawn_sequences: [MAX_LOW_PARTICLES]u64,
    dust_spawn_sequence: u64,

    dust_floor_rest_count: int,

    dust_field: Dust_Field_State,
    dust_transfers: [MAX_LOW_PARTICLES]Dust_Transfer,
    dust_transfer_count: int,
    dust_grounded_count: int,
    dust_peak_speed_sq: f32,
    dust_kinetic_measure: f32,

    next_index: int,
    spawn_timer: f32,
    rng_state: rand.Xoshiro256_Random_State,

    last_render_low: int,
    last_render_mid: int,
    last_render_high: int,

    use_max_dust_particles: int,
}
