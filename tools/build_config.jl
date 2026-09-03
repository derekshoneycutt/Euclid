module EuclidBuildConfiguration

export native_linker_flags, native_runtime_dirs, native_runtime_environment,
    resolve_msvc_tool_path

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_PROJECT = joinpath(REPOSITORY_ROOT, "src", "julia")
const IMPORT_LIB_DIR = joinpath(REPOSITORY_ROOT, "bin", ".native_import_libs")
const HARFBUZZ_PROVIDER_ENV = "EUCLID_HARFBUZZ_PROVIDER"

"""Validate one normalized HarfBuzz dependency provider."""
function validate_harfbuzz_provider(provider::Symbol, kernel::Symbol=Sys.KERNEL)
    provider in (:jll, :system) || error(
        "$HARFBUZZ_PROVIDER_ENV must be either jll or system.")
    provider == :system && kernel == :Windows && error(
        "System HarfBuzz linkage is unsupported on Windows.")
    return provider
end

"""Resolve and validate the configured HarfBuzz dependency provider."""
function harfbuzz_provider(
    value::AbstractString=get(ENV, HARFBUZZ_PROVIDER_ENV, "jll"),
    kernel::Symbol=Sys.KERNEL)
    provider = Symbol(lowercase(strip(value)))
    return validate_harfbuzz_provider(provider, kernel)
end

"""Run one command and return its exit code and captured streams."""
function capture_command(command::Cmd; cwd::Union{Nothing,String}=nothing)
    output = IOBuffer()
    error_output = IOBuffer()
    command = cwd === nothing ? command : Cmd(command; dir=cwd)
    process = run(pipeline(
        ignorestatus(command), stdout=output, stderr=error_output))
    return (
        exit_code=process.exitcode,
        output=String(take!(output)),
        error_output=String(take!(error_output)))
end

"""Query one pkg-config package and return normalized linker flags."""
function pkg_config_linker_flags(arguments::Vector{String})
    output = IOBuffer()
    process = run(pipeline(
        ignorestatus(Cmd(["pkg-config"; arguments])),
        stdout=output,
        stderr=devnull))
    process.exitcode == 0 || error(
        "Could not resolve system HarfBuzz through pkg-config.")
    return String.(split(String(take!(output))))
end

"""Return the HarfBuzz pkg-config query for one supported host kernel."""
function harfbuzz_pkg_config_arguments(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return ["--libs", "--static", "harfbuzz"]
    kernel == :Darwin && return ["--libs", "harfbuzz"]
    error("System HarfBuzz linkage is unsupported on $kernel.")
end

"""Apply the Linux PCRE2 runtime workaround to static HarfBuzz flags."""
function linux_harfbuzz_linker_flags(flags::Vector{String})
    pcre2_libdir = readchomp(`pkg-config --variable=libdir libpcre2-8`)
    pcre2_library = joinpath(pcre2_libdir, "libpcre2-8.so")
    isfile(pcre2_library) || error("Missing system PCRE2 library at $pcre2_library")
    replace!(flags, "-lpcre2-8" => pcre2_library)
    pushfirst!(flags, "-Wl,-rpath,$pcre2_libdir")
    return join(flags, " ")
end

"""Query mandatory platform HarfBuzz linker and runtime flags."""
function system_harfbuzz_linker_flags()
    flags = pkg_config_linker_flags(harfbuzz_pkg_config_arguments())
    if Sys.islinux()
        return linux_harfbuzz_linker_flags(flags)
    elseif Sys.isapple()
        return join(flags, " ")
    end
    error("System HarfBuzz linkage is unsupported on $(Sys.KERNEL).")
end

"""Query complete linker flags from the active Julia installation."""
function julia_linker_flags()
    (Sys.islinux() || Sys.isapple()) ||
        error("Julia linker flag discovery is unsupported on $(Sys.KERNEL).")
    julia_config_path = joinpath(
        Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl")
    isfile(julia_config_path) || error("Could not resolve julia-config.jl path.")
    command = Cmd([
        Base.julia_cmd().exec...,
        julia_config_path,
        "--ldflags",
        "--ldlibs",
    ])
    output = IOBuffer()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=devnull))
    process.exitcode == 0 || error("Failed to query Julia linker flags.")
    flags = join(split(String(take!(output))), " ")
    any(flag == "-ljulia" for flag in split(flags)) ||
        error("Julia linker flags do not contain -ljulia.")
    return flags
end

"""Resolve an MSVC tool path using the installed Visual Studio locator."""
function resolve_msvc_tool_path(find_glob::String, error_message::String)
    program_files_x86 = get(ENV, "ProgramFiles(x86)", nothing)
    program_files_x86 === nothing && error(
        "ProgramFiles(x86) environment variable is missing.")
    vswhere_path = joinpath(
        program_files_x86, "Microsoft Visual Studio", "Installer", "vswhere.exe")
    isfile(vswhere_path) || error(
        "Could not locate vswhere.exe. Install Visual Studio Build Tools.")

    result = capture_command(Cmd([
        vswhere_path,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-find",
        find_glob,
    ]))
    candidates = filter(!isempty, strip.(split(chomp(result.output), '\n')))
    result.exit_code == 0 && !isempty(candidates) || error(error_message)
    path = String(first(candidates))
    isfile(path) || error(error_message)
    return path
end

"""Generate one MSVC import library from a Windows DLL."""
function new_import_library(
    dll_path::String,
    def_path::String,
    out_lib_path::String,
    lib_exe_path::String)
    if isfile(out_lib_path) && stat(dll_path).mtime <= stat(out_lib_path).mtime
        return
    end

    mkpath(dirname(def_path))
    result = capture_command(
        Cmd(["gendef", dll_path]); cwd=dirname(def_path))
    result.exit_code == 0 && isfile(def_path) || error(
        "Failed to generate DEF file for $(basename(dll_path)).")

    result = capture_command(Cmd([
        lib_exe_path,
        "/def:$def_path",
        "/machine:x64",
        "/name:$(basename(dll_path))",
        "/out:$out_lib_path",
    ]); cwd=dirname(def_path))
    result.exit_code == 0 && isfile(out_lib_path) || error(
        "Failed to generate import library for $(basename(dll_path)): " *
        strip(result.error_output))
end

"""Resolve the HarfBuzz JLL library and its complete runtime search path."""
function harfbuzz_jll_paths()
    snippet = "using HarfBuzz_jll; " *
        "println(HarfBuzz_jll.libharfbuzz_path); " *
        "println.(HarfBuzz_jll.LIBPATH_list)"
    command = Cmd([
        Base.julia_cmd().exec...,
        "--project=$JULIA_PROJECT",
        "-e",
        snippet,
    ])
    result = capture_command(command)
    result.exit_code == 0 || error(
        "Failed to resolve HarfBuzz_jll paths: $(strip(result.error_output))")
    paths = filter(!isempty, String.(strip.(split(result.output, '\n'))))
    !isempty(paths) || error("HarfBuzz_jll returned no artifact paths.")
    isfile(first(paths)) || error("Missing HarfBuzz library at $(first(paths)).")
    return first(paths), unique(paths[2:end])
end

"""Resolve Unix linker flags for the HarfBuzz JLL product."""
function unix_harfbuzz_jll_linker_flags()
    harfbuzz_library, runtime_dirs = harfbuzz_jll_paths()
    (Sys.islinux() || Sys.isapple()) || error(
        "Unix HarfBuzz JLL linkage is unsupported on $(Sys.KERNEL).")
    if Sys.islinux()
        return "$harfbuzz_library -Wl,-rpath-link,$(join(runtime_dirs, ':'))"
    end
    return harfbuzz_library
end

"""Generate the Windows import libraries required by the Odin application."""
function windows_linker_flags()
    julia_bindir = Sys.BINDIR
    libjulia_dll = joinpath(julia_bindir, "libjulia.dll")
    libopenlibm_dll = joinpath(julia_bindir, "libopenlibm.dll")
    isfile(libjulia_dll) || error("Missing Julia runtime DLL at $libjulia_dll")
    isfile(libopenlibm_dll) || error("Missing Julia runtime DLL at $libopenlibm_dll")
    harfbuzz_dll, _ = harfbuzz_jll_paths()

    lib_exe_path = resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe",
        "Could not locate MSVC lib.exe. Install the C++ Build Tools workload.")
    new_import_library(
        libjulia_dll,
        joinpath(IMPORT_LIB_DIR, "libjulia.def"),
        joinpath(IMPORT_LIB_DIR, "julia.lib"),
        lib_exe_path)
    new_import_library(
        libopenlibm_dll,
        joinpath(IMPORT_LIB_DIR, "libopenlibm.def"),
        joinpath(IMPORT_LIB_DIR, "openlibm.lib"),
        lib_exe_path)
    new_import_library(
        harfbuzz_dll,
        joinpath(IMPORT_LIB_DIR, "libharfbuzz-0.def"),
        joinpath(IMPORT_LIB_DIR, "harfbuzz.lib"),
        lib_exe_path)
    return "/LIBPATH:$IMPORT_LIB_DIR " *
        "/DEFAULTLIB:julia.lib /DEFAULTLIB:openlibm.lib /DEFAULTLIB:harfbuzz.lib"
end

"""Resolve runtime library search directories for the active provider."""
function native_runtime_dirs(provider::Symbol=harfbuzz_provider())
    provider = validate_harfbuzz_provider(provider)
    provider == :system && return String[]
    _, paths = harfbuzz_jll_paths()
    return Sys.iswindows() ? unique([Sys.BINDIR; paths]) : paths
end

"""Build a host loader environment override from resolved runtime directories."""
function native_runtime_environment(runtime_dirs::Vector{String})
    isempty(runtime_dirs) && return nothing
    variable = Sys.iswindows() ? "PATH" :
        Sys.isapple() ? "DYLD_FALLBACK_LIBRARY_PATH" : "LD_LIBRARY_PATH"
    separator = Sys.iswindows() ? ';' : ':'
    current = get(ENV, variable, "")
    entries = isempty(current) ? runtime_dirs : [runtime_dirs; current]
    return variable => join(entries, separator)
end

"""Build the host loader environment override for one provider."""
function native_runtime_environment(provider::Symbol=harfbuzz_provider())
    return native_runtime_environment(native_runtime_dirs(provider))
end

"""Resolve complete mandatory native linker flags for the active provider."""
function native_linker_flags(provider::Symbol=harfbuzz_provider())
    provider = validate_harfbuzz_provider(provider)
    Sys.iswindows() && return windows_linker_flags()
    harfbuzz_flags = provider == :jll ? unix_harfbuzz_jll_linker_flags() :
        system_harfbuzz_linker_flags()
    return "$harfbuzz_flags $(julia_linker_flags())"
end

end