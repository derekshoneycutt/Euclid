"""Return the insertion text for every standard Julia completion kind."""
completion_insertion(item) = REPL.REPLCompletions.named_completion(item).completion

"""Resolve a useful REPL replacement, or explicit alternatives, at a byte cursor."""
function complete_input(
    code::AbstractString, cursor_byte::Integer;
    show_candidates::Bool=true,
    context_module::Module=Main)::CompletionResult
    0 < cursor_byte <= ncodeunits(code) || return CompletionResult(false, 0, 0, "")
    (cursor_byte == ncodeunits(code) || isvalid(code, Int(cursor_byte) + 1)) ||
        return CompletionResult(false, 0, 0, "")

    # Julia's provider takes the last character index, not the end-exclusive byte cursor.
    items, range, should_complete = REPL.REPLCompletions.completions(
        String(code), prevind(code, Int(cursor_byte) + 1), context_module, true, false)
    isempty(items) && return CompletionResult(false, 0, 0, "")

    insertion = ""
    if should_complete
        insertion = length(items) == 1 ? completion_insertion(first(items)) :
            REPL.LineEdit.common_prefix(completion_insertion.(items))
    end
    replaced = code[range]
    useful = !isempty(insertion) && insertion != replaced
    if !useful
        insertion = show_candidates ? format_completion_candidates(items) : ""
    end
    return CompletionResult(
        useful, first(range) - 1, first(range) - 1 + ncodeunits(replaced), insertion)
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