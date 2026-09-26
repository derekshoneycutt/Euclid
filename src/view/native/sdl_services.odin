package native

import sdl "vendor:sdl3"

// Sdl_Cursor_Kind identifies one retained platform cursor.
Sdl_Cursor_Kind :: enum u8 {
    Default,
    Text,
    Resize_Ew,
    Resize_Ns,
}

// sdl_platform_sync_text_input follows the window's effective focus exactly once.
sdl_platform_sync_text_input :: proc(platform: ^Sdl_Platform, focused: bool) {
    if platform^.text_input_active == focused {return}
    changed := sdl.StartTextInput(platform^.window) if focused else
        sdl.StopTextInput(platform^.window)
    if changed {platform^.text_input_active = focused}
}

// sdl_platform_admit_cursors creates every cursor required by current UI policy.
sdl_platform_admit_cursors :: proc(platform: ^Sdl_Platform) -> bool {
    platform^.default_cursor = sdl.CreateSystemCursor(.DEFAULT)
    platform^.text_cursor = sdl.CreateSystemCursor(.TEXT)
    platform^.resize_ew_cursor = sdl.CreateSystemCursor(.EW_RESIZE)
    platform^.resize_ns_cursor = sdl.CreateSystemCursor(.NS_RESIZE)
        if platform^.default_cursor == nil || platform^.text_cursor == nil ||
             platform^.resize_ew_cursor == nil ||
       platform^.resize_ns_cursor == nil {
        return false
    }
    platform^.active_cursor = platform^.default_cursor
    return sdl.SetCursor(platform^.active_cursor)
}

// sdl_platform_set_cursor applies one retained cursor only when it changes.
sdl_platform_set_cursor :: proc(
    platform: ^Sdl_Platform, kind: Sdl_Cursor_Kind) -> bool {
    cursor := platform^.default_cursor
    if kind == .Text {
        cursor = platform^.text_cursor
    } else if kind == .Resize_Ew {
        cursor = platform^.resize_ew_cursor
    } else if kind == .Resize_Ns {
        cursor = platform^.resize_ns_cursor
    }
    if cursor == nil {
        return false
    }
    if cursor == platform^.active_cursor {
        return true
    }
    if !sdl.SetCursor(cursor) {
        return false
    }
    platform^.active_cursor = cursor
    return true
}

// sdl_platform_destroy_cursors releases every admitted system cursor.
sdl_platform_destroy_cursors :: proc(platform: ^Sdl_Platform) {
    if platform^.resize_ns_cursor != nil {
        sdl.DestroyCursor(platform^.resize_ns_cursor)
    }
    if platform^.resize_ew_cursor != nil {
        sdl.DestroyCursor(platform^.resize_ew_cursor)
    }
    if platform^.text_cursor != nil {
        sdl.DestroyCursor(platform^.text_cursor)
    }
    if platform^.default_cursor != nil {
        sdl.DestroyCursor(platform^.default_cursor)
    }
    platform^.default_cursor = nil
    platform^.text_cursor = nil
    platform^.resize_ew_cursor = nil
    platform^.resize_ns_cursor = nil
    platform^.active_cursor = nil
}

// sdl_platform_open_url requests host activation of one validated URL.
sdl_platform_open_url :: proc(url: cstring) -> bool {
    return url != nil && sdl.OpenURL(url)
}