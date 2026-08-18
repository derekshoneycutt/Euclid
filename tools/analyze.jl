#!/usr/bin/env julia

import Pkg

const Repository_Root = normpath(joinpath(@__DIR__, ".."))
const Analysis_Project = get(
    ENV,
    "ODIN_JULIA_ANALYSIS_PROJECT",
    joinpath(Repository_Root, "tools", "analysis"))
const Default_Settings = joinpath(Repository_Root, "tools", "analysis_settings.jl")

Pkg.activate(Analysis_Project; io=devnull)

using OdinJuliaAnalysis

function analysis_arguments(arguments::Vector{String})
    resolved = copy(arguments)
    if !isempty(resolved) && first(resolved) == "check" &&
        !any(argument -> startswith(argument, "--settings="), resolved)
        push!(resolved, "--settings=" * Default_Settings)
    end
    return resolved
end

exit(OdinJuliaAnalysis.main(analysis_arguments(ARGS)))