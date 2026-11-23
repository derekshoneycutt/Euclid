package bridge_scene

import core "../../core"
import modifier "../../animation"
import shapemodel "../../shapes/model"

// Translate compact conic outputs into existing owner-controlled scene commands.
native_conic_command :: proc(
    state: ^core.Euclid_General_State,
    value: ^modifier.Modifier_Output) -> Scene_Command {
    command: Scene_Command = {
        entity = shapemodel.shape_entity_pack(state.world_parabola_tool),
        position = value.position,
        scalar = value.scalar,
        flag = value.flag,
        color = native_modifier_color(value.color_packed),
    }
    if value.integer != 0 {
        command.entity = shapemodel.shape_entity_pack(state.world_hyperbola_tool)
    }
    #partial switch value.kind {
    case .Set_Conic_Sample:
        command.kind = .Set_Parabola_Tool_Parameter
        if value.integer != 0 {
            command.kind = .Set_Hyperbola_Tool_Parameter
        }
    case .Set_Conic_Active:
        command.kind = .Set_Parabola_Tool_Active
        command.integer = int(value.scalar)
        if value.integer != 0 {
            command.kind = .Set_Hyperbola_Tool_Active
        }
    case .Set_Conic_Visible:
        command.kind = .Set_Shape_Visible
    case .Set_Conic_Frontier:
        command.entity = value.entity
        command.kind = .Set_Shape_Parabola_Frontier
        if value.integer != 0 {
            command.kind = .Set_Shape_Hyperbola_Frontier
        }
    }
    return command
}

// Validate the full pose before any apparatus, contact or frontier can be mutated.
native_conic_output_valid :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) -> bool {
    command := native_conic_command(state, value)
    validators := SCENE_COMMAND_VALIDATORS
    validator := validators[command.kind]
    if validator == nil || !validator(state, &command) {
        return false
    }
    if value.kind == .Set_Conic_Sample {
        command.kind = .Set_Shape_Position
        return validate_command_shape_transform(state, &command)
    }
    return true
}

// Commit a prevalidated pose through ordinary setters, preserving interpolation history.
apply_native_conic_output :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output,
    lifecycle: bool = false) {
    command := native_conic_command(state, value)
    if value.kind == .Set_Conic_Sample {
        position := command
        position.kind = .Set_Shape_Position
        apply_set_shape_position(state, &position)
        record_native_conic_command(state, &position, lifecycle)
    }
    appliers := SCENE_COMMAND_APPLIERS
    applier := appliers[command.kind]
    assert(applier != nil)
    applier(state, &command)
    record_native_conic_command(state, &command, lifecycle)
}

// Route evidence to the executing owner rather than writing another producer's ring.
record_native_conic_command :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command, lifecycle: bool) {
    if lifecycle {
        record_conic_creation_evidence(state, command)
    } else {
        record_scene_command_evidence(state, command)
    }
}
