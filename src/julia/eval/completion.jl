"""Return the insertion text for every standard Julia completion kind."""
completion_insertion(item) = REPL.REPLCompletions.named_completion(item).completion

"""Find the first standard Julia REPL completion at a zero-indexed byte cursor."""
function complete_input(
    code::AbstractString, cursor_byte::Integer;
    show_candidates::Bool=true,
    context_module::Module=Main)::CompletionResult
    cursor_byte < 0 || cursor_byte > ncodeunits(code) &&
        return CompletionResult(false, 0, 0, "")
    cursor_byte == 0 && return CompletionResult(false, 0, 0, "")

    items, range, _ = REPL.REPLCompletions.completions(
        String(code), Int(cursor_byte), context_module, true, false)
    isempty(items) && return CompletionResult(false, 0, 0, "")

    insertion = completion_insertion(first(items))
    insertion = show_candidates && length(items) > 1 ?
        format_completion_candidates(items) : insertion
    return CompletionResult(
        length(items) == 1, first(range) - 1, last(range), insertion)
end

"""Format completion names using Julia REPL-style multi-column rows."""
function format_completion_candidates(items)::String
    names = [REPL.REPLCompletions.named_completion(item).completion for item in items]
    column_width = 2 + maximum(textwidth, names; init=1)
    column_count = min(cld(length(names), 5), max(div(80, column_width), 1))
    entries_per_column = cld(length(names), column_count)
    output = IOBuffer()
    for row in 1:entries_per_column
        for column in 0:(column_count - 1)
            index = row + column * entries_per_column
            index > length(names) && continue
            print(output, names[index])
            print(output, " " ^ max(column_width - textwidth(names[index]), 1))
        end
        println(output)
    end
    return String(take!(output))
end