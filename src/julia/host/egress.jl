"""Primitive host adapter for one optional terminal visibility command."""
struct HostTerminalVisibilityCommand
    available::Bool
    decision_id::UInt64
    open::Bool
    x::Float32
    y::Float32
    width::Float32
    height::Float32
end

"""Primitive host adapter for one optional registry transaction command."""
struct HostHotkeyRegistryCommand
    kind::Int32
    generation::UInt64
    index::Int32
    expected_count::Int32
    action::Int32
    key::Int32
    modifiers::UInt8
    scope::Int32
end

"""Primitive host adapter for one optional completion result or failure."""
struct HostCompletionCommand
    kind::Int32
    request_id::UInt64
    found::Bool
    replacement_start::Int32
    replacement_end::Int32
    show_candidates::Bool
    insertion::String
    failure_reason::Int32
end

"""Primitive host adapter for one optional shell interpolation outcome."""
struct HostShellInterpolationCommand
    status::Int32
    request_id::UInt64
    element_count::Int32
    packed_elements::String
    diagnostic::String
end

"""Primitive host adapter for one optional shell-session policy command."""
struct HostShellSessionCommand
    kind::Int32
    request_id::UInt64
    owner_id::UInt64
    owner_generation::UInt64
    operation_slot::UInt32
    operation_generation::UInt64
end

"""Primitive host adapter for one optional structured terminal process launch."""
struct HostTerminalProcessCommand
    available::Bool
    request_id::UInt64
    owner_id::UInt64
    owner_generation::UInt64
    argument_count::Int32
    packed_arguments::String
    working_directory::String
    environment_count::Int32
    packed_environment::String
    inherit_environment::Bool
end

"""Primitive host adapter for one optional evaluation lifecycle command."""
struct HostEvaluationCommand
    kind::Int32
    request_id::UInt64
    text::String
    byte_count::Int32
    truncated_bytes::UInt64
end

"""Primitive host adapter for one optional Julia-session lifecycle result."""
struct HostSessionLifecycleCommand
    kind::Int32
    generation::UInt64
end

"""Primitive host adapter for one optional native tick stream command."""
struct HostTickStreamCommand
    kind::Int32
    session_generation::UInt64
    stream_generation::UInt64
    requested_period_ns::UInt64
end

"""Primitive host adapter for one optional container configuration request."""
struct HostTerminalContainerConfigureCommand
    available::Bool
    generation::UInt64
    background_red::UInt8
    background_green::UInt8
    background_blue::UInt8
    background_alpha::UInt8
    foreground_red::UInt8
    foreground_green::UInt8
    foreground_blue::UInt8
    foreground_alpha::UInt8
    border_red::UInt8
    border_green::UInt8
    border_blue::UInt8
    border_alpha::UInt8
    border_width::Float32
    resize_hit_width::Float32
    handle_height::Float32
    move_mode::UInt8
    resize_axes::UInt8
    initial_x::Float32
    initial_y::Float32
    initial_width::Float32
    initial_height::Float32
    allowed_x::Float32
    allowed_y::Float32
    allowed_width::Float32
    allowed_height::Float32
    minimum_columns::UInt16
    minimum_rows::UInt16
    maximum_columns::UInt16
    maximum_rows::UInt16
end

"""Primitive host adapter for one optional broker-processed acknowledgement."""
struct HostTerminalContainerObservedCommand
    available::Bool
    session_generation::UInt64
    bounds_generation::UInt64
    interaction_id::UInt64
end

"""Remove and return the first outgoing command of one concrete type."""
function take_outgoing_command!(runtime::HostRuntime, command_type)
    index = findfirst(command -> command isa command_type, runtime.actors.outgoing)
    index === nothing && return nothing
    return popat!(runtime.actors.outgoing, index)
end

"""Take one session started or quiescent result without consuming other output."""
function take_session_lifecycle_for_host(
    runtime::HostRuntime)::HostSessionLifecycleCommand
    command = take_outgoing_command!(
        runtime, Union{JuliaSessionStarted,JuliaSessionQuiescent})
    command === nothing &&
        return HostSessionLifecycleCommand(Int32(0), UInt64(0))
    kind = command isa JuliaSessionStarted ? Int32(1) : Int32(2)
    return HostSessionLifecycleCommand(kind, command.generation)
end

"""Take one tick configure or stop command without consuming other output."""
function take_tick_stream_for_host(runtime::HostRuntime)::HostTickStreamCommand
    command = take_outgoing_command!(runtime,
        Union{TickStreamConfigureRequested,TickStreamStopRequested})
    command === nothing && return HostTickStreamCommand(
        Int32(0), UInt64(0), UInt64(0), UInt64(0))
    if command isa TickStreamConfigureRequested
        return HostTickStreamCommand(
            Int32(1), command.session_generation, command.stream_generation,
            command.requested_period_ns)
    end
    return HostTickStreamCommand(
        Int32(2), command.session_generation, command.stream_generation,
        UInt64(0))
end

"""Take one complete container configuration without consuming other output."""
function take_terminal_container_configure_for_host(
    runtime::HostRuntime)::HostTerminalContainerConfigureCommand
    command = take_outgoing_command!(runtime, TerminalContainerConfigureRequested)
    command === nothing && return HostTerminalContainerConfigureCommand(
        false, UInt64(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        0.0f0, 0.0f0, 0.0f0, UInt8(0), UInt8(0),
        0.0f0, 0.0f0, 0.0f0, 0.0f0,
        0.0f0, 0.0f0, 0.0f0, 0.0f0,
        UInt16(0), UInt16(0), UInt16(0), UInt16(0))
    config = command.config
    return HostTerminalContainerConfigureCommand(
        true, config.generation,
        config.background.red, config.background.green,
        config.background.blue, config.background.alpha,
        config.foreground.red, config.foreground.green,
        config.foreground.blue, config.foreground.alpha,
        config.border_color.red, config.border_color.green,
        config.border_color.blue, config.border_color.alpha,
        config.border_width, config.resize_hit_width, config.handle_height,
        UInt8(config.move_mode), UInt8(config.resize_axes),
        config.initial_bounds.x, config.initial_bounds.y,
        config.initial_bounds.width, config.initial_bounds.height,
        config.allowed_bounds.x, config.allowed_bounds.y,
        config.allowed_bounds.width, config.allowed_bounds.height,
        config.minimum_dimensions.columns, config.minimum_dimensions.rows,
        config.maximum_dimensions.columns, config.maximum_dimensions.rows)
end

"""Take one broker acknowledgement without consuming other outgoing output."""
function take_terminal_container_observed_for_host(
    runtime::HostRuntime)::HostTerminalContainerObservedCommand
    command = take_outgoing_command!(runtime, TerminalContainerChangeObserved)
    command === nothing && return HostTerminalContainerObservedCommand(
        false, UInt64(0), UInt64(0), UInt64(0))
    return HostTerminalContainerObservedCommand(
        true, command.session_generation, command.bounds_generation,
        command.interaction_id)
end

"""Take one registry command without consuming unrelated actor output."""
function take_hotkey_registry_for_host(
    runtime::HostRuntime)::HostHotkeyRegistryCommand
    command = take_outgoing_command!(runtime,
        Union{HotkeyRegistryBegin,HotkeyRegistryEntry,HotkeyRegistryCommit})
    command === nothing && return HostHotkeyRegistryCommand(
        Int32(0), UInt64(0), Int32(0), Int32(0), Int32(0), Int32(0),
        UInt8(0), Int32(0))
    if command isa HotkeyRegistryBegin
        return HostHotkeyRegistryCommand(
            Int32(1), command.generation, Int32(0), command.expected_count,
            Int32(0), Int32(0), UInt8(0), Int32(0))
    elseif command isa HotkeyRegistryEntry
        binding = command.binding
        return HostHotkeyRegistryCommand(
            Int32(2), command.generation, command.index, Int32(0),
            Int32(binding.action), Int32(binding.key), binding.modifiers,
            binding.scope)
    end
    return HostHotkeyRegistryCommand(
        Int32(3), command.generation, Int32(0), Int32(0), Int32(0), Int32(0),
        UInt8(0), Int32(0))
end

"""Take one terminal visibility command and its Julia-selected rectangle."""
function take_terminal_visibility_for_host(
    runtime::HostRuntime)::HostTerminalVisibilityCommand
    command = take_outgoing_command!(runtime, SetTerminalVisibility)
    command === nothing &&
        return HostTerminalVisibilityCommand(
            false, UInt64(0), false, 0.0f0, 0.0f0, 0.0f0, 0.0f0)
    rectangle = command.rectangle
    return HostTerminalVisibilityCommand(
        true, command.decision_id, command.open, rectangle.x, rectangle.y,
        rectangle.width, rectangle.height)
end

"""Take one completion command without consuming other outgoing command types."""
function take_completion_for_host(runtime::HostRuntime)::HostCompletionCommand
    command = take_outgoing_command!(
        runtime, Union{CompletionResolved,CompletionFailed})
    command === nothing && return HostCompletionCommand(
        Int32(0), UInt64(0), false, Int32(0), Int32(0), false, "", Int32(0))
    if command isa CompletionFailed
        return HostCompletionCommand(
            Int32(2), command.request_id, false, Int32(0), Int32(0), false,
            "", Int32(command.reason))
    end
    return HostCompletionCommand(
        Int32(1), command.request_id, command.found,
        Int32(command.replacement_start), Int32(command.replacement_end),
        command.show_candidates, command.insertion, Int32(0))
end

"""Encode bounded interpolation elements for C-string-safe native transfer."""
function pack_shell_interpolation_elements(elements::Vector{String})::String
    output = IOBuffer()
    for element in elements
        bytes = codeunits(element)
        print(output, ncodeunits(element), ':')
        for byte in bytes
            print(output, string(byte; base=16, pad=2))
        end
    end
    return String(take!(output))
end

"""Take one interpolation outcome without consuming unrelated commands."""
function take_shell_interpolation_for_host(
    runtime::HostRuntime)::HostShellInterpolationCommand
    command = take_outgoing_command!(runtime, ShellInterpolationResolved)
    command === nothing && return HostShellInterpolationCommand(
        Int32(0), UInt64(0), Int32(0), "", "")
    return HostShellInterpolationCommand(
        command.status, command.request_id, Int32(length(command.elements)),
        pack_shell_interpolation_elements(command.elements), command.diagnostic)
end

"""Take one begin or cancellation command without consuming unrelated output."""
function take_shell_session_for_host(
    runtime::HostRuntime)::HostShellSessionCommand
    command = take_outgoing_command!(runtime,
        Union{BeginTerminalSessionRequested,CancelTerminalSessionRequested,
            AbandonTerminalSessionRequested})
    command === nothing && return HostShellSessionCommand(
        Int32(0), UInt64(0), UInt64(0), UInt64(0), UInt32(0), UInt64(0))
    if command isa BeginTerminalSessionRequested
        return HostShellSessionCommand(
            Int32(1), command.request_id, command.owner_id,
            command.owner_generation, UInt32(0), UInt64(0))
    end
    if command isa AbandonTerminalSessionRequested
        return HostShellSessionCommand(
            Int32(3), command.request_id, command.owner_id,
            command.owner_generation, UInt32(0), UInt64(0))
    end
    return HostShellSessionCommand(
        Int32(2), UInt64(0), command.owner_id, command.owner_generation,
        command.operation_id.slot, command.operation_id.generation)
end

"""Take and pack one process launch without consuming unrelated actor output."""
function take_terminal_process_for_host(
    runtime::HostRuntime)::HostTerminalProcessCommand
    command = take_outgoing_command!(runtime, TerminalProcessLaunchRequested)
    command === nothing && return HostTerminalProcessCommand(
        false, UInt64(0), UInt64(0), UInt64(0), Int32(0), "", "",
        Int32(0), "", false)
    command = command::TerminalProcessLaunchRequested
    environment_elements = String[]
    for change in command.environment
        if change.unset
            push!(environment_elements, "1")
        else
            push!(environment_elements, "0")
        end
        push!(environment_elements, change.key)
        push!(environment_elements, change.value)
    end
    return HostTerminalProcessCommand(
        true, command.request_id, command.owner_id, command.owner_generation,
        Int32(length(command.arguments)),
        pack_shell_interpolation_elements(command.arguments),
        command.working_directory, Int32(length(command.environment)),
        pack_shell_interpolation_elements(environment_elements),
        command.inherit_environment)
end

"""Report whether earlier output prevents one evaluation completion from escaping."""
function evaluation_completion_blocked(
    outgoing, completion_index::Int, request_id)::Bool
    for index in 1:completion_index - 1
        command = outgoing[index]
        if command isa TerminalOutputBatch && command.request_id == request_id
            return true
        end
    end
    return false
end

"""Find the next evaluation command allowed by output and completion ownership."""
function evaluation_command_index(
    outgoing, allow_output::Bool, allow_completion::Bool=true)
    command_type = Union{
        TerminalOutputBatch,EvaluationCompleted,EvaluationIncomplete,
        EvaluationExitRequested,TerminalInputAcquired,TerminalInputReleased}
    allow_output && return findfirst(command -> command isa command_type, outgoing)
    priority_index = findfirst(command ->
        command isa EvaluationIncomplete ||
        command isa EvaluationExitRequested ||
        command isa TerminalInputAcquired ||
        command isa TerminalInputReleased, outgoing)
    priority_index === nothing || return priority_index
    allow_completion || return nothing
    completion_index = findfirst(command -> command isa EvaluationCompleted, outgoing)
    completion_index === nothing && return nothing
    completion = outgoing[completion_index]::EvaluationCompleted
    return evaluation_completion_blocked(
        outgoing, completion_index, completion.request_id) ? nothing : completion_index
end

"""Take one evaluation command without consuming other command types."""
function take_evaluation_for_host(
    runtime::HostRuntime, allow_output::Bool=true)::HostEvaluationCommand
    process_idle = runtime.evaluator_state.runtime.process_client.active_request_id == 0
    index = evaluation_command_index(
        runtime.actors.outgoing, allow_output && process_idle, process_idle)
    index === nothing && return HostEvaluationCommand(
        Int32(0), UInt64(0), "", Int32(0), UInt64(0))
    command = popat!(runtime.actors.outgoing, index)
    if command isa TerminalOutputBatch
        runtime.evaluator_state.outstanding_output_bytes -= command.byte_count
        if command.truncated_bytes > 0
            @host_log(
                runtime, Logging.Warn, "evaluation output truncated",
                request_id=command.request_id,
                retained_bytes=command.byte_count,
                truncated_bytes=command.truncated_bytes)
        end
        return HostEvaluationCommand(
            Int32(1), command.request_id, command.text,
            Int32(command.byte_count), command.truncated_bytes)
    elseif command isa EvaluationCompleted
        return HostEvaluationCommand(
            Int32(2), command.request_id, "", Int32(0), UInt64(0))
    elseif command isa EvaluationIncomplete
        return HostEvaluationCommand(
            Int32(3), command.request_id, "", Int32(0), UInt64(0))
    elseif command isa TerminalInputAcquired
        return HostEvaluationCommand(
            Int32(5), command.request_id, "", Int32(0), UInt64(0))
    elseif command isa TerminalInputReleased
        return HostEvaluationCommand(
            Int32(6), command.request_id, "", Int32(0), UInt64(0))
    end
    exit_request = command::EvaluationExitRequested
    return HostEvaluationCommand(
        Int32(4), exit_request.request_id, "", Int32(0),
        exit_request.session_generation)
end