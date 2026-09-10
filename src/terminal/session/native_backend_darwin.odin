#+build darwin
package termsession

// Production terminal backend selected for Darwin builds.
Native_Terminal_Backend :: Unix_Terminal_Backend

// Initialize the production terminal backend for Darwin.
native_terminal_backend_init :: proc(
    backend: ^Native_Terminal_Backend) -> bool {
    return unix_terminal_backend_init(backend)
}

// Release Darwin backend workspace ownership after session shutdown.
native_terminal_backend_destroy :: proc(backend: ^Native_Terminal_Backend) {
    unix_terminal_backend_destroy(backend)
}

// Expose the Darwin backend through the common session contract.
native_terminal_backend_make :: proc(
    backend: ^Native_Terminal_Backend) -> Terminal_Process_Backend {
    return unix_terminal_backend_make(backend)
}