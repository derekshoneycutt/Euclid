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

- Odin package tests are `*_test.odin` files under `src/` and run with the
  all-packages Odin test command.
- Julia tests live in `src/julia/test/` and are included by
  `src/julia/test/runtests.jl`.

Add focused tests for changed behavior. Use the smallest relevant test while
developing, then run the CMake `check` target before considering the work
complete.

Run one Odin test by its package-qualified procedure name:

```sh
julia tools/make.jl unit odin \
  --test=core.core_test_animation_value_store_overwrites_bound_key
```

Run one test-bearing package by its path relative to `src/`:

```sh
julia tools/make.jl unit odin --package=dynview/math
ctest --preset all -L odin-package
```

The `odin-package` CTest label is deliberately outside the default `unit`
preset. Each entry invokes a separate Odin compile and link, so running the
whole granular label costs substantially more than the single all-packages
suite. Use it for package-level selection and editor discovery, not as a second
default gate.

Machine-readable runs emit schema `2.0.0` with source-located records in the
top-level `tests` array and aggregate timing in `suites`:

```sh
julia tools/make.jl unit --format=json
```

Each test record carries `name`, `language`, `package`, `file`, `line`,
`status`, `elapsed_ns`, and `message`. Both native runners expose aggregate
rather than leaf timing, so per-test `elapsed_ns` is `null`; suite
`elapsed_ns` remains measured. Failure messages are populated only for failed
or errored records.

## Optional Harness

The CMake `harness` target builds and runs the headless harness. It is a separate,
optional deterministic runtime scenario, not part of `check`. It produces
a canonical binary trace at `bin/semantic-trace-harness.bin` and is useful when
changing the runtime path it exercises. `evidence query` accepts either that bare trace
or a complete scenario bundle directory and applies the same kind, producer, lane,
correlation, and generation filters:

```sh
julia tools/make.jl evidence query bin/semantic-trace-harness.bin \
  --kind=animation_tick_committed --producer=display --lane=transport
```

Application semantic tracing retains JSONL as an explicit human-readable export through
`--semantic-trace-output=PATH`.

## Runtime Scenario Corpora

Source-controlled JSONL scenarios live in `tools/scenarios/`. This includes focused
typed-state and recursive math-font corpora plus a combined bounded flow covering typed
selection and updates, Terminal evaluation and generation replacement, runtime reload,
post-reload math publication, captures, shutdown, and allocation restoration.

Run one scenario by its filename stem, or explicitly run the complete corpus:

```sh
julia tools/make.jl scenario point-runtime-reload-preserves-state
julia tools/make.jl scenario --all
julia tools/make.jl scenario point-runtime-reload-preserves-state --format=json
```

Run an ad hoc scenario with an explicit artifact destination:

```sh
julia tools/make.jl run --debug -- \
  --scenario=path/to/scenario.jsonl \
  --scenario-artifacts=.build/scenario
```

### Authoring A Scenario

Each nonempty JSONL line contains exactly one action. A reliable visual workflow waits
for the state or correlated event that makes the intended frame meaningful, applies any
viewport changes, captures a presented frame, and waits for capture completion:

```jsonl
{"wait_state":"runtime_ready","timeout_ms":10000}
{"select_animation":"Proposition I","as":"selection"}
{"wait_event":"animation_selected","correlation":"selection","timeout_ms":10000}
{"wait_state":"animation_idle","timeout_ms":10000}
{"assert_state":"dynview_enabled"}
{"set_splitters":{"vertical":900,"horizontal":560}}
{"set_view_scroll":{"y":100000}}
{"screenshot":".build/scenario/proposition-1-bottom.png"}
{"wait_event":"capture_completed","timeout_ms":10000}
{"assert_no_bad_frees":true}
{"shutdown":true}
```

`as` stores the typed identity produced by an action. A later `wait_event` may name it
with `correlation`; matching includes identity kind, ID, and generation. Use correlated
waits when the scenario must prove that a particular request produced an event. An
uncorrelated wait consumes the next event of that kind.

The principal command forms are:

| Form | Purpose |
| --- | --- |
| `{"do":"ACTION"}` | Issue `reset_animation`, `reload_runtime`, pause/resume, or `stop_gif`. |
| `{"select_animation":"NAME"}` | Select by exact display name, or use `PARENT/NAME` to disambiguate duplicate leaf names. |
| `{"scratchpad":"CODE"}` | Submit code through the asynchronous Scratchpad path. |
| `{"set_view_scroll":{"y":Y}}` | Set non-Terminal presentation scroll in logical pixels. |
| `{"set_splitters":{"vertical":X,"horizontal":Y}}` | Atomically set both pane splitters in logical pixels. |
| `{"wait_event":"EVENT"}` | Wait for retained typed evidence, optionally correlated. |
| `{"wait_state":"STATE"}` | Wait until an observed scalar predicate holds. |
| `{"assert_state":"STATE"}` | Check an observed scalar predicate immediately. |
| `{"screenshot":"PATH"}` | Capture the next eligible presented frame. |
| `{"start_gif":"NAME"}` | Start GIF capture; stop it with `{"do":"stop_gif"}`. |
| `{"checkpoint":"NAME"}` | Store a semantic evidence checkpoint. |
| `{"allocation_checkpoint":"DOMAIN"}` | Store an arena-domain allocation baseline. |
| `{"assert_allocation_baseline":"DOMAIN"}` | Compare an arena domain with its baseline. |
| `{"assert_no_bad_frees":true}` | Require zero aggregate bad frees. |
| `{"shutdown":true}` | Request orderly application shutdown. |

Inspect the authoritative vocabulary and bounds rather than guessing names or limits:

```sh
julia tools/make.jl evidence capabilities
julia tools/make.jl evidence schema
```

Programs permit at most 128 commands and 64 KiB of source; each line is limited to
1024 bytes. Text payloads are limited to 256 bytes, alias names to 64 bytes, and waits
to 60 seconds. Unknown actions, events, states, aliases, or combined action fields fail
the scenario. Required evidence loss makes the result inconclusive, never passed.

### Presentation And Capture Semantics

View-scroll and splitter actions each create a frame boundary. The display applies the
request before the next frame's UI geometry and Dynview layout, so the following
`screenshot` observes the effective clamped viewport. View scrolling targets only the
non-Terminal presentation. Splitter changes preserve pane minimums and are rejected
while GIF capture is active or requested.

Screenshot completion occurs after a frame is presented. Follow `screenshot` with an
uncorrelated `capture_completed` wait when later steps depend on the file; screenshot
aliases do not currently match capture-completion identity. Completion requires a
successful SDL core PNG save and an existing output file. The focused
`screenshot-capture-acceptance` scenario proves real scene-target readback, persisted
completion, no bad frees, and orderly shutdown without unrelated animation evidence.

Native capture tests use padded source rows and decode the persisted PNG back to RGBA8
to verify dimensions, channel order, orientation, and representative pixels. Injected
completion operations cover fence-wait failure, map failure, successful unmap, and
exactly-once fence release. CPU capture tests separately cover crop, nearest-neighbor
resize, allocation failure, and idempotent release.

### Judging A Scenario Result

Orderly shutdown writes the following bundle:

| File | Required evidence |
| --- | --- |
| `manifest.json` | Result, failure reason and step, schema version, and trace completeness. |
| `evidence.bin` | Canonical fixed-record semantic trace. |
| `state.json` | Final display and Julia-host observations, including effective viewport values. |
| `allocations.json` | Aggregate allocation totals plus retained arena baseline samples. |

A screenshot is supporting visual evidence, not proof of scenario success. Require
`manifest.json` to report `result: "passed"` and `trace_complete: true`, then inspect
the relevant semantic records and final state. For viewport scenarios, compare
`view_text_scroll_y` with `view_text_scroll_max` and verify both effective splitter
coordinates in `state.json` before reviewing the image.

The command builds the headed debug application once, gives every selected scenario a
fresh directory under `.build/scenarios/`, and derives its reported result, reason,
failed step, and trace completeness from the validated terminal manifest. A failed or
inconclusive manifest returns a nonzero command status; inconclusive is never reported
as passed. Scenarios remain intentionally absent from `check` and continuous
integration because they require a display.

Allocation commands accept only the stable domain names `animation`, `snapshot_slots`,
and `display_cache`. Each `allocation_checkpoint` must precede the corresponding
`assert_allocation_baseline`; `assert_no_bad_frees` remains aggregate. Successful and
failed baseline comparisons emit typed semantic events, and terminal bundles retain
the checkpoint and final assertion samples in `allocations.json`.

Presentation capture scenarios may set the non-Terminal text viewport with
`{"set_view_scroll":{"y":Y}}` and atomically set both pane dividers with
`{"set_splitters":{"vertical":X,"horizontal":Y}}`. Coordinates are absolute
logical pixels. Each action yields a frame: the display applies it before the next UI
geometry and Dynview preparation pass, clamps it through ordinary UI policy, and only
then advances to a following screenshot command. Final `state.json` records the
effective scroll position, scroll maximum, and both splitter positions.

The session retains at most 4,096 semantic events. Required evidence loss makes a
scenario inconclusive, so combined corpora must remain below that fixed bound rather
than treating a partial trace as success. Run scenarios into fresh artifact directories
and require both `result: "passed"` and `trace_complete: true`.

Native codec qualification is separate from headed scenarios. Run
`julia tools/make.jl probe-sdl3-image` to strict-build the headless probe and write
`.build/sdl3-image-probe/result.json`. A passing result requires SDL_image 3.4,
memory-backed JPEG/PNG/GIF decode, two-frame streaming GIF encode and decode with exact
40/80 ms delays, and complete cleanup. Linux and macOS record the loaded library path
and SONAME or install name; Windows verifies the checked-in provider and PE imports with
MSVC `dumpbin`.

GPU qualification is also separate from `check`. Run
`julia tools/make.jl probe-sdl3` to write `.build/sdl3-probe/result.json` and
`diagnostics.log`. A passing result requires shader compilation, native device and
swapchain creation, frame presentation, resize observation, and complete cleanup.
Windows builds the vendored shadercross and SPIR-V tools with MSVC, converts the probe
shaders to DXIL, selects SDL's `direct3d12` driver, and verifies the executable's
`SDL3.dll` PE import. Set `EUCLID_SDL3_DEV_ROOT` when the complete official SDL3 VC
development package is not at the manifest-derived default under `C:\libs`.

Animated Terminal GIF decode uses SDL_image as its sole production pixel source. Odin
tests verify exact baseline and transparency/disposal canvases, parser-owned encoded and
normalized timing, finite/infinite loop metadata, malformed and quota admission,
between-frame cancellation, exact caller-owned capacities, and concurrent worker-local
decoders. Decoder-reported durations are intentionally ignored; Euclid's allocation-free
GIF walk owns timing and preserves the conservative decode working-budget reservation.
Terminal graphics service tests additionally require Sixel replacement to retain the
old resident until successful candidate upload publication. The checked-in Kitty
animation scenarios verify raster publication, frame transitions, stop/delete behavior,
capture where enabled, complete traces, orderly shutdown, and zero bad frees.

Focused capability scenarios cover GIF recording and armed cancellation, simulation
pause and resume, constrained-figure checkpoint storage, and rapid animation selection
supersession. The GIF completion flow records required `gif_started` and `gif_completed`
events at display-owned phase transitions; its allocation baseline is taken only for the
animation arena because reset-driven snapshot and display-cache high-water growth belongs
to those subsystems. Armed cancellation checks all three arena domains and aggregate bad
frees without entering recording.

Three advertised observations remain deliberately absent from authored scenario waits.
`runtime_shutdown_complete` is emitted during teardown after the scenario runner has
already reached its terminal status. `runtime_idle` and `animation_idle` can become true
between frames but are not observable at the scenario update boundary while ordinary
animation requests continue. Required checkpoint eviction similarly makes the run
inconclusive by design, so the corpus verifies correlated `checkpoint_stored` evidence
without treating eviction as a passing scenario. Covering these cases would require a
scenario-engine contract change rather than another JSONL program.

Runtime-generation rollback coverage lives in
`point-reload-candidate-load-rollback.jsonl` and
`point-reload-animation-enter-rollback.jsonl`. Each scenario selects and lazily
loads an animation, arms one Odin-owned failure with `inject_reload_failure`, then
issues the ordinary `reload_runtime` action. Passing evidence requires correlated
rollback, a committed old-generation animation tick after rollback's forced GC,
retained dynview, zero bad frees, complete trace retention, and orderly shutdown.
The Enter case proves candidate binding reached lifecycle validation; neither hook
mutates packaged assets or introduces Julia global state.

## Current Limits

The automated suite does not establish visual correctness. Rendering, layout,
and animation presentation still need appropriate visual review when those
surfaces change.
