"""
Reset the host dynview stream for the current state/frame.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_reset_stream(state_ptr::Ptr{Cvoid})
    @ccall dynview_reset_stream(state_ptr::Ptr{Cvoid})::Int32
end

"""
Begin a host dynview block for subsequent content commands.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_begin_block(state_ptr::Ptr{Cvoid}, block_kind::Integer, block_id::Integer)
    @ccall dynview_begin_block(
        state_ptr::Ptr{Cvoid},
        Int32(block_kind)::Int32,
        Int32(block_id)::Int32)::Int32
end

"""
Emit a visible text run inside the currently open host dynview block.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_text_run(state_ptr::Ptr{Cvoid}, text::AbstractString, style_id::Integer)
    @ccall dynview_text_run(
        state_ptr::Ptr{Cvoid},
        text::Cstring,
        Int32(style_id)::Int32)::Int32
end

"""
Emit a visible text run with an explicit brush color override.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_text_run_brush(
    state_ptr::Ptr{Cvoid},
    text::AbstractString,
    style_id::Integer,
    brush_color::BridgeColor)

    @ccall dynview_text_run_brush(
        state_ptr::Ptr{Cvoid},
        text::Cstring,
        Int32(style_id)::Int32,
        brush_color::BridgeColor)::Int32
end
function dynview_text_run_brush(
    state_ptr::Ptr{Cvoid},
    text::AbstractString,
    style_id::Integer,
    brush_color::Colorant)

    dynview_text_run_brush(state_ptr, text, style_id, bridge_color(brush_color))
end
function dynview_text_run_brush(
    state_ptr::Ptr{Cvoid},
    text::AbstractString,
    style_id::Integer,
    brush_color::Symbol)

    dynview_text_run_brush(state_ptr, text, style_id, bridge_color(brush_color))
end
function dynview_text_run_brush(
    state_ptr::Ptr{Cvoid},
    text::AbstractString,
    style_id::Integer,
    brush_color::AbstractString)

    dynview_text_run_brush(state_ptr, text, style_id, bridge_color(brush_color))
end

"""
Emit a visible math-glyph run inside the currently open host dynview block.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_math_glyph_run(state_ptr::Ptr{Cvoid}, text::AbstractString, style_id::Integer)
    @ccall dynview_math_glyph_run(
        state_ptr::Ptr{Cvoid},
        text::Cstring,
        Int32(style_id)::Int32)::Int32
end

"""
Emit one whole inline math block inside the currently open host dynview block.

This bridge surface is reserved for recursive, non-wrapping math-block layout.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_math_block(
    state_ptr::Ptr{Cvoid},
    latex_source::AbstractString,
    style_id::Integer)

    @ccall dynview_math_block(
        state_ptr::Ptr{Cvoid},
        latex_source::Cstring,
        Int32(style_id)::Int32)::Int32
end

"""
Emit one whole inline math block using a compiled flat math-op stream and shared text blob.

This is the bridge surface used by recursive-supportive math-block layout work.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_math_block_from_ops(
    state_ptr::Ptr{Cvoid},
    plain_text::AbstractString,
    style_id::Integer,
    ops::Vector{BridgeDynviewMathOp},
    top_level_op_count::Integer,
    text_blob::AbstractString)

    op_count = Int32(length(ops))
    GC.@preserve ops plain_text text_blob begin
        ops_ptr = op_count > 0 ? pointer(ops) : Ptr{BridgeDynviewMathOp}(C_NULL)
        @ccall dynview_math_block_from_ops(
            state_ptr::Ptr{Cvoid},
            plain_text::Cstring,
            Int32(style_id)::Int32,
            ops_ptr::Ptr{BridgeDynviewMathOp},
            op_count::Int32,
            Int32(top_level_op_count)::Int32,
            text_blob::Cstring)::Int32
    end
end

"""
Emit a non-rendering copy payload segment for the currently open host dynview block.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_copyable_text_run(
    state_ptr::Ptr{Cvoid},
    copy_text::AbstractString)

    @ccall dynview_copyable_text_run(
        state_ptr::Ptr{Cvoid},
        copy_text::Cstring)::Int32
end

"""
Emit one inline line atom inside the currently open host dynview block.

Length is expressed in wrap-column units; thickness is in host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_line(
    state_ptr::Ptr{Cvoid},
    length::Real,
    thickness::Real,
    style_id::Integer)

    @ccall dynview_inline_line(
        state_ptr::Ptr{Cvoid},
        Cfloat(length)::Cfloat,
        Cfloat(thickness)::Cfloat,
        Int32(style_id)::Int32)::Int32
end

"""
Emit one inline box atom inside the currently open host dynview block.

Width and height are expressed in wrap-column units; stroke is host pixel thickness.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_box(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer)

    @ccall dynview_inline_box(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32)::Int32
end

"""
Emit one inline circle atom inside the currently open host dynview block.

Radius is expressed in wrap-column units; stroke is host pixel thickness.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_circle(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    stroke::Real,
    style_id::Integer)

    @ccall dynview_inline_circle(
        state_ptr::Ptr{Cvoid},
        Cfloat(radius)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32)::Int32
end

"""
Emit one inline line atom with explicit brush color override.

Length is in wrap-column units; thickness is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_line_brush(
    state_ptr::Ptr{Cvoid},
    length::Real,
    thickness::Real,
    style_id::Integer,
    brush_color::BridgeColor)

    @ccall dynview_inline_line_brush(
        state_ptr::Ptr{Cvoid},
        Cfloat(length)::Cfloat,
        Cfloat(thickness)::Cfloat,
        Int32(style_id)::Int32,
        brush_color::BridgeColor)::Int32
end
function dynview_inline_line_brush(
    state_ptr::Ptr{Cvoid},
    length::Real,
    thickness::Real,
    style_id::Integer,
    brush_color::Colorant)

    dynview_inline_line_brush(state_ptr, length, thickness, style_id, bridge_color(brush_color))
end
function dynview_inline_line_brush(
    state_ptr::Ptr{Cvoid},
    length::Real,
    thickness::Real,
    style_id::Integer,
    brush_color::Symbol)

    dynview_inline_line_brush(state_ptr, length, thickness, style_id, bridge_color(brush_color))
end
function dynview_inline_line_brush(
    state_ptr::Ptr{Cvoid},
    length::Real,
    thickness::Real,
    style_id::Integer,
    brush_color::AbstractString)

    dynview_inline_line_brush(state_ptr, length, thickness, style_id, bridge_color(brush_color))
end

"""
Emit one inline box atom with explicit brush color override.

Width and height are in wrap-column units; stroke is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_box_brush(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::BridgeColor)

    @ccall dynview_inline_box_brush(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        brush_color::BridgeColor)::Int32
end
function dynview_inline_box_brush(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::Colorant)

    dynview_inline_box_brush(state_ptr, width, height, stroke, style_id, bridge_color(brush_color))
end
function dynview_inline_box_brush(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::Symbol)

    dynview_inline_box_brush(state_ptr, width, height, stroke, style_id, bridge_color(brush_color))
end
function dynview_inline_box_brush(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::AbstractString)

    dynview_inline_box_brush(state_ptr, width, height, stroke, style_id, bridge_color(brush_color))
end

"""
Emit one inline circle atom with explicit brush color override.

Radius is in wrap-column units; stroke is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_circle_brush(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::BridgeColor)

    @ccall dynview_inline_circle_brush(
        state_ptr::Ptr{Cvoid},
        Cfloat(radius)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        brush_color::BridgeColor)::Int32
end
function dynview_inline_circle_brush(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::Colorant)

    dynview_inline_circle_brush(state_ptr, radius, stroke, style_id, bridge_color(brush_color))
end
function dynview_inline_circle_brush(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::Symbol)

    dynview_inline_circle_brush(state_ptr, radius, stroke, style_id, bridge_color(brush_color))
end
function dynview_inline_circle_brush(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    stroke::Real,
    style_id::Integer,
    brush_color::AbstractString)

    dynview_inline_circle_brush(state_ptr, radius, stroke, style_id, bridge_color(brush_color))
end

"""
Emit one filled inline box atom.

Width and height are in wrap-column units; outline_stroke is optional host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_filled_box(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    style_id::Integer,
    fill_color::BridgeColor,
    outline_stroke::Real=0)

    @ccall dynview_inline_filled_box(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Int32(style_id)::Int32,
        fill_color::BridgeColor,
        Cfloat(outline_stroke)::Cfloat)::Int32
end
function dynview_inline_filled_box(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    style_id::Integer,
    fill_color::Colorant,
    outline_stroke::Real=0)

    dynview_inline_filled_box(state_ptr, width, height, style_id, bridge_color(fill_color), outline_stroke)
end
function dynview_inline_filled_box(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    style_id::Integer,
    fill_color::Symbol,
    outline_stroke::Real=0)

    dynview_inline_filled_box(state_ptr, width, height, style_id, bridge_color(fill_color), outline_stroke)
end
function dynview_inline_filled_box(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    style_id::Integer,
    fill_color::AbstractString,
    outline_stroke::Real=0)

    dynview_inline_filled_box(state_ptr, width, height, style_id, bridge_color(fill_color), outline_stroke)
end

"""
Emit one filled inline circle atom.

Radius is in wrap-column units; outline_stroke is optional host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_filled_circle(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    style_id::Integer,
    fill_color::BridgeColor,
    outline_stroke::Real=0)

    @ccall dynview_inline_filled_circle(
        state_ptr::Ptr{Cvoid},
        Cfloat(radius)::Cfloat,
        Int32(style_id)::Int32,
        fill_color::BridgeColor,
        Cfloat(outline_stroke)::Cfloat)::Int32
end
function dynview_inline_filled_circle(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    style_id::Integer,
    fill_color::Colorant,
    outline_stroke::Real=0)

    dynview_inline_filled_circle(state_ptr, radius, style_id, bridge_color(fill_color), outline_stroke)
end
function dynview_inline_filled_circle(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    style_id::Integer,
    fill_color::Symbol,
    outline_stroke::Real=0)

    dynview_inline_filled_circle(state_ptr, radius, style_id, bridge_color(fill_color), outline_stroke)
end
function dynview_inline_filled_circle(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    style_id::Integer,
    fill_color::AbstractString,
    outline_stroke::Real=0)

    dynview_inline_filled_circle(state_ptr, radius, style_id, bridge_color(fill_color), outline_stroke)
end

"""
Emit one filled inline pie section atom.

Radius is in wrap-column units. Angles are in degrees with positive sweep wrapping.
outline_stroke is optional host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_pie_section(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    start_angle_degrees::Real,
    end_angle_degrees::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::BridgeColor,
    arc_color::BridgeColor=fill_color,
    outline_stroke::Real=0)

    @ccall dynview_inline_pie_section(
        state_ptr::Ptr{Cvoid},
        Cfloat(radius)::Cfloat,
        Cfloat(start_angle_degrees)::Cfloat,
        Cfloat(end_angle_degrees)::Cfloat,
        Int32(style_id)::Int32,
        filled::Bool,
        fill_color::BridgeColor,
        arc_color::BridgeColor,
        Cfloat(outline_stroke)::Cfloat)::Int32
end
function dynview_inline_pie_section(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    start_angle_degrees::Real,
    end_angle_degrees::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::Colorant,
    arc_color::Colorant=fill_color,
    outline_stroke::Real=0)

    dynview_inline_pie_section(state_ptr, radius, start_angle_degrees, end_angle_degrees,
        style_id, filled, bridge_color(fill_color), bridge_color(arc_color), outline_stroke)
end

"""
Emit one inline perpendicular atom.

Length is the horizontal top bar; stem_height is the vertical drop.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_perpendicular(
    state_ptr::Ptr{Cvoid},
    length::Real,
    stem_height::Real,
    stroke::Real,
    style_id::Integer,
    top_color::BridgeColor,
    stem_color::BridgeColor)

    @ccall dynview_inline_perpendicular(
        state_ptr::Ptr{Cvoid},
        Cfloat(length)::Cfloat,
        Cfloat(stem_height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        top_color::BridgeColor,
        stem_color::BridgeColor)::Int32
end

"""
Emit one inline triangle atom.

Width and height are in wrap-column units; stroke is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_triangle(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::BridgeColor,
    edge1_color::BridgeColor,
    edge2_color::BridgeColor,
    edge3_color::BridgeColor)

    @ccall dynview_inline_triangle(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        filled::Bool,
        fill_color::BridgeColor,
        edge1_color::BridgeColor,
        edge2_color::BridgeColor,
        edge3_color::BridgeColor)::Int32
end

"""
Emit one inline box atom with four independently colored edges.

Width and height are in wrap-column units; stroke is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_box_edges(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    edge1_color::BridgeColor,
    edge2_color::BridgeColor,
    edge3_color::BridgeColor,
    edge4_color::BridgeColor)

    @ccall dynview_inline_box_edges(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        edge1_color::BridgeColor,
        edge2_color::BridgeColor,
        edge3_color::BridgeColor,
        edge4_color::BridgeColor)::Int32
end

"""
Emit one inline pentagon atom.

Width and height are in wrap-column units; stroke is host pixel units.
Returns a BRIDGE_STATUS_* code.
"""
function dynview_inline_pentagon(
    state_ptr::Ptr{Cvoid},
    width::Real,
    height::Real,
    stroke::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::BridgeColor,
    edge1_color::BridgeColor,
    edge2_color::BridgeColor,
    edge3_color::BridgeColor,
    edge4_color::BridgeColor,
    edge5_color::BridgeColor)

    @ccall dynview_inline_pentagon(
        state_ptr::Ptr{Cvoid},
        Cfloat(width)::Cfloat,
        Cfloat(height)::Cfloat,
        Cfloat(stroke)::Cfloat,
        Int32(style_id)::Int32,
        filled::Bool,
        fill_color::BridgeColor,
        edge1_color::BridgeColor,
        edge2_color::BridgeColor,
        edge3_color::BridgeColor,
        edge4_color::BridgeColor,
        edge5_color::BridgeColor)::Int32
end
function dynview_inline_pie_section(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    start_angle_degrees::Real,
    end_angle_degrees::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::Symbol,
    arc_color::Symbol=fill_color,
    outline_stroke::Real=0)

    dynview_inline_pie_section(state_ptr, radius, start_angle_degrees, end_angle_degrees,
        style_id, filled, bridge_color(fill_color), bridge_color(arc_color), outline_stroke)
end
function dynview_inline_pie_section(
    state_ptr::Ptr{Cvoid},
    radius::Real,
    start_angle_degrees::Real,
    end_angle_degrees::Real,
    style_id::Integer,
    filled::Bool,
    fill_color::AbstractString,
    arc_color::AbstractString=fill_color,
    outline_stroke::Real=0)

    dynview_inline_pie_section(state_ptr, radius, start_angle_degrees, end_angle_degrees,
        style_id, filled, bridge_color(fill_color), bridge_color(arc_color), outline_stroke)
end

"""
Emit one line-break command inside the currently open host dynview block.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_line_break(state_ptr::Ptr{Cvoid})
    @ccall dynview_line_break(state_ptr::Ptr{Cvoid})::Int32
end

"""
End the currently open host dynview block.

Returns a BRIDGE_STATUS_* code.
"""
function dynview_end_block(state_ptr::Ptr{Cvoid})
    @ccall dynview_end_block(state_ptr::Ptr{Cvoid})::Int32
end
