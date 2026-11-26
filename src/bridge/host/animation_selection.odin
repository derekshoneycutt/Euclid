package julia_host

import bridge_animation "../animation"

import bridgemodel "../model"
import julialib "../../../libs/julia/bindings"
import core "../../core"
import uuid "core:encoding/uuid"

when !core.HARNESS_ENABLED {
    _ :: julialib
}

//   Synchronize one programmatic animation selection and request its tree reveal.
select_animation_programmatically :: proc(
    state: ^core.Euclid_General_State,
    selected: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {

    if state == nil || state^.julia_interface == nil || selected == nil {
        return false
    }

    ji := state^.julia_interface
    found := false
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        found = found || node == selected
    }
    if !found {
        return false
    }

    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        node^.is_selected = node == selected
    }
    ji^.selected_animation = selected
    ancestor := selected^.parent
    for steps := 0; ancestor != nil && steps < ji^.animation_count; steps += 1 {
        ancestor^.is_expanded = true
        ancestor = ancestor^.parent
    }
    state^.ui_runtime.library.tree.reveal_pending = true
    state^.ui_runtime.library.tree.reveal_stable_id = selected^.stable_id
    state^.ui_runtime.library.tree.reveal_reason = .Programmatic
    return true
}

//   Select the first authored animation as the default selection.
select_default_animation :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_interface == nil {
        return
    }

    ji := state^.julia_interface
    target: ^bridgemodel.Euclid_Julia_Animation_Interface

    it := bridge_animation.animation_iterator_begin(ji)
    for {
        node := bridge_animation.animation_iterator_next(&it)
        if node == nil {
            break
        }
        if node^.node_kind != .Animation {
            continue
        }
        if target == nil || node^.catalog_order < target^.catalog_order {
            target = node
        }
    }

    if target == nil {
        return
    }

    _ = select_animation_programmatically(state, target)
}

//   Select one animation by stable UUID without involving UI input handling.
//
// Parameters:
//   - state: Global runtime state containing the active Julia interface.
//   - stable_id: Stable animation UUID to select.
//
// Returns:
//   - ok: true when the animation exists and selection state was updated.
select_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }

    selected := find_animation_by_stable_id(state, stable_id)
    if selected == nil {
        return false
    }

    return select_animation_programmatically(state, selected)
}

when core.HARNESS_ENABLED {
    //   Invoke one harness scenario callback on the Julia owner thread.
    //
    // Parameters:
    //   - state: Global runtime state forwarded to Julia.
    //   - scenario_name: Scenario function name resolved from Main.
    //   - step_count: Number of deterministic fixed steps already executed.
    //
    // Returns:
    //   - ok: true when the scenario callback completed successfully.
    invoke_harness_scenario :: proc(
        state: ^core.Euclid_General_State,
        scenario_name: string,
        step_count: int) -> bool {

        if state == nil || len(scenario_name) == 0 {
            return false
        }

        return invoke_harness_transaction(state, scenario_name, i64(step_count))
    }

    //   Execute one harness scenario callback after deterministic stepping.
    run_harness_scenario :: proc(
        host: ^Julia_Runtime_Host,
        request: bridgemodel.Harness_Scenario_Requested) -> bool {
        state := host^.native_state
        assert_julia_runtime_owner(state)
        context = state^.saved_context

        main_module := resolve_main_module()
        if main_module == nil || len(request.scenario_name) == 0 {
            return false
        }

        callback := julialib.jl_get_function(
            main_module, "invoke_generation_harness_scenario")
        if callback == nil || host^.runtime == nil {
            return false
        }

        scenario_bytes := transmute([]u8)request.scenario_name
        state_value := julialib.jl_box_voidpointer(state)
        step_value := julialib.jl_box_int64(request.step_count)
        result := julialib.jl_call4(
            callback,
            host^.runtime,
            julialib.jl_pchar_to_string(
                cstring(raw_data(scenario_bytes)), len(scenario_bytes)),
            state_value,
            step_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("harness scenario")
            return false
        }
        if result == nil {
            return false
        }
        return julialib.jl_unbox_bool(result) != 0
    }
}

//   Find an animation pointer by its registered stable UUID identity.
find_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> ^bridgemodel.Euclid_Julia_Animation_Interface {

    if state == nil || state^.julia_interface == nil {
        return nil
    }

    return bridge_animation.animation_lookup_find(state^.julia_interface, stable_id)
}
