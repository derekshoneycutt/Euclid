package bridge

import core "../core"
import modifier "../animation"
import shapemodel "../shapes/model"

// Validate a complete guide sample without relying on obsolete pre-batch geometry.
native_rolling_guide_valid :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) -> bool {
    world := &state.shape_world
    if value.kind == .Set_Trochoid_Guide_Sample {
        entity := state.world_trochoid_tool.shape
        return shapemodel.shape_trochoid_tool_is_valid(value.trochoid_tool) &&
            shapemodel.shape_component_contains(
                &world.trochoid_tools, &world.registry, entity) &&
            validate_command_shape_transform(state, &Scene_Command{
                entity = shapemodel.shape_entity_pack(entity),
                position = value.position,
            })
    }
    guide := state.world_cycloid_tool
    return shapemodel.shape_cycloid_tool_is_valid(value.cycloid_tool) &&
        shapemodel.shape_cycloid_line_is_valid(value.position, value.second_position,
            value.cycloid_tool.rolling_radius, value.cycloid_tool.parameter_start,
            value.cycloid_tool.parameter_finish) &&
        shapemodel.shape_component_contains(
            &world.cycloid_tools, &world.registry, guide.shape) &&
        shapemodel.shape_component_contains(
            &world.transforms, &world.registry, guide.first) &&
        shapemodel.shape_component_contains(
            &world.transforms, &world.registry, guide.second)
}

// Resolve frontier and visibility outputs to existing owner-side commands.
native_rolling_command :: proc(
    state: ^core.Euclid_General_State,
    value: ^modifier.Modifier_Output) -> Scene_Command {
    command: Scene_Command = {
        entity = value.entity,
        scalar = value.scalar,
        flag = value.flag,
    }
    #partial switch value.kind {
    case .Set_Rolling_Guide_Visible:
        command.kind = .Set_Shape_Visible
        command.entity = shapemodel.shape_entity_pack(state.world_cycloid_tool.shape)
        if value.integer != 0 {
            command.entity = shapemodel.shape_entity_pack(state.world_trochoid_tool.shape)
        }
    case .Set_Cycloid_Frontier:
        command.kind = .Set_Shape_Cycloid_Frontier
    case .Set_Trochoid_Frontier:
        command.kind = .Set_Shape_Trochoid_Frontier
    }
    return command
}

// Validate all rolling targets before the enclosing scene batch mutates any state.
native_rolling_output_valid :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) -> bool {
    if value.kind == .Set_Cycloid_Guide_Sample ||
        value.kind == .Set_Trochoid_Guide_Sample {
        return native_rolling_guide_valid(state, value)
    }
    command := native_rolling_command(state, value)
    validators := SCENE_COMMAND_VALIDATORS
    validator := validators[command.kind]
    return validator != nil && validator(state, &command)
}

// Commit one prevalidated Cycloid sample atomically and retain interpolation history.
apply_native_cycloid_guide :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) {
    world := &state.shape_world
    guide := state.world_cycloid_tool
    first, _ := shapemodel.shape_component_get_mut(
        &world.transforms, &world.registry, guide.first)
    second, _ := shapemodel.shape_component_get_mut(
        &world.transforms, &world.registry, guide.second)
    current, _ := shapemodel.shape_component_get_mut(
        &world.cycloid_tools, &world.registry, guide.shape)
    first.position, second.position = value.position, value.second_position
    previous := current^
    current^ = value.cycloid_tool
    bridge_cycloid_tool_preserve_previous(current, previous)
}

// Commit a Trochoid sample without resetting its analytic host orientation.
apply_native_trochoid_guide :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) {
    world := &state.shape_world
    entity := state.world_trochoid_tool.shape
    transform, _ := shapemodel.shape_component_get_mut(
        &world.transforms, &world.registry, entity)
    current, _ := shapemodel.shape_component_get_mut(
        &world.trochoid_tools, &world.registry, entity)
    transform.position = value.position
    previous := current^
    current^ = value.trochoid_tool
    bridge_trochoid_tool_preserve_previous(current, previous)
}

// Apply complete guide samples or ordinary prevalidated frontier/style commands.
apply_native_rolling_output :: proc(
    state: ^core.Euclid_General_State, value: ^modifier.Modifier_Output) {
    #partial switch value.kind {
    case .Set_Cycloid_Guide_Sample:
        apply_native_cycloid_guide(state, value)
    case .Set_Trochoid_Guide_Sample:
        apply_native_trochoid_guide(state, value)
    case .Set_Rolling_Guide_Visible, .Set_Cycloid_Frontier, .Set_Trochoid_Frontier:
        command := native_rolling_command(state, value)
        appliers := SCENE_COMMAND_APPLIERS
        applier := appliers[command.kind]
        assert(applier != nil)
        applier(state, &command)
    }
}
