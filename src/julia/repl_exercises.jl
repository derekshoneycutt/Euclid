"""One navigation frame; identities come directly from the existing catalogue."""
mutable struct ExerciseBrowserLocation
    id::Union{Nothing,UUID}
    title::String
    child_offset::Int
    exercise_offset::Int
    cursor::Int
end

"""A bounded menu row containing either a real content result or a navigation action."""
const ExerciseBrowserEntry = Union{ExerciseCatalogueNode,ExerciseSummary,Symbol}

"""Adapt only viewport sizing to live host geometry; RadioMenu retains selection policy."""
mutable struct ExerciseRadioMenu <: TerminalMenus.ConfiguredMenu{TerminalMenus.Config}
    radio::TerminalMenus.RadioMenu{TerminalMenus.Config}
    input::IO
    cursor::Base.RefValue{Int}
    pagesize::Int
    pageoffset::Int
    config::TerminalMenus.Config
end

"""Keep the selected row visible after a pane resize, without replacing input handling."""
function TerminalMenus.numoptions(menu::ExerciseRadioMenu)::Int
    rows, _ = Terminal.dimensions(menu.input)
    count = length(menu.radio.options)
    menu.pagesize = min(count, max(1, rows - 6))
    menu.pageoffset = clamp(menu.pageoffset,
        max(0, menu.cursor[] - menu.pagesize), max(0, menu.cursor[] - 1))
    menu.pageoffset = min(menu.pageoffset, max(0, count - menu.pagesize))
    return count
end

"""Use the standard RadioMenu's accepted selection."""
TerminalMenus.selected(menu::ExerciseRadioMenu) = TerminalMenus.selected(menu.radio)

"""Let RadioMenu commit the chosen option."""
TerminalMenus.pick(menu::ExerciseRadioMenu, cursor::Int) =
    TerminalMenus.pick(menu.radio, cursor)

"""Let RadioMenu cancel without selecting a content identity."""
TerminalMenus.cancel(menu::ExerciseRadioMenu) = TerminalMenus.cancel(menu.radio)

"""Keep standard RadioMenu non-navigation key handling."""
TerminalMenus.keypress(menu::ExerciseRadioMenu, key::UInt32) =
    TerminalMenus.keypress(menu.radio, key)

"""Fit labels to the current pane so one option always occupies one terminal row."""
function TerminalMenus.writeline(
    io::IO, menu::ExerciseRadioMenu, index::Int, _selected::Bool)
    _, columns = Terminal.dimensions(menu.input)
    print(io, exercise_menu_label(menu.radio.options[index], max(1, columns - 5)))
end

"""Remove terminal controls and truncate by display width, including wide Unicode text."""
function exercise_menu_label(text::AbstractString, width::Int)::String
    clean = replace(String(text), r"[\x00-\x1f\x7f-\x9f]" => " ")
    textwidth(clean) <= width && return clean
    width <= 3 && return "." ^ max(0, width)
    output = IOBuffer()
    used = 0
    for character in clean
        used + textwidth(character) > width - 3 && break
        print(output, character)
        used += textwidth(character)
    end
    print(output, "...")
    return String(take!(output))
end

"""Run Julia's standard request loop against the evaluation's streams and input lease."""
function request_exercise_menu(
    title::String, labels::Vector{String}, cursor::Base.RefValue{Int},
    input::IO=stdin, output::IO=stdout)
    radio = TerminalMenus.RadioMenu(labels; charset=:ascii, ctrl_c_interrupt=false)
    menu = ExerciseRadioMenu(radio, input, cursor, radio.pagesize, 0, radio.config)
    _, columns = Terminal.dimensions(input)
    println(output, "\n", exercise_menu_label(title, max(1, columns - 1)))
    println(output, exercise_menu_label(
        "Arrows/PgUp/PgDn: move | Enter: select | q/Ctrl-C: cancel", max(1, columns - 1)))
    term = Terminals.TTYTerminal("xterm", input, output, output)
    return TerminalMenus.request(term, menu; cursor=cursor)
end

"""
    choose_exercise()

Browse Built-in exercises using Julia's TerminalMenus. Use arrows and Enter to
browse or load, Back to return to a parent, and q or Ctrl-C to cancel. Selection
loads instructions without navigating or resetting the drawing, variables, or output.
"""
function choose_exercise(state_ptr::Ptr{Cvoid})
    return Terminal.with_interactive_input(stdin) do
        while true
            selected = request_exercise_menu(
                "Exercises", ["Built-in exercises", "Cancel"], Ref(1))
            selected == 1 || break
            result = browse_exercises(
                (id, offset) -> exercises(state_ptr, "builtin"; parent=id, offset=offset),
                (id, offset) -> exercises(state_ptr, "builtin", id; offset=offset),
                reference -> load_exercise!(state_ptr, reference),
                request_exercise_menu)
            result === :back && continue
            if !isnothing(result)
                println("Loaded exercise: ", result.title)
                return nothing
            end
            break
        end
        println("Exercise selection cancelled.")
        return nothing
    end
end

"""Return a clear bounded-page description without exposing storage or UUID details."""
function exercise_browser_title(
    stack::Vector{ExerciseBrowserLocation},
    children::ExercisePage, exercises::ExercisePage)
    title = last(stack).title
    if children.total == 0 && exercises.total == 0
        title *= " -- No exercises here."
    elseif exercises.total > 0
        title *= isempty(exercises.entries) ? " -- No exercises on this page." :
            " -- Exercises: $(exercises.offset + 1)-" *
                "$(exercises.offset + length(exercises.entries)) of $(exercises.total)"
    elseif children.more || children.offset > 0
        title *= " -- Catalogue: $(children.offset + 1)-" *
            "$(children.offset + length(children.entries)) of $(children.total)"
    end
    if length(stack) > 1
        title *= " -- " * join((node.title for node in stack[1:end-1]), " / ")
    end
    return title
end

"""Navigate bounded content pages, retaining only ancestor identities and page positions."""
function browse_exercises(children, associated, load, request)
    stack = [ExerciseBrowserLocation(nothing, "Built-in exercises", 0, 0, 1)]
    while !isempty(stack)
        location = last(stack)
        child_page = children(location.id, location.child_offset)
        exercise_page = isnothing(location.id) ?
            ExercisePage(ExerciseSummary[], 0, 0, false) :
            associated(location.id, location.exercise_offset)
        entries, labels = exercise_browser_entries(child_page, exercise_page)
        title = exercise_browser_title(stack, child_page, exercise_page)
        cursor = Ref(clamp(location.cursor, 1, length(entries)))
        selection = request(title, labels, cursor)
        location.cursor = cursor[]
        selection == -1 && return nothing
        entry = entries[selection]
        if entry isa ExerciseSummary
            return load("builtin:" * string(entry.id))
        elseif entry isa ExerciseCatalogueNode
            push!(stack, ExerciseBrowserLocation(entry.id, entry.title, 0, 0, 1))
        elseif entry === :back && length(stack) == 1
            return :back
        else
            exercise_browser_navigate!(stack, entry)
        end
    end
    return nothing
end

"""Build readable labels and typed choices for at most two bounded content pages."""
function exercise_browser_entries(children::ExercisePage, exercises::ExercisePage)
    entries = ExerciseBrowserEntry[]
    labels = String[]
    for exercise in exercises.entries
        push!(entries, exercise)
        push!(labels, "Load: " * exercise.title)
    end
    for child in children.entries
        push!(entries, child)
        push!(labels, "Browse: " * child.title)
    end
    for (enabled, action, label) in (
        (exercises.offset > 0, :previous_exercises, "Previous exercises"),
        (exercises.more, :next_exercises, "More exercises"),
        (children.offset > 0, :previous_children, "Previous catalogue page"),
        (children.more, :next_children, "More catalogue entries"),
        (true, :back, "Back"),
        (true, :cancel, "Cancel"))
        enabled || continue
        push!(entries, action)
        push!(labels, label)
    end
    return entries, labels
end

"""Change only navigation state; no action resets the Terminal or construction."""
function exercise_browser_navigate!(
    stack::Vector{ExerciseBrowserLocation}, action::Symbol)
    location = last(stack)
    if action === :back
        pop!(stack)
    elseif action === :cancel
        empty!(stack)
    elseif action === :next_children
        location.child_offset += 16
    elseif action === :previous_children
        location.child_offset = max(0, location.child_offset - 16)
    elseif action === :next_exercises
        location.exercise_offset += 16
    elseif action === :previous_exercises
        location.exercise_offset = max(0, location.exercise_offset - 16)
    else
        throw(ArgumentError("unknown exercise navigation action: $action"))
    end
    location.cursor = 1
    return nothing
end
