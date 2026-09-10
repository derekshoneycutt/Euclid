"""Logical host actions accepted by Julia policy actors."""
@enum LogicalAction::Int32 begin
    ToggleTerminal = 1
end

"""Semantic hotkey event carrying Odin's current authoritative visibility."""
struct HotkeyTriggered
    action::LogicalAction
    current_terminal_visibility::Bool
    decision_id::UInt64
end

"""Command asking Odin to set its authoritative terminal visibility."""
struct TerminalRectangle
    x::Float32
    y::Float32
    width::Float32
    height::Float32
end

"""Command asking Odin to set its authoritative terminal visibility and geometry."""
struct SetTerminalVisibility
    decision_id::UInt64
    open::Bool
    rectangle::TerminalRectangle
end

"""Policy actor responsible for terminal-level semantic actions."""
mutable struct TerminalController
    terminal_rectangle::TerminalRectangle
    committed_tick::UInt64
    committed_revision::UInt64
end

"""Kinds of authoritative facts published by Odin after engine commit."""
@enum EngineEventKind::Int32 begin
    EngineCommandAccepted = 1
    EngineCommandRejected = 2
    EngineCommandCompleted = 3
    EngineExternalFact = 4
    EngineDecisionDefaulted = 5
end

"""Latest committed engine fact delivered to Julia policy."""
struct EngineEventCommitted
    kind::EngineEventKind
    tick::UInt64
    revision::UInt64
end

"""Translate one semantic hotkey into a terminal visibility command."""
function EuclidActorRuntime.receive!(
    _actor::TerminalController,
    context::EuclidActorRuntime.ActorContext,
    message::HotkeyTriggered)::Nothing
    if message.action === ToggleTerminal
        EuclidActorRuntime.emit!(
            context, SetTerminalVisibility(
                message.decision_id,
                !message.current_terminal_visibility,
                _actor.terminal_rectangle))
    end
    return nothing
end

"""Observe committed engine progress without assuming command delivery is commit."""
function EuclidActorRuntime.receive!(
    actor::TerminalController,
    _context::EuclidActorRuntime.ActorContext,
    message::EngineEventCommitted)::Nothing
    actor.committed_tick = max(actor.committed_tick, message.tick)
    actor.committed_revision = max(actor.committed_revision, message.revision)
    return nothing
end