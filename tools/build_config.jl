module EuclidBuildConfiguration

using SHA
using TOML

export native_linker_flags, native_runtime_dirs, native_runtime_environment,
    native_test_linker_flags, resolve_msvc_tool_path, sdl3_library_path,
    sdl3_linker_flags, sdl3_provider_identity, sdl3_image_library_path,
    sdl3_image_linker_flags, sdl3_image_provider_identity,
    windows_sdl_manifest

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_PROJECT = joinpath(REPOSITORY_ROOT, "src", "julia")
const IMPORT_LIB_DIR = joinpath(REPOSITORY_ROOT, "bin", ".native_import_libs")
const WINDOWS_SDL_DIR = joinpath(REPOSITORY_ROOT, "libs", "bin", "win64", "sdl")
const HARFBUZZ_PROVIDER_ENV = "EUCLID_HARFBUZZ_PROVIDER"

struct SDL3ProviderIdentity
    kind::Symbol
    version::String
    library_path::String
end

struct SDL3ImageProviderIdentity
    kind::Symbol
    version::String
    library_path::String
end

const SDL3_IMAGE_MINIMUM_VERSION = v"3.4.0"

"""Join one provider directory and filename using target-platform separators."""
function sdl_library_candidate(
    directory::AbstractString, filename::AbstractString, kernel::Symbol)
    kernel == :NT && return joinpath(normpath(directory), filename)
    normalized = replace(normpath(directory), '\\' => '/')
    return string(rstrip(normalized, '/'), '/', filename)
end

"""Return one named library record from a parsed SDL payload manifest."""
function windows_sdl_library(manifest::AbstractDict, name::String)
    libraries = get(manifest, "library", Any[])
    index = findfirst(library -> get(library, "name", "") == name, libraries)
    index === nothing && error("Windows SDL manifest is missing $name.")
    return libraries[index]
end

"""Validate one Windows SDL library's dependencies, license, and artifacts."""
function validate_windows_sdl_library(
    library::AbstractDict, library_names::Set{String}, root::AbstractString,
    hash_file::Function)
    name = String(get(library, "name", ""))
    isempty(name) && error("Windows SDL manifest contains an unnamed library.")
    all(dependency -> dependency in library_names,
        String.(get(library, "dependencies", String[]))) || error(
        "Windows SDL manifest has an unknown dependency for $name.")
    license_path = joinpath(root, String(get(library, "license_file", "")))
    isfile(license_path) || error("Missing Windows SDL license for $name.")
    hash_file(license_path) == get(library, "license_sha256", "") || error(
        "Windows SDL license hash mismatch for $name.")
    for artifact in get(library, "artifact", Any[])
        filename = String(get(artifact, "file", ""))
        path = joinpath(root, filename)
        isfile(path) || error("Missing Windows SDL artifact: $filename")
        hash_file(path) == get(artifact, "sha256", "") || error(
            "Windows SDL artifact hash mismatch: $filename")
    end
end

"""Validate and return the repository-owned Windows SDL payload manifest."""
function windows_sdl_manifest(
    root::AbstractString=WINDOWS_SDL_DIR;
    architecture::Symbol=Sys.ARCH,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)))
    manifest_path = joinpath(normpath(root), "manifest.toml")
    isfile(manifest_path) || error(
        "Missing Windows SDL manifest at $manifest_path")
    manifest = parse_file(manifest_path)
    get(manifest, "schema_version", 0) == 1 || error(
        "Unsupported Windows SDL manifest schema.")
    get(manifest, "platform", "") == "windows" || error(
        "Windows SDL manifest has the wrong platform.")
    expected_architecture = architecture == :x86_64 ? "x86_64" : string(architecture)
    get(manifest, "architecture", "") == expected_architecture || error(
        "Windows SDL manifest does not support $expected_architecture.")
    get(manifest, "toolchain", "") == "msvc" || error(
        "Windows SDL manifest must use the MSVC toolchain.")

    library_names = Set(String(get(library, "name", ""))
        for library in get(manifest, "library", Any[]))
    for library in get(manifest, "library", Any[])
        validate_windows_sdl_library(library, library_names, root, hash_file)
    end
    windows_sdl_library(manifest, "SDL3")
    image = windows_sdl_library(manifest, "SDL3_image")
    image_version = tryparse(VersionNumber, String(get(image, "version", "")))
    image_version !== nothing && image_version >= SDL3_IMAGE_MINIMUM_VERSION || error(
        "Repository SDL_image version is older than $(SDL3_IMAGE_MINIMUM_VERSION).")
    return manifest
end

"""Return the platform runtime filename for one SDL library."""
function sdl_runtime_filename(
    stem::AbstractString, kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return "lib$(stem).so.0"
    kernel == :Darwin && return "lib$(stem).0.dylib"
    kernel == :NT && return "$(stem).dll"
    error("System $stem is unsupported on $kernel.")
end

"""Resolve the SDL3 runtime from one pkg-config library directory."""
function sdl3_library_path(
    library_directory::AbstractString;
    kernel::Symbol=Sys.KERNEL,
    is_file::Function=isfile,
    real_path::Function=realpath)
    directory = strip(library_directory)
    isempty(directory) && error(
        "System SDL3 pkg-config library directory is empty.")
    candidate = sdl_library_candidate(
        directory, sdl_runtime_filename("SDL3", kernel), kernel)
    is_file(candidate) || error("Missing system SDL3 runtime at $candidate")
    return real_path(candidate)
end

"""Resolve the system SDL3 provider through pkg-config."""
function sdl3_provider_identity(
    kernel::Symbol=Sys.KERNEL;
    capture::Function=capture_command,
    is_file::Function=isfile,
    real_path::Function=realpath,
    root::AbstractString=WINDOWS_SDL_DIR,
    architecture::Symbol=Sys.ARCH)
    if kernel == :NT
        manifest = windows_sdl_manifest(root; architecture)
        library = windows_sdl_library(manifest, "SDL3")
        return SDL3ProviderIdentity(
            :repository, String(library["version"]),
            real_path(joinpath(root, "SDL3.dll")))
    end
    sdl_runtime_filename("SDL3", kernel)
    version_result = capture(Cmd(["pkg-config", "--modversion", "sdl3"]))
    version_result.exit_code == 0 || error(
        "Could not resolve system SDL3 version through pkg-config.")
    libdir_result = capture(Cmd([
        "pkg-config", "--variable=libdir", "sdl3",
    ]))
    libdir_result.exit_code == 0 || error(
        "Could not resolve system SDL3 library directory through pkg-config.")
    version = strip(version_result.output)
    isempty(version) && error("System SDL3 pkg-config version is empty.")
    library_path = sdl3_library_path(strip(libdir_result.output);
        kernel, is_file, real_path)
    return SDL3ProviderIdentity(:system, version, library_path)
end

"""Resolve SDL3 linker flags through pkg-config metadata."""
function sdl3_linker_flags(
    kernel::Symbol=Sys.KERNEL;
    capture::Function=capture_command,
    root::AbstractString=WINDOWS_SDL_DIR,
    architecture::Symbol=Sys.ARCH)
    if kernel == :NT
        windows_sdl_manifest(root; architecture)
        return "/LIBPATH:$(normpath(root)) /DEFAULTLIB:SDL3.lib"
    end
    sdl_runtime_filename("SDL3", kernel)
    result = capture(Cmd(["pkg-config", "--libs", "sdl3"]))
    result.exit_code == 0 || error(
        "Could not resolve system SDL3 linker flags through pkg-config.")
    flags = join(split(result.output), " ")
    isempty(flags) && error("System SDL3 pkg-config linker flags are empty.")
    return flags
end

"""Resolve the SDL_image runtime from one pkg-config library directory."""
function sdl3_image_library_path(
    library_directory::AbstractString;
    kernel::Symbol=Sys.KERNEL,
    is_file::Function=isfile,
    real_path::Function=realpath)
    directory = strip(library_directory)
    isempty(directory) && error(
        "System SDL_image pkg-config library directory is empty.")
    candidate = sdl_library_candidate(
        directory, sdl_runtime_filename("SDL3_image", kernel), kernel)
    is_file(candidate) || error("Missing system SDL_image runtime at $candidate")
    return real_path(candidate)
end

"""Resolve the mandatory system SDL_image provider through pkg-config."""
function sdl3_image_provider_identity(
    kernel::Symbol=Sys.KERNEL;
    capture::Function=capture_command,
    is_file::Function=isfile,
    real_path::Function=realpath,
    root::AbstractString=WINDOWS_SDL_DIR,
    architecture::Symbol=Sys.ARCH)
    if kernel == :NT
        manifest = windows_sdl_manifest(root; architecture)
        library = windows_sdl_library(manifest, "SDL3_image")
        return SDL3ImageProviderIdentity(
            :repository, String(library["version"]),
            real_path(joinpath(root, "SDL3_image.dll")))
    end
    sdl_runtime_filename("SDL3_image", kernel)
    version_result = capture(Cmd([
        "pkg-config", "--modversion", "sdl3-image",
    ]))
    version_result.exit_code == 0 || error(
        "Could not resolve system SDL_image version through pkg-config.")
    libdir_result = capture(Cmd([
        "pkg-config", "--variable=libdir", "sdl3-image",
    ]))
    libdir_result.exit_code == 0 || error(
        "Could not resolve system SDL_image library directory through pkg-config.")
    version = strip(version_result.output)
    isempty(version) && error("System SDL_image pkg-config version is empty.")
    parsed_version = tryparse(VersionNumber, version)
    parsed_version === nothing && error(
        "System SDL_image pkg-config version is invalid: $version")
    parsed_version >= SDL3_IMAGE_MINIMUM_VERSION || error(
        "System SDL_image $version is older than required version " *
        "$(SDL3_IMAGE_MINIMUM_VERSION).")
    library_path = sdl3_image_library_path(strip(libdir_result.output);
        kernel, is_file, real_path)
    return SDL3ImageProviderIdentity(:system, version, library_path)
end

"""Resolve mandatory SDL_image linker flags through pkg-config metadata."""
function sdl3_image_linker_flags(
    kernel::Symbol=Sys.KERNEL;
    capture::Function=capture_command,
    root::AbstractString=WINDOWS_SDL_DIR,
    architecture::Symbol=Sys.ARCH)
    if kernel == :NT
        windows_sdl_manifest(root; architecture)
        return "/LIBPATH:$(normpath(root)) /DEFAULTLIB:SDL3_image.lib"
    end
    sdl_runtime_filename("SDL3_image", kernel)
    result = capture(Cmd(["pkg-config", "--libs", "sdl3-image"]))
    result.exit_code == 0 || error(
        "Could not resolve system SDL_image linker flags through pkg-config.")
    flags = join(split(result.output), " ")
    isempty(flags) && error(
        "System SDL_image pkg-config linker flags are empty.")
    return flags
end

"""Validate one normalized HarfBuzz dependency provider."""
function validate_harfbuzz_provider(provider::Symbol, kernel::Symbol=Sys.KERNEL)
    provider in (:jll, :system) || error(
        "$HARFBUZZ_PROVIDER_ENV must be either jll or system.")
    provider == :system && kernel == :NT && error(
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
    flags = join(Base.shell_split(String(take!(output))), " ")
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
    rpaths = ["-Wl,-rpath,$directory" for directory in runtime_dirs]
    return join([harfbuzz_library; rpaths], " ")
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

"""Merge native library parent directories without changing first-seen order."""
function native_runtime_directories(
    paths::Vector{String}, library_paths::Vector{String})
    return unique([paths; dirname.(library_paths)])
end

"""Resolve runtime library search directories for the active provider."""
function native_runtime_dirs(provider::Symbol=harfbuzz_provider())
    provider = validate_harfbuzz_provider(provider)
    paths = if provider == :system
        String[]
    else
        _, jll_paths = harfbuzz_jll_paths()
        Sys.iswindows() ? [Sys.BINDIR; jll_paths] : jll_paths
    end
    native_libraries = [
        sdl3_provider_identity().library_path,
        sdl3_image_provider_identity().library_path,
    ]
    return native_runtime_directories(paths, native_libraries)
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
    if Sys.iswindows()
        return "$(windows_linker_flags()) $(sdl3_linker_flags()) " *
            sdl3_image_linker_flags()
    end
    (Sys.islinux() || Sys.isapple()) || error(
        "SDL3 application linkage is unsupported on $(Sys.KERNEL).")
    harfbuzz_flags = provider == :jll ? unix_harfbuzz_jll_linker_flags() :
        system_harfbuzz_linker_flags()
    return "$harfbuzz_flags $(julia_linker_flags()) $(sdl3_linker_flags()) " *
        sdl3_image_linker_flags()
end

"""Append platform libraries and options required by Odin test executables."""
function native_test_linker_flags(
    linker_flags::String=native_linker_flags(), kernel::Symbol=Sys.KERNEL)
    kernel == :NT && return strip(string(linker_flags, " /STACK:8388608"))
    kernel == :Linux && return strip(string(
        linker_flags,
        " -lX11 -lXrandr -lXi -lXcursor -lXinerama"))
    kernel == :Darwin && return linker_flags
    error("Odin test linkage is unsupported on $kernel.")
end

end