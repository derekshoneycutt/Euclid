package animation

// Playback_Rate is session intent; its zero value preserves ordinary authored time.
Playback_Rate :: enum u8 {
    Normal,
    Double,
    Quadruple,
}

// playback_rate_multiplier resolves the three supported authored-time scales.
playback_rate_multiplier :: proc(rate: Playback_Rate) -> f32 {
    switch rate {
    case .Normal: return 1
    case .Double: return 2
    case .Quadruple: return 4
    }
    unreachable()
}

// playback_rate_next cycles the transport choice without changing pause state.
playback_rate_next :: proc(rate: Playback_Rate) -> Playback_Rate {
    switch rate {
    case .Normal: return .Double
    case .Double: return .Quadruple
    case .Quadruple: return .Normal
    }
    unreachable()
}
