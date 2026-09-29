#!/usr/bin/env julia

include(joinpath(@__DIR__, "..", "build_config.jl"))
using .EuclidBuildConfiguration: accesskit_manifest, accesskit_provider_identity,
    native_runtime_environment

const EXPECTED_ACCESSKIT_ABI = Dict(
    "action_click" => 0,
    "action_focus" => 1,
    "role_button" => 18,
    "action" => 1,
    "role" => 1,
    "node_id" => 8,
    "tree_id" => 16,
    "optional_node_id" => 16,
    "optional_double" => 16,
    "optional_index" => 16,
    "rect" => 32,
    "text_position" => 16,
    "text_selection" => 32,
    "action_data_tag" => 4,
    "action_data" => 40,
    "optional_action_data" => 48,
    "action_request" => 80,
    "action_request_data_offset" => 32)

"""Return the retained library used to link the host C ABI probe."""
function accesskit_probe_link_library()
    provider = accesskit_provider_identity()
    Sys.iswindows() || return provider.library_path
    manifest = accesskit_manifest()
    artifact = only(filter(record ->
        get(record, "role", "") == "import-library", manifest["artifact"]))
    return joinpath(dirname(dirname(dirname(dirname(provider.library_path)))),
        String(artifact["file"]))
end

"""Compile the AccessKit C ABI probe with the active host compiler."""
function compile_accesskit_abi_probe(output_path::String)
    compiler = Sys.which("clang")
    compiler === nothing && error("AccessKit ABI probe requires clang.")
    repository_root = normpath(joinpath(@__DIR__, "..", ".."))
    source = joinpath(@__DIR__, "accesskit_abi_probe.c")
    include_directory = joinpath(repository_root, "libs", "accesskit", "include")
    arguments = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-I$include_directory", source, accesskit_probe_link_library(),
        "-o", output_path]
    run(Cmd(Cmd(arguments); dir=repository_root))
end

"""Parse key-value layout records emitted by the C ABI probe."""
function parse_accesskit_abi_output(output::AbstractString)
    values = Dict{String,Int}()
    for line in eachline(IOBuffer(output))
        key, value = split(line, '='; limit=2)
        values[key] = parse(Int, value)
    end
    return values
end

"""Run and validate the host AccessKit ABI probe."""
function run_accesskit_abi_probe()
    repository_root = normpath(joinpath(@__DIR__, "..", ".."))
    output_directory = joinpath(repository_root, ".build", "accesskit-abi")
    mkpath(output_directory)
    executable = joinpath(output_directory,
        Sys.iswindows() ? "accesskit_abi_probe.exe" : "accesskit_abi_probe")
    compile_accesskit_abi_probe(executable)
    provider = accesskit_provider_identity()
    environment = native_runtime_environment([dirname(provider.library_path)])
    command = addenv(Cmd([executable]), environment)
    output = read(command, String)
    actual = parse_accesskit_abi_output(output)
    actual == EXPECTED_ACCESSKIT_ABI || error(
        "AccessKit ABI mismatch. Expected $EXPECTED_ACCESSKIT_ABI, received $actual")
    print(output)
end

run_accesskit_abi_probe()