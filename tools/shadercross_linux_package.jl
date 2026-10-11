using SHA
using TOML

include(joinpath(@__DIR__, "shadercross_package.jl"))

"""Publish the Linux payload using the matching Windows source/license inventory."""
function package_linux_shadercross()
    repository = normpath(joinpath(@__DIR__, ".."))
    work = joinpath(repository, ".build", "shadercross-linux-provider")
    payload = joinpath(work, "payload")
    windows = joinpath(repository, "libs", "sdl_shadercross", "bin", "win64")
    destination = joinpath(repository, "libs", "sdl_shadercross", "bin", "linux64")
    manifest = TOML.parsefile(joinpath(windows, "manifest.toml"))
    validate_packaged_shadercross_pin(manifest, repository)
    inventory = Dict(
        "SDL_shadercross" => ["shadercross" => "cli"],
        "SPIRV-Tools" => ["spirv-val" => "validator", "spirv-dis" => "disassembler"],
        "DirectXShaderCompiler" => [
            "libdxcompiler.so" => "runtime", "libdxil.so" => "runtime"])
    mkpath(joinpath(destination, "licenses"))
    for component in manifest["component"]
        component["artifact"] = [
            package_shadercross_artifact(payload, destination, file, role)
            for (file, role) in get(inventory, component["name"], Pair{String,String}[])]
    end
    for filename in readdir(joinpath(windows, "licenses"))
        cp(joinpath(windows, "licenses", filename),
            joinpath(destination, "licenses", filename); force=true)
    end
    sdl = only(filter(library -> library["name"] == "SDL3",
        TOML.parsefile(joinpath(repository, "libs", "sdl", "bin", "win64",
            "manifest.toml"))["library"]))
    sdl["artifact"] = Any[]
    sdl["source_archive_sha256"] =
        "7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68"
    cp(joinpath(work, "SDL3-3.4.16", "LICENSE.txt"),
        joinpath(destination, sdl["license_file"]); force=true)
    push!(manifest["component"], sdl)
    write_linux_shadercross_manifest(manifest, work, destination)
end

"""Record baseline build provenance and persist the refreshed Linux manifest."""
function write_linux_shadercross_manifest(
    manifest::AbstractDict, work::String, destination::String)
    for field in ("sdl_manifest", "msvc_version", "cmake_options")
        delete!(manifest, field)
    end
    manifest["platform"] = "linux"
    manifest["toolchain"] = "gcc-11"
    manifest["build_distribution"] = "Ubuntu 22.04"
    manifest["glibc_minimum"] = "2.35"
    manifest["glibcxx_minimum"] = "3.4.29"
    manifest["runtime_search_path"] = "\$ORIGIN"
    manifest["static_components"] = ["SDL3", "SDL_shadercross", "SPIRV-Cross"]
    manifest["build_recipe"] = "../../../../tools/shadercross_linux_build/build.sh"
    manifest["rootfs_sha256"] =
        "242cd8898b33ea806ef5f13b1076ed7c76f9f989d18384452f7166692438ff1a"
    cp(joinpath(work, "build-packages.txt"),
        joinpath(destination, "build-packages.txt"); force=true)
    manifest["build_packages_sha256"] =
        bytes2hex(open(sha256, joinpath(destination, "build-packages.txt")))
    open(joinpath(destination, "manifest.toml"), "w") do io
        TOML.print(io, manifest; sorted=true)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    package_linux_shadercross()
end
