package dynview_parse

TEX_DOCUMENT_STYLE_REGULAR :: i32(4)
TEX_DOCUMENT_STYLE_BOLD :: i32(32)
TEX_DOCUMENT_STYLE_ITALIC :: i32(1)

// Distinguish standalone math from complete semantic documents.
Tex_Source_Mode :: enum {
    Math,
    Document,
}

// Describe one recognized document math delimiter pair.
Tex_Document_Math_Delimiters :: struct {
    opener: string,
    closer: string,
    is_inline: bool,
    present: bool,
}

// Describe one recognized Euclid shape command.
Tex_Document_Shape_Command :: struct {
    kind: Tex_Document_Shape_Kind,
    text: string,
    present: bool,
}

// Describe one complete outer math fragment.
Tex_Document_Whole_Math :: struct {
    content: string,
    style: Tex_Math_Root_Style,
    present: bool,
}

// Identify one supported prose alignment environment during recursive parsing.
Tex_Document_Environment :: enum u8 {
    None,
    Center,
    Flush_Left,
    Flush_Right,
    Quote,
    Quotation,
    Itemize,
    Enumerate,
    Description,
}

// Carry inherited prose style and one recursive sequence terminator.
Tex_Document_Parse_Context :: struct {
    font_flags: i32,
    color: Tex_Document_Color,
    environment: Tex_Document_Environment,
    container_kind: Tex_Document_Container_Kind,
    container_depth: u8,
    left_margin_levels: u8,
    right_margin_levels: u8,
    suppress_first_indent: bool,
    stop_on_brace: bool,
    stop_on_bracket: bool,
    inline_only: bool,
}

// Preserve parser-owned formatting and list state across one nested environment.
Tex_Document_Environment_State :: struct {
    alignment: Tex_Document_Alignment,
    format: Tex_Document_Format,
    quotation_first: bool,
    item_started: bool,
    item_first: bool,
    item_block_start: int,
}

// Track bounded recursive document parsing without allocation.
Tex_Document_Parser :: struct {
    source: string,
    offset: int,
    work_count: int,
    depth: int,
    active_paragraph: int,
    paragraph_alignment: Tex_Document_Alignment,
    pending_no_indent: bool,
    paragraph_format: Tex_Document_Format,
    quotation_first_paragraph: bool,
    next_list_id: u16,
    list_item_started: bool,
    list_item_first_block: bool,
    list_item_block_start: int,
    description_label_active: bool,
    limits: Tex_Parse_Limits,
    output: ^Tex_Semantic_Output,
}

// Tex_Document_Math_Input describes one parsed math run awaiting publication.
Tex_Document_Math_Input :: struct {
    text: Tex_Text_Span,
    color: Tex_Document_Color,
    root_style: Tex_Math_Root_Style,
    math_program, source_start: int,
    is_inline: bool,
}

//   Classify one source using the frozen document-marker heuristic.
tex_classify_source_mode :: proc(source: string) -> Tex_Source_Mode {
    text := tex_document_trim(source)
    if tex_document_whole_math(text).present ||
        tex_source_starts_math_environment(text) {
        return .Math
    }
    markers := [?]string{
        "\\textbf{", "\\textit{", "\\emph{", "\\textcolor{",
        "\\textnormal{", "\\texttt{", "\\bfseries", "\\itshape",
        "\\begin{", "\\noindent", "\\newline", "\\par", "\\euclid",
        "\\%", "\\#", "\\_", "\\&", "\\{", "\\}", "\\ ",
        "\\\\", "$", "\\(", "\\[", "~", "%",
    }
    for marker in markers {
        if tex_document_contains(text, marker) {
            return .Document
        }
    }
    return .Math
}

// Report whether source starts with a matrix-like environment valid only in math mode.
tex_source_starts_math_environment :: proc(source: string) -> bool {
    prefix := "\\begin{"
    if len(source) <= len(prefix) || source[:len(prefix)] != prefix {
        return false
    }
    close := tex_document_find(source, "}", len(prefix))
    if close < 0 {return false}
    return tex_table_environment_supported(source[len(prefix):close])
}

//   Parse a complete document transaction into bounded semantic blocks and inlines.
tex_parse_document :: proc(
    source: string,
    output: ^Tex_Semantic_Output,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> Tex_Parse_Status {
    if !tex_semantic_output_init(output) {
        return .Work_Limit
    }
    parser := Tex_Document_Parser{
        source = source,
        active_paragraph = -1,
        paragraph_alignment = .Left,
        paragraph_format = {alignment = .Left},
        output = output,
        limits = limits,
    }
    status := tex_document_validate_source(&parser)
    if status == .Ok {
        status = tex_document_parse_sequence(&parser, {
            font_flags = TEX_DOCUMENT_STYLE_REGULAR,
        })
    }
    if status == .Ok {
        tex_document_close_paragraph(&parser)
    }
    output.status = status
    output.error_offset = parser.offset
    if status != .Ok {
        output.document_block_count = 0
        output.document_inline_count = 0
        output.document_display_row_count = 0
    }
    return status
}

//   Validate source bytes and admission limits before semantic mutation.
tex_document_validate_source :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Parse_Status {
    if len(parser.source) > parser.limits.source_bytes {
        return .Source_Too_Large
    }
    offset := 0
    for offset < len(parser.source) {
        width := tex_utf8_sequence_width(parser.source, offset)
        if width == 0 {
            parser.offset = offset
            return .Invalid_Utf8
        }
        offset += width
    }
    return .Ok
}

// Consume one closing token or environment terminator when present.
tex_document_parse_sequence_end :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> (Tex_Parse_Status, bool) {
    if parser.source[parser.offset] == '}' {
        parser.offset += 1
        status := Tex_Parse_Status.Ok if parse_ctx.stop_on_brace else .Unexpected_Token
        return status, true
    }
    if parser.description_label_active && parser.source[parser.offset] == ']' {
        if !parse_ctx.stop_on_bracket {return .Unexpected_Token, true}
        parser.offset += 1
        return .Ok, true
    }
    if tex_document_environment_ends(parser, parse_ctx.environment) {
        tex_document_close_paragraph(parser)
        tex_document_consume_environment_end(parser, parse_ctx.environment)
        return .Ok, true
    }
    return .Ok, false
}

//   Parse runs recursively through source end or one required closing brace.
tex_document_parse_sequence :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    if parser.depth >= parser.limits.depth {
        return .Work_Limit
    }
    parse_ctx := inherited
    parser.depth += 1
    defer parser.depth -= 1
    for parser.offset < len(parser.source) {
        if !tex_document_charge(parser) {
            return .Work_Limit
        }
        end_status, ended := tex_document_parse_sequence_end(parser, parse_ctx)
        if ended {return end_status}
        if parser.source[parser.offset] == '{' {
            status := tex_document_parse_group(parser, parse_ctx)
            if status != .Ok {return status}
        } else if !tex_document_parse_declaration(parser, &parse_ctx) {
            status := tex_document_parse_run(parser, parse_ctx)
            if status != .Ok {return status}
        }
    }
    return .Unclosed_Group if parse_ctx.stop_on_brace || parse_ctx.stop_on_bracket ||
        parse_ctx.environment != .None else .Ok
}

// Parse one bare brace group while preserving value-scoped declarations.
tex_document_parse_group :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    parser.offset += 1
    nested := inherited
    nested.stop_on_brace = true
    nested.stop_on_bracket = false
    return tex_document_parse_sequence(parser, nested)
}

// Parse one display, environment, or list-item structural run when present.
tex_document_parse_structural_run :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> (Tex_Parse_Status, bool) {
    display_info := tex_document_display_info(parser)
    if display_info.kind != .Plain {
        if parse_ctx.inline_only {return .Unexpected_Token, true}
        status := tex_document_parse_display_environment(
            parser, display_info, parse_ctx.color)
        return status, true
    }
    environment := tex_document_environment_starts(parser)
    if environment != .None {
        if parse_ctx.inline_only {return .Unexpected_Token, true}
        return tex_document_parse_environment(parser, parse_ctx, environment), true
    }
    if tex_document_command_starts(parser, "\\item") {
        if parse_ctx.inline_only {return .Unexpected_Token, true}
        return tex_document_parse_list_item(parser, parse_ctx), true
    }
    return .Ok, false
}

//   Parse one styled, colored, shape, math, break, or prose run.
tex_document_parse_run :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    structural_status, structural := tex_document_parse_structural_run(
        parser, parse_ctx)
    if structural {return structural_status}
    style_status, style_handled := tex_document_parse_style_command(
        parser, parse_ctx)
    if style_handled {return style_status}
    if tex_document_starts(parser, "\\textcolor{") {
        return tex_document_parse_color(
            parser, parse_ctx.font_flags, parse_ctx.color)
    }
    shape_command := tex_document_shape_command(parser)
    if shape_command.present {
        if parse_ctx.inline_only {return .Unexpected_Token}
        return tex_document_parse_shape(parser, parse_ctx.font_flags, parse_ctx.color,
            shape_command.kind, shape_command.text)
    }
    if tex_document_math_delimiters(parser).present {
        return tex_document_parse_math_run(parser, parse_ctx.color)
    }
    return tex_document_parse_prose_or_break(
        parser, parse_ctx.font_flags, parse_ctx.color, parse_ctx.inline_only)
}


// Parse one scoped prose style command when the current source begins one.
tex_document_parse_style_command :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> (Tex_Parse_Status, bool) {

    if tex_document_starts(parser, "\\textbf{") {
        return tex_document_parse_nested_style(
            parser, parse_ctx, "\\textbf{", TEX_DOCUMENT_STYLE_BOLD, false), true
    }
    if tex_document_starts(parser, "\\textit{") ||
        tex_document_starts(parser, "\\emph{") {
        command := "\\textit{" if tex_document_starts(
            parser, "\\textit{") else "\\emph{"
        return tex_document_parse_nested_style(
            parser, parse_ctx, command, TEX_DOCUMENT_STYLE_ITALIC, false), true
    }
    if tex_document_starts(parser, "\\textnormal{") {
        return tex_document_parse_nested_style(parser, parse_ctx,
            "\\textnormal{", TEX_DOCUMENT_STYLE_REGULAR, true), true
    }
    if tex_document_starts(parser, "\\texttt{") {
        return tex_document_parse_nested_style(
            parser, parse_ctx, "\\texttt{", 0, false), true
    }
    if tex_document_starts(parser, "\\textrm{") ||
        tex_document_starts(parser, "\\textsc{") {
        return .Unexpected_Token, true
    }
    return .Ok, false
}

// Parse one braced style scope after applying its font flag policy.
tex_document_parse_nested_style :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context,
    command: string,
    font_flags: i32,
    replace_flags: bool) -> Tex_Parse_Status {

    parser.offset += len(command)
    nested := parse_ctx
    if replace_flags {
        nested.font_flags = font_flags
    } else {
        nested.font_flags |= font_flags
    }
    nested.stop_on_brace = true
    nested.stop_on_bracket = false
    return tex_document_parse_sequence(parser, nested)
}

//   Parse one nested text-color command with unresolved-name inheritance.
tex_document_parse_color :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    inherited: Tex_Document_Color) -> Tex_Parse_Status {
    parser.offset += len("\\textcolor")
    name, ok := tex_document_take_group_source(parser)
    if !ok || parser.offset >= len(parser.source) ||
        parser.source[parser.offset] != '{' {
        return .Unexpected_Token
    }
    color, resolved := tex_document_resolve_color(tex_document_trim(name))
    if !resolved {
        color = inherited
    }
    parser.offset += 1
    return tex_document_parse_sequence(parser, {
        font_flags = font_flags, color = color, stop_on_brace = true,
        inline_only = parser.description_label_active,
    })
}

//   Parse and append one validated Euclid inline shape.
tex_document_parse_shape :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    shape_kind: Tex_Document_Shape_Kind,
    command: string) -> Tex_Parse_Status {
    source_start := parser.offset
    parser.offset += len(command)
    shape, ok := tex_document_parse_shape_options(parser, shape_kind)
    if !ok {
        return .Unexpected_Token
    }
    return tex_document_append_paragraph_inline(parser, {
        kind = .Shape,
        source = {source_start, parser.offset - source_start},
        font_flags = font_flags,
        color = color,
        shape = shape,
        math_program = -1,
    })
}

//   Parse one trimmed inline or display math fragment into semantic structure.
tex_document_parse_math_run :: proc(
    parser: ^Tex_Document_Parser,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    source_start := parser.offset
    delimiters := tex_document_math_delimiters(parser)
    content_start := parser.offset + len(delimiters.opener)
    close_offset := tex_document_find(
        parser.source, delimiters.closer, content_start)
    if close_offset < 0 {
        return .Unexpected_Token
    }
    content := tex_document_trim(parser.source[content_start:close_offset])
    if len(content) == 0 {
        return .Unexpected_Token
    }
    parser.offset = close_offset + len(delimiters.closer)
    style := Tex_Math_Root_Style.Display
    if delimiters.is_inline {
        style = .Text
    }
    program, status := tex_parse_math_fragment(
        content, style, parser.output, parser.limits)
    if status != .Ok {
        return status
    }
    span, span_ok := tex_semantic_append_text(parser.output, content)
    if !span_ok {
        return .Work_Limit
    }
    return tex_document_append_semantic_math(parser, {
        text = span, color = color, root_style = style,
        math_program = program, source_start = source_start,
        is_inline = delimiters.is_inline,
    })
}

//   Append parsed math to its semantic paragraph or display block.
tex_document_append_semantic_math :: proc(
    parser: ^Tex_Document_Parser,
    input: Tex_Document_Math_Input) -> Tex_Parse_Status {
    item := Tex_Document_Inline{
        kind = .Math,
        source = {input.source_start, parser.offset-input.source_start},
        text = input.text,
        color = input.color,
        root_style = input.root_style,
        math_program = input.math_program,
    }
    if input.is_inline {
        return tex_document_append_paragraph_inline(parser, item)
    }
    tex_document_close_paragraph(parser)
    block_index := tex_semantic_append_document_block(parser.output, {
        kind = .Display,
        inline_start = parser.output.document_inline_count,
        source = item.source,
        format = tex_document_block_format(parser, .Center),
    })
    if block_index < 0 ||
        !tex_semantic_append_document_inline(parser.output, block_index, item) {
        return .Work_Limit
    }
    return .Ok
}

//   Parse source newlines, forced breaks, ordinary prose, or reject commands.
tex_document_parse_prose_or_break :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    inline_only: bool = false) -> Tex_Parse_Status {
    control_status, handled := tex_document_parse_prose_control(
        parser, font_flags, color)
    if handled {return control_status}
    break_status, break_handled := tex_document_parse_break_control(
        parser, font_flags, color, inline_only)
    if break_handled {return break_status}
    if parser.source[parser.offset] == '\\' ||
        parser.source[parser.offset] == '$' {
        return .Unexpected_Token
    }
    return tex_document_parse_text(parser, font_flags, color)
}

// Parse one explicit forced-break command when present.
tex_document_parse_forced_break_control :: proc(
    parser: ^Tex_Document_Parser,
    inline_only: bool) -> (Tex_Parse_Status, bool) {
    command_length := 0
    if tex_document_starts(parser, "\\\\") {
        command_length = 2
    } else if tex_document_command_starts(parser, "\\newline") {
        command_length = len("\\newline")
    } else {
        return .Ok, false
    }
    if inline_only {return .Unexpected_Token, true}
    source_start := parser.offset
    parser.offset += command_length
    tex_document_consume_break_whitespace(parser)
    return tex_document_append_forced_break(parser, source_start), true
}

// Parse a prose newline or explicit paragraph and line-break command when present.
tex_document_parse_break_control :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    inline_only: bool) -> (Tex_Parse_Status, bool) {

    if parser.source[parser.offset] == '\n' {
        return tex_document_parse_newlines(
            parser, font_flags, color, inline_only), true
    }
    forced_status, forced := tex_document_parse_forced_break_control(
        parser, inline_only)
    if forced {return forced_status, true}
    if tex_document_command_starts(parser, "\\par") {
        if inline_only {return .Unexpected_Token, true}
        parser.offset += len("\\par")
        tex_document_close_paragraph(parser)
        return .Ok, true
    }
    if tex_document_command_starts(parser, "\\noindent") {
        if inline_only {return .Unexpected_Token, true}
        if parser.active_paragraph >= 0 {
            return .Unexpected_Token, true
        }
        parser.offset += len("\\noindent")
        parser.pending_no_indent = true
        return .Ok, true
    }
    return .Ok, false
}

// Parse a prose comment, escaped special, or controlled-space symbol when present.
tex_document_parse_prose_control :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> (Tex_Parse_Status, bool) {

    if parser.source[parser.offset] == '%' {
        tex_document_consume_comment(parser)
        return .Ok, true
    }
    if tex_document_is_escaped_special(parser) {
        return tex_document_parse_escaped_special(
            parser, font_flags, color), true
    }
    if !tex_document_starts(parser, "\\ ") {return .Ok, false}
    source_start := parser.offset
    parser.offset += 2
    return tex_document_append_semantic_space(
        parser, {source_start, 2}, .Controlled, font_flags, color), true
}

//   Normalize one source newline run to a space or a blank line.
tex_document_parse_newlines :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    inline_only: bool = false) -> Tex_Parse_Status {
    source_start := parser.offset
    newline_count := 0
    for parser.offset < len(parser.source) &&
        tex_math_ascii_space(parser.source[parser.offset]) {
        if parser.source[parser.offset] == '\n' {
            newline_count += 1
        }
        parser.offset += 1
    }
    if newline_count < 2 {
        if parser.active_paragraph < 0 {
            return .Ok
        }
        return tex_document_append_semantic_space(parser,
            {source_start, parser.offset - source_start},
            .Breakable, font_flags, color)
    }
    if inline_only {return .Unexpected_Token}
    tex_document_close_paragraph(parser)
    return .Ok
}

//   Parse ordinary document bytes up to the next syntax character.
tex_document_parse_text :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := parser.offset
    for parser.offset < len(parser.source) {
        value := parser.source[parser.offset]
        if value == '\\' || value == '$' || value == '{' || value == '}' ||
            parser.description_label_active && value == ']' ||
            value == '%' || value == '\n' {
            break
        }
        width := tex_utf8_sequence_width(parser.source, parser.offset)
        parser.offset += width
    }
    text := parser.source[start:parser.offset]
    status := tex_document_append_semantic_prose(
        parser, text, start, font_flags, color)
    if status != .Ok {
        return status
    }
    return .Ok
}

//   Lower one prose source span to text and semantic space nodes.
tex_document_append_semantic_prose :: proc(
    parser: ^Tex_Document_Parser,
    text: string,
    source_start: int,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := 0
    for index := 0; index < len(text); {
        if text[index] == '~' {
            status := tex_document_append_semantic_text_span(
                parser, text[start:index], source_start + start, font_flags, color)
            if status != .Ok {return status}
            status = tex_document_append_semantic_space(
                parser, {source_start + index, 1}, .Nonbreaking, font_flags, color)
            if status != .Ok {return status}
            index += 1
            start = index
            continue
        }
        if tex_math_ascii_space(text[index]) {
            status := tex_document_append_semantic_text_span(
                parser, text[start:index], source_start + start, font_flags, color)
            if status != .Ok {return status}
            space_start := index
            for index < len(text) && tex_math_ascii_space(text[index]) {index += 1}
            status = tex_document_append_semantic_space(parser,
                {source_start + space_start, index - space_start},
                .Breakable, font_flags, color)
            if status != .Ok {return status}
            start = index
            continue
        }
        index += tex_utf8_sequence_width(text, index)
    }
    return tex_document_append_semantic_text_span(
        parser, text[start:], source_start + start, font_flags, color)
}

//   Append one semantic text node with its canonical bytes and source range.
tex_document_append_semantic_text_span :: proc(
    parser: ^Tex_Document_Parser,
    text: string,
    source_start: int,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if len(text) == 0 {return .Ok}
    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok {return .Work_Limit}
    return tex_document_append_paragraph_inline(parser, {
        kind = .Text,
        source = {source_start, len(text)},
        text = span,
        font_flags = font_flags,
        color = color,
        math_program = -1,
    })
}

//   Append one semantic spacing node without assigning physical dimensions.
tex_document_append_semantic_space :: proc(
    parser: ^Tex_Document_Parser,
    source: Tex_Source_Span,
    kind: Tex_Document_Space_Kind,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 && kind == .Breakable {
        return .Ok
    }
    text, ok := tex_semantic_append_text(parser.output, " ")
    if !ok {return .Work_Limit}
    return tex_document_append_paragraph_inline(parser, {
        kind = .Space,
        source = source,
        text = text,
        font_flags = font_flags,
        color = color,
        space_kind = kind,
        math_program = -1,
    })
}

//   Append an inline to the current paragraph, opening one when necessary.
tex_document_append_paragraph_inline :: proc(
    parser: ^Tex_Document_Parser,
    item: Tex_Document_Inline) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 {
        parser.active_paragraph = tex_semantic_append_document_block(
            parser.output, {
                kind = .Paragraph,
                inline_start = parser.output.document_inline_count,
                source = {item.source.offset, 0},
                format = tex_document_block_format(
                    parser, parser.paragraph_alignment),
            })
        if parser.active_paragraph >= 0 && parser.list_item_first_block {
            parser.list_item_first_block = false
        }
        parser.pending_no_indent = false
    }
    if parser.active_paragraph < 0 || !tex_semantic_append_document_inline(
        parser.output, parser.active_paragraph, item) {
        return .Work_Limit
    }
    return .Ok
}

// Apply one scoped declaration to the remainder of the current group.
tex_document_parse_declaration :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: ^Tex_Document_Parse_Context) -> bool {

    if tex_document_command_starts(parser, "\\bfseries") {
        parser.offset += len("\\bfseries")
        parse_ctx.font_flags |= TEX_DOCUMENT_STYLE_BOLD
        return true
    }
    if tex_document_command_starts(parser, "\\itshape") {
        parser.offset += len("\\itshape")
        parse_ctx.font_flags |= TEX_DOCUMENT_STYLE_ITALIC
        return true
    }
    return false
}

// Return the alignment environment beginning at the current source offset.
tex_document_environment_starts :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Environment {

    if tex_document_starts(parser, "\\begin{center}") {return .Center}
    if tex_document_starts(parser, "\\begin{flushleft}") {return .Flush_Left}
    if tex_document_starts(parser, "\\begin{flushright}") {return .Flush_Right}
    if tex_document_starts(parser, "\\begin{quote}") {return .Quote}
    if tex_document_starts(parser, "\\begin{quotation}") {return .Quotation}
    if tex_document_starts(parser, "\\begin{itemize}") {return .Itemize}
    if tex_document_starts(parser, "\\begin{enumerate}") {return .Enumerate}
    if tex_document_starts(parser, "\\begin{description}") {return .Description}
    return .None
}

// Return the exact source spelling for one supported alignment environment.
tex_document_environment_name :: proc(environment: Tex_Document_Environment) -> string {
    switch environment {
    case .Center: return "center"
    case .Flush_Left: return "flushleft"
    case .Flush_Right: return "flushright"
    case .Quote: return "quote"
    case .Quotation: return "quotation"
    case .Itemize: return "itemize"
    case .Enumerate: return "enumerate"
    case .Description: return "description"
    case .None: return ""
    }
    return ""
}

// Report whether the current source closes the active alignment environment.
tex_document_environment_ends :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) -> bool {

    switch environment {
    case .Center: return tex_document_starts(parser, "\\end{center}")
    case .Flush_Left: return tex_document_starts(parser, "\\end{flushleft}")
    case .Flush_Right: return tex_document_starts(parser, "\\end{flushright}")
    case .Quote: return tex_document_starts(parser, "\\end{quote}")
    case .Quotation: return tex_document_starts(parser, "\\end{quotation}")
    case .Itemize: return tex_document_starts(parser, "\\end{itemize}")
    case .Enumerate: return tex_document_starts(parser, "\\end{enumerate}")
    case .Description: return tex_document_starts(parser, "\\end{description}")
    case .None: return false
    }
    return false
}

// Consume the already-validated closing command for one environment.
tex_document_consume_environment_end :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) {

    parser.offset += len("\\end{")+len(tex_document_environment_name(environment))+1
}

// Capture parser-owned state changed while parsing one nested environment.
tex_document_environment_state :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Environment_State {

    return {
        alignment = parser.paragraph_alignment,
        format = parser.paragraph_format,
        quotation_first = parser.quotation_first_paragraph,
        item_started = parser.list_item_started,
        item_first = parser.list_item_first_block,
        item_block_start = parser.list_item_block_start,
    }
}

// Restore parser-owned state after parsing one nested environment.
tex_document_restore_environment_state :: proc(
    parser: ^Tex_Document_Parser,
    state: Tex_Document_Environment_State) {

    parser.paragraph_alignment = state.alignment
    parser.paragraph_format = state.format
    parser.quotation_first_paragraph = state.quotation_first
    parser.list_item_started = state.item_started
    parser.list_item_first_block = state.item_first
    parser.list_item_block_start = state.item_block_start
}

// Apply bounded quote-container policy for one entered quote environment.
tex_document_enter_quote_environment :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) -> Tex_Parse_Status {
    next_depth := int(parser.paragraph_format.container_depth)+1
    if next_depth > 4 {return .Work_Limit}
    parser.paragraph_format.container_kind = .Quote if
        environment == .Quote else .Quotation
    parser.paragraph_format.container_depth = u8(next_depth)
    parser.paragraph_format.left_margin_levels += 1
    parser.paragraph_format.right_margin_levels += 1
    parser.paragraph_format.no_indent = true
    parser.quotation_first_paragraph = environment == .Quotation
    return .Ok
}

// Apply bounded list-container policy for one entered list environment.
tex_document_enter_list_environment :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) -> Tex_Parse_Status {
    next_depth := int(parser.paragraph_format.container_depth)+1
    if next_depth > 4 {return .Work_Limit}
    parser.next_list_id += 1
    #partial switch environment {
    case .Itemize:
        parser.paragraph_format.container_kind = .Itemize
        parser.paragraph_format.list_kind = .Itemize
    case .Enumerate:
        parser.paragraph_format.container_kind = .Enumerate
        parser.paragraph_format.list_kind = .Enumerate
    case .Description:
        parser.paragraph_format.container_kind = .Description
        parser.paragraph_format.list_kind = .Description
    }
    parser.paragraph_format.container_depth = u8(next_depth)
    parser.paragraph_format.left_margin_levels += 1
    parser.paragraph_format.no_indent = true
    parser.paragraph_format.list_id = parser.next_list_id
    parser.paragraph_format.item_ordinal = 0
    parser.list_item_started = false
    parser.list_item_first_block = false
    parser.list_item_block_start = parser.output.document_block_count
    return .Ok
}

// Apply the alignment, quotation, or list policy for one entered environment.
tex_document_enter_environment :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) -> Tex_Parse_Status {

    switch environment {
    case .Center: parser.paragraph_alignment = .Center
    case .Flush_Left: parser.paragraph_alignment = .Left
    case .Flush_Right: parser.paragraph_alignment = .Right
    case .Quote, .Quotation:
        return tex_document_enter_quote_environment(parser, environment)
    case .Itemize, .Enumerate, .Description:
        return tex_document_enter_list_environment(parser, environment)
    case .None: return .Unexpected_Token
    }
    return .Ok
}

// Parse one alignment environment as complete paragraphs with inherited inline style.
tex_document_parse_environment :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context,
    environment: Tex_Document_Environment) -> Tex_Parse_Status {

    tex_document_close_paragraph(parser)
    name := tex_document_environment_name(environment)
    parser.offset += len("\\begin{")+len(name)+1
    prior := tex_document_environment_state(parser)
    enter_status := tex_document_enter_environment(parser, environment)
    if enter_status != .Ok {return enter_status}
    nested := inherited
    nested.environment = environment
    nested.stop_on_brace = false
    status := tex_document_parse_sequence(parser, nested)
    tex_document_close_paragraph(parser)
    if status == .Ok && tex_document_environment_is_list(environment) &&
        (!parser.list_item_started || parser.output.document_block_count ==
            parser.list_item_block_start) {
        status = .Unexpected_Token
    }
    tex_document_restore_environment_state(parser, prior)
    return status
}

// Resolve one emitted block's inherited container and local alignment policy.
tex_document_block_format :: proc(
    parser: ^Tex_Document_Parser,
    alignment: Tex_Document_Alignment) -> Tex_Document_Format {

    result := parser.paragraph_format
    result.alignment = alignment
    result.no_indent = result.no_indent || parser.pending_no_indent
    result.item_first_block = parser.list_item_first_block
    return result
}

// Report whether one environment requires item-delimited body content.
tex_document_environment_is_list :: #force_inline proc(
    environment: Tex_Document_Environment) -> bool {

    return environment == .Itemize || environment == .Enumerate ||
        environment == .Description
}

// Begin one explicit list-item block that owns its label inlines.
tex_document_begin_list_label :: proc(
    parser: ^Tex_Document_Parser,
    source: Tex_Source_Span) -> int {

    format := tex_document_block_format(parser, .Left)
    format.item_first_block = false
    return tex_semantic_append_document_block(parser.output, {
        kind = .List_Item,
        inline_start = parser.output.document_inline_count,
        source = source,
        format = format,
    })
}

// Append one parser-generated label to its explicit list-item semantic block.
tex_document_append_list_label :: proc(
    parser: ^Tex_Document_Parser,
    source: Tex_Source_Span,
    text: string) -> Tex_Parse_Status {

    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok {return .Work_Limit}
    block_index := tex_document_begin_list_label(parser, source)
    if block_index < 0 || !tex_semantic_append_document_inline(
        parser.output, block_index, {
        kind = .Text, source = source, text = span,
        font_flags = TEX_DOCUMENT_STYLE_BOLD, math_program = -1,
    }) {return .Work_Limit}
    return .Ok
}

// Append one bounded decimal enumerate label without transient allocation.
tex_document_append_enumerate_label :: proc(
    parser: ^Tex_Document_Parser,
    source: Tex_Source_Span,
    ordinal: int) -> Tex_Parse_Status {

    bytes: [4]u8
    digit_count := 0
    remaining := ordinal
    for remaining > 0 {
        bytes[digit_count] = u8(remaining%10)+'0'
        remaining /= 10
        digit_count += 1
    }
    for left, right := 0, digit_count-1; left < right; left, right = left+1, right-1 {
        bytes[left], bytes[right] = bytes[right], bytes[left]
    }
    bytes[digit_count] = '.'
    return tex_document_append_list_label(
        parser, source, string(bytes[:digit_count+1]))
}

// Parse one required description term through the bounded inline grammar.
tex_document_parse_description_label :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Parse_Status {
    if parser.offset >= len(parser.source) || parser.source[parser.offset] != '[' {
        return .Unexpected_Token
    }
    start := parser.offset
    parser.offset += 1
    block_index := tex_document_begin_list_label(parser, {start, 1})
    if block_index < 0 {return .Work_Limit}
    parser.active_paragraph = block_index
    parser.description_label_active = true
    status := tex_document_parse_sequence(parser, {
        font_flags = TEX_DOCUMENT_STYLE_BOLD,
        stop_on_bracket = true,
        inline_only = true,
    })
    parser.description_label_active = false
    tex_document_close_paragraph(parser)
    block := &parser.output.document_blocks[block_index]
    block.source.length = parser.offset-start
    if status != .Ok {return status}
    if block.inline_count == 0 {return .Unexpected_Token}
    return .Ok
}

// Report whether the next list item may follow the current list body.
tex_document_list_item_position_valid :: proc(
    parser: ^Tex_Document_Parser) -> bool {
    if !parser.list_item_started {
        return parser.output.document_block_count == parser.list_item_block_start
    }
    return parser.output.document_block_count != parser.list_item_block_start
}

// Parse or synthesize one list-item label according to its container kind.
tex_document_parse_list_item_label :: proc(
    parser: ^Tex_Document_Parser,
    list_kind: Tex_Document_List_Kind,
    source: Tex_Source_Span,
    ordinal: int) -> Tex_Parse_Status {
    has_optional_label := parser.offset < len(parser.source) &&
        parser.source[parser.offset] == '['
    switch list_kind {
    case .Enumerate:
        if has_optional_label {return .Unexpected_Token}
        if ordinal > 999 {return .Work_Limit}
        return tex_document_append_enumerate_label(parser, source, ordinal)
    case .Description:
        return tex_document_parse_description_label(parser)
    case .Itemize:
        if has_optional_label {return .Unexpected_Token}
        return tex_document_append_list_label(parser, source, "•")
    case .None: return .Unexpected_Token
    }
    return .Unexpected_Token
}

// Begin one validated list item and prepare its first body block metadata.
tex_document_parse_list_item :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    list_kind := parser.paragraph_format.list_kind
    if list_kind == .None {return .Unexpected_Token}
    tex_document_close_paragraph(parser)
    if !tex_document_list_item_position_valid(parser) {return .Unexpected_Token}
    source_start := parser.offset
    parser.offset += len("\\item")
    label_source := Tex_Source_Span{source_start, len("\\item")}
    ordinal := int(parser.paragraph_format.item_ordinal)+1
    parser.paragraph_format.item_ordinal += 1
    parser.list_item_started = true
    parser.list_item_first_block = true
    label_status := tex_document_parse_list_item_label(
        parser, list_kind, label_source, ordinal)
    if label_status != .Ok {return label_status}
    parser.list_item_block_start = parser.output.document_block_count
    tex_document_consume_break_whitespace(parser)
    return .Ok
}

// Report whether one control symbol emits a literal prose special.
tex_document_is_escaped_special :: proc(parser: ^Tex_Document_Parser) -> bool {
    if parser.offset > len(parser.source)-2 || parser.source[parser.offset] != '\\' {
        return false
    }
    value := parser.source[parser.offset+1]
    return value == '%' || value == '#' || value == '_' || value == '&' ||
        value == '{' || value == '}'
}

// Append one escaped prose special while preserving its two-byte source span.
tex_document_parse_escaped_special :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {

    source_start := parser.offset
    parser.offset += 2
    return tex_document_append_semantic_text_span(parser,
        parser.source[source_start+1:parser.offset], source_start,
        font_flags, color)
}

// Consume a prose comment and its terminating source newline.
tex_document_consume_comment :: proc(parser: ^Tex_Document_Parser) {
    for parser.offset < len(parser.source) &&
        parser.source[parser.offset] != '\n' {
        parser.offset += 1
    }
    if parser.offset < len(parser.source) {
        parser.offset += 1
    }
}

//   Close one paragraph after removing trailing breakable spacing nodes.
tex_document_close_paragraph :: proc(parser: ^Tex_Document_Parser) {
    if parser.active_paragraph < 0 {return}
    block := &parser.output.document_blocks[parser.active_paragraph]
    for block.inline_count > 0 {
        item := &parser.output.document_inlines[
            block.inline_start + block.inline_count - 1]
        if item.kind != .Space || item.space_kind != .Breakable {break}
        block.inline_count -= 1
        parser.output.document_inline_count -= 1
    }
    if block.inline_count == 0 {
        parser.output.document_block_count -= 1
    } else {
        last := &parser.output.document_inlines[
            block.inline_start + block.inline_count - 1]
        block.source.length = last.source.offset + last.source.length -
            block.source.offset
        if parser.quotation_first_paragraph &&
            parser.paragraph_format.container_kind == .Quotation {
            parser.paragraph_format.no_indent = false
            parser.quotation_first_paragraph = false
        }
    }
    parser.active_paragraph = -1
}

//   Preserve one explicit line break inside the current paragraph.
tex_document_append_forced_break :: proc(
    parser: ^Tex_Document_Parser,
    source_start: int) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 {
        return .Unexpected_Token
    }
    return tex_document_append_paragraph_inline(parser, {
        kind = .Forced_Break,
        source = {source_start, parser.offset - source_start},
        math_program = -1,
    })
}

//   Return the supported shape command at the current source offset.
tex_document_shape_command :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Shape_Command {
    commands := [?]string{
        "\\euclidpoint", "\\euclidline", "\\euclidcircle", "\\euclidbox",
        "\\euclidangle", "\\euclidsemicircle", "\\euclidperpendicular",
        "\\euclidtriangle", "\\euclidpentagon",
    }
    kinds := [?]Tex_Document_Shape_Kind{
        .Point, .Line, .Circle, .Box, .Angle, .Semicircle,
        .Perpendicular, .Triangle, .Pentagon,
    }
    for index in 0..<len(commands) {
        if tex_document_command_starts(parser, commands[index]) {
            return {kind = kinds[index], text = commands[index], present = true}
        }
    }
    return {}
}

//   Return math delimiters and whether they imply inline Text style.
tex_document_math_delimiters :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Math_Delimiters {
    if tex_document_starts(parser, "$$") {
        return {opener = "$$", closer = "$$", present = true}
    }
    if tex_document_starts(parser, "$") {
        return {opener = "$", closer = "$", is_inline = true, present = true}
    }
    if tex_document_starts(parser, "\\(") {
        return {
            opener = "\\(",
            closer = "\\)",
            is_inline = true,
            present = true,
        }
    }
    if tex_document_starts(parser, "\\[") {
        return {opener = "\\[", closer = "\\]", present = true}
    }
    return {}
}

//   Return a complete outer math fragment and its root style.
tex_document_whole_math :: proc(
    source: string) -> Tex_Document_Whole_Math {
    parser := Tex_Document_Parser{source = source}
    delimiters := tex_document_math_delimiters(&parser)
    if !delimiters.present ||
        len(source) < len(delimiters.opener)+len(delimiters.closer) ||
        source[len(source)-len(delimiters.closer):] != delimiters.closer {
        return {}
    }
    content := source[
        len(delimiters.opener):len(source)-len(delimiters.closer)]
    style := Tex_Math_Root_Style.Text if delimiters.is_inline else .Display
    return {content = content, style = style, present = true}
}

//   Consume one nonnested braced source field.
tex_document_take_group_source :: proc(
    parser: ^Tex_Document_Parser) -> (string, bool) {
    if parser.offset >= len(parser.source) || parser.source[parser.offset] != '{' {
        return "", false
    }
    start := parser.offset + 1
    end := start
    for end < len(parser.source) && parser.source[end] != '}' {
        end += 1
    }
    if end >= len(parser.source) {
        return "", false
    }
    parser.offset = end + 1
    return parser.source[start:end], true
}

//   Consume whitespace attached to one forced line break.
tex_document_consume_break_whitespace :: proc(parser: ^Tex_Document_Parser) {
    for parser.offset < len(parser.source) &&
        (parser.source[parser.offset] == ' ' || parser.source[parser.offset] == '\t') {
        parser.offset += 1
    }
    if parser.offset >= len(parser.source) || parser.source[parser.offset] != '\n' {
        return
    }
    next := parser.offset + 1
    for next < len(parser.source) &&
        (parser.source[next] == ' ' || parser.source[next] == '\t') {
        next += 1
    }
    if next >= len(parser.source) || parser.source[next] != '\n' {
        parser.offset = next
    }
}

//   Charge one document parser work unit.
tex_document_charge :: proc(parser: ^Tex_Document_Parser) -> bool {
    if parser.work_count >= parser.limits.work_units {
        return false
    }
    parser.work_count += 1
    return true
}

//   Return whether one literal starts at the parser offset.
tex_document_starts :: proc(
    parser: ^Tex_Document_Parser,
    text: string) -> bool {
    return parser.offset <= len(parser.source)-len(text) &&
        parser.source[parser.offset:parser.offset+len(text)] == text
}

//   Match a complete control word rather than a longer command prefix.
tex_document_command_starts :: proc(
    parser: ^Tex_Document_Parser,
    command: string) -> bool {
    if !tex_document_starts(parser, command) {
        return false
    }
    next := parser.offset + len(command)
    return next >= len(parser.source) || parser.source[next] < 'A' ||
        parser.source[next] > 'Z' && parser.source[next] < 'a' ||
        parser.source[next] > 'z'
}

//   Find one literal byte sequence at or after a source offset.
tex_document_find :: proc(source, text: string, start: int) -> int {
    if len(text) == 0 {
        return -1
    }
    for index in start..=len(source)-len(text) {
        if source[index:index+len(text)] == text {
            return index
        }
    }
    return -1
}

//   Return whether a source contains one literal byte sequence.
tex_document_contains :: proc(source, text: string) -> bool {
    return tex_document_find(source, text, 0) >= 0
}