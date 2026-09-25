module EuclidSDL3ImageProbe

using Base64
using Dates
using SHA
import Main.EuclidSDL3Probe
import Main.EuclidBuildConfiguration

export image_binding_path, image_probe_build_command, image_runtime_evidence,
    run_image_probe

const SCHEMA_VERSION = "1.0.0"
const PROBE_RELATIVE_DIR = joinpath("tools", "sdl3_image_probe")
const OUTPUT_RELATIVE_DIR = joinpath(".build", "sdl3-image-probe")
const JPEG_FIXTURE = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAB//EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAH/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AIi2L3//Z"
const PNG_FIXTURE = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
const GIF_FIXTURE = "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="

struct ImageProbeArtifacts
    output_dir::String
    diagnostics_path::String
    result_path::String
    source_dir::String
    binary::String
    jpeg_fixture::String
    png_fixture::String
    gif_fixture::String
    animation_output::String
end

"""Resolve the installed Odin SDL_image binding used by the native probe."""
function image_binding_path(odin_root::AbstractString; kernel::Symbol=Sys.KERNEL)
    kernel in (:Linux, :Darwin) || error(
        "The SDL_image capability probe is unsupported on $kernel.")
    path = joinpath(normpath(odin_root), "vendor", "sdl3", "image", "sdl_image.odin")
    isfile(path) || error("Missing Odin SDL_image binding file: $path")
    return path
end

"""Return the strict command used to build the isolated SDL_image probe."""
function image_probe_build_command(
    source::AbstractString, output::AbstractString, linker_flags::AbstractString)
    isempty(strip(linker_flags)) && error("SDL_image linker flags must not be empty.")
    return Cmd([
        "odin", "build", source, "-out:$output", "-vet", "-strict-style",
        "-disallow-do", "-warnings-as-errors",
        "-extra-linker-flags:$(String(linker_flags))",
    ])
end

"""Create fresh generated paths for one SDL_image probe invocation."""
function prepare_image_artifacts(root::String)
    output_dir = joinpath(root, OUTPUT_RELATIVE_DIR)
    rm(output_dir; recursive=true, force=true)
    mkpath(output_dir)
    return ImageProbeArtifacts(
        output_dir,
        joinpath(output_dir, "diagnostics.log"),
        joinpath(output_dir, "result.json"),
        joinpath(root, PROBE_RELATIVE_DIR),
        joinpath(output_dir, "euclid-sdl3-image-probe"),
        joinpath(output_dir, "static.jpg"),
        joinpath(output_dir, "static.png"),
        joinpath(output_dir, "static.gif"),
        joinpath(output_dir, "animated.gif"))
end

"""Write deterministic required-codec fixtures into the generated probe directory."""
function write_image_fixtures!(paths::ImageProbeArtifacts)
    for (path, encoded) in (
        (paths.jpeg_fixture, JPEG_FIXTURE),
        (paths.png_fixture, PNG_FIXTURE),
        (paths.gif_fixture, GIF_FIXTURE))
        write(path, base64decode(encoded))
    end
end

"""Return the loaded SDL_image path reported for the probe executable."""
function loaded_sdl3_image_path(ldd_output::String)
    for line in split(ldd_output, '\n')
        occursin("libSDL3_image.so", line) || continue
        match_result = match(r"=>\s+(\S+)", line)
        match_result === nothing || return match_result.captures[1]
    end
    return ""
end

"""Return the loaded SDL_image path reported by Mach-O inspection."""
function loaded_sdl3_image_path_darwin(otool_output::String)
    for line in split(otool_output, '\n')
        match_result = match(
            r"^\s+(\S*libSDL3_image(?:\.[^/]*)?\.dylib)\s+\(", line)
        match_result === nothing || return match_result.captures[1]
    end
    return ""
end

"""Normalize line-oriented image capability facts into the result schema."""
function image_runtime_evidence(facts::Dict{String,String})
    return Dict{String,Any}(
        "binding_version" => get(facts, "binding_version", ""),
        "runtime_version" => EuclidSDL3Probe.dotted_runtime_version(
            get(facts, "runtime_version", "")),
        "jpeg_decode" => get(facts, "jpeg_decode", "false") == "true",
        "png_decode" => get(facts, "png_decode", "false") == "true",
        "gif_decode" => get(facts, "gif_decode", "false") == "true",
        "gif_encode" => get(facts, "gif_encode", "false") == "true",
        "gif_stream_decode" =>
            get(facts, "gif_stream_decode", "false") == "true",
        "animation_frames" => parse(Int, get(facts, "animation_frames", "0")),
        "animation_delays_ms" => [parse(Int, value) for value in
            split(get(facts, "animation_delays", ""), ','; keepempty=false)],
        "cleanup_complete" => get(facts, "cleanup_complete", "false") == "true")
end

"""Require every external command used by the image probe."""
function require_image_probe_tools()
    (Sys.islinux() || Sys.isapple()) || error(
        "The SDL_image capability probe is unsupported on $(Sys.KERNEL).")
    EuclidSDL3Probe.require_tool("odin", "Install the Odin compiler.")
    EuclidSDL3Probe.require_tool(
        "pkg-config", "Install pkg-config and SDL_image development metadata.")
    if Sys.islinux()
        EuclidSDL3Probe.require_tool("readelf", "Install binutils.")
        EuclidSDL3Probe.require_tool("ldd", "Install the system ELF loader tools.")
    else
        EuclidSDL3Probe.require_tool(
            "otool", "Install the Xcode command-line tools.")
    end
end

"""Record host, binding, and mandatory system SDL_image provider identities."""
function collect_image_environment!(result, diagnostics::IO, root::String)
    odin_root = EuclidSDL3Probe.command_value!(
        diagnostics, "odin-root", Cmd(["odin", "root"]); cwd=root)
    odin_version = EuclidSDL3Probe.command_value!(
        diagnostics, "odin-version", Cmd(["odin", "version"]); cwd=root)
    binding = image_binding_path(odin_root)
    provider = EuclidBuildConfiguration.sdl3_image_provider_identity()
    result["host"] = Dict{String,Any}(
        "kernel" => string(Sys.KERNEL), "architecture" => string(Sys.ARCH),
        "kernel_release" => EuclidSDL3Probe.command_value!(diagnostics,
            "kernel-release", Cmd(["uname", "-r"]); cwd=root))
    result["git"] = EuclidSDL3Probe.git_metadata!(diagnostics, root)
    result["odin"] = Dict{String,Any}("version" => odin_version, "root" => odin_root)
    result["binding"] = Dict{String,Any}(
        "path" => binding, "sha256" => EuclidSDL3Probe.file_sha256(binding))
    result["sdl_image_provider"] = Dict{String,Any}(
        "kind" => "system", "pkg_config_version" => provider.version,
        "library_path" => provider.library_path,
        "sha256" => EuclidSDL3Probe.file_sha256(provider.library_path))
    return provider.library_path
end

"""Strict-build the standalone image probe and record its binary identity."""
function build_image_probe!(result, diagnostics::IO, root::String,
    paths::ImageProbeArtifacts)
    flags = EuclidSDL3Probe.command_value!(diagnostics, "sdl-image-linker-flags",
        Cmd(["pkg-config", "--libs", "sdl3-image"]); cwd=root)
    command = image_probe_build_command(paths.source_dir, paths.binary, flags)
    EuclidSDL3Probe.checked_step!(diagnostics, "probe-build", command; cwd=root)
    result["executable"] = Dict{String,Any}(
        "path" => paths.binary,
        "sha256" => EuclidSDL3Probe.file_sha256(paths.binary))
end

"""Run the bounded native image probe and require every advertised capability."""
function run_image_runtime!(result, diagnostics::IO, root::String,
    paths::ImageProbeArtifacts)
    command = Cmd([paths.binary, paths.jpeg_fixture,
        paths.png_fixture, paths.gif_fixture, paths.animation_output])
    println(diagnostics, "[probe-runtime] ", command)
    runtime = EuclidSDL3Probe.capture_command_timeout(command, 15; cwd=root)
    write(diagnostics, runtime.stdout)
    write(diagnostics, runtime.stderr)
    facts = EuclidSDL3Probe.parse_probe_output(runtime.stdout * runtime.stderr)
    result["runtime"] = image_runtime_evidence(facts)
    runtime.exit_code == 0 || error(
        "probe-runtime failed with exit code $(runtime.exit_code)")
    get(facts, "result", "") == "passed" || error(
        "SDL_image probe did not report a passing result.")
    required = ("jpeg_decode", "png_decode", "gif_decode", "gif_encode",
        "gif_stream_decode", "cleanup_complete")
    all(name -> result["runtime"][name], required) || error(
        "SDL_image probe omitted a required capability.")
    result["runtime"]["animation_frames"] == 2 || error(
        "SDL_image probe did not decode two animation frames.")
    result["runtime"]["animation_delays_ms"] == [40, 80] || error(
        "SDL_image probe did not preserve animation delays.")
end

"""Record the executable dependency closure and loaded SDL_image SONAME."""
function inspect_image_binary!(result, diagnostics::IO, root::String,
    paths::ImageProbeArtifacts, library::String)
    dependency_command = Sys.isapple() ? Cmd(["otool", "-L", paths.binary]) :
        Cmd(["ldd", paths.binary])
    identity_command = Sys.isapple() ? Cmd(["otool", "-D", library]) :
        Cmd(["readelf", "-d", library])
    dependency_result = EuclidSDL3Probe.checked_step!(
        diagnostics, "dynamic-dependencies", dependency_command; cwd=root)
    identity_result = EuclidSDL3Probe.checked_step!(
        diagnostics, "runtime-identity", identity_command; cwd=root)
    result["dynamic_dependencies"] = split(chomp(dependency_result.stdout), '\n';
        keepempty=false)
    provider = result["sdl_image_provider"]
    if Sys.isapple()
        provider["loaded_path"] =
            loaded_sdl3_image_path_darwin(dependency_result.stdout)
        lines = split(chomp(identity_result.stdout), '\n'; keepempty=false)
        provider["install_name"] = length(lines) < 2 ? "" : strip(lines[2])
    else
        provider["loaded_path"] = loaded_sdl3_image_path(dependency_result.stdout)
        soname = match(r"Library soname: \[([^]]+)\]", identity_result.stdout)
        provider["soname"] = soname === nothing ? "" : soname.captures[1]
    end
end

"""Execute each image probe stage and update the current failure marker."""
function execute_image_probe!(result, diagnostics::IO, root::String,
    paths::ImageProbeArtifacts)
    result["failed_stage"] = "tool_discovery"
    require_image_probe_tools()
    result["failed_stage"] = "provider_discovery"
    library = collect_image_environment!(result, diagnostics, root)
    result["failed_stage"] = "fixture_generation"
    write_image_fixtures!(paths)
    result["failed_stage"] = "probe_build"
    build_image_probe!(result, diagnostics, root, paths)
    result["failed_stage"] = "runtime"
    run_image_runtime!(result, diagnostics, root, paths)
    result["failed_stage"] = "binary_inspection"
    inspect_image_binary!(result, diagnostics, root, paths, library)
    result["result"] = "passed"
    result["failed_stage"] = nothing
    result["reason"] = "SDL_image static and streaming GIF capability probe passed"
end

"""Build and run the explicit SDL_image capability probe."""
function run_image_probe(root::String)
    paths = prepare_image_artifacts(root)
    result = EuclidSDL3Probe.initial_result()
    result["schema_version"] = SCHEMA_VERSION
    status = 1
    open(paths.diagnostics_path, "w") do diagnostics
        try
            execute_image_probe!(result, diagnostics, root, paths)
            status = 0
        catch error_object
            result["reason"] = sprint(showerror, error_object)
            println(diagnostics, "[failure] ", result["reason"])
        finally
            EuclidSDL3Probe.write_result(paths.result_path, result)
        end
    end
    println("Wrote $(relpath(paths.result_path, root))")
    println("Wrote $(relpath(paths.diagnostics_path, root))")
    return status
end

end
