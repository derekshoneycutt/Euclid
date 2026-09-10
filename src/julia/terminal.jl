module Terminal

export Capabilities, ColorLevel, TextEncoding
export capabilities, dimensions, interactive_input_available
export ProcessOutcome, TerminalProcess, TerminalProcessError, TerminalProcessResult
export cancel_process, process_running, run_process, start_process, wait_process

const CAPABILITY_VERSION = UInt16(3)
const CAPABILITIES_CONTEXT_KEY = :euclid_terminal_capabilities
const PROCESS_CONTEXT_KEY = :euclid_terminal_process_client
const PROCESS_REQUEST_CAPACITY = 4
const PROCESS_ARGUMENT_CAPACITY = 256
const PROCESS_ARGUMENT_MAX_BYTES = 4096
const PROCESS_ARGUMENT_TOTAL_MAX_BYTES = 65536
const PROCESS_WORKING_DIRECTORY_MAX_BYTES = 4096
const PROCESS_ENVIRONMENT_CAPACITY = 61
const PROCESS_ENVIRONMENT_TOTAL_MAX_BYTES = 16384

Base.@enum TextEncoding::UInt8 begin
    EncodingUnknown = 0
    UTF8 = 1
end

Base.@enum ColorLevel::UInt8 begin
    ColorUnknown = 0
    ColorNone = 1
    ANSI16 = 2
    Indexed256 = 3
    Truecolor = 4
end

"""Immutable snapshot of the terminal surface implemented by the host."""
struct Capabilities
    version::UInt16
    encoding::TextEncoding
    color::ColorLevel
    alternate_screen::Bool
    bracketed_paste::Bool
    focus_events::Bool
    sgr_mouse::Bool
    modify_other_keys_level::UInt8
    kitty_keyboard_flags::UInt8
    query_modify_other_keys::Bool
    query_kitty_keyboard::Bool
    query_primary_device_attributes::Bool
    query_secondary_device_attributes::Bool
    query_device_status::Bool
    query_cursor_position::Bool
    query_private_mode_status::Bool
    query_window_pixels::Bool
    query_cell_pixels::Bool
    query_text_area_size::Bool
    kitty_graphics::Bool
    sixel_graphics::Bool
    iterm2_inline_images::Bool
    hyperlinks::Bool
    clipboard_writes::Bool
    synchronized_output::Bool
end

Base.@enum ProcessOutcome::Int32 begin
    ProcessExited = 0
    ProcessSignalled = 1
    ProcessCancelled = 2
    ProcessInfrastructureFailure = 3
end

"""Final status of one Odin-owned terminal process."""
struct TerminalProcessResult
    outcome::ProcessOutcome
    status::Int32
end

"""Public error raised when a terminal process request cannot be admitted."""
struct TerminalProcessError <: Exception
    message::String
end

"""Semantic handle for one admitted foreground terminal process."""
mutable struct TerminalProcess
    request_id::UInt64
    operation_slot::UInt32
    operation_generation::UInt64
    running::Bool
    result::Core.Union{Core.Nothing,TerminalProcessResult}
    completion::Base.Channel{TerminalProcessResult}
    client::Core.Any
end

"""One explicit environment mutation supplied to the native plan builder."""
struct ProcessEnvironmentChange
    unset::Bool
    key::String
    value::String
end

"""Validated direct launch values copied from one public API invocation."""
struct ProcessLaunchValues
    arguments::Vector{String}
    working_directory::String
    environment::Vector{ProcessEnvironmentChange}
end

"""Evaluation-owned launch request transferred to the process actor."""
struct ProcessLaunchRequest
    request_id::UInt64
    arguments::Vector{String}
    working_directory::String
    environment::Vector{ProcessEnvironmentChange}
    inherit_environment::Bool
    handle::TerminalProcess
    admission::Base.Channel{Core.Any}
end

"""Evaluation-owned graceful cancellation request."""
struct ProcessCancelRequest
    handle::TerminalProcess
end

"""Bounded broker shared by one evaluator and its process service actor."""
mutable struct ProcessClient
    requests::Base.Channel{Core.Any}
    next_request_id::UInt64
    active_request_id::UInt64
end

"""Create an idle bounded process broker for one host runtime."""
function ProcessClient()
    return ProcessClient(
        Base.Channel{Core.Any}(PROCESS_REQUEST_CAPACITY), UInt64(1), UInt64(0))
end

"""Render one public process error without exposing internal state."""
function Base.showerror(io::IO, error::TerminalProcessError)
    Base.print(io, error.message)
end

const CONSERVATIVE_CAPABILITIES = Capabilities(
    CAPABILITY_VERSION, EncodingUnknown, ColorUnknown,
    false, false, false, false, UInt8(0), UInt8(0),
    false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false)

"""Return conservative capabilities for IO not owned by Euclid Terminal."""
function capabilities(_io::IO)::Capabilities
    return CONSERVATIVE_CAPABILITIES
end

"""Return capabilities associated with the current evaluation input."""
function capabilities()::Capabilities
    return capabilities(stdin)
end

"""Return the current terminal dimensions or `nothing` outside Euclid Terminal."""
function dimensions(_io::IO)
    return nothing
end

"""Return dimensions associated with the current evaluation input."""
function dimensions()
    return dimensions(stdin)
end

"""Return whether the current input belongs to an interactive evaluation."""
function interactive_input_available(_io::IO)::Bool
    return false
end

"""Return whether the current evaluation can request terminal input."""
function interactive_input_available()::Bool
    return interactive_input_available(stdin)
end

"""Return capabilities inherited by one output context."""
function context_capabilities(io::IO)::Capabilities
    return get(io, CAPABILITIES_CONTEXT_KEY, CONSERVATIVE_CAPABILITIES)
end

"""Run an operation with terminal-process authority scoped to the current task."""
function with_process_client(operation, client::ProcessClient)
    return task_local_storage(operation, PROCESS_CONTEXT_KEY, client)
end

"""Return the current evaluation's process broker or reject unsupported context."""
function current_process_client()::ProcessClient
    client = get(task_local_storage(), PROCESS_CONTEXT_KEY, Core.nothing)
    client isa ProcessClient || throw(TerminalProcessError(
        "terminal process operations require an active Euclid evaluation"))
    return client
end

"""Normalize bounded environment set and unset operations from pairs."""
function process_environment_changes(environment)::Vector{ProcessEnvironmentChange}
    changes = ProcessEnvironmentChange[]
    environment === Core.nothing && return changes
    for entry in environment
        entry isa Pair || throw(TerminalProcessError(
            "terminal process environment entries must be pairs"))
        key = String(entry.first)
        value = entry.second
        isempty(key) && throw(TerminalProcessError(
            "terminal process environment keys must not be empty"))
        change = value === Core.nothing ?
            ProcessEnvironmentChange(true, key, "") :
            ProcessEnvironmentChange(false, key, String(value))
        Base.push!(changes, change)
    end
    length(changes) <= PROCESS_ENVIRONMENT_CAPACITY || throw(
        TerminalProcessError("too many terminal process environment changes"))
    total = Base.sum(change ->
        ncodeunits(change.key) + ncodeunits(change.value), changes; init=0)
    total <= PROCESS_ENVIRONMENT_TOTAL_MAX_BYTES || throw(
        TerminalProcessError("terminal process environment is too large"))
    return changes
end

"""Validate and copy one direct Julia command into bounded launch values."""
function process_launch_values(
    command::Cmd, directory, environment)::ProcessLaunchValues
    command.flags == 0 || throw(TerminalProcessError(
        "detached and platform-specific Cmd flags are unsupported"))
    command.cpus === Core.nothing || throw(TerminalProcessError(
        "Cmd CPU affinity is unsupported"))
    arguments = String[String(argument) for argument in command.exec]
    isempty(arguments) && throw(TerminalProcessError(
        "terminal process command must contain an executable"))
    length(arguments) <= PROCESS_ARGUMENT_CAPACITY || throw(
        TerminalProcessError("too many terminal process arguments"))
    for argument in arguments
        ncodeunits(argument) <= PROCESS_ARGUMENT_MAX_BYTES || throw(
            TerminalProcessError("terminal process argument is too large"))
    end
    Base.sum(ncodeunits, arguments; init=0) <=
        PROCESS_ARGUMENT_TOTAL_MAX_BYTES || throw(
            TerminalProcessError("terminal process arguments are too large"))
    working_directory = realpath(String(directory))
    ncodeunits(working_directory) <= PROCESS_WORKING_DIRECTORY_MAX_BYTES || throw(
        TerminalProcessError("terminal process working directory is too large"))
    return ProcessLaunchValues(
        arguments, working_directory,
        process_environment_changes(environment))
end

"""Request one foreground PTY or ConPTY process and wait only for admission."""
function start_process(
    command::Cmd; dir=pwd(), env=Core.nothing,
    inherit_environment::Bool=true)::TerminalProcess
    client = current_process_client()
    client.active_request_id == 0 || throw(TerminalProcessError(
        "a terminal process is already active"))
    launch = process_launch_values(command, dir, env)
    request_id = client.next_request_id
    client.next_request_id += 1
    completion = Base.Channel{TerminalProcessResult}(1)
    process = TerminalProcess(
        request_id, UInt32(0), UInt64(0), false, Core.nothing,
        completion, client)
    admission = Base.Channel{Core.Any}(1)
    client.active_request_id = request_id
    Base.put!(client.requests, ProcessLaunchRequest(
        request_id, launch.arguments, launch.working_directory,
        launch.environment,
        inherit_environment, process, admission))
    rejection = take!(admission)
    rejection === Core.nothing || throw(rejection)
    return process
end

"""Wait for one process's final typed result, returning the retained result thereafter."""
function wait_process(process::TerminalProcess)::TerminalProcessResult
    process.result === Core.nothing || return process.result
    process.result = take!(process.completion)
    return process.result
end

"""Request graceful cancellation of one running process."""
function cancel_process(process::TerminalProcess)::Bool
    process.running || return false
    Base.put!(process.client.requests, ProcessCancelRequest(process))
    return true
end

"""Return whether the semantic process handle still owns a native operation."""
function process_running(process::TerminalProcess)::Bool
    return process.running
end

"""Start one foreground terminal process and wait for its final result."""
function run_process(command::Cmd; keywords...)::TerminalProcessResult
    return wait_process(start_process(command; keywords...))
end

end