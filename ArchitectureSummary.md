# EuclidApp Architecture Summary

## Table Of Contents

1. [What This Project Is](#what-this-project-is)
1. [Where To Start Reading](#where-to-start-reading)
1. [Host Modules (Odin)](#host-modules-odin)
1. [Runtime Modules (Julia)](#runtime-modules-julia)
1. [Scratchpad Architecture (Interactive Runtime Surface)](#scratchpad-architecture-interactive-runtime-surface)
1. [Odin-Julia Bridge: How the Boundary Works](#odin-julia-bridge-how-the-boundary-works)
1. [Allocation Strategy: Init-First with Explicit Exceptions](#allocation-strategy-init-first-with-explicit-exceptions)
1. [Build and Packaging Model](#build-and-packaging-model)
1. [Isometric Projection and Right-Hand Rule](#isometric-projection-and-right-hand-rule)
1. [Polygon Vertex Order Conventions](#polygon-vertex-order-conventions)
1. [Practical Contributor Guide](#practical-contributor-guide)
1. [Key Architecture Takeaways](#key-architecture-takeaways)

## What This Project Is

EuclidApp is a desktop visualization app for geometric constructions and proofs.
The overall structure includes 2 programming languages, Odin and Julia.

- **Odin** code provides the application shell, rendering loop, simulation data model,
    memory ownership, and bridge exports. It owns long-lived application state
    (`Euclid_General_State`), rendering, UI, and systems (kine + particles + gif capture).
- **Julia** code provides animation/content logic loaded from scripts at runtime. It
    registers an animation tree and drives per-animation behavior by calling exported
    Odin-Julia Bridge functions.

A useful mental model:

- Odin is the **engine and host process**.
- Julia is the **animation/content runtime** running inside that host.

---

## Where To Start Reading

If you are new, read in this order:

1. Host lifecycle path:
   - `src/main.odin`
   - `src/view/view.odin`
1. Host/runtime boundary:
   - `src/julia/julia.odin`
   - `src/julia/odin-julia-bridge.odin`
   - `src/julia/odin-julia-bridge.jl`
1. Julia runtime entry:
   - `src/julia/script.jl`
1. Then continue by module using the maps below, touching only each module's
   highlighted files first.

---

## Host Modules (Odin)

- `src/main.odin`
  - Process entry, argument parsing, startup/shutdown sequencing.

### Core Definitions Module

Purpose: canonical data shapes and global capacity limits.

Important files:

- `src/core/core.odin`
  - Defines major runtime structures (including Julia structures and `Euclid_General_State`).
  - Declares system capacity constants.

### Rendering and UI Module

Purpose: world rendering, projection, tool/shape visuals, runtime UI panels.

Important files:

- `src/view/view.odin`
  - Runtime state wiring and fixed-step update loop (`FIXED_DT`).
- `src/view/elements.odin`
  - World geometry drawing and tool visual rendering.
- `src/view/core/view_core.odin`
  - Shared view render/update helpers used by top-level view code.
- `src/view/core/isomath.odin`
  - Isometric projection math and coordinate transforms.
- `src/view/ui/ui.odin`
  - Tree/settings/text panels and interaction routing.

### Geometry Kernel Module

Purpose: geometric primitives, constraints, and system-level evolution.

Important files:

- `src/kine/shapes.odin`
  - Shape/tool constructors and default geometric setup.
- `src/kine/constraints.odin`
  - Constraint definitions, error functions, and iterative solving.
- `src/kine/system.odin`
  - Frame integration rules, cache/update boundary behavior.

### Bridge and Embedding Module

Purpose: host-side Julia lifecycle and strict Odin<->Julia API boundary.

Important files:

- `src/julia/julia.odin`
  - Julia runtime initialization/shutdown and per-frame orchestration.
- `src/julia/odin-julia-bridge.odin`
  - Exported bridge ABI used by Julia scripts.
- `src/julia/julialib.odin`
  - Low-level Julia embedding declarations (`jl_*`) mirrored from `julia.h`.

### Assets and IO Module

Purpose: packaged asset extraction/reload and generated media output.

Important files:

- `src/files/files.odin`
  - Runtime asset package extraction and path resolution.
- `src/files/gif_encode.odin`
  - GIF encoding internals and output buffer production.

### Particles Module

Purpose: particle simulation and layered visual effects.

Important files:

- `src/particles/particles.odin`
  - Multi-layer particle systems for flicker/trails/dust.

---

## Runtime Modules (Julia)

### Runtime Bootstrap Module

Purpose: script loading, animation registry setup, global frame dispatch.

Important files:

- `src/julia/script.jl`
  - Loads shared modules/content groups.
  - Exposes `init_euclid_scripts` and `global_euclid_loop` for Odin.

### Bridge Wrapper Module

Purpose: Julia-side ergonomic API over bridge exports.

Important files:

- `src/julia/odin-julia-bridge.jl`
  - `@ccall` wrappers plus helper conversion/utility routines.

### Shared Animation Utility Module

Purpose: reusable helpers that keep content scripts concise and consistent.

Important files:

- `src/julia/animations.jl`
  - Pen/compass movement and drawing choreography helpers.
- `src/julia/geometry.jl`
  - Reusable geometric computations.
- `src/julia/nullanimation.jl`
  - Default no-op behavior used for non-leaf/root nodes.

### Interactive Runtime Module

Purpose: REPL-like runtime surfaces and command/session orchestration.

Important files:

- `src/julia/scratchpad.jl`
  - Scratchpad session lifecycle, command queueing, and per-frame evaluation.
- `src/julia/euclidrepl.jl`
  - REPL parsing/evaluation helpers used by interactive runtime flows. Mostly to draw shapes
    immediately, with relative ease.

### Content Modules

Purpose: domain content organized into chapter/family groups.

Important files:

- `src/julia/elements/elements.jl`
  - Euclid Elements group root and registration path.
- `src/julia/proclus/proclus.jl`
  - Proclus group root and registration path.
- `src/julia/hilbert/hilbert.jl`
  - Hilbert group root and registration path.

Each content module typically follows this contract:

- Root module registers tree/category nodes.
- Leaf files provide `get_view_text`, `initialize`, `loop`, `clean`.
- Bridge calls mutate host state; local logic determines pedagogical flow.

---

## Scratchpad Architecture (Interactive Runtime Surface)

The scratchpad is not a normal content animation. It is an embedded interactive
runtime surface that uses the animation lifecycle and view text channel as a
REPL-like control plane.

### What Makes It Architecturally Unique

- It is registered as a regular animation node (`"Scratchpad"`) but behaves as
  an interactive shell instead of deterministic scene content.
- It bridges keyboard-driven UI editing in Odin with queued/evaluated Julia input.
- It uses one-command-per-frame dequeue semantics to keep evaluation latency,
  frame pacing, and failure behavior bounded.
- It supports optional per-frame user hooks, which effectively allow user-provided
  Julia callbacks to run on the simulation timeline.

### Host/UI Side Responsibilities (Odin)

- The `view/ui` module gates scratchpad input handling behind tree selection,
  so keyboard capture only occurs while the Scratchpad node is active.
- Input lives in fixed-size UI runtime buffers (`scratchpad_input`, cursor,
  follow-output flags, last-output length) inside `Euclid_UI_Runtime_State`.
- Enter submission is parse-state aware:
  - Incomplete parse inserts newline for multiline continuation.
  - Complete parse enqueues input through Julia bridge calls.
- Up/Down key history navigation is delegated to Julia, while Odin owns the
  active editable input buffer and cursor behavior.

### Julia Side Responsibilities

- `src/julia/script.jl` exposes dedicated bridge entrypoints for scratchpad
  classify/queue/history/save operations.
- `src/julia/scratchpad.jl` owns session state (`ScratchpadSession`) including:
  - isolated runtime module,
  - input queue,
  - output scrollback,
  - command history,
  - frame hooks,
  - runtime metrics.
- `initialize` creates a fresh session and seeds help text.
- `loop` processes at most one queued command per frame, then runs enabled hooks.
- `get_view_text` returns newline-joined output consumed by Odin text rendering.

### Session Isolation and Lifecycle

- Each session is backed by a fresh runtime module (`EuclidScratchpadSession_*`)
  to isolate evaluated bindings from previous resets.
- `:reset` and intercepted `exit()/quit()` explicitly reset session state without
  terminating the host app.
- `clean` clears session reference on animation unload/switch.

### Safety and Policy Boundaries

- Scratchpad input is filtered by a blocklist policy before eval (for example,
  package-management commands and selected process/file/system call tokens).
- Parse classification runs before queueing/eval and surfaces parse errors into
  scratchpad output.
- Eval and hook failures are converted into user-visible output lines instead of
  panicking host runtime.
- Hooks auto-disable after repeated consecutive failures to prevent persistent
  frame-time error spam.

### Throughput and Observability Guarantees

- Queue, history, and output each have explicit retention caps.
- Queue overflow drops oldest pending entries (bounded-memory behavior).
- Slow eval and slow hook warnings are emitted from timing thresholds.
- Runtime counters (enqueue/dequeue, drops, trims, error counts, transitions)
  are exposed via `:stats` for in-app diagnostics.

---

## Odin-Julia Bridge: How the Boundary Works

### Control Flow

1. Odin initializes Julia and includes `julia/script.jl` from packaged assets.
1. Odin queries Julia functions (`init_euclid_scripts`, `global_euclid_loop`).
1. Julia registration code calls back into exported Odin bridge functions to
  build the animation tree.
1. During runtime, Odin invokes `julia.perform_animation_frame(...)`, which runs
  reload checks plus Julia global loop and current animation loop.
1. Julia animation code manipulates Odin state through bridge exports
  (create/mutate points, constraints, tools, particles, metadata).

### Ownership Model

- Odin owns all core app state and fixed-capacity data structures.
- Julia receives a state pointer and issues operations through exported API calls.
- Bridge functions may restore Odin runtime context
  (`context = state^.SavedContext`) before allocation-sensitive operations.

### Hot Reload Behavior

- Odin checks packaged asset archive mtime at runtime.
- On change, it re-extracts assets, re-includes `script.jl`, refreshes function
  handles, rebuilds animation registry, and attempts to restore the current
  animation by name.

---

## Allocation Strategy: Init-First with Explicit Exceptions

The allocation policy is intentionally init-first in Odin:

- Long-lived application structures are created during startup (global state, core systems,
    tool state, caches) and used statically throughout the lifetime of the application.
- Runtime updates prefer mutating preallocated structures instead of growing state each frame.

This keeps ownership clear and limits fragmentation pressure in hot paths.

That said, there are explicit and justified exceptions outside startup.

### 1) Frame-Scoped Scratch Allocations (Temp Allocator)

Examples:

- UI text rendering converts strings to temporary C strings during drawing.
- View text returned from Julia is cloned into temporary host memory before rendering.

Defense:

- These are scratch values whose lifetime is one frame or less.
- The frame loop performs allocator reset (`free_all(context.temp_allocator)`),
  so this memory is reclaimed deterministically each frame.

### 2) Event-Driven Runtime Allocations (Not Per-Frame)

Examples:

- Asset reload/path resolution builds temporary path strings and metadata during startup/reload checks.
- Julia animation registry stores cloned animation names when scripts register interfaces.
- GIF capture allocates encoder working buffers and final output buffer only for active capture sessions.

Defense:

- These allocations are tied to user actions or lifecycle events, not continuous simulation ticks.
- They happen infrequently relative to frame updates.
- They represent data that is either naturally persistent (registry names) or
  naturally session-scoped (GIF encoding buffers).

### 3) Julia Runtime and GC-Managed Allocations

Examples:

- Julia script loading/JIT compilation.
- Julia-side objects and values produced by animation logic.
- Host-to-Julia call boxing/unboxing and return handling.

Defense:

- This is an intentional language-boundary tradeoff: Odin provides deterministic
  host ownership, while Julia provides dynamic, productive animation scripting
  with GC.
- The boundary keeps responsibilities explicit: Odin owns host state/layout;
  Julia owns its runtime-managed objects.

### Practical Rule of Thumb

- If data is persistent across frames, prefer startup allocation or explicit long-lived ownership.
- If a runtime buffer has a stable maximum size, prefer statically allocated storage owned
  by the long-lived system that uses it, and reuse that storage across updates instead of
  rebuilding it from temporary frame memory.
- If data is transient and frame-local, temp allocator usage is acceptable and expected.
- If data belongs to scripting/runtime orchestration (Julia, asset reload, GIF
  session work), event-driven allocation is acceptable by design.

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

## Isometric Projection and Right-Hand Rule

The isometric helper in `src/view/core/isomath.odin` uses a right-handed
world-space convention.

What that means in practice:

- Hand-position rule used in this project: hold your **right hand palm up**,
  curl the last three fingers naturally, and keep your thumb and index finger
  perpendicular.
- In that pose, the **thumb points +X** and the **index finger points +Y**.
- Therefore, by the right-hand rule (`X × Y = Z`), **+Z is up**
  (height/elevation).
- Positive rotation follows the right-hand rule around each axis: curl your right-hand
  fingers in the rotation direction; your thumb points toward the positive axis.

Projection note:

- The projection maps world coordinates into screen coordinates, so signs in the
  formula account for screen-space Y increasing downward.
- In effect, increasing `coord.z` renders higher on screen, consistent with
  treating +Z as world up.

---

## Polygon Vertex Order Conventions

For filled polygons created from Julia (`create_new_triangle`,
`create_new_square`, `create_new_pentagon`, and future polygon constructors),
**vertex order still matters**, but the renderer now uses general polygon
triangulation instead of shape-specific hardcoded triangle layouts.

Renderer note:

- `src/kine/system.odin` triangulates polygon vertex rings with an
  ear-clipping pipeline (`triangulate_polygon_ear_clip`).
- `src/view/elements.odin` renders the emitted triangle list from the draw cache.
- If the supplied vertex order does not follow the polygon perimeter
  consistently, triangulation can fail or produce visually incorrect faces.

### Required ordering rule (all supported polygons)

- Supply polygon vertices in perimeter order (clockwise or counter-clockwise,
  but consistent around the boundary).
- Never provide crossed/zig-zag/diagonal-jump orderings.
- Triangulation winding is inferred from XY signed area in
  `triangulate_polygon_ear_clip` and triangles are emitted to match that
  winding.
- Ear clipping is the primary path; if a valid ear sequence cannot be resolved
  (for degenerate/non-simple cases), the implementation falls back to a
  winding-aware fan (`emit_polygon_fallback_fan`).

### Practical implications by shape

- Triangle (`create_new_triangle`):
  - Triangulates to one cached triangle.
  - Still provide perimeter order; avoid collinear/degenerate input.
- Square (`create_new_square`):
  - Triangulates to two cached triangles selected by ear clipping.
  - No single hardcoded split order should be treated as universal.
- Pentagon (`create_new_pentagon`):
  - Triangulates to three cached triangles selected by ear clipping.
  - Keep vertices on the perimeter in consistent rotational order.

The same ordering rules apply to any polygon with `n >= 3`.

Practical check when debugging visibility:

1. Verify the input vertex ring is non-self-intersecting and perimeter-ordered.
1. Inspect cached triangle output generated by
   `triangulate_polygon_ear_clip` in `src/kine/system.odin`.
1. If fallback fan triangulation was used, treat the polygon input as likely
   degenerate/non-simple and adjust vertices.
1. Only after triangulation is valid, tune color/alpha/placement.

---

## Practical Contributor Guide

### If You Need To

Choose the owning module first, then touch that module's highlighted files.

- **Lifecycle/timing issues**:
  - Application Lifecycle Module (`src/main.odin`, `src/view/view.odin`).
- **Rendering/UI behavior**:
  - Rendering and UI Module (`src/view/elements.odin`, `src/view/ui/ui.odin`,
    `src/view/core/view_core.odin`).
- **Geometry/constraints behavior**:
  - Geometry Kernel Module (`src/kine/shapes.odin`,
    `src/kine/constraints.odin`, `src/kine/system.odin`).
- **Julia feature surface / bridge contract**:
  - Bridge and Embedding Module + Bridge Wrapper Module
    (`src/julia/odin-julia-bridge.odin`, `src/julia/odin-julia-bridge.jl`).
- **New lesson/content animation**:
  - Content Modules (`src/julia/elements/**`, `src/julia/proclus/**`,
    `src/julia/hilbert/**`).
- **Modify the Scratchpad/REPL surface**:
  - Scratchpad and UI modules (`src/julia/sratchpad.jl`, `src/julia/euclidrepl.jl`,
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
- Assets are packaged and loaded at runtime, enabling script/content iteration without redesigning host architecture.
