package exerciseheader

// Link_Phase tracks one internal exercise link through resolve, reset, and read.
Link_Phase :: enum u8 {
    Idle,
    Resolving,
    Awaiting_Reset,
    Awaiting_Ready,
    Reading,
}

// Link_State retains only the request and resolved identity across Terminal reset.
Link_State :: struct {
    phase: Link_Phase,
    user_namespace: bool,
    token: u64,
    source_animation_generation: u64,
    source_animation_id: [36]u8,
    terminal_generation: u64,
    header_request_id: u64,
    identity: [36]u8,
}
