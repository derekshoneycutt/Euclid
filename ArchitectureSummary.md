# EuclidApp Architecture Summary

## Table Of Contents

1. [What This Project Is](#what-this-project-is)
1. [High-Level Runtime Architecture](#high-level-runtime-architecture)
1. [Where To Start Reading](#where-to-start-reading)
1. [Odin Side (Host Application)](#odin-side-host-application)
1. [Julia Side (Scripted Animation Runtime)](#julia-side-scripted-animation-runtime)
1. [Odin-Julia Bridge: How the Boundary Works](#odin-julia-bridge-how-the-boundary-works)
1. [Memory and Compilation Model](#memory-and-compilation-model)
1. [Allocation Strategy: Init-First with Explicit Exceptions](#allocation-strategy-init-first-with-explicit-exceptions)
1. [Build and Packaging Model](#build-and-packaging-model)
1. [Practical Contributor Guide](#practical-contributor-guide)
1. [Key Architecture Takeaways](#key-architecture-takeaways)

## What This Project Is

EuclidApp is a desktop visualization app for geometric constructions and proofs.

- **Odin** provides the application shell, rendering loop, simulation data model, memory ownership, and bridge exports.
- **Julia** provides animation/content logic loaded from scripts at runtime.

A useful mental model:

- Odin is the **engine and host process**.
- Julia is the **animation/content runtime** running inside that host.

---

## High-Level Runtime Architecture

```text
main.odin
  -> unpack assets.pkg (scripts, shaders, assets)
  -> initialize Julia runtime
  -> create app state + window + render resources
  -> fixed-step update loop:
       - animation selection/reload handling
      - Julia frame orchestration (global loop + selected animation loop)
       - particle update
       - constraint solve
       - draw frame
  -> shutdown window/resources
  -> shutdown Julia runtime
```

Core split of concerns:

- **Odin** owns long-lived application state (`EuclidGeneralState`), rendering,
  UI, and systems (kine + particles + gif capture).
- **Julia** registers an animation tree and drives per-animation behavior by
  calling exported Odin bridge functions.

---

## Where To Start Reading

If you are new, read in this order:

1. `src/main.odin`
   - Application startup/shutdown sequence.
1. `src/view/view.odin`
   - State initialization and the fixed timestep window loop.
1. `src/julia/julia.odin`
   - Host-side Julia lifecycle and per-frame orchestration (`perform_animation_frame`).
1. `src/julia/odin-julia-bridge.odin`
   - Exported C ABI bridge operations that Julia scripts call into.
1. `src/julia/script.jl`
   - Julia-side entrypoint and script/module loading.
1. `src/julia/odin-julia-bridge.jl`
   - Julia wrapper API over bridge exports.

Then branch out to module-specific files listed below.

---

## Odin Side (Host Application)

### Entry and Lifecycle

- `src/main.odin`
  - Ensures packaged assets are unpacked.
  - Initializes and later terminates Julia (`initiate_julia` / `end_julia`).
  - Starts the main window loop.

### Global State and Core Types

- `src/core/core.odin`
  - Defines central state: `EuclidGeneralState`.
  - Defines kinematic shape/constraint structs and draw-cache structs.
  - Defines Julia interface structs (`EuclidJuliaInterface`, animation interface entries).
  - Sets capacity constants (`MAX_KINEPOINTS`, `MAX_KINECONSTRAINTS`, etc.).

### Window Handling, Rendering, and UI

- `src/view/view.odin`
  - Creates persistent runtime state (surface, particle system, point system, tools).
  - Runs fixed-step simulation (`FIXED_DT`) with a frame accumulator.
  - Calls `julia.perform_animation_frame(...)` each simulation step.
  - Triggers rendering of scene + UI each frame.
- `src/view/elements.odin`
  - Draws surface and shape/tool visuals.
  - Uses shader-backed stroke rendering for pen/compass.
- `src/view/ui.odin`
  - Tree UI of registered animations.
  - Settings controls (FPS display, GIF controls, etc.).
- `src/view/isomath.odin`
  - Isometric projection helpers.
- `src/view/gif_capture.odin`
  - Captures animation cycles to GIF from view area.

### Assets and Packaging Runtime

- `src/files/files.odin`
  - Unpacks `assets.pkg` into a writable cache location.
  - Resolves packaged asset paths (Julia scripts, shaders, textures/fonts).
  - Supports asset reload checks via archive modification time.

### Kinematics and Constraints

- `src/kine/shapes.odin`
  - Shape/tool constructors and default structural setup.
- `src/kine/constraints.odin`
  - Constraint definitions, error metrics, and iterative solving.
- `src/kine/system.odin`
  - Animation boundary freezing/clearing and draw-cache generation/interpolation.

### Particles

- `src/particles/particles.odin`
  - Multi-layer particle system used for trails/flicker/burnout/dust effects.

### GIF Encoding

- `src/gif/gif_encode.odin`
  - Implements GIF encoder internals used by capture flow.
  - Handles palette/frame encoding and output buffer construction.

### Julia FFI Bindings (Low-Level)

- `src/julialib/julialib.odin`
  - Odin declarations for Julia embedding API (`jl_*`).
  - Includes runtime init/eval/call/exception and type declarations.

### Julia Host Runtime and Bridge Exports

- `src/julia/julia.odin`
  - Owns Julia lifecycle (`initiate_julia`, `end_julia`) and interface handle setup.
  - Runs per-step Julia orchestration (`perform_animation_frame`) and reload checks.
- `src/julia/odin-julia-bridge.odin`
  - Defines exported C ABI operations used by Julia scripts for geometry/tools/constraints/particles.

---

## Julia Side (Scripted Animation Runtime)

### Julia Entry and Registration

- `src/julia/script.jl`
  - Loads bridge wrapper + shared modules + content groups.
  - Exposes `init_euclid_scripts` and `global_euclid_loop` expected by Odin.
  - Registers root nodes and child animation interfaces.

### Julia Bridge Wrapper API

- `src/julia/odin-julia-bridge.jl`
  - Julia-friendly wrappers over Odin exported bridge calls (`@ccall`).
  - Defines mirror bridge structs for point/constraint/shape views.
  - Provides helper overloads and color conversion utilities.

### Shared Julia Utility Modules

- `src/julia/animations.jl`
  - Reusable animation helper routines for pen/compass movement and drawing behavior.
- `src/julia/geometry.jl`
  - Geometric helper computations (line intersections, circle intersections).
- `src/julia/nullanimation.jl`
  - Default no-op animation behavior used for category/root nodes.

### Content Groups

- `src/julia/elements/`
  - Euclid Elements hierarchy and scripts (Book I definitions/postulates/propositions).
- `src/julia/proclus/`
  - Proclus commentary animations.
- `src/julia/hilbert/`
  - Hilbert foundations content and axiom-driven animations.

Pattern for content organization:

- Group root script registers a root tree node.
- Child scripts register specific animation entries with `get_view_text`,
  `initialize`, `loop`, `clean` handlers.

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

## Memory and Compilation Model

### Odin

- Built ahead-of-time into the native executable (`bin/euclid` or `bin/euclid.exe`).
- Primary application state is manually managed and long-lived.
- Design prefers preallocated/fixed-capacity arrays to avoid uncontrolled growth.

### Julia

- Embedded runtime initialized inside Odin process.
- Scripts are loaded/included at runtime from packaged assets.
- Animation logic executes JIT-compiled Julia code with Julia GC-managed allocations.

Practical implication:

- Performance-critical host/render/simulation scaffolding stays in Odin.
- Flexible animation authoring and content iteration stay in Julia.

---

## Allocation Strategy: Init-First with Explicit Exceptions

The allocation policy is intentionally init-first in Odin:

- Long-lived application structures are created during startup (global state, core systems, tool state, caches).
- Runtime updates prefer mutating preallocated structures instead of growing state each frame.

This keeps ownership clear and limits fragmentation pressure in hot paths.

That said, there are explicit and justified exceptions outside startup.

### 1) Frame-Scoped Scratch Allocations (Temp Allocator)

Examples:

- UI text rendering converts strings to temporary C strings during drawing.
- View text returned from Julia is cloned into temporary host memory before rendering.
- Dust collision grid buckets/counts are built as temporary arrays during particle update.

Defense:

- These are scratch values whose lifetime is one frame or less.
- The frame loop performs allocator reset (`free_all(context.temp_allocator)`),
  so this memory is reclaimed deterministically each frame.
- This avoids polluting long-lived state with transient buffers while keeping frame code straightforward.

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
- If data is transient and frame-local, temp allocator usage is acceptable and expected.
- If data belongs to scripting/runtime orchestration (Julia, asset reload, GIF
  session work), event-driven allocation is acceptable by design.

---

## Build and Packaging Model

- `make.sh` (Linux/macOS) and `make.ps1` (Windows) build Odin executable and
  package runtime assets into `bin/assets.pkg`.
- Packaged assets include:
  - `src/julia/**` scripts
  - `src/view/shaders/**`
  - `assets/**`
  - `manifest.txt`
- At startup, app unpacks `assets.pkg` to a writable cache directory and resolves runtime paths from there.

---

## Practical Contributor Guide

### If You Need To

- **Change render loop / timing / frame orchestration**:
  - Start in `src/view/view.odin`.
- **Change shape/constraint behavior**:
  - Use `src/kine/constraints.odin`, `src/kine/shapes.odin`, `src/kine/system.odin`.
- **Add a new bridge capability for Julia scripts**:
  - Add Odin export in `src/julia/odin-julia-bridge.odin`.
  - Add matching Julia wrapper in `src/julia/odin-julia-bridge.jl`.
- **Add a new animation/scripted chapter item**:
  - Create Julia script file in the appropriate content folder and register it in that group's initializer.
- **Adjust UI behavior and animation tree interactions**:
  - Use `src/view/ui.odin`.

### Typical New Animation Workflow

1. Add Julia animation module/file in `src/julia/...`.
1. Implement `get_view_text`, `initialize`, `loop`, `clean`.
1. Register it via `add_child_animation_interface` in the relevant group init script.
1. If bridge functionality is missing, add symmetric Odin export + Julia wrapper.

---

## Key Architecture Takeaways

- The app is **host-driven**: Odin controls lifecycle, simulation pacing, rendering, and core state.
- Julia is **content-driven**: scripts define what animation behavior runs and what geometry/tools are manipulated.
- The bridge is the contract: keep Odin exports and Julia wrappers aligned.
- Assets are packaged and loaded at runtime, enabling script/content iteration without redesigning host architecture.
