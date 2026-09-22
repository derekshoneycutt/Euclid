using Colors

const Header = """package color

// Generated from Colors.color_names by tools/generate_named_colors.jl.
// Regenerate with: julia --project=src/julia tools/generate_named_colors.jl

NAMED_COLORS :: [?]Named_Color_Entry{
"""

"""Write the pinned Colors.jl named-color registry as immutable Odin data."""
function generate_named_colors(output_path::AbstractString)
    names = sort!(collect(keys(Colors.color_names)))
    open(output_path, "w") do io
        print(io, Header)
        for name in names
            red, green, blue = Colors.color_names[name]
            println(io, "    {\"$name\", {$red, $green, $blue, 255}},")
        end
        println(io, "}")
    end
end

generate_named_colors(isempty(ARGS) ?
    joinpath(@__DIR__, "..", "src", "core", "color", "named_colors_generated.odin") :
    ARGS[1])