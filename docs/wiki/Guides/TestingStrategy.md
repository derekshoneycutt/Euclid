# Testing Strategy

Euclid verifies behavior through Odin and Julia test suites. The standard
repository gate builds with validation enabled, runs both suites, and performs
repository analysis.

## Standard Verification

Run this before delivery:

```sh
make test
```

`make test` runs `tools/configure.sh` when needed, then invokes the combined
build, vet, analysis, and test gate. `make check` is an alias. `make vet` runs
only the validated build and analysis, so it is not a substitute for `make
test`.

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
developing, then run `make test` before considering the work complete.

## Optional Harness

`make harness` builds and runs the headless harness. It is a separate,
optional deterministic runtime scenario, not part of `make test`. It produces
a semantic trace artifact for that scenario and is useful when changing the
runtime path it exercises.

## Current Limits

The automated suite does not establish visual correctness. Rendering, layout,
and animation presentation still need appropriate visual review when those
surfaces change.
