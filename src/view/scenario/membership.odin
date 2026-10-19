package viewscenario

import viewmodel "../ui/model"
import uisemantics "../ui/semantics"
import uianimation "../ui/animation"
import uioverlay "../ui/overlay"

// Membership scenarios address published controls rather than mutating model or popup state.
scenario_membership_control :: proc(
    runtime: ^Scenario_Runtime, operation, address: string) -> (bool, bool) {
    if operation != "membership_open" && operation != "membership_toggle" &&
        operation != "membership_focus" && operation != "membership_press" &&
        operation != "membership_release" {
        return false, false
    }
    id, found := scenario_membership_target(runtime, operation, address)
    if !found {
        return true, false
    }
    focus := runtime.state.ui_runtime.semantic_focus
    if operation == "membership_press" || operation == "membership_release" {
        snapshot := uisemantics.semantic_snapshot(focus)
        index := uisemantics.semantic_node_index(snapshot, id)
        if index < 0 || .Enabled not_in snapshot.nodes[index].states {
            return true, false
        }
        return true, scenario_favorites_pointer(runtime, snapshot.nodes[index].bounds,
            "press" if operation == "membership_press" else "release")
    }
    action := viewmodel.Ui_Focus_Command_Kind.Toggle
    if operation == "membership_open" {
        action = .Activate
    }
    if operation == "membership_focus" {
        action = .Focus
    }
    return true, scenario_library_queue_command(runtime, {target = id, kind = action})
}

// Resolve current published UUID/opening identity; destination names are never scenario keys.
scenario_membership_target :: proc(
    runtime: ^Scenario_Runtime,
    operation, address: string) -> (viewmodel.Ui_Node_Id, bool) {
    if operation == "membership_open" {
        return uisemantics.semantic_control_id(.Animation_Control,
            uianimation.ANIMATION_MEMBERSHIP_BUTTON_ID), true
    }
    item := scenario_custom_collection(runtime, address)
    if item == nil || !runtime.state.ui_runtime.membership.active {
        return {}, false
    }
    return uioverlay.membership_id(&runtime.state.ui_runtime.membership, item.key), true
}
