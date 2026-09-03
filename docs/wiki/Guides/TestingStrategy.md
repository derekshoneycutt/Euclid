# Testing Strategy

Euclid verifies behavior through Odin and Julia test suites. The standard
repository gate builds with validation enabled, runs both suites, and performs
repository analysis.

## Standard Verification

Run this before delivery:

```sh
cmake --preset default
cmake --build --preset default --target check
```

The CMake `check` target invokes the combined build, analysis, and test gate.
The `vet` target runs only the validated build and analysis, so it is not a
substitute for `check`.

The gate runs:

- Odin tests with `odin test src -all-packages`.
- Julia tests from `src/julia/test/runtests.jl` using the Julia project in
  `src/julia`.
- Repository analysis and its regression tests, with the report written to
  `.build/reports/analysis.md`.

## Test Placement

Keep tests with the code they exercise:

- Odin package tests are `*_tests.odin` files under `src/` and run with the
  all-packages Odin test command.
- Julia tests live in `src/julia/test/` and are included by
  `src/julia/test/runtests.jl`.

Add focused tests for changed behavior. Use the smallest relevant test while
developing, then run the CMake `check` target before considering the work
complete.

## Optional Harness

The CMake `harness` target builds and runs the headless harness. It is a separate,
optional deterministic runtime scenario, not part of `check`. It produces
a semantic trace artifact for that scenario and is useful when changing the
runtime path it exercises.

## Runtime Scenario Corpora

Source-controlled JSONL scenarios live in `tools/scenarios/`. This includes focused
typed-state and recursive math-font corpora plus a combined bounded flow covering typed
selection and updates, Scratchpad failure fallback, runtime reload, post-reload math
publication, captures, shutdown, and allocation restoration.

Allocation commands accept only the stable domain names `animation`, `snapshot_slots`,
and `display_cache`. Each `allocation_checkpoint` must precede the corresponding
`assert_allocation_baseline`; `assert_no_bad_frees` remains aggregate. Successful and
failed baseline comparisons emit typed semantic events, and terminal bundles retain
the checkpoint and final assertion samples in `allocations.json`.

The session retains at most 4,096 semantic events. Required evidence loss makes a
scenario inconclusive, so combined corpora must remain below that fixed bound rather
than treating a partial trace as success. Run scenarios into fresh artifact directories
and require both `result: "passed"` and `trace_complete: true`.

Runtime-generation rollback coverage lives in
`phase-runtime-generation-load-rollback.jsonl` and
`phase-runtime-generation-enter-rollback.jsonl`. Each scenario selects and lazily loads
an animation, arms one Odin-owned failure with `inject_reload_failure`, then issues the
ordinary `reload_runtime` action. Passing evidence requires correlated rollback, a
committed old-generation animation tick after rollback's forced GC, retained dynview,
zero bad frees, complete trace retention, and orderly shutdown. The Enter case proves
candidate binding reached lifecycle validation; neither hook mutates packaged assets or
introduces Julia global state.

## Current Limits

The automated suite does not establish visual correctness. Rendering, layout,
and animation presentation still need appropriate visual review when those
surfaces change.
