module EuclidAnalysisBootstrap

include(joinpath(@__DIR__, "build_config.jl"))
include(joinpath(@__DIR__, "sqlite_validation.jl"))

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SETTINGS = joinpath(@__DIR__, "analysis_settings.jl")

"""Select only checks using Euclid's production settings, never standalone analyzer work."""
function needs_sqlite_runner(arguments::Vector{String})
    isempty(arguments) && return false
    first(arguments) == "check" || return false
    any(argument -> argument in ("--help", "-h"), arguments) && return false
    settings = filter(argument -> startswith(argument, "--settings="), arguments)
    isempty(settings) && return true
    path = split(last(settings), "="; limit=2)[2]
    return normpath(abspath(path)) == normpath(SETTINGS)
end

"""Euclid prepares its provider outside the analyzer; stdout remains protocol/report only."""
function prepare_analysis_runner(arguments::Vector{String})
    needs_sqlite_runner(arguments) || return nothing
    artifact = EuclidBuildConfiguration.sqlite3_artifact()
    flags = EuclidBuildConfiguration.sqlite3_tool_linker_flags()
    return EuclidSQLiteValidation.prepare_runner(artifact, flags)
end

end
