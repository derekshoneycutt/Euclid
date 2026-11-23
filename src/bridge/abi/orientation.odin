package bridge_abi

import scene "../scene"
import core "../../core"

// Query canonical plane orientation only through the active immutable query source.
@(export)
shape_get_orientation :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Orientation_Result {
    return scene.shape_get_orientation(state, packed)
}

// Capture a complete plane rotation; positional changes share its scene transaction.
@(export)
shape_set_orientation :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    components: [4]f32) -> i32 {
    return scene.shape_set_orientation(state, packed, components)
}
