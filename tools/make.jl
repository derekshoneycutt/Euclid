#!/usr/bin/env julia

const HELP_TEXT = """
Euclid repository driver

Usage: julia tools/make.jl COMMAND [ARGUMENTS]

Commands:
    help                         Show this help text.
    build [--debug] [--strict]   Build the application and assets.
    run [--debug] [--strict] [-- APP_ARGS]
                                 Build and run the application.
    run-only [--debug] [-- APP_ARGS]
                                 Run an existing application binary.
    assets                       Build assets.pkg only.
    sysimage [--debug] [--strict]
                                 Force rebuilding the Julia sysimage, application, and assets.
    harness                      Build and run the deterministic headless harness.
    probe-sdl3                   Build and run the Linux SDL3/Vulkan capability probe.
    probe-sdl3-image             Build and run the Linux SDL_image capability probe.
    unit [julia|odin] [OPTS]     Run all application tests or one language suite.
    vet [OPTS]                   Build and analyze the repository.
    test [OPTS]                  Run the complete verification gate.
    check [PATH] [OPTS]          Analyze PATH; defaults to the repository.
    stats FILE [OPTS]            Show targeted source statistics.
    evidence COMMAND [ARGS]      Inspect canonical scenario evidence bundles.
    scenario NAME [--format=text|json]
                                 Build debug and run one named scenario.
    scenario --all [--format=text|json]
                                 Build debug and run the scenario corpus.
    analyzer-test                Run the analyzer's own test suite.
    wiki                         Generate the publishable Wiki artifact.
    check-wiki                   Verify that the Wiki artifact is current.
    clean                        Delete generated build artifacts.

Build options:
    --debug             Build with -debug -o:none under .build/debug.
    --strict            Build with strict Odin validation flags.

Verification options (forwarded by vet and test):
    --verbosity=0|1|2   Summary, details, or complete trace output.
    --verbose           Alias for --verbosity=2.
    --color=auto|always|never
    --format=text|json  Select human or complete machine output.
    --settings=PATH     Load analyzer settings from PATH.
    --report=PATH       Write the compact Markdown analysis report.
    --full-report=PATH  Write the comprehensive Markdown analysis report.

Targeted statistics examples:
    julia tools/make.jl stats src/view/view.odin
    julia tools/make.jl stats tools/make.jl --function=run_plan_build
"""

"""Return CLI help text for the build script."""
show_help() = HELP_TEXT

const DRIVER_COMMANDS = Set([
    "help", "build", "run", "run-only", "assets", "sysimage",
    "harness", "probe-sdl3", "probe-sdl3-image",
    "unit", "vet", "test", "check", "stats", "evidence", "scenario",
    "analyzer-test", "wiki", "check-wiki", "clean"])

"""Parse one required repository-driver command and its scoped arguments."""
function parse_driver_invocation(arguments::Vector{String})
    isempty(arguments) && return DriverInvocation(:help, String[])
    command = first(arguments)
    command in DRIVER_COMMANDS || error("Unknown command: $command")
    return DriverInvocation(Symbol(replace(command, '-' => '_')), arguments[2:end])
end


using Dates
using Libdl
using SHA
using TOML
using UUIDs

include(joinpath(@__DIR__, "build_config.jl"))
using .EuclidBuildConfiguration: native_linker_flags, native_runtime_dirs,
    native_runtime_environment, resolve_msvc_tool_path, sdl3_provider_identity
include(joinpath(@__DIR__, "shaders.jl"))
using .EuclidShaders: ShaderArtifacts, build_shaders
include(joinpath(@__DIR__, "sdl3_probe.jl"))
using .EuclidSDL3Probe: run_probe
include(joinpath(@__DIR__, "sdl3_image_probe.jl"))
using .EuclidSDL3ImageProbe: run_image_probe

struct BuildCommand
    action::Symbol
    debug::Bool
    strict::Bool
    arguments::Vector{String}
end

"""Top-level command dispatch decision and its command-scoped arguments."""
struct DriverInvocation
    action::Symbol
    arguments::Vector{String}
end

struct CommandResult
    exit_code::Int
    stdout::String
    stderr::String
end

struct JuliaPackageDep
    name::String
    version::String
end

"""Validated generated Julia image and the identities governing its reuse."""
struct JuliaSysimageArtifact
    input_fingerprint::String
    artifact_sha256::String
    path::String
end

"""Resolved build/vet/assets toggles derived from CLI arguments."""
struct BuildPlanToggles
    do_build::Bool
    do_vet::Bool
    do_assets::Bool
end

# The driver lives in tools/; the repository root (which owns src/, bin/,
# and the other build inputs) is its parent directory.
const SCRIPT_DIR = abspath(joinpath(@__DIR__, ".."))
const SRC_DIR = joinpath(SCRIPT_DIR, "src")
const EVIDENCE_SCRIPT = joinpath(SCRIPT_DIR, "tools", "evidence.jl")
const BIN_DIR = joinpath(SCRIPT_DIR, "bin")
const ASSETS_STAGING_DIR = joinpath(BIN_DIR, ".assets_staging")
const ASSETS_ARCHIVE_PATH = joinpath(BIN_DIR, "assets.pkg")
const SYSIMAGE_CACHE_ROOT = joinpath(SCRIPT_DIR, ".build", "sysimage-cache")
const JULIA_EXE = Base.julia_cmd().exec[1]
const JULIA_TEST_PROJECT = joinpath(SRC_DIR, "julia")
const WIKI_GENERATOR = joinpath(SCRIPT_DIR, "tools", "code_wiki.jl")
const WIKI_ARTIFACT_DIR = joinpath(BIN_DIR, "wiki")
const ANALYZER_SCRIPT = joinpath(SCRIPT_DIR, "tools", "analyze.jl")
const TEST_RUNNER_SCRIPT = joinpath(SCRIPT_DIR, "tools", "test_runner.jl")
const SCENARIO_RUNNER_SCRIPT = joinpath(SCRIPT_DIR, "tools", "scenario_runner.jl")


"""Return true when running on Windows."""
is_windows() = Sys.iswindows()

const HARNESS_BINARY_PATH = joinpath(
    BIN_DIR, is_windows() ? "euclid_harness.exe" : "euclid_harness")
const HARNESS_TRACE_PATH = joinpath(BIN_DIR, "semantic-trace-harness.bin")
const HARNESS_ANIMATION_ID = "03bf688d-40d0-56a2-a6be-ca2656c9b10d"
const SYSIMAGE_STABLE_INPUTS = String[
    "Project.toml",
    "Manifest.toml",
    "sysimage_build.jl",
    "sysimage_core.jl",
    "sysimage_workload.jl",
    "odin-julia-bridge.jl",
    "latex.jl",
    "geometry.jl",
    "animations.jl",
    "animation_catalog.jl",
    "runtime.jl",
    "terminal.jl",
    "ticks.jl",
    "euclidrepl.jl",
    "terminal_container.jl",
    "eval.jl",
    "interpolation.jl",
    "policy.jl",
    "host.jl",
    "runtime_host.jl",
    "runtime_api.jl",
    "bridge",
    "latex",
    "eval",
    "policy",
    "host",
]

"""Return canonical stable files whose bytes determine the Euclid sysimage."""
function sysimage_stable_input_paths(root::String=JULIA_TEST_PROJECT)
    paths = String[]
    for relative in SYSIMAGE_STABLE_INPUTS
        path = joinpath(root, relative)
        if isdir(path)
            for (directory, _, names) in walkdir(path), name in names
                push!(paths, joinpath(directory, name))
            end
        elseif isfile(path)
            push!(paths, path)
        else
            error("Missing stable sysimage input: $path")
        end
    end
    sort!(paths; by=path -> replace(relpath(path, root), '\\' => '/'))
    return paths
end

"""Return the toolchain identity that prevents incompatible image reuse."""
function sysimage_toolchain_identity()
    commit = string(Base.GIT_VERSION_INFO.commit)
    cpu_target = get(ENV, "JULIA_CPU_TARGET", "native")
    return "julia=$(VERSION);commit=$commit;kernel=$(Sys.KERNEL);arch=$(Sys.ARCH);" *
        "cpu_target=$cpu_target"
end

"""Hash named files and toolchain identity using an unambiguous byte framing."""
function fingerprint_sysimage_inputs(
    paths::Vector{String}, root::String; identity::String=sysimage_toolchain_identity())
    framed = IOBuffer()
    identity_bytes = codeunits(identity)
    write(framed, "identity\0", string(length(identity_bytes)), '\0', identity_bytes)
    for path in paths
        relative = replace(relpath(path, root), '\\' => '/')
        contents = read(path)
        write(framed, "file\0", string(ncodeunits(relative)), '\0', relative,
            '\0', string(length(contents)), '\0', contents)
    end
    return bytes2hex(sha256(take!(framed)))
end

"""Return the deterministic identity of the current stable Julia image inputs."""
function sysimage_input_fingerprint(root::String=JULIA_TEST_PROJECT)
    paths = sysimage_stable_input_paths(root)
    return fingerprint_sysimage_inputs(paths, root)
end

"""Return the deterministic identity of reloadable Julia content bytes."""
function content_input_fingerprint(root::String=joinpath(SRC_DIR, "content"))
    paths = String[]
    for (directory, _, names) in walkdir(root), name in names
        push!(paths, joinpath(directory, name))
    end
    sort!(paths; by=path -> replace(relpath(path, root), '\\' => '/'))
    return fingerprint_sysimage_inputs(paths, root; identity="euclid-content-v1")
end

"""Return the platform-specific generated sysimage filename."""
julia_sysimage_filename() = "euclid-sysimage." * Libdl.dlext

"""Return the platform cache partition for generated Julia images."""
function sysimage_platform_key()
    architecture = Sys.ARCH == :x86_64 ? "amd64" :
        Sys.ARCH == :aarch64 ? "arm64" : lowercase(string(Sys.ARCH))
    kernel = Sys.iswindows() ? "nt" : lowercase(string(Sys.KERNEL))
    return "$kernel-$architecture"
end

"""Return the cache directory for one stable-input fingerprint."""
function sysimage_cache_dir(
    fingerprint::String; cache_root::String=SYSIMAGE_CACHE_ROOT)
    return joinpath(cache_root, sysimage_platform_key(), fingerprint)
end

"""Return the SHA-256 digest of one generated image."""
sysimage_artifact_sha256(path::String) = bytes2hex(open(sha256, path))

"""Write generated-image metadata after PackageCompiler succeeds."""
function write_sysimage_cache_metadata(
    path::String, artifact::JuliaSysimageArtifact)
    metadata = Dict(
        "schema_version" => 1,
        "input_fingerprint" => artifact.input_fingerprint,
        "artifact_sha256" => artifact.artifact_sha256,
        "image_filename" => basename(artifact.path),
        "toolchain_identity" => sysimage_toolchain_identity())
    open(path, "w") do io
        TOML.print(io, metadata; sorted=true)
    end
end

"""Return whether cached metadata identifies the requested image and toolchain."""
function cached_sysimage_metadata_matches(
    metadata, fingerprint::String, image_path::String)

    return get(metadata, "schema_version", 0) == 1 &&
        get(metadata, "input_fingerprint", "") == fingerprint &&
        get(metadata, "image_filename", "") == basename(image_path) &&
        get(metadata, "toolchain_identity", "") == sysimage_toolchain_identity()
end

"""Return a cached image only when its metadata and bytes remain valid."""
function load_cached_julia_sysimage(
    fingerprint::String; cache_root::String=SYSIMAGE_CACHE_ROOT)
    directory = sysimage_cache_dir(fingerprint; cache_root)
    image_path = joinpath(directory, julia_sysimage_filename())
    metadata_path = joinpath(directory, "metadata.toml")
    isfile(image_path) && isfile(metadata_path) || return nothing
    metadata = try
        TOML.parsefile(metadata_path)
    catch error_object
        error_object isa TOML.ParserError || rethrow()
        return nothing
    end
    cached_sysimage_metadata_matches(metadata, fingerprint, image_path) || return nothing
    expected_digest = get(metadata, "artifact_sha256", "")
    length(expected_digest) == 64 || return nothing
    sysimage_artifact_sha256(image_path) == expected_digest || return nothing
    return JuliaSysimageArtifact(fingerprint, expected_digest, image_path)
end

"""Return the expected output path for the Euclid application binary."""
app_binary_path(debug::Bool=false) = debug ? debug_app_binary_path() :
    joinpath(BIN_DIR, is_windows() ? "euclid.exe" : "euclid")

"""Return the isolated debug application output path."""
debug_app_binary_path() = joinpath(
    SCRIPT_DIR, ".build", "debug", is_windows() ? "euclid.exe" : "euclid")

"""Return the assets package path adjacent to the debug application."""
debug_assets_archive_path() = joinpath(dirname(debug_app_binary_path()), "assets.pkg")

"""Return the default synchronized diagnostics path for debug runs."""
debug_diagnostics_path() = joinpath(SCRIPT_DIR, ".build", "debug", "euclid.log")

"""Add default synchronized diagnostics to debug runs without an override."""
function debug_application_arguments(arguments::Vector{String}, debug::Bool)
    enabled = debug &&
        !any(startswith(argument, "--diagnostics=") for argument in arguments)
    return enabled ? vcat(["--diagnostics=$(debug_diagnostics_path())"], arguments) :
        arguments
end

"""Ensure a required command exists on PATH, otherwise raise a helpful error."""
function require_command(command_name::String, install_hint::String)
    if Sys.which(command_name) === nothing
        error(
            "Error: $command_name is required but not installed or not on PATH.\n" *
            install_hint)
    end
end

"""
Run a command and return its exit code and optional captured output.

When capture_output is false, stdout and stderr in the return value are empty strings.
"""
function run_command(
    command::Cmd; cwd::Union{Nothing,AbstractString}=nothing, capture_output::Bool=false)
    if capture_output
        stdout_buffer = IOBuffer()
        stderr_buffer = IOBuffer()
        exit_code = 0

        try
            if cwd === nothing
                run(pipeline(command; stdout=stdout_buffer, stderr=stderr_buffer))
            else
                cd(cwd) do
                    run(pipeline(command; stdout=stdout_buffer, stderr=stderr_buffer))
                end
            end
        catch error_object
            exit_code = failed_process_exit_code(error_object)
        end

        return CommandResult(
            exit_code, String(take!(stdout_buffer)), String(take!(stderr_buffer)))
    end

    exit_code = 0
    try
        if cwd === nothing
            run(command)
        else
            cd(cwd) do
                run(command)
            end
        end
    catch error_object
        exit_code = failed_process_exit_code(error_object)
    end

    return CommandResult(exit_code, "", "")
end

"""Best-effort exit code extraction for process and pipeline failures."""
function failed_process_exit_code(error_object)
    if !(error_object isa Base.ProcessFailedException)
        return 1
    end

    failed = error_object.procs
    if isempty(failed)
        return 1
    end

    return failed[1].exitcode
end

"""Print captured command output blocks in a consistent, scan-friendly format."""
function print_captured_output(label::String, output::String)
    normalized = chomp(output)
    if isempty(normalized)
        return
    end

    println(label)
    println(normalized)
end

"""Return whether an argument is a verification presentation option to forward."""
function is_verification_option(arg::String)
    return arg == "--verbose" ||
        startswith(arg, "--verbosity=") ||
        startswith(arg, "--color=") ||
        startswith(arg, "--format=") ||
        startswith(arg, "--settings=") ||
        startswith(arg, "--report=") ||
        startswith(arg, "--full-report=")
end

"""Split build options from application arguments following `--`."""
function split_build_arguments(invocation::DriverInvocation)
    split_index = findfirst(==("--"), invocation.arguments)
    options = split_index === nothing ? invocation.arguments :
        invocation.arguments[1:split_index-1]
    application_arguments = split_index === nothing ? String[] :
        invocation.arguments[split_index+1:end]
    invocation.action in (:run, :run_only) || split_index === nothing || error(
        "Only run and run-only accept application arguments after --.")
    return options, application_arguments
end

"""Parse mode modifiers for a build, run, run-only, or sysimage command."""
function parse_mode_build_command(invocation::DriverInvocation)
    options, application_arguments = split_build_arguments(invocation)
    all(option -> option in ("--debug", "--strict"), options) || error(
        "$(replace(string(invocation.action), '_' => '-')) accepts only --debug and --strict.")
    debug = "--debug" in options
    strict = "--strict" in options
    invocation.action == :run_only && strict && error(
        "run-only cannot apply --strict to an existing binary.")
    return BuildCommand(invocation.action, debug, strict, application_arguments)
end

"""Parse build modifiers and optional application arguments for one build command."""
function parse_build_command(invocation::DriverInvocation)
    if invocation.action in (:vet, :test)
        all(is_verification_option, invocation.arguments) || error(
            "$(invocation.action) accepts only verification options.")
        return BuildCommand(invocation.action, false, false, invocation.arguments)
    end
    if invocation.action in (:assets, :harness)
        require_no_arguments(invocation)
        return BuildCommand(invocation.action, false, false, String[])
    end
    return parse_mode_build_command(invocation)
end

"""Parse runtime dependency tool output into a unique list of library names."""
function parse_runtime_libs(
    output::String; skip_first_line::Bool=false, stop_at_summary::Bool=false)
    libs = String[]
    for (index, raw_line) in enumerate(split(output, '\n'))
        if skip_first_line && index == 1
            continue
        end

        line = strip(raw_line)
        if isempty(line)
            continue
        end

        if stop_at_summary && line == "Summary"
            break
        end

        lib_name = split(line)[1]
        if !isempty(lib_name) && lib_name != "statically"
            push!(libs, lib_name)
        end
    end
    return unique(libs)
end

"""Collect runtime library dependencies for a Linux binary via `ldd`."""
function collect_linux_runtime_libs(binary_path::String)
    if Sys.which("ldd") === nothing
        return String[]
    end

    result = run_command(Cmd(["ldd", binary_path]); capture_output=true)
    return parse_runtime_libs(result.stdout)
end

"""Collect runtime library dependencies for a macOS binary via `otool -L`."""
function collect_macos_runtime_libs(binary_path::String)
    if Sys.which("otool") === nothing
        return String[]
    end

    result = run_command(Cmd(["otool", "-L", binary_path]); capture_output=true)
    return parse_runtime_libs(result.stdout; skip_first_line=true)
end

"""Collect runtime library dependencies for a Windows binary via `dumpbin /dependents`."""
function collect_windows_runtime_libs(binary_path::String)
    dumpbin_path = resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/dumpbin.exe",
        "Error: Could not locate MSVC dumpbin.exe. Install the C++ Build Tools workload.")
    result = run_command(Cmd([dumpbin_path, "/dependents", binary_path]);
        capture_output=true)
    if result.exit_code != 0
        return String[]
    end

    lines = split(result.stdout, '\n')
    start_index = findfirst(line ->
        occursin("Image has the following dependencies", line), lines)
    if start_index === nothing
        return String[]
    end

    return parse_runtime_libs(join(lines[start_index+1:end], "\n"); stop_at_summary=true)
end

"""Collect runtime library dependencies for the active operating system."""
function collect_runtime_libs(binary_path::String)
    if Sys.islinux()
        return collect_linux_runtime_libs(binary_path)
    elseif Sys.isapple()
        return collect_macos_runtime_libs(binary_path)
    elseif Sys.iswindows()
        return collect_windows_runtime_libs(binary_path)
    end

    return String[]
end

"""Collect direct Julia package dependencies from a Julia project environment."""
function collect_julia_packages(julia_project_dir::String)
    if Sys.which("julia") === nothing
        return JuliaPackageDep[]
    end

    snippet = "using Pkg; deps = collect(values(Pkg.dependencies())); " *
        "direct = filter(d -> d.is_direct_dep, deps); " *
        "sort!(direct, by = d -> lowercase(d.name)); " *
        "for d in direct; version = isnothing(d.version) ? \"stdlib\" : string(d.version); " *
        "println(d.name, \"|\", version); end"
    result = run_command(
        Cmd([JULIA_EXE, "--project=" * julia_project_dir, "-e", snippet]),
        capture_output=true)
    if result.exit_code != 0
        return JuliaPackageDep[]
    end

    packages = JuliaPackageDep[]
    seen = Set{String}()
    for line in split(result.stdout, '\n')
        entry = strip(line)
        if isempty(entry) || !occursin("|", entry)
            continue
        end

        name, version = split(entry, "|", limit=2)
        name = strip(name)
        version = strip(version)
        if isempty(name)
            continue
        end

        key = string(name, "|", version)
        if key in seen
            continue
        end

        push!(seen, key)
        push!(packages, JuliaPackageDep(name, version))
    end

    return packages
end

"""Write a JSON-escaped string value to an IO stream."""
function write_json_string(io::IO, value::AbstractString)
    print(io, '"')
    for char in value
        if char == '"'
            print(io, "\\\"")
        elseif char == '\\'
            print(io, "\\\\")
        elseif char == '\b'
            print(io, "\\b")
        elseif char == '\f'
            print(io, "\\f")
        elseif char == '\n'
            print(io, "\\n")
        elseif char == '\r'
            print(io, "\\r")
        elseif char == '\t'
            print(io, "\\t")
        elseif Int(char) < 0x20
            print(io, "\\u", uppercase(string(Int(char), base=16, pad=4)))
        else
            print(io, char)
        end
    end
    print(io, '"')
end

"""Write a JSON `null` literal."""
function write_json(io::IO, value::Nothing)
    print(io, "null")
end

"""Write a JSON boolean literal."""
function write_json(io::IO, value::Bool)
    print(io, value ? "true" : "false")
end

"""Write a JSON integer literal."""
function write_json(io::IO, value::Integer)
    print(io, value)
end

"""Write a JSON floating-point literal."""
function write_json(io::IO, value::AbstractFloat)
    print(io, value)
end

"""Write a JSON string value."""
function write_json(io::IO, value::AbstractString)
    write_json_string(io, value)
end

"""Write a JSON object from an AbstractDict keyed by strings."""
function write_json(io::IO, value::AbstractDict{<:AbstractString})
    print(io, '{')
    for (index, pair) in enumerate(value)
        if index > 1
            print(io, ',')
        end
        write_json(io, pair.first)
        print(io, ':')
        write_json(io, pair.second)
    end
    print(io, '}')
end

"""Write a JSON object from a vector of key-value pairs."""
function write_json(io::IO, value::AbstractVector{<:Pair})
    print(io, '{')
    for (index, pair) in enumerate(value)
        if index > 1
            print(io, ',')
        end
        write_json(io, pair.first)
        print(io, ':')
        write_json(io, pair.second)
    end
    print(io, '}')
end

"""Write a JSON array from an abstract vector."""
function write_json(io::IO, value::AbstractVector)
    print(io, '[')
    for (index, item) in enumerate(value)
        if index > 1
            print(io, ',')
        end
        write_json(io, item)
    end
    print(io, ']')
end

"""
Write a CycloneDX runtime SBOM for the built binary, assets archive, runtime libs,
and Julia package dependencies.
"""
function write_runtime_sbom(
    binary_path::String, assets_path::String,
    output_path::String, julia_project_dir::String,
    shader_manifest_path::Union{Nothing,String}=nothing)

    serial_uuid = runtime_sbom_serial_uuid()
    runtime_libs = collect_runtime_libs(binary_path)
    julia_packages = collect_julia_packages(julia_project_dir)

    bom = runtime_sbom_document(
        serial_uuid, runtime_libs, julia_packages,
        binary_path, assets_path, shader_manifest_path)

    open(output_path, "w") do io
        write_json(io, bom)
        write(io, '\n')
    end
end

"""Return one CycloneDX SHA-256 hash record for a concrete file."""
function component_hash(path::String)
    return Dict{String,Any}(
        "alg" => "SHA-256", "content" => sysimage_artifact_sha256(path))
end

"""Resolve the concrete Linux Vulkan loader used by SDL_GPU."""
function vulkan_loader_path()
    Sys.islinux() || return nothing
    handle = Libdl.dlopen_e("libvulkan.so.1")
    handle == C_NULL && error("Could not resolve the Vulkan loader.")
    path = realpath(Libdl.dlpath(handle))
    Libdl.dlclose(handle)
    return path
end

"""Describe provisional native migration inputs in CycloneDX form."""
function migration_runtime_components()
    provider = sdl3_provider_identity()
    loader = vulkan_loader_path()
    return Dict{String,Any}[
        Dict("type" => "library", "bom-ref" => "native:sdl3",
            "name" => "SDL3", "version" => provider.version,
            "scope" => "required", "hashes" => [component_hash(
                provider.library_path)],
            "properties" => [Dict("name" => "euclid:provider",
                "value" => "provisional-system")]),
        Dict("type" => "library", "bom-ref" => "native:vulkan-loader",
            "name" => basename(loader), "version" => "system",
            "scope" => "required", "hashes" => [component_hash(loader)]),
    ]
end

"""Describe shader compilers as build-only CycloneDX components."""
function shader_tool_components(manifest_path::Union{Nothing,String})
    manifest_path === nothing && return Dict{String,Any}[]
    manifest = TOML.parsefile(manifest_path)
    components = Dict{String,Any}[]
    for (name, prefix) in (("SDL_shadercross", "shadercross"),
        ("SPIR-V Tools validator", "spirv_validator"))
        path = manifest["$(prefix)_path"]
        closure = join(manifest["$(prefix)_closure"], ";")
        push!(components, Dict("type" => "application",
            "bom-ref" => "build-tool:$prefix", "name" => name,
            "version" => manifest["$(prefix)_identity"], "scope" => "excluded",
            "hashes" => [Dict("alg" => "SHA-256",
                "content" => manifest["$(prefix)_sha256"])],
            "properties" => [
                Dict("name" => "euclid:build-only", "value" => "true"),
                Dict("name" => "euclid:path", "value" => path),
                Dict("name" => "euclid:dynamic-closure", "value" => closure)]))
    end
    return components
end

"""Describe generated shader artifacts as required CycloneDX components."""
function shader_artifact_components(manifest_path::Union{Nothing,String})
    manifest_path === nothing && return Dict{String,Any}[]
    manifest = TOML.parsefile(manifest_path)
    components = Dict{String,Any}[]
    for shader in manifest["shader"]
        for (kind, field) in (("SPIR-V", "artifact"),
            ("reflection", "reflection"))
            name = shader[field]
            push!(components, Dict("type" => "file",
                "bom-ref" => "shader:$(shader["name"]):$kind",
                "name" => "shaders/$name", "version" => "dev",
                "scope" => "required", "hashes" => [Dict(
                    "alg" => "SHA-256",
                    "content" => shader["$(field)_sha256"])]))
        end
    end
    return components
end

"""Resolve a UUID for the SBOM serial number, preferring a Julia subprocess."""
function runtime_sbom_serial_uuid()
    if Sys.which("julia") === nothing
        return string(uuid4())
    end
    result = run_command(
        Cmd([JULIA_EXE, "-e", "using UUIDs; print(uuid4())"]); capture_output=true)
    if result.exit_code == 0 && !isempty(strip(result.stdout))
        return strip(result.stdout)
    end
    return "00000000-0000-0000-0000-000000000000"
end

"""Describe the application binary and asset archive as required files."""
function runtime_file_components(
    binary_name::String, binary_path::String, assets_path::String)
    return Dict{String,Any}[
        Dict("type" => "file", "bom-ref" => "file:$binary_name",
            "name" => binary_name, "version" => "dev", "scope" => "required",
            "hashes" => [component_hash(binary_path)]),
        Dict("type" => "file", "bom-ref" => "file:bin/assets.pkg",
            "name" => "bin/assets.pkg", "version" => "dev",
            "scope" => "required", "hashes" => [component_hash(assets_path)]),
    ]
end

"""Build the CycloneDX component list from the binary, assets, libs, and packages."""
function runtime_sbom_components(
    runtime_libs, julia_packages, binary_name::String,
    binary_path::String, assets_path::String,
    shader_manifest_path::Union{Nothing,String}=nothing)
    components = runtime_file_components(binary_name, binary_path, assets_path)

    for lib in runtime_libs
        push!(components, Dict{String,Any}(
            "type" => "library",
            "bom-ref" => "runtime:$lib",
            "name" => lib,
            "version" => "unknown",
            "scope" => "required"))
    end

    for package in julia_packages
        push!(components, Dict{String,Any}(
            "type" => "library",
            "bom-ref" => "pkg:julia/$(package.name)",
            "name" => package.name,
            "version" => package.version,
            "scope" => "required"))
    end
    append!(components, migration_runtime_components(),
        shader_tool_components(shader_manifest_path),
        shader_artifact_components(shader_manifest_path))
    return components
end

"""Assemble the CycloneDX BOM document from its components and dependency refs."""
function runtime_sbom_document(
    serial_uuid::AbstractString, runtime_libs, julia_packages,
    binary_path::String, assets_path::String,
    shader_manifest_path::Union{Nothing,String}=nothing)
    timestamp = Dates.format(now(UTC), DateFormat("yyyy-mm-ddTHH:MM:SSZ"))
    binary_name = is_windows() ? "bin/euclid.exe" : "bin/euclid"
    components = runtime_sbom_components(
        runtime_libs, julia_packages, binary_name,
        binary_path, assets_path, shader_manifest_path)

    depends_on = String[component["bom-ref"] for component in components
        if component["scope"] == "required"]

    return Dict{String,Any}(
        "\$schema" => "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat" => "CycloneDX",
        "specVersion" => "1.6",
        "serialNumber" => "urn:uuid:$serial_uuid",
        "version" => 1,
        "metadata" => Dict{String,Any}(
            "timestamp" => timestamp,
            "component" => Dict{String,Any}(
                "type" => "application",
                "bom-ref" => "app:euclid",
                "name" => "EuclidApp",
                "version" => "dev")),
        "components" => components,
        "dependencies" => Any[
            Dict{String,Any}(
                "ref" => "app:euclid",
                "dependsOn" => depends_on),
        ])
end

"""Run the Odin build command and capture its output for the gate."""
function execute_odin_build(
    julia_linker_flags::String, debug::Bool=false, strict::Bool=false)
    println("Building Odin...")
    mkpath(BIN_DIR)
    debug && mkpath(dirname(debug_app_binary_path()))

    cmd_parts = odin_build_command(julia_linker_flags, debug, strict)
    return run_command(Cmd(cmd_parts); cwd=SRC_DIR, capture_output=true)
end

"""Build the Odin application with standard parameters."""
function build_odin(
    julia_linker_flags::String, debug::Bool=false, strict::Bool=false)
    build_result = execute_odin_build(julia_linker_flags, debug, strict)

    println("Build exited $(build_result.exit_code)")
    if build_result.exit_code != 0
        report_odin_build_failure(build_result)
        error("Build failed.")
    end

    remove_staged_raylib(dirname(app_binary_path(debug)))
    debug && write_debug_environment(native_runtime_dirs())

    return nothing
end

"""Write the native loader environment consumed by the CodeLLDB launch."""
function write_debug_environment(
    runtime_dirs::Vector{String};
    path::String=joinpath(dirname(debug_app_binary_path()), "euclid.env"))
    environment = native_runtime_environment(runtime_dirs)
    environment === nothing && return nothing
    value = Sys.iswindows() ? replace(environment.second, '\\' => '/') :
        environment.second
    escaped = replace(value, '\\' => "\\\\", '"' => "\\\"")
    write(path, "$(environment.first)=\"$escaped\"\n")
    return nothing
end

"""Remove stale generated Raylib libraries from one executable directory."""
function remove_staged_raylib(destination::String)
    for filename in (
        "libraylib.so.600", "libraylib.600.dylib", "raylib.dll")
        path = joinpath(destination, filename)
        (ispath(path) || islink(path)) && rm(path; force=true)
    end
    return nothing
end

"""Assemble the Odin command for a standard, debug, or strict application build."""
function odin_build_command(
    julia_linker_flags::String, debug::Bool=false, strict::Bool=false)
    out_flag = "-out:$(app_binary_path(debug))"
    cmd_parts = ["odin", "build", "main.odin", "-file", out_flag]
    debug && append!(cmd_parts, [
        "-define:EUCLID_ENABLE_SCENARIOS=true", "-debug", "-o:none"])
    strict && append!(cmd_parts,
        ["-vet", "-strict-style", "-disallow-do", "-warnings-as-errors"])
    if is_windows()
        julia_linker_flags = string(julia_linker_flags, " /STACK:8388608")
    end
    if !isempty(julia_linker_flags)
        push!(cmd_parts, "-extra-linker-flags:$julia_linker_flags")
    end
    return cmd_parts
end

"""Print captured odin output when a build fails."""
function report_odin_build_failure(build_result::CommandResult)
    println("Odin build failed with captured output:")
    print_captured_output("stdout:", build_result.stdout)
    print_captured_output("stderr:", build_result.stderr)
    if isempty(chomp(build_result.stdout)) &&
       isempty(chomp(build_result.stderr))
        println("(No captured output from Odin process.)")
    end
end

"""Build the deterministic headless harness target."""
function build_harness(julia_linker_flags::String)
    println("Building headless harness...")
    mkpath(BIN_DIR)

    cmd_parts = [
        "odin",
        "build",
        "harness/main.odin",
        "-file",
        "-define:EUCLID_ENABLE_HARNESS=true",
        is_windows() ? "-out:../bin/euclid_harness.exe" : "-out:../bin/euclid_harness",
    ]
    if !isempty(julia_linker_flags)
        push!(cmd_parts, "-extra-linker-flags:$julia_linker_flags")
    end

    build_result = run_command(Cmd(cmd_parts); cwd=SRC_DIR, capture_output=true)
    print_captured_output("stdout:", build_result.stdout)
    print_captured_output("stderr:", build_result.stderr)
    build_result.exit_code == 0 || error("Harness build failed.")
    remove_staged_raylib(dirname(HARNESS_BINARY_PATH))

    return nothing
end

"""Run one deterministic harness case and return elapsed wall time in seconds."""
function run_harness_once(runtime_dirs::Vector{String}; capture_output::Bool=false)
    rm(HARNESS_TRACE_PATH; force=true)
    harness_args = [
        "--asset-root=" * BIN_DIR,
        "--animation-id=" * HARNESS_ANIMATION_ID,
        "--steps=8",
        "--trace-output=" * relpath(HARNESS_TRACE_PATH, SCRIPT_DIR),
        "--scenario=scenario_point_after_eight_steps",
    ]
    harness_command = Cmd([HARNESS_BINARY_PATH; harness_args...])
    runtime_environment = native_runtime_environment(runtime_dirs)
    if runtime_environment !== nothing
        harness_command = addenv(harness_command, runtime_environment)
    end
    started = time_ns()
    harness_result = run_command(
        harness_command; cwd=SCRIPT_DIR, capture_output=capture_output)
    elapsed_seconds = (time_ns() - started) / 1.0e9
    if harness_result.exit_code != 0
        print_captured_output("stdout:", harness_result.stdout)
        print_captured_output("stderr:", harness_result.stderr)
        error("Harness execution failed.")
    end
    isfile(HARNESS_TRACE_PATH) || error(
        "Harness did not produce a semantic trace artifact.")
    return elapsed_seconds
end

"""Build and run the deterministic headless harness target."""
function run_harness(julia_linker_flags::String, runtime_dirs::Vector{String})
    build_harness(julia_linker_flags)
    println("Running headless harness...")
    run_harness_once(runtime_dirs)
    println("Wrote $(relpath(HARNESS_TRACE_PATH, SCRIPT_DIR))")
end

"""Load the verification adapter, failing clearly when the analyzer is unavailable."""
function load_verification_adapter()
    verify_path = joinpath(SCRIPT_DIR, "tools", "verify.jl")
    isfile(verify_path) || error(
        "Verification adapter missing at $(relpath(verify_path, SCRIPT_DIR)).")
    analysis_project = get(ENV, "ODIN_JULIA_ANALYSIS_PROJECT",
        joinpath(SCRIPT_DIR, "tools", "analysis"))
    isfile(joinpath(analysis_project, "Project.toml")) || error(
        "Analysis submodule is not initialized. " *
        "Run `git submodule update --init --recursive`, then `cmake --preset default`.")
    include(verify_path)
    return Base.invokelatest(getglobal, Main, :EuclidVerification)
end

"""Return verification arguments with the canonical report default applied."""
function with_default_report(verify_args::Vector{String})
    any(arg -> startswith(arg, "--report="), verify_args) && return verify_args
    return [verify_args..., "--report=" * joinpath(".build", "reports", "analysis.md")]
end

"""Run the verification gate for the requested vet/test combination."""
function run_verification_gate(
    selection::Symbol, build_result, build_elapsed_ns::UInt64,
    verify_args::Vector{String})
    verification = Base.invokelatest(getglobal, Main, :EuclidVerification)
    gate_args = with_default_report(verify_args)
    build_data = build_result === nothing ? nothing : (
        detail="Euclid application",
        elapsed_ns=build_elapsed_ns,
        exit_code=build_result.exit_code,
        output=build_result.stdout * build_result.stderr)
    return Base.invokelatest() do
        verification.driver_gate(gate_args, selection, build_data)
    end
end

"""Copy all files under a source directory into a destination directory tree."""
function copy_directory_contents(source::String, destination::String)
    for (dirpath, _, filenames) in walkdir(source)
        dirpath_root::String = dirpath
        relative_root = relpath(dirpath_root, String(source))
        target_root::String = relative_root == "." ? destination :
            joinpath(destination, relative_root)
        mkpath(target_root)

        for filename in filenames
            cp(joinpath(dirpath, filename), joinpath(target_root, filename); force=true)
        end
    end
end

"""Compile the staged Euclid terminfo entry using the host ncurses layout."""
function compile_staged_terminfo()
    Sys.iswindows() && return
    terminfo_dir = joinpath(ASSETS_STAGING_DIR, "terminfo")
    source_path = joinpath(terminfo_dir, "euclid.terminfo")
    result = run_command(Cmd(["tic", "-x", "-o", terminfo_dir, source_path]))
    result.exit_code == 0 || error("Euclid terminfo compilation failed.")
end

"""Create the compressed assets archive from staging content."""
function create_assets_archive()
    result = run_command(
        Cmd(["tar", "-czf", ASSETS_ARCHIVE_PATH, "-C", ASSETS_STAGING_DIR, "."]))
    return result.exit_code == 0
end

"""Build and package runtime assets, then optionally generate runtime SBOM metadata."""
function build_assets(
    do_build::Bool, debug::Bool=false; force_sysimage::Bool=false)
    println("Building assets package...")
    prepare_julia_packages()
    sysimage = ensure_julia_sysimage(; force=force_sysimage)
    shaders = build_shaders(SCRIPT_DIR)
    stage_assets_content(sysimage, shaders)
    finalize_assets_archive()
    if debug
        debug_archive = debug_assets_archive_path()
        mkpath(dirname(debug_archive))
        cp(ASSETS_ARCHIVE_PATH, debug_archive; force=true)
        println("Wrote $debug_archive")
    end

    if do_build
        runtime_sbom_path = joinpath(BIN_DIR, "runtime-closure.generated.cdx.json")
        write_runtime_sbom(
            app_binary_path(debug),
            ASSETS_ARCHIVE_PATH,
            runtime_sbom_path,
            joinpath(SRC_DIR, "julia"),
            shaders.manifest_path)
        println("Wrote $runtime_sbom_path")
    end
end

"""Instantiate and precompile the Julia project used by the assets build."""
function prepare_julia_packages()
    package_init = run_command(
        Cmd([
            JULIA_EXE,
            "--project=" * joinpath(SCRIPT_DIR, "src", "julia"),
            "-e",
            "using Pkg; Pkg.instantiate(); Pkg.precompile()",
        ]))
    println("Julia package init exited $(package_init.exit_code)")
    if package_init.exit_code != 0
        error("Julia package init failed.")
    end
end

"""Write deterministic metadata for the staged asset archive."""
function write_assets_manifest(
    sysimage::JuliaSysimageArtifact, shaders::ShaderArtifacts,
    sysimage_relative_path::String)
    open(joinpath(ASSETS_STAGING_DIR, "manifest.txt"), "w") do io
        write(io, """
package=assets.pkg
julia_root=julia
content_root=content
content_input_fingerprint=$(content_input_fingerprint())
shader_root=shaders
shader_manifest=shaders/manifest.toml
shader_manifest_sha256=$(bytes2hex(open(sha256, shaders.manifest_path)))
shader_schema_version=1
schema_version=2
sysimage_path=$(replace(sysimage_relative_path, '\\' => '/'))
sysimage_input_fingerprint=$(sysimage.input_fingerprint)
sysimage_artifact_sha256=$(sysimage.artifact_sha256)
sysimage_platform=$(sysimage_platform_key())
sysimage_toolchain=$(sysimage_toolchain_identity())
format=tar.gz
""")
    end
end

"""Populate asset staging with content and validated generated artifacts."""
function stage_assets_content(
    sysimage::JuliaSysimageArtifact, shaders::ShaderArtifacts)
    if ispath(ASSETS_STAGING_DIR)
        rm(ASSETS_STAGING_DIR; force=true, recursive=true)
    end

    mkpath(joinpath(ASSETS_STAGING_DIR, "julia"))
    mkpath(joinpath(ASSETS_STAGING_DIR, "content"))
    mkpath(joinpath(ASSETS_STAGING_DIR, "shaders"))

    copy_directory_contents(joinpath(SRC_DIR, "julia"),
        joinpath(ASSETS_STAGING_DIR, "julia"))
    copy_directory_contents(joinpath(SRC_DIR, "content"),
        joinpath(ASSETS_STAGING_DIR, "content"))
    copy_directory_contents(shaders.directory,
        joinpath(ASSETS_STAGING_DIR, "shaders"))
    copy_directory_contents(joinpath(SCRIPT_DIR, "assets"), ASSETS_STAGING_DIR)
    rm(joinpath(ASSETS_STAGING_DIR, "Chalk On Blackboard.wav"); force=true)
    compile_staged_terminfo()

    sysimage_relative_path = joinpath(
        "sysimage", sysimage.input_fingerprint, julia_sysimage_filename())
    staged_sysimage = joinpath(ASSETS_STAGING_DIR, sysimage_relative_path)
    mkpath(dirname(staged_sysimage))
    cp(sysimage.path, staged_sysimage; force=true)
    write_assets_manifest(sysimage, shaders, sysimage_relative_path)
end

"""Create the assets archive from staging and clean up the staging directory."""
function finalize_assets_archive()
    mkpath(BIN_DIR)
    assets_exit_code = create_assets_archive() ? 0 : 1
    println("Assets package build exited $assets_exit_code")

    if ispath(ASSETS_STAGING_DIR)
        rm(ASSETS_STAGING_DIR; force=true, recursive=true)
    end

    if assets_exit_code != 0
        error("Assets package build failed.")
    end

    println("Wrote $ASSETS_ARCHIVE_PATH")
end

"""Build or reuse the generated Julia image for the current stable inputs."""
function ensure_julia_sysimage(; force::Bool=false)
    fingerprint = sysimage_input_fingerprint()
    cached = load_cached_julia_sysimage(fingerprint)
    if !force && cached !== nothing
        println("Reusing Julia sysimage $(cached.input_fingerprint)")
        return cached
    end

    reason = force ? "forced rebuild" : "missing, stale, or invalid cache"
    println("Building Julia sysimage ($reason)...")
    final_directory = sysimage_cache_dir(fingerprint)
    mkpath(dirname(final_directory))
    build_script = joinpath(SRC_DIR, "julia", "sysimage_build.jl")
    artifact = mktempdir(dirname(final_directory)) do candidate_directory
        image_path = joinpath(candidate_directory, julia_sysimage_filename())
        result = run_command(Cmd([
            JULIA_EXE,
            "--project=" * JULIA_TEST_PROJECT,
            build_script,
            image_path,
        ]); cwd=SCRIPT_DIR)
        println("Julia sysimage build exited $(result.exit_code)")
        if result.exit_code != 0 || !isfile(image_path)
            error("Julia sysimage build failed.")
        end
        digest = sysimage_artifact_sha256(image_path)
        candidate = JuliaSysimageArtifact(fingerprint, digest, image_path)
        write_sysimage_cache_metadata(
            joinpath(candidate_directory, "metadata.toml"), candidate)
        ispath(final_directory) && rm(final_directory; force=true, recursive=true)
        mv(candidate_directory, final_directory)
        return JuliaSysimageArtifact(
            fingerprint, digest, joinpath(final_directory, basename(image_path)))
    end
    println("Wrote $(artifact.path)")
    return artifact
end

"""Resolve native linker flags and runtime library directories."""
function resolve_native_linker_flags(do_build::Bool)
    if !do_build
        return "", native_runtime_dirs()
    end
    return native_linker_flags(), native_runtime_dirs()
end

"""Run the built Euclid binary with optional trailing run arguments."""
function run_binary(
    run_args::Vector{String}, runtime_dirs::Vector{String},
    debug::Bool=false)
    binary = app_binary_path(debug)
    if !isfile(binary)
        error("Error: Built binary not found in bin/.")
    end

    runtime_environment = native_runtime_environment(runtime_dirs)
    if runtime_environment !== nothing
        withenv(runtime_environment) do
            arguments = debug_application_arguments(run_args, debug)
            result = run_command(Cmd([binary; arguments...]); cwd=BIN_DIR)
                if result.exit_code != 0
                    error("Run step failed with exit code $(result.exit_code).")
            end
        end
        return
    end

    arguments = debug_application_arguments(run_args, debug)
    result = run_command(Cmd([binary; arguments...]); cwd=BIN_DIR)
        if result.exit_code != 0
            error("Run step failed with exit code $(result.exit_code).")
    end
end

"""Remove known generated build artifacts from the repository."""
function clean_build_files()
    targets = String[
        app_binary_path(),
        ASSETS_ARCHIVE_PATH,
        joinpath(BIN_DIR, "runtime-closure.generated.cdx.json"),
        joinpath(BIN_DIR, "libeuclid.so"),
        joinpath(BIN_DIR, "libeuclid.dll"),
        joinpath(BIN_DIR, "libeuclid.dylib"),
        joinpath(BIN_DIR, "build"),
        ASSETS_STAGING_DIR,
        joinpath(BIN_DIR, ".native_import_libs"),
        WIKI_ARTIFACT_DIR,
        joinpath(SCRIPT_DIR, ".build", "analysis"),
        joinpath(SCRIPT_DIR, ".build", "debug"),
        joinpath(SCRIPT_DIR, ".build", "reports"),
        joinpath(SCRIPT_DIR, ".build", "scenarios"),
        joinpath(SCRIPT_DIR, ".build", "sdl3-probe"),
        SYSIMAGE_CACHE_ROOT,
        joinpath(SCRIPT_DIR, "__pycache__"),
    ]

    removed = remove_build_targets(targets)

    if !isempty(removed)
        println("Cleaned build artifacts:")
        for item in removed
            println("  - $item")
        end
    else
        println("No build artifacts found to clean.")
    end
end

"""Remove each existing build target, returning the repository-relative removed paths."""
function remove_build_targets(targets::Vector{String})
    removed = String[]
    for target in targets
        if !ispath(target)
            continue
        end

        if isdir(target)
            rm(target; force=true, recursive=true)
        else
            rm(target; force=true)
        end

        push!(removed, relpath(target, SCRIPT_DIR))
    end
    return removed
end

"""Return the fixed build, analysis, and asset plan for one command."""
function build_plan_for(action::Symbol)
    action == :assets && return BuildPlanToggles(false, false, true)
    action in (:run_only, :harness) && return BuildPlanToggles(false, false, false)
    action == :vet && return BuildPlanToggles(true, true, true)
    action == :test && return BuildPlanToggles(true, true, true)
    action in (:build, :run, :sysimage) && return BuildPlanToggles(true, false, true)
    error("Command does not have a build plan: $action")
end

"""Verify required external tooling exists for the selected build steps."""
function ensure_required_commands(
    do_build::Bool, do_assets::Bool, run_tests::Bool, run_wiki::Bool)

    if do_build || run_tests || run_wiki
        require_command("odin", "Please install Odin to continue.")
    end

    if do_assets
        require_command("tar", "Please install tar to continue.")
    end

    if do_build && is_windows()
        require_command(
            "gendef",
            "Install gendef (for example via Strawberry Perl or MSYS2) to generate import libraries.")
    end

end

"""Return the GitHub source prefix pinned to the generated artifact's commit."""
function wiki_source_link_prefix()
    repository = get(ENV, "GITHUB_REPOSITORY", "derekshoneycutt/Euclid")
    revision = get(ENV, "GITHUB_SHA", "")
    if isempty(revision)
        result = run_command(Cmd(["git", "rev-parse", "HEAD"]); capture_output=true)
        result.exit_code == 0 || error("Could not resolve the Wiki source revision.")
        revision = strip(result.stdout)
    end
    isempty(revision) && error("Wiki source revision is empty.")
    return "https://github.com/$repository/blob/$revision/"
end

"""Run the Wiki generator for one explicit artifact directory."""
function generate_wiki(output_root::String)
    mkpath(dirname(output_root))
    command = addenv(Cmd([
        JULIA_EXE,
        "--project=" * JULIA_TEST_PROJECT,
        WIKI_GENERATOR,
    ]),
        "EUCLID_WIKI_OUTPUT_ROOT" => output_root,
        "EUCLID_WIKI_SOURCE_PREFIX" => wiki_source_link_prefix())
    result = run_command(command; cwd=SCRIPT_DIR)
    result.exit_code == 0 || error("Wiki generation failed.")
end

"""Read one generated tree into a deterministic repository-relative byte map."""
function wiki_tree_snapshot(root::String)
    isdir(root) || error("Wiki artifact is missing: $(relpath(root, SCRIPT_DIR))")
    snapshot = Dict{String,Vector{UInt8}}()
    for (directory, _, names) in walkdir(root), name in sort(names)
        path = joinpath(directory, name)
        relative = replace(relpath(path, root), '\\' => '/')
        snapshot[relative] = read(path)
    end
    return snapshot
end

"""Generate or non-destructively validate the publishable Wiki artifact."""
function run_wiki_action(check_only::Bool)
    if !check_only
        println("Generating Wiki artifact...")
        generate_wiki(WIKI_ARTIFACT_DIR)
        println("Wrote $(relpath(WIKI_ARTIFACT_DIR, SCRIPT_DIR))")
        return
    end

    expected = wiki_tree_snapshot(WIKI_ARTIFACT_DIR)
    mktempdir(BIN_DIR) do directory
        candidate_root = joinpath(directory, "wiki")
        generate_wiki(candidate_root)
        candidate = wiki_tree_snapshot(candidate_root)
        expected == candidate || error(
            "Wiki artifact is stale. Run `julia tools/make.jl wiki` and review it.")
    end
    println("Wiki artifact is current and deterministic.")
end

"""Run the build step, returning the captured build result for the gate."""
function run_plan_build(
    command::BuildCommand, plan::BuildPlanToggles, julia_flags::String)
    plan.do_build || return nothing, UInt64(0)
    if plan.do_vet
        build_started = time_ns()
        build_result = execute_odin_build(
            julia_flags, command.debug, command.strict)
        build_elapsed_ns = UInt64(time_ns() - build_started)
        println("Build exited $(build_result.exit_code)")
        build_result.exit_code == 0 &&
            remove_staged_raylib(dirname(app_binary_path(command.debug)))
        return build_result, build_elapsed_ns
    end
    build_odin(julia_flags, command.debug, command.strict)
    return nothing, UInt64(0)
end

"""Run the assets and sysimage packaging steps unless the build failed."""
function run_plan_packaging(
    command::BuildCommand, plan::BuildPlanToggles, build_ok::Bool)
    if !build_ok && (plan.do_assets || command.action == :sysimage)
        println(stderr, "Skipping assets and sysimage because the build failed.")
    end
    plan.do_assets && build_ok && build_assets(
        plan.do_build, command.debug; force_sysimage=command.action == :sysimage)
    return nothing
end

"""Run the verification gate selected by the resolved plan, when requested."""
function run_plan_gate(
    command::BuildCommand, plan::BuildPlanToggles,
    build_result, build_elapsed_ns::UInt64)
    plan.do_vet || return 0
    selection = command.action == :test ? :full : :analysis
    return run_verification_gate(
        selection, build_result, build_elapsed_ns, command.arguments)
end

"""Run the harness and application run steps after a passing gate."""
function run_plan_validation(
    command::BuildCommand, julia_flags::String, runtime_dirs::Vector{String})
    command.action == :harness && run_harness(julia_flags, runtime_dirs)
    command.action in (:run, :run_only) && run_binary(
        command.arguments, runtime_dirs, command.debug)
    return nothing
end

"""Prepare linker, sysimage, and verification dependencies for a build plan."""
function prepare_build_plan(command::BuildCommand, plan::BuildPlanToggles)
    julia_flags, runtime_dirs = resolve_native_linker_flags(
        plan.do_build || command.action == :harness)
    plan.do_vet && load_verification_adapter()
    return julia_flags, runtime_dirs
end

"""Translate a check or stats command into analyzer command arguments."""
function analysis_command_arguments(action::Symbol, arguments::Vector{String})
    paths = filter(argument -> !startswith(argument, "-"), arguments)
    length(paths) <= 1 || error("$(action) accepts at most one path.")
    action == :stats && isempty(paths) && error("stats requires a source file.")
    path = isempty(paths) ? SCRIPT_DIR : only(paths)
    options = filter(!=(path), arguments)
    return [string(action), path, options...]
end

"""Run repository analysis or targeted source statistics without a build."""
function run_analysis_command(action::Symbol, arguments::Vector{String})
    analysis_project = get(ENV, "ODIN_JULIA_ANALYSIS_PROJECT",
        joinpath(SCRIPT_DIR, "tools", "analysis"))
    analyzer_arguments = analysis_command_arguments(action, arguments)
    command = Cmd(vcat([
        JULIA_EXE,
        "--project=$analysis_project",
        ANALYZER_SCRIPT,
    ], analyzer_arguments))
    return run_command(command; cwd=SCRIPT_DIR).exit_code
end

"""Run the canonical evidence bundle inspection CLI."""
function run_evidence_command(arguments::Vector{String})
    analysis_project = get(ENV, "ODIN_JULIA_ANALYSIS_PROJECT",
        joinpath(SCRIPT_DIR, "tools", "analysis"))
    command = Cmd(vcat([
        JULIA_EXE,
        "--project=$analysis_project",
        EVIDENCE_SCRIPT,
    ], arguments))
    return run_command(command; cwd=SCRIPT_DIR).exit_code
end

"""Build the headed debug application and run selected scenarios through it."""
function run_scenario_command(arguments::Vector{String})
    isempty(arguments) && error("scenario requires one NAME or --all")
    build = BuildCommand(:build, true, false, String[])
    build_status = if "--format=json" in arguments
        redirect_stdout(stderr) do
            execute_build_plan(build, build_plan_for(:build))
        end
    else
        execute_build_plan(build, build_plan_for(:build))
    end
    build_status == 0 || return build_status
    analysis_project = get(ENV, "ODIN_JULIA_ANALYSIS_PROJECT",
        joinpath(SCRIPT_DIR, "tools", "analysis"))
    command = Cmd(vcat([
        JULIA_EXE, "--project=$analysis_project", SCENARIO_RUNNER_SCRIPT,
        "--binary=$(debug_app_binary_path())"], arguments))
    runtime_environment = native_runtime_environment(native_runtime_dirs())
    command = runtime_environment === nothing ? command :
        addenv(command, runtime_environment)
    return run_command(command; cwd=SCRIPT_DIR).exit_code
end

"""Return whether a unit invocation includes the Odin application suite."""
unit_command_runs_odin(arguments::Vector{String}) = !("julia" in arguments)

"""Return whether assets.pkg contains current runtime and content identities."""
function packaged_assets_are_current()
    isfile(ASSETS_ARCHIVE_PATH) || return false
    result = run_command(Cmd([
        "tar", "-xOf", ASSETS_ARCHIVE_PATH, "./manifest.txt",
    ]); capture_output=true)
    result.exit_code == 0 || return false
    expected = "sysimage_input_fingerprint=$(sysimage_input_fingerprint())"
    expected_platform = "sysimage_platform=$(sysimage_platform_key())"
    expected_content = "content_input_fingerprint=$(content_input_fingerprint())"
    lines = split(result.stdout, '\n')
    return expected in lines && expected_platform in lines && expected_content in lines
end

"""Prepare packaged assets required by Odin runtime integration tests."""
function prepare_unit_assets(arguments::Vector{String})
    unit_command_runs_odin(arguments) || return nothing
    packaged_assets_are_current() && return nothing
    ensure_required_commands(false, true, false, false)
    build_assets(false)
    return nothing
end

"""Run all application unit tests or one selected language suite."""
function run_unit_command(arguments::Vector{String})
    prepare_unit_assets(arguments)
    command = Cmd(vcat([JULIA_EXE, TEST_RUNNER_SCRIPT], arguments))
    return run_command(command; cwd=SCRIPT_DIR).exit_code
end

"""Run the analyzer package's regression suite."""
function run_analyzer_test_command(arguments::Vector{String})
    isempty(arguments) || error("analyzer-test does not accept arguments.")
    analysis_project = get(ENV, "ODIN_JULIA_ANALYSIS_PROJECT",
        joinpath(SCRIPT_DIR, "tools", "analysis"))
    expression = "using Pkg; Pkg.test()"
    command = Cmd([
        JULIA_EXE, "--project=$analysis_project", "-e", expression])
    return run_command(command; cwd=SCRIPT_DIR).exit_code
end

"""Execute the finalized build plan, verification gate, and optional run step."""
function execute_build_plan(command::BuildCommand, plan::BuildPlanToggles)
    julia_flags, runtime_dirs = prepare_build_plan(command, plan)
    build_result, build_elapsed_ns = run_plan_build(command, plan, julia_flags)
    build_ok = build_result === nothing || build_result.exit_code == 0
    run_plan_packaging(command, plan, build_ok)

    gate_status = run_plan_gate(command, plan, build_result, build_elapsed_ns)
    gate_status == 0 || return gate_status
    build_ok || return 1

    run_plan_validation(command, julia_flags, runtime_dirs)
    return 0
end

"""Require that a standalone command received no arguments."""
function require_no_arguments(invocation::DriverInvocation)
    isempty(invocation.arguments) || error(
        "$(replace(string(invocation.action), '_' => '-')) does not accept arguments.")
end

"""Execute one parsed repository-driver command."""
function execute_driver_action(invocation::DriverInvocation)
    if invocation.action == :help
        require_no_arguments(invocation)
        print(show_help())
        return 0
    end
    invocation.action == :unit && return run_unit_command(invocation.arguments)
    invocation.action in (:check, :stats) && return run_analysis_command(
        invocation.action, invocation.arguments)
    invocation.action == :evidence && return run_evidence_command(invocation.arguments)
    invocation.action == :scenario && return run_scenario_command(invocation.arguments)
    if invocation.action == :probe_sdl3
        require_no_arguments(invocation)
        return run_probe(SCRIPT_DIR)
    end
    if invocation.action == :probe_sdl3_image
        require_no_arguments(invocation)
        return run_image_probe(SCRIPT_DIR)
    end
    invocation.action == :analyzer_test &&
        return run_analyzer_test_command(invocation.arguments)
    if invocation.action in (:wiki, :check_wiki)
        require_no_arguments(invocation)
        ensure_required_commands(false, false, false, true)
        run_wiki_action(invocation.action == :check_wiki)
        return 0
    end
    if invocation.action == :clean
        require_no_arguments(invocation)
        clean_build_files()
        return 0
    end
    command = parse_build_command(invocation)
    plan = build_plan_for(command.action)
    ensure_required_commands(
        plan.do_build, plan.do_assets, command.action == :test, false)
    return execute_build_plan(command, plan)
end

"""Entrypoint for CLI execution. Returns process-style exit status."""
function main(arguments::Vector{String}=collect(ARGS))
    invocation = try
        parse_driver_invocation(arguments)
    catch err
        println(stderr, sprint(showerror, err))
        println(stderr, "Run `julia tools/make.jl help` for usage.")
        return 2
    end
    return try
        execute_driver_action(invocation)
    catch err
        println(stderr, sprint(showerror, err))
        return 1
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
