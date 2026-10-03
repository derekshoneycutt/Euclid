module EuclidBuildConfiguration

using SHA
using TOML

export accesskit_artifact_path, accesskit_linker_flags, accesskit_manifest,
    accesskit_provider_identity,
    native_linker_flags, native_runtime_dirs, native_runtime_environment,
    native_test_linker_flags, msvc_build_environment, resolve_msvc_tool_path,
    sdl3_library_path,
    sdl3_linker_flags, sdl3_provider_identity, sdl3_image_library_path,
    sdl3_image_linker_flags, sdl3_image_provider_identity,
    freetype_artifact, freetype_jll_paths, freetype_linker_flags,
    sqlite3_artifact, sqlite3_tool_linker_flags, windows_sdl_manifest

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_PROJECT = joinpath(REPOSITORY_ROOT, "src", "julia")
const IMPORT_LIB_DIR = joinpath(REPOSITORY_ROOT, "bin", ".native_import_libs")
const WINDOWS_SDL_DIR = joinpath(REPOSITORY_ROOT, "libs", "sdl", "bin", "win64")
const ACCESSKIT_ROOT = joinpath(REPOSITORY_ROOT, "libs", "accesskit")
const ACCESSKIT_VERSION = "0.23.1"
const ACCESSKIT_BUNDLE_SHA256 =
    "35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f"
const ACCESSKIT_HEADER_SHA256 =
    "1a99c7a8dac2f5b4fa99ab323d0274ab5a3bbac8bee02220ef941cde4d36af4f"
const HARFBUZZ_PROVIDER_ENV = "EUCLID_HARFBUZZ_PROVIDER"
const SQLITE3_SOURCE_DIR = joinpath(REPOSITORY_ROOT, "libs", "sqlite3", "source")
const SQLITE3_BUILD_DIR = joinpath(REPOSITORY_ROOT, ".build", "sqlite3")
const SQLITE3_INPUTS = [
    "sqlite3.c", "sqlite3.h", "sqlite3ext.h", "spellfix.c", "sqlite3_custom.c"]
const FREETYPE_SOURCE_DIR = joinpath(REPOSITORY_ROOT, "libs", "freetype", "source")
const FREETYPE_BUILD_DIR = joinpath(REPOSITORY_ROOT, ".build", "freetype")

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

struct SQLite3Artifact
    archive_path::String
    fingerprint::String
    compiler_identity::String
end

struct FreeTypeArtifact
    archive_path::String
    fingerprint::String
    compiler_identity::String
    library_path::String
    runtime_dirs::Vector{String}
end

struct AccessKitProviderIdentity
    kind::Symbol
    version::String
    library_path::String
    manifest_path::String
end

"""Return manifest vocabulary for one supported AccessKit target."""
function accesskit_target(kernel::Symbol, architecture::Symbol)
    platform, toolchain, abi, adapter_version = if kernel == :Linux
        ("linux", "gnu", "gnu", "0.24.0")
    elseif kernel == :Darwin
        ("macos", "apple-clang", "darwin", "0.27.1")
    elseif kernel == :NT
        ("windows", "msvc", "msvc", "0.35.1")
    else
        error("AccessKit is unsupported on $kernel.")
    end
    normalized_architecture = architecture == :aarch64 ? "arm64" :
        string(architecture)
    kernel == :Linux && normalized_architecture != "x86_64" && error(
        "AccessKit has no retained Linux $normalized_architecture payload.")
    kernel == :NT && normalized_architecture != "x86_64" && error(
        "AccessKit has no retained Windows $normalized_architecture payload.")
    normalized_architecture in ("x86_64", "arm64") || error(
        "AccessKit has no retained $platform $normalized_architecture payload.")
    return (; platform, architecture=normalized_architecture, toolchain, abi,
        adapter_version)
end

"""Validate one AccessKit payload file against its manifest hash."""
function validate_accesskit_file(
    root::AbstractString, record::AbstractDict, hash_file::Function)
    relative_path = String(get(record, "file", ""))
    isempty(relative_path) && error("AccessKit manifest contains an empty file path.")
    path = joinpath(root, relative_path)
    isfile(path) || error("Missing AccessKit payload file: $relative_path")
    hash_file(path) == get(record, "sha256", "") || error(
        "AccessKit payload hash mismatch: $relative_path")
    return path
end

"""Validate the fixed release and target identity in one AccessKit manifest."""
function validate_accesskit_manifest_identity(
    manifest::AbstractDict, target::NamedTuple)
    get(manifest, "schema_version", 0) == 1 || error(
        "Unsupported AccessKit manifest schema.")
    get(manifest, "name", "") == "accesskit-c" || error(
        "AccessKit manifest has the wrong package name.")
    get(manifest, "version", "") == ACCESSKIT_VERSION || error(
        "AccessKit manifest has the wrong version.")
    get(manifest, "bundle_sha256", "") == ACCESSKIT_BUNDLE_SHA256 || error(
        "AccessKit manifest has the wrong release bundle hash.")
    get(manifest, "accesskit_version", "") == "0.25.1" || error(
        "AccessKit manifest has the wrong schema crate version.")
    get(manifest, "adapter_version", "") == target.adapter_version || error(
        "AccessKit manifest has the wrong adapter crate version.")
    for field in (:platform, :architecture, :toolchain, :abi)
        get(manifest, string(field), "") == getproperty(target, field) || error(
            "AccessKit manifest has the wrong $(field).")
    end
end

"""Validate and return the repository-owned AccessKit payload manifest."""
function accesskit_manifest(
    root::AbstractString=ACCESSKIT_ROOT;
    kernel::Symbol=Sys.KERNEL,
    architecture::Symbol=Sys.ARCH,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)))
    target = accesskit_target(kernel, architecture)
    manifest_path = joinpath(root, "bin", target.platform,
        target.architecture, "manifest.toml")
    isfile(manifest_path) || error(
        "Missing AccessKit manifest at $manifest_path")
    manifest = parse_file(manifest_path)
    validate_accesskit_manifest_identity(manifest, target)
    header = Dict("file" => get(manifest, "header_file", ""),
        "sha256" => get(manifest, "header_sha256", ""))
    get(manifest, "header_sha256", "") == ACCESSKIT_HEADER_SHA256 || error(
        "AccessKit manifest has the wrong tagged header hash.")
    validate_accesskit_file(root, header, hash_file)
    license = Dict("file" => get(manifest, "license_file", ""),
        "sha256" => get(manifest, "license_sha256", ""))
    validate_accesskit_file(root, license, hash_file)
    for record in [get(manifest, "notice", Any[]); get(manifest, "artifact", Any[])]
        validate_accesskit_file(root, record, hash_file)
    end
    isempty(get(manifest, "artifact", Any[])) && error(
        "AccessKit manifest has no artifacts.")
    return manifest
end

"""Return the unique artifact record with one manifest role."""
function accesskit_artifact_record(manifest::AbstractDict, role::AbstractString)
    matches = filter(record -> get(record, "role", "") == role,
        get(manifest, "artifact", Any[]))
    length(matches) == 1 || error(
        "AccessKit manifest must contain exactly one $role artifact.")
    return only(matches)
end

"""Resolve one validated AccessKit artifact by manifest role."""
function accesskit_artifact_path(
    role::AbstractString,
    kernel::Symbol=Sys.KERNEL;
    root::AbstractString=ACCESSKIT_ROOT,
    architecture::Symbol=Sys.ARCH,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)))
    manifest = accesskit_manifest(
        root; kernel, architecture, parse_file, hash_file)
    artifact = accesskit_artifact_record(manifest, role)
    return joinpath(root, String(artifact["file"]))
end

"""Resolve the validated repository-owned AccessKit provider."""
function accesskit_provider_identity(
    kernel::Symbol=Sys.KERNEL;
    root::AbstractString=ACCESSKIT_ROOT,
    architecture::Symbol=Sys.ARCH,
    hash_file::Function=path -> bytes2hex(open(sha256, path)))
    target = accesskit_target(kernel, architecture)
    manifest = accesskit_manifest(root; kernel, architecture, hash_file)
    runtime_role = kernel == :NT ? "runtime" : "runtime-link-library"
    artifact = accesskit_artifact_record(manifest, runtime_role)
    library_path = joinpath(root, String(artifact["file"]))
    manifest_path = joinpath(root, "bin", target.platform,
        target.architecture, "manifest.toml")
    return AccessKitProviderIdentity(
        :repository, String(manifest["version"]), library_path, manifest_path)
end

"""Return linker flags for the validated AccessKit payload."""
function accesskit_linker_flags(
    kernel::Symbol=Sys.KERNEL;
    root::AbstractString=ACCESSKIT_ROOT,
    architecture::Symbol=Sys.ARCH)
    provider = accesskit_provider_identity(kernel; root, architecture)
    directory = dirname(provider.library_path)
    kernel == :NT && return "/LIBPATH:$(normpath(directory)) /DEFAULTLIB:accesskit.lib"
    return "-L$directory -Wl,-rpath,$directory -laccesskit"
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

"""Capture the Visual Studio x64 compiler and Windows SDK environment."""
function msvc_build_environment()
    vcvars = resolve_msvc_tool_path(
        "VC/Auxiliary/Build/vcvars64.bat",
        "Could not locate vcvars64.bat. Install the C++ Build Tools workload.")
    output = IOBuffer()
    command = Cmd(["cmd", "/d", "/c", "call", vcvars, ">nul", "&&", "set"])
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=devnull))
    process.exitcode == 0 || error(
        "Could not initialize the Visual Studio x64 build environment.")
    environment = Dict{String,String}()
    for line in split(String(take!(output)), '\n')
        separator = findfirst(==('='), line)
        (separator === nothing || separator == firstindex(line)) && continue
        key = strip(line[firstindex(line):prevind(line, separator)])
        value = strip(line[nextind(line, separator):end])
        environment[key] = value
    end
    return environment
end

"""Resolve the host C compiler and static archiver for SQLite."""
function sqlite3_tool_paths(kernel::Symbol=Sys.KERNEL)
    if kernel == :NT
        compiler = resolve_msvc_tool_path(
            "VC/Tools/MSVC/**/bin/Hostx64/x64/cl.exe",
            "Could not locate MSVC cl.exe. Install the C++ Build Tools workload.")
        archiver = resolve_msvc_tool_path(
            "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe",
            "Could not locate MSVC lib.exe. Install the C++ Build Tools workload.")
        return compiler, archiver
    end
    (kernel == :Linux || kernel == :Darwin) || error(
        "SQLite archive builds are unsupported on $kernel.")
    compiler = Sys.which(get(ENV, "CC", "cc"))
    compiler === nothing && error("Could not locate the host C compiler.")
    archiver = Sys.which(get(ENV, "AR", "ar"))
    archiver === nothing && error("Could not locate the host static archiver.")
    return compiler, archiver
end

"""Capture one native tool identity for the SQLite archive fingerprint."""
function sqlite3_tool_identity(path::String, kernel::Symbol=Sys.KERNEL)
    arguments = kernel == :NT ? [path] : [path, "--version"]
    result = capture_command(Cmd(arguments))
    identity = strip(string(result.output, result.error_output))
    return isempty(identity) ? path : "$path\n$identity"
end

"""Return the platform compile arguments for the SQLite translation unit."""
function sqlite3_compile_arguments(
    compiler::String, object_path::String, kernel::Symbol=Sys.KERNEL)
    source = joinpath(SQLITE3_SOURCE_DIR, "sqlite3_custom.c")
    if kernel == :NT
        return [compiler, "/nologo", "/c", "/O2", "/DNDEBUG",
            "/Fo$object_path", source]
    end
    return [compiler, "-std=c17", "-O2", "-DNDEBUG", "-fPIC", "-c",
        source, "-o", object_path]
end

"""Hash SQLite inputs, tools, target, and flags into one archive identity."""
function sqlite3_fingerprint(
    compiler::String, archiver::String, kernel::Symbol=Sys.KERNEL)
    input_hashes = [bytes2hex(open(sha256, joinpath(SQLITE3_SOURCE_DIR, name)))
        for name in SQLITE3_INPUTS]
    object_name = kernel == :NT ? "sqlite3.obj" : "sqlite3.o"
    compile_arguments = sqlite3_compile_arguments(compiler, object_name, kernel)
    identity = [string(kernel), string(Sys.ARCH), compile_arguments...,
        sqlite3_tool_identity(compiler, kernel),
        sqlite3_tool_identity(archiver, kernel), input_hashes...]
    return bytes2hex(sha256(join(identity, '\n')))
end

"""Compile and archive SQLite in one candidate directory."""
function build_sqlite3_archive(
    directory::String, compiler::String, archiver::String,
    kernel::Symbol=Sys.KERNEL)
    object_path = joinpath(directory, kernel == :NT ? "sqlite3.obj" : "sqlite3.o")
    archive_path = joinpath(directory, kernel == :NT ? "sqlite3.lib" : "libsqlite3.a")
    compile_command = Cmd(sqlite3_compile_arguments(compiler, object_path, kernel))
    kernel == :NT && (compile_command = addenv(
        compile_command, msvc_build_environment()))
    compile_result = capture_command(compile_command)
    compile_result.exit_code == 0 || error(
        "SQLite compilation failed: " *
        strip(compile_result.output * compile_result.error_output))
    archive_arguments = kernel == :NT ?
        [archiver, "/nologo", "/OUT:$archive_path", object_path] :
        [archiver, "rcs", archive_path, object_path]
    archive_command = Cmd(archive_arguments)
    kernel == :NT && (archive_command = addenv(
        archive_command, msvc_build_environment()))
    archive_result = capture_command(archive_command)
    archive_result.exit_code == 0 || error(
        "SQLite archive creation failed: " *
        strip(archive_result.output * archive_result.error_output))
    return archive_path
end

"""Build or reuse the content-addressed repository SQLite archive."""
function sqlite3_artifact(kernel::Symbol=Sys.KERNEL)
    compiler, archiver = sqlite3_tool_paths(kernel)
    fingerprint = sqlite3_fingerprint(compiler, archiver, kernel)
    final_directory = joinpath(SQLITE3_BUILD_DIR, fingerprint)
    archive_name = kernel == :NT ? "sqlite3.lib" : "libsqlite3.a"
    archive_path = joinpath(final_directory, archive_name)
    if !isfile(archive_path)
        mkpath(SQLITE3_BUILD_DIR)
        mktempdir(SQLITE3_BUILD_DIR) do candidate_directory
            build_sqlite3_archive(candidate_directory, compiler, archiver, kernel)
            ispath(final_directory) && rm(final_directory; force=true, recursive=true)
            mv(candidate_directory, final_directory)
        end
    end
    compiler_identity = sqlite3_tool_identity(compiler, kernel)
    return SQLite3Artifact(archive_path, fingerprint, compiler_identity)
end

"""Return linker flags for the repository-owned SQLite archive."""
function sqlite3_linker_flags(kernel::Symbol=Sys.KERNEL)
    artifact = sqlite3_artifact(kernel)
    directory = dirname(artifact.archive_path)
    return kernel == :NT ? "/LIBPATH:$directory /DEFAULTLIB:sqlite3.lib" :
        "-L$directory -lsqlite3"
end

"""Return the minimal platform linkage for a standalone SQLite build tool."""
function sqlite3_tool_linker_flags(kernel::Symbol=Sys.KERNEL)
    flags = sqlite3_linker_flags(kernel)
    kernel == :Linux && return "$flags -lm -ldl -lpthread"
    (kernel == :Darwin || kernel == :NT) && return flags
    error("SQLite build-tool linkage is unsupported on $kernel.")
end

"""Resolve the pinned Linux FreeType library, headers, and runtime directories."""
function freetype_jll_paths(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux || error(
        "The Phase 2 FreeType adapter currently supports Linux only.")
    snippet = "using FreeType2_jll; " *
        "println(FreeType2_jll.libfreetype_path); " *
        "println.(FreeType2_jll.LIBPATH_list); " *
        "println(FreeType2_jll.artifact_dir); " *
        "println(Base.pkgversion(FreeType2_jll))"
    command = Cmd([
        Base.julia_cmd().exec...,
        "--project=$JULIA_PROJECT",
        "-e",
        snippet,
    ])
    result = capture_command(command)
    result.exit_code == 0 || error(
        "Failed to resolve FreeType2_jll paths: $(strip(result.error_output))")
    paths = filter(!isempty, String.(strip.(split(result.output, '\n'))))
    length(paths) >= 4 || error("FreeType2_jll returned incomplete artifact paths.")
    library_path, runtime_dirs, artifact_dir, version =
        first(paths), unique(paths[2:end-2]), paths[end-1], paths[end]
    isfile(library_path) || error("Missing FreeType library at $library_path.")
    include_dir = joinpath(artifact_dir, "include", "freetype2")
    all(isfile(joinpath(include_dir, path)) for path in
        ("ft2build.h", "freetype/freetype.h", "freetype/config/ftconfig.h")) ||
        error("FreeType2_jll does not contain the expected matching headers.")
    return (; library_path, runtime_dirs, include_dir, version)
end

"""Hash adapter sources and every pinned FreeType header input."""
function freetype_input_hashes(include_dir::String)
    source_hashes = [bytes2hex(open(sha256, joinpath(FREETYPE_SOURCE_DIR, name)))
        for name in ("euclid_freetype.c", "euclid_freetype.h")]
    header_paths = String[]
    for (directory, _, files) in walkdir(include_dir)
        append!(header_paths, joinpath(directory, file) for file in files)
    end
    sort!(header_paths)
    header_hashes = [bytes2hex(open(sha256, path)) for path in header_paths]
    return [source_hashes; header_hashes]
end

"""Build the repository-owned FreeType adapter archive in one candidate directory."""
function build_freetype_archive(
    directory::String, compiler::String, archiver::String,
    include_dir::String)
    object_path = joinpath(directory, "euclid_freetype.o")
    archive_path = joinpath(directory, "libeuclid_freetype.a")
    source_path = joinpath(FREETYPE_SOURCE_DIR, "euclid_freetype.c")
    compile_result = capture_command(Cmd([
        compiler, "-std=c17", "-O2", "-DNDEBUG", "-fPIC", "-Wall", "-Wextra",
        "-Werror", "-I$include_dir", "-c", source_path, "-o", object_path,
    ]))
    compile_result.exit_code == 0 || error(
        "FreeType adapter compilation failed: " *
        strip(compile_result.output * compile_result.error_output))
    archive_result = capture_command(Cmd([
        archiver, "rcs", archive_path, object_path,
    ]))
    archive_result.exit_code == 0 || error(
        "FreeType adapter archive creation failed: " *
        strip(archive_result.output * archive_result.error_output))
    return archive_path
end

"""Build or reuse the content-addressed Linux FreeType adapter archive."""
function freetype_artifact(kernel::Symbol=Sys.KERNEL)
    paths = freetype_jll_paths(kernel)
    compiler = Sys.which(get(ENV, "CC", "cc"))
    archiver = Sys.which(get(ENV, "AR", "ar"))
    compiler === nothing && error("Could not locate the host C compiler.")
    archiver === nothing && error("Could not locate the host static archiver.")
    compile_arguments = [compiler, "-std=c17", "-O2", "-DNDEBUG", "-fPIC",
        "-Wall", "-Wextra", "-Werror", "-I$(paths.include_dir)"]
    identity = [string(kernel), string(Sys.ARCH), paths.version,
        bytes2hex(open(sha256, paths.library_path)), compile_arguments...,
        sqlite3_tool_identity(compiler, kernel), sqlite3_tool_identity(archiver, kernel),
        freetype_input_hashes(paths.include_dir)...]
    fingerprint = bytes2hex(sha256(join(identity, '\n')))
    final_directory = joinpath(FREETYPE_BUILD_DIR, fingerprint)
    archive_path = joinpath(final_directory, "libeuclid_freetype.a")
    if !isfile(archive_path)
        mkpath(FREETYPE_BUILD_DIR)
        mktempdir(FREETYPE_BUILD_DIR) do candidate_directory
            build_freetype_archive(
                candidate_directory, compiler, archiver, paths.include_dir)
            ispath(final_directory) && rm(final_directory; force=true, recursive=true)
            mv(candidate_directory, final_directory)
        end
    end
    return FreeTypeArtifact(archive_path, fingerprint,
        sqlite3_tool_identity(compiler, kernel), paths.library_path,
        unique(paths.runtime_dirs))
end

"""Return Linux linker flags for the pinned FreeType and Euclid adapter."""
function freetype_linker_flags(kernel::Symbol=Sys.KERNEL)
    artifact = freetype_artifact(kernel)
    return "-L$(dirname(artifact.archive_path)) -leuclid_freetype " *
        "$(artifact.library_path) " *
        "-Wl,-rpath-link,$(join(artifact.runtime_dirs, ':'))"
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
        accesskit_provider_identity().library_path,
        sdl3_provider_identity().library_path,
        sdl3_image_provider_identity().library_path,
    ]
    Sys.islinux() && append!(paths, freetype_jll_paths().runtime_dirs)
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
            "$(sdl3_image_linker_flags()) $(accesskit_linker_flags()) " *
            "$(sqlite3_linker_flags())"
    end
    (Sys.islinux() || Sys.isapple()) || error(
        "SDL3 application linkage is unsupported on $(Sys.KERNEL).")
    harfbuzz_flags = provider == :jll ? unix_harfbuzz_jll_linker_flags() :
        system_harfbuzz_linker_flags()
    freetype_flags = Sys.islinux() ? freetype_linker_flags() : ""
    return "$harfbuzz_flags $(julia_linker_flags()) $(sdl3_linker_flags()) " *
        "$(sdl3_image_linker_flags()) $(accesskit_linker_flags()) " *
        "$(sqlite3_linker_flags()) $freetype_flags"
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