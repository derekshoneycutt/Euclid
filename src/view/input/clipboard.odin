package input

import "core:strings"

import sdl "vendor:sdl3"

// Write plain UTF-8 text to the SDL-owned system clipboard boundary.
input_set_clipboard_text :: proc(text: string) -> bool {
    clipboard_text := strings.clone_to_cstring(text, context.temp_allocator)
    return sdl.SetClipboardText(clipboard_text)
}

// Copy plain text from SDL ownership into temporary frame storage.
input_get_clipboard_text :: proc() -> string {
    text := sdl.GetClipboardText()
    if text == nil {
        return ""
    }
    defer sdl.free(text)
    return strings.clone(string(cstring(text)), context.temp_allocator)
}
