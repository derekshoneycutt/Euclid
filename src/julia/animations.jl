"""
Reusable animation-motion helpers for EuclidApp scripts.

`EuclidAnimations` provides shared pen/compass motion primitives and higher-level
draw helpers that orchestrate bridge calls through `OdinJuliaBridge`. Animation
modules should consume this API to keep motion pacing and tool behavior consistent
across Euclid content and Terminal workflows.
"""
module EuclidAnimations

using ..OdinJuliaBridge
using ..EuclidGeometry

using LinearAlgebra

export animate_pen_descend, animate_pen_rise, animate_compass_descend,
    animate_compass_rise, animate_pen_tilt, animate_pen_cone, animate_pen_drag,
    animate_pen_arcmove, animate_compass_arcmove, animate_highlight_point,
    animate_extend_line, animate_pen_tilt_and_drag, animate_draw_point,
    animate_draw_line,
    animate_draw_filledcircle,
    animate_draw_two_line_segments,
    animate_draw_circle, animate_compass_fill_arc_highlight,
    animate_compass_arc_highlight,
    animate_repl_draw_point, animate_repl_draw_line,
    animate_repl_draw_circle, animate_repl_draw_filledcircle,
    transform_translate_point,
    transform_rotate_point, transform_rotate_point_x,
    transform_rotate_point_y, transform_rotate_point_z,
    transform_reflect2d_point, transform_reflect2d_point_negative,
    transform_reflect2d_point_x_axis,
    transform_reflect2d_point_y_axis, transform_reflect2d_point_diag_pos,
    transform_reflect2d_point_diag_neg,
    reflected_angle_marker_pose_xy,
    animate_reflect2d_filled_angle_marker,
    reveal_label, reveal_region,
    animate_cycloid_descend, animate_draw_cycloid, animate_cycloid_rise,
    animate_trochoid_descend, animate_draw_trochoid, animate_trochoid_rise,
    animate_parabola_descend, animate_draw_parabola, animate_parabola_rise,
    animate_hyperbola_descend, animate_draw_hyperbola, animate_hyperbola_rise

include("animations/common.jl")
include("animations/transforms.jl")
include("animations/pen.jl")
include("animations/compass.jl")
include("animations/strokes.jl")
include("animations/circles.jl")
include("animations/completion.jl")
include("animations/repl.jl")
include("animations/cycloids.jl")
include("animations/trochoids.jl")
include("animations/conics.jl")

end
