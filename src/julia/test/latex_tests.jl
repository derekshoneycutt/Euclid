if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidLatex)
    include("../latex.jl")
end

using .EuclidLatex
using Test

const TEX_COMPLIANCE_BASELINE = [
    (category=:atom_spacing, source="a+b=c,\\;-a+b"),
    (category=:scripts, source="x_i^2+V_A"),
    (category=:fractions, source="\\frac{a+b}{c}"),
    (category=:operators, source="\\sum_{i=1}^{n}i+\\int_0^1f(x)\\,dx"),
    (category=:radicals, source="\\sqrt[n]{x+1}"),
    (category=:delimiters, source="\\left(\\frac{a}{b}\\right)"),
    (category=:matrices, source="\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}"),
    (category=:bars, source="\\overline{AB}+\\underline{CD}"),
    (category=:nesting, source="\\frac{1}{1+\\frac{1}{x^2}}"),
    (category=:fallback, source="\\unsupported{readable}"),
]

@testset "TeX compliance baseline corpus" begin
    for fixture in TEX_COMPLIANCE_BASELINE
        program = EuclidLatex.compiled_program_for(fixture.source)
        @test !isempty(program)
        @test !isempty(EuclidLatex.latex_to_plain_text(fixture.source))
    end
end

@testset "latex mode classification" begin
    @test EuclidLatex.classify_latex_mode("\\frac{1}{2}") == :math
    @test EuclidLatex.classify_latex_mode("\$\\alpha + 1\$") == :math
    @test EuclidLatex.classify_latex_mode("Value: \$x^2\$") == :document
    @test EuclidLatex.classify_latex_mode("\\textbf{Definition}") == :document
end

@testset "document mode parsing" begin
    runs = EuclidLatex.parse_latex_document(
        "\\textbf{Title} Plain \\textit{italic} and \$x^2\$.")
    @test runs !== nothing
    @test any(run -> run.kind == :math_inline && run.text == "x^2", runs)
    @test any(run -> run.kind == :text && run.text == "Title" &&
        run.font_flags == EuclidLatex.DOCUMENT_STYLE_REGULAR |
            EuclidLatex.DOCUMENT_STYLE_BOLD, runs)
    @test any(run -> run.kind == :text && run.text == "italic" &&
        run.font_flags == EuclidLatex.DOCUMENT_STYLE_REGULAR |
            EuclidLatex.DOCUMENT_STYLE_ITALIC, runs)

    nested = EuclidLatex.parse_latex_document("\\textbf{bold \\emph{and italic}}")
    @test nested !== nothing
    @test nested[end].font_flags == EuclidLatex.DOCUMENT_STYLE_REGULAR |
        EuclidLatex.DOCUMENT_STYLE_BOLD | EuclidLatex.DOCUMENT_STYLE_ITALIC
    multiline = EuclidLatex.parse_latex_document(
        "\\textbf{Heading}\n\nBody\n\n\$\$x + y\$\$\n\n\\textbf{Proof:} done.")
    @test multiline !== nothing
    @test count(run -> run.kind == :math_display, multiline) == 1
    delimited = EuclidLatex.parse_latex_document(
        "inline \\(x\\) then display \\[y\\]")
    @test delimited !== nothing
    @test [run.kind for run in delimited if startswith(String(run.kind), "math_")] ==
        [:math_inline, :math_display]
    slash_break = EuclidLatex.parse_latex_document("first\\\\\n    second")
    @test slash_break !== nothing
    @test [(run.kind, run.text) for run in slash_break] ==
        [(:text, "first"), (:line_break, ""), (:text, "second")]
    newline_break = EuclidLatex.parse_latex_document("first\\newline\n    second")
    @test newline_break !== nothing
    @test [(run.kind, run.text) for run in newline_break] ==
        [(:text, "first"), (:line_break, ""), (:text, "second")]
    paragraph_after_break = EuclidLatex.parse_latex_document("first\\\\\n\nsecond")
    @test paragraph_after_break !== nothing
    @test [(run.kind, run.text) for run in paragraph_after_break] ==
        [(:text, "first"), (:line_break, ""), (:line_break, ""), (:text, "second")]
    @test EuclidLatex.classify_latex_mode("first\\newline second") == :document
    shapes = EuclidLatex.parse_latex_document(
        "\\euclidpoint[color=steelblue,size=1] \\euclidline[length=4,thickness=2] " *
        "\\euclidcircle[color=khaki3,size=2,filled] " *
        "\\euclidbox[width=3,height=2,thickness=1,filled=false]")
    @test shapes !== nothing
    @test [run.shape.kind for run in shapes if run.kind == :shape] ==
        [:point, :line, :circle, :box]
    @test [run.shape.filled for run in shapes if run.kind == :shape] ==
        [true, false, true, false]
    @test EuclidLatex.classify_latex_mode("x \\euclidpoint y") == :document
    @test EuclidLatex.parse_latex_document("\\euclidpoint[color=not-a-color]") === nothing
    @test EuclidLatex.parse_latex_document("\\euclidline[size=2]") === nothing
    @test EuclidLatex.parse_latex_document("\\euclidcircle[size=0]") === nothing
    @test EuclidLatex.parse_latex_document("\\euclidbox[filled=maybe]") === nothing
    @test EuclidLatex.parse_latex_document("\\euclidpointless") === nothing
    @test EuclidLatex.parse_latex_document("broken \$math") === nothing
    @test EuclidLatex.parse_latex_document("\\section{unsupported}") === nothing
    @test EuclidLatex.parse_latex_document(EuclidLatex.LATEX_PRIME_DOCUMENT) !== nothing
end

@testset "document text colors" begin
    @test EuclidLatex.classify_latex_mode("\\textcolor{red}{alert}") == :document

    common = EuclidLatex.parse_latex_document("\\textcolor{green}{common}")
    @test common !== nothing
    @test only(common).color == OdinJuliaBridge.BridgeColor(0x00, 0xff, 0x00, 0xff)

    julia_palette = EuclidLatex.parse_latex_document(
        "\\textcolor{julia_blue}{blue} \\textcolor{julia_red}{red} " *
        "\\textcolor{julia_green}{green} \\textcolor{julia_purple}{purple}")
    @test julia_palette !== nothing
    colored_runs = [run for run in julia_palette if run.color !== nothing]
    @test [run.color for run in colored_runs] == [
        OdinJuliaBridge.bridge_color(:julia_blue),
        OdinJuliaBridge.bridge_color(:julia_red),
        OdinJuliaBridge.bridge_color(:julia_green),
        OdinJuliaBridge.bridge_color(:julia_purple),
    ]

    colors_symbol = EuclidLatex.parse_latex_document(
        "\\textcolor{steelblue}{Colors.jl}")
    @test colors_symbol !== nothing
    @test only(colors_symbol).color == OdinJuliaBridge.bridge_color(:steelblue)

    nested = EuclidLatex.parse_latex_document(
        "\\textcolor{julia_blue}{outer \\textbf{bold} " *
        "\\textcolor{not_a_color}{inherited}} default")
    @test nested !== nothing
    inherited_color = OdinJuliaBridge.bridge_color(:julia_blue)
    @test all(run -> run.color == inherited_color, nested[1:3])
    @test nested[2].font_flags == EuclidLatex.DOCUMENT_STYLE_REGULAR |
        EuclidLatex.DOCUMENT_STYLE_BOLD
    @test nested[end].color === nothing

    unknown_root = EuclidLatex.parse_latex_document(
        "\\textcolor{not_a_color}{context default}")
    @test unknown_root !== nothing
    @test only(unknown_root).color === nothing

    @test EuclidLatex.parse_latex_document("\\textcolor{}{empty}") === nothing
    @test EuclidLatex.parse_latex_document("\\textcolor{red}missing") === nothing
    @test EuclidLatex.parse_latex_document("\\textcolor{red}{unclosed") === nothing
end

@testset "unicode and text operators" begin
    plain = EuclidLatex.latex_to_plain_text("\\alpha + \\beta + \\sin(x)")
    @test plain == "α+β+sin(x)"

    circ_plain = EuclidLatex.latex_to_plain_text("f \\circ g")
    @test circ_plain == "f∘g"

    alias_plain = EuclidLatex.latex_to_plain_text("a \\ne b, x \\ge y")
    @test alias_plain == "a≠b,x≥y"

    symbol_plain = EuclidLatex.latex_to_plain_text(
        "1,2,\\dots,n; x \\mapsto y; A \\rtimes B")
    @test symbol_plain == "1,2,…,n;x↦y;A⋊B"

    spacing_plain = EuclidLatex.latex_to_plain_text("a\\;b")
    @test spacing_plain == "a b"

    greek_plain = EuclidLatex.latex_to_plain_text("\\varpi \\digamma")
    @test greek_plain == "ϖϝ"

    operator_plain = EuclidLatex.latex_to_plain_text(
        "\\mp \\ast \\star \\bullet \\oplus \\otimes \\setminus \\sqcap \\amalg")
    @test operator_plain == "∓∗⋆∙⊕⊗∖⊓⨿"

    relation_plain = EuclidLatex.latex_to_plain_text(
        "\\ll \\prec \\preceq \\sim \\simeq \\cong \\parallel \\perp \\models \\sqsubseteq \\ni")
    @test relation_plain == "≪≺≼∼≃≅∥⊥⊨⊑∋"

    logic_plain = EuclidLatex.latex_to_plain_text(
        "\\emptyset \\complement \\therefore \\because \\top \\bot")
    @test logic_plain == "∅∁∴∵⊤⊥"

    arrow_plain = EuclidLatex.latex_to_plain_text(
        "\\rightarrow \\leftrightarrow \\uparrow \\Uparrow \\longrightarrow " *
        "\\hookrightarrow \\leftharpoonup \\rightleftharpoons \\leadsto")
    @test arrow_plain == "→↔↑⇑⟶↪↼⇌⇝"

    notation_plain = EuclidLatex.latex_to_plain_text(
        "\\prime \\hbar \\ell \\Re \\Im \\wp \\angle \\triangle \\Box " *
        "\\Diamond \\clubsuit \\flat \\checkmark \\oint \\iint")
    @test notation_plain == "′ℏℓℜℑ℘∠△□◇♣♭✓∮∬"

    command_space_plain = EuclidLatex.latex_to_plain_text("\\angle ABC")
    @test command_space_plain == "∠ABC"

    command_escaped_space_plain = EuclidLatex.latex_to_plain_text("\\angle\\ ABC")
    @test command_escaped_space_plain == "∠ ABC"

    command_nonbreaking_space_plain = EuclidLatex.latex_to_plain_text("\\angle~ABC")
    @test command_nonbreaking_space_plain == "∠\u00a0ABC"

    program = EuclidLatex.compiled_program_for("\\sin(x)+x")
    @test length(program) == 6
    @test program[1].kind == EuclidLatex.MATH_OP_TEXT_RUN
    @test program[1].text == "sin"
    @test program[2].kind == EuclidLatex.MATH_OP_MATH_GLYPH_RUN
    @test program[2].text == "("
    @test program[2].style_role == :math_upright
    @test program[3].text == "x"
    @test program[3].style_role == :math_italic
    @test program[4].text == ")"
    @test program[4].style_role == :math_upright
    @test program[5].text == "+"
    @test program[6].text == "x"
    @test program[6].style_role == :math_italic
end

@testset "normal math semantic roles" begin
    program = EuclidLatex.compiled_program_for("Ax+Γα=2")
    @test [(op.text, op.style_role, op.atom_class) for op in program] == [
        ("Ax", :math_italic, EuclidLatex.MATH_ATOM_ORD),
        ("+", :math_upright, EuclidLatex.MATH_ATOM_BIN),
        ("Γ", :math_upright, EuclidLatex.MATH_ATOM_ORD),
        ("α", :math_italic, EuclidLatex.MATH_ATOM_ORD),
        ("=", :math_upright, EuclidLatex.MATH_ATOM_REL),
        ("2", :math_upright, EuclidLatex.MATH_ATOM_ORD),
    ]
    @test EuclidLatex.latex_to_plain_text("Ax+Γα=2") == "Ax+Γα=2"
end

@testset "math whitespace and explicit glue" begin
    compact = EuclidLatex.compiled_program_for("a+b=c")
    spaced = EuclidLatex.compiled_program_for(" a + b = c ")
    semantic_fields = program -> [(op.kind, op.text, op.style_role,
        op.atom_class, op.glue_kind) for op in program]
    @test semantic_fields(compact) == semantic_fields(spaced)

    explicit = EuclidLatex.compiled_program_for("a\\;b\\ c~d\\!e\\quad f\\,g")
    @test [op.glue_kind for op in explicit] == [
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_THICK,
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_SPACE,
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_SPACE,
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_NEGATIVE_THIN,
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_QUAD,
        EuclidLatex.MATH_GLUE_NONE,
        EuclidLatex.MATH_GLUE_THIN,
        EuclidLatex.MATH_GLUE_NONE,
    ]
end

@testset "text command and scripts" begin
    plain = EuclidLatex.latex_to_plain_text("\\text{Area }A_1^2")
    @test plain == "Area {A}^{2}_{1}"

    roman_plain = EuclidLatex.latex_to_plain_text("i+j \\mathrm{mod} n")
    @test roman_plain == "i+jmodn"

    continued = EuclidLatex.latex_to_plain_text("A_1^2 + \\mathbb{R}")
    @test continued == "{A}^{2}_{1}+ℝ"

    fallback = EuclidLatex.latex_to_plain_text("x_{ij}")
    @test fallback == "{x}_{ij}"

    canonical = EuclidLatex.latex_to_plain_text("x^2_1")
    @test canonical == "{x}^{2}_{1}"

    canonical_swapped = EuclidLatex.latex_to_plain_text("x_1^2")
    @test canonical_swapped == "{x}^{2}_{1}"
end

@testset "mathbb uppercase mapping" begin
    plain = EuclidLatex.latex_to_plain_text(
        "\\mathbb{A}\\mathbb{B}\\mathbb{C}\\mathbb{H}\\mathbb{N}\\mathbb{P}\\mathbb{Q}\\mathbb{R}\\mathbb{Y}\\mathbb{Z}")
    @test plain == "𝔸𝔹ℂℍℕℙℚℝ𝕐ℤ"

    unsupported = EuclidLatex.latex_to_plain_text("\\mathbb{a}")
    @test unsupported == "\\mathbb"
end

@testset "mathbb segmentation and style role" begin
    program = EuclidLatex.compiled_program_for("A + \\mathbb{R} + B")
    @test length(program) == 5
    @test program[1].kind == EuclidLatex.MATH_OP_MATH_GLYPH_RUN
    @test program[1].style_role == :math_italic
    @test program[3].kind == EuclidLatex.MATH_OP_MATH_GLYPH_RUN
    @test program[3].text == "ℝ"
    @test program[3].style_role == :mathbb
    @test program[5].kind == EuclidLatex.MATH_OP_MATH_GLYPH_RUN
    @test program[5].style_role == :math_italic
end

@testset "script attach emit program" begin
    program = EuclidLatex.compiled_program_for("A_1^2")
    @test length(program) == 1
    @test program[1].kind == EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test program[1].text == "A"
    @test program[1].sup_text == "2"
    @test program[1].sub_text == "1"
    @test program[1].style_role == :math_italic
    @test program[1].secondary_children[1].text == "2"
    @test program[1].tertiary_children[1].text == "1"

    mathbb_program = EuclidLatex.compiled_program_for("\\mathbb{R}_0")
    @test length(mathbb_program) == 1
    @test mathbb_program[1].kind == EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test mathbb_program[1].text == "ℝ"
    @test mathbb_program[1].sup_text == ""
    @test mathbb_program[1].sub_text == "0"
    @test mathbb_program[1].style_role == :mathbb

    recursive_parent_program = EuclidLatex.compiled_program_for("\\overline{AB}_1^2")
    @test length(recursive_parent_program) == 1
    @test recursive_parent_program[1].kind == EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test recursive_parent_program[1].sup_text == "2"
    @test recursive_parent_program[1].sub_text == "1"
    @test length(recursive_parent_program[1].children) == 1
    @test recursive_parent_program[1].children[1].kind ==
        EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE

    io = IOBuffer()
    _, bridge_ops = EuclidLatex.bridge_math_payload_preorder(
        program, io, Int32(1), Int32(2), Int32(3))
    @test bridge_ops[1].child_program_id == 1
    @test bridge_ops[1].secondary_child_program_id == 1
    @test bridge_ops[1].tertiary_child_program_id == 1
    @test bridge_ops[2].text_len == 1
    @test bridge_ops[3].text_len == 1
    @test bridge_ops[4].text_len == 1
end

@testset "large operators" begin
    plain_sum = EuclidLatex.latex_to_plain_text("\\sum_{i=1}^n i")
    @test plain_sum == "∑_{i=1}^{n}i"

    plain_prod = EuclidLatex.latex_to_plain_text("\\prod_{k=0}^{m} x_k")
    @test plain_prod == "∏_{k=0}^{m}{x}_{k}"

    plain_int = EuclidLatex.latex_to_plain_text("\\int_0^1 f(x)")
    @test plain_int == "∫_{0}^{1}f(x)"

    plain_lim = EuclidLatex.latex_to_plain_text("\\lim_{x \\to 0} f(x)")
    @test plain_lim == "lim_{x→0}f(x)"

    sum_program = EuclidLatex.compiled_program_for("\\sum_{i=1}^n i")
    @test length(sum_program) == 2
    @test sum_program[1].kind == EuclidLatex.MATH_OP_LARGE_OP_RECURSIVE
    @test sum_program[1].text == "∑"
    @test sum_program[1].sup_text == "n"
    @test sum_program[1].sub_text == "i=1"
    @test sum_program[1].large_op_kind == EuclidLatex.LARGE_OP_KIND_SUM
    @test sum_program[1].operator_growth == EuclidLatex.OPERATOR_GROWTH_DISPLAY
    @test sum_program[1].operator_limits == EuclidLatex.OPERATOR_LIMITS_STACKED
    @test sum_program[1].secondary_children[1].text == "n"
    @test EuclidLatex.plain_text_for_program(
        sum_program[1].tertiary_children) == "i=1"

    lim_program = EuclidLatex.compiled_program_for("\\lim_{x \\to 0} f(x)")
    @test length(lim_program) == 5
    @test lim_program[1].kind == EuclidLatex.MATH_OP_LARGE_OP_RECURSIVE
    @test lim_program[1].text == "lim"
    @test lim_program[1].sup_text == ""
    @test lim_program[1].sub_text == "x→0"
    @test lim_program[1].large_op_kind == EuclidLatex.LARGE_OP_KIND_LIM
    @test lim_program[1].operator_growth == EuclidLatex.OPERATOR_GROWTH_NONE
    @test lim_program[1].operator_limits == EuclidLatex.OPERATOR_LIMITS_STACKED

    int_program = EuclidLatex.compiled_program_for("\\int_0^1 f(x)")
    @test int_program[1].large_op_kind == EuclidLatex.LARGE_OP_KIND_INT
    @test int_program[1].operator_growth == EuclidLatex.OPERATOR_GROWTH_DISPLAY
    @test int_program[1].operator_limits == EuclidLatex.OPERATOR_LIMITS_SIDE
end

@testset "accent bars" begin
    over = EuclidLatex.latex_to_plain_text("\\overline{AB}")
    @test over == "\\overline{AB}"

    under = EuclidLatex.latex_to_plain_text("\\underline{CD}")
    @test under == "\\underline{CD}"

    nested = EuclidLatex.latex_to_plain_text("\\overline{\\underline{x}}")
    @test nested == "\\overline{\\underline{x}}"

    accent_program = EuclidLatex.compiled_program_for(
        "f(\\overline{AB}) + \\underline{CD}")
    @test length(accent_program) == 6
    @test accent_program[1].kind == EuclidLatex.MATH_OP_MATH_GLYPH_RUN
    @test accent_program[1].style_role == :math_italic
    @test accent_program[3].kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE
    @test accent_program[3].accent_mode == :overline
    @test length(accent_program[3].children) == 1
    @test accent_program[3].children[1].text == "AB"
    @test accent_program[6].kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE
    @test accent_program[6].accent_mode == :underline

    glyph_accents = EuclidLatex.compiled_program_for(
        "\\hat{x}+\\widehat{AB}+\\tilde{y}+\\vec{v}+\\dot{x}+\\ddot{x}+\\bar{z}")
    accent_modes = [op.accent_mode for op in glyph_accents if
        op.kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE]
    @test accent_modes == [:hat, :hat, :tilde, :vec, :dot, :ddot, :bar]
    hat_payload = EuclidLatex.bridge_math_block_payload(
        EuclidLatex.compiled_program_for("\\hat{x}");
        text_style=Int32(1), math_style=Int32(2), mathbb_style=Int32(3))
    hat_op = only(filter(op ->
        op.kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE, hat_payload.ops))
    @test hat_op.accent_mode == OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_HAT
    @test length(accent_program[6].children) == 1
    @test accent_program[6].children[1].text == "CD"

    embedded_scripts = EuclidLatex.compiled_program_for(
        "\\overline{AB^2} + \\underline{CD_4}")
    @test length(embedded_scripts) == 3
    @test embedded_scripts[1].kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE
    @test embedded_scripts[1].accent_mode == :overline
    @test length(embedded_scripts[1].children) == 1
    @test embedded_scripts[1].children[1].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test embedded_scripts[1].children[1].text == "AB"
    @test embedded_scripts[1].children[1].sup_text == "2"
    @test embedded_scripts[1].style_role == :math
    @test embedded_scripts[3].kind == EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE
    @test embedded_scripts[3].accent_mode == :underline
    @test length(embedded_scripts[3].children) == 1
    @test embedded_scripts[3].children[1].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test embedded_scripts[3].children[1].text == "CD"
    @test embedded_scripts[3].children[1].sub_text == "4"
    @test embedded_scripts[3].style_role == :math
end

@testset "radicals" begin
    plain = EuclidLatex.latex_to_plain_text("\\sqrt{x}")
    @test plain == "\\sqrt{x}"

    indexed = EuclidLatex.latex_to_plain_text("\\sqrt[3]{x}")
    @test indexed == "\\sqrt[3]{x}"

    indexed_unicode = EuclidLatex.latex_to_plain_text("\\sqrt[α]{AB}")
    @test indexed_unicode == "\\sqrt[α]{AB}"

    indexed_unicode_command = EuclidLatex.latex_to_plain_text("\\sqrt[\\alpha]{AB}")
    @test indexed_unicode_command == "\\sqrt[α]{AB}"

    scripted = EuclidLatex.latex_to_plain_text("\\sqrt{A_1^2}")
    @test scripted == "\\sqrt{{A}^{2}_{1}}"

    recursive_degree = EuclidLatex.latex_to_plain_text("\\sqrt[2n^3]{x}")
    @test recursive_degree == "\\sqrt[2n^3]{x}"
    degree_program = EuclidLatex.compiled_program_for("\\sqrt[2n^3]{x}")
    @test length(degree_program[1].secondary_children) == 2
    @test degree_program[1].secondary_children[2].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    degree_io = IOBuffer()
    _, degree_ops = EuclidLatex.bridge_math_payload_preorder(
        degree_program, degree_io, Int32(1), Int32(2), Int32(3))
    @test degree_ops[1].child_program_id == 1
    @test degree_ops[1].secondary_child_program_id == 2
    @test degree_ops[1].tertiary_child_program_id == 0

    radical_program = EuclidLatex.compiled_program_for("\\sqrt{AB} + \\sqrt{x^2}")
    @test length(radical_program) == 3
    @test radical_program[1].kind == EuclidLatex.MATH_OP_RADICAL_BAR_RECURSIVE
    @test radical_program[1].text == "AB"
    @test length(radical_program[1].children) == 1
    @test radical_program[1].children[1].text == "AB"
    @test radical_program[1].radical_mode == :sqrt
    @test radical_program[1].style_role == :math
    @test radical_program[3].kind == EuclidLatex.MATH_OP_RADICAL_BAR_RECURSIVE
    @test length(radical_program[3].children) == 1
    @test radical_program[3].children[1].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test radical_program[3].children[1].text == "x"
    @test radical_program[3].children[1].sup_text == "2"
    @test radical_program[3].style_role == :math

    indexed_program = EuclidLatex.compiled_program_for("\\sqrt[n]{A_1^2}")
    @test length(indexed_program) == 1
    @test indexed_program[1].kind == EuclidLatex.MATH_OP_RADICAL_BAR_RECURSIVE
    @test indexed_program[1].radical_index_text == "n"
    @test length(indexed_program[1].children) == 1
    @test indexed_program[1].children[1].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test indexed_program[1].children[1].text == "A"
    @test indexed_program[1].children[1].sup_text == "2"
    @test indexed_program[1].children[1].sub_text == "1"
    @test indexed_program[1].radical_mode == :nthroot
    @test indexed_program[1].style_role == :math

    radical_parent_program = EuclidLatex.compiled_program_for("\\sqrt{AB}_1^2")
    @test length(radical_parent_program) == 1
    @test radical_parent_program[1].kind == EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE
    @test radical_parent_program[1].sup_text == "2"
    @test radical_parent_program[1].sub_text == "1"
    @test length(radical_parent_program[1].children) == 1
    @test radical_parent_program[1].children[1].kind ==
        EuclidLatex.MATH_OP_RADICAL_BAR_RECURSIVE
end

@testset "fractions" begin
    plain_basic = EuclidLatex.latex_to_plain_text("\\frac{a}{b}")
    @test plain_basic == "{a}/{b}"

    plain_scripts = EuclidLatex.latex_to_plain_text("\\frac{x^2}{y_1}")
    @test plain_scripts == "{{x}^{2}}/{{y}_{1}}"

    plain_nested = EuclidLatex.latex_to_plain_text("\\frac{\\frac{a}{b}}{c}")
    @test plain_nested == "{{a}/{b}}/{c}"

    plain_mixed = EuclidLatex.latex_to_plain_text("\\frac{\\sqrt{x}}{\\overline{y}}")
    @test plain_mixed == "{\\sqrt{x}}/{\\overline{y}}"

    basic_program = EuclidLatex.compiled_program_for("\\frac{a}{b}")
    @test length(basic_program) == 1
    @test basic_program[1].kind == EuclidLatex.MATH_OP_FRACTION_RECURSIVE
    @test length(basic_program[1].children) == 1
    @test length(basic_program[1].secondary_children) == 1
    @test basic_program[1].children[1].text == "a"
    @test basic_program[1].secondary_children[1].text == "b"

    mixed_program = EuclidLatex.compiled_program_for("\\frac{\\sqrt{x}}{\\overline{y}}")
    @test length(mixed_program) == 1
    @test mixed_program[1].kind == EuclidLatex.MATH_OP_FRACTION_RECURSIVE
    @test length(mixed_program[1].children) == 1
    @test length(mixed_program[1].secondary_children) == 1
    @test mixed_program[1].children[1].kind == EuclidLatex.MATH_OP_RADICAL_BAR_RECURSIVE
    @test mixed_program[1].secondary_children[1].kind ==
        EuclidLatex.MATH_OP_ACCENT_BAR_RECURSIVE
end

@testset "stretch delimiters" begin
    plain_basic = EuclidLatex.latex_to_plain_text("\\left( x + y \\right)")
    @test plain_basic == "\\left(x+y\\right)"

    plain_mixed = EuclidLatex.latex_to_plain_text("\\left[ a + b \\right)")
    @test plain_mixed == "\\left[a+b\\right)"

    mixed_program = EuclidLatex.compiled_program_for("\\left[ a + b \\right)")
    @test length(mixed_program) == 1
    @test mixed_program[1].kind == EuclidLatex.MATH_OP_STRETCH_DELIMITER_RECURSIVE
    @test mixed_program[1].radical_index_text == "["
    @test mixed_program[1].sup_text == ")"

    plain_left_omit = EuclidLatex.latex_to_plain_text("\\left. x \\right)")
    @test plain_left_omit == "\\left.x\\right)"

    plain_right_omit = EuclidLatex.latex_to_plain_text("\\left( x \\right.")
    @test plain_right_omit == "\\left(x\\right."

    plain_nested = EuclidLatex.latex_to_plain_text(
        "\\left[ a + \\left( b \\right) \\right]")
    @test plain_nested == "\\left[a+\\left(b\\right)\\right]"

    plain_embedded = EuclidLatex.latex_to_plain_text(
        "\\left\\{ \\frac{a}{b} + \\sqrt{x} \\right\\}")
    @test plain_embedded == "\\left\\{{a}/{b}+\\sqrt{x}\\right\\}"

    structure_program = EuclidLatex.compiled_program_for("\\left( \\frac{a}{b} \\right)")
    @test length(structure_program) == 1
    @test structure_program[1].kind == EuclidLatex.MATH_OP_STRETCH_DELIMITER_RECURSIVE
    @test structure_program[1].radical_index_text == "("
    @test structure_program[1].sup_text == ")"
    @test any(op -> op.kind == EuclidLatex.MATH_OP_FRACTION_RECURSIVE,
        structure_program[1].children)

    unmatched_left = EuclidLatex.latex_to_plain_text("\\left( x")
    @test unmatched_left == "\\left(x\\right."

    unmatched_right = EuclidLatex.latex_to_plain_text("x \\right)")
    @test unmatched_right == "x\\right)"
end

@testset "matrix blocks" begin
    plain_square = EuclidLatex.latex_to_plain_text(
        "\\begin{matrix}a&b\\\\c&d\\end{matrix}")
    @test plain_square == "\\begin{matrix}a&b\\\\c&d\\end{matrix}"

    array_single = EuclidLatex.latex_to_plain_text("\\begin{array}{c}x\\end{array}")
    @test array_single == "\\begin{array}{c}x\\end{array}"

    array_rect = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cc}a&b\\\\c&d\\end{array}")
    @test array_rect == "\\begin{array}{cc}a&b\\\\c&d\\end{array}"

    array_formatted = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cccc}\n1 & 2 & 3 & 4 \\\\ \n5 & 6 & 7 & 8 \\\\ \n\\end{array}")
    @test array_formatted == "\\begin{array}{cccc}1&2&3&4\\\\5&6&7&8\\end{array}"

    array_with_trailing_row_sep = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cccc}1&2&3&4\\\\5&6&7&8\\\\\\end{array}")
    @test array_with_trailing_row_sep == "\\begin{array}{cccc}1&2&3&4\\\\5&6&7&8\\end{array}"

    array_trailing_sep = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cc}a&b\\\\c&d\\\\\\end{array}")
    @test array_trailing_sep == "\\begin{array}{cc}a&b\\\\c&d\\end{array}"

    matrix_trailing_sep = EuclidLatex.latex_to_plain_text(
        "\\begin{matrix}a&b\\\\c&d\\\\\\end{matrix}")
    @test matrix_trailing_sep == "\\begin{matrix}a&b\\\\c&d\\end{matrix}"

    array_trailing_row_break = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cc}a&b\\\\c&d\\\\\\end{array}")
    @test array_trailing_row_break == "\\begin{array}{cc}a&b\\\\c&d\\end{array}"

    plain_rect = EuclidLatex.latex_to_plain_text(
        "\\begin{matrix}x&y&z\\\\1&2&3\\end{matrix}")
    @test plain_rect == "\\begin{matrix}x&y&z\\\\1&2&3\\end{matrix}"

    bmatrix_plain = EuclidLatex.latex_to_plain_text(
        "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}")
    @test bmatrix_plain == "\\left[\\begin{matrix}a&b\\\\c&d\\end{matrix}\\right]"

    bmatrix_program = EuclidLatex.compiled_program_for(
        "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}")
    @test length(bmatrix_program) == 1
    @test bmatrix_program[1].kind == EuclidLatex.MATH_OP_STRETCH_DELIMITER_RECURSIVE
    @test bmatrix_program[1].radical_index_text == "["
    @test bmatrix_program[1].sup_text == "]"
    @test length(bmatrix_program[1].children) == 1
    @test bmatrix_program[1].children[1].kind == EuclidLatex.MATH_OP_MATRIX_RECURSIVE

    pmatrix_plain = EuclidLatex.latex_to_plain_text(
        "\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}")
    @test pmatrix_plain == "\\left(\\begin{matrix}a&b\\\\c&d\\end{matrix}\\right)"

    pmatrix_program = EuclidLatex.compiled_program_for(
        "\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}")
    @test length(pmatrix_program) == 1
    @test pmatrix_program[1].kind == EuclidLatex.MATH_OP_STRETCH_DELIMITER_RECURSIVE
    @test pmatrix_program[1].radical_index_text == "("
    @test pmatrix_program[1].sup_text == ")"
    @test length(pmatrix_program[1].children) == 1
    @test pmatrix_program[1].children[1].kind == EuclidLatex.MATH_OP_MATRIX_RECURSIVE

    vmatrix_plain = EuclidLatex.latex_to_plain_text(
        "\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}")
    @test vmatrix_plain == "\\left|\\begin{matrix}a&b\\\\c&d\\end{matrix}\\right|"

    vmatrix_program = EuclidLatex.compiled_program_for(
        "\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}")
    @test length(vmatrix_program) == 1
    @test vmatrix_program[1].kind == EuclidLatex.MATH_OP_STRETCH_DELIMITER_RECURSIVE
    @test vmatrix_program[1].radical_index_text == "|"
    @test vmatrix_program[1].sup_text == "|"
    @test length(vmatrix_program[1].children) == 1
    @test vmatrix_program[1].children[1].kind == EuclidLatex.MATH_OP_MATRIX_RECURSIVE

    matrix_program = EuclidLatex.compiled_program_for(
        "\\begin{matrix}a&\\frac{1}{2}\\\\c&d_1\\end{matrix}")
    @test length(matrix_program) == 1
    @test matrix_program[1].kind == EuclidLatex.MATH_OP_MATRIX_RECURSIVE
    @test matrix_program[1].radical_index_text == "2"
    @test matrix_program[1].sup_text == "2"
    @test length(matrix_program[1].children) == 4
    @test matrix_program[1].children[2].kind == EuclidLatex.MATH_OP_FRACTION_RECURSIVE
    @test matrix_program[1].children[4].kind ==
        EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE

    array_program = EuclidLatex.compiled_program_for(
        "\\begin{array}{cc}a&\\frac{1}{2}\\\\c&d_1\\end{array}")
    @test length(array_program) == 1
    @test array_program[1].kind == EuclidLatex.MATH_OP_MATRIX_RECURSIVE
    @test array_program[1].radical_index_text == "2"
    @test array_program[1].sup_text == "2"
    @test array_program[1].sub_text == "cc"
    @test array_program[1].text == "\\begin{array}{cc}a&\\frac{1}{2}\\\\c&d_1\\end{array}"
    @test length(array_program[1].children) == 4
    @test array_program[1].children[2].kind == EuclidLatex.MATH_OP_FRACTION_RECURSIVE
    @test array_program[1].children[4].kind == EuclidLatex.MATH_OP_SCRIPT_ATTACH_RECURSIVE

    array_program_mixed = EuclidLatex.compiled_program_for(
        "\\begin{array}{l c r}a&b&c\\end{array}")
    @test length(array_program_mixed) == 1
    @test array_program_mixed[1].sub_text == "lcr"

    @test matrix_program[1].sub_text == ""

    malformed = EuclidLatex.latex_to_plain_text("\\begin{matrix}a&b\\\\c\\end{matrix}")
    @test malformed == "\\begin"

    malformed_array = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{cx}a&b\\\\c&d\\end{array}")
    @test malformed_array == "\\begin"

    malformed_array_mismatch = EuclidLatex.latex_to_plain_text(
        "\\begin{array}{c}a&b\\end{array}")
    @test malformed_array_mismatch == "\\begin"
end

