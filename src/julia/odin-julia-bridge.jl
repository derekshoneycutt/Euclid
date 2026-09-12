"""
Julia wrapper layer over the Odin bridge API used by Euclid animations.

`OdinJuliaBridge` defines bridge-facing structs/constants and provides typed
wrapper functions around native `@ccall` entrypoints. Animation scripts should
use this module as the public host-integration surface for creating geometry,
controlling tools, managing constraints, and emitting particles.
"""
module OdinJuliaBridge

using Colors
using UUIDs

export BridgeColor, BridgePointView, BridgeSolveResult,
    PresentationMime, PresentedText, TextPlain, TextLatex,
    PRESENTATION_MAX_SOURCE_BYTES, presented_text, present,
    AnimationKey, animation_schema_id, set_animation_value!, get_animation_value,
    BridgeShapeLine, BridgeShapeCircle, BridgeShapeFilledCircle, BridgeShapeTriangle,
    BridgeShapeSquare, BridgeShapePentagon,
    BRIDGE_STATUS_OK, BRIDGE_STATUS_INVALID_INDEX, BRIDGE_STATUS_INVALID_ARGUMENT,
    BRIDGE_STATUS_INVALID_GRAPH, BRIDGE_STATUS_INVALID_CONSTRAINT,
    BRIDGE_STATUS_OUT_OF_CAPACITY, BRIDGE_STATUS_ILLEGAL_STATE,
    BRIDGE_STATUS_NON_CONVERGED, BRIDGE_STATUS_NOT_FOUND,
    BRIDGE_STATUS_SCHEMA_MISMATCH,
    BRIDGE_VERSION, BRIDGE_FEATURE_TYPED_ANIMATION_STATE,
    BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG, BRIDGE_FEATURE_MIME_PRESENTATION,
    bridge_color, set_null_animations, add_root_animation_interface,
    add_child_animation_interface, add_animation_descriptor, bind_animation_entry,
    create_new_label,
    create_new_point, create_new_line, create_new_circle, create_new_filledcircle,
    create_new_triangle, create_new_square, create_new_pentagon, get_point, show_point,
    hide_point, hide_point_batch, set_point_position, set_point_brush, set_point_color,
    set_point_active_color, notify_animation_cycle_boundary,
    publish_view_content, publish_presented_text,
    get_bridge_version,
    get_bridge_feature_flags, set_point_position_status,
    set_point_active_color_status, set_point_brush_size, set_point_offset,
    create_floor_constraint, create_snap_to_floor_constraint,
    create_snap_point_constraint, create_distance_constraint,
    create_max_angle_constraint, create_min_angle_constraint,
    create_center_pivot_constraint, get_total_constraint_error_bridge,
    apply_all_constraints_bridge, solve_constraints_to_error,
    show_pen, hide_pen, set_pen_active, clear_pen_active,
    lock_pen_joint1, unlock_pen_joint1, move_pen_joint1, get_pen_joint1_position,
    lock_pen_joint2, unlock_pen_joint2, move_pen_joint2, get_pen_joint2_position,
    show_compass, hide_compass, set_compass_active, clear_compass_active,
    lock_compass_joint1, unlock_compass_joint1, move_compass_joint1,
    get_compass_joint1_position, lock_compass_joint2, unlock_compass_joint2,
    move_compass_joint2, get_compass_joint2_position,
    emit_trailing_particle, emit_flicker_particle

include("bridge/common.jl")
include("bridge/points.jl")
include("bridge/constraints.jl")
include("bridge/tools.jl")
include("bridge/animations.jl")
include("bridge/presentation.jl")

end

