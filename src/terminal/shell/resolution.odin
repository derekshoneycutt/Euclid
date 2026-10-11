package shell

// Resolution uses fixed storage so shell submission has explicit argument-count
// and byte budgets and produces an allocation-free, self-contained command.
SHELL_RESOLVED_ARGUMENT_CAPACITY :: 256
SHELL_RESOLVED_BYTE_CAPACITY :: 32 * 1024
SHELL_INTERPOLATION_ELEMENT_CAPACITY :: 64

// One resolved argument's provenance and half-open byte range.
// `source_span` refers to the parsed source; text offsets index the owning
// `Resolved_Command.bytes` prefix.
Resolved_Argument :: struct {
    source_span: Source_Span,
    text_start: int,
    text_end: int,
}

// Owned argument-vector data produced by successful shell resolution.
// `byte_count` and `argument_count` delimit valid prefixes; argument strings are
// represented by descriptors into the inline byte arena and require no cleanup.
Resolved_Command :: struct {
    bytes: [SHELL_RESOLVED_BYTE_CAPACITY]u8,
    byte_count: int,
    arguments: [SHELL_RESOLVED_ARGUMENT_CAPACITY]Resolved_Argument,
    argument_count: int,
}

// One Julia interpolation value presented as zero or more shell arguments.
// Element strings are borrowed for the duration of `shell_resolve` and copied
// into its result; `element_count` delimits the valid prefix.
Shell_Interpolation_Value :: struct {
    elements: [SHELL_INTERPOLATION_ELEMENT_CAPACITY]string,
    element_count: int,
}

// Discriminator for the tagged shell-resolution result.
Shell_Resolution_Result_Kind :: enum u8 {
    Success,
    Error,
}

// Semantic reason bounded template expansion could not produce an argv.
Shell_Resolution_Error_Kind :: enum u8 {
    None,
    Missing_Interpolation,
    Extra_Interpolation,
    Invalid_Interpolation_Value,
    Collection_In_Compound_Word,
    Empty_Collection_In_Compound_Word,
    Too_Many_Arguments,
    Argument_Data_Too_Long,
}

// Resolution failure plus the source range responsible when one is available.
Shell_Resolution_Error :: struct {
    kind: Shell_Resolution_Error_Kind,
    source_span: Source_Span,
}

// Tagged result of resolving a parsed command template.
// `command` is consumable only for `Success`; `error` is meaningful only for
// `Error`, and any partially written command data must then be ignored.
Shell_Resolution_Result :: struct {
    kind: Shell_Resolution_Result_Kind,
    command: Resolved_Command,
    error: Shell_Resolution_Error,
}

// Internal cursor and output accumulator for one resolution pass.
// The template and interpolation slice are borrowed; `result` owns all output.
Shell_Resolver :: struct {
    template: ^Command_Template,
    interpolations: []Shell_Interpolation_Value,
    interpolation_index: int,
    result: Shell_Resolution_Result,
}

//   Resolve one parsed template into bounded, owned argument-vector data.
//
// Notes:
//   - Interpolations are consumed in parser order and are never reparsed as syntax.
//   - A whole-word collection expands into arguments; a compound requires a scalar.
//
// Parameters:
//   - template: The parsed command template to borrow during resolution.
//   - interpolations: Ordered Julia values corresponding exactly to template holes.
//
// Returns:
//   - A self-contained command on success, or the first semantic/capacity error.
shell_resolve :: proc(template: ^Command_Template,
    interpolations: []Shell_Interpolation_Value) -> Shell_Resolution_Result {
    resolver := Shell_Resolver{
        template = template,
        interpolations = interpolations,
    }
    if template == nil {
        shell_resolver_fail(&resolver, .Missing_Interpolation, {})
        return resolver.result
    }
    for word_index in 0..<template.word_count {
        if !shell_resolver_resolve_word(&resolver, &template.words[word_index]) {
            return resolver.result
        }
    }
    if resolver.interpolation_index != len(interpolations) {
        shell_resolver_fail(&resolver, .Extra_Interpolation, {})
        return resolver.result
    }
    resolver.result.kind = .Success
    return resolver.result
}

//   Borrow one argument's frozen text from its resolved command.
//
// Parameters:
//   - command: The successful resolved command owning argument bytes.
//   - argument_index: The zero-based argument index.
//
// Returns:
//   - The argument text, or an empty string for nil or out-of-range input.
//
// Notes:
//   - The returned string aliases `command` and must not outlive or mutate it.
resolved_command_argument_text :: proc(
    command: ^Resolved_Command, argument_index: int) -> string {
    if command == nil || argument_index < 0 ||
       argument_index >= command.argument_count {
        return ""
    }
    argument := &command.arguments[argument_index]
    return string(command.bytes[argument.text_start:argument.text_end])
}

//   Expand one interpolation that occupies its complete source word.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - word: The source word providing provenance for generated arguments.
//   - part: The word's sole interpolation part.
//
// Returns:
//   - True after appending every element; false after recording an error.
//
// Side effects:
//   - Consumes one interpolation and appends zero, one, or many arguments in order.
shell_resolver_resolve_interpolation_word :: proc(
    resolver: ^Shell_Resolver, word: ^Word_Template,
    part: ^Command_Part) -> bool {
    value, ok := shell_resolver_take_interpolation(resolver, part)
    if !ok {
        return false
    }
    if value.element_count == 1 {
        return shell_resolver_append_argument(
            resolver, value.elements[0], word.source_span)
    }
    for element in value.elements[:value.element_count] {
        if !shell_resolver_append_argument(
            resolver, element, word.source_span) {
            return false
        }
    }
    return true
}

//   Concatenate one compound word's literal and scalar parts into an argument.
//
// Notes:
//   - Empty and multi-element interpolation collections are ambiguous in a
//     compound word and fail rather than implying shell expansion rules.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - word: The compound word whose parts are resolved in source order.
//
// Returns:
//   - True after committing one argument; false after recording an error.
//
// Side effects:
//   - Copies resolved bytes and consumes each interpolation encountered.
shell_resolver_resolve_compound_word :: proc(
    resolver: ^Shell_Resolver, word: ^Word_Template) -> bool {
    argument_start := resolver.result.command.byte_count
    for part_index in 0..<word.part_count {
        part := &resolver.template.parts[word.first_part + part_index]
        if part.kind == .Literal {
            text := command_template_part_text(resolver.template, part)
            if !shell_resolver_append_bytes(resolver, text, part.source_span) {
                return false
            }
            continue
        }
        value, ok := shell_resolver_take_interpolation(resolver, part)
        if !ok {
            return false
        }
        if value.element_count == 0 {
            shell_resolver_fail(resolver,
                .Empty_Collection_In_Compound_Word, part.source_span)
            return false
        }
        if value.element_count != 1 {
            shell_resolver_fail(resolver,
                .Collection_In_Compound_Word, part.source_span)
            return false
        }
        if !shell_resolver_append_bytes(
            resolver, value.elements[0], part.source_span) {
            return false
        }
    }
    return shell_resolver_commit_argument(
        resolver, argument_start, word.source_span)
}

//   Resolve one source word under scalar and whole-word collection rules.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - word: The parsed word to resolve.
//
// Returns:
//   - True when the word is resolved; false after recording an error.
//
// Side effects:
//   - Appends zero or more arguments and advances interpolation consumption.
shell_resolver_resolve_word :: proc(
    resolver: ^Shell_Resolver, word: ^Word_Template) -> bool {
    if word.part_count == 0 {
        return shell_resolver_append_argument(resolver, "", word.source_span)
    }
    if word.part_count == 1 {
        part := &resolver.template.parts[word.first_part]
        if part.kind != .Literal {
            return shell_resolver_resolve_interpolation_word(
                resolver, word, part)
        }
    }
    return shell_resolver_resolve_compound_word(resolver, word)
}

//   Consume and validate the next interpolation value in parser order.
//
// Parameters:
//   - resolver: The active resolution pass and interpolation cursor.
//   - part: The source part used to locate any resulting error.
//
// Returns:
//   - The borrowed value and true, or a zero value and false on missing/invalid data.
//
// Side effects:
//   - Advances the cursor for present values and records the first shape error.
shell_resolver_take_interpolation :: proc(
    resolver: ^Shell_Resolver, part: ^Command_Part) -> (
        Shell_Interpolation_Value, bool) {
    if resolver.interpolation_index >= len(resolver.interpolations) {
        shell_resolver_fail(resolver, .Missing_Interpolation, part.source_span)
        return {}, false
    }
    value := resolver.interpolations[resolver.interpolation_index]
    resolver.interpolation_index += 1
    if value.element_count < 0 ||
       value.element_count > SHELL_INTERPOLATION_ELEMENT_CAPACITY {
        shell_resolver_fail(
            resolver, .Invalid_Interpolation_Value, part.source_span)
        return {}, false
    }
    return value, true
}

//   Copy and commit one complete argument with its source provenance.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - text: Opaque argument bytes to copy without syntax interpretation.
//   - span: The source range that produced the argument.
//
// Returns:
//   - True on commit; false after recording a byte or argument capacity error.
//
// Side effects:
//   - Appends bytes and one descriptor atomically, rolling bytes back if full.
shell_resolver_append_argument :: proc(
    resolver: ^Shell_Resolver, text: string, span: Source_Span) -> bool {
    start := resolver.result.command.byte_count
    if !shell_resolver_append_bytes(resolver, text, span) {
        return false
    }
    return shell_resolver_commit_argument(resolver, start, span)
}

//   Append opaque bytes to the in-progress resolved argument.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - text: The bytes to copy without shell parsing or expansion.
//   - span: The source range reported if byte capacity is exceeded.
//
// Returns:
//   - True after copying, or false after recording `Argument_Data_Too_Long`.
//
// Side effects:
//   - Extends the valid byte prefix only when the complete text fits.
shell_resolver_append_bytes :: proc(
    resolver: ^Shell_Resolver, text: string, span: Source_Span) -> bool {
    command := &resolver.result.command
    if command.byte_count + len(text) > SHELL_RESOLVED_BYTE_CAPACITY {
        shell_resolver_fail(resolver, .Argument_Data_Too_Long, span)
        return false
    }
    copy(command.bytes[command.byte_count:], text)
    command.byte_count += len(text)
    return true
}

//   Commit one descriptor for bytes already appended to the current argument.
//
// Parameters:
//   - resolver: The active resolution pass.
//   - start: The argument's inclusive offset in the result byte arena.
//   - span: The source range represented by the argument.
//
// Returns:
//   - True on commit, or false when argument capacity is exhausted.
//
// Side effects:
//   - On failure, rolls `byte_count` back to `start` and records the error.
shell_resolver_commit_argument :: proc(
    resolver: ^Shell_Resolver, start: int, span: Source_Span) -> bool {
    command := &resolver.result.command
    if command.argument_count >= SHELL_RESOLVED_ARGUMENT_CAPACITY {
        command.byte_count = start
        shell_resolver_fail(resolver, .Too_Many_Arguments, span)
        return false
    }
    command.arguments[command.argument_count] = {
        source_span = span,
        text_start = start,
        text_end = command.byte_count,
    }
    command.argument_count += 1
    return true
}

//   Record the terminal error for the current resolution pass.
//
// Parameters:
//   - resolver: The active resolution pass whose result becomes `Error`.
//   - kind: The semantic or capacity failure.
//   - span: The source range responsible, or zero when no range applies.
//
// Side effects:
//   - Replaces the result discriminator and error payload; partial output remains
//     internal and must not be consumed by callers.
shell_resolver_fail :: proc(resolver: ^Shell_Resolver,
    kind: Shell_Resolution_Error_Kind, span: Source_Span) {
    resolver.result.kind = .Error
    resolver.result.error = {kind = kind, source_span = span}
}
