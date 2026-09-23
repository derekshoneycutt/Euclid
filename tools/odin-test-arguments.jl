#!/usr/bin/env julia

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))

pushfirst!(LOAD_PATH, joinpath(@__DIR__, "analysis"))
include("build_config.jl")

using .EuclidBuildConfiguration: native_runtime_environment, native_test_linker_flags
using JSON

"""Build the shared compiler arguments and runtime environment for this workspace."""
function provider_result()
    isempty(ARGS) || error("This workspace-scoped provider accepts no arguments.")
    arguments = [
        "-define:EUCLID_ENABLE_HARNESS=true",
        "-define:EUCLID_ENABLE_SCENARIOS=true",
        "-define:ODIN_TEST_THREADS=1",
        "-extra-linker-flags:$(native_test_linker_flags())",
    ]
    runtime_environment = native_runtime_environment()
    environment = runtime_environment === nothing ? Dict{String,String}() :
        Dict(String(runtime_environment.first) => runtime_environment.second)
    return (; arguments, environment)
end

"""Print exactly one provider JSON object or report a clear failure on stderr."""
function main()
    try
        JSON.print(stdout, provider_result())
        println()
    catch exception
        println(stderr, "odin-test-arguments: ", sprint(showerror, exception))
        exit(1)
    end
end

main()