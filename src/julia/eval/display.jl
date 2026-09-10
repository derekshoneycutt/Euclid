"""Open a connected, async-capable pipe pair for redirected output."""
function open_capture_pipe()::Pipe
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
    return pipe
end

"""Forward capture-pipe bytes into a bounded stream-event channel."""
function stream_pipe_output!(pipe_out::IO, chunks::Channel{EvalStreamEvent})
    try
        while !eof(pipe_out)
            bytes = readavailable(pipe_out)
            offset = 1
            while offset <= length(bytes)
                stop = min(offset + EVAL_STREAM_CHUNK_MAX_BYTES - 1, length(bytes))
                while stop < length(bytes) && !isvalid(String, @view(bytes[offset:stop]))
                    stop -= 1
                end
                put!(chunks, EvalOutputChunk(String(bytes[offset:stop])))
                offset = stop + 1
            end
        end
    finally
        close(chunks)
    end
end

"""Return Julia's own colorized startup banner text."""
startup_banner_for_host()::String =
    sprint(io -> REPL.banner(io), context=:color => true)

"""Report that the embedded display supports plain-text values."""
Base.displayable(_display::PlainTextDisplay, ::MIME"text/plain") = true

"""Render one value with Julia's standard REPL plain-text formatting."""
function Base.display(sink::PlainTextDisplay, mime::MIME"text/plain", value)
    context = IOContext(
        sink.output, :color => true, :limit => true,
        :module => sink.context_module)
    Base.invokelatest(REPL.show_repl, context, mime, value)
    println(sink.output)
    return nothing
end

Base.display(display::PlainTextDisplay, value) =
    Base.display(display, MIME"text/plain"(), value)

"""Append Julia's standard plain-text REPL response formatting."""
function append_repl_response!(
    output::IO, response::Pair{Any,Bool}, code::AbstractString,
    context_module::Module=Main)
    value, is_error = response
    if is_error
        context = IOContext(output, :color => true)
        REPL.repl_display_error(context, Base.scrub_repl_backtrace(value))
    elseif value !== nothing && !REPL.ends_with_semicolon(code)
        context = IOContext(
            output, :color => true, :limit => true,
            :module => context_module)
        Base.invokelatest(REPL.show_repl, context, MIME"text/plain"(), value)
        println(output)
    end
    return nothing
end

"""Evaluate one AST and capture REPL-compatible output synchronously."""
function run_ast(session::EvaluationSession, build_ast, code::AbstractString)::String
    output = mktemp() do _path, io
        ast = build_ast(io)
        display = PlainTextDisplay(io, session.context_module)
        response = nothing
        pushdisplay(display)
        try
            response = redirect_stdout(io) do
                redirect_stderr(io) do
                    REPL.eval_user_input(
                        ast, session.backend, session.context_module)
                    take!(session.backend.response_channel)
                end
            end
        finally
            popdisplay(display)
        end
        append_repl_response!(io, response, code, session.context_module)
        flush(io)
        seekstart(io)
        return read(io, String)
    end
    session.input_number += 1
    return output
end