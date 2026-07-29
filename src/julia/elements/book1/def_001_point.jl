module ElementsOneDefinitionPoint

using ..OdinJuliaBridge
using ..EuclidAnimations
using ...EuclidLatex

export get_view_text, initialize, clean, loop

const Point = [0.5f0, 0.5f0, 0f0]

const PointColor = :steelblue
const PointMaxBrush = 5f0

const PenTopZ = 1.4f0

const DescendDuration = 3f0
const DrawDuration = 4f0
const RiseDuration = 3f0

const MetaPointId = 1
const MetaPhase = 2
const MetaTimer = 3

const PhaseDescend = 0f0
const PhaseDraw = 1f0
const PhaseRise = 2f0

const DynviewBlockOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT
const DynviewStyleBold = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_BOLD
const DynviewStyleItalic = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC
const DynviewStyleOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT

const DefinitionViewText = """Euclid Elements - Book I - Definition: Point

A point is that which has no part."""


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = DefinitionViewText

    if OdinJuliaBridge.dynview_reset_stream(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_begin_block(state_ptr, DynviewBlockOutput, Int32(1)) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_copyable_text_run(
        state_ptr,
        DefinitionViewText) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(
        state_ptr,
        "Euclid Elements - Book I - Definition: Point",
        DynviewStyleBold) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(
        state_ptr,
        "A point ",
        DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_inline_filled_circle(
        state_ptr, 1, DynviewStyleOutput, PointColor, 0) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(
        state_ptr,
        " is that which has no part.",
        DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    # TEMPORARY TESTING ONLY: Phase 1 LaTeX sample rendering.
    # Keep the original definition text and append test output on a new line.
    latex_test_source = "\\text{TEMP TEST: Phase 2} \\alpha + \\beta + \\sin(x) + f(A_1^2) + \\overline{AB^2} + \\underline{CD_4} + \\overline{A\\underline{B^2_6}} + \\mathbb{R}"
    latex_radical_test_source = "\\text{TEMP TEST: Phase 3} \\sqrt{x} + q\\sqrt[3]{AB}b + \\sqrt[n]{\\underline{A_1^2}} + \\sqrt[α]{\\overline{x}}"
    latex_largeop_test_source = "\\text{TEMP TEST: Phase 4} \\sum_{i=1}^{n} a_i + \\sqrt[2]{\\sum_{k=0}^{m} b_k} + \\prod_{j=1}^{p} \\sqrt{j} + \\int_{0}^{1} \\sqrt{x} + \\lim_{x \\to 0} \\sqrt{x}"
    latex_fraction_test_source = "\\text{TEMP TEST: Phase 5} \\frac{a+b}{c+d} + \\left(\\frac{\\sqrt{x}}{\\overline{y_1}}\\right] + \\left\\{\\frac{\\frac{m}{n}}{\\sum_{i=1}^{k} i}\\right) + \\left[\\overline{\\frac{A_1^2}{\\underline{B}}}\\right\\}"
    latex_matrix_test_source = "\\text{TEMP TEST: Phase 6} \\left(\\begin{matrix}a&\\frac{1}{2}\\\\\\sqrt{x}&d_1\\end{matrix}\\right) + \\begin{matrix}x&y&z\\\\1&2&3\\end{matrix}"
    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        latex_test_source;
        text_style=DynviewStyleOutput,
        math_style=DynviewStyleItalic)
        return fallback
    end

    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        latex_radical_test_source;
        text_style=DynviewStyleOutput,
        math_style=DynviewStyleItalic)
        return fallback
    end

    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        latex_largeop_test_source;
        text_style=DynviewStyleOutput,
        math_style=DynviewStyleItalic)
        return fallback
    end

    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        latex_fraction_test_source;
        text_style=DynviewStyleOutput,
        math_style=DynviewStyleItalic)
        return fallback
    end

    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        latex_matrix_test_source;
        text_style=DynviewStyleOutput,
        math_style=DynviewStyleItalic)
        return fallback
    end

    if OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_text_run(
        state_ptr,
        "So ends the LaTeX Testing blocks and All That Fun.",
        DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end
    # END TEMPORARY TESTING ONLY.

    if OdinJuliaBridge.dynview_end_block(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    return fallback
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    pointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point(state_ptr, pointId)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    point = OdinJuliaBridge.create_new_point(
        state_ptr, Point, PointColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointId, Float32(point.index))
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    pointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))
    if pointId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDraw
            timer = 0f0
        end
    elseif phase == PhaseDraw
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawDuration, Point,
            PointMaxBrush, PointColor, pointId)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            OdinJuliaBridge.hide_point(state_ptr, pointId)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
