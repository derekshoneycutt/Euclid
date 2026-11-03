const PenLength = 0.35f0
const PenStraightFloorAngle = π / 2f0

const PenDrawLineAngle = π / 3f0

const PenConeRadius = 0.02f0
const PenConeSpinSpeed = 6f0
const PenConeTipHeight =
    Float32(sqrt(PenLength * PenLength - PenConeRadius * PenConeRadius))
const PenConeFloorAngle = Float32(atan(PenConeTipHeight, PenConeRadius))

const TiltToConeDuration = 0.15f0
const GroundTrailDuration = 0.7f0
const GroundTrailEndTime = TiltToConeDuration + GroundTrailDuration

const TiltToLineDuration = 0.15f0
const GroundLineDuration = 0.7f0
const GroundLineEndTime = TiltToLineDuration + GroundLineDuration

"""
Normalize elapsed time into `[0, 1]` progress.

Treats non-positive duration as an immediate completion (`1f0`).
"""
@inline function normalized_progress(current_time::Real, total_duration::Real)
    if total_duration <= 0
        return 1f0
    end
    return clamp(Float32(current_time / total_duration), 0f0, 1f0)
end

"""Surface rejected curve bridge work through the ordinary animation error path."""
function checked_curve_status(status::Int32)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Curve animation bridge operation failed with status $status")
    return nothing
end

"""Resolve one directed drawing interval from explicit phase-local elapsed time."""
function curve_parameter(timer::Real, duration::Real, first::Real, last::Real)
    progress = normalized_progress(timer, duration)
    progress == 0f0 && return Float32(first)
    progress == 1f0 && return Float32(last)
    return Float32(first + (last - first) * progress)
end
