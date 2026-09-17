using Colors

const Header = """package color_names

// Generated from Colors.color_names by tools/generate_named_colors.jl.
// Regenerate with: julia --project=src/julia tools/generate_named_colors.jl

import colormodel "../model"

Named_Color_Entry :: struct {
    name: string,
    value: colormodel.Color_RGBA8,
}

NAMED_COLORS :: [?]Named_Color_Entry{
"""

const ProjectColors = [
    "julia_blue" => (64, 99, 216),
    "julia_green" => (56, 152, 38),
    "julia_purple" => (149, 88, 178),
    "julia_red" => (203, 60, 51),
]

"""Write the pinned Colors.jl named-color registry as immutable Odin data."""
function generate_named_colors(output_path::AbstractString)
    names = sort!(collect(keys(Colors.color_names)))
    mkpath(dirname(output_path))
    open(output_path, "w") do io
        print(io, Header)
        for name in names
            red, green, blue = Colors.color_names[name]
            println(io, "    {\"$name\", {$red, $green, $blue, 255}},")
        end
        for (name, (red, green, blue)) in ProjectColors
            println(io, "    {\"$name\", {$red, $green, $blue, 255}},")
        end
        println(io, "}")
        print(io, """

// resolve_named_color resolves one exact supported source color name.
resolve_named_color :: proc(name: string) -> (colormodel.Color_RGBA8, bool) {
    for named in NAMED_COLORS {
        if named.name == name {
            return named.value, true
        }
    }
    return {}, false
}
""")
    end
end

generate_named_colors(isempty(ARGS) ?
    joinpath(@__DIR__, "..", "src", "color", "names", "names.odin") : ARGS[1])