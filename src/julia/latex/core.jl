const PARSER_GRAMMAR_VERSION = Int32(17)
const DEFAULT_STYLE_PROFILE = Int32(0)
const SCRIPT_SCALE = Float32(0.62)
const SCRIPT_SUP_RAISE = Float32(0.44)
const SCRIPT_SUB_DROP = Float32(0.30)
const SCRIPT_GAP = Float32(0.04)
const ACCENT_BAR_THICKNESS = Float32(0.08)
const ACCENT_BAR_OFFSET = Float32(0.10)
const RADICAL_BAR_THICKNESS = Float32(0.08)
const RADICAL_BAR_OFFSET = Float32(0.10)
const PARSE_CACHE_MAX_ENTRIES = 256
const MATH_OP_TEXT_RUN = Int32(1)
const MATH_OP_MATH_GLYPH_RUN = Int32(2)
const MATH_OP_ACCENT_BAR_RECURSIVE = Int32(3)
const MATH_OP_RADICAL_BAR_RECURSIVE = Int32(4)
const MATH_OP_SCRIPT_ATTACH_RECURSIVE = Int32(5)
const MATH_OP_LARGE_OP_RECURSIVE = Int32(6)
const MATH_OP_FRACTION_RECURSIVE = Int32(7)
const MATH_OP_STRETCH_DELIMITER_RECURSIVE = Int32(8)
const MATH_OP_MATRIX_RECURSIVE = Int32(9)

const LATEX_MODE_MATH = :math
const LATEX_MODE_DOCUMENT = :document
const DOCUMENT_STYLE_REGULAR = OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR
const DOCUMENT_STYLE_BOLD = OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_BOLD
const DOCUMENT_STYLE_ITALIC = OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_ITALIC
const DOCUMENT_LATEX_COLORS = Dict(
    "black" => OdinJuliaBridge.BridgeColor(0x00, 0x00, 0x00, 0xff),
    "blue" => OdinJuliaBridge.BridgeColor(0x00, 0x00, 0xff, 0xff),
    "brown" => OdinJuliaBridge.BridgeColor(0xbf, 0x80, 0x40, 0xff),
    "cyan" => OdinJuliaBridge.BridgeColor(0x00, 0xff, 0xff, 0xff),
    "darkgray" => OdinJuliaBridge.BridgeColor(0x40, 0x40, 0x40, 0xff),
    "gray" => OdinJuliaBridge.BridgeColor(0x80, 0x80, 0x80, 0xff),
    "green" => OdinJuliaBridge.BridgeColor(0x00, 0xff, 0x00, 0xff),
    "lightgray" => OdinJuliaBridge.BridgeColor(0xbf, 0xbf, 0xbf, 0xff),
    "lime" => OdinJuliaBridge.BridgeColor(0xbf, 0xff, 0x00, 0xff),
    "magenta" => OdinJuliaBridge.BridgeColor(0xff, 0x00, 0xff, 0xff),
    "olive" => OdinJuliaBridge.BridgeColor(0x80, 0x80, 0x00, 0xff),
    "orange" => OdinJuliaBridge.BridgeColor(0xff, 0x80, 0x00, 0xff),
    "pink" => OdinJuliaBridge.BridgeColor(0xff, 0xbf, 0xbf, 0xff),
    "purple" => OdinJuliaBridge.BridgeColor(0xbf, 0x00, 0x40, 0xff),
    "red" => OdinJuliaBridge.BridgeColor(0xff, 0x00, 0x00, 0xff),
    "teal" => OdinJuliaBridge.BridgeColor(0x00, 0x80, 0x80, 0xff),
    "violet" => OdinJuliaBridge.BridgeColor(0x80, 0x00, 0x80, 0xff),
    "white" => OdinJuliaBridge.BridgeColor(0xff, 0xff, 0xff, 0xff),
    "yellow" => OdinJuliaBridge.BridgeColor(0xff, 0xff, 0x00, 0xff))

const LATEX_PRIME_DOCUMENT = raw"""\textbf{Euclid} \textit{document} $x_1^2 \in \mathbb{R}$

\euclidpoint[color=steelblue,size=1] \euclidline[color=steelblue,length=3,thickness=2]

$$\frac{a+b}{\sqrt{c}}$$"""
const LATEX_PRIME_FALLBACK = "Euclid document x in R"

const STRETCH_DELIMITER_NONE = "."
const STRETCH_DELIMITER_RIGHT = "\\right"
const STRETCH_DELIMITER_TOKEN_MAP = Dict(
    "(" => "(",
    ")" => ")",
    "[" => "[",
    "]" => "]",
    "|" => "|",
    "." => STRETCH_DELIMITER_NONE,
    "\\{" => "\\{",
    "\\}" => "\\}",
    "\\|" => "\\|",
    "\\lceil" => "\\lceil",
    "\\rceil" => "\\rceil",
    "\\lfloor" => "\\lfloor",
    "\\rfloor" => "\\rfloor",
    "\\langle" => "\\langle",
    "\\rangle" => "\\rangle")

const BRIDGE_DELIMITER_KIND_MAP = Dict(
    STRETCH_DELIMITER_NONE => Int32(0),
    "(" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_PAREN,
    ")" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_PAREN,
    "[" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACKET,
    "]" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACKET,
    "\\{" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACE,
    "\\}" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACE,
    "|" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_VERT,
    "\\|" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_DOUBLE_VERT,
    "\\lceil" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_CEIL,
    "\\rceil" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_CEIL,
    "\\lfloor" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_FLOOR,
    "\\rfloor" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_FLOOR,
    "\\langle" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_ANGLE,
    "\\rangle" => OdinJuliaBridge.BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_ANGLE)

const LARGE_OP_KIND_NONE = Int32(0)
const LARGE_OP_KIND_SUM = Int32(1)
const LARGE_OP_KIND_PROD = Int32(2)
const LARGE_OP_KIND_INT = Int32(3)
const LARGE_OP_KIND_LIM = Int32(4)

const TEXT_OPERATOR_COMMANDS = Set([
    "\\arccos", "\\arcsin", "\\arctan", "\\arg", "\\cos", "\\csc", "\\cot",
    "\\coth", "\\deg", "\\det", "\\dim", "\\exp", "\\gcd", "\\hom", "\\inf",
    "\\ker", "\\lg", "\\liminf", "\\limsup", "\\ln", "\\log", "\\max",
    "\\min", "\\Pr", "\\sec", "\\sin", "\\sinh", "\\sup", "\\tan", "\\tanh"
])

const LARGE_OPERATOR_COMMAND_MAP = Dict(
    "\\sum" => ("∑", LARGE_OP_KIND_SUM),
    "\\prod" => ("∏", LARGE_OP_KIND_PROD),
    "\\int" => ("∫", LARGE_OP_KIND_INT),
    "\\lim" => ("lim", LARGE_OP_KIND_LIM))

const UNICODE_COMMAND_MAP = Dict(
    "\\ " => " ",
    "\\alpha" => "α",
    "\\beta" => "β",
    "\\gamma" => "γ",
    "\\delta" => "δ",
    "\\epsilon" => "ϵ",
    "\\varepsilon" => "ε",
    "\\zeta" => "ζ",
    "\\eta" => "η",
    "\\theta" => "θ",
    "\\vartheta" => "ϑ",
    "\\iota" => "ι",
    "\\kappa" => "κ",
    "\\varkappa" => "ϰ",
    "\\lambda" => "λ",
    "\\mu" => "μ",
    "\\nu" => "ν",
    "\\xi" => "ξ",
    "\\pi" => "π",
    "\\rho" => "ρ",
    "\\varrho" => "ϱ",
    "\\sigma" => "σ",
    "\\varsigma" => "ς",
    "\\tau" => "τ",
    "\\upsilon" => "υ",
    "\\phi" => "φ",
    "\\varphi" => "ϕ",
    "\\chi" => "χ",
    "\\psi" => "ψ",
    "\\omega" => "ω",
    "\\varpi" => "ϖ",
    "\\digamma" => "ϝ",
    "\\Gamma" => "Γ",
    "\\Delta" => "Δ",
    "\\Theta" => "Θ",
    "\\Lambda" => "Λ",
    "\\Xi" => "Ξ",
    "\\Pi" => "Π",
    "\\Sigma" => "Σ",
    "\\Upsilon" => "Υ",
    "\\Phi" => "Φ",
    "\\Psi" => "Ψ",
    "\\Omega" => "Ω",
    "\\aleph" => "ℵ",
    "\\beth" => "ℶ",
    "\\gimel" => "ℷ",
    "\\daleth" => "ℸ",
    "\\pm" => "±",
    "\\mp" => "∓",
    "\\times" => "×",
    "\\div" => "÷",
    "\\cdot" => "·",
    "\\ast" => "∗",
    "\\star" => "⋆",
    "\\bullet" => "∙",
    "\\diamond" => "⋄",
    "\\bigtriangleup" => "△",
    "\\bigtriangledown" => "▽",
    "\\triangleleft" => "◁",
    "\\triangleright" => "▷",
    "\\lhd" => "⊲",
    "\\rhd" => "⊳",
    "\\unlhd" => "⊴",
    "\\unrhd" => "⊵",
    "\\oplus" => "⊕",
    "\\ominus" => "⊖",
    "\\otimes" => "⊗",
    "\\oslash" => "⊘",
    "\\odot" => "⊙",
    "\\bigcirc" => "○",
    "\\dagger" => "†",
    "\\ddagger" => "‡",
    "\\amalg" => "⨿",
    "\\wr" => "≀",
    "\\setminus" => "∖",
    "\\sqcap" => "⊓",
    "\\sqcup" => "⊔",
    "\\uplus" => "⊎",
    "\\infty" => "∞",
    "\\partial" => "∂",
    "\\nabla" => "∇",
    "\\oint" => "∮",
    "\\iint" => "∬",
    "\\iiint" => "∭",
    "\\coprod" => "∐",
    "\\forall" => "∀",
    "\\exists" => "∃",
    "\\nexists" => "∄",
    "\\neg" => "¬",
    "\\land" => "∧",
    "\\lor" => "∨",
    "\\wedge" => "∧",
    "\\vee" => "∨",
    "\\in" => "∈",
    "\\notin" => "∉",
    "\\ni" => "∋",
    "\\owns" => "∋",
    "\\notni" => "∌",
    "\\subset" => "⊂",
    "\\subseteq" => "⊆",
    "\\subsetneq" => "⊊",
    "\\nsubseteq" => "⊈",
    "\\supset" => "⊃",
    "\\supseteq" => "⊇",
    "\\supsetneq" => "⊋",
    "\\nsupseteq" => "⊉",
    "\\sqsubset" => "⊏",
    "\\sqsubseteq" => "⊑",
    "\\sqsupset" => "⊐",
    "\\sqsupseteq" => "⊒",
    "\\cup" => "∪",
    "\\cap" => "∩",
    "\\emptyset" => "∅",
    "\\varnothing" => "∅",
    "\\complement" => "∁",
    "\\to" => "→",
    "\\rightarrow" => "→",
    "\\leftarrow" => "←",
    "\\leftrightarrow" => "↔",
    "\\uparrow" => "↑",
    "\\downarrow" => "↓",
    "\\updownarrow" => "↕",
    "\\Rightarrow" => "⇒",
    "\\Leftarrow" => "⇐",
    "\\iff" => "⇔",
    "\\Leftrightarrow" => "⇔",
    "\\Uparrow" => "⇑",
    "\\Downarrow" => "⇓",
    "\\Updownarrow" => "⇕",
    "\\longleftarrow" => "⟵",
    "\\longrightarrow" => "⟶",
    "\\longleftrightarrow" => "⟷",
    "\\Longleftarrow" => "⟸",
    "\\Longrightarrow" => "⟹",
    "\\Longleftrightarrow" => "⟺",
    "\\hookleftarrow" => "↩",
    "\\hookrightarrow" => "↪",
    "\\nearrow" => "↗",
    "\\searrow" => "↘",
    "\\swarrow" => "↙",
    "\\nwarrow" => "↖",
    "\\leftharpoonup" => "↼",
    "\\leftharpoondown" => "↽",
    "\\rightharpoonup" => "⇀",
    "\\rightharpoondown" => "⇁",
    "\\rightleftharpoons" => "⇌",
    "\\leftrightharpoons" => "⇋",
    "\\leadsto" => "⇝",
    "\\leq" => "≤",
    "\\le" => "≤",
    "\\ge" => "≥",
    "\\geq" => "≥",
    "\\ll" => "≪",
    "\\gg" => "≫",
    "\\ne" => "≠",
    "\\neq" => "≠",
    "\\approx" => "≈",
    "\\equiv" => "≡",
    "\\propto" => "∝",
    "\\prec" => "≺",
    "\\succ" => "≻",
    "\\preceq" => "≼",
    "\\succeq" => "≽",
    "\\sim" => "∼",
    "\\simeq" => "≃",
    "\\cong" => "≅",
    "\\asymp" => "≍",
    "\\doteq" => "≐",
    "\\parallel" => "∥",
    "\\nparallel" => "∦",
    "\\mid" => "∣",
    "\\nmid" => "∤",
    "\\perp" => "⊥",
    "\\models" => "⊨",
    "\\vdash" => "⊢",
    "\\dashv" => "⊣",
    "\\bowtie" => "⋈",
    "\\smile" => "⌣",
    "\\frown" => "⌢",
    "\\therefore" => "∴",
    "\\because" => "∵",
    "\\top" => "⊤",
    "\\bot" => "⊥",
    "\\circ" => "∘",
    "\\dots" => "…",
    "\\ldots" => "…",
    "\\cdots" => "⋯",
    "\\vdots" => "⋮",
    "\\ddots" => "⋱",
    "\\mapsto" => "↦",
    "\\rtimes" => "⋊",
    "\\prime" => "′",
    "\\hbar" => "ℏ",
    "\\ell" => "ℓ",
    "\\Re" => "ℜ",
    "\\Im" => "ℑ",
    "\\wp" => "℘",
    "\\angle" => "∠",
    "\\measuredangle" => "∡",
    "\\sphericalangle" => "∢",
    "\\triangle" => "△",
    "\\Box" => "□",
    "\\square" => "□",
    "\\Diamond" => "◇",
    "\\lozenge" => "◊",
    "\\clubsuit" => "♣",
    "\\diamondsuit" => "♢",
    "\\heartsuit" => "♡",
    "\\spadesuit" => "♠",
    "\\flat" => "♭",
    "\\natural" => "♮",
    "\\sharp" => "♯",
    "\\checkmark" => "✓",
    "\\mho" => "℧",
    "\\degree" => "°",
    "\\surd" => "√",
    "\\;" => " ",
    "\\lceil" => "⌈",
    "\\rceil" => "⌉",
    "\\lfloor" => "⌊",
    "\\rfloor" => "⌋",
    "\\vert" => "|",
    "\\|" => "‖",
    "\\Vert" => "‖",
    "\\backslash" => "∖",
    "\\{" => "{",
    "\\}" => "}")

const NONBREAKING_SPACE = "\u00a0"

const MATHBB_UPPERCASE_MAP = Dict(
    "A" => "𝔸",
    "B" => "𝔹",
    "C" => "ℂ",
    "D" => "𝔻",
    "E" => "𝔼",
    "F" => "𝔽",
    "G" => "𝔾",
    "H" => "ℍ",
    "I" => "𝕀",
    "J" => "𝕁",
    "K" => "𝕂",
    "L" => "𝕃",
    "M" => "𝕄",
    "N" => "ℕ",
    "O" => "𝕆",
    "P" => "ℙ",
    "Q" => "ℚ",
    "R" => "ℝ",
    "S" => "𝕊",
    "T" => "𝕋",
    "U" => "𝕌",
    "V" => "𝕍",
    "W" => "𝕎",
    "X" => "𝕏",
    "Y" => "𝕐",
    "Z" => "ℤ")

const MATHBB_GLYPH_TO_SOURCE_MAP =
    Dict(value => key for (key, value) in MATHBB_UPPERCASE_MAP)
const COMMANDS_IGNORE_TRAILING_SPACE = Set([
    "\\angle",
    "\\measuredangle",
    "\\sphericalangle",
])

struct LatexToken
    kind::Symbol
    text::String
end

struct LatexRun
    text::String
    role::Symbol
    segment::Symbol
    children::Vector{LatexRun}
    secondary_children::Vector{LatexRun}
end

struct MathPayloadOp
    kind::Int32
    text::String
    radical_index_text::String
    sup_text::String
    sub_text::String
    accent_mode::Symbol
    radical_mode::Symbol
    large_op_kind::Int32
    style_role::Symbol
    children::Vector{MathPayloadOp}
    secondary_children::Vector{MathPayloadOp}
end

struct ParseCacheEntry
    source::String
    grammar_version::Int32
    style_profile::Int32
    tokens::Vector{LatexToken}
    ast::Vector{LatexRun}
    normalized_ast::Vector{LatexRun}
    program::Vector{MathPayloadOp}
end

struct LatexDocumentShape
    kind::Symbol
    color::Union{Nothing,OdinJuliaBridge.BridgeColor}
    width::Float32
    height::Float32
    thickness::Float32
    filled::Bool
    start_angle::Float32
    end_angle::Float32
    fill_color::Union{Nothing,OdinJuliaBridge.BridgeColor}
    arc_color::Union{Nothing,OdinJuliaBridge.BridgeColor}
    edge_color_1::Union{Nothing,OdinJuliaBridge.BridgeColor}
    edge_color_2::Union{Nothing,OdinJuliaBridge.BridgeColor}
    edge_color_3::Union{Nothing,OdinJuliaBridge.BridgeColor}
    edge_color_4::Union{Nothing,OdinJuliaBridge.BridgeColor}
    edge_color_5::Union{Nothing,OdinJuliaBridge.BridgeColor}
end

struct LatexDocumentRun
    kind::Symbol
    text::String
    font_flags::Int32
    shape::Union{Nothing,LatexDocumentShape}
    color::Union{Nothing,OdinJuliaBridge.BridgeColor}
end

"""Construct a document run with no shape or color payload."""
LatexDocumentRun(kind::Symbol, text::String, font_flags::Int32) =
    LatexDocumentRun(kind, text, font_flags, nothing, nothing)

LatexDocumentRun(
    kind::Symbol,
    text::String,
    font_flags::Int32,
    shape::Union{Nothing,LatexDocumentShape}) =
    LatexDocumentRun(kind, text, font_flags, shape, nothing)

mutable struct LatexDocumentParser
    source::String
    index::Int
end

const PARSE_CACHE = Dict{Tuple{String, Int32, Int32}, ParseCacheEntry}()
const PARSE_CACHE_ORDER = Tuple{String, Int32, Int32}[]

const EMPTY_CHILD_RUNS = LatexRun[]

"""Return one normal atom run payload."""
latex_atom_run(text::AbstractString, role::Symbol) =
    LatexRun(text, role, :atom, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Classify one normal-math scalar as an italic variable or upright math."""
function normal_math_role(character::Char)
    if isascii(character) && isletter(character)
        return :math_italic
    end
    codepoint = UInt32(character)
    if UInt32(0x03b1) <= codepoint <= UInt32(0x03c9) ||
            character in ('ϵ', 'ϑ', 'ϰ', 'ϕ', 'ϱ', 'ϖ')
        return :math_italic
    end
    return :math_upright
end

"""Split normal-math text whenever its italic-variable semantic role changes."""
function normal_math_atom_runs(text::AbstractString)
    runs = LatexRun[]
    characters = collect(String(text))
    current_role = :none
    current = IOBuffer()
    for (index, character) in pairs(characters)
        role = if isspace(character)
            next_index = findnext(candidate -> !isspace(candidate), characters, index + 1)
            isnothing(next_index) ?
                (current_role == :none ? :math_upright : current_role) :
                normal_math_role(characters[next_index])
        else
            normal_math_role(character)
        end
        if current_role != :none && role != current_role
            push!(runs, latex_atom_run(String(take!(current)), current_role))
        end
        current_role = role
        write(current, character)
    end
    if current_role != :none
        push!(runs, latex_atom_run(String(take!(current)), current_role))
    end
    return runs
end

"""Return one superscript script-segment run payload."""
latex_sup_run(text::AbstractString) =
    LatexRun(text, :math, :script_sup, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one subscript script-segment run payload."""
latex_sub_run(text::AbstractString) =
    LatexRun(text, :math, :script_sub, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one overline accent run payload."""
latex_overline_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :accent_over, children, EMPTY_CHILD_RUNS)

"""Return one underline accent run payload."""
latex_underline_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :accent_under, children, EMPTY_CHILD_RUNS)

"""Return one square-root radical run payload."""
latex_sqrt_run(children::Vector{LatexRun}, index_text::AbstractString="") =
    LatexRun(String(index_text), :math, :radical_sqrt, children, EMPTY_CHILD_RUNS)

"""Return one fraction run payload with numerator and denominator child runs."""
latex_fraction_run(
    numerator_children::Vector{LatexRun}, denominator_children::Vector{LatexRun}) =
    LatexRun("", :math, :fraction, numerator_children, denominator_children)

"""Return one stretch-delimiter run payload with left/right delimiters and inner runs."""
latex_stretch_delimiter_run(left::String, right::String, children::Vector{LatexRun}) =
    LatexRun(left, :math, :stretch_delimiter, children, [latex_atom_run(right, :math)])

"""Return compact matrix dimension text for one matrix run."""
matrix_dims_text(rows::Int, cols::Int) = string(rows) * "," * string(cols)

"""Return one matrix-cell run payload wrapping child runs for a single cell."""
latex_matrix_cell_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :matrix_cell, children, EMPTY_CHILD_RUNS)

"""Return one matrix run payload with row/column metadata and row-major cell runs."""
latex_matrix_run(rows::Int, cols::Int, cells::Vector{LatexRun}) =
    LatexRun(matrix_dims_text(rows, cols), :math, :matrix, cells, EMPTY_CHILD_RUNS)

"""Return one array run payload with row/column metadata and normalized alignment preamble."""
latex_array_run(rows::Int, cols::Int, cells::Vector{LatexRun}, preamble::String) =
    LatexRun(matrix_dims_text(rows, cols), :math, :array, cells,
        [latex_atom_run(preamble, :math)])
