#!/usr/bin/env julia

"""Return CLI help text for the build script."""
function show_help()
    return """
Usage: ./make.jl [options]
       (normally invoked via `make <target>` or `make.ps1 <target>`)

Options:
    --build, -b         Build the project. (default)
    --no-build, -B      Skip any build, including vet builds.
    --assets, -a        Build assets.pkg. (default)
    --no-assets, -A     Skip assets.pkg build.
    --sysimage, -s      Build a custom Julia sysimage beside the application.
    --harness, -H       Build and run the headless semantic trace harness.
    --clean, -c         Delete generated build artifacts.
    --run, -r           Run bin/euclid after all other requests.
    --test, -t          Run application and analyzer tests.
    --vet, -v           Build, then run repository analysis. With --test, run the
                        full verification gate (build, tests, analyzer tests,
                        analyzer self-analysis, and repository analysis).
    --wiki, -w          Generate the publishable Wiki artifact in bin/wiki.
    --check-wiki, -W    Compare bin/wiki with a fresh generation without modifying it.
    --                  Pass all remaining args directly to bin/euclid (only with --run).
    --help, -h          Show this help text.

Verification options (forwarded to the analysis gate for --vet/--test):
    --verbosity=0|1|2   Summary, details, or complete trace output.
    --verbose           Alias for --verbosity=2.
    --color=auto|always|never
    --format=text|json  Select human or complete machine output.
    --settings=PATH     Load analyzer settings from PATH.
    --report=PATH       Write the comprehensive Markdown analysis report.

Notes:
    - If no options are provided, the default is --build --assets.
    - Lowercase -b/-a enables build/assets; uppercase -B/-A disables them.
    - Short options can be combined, e.g. -rvas or -Ba.
"""
end


using Dates
using Libdl
using UUIDs

struct Args
    run::Bool
    build::Bool
    assets::Bool
    sysimage::Bool
    harness::Bool
    clean::Bool
    test::Bool
    vet::Bool
    wiki::Bool
    check_wiki::Bool
    no_build::Bool
    no_assets::Bool
    help::Bool
    verify_args::Vector{String}
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

# Each short flag maps to the parsed-field mutations it applies.
const SHORT_FLAG_EFFECTS = Dict{Char,Vector{Tuple{Symbol,Bool}}}(
    'r' => [(:run, true)],
    'b' => [(:build, true), (:no_build, false)],
    'B' => [(:build, false), (:vet, false), (:no_build, true)],
    'a' => [(:assets, true), (:no_assets, false)],
    'A' => [(:assets, false), (:no_assets, true)],
    's' => [(:sysimage, true)],
    'H' => [(:harness, true)],
    'c' => [(:clean, true)],
    't' => [(:test, true)],
    'v' => [(:vet, true), (:no_build, false)],
    'w' => [(:wiki, true)],
    'W' => [(:check_wiki, true)],
    'h' => [(:help, true)])

# Each long/short option maps to the parsed-field mutations it applies.
const OPTION_FLAG_EFFECTS = Dict{String,Vector{Tuple{Symbol,Bool}}}(
    "--run" => [(:run, true)], "-r" => [(:run, true)],
    "--build" => [(:build, true), (:no_build, false)],
    "-b" => [(:build, true), (:no_build, false)],
    "--assets" => [(:assets, true), (:no_assets, false)],
    "-a" => [(:assets, true), (:no_assets, false)],
    "--sysimage" => [(:sysimage, true)], "-s" => [(:sysimage, true)],
    "--harness" => [(:harness, true)], "-H" => [(:harness, true)],
    "--clean" => [(:clean, true)], "-c" => [(:clean, true)],
    "--test" => [(:test, true)], "-t" => [(:test, true)],
    "--vet" => [(:vet, true), (:no_build, false)],
    "-v" => [(:vet, true), (:no_build, false)],
    "--wiki" => [(:wiki, true)], "-w" => [(:wiki, true)],
    "--check-wiki" => [(:check_wiki, true)], "-W" => [(:check_wiki, true)],
    "--no-build" => [(:build, false), (:vet, false), (:no_build, true)],
    "-B" => [(:build, false), (:vet, false), (:no_build, true)],
    "--no-assets" => [(:assets, false), (:no_assets, true)],
    "-A" => [(:assets, false), (:no_assets, true)],
    "--help" => [(:help, true)], "-h" => [(:help, true)])

const ARG_FIELDS = [
    :run, :build, :assets, :sysimage, :harness, :clean, :test, :vet,
    :wiki, :check_wiki, :no_build, :no_assets, :help]

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
const BIN_DIR = joinpath(SCRIPT_DIR, "bin")
const ASSETS_STAGING_DIR = joinpath(BIN_DIR, ".assets_staging")
const ASSETS_ARCHIVE_PATH = joinpath(BIN_DIR, "assets.pkg")
const JULIA_SYSIMAGE_PATH = joinpath(BIN_DIR, "euclid-sysimage." * Libdl.dlext)
const JULIA_EXE = Base.julia_cmd().exec[1]
const JULIA_TEST_PROJECT = joinpath(SRC_DIR, "julia")
const WIKI_GENERATOR = joinpath(SCRIPT_DIR, "tools", "code_wiki.jl")
const WIKI_ARTIFACT_DIR = joinpath(BIN_DIR, "wiki")


"""Return true when running on Windows."""
is_windows() = Sys.iswindows()

const HARNESS_BINARY_PATH = joinpath(
    BIN_DIR, is_windows() ? "euclid_harness.exe" : "euclid_harness")
const HARNESS_TRACE_PATH = joinpath(BIN_DIR, "semantic-trace-harness.jsonl")
const HARNESS_ANIMATION_ID = "03bf688d-40d0-56a2-a6be-ca2656c9b10d"

"""Return the expected output path for the Euclid application binary."""
app_binary_path() = joinpath(BIN_DIR, is_windows() ? "euclid.exe" : "euclid")

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

"""Set a single short option flag in the parsed CLI argument dictionary."""
function set_short_flag!(args::Dict{Symbol,Bool}, flag::Char)
    effects = get(SHORT_FLAG_EFFECTS, flag, nothing)
    effects === nothing && error("Unsupported parameter provided.")
    for (field, value) in effects
        args[field] = value
    end
end

"""Apply one CLI option's parsed-field mutations from the lookup table."""
function apply_cli_option!(parsed::Dict{Symbol,Bool}, arg::String)
    effects = get(OPTION_FLAG_EFFECTS, arg, nothing)
    if effects !== nothing
        for (field, value) in effects
            parsed[field] = value
        end
        return
    end
    if startswith(arg, "-") && !startswith(arg, "--") && length(arg) > 2
        for flag in arg[2:end]
            set_short_flag!(parsed, flag)
        end
        return
    end
    error("Unsupported parameter provided.")
end

"""Return whether an argument is a verification presentation option to forward."""
function is_verification_option(arg::String)
    return arg == "--verbose" ||
        startswith(arg, "--verbosity=") ||
        startswith(arg, "--color=") ||
        startswith(arg, "--format=") ||
        startswith(arg, "--settings=") ||
        startswith(arg, "--report=")
end

"""
Parse command-line arguments into structured build flags, optional run arguments,
and verification presentation options forwarded to the analysis gate.

Returns a tuple of Args and trailing arguments passed after `--` for `--run`.
"""
function parse_args(argv::Vector{String})::Tuple{Args, Vector{String}}
    run_args = String[]
    cli_args = argv

    if "--" in argv
        split_index = findfirst(==("--"), argv)
        cli_args = argv[1:split_index-1]
        run_args = argv[split_index+1:end]
    end

    parsed = Dict{Symbol,Bool}(field => false for field in ARG_FIELDS)
    verify_args = String[]

    for arg in cli_args
        if is_verification_option(arg)
            push!(verify_args, arg)
        else
            apply_cli_option!(parsed, arg)
        end
    end

    if !isempty(run_args) && !parsed[:run]
        error("Run arguments after -- are only valid with --run.")
    end

    return Args((parsed[field] for field in ARG_FIELDS)..., verify_args), run_args
end

"""Resolve the full path to `vswhere.exe` on Windows."""
function get_vswhere_path()
    program_files_x86 = get(ENV, "ProgramFiles(x86)", nothing)
    if program_files_x86 === nothing
        error("Error: ProgramFiles(x86) environment variable is missing.")
    end

    vswhere_path = joinpath(
        program_files_x86, "Microsoft Visual Studio", "Installer", "vswhere.exe")
    if !isfile(vswhere_path)
        error("Error: Could not locate vswhere.exe. Install Visual Studio Build Tools.")
    end

    return vswhere_path
end

"""Resolve an MSVC tool path using `vswhere` and a `-find` glob pattern."""
function resolve_msvc_tool_path(find_glob::String, error_message::String)
    vswhere_path = get_vswhere_path()
    result = run_command(
        Cmd([
            vswhere_path,
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-find",
            find_glob,
        ]),
        capture_output=true)

    candidate = split(chomp(result.stdout), '\n')
    if result.exit_code != 0 || isempty(filter(!isempty, candidate))
        error(error_message)
    end

    path = strip(first(filter(!isempty, candidate)))
    if !isfile(path)
        error(error_message)
    end

    return path
end

"""
Generate a Windows import library from a DLL.

This creates a DEF file with `gendef` and then invokes `lib.exe` to produce the `.lib`.
"""
function new_import_library(
    dll_path::String,
    def_path::String,
    out_lib_path::String,
    dll_name::String,
    lib_exe_path::String,
    strip_data_markers::Bool=false)
    needs_rebuild = !isfile(out_lib_path)
    if !needs_rebuild && stat(dll_path).mtime > stat(out_lib_path).mtime
        needs_rebuild = true
    end

    if !needs_rebuild
        return
    end

    mkpath(dirname(def_path))

    gendef_result = run_command(Cmd(["gendef", dll_path]); cwd=dirname(def_path))
    if gendef_result.exit_code != 0 || !isfile(def_path)
        error("Error: Failed to generate DEF file for $dll_name")
    end

    if strip_data_markers
        lines = readlines(def_path)
        normalized = replace.(lines, r" DATA$" => "")
        open(def_path, "w") do io
            write(io, join(normalized, "\n") * "\n")
        end
    end

    lib_result = run_command(
        Cmd([
            lib_exe_path,
            "/def:$def_path",
            "/machine:x64",
            "/name:$dll_name",
            "/out:$out_lib_path",
        ]),
        cwd=dirname(def_path))
    if lib_result.exit_code != 0 || !isfile(out_lib_path)
        error("Error: Failed to generate import library for $dll_name")
    end
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
    output_path::String, julia_project_dir::String)

    serial_uuid = runtime_sbom_serial_uuid()
    runtime_libs = collect_runtime_libs(binary_path)
    julia_packages = collect_julia_packages(julia_project_dir)

    bom = runtime_sbom_document(
        serial_uuid, runtime_libs, julia_packages)

    open(output_path, "w") do io
        write_json(io, bom)
        write(io, '\n')
    end
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

"""Build the CycloneDX component list from the binary, assets, libs, and packages."""
function runtime_sbom_components(runtime_libs, julia_packages, binary_name::String)
    components = Dict{String,Any}[
        Dict{String,Any}(
            "type" => "file",
            "bom-ref" => "file:$binary_name",
            "name" => binary_name,
            "version" => "dev",
            "scope" => "required"),
        Dict{String,Any}(
            "type" => "file",
            "bom-ref" => "file:bin/assets.pkg",
            "name" => "bin/assets.pkg",
            "version" => "dev",
            "scope" => "required"),
    ]

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
    return components
end

"""Assemble the CycloneDX BOM document from its components and dependency refs."""
function runtime_sbom_document(serial_uuid::AbstractString, runtime_libs, julia_packages)
    timestamp = Dates.format(now(UTC), DateFormat("yyyy-mm-ddTHH:MM:SSZ"))
    binary_name = is_windows() ? "bin/euclid.exe" : "bin/euclid"
    components = runtime_sbom_components(runtime_libs, julia_packages, binary_name)

    depends_on = String["file:$binary_name", "file:bin/assets.pkg"]
    append!(depends_on, ["runtime:$lib" for lib in runtime_libs])
    append!(depends_on, ["pkg:julia/$(package.name)" for package in julia_packages])

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
function execute_odin_build(julia_linker_flags::String)
    println("Building Odin...")
    mkpath(BIN_DIR)

    cmd_parts = odin_build_command(julia_linker_flags)
    return run_command(Cmd(cmd_parts); cwd=SRC_DIR, capture_output=true)
end

"""Build the Odin application with standard parameters."""
function build_odin(julia_linker_flags::String)
    build_result = execute_odin_build(julia_linker_flags)

    println("Build exited $(build_result.exit_code)")
    if build_result.exit_code != 0
        report_odin_build_failure(build_result)
        error("Build failed.")
    end

    return nothing
end

"""Assemble the odin build command parts for the standard application build.

Strict compiler-validation flags intentionally stay out of this command: the
analysis engine performs its own dedicated strict build through
`OdinBuildSettings`, so the application build only needs standard parameters.
"""
function odin_build_command(julia_linker_flags::String)
    out_flag = is_windows() ? "-out:../bin/euclid.exe" : "-out:../bin/euclid"
    cmd_parts = ["odin", "build", "main.odin", "-file", out_flag]
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

"""Build and run the deterministic headless harness target."""
function run_harness(julia_linker_flags::String)
    println("Running headless harness...")
    mkpath(BIN_DIR)

    cmd_parts = [
        "odin",
        "build",
        "harness/main.odin",
        "-file",
        is_windows() ? "-out:../bin/euclid_harness.exe" : "-out:../bin/euclid_harness",
    ]
    if !isempty(julia_linker_flags)
        push!(cmd_parts, "-extra-linker-flags:$julia_linker_flags")
    end

    build_result = run_command(Cmd(cmd_parts); cwd=SRC_DIR, capture_output=true)
    print_captured_output("stdout:", build_result.stdout)
    print_captured_output("stderr:", build_result.stderr)
    build_result.exit_code == 0 || error("Harness build failed.")

    harness_args = [
        "--asset-root=" * BIN_DIR,
        "--animation-id=" * HARNESS_ANIMATION_ID,
        "--steps=8",
        "--trace-output=" * HARNESS_TRACE_PATH,
        "--scenario=scenario_point_after_eight_steps",
    ]
    harness_result = run_command(
        Cmd([HARNESS_BINARY_PATH; harness_args...]); cwd=SCRIPT_DIR)
    harness_result.exit_code == 0 || error("Harness execution failed.")
    isfile(HARNESS_TRACE_PATH) || error(
        "Harness did not produce a semantic trace artifact.")
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
        "Run `git submodule update --init --recursive`, then `make configure`.")
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

"""Create the compressed assets archive from staging content."""
function create_assets_archive()
    result = run_command(
        Cmd(["tar", "-czf", ASSETS_ARCHIVE_PATH, "-C", ASSETS_STAGING_DIR, "."]))
    return result.exit_code == 0
end

"""Build and package runtime assets, then optionally generate runtime SBOM metadata."""
function build_assets(do_build::Bool)
    println("Building assets package...")
    prepare_julia_packages()
    stage_assets_content()
    finalize_assets_archive()

    if do_build
        runtime_sbom_path = joinpath(BIN_DIR, "runtime-closure.generated.cdx.json")
        write_runtime_sbom(
            app_binary_path(),
            ASSETS_ARCHIVE_PATH,
            runtime_sbom_path,
            joinpath(SRC_DIR, "julia"))
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

"""Populate the assets staging directory with Julia, shader, and static content."""
function stage_assets_content()
    if ispath(ASSETS_STAGING_DIR)
        rm(ASSETS_STAGING_DIR; force=true, recursive=true)
    end

    mkpath(joinpath(ASSETS_STAGING_DIR, "julia"))
    mkpath(joinpath(ASSETS_STAGING_DIR, "shaders"))

    copy_directory_contents(joinpath(SRC_DIR, "julia"),
        joinpath(ASSETS_STAGING_DIR, "julia"))
    copy_directory_contents(joinpath(SRC_DIR, "view", "shaders"),
        joinpath(ASSETS_STAGING_DIR, "shaders"))
    copy_directory_contents(joinpath(SCRIPT_DIR, "assets"), ASSETS_STAGING_DIR)

    open(joinpath(ASSETS_STAGING_DIR, "manifest.txt"), "w") do io
        write(io, """
package=assets.pkg
julia_root=julia
shader_root=shaders
format=tar.gz
""")
    end
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

"""Build a custom Julia sysimage containing Euclid definitions and pure compiler workloads."""
function build_julia_sysimage()
    println("Building Julia sysimage...")
    mkpath(BIN_DIR)

    build_script = joinpath(SRC_DIR, "julia", "sysimage_build.jl")
    result = run_command(Cmd([
        JULIA_EXE,
        "--project=" * JULIA_TEST_PROJECT,
        build_script,
        JULIA_SYSIMAGE_PATH,
    ]); cwd=SCRIPT_DIR)
    println("Julia sysimage build exited $(result.exit_code)")
    if result.exit_code != 0 || !isfile(JULIA_SYSIMAGE_PATH)
        error("Julia sysimage build failed.")
    end

    println("Wrote $JULIA_SYSIMAGE_PATH")
end

"""Remove an old custom sysimage when this build did not explicitly regenerate it."""
function remove_stale_julia_sysimage()
    if isfile(JULIA_SYSIMAGE_PATH)
        rm(JULIA_SYSIMAGE_PATH; force=true)
        println("Removed stale $JULIA_SYSIMAGE_PATH")
    end
end

"""Resolve Julia's runtime directory for Windows DLL loading."""
function resolve_julia_bindir()
    julia_bindir_result = run_command(
        Cmd([JULIA_EXE, "-e", "print(Sys.BINDIR)"]); capture_output=true)
    if julia_bindir_result.exit_code != 0 || isempty(strip(julia_bindir_result.stdout))
        error("Error: Could not resolve Julia Sys.BINDIR.")
    end
    return strip(julia_bindir_result.stdout)
end

"""Resolve Julia linker flags and optional runtime bindir data for the current platform."""
function resolve_julia_linker_flags(do_build::Bool)
    if !do_build
        return "", nothing
    end
    return is_windows() ?
        windows_julia_linker_flags() : posix_julia_linker_flags()
end

"""Resolve Julia linker flags on non-Windows platforms via julia-config.jl."""
function posix_julia_linker_flags()
    julia_config_path = joinpath(
        Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl")
    if !isfile(julia_config_path)
        error("Error: Could not resolve julia-config.jl path.")
    end

    flags_result = run_command(
        Cmd([JULIA_EXE, julia_config_path, "--ldflags", "--ldlibs"]);
        capture_output=true)
    if flags_result.exit_code != 0
        error("Error: Failed to query Julia linker flags.")
    end

    return join(split(flags_result.stdout), " "), nothing
end

"""Resolve Julia linker flags on Windows by generating import libraries."""
function windows_julia_linker_flags()
    julia_bindir = resolve_julia_bindir()
    libjulia_dll = joinpath(julia_bindir, "libjulia.dll")
    libopenlibm_dll = joinpath(julia_bindir, "libopenlibm.dll")
    if !isfile(libjulia_dll)
        error("Error: Missing Julia runtime DLL at $libjulia_dll")
    end
    if !isfile(libopenlibm_dll)
        error("Error: Missing Julia runtime DLL at $libopenlibm_dll")
    end

    import_lib_dir::String = joinpath(BIN_DIR, ".julia_import_libs")
    mkpath(import_lib_dir)

    lib_exe_path = String(resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe",
        "Error: Could not locate MSVC lib.exe. Install the C++ Build Tools workload."))

    new_import_library(
        libjulia_dll,
        joinpath(import_lib_dir, "libjulia.def"),
        joinpath(import_lib_dir, "julia.lib"),
        "libjulia.dll",
        lib_exe_path,
        true)
    new_import_library(
        libopenlibm_dll,
        joinpath(import_lib_dir, "libopenlibm.def"),
        joinpath(import_lib_dir, "openlibm.lib"),
        "libopenlibm.dll",
        lib_exe_path)

    return "/LIBPATH:$import_lib_dir /DEFAULTLIB:julia.lib /DEFAULTLIB:openlibm.lib",
        julia_bindir
end

"""Run the built Euclid binary with optional trailing run arguments."""
function run_binary(
    run_args::Vector{String}, julia_bindir::Union{Nothing,AbstractString})
    binary = app_binary_path()
    if !isfile(binary)
        error("Error: Built binary not found in bin/.")
    end

    if is_windows() && julia_bindir !== nothing
        new_path = string(julia_bindir, ';', get(ENV, "PATH", ""))
        withenv("PATH" => new_path) do
            result = run_command(Cmd([binary; run_args...]); cwd=BIN_DIR)
            if result.exit_code != 0
                error("Run step failed.")
            end
        end
        return
    end

    result = run_command(Cmd([binary; run_args...]); cwd=BIN_DIR)
    if result.exit_code != 0
        error("Run step failed.")
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
        JULIA_SYSIMAGE_PATH,
        joinpath(BIN_DIR, "build"),
        ASSETS_STAGING_DIR,
        joinpath(BIN_DIR, ".julia_import_libs"),
        WIKI_ARTIFACT_DIR,
        joinpath(SCRIPT_DIR, ".build", "analysis"),
        joinpath(SCRIPT_DIR, ".build", "reports"),
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

"""Return true when any build/run action flag was explicitly requested."""
explicit_action_requested(args::Args) =
    any(getfield(args, field) for field in (
        :run, :build, :assets, :sysimage, :harness,
        :vet, :test, :wiki, :check_wiki, :no_build, :no_assets))

"""Resolve effective build, vet, and asset steps from CLI argument combinations."""
function resolve_build_plan(args::Args)
    do_build, do_vet = resolve_build_and_vet(args)
    do_assets = resolve_assets(args)
    do_build = apply_build_overrides(args, do_build, do_vet, do_assets)
    do_assets = apply_asset_overrides(args, do_build, do_vet, do_assets)
    return BuildPlanToggles(do_build, do_vet, do_assets)
end

"""Resolve the build and vet toggles from the no-build/vet/build flags."""
function resolve_build_and_vet(args::Args)
    args.no_build && return false, false
    args.vet && return true, true
    return true, false
end

"""Resolve the assets toggle from the asset override flags."""
function resolve_assets(args::Args)
    args.no_assets && return false
    return true
end

"""Apply the build overrides implied by assets-only, test-only, and wiki-only runs."""
function apply_build_overrides(args::Args, do_build::Bool, do_vet::Bool, do_assets::Bool)
    (assets_only_run(args) || test_only_run(args) || wiki_only_run(args)) && return false
    return do_build
end

"""Apply the asset overrides implied by test-only and wiki-only runs."""
function apply_asset_overrides(args::Args, do_build::Bool, do_vet::Bool, do_assets::Bool)
    (test_only_run(args) || wiki_only_run(args)) && return false
    return do_assets
end

"""Return true when only asset building was requested."""
assets_only_run(args::Args) =
    args.assets && !args.build && !args.vet && !args.no_build

"""Return true when only the test step was requested."""
test_only_run(args::Args) =
    args.test && !args.build && !args.vet &&
        !args.no_build && !args.assets && !args.no_assets

"""Return true when only wiki generation or checking was requested."""
wiki_only_run(args::Args) =
    (args.wiki || args.check_wiki) && !args.run && !args.build &&
        !args.assets && !args.sysimage && !args.vet && !args.test

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
            "Wiki artifact is stale. Run `julia make.jl -w` and review the generated artifact.")
    end
    println("Wiki artifact is current and deterministic.")
end

"""Run the build step, returning the captured build result for the gate."""
function run_plan_build(args::Args, plan::BuildPlanToggles, julia_flags::String)
    plan.do_build || return nothing, UInt64(0)
    if plan.do_vet || args.test
        build_started = time_ns()
        build_result = execute_odin_build(julia_flags)
        build_elapsed_ns = UInt64(time_ns() - build_started)
        println("Build exited $(build_result.exit_code)")
        return build_result, build_elapsed_ns
    end
    build_odin(julia_flags)
    return nothing, UInt64(0)
end

"""Run the assets and sysimage packaging steps unless the build failed."""
function run_plan_packaging(args::Args, plan::BuildPlanToggles, build_ok::Bool)
    if !build_ok && (plan.do_assets || args.sysimage)
        println(stderr, "Skipping assets and sysimage because the build failed.")
    end
    plan.do_assets && build_ok && build_assets(plan.do_build)
    args.sysimage && build_ok && build_julia_sysimage()
    return nothing
end

"""Run the verification gate selected by the resolved plan, when requested."""
function run_plan_gate(
    args::Args, plan::BuildPlanToggles, build_result, build_elapsed_ns::UInt64)
    plan.do_vet || args.test || return 0
    selection = plan.do_vet && args.test ? :full : plan.do_vet ? :analysis : :tests
    return run_verification_gate(
        selection, build_result, build_elapsed_ns, args.verify_args)
end

"""Run the harness and application run steps after a passing gate."""
function run_plan_validation(
    args::Args, run_args::Vector{String}, julia_flags::String, julia_bindir)
    args.harness && run_harness(julia_flags)
    args.run && run_binary(run_args, julia_bindir)
    return nothing
end

"""Prepare linker, sysimage, and verification dependencies for a build plan."""
function prepare_build_plan(args::Args, plan::BuildPlanToggles)
    julia_flags, julia_bindir = resolve_julia_linker_flags(
        plan.do_build || args.harness)
    if args.run && is_windows() && julia_bindir === nothing
        julia_bindir = resolve_julia_bindir()
    end
    if (plan.do_build || plan.do_assets) && !args.sysimage
        remove_stale_julia_sysimage()
    end
    (plan.do_vet || args.test) && load_verification_adapter()
    return julia_flags, julia_bindir
end

"""Execute the finalized build plan, verification gate, and optional run step."""
function execute_build_plan(args::Args, plan::BuildPlanToggles, run_args::Vector{String})
    julia_flags, julia_bindir = prepare_build_plan(args, plan)
    build_result, build_elapsed_ns = run_plan_build(args, plan, julia_flags)
    build_ok = build_result === nothing || build_result.exit_code == 0
    run_plan_packaging(args, plan, build_ok)

    gate_status = run_plan_gate(args, plan, build_result, build_elapsed_ns)
    gate_status == 0 || return gate_status
    build_ok || return 1

    run_plan_validation(args, run_args, julia_flags, julia_bindir)
    return 0
end

"""Entrypoint for CLI execution. Returns process-style exit status."""
function main()
    args, run_args = try
        parse_args(collect(ARGS))
    catch err
        println(stderr, sprint(showerror, err))
        println(stderr, show_help())
        return 1
    end

    if args.help
        print(show_help())
        return 0
    end

    run_tests = args.test
    has_explicit_action = explicit_action_requested(args)

    if args.clean
        clean_build_files()
        if !has_explicit_action
            return 0
        end
    end

    plan = resolve_build_plan(args)
    return execute_requested_actions(args, plan, run_tests, run_args)
end

"""Run the resolved build plan and wiki action, returning the process exit status."""
function execute_requested_actions(
    args::Args, plan::BuildPlanToggles, run_tests::Bool, run_args::Vector{String})

    try
        args.wiki && args.check_wiki && error(
            "Choose either --wiki or --check-wiki, not both.")
        ensure_required_commands(
            plan.do_build, plan.do_assets, run_tests, args.wiki || args.check_wiki)
        plan_status = execute_build_plan(args, plan, run_args)
        plan_status == 0 || return plan_status
        if args.wiki || args.check_wiki
            run_wiki_action(args.check_wiki)
        end
        return 0
    catch err
        println(stderr, sprint(showerror, err))
        return 1
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
