#!/usr/bin/env julia

import Pkg

const RepositoryRoot = normpath(joinpath(@__DIR__, ".."))
const AnalysisProject = get(
    ENV,
    "ODIN_JULIA_ANALYSIS_PROJECT",
    joinpath(RepositoryRoot, "tools", "analysis"))
const DefaultSettings = joinpath(RepositoryRoot, "tools", "analysis_settings.jl")

Pkg.activate(AnalysisProject; io=devnull)

using OdinJuliaAnalysis

"""Construct the arguments for the analysis engine."""
function analysis_arguments(arguments::Vector{String})
    resolved = copy(arguments)
    if !isempty(resolved) && first(resolved) == "check" &&
        !any(argument -> startswith(argument, "--settings="), resolved)
        push!(resolved, "--settings=" * DefaultSettings)
    end
    return resolved
end

exit(OdinJuliaAnalysis.main(analysis_arguments(ARGS)))