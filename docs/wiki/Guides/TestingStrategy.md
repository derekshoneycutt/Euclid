# Testing Strategy

## Table Of Contents

1. [Purpose](#purpose)
1. [Testing Layers](#testing-layers)
1. [Semantic Trace Contract](#semantic-trace-contract)
1. [Deterministic Execution Model](#deterministic-execution-model)
1. [Headless Harness](#headless-harness)
1. [Scenario Authoring](#scenario-authoring)
1. [Checkpoint Snapshots](#checkpoint-snapshots)
1. [End-To-End Direction](#end-to-end-direction)
1. [Failure Policy](#failure-policy)
1. [Performance And Volume Controls](#performance-and-volume-controls)
1. [Current Coverage](#current-coverage)
1. [Known Gaps](#known-gaps)
1. [Engineering Guidelines](#engineering-guidelines)

## Purpose

This document describes Euclid's testing strategy for runtime correctness, animation behavior,
and semantic observability.

The foundation of that strategy is the ordinary unit and module test suite. Those tests are the
baseline for correctness in geometry, dynview, files, particles, bridge behavior, and runtime
invariants. Semantic tracing and deterministic harness execution build on top of that baseline;
they do not replace it.

The project now has two related but distinct capabilities layered over the standard test suite:

- a versioned semantic trace system for machine-readable runtime evidence;
- a deterministic headless harness for exact-step animation and runtime scenario execution.

The goal is to make behavior reviewable and reproducible without claiming that semantic
correctness proves rendered pixel correctness. Rendering regressions, layout issues, and visual
review remain separate concerns.

## Testing Layers

Euclid's test strategy is intentionally layered.

### Unit And Focused Module Tests

These are the foundation of the test strategy and the first place new behavior should be
validated. They cover local invariants and narrow behavior:

- JSONL serialization and trace buffering;
- scene-command validation and commit behavior;
- point, constraint, dynview, and simulation helpers;
- configuration parsing and overflow policy.

These tests should stay fast, bounded, and close to the code under test. When a bug can be
proven at this level, it should be proven at this level before reaching for the harness or trace
system.

### Embedded Runtime Integration Tests

These run the embedded Julia runtime against production host behavior without creating a window.
They are the right place to verify:

- runtime startup and shutdown;
- animation selection by stable UUID;
- fixed-step progression;
- committed versus rejected animation ticks;
- checkpoint capture and generation identity.

### Headless Scenario Tests

These run deterministic animation scenarios through the test-only harness executable. They are
for semantic animation verification, not visual review.

### Running-Application End-To-End Tests

These should launch the built application, collect trace artifacts, and correlate semantic
checkpoints with visual artifacts. This layer is planned but not yet implemented.

### Visual Review

Screenshots, GIFs, and manual review remain necessary. The semantic trace does not prove draw
order, shader correctness, clipping quality, antialiasing, or label readability.

## Semantic Trace Contract

The trace system is disabled by default. Enabling it must not alter runtime semantics, thread
ownership, or publication order.

### Core Rule

Trace committed semantics, not attempted operations.

A Julia callback may create a scene-command batch, but point movement is not a traceable fact
until the display thread validates and commits that batch. Invalid or stale work should appear
as rejection evidence, not false movement.

### Output Model

Trace output is JSON Lines. Each line is one complete JSON object with a stable schema envelope
and monotonically increasing sequence number.

The trace starts with lifecycle records such as `trace.started` and `trace.configuration` and,
when shutdown is orderly, ends with `trace.finished`.

### Ownership

- Core owns the fixed-capacity trace storage embedded in runtime state.
- The trace module owns configuration, serialization, file lifecycle, and overflow policy.
- The display thread publishes records from authoritative commit and post-join boundaries.
- Julia owner work and simulation workers do not write trace files or format trace JSON.

### Overflow Policy

Strict mode treats trace-invalidating overflow or serialization failure as run failure.
Diagnostic mode may drop records, but it must count the loss and emit an overflow summary when
capacity is available.

## Deterministic Execution Model

Semantic animation testing depends on deterministic stepping, not wall-clock playback.

The canonical fixed-step boundary is `run_deterministic_fixed_step`. It is the operation shared
by the interactive runtime and the headless harness.

That boundary currently includes:

1. publish the newest valid animation tick;
1. schedule the next Julia animation tick;
1. run particle and constraint workers;
1. join the fixed-step worker batch;
1. advance display-owned `fixed_step` and `simulation_time`;
1. emit post-join trace records.

The interactive app adds presentation policy around that step. The headless harness uses the
step directly.

## Headless Harness

The headless harness exists so deterministic runtime and animation scenarios can run without a
window, renderer, audio device, or UI input path.

### Harness Responsibilities

The harness currently supports:

- explicit packaged-asset root selection;
- animation selection by stable UUID;
- exact fixed-step advancement;
- strict semantic trace output;
- optional invocation of a Julia-authored scenario callback after stepping.

### Harness Boundaries

The harness is a test-only executable target. It reuses production runtime modules but is not
part of the default application build. It should not become a production control surface.

### Current Entry Points

The harness binary accepts explicit runtime arguments for:

- asset root;
- animation UUID;
- step count;
- trace output path;
- optional scenario callback name.

The build system also provides a convenience target that builds and runs the default harness
scenario and writes a trace artifact for review.

## Scenario Authoring

Scenario checks should remain ordinary Julia code rather than a new custom language.

The current model is intentionally narrow:

- Odin owns startup, stepping, and shutdown;
- Julia receives a named scenario callback after deterministic stepping;
- scenario code reads bridge-visible state and returns success or failure.

That is enough for the first semantic animation scenarios. The API can grow later, but it should
grow around stable data access and clear failure semantics rather than speculative breadth.

## Checkpoint Snapshots

Checkpoint snapshots establish canonical state at a stable post-join boundary.

### Valid Boundary

A checkpoint is valid only after the deterministic fixed-step worker join completes and the
display side has assigned current step identity.

### Current Contents

The first checkpoint schema is deliberately bounded. It includes:

- run and generation identity;
- fixed-step sequence and simulation time;
- animation identity;
- bounded point records;
- point and constraint capacity counters;
- pen and compass summaries;
- failure and rejection counters;
- trace validity counters.

### Usage Rule

The direct runtime snapshot and the serialized `trace.checkpoint` record should describe the
same canonical state. The trace is a serialized view of the checkpoint, not a second source of
truth.

## End-To-End Direction

The next major testing expansion is running-application end-to-end validation.

That work is not just more tracing. It requires:

- an external orchestration path for the built app;
- request-driven checkpoints instead of always-on checkpoint volume;
- visual artifact capture correlated by run and checkpoint identity;
- a CI-side consumer that validates JSONL ordering and artifact completeness.

The open design question is whether the built app should consume a test-only scenario manifest,
remain launch-and-observe, or expose a narrow local control channel. The current bias is toward
a test-only scenario manifest rather than a live control channel.

## Failure Policy

Testing infrastructure should fail loudly and predictably.

Expected failure modes include:

- invalid animation selection;
- strict trace overflow;
- trace serialization failure;
- rejected animation ticks when a scenario expected none;
- invalid checkpoint boundaries;
- non-orderly runtime shutdown;
- scenario assertion failure.

Harness and end-to-end runs should return a failing process status and preserve enough trace
output to diagnose the failure without rerunning under a debugger.

## Performance And Volume Controls

Tracing and testing infrastructure need bounded overhead.

Current expectations:

- disabled trace mode should be effectively inert;
- enabled trace mode uses bounded storage and explicit output buffers;
- summary and checkpoint records should stay structured and bounded;
- high-volume records should be summarized or filtered rather than emitted blindly.

For future E2E work, always-on checkpoint capture per fixed step is likely too chatty. The
system should move toward explicit or phase-driven checkpoint requests for external orchestration.

## Current Coverage

The current implementation already covers:

- trace foundation and JSONL lifecycle;
- runtime and animation lifecycle events;
- committed versus rejected animation tick evidence;
- post-commit geometry and tool summary events;
- summarized particle emission events;
- deterministic fixed-step identity;
- headless runtime startup and shutdown;
- bounded checkpoint snapshot emission;
- a first Julia-authored scenario callback path.

## Known Gaps

The main remaining gaps are:

- request-driven checkpoint control;
- running-app external orchestration;
- screenshot or visual artifact correlation;
- CI-side trace validation and artifact consumption;
- broader semantic scenario coverage across real content;
- release-side smoke and visual regression packaging.

## Engineering Guidelines

When extending the testing system:

- add or update focused unit tests before extending semantic trace or harness behavior;
- keep semantic records tied to authoritative commit or post-join boundaries;
- do not let Julia or simulation workers write trace output directly;
- keep test-only control paths out of the default production surface;
- prefer deterministic step counts, stable UUIDs, and explicit tolerances;
- keep scenario assertions ordinary Julia over stable data;
- keep checkpoint schemas bounded and expand them only when a test needs more;
- do not treat trace correctness as proof of pixel correctness.
