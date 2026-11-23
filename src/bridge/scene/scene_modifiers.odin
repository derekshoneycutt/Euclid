package bridge_scene

import shapemodel "../../shapes/model"
import modifier "../../animation"
import "../../core"
import "../../particles"

// Decode one little-endian RGBA packed native modifier value.
native_modifier_color :: proc(packed: u32) -> Bridge_Color {
    return Bridge_Color{
        u8(packed),
        u8(packed >> 8),
        u8(packed >> 16),
        u8(packed >> 24),
    }
}

// Apply native point style, brush, visibility, and active-feature outputs.
apply_native_modifier_style_output :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) {
    #partial switch evaluated.kind {
    case .Set_Point_Color:
        apply_set_shape_color(state, &Scene_Command{
            kind = .Set_Shape_Color,
            entity = evaluated.entity,
            color = native_modifier_color(evaluated.color_packed),
        })
    case .Set_Point_Brush:
        apply_set_shape_brush(state, &Scene_Command{
            kind = .Set_Shape_Brush,
            entity = evaluated.entity,
            scalar = evaluated.scalar,
        })
    case .Set_Point_Visible:
        _ = shape_set_visible(state, evaluated.entity, u8(evaluated.flag))
    case .Set_Point_Active_Color:
        apply_set_shape_active_color(state, &Scene_Command{
            kind = .Set_Shape_Active_Color,
            entity = evaluated.entity,
            color = native_modifier_color(evaluated.color_packed),
        })
    case .Set_Point_Active_Feature:
        apply_set_shape_active_feature(state, &Scene_Command{
            kind = .Set_Shape_Active_Feature,
            entity = evaluated.entity,
            integer = evaluated.integer,
        })
    }
}

// Apply native pen and compass tool position and lock outputs.
apply_native_modifier_tool_output :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) {
    #partial switch evaluated.kind {
    case .Set_Tool_Position:
        set_tool_position(state, native_modifier_tool_entity(
            state, evaluated.entity), evaluated.position, evaluated.integer != 0)
    case .Set_Tool_Lock:
        set_tool_lock(state, native_modifier_tool_entity(state, evaluated.entity),
            evaluated.position, evaluated.flag, evaluated.integer != 0)
    case .Set_Tool_Style, .Set_Tool_Active:
        host := native_modifier_tool_host(state, evaluated.entity)
        _ = shape_set_active_color(state, host,
            native_modifier_color(evaluated.color_packed))
        _ = shape_set_active_feature(state, host, u16(evaluated.integer))
        if evaluated.kind == .Set_Tool_Style {
            _ = shape_set_visible(state, host, u8(evaluated.flag))
        }
    case .Set_Tool_Visible:
        _ = shape_set_visible(state,
            native_modifier_tool_host(state, evaluated.entity), u8(evaluated.flag))
    }
}

// Expand nine legacy radius samples using the display-owned particle RNG.
apply_native_radial_trail :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) {
    intervals := f32(modifier.RADIAL_TRAIL_SAMPLES - 1)
    for index in 0..<modifier.RADIAL_TRAIL_SAMPLES {
        jitter := particles.random_f32_range(&state^.particle_system, -0.5, 0.5)
        progress := (f32(index) + jitter) / intervals
        position := evaluated.position +
            (evaluated.second_position - evaluated.position) * progress
        emit_trailing_particle(state, position,
            native_modifier_color(evaluated.color_packed))
    }
}

// Apply native particle and sweep reveal outputs.
apply_native_modifier_effect_output :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) {
    #partial switch evaluated.kind {
    case .Emit_Trailing_Particle:
        emit_trailing_particle(state, evaluated.position,
            native_modifier_color(evaluated.color_packed))
    case .Emit_Radial_Trail:
        apply_native_radial_trail(state, evaluated)
    case .Queue_Tool_Contact:
        queue_tool_dust_contact(state, evaluated.position)
    }
}

// Convert a validated native output into the ordinary owner-side scene API.
apply_native_modifier_output :: proc(
    state: ^core.Euclid_General_State,
    evaluated: ^modifier.Modifier_Output) {
    #partial switch evaluated.kind {
    case .Set_Shape_Orientation:
        apply_native_shape_orientation(state, evaluated)
    case .Set_Conic_Sample, .Set_Conic_Active, .Set_Conic_Visible, .Set_Conic_Frontier:
        apply_native_conic_output(state, evaluated)
    case .Set_Cycloid_Guide_Sample, .Set_Trochoid_Guide_Sample,
        .Set_Rolling_Guide_Visible, .Set_Cycloid_Frontier, .Set_Trochoid_Frontier:
        apply_native_rolling_output(state, evaluated)
    case .Set_Point_Position:
        apply_set_shape_position(state, &Scene_Command{
            kind = .Set_Shape_Position,
            entity = evaluated.entity,
            position = evaluated.position,
        })
    case .Set_Point_Color, .Set_Point_Brush, .Set_Point_Visible,
        .Set_Point_Active_Color, .Set_Point_Active_Feature:
        apply_native_modifier_style_output(state, evaluated)
    case .Set_Shape_Arc:
        apply_set_shape_arc(state, &Scene_Command{
            kind = .Set_Shape_Arc,
            entity = evaluated.entity,
            arc = shapemodel.Shape_Arc{
                radius = evaluated.arc_radius,
                start_theta = evaluated.arc_start,
                sweep_theta = evaluated.arc_sweep,
            },
        })
    case .Set_Tool_Position, .Set_Tool_Lock, .Set_Tool_Style,
        .Set_Tool_Visible, .Set_Tool_Active:
        apply_native_modifier_tool_output(state, evaluated)
    case .Emit_Trailing_Particle, .Emit_Radial_Trail, .Queue_Tool_Contact:
        apply_native_modifier_effect_output(state, evaluated)
    }
}

// Publish sampled outputs while starting formation at the same endpoint as Julia reveals.
apply_native_modifier_batch_command :: proc(
    state: ^core.Euclid_General_State,
    batch: ^Scene_Command_Batch, command_index: int) {
    output: modifier.Modifier_Output_Buffer
    status := modifier.evaluate_modifier(
        batch.commands[command_index].modifier, &output)
    assert(status == .Ok)
    for output_index in 0..<output.count {
        evaluated := &output.outputs[output_index]
        if evaluated.kind == .Reveal_Sweep {
            if !scene_reveal_superseded_later(batch, command_index) {
                command := native_sweep_reveal_command(evaluated)
                apply_animation_reveal(state, &command, batch)
            }
        } else {
            apply_native_modifier_output(state, evaluated)
        }
    }
}

