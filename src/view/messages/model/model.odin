package messagesmodel

import content "../../../core/content"

// Label_Cache owns bounded display-lifetime copies of one content generation's labels.
Label_Cache :: struct {
    shell_message_generation: u64,
    shell_message_bytes: [content.CONTENT_MESSAGE_CAPACITY][128]u8,
    shell_message_lengths: [content.CONTENT_MESSAGE_CAPACITY]u16,
}
