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

// Verify arena baselines enforce stable usage and high water while allowing resets.
@(test)
allocation_test_arena_baseline_matches_warm_rebuild :: proc(t: ^testing.T) {
    baselines: Arena_Baselines
    warm := Arena_Snapshot{
        current_used = 10, current_reserved = 20, current_committed = 15,
        peak_used = 10, peak_reserved = 20, peak_committed = 15,
        reset_count = 2, initialized_count = 1}
    testing.expect(t, arena_checkpoint(&baselines, .Display_Cache, warm))
    rebuilt := warm
    rebuilt.reset_count += 1
    testing.expect(t, arena_matches_baseline(
        &baselines, .Display_Cache, rebuilt))
    testing.expect(t, baselines.observed_present[Arena_Domain_Kind.Display_Cache])
    testing.expect(t, baselines.matched[Arena_Domain_Kind.Display_Cache])
    rebuilt.peak_used += 1
    testing.expect(t, !arena_matches_baseline(
        &baselines, .Display_Cache, rebuilt))
    testing.expect(t, !baselines.matched[Arena_Domain_Kind.Display_Cache])
}

// Verify only the three source-controlled allocation domain names are accepted.
@(test)
allocation_test_arena_domain_names_are_stable :: proc(t: ^testing.T) {
    _, animation_ok := arena_domain_kind("animation")
    _, slots_ok := arena_domain_kind("snapshot_slots")
    _, cache_ok := arena_domain_kind("display_cache")
    _, unknown_ok := arena_domain_kind("runtime")
    testing.expect(t, animation_ok && slots_ok && cache_ok && !unknown_ok)
}
