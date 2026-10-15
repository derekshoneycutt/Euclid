const MACOS_SHADERCROSS_DIR = joinpath(
    REPOSITORY_ROOT, "libs", "sdl_shadercross", "bin", "macos_arm64")
const MACOS_SHADERCROSS_ARTIFACTS = Set([
    "shadercross", "spirv-val", "spirv-dis", "libdxcompiler.dylib", "libdxil.dylib"])

"""Validate the Apple Silicon provider's platform and loader-relative closure."""
function validate_macos_shadercross_header(manifest::AbstractDict,
    architecture::Symbol, expected_source_commit::Union{Nothing,String})
    get(manifest, "schema_version", 0) == 1 || error(
        "Unsupported macOS SDL_shadercross manifest schema.")
    get(manifest, "platform", "") == "macos" || error(
        "macOS SDL_shadercross manifest has the wrong platform.")
    architecture == :aarch64 && get(manifest, "architecture", "") == "aarch64" ||
        error("macOS SDL_shadercross payload supports only Apple Silicon (aarch64).")
    get(manifest, "provider", "") == "euclid-built" || error(
        "macOS SDL_shadercross manifest has an unknown provider.")
    get(manifest, "toolchain", "") == "apple-clang" || error(
        "macOS SDL_shadercross manifest must use Apple Clang.")
    get(manifest, "macos_minimum", "") == "11.0" || error(
        "macOS SDL_shadercross manifest must target macOS 11.0.")
    get(manifest, "runtime_search_path", "") == "@loader_path" || error(
        "macOS SDL_shadercross payload must use loader-relative libraries.")
    validate_macos_shadercross_source_pin(manifest, expected_source_commit)
end

"""Require a well-formed source commit and match the repository pin when supplied."""
function validate_macos_shadercross_source_pin(
    manifest::AbstractDict, expected_source_commit::Union{Nothing,String})
    source_commit = String(get(manifest, "source_commit", ""))
    occursin(r"^[0-9a-f]{40}$", source_commit) || error(
        "macOS SDL_shadercross manifest has an invalid source commit.")
    expected_source_commit === nothing || source_commit == expected_source_commit ||
        error("macOS SDL_shadercross payload does not match the repository source pin.")
end

"""Validate hashes, licenses, and inventory of the Apple Silicon build tools."""
function macos_shadercross_manifest(root::AbstractString=MACOS_SHADERCROSS_DIR;
    architecture::Symbol=Sys.ARCH,
    expected_source_commit::Union{Nothing,String}=nothing,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)),
    file_size::Function=filesize)
    manifest_path = joinpath(root, "manifest.toml")
    isfile(manifest_path) || error(
        "Missing macOS SDL_shadercross binary manifest at $manifest_path.")
    manifest = parse_file(manifest_path)
    validate_macos_shadercross_header(manifest, architecture, expected_source_commit)
    validate_shadercross_inventory(manifest, root, STATIC_SHADERCROSS_COMPONENTS,
        MACOS_SHADERCROSS_ARTIFACTS, hash_file, file_size)
    return manifest
end

"""Resolve a verified macOS tool without consulting source builds or PATH."""
function macos_shadercross_artifact(repository_root::String, filename::String)
    filename in MACOS_SHADERCROSS_ARTIFACTS || error(
        "Unknown macOS SDL_shadercross artifact: $filename")
    root = joinpath(repository_root, "libs", "sdl_shadercross", "bin", "macos_arm64")
    macos_shadercross_manifest(root;
        expected_source_commit=repository_shadercross_commit(repository_root))
    return realpath(joinpath(root, filename))
end
