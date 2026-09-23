package native

import sdl "vendor:sdl3"

NANOSECONDS_PER_SECOND :: u64(1_000_000_000)

// Sdl_Frame_Clock retains the previous monotonic sample for one display loop.
Sdl_Frame_Clock :: struct {
    previous_tick: u64,
}

// sdl_time_seconds returns monotonic seconds since SDL initialization.
sdl_time_seconds :: proc() -> f64 {
    return f64(sdl.GetTicksNS()) / f64(NANOSECONDS_PER_SECOND)
}

// sdl_frame_clock_reset starts one frame clock at the current monotonic tick.
sdl_frame_clock_reset :: proc(clock: ^Sdl_Frame_Clock) {
    clock^.previous_tick = sdl.GetTicksNS()
}

// sdl_frame_clock_step returns elapsed seconds since the previous sample.
sdl_frame_clock_step :: proc(clock: ^Sdl_Frame_Clock) -> f32 {
    current := sdl.GetTicksNS()
    previous := clock^.previous_tick
    clock^.previous_tick = current
    if previous == 0 || current <= previous {
        return 0
    }
    return f32(f64(current - previous) / f64(NANOSECONDS_PER_SECOND))
}

// sdl_delay_until_rate sleeps for the remainder of one requested frame interval.
sdl_delay_until_rate :: proc(started_at: u64, frames_per_second: u64) {
    if frames_per_second == 0 {
        return
    }
    interval := NANOSECONDS_PER_SECOND / frames_per_second
    elapsed := sdl.GetTicksNS() - started_at
    if elapsed < interval {
        sdl.DelayNS(interval - elapsed)
    }
}

// sdl_time_ticks returns the current monotonic nanosecond counter.
sdl_time_ticks :: proc() -> u64 {
    return sdl.GetTicksNS()
}