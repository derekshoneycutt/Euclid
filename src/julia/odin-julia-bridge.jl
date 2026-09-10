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

export BridgeColor, BridgePointView, BridgeConstraintView, BridgeConstraintSpec,
    BridgeSolveResult,
    PresentationMime, PresentedText, TextPlain, TextLatex,
    PRESENTATION_MAX_SOURCE_BYTES, presented_text, present,
    AnimationKey, animation_schema_id, set_animation_value!, get_animation_value,
    BridgeShapeLine, BridgeShapeCircle, BridgeShapeFilledCircle, BridgeShapeTriangle,
    BridgeShapeSquare, BridgeShapePentagon, BridgeShapePen, BridgeShapeCompass,
    LABEL_DECORATION_NONE, LABEL_DECORATION_PRIME, LABEL_DECORATION_DOUBLEPRIME,
    LABEL_DECORATION_TRIPLEPRIME, LABEL_DECORATION_HAT, LABEL_DECORATION_BAR,
    BRIDGE_STATUS_OK, BRIDGE_STATUS_INVALID_INDEX, BRIDGE_STATUS_INVALID_ARGUMENT,
    BRIDGE_STATUS_INVALID_GRAPH, BRIDGE_STATUS_INVALID_CONSTRAINT,
    BRIDGE_STATUS_OUT_OF_CAPACITY, BRIDGE_STATUS_ILLEGAL_STATE,
    BRIDGE_STATUS_NON_CONVERGED, BRIDGE_STATUS_NOT_FOUND,
    BRIDGE_STATUS_SCHEMA_MISMATCH,
    BRIDGE_VERSION, BRIDGE_FEATURE_TYPED_ANIMATION_STATE,
    BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG, BRIDGE_FEATURE_MIME_PRESENTATION,
    CONSTRAINT_SPEC_TRAITS, CONSTRAINT_SPEC_ONPOINT, CONSTRAINT_SPEC_RESTRICTION,
    CONSTRAINT_SPEC_BOUNCE, CONSTRAINT_SPEC_ALLOWANCE, CONSTRAINT_SPEC_DEPENDON,
    CONSTRAINT_SPEC_CHILDOFFSET, CONSTRAINT_SPEC_DOAPPLY,
    bridge_color, set_null_animations, add_root_animation_interface,
    add_child_animation_interface, add_animation_descriptor, bind_animation_entry,
    create_new_label, create_new_label_decorated,
    create_new_point, create_new_line, create_new_circle, create_new_filledcircle,
    create_new_triangle, create_new_square, create_new_pentagon, get_point, show_point,
    hide_point, hide_point_batch, set_point_position, set_point_brush, set_point_color,
    set_point_active_color, notify_animation_cycle_boundary,
    publish_view_content, publish_presented_text,
    get_bridge_version,
    get_bridge_feature_flags, get_point_capacity, get_point_next_index,
    is_point_index_in_range, set_point_draw_enabled, set_point_position_status,
    clear_point_position, set_point_color_status, clear_point_color,
    set_point_active_color_status, clear_point_active_color, set_point_brush_size,
    set_point_offset, attach_child_point, detach_child_point, rebuild_child_count,
    validate_parent_child_chain, get_constraint_capacity, get_constraint_next_index,
    is_constraint_index_in_range, get_constraint_view, create_constraint,
    update_constraint, set_constraint_enabled, clear_constraint,
    get_total_constraint_error_bridge, get_constraint_error_bridge,
    apply_constraint_bridge, apply_all_constraints_bridge, solve_constraints_to_error,
    get_shape_line_view, get_shape_circle_view, get_shape_filledcircle_view,
    get_shape_triangle_view, get_shape_square_view, get_shape_pentagon_view,
    get_pen_view, get_compass_view, get_shapes_anim_points_start,
    get_shapes_anim_constraints_start, freeze_shapes_animation_boundary,
    clear_shapes_animation_data, get_max_shapes_points, get_max_shapes_constraints,
    validate_shapes_graph, show_pen, hide_pen, set_pen_active, clear_pen_active,
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

