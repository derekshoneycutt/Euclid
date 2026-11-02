#+test
package viewsharing

import sharingmodel "../../view/sharing/model"
import storage "../../core/storage"
import "core:testing"

// Verify cancelling a staged import retires every exchange arena allocation.
@(test)
exchange_memory_cancel_releases_staged_arena :: proc(t: ^testing.T) {
    runtime: sharingmodel.Exchange_Runtime
    testing.expect(t, exchange_memory_prepare_import(&runtime))
    testing.expect(t,
        storage.arena_owner_diagnostics(&runtime.arena).current_used > 0)
    testing.expect(t, exchange_memory_destroy(&runtime))
    diagnostics := storage.arena_owner_diagnostics(&runtime.arena)
    testing.expect_value(t, diagnostics.current_used, uint(0))
    testing.expect_value(t, diagnostics.current_reserved, uint(0))
}

// Verify committed import cleanup also retires its staged plan storage.
@(test)
exchange_memory_commit_releases_staged_arena :: proc(t: ^testing.T) {
    runtime: sharingmodel.Exchange_Runtime
    testing.expect(t, exchange_memory_prepare_import(&runtime))
    allocator := storage.arena_owner_allocator(&runtime.arena)
    bytes, allocation_error := make([]u8, 128, allocator)
    testing.expect(t, allocation_error == nil)
    testing.expect(t, len(bytes) == 128)
    testing.expect(t, exchange_memory_destroy(&runtime))
    diagnostics := storage.arena_owner_diagnostics(&runtime.arena)
    testing.expect_value(t, diagnostics.current_used, uint(0))
    testing.expect_value(t, diagnostics.current_reserved, uint(0))
}

// Verify staged storage cannot be retired until the submitted worker has joined.
@(test)
exchange_memory_rejects_inflight_retirement :: proc(t: ^testing.T) {
    runtime: sharingmodel.Exchange_Runtime
    testing.expect(t, exchange_memory_prepare_import(&runtime))
    runtime.task_active = true
    testing.expect(t, !exchange_memory_destroy(&runtime))
    testing.expect(t,
        storage.arena_owner_diagnostics(&runtime.arena).current_used > 0)
    runtime.task_active = false
    testing.expect(t, exchange_memory_destroy(&runtime))
}
