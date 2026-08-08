# EuclidApp Architecture Summary

## Table Of Contents

1. [What This Project Is](#what-this-project-is)
1. [Where To Start Reading](#where-to-start-reading)
1. [Module Map (Odin + Julia)](#module-map-odin--julia)
1. [Scratchpad Architecture (Interactive Runtime Surface)](#scratchpad-architecture-interactive-runtime-surface)
1. [Dynview Text Engine (Hybrid-Immediate Rendering)](#dynview-text-engine-hybrid-immediate-rendering)
1. [Dynamic LaTeX Pipeline (Julia Parse + Odin Layout)](#dynamic-latex-pipeline-julia-parse--odin-layout)
1. [Odin-Julia Bridge: How the Boundary Works](#odin-julia-bridge-how-the-boundary-works)
1. [Allocation Strategy: Init-First with Explicit Exceptions](#allocation-strategy-init-first-with-explicit-exceptions)
1. [Build and Packaging Model](#build-and-packaging-model)
1. [Practical Contributor Guide](#practical-contributor-guide)
1. [Key Architecture Takeaways](#key-architecture-takeaways)

## What This Project Is

EuclidApp is a desktop visualization app for geometric constructions and proofs.
The overall structure includes 2 programming languages, Odin and Julia.

- **Odin** code provides the application shell, rendering loop, simulation data model,
    memory ownership, and bridge exports. It owns long-lived application state
    (`Euclid_General_State`), rendering, UI, and systems (shapes + particles + gif capture).
- **Julia** code provides animation/content logic loaded from scripts at runtime. It
    registers an animation tree and drives per-animation behavior by calling exported
    Odin-Julia Bridge functions.

A useful mental model:

- Odin is the **engine and host process**.
- Julia is the **animation/content runtime** running inside that host.

---

## Where To Start Reading

If you are new, read in this order:

1. Host lifecycle path (`src/main.odin`, `src/view/view.odin`).
1. Host/runtime boundary (`src/bridge/abi.odin`, `src/bridge/abi-*.odin`, `src/bridge/bootstrap.odin`, `src/bridge/animations.odin`, `src/bridge/scene.odin`, `src/bridge/scratchpad.odin`, `src/bridge/dynview.odin`, `src/julia/odin-julia-bridge.jl`).
1. Dynview runtime (`src/dynview/dynview.odin`, `src/dynview/compile.odin`, `src/dynview/layout_build.odin`, `src/dynview/layout_math_programs.odin`, `src/dynview/styles.odin`).
1. Julia runtime entry (`src/julia/script.jl`).
1. Then continue by module using the maps below, touching only each module's
   highlighted files first.

---

## Module Map (Odin + Julia)

| Section | Module | Purpose | Key files |
| --- | --- | --- | --- |
| **Odin** | Application Lifecycle | Process entry and startup/shutdown sequencing. | `src/main.odin` |
| **Odin** | Core Definitions | Canonical runtime data shapes and capacity constants. | `src/core/core.odin` |
| **Odin** | Rendering and UI | Frame loop wiring, world rendering, panel rendering, and interaction routing. | `src/view/view.odin`, `src/view/elements.odin`, `src/view/core/view_core.odin`, `src/view/core/isomath.odin`, `src/view/ui/ui.odin` |
| **Odin** | Dynview Runtime | Text/math command compilation, layout planning, and draw-ready dynview caches. | `src/dynview/dynview.odin`, `src/dynview/compile.odin`, `src/dynview/layout_build.odin`, `src/dynview/layout_math_programs.odin`, `src/dynview/styles.odin`, `src/dynview/tracking.odin` |
| **Odin** | Geometry Kernel | Shapes, constraints, and system evolution/integration rules. | `src/shapes/shapes.odin`, `src/shapes/constraints.odin`, `src/shapes/system.odin` |
| **Odin** | Bridge and Embedding | Host-side Julia lifecycle and strict bridge ABI surface. | `src/bridge/abi.odin`, `src/bridge/abi-*.odin`, `src/bridge/bootstrap.odin`, `src/bridge/animations.odin`, `src/bridge/scene.odin`, `src/bridge/scratchpad.odin`, `src/bridge/dynview.odin` |
| **Odin** | Julia Interop Dependency | External Odin<->Julia interop package consumed by bridge embedding code. | `src/julialib/julialib.odin` (git submodule) |
| **Odin** | Assets and IO | Asset package extraction/path resolution and GIF output internals. | `src/files/files.odin`, `src/files/gif_encode.odin` |
| **Odin** | Particles | Multi-layer particle systems and visual effects. | `src/particles/particles.odin` |
| **---** | **--- Julia Modules ---** | **---** | **---** |
| **Julia** | Runtime Bootstrap | Script loading, animation registration, and global frame dispatch. | `src/julia/script.jl` |
| **Julia** | Bridge Wrapper | Ergonomic Julia wrappers around bridge exports. | `src/julia/odin-julia-bridge.jl` |
| **Julia** | Shared Animation Utilities | Reusable animation and geometry helper routines. | `src/julia/animations.jl`, `src/julia/geometry.jl`, `src/julia/nullanimation.jl` |
| **Julia** | Interactive Runtime | Scratchpad/REPL session lifecycle, queueing, and evaluation flow. | `src/julia/scratchpad.jl`, `src/julia/euclidrepl.jl` |
| **Julia** | LaTeX Compiler | Compiles LaTeX to dynview command instructions. | `src/julia/latex.jl` |
| **Julia** | Content Modules | Domain content roots and leaf animation definitions. | `src/julia/elements/elements.jl`, `src/julia/proclus/proclus.jl`, `src/julia/hilbert/hilbert.jl` |

Content-module contract:

- Root modules register tree/category nodes.
- Leaf files provide `get_view_text`, `initialize`, `loop`, `clean`.
- Bridge calls mutate host state while Julia controls pedagogical flow.

---

## Scratchpad Architecture (Interactive Runtime Surface)

Scratchpad is an interactive runtime surface, not a normal deterministic
animation. It is mounted in the animation tree as `"Scratchpad"`, but behaves
like an embedded REPL control plane.

### Core Architecture

- Odin owns UI input capture, text panel interaction, and buffer/cursor state.
- Julia owns command parsing/evaluation, command history, and output stream
  generation.
- Communication crosses the bridge through explicit scratchpad entrypoints.

### Frame Model And Lifecycle

- Input is only captured when the Scratchpad node is the active selection.
- Enter submission is parse-aware:
  - incomplete parse appends newline
  - complete parse enqueues command
- Julia processes at most one queued command per frame, then runs optional
  per-frame hooks.
- Sessions are isolated via fresh runtime modules and support explicit
  reset/clean transitions without terminating the host.

### Safety, Reliability, And Limits

- Input is policy-filtered before eval.
- Parse/eval/hook failures are surfaced as user-visible output, not host
  crashes.
- Repeated failing hooks auto-disable to prevent recurring frame-time spam.
- Queue/history/output are bounded with retention caps and overflow behavior.
- Runtime diagnostics are exposed through `:stats` counters.

---

## Dynview Text Engine (Hybrid-Immediate Rendering)

Dynview now has 2 parallel surfaces every frame:

- Plain fallback text (`get_view_text`) for guaranteed readability.
- Structured command stream for styled text, inline atoms, and recursive math blocks.

Snapshot and display flow:

1. The Julia worker produces fallback text and dynview commands in a bounded
  worker-owned staging runtime.
1. The worker publishes a complete animation-tagged semantic snapshot.
1. Odin validates and imports populated spans at a frame boundary.
1. Odin compiles command buffers to cached plain/copy/layout state.
1. If compile/layout is valid, Odin renders dynview output.
1. If any stream stage fails, Odin falls back to plain text with no host crash.

### Architectural Contract

| Ownership | Odin | Julia |
| --- | --- | --- |
| Runtime/UI state | Owns front buffer/cache/layout/draw and copy-hit targets | Reads nothing directly |
| Text intent | Validates and consumes immutable snapshots | Produces fallback + optional stream in worker staging |
| Failure semantics | Invalid stream marks cache invalid and falls back | Must treat non-OK bridge status as stop-and-fallback |

---

## Dynamic LaTeX Pipeline (Julia Parse + Odin Layout)

Dynamic LaTeX support is now a first-class dynview path, not a special case.
The parser and compiler live in `src/julia/latex.jl`; host import, measure,
and draw live in `src/dynview/**` with bridge import boundaries in
`src/bridge/dynview.odin`.

### Parsing Algorithm (Julia)

`src/julia/latex.jl` uses a recursive-descent parser with normalization and
payload compilation:

| Stage | Core functions in `src/julia/latex.jl` | Result |
| --- | --- | --- |
| Tokenize | `tokenize_latex`, `read_command_token`, `read_text_token` | `LatexToken[]` stream |
| Parse | `parse_sequence`, `parse_atom`, `parse_command_atom`, `consume_scripts!` | `LatexRun[]` semantic tree |
| Normalize | `normalize_runs` and script canonicalization | Stable AST form |
| Compile | `compile_emit_program`, `math_payload_ops_for_runs` | Recursive `MathPayloadOp[]` |
| Serialize/Cache | `resolve_cache_entry`, `latex_to_plain_text` | Cached parse + canonical fallback |
| Bridge Encode | `bridge_math_payload_preorder`, `replay_emit_math_block!` | Flat op stream + shared text blob |

Key parsing behavior now covered in tests includes nested scripts, accents,
radicals, fractions, stretch delimiters, and matrix environments.

### End-To-End Flow

```mermaid
flowchart LR
    A[Julia source string]
    B[src/julia/latex.jl\nparse_latex]
    C[LatexRun tree]
    D[compile_emit_program\nMathPayloadOp tree]
    E[bridge_math_payload_preorder\nops + text blob]
    F[Odin bridge\ndynview_math_block_from_ops]
    G[Odin cache\nmath_programs/math_commands]
    H[Odin dynview layout\nmeasure_math_program + layout_consume_math_block]
    I[Rendered dynview math block]
    J[Fallback plain text]

    A --> B --> C --> D --> E --> F --> G --> H --> I
    D --> J
```

### Runtime Boundaries For LaTeX

- Julia side:
  - `replay_emit_math_block!` and `emit_latex_dynview!` emit recursive math
    blocks through `dynview_math_block_from_ops`.
  - Parse cache key is `(source, PARSER_GRAMMAR_VERSION, style_profile)`.
- Odin side:
  - `dynview_math_block_from_ops` validates spans/capacity and recursively imports
    child programs into `math_programs` and `math_commands`.
  - `layout_math_programs.odin` measures script/large-op/fraction/radical/matrix
    structures before draw.

Practical effect: math layout is now data-driven from Julia but rendered with
host-side deterministic metrics and fallback safety.

---

## Odin-Julia Bridge: How the Boundary Works

### Basic Flow

```mermaid
sequenceDiagram
  participant D as Display Thread
  participant W as Julia Worker
  participant B as Bridge API
  participant J as Julia Runtime

  D->>W: Initialize request
  W->>J: initialize + include("julia/script.jl")
  W->>J: resolve init_euclid_scripts/global_euclid_loop
  J->>B: register animation tree
  B->>D: mutate quarantined startup state
  W-->>D: Ready event

  loop Per frame
    D->>W: nonblocking coalesced animation tick
    W->>J: run global + selected animation loops
    J->>B: read immutable query snapshot
    J->>B: capture mutations in scene-command batch
    W-->>D: complete tick event
    D->>D: commit batch at fixed-step boundary
    D->>D: solve constraints before next snapshot
    D->>W: nonblocking view snapshot request
    W->>J: get_view_text(state_ptr)
    J->>B: emit into worker dynview staging
    W-->>D: complete view snapshot event
    D->>D: validate, import, compile, layout, draw
  end

  alt Asset package changed
    W->>J: include candidate script.jl
    W->>W: build staged handles + registry
    W->>W: restore current animation by stable ID
    W->>D: publish generation or retain previous generation
  else No change
    W->>J: continue normal frame loop
  end
```

### Ownership And Rules

- Odin owns application state, memory, rendering, and final frame orchestration.
- One persistent worker thread owns Julia initialization, every Julia C API
  operation, callback handles, and Julia shutdown.
- Startup uses bounded typed channels and nonblocking event draining so the
  display continues rendering while Julia initializes and registers content.
- Scratchpad submission, completion, history, cursor reset, and save-history
  operations use bounded copied requests with correlated, generation-checked
  replies. View-text generation publishes bounded immutable semantic snapshots;
  panel drawing does not call Julia. Every selected animation loop captures its
  recurring mutations in a bounded ordered scene-command batch whose vocabulary
  covers the current animation catalogue. The display thread validates the
  entire batch and commits it atomically at a fixed-step boundary. Canonical
  constraints settle worker-commanded tool geometry before rendering. Animation
  ticks are nonblocking, bounded to one pending request, and coalesce elapsed
  fixed-step time up to 250 ms. Tick queries use worker-slot snapshots rather
  than canonical scene state. Selection and reset invalidate stale results;
  lifecycle transitions remain rare serialized compatibility tasks because
  initialization creates stable IDs and rebuilds canonical scene state.
- Reload builds a fresh interface catalogue on the owner thread and publishes
  it only after callback validation, registration, and stable-ID restoration.
  Failure retains the previous interface generation and suppresses repeated
  retries for the same broken package revision.
- Worker completion events carry explicit success and request identity.
  Display-owned diagnostics retain failed request, queue saturation, reload
  stage, lifecycle state, and runtime generation without consulting Julia.
- Julia owns animation/content logic and drives changes only through bridge APIs.
- Bridge failures should be surfaced clearly; no silent state corruption paths.
- Bridge entrypoints restore the Julia worker's saved Odin runtime context
  (`context = state^.saved_context`) before allocation-sensitive work.

---

## Allocation Strategy: Init-First with Explicit Exceptions

This policy is strict by design.

### Non-Negotiable Rules

- Default rule: no growing host allocations in steady per-frame paths.
- Long-lived host state must be allocated at startup and reused.
- When a maximum size is known, preallocate and mutate in place.
- New per-frame heap growth requires explicit justification in review.

### Allowed Exceptions

1. Frame-scoped scratch memory from the temp allocator.
   - Example: temporary UI/text conversion buffers.
   - Requirement: reclaimed by frame reset (`free_all(context.temp_allocator)`).
1. Julia runtime GC-managed allocations.
   - Julia owns script/runtime objects.
   - Odin owns host state and must stay deterministic on the host side.
1. Dedicated virtual arenas for lifecycle-scoped subsystems.
   - Examples: GIF encoder working memory and bridge animation-name storage.
   - Requirement: `arena_free_all` on logical reset/reload and `arena_destroy`
    on subsystem/application teardown.
1. Event-driven allocations outside steady frame loops.
   - Current approved cases are intentionally narrow:
     1. Final contiguous GIF output buffer returned by encoder end with documented allocation.
     1. Asset-unpack decompression staging allocation released immediately when unpack completes.
   - Requirement: tied to lifecycle/user events, not continuous simulation ticks.

### Current Arena Notes

- GIF encoder internals are arena-backed for session-local working memory.
- Bridge animation names are arena-backed and reset as a batch on hot reload.

### Not Allowed Without Explicit Approval

- Growing slices/arrays every frame in hot UI, view, or simulation loops.
- Rebuilding stable-capacity runtime buffers from scratch each frame.
- Hiding ownership so it is unclear who allocates, mutates, and frees.

---

## Build and Packaging Model

- `make.jl` builds Odin executable and package runtime assets into `bin/assets.pkg`.
- Packaged assets include:
  - `src/julia/**` scripts
  - `src/view/shaders/**`
  - `assets/**`
  - `manifest.txt`
- At startup, app unpacks `assets.pkg` to a writable cache directory and resolves runtime paths from there.

---

## Practical Contributor Guide

### If You Need To

Choose the owning module first, then touch that module's highlighted files.

- **Lifecycle/timing issues**:
  - Application Lifecycle Module (`src/main.odin`, `src/view/view.odin`).
- **Rendering/UI behavior**:
  - Rendering and UI Module (`src/view/elements.odin`, `src/view/ui/ui.odin`,
    `src/view/core/view_core.odin`).
- **Dynview text/math behavior**:
  - Dynview Runtime Module (`src/dynview/dynview.odin`,
    `src/dynview/compile.odin`, `src/dynview/layout_build.odin`,
    `src/dynview/layout_math_programs.odin`, `src/dynview/styles.odin`).
- **Geometry/constraints behavior**:
  - Geometry Kernel Module (`src/shapes/shapes.odin`,
    `src/shapes/constraints.odin`, `src/shapes/system.odin`).
- **Julia feature surface / bridge contract**:
  - Bridge and Embedding Module + Bridge Wrapper Module
    (`src/bridge/abi.odin`, `src/bridge/abi-*.odin`, `src/julia/odin-julia-bridge.jl`).
- **New content animation**:
  - Content Modules (`src/julia/elements/**`, `src/julia/proclus/**`,
    `src/julia/hilbert/**`).
- **Modify the Scratchpad/REPL surface**:
  - Scratchpad and UI modules (`src/julia/scratchpad.jl`, `src/julia/euclidrepl.jl`,
    `src/view/ui/scratchpad_panel.odin`)

### Typical New Animation Workflow

1. Add Julia animation module/file in `src/julia/...`.
1. Implement `get_view_text`, `initialize`, `loop`, `clean`.
1. Register it via `add_child_animation_interface` in the relevant group init script.
1. If bridge functionality is missing, add symmetric Odin export + Julia wrapper.

Review [AnimationsStyle.md](AnimationsStyle.md) for considerations on how to
make animations "fit in".

---

## Key Architecture Takeaways

- The app is **host-driven**: Odin controls lifecycle, simulation pacing, rendering, and core state.
- Julia is **content-driven**: scripts define what animation behavior runs and what geometry/tools are manipulated.
- The bridge is the contract: keep Odin exports and Julia wrappers aligned.
- Host memory strategy is lifecycle-scoped: startup allocations, temp scratch,
  and dedicated arenas for targeted subsystems.
- Dynview is now a dual-path text system: fallback plain text plus validated structured streams.
- LaTeX is parsed and compiled in Julia (`src/julia/latex.jl`) and laid out/rendered in Odin dynview.
- Assets are packaged and loaded at runtime, enabling script/content iteration without redesigning host architecture.
