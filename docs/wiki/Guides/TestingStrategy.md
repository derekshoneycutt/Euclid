# Testing Strategy

> Tests provide evidence for specific behavior; choose the narrowest useful check, and
> do not claim more than its evidence shows.

## Choose A Verification Path

- **Local Odin or Julia behavior:** Run the corresponding language suite:
  `julia tools/make.jl unit odin` or `julia tools/make.jl unit julia`.
- **Repository gate:** Run
  `cmake --build --preset default --target check`.
- **Runtime ordering, bridge work, display frames, or shutdown:** Run a relevant
  application scenario in a debug build.
- **Deterministic headless runtime path:** Run the optional CMake `harness` target.
- **Visual presentation or platform-native events:** Review the rendered result or
  perform the platform acceptance check; unit tests alone do not establish these claims.

Tests live beside the behavior they exercise: Odin package tests are `*_test.odin`
files under `src/`, and Julia tests live under `src/julia/test/`. Add focused coverage
for changed behavior, then use the complete gate before delivery.

VS Code's Odin Test Explorer uses the workspace
[argument provider](../../../tools/odin-test-arguments.jl) for native linkage and
runtime environment. The provider also generates the selected Julia runtime's
history-search oracle under `.build/test/` and exports its path through
`EUCLID_HISTORY_SEARCH_ORACLE`. The command-line test runner generates a temporary
corpus for the same test; neither launch path requires a manually configured oracle.

Worker-ownership tests use explicit condition-variable gates to establish ordering.
Elapsed wall-clock time must not release a blocked worker or substitute for the
owner's release signal. Font gate regression coverage deliberately holds a worker
beyond the former five-second fixture watchdog before requesting release.

The shared user-data save tests cover coalesced settings and collection writes, retry
retention, and revision-aware failure acknowledgement. A prior transaction success
must not erase an unresolved failure; only a committed batch covering that failure's
revision resolves it.

The `check` target combines the validated build, Odin and Julia tests, and repository
analysis. `vet` runs the validated build and analysis but does not run the application
test suites, so it is not a replacement for `check`.

Interactive verification displays a spinner and elapsed `MM:SS` for the active
phase. Analyzer milestones and diagnostics print above the refreshed line; completion
replaces it with the phase result and final duration. Redirected output and dumb
terminals retain static progress without animation or cursor-control sequences.
The final tables and estimates are unchanged.

## Runtime Scenarios

Scenarios are bounded JSONL programs in [`tools/scenarios/`](../../../tools/scenarios/).
Use them when a behavioral claim crosses ordinary application boundaries—for example,
when a request must be correlated with a later event, a frame must be captured after a
state change, or shutdown evidence matters.

```sh
julia tools/make.jl scenario SCENARIO_NAME
julia tools/make.jl scenario --all
```

An ad hoc scenario can exercise a debug build and retain its evidence bundle:

```sh
julia tools/make.jl run --debug -- \
  --scenario=path/to/scenario.jsonl \
  --scenario-artifacts=.build/scenario
```

Each nonempty line issues one action. Use the vocabulary and limits exposed by the
evidence commands rather than guessing names:

```sh
julia tools/make.jl evidence capabilities
julia tools/make.jl evidence schema
```

### Author A Scenario

Build a scenario as a sequence of observable transitions, not as a script that assumes
work finished after an arbitrary delay. Wait for readiness, issue the ordinary
application action, then wait for the event or state that makes the next step valid:

```jsonl
{"wait_state":"runtime_ready","timeout_ms":10000}
{"select_animation":"Proposition I","as":"selection"}
{"wait_event":"animation_selected","correlation":"selection","timeout_ms":10000}
{"wait_event":"dynview_published","correlation":"selection","timeout_ms":10000}
{"assert_state":"dynview_enabled"}
{"screenshot":".build/scenario/proposition-1.png"}
{"wait_event":"capture_completed","timeout_ms":10000}
{"assert_no_bad_frees":true}
{"shutdown":true}
```

Every nonempty line must be one JSON object selecting exactly one action. A text-bearing
action uses its dedicated field; payload-free actions such as reset or pause use `do`.
The `as` property names the identity returned by an action. A correlated event wait
matches that action's identity, including its kind, ID, and generation. Prefer correlated
waits when another request could produce the same event; use uncorrelated waits for
events such as screenshot completion that do not match the initiating action's identity.

| Scenario need | Common actions |
| --- | --- |
| Change runtime or animation state | `select_animation`, `{"do":"reset_animation"}`, `{"do":"reload_runtime"}` |
| Submit Terminal or presentation content | `scratchpad`, `set_view_content` |
| Wait for progress or verify an observation | `wait_event`, `wait_state`, `assert_state`, `assert_focus` |
| Exercise viewport or input behavior | `set_view_scroll`, `set_splitters`, `key`, `contact_dust` |
| Verify exact Library search text | `{"assert_library_search":"α"}` (nonempty, exact UTF-8 text) |
| Type into an open Favorite name editor | `{"type_library_name":"α"}` (requires input focus on that editor) |
| Capture or retain evidence | `screenshot`, `start_gif`, `checkpoint`, `allocation_checkpoint`, `assert_allocation_baseline` |
| End a run safely | `assert_no_bad_frees`, `shutdown` |

Construction transport has its own boundary: `{"do":"pause_construction"}` holds
authored work, while `simulation_running` and native dust remain independent.
Wait for `construction_paused` to acknowledge the final pending tick. Then
`{"do":"show_completed","as":"figure"}` and a correlated
`{"wait_event":"animation_completed","correlation":"figure"}` prove a distinct
completed-form commit, not elapsed playback. `resume_construction` continues an
ordinary pause or resets a completed form; await `animation_reset_committed` in
the latter case. Full `pause_simulation` and policy `pause_animation` are separate.

The [completed-figure acceptance](../../../tools/scenarios/completed-figure-acceptance.jsonl)
checks transport, completed-first selection, and independent particle disablement.
The [completed-figure lifecycle acceptance](../../../tools/scenarios/completed-figure-lifecycle-acceptance.jsonl)
checks reload retention, selection-policy isolation, ordinary Resume, and captures
representative null, surface, polygon, curve, reflection, and Hilbert figures.
`particle_effects_disabled` requires disabled preference intent and empty world
and presentation material. Do not use `dust_settled` for this: that predicate
intentionally requires live grounded dust. Preference snapshots retain both
`interface.enable_particle_effects` and `animation.open_completed`.
The isolated [completed-preferences persistence acceptance](../../../tools/scenarios/completed-preferences-persistence-acceptance.jsonl)
checks both committed database rows and their restored values in a new process,
including the held completed figure on startup.

Viewport and splitter requests take effect at a frame boundary; put them before the
screenshot whose layout they are meant to exercise. A screenshot completes only after
a presented frame has been captured, so wait for `capture_completed` before depending on
the output file. Correlate other events to the request that should cause them, and make
the scenario fail explicitly through assertions rather than treating a screenshot as a
pass condition.

The scenario runner enforces bounded command, source, line, payload, alias, wait, and
event-retention limits. Query `evidence capabilities` and `evidence schema` for the
current vocabulary and bounds. Keep scenarios focused on one behavioral claim, and use
the checked-in [MIME presentation](../../../tools/scenarios/mime-presentation-acceptance.jsonl),
[keyboard focus](../../../tools/scenarios/keyboard-focus-acceptance.jsonl), and
[context menu](../../../tools/scenarios/context-menu-acceptance.jsonl) scenarios as
examples of longer flows.

For a successful result, inspect the bundle's `manifest.json` and require both
`result: "passed"` and `trace_complete: true`; consult `state.json` and `evidence.bin`
for the relevant final state and semantic events. A screenshot is supporting visual
evidence, not proof that the scenario passed.

Scenarios are intentionally separate from `check`: headed scenarios require a display.
Required evidence loss makes a scenario inconclusive, never passed.

### Native live-resize acceptance

The desktop scheduler is SDL's main-callback interface, including loading. Unit
regressions cover callback result mapping, nonrecursive admission and nonblocking
pacing, copied text/IME payloads, bounded off-thread handoff and shutdown, and
transactional scene-target replacement. Run the complete documented Odin suite;
the driver does not accept invented file or test selectors.

Use the existing
[geometry lifecycle](../../../tools/scenarios/sdl3-geometry-lifecycle.jsonl),
[keyboard focus](../../../tools/scenarios/keyboard-focus-acceptance.jsonl),
[IME targeting](../../../tools/scenarios/ime-text-target-acceptance.jsonl),
[MIME presentation](../../../tools/scenarios/mime-presentation-acceptance.jsonl), and
[GIF cancellation](../../../tools/scenarios/gif-armed-cancellation-restores-allocations.jsonl)
scenarios as bounded integration checks. A successful process alone is insufficient:
inspect each manifest's result and trace-completeness fields. These scenarios do not
themselves synthesize native interactive window resizing.

| Environment | What it can establish | Additional acceptance needed |
| --- | --- | --- |
| Linux/Hyprland/Wayland with Vulkan | Callback startup, ordinary input, compositor-requested size changes, relayout, frame/tick progress, target-size agreement, close and restoration | Actual drag gestures, display-scale transitions, and compositor-specific minimize behavior |
| Linux/X11 with Vulkan | The same lifecycle under the X11 backend when a server is available | Actual WM drag and minimize/restore; XWayland is not a native X11 desktop certification |
| Windows with D3D12 | SDL modal-resize callback progress | Native Windows machine: loading and ready-state drag, normal/paused animation, close during drag |
| macOS with Metal | SDL Cocoa live-resize callback progress | Native Mac: loading and ready-state drag, normal/paused animation, close during drag |

During each platform run, check portrait/landscape reversals, Terminal and Dynview
reflow, DPI/display changes, FPS limiting and vsync on/off, and active GIF cancellation.
Debug `sdl_frame_extent_admitted` records report logical, pixel, and target dimensions.
Match those with presented-frame/fixed-step/animation-tick evidence while resizing.
Programmatic resize requests prove target admission and layout, **not** Windows/macOS
native modal-loop dispatch. Report unavailable platform checks as unperformed.

Native target replacement currently retains a conservative global GPU-idle wait.
Measure any drag stutter separately before changing that resource-lifetime guarantee;
do not infer a scheduling failure solely from compositor/GPU presentation cadence.

### Input And IME Evidence

The [IME text-target scenario](../../../tools/scenarios/ime-text-target-acceptance.jsonl)
checks real field-to-Terminal focus ownership. The
[Terminal editor scenario](../../../tools/scenarios/terminal-editor-acceptance.jsonl)
checks selection replacement, explicit multiline source, continuation, and clean
shutdown. Run the existing keyboard-focus and context-menu scenarios alongside them.
The [Terminal undo scenario](../../../tools/scenarios/terminal-undo-acceptance.jsonl)
checks desktop undo/redo shortcuts, redo-branch replacement, completed-command reset,
and retained edits across incomplete evaluation using evaluated output and clean
shutdown. Its `z` key uses the existing structured `ctrl`/`shift` modifiers.
Unit tests separately cover SDL preedit/commit translation, composing-key suppression,
ordered commit-before-Enter, atomic edits, owner retirement, and foreground encoders.
Undo model and Terminal tests also cover Julia aliases, cursor/selection restoration,
operation grouping, transient preedit, completion, retained capacity, and allocation
failure without partial draft/timeline publication.

The [Terminal completion scenario](../../../tools/scenarios/terminal-completion-acceptance.jsonl)
exercises `func` → `function`, subsequent alternatives without replacing the draft,
evaluation of the resulting function, unique `println` completion, and clean shutdown.
The debug/test-only `terminal_completion_ready` predicate waits for a retained useful
preview before capture or acceptance, rather than guessing at debounce or Julia
response timing. Its screenshots are supporting single-row visual evidence.
Owner-level tests deterministically cover Tab with a ready preview and
before its response, Right acceptance, stale/duplicate responses, undo, Unicode byte
boundaries, multiline replacement, bounded-buffer reuse, and capacity rejection at
the exact byte limit and one byte over. Julia adapter tests exercise common prefixes,
list-only contexts, Unicode cursor conversion, and no-op suppression separately from
host propagation. No popup or candidate-navigation behavior is implied.

These synthetic tests do not certify a desktop IME. Native Linux composition with an
installed IBus/Fcitx engine, candidate-window placement through resize/scroll/DPI changes,
and cancellation during window/menu transitions still require interactive testing.
Windows TSF and macOS input-source checks also require their native platforms. Report
those checks as unperformed unless actually observed; a Linux headed scenario is not
evidence of native candidate selection or cross-platform certification.

Large-store, save/reopen, and warmed-reuse coverage starts at the
[Favorites runner](../../../tools/favorites_scenarios.jl) and owner-local storage tests.

## Harness And Semantic Traces

The optional CMake `harness` target runs a deterministic headless runtime case and
writes `bin/semantic-trace-harness.bin`. It is useful for the runtime path it exercises,
but it is not part of the standard `check` gate.

The evidence CLI can inspect a harness trace or a scenario bundle. Application semantic
tracing also supports an explicit JSONL export through `--semantic-trace-output=PATH`.
These traces provide behavioral evidence; they do not replace tests or prove visual
correctness.

## Limits Of The Evidence

- Passing unit tests establish only the behavior covered by those tests.
- Passing scenarios establish only the observed state and retained events they assert.
- A presented frame or screenshot does not by itself prove successful shutdown, complete
  semantic evidence, or correct behavior on other platforms.
- Window-manager events and other platform-specific behavior may need acceptance checks
  outside the scenario system.

Choose evidence to match the claim, and keep the claim within what was actually run.
