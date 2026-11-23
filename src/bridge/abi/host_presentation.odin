package bridge_abi

import host "../host"
import core "../../core"

//   Copy exact MIME-bearing bytes into the display-owned inbox.
@(export)
publish_presented_text :: proc "c" (
    state: ^core.Euclid_General_State,
    mime_value: i32,
    source: ^u8,
    byte_count: i32) -> i32 {
    return host.publish_presented_text(state, mime_value, source, byte_count)
}
