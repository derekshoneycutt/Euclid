#+build windows
package termsession

// Production terminal backend selected for Windows builds.
Native_Terminal_Backend :: Windows_Terminal_Backend

//   Initialize the production terminal backend for Windows.
//
// Returns:
//   - The result of `windows_terminal_backend_init`.
native_terminal_backend_init :: proc(
    backend: ^Native_Terminal_Backend) -> bool {
    return windows_terminal_backend_init(backend)
}

// Release Windows backend workspace ownership after session shutdown.
native_terminal_backend_destroy :: proc(backend: ^Native_Terminal_Backend) {
    windows_terminal_backend_destroy(backend)
}

//   Expose the Windows backend through the common session contract.
//
// Returns:
//   - Complete callback table borrowing `backend`.
native_terminal_backend_make :: proc(
    backend: ^Native_Terminal_Backend) -> Terminal_Process_Backend {
    return windows_terminal_backend_make(backend)
}