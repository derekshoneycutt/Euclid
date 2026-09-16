const FirstCenter = Float32[0.42f0, 0.50f0, 0f0]
const SecondCenter = Float32[0.58f0, 0.50f0, 0f0]
const CircleRadius = 0.24f0
const FirstStart = FirstCenter + Float32[CircleRadius, 0f0, 0f0]
const SecondStart = SecondCenter + Float32[CircleRadius, 0f0, 0f0]
const FirstLabelPosition = Float32[0.29f0, 0.68f0, 0f0]
const SecondLabelPosition = Float32[0.68f0, 0.68f0, 0f0]
const FullSweep = 2f0 * Float32(pi)

const FirstColor = :steelblue
const SecondColor = :palevioletred1
const RegionColor = :khaki3
const LabelColor = :plum1
const FlickerColor = :white
const RegionBaseColor = OdinJuliaBridge.bridge_color(RegionColor)
const RegionMaxAlpha = UInt8(112)
const CircleBrush = 5f0
const LabelBrush = 16f0
const TopZ = 1.4f0
const DescendDuration = 1.5f0
const DrawDuration = 6f0
const ArcMoveDuration = 2.5f0
const RiseDuration = 1.5f0
const RevealDuration = 1.5f0
const HoldDuration = 3f0
const FlickerSamplesPerFrame = 8
const FlickerSampleAttempts = 24

const PhaseDescendFirst = UInt8(0)
const PhaseDrawFirst = UInt8(1)
const PhaseArcMoveSecond = UInt8(2)
const PhaseDrawSecond = UInt8(3)
const PhaseRiseSecond = UInt8(4)
const PhaseReveal = UInt8(5)
const PhaseHold = UInt8(6)

"""Immutable native identities and cycle timing for one circle-region animation."""
struct AnimationState
    first_circle_id::UInt64
    second_circle_id::UInt64
    region_id::UInt64
    first_label_id::UInt64
    second_label_id::UInt64
    phase::UInt8
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Return state with updated timing and unchanged native identities."""
function with_timing(state::AnimationState, phase::UInt8, timer::Float32)
    return AnimationState(state.first_circle_id, state.second_circle_id,
        state.region_id, state.first_label_id, state.second_label_id, phase, timer)
end

"""Place the compass for one circle at an angular parameter and elevation."""
function place_compass(state_ptr::Ptr{Cvoid}, center, parameter, elevation)
    pivot = Float32[center[1], center[2], elevation]
    pencil = Float32[center[1] + CircleRadius * cos(parameter),
        center[2] + CircleRadius * sin(parameter), elevation]
    OdinJuliaBridge.lock_compass_joint1(state_ptr, pivot; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, pencil; sweep=false)
end

"""Set the filled region alpha from normalized reveal progress."""
function set_region_alpha(state_ptr::Ptr{Cvoid}, region_id, alpha01)
    alpha = UInt8(round(Int, Float32(RegionMaxAlpha) * clamp(alpha01, 0f0, 1f0)))
    color = OdinJuliaBridge.BridgeColor(RegionBaseColor.r,
        RegionBaseColor.g, RegionBaseColor.b, alpha)
    OdinJuliaBridge.set_point_color(state_ptr, region_id, color)
end

"""Return whether one point belongs to this leaf's semantic region."""
function point_belongs_to_region(x::Float32, y::Float32)
    first_dx, first_dy = x - FirstCenter[1], y - FirstCenter[2]
    second_dx, second_dy = x - SecondCenter[1], y - SecondCenter[2]
    inside_first = first_dx * first_dx + first_dy * first_dy <= CircleRadius^2
    inside_second = second_dx * second_dx + second_dy * second_dy <= CircleRadius^2
    return RegionOperation == :intersection ?
        inside_first && inside_second : inside_first && !inside_second
end

"""Emit one flicker from a bounded rejection sample inside the active region."""
function emit_region_flicker(state_ptr::Ptr{Cvoid})
    for _ in 1:FlickerSampleAttempts
        x = FirstCenter[1] + CircleRadius * (2f0 * rand(Float32) - 1f0)
        y = FirstCenter[2] + CircleRadius * (2f0 * rand(Float32) - 1f0)
        if point_belongs_to_region(x, y)
            OdinJuliaBridge.emit_flicker_particle(
                state_ptr, Float32[x, y, 0f0], FlickerColor)
            return
        end
    end
end

"""Reset both circles, the region, labels, and compass for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    OdinJuliaBridge.hide_point_batch(state_ptr, [state.first_circle_id,
        state.second_circle_id, state.region_id, state.first_label_id,
        state.second_label_id])
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.first_circle_id, CircleRadius, 0f0, 0f0)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.second_circle_id, CircleRadius, 0f0, 0f0)
    set_region_alpha(state_ptr, state.region_id, 0f0)
    OdinJuliaBridge.hide_compass(state_ptr)
    place_compass(state_ptr, FirstCenter, 0f0, TopZ)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendFirst, 0f0))
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Create both outlined circles, their labels, and the hidden semantic region."""
function initialize(state_ptr::Ptr{Cvoid})
    first = OdinJuliaBridge.create_new_circle(
        state_ptr, FirstCenter, CircleRadius, 0f0, 0f0, FirstColor, CircleBrush)
    second = OdinJuliaBridge.create_new_circle(
        state_ptr, SecondCenter, CircleRadius, 0f0, 0f0, SecondColor, CircleBrush)
    region = create_region(state_ptr, FirstCenter, CircleRadius,
        SecondCenter, CircleRadius; color=RegionColor)
    first_label = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', FirstLabelPosition, LabelColor, LabelBrush)
    second_label = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', SecondLabelPosition, LabelColor, LabelBrush)
    state = AnimationState(first.host_id, second.host_id, region.host_id,
        first_label.index, second_label.index, PhaseDescendFirst, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, FirstColor)
    publish_content(state_ptr)
end

"""Hide the process-global compass when the animation is deselected."""
function clean(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.hide_compass(state_ptr)
end

"""Advance one full-circle compass drawing phase."""
function advance_circle_draw(state_ptr::Ptr{Cvoid}, circle_id::UInt64,
    center, color, timer::Float32, dt::Float32)
    progress = clamp(timer / DrawDuration, 0f0, 1f0)
    sweep = FullSweep * progress
    place_compass(state_ptr, center, sweep, 0f0)
    OdinJuliaBridge.set_arc_geometry(state_ptr, circle_id, CircleRadius, 0f0, sweep)
    pencil = Float32[center[1] + CircleRadius * cos(sweep),
        center[2] + CircleRadius * sin(sweep), 0f0]
    OdinJuliaBridge.emit_trailing_particle(state_ptr, pencil, color)
    return timer + dt
end

"""Advance the first circle and transfer the compass to the second."""
function advance_first_construction_and_transfer(
    state_ptr::Ptr{Cvoid}, state::AnimationState, phase::UInt8,
    timer::Float32, dt::Float32)
    if phase == PhaseDescendFirst
        place_compass(state_ptr, FirstCenter, 0f0,
            TopZ * (1f0 - clamp(timer / DescendDuration, 0f0, 1f0)))
        OdinJuliaBridge.show_compass(state_ptr)
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, state.first_circle_id)
            return PhaseDrawFirst, 0f0
        end
    elseif phase == PhaseDrawFirst
        timer = advance_circle_draw(state_ptr, state.first_circle_id,
            FirstCenter, FirstColor, timer, dt)
        if timer >= DrawDuration
            OdinJuliaBridge.set_arc_geometry(
                state_ptr, state.first_circle_id, CircleRadius, 0f0, FullSweep)
            OdinJuliaBridge.show_point(state_ptr, state.first_label_id)
            return PhaseArcMoveSecond, 0f0
        end
    elseif phase == PhaseArcMoveSecond
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            FirstCenter, SecondCenter, FirstStart, SecondStart)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_compass_active(state_ptr, 3, SecondColor)
            OdinJuliaBridge.show_point(state_ptr, state.second_circle_id)
            return PhaseDrawSecond, 0f0
        end
    end
    return phase, timer
end

"""Advance the second circle's draw and final rise phases."""
function advance_second_construction(
    state_ptr::Ptr{Cvoid}, state::AnimationState, phase::UInt8,
    timer::Float32, dt::Float32)
    if phase == PhaseDrawSecond
        timer = advance_circle_draw(state_ptr, state.second_circle_id,
            SecondCenter, SecondColor, timer, dt)
        if timer >= DrawDuration
            OdinJuliaBridge.set_arc_geometry(
                state_ptr, state.second_circle_id, CircleRadius, 0f0, FullSweep)
            return PhaseRiseSecond, 0f0
        end
    elseif phase == PhaseRiseSecond
        place_compass(state_ptr, SecondCenter, FullSweep,
            TopZ * clamp(timer / RiseDuration, 0f0, 1f0))
        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_point(state_ptr, state.second_label_id)
            OdinJuliaBridge.show_point(state_ptr, state.region_id)
            return PhaseReveal, 0f0
        end
    end
    return phase, timer
end

"""Advance the synchronized region reveal and readable hold phases."""
function advance_region_finish(
    state_ptr::Ptr{Cvoid}, state::AnimationState, phase::UInt8,
    timer::Float32, dt::Float32)
    if phase == PhaseReveal
        set_region_alpha(state_ptr, state.region_id, timer / RevealDuration)
        for _ in 1:FlickerSamplesPerFrame
            emit_region_flicker(state_ptr)
        end
        timer += dt
        if timer >= RevealDuration
            set_region_alpha(state_ptr, state.region_id, 1f0)
            OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
            return PhaseHold, 0f0
        end
    elseif phase == PhaseHold
        timer += dt
        if timer >= HoldDuration
            reset_cycle_state(state_ptr, state)
            return PhaseDescendFirst, 0f0
        end
    end
    return phase, timer
end

"""Advance the two compass constructions and synchronized region reveal."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase, timer = state.phase, state.timer
    if phase <= PhaseArcMoveSecond
        phase, timer = advance_first_construction_and_transfer(
            state_ptr, state, phase, timer, dt)
    elseif phase <= PhaseRiseSecond
        phase, timer = advance_second_construction(
            state_ptr, state, phase, timer, dt)
    else
        phase, timer = advance_region_finish(state_ptr, state, phase, timer, dt)
        phase == PhaseDescendFirst && return
    end
    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

"""Dispatch one bridge-stable lifecycle operation for a circle-region animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool
    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end
