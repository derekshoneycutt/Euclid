package messagesmodel

// Label_Cache owns bounded display-lifetime copies of one content generation's labels.
Label_Cache :: struct {
    shell_message_generation: u64,
    shell_message_bytes: [96][128]u8,
    shell_message_lengths: [96]u16,
}
