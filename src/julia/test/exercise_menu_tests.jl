
if !isdefined(Main, :EUCLID_RUNTIME_API_LOADED)
    include("../runtime_api.jl")
end

const MENU_TEST_ANIMATION = UUID("76fdebfe-2600-551e-be64-03f1942f4f49")
const MENU_TEST_EXERCISE = ExerciseSummary(
    UUID("a9237c51-c9f6-4d54-8bf5-f8c651906e1c"), MENU_TEST_ANIMATION,
    "builtin:elements-i-1", "Construct an equilateral triangle")

@testset "exercise REPL output is readable" begin
    summary = sprint(show, MIME"text/plain"(), MENU_TEST_EXERCISE)
    @test summary == "Construct an equilateral triangle (builtin:elements-i-1)"
    @test !occursin("ExerciseSummary", summary)
    node = ExerciseCatalogueNode(MENU_TEST_ANIMATION, "Proposition I")
    page = ExercisePage([node], 16, 20, true)
    rendered = sprint(show, MIME"text/plain"(), page)
    @test occursin("17. Proposition I", rendered)
    @test occursin("Showing 17-17 of 20", rendered)
    @test occursin("offset=17", rendered)
    @test occursin("choose_exercise()", rendered)
    @test !occursin("UUID", rendered)
    empty_page = sprint(
        show, MIME"text/plain"(), ExercisePage(ExerciseSummary[], 0, 0, false))
    @test occursin("No entries found.", empty_page)
    trailing = sprint(
        show, MIME"text/plain"(), ExercisePage(ExerciseSummary[], 16, 1, false))
    @test occursin("No entries on this page.", trailing)
    for width in (1, 3, 5, 10, 30)
        @test textwidth(EuclidRepl.exercise_menu_label("Wide 漢字 catalogue title", width)) <= width
    end
    @test EuclidRepl.exercise_menu_label("name\e[31m\nnext", 40) == "name [31m next"
end

@testset "exercise browser uses catalogue identities and restores parent positions" begin
    node = ExerciseCatalogueNode(MENU_TEST_ANIMATION, "Proposition I")
    children_calls = Tuple{Union{Nothing,UUID},Int}[]
    loads = String[]
    choices = ["Browse: Proposition I", "Back", "Browse: Proposition I",
        "Load: Construct an equilateral triangle"]
    children = (id, offset) -> begin
        push!(children_calls, (id, offset))
        entries = isnothing(id) ? [node] : ExerciseCatalogueNode[]
        ExercisePage(entries, offset, length(entries), false)
    end

    associated = (id, offset) -> begin
        @test id == MENU_TEST_ANIMATION
        ExercisePage([MENU_TEST_EXERCISE], offset, 1, false)
    end
    load = reference -> begin
        push!(loads, reference)
        MENU_TEST_EXERCISE
    end
    request =
        (title, labels, cursor) -> something(findfirst(==(popfirst!(choices)), labels))
    @test EuclidRepl.browse_exercises(children, associated, load, request) ===
        MENU_TEST_EXERCISE
    @test loads == ["builtin:" * string(MENU_TEST_EXERCISE.id)]
    @test children_calls == [(nothing, 0), (MENU_TEST_ANIMATION, 0),
        (nothing, 0), (MENU_TEST_ANIMATION, 0)]
    @test isempty(choices)
end

@testset "exercise browser keeps user records in their explicit namespace" begin
    node = ExerciseCatalogueNode(MENU_TEST_ANIMATION, "Proposition I")
    user_summary = ExerciseSummary(
        MENU_TEST_EXERCISE.id, MENU_TEST_ANIMATION,
        "user:triangle-basic", "Triangle", true)
    loaded = String[]
    choices = ["Browse: Proposition I", "Load: Triangle"]
    children = (id, offset) -> isnothing(id) ?
        ExercisePage([node], offset, 1, false) :
        ExercisePage(ExerciseCatalogueNode[], offset, 0, false)
    associated = (id, offset) -> ExercisePage([user_summary], offset, 1, false)
    request = (_, labels, _) -> something(findfirst(==(popfirst!(choices)), labels))
    result = EuclidRepl.browse_exercises(
        children, associated, reference -> (push!(loaded, reference); user_summary),
        request; namespace="user")
    @test result === user_summary
    @test loaded == ["user:" * string(user_summary.id)]
    @test isempty(choices)

    unavailable = ExerciseSummary(
        MENU_TEST_EXERCISE.id, MENU_TEST_ANIMATION,
        "user:orphaned", "Unavailable construction", false)
    @test occursin("animation unavailable", sprint(show, unavailable))
    @test occursin("Unavailable: Unavailable construction",
        first(EuclidRepl.exercise_browser_entries(
            ExercisePage(ExerciseCatalogueNode[], 0, 0, false),
            ExercisePage([unavailable], 0, 1, false))[2]))
    @test !unavailable.animation_available
end

@testset "all-user browser reports unavailable associations without loading them" begin
    unavailable = ExerciseSummary(
        MENU_TEST_EXERCISE.id, MENU_TEST_ANIMATION,
        "user:orphaned", "Unavailable construction", false)
    loaded = String[]
    selections = ["Unavailable: Unavailable construction"]
    list_page = offset -> begin
        @test offset == 0
        ExercisePage([unavailable], offset, 1, false)
    end
    request = (_, labels, _) -> something(findfirst(==(popfirst!(selections)), labels))
    result = EuclidRepl.browse_user_exercise_pages(
        list_page, reference -> (push!(loaded, reference); unavailable), request)
    @test result === unavailable
    @test isempty(loaded)
    @test isempty(selections)
end

@testset "exercise browser bounded pages, empty state, cancel, and database failure" begin
    node = ExerciseCatalogueNode(MENU_TEST_ANIMATION, "Same display name")
    page = ExercisePage(fill(node, 16), 16, 40, true)
    entries, labels = EuclidRepl.exercise_browser_entries(page,
        ExercisePage(fill(MENU_TEST_EXERCISE, 16), 16, 40, true))
    @test length(entries) == 38
    @test all(label -> !occursin("UUID", label), labels)
    location = EuclidRepl.ExerciseBrowserLocation(nothing, "Built-in exercises", 0, 0, 1)
    stack = [location]
    for action in (:next_children, :next_exercises)
        EuclidRepl.exercise_browser_navigate!(stack, action)
    end

    @testset "browser follows bounded windows and does not resolve duplicate titles by name" begin
        node = ExerciseCatalogueNode(MENU_TEST_ANIMATION, "Shared name")
        other = ExerciseCatalogueNode(UUID("00000000-0000-0000-0000-000000000001"), "Shared name")
        requests = Tuple{Union{Nothing,UUID},Int}[]
        selections = ["More catalogue entries", "Previous catalogue page",
            "Browse: Shared name", "Back", "More catalogue entries", "Browse: Shared name",
            "Load: Construct an equilateral triangle"]
        children = (id, offset) -> begin
            push!(requests, (id, offset))
            if isnothing(id)
                entries = offset == 0 ? fill(other, 16) : [node]
                return ExercisePage(entries, offset, 17, offset == 0)
            end
            ExercisePage(ExerciseCatalogueNode[], offset, 0, false)
        end
        associated = (id, offset) -> ExercisePage(
            id == MENU_TEST_ANIMATION ? [MENU_TEST_EXERCISE] : ExerciseSummary[],
            offset, id == MENU_TEST_ANIMATION ? 1 : 0, false)
        request = (_, labels, _) ->
            something(findfirst(==(popfirst!(selections)), labels))
        result = EuclidRepl.browse_exercises(children, associated, identity, request)
        @test result == "builtin:" * string(MENU_TEST_EXERCISE.id)
        @test requests == [(nothing, 0), (nothing, 16), (nothing, 0),
            (other.id, 0), (nothing, 0), (nothing, 16), (MENU_TEST_ANIMATION, 0)]
        @test isempty(selections)
    end
    @test (location.child_offset, location.exercise_offset) == (16, 16)
    for action in (:previous_children, :previous_exercises)
        EuclidRepl.exercise_browser_navigate!(stack, action)
    end
    @test (location.child_offset, location.exercise_offset) == (0, 0)
    empty_children = ExercisePage(ExerciseCatalogueNode[], 0, 0, false)
    empty_exercises = ExercisePage(ExerciseSummary[], 0, 0, false)
    cancelled = EuclidRepl.browse_exercises(
        (_, _) -> empty_children, (_, _) -> empty_exercises,
        _ -> error("cancel must not load"), (title, labels, _) -> begin
            @test occursin("No exercises here", title)
            @test labels == ["Back", "Cancel"]
            -1
        end)
    @test isnothing(cancelled)
    @test EuclidRepl.browse_exercises(
        (_, _) -> empty_children, (_, _) -> empty_exercises,
        _ -> error("back must not load"), (_, _, _) -> 1) === :back
    @test_throws ExerciseQueryError EuclidRepl.browse_exercises(
        (_, _) -> throw(ExerciseQueryError(:database_failed)),
        (_, _) -> empty_exercises, identity, (_, _, _) -> error("must not prompt"))
end

"""Run a real standard menu through Euclid's pipe input and return its completed output."""
function exercise_test_standard_menu(keys::String; resize::Bool=false)
    evaluation = EuclidReplEvaluation
    terminal = evaluation.InteractiveTerminal()
    input = evaluation.interactive_input(terminal)
    output = IOBuffer()
    labels = ["Option $index with a long readable title" for index in 1:20]
    cursor = Ref(1)
    task = @async Terminal.with_interactive_input(input) do
        EuclidRepl.request_exercise_menu("Exercise menu", labels, cursor, input, output)
    end
    try
        @test timedwait(() -> isready(terminal.events), 5) === :ok
        @test take!(terminal.events).kind == evaluation.InteractiveAcquired
        @test terminal.acquired
        if resize
            @test evaluation.update_terminal_geometry!(terminal, 8, 24, UInt64(1))
        end
        @test evaluation.interactive_write!(terminal, codeunits(keys))
        @test timedwait(() -> istaskdone(task), 5) === :ok
        result = fetch(task)
        @test !terminal.acquired && terminal.read_depth == 0
        @test take!(terminal.events).kind == evaluation.InteractiveReleased
        @test !isready(terminal.events)
        return result, String(take!(output))
    finally
        if !istaskdone(task)
            schedule(task, InterruptException(); error=true)
            wait(task)
        end
        evaluation.close_interactive_terminal!(terminal)
    end
end

@testset "standard Julia RadioMenu receives input and restores the lease" begin
    chosen, output = exercise_test_standard_menu("\e[B\r")
    @test chosen == 2
    @test occursin("Option 2", output)
    @test occursin("\e[?25h", output)
    @test first(exercise_test_standard_menu("q")) == -1
    @test first(exercise_test_standard_menu("\x03")) == -1
    @test first(exercise_test_standard_menu("\e[F\r"; resize=true)) == 20
    @test_throws ArgumentError Terminal.with_interactive_input(identity, IOBuffer())
end

@testset "menu failure and evaluation retirement restore interactive input" begin
    evaluation = EuclidReplEvaluation
    terminal = evaluation.InteractiveTerminal()
    input = evaluation.interactive_input(terminal)
    try
        @test_throws ExerciseQueryError Terminal.with_interactive_input(input) do
            throw(ExerciseQueryError(:database_failed))
        end

        @test !terminal.acquired && terminal.read_depth == 0
        @test take!(terminal.events).kind == evaluation.InteractiveAcquired
        @test take!(terminal.events).kind == evaluation.InteractiveReleased
        output = IOBuffer()
        task = @async Terminal.with_interactive_input(input) do
            try
                EuclidRepl.request_exercise_menu("Retiring", ["Back", "Cancel"], Ref(1),
                    input, output)
            catch error
                error isa InterruptException || rethrow()
                :retired
            end
        end
        @test timedwait(() -> isready(terminal.events), 5) === :ok
        @test take!(terminal.events).kind == evaluation.InteractiveAcquired
        schedule(task, InterruptException(); error=true)
        @test timedwait(() -> istaskdone(task), 5) === :ok
        @test fetch(task) === :retired
        @test !terminal.acquired && terminal.read_depth == 0
        @test take!(terminal.events).kind == evaluation.InteractiveReleased
        @test occursin("\e[?25h", String(take!(output)))
    finally
        evaluation.close_interactive_terminal!(terminal)
    end
end

@testset "native runtime facade installs menu environment and guards input identity" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    terminal = host.reactor.evaluator_state.runtime.terminal
    input = EuclidReplEvaluation.interactive_input(terminal)
    task = nothing
    try
        @test terminal_host_ingest_geometry(host, UInt64(3), UInt16(74), UInt16(9))
        @test terminal.dimensions == (9, 74)
        @test terminal_host_ingest_capabilities(host, Terminal.CAPABILITY_VERSION,
            UInt8(1), UInt8(4), UInt8(0), UInt8(0), UInt32(0))
        @test Terminal.capabilities(input).color == Terminal.Truecolor
        host.reactor.evaluator_state.active_request = UInt64(19)
        @test terminal_host_ingest_interactive_input(
            host, UInt64(19), "ignored", host.reactor.session.generation)
        @test !isready(terminal.events)
        task = @async Terminal.with_interactive_input(input) do
            EuclidRepl.request_exercise_menu(
                "Native facade", ["Back", "Cancel"], Ref(1), input, IOBuffer())
        end
        @test timedwait(() -> isready(terminal.events), 5) === :ok
        @test take!(terminal.events).kind == EuclidReplEvaluation.InteractiveAcquired
        @test terminal_host_ingest_interactive_input(
            host, UInt64(19), "\r", host.reactor.session.generation + UInt64(1))
        @test terminal_host_ingest_interactive_input(
            host, UInt64(20), "\r", host.reactor.session.generation)
        @test terminal_host_ingest_interactive_input(
            host, UInt64(19), "q", host.reactor.session.generation)
        @test timedwait(() -> istaskdone(task), 5) === :ok
        istaskdone(task) && @test fetch(task) == -1
    finally
        if task !== nothing && !istaskdone(task)
            schedule(task, InterruptException(); error=true)
            @test timedwait(() -> istaskdone(task), 5) === :ok
        end
        host.reactor.evaluator_state.active_request = nothing
        @test shutdown_euclid_reactor!(host)
    end
end
