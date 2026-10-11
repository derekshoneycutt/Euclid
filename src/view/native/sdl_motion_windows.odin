#+build windows

package native

import win "core:sys/windows"

// sdl_query_reduced_motion reads the client-area animation accessibility preference.
sdl_query_reduced_motion :: proc() -> (bool, Sdl_Motion_Status) {
    enabled: win.BOOL
    if win.SystemParametersInfoW(win.SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) == 0 {
        return false, .Failed
    }
    return enabled == 0, .Supported
}
