Base.@kwdef struct WikiSection
    id::String
    display_name::String
    description::String
    source_policy::String
    owner::String
    managed_output_paths::Vector{String}
    navigation_order::Int
    landing_page::String
    stale_boundary::String
    publish::Bool
end

Base.@kwdef struct WikiGuide
    title::String
    path::String
    summary::String
    navigation_order::Int
    owner::String = "guide_authors"
end

Base.@kwdef struct WikiGuideRelation
    package_id::String
    guide_paths::Vector{String}
    symbol_prefixes::Vector{String}
end

Base.@kwdef struct WikiManifest
    wiki_root::String
    shared_output_paths::Vector{String}
    sections::Vector{WikiSection}
    guides::Vector{WikiGuide}
    guide_relations::Vector{WikiGuideRelation}
    bridge_exceptions::Vector{String} = String[]
    shared_output_owner::String = "wiki_compositor"
end

Base.@kwdef struct WikiOutput
    owner::String
    path::String
    content::String
end

const CODE_WIKI_OWNER = "code_wiki"
const WIKI_COMPOSITOR_OWNER = "wiki_compositor"

"""Construct one typed Wiki section from parsed manifest data."""
function parsed_wiki_section(data::Dict{String,Any})
    return WikiSection(
        id=data["id"], display_name=data["display_name"],
        description=data["description"], source_policy=data["source_policy"],
        owner=data["owner"], managed_output_paths=String.(data["managed_output_paths"]),
        navigation_order=data["navigation_order"], landing_page=data["landing_page"],
        stale_boundary=data["stale_boundary"], publish=data["publish"])
end

"""Construct one typed authored-guide record from parsed manifest data."""
function parsed_wiki_guide(data::Dict{String,Any})
    return WikiGuide(
        title=data["title"], path=data["path"], summary=data["summary"],
        navigation_order=data["navigation_order"],
        owner=get(data, "owner", "guide_authors"))
end

"""Construct one typed Code-to-Guide relationship from manifest data."""
function parsed_guide_relation(data::Dict{String,Any})
    return WikiGuideRelation(
        package_id=data["package_id"], guide_paths=String.(data["guide_paths"]),
        symbol_prefixes=String.(data["symbol_prefixes"]))
end

"""Load and validate the reviewed Wiki composition manifest."""
function load_wiki_manifest(path::AbstractString)
    data = TOML.parsefile(path)
    manifest = WikiManifest(
        wiki_root=data["wiki_root"],
        shared_output_paths=String.(data["shared_output_paths"]),
        sections=parsed_wiki_section.(data["sections"]),
        guides=parsed_wiki_guide.(data["guides"]),
        guide_relations=parsed_guide_relation.(data["guide_relations"]),
        bridge_exceptions=String.(get(data, "bridge_exceptions", String[])),
        shared_output_owner=get(data, "shared_output_owner", "wiki_compositor"))
    return validate_wiki_manifest(manifest)
end

"""Return whether a manifest path is normalized and repository-relative."""
function wiki_path_is_safe(path::String)
    normalized = normalize_repo_path(path)
    return !isempty(path) && !isabspath(path) && normalized == path &&
        normalized != ".." && !startswith(normalized, "../")
end

"""Return whether two managed paths overlap by equality or ancestry."""
function wiki_paths_overlap(first_path::String, second_path::String)
    return first_path == second_path || startswith(first_path, second_path * "/") ||
        startswith(second_path, first_path * "/")
end

"""Return whether one output path is contained by a manifest path claim."""
function wiki_path_contains(claim::String, path::String)
    claim == path && return true
    endswith(lowercase(claim), ".md") && return false
    return startswith(path, claim * "/")
end

"""Fail when any managed output path has ambiguous ownership."""
function validate_managed_path_ownership(
    sections::Vector{WikiSection}, shared_paths::Vector{String})

    claims = [(path, section.id)
        for section in sections for path in section.managed_output_paths]
    append!(claims, [(path, "shared") for path in shared_paths])
    for index in eachindex(claims), other_index in index + 1:length(claims)
        path, owner = claims[index]
        other_path, other_owner = claims[other_index]
        wiki_paths_overlap(path, other_path) && error(
            "Managed Wiki paths overlap: $owner:$path and $other_owner:$other_path")
    end
end

"""Validate manifest identities, paths, ownership, and Guide references."""
function validate_wiki_manifest(manifest::WikiManifest)
    section_ids = [section.id for section in manifest.sections]
    length(unique(section_ids)) == length(section_ids) || error("Duplicate Wiki section ID.")
    all(wiki_path_is_safe, manifest.shared_output_paths) || error("Unsafe shared Wiki path.")
    validate_section_paths(manifest.sections)
    validate_managed_path_ownership(manifest.sections, manifest.shared_output_paths)
    validate_guide_paths(manifest)
    return manifest
end

"""Validate section output paths, landing pages, and owners."""
function validate_section_paths(sections::Vector{WikiSection})
    all(section -> all(wiki_path_is_safe, section.managed_output_paths),
        sections) || error("Unsafe managed Wiki path.")
    all(section -> wiki_path_is_safe(section.landing_page) &&
        wiki_path_is_safe(section.stale_boundary), sections) ||
        error("Unsafe Wiki section path.")
    all(section -> any(path -> wiki_path_contains(path, section.landing_page),
        section.managed_output_paths), sections) ||
        error("Wiki landing page is outside its section ownership.")
    all(section -> !isempty(strip(section.owner)), sections) ||
        error("Wiki section owner must not be empty.")
end

"""Validate guide paths, owners, relations, and bridge exceptions."""
function validate_guide_paths(manifest::WikiManifest)
    guide_paths = [guide.path for guide in manifest.guides]
    length(unique(guide_paths)) == length(guide_paths) || error("Duplicate Wiki Guide path.")
    all(wiki_path_is_safe, guide_paths) || error("Unsafe Wiki Guide path.")
    all(guide -> !isempty(strip(guide.owner)), manifest.guides) ||
        error("Wiki Guide owner must not be empty.")
    !isempty(strip(manifest.shared_output_owner)) ||
        error("Shared Wiki output owner must not be empty.")
    known_guides = Set(guide_paths)
    all(relation -> all(path -> guide_reference_path(path) in known_guides,
        relation.guide_paths),
        manifest.guide_relations) || error("Code-to-Guide relation references an unknown Guide.")
    length(unique(manifest.bridge_exceptions)) == length(manifest.bridge_exceptions) ||
        error("Duplicate bridge exception.")
end


"""Return the manifest owner authorized to emit one managed Wiki path."""
function wiki_output_owner(manifest::WikiManifest, path::String)
    path in manifest.shared_output_paths && return manifest.shared_output_owner
    for guide in manifest.guides
        guide.path == path && return guide.owner
    end
    for section in manifest.sections
        any(claim -> wiki_path_contains(claim, path), section.managed_output_paths) ||
            continue
        return section.owner
    end
    error("Unowned Wiki output path: $path")
end

"""Reject unsafe, duplicate, unowned, or cross-owner output records."""
function validate_wiki_outputs(manifest::WikiManifest, outputs::Vector{WikiOutput})
    paths = [output.path for output in outputs]
    length(unique(paths)) == length(paths) || error("Duplicate Wiki output path.")
    all(output -> wiki_path_is_safe(output.path), outputs) ||
        error("Unsafe Wiki output path.")
    for output in outputs
        expected_owner = wiki_output_owner(manifest, output.path)
        output.owner == expected_owner || error(
            "Wiki output ownership violation: $(output.owner):$(output.path) " *
            "is owned by $expected_owner")
    end
    return outputs
end

"""Create a stable ASCII slug from a documentation identity."""
function wiki_slug(value::AbstractString)
    ascii = replace(String(value), r"[^A-Za-z0-9]+" => "-")
    return strip(ascii, '-')
end

"""Return the explicit stable anchor for one normalized symbol."""
wiki_symbol_anchor(symbol::DocumentationSymbol) = "symbol-" * wiki_slug(symbol.stable_id)

"""Return the authored Guide path without an optional section fragment."""
guide_reference_path(reference::String) = first(split(reference, '#'; limit=2))

"""Return a readable label for one authored Guide reference."""
function guide_reference_title(reference::String)
    path = guide_reference_path(reference)
    return splitext(basename(path))[1]
end

"""Return one package page's language namespace."""
function package_language_directory(package::DocumentationPackage)
    package.language == :odin && return "Odin"
    package.language == :julia && return "Julia"
    error("Unsupported documentation language: $(package.language)")
end

"""Assign deterministic package pages and disambiguate filename collisions."""
function assign_package_page_paths(packages::Vector{DocumentationPackage})
    paths = Dict{String,String}()
    ordered = sort(packages; by=package -> package.stable_id)
    base_paths = [joinpath("Code", package_language_directory(package),
        wiki_slug(package.display_name) * ".md") for package in ordered]
    for (package, base_path) in zip(ordered, base_paths)
        duplicates = count(==(base_path), base_paths)
        suffix = duplicates == 1 ? "" : "-" * wiki_slug(package.stable_id)
        paths[package.stable_id] = duplicates == 1 ? base_path :
            replace(base_path, ".md" => suffix * ".md")
    end
    length(paths) == length(packages) || error("Duplicate documentation package ID.")
    return paths
end

"""Apply configured authored Guide links to packages and matching symbols."""
function apply_guide_relations!(
    packages::Vector{DocumentationPackage}, manifest::WikiManifest)

    package_by_id = Dict(package.stable_id => package for package in packages)
    for relation in manifest.guide_relations
        package = get(package_by_id, relation.package_id, nothing)
        package === nothing &&
            error("Guide relation package not extracted: $(relation.package_id)")
        append!(package.authored_document_refs, relation.guide_paths)
        for symbol in package.symbols
            any(prefix -> startswith(symbol.name, prefix), relation.symbol_prefixes) ||
                continue
            append!(symbol.authored_document_refs, relation.guide_paths)
        end
    end
    for package in packages
        package.authored_document_refs = sort!(unique!(package.authored_document_refs))
        for symbol in package.symbols
            symbol.authored_document_refs = sort!(unique!(symbol.authored_document_refs))
        end
    end
    return packages
end

"""Render package-level links to canonical authored Guides."""
function render_package_guide_links!(io::IO, references::Vector{String})
    isempty(references) && return
    write(io, "## Related Guides\n\n")
    for reference in sort(references)
        write(io, "- [", guide_reference_title(reference), "](../../",
            reference, ")\n")
    end
    write(io, "\n")
end

"""Render symbol-level links to canonical authored Guides."""
function render_authored_document_links!(io::IO, references::Vector{String})
    isempty(references) && return
    links = map(sort(references)) do reference
        title = guide_reference_title(reference)
        "[$title](../../$reference)"
    end
    write(io, "**Related guides:** ", join(links, ", "), "\n\n")
end

"""Return the standard banner for generated Wiki pages."""
generated_wiki_banner() =
    "<!-- Generated from source doc comments. Do not edit this file directly. -->\n\n"

"""Render the shared Wiki landing page from section metadata."""
function render_wiki_home(manifest::WikiManifest)
    io = IOBuffer()
    write(io, generated_wiki_banner(), "# Euclid Wiki\n\n")
    write(io, "Documentation for the Euclid application, its code, and authored guides.\n")
    for section in sort(manifest.sections; by=item -> item.navigation_order)
        write(io, "\n## [", section.display_name, "](", section.landing_page, ")\n\n",
            section.description, "\n")
    end
    return String(take!(io))
end

"""Render compact shared navigation without listing every symbol."""
function render_wiki_sidebar(manifest::WikiManifest)
    io = IOBuffer()
    write(io, generated_wiki_banner(), "- [Home](Home.md)\n")
    for section in sort(manifest.sections; by=item -> item.navigation_order)
        write(io, "- [", section.display_name, "](", section.landing_page, ")\n")
        section.id == "code" && write(io,
            "  - [Bridge](Code/Bridge/Home.md)\n",
            "  - [Odin](Code/Odin/Home.md)\n  - [Julia](Code/Julia/Home.md)\n",
            "  - [Symbols](Code/Symbols.md)\n")
        if section.id == "guides"
            for guide in sort(manifest.guides; by=item -> item.navigation_order)
                write(io, "  - [", guide.title, "](", guide.path, ")\n")
            end
        end
    end
    return String(take!(io))
end

"""Render the generated Code section landing page."""
function render_code_home(
    packages::Vector{DocumentationPackage}, bridge_pairs::Vector{BridgePair})

    odin_count = count(package -> package.language == :odin, packages)
    julia_count = count(package -> package.language == :julia, packages)
    return generated_wiki_banner() * "# Code Reference\n\n" *
        "Generated API documentation extracted from source comments without executing modules.\n\n" *
        "- [Odin-Julia bridge](Bridge/Home.md) ($(length(bridge_pairs)))\n" *
        "- [Odin packages](Odin/Home.md) ($odin_count)\n" *
        "- [Julia modules](Julia/Home.md) ($julia_count)\n" *
        "- [All documented symbols](Symbols.md)\n"
end

"""Return the first nonempty documentation line for compact indexes."""
function first_documentation_line(markdown::String)
    lines = split(markdown, '\n')
    line_index = findfirst(value -> !isempty(strip(value)), lines)
    return line_index === nothing ? "No package summary." : strip(lines[line_index])
end

"""Render one deterministic language package index."""
function render_language_index(
    packages::Vector{DocumentationPackage}, language::Symbol,
    page_paths::Dict{String,String})

    selected = sort(filter(package -> package.language == language, packages);
        by=package -> lowercase(package.display_name))
    display_language = language == :odin ? "Odin" : "Julia"
    io = IOBuffer()
    write(io, generated_wiki_banner(), "# ", display_language, " Code\n")
    for package in selected
        relative_path = basename(page_paths[package.stable_id])
        write(io, "\n- [`", package.display_name, "`](", relative_path, ") - ",
            first_documentation_line(package.doc_markdown), "\n")
    end
    return String(take!(io))
end

"""Render the alphabetical cross-language documented-symbol index."""
function render_symbol_index(
    packages::Vector{DocumentationPackage}, page_paths::Dict{String,String})

    entries = [(symbol, package) for package in packages for symbol in package.symbols
        if !isempty(symbol.doc_markdown)]
    sort!(entries; by=entry -> (lowercase(entry[1].name), entry[1].qualified_name))
    io = IOBuffer()
    write(io, generated_wiki_banner(), "# Documented Symbols\n")
    for (symbol, package) in entries
        page = page_paths[package.stable_id]
        write(io, "\n- `", symbol.qualified_name, "` (`", symbol.declaration_kind, "`)\n",
            "  [Reference](", page[6:end], "#", wiki_symbol_anchor(symbol), ")\n")
    end
    return String(take!(io))
end

"""Render the canonical authored-Guide index without rewriting Guide prose."""
function render_guides_home(manifest::WikiManifest)
    io = IOBuffer()
    write(io, generated_wiki_banner(), "# Guides\n")
    for guide in sort(manifest.guides; by=item -> item.navigation_order)
        write(io, "\n- [", guide.title, "](", basename(guide.path), ")\n",
            "  ", guide.summary, "\n")
    end
    return String(take!(io))
end

"""Render the reserved Content section landing page."""
function render_content_home()
    return generated_wiki_banner() * "# Content\n\n" *
        "Euclid propositions and animation catalogues will be organized here.\n"
end

"""Write one generated Wiki page beneath the configured Wiki root."""
function write_wiki_page(repository_root::String, manifest::WikiManifest,
    relative_path::String, content::String)

    output_path = joinpath(repository_root, manifest.wiki_root, relative_path)
    mkpath(dirname(output_path))
    write(output_path, replace(content, "\r\n" => "\n"))
    return relative_path
end

"""Build owned package/module outputs with configured Guide relationships."""
function build_package_outputs(
    packages::Vector{DocumentationPackage}, page_paths::Dict{String,String},
    source_link_prefix::String)

    outputs = WikiOutput[]
    for package in sort(packages; by=item -> item.stable_id)
        relative_path = page_paths[package.stable_id]
        content = package.language == :odin ? render_odin_package_page(
            package; source_link_prefix=source_link_prefix) : render_julia_module_page(
            package; source_link_prefix=source_link_prefix)
        push!(outputs, WikiOutput(
            owner=CODE_WIKI_OWNER, path=relative_path, content=content))
    end
    return outputs
end

"""Build Code-owned landing, bridge, symbol, and language index outputs."""
function build_code_navigation_outputs(
    packages::Vector{DocumentationPackage}, page_paths::Dict{String,String},
    bridge_pairs::Vector{BridgePair}, source_link_prefix::String)

    pages = [
        "Code/Home.md" => render_code_home(packages, bridge_pairs),
        "Code/Bridge/Home.md" => render_bridge_page(
            bridge_pairs; source_link_prefix=source_link_prefix),
        "Code/Symbols.md" => render_symbol_index(packages, page_paths),
        "Code/Odin/Home.md" => render_language_index(packages, :odin, page_paths),
        "Code/Julia/Home.md" => render_language_index(packages, :julia, page_paths),
    ]
    return [WikiOutput(owner=CODE_WIKI_OWNER, path=path, content=content)
        for (path, content) in pages]
end

"""Build the complete Code-owned output batch without writing files."""
function build_code_wiki_outputs(
    packages::Vector{DocumentationPackage}, bridge_pairs::Vector{BridgePair};
    source_link_prefix::String="../../../../")

    page_paths = assign_package_page_paths(packages)
    outputs = build_package_outputs(packages, page_paths, source_link_prefix)
    append!(outputs, build_code_navigation_outputs(
        packages, page_paths, bridge_pairs, source_link_prefix))
    return sort!(outputs; by=output -> output.path)
end

"""Copy canonical authored Guides into the publishable artifact unchanged."""
function build_authored_guide_outputs(
    repository_root::String, manifest::WikiManifest)

    source_root = joinpath(repository_root, manifest.wiki_root)
    return [WikiOutput(owner=guide.owner, path=guide.path,
        content=read(joinpath(source_root, guide.path), String))
        for guide in manifest.guides]
end

"""Render a landing page for one section owned by the Wiki compositor."""
function render_compositor_section_home(section::WikiSection, manifest::WikiManifest)
    section.id == "content" && return render_content_home()
    section.id == "guides" && return render_guides_home(manifest)
    error("Wiki compositor has no landing-page renderer for section: $(section.id)")
end

"""Build shared navigation and compositor-owned section landing outputs."""
function build_wiki_compositor_outputs(manifest::WikiManifest)
    outputs = [
        WikiOutput(owner=WIKI_COMPOSITOR_OWNER, path="Home.md",
            content=render_wiki_home(manifest)),
        WikiOutput(owner=WIKI_COMPOSITOR_OWNER, path="_Sidebar.md",
            content=render_wiki_sidebar(manifest)),
    ]
    for section in sort(manifest.sections; by=item -> item.navigation_order)
        section.owner == WIKI_COMPOSITOR_OWNER || continue
        push!(outputs, WikiOutput(owner=WIKI_COMPOSITOR_OWNER,
            path=section.landing_page,
            content=render_compositor_section_home(section, manifest)))
    end
    return sort!(outputs; by=output -> output.path)
end

"""Validate a complete producer batch before writing any managed Wiki page."""
function write_wiki_outputs(
    repository_root::String, manifest::WikiManifest, outputs::Vector{WikiOutput})

    validate_wiki_outputs(manifest, outputs)
    return sort!([write_wiki_page(
        repository_root, manifest, output.path, output.content) for output in outputs])
end

"""Write only the outputs owned by the Code-reference producer."""
function write_code_wiki(
    repository_root::String, manifest::WikiManifest,
    packages::Vector{DocumentationPackage}, bridge_pairs::Vector{BridgePair})

    outputs = build_code_wiki_outputs(packages, bridge_pairs)
    return write_wiki_outputs(repository_root, manifest, outputs)
end

"""List generated files currently present under one scoped stale boundary."""
function files_under_wiki_boundary(wiki_root::String, boundary::String)
    absolute = joinpath(wiki_root, boundary)
    isfile(absolute) && return [boundary]
    isdir(absolute) || return String[]
    files = String[]
    for (directory, _, names) in walkdir(absolute), name in names
        endswith(name, ".md") || continue
        push!(files, normalize_repo_path(relpath(joinpath(directory, name), wiki_root)))
    end
    return files
end

"""Fail when a producer-owned stale boundary contains an unexpected page."""
function validate_managed_outputs(
    manifest::WikiManifest, expected_paths::Vector{String}, repository_root::String)

    expected = Set(expected_paths)
    wiki_root = joinpath(repository_root, manifest.wiki_root)
    boundaries = [section.stale_boundary for section in manifest.sections]
    append!(boundaries, manifest.shared_output_paths)
    append!(boundaries, [guide.path for guide in manifest.guides])
    actual = Set(path for boundary in boundaries
        for path in files_under_wiki_boundary(wiki_root, boundary))
    stale = sort!(collect(setdiff(actual, expected)))
    missing = sort!(collect(setdiff(expected, actual)))
    isempty(stale) || error("Stale managed Wiki pages: $(join(stale, ", "))")
    isempty(missing) || error("Missing managed Wiki pages: $(join(missing, ", "))")
    return true
end

"""Return local Markdown link targets from one document body."""
function local_markdown_links(markdown::String)
    links = String[]
    for matched in eachmatch(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)", markdown)
        target = matched.captures[1]
        occursin(r"^[A-Za-z][A-Za-z0-9+.-]*:", target) && continue
        push!(links, target)
    end
    return links
end

"""Return explicit and GitHub-style heading anchors from one Markdown page."""
function markdown_anchors(markdown::String)
    anchors = Set{String}()
    for matched in eachmatch(r"(?m)^<a id=\"([^\"]+)\"></a>$", markdown)
        push!(anchors, matched.captures[1])
    end
    for matched in eachmatch(r"(?m)^#{1,6}\s+(.+?)\s*$", markdown)
        heading = lowercase(replace(matched.captures[1], r"[^\p{L}\p{N} _-]" => ""))
        push!(anchors, replace(strip(heading), r"\s" => "-"))
    end
    return anchors
end

"""Validate one local Markdown link against repository files and page anchors."""
function validate_local_markdown_link(
    repository_root::String, source_path::String, target::String)

    target_parts = split(target, '#'; limit=2)
    relative_target = first(target_parts)
    anchor = length(target_parts) == 2 ? last(target_parts) : ""
    resolved = isempty(relative_target) ? source_path :
        normpath(joinpath(dirname(source_path), relative_target))
    absolute = abspath(joinpath(repository_root, resolved))
    repository_relative = normalize_repo_path(relpath(absolute, repository_root))
    repository_relative != ".." && !startswith(repository_relative, "../") ||
        error("Wiki link escapes repository: $source_path -> $target")
    ispath(absolute) || error("Broken Wiki link: $source_path -> $target")
    if !isempty(anchor) && endswith(lowercase(resolved), ".md")
        anchor in markdown_anchors(read(absolute, String)) ||
            error("Broken Wiki anchor: $source_path -> $target")
    end
end

"""Validate all repository and cross-Wiki links in the assembled Wiki."""
function validate_wiki_links(manifest::WikiManifest, repository_root::String)
    wiki_root = joinpath(repository_root, manifest.wiki_root)
    for (directory, _, names) in walkdir(wiki_root), name in names
        endswith(name, ".md") || continue
        absolute = joinpath(directory, name)
        source_path = normalize_repo_path(relpath(absolute, repository_root))
        for target in local_markdown_links(read(absolute, String))
            validate_local_markdown_link(repository_root, source_path, target)
        end
    end
    return true
end

"""Return all manifest paths published from the assembled Wiki artifact."""
function published_wiki_paths(manifest::WikiManifest)
    paths = copy(manifest.shared_output_paths)
    for section in manifest.sections
        section.publish || continue
        append!(paths, section.managed_output_paths)
    end
    append!(paths, [guide.path for guide in manifest.guides])
    return sort!(unique!(paths))
end

"""Return all Markdown files selected for publication by manifest path claims."""
function published_wiki_files(manifest::WikiManifest, artifact_root::String)
    files = String[]
    for path in published_wiki_paths(manifest)
        ispath(joinpath(artifact_root, path)) ||
            error("Wiki artifact is missing managed path: $path")
        append!(files, files_under_wiki_boundary(artifact_root, path))
    end
    return sort!(unique!(files))
end

"""Map one structured artifact path to a unique GitHub Wiki page path."""
function github_wiki_page_path(path::String)
    directory = dirname(path)
    stem = splitext(basename(path))[1]
    parts = isempty(directory) || directory == "." ? String[] : split(directory, '/')
    stem == "Home" && !isempty(parts) || push!(parts, stem)
    return join(parts, "-") * ".md"
end

"""Rewrite artifact-local Markdown links for GitHub Wiki page routing."""
function rewrite_github_wiki_links(
    markdown::String, source_path::String, page_paths::Dict{String,String})

    pattern = r"(!?\[[^\]]*\]\()([^\s)]+)((?:\s+[^)]*)?\))"
    return replace(markdown, pattern => matched_text -> begin
        matched = match(pattern, matched_text)
        matched === nothing && error("Matched Wiki link could not be parsed.")
        target = matched.captures[2]
        occursin(r"^[A-Za-z][A-Za-z0-9+.-]*:", target) && return matched.match
        parts = split(target, '#'; limit=2)
        relative_target = first(parts)
        isempty(relative_target) && return matched.match
        resolved =
            normalize_repo_path(normpath(joinpath(dirname(source_path), relative_target)))
        haskey(page_paths, resolved) || return matched.match
        fragment = length(parts) == 2 ? "#" * last(parts) : ""
        page = splitext(page_paths[resolved])[1]
        return matched.captures[1] * page * fragment * matched.captures[3]
    end)
end

"""Remove stale files from directory-backed flat publication namespaces."""
function remove_stale_github_wiki_pages!(
    manifest::WikiManifest, destination_root::String, expected::Set{String})

    for section in manifest.sections, claim in section.managed_output_paths
        endswith(lowercase(claim), ".md") && continue
        prefix = replace(claim, '/' => '-')
        for name in readdir(destination_root)
            managed = name == prefix * ".md" || startswith(name, prefix * "-")
            managed && name ∉ expected && rm(joinpath(destination_root, name); force=true)
        end
    end
end

"""Replace only manifest-managed pages in a checked-out GitHub Wiki tree."""
function sync_wiki_artifact(
    manifest::WikiManifest, artifact_root::String, destination_root::String)

    isdir(artifact_root) || error("Wiki artifact directory does not exist: $artifact_root")
    mkpath(destination_root)
    source_paths = published_wiki_files(manifest, artifact_root)
    page_paths = Dict(path => github_wiki_page_path(path) for path in source_paths)
    length(unique(values(page_paths))) == length(page_paths) ||
        error("GitHub Wiki page names collide after flattening.")
    expected = Set(values(page_paths))
    for claim in published_wiki_paths(manifest)
        destination = joinpath(destination_root, claim)
        ispath(destination) && rm(destination; recursive=true, force=true)
    end
    remove_stale_github_wiki_pages!(manifest, destination_root, expected)
    for source_path in source_paths
        content = read(joinpath(artifact_root, source_path), String)
        destination = joinpath(destination_root, page_paths[source_path])
        write(destination, rewrite_github_wiki_links(content, source_path, page_paths))
    end
    return sort!(collect(expected))
end