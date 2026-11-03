"""Position the integrated parabola apparatus without changing authored flow."""
function place_parabola_tool(state_ptr::Ptr{Cvoid}, vertex,
    parameter::Real, elevation::Real)
    checked_curve_status(OdinJuliaBridge.set_parabola_tool_position(
        state_ptr, (vertex[1], vertex[2], vertex[3] + elevation)))
    checked_curve_status(
        OdinJuliaBridge.set_parabola_tool_parameter(state_ptr, parameter))
end

"""Lower an inactive parabola apparatus to the exact starting parameter."""
function animate_parabola_descend(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, vertex, parameter_start::Real; color)
    checked_curve_status(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 0, color))
    place_parabola_tool(state_ptr, vertex, parameter_start,
        topz * (1f0 - normalized_progress(timer, duration)))
    checked_curve_status(OdinJuliaBridge.show_parabola_tool(state_ptr))
end

"""Advance the parabola apparatus, analytic frontier and ordinary tracing trail."""
function animate_draw_parabola(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, vertex, focal_distance::Real,
    parameter_start::Real, parameter_finish::Real;
    curve_id::Integer, color, rotation::Real=0f0)
    parameter = curve_parameter(timer, duration, parameter_start, parameter_finish)
    place_parabola_tool(state_ptr, vertex, parameter, 0f0)
    checked_curve_status(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 1, color))
    checked_curve_status(
        OdinJuliaBridge.set_parabola_frontier(state_ptr, curve_id, parameter))
    tip = EuclidGeometry.parabola_point(
        vertex, focal_distance, parameter; rotation)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, tip[1], tip[2], tip[3], color)
end

"""Lift an inactive parabola apparatus from its actual final tracing pose."""
function animate_parabola_rise(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, vertex, parameter_finish::Real; color)
    checked_curve_status(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 0, color))
    place_parabola_tool(state_ptr, vertex, parameter_finish,
        topz * normalized_progress(timer, duration))
end

"""Position the paired hyperbola apparatus without changing the curve frontier."""
function place_hyperbola_tool(state_ptr::Ptr{Cvoid}, center,
    parameter::Real, elevation::Real)
    checked_curve_status(OdinJuliaBridge.set_hyperbola_tool_position(
        state_ptr, (center[1], center[2], center[3] + elevation)))
    checked_curve_status(
        OdinJuliaBridge.set_hyperbola_tool_parameter(state_ptr, parameter))
end

"""Lower both inactive hyperbola pens using the existing paired-contact API."""
function animate_hyperbola_descend(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, center, parameter_start::Real; color)
    checked_curve_status(OdinJuliaBridge.set_hyperbola_tool_active(state_ptr, 0, color))
    place_hyperbola_tool(state_ptr, center, parameter_start,
        topz * (1f0 - normalized_progress(timer, duration)))
    checked_curve_status(OdinJuliaBridge.show_hyperbola_tool(state_ptr))
end

"""Move both hyperbola pens while selected tips alone leave authored ink."""
function animate_draw_hyperbola(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, center, semimajor::Real, semiminor::Real,
    parameter_start::Real, parameter_finish::Real;
    curve_id::Integer, color, rotation::Real=0f0, branches::Symbol=:both)
    selection = OdinJuliaBridge.hyperbola_branches(branches)
    parameter = curve_parameter(timer, duration, parameter_start, parameter_finish)
    place_hyperbola_tool(state_ptr, center, parameter, 0f0)
    checked_curve_status(OdinJuliaBridge.set_hyperbola_tool_active(
        state_ptr, 1, color; branches))
    checked_curve_status(OdinJuliaBridge.set_hyperbola_frontier(
        state_ptr, curve_id, parameter))
    for branch in (1, -1)
        selected_branch = branch == 1 ? OdinJuliaBridge.HYPERBOLA_POSITIVE :
            OdinJuliaBridge.HYPERBOLA_NEGATIVE
        selection != OdinJuliaBridge.HYPERBOLA_BOTH &&
            selection != selected_branch && continue
        tip = EuclidGeometry.hyperbola_point(
            center, semimajor, semiminor, parameter; branch, rotation)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, tip[1], tip[2], tip[3], color)
    end
end

"""Lift both inactive hyperbola pens from the final paired tracing parameter."""
function animate_hyperbola_rise(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, center, parameter_finish::Real; color)
    checked_curve_status(OdinJuliaBridge.set_hyperbola_tool_active(state_ptr, 0, color))
    place_hyperbola_tool(state_ptr, center, parameter_finish,
        topz * normalized_progress(timer, duration))
end
