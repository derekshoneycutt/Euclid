module HilbertChapterOneAxiomIV2

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineABStart = [0.14f0, 0.72f0, 0f0]
const LineABEnd = [0.86f0, 0.72f0, 0f0]
const LineAPrimeStart = [0.14f0, 0.50f0, 0f0]
const LineAPrimeEnd = [0.86f0, 0.50f0, 0f0]
const LineADoublePrimeStart = [0.14f0, 0.28f0, 0f0]
const LineADoublePrimeEnd = [0.86f0, 0.28f0, 0f0]

const PointA = [0.30f0, 0.72f0, 0f0]
const PointB = [0.54f0, 0.72f0, 0f0]
const PointAPrime = [0.30f0, 0.50f0, 0f0]
const PointBPrime = [0.54f0, 0.50f0, 0f0]
const PointADoublePrime = [0.30f0, 0.28f0, 0f0]
const PointBDoublePrime = [0.54f0, 0.28f0, 0f0]

const PenTopZ = 1.4f0

const LabelColor = :plum1
const DragColor = :lightgreen
const LineABColor = :steelblue
const LineAPrimeColor = :palevioletred1
const LineADoublePrimeColor = :khaki3

const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointAPrimeColor = :khaki3
const PointBPrimeColor = :steelblue
const PointADoublePrimeColor = :steelblue
const PointBDoublePrimeColor = :palevioletred1

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const LabelAPoint = PointA + [0f0, 0.07f0, 0f0]
const LabelBPoint = PointB + [0f0, 0.07f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0f0, 0.07f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0f0, 0.07f0, 0f0]
const LabelADoublePrimePoint = PointADoublePrime + [0f0, 0.07f0, 0f0]
const LabelBDoublePrimePoint = PointBDoublePrime + [0f0, 0.07f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 2.5f0
const ArcMoveDuration = 1.4f0
const PointDrawDuration = 1.6f0
const DragDuration = 1.5f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineABHostId = 1
const MetaLineABJoint1Id = 2
const MetaLineABJoint2Id = 3
const MetaLineAPrimeHostId = 11
const MetaLineAPrimeJoint1Id = 12
const MetaLineAPrimeJoint2Id = 13
const MetaLineADoublePrimeHostId = 21
const MetaLineADoublePrimeJoint1Id = 22
const MetaLineADoublePrimeJoint2Id = 23

const MetaPointAId = 31
const MetaPointBId = 32
const MetaPointAPrimeId = 33
const MetaPointBPrimeId = 34
const MetaPointADoublePrimeId = 35
const MetaPointBDoublePrimeId = 36

const MetaLabelAId = 41
const MetaLabelBId = 42
const MetaLabelAPrimeId = 43
const MetaLabelBPrimeId = 44
const MetaLabelADoublePrimeId = 45
const MetaLabelBDoublePrimeId = 46

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineAB = 1f0
const PhaseMoveToA = 2f0
const PhaseDrawA = 3f0
const PhaseMoveToB = 4f0
const PhaseDrawB = 5f0
const PhaseMoveToLineAPrimeStart = 6f0
const PhaseDrawLineAPrime = 7f0
const PhaseMoveToAPrime = 8f0
const PhaseDrawAPrime = 9f0
const PhaseMoveToBPrime = 10f0
const PhaseDrawBPrime = 11f0
const PhaseMoveToLineADoublePrimeStart = 12f0
const PhaseDrawLineADoublePrime = 13f0
const PhaseMoveToADoublePrime = 14f0
const PhaseDrawADoublePrime = 15f0
const PhaseMoveToBDoublePrime = 16f0
const PhaseDrawBDoublePrime = 17f0
const PhaseArcFromBDoublePrimeToA = 17.5f0
const PhaseDragAToB = 18f0
const PhaseDragBToA = 19f0
const PhaseArcToAPrime = 20f0
const PhaseDragAPrimeToBPrime = 21f0
const PhaseDragBPrimeToAPrime = 22f0
const PhaseArcToADoublePrime = 23f0
const PhaseDragADoublePrimeToBDoublePrime = 24f0
const PhaseDragBDoublePrimeToADoublePrime = 25f0
const PhaseArcToA = 26f0
const PhaseDragAToBAgain = 27f0
const PhaseDragBToAAgain = 28f0
const PhaseEndLift = 29f0
const PhaseFinalHold = 30f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom IV,2

IV, 2. If a segment AB is congruent to the segment A'B' and also to the segment A''B'', then the segment A'B' is congruent to the segment A''B''; that is, if AB ≡ A'B' and AB ≡ A''B'', then A'B' ≡ A''B''."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,2}

\textbf{IV, 2.} If a segment $AB$ \euclidline[color=steelblue,length=3,thickness=4] is
congruent to the segment $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] and
also to the segment $A''B''$ \euclidline[color=khaki3,length=3,thickness=4], then the
segment $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] is congruent to the
segment $A''B''$ \euclidline[color=khaki3,length=3,thickness=4]; that is, if
$AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4]
and $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A''B''$ \euclidline[color=khaki3,length=3,thickness=4],
then $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv A''B''$ \euclidline[color=khaki3,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint1Id))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))
    line_a_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeHostId))
    line_a_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeJoint1Id))
    line_a_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeJoint2Id))
    line_a_double_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeHostId))
    line_a_double_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint1Id))
    line_a_double_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint2Id))

    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointAPrimeId))
    point_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointBPrimeId))
    point_a_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointADoublePrimeId))
    point_b_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointBDoublePrimeId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_a_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelADoublePrimeId))
    label_b_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBDoublePrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_b_host_id, line_a_prime_host_id, line_a_double_prime_host_id,
         point_a_id, point_b_id, point_a_prime_id, point_b_prime_id,
         point_a_double_prime_id, point_b_double_prime_id,
         label_a_id, label_b_id, label_a_prime_id, label_b_prime_id,
         label_a_double_prime_id, label_b_double_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_b_joint1_id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_b_joint2_id, LineABStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_prime_joint1_id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_prime_joint2_id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_double_prime_joint1_id, LineADoublePrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_double_prime_joint2_id, LineADoublePrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineABColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineABStart, LineABStart, LineABColor, 0f0)
    line_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, LineAPrimeStart, LineAPrimeStart, LineAPrimeColor, 0f0)
    line_a_double_prime = OdinJuliaBridge.create_new_line(
        state_ptr, LineADoublePrimeStart,
        LineADoublePrimeStart, LineADoublePrimeColor, 0f0)

    point_a = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    point_b_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBPrime, PointBPrimeColor, 0f0)
    point_a_double_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointADoublePrime, PointADoublePrimeColor, 0f0)
    point_b_double_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBDoublePrime, PointBDoublePrimeColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_a_double_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelADoublePrimePoint, LabelColor, 16f0)
    label_b_double_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelBDoublePrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, line_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, line_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, line_a_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineAPrimeHostId, line_a_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineAPrimeJoint1Id, line_a_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineAPrimeJoint2Id, line_a_prime.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeHostId, line_a_double_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint1Id, line_a_double_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint2Id, line_a_double_prime.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPointAPrimeId, point_a_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPointBPrimeId, point_b_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPointADoublePrimeId, point_a_double_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPointBDoublePrimeId, point_b_double_prime.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelAPrimeId, label_a_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelBPrimeId, label_b_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelADoublePrimeId, label_a_double_prime.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelBDoublePrimeId, label_b_double_prime.index)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint1Id))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))
    line_a_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeHostId))
    line_a_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeJoint1Id))
    line_a_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAPrimeJoint2Id))
    line_a_double_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeHostId))
    line_a_double_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint1Id))
    line_a_double_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint2Id))

    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointAPrimeId))
    point_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointBPrimeId))
    point_a_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointADoublePrimeId))
    point_b_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointBDoublePrimeId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_a_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelADoublePrimeId))
    label_b_double_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBDoublePrimeId))

    if line_a_b_host_id < 0 || line_a_prime_host_id < 0 || line_a_double_prime_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineABStart[1], LineABStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineAB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineABStart, LineABEnd,
            LineMaxBrush, LineABColor, line_a_b_host_id,
            line_a_b_joint1_id, line_a_b_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToA
            timer = 0f0
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineABEnd, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhaseDrawA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToB
            timer = 0f0
        end
    elseif phase == PhaseMoveToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhaseDrawB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToLineAPrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineAPrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, LineAPrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAPrimeStart, LineAPrimeEnd,
            LineMaxBrush, LineAPrimeColor, line_a_prime_host_id,
            line_a_prime_joint1_id, line_a_prime_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineAPrimeEnd,
            PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhaseDrawAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, point_a_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToBPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime,
            PointBPrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
        end
    elseif phase == PhaseDrawBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointBPrime,
            PointMaxBrush, PointBPrimeColor, point_b_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToLineADoublePrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineADoublePrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime,
            LineADoublePrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineADoublePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineADoublePrimeStart,
            LineADoublePrimeEnd, LineMaxBrush, LineADoublePrimeColor,
            line_a_double_prime_host_id, line_a_double_prime_joint1_id,
            line_a_double_prime_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToADoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineADoublePrimeEnd,
            PointADoublePrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawADoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_double_prime_id)
        end
    elseif phase == PhaseDrawADoublePrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointADoublePrime,
            PointMaxBrush, PointADoublePrimeColor, point_a_double_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToBDoublePrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBDoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointADoublePrime,
            PointBDoublePrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_double_prime_id)
        end
    elseif phase == PhaseDrawBDoublePrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointBDoublePrime,
            PointMaxBrush, PointBDoublePrimeColor, point_b_double_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseArcFromBDoublePrimeToA
            timer = 0f0
        end
    elseif phase == PhaseArcFromBDoublePrimeToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBDoublePrime,
            PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToB
            timer = 0f0
        end
    elseif phase == PhaseDragAToB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBToA
            timer = 0f0
        end
    elseif phase == PhaseDragBToA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseArcToADoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime,
            PointADoublePrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragADoublePrimeToBDoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDragADoublePrimeToBDoublePrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointADoublePrime,
            PointBDoublePrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBDoublePrimeToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDragBDoublePrimeToADoublePrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBDoublePrime,
            PointADoublePrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointADoublePrime,
            PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToBAgain
            timer = 0f0
        end
    elseif phase == PhaseDragAToBAgain
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBToAAgain
            timer = 0f0
        end
    elseif phase == PhaseDragBToAAgain
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        timer += dt
        if timer >= FinalHoldDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
