package bridge_abi

import host "../host"
import core "../../core"
import contentdata "../../core/content"

// Copy one validated callback value to Julia-owned storage; failed queries leave it unchanged.
@(export)
copy_animation_content_specification :: proc "c" (
    state: ^core.Euclid_General_State,
    invocation: host.Animation_Content_Invocation,
    output: ^contentdata.Animation_Content_Specification) -> u32 {
    return host.copy_animation_content_specification(state, invocation, output)
}
