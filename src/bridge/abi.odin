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

BRIDGE_LABEL_DECORATION_NONE :: i32(core.Shapes_Label_Decoration_Kind.None)
BRIDGE_LABEL_DECORATION_PRIME :: i32(core.Shapes_Label_Decoration_Kind.Prime)
BRIDGE_LABEL_DECORATION_DOUBLEPRIME :: i32(core.Shapes_Label_Decoration_Kind.Double_Prime)
BRIDGE_LABEL_DECORATION_TRIPLEPRIME :: i32(core.Shapes_Label_Decoration_Kind.Triple_Prime)
BRIDGE_LABEL_DECORATION_HAT :: i32(core.Shapes_Label_Decoration_Kind.Hat)
BRIDGE_LABEL_DECORATION_BAR :: i32(core.Shapes_Label_Decoration_Kind.Bar)

SHAPES_CONSTRAINT_KIND_MIN :: i32(core.Shapes_Constraint_Kind.Distance)
SHAPES_CONSTRAINT_KIND_MAX :: i32(core.Shapes_Constraint_Kind.Center_Pivot)

CONSTRAINT_SPEC_TRAITS :: (1 << 0)
CONSTRAINT_SPEC_ONPOINT :: (1 << 1)
CONSTRAINT_SPEC_RESTRICTION :: (1 << 2)
CONSTRAINT_SPEC_BOUNCE :: (1 << 3)
CONSTRAINT_SPEC_ALLOWANCE :: (1 << 4)
CONSTRAINT_SPEC_DEPENDON :: (1 << 5)
CONSTRAINT_SPEC_CHILDOFFSET :: (1 << 6)
CONSTRAINT_SPEC_DOAPPLY :: (1 << 7)

Bridge_Color :: core.Bridge_Color

Bridge_Point_View :: struct {
    valid: bool,
    index: int,

    point_type: int,
    do_draw: bool,
    brush_size: f32,
    offset: f32,

    has_position: bool,
    position: core.Vector3,
    
    has_color: bool,
    color: Bridge_Color,

    has_active_color: bool,
    active_color: Bridge_Color,

    has_label : bool,
    label : rune,
    decoration_kind: i32,

    active_child: int,
    child_count: int,
    child_point_head: int,
    next_child_point: int,
}

Bridge_Constraint_View :: struct {
    valid: u8,
    index: i32,

    traits: i32,
    on_point: i32,
    restriction: core.Vector3,
    bounce: f32,
    allowance: f32,
    depend_on: i32,
    has_child_offset: u8,
    child_offset: i32,
    do_apply: u8,
}

Bridge_Constraint_Spec :: struct {
    traits: i32,
    on_point: i32,
    restriction: core.Vector3,
    bounce: f32,
    allowance: f32,
    depend_on: i32,
    has_child_offset: u8,
    child_offset: i32,
    do_apply: u8,
}

Bridge_Solve_Result :: struct {
    status: i32,
    iterations: i32,
    initial_error: f32,
    final_error: f32,
    converged: u8,
}
