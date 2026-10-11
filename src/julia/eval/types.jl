"""The outcome of submitting source to the persistent Julia REPL session."""
@enum Evaluation_Status begin
    Evaluation_Incomplete
    Evaluation_Complete
    Evaluation_Exit
end

"""One evaluation outcome with plain-text REPL-compatible output."""
struct EvaluationResult
    status::Evaluation_Status
    output::String
end

"""One completion replacement using Odin's 0-indexed end-exclusive bytes."""
struct CompletionResult
    found::Bool
    replacement_start::Int
    replacement_end::Int
    insertion::String
end

"""Persistent Julia REPL evaluation state."""
mutable struct EvaluationSession
    backend::REPL.REPLBackend
    input_number::Int
    context_module::Module
end

"""A plain-text display sink for an embedded REPL evaluation."""
struct PlainTextDisplay <: AbstractDisplay
    output::IO
    context_module::Module
end

"""One event produced while a streaming evaluation is in flight."""
abstract type EvalStreamEvent end

"""One captured slice of plain-text REPL-compatible output."""
struct EvalOutputChunk <: EvalStreamEvent
    text::String
end

"""One pure streaming poll result: 0 pending, 1 chunk, or 2 complete."""
struct EvaluationPoll
    status::Int32
    chunk::String
end

const EVAL_STREAM_CAPACITY = 64
const EVAL_STREAM_CHUNK_MAX_BYTES = 4 * 1024

"""One in-flight streaming evaluation and its bounded output channel."""
mutable struct StreamingEval
    producer::Task
    forwarder::Task
    chunks::Channel{EvalStreamEvent}
end

"""Mutable bridge-free evaluation state with exactly one persistent session."""
mutable struct EvaluationRuntime
    session::EvaluationSession
    active_stream::Union{Nothing,StreamingEval}
    terminal::InteractiveTerminal
    process_client::Terminal.ProcessClient
    tick_client::Ticks.TickClient
    terminal_container_client::TerminalContainer.Client
end

"""Create a persistent REPL session beginning with input number one."""
EvaluationSession(context_module::Module=Main) =
    EvaluationSession(REPL.REPLBackend(), 1, context_module)

"""Create a bridge-free runtime containing exactly one evaluation session."""
EvaluationRuntime(context_module::Module=Main) =
    create_eval_runtime(context_module)

"""Create one bridge-free Julia evaluation runtime."""
function create_eval_runtime(
    context_module::Module=Main; session_generation::UInt64=UInt64(1))
    return EvaluationRuntime(
        EvaluationSession(context_module), nothing, InteractiveTerminal(),
        Terminal.ProcessClient(),
        Ticks.TickClient(session_generation),
        TerminalContainer.Client(session_generation))
end