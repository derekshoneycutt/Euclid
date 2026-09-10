"""Portable key values shared with the native registry protocol."""
@enum HotkeyKey::Int32 begin
    HotkeyA = 1
    HotkeyB
    HotkeyC
    HotkeyD
    HotkeyE
    HotkeyF
    HotkeyG
    HotkeyH
    HotkeyI
    HotkeyJ
    HotkeyK
    HotkeyL
    HotkeyM
    HotkeyN
    HotkeyO
    HotkeyP
    HotkeyQ
    HotkeyR
    HotkeyS
    HotkeyT
end

"""One semantic binding desired by Julia policy."""
struct HotkeyBinding
    action::LogicalAction
    key::HotkeyKey
    modifiers::UInt8
    scope::Int32
end

struct RegisterHotkeys end

struct HotkeyRegistryBegin
    generation::UInt64
    expected_count::Int32
end

struct HotkeyRegistryEntry
    generation::UInt64
    index::Int32
    binding::HotkeyBinding
end

struct HotkeyRegistryCommit
    generation::UInt64
end

struct HotkeyRegistryResult
    generation::UInt64
    accepted::Bool
    reason::Int32
    offending_index::Int32
end

"""Policy owner for desired semantic chords and accepted native generation."""
mutable struct HotkeyController
    generation::UInt64
    accepted_generation::UInt64
    bindings::Vector{HotkeyBinding}
    terminal_controller::EuclidActorRuntime.ActorId
end

"""Emit one complete generation of desired bindings in stable index order."""
function EuclidActorRuntime.receive!(
    actor::HotkeyController, context::EuclidActorRuntime.ActorContext,
    _message::RegisterHotkeys)::Nothing
    actor.generation += UInt64(1)
    generation = actor.generation
    EuclidActorRuntime.emit!(context,
        HotkeyRegistryBegin(generation, Int32(length(actor.bindings))))
    for (index, binding) in enumerate(actor.bindings)
        EuclidActorRuntime.emit!(context,
            HotkeyRegistryEntry(generation, Int32(index - 1), binding))
    end
    EuclidActorRuntime.emit!(context, HotkeyRegistryCommit(generation))
    return nothing
end

"""Route a normalized semantic action to its action-specific policy owner."""
function EuclidActorRuntime.receive!(
    actor::HotkeyController, context::EuclidActorRuntime.ActorContext,
    message::HotkeyTriggered)::Nothing
    if message.action === ToggleTerminal
        EuclidActorRuntime.send!(
            context, actor.terminal_controller, message)
    end
    return nothing
end

"""Remember only native acceptance of the controller's current generation."""
function EuclidActorRuntime.receive!(
    actor::HotkeyController, _context::EuclidActorRuntime.ActorContext,
    result::HotkeyRegistryResult)::Nothing
    if result.accepted && result.generation == actor.generation
        actor.accepted_generation = result.generation
    end
    return nothing
end