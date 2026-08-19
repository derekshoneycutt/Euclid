Base.@kwdef struct JuliaWikiConfig
    repository_root::String
end

Base.@kwdef struct JuliaDeclarationIdentity
    name::String
    signature::String
end

"""Return parser children as an iterable collection for both branch and leaf nodes."""
julia_syntax_children(node) = something(JuliaSyntax.children(node), ())

"""Return the parser kind of one Julia syntax node as a symbol."""
julia_syntax_kind(node) = Symbol(string(JuliaSyntax.kind(node)))

"""Return owned source text for one Julia syntax node."""
julia_syntax_text(node) = String(JuliaSyntax.sourcetext(node))

"""Return a one-based source line from a parser byte offset."""
function julia_source_line(source::String, byte_offset::Int)
    byte_offset <= 1 && return 1
    return count(==(0x0a), @view(codeunits(source)[1:byte_offset - 1])) + 1
end

"""Return a supported declaration nested beneath transparent macro wrappers."""
function unwrap_julia_declaration(node)
    kind = julia_syntax_kind(node)
    kind in (:function, :struct, :macro, :const, :module) && return node
    kind == :macrocall || return nothing
    for child in reverse(collect(julia_syntax_children(node)))
        declaration = unwrap_julia_declaration(child)
        declaration === nothing || return declaration
    end
    return nothing
end

"""Return the declaration and static Markdown from one parser doc node."""
function julia_documented_declaration(node)
    julia_syntax_kind(node) == :doc || return nothing, ""
    children = collect(julia_syntax_children(node))
    length(children) >= 2 || error("Malformed Julia doc node.")
    literal = Meta.parse(julia_syntax_text(first(children)))
    literal isa String || error("Julia documentation must use a static string literal.")
    return unwrap_julia_declaration(last(children)), literal
end

"""Return the callable name represented by a parsed Julia signature expression."""
function julia_callable_name(expression)
    expression isa Symbol && return String(expression)
    expression isa QuoteNode && expression.value isa Symbol &&
        return String(expression.value)
    expression isa Expr || return ""
    expression.head in (:where, :(::)) && return julia_callable_name(expression.args[1])
    expression.head == :call && return julia_callable_name(expression.args[1])
    expression.head == :curly && return julia_callable_name(expression.args[1])
    if expression.head == :. && !isempty(expression.args)
        return julia_callable_name(last(expression.args))
    end
    return ""
end

"""Return the declared type name represented by a parsed Julia type expression."""
function julia_type_name(expression)
    expression isa Symbol && return String(expression)
    expression isa Expr || return ""
    expression.head == :(<:) && return julia_type_name(expression.args[1])
    expression.head == :curly && return julia_type_name(expression.args[1])
    return julia_callable_name(expression)
end

"""Return a function or macro signature node from one declaration."""
function julia_callable_signature_node(declaration)
    children = collect(julia_syntax_children(declaration))
    isempty(children) && error("Julia callable declaration has no signature.")
    return first(children)
end

"""Return the name and display signature for one supported Julia declaration."""
function julia_declaration_identity(declaration)
    kind = julia_syntax_kind(declaration)
    kind == :function && return julia_callable_identity(declaration, "")
    kind == :macro && return julia_callable_identity(declaration, "@")
    kind == :struct && return julia_struct_identity(declaration)
    kind == :const && return julia_const_identity(declaration)
    error("Unsupported Julia declaration kind: $kind")
end

"""Return the identity for one function or macro declaration, with a display prefix."""
function julia_callable_identity(declaration, prefix::String)
    signature = strip(julia_syntax_text(julia_callable_signature_node(declaration)))
    name = julia_callable_name(Meta.parse(signature))
    return JuliaDeclarationIdentity(name=name, signature=prefix * String(signature))
end

"""Return the identity for one struct declaration."""
function julia_struct_identity(declaration)
    children = collect(julia_syntax_children(declaration))
    isempty(children) && error("Julia struct declaration has no type expression.")
    type_text = strip(julia_syntax_text(first(children)))
    prefix = startswith(strip(julia_syntax_text(declaration)), "mutable struct") ?
        "mutable struct " : "struct "
    return JuliaDeclarationIdentity(
        name=julia_type_name(Meta.parse(type_text)), signature=prefix * String(type_text))
end

"""Return the identity for one const declaration."""
function julia_const_identity(declaration)
    source = strip(julia_syntax_text(declaration))
    expression = Meta.parse(source)
    value = expression isa Expr && expression.head == :const ?
        expression.args[1] : expression
    name_expr = value isa Expr && value.head == :(=) ? value.args[1] : value
    return JuliaDeclarationIdentity(
        name=julia_callable_name(name_expr), signature=String(source))
end

"""Return a normalized declaration kind for one Julia syntax declaration."""
function julia_declaration_kind(declaration)
    kind = julia_syntax_kind(declaration)
    kind == :function && return :function
    kind == :macro && return :macro
    kind == :struct && return :struct
    kind == :const && return :constant
    error("Unsupported Julia declaration kind: $kind")
end

"""Build one static Julia symbol record from a parser-owned declaration span."""
function parsed_julia_symbol(
    declaration, doc_markdown::String, package::DocumentationPackage,
    source::String, source_path::String, exported_names::Set{String})

    identity = julia_declaration_identity(declaration)
    name = identity.name
    signature = identity.signature
    isempty(name) && error("Unable to resolve Julia declaration name: $signature")
    kind = julia_declaration_kind(declaration)
    line = julia_source_line(source, JuliaSyntax.first_byte(declaration))
    visibility = name in exported_names ? :public :
        (isempty(doc_markdown) ? :all : :documented)
    return DocumentationSymbol(
        language=:julia,
        stable_id="julia:$(package.display_name):$kind:$name",
        package_id=package.stable_id,
        name=name,
        qualified_name="$(package.display_name).$name",
        declaration_kind=kind,
        signature=signature,
        doc_markdown=doc_markdown,
        source_path=source_path,
        source_line=line,
        visibility=visibility,
        method_signatures=kind == :function ? [signature] : String[])
end

"""Return direct body nodes from a parsed module or top-level syntax tree."""
function julia_container_nodes(container)
    children = collect(julia_syntax_children(container))
    if julia_syntax_kind(container) == :module
        block_index = findfirst(node -> julia_syntax_kind(node) == :block, children)
        block_index === nothing && error("Julia module has no body block.")
        return collect(julia_syntax_children(children[block_index]))
    end
    return children
end

"""Return the documented module declaration and its static module documentation."""
function julia_module_declaration(tree)
    for node in julia_container_nodes(tree)
        declaration, markdown = julia_documented_declaration(node)
        declaration === nothing && continue
        julia_syntax_kind(declaration) == :module && return declaration, markdown
    end
    error("Julia entry file must contain one documented module declaration.")
end

"""Return a module name from its parser declaration."""
function julia_module_name(module_node)
    for child in julia_syntax_children(module_node)
        if julia_syntax_kind(child) == :Identifier
            return String(strip(julia_syntax_text(child)))
        end
    end
    error("Julia module declaration has no name.")
end

"""Collect exported binding names from module body nodes."""
function julia_exported_names(nodes)
    exported = Set{String}()
    for node in nodes
        julia_syntax_kind(node) == :export || continue
        for child in julia_syntax_children(node)
            name = strip(julia_syntax_text(child))
            isempty(name) || push!(exported, String(name))
        end
    end
    return exported
end

"""Return a literal include path, an empty marker for dynamic include, or `nothing`."""
function julia_include_argument(node)
    julia_syntax_kind(node) == :call || return nothing
    source = strip(julia_syntax_text(node))
    startswith(source, "include") || return nothing
    expression = Meta.parse(source)
    expression isa Expr && expression.head == :call || return ""
    length(expression.args) == 2 && expression.args[1] == :include || return ""
    return expression.args[2] isa String ? expression.args[2] : ""
end

"""Resolve safe literal includes from one file's top-level nodes."""
function collect_julia_includes!(
    pending::Vector{String}, package::DocumentationPackage, nodes,
    source_path::String, repository_root::String)

    for node in nodes
        include_path = julia_include_argument(node)
        include_path === nothing && continue
        if isempty(include_path)
            push!(package.diagnostics, "Dynamic include skipped in $source_path.")
            continue
        end
        resolved = normalize_repo_path(joinpath(dirname(source_path), include_path))
        startswith(resolved, "../") && error("Julia include escapes repository: $resolved")
        isfile(joinpath(repository_root, resolved)) || error("Julia include not found: $resolved")
        push!(pending, resolved)
    end
end

"""Collect supported declarations from one file without evaluating source code."""
function collect_julia_declarations!(
    package::DocumentationPackage, nodes, source::String,
    source_path::String, exported_names::Set{String})

    for node in nodes
        declaration, markdown = julia_documented_declaration(node)
        declaration === nothing && (declaration = unwrap_julia_declaration(node))
        declaration === nothing && continue
        julia_syntax_kind(declaration) == :module && continue
        push!(package.symbols, parsed_julia_symbol(
            declaration, markdown, package, source, source_path, exported_names))
    end
end

"""Merge Julia function methods into one deterministic normalized symbol."""
function group_julia_methods!(package::DocumentationPackage)
    functions = filter(symbol -> symbol.declaration_kind == :function, package.symbols)
    nonfunctions = filter(symbol -> symbol.declaration_kind != :function, package.symbols)
    grouped = DocumentationSymbol[]
    for name in sort!(unique(symbol.name for symbol in functions))
        methods = sort(filter(symbol -> symbol.name == name, functions);
            by=symbol -> (symbol.source_path, symbol.source_line))
        documented = filter(symbol -> !isempty(symbol.doc_markdown), methods)
        primary = isempty(documented) ? first(methods) : first(documented)
        primary.method_signatures = sort!(unique(symbol.signature for symbol in methods))
        if length(unique(symbol.doc_markdown for symbol in documented)) > 1
            push!(primary.diagnostics, "Multiple distinct method docstrings were grouped.")
        end
        primary.visibility = any(symbol -> symbol.visibility == :public, methods) ?
            :public : primary.visibility
        push!(grouped, primary)
    end
    package.symbols = sort!(vcat(nonfunctions, grouped);
        by=symbol -> (String(symbol.declaration_kind), symbol.qualified_name))
    return package
end

"""Extract one Julia module and its literal includes without executing source."""
function extract_julia_module(config::JuliaWikiConfig, entry_file::AbstractString)
    entry_path = normalize_repo_path(entry_file)
    entry_source = read(joinpath(config.repository_root, entry_path), String)
    entry_tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, entry_source)
    module_node, module_doc = julia_module_declaration(entry_tree)
    module_name = julia_module_name(module_node)
    package = DocumentationPackage(
        language=:julia,
        stable_id="julia:$module_name",
        display_name=module_name,
        source_root=normalize_repo_path(dirname(entry_path)),
        doc_markdown=module_doc)
    extract_julia_files!(package, config, entry_path, module_node)
    return group_julia_methods!(package)
end

"""Traverse one module entrypoint and its safe literal include closure."""
function extract_julia_files!(
    package::DocumentationPackage, config::JuliaWikiConfig,
    entry_path::String, module_node)

    pending = [entry_path]
    visited = Set{String}()
    exported_names = julia_exported_names(julia_container_nodes(module_node))
    while !isempty(pending)
        source_path = popfirst!(pending)
        source_path in visited && continue
        push!(visited, source_path)
        source = read(joinpath(config.repository_root, source_path), String)
        tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, source)
        nodes = source_path == entry_path ?
            julia_container_nodes(module_node) : julia_container_nodes(tree)
        collect_julia_includes!(pending, package, nodes,
            source_path, config.repository_root)
        collect_julia_declarations!(package, nodes, source, source_path, exported_names)
    end
    package.source_files = sort!(normalize_repo_path.(
        relpath.(collect(visited), Ref(package.source_root))))
    return package
end

"""Return a human-readable Julia declaration group heading."""
function julia_declaration_heading(kind::Symbol)
    headings = Dict(
        :constant => "Constants", :function => "Functions",
        :macro => "Macros", :struct => "Types")
    return get(headings, kind, titlecase(String(kind)))
end

"""Render links to every binding exported by one Julia module."""
function render_julia_public_api!(io::IO, symbols::Vector{DocumentationSymbol})
    public_symbols = filter(symbol -> symbol.visibility == :public, symbols)
    isempty(public_symbols) && return
    write(io, "## Public API\n")
    kinds = sort!(unique(symbol.declaration_kind for symbol in public_symbols); by=String)
    for kind in kinds
        write(io, "\n### ", julia_declaration_heading(kind), "\n")
        selected = sort(filter(symbol -> symbol.declaration_kind == kind, public_symbols);
            by=symbol -> lowercase(symbol.name))
        for symbol in selected
            write(io, "\n- [`", symbol.name, "`](#", wiki_symbol_anchor(symbol), ")\n")
        end
    end
    write(io, "\n")
end

"""Render one deterministic GitHub-flavored Markdown Julia module page."""
function render_julia_module_page(package::DocumentationPackage;
    source_link_prefix::String="../../../../")

    symbols = filter(symbol -> symbol.visibility == :public ||
        !isempty(symbol.doc_markdown), package.symbols)
    io = IOBuffer()
    write(io, "<!-- Generated from source doc comments. Do not edit this file directly. -->\n\n")
    write(io, "# Julia Module `", package.display_name, "`\n\n")
    write(io, shift_markdown_headings(package.doc_markdown), "\n\n")
    render_package_guide_links!(io, package.authored_document_refs)
    render_julia_public_api!(io, package.symbols)
    write(io, "## Source Files\n\n")
    for source_file in package.source_files
        source_path = normalize_repo_path(joinpath(package.source_root, source_file))
        write(io, "- [`", source_path, "`](", source_link_prefix, source_path, ")\n")
    end
    render_julia_symbol_groups!(io, symbols, source_link_prefix)
    return String(take!(io))
end

"""Render documented Julia symbols and grouped method signatures."""
function render_julia_symbol_groups!(
    io::IO, symbols::Vector{DocumentationSymbol}, source_link_prefix::String)

    kinds = sort!(unique(symbol.declaration_kind for symbol in symbols); by=String)
    for kind in kinds
        write(io, "\n## ", julia_declaration_heading(kind), "\n")
        for symbol in filter(item -> item.declaration_kind == kind, symbols)
            signatures = isempty(symbol.method_signatures) ? [symbol.signature] :
                symbol.method_signatures
            write(io, "\n<a id=\"", wiki_symbol_anchor(symbol), "\"></a>\n")
            write(io, "\n### `", symbol.name, "`\n\n```julia\n",
                join(signatures, "\n"), "\n```\n\n")
            write(io, "[Source](", source_link_prefix, symbol.source_path,
                "#L", string(symbol.source_line), ")\n\n")
            render_authored_document_links!(io, symbol.authored_document_refs)
            write(io, shift_markdown_headings(symbol.doc_markdown), "\n")
        end
    end
end

"""Write one rendered Julia module page, creating its parent directory."""
function write_julia_module_page(
    package::DocumentationPackage, output_path::AbstractString;
    source_link_prefix::String="../../../../")

    mkpath(dirname(output_path))
    write(output_path, render_julia_module_page(
        package; source_link_prefix=source_link_prefix))
    return String(output_path)
end