using SHA
using TOML

include(joinpath(@__DIR__, "shadercross_package.jl"))

"""Publish Apple Silicon tools with the matching source and license inventory."""
function package_macos_shadercross()
    repository = normpath(joinpath(@__DIR__, ".."))
    work = joinpath(repository, ".build", "shadercross-macos-provider")
    windows = joinpath(repository, "libs", "sdl_shadercross", "bin", "win64")
    destination = joinpath(repository, "libs", "sdl_shadercross", "bin", "macos_arm64")
    manifest = TOML.parsefile(joinpath(windows, "manifest.toml"))
    validate_packaged_shadercross_pin(manifest, repository)
    inventory = Dict(
        "SDL_shadercross" => ["shadercross" => "cli"],
        "SPIRV-Tools" => ["spirv-val" => "validator", "spirv-dis" => "disassembler"],
        "DirectXShaderCompiler" => [
            "libdxcompiler.dylib" => "runtime", "libdxil.dylib" => "runtime"])
    mkpath(joinpath(destination, "licenses"))
    for component in manifest["component"]
        component["artifact"] = [
            package_shadercross_artifact(
                joinpath(work, "payload"), destination, file, role)
            for (file, role) in get(inventory, component["name"], Pair{String,String}[])]
    end
    for filename in readdir(joinpath(windows, "licenses"))
        cp(joinpath(windows, "licenses", filename),
            joinpath(destination, "licenses", filename); force=true)
    end
    sdl = only(filter(component -> component["name"] == "SDL3",
        TOML.parsefile(joinpath(repository, "libs", "sdl_shadercross", "bin",
            "linux64", "manifest.toml"))["component"]))
    cp(joinpath(work, "SDL3-3.4.16", "LICENSE.txt"),
        joinpath(destination, sdl["license_file"]); force=true)
    push!(manifest["component"], sdl)
    write_macos_shadercross_manifest!(manifest, destination)
end

"""Record the native toolchain, runtime baseline, and maintenance recipe."""
function write_macos_shadercross_manifest!(manifest::AbstractDict, destination::String)
    for field in ("sdl_manifest", "msvc_version", "cmake_options")
        delete!(manifest, field)
    end
    manifest["platform"] = "macos"
    manifest["architecture"] = "aarch64"
    manifest["toolchain"] = "apple-clang"
    manifest["compiler_version"] = strip(read(`cc --version`, String))
    manifest["sdk_version"] = strip(read(`xcrun --show-sdk-version`, String))
    manifest["cmake_version"] = strip(read(`cmake --version`, String))
    manifest["macos_minimum"] = "11.0"
    manifest["runtime_search_path"] = "@loader_path"
    manifest["static_components"] = ["SDL3", "SDL_shadercross", "SPIRV-Cross"]
    manifest["code_signature"] = "ad-hoc"
    manifest["build_recipe"] = "../../../../tools/shadercross_macos_provider.sh"
    open(joinpath(destination, "manifest.toml"), "w") do io
        TOML.print(io, manifest; sorted=true)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    package_macos_shadercross()
end
