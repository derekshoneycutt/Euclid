#!/usr/bin/env julia

include(joinpath(@__DIR__, "..", "build_config.jl"))
using .EuclidBuildConfiguration: accesskit_artifact_path,
    accesskit_provider_identity, msvc_build_environment,
    native_runtime_environment,
    resolve_msvc_tool_path
using SHA

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

if Sys.isapple()
    EXPECTED_ACCESSKIT_ABI["macos_symbols"] = 1
end
if Sys.iswindows()
    EXPECTED_ACCESSKIT_ABI["windows_symbols"] = 1
    EXPECTED_ACCESSKIT_ABI["windows_module_adjacent"] = 1
end

"""Return the retained library used to link the host C ABI probe."""
function accesskit_probe_link_library()
    provider = accesskit_provider_identity()
    Sys.iswindows() || return provider.library_path
    return accesskit_artifact_path("import-library")
end

"""Stage and verify the exact AccessKit runtime beside the Windows probe."""
function stage_accesskit_probe_runtime(output_path::String)
    source = accesskit_artifact_path("runtime")
    destination = joinpath(dirname(output_path), basename(source))
    cp(source, destination; force=true)
    expected = bytes2hex(open(sha256, source))
    bytes2hex(open(sha256, destination)) == expected || error(
        "Staged AccessKit probe runtime hash mismatch.")
    return source
end

"""Return PATH without the retained source provider directory."""
function probe_windows_path(source_runtime::String)
    source_directory = lowercase(normpath(dirname(source_runtime)))
    entries = split(get(ENV, "PATH", ""), ';'; keepempty=false)
    filtered = filter(entries) do entry
        lowercase(normpath(entry)) != source_directory
    end
    return join(filtered, ';')
end

"""Compile the AccessKit C ABI probe with the active host compiler."""
function compile_accesskit_abi_probe(output_path::String)
    repository_root = normpath(joinpath(@__DIR__, "..", ".."))
    source = joinpath(@__DIR__, "accesskit_abi_probe.c")
    include_directory = joinpath(repository_root, "libs", "accesskit", "include")
    if Sys.iswindows()
        compiler = resolve_msvc_tool_path(
            "VC/Tools/MSVC/**/bin/Hostx64/x64/cl.exe",
            "Could not locate MSVC cl.exe. Install the C++ Build Tools workload.")
        arguments = [compiler, "/nologo", "/std:c11", "/W4", "/WX",
            "/I$include_directory", source, accesskit_probe_link_library(),
            "/Fe:$output_path"]
        run(addenv(Cmd(Cmd(arguments); dir=repository_root),
            msvc_build_environment()))
        return
    end
    compiler = Sys.which("clang")
    compiler === nothing && error("AccessKit ABI probe requires clang.")
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
    environment = if Sys.iswindows()
        source_runtime = stage_accesskit_probe_runtime(executable)
        "PATH" => probe_windows_path(source_runtime)
    else
        native_runtime_environment([dirname(provider.library_path)])
    end
    command = addenv(Cmd([executable]), environment)
    output = read(command, String)
    actual = parse_accesskit_abi_output(output)
    actual == EXPECTED_ACCESSKIT_ABI || error(
        "AccessKit ABI mismatch. Expected $EXPECTED_ACCESSKIT_ABI, received $actual")
    print(output)
end

run_accesskit_abi_probe()