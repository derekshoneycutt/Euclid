const PARSER_GRAMMAR_VERSION = Int32(24)
const DEFAULT_STYLE_PROFILE = Int32(0)
const SCRIPT_SCALE = Float32(0.62)
const SCRIPT_SUP_RAISE = Float32(0.44)
const SCRIPT_SUB_DROP = Float32(0.30)
const SCRIPT_GAP = Float32(0.04)
const ACCENT_BAR_THICKNESS = Float32(0.08)
const ACCENT_BAR_OFFSET = Float32(0.10)
const RADICAL_BAR_THICKNESS = Float32(0.08)
const RADICAL_BAR_OFFSET = Float32(0.10)
const MATH_OP_TEXT_RUN = Int32(1)
const MATH_OP_MATH_GLYPH_RUN = Int32(2)
const MATH_OP_ACCENT_BAR_RECURSIVE = Int32(3)
const MATH_OP_RADICAL_BAR_RECURSIVE = Int32(4)
const MATH_OP_SCRIPT_ATTACH_RECURSIVE = Int32(5)
const MATH_OP_LARGE_OP_RECURSIVE = Int32(6)
const MATH_OP_FRACTION_RECURSIVE = Int32(7)
const MATH_OP_STRETCH_DELIMITER_RECURSIVE = Int32(8)
const MATH_OP_MATRIX_RECURSIVE = Int32(9)
const MATH_OP_STYLE_OVERRIDE_RECURSIVE = Int32(10)
const MATH_OP_STACK_RECURSIVE = Int32(11)

const OPERATOR_GROWTH_NONE = Int32(0)
const OPERATOR_GROWTH_DISPLAY = Int32(1)
const OPERATOR_LIMITS_NONE = Int32(0)
const OPERATOR_LIMITS_SIDE = Int32(1)
const OPERATOR_LIMITS_STACKED = Int32(2)

const MATH_ATOM_NONE = Int32(0)
const MATH_ATOM_ORD = Int32(1)
const MATH_ATOM_OP = Int32(2)
const MATH_ATOM_BIN = Int32(3)
const MATH_ATOM_REL = Int32(4)
const MATH_ATOM_OPEN = Int32(5)
const MATH_ATOM_CLOSE = Int32(6)
const MATH_ATOM_PUNCT = Int32(7)
const MATH_ATOM_INNER = Int32(8)

const MATH_GLUE_NONE = Int32(0)
const MATH_GLUE_THICK = Int32(1)
const MATH_GLUE_SPACE = Int32(2)
const MATH_GLUE_NEGATIVE_THIN = Int32(3)
const MATH_GLUE_QUAD = Int32(4)
const MATH_GLUE_THIN = Int32(5)
const MATH_GLUE_SOURCE = Int32(6)

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
const STRETCH_DELIMITER_MIDDLE = "\\middle"
const FIXED_DELIMITER_COMMANDS = Dict(
    "\\big" => (Int32(1), MATH_ATOM_ORD),
    "\\bigl" => (Int32(1), MATH_ATOM_OPEN),
    "\\bigr" => (Int32(1), MATH_ATOM_CLOSE),
    "\\bigm" => (Int32(1), MATH_ATOM_REL),
    "\\Big" => (Int32(2), MATH_ATOM_ORD),
    "\\Bigl" => (Int32(2), MATH_ATOM_OPEN),
    "\\Bigr" => (Int32(2), MATH_ATOM_CLOSE),
    "\\Bigm" => (Int32(2), MATH_ATOM_REL),
    "\\bigg" => (Int32(3), MATH_ATOM_ORD),
    "\\biggl" => (Int32(3), MATH_ATOM_OPEN),
    "\\biggr" => (Int32(3), MATH_ATOM_CLOSE),
    "\\biggm" => (Int32(3), MATH_ATOM_REL),
    "\\Bigg" => (Int32(4), MATH_ATOM_ORD),
    "\\Biggl" => (Int32(4), MATH_ATOM_OPEN),
    "\\Biggr" => (Int32(4), MATH_ATOM_CLOSE),
    "\\Biggm" => (Int32(4), MATH_ATOM_REL))
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
const LARGE_OP_KIND_NARY = Int32(5)

const TEXT_OPERATOR_COMMANDS = Set([
    "\\arccos", "\\arcsin", "\\arctan", "\\arg", "\\cos", "\\csc", "\\cot",
    "\\coth", "\\deg", "\\det", "\\dim", "\\exp", "\\gcd", "\\hom", "\\inf",
    "\\ker", "\\lg", "\\liminf", "\\limsup", "\\ln", "\\log", "\\max",
    "\\min", "\\Pr", "\\sec", "\\sin", "\\sinh", "\\sup", "\\tan", "\\tanh"
])

const LARGE_OPERATOR_COMMAND_MAP = Dict(
    "\\sum" => ("∑", LARGE_OP_KIND_SUM),
    "\\prod" => ("∏", LARGE_OP_KIND_PROD),
    "\\coprod" => ("∐", LARGE_OP_KIND_PROD),
    "\\int" => ("∫", LARGE_OP_KIND_INT),
    "\\oint" => ("∮", LARGE_OP_KIND_INT),
    "\\iint" => ("∬", LARGE_OP_KIND_INT),
    "\\iiint" => ("∭", LARGE_OP_KIND_INT),
    "\\bigcup" => ("⋃", LARGE_OP_KIND_NARY),
    "\\bigcap" => ("⋂", LARGE_OP_KIND_NARY),
    "\\bigvee" => ("⋁", LARGE_OP_KIND_NARY),
    "\\bigwedge" => ("⋀", LARGE_OP_KIND_NARY),
    "\\bigsqcup" => ("⨆", LARGE_OP_KIND_NARY),
    "\\biguplus" => ("⨄", LARGE_OP_KIND_NARY),
    "\\bigoplus" => ("⨁", LARGE_OP_KIND_NARY),
    "\\bigotimes" => ("⨂", LARGE_OP_KIND_NARY),
    "\\bigodot" => ("⨀", LARGE_OP_KIND_NARY),
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
    "\\lvert" => "|",
    "\\rvert" => "|",
    "\\|" => "‖",
    "\\Vert" => "‖",
    "\\lVert" => "‖",
    "\\rVert" => "‖",
    "\\backslash" => "∖",
    "\\{" => "{",
    "\\}" => "}")

const BINARY_ATOM_COMMANDS = Set([
    "\\pm", "\\mp", "\\times", "\\div", "\\cdot", "\\ast", "\\star",
    "\\bullet", "\\diamond", "\\bigtriangleup", "\\bigtriangledown",
    "\\triangleleft", "\\triangleright", "\\lhd", "\\rhd", "\\unlhd",
    "\\unrhd", "\\oplus", "\\ominus", "\\otimes", "\\oslash", "\\odot",
    "\\bigcirc", "\\dagger", "\\ddagger", "\\amalg", "\\wr", "\\setminus",
    "\\sqcap", "\\sqcup", "\\uplus", "\\land", "\\lor", "\\wedge", "\\vee",
    "\\cup", "\\cap", "\\circ", "\\rtimes",
])
const RELATION_ATOM_COMMANDS = Set([
    "\\in", "\\notin", "\\ni", "\\owns", "\\notni", "\\subset", "\\subseteq",
    "\\subsetneq", "\\nsubseteq", "\\supset", "\\supseteq", "\\supsetneq",
    "\\nsupseteq", "\\sqsubset", "\\sqsubseteq", "\\sqsupset", "\\sqsupseteq",
    "\\to", "\\rightarrow", "\\leftarrow", "\\leftrightarrow", "\\uparrow",
    "\\downarrow", "\\updownarrow", "\\Rightarrow", "\\Leftarrow", "\\iff",
    "\\Leftrightarrow", "\\Uparrow", "\\Downarrow", "\\Updownarrow",
    "\\longleftarrow", "\\longrightarrow", "\\longleftrightarrow",
    "\\Longleftarrow", "\\Longrightarrow", "\\Longleftrightarrow",
    "\\hookleftarrow", "\\hookrightarrow", "\\nearrow", "\\searrow", "\\swarrow",
    "\\nwarrow", "\\leftharpoonup", "\\leftharpoondown", "\\rightharpoonup",
    "\\rightharpoondown", "\\rightleftharpoons", "\\leftrightharpoons", "\\leadsto",
    "\\mapsto", "\\leq", "\\le", "\\ge", "\\geq", "\\ll", "\\gg", "\\ne",
    "\\neq", "\\approx", "\\equiv", "\\propto", "\\prec", "\\succ", "\\preceq",
    "\\succeq", "\\sim", "\\simeq", "\\cong", "\\asymp", "\\doteq",
    "\\parallel", "\\nparallel", "\\mid", "\\nmid", "\\perp", "\\models",
    "\\vdash", "\\dashv", "\\bowtie", "\\smile", "\\frown", "\\therefore",
    "\\because",
])
const OPEN_ATOM_COMMANDS = Set(["\\lceil", "\\lfloor", "\\lvert", "\\lVert", "\\{"])
const CLOSE_ATOM_COMMANDS = Set(["\\rceil", "\\rfloor", "\\rvert", "\\rVert", "\\}"])

const NONBREAKING_SPACE = "\u00a0"

"""Build one ASCII-to-Unicode mathematical alphabet map from standard ranges."""
function build_math_alphabet_map(
    uppercase_start::Integer, lowercase_start::Integer, digit_start::Integer;
    exceptions::Dict{Char,Char}=Dict{Char,Char}())

    result = Dict{Char,Char}()
    for (source_start, target_start, count) in (
        ('A', uppercase_start, 26), ('a', lowercase_start, 26),
        ('0', digit_start, 10))
        target_start == 0 && continue
        for offset in 0:(count - 1)
            source = Char(Int(source_start) + offset)
            result[source] = get(exceptions, source, Char(target_start + offset))
        end
    end
    return result
end

const MATHBB_MAP = build_math_alphabet_map(0x1d538, 0x1d552, 0x1d7d8;
    exceptions=Dict(
        'C' => 'ℂ', 'H' => 'ℍ', 'N' => 'ℕ', 'P' => 'ℙ', 'Q' => 'ℚ',
        'R' => 'ℝ', 'Z' => 'ℤ'))
const MATHBF_MAP = build_math_alphabet_map(0x1d400, 0x1d41a, 0x1d7ce)
const MATHIT_MAP = build_math_alphabet_map(0x1d434, 0x1d44e, 0;
    exceptions=Dict('h' => 'ℎ'))
const MATHCAL_MAP = build_math_alphabet_map(0x1d49c, 0, 0;
    exceptions=Dict(
        'B' => 'ℬ', 'E' => 'ℰ', 'F' => 'ℱ', 'H' => 'ℋ', 'I' => 'ℐ',
        'L' => 'ℒ', 'M' => 'ℳ', 'R' => 'ℛ'))

const MATH_ALPHABET_COMMANDS = Dict(
    "\\mathbb" => (:mathbb, MATHBB_MAP),
    "\\mathbf" => (:mathbf, MATHBF_MAP),
    "\\mathit" => (:mathit, MATHIT_MAP),
    "\\mathcal" => (:mathcal, MATHCAL_MAP))
const MATH_ALPHABET_SOURCE_MAPS = Dict(
    role => Dict(glyph => source for (source, glyph) in mapping)
    for (_, (role, mapping)) in MATH_ALPHABET_COMMANDS)
const MATH_ALPHABET_ROLE_COMMANDS = Dict(
    role => command for (command, (role, _)) in MATH_ALPHABET_COMMANDS)
const COMMANDS_IGNORE_TRAILING_SPACE = Set([
    "\\angle",
    "\\measuredangle",
    "\\sphericalangle",
])

struct LatexToken
    kind::Symbol
    text::String
end

"""Semantic classification for one fixed math command."""
struct MathCommandSpec
    output::String
    role::Symbol
    atom_class::Int32
    operator_family::Int32
    operator_growth::Int32
    operator_limits::Int32
end

struct MathTableLength
    value::Float32
    unit::Symbol
end

struct MathTableSemanticDescriptor
    alignments::Vector{Char}
    boundary_gaps::Vector{MathTableLength}
    vertical_rule_counts::Vector{Int}
    row_extra_gaps::Vector{MathTableLength}
    horizontal_rule_counts::Vector{Int}
    cell_style::Symbol
    row_spacing::Symbol
end

struct LatexRun
    text::String
    role::Symbol
    segment::Symbol
    atom_class::Int32
    glue_kind::Int32
    children::Vector{LatexRun}
    secondary_children::Vector{LatexRun}
    table_descriptor::Union{Nothing,MathTableSemanticDescriptor}
end

"""Construct one non-table semantic run with no table descriptor."""
LatexRun(text::AbstractString, role::Symbol, segment::Symbol, atom_class::Int32,
    glue_kind::Int32, children::Vector{LatexRun}, secondary::Vector{LatexRun}) =
    LatexRun(String(text), role, segment, atom_class, glue_kind,
        children, secondary, nothing)

struct ParsedScript
    text::String
    was_grouped::Bool
    runs::Vector{LatexRun}
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
    operator_growth::Int32
    operator_limits::Int32
    style_role::Symbol
    atom_class::Int32
    glue_kind::Int32
    children::Vector{MathPayloadOp}
    secondary_children::Vector{MathPayloadOp}
    tertiary_children::Vector{MathPayloadOp}
    table_descriptor::Union{Nothing,MathTableSemanticDescriptor}

    function MathPayloadOp(parts::Tuple,
        descriptor::Union{Nothing,MathTableSemanticDescriptor})
        length(parts) == 16 || throw(ArgumentError("expected 16 base payload fields"))
        return new(parts..., descriptor)
    end
end

"""Construct one nontable payload from compact or explicit operator policies."""
function MathPayloadOp(parts...)
    if length(parts) == 14
        return MathPayloadOp((parts[1], parts[2], parts[3], parts[4], parts[5],
            parts[6], parts[7], parts[8], OPERATOR_GROWTH_NONE,
            OPERATOR_LIMITS_NONE, parts[9], parts[10], parts[11], parts[12],
            parts[13], parts[14]), nothing)
    end
    length(parts) == 16 || throw(ArgumentError("expected 14 or 16 payload fields"))
    return MathPayloadOp(parts, nothing)
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

const EMPTY_CHILD_RUNS = LatexRun[]

"""Return one atom run payload with explicit mathematical class."""
latex_atom_run(text::AbstractString, role::Symbol, atom_class::Int32=MATH_ATOM_ORD) =
    LatexRun(text, role, :atom, atom_class, MATH_GLUE_NONE,
        EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one explicit math-glue run with readable fallback text."""
latex_glue_run(text::AbstractString, glue_kind::Int32) =
    LatexRun(text, :math_upright, :glue, MATH_ATOM_NONE, glue_kind,
        EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

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

const BINARY_ATOM_CHARACTERS = Set("+-*/±∓×÷·∗⋆∙⋄⊕⊖⊗⊘⊙∖⊓⊔⊎∪∩")
const RELATION_ATOM_CHARACTERS = Set("=<>≤≥≠≪≫≺≻≼≽∼≃≅≈≡∝∈∉∋∌⊂⊆⊊⊈⊃⊇⊋⊉⊏⊑⊐⊒∥⊥⊨")
const OPEN_ATOM_CHARACTERS = Set("([{⌈⌊⟨")
const CLOSE_ATOM_CHARACTERS = Set(")]}⌉⌋⟩")
const PUNCT_ATOM_CHARACTERS = Set(",;")

"""Classify one scalar into its initial TeX atom class."""
function normal_math_atom_class(character::Char)
    character in BINARY_ATOM_CHARACTERS && return MATH_ATOM_BIN
    character in RELATION_ATOM_CHARACTERS && return MATH_ATOM_REL
    character in OPEN_ATOM_CHARACTERS && return MATH_ATOM_OPEN
    character in CLOSE_ATOM_CHARACTERS && return MATH_ATOM_CLOSE
    character in PUNCT_ATOM_CHARACTERS && return MATH_ATOM_PUNCT
    return MATH_ATOM_ORD
end

"""Append and clear one buffered normal-math atom run."""
function flush_normal_math_run!(runs::Vector{LatexRun}, current::IOBuffer,
    role::Symbol, atom_class::Int32)
    current.size == 0 && return nothing
    push!(runs, latex_atom_run(String(take!(current)), role, atom_class))
    return nothing
end

"""Split normal math by font role and atom class while discarding source whitespace."""
function normal_math_atom_runs(text::AbstractString)
    runs = LatexRun[]
    current_role = :none
    current_class = MATH_ATOM_NONE
    current = IOBuffer()
    for character in String(text)
        if character == only(NONBREAKING_SPACE)
            flush_normal_math_run!(runs, current, current_role, current_class)
            push!(runs, latex_glue_run(NONBREAKING_SPACE, MATH_GLUE_SPACE))
            current_role = :none
            current_class = MATH_ATOM_NONE
            continue
        end
        if isspace(character)
            flush_normal_math_run!(runs, current, current_role, current_class)
            push!(runs, latex_glue_run(string(character), MATH_GLUE_SOURCE))
            current_role = :none
            current_class = MATH_ATOM_NONE
            continue
        end
        role = normal_math_role(character)
        atom_class = normal_math_atom_class(character)
        if current_role != :none &&
                (role != current_role || atom_class != current_class)
            flush_normal_math_run!(runs, current, current_role, current_class)
        end
        current_role = role
        current_class = atom_class
        write(current, character)
    end
    flush_normal_math_run!(runs, current, current_role, current_class)
    return runs
end

"""Return the explicit TeX atom class for one fixed scalar command."""
function fixed_math_command_atom_class(command::String, fallback::Int32)
    command in BINARY_ATOM_COMMANDS && return MATH_ATOM_BIN
    command in RELATION_ATOM_COMMANDS && return MATH_ATOM_REL
    command in OPEN_ATOM_COMMANDS && return MATH_ATOM_OPEN
    command in CLOSE_ATOM_COMMANDS && return MATH_ATOM_CLOSE
    return fallback
end

"""Return one scalar command spec when output normalizes to one math atom."""
function scalar_math_command_spec(command::String, output::String)
    runs = normal_math_atom_runs(output)
    if length(runs) != 1 || runs[1].segment != :atom
        return nothing
    end
    run = runs[1]
    atom_class = fixed_math_command_atom_class(command, run.atom_class)
    return MathCommandSpec(output, run.role, atom_class, LARGE_OP_KIND_NONE,
        OPERATOR_GROWTH_NONE, OPERATOR_LIMITS_NONE)
end

"""Return the semantic run role for one registered large-operator family."""
function large_operator_role(family::Int32)
    family == LARGE_OP_KIND_SUM && return :largeop_sum
    family == LARGE_OP_KIND_PROD && return :largeop_prod
    family == LARGE_OP_KIND_INT && return :largeop_int
    family == LARGE_OP_KIND_LIM && return :largeop_lim
    return :largeop_nary
end

"""Return one fixed command spec for a semantic large operator."""
function large_math_command_spec(output::String, family::Int32)
    growth = family == LARGE_OP_KIND_LIM ?
        OPERATOR_GROWTH_NONE : OPERATOR_GROWTH_DISPLAY
    limits = family == LARGE_OP_KIND_INT ?
        OPERATOR_LIMITS_SIDE : OPERATOR_LIMITS_STACKED
    return MathCommandSpec(output, large_operator_role(family), MATH_ATOM_OP,
        family, growth, limits)
end

"""Build the fixed-command registry after scalar classification helpers are available."""
function build_math_command_registry()
    registry = Dict{String,MathCommandSpec}()
    for (command, output) in UNICODE_COMMAND_MAP
        spec = scalar_math_command_spec(command, output)
        !isnothing(spec) && (registry[command] = spec)
    end
    for command in TEXT_OPERATOR_COMMANDS
        registry[command] = MathCommandSpec(replace(command, "\\" => ""),
            :text, MATH_ATOM_OP, LARGE_OP_KIND_NONE,
            OPERATOR_GROWTH_NONE, OPERATOR_LIMITS_SIDE)
    end
    for (command, (output, family)) in LARGE_OPERATOR_COMMAND_MAP
        registry[command] = large_math_command_spec(output, family)
    end
    return registry
end

const MATH_COMMAND_REGISTRY = build_math_command_registry()

"""Return one superscript script run with recursive semantic children."""
latex_sup_run(text::AbstractString, children::Vector{LatexRun}) =
    LatexRun(text, :math, :script_sup, MATH_ATOM_NONE, MATH_GLUE_NONE,
    children, EMPTY_CHILD_RUNS)

"""Return one subscript script run with recursive semantic children."""
latex_sub_run(text::AbstractString, children::Vector{LatexRun}) =
    LatexRun(text, :math, :script_sub, MATH_ATOM_NONE, MATH_GLUE_NONE,
    children, EMPTY_CHILD_RUNS)

"""Return one overline accent run payload."""
latex_overline_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :accent_over, MATH_ATOM_ORD, MATH_GLUE_NONE,
        children, EMPTY_CHILD_RUNS)

"""Return one underline accent run payload."""
latex_underline_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :accent_under, MATH_ATOM_ORD, MATH_GLUE_NONE,
        children, EMPTY_CHILD_RUNS)

"""Return one recursive semantic glyph-accent run."""
latex_glyph_accent_run(accent::Symbol, children::Vector{LatexRun}) =
    LatexRun("", :math, accent, MATH_ATOM_ORD, MATH_GLUE_NONE,
        children, EMPTY_CHILD_RUNS)

"""Return one square-root run with recursive radicand and degree children."""
latex_sqrt_run(
    children::Vector{LatexRun}, degree_children::Vector{LatexRun}=LatexRun[]) =
    LatexRun(join(latex_run_serialized_text.(degree_children)), :math,
        :radical_sqrt, MATH_ATOM_ORD, MATH_GLUE_NONE, children, degree_children)

"""Return one fraction run payload with numerator and denominator child runs."""
latex_fraction_run(
    numerator_children::Vector{LatexRun}, denominator_children::Vector{LatexRun}) =
    LatexRun("", :math, :fraction, MATH_ATOM_INNER, MATH_GLUE_NONE,
        numerator_children, denominator_children)

"""Return one recursive style override around a scoped child run list."""
latex_style_override_run(style::Symbol, children::Vector{LatexRun}) =
    LatexRun("", style, :style_override, MATH_ATOM_INNER, MATH_GLUE_NONE,
        children, EMPTY_CHILD_RUNS)

"""Return one ruleless two-part stack semantic run."""
latex_stack_run(top::Vector{LatexRun}, bottom::Vector{LatexRun}) =
    LatexRun("", :math, :stack, MATH_ATOM_INNER, MATH_GLUE_NONE, top, bottom)

"""Return one top annotation over an unscaled base program."""
latex_overset_run(annotation::Vector{LatexRun}, base::Vector{LatexRun}) =
    LatexRun("", :math, :overset, MATH_ATOM_ORD, MATH_GLUE_NONE, annotation, base)

"""Return one bottom annotation under an unscaled base program."""
latex_underset_run(annotation::Vector{LatexRun}, base::Vector{LatexRun}) =
    LatexRun("", :math, :underset, MATH_ATOM_ORD, MATH_GLUE_NONE, base, annotation)

"""Return one stretch-delimiter run payload with left/right delimiters and inner runs."""
latex_stretch_delimiter_run(left::String, right::String, children::Vector{LatexRun}) =
    LatexRun(left, :math, :stretch_delimiter, MATH_ATOM_INNER, MATH_GLUE_NONE,
        children, [latex_atom_run(right, :math)])

"""Return one fixed-size delimiter with explicit atom class and size policy."""
latex_fixed_delimiter_run(delimiter::String, size::Int32, atom_class::Int32) =
    LatexRun(delimiter, Symbol("delimiter_size_" * string(size)),
        :fixed_delimiter, atom_class, MATH_GLUE_NONE,
        EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one middle delimiter whose size is resolved by its enclosing group."""
latex_middle_delimiter_run(delimiter::String) =
    LatexRun(delimiter, :delimiter_shared_extent, :middle_delimiter,
        MATH_ATOM_REL, MATH_GLUE_NONE, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return compact matrix dimension text for one matrix run."""
matrix_dims_text(rows::Int, cols::Int) = string(rows) * "," * string(cols)

"""Return one matrix-cell run payload wrapping child runs for a single cell."""
latex_matrix_cell_run(children::Vector{LatexRun}) =
    LatexRun("", :math, :matrix_cell, MATH_ATOM_INNER, MATH_GLUE_NONE,
        children, EMPTY_CHILD_RUNS)

"""Return one matrix run payload with row/column metadata and row-major cell runs."""
latex_matrix_run(rows::Int, cols::Int, cells::Vector{LatexRun}) =
    LatexRun(matrix_dims_text(rows, cols), :math, :matrix, MATH_ATOM_INNER,
        MATH_GLUE_NONE, cells, EMPTY_CHILD_RUNS)

"""Return one array run with typed row, column, gap, and rule metadata."""
latex_array_run(rows::Int, cols::Int, cells::Vector{LatexRun}, preamble::String,
    descriptor::MathTableSemanticDescriptor) =
    LatexRun(matrix_dims_text(rows, cols), :math, :array, MATH_ATOM_INNER,
        MATH_GLUE_NONE, cells, [latex_atom_run(preamble, :math)], descriptor)

"""Return one preset table run using the shared recursive matrix operation."""
latex_table_run(rows::Int, cols::Int, cells::Vector{LatexRun}, segment::Symbol,
    descriptor::MathTableSemanticDescriptor, metadata::String="") =
    LatexRun(matrix_dims_text(rows, cols), :math, segment, MATH_ATOM_INNER,
        MATH_GLUE_NONE, cells,
        isempty(metadata) ? EMPTY_CHILD_RUNS : [latex_atom_run(metadata, :math)],
        descriptor)
