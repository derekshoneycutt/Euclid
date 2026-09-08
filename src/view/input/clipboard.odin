package input

import "core:strings"

import rl "vendor:raylib"

// Write plain text to the system clipboard.
input_set_clipboard_text :: proc(text: string) {
    clipboard_text := strings.clone_to_cstring(text, context.temp_allocator)
    rl.SetClipboardText(clipboard_text)
}

// Borrow plain text from the system clipboard, or empty when unavailable.
input_get_clipboard_text :: proc() -> string {
    text := rl.GetClipboardText()
    if text == nil {
        return ""
    }
    return string(text)
}
