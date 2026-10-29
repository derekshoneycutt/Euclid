package native

// Sdl_Iteration_Gate rejects recursive entry before frame scratch or clocks can be touched.
Sdl_Iteration_Gate :: struct {
    active: bool,
    pending: bool,
    next_tick: u64,
}

SDL_CALLBACK_FRAME_RATE :: u64(60)
SDL_CALLBACK_DEADLINE_TOLERANCE :: u64(1_000_000)

// sdl_iteration_enter coalesces nested callbacks without executing their frames recursively.
sdl_iteration_enter :: proc(gate: ^Sdl_Iteration_Gate) -> bool {
    if gate^.active {
        gate^.pending = true
        return false
    }
    gate^.active = true
    return true
}

// sdl_iteration_leave releases the display guard; SDL supplies the next scheduling opportunity.
sdl_iteration_leave :: proc(gate: ^Sdl_Iteration_Gate) {
    gate^.active = false
}

// sdl_iteration_due applies a nonblocking deadline, with resize repaint bypass and no catch-up burst.
sdl_iteration_due :: proc(
    gate: ^Sdl_Iteration_Gate, now: u64, limited, resized: bool) -> bool {
    if limited && !resized &&
        now + SDL_CALLBACK_DEADLINE_TOLERANCE < gate^.next_tick {
        return false
    }
    gate^.pending = false
    gate^.next_tick = now + NANOSECONDS_PER_SECOND / SDL_CALLBACK_FRAME_RATE
    return true
}
