#+build linux
package termsession

// Production terminal backend selected for Linux builds.
Native_Terminal_Backend :: Unix_Terminal_Backend

//   Initialize the production terminal backend for Linux.
//
// Returns:
//   - The result of `unix_terminal_backend_init`.
native_terminal_backend_init :: proc(
    backend: ^Native_Terminal_Backend) -> bool {
    return unix_terminal_backend_init(backend)
}

// Release Linux backend workspace ownership after session shutdown.
native_terminal_backend_destroy :: proc(backend: ^Native_Terminal_Backend) {
    unix_terminal_backend_destroy(backend)
}

//   Expose the Linux backend through the common session contract.
//
// Returns:
//   - Complete callback table borrowing `backend`.
native_terminal_backend_make :: proc(
    backend: ^Native_Terminal_Backend) -> Terminal_Process_Backend {
    return unix_terminal_backend_make(backend)
}