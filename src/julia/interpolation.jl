"""Bounded normalization and evaluation for explicit shell interpolation leaves."""
module EuclidShellInterpolation

export SHELL_INTERPOLATION_DIAGNOSTIC_MAX_BYTES
export SHELL_INTERPOLATION_ELEMENT_CAPACITY
export SHELL_INTERPOLATION_ELEMENT_MAX_BYTES
export SHELL_INTERPOLATION_SOURCE_MAX_BYTES
export SHELL_INTERPOLATION_TOTAL_MAX_BYTES
export ShellInterpolationResult, ShellInterpolationStatus
export ShellInterpolationSucceeded, ShellInterpolationEvaluationFailed
export ShellInterpolationUnsupportedValue, ShellInterpolationTooManyElements
export ShellInterpolationElementTooLong, ShellInterpolationTotalTooLong
export evaluate_shell_interpolation, normalize_shell_interpolation

const SHELL_INTERPOLATION_SOURCE_MAX_BYTES = 4 * 1024
const SHELL_INTERPOLATION_ELEMENT_CAPACITY = 64
const SHELL_INTERPOLATION_ELEMENT_MAX_BYTES = 1024
const SHELL_INTERPOLATION_TOTAL_MAX_BYTES = 8 * 1024
const SHELL_INTERPOLATION_DIAGNOSTIC_MAX_BYTES = 512

"""Terminal status produced while evaluating or normalizing one interpolation."""
@enum ShellInterpolationStatus::Int32 begin
    ShellInterpolationSucceeded = 1
    ShellInterpolationEvaluationFailed = 2
    ShellInterpolationUnsupportedValue = 3
    ShellInterpolationTooManyElements = 4
    ShellInterpolationElementTooLong = 5
    ShellInterpolationTotalTooLong = 6
end

"""One bounded normalized interpolation result containing argument data only."""
struct ShellInterpolationResult
    status::ShellInterpolationStatus
    elements::Vector{String}
    diagnostic::String
end

"""Return whether one Julia value has the scalar shell-data contract."""
function is_shell_interpolation_scalar(value)::Bool
    return value isa Union{AbstractString,Char,Symbol,Number,Bool}
end

"""Construct one failure result without retaining caller-controlled text."""
function interpolation_failure(
    status::ShellInterpolationStatus, diagnostic::String)::ShellInterpolationResult
    @assert ncodeunits(diagnostic) <= SHELL_INTERPOLATION_DIAGNOSTIC_MAX_BYTES
    return ShellInterpolationResult(status, String[], diagnostic)
end

"""Convert one scalar to bounded argument text, rejecting native NUL bytes."""
function normalize_shell_scalar(value)
    is_shell_interpolation_scalar(value) || return nothing
    text = string(value)
    occursin('\0', text) && return nothing
    return text
end

"""Normalize a scalar, flat vector, tuple, or empty value into argument data."""
function normalize_shell_interpolation(value)::ShellInterpolationResult
    values = if value === nothing
        ()
    elseif value isa Union{AbstractVector,Tuple}
        value
    else
        (value,)
    end
    length(values) <= SHELL_INTERPOLATION_ELEMENT_CAPACITY ||
        return interpolation_failure(
            ShellInterpolationTooManyElements,
            "interpolation produced too many elements")
    elements = String[]
    sizehint!(elements, length(values))
    total_bytes = 0
    for element in values
        text = normalize_shell_scalar(element)
        text === nothing && return interpolation_failure(
            ShellInterpolationUnsupportedValue,
            "interpolation produced an unsupported or nested value")
        byte_count = ncodeunits(text)
        byte_count <= SHELL_INTERPOLATION_ELEMENT_MAX_BYTES ||
            return interpolation_failure(
                ShellInterpolationElementTooLong,
                "interpolation element exceeds its byte limit")
        total_bytes += byte_count
        total_bytes <= SHELL_INTERPOLATION_TOTAL_MAX_BYTES ||
            return interpolation_failure(
                ShellInterpolationTotalTooLong,
                "interpolation result exceeds its total byte limit")
        push!(elements, text)
    end
    return ShellInterpolationResult(
        ShellInterpolationSucceeded, elements, "")
end

"""Evaluate one expression in the supplied session module and normalize its value."""
function evaluate_shell_interpolation(
    source::AbstractString;
    context_module::Module=Main)::ShellInterpolationResult
    text = String(source)
    ncodeunits(text) <= SHELL_INTERPOLATION_SOURCE_MAX_BYTES ||
        return interpolation_failure(
            ShellInterpolationEvaluationFailed,
            "interpolation source exceeds its byte limit")
    value = try
        syntax = Meta.parse(text; raise=true)
        Core.eval(context_module, syntax)
    catch error
        error isa InterruptException && rethrow()
        return interpolation_failure(
            ShellInterpolationEvaluationFailed,
            "interpolation evaluation failed: $(nameof(typeof(error)))")
    end
    return normalize_shell_interpolation(value)
end

end
