package input

import "core:strings"
import "core:log"

import sdl "vendor:sdl3"

// Write plain UTF-8 text to the SDL-owned system clipboard boundary.
input_set_clipboard_text :: proc(text: string) -> bool {
    clipboard_text := strings.clone_to_cstring(text, context.temp_allocator)
    accepted := sdl.SetClipboardText(clipboard_text)
    if !accepted {
        log.warn("clipboard_write_failed")
    }
    return accepted
}

// input_read_clipboard_text distinguishes empty content from native read failure.
input_read_clipboard_text :: proc() -> (string, bool) {
    text := sdl.GetClipboardText()
    if text == nil {
        log.warn("clipboard_read_failed")
        return "", false
    }
    defer sdl.free(text)
    return strings.clone(string(cstring(text)), context.temp_allocator), true
}

// Copy plain text from SDL ownership into temporary frame storage.
input_get_clipboard_text :: proc() -> string {
    text, _ := input_read_clipboard_text()
    return text
}
