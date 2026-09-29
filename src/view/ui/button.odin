package ui

import viewmodel "../model"

// Button_Semantics describes optional semantic publication for one button.
Button_Semantics :: struct {
    publish: bool,
    focus: ^viewmodel.Ui_Semantic_Focus_State,
    id: viewmodel.Ui_Node_Id,
    parent: viewmodel.Ui_Node_Id,
    role: viewmodel.Ui_Node_Role,
    states: viewmodel.Ui_Node_State,
    region: viewmodel.Ui_Focus_Region,
    traversal_order: u16,
    clip_bounds: viewmodel.Rectangle,
    label: string,
    value: string,
}

// Button_Action_Result reports one activation after all admitted routes converge.
Button_Action_Result :: struct {
    activated: bool,
    sources: viewmodel.Ui_Control_Action_Source,
}

// Button_Action_Input groups semantic publication and pointer activation facts.
Button_Action_Input :: struct {
    semantics: Button_Semantics,
    bounds: viewmodel.Rectangle,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    press_kind: viewmodel.Ui_Press_Owner_Kind,
    press_id: int,
    pointer_activated: bool,
}

// button_semantic_states returns ordinary focusable button state.
button_semantic_states :: #force_inline proc(
    enabled: bool) -> viewmodel.Ui_Node_State {
    states := viewmodel.Ui_Node_State{.Visible, .Focusable, .Tab_Stop}
    if enabled {states += {.Enabled}}
    return states
}

// button_publish_semantics registers one prepared button and pointer focus.
button_publish_semantics :: proc(input: Button_Action_Input) {
    semantics := input.semantics
    _ = semantic_register_control(semantics.focus, {
        id = semantics.id, parent = semantics.parent, role = semantics.role,
        states = semantics.states, actions = {.Focus, .Activate},
        region = semantics.region, traversal_order = semantics.traversal_order,
        bounds = input.bounds, clip_bounds = semantics.clip_bounds,
        label = semantics.label, value = semantics.value,
    })
    _ = semantic_focus_for_press(semantics.focus, input.press_owner,
        input.press_kind, input.press_id, semantics.id)
}

// button_resolve_action publishes semantics and converges pointer and addressed input.
button_resolve_action :: proc(input: Button_Action_Input) -> Button_Action_Result {
    semantics := input.semantics
    result := Button_Action_Result{}
    if input.pointer_activated {
        result.activated = true
        result.sources += {.Pointer}
    }
    if semantics.focus == nil || semantics.id == (viewmodel.Ui_Node_Id{}) {
        return result
    }
    if .Enabled in semantics.states &&
        semantic_command_requested(semantics.focus, semantics.id, .Activate) {
        result.activated = true
        result.sources += {.Semantic}
    }
    if !semantics.publish {
        return result
    }
    button_publish_semantics(input)
    return result
}