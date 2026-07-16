#!/usr/bin/env julia

"""Return CLI help text for the build script."""
function show_help()
    return """
Usage: ./make.jl [options]

Options:
    --build, -b         Build the project.
    --assets, -a        Build assets.pkg.
    --clean, -c         Delete generated build artifacts.
    --run, -r           Run bin/euclid after all other requests.
    --test, -t          Run project tests for the phased testing plan.
    --vet, -v           Build with validation flags.
    --no-build, -n      Skip any build (overrides --build and --vet).
    --no-assets, -x     Skip assets.pkg build (overrides --assets).
    --                  Pass all remaining args directly to bin/euclid (only with --run).
    --help, -h          Show this help text.

Notes:
    - If no options are provided, the default is --build --assets.
    - That is, --build and --assets are essentially non-altering flags, included for visibility.
    - Short options can be combined, e.g. -rva or -bnx.
"""
end


using Dates
using UUIDs

struct Args
    run::Bool
    build::Bool
    assets::Bool
    clean::Bool
    test::Bool
    vet::Bool
    no_build::Bool
    no_assets::Bool
    help::Bool
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


const SCRIPT_DIR = abspath(@__DIR__)
const SRC_DIR = joinpath(SCRIPT_DIR, "src")
const BIN_DIR = joinpath(SCRIPT_DIR, "bin")
const ASSETS_STAGING_DIR = joinpath(BIN_DIR, ".assets_staging")
const ASSETS_ARCHIVE_PATH = joinpath(BIN_DIR, "assets.pkg")
const JULIA_EXE = Base.julia_cmd().exec[1]
const JULIA_TEST_RUNNER = joinpath(SRC_DIR, "julia", "test", "runtests.jl")
const JULIA_TEST_PROJECT = joinpath(SRC_DIR, "julia")
const ODIN_TEST_ROOT = joinpath(SCRIPT_DIR, "tests")


"""Return true when running on Windows."""
is_windows() = Sys.iswindows()

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
function run_command(command::Cmd; cwd::Union{Nothing,AbstractString}=nothing, capture_output::Bool=false)
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
        catch
            exit_code = 1
        end

        return CommandResult(exit_code, String(take!(stdout_buffer)), String(take!(stderr_buffer)))
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
    catch
        exit_code = 1
    end

    return CommandResult(exit_code, "", "")
end

"""Set a single short option flag in the parsed CLI argument dictionary."""
function set_short_flag!(args::Dict{Symbol,Bool}, flag::Char)
    if flag == 'r'
        args[:run] = true
    elseif flag == 'b'
        args[:build] = true
    elseif flag == 'a'
        args[:assets] = true
    elseif flag == 'c'
        args[:clean] = true
    elseif flag == 't'
        args[:test] = true
    elseif flag == 'v'
        args[:vet] = true
    elseif flag == 'n'
        args[:no_build] = true
    elseif flag == 'x'
        args[:no_assets] = true
    elseif flag == 'h'
        args[:help] = true
    else
        error("Unsupported parameter provided.")
    end
end

"""
Parse command-line arguments into structured build flags and optional run arguments.

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

    parsed = Dict{Symbol,Bool}(
        :run => false,
        :build => false,
        :assets => false,
        :clean => false,
        :test => false,
        :vet => false,
        :no_build => false,
        :no_assets => false,
        :help => false)

    for arg in cli_args
        if arg == "--run" || arg == "-r"
            parsed[:run] = true
        elseif arg == "--build" || arg == "-b"
            parsed[:build] = true
        elseif arg == "--assets" || arg == "-a"
            parsed[:assets] = true
        elseif arg == "--clean" || arg == "-c"
            parsed[:clean] = true
        elseif arg == "--test" || arg == "-t"
            parsed[:test] = true
        elseif arg == "--vet" || arg == "-v"
            parsed[:vet] = true
        elseif arg == "--no-build" || arg == "-n"
            parsed[:no_build] = true
        elseif arg == "--no-assets" || arg == "-x"
            parsed[:no_assets] = true
        elseif arg == "--help" || arg == "-h"
            parsed[:help] = true
        elseif startswith(arg, "-") && !startswith(arg, "--") && length(arg) > 2
            for flag in arg[2:end]
                set_short_flag!(parsed, flag)
            end
        elseif startswith(arg, "-")
            error("Unsupported parameter provided.")
        else
            error("Unsupported parameter provided.")
        end
    end

    if !isempty(run_args) && !parsed[:run]
        error("Run arguments after -- are only valid with --run.")
    end

    return Args(
        parsed[:run],
        parsed[:build],
        parsed[:assets],
        parsed[:clean],
        parsed[:test],
        parsed[:vet],
        parsed[:no_build],
        parsed[:no_assets],
        parsed[:help]), run_args
end

"""Run Julia and Odin tests that implement the phased testing plan."""
function run_test_plan()
    println("Running test plan...")

    ran_any = false

    if isfile(JULIA_TEST_RUNNER)
        println("Running Julia tests...")
        julia_result = run_command(Cmd([
            JULIA_EXE,
            "--project=" * JULIA_TEST_PROJECT,
            JULIA_TEST_RUNNER,
        ]))
        println("Julia tests exited $(julia_result.exit_code)")
        if julia_result.exit_code != 0
            error("Julia tests failed.")
        end
        ran_any = true
    else
        println("Skipping Julia tests: missing $(relpath(JULIA_TEST_RUNNER, SCRIPT_DIR))")
    end

    if isdir(ODIN_TEST_ROOT)
        println("Running Odin tests...")
        odin_result = run_command(Cmd([
            "odin",
            "test",
            ODIN_TEST_ROOT,
            "-all-packages",
        ]); cwd=SCRIPT_DIR)
        println("Odin tests exited $(odin_result.exit_code)")
        if odin_result.exit_code != 0
            error("Odin tests failed.")
        end
        ran_any = true
    else
        println("Skipping Odin tests: missing $(relpath(ODIN_TEST_ROOT, SCRIPT_DIR))/")
    end

    if !ran_any
        error(
            "No tests were discovered. Add Julia tests at " *
            "$(relpath(JULIA_TEST_RUNNER, SCRIPT_DIR)) and/or Odin tests under " *
            "$(relpath(ODIN_TEST_ROOT, SCRIPT_DIR))/.")
    end

    println("Test plan completed successfully.")
end

"""Resolve the full path to `vswhere.exe` on Windows."""
function get_vswhere_path()
    program_files_x86 = get(ENV, "ProgramFiles(x86)", nothing)
    if program_files_x86 === nothing
        error("Error: ProgramFiles(x86) environment variable is missing.")
    end

    vswhere_path = joinpath(program_files_x86, "Microsoft Visual Studio", "Installer", "vswhere.exe")
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
function parse_runtime_libs(output::String; skip_first_line::Bool=false, stop_at_summary::Bool=false)
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
    result = run_command(Cmd([dumpbin_path, "/dependents", binary_path]); capture_output=true)
    if result.exit_code != 0
        return String[]
    end

    lines = split(result.stdout, '\n')
    start_index = findfirst(line -> occursin("Image has the following dependencies", line), lines)
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

    snippet = "using Pkg; deps = collect(values(Pkg.dependencies())); direct = filter(d -> d.is_direct_dep, deps); sort!(direct, by = d -> lowercase(d.name)); for d in direct; version = isnothing(d.version) ? \"stdlib\" : string(d.version); println(d.name, \"|\", version); end"
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
function write_runtime_sbom(binary_path::String, assets_path::String, output_path::String, julia_project_dir::String)
    timestamp = Dates.format(now(UTC), DateFormat("yyyy-mm-ddTHH:MM:SSZ"))

    serial_uuid = "00000000-0000-0000-0000-000000000000"
    if Sys.which("julia") !== nothing
        result = run_command(Cmd([JULIA_EXE, "-e", "using UUIDs; print(uuid4())"]); capture_output=true)
        if result.exit_code == 0 && !isempty(strip(result.stdout))
            serial_uuid = strip(result.stdout)
        end
    else
        serial_uuid = string(uuid4())
    end

    runtime_libs = collect_runtime_libs(binary_path)
    julia_packages = collect_julia_packages(julia_project_dir)
    binary_name = is_windows() ? "bin/euclid.exe" : "bin/euclid"

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

    depends_on = String["file:$binary_name", "file:bin/assets.pkg"]
    append!(depends_on, ["runtime:$lib" for lib in runtime_libs])
    append!(depends_on, ["pkg:julia/$(package.name)" for package in julia_packages])

    bom = Dict{String,Any}(
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

    open(output_path, "w") do io
        write_json(io, bom)
        write(io, '\n')
    end
end

"""Build the Odin application and optionally run strict vet and Julia syntax validation."""
function build_odin(do_vet::Bool, julia_linker_flags::String)
    println("Building Odin...")

    out_flag = is_windows() ? "-out:../bin/euclid.exe" : "-out:../bin/euclid"
    cmd_parts = ["odin", "build", "main.odin", "-file", out_flag]
    if !isempty(julia_linker_flags)
        push!(cmd_parts, "-extra-linker-flags:$julia_linker_flags")
    end
    if do_vet
        append!(cmd_parts, ["-vet", "-strict-style", "-disallow-do", "-warnings-as-errors"])
    end

    build_result = run_command(Cmd(cmd_parts); cwd=SRC_DIR, capture_output=true)
    if do_vet
        println("Odin build exited $(build_result.exit_code)")
    else
        println("Build exited $(build_result.exit_code)")
    end
    if build_result.exit_code != 0
        error("Build failed.")
    end

    if do_vet
        return build_result
    end

    return nothing
end

"""Include and run externalized vet analysis from make-vet.jl."""
function run_vet_analysis(odin_build_result=nothing)
    vet_script_path = joinpath(SCRIPT_DIR, "make-vet.jl")
    if !isfile(vet_script_path)
        error("Vet script missing at $(relpath(vet_script_path, SCRIPT_DIR)).")
    end

    include(vet_script_path)
    @invokelatest run_vet_analysis(SCRIPT_DIR, SRC_DIR, odin_build_result)
end

"""Copy all files under a source directory into a destination directory tree."""
function copy_directory_contents(source::String, destination::String)
    for (dirpath, _, filenames) in walkdir(source)
        dirpath_root::String = dirpath
        relative_root = relpath(dirpath_root, String(source))
        target_root::String = relative_root == "." ? destination : joinpath(destination, relative_root)
        mkpath(target_root)

        for filename in filenames
            cp(joinpath(dirpath, filename), joinpath(target_root, filename); force=true)
        end
    end
end

"""Create the compressed assets archive from staging content."""
function create_assets_archive()
    result = run_command(Cmd(["tar", "-czf", ASSETS_ARCHIVE_PATH, "-C", ASSETS_STAGING_DIR, "."]))
    return result.exit_code == 0
end

"""Build and package runtime assets, then optionally generate runtime SBOM metadata."""
function build_assets(do_build::Bool)
    println("Building assets package...")

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

    if ispath(ASSETS_STAGING_DIR)
        rm(ASSETS_STAGING_DIR; force=true, recursive=true)
    end

    mkpath(joinpath(ASSETS_STAGING_DIR, "julia"))
    mkpath(joinpath(ASSETS_STAGING_DIR, "shaders"))

    copy_directory_contents(joinpath(SRC_DIR, "julia"), joinpath(ASSETS_STAGING_DIR, "julia"))
    copy_directory_contents(joinpath(SRC_DIR, "view", "shaders"), joinpath(ASSETS_STAGING_DIR, "shaders"))
    copy_directory_contents(joinpath(SCRIPT_DIR, "assets"), ASSETS_STAGING_DIR)

    open(joinpath(ASSETS_STAGING_DIR, "manifest.txt"), "w") do io
        write(io, """
package=assets.pkg
julia_root=julia
shader_root=shaders
format=tar.gz
""")
    end

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

"""Resolve Julia linker flags and optional runtime bindir data for the current platform."""
function resolve_julia_linker_flags(do_build::Bool)
    if !do_build
        return "", nothing
    end

    if !is_windows()
        julia_config_path = joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl")
        if !isfile(julia_config_path)
            error("Error: Could not resolve julia-config.jl path.")
        end

        flags_result = run_command(Cmd([JULIA_EXE, julia_config_path, "--ldflags", "--ldlibs"]);
            capture_output=true)
        if flags_result.exit_code != 0
            error("Error: Failed to query Julia linker flags.")
        end

        return join(split(flags_result.stdout), " "), nothing
    end

    julia_bindir_result = run_command(Cmd([JULIA_EXE, "-e", "print(Sys.BINDIR)"]); capture_output=true)
    if julia_bindir_result.exit_code != 0 || isempty(strip(julia_bindir_result.stdout))
        error("Error: Could not resolve Julia Sys.BINDIR.")
    end

    julia_bindir = strip(julia_bindir_result.stdout)
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

    lib_exe_path = resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe",
        "Error: Could not locate MSVC lib.exe. Install the C++ Build Tools workload.")

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

    return "/LIBPATH:$import_lib_dir /DEFAULTLIB:julia.lib /DEFAULTLIB:openlibm.lib", julia_bindir
end

"""Run the built Euclid binary with optional trailing run arguments."""
function run_binary(run_args::Vector{String}, julia_bindir::Union{Nothing,AbstractString})
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
        joinpath(BIN_DIR, "vet-report.md"),
        joinpath(BIN_DIR, "libeuclid.so"),
        joinpath(BIN_DIR, "libeuclid.dll"),
        joinpath(BIN_DIR, "libeuclid.dylib"),
        joinpath(BIN_DIR, "build"),
        ASSETS_STAGING_DIR,
        joinpath(BIN_DIR, ".julia_import_libs"),
        joinpath(SCRIPT_DIR, "__pycache__"),
    ]

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

    if !isempty(removed)
        println("Cleaned build artifacts:")
        for item in removed
            println("  - $item")
        end
    else
        println("No build artifacts found to clean.")
    end
end

"""Return true when any build/run action flag was explicitly requested."""
explicit_action_requested(args::Args) =
    args.run || args.build || args.assets || args.vet || args.test || args.no_build || args.no_assets

"""Resolve effective build, vet, and asset steps from CLI argument combinations."""
function resolve_build_plan(args::Args)
    do_build = true
    do_vet = false
    do_assets = true

    if args.no_build
        do_build = false
        do_vet = false
    elseif args.vet
        do_build = true
        do_vet = true
    elseif args.build
        do_build = true
        do_vet = false
    end

    if args.no_assets
        do_assets = false
    elseif args.assets
        do_assets = true
    end

    if args.assets && !args.build && !args.vet && !args.no_build
        do_build = false
    end

    if args.test && !args.build && !args.vet && !args.no_build && !args.assets && !args.no_assets
        do_build = false
        do_assets = false
    end

    return do_build, do_vet, do_assets
end

"""Verify required external tooling exists for the selected build steps."""
function ensure_required_commands(do_build::Bool, do_assets::Bool)
    if do_build
        require_command("julia", "Please install Julia to continue.")
        require_command("odin", "Please install Odin to continue.")
    end

    if do_assets
        require_command("julia", "Please install Julia to continue.")
        require_command("tar", "Please install tar to continue.")
    end

    if do_build && is_windows()
        require_command(
            "gendef",
            "Install gendef (for example via Strawberry Perl or MSYS2) to generate import libraries.")
    end

    if isfile(JULIA_TEST_RUNNER)
        require_command("julia", "Please install Julia to run Julia tests.")
    end

    if isdir(ODIN_TEST_ROOT)
        require_command("odin", "Please install Odin to run Odin tests.")
    end
end

"""Execute the finalized build plan, vet checks, assets build, and optional run step."""
function execute_build_plan(
    do_build::Bool,
    do_vet::Bool,
    do_assets::Bool,
    run_tests::Bool,
    run_after_build::Bool,
    run_args::Vector{String})
    julia_flags, julia_bindir = resolve_julia_linker_flags(do_build)
    odin_build_result = nothing

    if do_build
        odin_build_result = build_odin(do_vet, julia_flags)
    end

    if do_vet
        run_vet_analysis(odin_build_result)
    end

    if do_assets
        build_assets(do_build)
    end

    if run_tests
        run_test_plan()
    end

    if run_after_build
        run_binary(run_args, julia_bindir)
    end
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

    run_after_build = args.run
    run_tests = args.test
    has_explicit_action = explicit_action_requested(args)

    if args.clean
        clean_build_files()
        if !has_explicit_action
            return 0
        end
    end

    do_build, do_vet, do_assets = resolve_build_plan(args)

    try
        ensure_required_commands(do_build, do_assets)
        execute_build_plan(
            do_build,
            do_vet,
            do_assets,
            run_tests,
            run_after_build,
            run_args)
        return 0
    catch err
        println(stderr, sprint(showerror, err))
        return 1
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
