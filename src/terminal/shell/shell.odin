package shell

import "core:unicode/utf8"

// Parsing uses fixed storage so accepted input has explicit byte, structure, and
// nesting limits and the returned template owns everything needed for resolution.
SHELL_SOURCE_BYTE_CAPACITY :: 4096
SHELL_DECODED_BYTE_CAPACITY :: SHELL_SOURCE_BYTE_CAPACITY
SHELL_WORD_CAPACITY :: 64
SHELL_PART_CAPACITY :: 256
SHELL_INTERPOLATION_CAPACITY :: 64
SHELL_INTERPOLATION_DEPTH_CAPACITY :: 32

// Half-open UTF-8 byte range in a command template's original source.
Source_Span :: struct {
    start: int,
    end: int,
}

// Semantic role of one decoded command part.
Command_Part_Kind :: enum u8 {
    Literal,
    Interpolation_Identifier,
    Interpolation_Expression,
}

// One literal or interpolation leaf within a parsed word.
// Source offsets preserve user-facing provenance; text offsets index the owning
// template's decoded byte arena and exclude quoting/interpolation delimiters.
Command_Part :: struct {
    // Semantic interpretation chosen by the parser.
    kind: Command_Part_Kind,

    // Half-open provenance range in `Command_Template.source`.
    source_span: Source_Span,

    // Half-open payload range in `Command_Template.decoded`.
    text_start: int,
    text_end: int,
}

// One source word represented by a contiguous range of command parts.
// A zero-part word preserves an explicitly quoted empty argument.
Word_Template :: struct {
    // Half-open range of the complete word in original source bytes.
    source_span: Source_Span,

    // Contiguous range in `Command_Template.parts` owned by this word.
    first_part: int,
    part_count: int,
}

// Self-contained, bounded parse tree for one shell command.
//
// Source and decoded bytes are owned inline. Counts delimit valid prefixes, words
// cover contiguous part ranges in source order, and `interpolation_count` records
// the values a resolver must supply.
Command_Template :: struct {
    // Original validated UTF-8 retained for diagnostics and source spans.
    source: [SHELL_SOURCE_BYTE_CAPACITY]u8,
    source_count: int,

    // Quote/escape-decoded literal and interpolation payloads. Command parts
    // address this arena through half-open text ranges.
    decoded: [SHELL_DECODED_BYTE_CAPACITY]u8,
    decoded_count: int,

    // Parsed word topology. Each valid word owns a contiguous part subrange;
    // counts delimit all fixed-array prefixes.
    words: [SHELL_WORD_CAPACITY]Word_Template,
    word_count: int,
    parts: [SHELL_PART_CAPACITY]Command_Part,
    part_count: int,

    // Number of interpolation parts, and therefore values resolution must supply.
    interpolation_count: int,
}

// Discriminator for empty, successful, and failed parse results.
Shell_Parse_Result_Kind :: enum u8 {
    Empty,
    Success,
    Error,
}

// Stable syntax, encoding, and capacity failures produced by the parser.
Shell_Parse_Error_Kind :: enum u8 {
    None,
    Source_Too_Long,
    Invalid_Utf8,
    Too_Many_Words,
    Too_Many_Parts,
    Too_Many_Interpolations,
    Interpolation_Too_Deep,
    Decoded_Text_Too_Long,
    Reserved_Operator,
    Unterminated_Single_Quote,
    Unterminated_Double_Quote,
    Trailing_Escape,
    Invalid_Interpolation,
    Unterminated_Interpolation,
    Mismatched_Interpolation_Delimiter,
}

// Terminal parse failure and its half-open range in the original source.
Shell_Parse_Error :: struct {
    kind: Shell_Parse_Error_Kind,
    source_span: Source_Span,
}

// Tagged result of parsing one command line.
// `template` is consumable only for `Success`; `error` is meaningful only for
// `Error`. `Empty` represents input containing no non-whitespace word.
Shell_Parse_Result :: struct {
    kind: Shell_Parse_Result_Kind,
    template: Command_Template,
    error: Shell_Parse_Error,
}

// Internal cursor and output accumulator for one parse pass.
// After source validation/copy, `source` aliases `result.template.source` so the
// parser never depends on caller storage.
Shell_Parser :: struct {
    // Borrowed view into the owned source prefix plus its current byte position.
    source: string,
    cursor: int,

    // In-place parse product, including partial state when an error terminates.
    result: Shell_Parse_Result,
}

// Mutable boundaries for the literal run currently being assembled in one word.
Word_Parse_State :: struct {
    // Destination word whose part range grows as literals/interpolations flush.
    word: ^Word_Template,

    // Paired starts in original source and decoded output for the open literal run.
    literal_source_start: int,
    literal_text_start: int,
}

// State for quote-aware balanced scanning inside `$(` expression interpolation.
// The stack stores expected closing delimiters; source/text starts locate the
// complete source span and decoded expression body respectively.
Interpolation_Scan_State :: struct {
    // Balanced delimiter stack. `depth` delimits expected closers and begins at
    // one for the outer `$(` expression delimiter.
    stack: [SHELL_INTERPOLATION_DEPTH_CAPACITY]u8,
    depth: int,

    // Quote sub-state suppresses delimiter balancing; `escaped` applies only
    // while scanning a quoted region.
    quote: u8,
    escaped: bool,

    // Original-source and decoded-output starts for the interpolation being built.
    start: int,
    text_start: int,
}

// Control result from consuming one expression-interpolation byte.
Interpolation_Step :: enum u8 {
    Continue,
    Complete,
    Error,
}

//   Parse one command according to the bounded Euclid terminal shell grammar.
//
// Notes:
//   - Input is validated as UTF-8 and copied before any template views are formed.
//   - Quotes and escapes decode literals; unquoted shell operators are rejected.
//   - `$name` and balanced `$(...)` regions become interpolation leaves.
//
// Parameters:
//   - source: The command bytes to parse; caller storage is never retained.
//
// Returns:
//   - An owned template, `Empty` for whitespace-only input, or a located error.
shell_parse :: proc(source: string) -> Shell_Parse_Result {
    parser: Shell_Parser
    if len(source) > SHELL_SOURCE_BYTE_CAPACITY {
        shell_parser_fail(&parser, .Source_Too_Long, 0, len(source))
        return parser.result
    }
    if !utf8.valid_string(source) {
        shell_parser_fail(&parser, .Invalid_Utf8, 0, len(source))
        return parser.result
    }
    copy(parser.result.template.source[:], transmute([]u8)source)
    parser.result.template.source_count = len(source)
    parser.source = string(parser.result.template.source[:len(source)])

    shell_parser_skip_whitespace(&parser)
    if parser.cursor == len(parser.source) {
        parser.result.kind = .Empty
        return parser.result
    }
    for parser.cursor < len(parser.source) {
        if !shell_parser_parse_word(&parser) {
            return parser.result
        }
        shell_parser_skip_whitespace(&parser)
    }
    parser.result.kind = .Success
    return parser.result
}

//   Borrow the decoded text owned by one command part's template.
//
// Parameters:
//   - template: The template owning the decoded byte arena.
//   - part: A part whose text offsets refer to that template.
//
// Returns:
//   - The decoded text, or an empty string for nil or invalid bounds.
//
// Notes:
//   - The returned string aliases `template` and must not outlive or mutate it.
command_template_part_text :: proc(
    template: ^Command_Template, part: ^Command_Part) -> string {
    if template == nil || part == nil || part.text_start < 0 ||
       part.text_end < part.text_start || part.text_end > template.decoded_count {
        return ""
    }
    return string(template.decoded[part.text_start:part.text_end])
}

//   Parse one whitespace-delimited word into contiguous template parts.
//
// Parameters:
//   - parser: The active parser positioned at the word's first byte.
//
// Returns:
//   - True at the word boundary; false after recording an error.
//
// Side effects:
//   - Advances the cursor and appends one word plus its decoded parts.
shell_parser_parse_word :: proc(parser: ^Shell_Parser) -> bool {
    template := &parser.result.template
    if template.word_count >= SHELL_WORD_CAPACITY {
        shell_parser_fail(parser, .Too_Many_Words, parser.cursor, parser.cursor)
        return false
    }
    word_index := template.word_count
    template.word_count += 1
    word := &template.words[word_index]
    word.source_span.start = parser.cursor
    word.first_part = template.part_count
    state := Word_Parse_State {
        word = word,
        literal_source_start = parser.cursor,
        literal_text_start = template.decoded_count,
    }

    for parser.cursor < len(parser.source) &&
        !shell_byte_is_whitespace(parser.source[parser.cursor]) {
        if !shell_parser_parse_word_byte(parser, &state) {
            return false
        }
    }
    if !shell_parser_flush_literal(parser, state.literal_source_start,
        parser.cursor, state.literal_text_start, word) {
        return false
    }
    word.source_span.end = parser.cursor
    return true
}

//   Consume one unquoted byte or dispatch one quoted/interpolated region.
//
// Parameters:
//   - parser: The active parser positioned within an unquoted word.
//   - state: The current word's literal-run boundaries.
//
// Returns:
//   - True after consuming a valid unit; false after recording an error.
//
// Side effects:
//   - Advances the cursor, appends decoded bytes, or emits interpolation parts.
shell_parser_parse_word_byte :: proc(
    parser: ^Shell_Parser, state: ^Word_Parse_State) -> bool {
    byte := parser.source[parser.cursor]
    if shell_byte_is_reserved(byte) {
        shell_parser_fail(parser, .Reserved_Operator,
            parser.cursor, parser.cursor + 1)
        return false
    }
    if byte == '\\' {
        return shell_parser_parse_word_escape(parser)
    }
    if byte == '\'' {
        return shell_parser_parse_single_quote(parser)
    }
    if byte == '"' {
        return shell_parser_parse_double_quote(parser,
            &state.literal_source_start, &state.literal_text_start, state.word)
    }
    if byte == '$' {
        if !shell_parser_flush_literal(parser, state.literal_source_start,
            parser.cursor, state.literal_text_start, state.word) ||
           !shell_parser_parse_interpolation(parser, state.word) {
            return false
        }
        state.literal_source_start = parser.cursor
        state.literal_text_start = parser.result.template.decoded_count
        return true
    }
    if !shell_parser_append_byte(parser, byte) {
        return false
    }
    parser.cursor += 1
    return true
}

//   Decode one unquoted escape sequence into the active literal run.
shell_parser_parse_word_escape :: proc(parser: ^Shell_Parser) -> bool {
    if parser.cursor + 1 >= len(parser.source) {
        shell_parser_fail(parser, .Trailing_Escape,
            parser.cursor, parser.cursor + 1)
        return false
    }
    parser.cursor += 1
    if !shell_parser_append_byte(parser, parser.source[parser.cursor]) {
        return false
    }
    parser.cursor += 1
    return true
}

//   Decode one single-quoted region as literal bytes.
//
// Notes:
//   - Escapes and interpolation have no special meaning inside single quotes.
//
// Parameters:
//   - parser: The active parser positioned at the opening quote.
//
// Returns:
//   - True after the closing quote; false on capacity or unterminated input.
//
// Side effects:
//   - Advances the cursor and appends interior bytes without the quote delimiters.
shell_parser_parse_single_quote :: proc(parser: ^Shell_Parser) -> bool {
    quote_start := parser.cursor
    parser.cursor += 1
    for parser.cursor < len(parser.source) && parser.source[parser.cursor] != '\'' {
        if !shell_parser_append_byte(parser, parser.source[parser.cursor]) {
            return false
        }
        parser.cursor += 1
    }
    if parser.cursor >= len(parser.source) {
        shell_parser_fail(parser, .Unterminated_Single_Quote,
            quote_start, len(parser.source))
        return false
    }
    parser.cursor += 1
    return true
}

//   Decode one double-quoted region and emit embedded interpolation leaves.
//
// Notes:
//   - Backslash decodes only `\\`, `\"`, and `\$`; other pairs remain literal.
//
// Parameters:
//   - parser: The active parser positioned at the opening quote.
//   - literal_source_start: Source start of the current literal run, updated in place.
//   - literal_text_start: Decoded start of the current literal run, updated in place.
//   - word: The word receiving flushed literal and interpolation parts.
//
// Returns:
//   - True after the closing quote; false after recording an error.
//
// Side effects:
//   - Advances the cursor, appends decoded bytes, and may append command parts.
shell_parser_parse_double_quote :: proc(parser: ^Shell_Parser,
    literal_source_start, literal_text_start: ^int, word: ^Word_Template) -> bool {
    quote_start := parser.cursor
    parser.cursor += 1
    for parser.cursor < len(parser.source) && parser.source[parser.cursor] != '"' {
        byte := parser.source[parser.cursor]
        if byte == '\\' && parser.cursor + 1 < len(parser.source) {
            next := parser.source[parser.cursor + 1]
            if next == '\\' || next == '"' || next == '$' {
                if shell_parser_parse_double_quote_escape(parser, next) {
                    continue
                }
                return false
            }
        }
        if byte == '$' {
            if !shell_parser_parse_quoted_interpolation(parser,
                literal_source_start, literal_text_start, word) {
                return false
            }
            continue
        }
        if !shell_parser_append_byte(parser, byte) {
            return false
        }
        parser.cursor += 1
    }
    if parser.cursor >= len(parser.source) {
        shell_parser_fail(parser, .Unterminated_Double_Quote,
            quote_start, len(parser.source))
        return false
    }
    parser.cursor += 1
    return true
}

//   Flush one quoted literal, append its interpolation, and reopen the literal run.
shell_parser_parse_quoted_interpolation :: proc(parser: ^Shell_Parser,
    literal_source_start, literal_text_start: ^int, word: ^Word_Template) -> bool {
    if !shell_parser_flush_literal(parser, literal_source_start^,
        parser.cursor, literal_text_start^, word) ||
       !shell_parser_parse_interpolation(parser, word) {
        return false
    }
    literal_source_start^ = parser.cursor
    literal_text_start^ = parser.result.template.decoded_count
    return true
}

//   Append one recognized double-quote escape and advance beyond both bytes.
shell_parser_parse_double_quote_escape :: proc(
    parser: ^Shell_Parser, escaped: u8) -> bool {
    if !shell_parser_append_byte(parser, escaped) {
        return false
    }
    parser.cursor += 2
    return true
}

//   Parse one `$name` or `$(...)` interpolation leaf.
//
// Parameters:
//   - parser: The active parser positioned at `$`.
//   - word: The word receiving the interpolation part.
//
// Returns:
//   - True after appending a valid leaf; false after recording an error.
//
// Side effects:
//   - Advances the cursor and appends decoded interpolation text and metadata.
shell_parser_parse_interpolation :: proc(
    parser: ^Shell_Parser, word: ^Word_Template) -> bool {
    start := parser.cursor
    parser.cursor += 1
    if parser.cursor >= len(parser.source) {
        shell_parser_fail(parser, .Invalid_Interpolation, start, parser.cursor)
        return false
    }
    if parser.source[parser.cursor] == '(' {
        return shell_parser_parse_expression_interpolation(parser, word, start)
    }
    if !shell_byte_is_identifier_start(parser.source[parser.cursor]) {
        shell_parser_fail(parser, .Invalid_Interpolation, start, parser.cursor + 1)
        return false
    }
    text_start := parser.result.template.decoded_count
    for parser.cursor < len(parser.source) &&
        shell_byte_is_identifier_continue(parser.source[parser.cursor]) {
        if !shell_parser_append_byte(parser, parser.source[parser.cursor]) {
            return false
        }
        parser.cursor += 1
    }
    return shell_parser_append_interpolation(parser, word, {
        kind = .Interpolation_Identifier,
        source_span = {start, parser.cursor},
        text_start = text_start,
    })
}

//   Scan one balanced expression interpolation without parsing Julia syntax.
//
// Notes:
//   - Parentheses, brackets, and braces balance across nested quoted regions.
//   - The outer `$(` and closing `)` are excluded from decoded expression text.
//
// Parameters:
//   - parser: The active parser positioned at the opening parenthesis.
//   - word: The word receiving the completed interpolation part.
//   - start: The source offset of the interpolation's `$`.
//
// Returns:
//   - True after a balanced close; false on mismatch, depth, capacity, or EOF.
//
// Side effects:
//   - Advances the cursor and appends expression bytes and one command part.
shell_parser_parse_expression_interpolation :: proc(
    parser: ^Shell_Parser, word: ^Word_Template, start: int) -> bool {
    parser.cursor += 1
    state := Interpolation_Scan_State {
        depth = 1,
        start = start,
        text_start = parser.result.template.decoded_count,
    }
    state.stack[0] = ')'
    for parser.cursor < len(parser.source) {
        switch shell_parser_scan_expression_byte(parser, &state) {
        case .Continue:
        case .Complete:
            return shell_parser_append_interpolation(parser, word, {
                kind = .Interpolation_Expression,
                source_span = {start, parser.cursor},
                text_start = state.text_start,
            })
        case .Error:
            return false
        }
    }
    shell_parser_fail(parser, .Unterminated_Interpolation, start, len(parser.source))
    return false
}

//   Consume one byte of a balanced expression interpolation.
//
// Parameters:
//   - parser: The active parser positioned at the next expression byte.
//   - state: Quote, escape, and expected-delimiter state updated in place.
//
// Returns:
//   - `Continue`, `Complete` after the outer close, or `Error` after failure.
//
// Side effects:
//   - Advances the cursor and appends every byte except the outer closing delimiter.
shell_parser_scan_expression_byte :: proc(parser: ^Shell_Parser,
    state: ^Interpolation_Scan_State) -> Interpolation_Step {
    byte := parser.source[parser.cursor]
    if state.quote != 0 {
        return shell_parser_scan_quoted_expression_byte(parser, state, byte)
    }
    return shell_parser_scan_unquoted_expression_byte(parser, state, byte)
}

//   Consume one expression byte while delimiter balancing is suppressed by a quote.
shell_parser_scan_quoted_expression_byte :: proc(parser: ^Shell_Parser,
    state: ^Interpolation_Scan_State, byte: u8) -> Interpolation_Step {
    if !shell_parser_append_byte(parser, byte) {
        return .Error
    }
    parser.cursor += 1
    if state.escaped {
        state.escaped = false
    } else if byte == '\\' {
        state.escaped = true
    } else if byte == state.quote {
        state.quote = 0
    }
    return .Continue
}

//   Consume one expression byte while maintaining balanced delimiters.
shell_parser_scan_unquoted_expression_byte :: proc(parser: ^Shell_Parser,
    state: ^Interpolation_Scan_State, byte: u8) -> Interpolation_Step {
    if byte == '\'' || byte == '"' {
        state.quote = byte
    } else if byte == '(' || byte == '[' || byte == '{' {
        if state.depth >= SHELL_INTERPOLATION_DEPTH_CAPACITY {
            shell_parser_fail(parser, .Interpolation_Too_Deep,
                state.start, parser.cursor + 1)
            return .Error
        }
        state.stack[state.depth] = shell_matching_delimiter(byte)
        state.depth += 1
    } else if byte == ')' || byte == ']' || byte == '}' {
        if byte != state.stack[state.depth - 1] {
            shell_parser_fail(parser, .Mismatched_Interpolation_Delimiter,
                parser.cursor, parser.cursor + 1)
            return .Error
        }
        state.depth -= 1
        if state.depth == 0 {
            parser.cursor += 1
            return .Complete
        }
    }
    if !shell_parser_append_byte(parser, byte) {
        return .Error
    }
    parser.cursor += 1
    return .Continue
}

//   Append one interpolation part after enforcing structural capacities.
//
// Parameters:
//   - parser: The active parser and destination template.
//   - word: The word receiving the new part.
//   - part: Interpolation metadata with an open decoded-text range.
//
// Returns:
//   - True on commit; false after recording a capacity error.
//
// Side effects:
//   - Closes the text range and increments part and interpolation counts.
shell_parser_append_interpolation :: proc(parser: ^Shell_Parser,
    word: ^Word_Template, part: Command_Part) -> bool {
    template := &parser.result.template
    if template.interpolation_count >= SHELL_INTERPOLATION_CAPACITY {
        shell_parser_fail(parser, .Too_Many_Interpolations,
            part.source_span.start, part.source_span.end)
        return false
    }
    resolved_part := part
    resolved_part.text_end = template.decoded_count
    if !shell_parser_append_part(parser, word, resolved_part) {
        return false
    }
    template.interpolation_count += 1
    return true
}

//   Materialize the current nonempty decoded literal run as a command part.
//
// Parameters:
//   - parser: The active parser and destination template.
//   - source_start: Inclusive source offset of the literal run.
//   - source_end: Exclusive source offset of the literal run.
//   - text_start: Inclusive decoded-text offset of the literal run.
//   - word: The word receiving the literal part.
//
// Returns:
//   - True for an empty run or successful append; false on part-capacity failure.
shell_parser_flush_literal :: proc(parser: ^Shell_Parser,
    source_start, source_end, text_start: int, word: ^Word_Template) -> bool {
    if text_start == parser.result.template.decoded_count {
        return true
    }
    return shell_parser_append_part(parser, word, {
        kind = .Literal,
        source_span = {source_start, source_end},
        text_start = text_start,
        text_end = parser.result.template.decoded_count,
    })
}

//   Append one bounded part descriptor to the current word.
//
// Parameters:
//   - parser: The active parser and destination template.
//   - word: The word whose contiguous part count is extended.
//   - part: The complete descriptor to append.
//
// Returns:
//   - True on commit; false after recording `Too_Many_Parts`.
//
// Side effects:
//   - Appends the descriptor and increments template and word part counts.
shell_parser_append_part :: proc(parser: ^Shell_Parser,
    word: ^Word_Template, part: Command_Part) -> bool {
    template := &parser.result.template
    if template.part_count >= SHELL_PART_CAPACITY {
        shell_parser_fail(parser, .Too_Many_Parts,
            part.source_span.start, part.source_span.end)
        return false
    }
    template.parts[template.part_count] = part
    template.part_count += 1
    word.part_count += 1
    return true
}

//   Append one byte to the template's decoded-text arena.
//
// Parameters:
//   - parser: The active parser and destination template.
//   - byte: The decoded byte to append.
//
// Returns:
//   - True on append; false after recording `Decoded_Text_Too_Long`.
//
// Side effects:
//   - Extends the valid decoded prefix only when capacity remains.
shell_parser_append_byte :: proc(parser: ^Shell_Parser, byte: u8) -> bool {
    template := &parser.result.template
    if template.decoded_count >= SHELL_DECODED_BYTE_CAPACITY {
        shell_parser_fail(parser, .Decoded_Text_Too_Long,
            parser.cursor, parser.cursor + 1)
        return false
    }
    template.decoded[template.decoded_count] = byte
    template.decoded_count += 1
    return true
}

//   Record the terminal parse failure and its source span.
//
// Parameters:
//   - parser: The active parser whose result becomes `Error`.
//   - kind: The syntax, encoding, or capacity failure.
//   - start: Inclusive source offset of the failure.
//   - end: Exclusive source offset of the failure.
//
// Side effects:
//   - Replaces the result discriminator and error payload.
shell_parser_fail :: proc(parser: ^Shell_Parser, kind: Shell_Parse_Error_Kind,
    start, end: int) {
    parser.result.kind = .Error
    parser.result.error = {kind = kind, source_span = {start, end}}
}

//   Advance over ASCII shell whitespace between words.
//
// Parameters:
//   - parser: The active parser positioned between words or at end of input.
//
// Side effects:
//   - Advances the cursor through spaces, tabs, carriage returns, and newlines.
shell_parser_skip_whitespace :: proc(parser: ^Shell_Parser) {
    for parser.cursor < len(parser.source) &&
        shell_byte_is_whitespace(parser.source[parser.cursor]) {
        parser.cursor += 1
    }
}

//   Report whether one byte separates unquoted words.
//
// Parameters:
//   - byte: The source byte to classify.
//
// Returns:
//   - True for supported ASCII shell whitespace.
shell_byte_is_whitespace :: proc(byte: u8) -> bool {
    return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n'
}

//   Report whether one unquoted byte begins an unsupported shell operator.
//
// Parameters:
//   - byte: The source byte to classify.
//
// Returns:
//   - True for pipe, redirection, backgrounding, or command-separator bytes.
shell_byte_is_reserved :: proc(byte: u8) -> bool {
    return byte == '|' || byte == '<' || byte == '>' || byte == '&' || byte == ';'
}

//   Report whether one byte may begin an interpolation identifier.
//
// Parameters:
//   - byte: The source byte to classify.
//
// Returns:
//   - True for ASCII underscore or letter.
shell_byte_is_identifier_start :: proc(byte: u8) -> bool {
    return byte == '_' || byte >= 'a' && byte <= 'z' || byte >= 'A' && byte <= 'Z'
}

//   Report whether one byte may continue an interpolation identifier.
//
// Parameters:
//   - byte: The source byte to classify.
//
// Returns:
//   - True for an identifier-start byte or ASCII digit.
shell_byte_is_identifier_continue :: proc(byte: u8) -> bool {
    return shell_byte_is_identifier_start(byte) || byte >= '0' && byte <= '9'
}

//   Map one interpolation opener to its closing delimiter.
//
// Parameters:
//   - byte: The opening parenthesis, bracket, or brace.
//
// Returns:
//   - The paired closing byte, or zero for an unsupported opener.
shell_matching_delimiter :: proc(byte: u8) -> u8 {
    switch byte {
    case '(':
        return ')'
    case '[':
        return ']'
    case '{':
        return '}'
    }
    return 0
}