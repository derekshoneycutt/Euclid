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

The `check` target combines the validated build, Odin and Julia tests, and repository
analysis. `vet` runs the validated build and analysis but does not run the application
test suites, so it is not a replacement for `check`.

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
| Capture or retain evidence | `screenshot`, `start_gif`, `checkpoint`, `allocation_checkpoint`, `assert_allocation_baseline` |
| End a run safely | `assert_no_bad_frees`, `shutdown` |

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
