#+test
package allocation

import "core:mem"
import "core:testing"

// Verify clean allocation lifecycles restore named baselines exactly.
@(test)
allocation_test_baseline_restoration :: proc(t: ^testing.T) {
    domain: Domain
    testing.expect(t, domain_init(
        &domain, context.allocator, context.allocator))
    defer domain_destroy(&domain)
    allocator := domain_allocator(&domain)
    testing.expect(t, domain_checkpoint(&domain, "clean"))

    bytes, allocation_error := make([]byte, 64, allocator)
    testing.expect(t, allocation_error == nil)
    testing.expect(t, !domain_matches_baseline(&domain, "clean"))
    delete(bytes, allocator)

    testing.expect(t, domain_matches_baseline(&domain, "clean"))
    testing.expect(t, domain_has_no_bad_frees(&domain))
}

// Verify invalid frees become queryable evidence without invoking diagnostics.
@(test)
allocation_test_bad_free_is_evidence :: proc(t: ^testing.T) {
    domain: Domain
    testing.expect(t, domain_init(
        &domain, context.allocator, context.allocator))
    defer domain_destroy(&domain)
    allocator := domain_allocator(&domain)
    foreign_bytes, allocation_error := make([]byte, 8, context.allocator)
    testing.expect(t, allocation_error == nil)
    defer delete(foreign_bytes)

    mem.free(raw_data(foreign_bytes), allocator)

    testing.expect(t, !domain_has_no_bad_frees(&domain))
    testing.expect_value(t, domain_snapshot(&domain).bad_frees, 1)
}
