const LINUX_SHADERCROSS_DIR = joinpath(
    REPOSITORY_ROOT, "libs", "sdl_shadercross", "bin", "linux64")
const LINUX_SHADERCROSS_ARTIFACTS = Set([
    "shadercross", "spirv-val", "spirv-dis", "libdxcompiler.so", "libdxil.so"])
const LINUX_SHADERCROSS_COMPONENTS = union(
    WINDOWS_SHADERCROSS_COMPONENTS, Set(["SDL3"]))

"""Validate the Linux provider's supported platform and baseline runtime."""
function validate_linux_shadercross_platform(
    manifest::AbstractDict, architecture::Symbol)
    get(manifest, "schema_version", 0) == 1 || error(
        "Unsupported Linux SDL_shadercross manifest schema.")
    get(manifest, "platform", "") == "linux" || error(
        "Linux SDL_shadercross manifest has the wrong platform.")
    architecture == :x86_64 && get(manifest, "architecture", "") == "x86_64" ||
        error("Linux SDL_shadercross payload supports only x86_64.")
    get(manifest, "provider", "") == "euclid-built" || error(
        "Linux SDL_shadercross manifest has an unknown provider.")
    get(manifest, "glibc_minimum", "") == "2.35" || error(
        "Linux SDL_shadercross manifest must target glibc 2.35.")
    get(manifest, "glibcxx_minimum", "") == "3.4.29" || error(
        "Linux SDL_shadercross manifest must target GLIBCXX_3.4.29.")
end

"""Validate origin-relative lookup and the Linux provider's source identity."""
function validate_linux_shadercross_header(manifest::AbstractDict,
    architecture::Symbol, expected_source_commit::Union{Nothing,String})
    validate_linux_shadercross_platform(manifest, architecture)
    get(manifest, "runtime_search_path", "") == "\$ORIGIN" || error(
        "Linux SDL_shadercross payload must use origin-relative libraries.")
    source_commit = String(get(manifest, "source_commit", ""))
    occursin(r"^[0-9a-f]{40}$", source_commit) || error(
        "Linux SDL_shadercross manifest has an invalid source commit.")
    expected_source_commit === nothing || source_commit == expected_source_commit ||
        error("Linux SDL_shadercross payload does not match the repository gitlink.")
end

"""Validate hashes, licenses, and complete inventory of the Linux build tools."""
function linux_shadercross_manifest(root::AbstractString=LINUX_SHADERCROSS_DIR;
    architecture::Symbol=Sys.ARCH,
    expected_source_commit::Union{Nothing,String}=nothing,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)),
    file_size::Function=filesize)
    manifest_path = joinpath(root, "manifest.toml")
    isfile(manifest_path) || error(
        "Missing Linux SDL_shadercross binary manifest at $manifest_path.")
    manifest = parse_file(manifest_path)
    validate_linux_shadercross_header(manifest, architecture, expected_source_commit)
    components = get(manifest, "component", Any[])
    names = Set(String(get(component, "name", "")) for component in components)
    names == LINUX_SHADERCROSS_COMPONENTS && length(names) == length(components) ||
        error("Linux SDL_shadercross manifest has an invalid component inventory.")
    source_names = validate_shadercross_source_dependencies!(manifest, root, hash_file)
    artifacts = Set{String}()
    for component in components
        validate_shadercross_component!(component, union(names, source_names),
            artifacts, root, hash_file, file_size)
    end
    artifacts == LINUX_SHADERCROSS_ARTIFACTS || error(
        "Linux SDL_shadercross manifest has an incomplete artifact inventory.")
    return manifest
end

"""Resolve a verified Linux tool without consulting source builds or PATH."""
function linux_shadercross_artifact(repository_root::String, filename::String)
    filename in LINUX_SHADERCROSS_ARTIFACTS || error(
        "Unknown Linux SDL_shadercross artifact: $filename")
    root = joinpath(repository_root, "libs", "sdl_shadercross", "bin", "linux64")
    linux_shadercross_manifest(root;
        expected_source_commit=repository_shadercross_commit(repository_root))
    return realpath(joinpath(root, filename))
end
