module EuclidSDL3Probe

using Dates
using SHA
import Main.EuclidBuildConfiguration
import Main.EuclidShaders

export ProbeCommandResult, binding_paths, parse_probe_output, probe_build_command,
    probe_shader_command, run_probe

const SCHEMA_VERSION = "1.0.0"
const PROBE_RELATIVE_DIR = joinpath("tools", "sdl3_probe")
const OUTPUT_RELATIVE_DIR = joinpath(".build", "sdl3-probe")

struct ProbeCommandResult
    exit_code::Int
    stdout::String
    stderr::String
end

struct ProbeArtifacts
    output_dir::String
    diagnostics_path::String
    result_path::String
    source_dir::String
    vertex_source::String
    fragment_source::String
    vertex_spv::String
    fragment_spv::String
    vertex_runtime::String
    fragment_runtime::String
    binary::String
end

"""Run one probe subprocess and capture both output streams."""
function capture_command(command::Cmd; cwd::Union{Nothing,String}=nothing)
    stdout = IOBuffer()
    stderr = IOBuffer()
    command = cwd === nothing ? command : Cmd(command; dir=cwd)
    if Sys.iswindows()
        runtime_path = join(EuclidShaders.windows_shadercross_runtime_dirs(), ';')
        command = addenv(command, "PATH" => string(
            runtime_path, ';', get(ENV, "PATH", "")))
    end
    process = run(pipeline(ignorestatus(command), stdout=stdout, stderr=stderr))
    return ProbeCommandResult(
        process.exitcode, String(take!(stdout)), String(take!(stderr)))
end

"""Resolve the binding files that define the SDL3 ABI used by the probe."""
function binding_paths(odin_root::AbstractString; kernel::Symbol=Sys.KERNEL)
    kernel in (:Linux, :Darwin, :NT) || error(
        "The SDL3 capability probe is unsupported on $kernel.")
    root = normpath(odin_root)
    paths = [
        joinpath(root, "vendor", "sdl3", "sdl3__foreign.odin"),
        joinpath(root, "vendor", "sdl3", "sdl3_gpu.odin"),
        joinpath(root, "vendor", "sdl3", "sdl3_version.odin"),
    ]
    missing = filter(path -> !isfile(path), paths)
    isempty(missing) || error("Missing Odin SDL3 binding file: $(first(missing))")
    return paths
end

"""Run one bounded probe subprocess and capture both output streams."""
function capture_command_timeout(
    command::Cmd, timeout_seconds::Real; cwd::Union{Nothing,String}=nothing)
    stdout = IOBuffer()
    stderr = IOBuffer()
    command = cwd === nothing ? command : Cmd(command; dir=cwd)
    process = run(pipeline(
        ignorestatus(command), stdout=stdout, stderr=stderr); wait=false)
    wait_status = timedwait(() -> process_exited(process), timeout_seconds)
    if wait_status == :timed_out
        kill(process)
        wait(process)
        return ProbeCommandResult(
            124, String(take!(stdout)), String(take!(stderr)))
    end
    wait(process)
    return ProbeCommandResult(
        process.exitcode, String(take!(stdout)), String(take!(stderr)))
end

"""Return the strict Odin command used to build the isolated probe."""
function probe_build_command(
    source::String, output::String; linker_flags::String="")
    arguments = [
        "odin", "build", source, "-out:$output", "-vet", "-strict-style",
        "-disallow-do", "-warnings-as-errors",
    ]
    isempty(linker_flags) || push!(arguments,
        "-extra-linker-flags:$linker_flags")
    return Cmd(arguments)
end

"""Return the deterministic GLSL-to-SPIR-V command for one shader stage."""
function probe_shader_command(source::String, output::String, stage::String)
    stage in ("vertex", "fragment") || error("Unsupported probe shader stage: $stage")
    return Cmd(["glslc", "-fshader-stage=$stage", source, "-o", output])
end

"""Return the deterministic SPIR-V-to-MSL command for one shader stage."""
function probe_msl_command(
    tool::String, source::String, output::String, stage::String)
    stage in ("vertex", "fragment") || error(
        "Unsupported probe shader stage: $stage")
    return Cmd([tool, source, "--source", "SPIRV", "--dest", "MSL",
        "--stage", stage, "--entrypoint", "main", "--msl-version", "2.0.0",
        "--output", output])
end

"""Return the shadercross command for one probe shader conversion."""
function probe_shadercross_command(tool::String, source::String, output::String,
    source_format::String, destination_format::String, stage::String)
    stage in ("vertex", "fragment") || error(
        "Unsupported probe shader stage: $stage")
    return Cmd([tool, source, "--source", source_format, "--dest",
        destination_format, "--stage", stage, "--entrypoint", "main",
        "--output", output])
end

"""Parse the probe's line-oriented runtime facts without interpreting values."""
function parse_probe_output(output::String)
    facts = Dict{String,String}()
    drivers = String[]
    for raw_line in split(output, '\n')
        line = strip(raw_line)
        startswith(line, "probe.") || continue
        separator = findfirst(==('='), line)
        separator === nothing && continue
        key = line[7:prevind(line, separator)]
        value = line[nextind(line, separator):end]
        if startswith(key, "gpu_driver[")
            push!(drivers, value)
        else
            facts[key] = value
        end
    end
    facts["gpu_drivers"] = join(drivers, ",")
    return facts
end

"""Write one JSON string with complete control-character escaping."""
function write_json_string(io::IO, value::AbstractString)
    print(io, '"')
    for character in value
        if character == '"'
            print(io, "\\\"")
        elseif character == '\\'
            print(io, "\\\\")
        elseif character == '\n'
            print(io, "\\n")
        elseif character == '\r'
            print(io, "\\r")
        elseif character == '\t'
            print(io, "\\t")
        elseif Int(character) < 0x20
            print(io, "\\u", uppercase(string(Int(character), base=16, pad=4)))
        else
            print(io, character)
        end
    end
    print(io, '"')
end

"""Write one JSON null literal."""
write_json(io::IO, _value::Nothing) = print(io, "null")

"""Write one JSON boolean literal."""
write_json(io::IO, value::Bool) = print(io, value)

"""Write one JSON number literal."""
write_json(io::IO, value::Number) = print(io, value)

"""Write one JSON string value."""
write_json(io::IO, value::AbstractString) = write_json_string(io, value)

"""Write one JSON array value."""
function write_json(io::IO, value::AbstractVector)
    print(io, '[')
    for (index, item) in enumerate(value)
        index > 1 && print(io, ',')
        write_json(io, item)
    end
    print(io, ']')
end

"""Write one JSON object with stable key ordering."""
function write_json(io::IO, value::AbstractDict)
    print(io, '{')
    for (index, key) in enumerate(sort!(collect(keys(value))))
        index > 1 && print(io, ',')
        write_json_string(io, string(key))
        print(io, ':')
        write_json(io, value[key])
    end
    print(io, '}')
end

"""Write the coordinator-owned result envelope atomically enough for local evidence."""
function write_result(path::String, result::Dict{String,Any})
    open(path, "w") do io
        write_json(io, result)
        write(io, '\n')
    end
end

"""Return a SHA-256 digest for one evidence input or artifact."""
file_sha256(path::String) = bytes2hex(open(sha256, path))

"""Require one external probe command and return its resolved executable path."""
function require_tool(name::String, hint::String)
    path = Sys.which(name)
    path === nothing && error("$name is required for the SDL3 probe. $hint")
    return path
end

"""Run a checked probe step, retaining its command and streams in diagnostics."""
function checked_step!(
    diagnostics::IO, stage::String, command::Cmd; cwd::Union{Nothing,String}=nothing)
    println(diagnostics, "[$stage] ", command)
    result = capture_command(command; cwd)
    write(diagnostics, result.stdout)
    write(diagnostics, result.stderr)
    (!isempty(result.stdout) && !endswith(result.stdout, '\n')) && println(diagnostics)
    (!isempty(result.stderr) && !endswith(result.stderr, '\n')) && println(diagnostics)
    result.exit_code == 0 || error("$stage failed with exit code $(result.exit_code)")
    return result
end

"""Resolve one command's first nonempty output line."""
function command_value!(
    diagnostics::IO, stage::String, command::Cmd; cwd::Union{Nothing,String}=nothing)
    result = checked_step!(diagnostics, stage, command; cwd)
    return strip(result.stdout)
end

"""Return the loaded SDL3 path reported for the probe executable."""
function loaded_sdl_path(ldd_output::String)
    for line in split(ldd_output, '\n')
        occursin("libSDL3.so", line) || continue
        match_result = match(r"=>\s+(\S+)", line)
        match_result === nothing || return match_result.captures[1]
    end
    return ""
end

"""Return the loaded SDL3 path reported by Mach-O dependency inspection."""
function loaded_sdl_path_darwin(otool_output::String)
    for line in split(otool_output, '\n')
        match_result = match(r"^\s+(\S*libSDL3(?:\.[^/]*)?\.dylib)\s+\(", line)
        match_result === nothing || return match_result.captures[1]
    end
    return ""
end

"""Return an integer runtime version as dotted major, minor, and micro fields."""
function dotted_runtime_version(value::String)
    version = tryparse(Int, value)
    version === nothing && return value
    major = version ÷ 1_000_000
    minor = version ÷ 1_000 % 1_000
    micro = version % 1_000
    return "$major.$minor.$micro"
end

"""Return the working tree's concise status for probe provenance."""
function git_metadata!(diagnostics::IO, root::String)
    branch = command_value!(diagnostics, "git-branch",
        Cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"]); cwd=root)
    commit = command_value!(diagnostics, "git-commit",
        Cmd(["git", "rev-parse", "HEAD"]); cwd=root)
    status = checked_step!(diagnostics, "git-status",
        Cmd(["git", "status", "--short"]); cwd=root).stdout
    return Dict{String,Any}(
        "branch" => branch,
        "commit" => commit,
        "worktree_status" => split(chomp(status), '\n'; keepempty=false))
end

"""Create fresh generated paths for one probe invocation."""
function prepare_artifacts(root::String)
    output_dir = joinpath(root, OUTPUT_RELATIVE_DIR)
    rm(output_dir; recursive=true, force=true)
    mkpath(output_dir)
    source_dir = joinpath(root, PROBE_RELATIVE_DIR)
    vertex_spv = joinpath(output_dir, "triangle.vert.spv")
    fragment_spv = joinpath(output_dir, "triangle.frag.spv")
    runtime_extension = Sys.iswindows() ? "dxil" : Sys.isapple() ? "msl" : "spv"
    return ProbeArtifacts(
        output_dir,
        joinpath(output_dir, "diagnostics.log"),
        joinpath(output_dir, "result.json"),
        source_dir,
        joinpath(source_dir,
            Sys.iswindows() ? "triangle.vert.hlsl" : "triangle.vert"),
        joinpath(source_dir,
            Sys.iswindows() ? "triangle.frag.hlsl" : "triangle.frag"),
        vertex_spv,
        fragment_spv,
        runtime_extension == "spv" ? vertex_spv :
            joinpath(output_dir, "triangle.vert.$runtime_extension"),
        runtime_extension == "spv" ? fragment_spv :
            joinpath(output_dir, "triangle.frag.$runtime_extension"),
        joinpath(output_dir,
            Sys.iswindows() ? "euclid-sdl3-probe.exe" : "euclid-sdl3-probe"))
end

"""Create the failure-first result envelope owned by the coordinator."""
function initial_result()
    return Dict{String,Any}(
        "schema_version" => SCHEMA_VERSION,
        "timestamp_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "result" => "failed",
        "failed_stage" => "initialization",
        "reason" => "probe did not complete")
end

"""Resolve the shadercross executable used for Darwin MSL generation."""
function probe_shadercross_path(root::String)
    override = get(ENV, "EUCLID_SHADERCROSS", "")
    candidates = isempty(override) ? [
        joinpath(root, ".build", "shadercross",
            Sys.iswindows() ? "shadercross.exe" : "shadercross"),
        something(Sys.which("shadercross"), ""),
    ] : [override]
    index = findfirst(isfile, candidates)
    index === nothing && error(
        "shadercross is required for the Darwin SDL3 probe. Build assets first.")
    return realpath(candidates[index])
end

"""Require every external command used by the platform probe."""
function require_probe_tools(root::String)
    (Sys.islinux() || Sys.isapple() || Sys.iswindows()) || error(
        "The SDL3 capability probe is unsupported on $(Sys.KERNEL).")
    require_tool("odin", "Install the Odin compiler.")
    if Sys.iswindows()
        probe_shadercross_path(root)
        EuclidBuildConfiguration.resolve_msvc_tool_path(
            "VC/Tools/MSVC/**/bin/Hostx64/x64/dumpbin.exe",
            "Could not locate MSVC dumpbin.exe. Install the C++ Build Tools workload.")
    else
        require_tool("glslc", "Install shaderc/glslc.")
        require_tool("spirv-val", "Install SPIR-V Tools.")
        require_tool("pkg-config", "Install pkg-config and SDL3 development metadata.")
    end
    if Sys.islinux()
        require_tool("readelf", "Install binutils.")
        require_tool("ldd", "Install the system ELF loader tools.")
    elseif Sys.isapple()
        require_tool("otool", "Install the Xcode command-line tools.")
        probe_shadercross_path(root)
    end
end

"""Record host, source-control, binding, and system SDL provider identities."""
function collect_environment!(result, diagnostics::IO, root::String)
    odin_root = command_value!(diagnostics, "odin-root", Cmd(["odin", "root"]); cwd=root)
    odin_version = command_value!(
        diagnostics, "odin-version", Cmd(["odin", "version"]); cwd=root)
    bindings = binding_paths(odin_root)
    provider = EuclidBuildConfiguration.sdl3_provider_identity()
    release_command = Sys.iswindows() ? Cmd(["cmd", "/c", "ver"]) :
        Cmd(["uname", "-r"])
    result["host"] = Dict{String,Any}(
        "kernel" => string(Sys.KERNEL), "architecture" => string(Sys.ARCH),
        "kernel_release" => command_value!(diagnostics, "kernel-release",
            release_command; cwd=root))
    result["git"] = git_metadata!(diagnostics, root)
    result["odin"] = Dict{String,Any}("version" => odin_version, "root" => odin_root)
    result["bindings"] = [Dict{String,Any}(
        "path" => path, "sha256" => file_sha256(path)) for path in bindings]
    result["sdl_provider"] = Dict{String,Any}(
        "kind" => string(provider.kind), "version" => provider.version,
        "library_path" => provider.library_path,
        "sha256" => file_sha256(provider.library_path))
    return provider.library_path
end

"""Compile and validate both checked-in shaders, then record their identities."""
function compile_shaders!(result, diagnostics::IO, root::String, paths::ProbeArtifacts)
    shadercross = Sys.iswindows() ? probe_shadercross_path(root) : ""
    if Sys.iswindows()
        for (stage, source, spirv) in (("vertex", paths.vertex_source,
            paths.vertex_spv), ("fragment", paths.fragment_source,
            paths.fragment_spv))
            checked_step!(diagnostics, "$stage-compile", probe_shadercross_command(
                shadercross, source, spirv, "HLSL", "SPIRV", stage); cwd=root)
        end
    else
        checked_step!(diagnostics, "vertex-compile",
            probe_shader_command(paths.vertex_source, paths.vertex_spv, "vertex"); cwd=root)
        checked_step!(diagnostics, "fragment-compile",
            probe_shader_command(paths.fragment_source, paths.fragment_spv, "fragment"); cwd=root)
        checked_step!(diagnostics, "vertex-validate", Cmd(["spirv-val", paths.vertex_spv]);
            cwd=root)
        checked_step!(diagnostics, "fragment-validate",
            Cmd(["spirv-val", paths.fragment_spv]); cwd=root)
    end
    compiler = Sys.iswindows() ? shadercross : command_value!(diagnostics,
        "glslc-version", Cmd(["glslc", "--version"]); cwd=root)
    result["shaders"] = Dict{String,Any}(
        "compiler" => first(split(compiler, '\n')),
        "vertex_source_sha256" => file_sha256(paths.vertex_source),
        "fragment_source_sha256" => file_sha256(paths.fragment_source),
        "vertex_spirv_sha256" => file_sha256(paths.vertex_spv),
        "fragment_spirv_sha256" => file_sha256(paths.fragment_spv))
    if Sys.iswindows()
        checked_step!(diagnostics, "vertex-dxil", probe_shadercross_command(
            shadercross, paths.vertex_spv, paths.vertex_runtime,
            "SPIRV", "DXIL", "vertex"); cwd=root)
        checked_step!(diagnostics, "fragment-dxil", probe_shadercross_command(
            shadercross, paths.fragment_spv, paths.fragment_runtime,
            "SPIRV", "DXIL", "fragment"); cwd=root)
        result["shaders"]["runtime_format"] = "DXIL"
        result["shaders"]["vertex_runtime_sha256"] =
            file_sha256(paths.vertex_runtime)
        result["shaders"]["fragment_runtime_sha256"] =
            file_sha256(paths.fragment_runtime)
    elseif Sys.isapple()
        shadercross = probe_shadercross_path(root)
        checked_step!(diagnostics, "vertex-msl",
            probe_msl_command(shadercross, paths.vertex_spv,
                paths.vertex_runtime, "vertex"); cwd=root)
        checked_step!(diagnostics, "fragment-msl",
            probe_msl_command(shadercross, paths.fragment_spv,
                paths.fragment_runtime, "fragment"); cwd=root)
        result["shaders"]["runtime_format"] = "MSL"
        result["shaders"]["vertex_runtime_sha256"] =
            file_sha256(paths.vertex_runtime)
        result["shaders"]["fragment_runtime_sha256"] =
            file_sha256(paths.fragment_runtime)
    else
        result["shaders"]["runtime_format"] = "SPIR-V"
    end
end

"""Strict-build the standalone Odin probe and record its binary identity."""
function build_probe!(result, diagnostics::IO, root::String, paths::ProbeArtifacts)
    linker_flags = Sys.iswindows() ?
        EuclidBuildConfiguration.sdl3_linker_flags() : ""
    checked_step!(diagnostics, "probe-build",
        probe_build_command(paths.source_dir, paths.binary; linker_flags); cwd=root)
    result["executable"] = Dict{String,Any}(
        "path" => paths.binary, "sha256" => file_sha256(paths.binary))
end

"""Normalize line-oriented runtime facts into the result schema."""
function runtime_evidence(facts::Dict{String,String})
    return Dict{String,Any}(
        "binding_version" => get(facts, "binding_version", ""),
        "runtime_version" => dotted_runtime_version(get(facts, "runtime_version", "")),
        "video_driver" => get(facts, "video_driver", ""),
        "gpu_drivers" => split(get(facts, "gpu_drivers", ""), ','; keepempty=false),
        "selected_gpu_driver" => get(facts, "selected_gpu_driver", ""),
        "shader_formats" => get(facts, "shader_formats", ""),
        "gpu_device_name" => get(facts, "gpu_device_name", ""),
        "gpu_driver_name" => get(facts, "gpu_driver_name", ""),
        "gpu_driver_version" => get(facts, "gpu_driver_version", ""),
        "swapchain_composition" => get(facts, "swapchain_composition", ""),
        "present_mode" => get(facts, "present_mode", ""),
        "swapchain_format" => get(facts, "swapchain_format", ""),
        "initial_size" => get(facts, "initial_size", ""),
        "initial_pixels" => get(facts, "initial_pixels", ""),
        "final_size" => get(facts, "final_size", ""),
        "final_pixels" => get(facts, "final_pixels", ""),
        "display_scale" => get(facts, "display_scale", ""),
        "resize_status" => get(facts, "resize_status", "indeterminate"),
        "frames_presented" => parse(Int, get(facts, "frames_presented", "0")),
        "unavailable_frames" => parse(Int, get(facts, "unavailable_frames", "0")),
        "cleanup_complete" => get(facts, "cleanup_complete", "false") == "true")
end

"""Run the bounded native probe and retain runtime facts even when it fails."""
function run_runtime!(result, diagnostics::IO, root::String, paths::ProbeArtifacts)
    command = Cmd([paths.binary, paths.vertex_runtime, paths.fragment_runtime])
    environment = EuclidBuildConfiguration.native_runtime_environment()
    command = environment === nothing ? command : addenv(command, environment)
    println(diagnostics, "[probe-runtime] ", command)
    runtime = capture_command_timeout(command, 15; cwd=root)
    write(diagnostics, runtime.stdout)
    write(diagnostics, runtime.stderr)
    facts = parse_probe_output(runtime.stdout * runtime.stderr)
    result["runtime"] = runtime_evidence(facts)
    runtime.exit_code == 0 || error(
        "probe-runtime failed with exit code $(runtime.exit_code)")
    get(facts, "result", "") == "passed" || error(
        "Probe did not report a passing result.")
    result["runtime"]["cleanup_complete"] || error(
        "Probe did not report complete cleanup.")
end

"""Record the executable dependency closure and loaded SDL SONAME."""
function inspect_binary!(
    result, diagnostics::IO, root::String, paths::ProbeArtifacts, sdl_library::String)
    dumpbin = Sys.iswindows() ? EuclidBuildConfiguration.resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/dumpbin.exe",
        "Could not locate MSVC dumpbin.exe.") : ""
    dependency_command = Sys.iswindows() ? Cmd([dumpbin, "/dependents", paths.binary]) :
        Sys.isapple() ? Cmd(["otool", "-L", paths.binary]) : Cmd(["ldd", paths.binary])
    identity_command = Sys.iswindows() ? Cmd([dumpbin, "/headers", sdl_library]) :
        Sys.isapple() ? Cmd(["otool", "-D", sdl_library]) : Cmd(["readelf", "-d", sdl_library])
    dependency_result = checked_step!(diagnostics, "dynamic-dependencies",
        dependency_command; cwd=root)
    identity_result = checked_step!(diagnostics, "runtime-identity",
        identity_command; cwd=root)
    result["dynamic_dependencies"] = split(chomp(dependency_result.stdout), '\n';
        keepempty=false)
    if Sys.iswindows()
        occursin(r"(?i)SDL3\.dll", dependency_result.stdout) || error(
            "The probe executable does not depend on SDL3.dll.")
        result["sdl_provider"]["loaded_path"] = sdl_library
        result["sdl_provider"]["pe_headers"] =
            split(chomp(identity_result.stdout), '\n'; keepempty=false)
    elseif Sys.isapple()
        result["sdl_provider"]["loaded_path"] =
            loaded_sdl_path_darwin(dependency_result.stdout)
        lines = split(chomp(identity_result.stdout), '\n'; keepempty=false)
        result["sdl_provider"]["install_name"] =
            length(lines) < 2 ? "" : strip(lines[2])
    else
        result["sdl_provider"]["loaded_path"] =
            loaded_sdl_path(dependency_result.stdout)
        soname = match(
            r"Library soname: \[([^]]+)\]", identity_result.stdout)
        result["sdl_provider"]["soname"] =
            soname === nothing ? "" : soname.captures[1]
    end
end

"""Execute each probe stage and update the current failure-stage marker."""
function execute_probe!(result, diagnostics::IO, root::String, paths::ProbeArtifacts)
    result["failed_stage"] = "tool_discovery"
    require_probe_tools(root)
    result["failed_stage"] = "provider_discovery"
    sdl_library = collect_environment!(result, diagnostics, root)
    result["failed_stage"] = "shader_compile"
    compile_shaders!(result, diagnostics, root, paths)
    result["failed_stage"] = "probe_build"
    build_probe!(result, diagnostics, root, paths)
    result["failed_stage"] = "runtime"
    run_runtime!(result, diagnostics, root, paths)
    result["failed_stage"] = "binary_inspection"
    inspect_binary!(result, diagnostics, root, paths, sdl_library)
    result["result"] = "passed"
    result["failed_stage"] = nothing
    result["reason"] = "SDL3 GPU capability probe passed"
end

"""Build and run the explicit SDL3 GPU capability probe, preserving evidence."""
function run_probe(root::String)
    paths = prepare_artifacts(root)
    result = initial_result()
    status = 1
    open(paths.diagnostics_path, "w") do diagnostics
        try
            execute_probe!(result, diagnostics, root, paths)
            status = 0
        catch error_object
            result["reason"] = sprint(showerror, error_object)
            println(diagnostics, "[failure] ", result["reason"])
        finally
            write_result(paths.result_path, result)
        end
    end
    println("Wrote $(relpath(paths.result_path, root))")
    println("Wrote $(relpath(paths.diagnostics_path, root))")
    return status
end

end
