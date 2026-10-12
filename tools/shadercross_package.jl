using SHA
using TOML

"""Require packaging provenance to match the independent repository source pin."""
function validate_packaged_shadercross_pin(manifest::AbstractDict, repository::String)
    pin = TOML.parsefile(joinpath(
        repository, "libs", "sdl_shadercross", "source-pin.toml"))
    manifest["source_commit"] == pin["source_commit"] || error(
        "SDL_shadercross packaging inventory does not match the repository source pin.")
    return nothing
end

"""Copy a produced shader tool and return its hashed manifest record."""
function package_shadercross_artifact(
    payload::String, destination::String, filename::String, role::String)
    cp(joinpath(payload, filename), joinpath(destination, filename); force=true)
    path = joinpath(destination, filename)
    return Dict("file" => filename, "role" => role, "bytes" => filesize(path),
        "sha256" => bytes2hex(open(sha256, path)))
end
