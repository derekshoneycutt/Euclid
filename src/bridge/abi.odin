package bridge

// Julia module provides the Odin-Julia Bridge to coordinate all actions between the 2
// languages. Most of these are wrappers around Odin module functions with some specific
// behavior for simplicity on the animation.
// Otherwise, the rest of Julia module is the Julia code.

// We provide a basic Bridge version and feature flags capability for building onto.
// Effort was made to wrap most of what the animations might need for now in the Shapes
// system especially, and also some access to particle system.
// Doc comments are verbose in the julia companion to this, and methods are largely 1-to-1.

// Importantly, the catalogue of animations is stored as Julia Animation Interfaces in
// the Julia Interface. There is really not enough to justify separating them out, although
// it can feel a little tight here. Ultimately, the Julia is more in control of the catalogue,
// though it is stored and chosen from via the Odin.

import "../core"

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
MAX_SHAPESCONSTRAINTS :: core.MAX_SHAPESCONSTRAINTS

ANIMATION_RESET_MIN_INTERVAL :: 0.35
FLOOR_CONTACT_Z_EPSILON :: 0.015
COMPASS_LINE_DUST_SAMPLES :: 24

BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY :: (1 << 1)
BRIDGE_FEATURE_ANIMATION_STABLE_ID :: (1 << 3)
BRIDGE_FEATURE_TYPED_ANIMATION_STATE :: (1 << 4)
BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG :: (1 << 5)
BRIDGE_FEATURE_MIME_PRESENTATION :: (1 << 6)

BRIDGE_VERSION :: 6
BRIDGE_FEATURE_FLAGS :: 1 |
    BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY |
    BRIDGE_FEATURE_ANIMATION_STABLE_ID |
    BRIDGE_FEATURE_TYPED_ANIMATION_STATE |
    BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG |
    BRIDGE_FEATURE_MIME_PRESENTATION

BRIDGE_STATUS_OK :: 0
BRIDGE_STATUS_INVALID_INDEX :: 1
BRIDGE_STATUS_INVALID_ARGUMENT :: 2
BRIDGE_STATUS_INVALID_GRAPH :: 3
BRIDGE_STATUS_INVALID_CONSTRAINT :: 4
BRIDGE_STATUS_OUT_OF_CAPACITY :: 5
BRIDGE_STATUS_ILLEGAL_STATE :: 6
BRIDGE_STATUS_NON_CONVERGED :: 7
BRIDGE_STATUS_NOT_FOUND :: 8
BRIDGE_STATUS_SCHEMA_MISMATCH :: 9
BRIDGE_STATUS_INVALID_UTF8 :: 10
BRIDGE_STATUS_UNSUPPORTED_MIME :: 11

Bridge_Color :: core.Bridge_Color

// Carry presentation values shared by shape construction exports.
Bridge_Shape_Style :: struct {
    color: Bridge_Color,
    brush_size: f32,
}

// Carry one positioned shape's construction values within the ABI parameter budget.
Bridge_Positioned_Shape_Input :: struct {
    position: core.Vector3,
    style: Bridge_Shape_Style,
}

// Carry direct distance-constraint targets and policy as one ABI value.
Bridge_Distance_Constraint_Input :: struct {
    first: u64,
    second: u64,
    length: f32,
    movement: i32,
    enabled: u8,
}

// Carry direct angle-constraint targets and policy as one ABI value.
Bridge_Angle_Constraint_Input :: struct {
    first: u64,
    pivot: u64,
    second: u64,
    limit: f32,
    movement: i32,
    enabled: u8,
}

// Return one packed entity identity with an explicit operation status.
Bridge_Shape_Entity_Result :: struct {
    status: i32,
    entity: u64,
}

// Return one line host and both direct endpoint identities.
Bridge_Shape_Line_Result :: struct {
    status: i32,
    shape: u64,
    first: u64,
    second: u64,
}

// Return one arc host and all direct transform identities.
Bridge_Shape_Arc_Result :: struct {
    status: i32,
    shape: u64,
    center: u64,
    start: u64,
    finish: u64,
}

// Return one triangle host and its direct ordered vertex identities.
Bridge_Shape_Triangle_Result :: struct {
    status: i32,
    shape: u64,
    first: u64,
    second: u64,
    third: u64,
}

// Return one square host and its direct ordered vertex identities.
Bridge_Shape_Square_Result :: struct {
    status: i32,
    shape: u64,
    vertices: [4]u64,
}

// Return one pentagon host and its direct ordered vertex identities.
Bridge_Shape_Pentagon_Result :: struct {
    status: i32,
    shape: u64,
    vertices: [5]u64,
}

// Return component projections for one resolved packed entity.
Bridge_Shape_View :: struct {
    status: i32,
    entity: u64,
    kind: i32,
    visible: u8,
    has_transform: u8,
    has_style: u8,
    has_active_feature: u8,
    position: core.Vector3,
    color: Bridge_Color,
    active_color: Bridge_Color,
    has_active_color: u8,
    brush_size: f32,
    offset: f32,
    active_feature: u16,
}

// Return metadata from copying one immutable label source.
Bridge_Label_Copy_Result :: struct {
    status: i32,
    byte_count: i32,
    mime: i32,
}

Bridge_Solve_Result :: struct {
    status: i32,
    iterations: i32,
    initial_error: f32,
    final_error: f32,
    converged: u8,
}
