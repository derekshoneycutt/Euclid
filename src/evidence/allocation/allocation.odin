package allocation

// Package allocation records selected Odin allocator-domain evidence.

import "core:mem"
import "core:sync"

ALLOCATION_BASELINE_CAPACITY :: 16
ALLOCATION_BASELINE_NAME_CAPACITY :: 32

// Point-in-time allocation counters copied from one tracked domain.
//
// The live and byte counters describe current ownership, while peak and total
// counters describe cumulative pressure. Invalid frees are retained separately
// because they do not represent live backing allocations.
Snapshot :: struct {
    // Current tracked ownership.
    live_allocations : int,
    current_bytes : i64,

    // Lifetime pressure and misuse evidence.
    peak_bytes : i64,
    total_allocations : i64,
    bad_frees : int,
}

// Fixed domain-owned checkpoint used for later allocation-state comparisons.
//
// Names are stored inline so creating or replacing a checkpoint does not add an
// allocation to the domain being measured.
Baseline :: struct {
    // Inline UTF-8 checkpoint identity and its initialized byte count.
    name : [ALLOCATION_BASELINE_NAME_CAPACITY]u8,
    name_count : int,

    // Counters captured when the checkpoint was last stored.
    snapshot : Snapshot,
}

// Explicit allocator domain with tracking metadata and bounded named baselines.
//
// The tracker wraps caller-provided backing storage. Baselines belong to the
// domain value itself and remain valid until replacement or destruction.
Domain :: struct {
    // Allocation accounting and invalid-free evidence managed by core:mem.
    tracker : mem.Tracking_Allocator,

    // Fixed checkpoint registry; only the prefix selected by baseline_count is valid.
    baselines : [ALLOCATION_BASELINE_CAPACITY]Baseline,
    baseline_count : int,

    // Lifecycle guard for allocator access, snapshots, and idempotent destruction.
    initialized : bool,
}

//   Initialize one explicit tracked allocator domain with separate metadata storage.
//
// Parameters:
//   - domain: Destination replaced with a newly initialized domain.
//   - backing: Allocator used for allocations made through this domain.
//   - internals: Allocator used exclusively for tracking metadata.
//
// Returns:
//   - True after initialization, or false for a nil domain or unusable allocator.
//
// Side effects:
//   - Discards the destination's previous value and installs invalid-free collection.
//
// Notes:
//   - The caller must destroy an initialized domain before reinitializing it.
domain_init :: proc(
    domain: ^Domain, backing, internals: mem.Allocator) -> bool {
    if domain == nil || backing.procedure == nil || internals.procedure == nil {
        return false
    }
    domain^ = {}
    mem.tracking_allocator_init(&domain.tracker, backing, internals)
    domain.tracker.bad_free_callback =
        mem.tracking_allocator_bad_free_callback_add_to_array
    domain.initialized = true
    return true
}

//   Release only tracking metadata; live backing allocations remain caller errors.
//
// Parameters:
//   - domain: Domain to destroy; nil and uninitialized domains are accepted.
//
// Side effects:
//   - Releases tracker metadata and clears the complete domain value.
//
// Notes:
//   - The caller must stop using allocators previously returned for this domain.
domain_destroy :: proc(domain: ^Domain) {
    if domain == nil || !domain.initialized {
        return
    }
    mem.tracking_allocator_destroy(&domain.tracker)
    domain^ = {}
}

//   Return the allocator to pass into one explicitly instrumented ownership domain.
//
// Parameters:
//   - domain: Initialized domain that will account for allocator operations.
//
// Returns:
//   - The tracking allocator, or the nil allocator when the domain is unavailable.
domain_allocator :: proc(domain: ^Domain) -> mem.Allocator {
    if domain == nil || !domain.initialized {
        return mem.nil_allocator()
    }
    return mem.tracking_allocator(&domain.tracker)
}

//   Copy current counters without logging or allocating.
//
// Parameters:
//   - domain: Initialized domain whose counters will be sampled.
//
// Returns:
//   - A consistent counter snapshot, or zero values when the domain is unavailable.
//
// Notes:
//   - Sampling acquires the tracking allocator mutex and is safe with concurrent
//     allocator operations.
domain_snapshot :: proc(domain: ^Domain) -> Snapshot {
    if domain == nil || !domain.initialized {
        return {}
    }
    sync.mutex_lock(&domain.tracker.mutex)
    defer sync.mutex_unlock(&domain.tracker.mutex)
    return {
        live_allocations = len(domain.tracker.allocation_map),
        current_bytes = domain.tracker.current_memory_allocated,
        peak_bytes = domain.tracker.peak_memory_allocated,
        total_allocations = domain.tracker.total_allocation_count,
        bad_frees = len(domain.tracker.bad_free_array),
    }
}

//   Store or replace a named baseline using fixed domain-owned metadata.
//
// Parameters:
//   - domain: Initialized domain that owns the bounded baseline registry.
//   - name: Nonempty checkpoint name within the fixed byte capacity.
//
// Returns:
//   - True when the checkpoint was stored; false for invalid input or full capacity.
//
// Side effects:
//   - Replaces a matching snapshot or appends one baseline to the registry.
domain_checkpoint :: proc(domain: ^Domain, name: string) -> bool {
    if domain == nil || !domain.initialized || len(name) == 0 ||
        len(name) > ALLOCATION_BASELINE_NAME_CAPACITY {
        return false
    }
    for &baseline in domain.baselines[:domain.baseline_count] {
        if baseline_name(&baseline) == name {
            baseline.snapshot = domain_snapshot(domain)
            return true
        }
    }
    if domain.baseline_count == len(domain.baselines) {
        return false
    }
    baseline := &domain.baselines[domain.baseline_count]
    copy(baseline.name[:], transmute([]u8)name)
    baseline.name_count = len(name)
    baseline.snapshot = domain_snapshot(domain)
    domain.baseline_count += 1
    return true
}

//   Test whether current live allocation, byte, and bad-free state matches a baseline.
//
// Parameters:
//   - domain: Initialized domain to sample.
//   - name: Existing checkpoint name to compare against.
//
// Returns:
//   - True only when the named baseline exists and all compared counters match.
//
// Notes:
//   - Peak bytes and total allocation count are cumulative pressure metrics and are
//     intentionally excluded from restoration checks.
domain_matches_baseline :: proc(domain: ^Domain, name: string) -> bool {
    if domain == nil || !domain.initialized {
        return false
    }
    current := domain_snapshot(domain)
    for &baseline in domain.baselines[:domain.baseline_count] {
        if baseline_name(&baseline) == name {
            return current.live_allocations == baseline.snapshot.live_allocations &&
                current.current_bytes == baseline.snapshot.current_bytes &&
                current.bad_frees == baseline.snapshot.bad_frees
        }
    }
    return false
}

//   Return whether no invalid free was observed in this domain lifetime.
//
// Parameters:
//   - domain: Initialized domain whose invalid-free evidence will be inspected.
//
// Returns:
//   - True only for an initialized domain with no recorded invalid frees.
domain_has_no_bad_frees :: proc(domain: ^Domain) -> bool {
    return domain != nil && domain.initialized &&
        len(domain.tracker.bad_free_array) == 0
}

//   Return a borrowed name from fixed baseline storage.
//
// Parameters:
//   - baseline: Baseline whose initialized name prefix will be exposed.
//
// Returns:
//   - A string borrowing the baseline's inline name bytes.
//
// Notes:
//   - The result remains valid only while the baseline storage remains alive and stable.
baseline_name :: proc(baseline: ^Baseline) -> string {
    return string(baseline.name[:baseline.name_count])
}
