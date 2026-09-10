"""Evaluate one AST with terminal streams and process/tick authority installed."""
function evaluate_streaming_ast!(
    runtime::EvaluationRuntime, build_ast, code::AbstractString, output)::Nothing
    session = runtime.session
    ast = build_ast(output)
    display = PlainTextDisplay(output, session.context_module)
    try
        pushdisplay(display)
        response = TerminalContainer.with_client(
            runtime.terminal_container_client) do
            Ticks.with_tick_client(runtime.tick_client) do
                Terminal.with_process_client(runtime.process_client) do
                redirect_stdin(interactive_input(runtime.terminal)) do
                    redirect_stdout(output) do
                        redirect_stderr(output) do
                            REPL.eval_user_input(
                                ast, session.backend, session.context_module)
                            take!(session.backend.response_channel)
                        end
                    end
                end
            end
        end
        end
        append_repl_response!(output, response, code, session.context_module)
    finally
        popdisplay(display)
    end
    return nothing
end

"""Start one AST evaluation whose capture pipe emits bounded output events."""
function run_ast_streaming!(
    runtime::EvaluationRuntime, build_ast, code::AbstractString)
    session = runtime.session
    pipe = open_capture_pipe()
    chunks = Channel{EvalStreamEvent}(EVAL_STREAM_CAPACITY)
    forwarder = @async stream_pipe_output!(pipe.out, chunks)
    producer = @async begin
        try
            output = terminal_io_context(runtime.terminal, pipe.in)
            evaluate_streaming_ast!(runtime, build_ast, code, output)
        catch error
            showerror(pipe.in, error, catch_backtrace())
        finally
            interactive_release!(runtime.terminal)
            close(pipe.in)
            session.input_number += 1
        end
    end
    runtime.active_stream = StreamingEval(producer, forwarder, chunks)
end

"""Start one Pkg command whose capture pipe emits bounded output events."""
function run_pkg_streaming!(runtime::EvaluationRuntime, code::AbstractString)
    pipe = open_capture_pipe()
    chunks = Channel{EvalStreamEvent}(EVAL_STREAM_CAPACITY)
    forwarder = @async stream_pipe_output!(pipe.out, chunks)
    producer = @async begin
        try
            output = terminal_io_context(runtime.terminal, pipe.in)
            redirect_stdout(output) do
                redirect_stderr(output) do
                    try
                        run_pkg_command(code, output)
                    catch error
                        showerror(pipe.in, error, catch_backtrace())
                    end
                end
            end
        finally
            close(pipe.in)
        end
    end
    runtime.active_stream = StreamingEval(producer, forwarder, chunks)
end

"""Classify normal input and start streaming when it is complete code."""
function begin_input_for_host(
    runtime::EvaluationRuntime, code::AbstractString)::Cint
    ast, status = classify_input(runtime.session, code)
    status != Evaluation_Complete && return Cint(status)
    run_ast_streaming!(runtime, _ -> ast, code)
    return Cint(Evaluation_Complete)
end

"""Start one streaming Julia help-mode query."""
function begin_help_for_host(
    runtime::EvaluationRuntime, code::AbstractString)::Cint
    run_ast_streaming!(
        runtime,
        io -> REPL.helpmode(
            io, code, runtime.session.context_module), code)
    return Cint(Evaluation_Complete)
end

"""Start one streaming Pkg REPL-mode command."""
function begin_pkg_for_host(
    runtime::EvaluationRuntime, code::AbstractString)::Cint
    run_pkg_streaming!(runtime, code)
    return Cint(Evaluation_Complete)
end

"""Return one pending, chunk, or complete value for the active stream."""
function poll_evaluation(runtime::EvaluationRuntime)::EvaluationPoll
    stream = runtime.active_stream
    stream === nothing && return EvaluationPoll(Int32(2), "")

    yield()
    if isready(stream.chunks)
        event = take!(stream.chunks)
        if event isa EvalOutputChunk
            return EvaluationPoll(Int32(1), event.text)
        end
        return EvaluationPoll(Int32(0), "")
    end
    if istaskdone(stream.forwarder)
        wait(stream.producer)
        wait(stream.forwarder)
        runtime.active_stream = nothing
        return EvaluationPoll(Int32(2), "")
    end
    return EvaluationPoll(Int32(0), "")
end

"""Evaluate one line through the streaming compatibility API."""
function evaluate_line(code::AbstractString)::String
    runtime = EvaluationRuntime()
    status = begin_input_for_host(runtime, code)
    status == Cint(Evaluation_Incomplete) && return ""

    output = IOBuffer()
    while true
        poll = poll_evaluation(runtime)
        if poll.status == Int32(1)
            print(output, poll.chunk)
        elseif poll.status == Int32(2)
            break
        end
    end
    return String(take!(output))
end