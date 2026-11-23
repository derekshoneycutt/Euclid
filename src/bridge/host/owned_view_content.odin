package julia_host

import bridgemodel "../model"
import "core:log"

// Copy retained presentation into a stable owner's bounded record before batch recycling.
owned_view_content_store :: proc(
    destination: ^bridgemodel.Owned_View_Content,
    content: bridgemodel.View_Content_Ready) -> bool {
    if len(content.content.bytes) > len(destination.bytes) {
        log.error("presentation_owned_source_exceeds_capacity")
        return false
    }
    copied := content
    bytes := destination.bytes[:len(content.content.bytes)]
    copy(bytes, content.content.bytes)
    copied.content.bytes = bytes
    destination.message = copied
    destination.present = true
    return true
}

// End owner-local retention without mutating any message in a mailbox batch.
owned_view_content_clear :: proc(destination: ^bridgemodel.Owned_View_Content) {
    destination.message = {}
    destination.present = false
}
