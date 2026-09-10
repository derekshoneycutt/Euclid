const INTERACTIVE_EVENT_CAPACITY = 4
const INTERACTIVE_TERMINAL_SIZE = (34, 128)
const INTERACTIVE_INPUT_MAX_BYTES = 16
const TERMINAL_MODIFY_OTHER_KEYS_MAX_LEVEL = UInt8(2)
const TERMINAL_KITTY_KEYBOARD_SUPPORTED_FLAGS = UInt8(31)
const TERMINAL_CAPABILITY_FEATURE_MASK = UInt32(0x000fffff)

const CAPABILITY_ALTERNATE_SCREEN = UInt32(1 << 0)
const CAPABILITY_BRACKETED_PASTE = UInt32(1 << 1)
const CAPABILITY_FOCUS_EVENTS = UInt32(1 << 2)
const CAPABILITY_SGR_MOUSE = UInt32(1 << 3)
const CAPABILITY_QUERY_MODIFY_OTHER_KEYS = UInt32(1 << 4)
const CAPABILITY_QUERY_KITTY_KEYBOARD = UInt32(1 << 5)
const CAPABILITY_QUERY_PRIMARY_DEVICE_ATTRIBUTES = UInt32(1 << 6)
const CAPABILITY_HYPERLINKS = UInt32(1 << 7)
const CAPABILITY_CLIPBOARD_WRITES = UInt32(1 << 8)
const CAPABILITY_SYNCHRONIZED_OUTPUT = UInt32(1 << 9)
const CAPABILITY_QUERY_SECONDARY_DEVICE_ATTRIBUTES = UInt32(1 << 10)
const CAPABILITY_QUERY_DEVICE_STATUS = UInt32(1 << 11)
const CAPABILITY_QUERY_CURSOR_POSITION = UInt32(1 << 12)
const CAPABILITY_QUERY_PRIVATE_MODE_STATUS = UInt32(1 << 13)
const CAPABILITY_QUERY_WINDOW_PIXELS = UInt32(1 << 14)
const CAPABILITY_QUERY_CELL_PIXELS = UInt32(1 << 15)
const CAPABILITY_QUERY_TEXT_AREA_SIZE = UInt32(1 << 16)
const CAPABILITY_KITTY_GRAPHICS = UInt32(1 << 17)
const CAPABILITY_SIXEL_GRAPHICS = UInt32(1 << 18)
const CAPABILITY_ITERM2_INLINE_IMAGES = UInt32(1 << 19)

@enum InteractiveEventKind::Int32 begin
    InteractiveAcquired = 1
    InteractiveReleased = 2
end

"""One input-ownership transition produced by an evaluation task."""
struct InteractiveEvent
    kind::InteractiveEventKind
end

"""One fixed-size terminal input adapter shared by serial evaluations."""
mutable struct InteractiveTerminal
    input::Base.PipeEndpoint
    writer::Base.PipeEndpoint
    events::Channel{InteractiveEvent}
    acquired::Bool
    read_lock::ReentrantLock
    read_depth::Int
    dimensions::Tuple{Int,Int}
    geometry_generation::UInt64
    capabilities::Terminal.Capabilities
end

"""Read-aware stdin facade over one interactive terminal pipe."""
struct InteractiveInput <: Base.AbstractPipe
    terminal::InteractiveTerminal
end

"""Expose the underlying libuv handle required by terminal raw-mode probes."""
function Base.getproperty(input::InteractiveInput, name::Symbol)
    name === :handle && return getfield(getfield(input, :terminal), :input).handle
    return getfield(input, name)
end

"""Create a bounded terminal adapter with a raw-mode-compatible libuv handle."""
function InteractiveTerminal()
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
    return InteractiveTerminal(
        pipe.out, pipe.in, Channel{InteractiveEvent}(INTERACTIVE_EVENT_CAPACITY),
        false, ReentrantLock(), 0, INTERACTIVE_TERMINAL_SIZE, UInt64(0),
        Terminal.CONSERVATIVE_CAPABILITIES)
end

"""Return the libuv reader used when Julia redirects process-level stdin."""
Base.pipe_reader(input::InteractiveInput) = input.terminal.input

"""Report whether the underlying interactive input pipe remains open."""
Base.isopen(input::InteractiveInput) = isopen(input.terminal.input)

"""Report bytes already buffered for nonblocking delegated reads."""
Base.bytesavailable(input::InteractiveInput) = bytesavailable(input.terminal.input)

"""Report end-of-file from the underlying interactive input pipe."""
Base.eof(input::InteractiveInput) = eof(input.terminal.input)

"""Read available bytes without creating a new blocking-read lease."""
Base.readavailable(input::InteractiveInput) = readavailable(input.terminal.input)

"""Close the underlying interactive input endpoint."""
Base.close(input::InteractiveInput) = close(input.terminal.input)

"""Create the read-aware stdin facade for one evaluation."""
interactive_input(terminal::InteractiveTerminal) = InteractiveInput(terminal)

"""Close both libuv pipe endpoints after the owning evaluation runtime stops."""
function close_interactive_terminal!(terminal::InteractiveTerminal)::Nothing
    isopen(terminal.writer) && close(terminal.writer)
    isopen(terminal.input) && close(terminal.input)
    return nothing
end

"""Return the stable host snapshot associated with this evaluation input."""
function Terminal.capabilities(
    input::InteractiveInput)::Terminal.Capabilities
    return input.terminal.capabilities
end

"""Return the current generation-ordered size for this evaluation input."""
function Terminal.dimensions(input::InteractiveInput)::Tuple{Int,Int}
    return displaysize(input.terminal)
end

"""Report that this input can acquire an evaluation-scoped terminal lease."""
function Terminal.interactive_input_available(
    _input::InteractiveInput)::Bool
    return true
end

"""Return the latest generation-ordered host dimensions in row-column order."""
Base.displaysize(terminal::InteractiveTerminal) = terminal.dimensions

"""Decode one host text-encoding value or reject an unknown enum member."""
function terminal_text_encoding(value::UInt8)
    try
        return Terminal.TextEncoding(value)
    catch error
        error isa ArgumentError || rethrow()
        return nothing
    end
end

"""Decode one host color-level value or reject an unknown enum member."""
function terminal_color_level(value::UInt8)
    try
        return Terminal.ColorLevel(value)
    catch error
        error isa ArgumentError || rethrow()
        return nothing
    end
end

"""Install one newer accepted host geometry in row-column order."""
function update_terminal_geometry!(
    terminal::InteractiveTerminal, rows::Integer, columns::Integer,
    generation::UInt64)::Bool
    rows > 0 && columns > 0 && generation > 0 || return false
    generation < terminal.geometry_generation && return false
    dimensions = (Int(rows), Int(columns))
    generation == terminal.geometry_generation &&
        return dimensions == terminal.dimensions
    terminal.dimensions = dimensions
    terminal.geometry_generation = generation
    return true
end

"""Install one supported versioned host capability snapshot."""
function update_terminal_capabilities!(
    terminal::InteractiveTerminal, version::UInt16, encoding::UInt8,
    color::UInt8, modify_other_keys_level::UInt8,
    kitty_keyboard_flags::UInt8, features::UInt32)::Bool
    version == Terminal.CAPABILITY_VERSION || return false
    features & ~TERMINAL_CAPABILITY_FEATURE_MASK == 0 || return false
    modify_other_keys_level <= TERMINAL_MODIFY_OTHER_KEYS_MAX_LEVEL || return false
    kitty_keyboard_flags & ~TERMINAL_KITTY_KEYBOARD_SUPPORTED_FLAGS == 0 ||
        return false
    text_encoding = terminal_text_encoding(encoding)
    text_encoding === nothing && return false
    color_level = terminal_color_level(color)
    color_level === nothing && return false
    terminal.capabilities = Terminal.Capabilities(
        version, text_encoding, color_level,
        features & CAPABILITY_ALTERNATE_SCREEN != 0,
        features & CAPABILITY_BRACKETED_PASTE != 0,
        features & CAPABILITY_FOCUS_EVENTS != 0,
        features & CAPABILITY_SGR_MOUSE != 0,
        modify_other_keys_level, kitty_keyboard_flags,
        features & CAPABILITY_QUERY_MODIFY_OTHER_KEYS != 0,
        features & CAPABILITY_QUERY_KITTY_KEYBOARD != 0,
        features & CAPABILITY_QUERY_PRIMARY_DEVICE_ATTRIBUTES != 0,
        features & CAPABILITY_QUERY_SECONDARY_DEVICE_ATTRIBUTES != 0,
        features & CAPABILITY_QUERY_DEVICE_STATUS != 0,
        features & CAPABILITY_QUERY_CURSOR_POSITION != 0,
        features & CAPABILITY_QUERY_PRIVATE_MODE_STATUS != 0,
        features & CAPABILITY_QUERY_WINDOW_PIXELS != 0,
        features & CAPABILITY_QUERY_CELL_PIXELS != 0,
        features & CAPABILITY_QUERY_TEXT_AREA_SIZE != 0,
        features & CAPABILITY_KITTY_GRAPHICS != 0,
        features & CAPABILITY_SIXEL_GRAPHICS != 0,
        features & CAPABILITY_ITERM2_INLINE_IMAGES != 0,
        features & CAPABILITY_HYPERLINKS != 0,
        features & CAPABILITY_CLIPBOARD_WRITES != 0,
        features & CAPABILITY_SYNCHRONIZED_OUTPUT != 0)
    return true
end

"""Attach the current accepted display size to one redirected Julia stream."""
terminal_io_context(terminal::InteractiveTerminal, io::IO) =
    IOContext(io,
        :color => terminal.capabilities.color > Terminal.ColorNone,
        :displaysize => displaysize(terminal),
        Terminal.CAPABILITIES_CONTEXT_KEY => terminal.capabilities)

"""Deliver one bounded terminal byte sequence to the active Julia reader."""
function interactive_write!(terminal::InteractiveTerminal, bytes)::Bool
    terminal.acquired || return false
    0 < length(bytes) <= INTERACTIVE_INPUT_MAX_BYTES || return false
    write(terminal.writer, bytes)
    return true
end

"""Acquire input before one outer read that may block."""
function interactive_acquire!(terminal::InteractiveTerminal)::Nothing
    terminal.acquired && return nothing
    terminal.acquired = true
    put!(terminal.events, InteractiveEvent(InteractiveAcquired))
    return nothing
end

"""Release interactive ownership after evaluation completion or failure."""
function interactive_release!(terminal::InteractiveTerminal)::Nothing
    terminal.acquired || return nothing
    terminal.acquired = false
    put!(terminal.events, InteractiveEvent(InteractiveReleased))
    return nothing
end

"""Run one read while coalescing delegated calls into one ownership lease."""
function with_interactive_read(
    operation, input::InteractiveInput; buffered_ready=(_stream -> false))
    terminal = input.terminal
    lock(terminal.read_lock)
    terminal.read_depth += 1
    outer_blocking = terminal.read_depth == 1 && !buffered_ready(terminal.input)
    outer_blocking && interactive_acquire!(terminal)
    try
        return operation(terminal.input)
    finally
        terminal.read_depth -= 1
        outer_blocking && interactive_release!(terminal)
        unlock(terminal.read_lock)
    end
end

"""Read one menu character under a semantic lease when blocking is possible."""
Base.read(input::InteractiveInput, ::Type{Char}) =
    with_interactive_read(
        stream -> read(stream, Char), input;
        buffered_ready=stream -> bytesavailable(stream) > 0)

"""Fill one array under a semantic input lease when blocking is possible."""
Base.read!(input::InteractiveInput, destination::AbstractArray) =
    with_interactive_read(
        stream -> read!(stream, destination), input;
        buffered_ready=stream -> bytesavailable(stream) >= sizeof(destination))

"""Fill raw storage under a semantic input lease when blocking is possible."""
Base.unsafe_read(input::InteractiveInput, pointer::Ptr{UInt8}, bytes::UInt) =
    with_interactive_read(
        stream -> unsafe_read(stream, pointer, bytes), input;
        buffered_ready=stream -> UInt(bytesavailable(stream)) >= bytes)

"""Read one terminal line, accepting carriage return as the Enter delimiter."""
function read_interactive_line(stream::IO; keep::Bool=false)::String
    output = IOBuffer()
    while true
        character = try
            read(stream, Char)
        catch error
            error isa EOFError || rethrow()
            break
        end
        if character == '\r' || character == '\n'
            keep && write(output, '\n')
            break
        end
        write(output, character)
    end
    return String(take!(output))
end

"""Read one line under a single semantic input lease."""
Base.readline(input::InteractiveInput; keep::Bool=false) =
    with_interactive_read(
        stream -> read_interactive_line(stream; keep=keep), input)

"""Take one pending terminal ownership event without blocking."""
function take_interactive_event!(terminal::InteractiveTerminal)
    isready(terminal.events) || return nothing
    return take!(terminal.events)
end
