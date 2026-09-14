# UI System

## Table Of Contents

1. [Purpose And Scope](#purpose-and-scope)
1. [System Model](#system-model)
1. [Source Map](#source-map)
1. [Ownership Model](#ownership-model)
1. [Frame Lifecycle](#frame-lifecycle)
1. [Startup Assembly](#startup-assembly)
1. [Window And Layout](#window-and-layout)
1. [Panel Composition](#panel-composition)
1. [UI Runtime State](#ui-runtime-state)
1. [Input Model](#input-model)
1. [Press Ownership](#press-ownership)
1. [Widgets](#widgets)
1. [Scrolling](#scrolling)
1. [Presentation Panel](#presentation-panel)
1. [Terminal Panel](#terminal-panel)
1. [Accordion And Animation Controls](#accordion-and-animation-controls)
1. [Fonts And Text Drawing](#fonts-and-text-drawing)
1. [GIF Capture Coordination](#gif-capture-coordination)
1. [Allocation And Lifetime](#allocation-and-lifetime)
1. [Verification](#verification)
1. [Current Limitations](#current-limitations)
1. [Change Guide](#change-guide)
1. [Correctness Invariants](#correctness-invariants)

## Purpose And Scope

Euclid's UI is the display-thread-owned layer that turns application state into one
window containing the geometry world, presentation or Terminal content, animation
catalogue, settings, GIF controls, and shared panel chrome.

This guide documents the current implementation. It focuses on:

- frame ordering and display-thread ownership;
- fixed-window panel layout and splitter behavior;
- input snapshots, widget interaction, and shared press capture;
- presentation, Terminal, accordion, animation controls, settings, and GIF composition;
- scrolling, text selection, copy affordances, fonts, and drawing;
- current verification surfaces and architectural limitations.

It deliberately does not describe shape construction, constraint solving, particle
simulation, animation authoring, Dynview parsing, or terminal emulation in depth. Those
subsystems have their own owners and documentation. The UI consumes their prepared or
committed state and controls where it is visible.

Related guides are:

- [ArchitectureSummary.md](ArchitectureSummary.md) for process-wide ownership and
  execution roles;
- [TerminalArchitecture.md](TerminalArchitecture.md) for terminal protocols, sessions,
  grids, graphics, and Julia policy;
- [AnimationsStyle.md](AnimationsStyle.md) for visual and motion conventions;
- [LaTeXSupport.md](LaTeXSupport.md) for authored Dynview document and math syntax;
- [ToolRendering.md](ToolRendering.md) for pen and compass rendering details.

## System Model

The UI is not a separate thread or an independent retained widget runtime. It is a set
of Odin packages called by the display loop. The same display thread owns layout,
interaction state, visible application state, Raylib resources, and draw submission.

```mermaid
flowchart LR
    Input[Device input snapshot]
    State[Euclid application state]
    Layout[Geometry and static interaction]
    Services[Presentation and Terminal services]
    Prepare[Worker caches and layout interaction]
    Panels[Panel and widget code]
    Draw[Raylib drawing]

    Input --> Layout
    State --> Layout
    Layout --> Services
    Services --> Prepare
    State --> Panels
    Input --> Panels
    Prepare --> Panels
    Panels --> Draw
```

The UI combines immediate geometry and drawing with persistent interaction fields in
`Euclid_Ui_Runtime_State`. Update procedures compute widget rectangles, consume routed
frame copies, and commit display-owned state before `BeginDrawing`. Draw procedures
consume fixed frame-local preparation records and committed state.

This is a hybrid model:

| Property | Current behavior |
| --- | --- |
| Widget geometry | Recomputed from panel rectangles each frame. |
| Widget state | Stored in application, subsystem, or UI runtime state. |
| Input | One borrowed raw snapshot filtered into per-surface value copies. |
| Drawing | Immediate Raylib calls on the display thread. |
| Layout caches | Dynview, font, shape, and Terminal owners retain derived state. |
| Cross-thread work | Workers prepare finite results; the display commits and draws. |

## Source Map

| Area | Primary files | Responsibility |
| --- | --- | --- |
| Window and frame loop | `src/view/view.odin` | Window lifecycle, frame order, world and panel drawing. |
| Startup presentation | `src/view/loading.odin`, `src/view/startup_outline.odin` | Loading milestones, fixed UI silhouette, warning, and ready handoff. |
| Shared UI entry point | `src/view/ui/ui.odin` | Constants, frame preparation, panel draw dispatch. |
| Region layout | `src/view/ui/layout.odin` | Clamp and derive all panel rectangles. |
| Splitters | `src/view/ui/splitter.odin` | Resize hit testing, capture, drag, fade, and cursor. |
| Containers | `src/view/ui/container.odin` | Clamped fill, border, and inner geometry. |
| Scrolling | `src/view/ui/scroll.odin` | Viewport, wheel, thumb geometry, capture, scissor, and draw. |
| Presentation panel | `src/view/ui/text_panel.odin` | Dynview/fallback dispatch, scrolling, selection, copy targets. |
| Dynview UI | `src/view/ui/dynview/` | Layout drawing, selection geometry, and styled presentation. |
| Terminal facade | `src/view/ui/terminal.odin` | Terminal panel layout, scroll container, and draw calls. |
| Terminal service | `src/view/terminal_service.odin` | Terminal lifecycle, input update, Julia messages, and links. |
| Terminal rendering | `src/view/terminal/` | Grid, prompt, selection, links, attachments, and overlays. |
| Accordion | `src/view/ui/accordion.odin` | Section layout, header interaction, and one-expanded-section policy. |
| Accordion children | `src/view/ui/tree_panel.odin` | Accordion orchestration plus catalogue traversal, reveal, and scrolling. |
| Animation controls | `src/view/ui/animation_controls.odin` | World-anchored refresh and pause/play interaction and drawing. |
| Utility panels | `settings_panel.odin`, `gif_panel.odin` | Runtime settings and GIF controls. |
| Basic widgets | `*button.odin`, `checkbox.odin`, `sliders.odin` | Shared press/release and visuals. |
| Copy affordances | `src/view/core/copy_interaction.odin` | Copy icon interaction and clipboard action. |
| Input boundary | `src/view/input/` | Device polling, event storage, hotkeys, and Terminal encoding. |
| Font service | `src/view/font/` | Face preparation, publication, lookup, and shaping identity. |
| Shared state | `src/view/model/model.odin` | UI regions, press owner, interaction, selection, and GIF state. |

## Ownership Model

The display thread is the sole writer of visible UI state and the only execution role
allowed to call Raylib drawing and resource APIs.

| Concern | Owner | Boundary |
| --- | --- | --- |
| Window and Raylib resources | Display thread | Initialized and destroyed by the view lifecycle. |
| Panel geometry | `Euclid_Ui_Runtime_State` | Computed before drawing each frame. |
| Widget press state | UI runtime or owning subsystem | Mutated only by display-thread UI calls. |
| Device frame storage | `input.Input_Runtime` | Borrowed until the next input poll. |
| Animation catalogue | Julia interface mirrored in Odin | Tree reads and requests changes; it does not run Julia. |
| Dynview content | Dynview system and compile cache | Prepared before display consumption. |
| Terminal cells and selection | Display-owned `Terminal_State` | Children send bounded messages or bytes. |
| Font atlases | Display-owned font cache | CPU preparation may run on workers; publication is display-owned. |
| World render packets | Shape and simulation owners | UI supplies viewport geometry and invokes drawing. |
| GIF state and capture | Display-owned GIF coordinator | UI requests actions; capture commits after presentation. |

The UI may call application services, such as animation reset or GIF capture, but it
does not bypass their ownership. An animation-control or accordion-child click sets
display-owned request state; the normal frame and service paths perform the operation.

## Frame Lifecycle

`run_window_frame` defines the authoritative ordering:

```mermaid
sequenceDiagram
    participant F as Font and Julia services
    participant I as Input
    participant U as UI preparation
    participant T as Terminal service
    participant S as Simulation and workers
    participant D as Drawing
    participant E as Evidence and capture

    F->>F: Publish available font and presentation results
    I->>I: Poll one Input_Frame
    I->>U: Raw frame snapshot
    U->>U: Prepare geometry and snapshot pointer capture
    U->>U: Resolve static focus, hover, pointer, and wheel targets
    U->>U: Update animation controls, accordion headers, and active child
    U->>T: Raw frame, router result, and prepared panel geometry
    T->>T: Refine Terminal scrollbar routing and update sessions
    T->>S: Continue fixed-step and frame preparation
    S->>U: Joined Dynview layout and copy targets
    U->>U: Update presentation scroll, copy, and selection
    U->>D: Prepared interaction and draw-ready state
    D->>D: Draw world, panels, splitters, overlays
    D->>E: Present, scenario capture, GIF frame, evidence
    E->>E: Reset the temporary allocator
```

The concrete high-level order is:

1. service the font cache and synchronize math and prose shaping generations;
1. publish available Julia presentation state;
1. service presentation parsing and publication;
1. poll one device-independent `Input_Frame`;
1. call `ui.prepare_ui_geometry`;
1. call `ui.prepare_ui_static_interaction`;
1. call `ui.prepare_ui_controls` for animation controls, accordion headers, and the
    active Library, Save GIF, or Settings child;
1. update the selected Terminal and active shell session;
1. advance fixed-step simulation;
1. run and join frame preparation that depends on the new UI geometry;
1. call `ui.prepare_ui_layout_interaction` for presentation interaction;
1. update audio and pre-presentation scenarios;
1. call `BeginDrawing`, draw the frame, and call `EndDrawing`;
1. service post-presentation scenarios and GIF capture;
1. publish frame evidence and reset `context.temp_allocator`.

Three ordering details are especially important:

- splitter changes happen before `Ui_Regions` and Dynview panel tracking;
- capture identity from frame start survives splitter and widget release updates;
- static routing and geometry-known controls precede Terminal processing;
- Terminal scrollbar geometry refines the static panel target before input consumption;
- presentation scrolling, copy targets, and selection update after authoritative
    Dynview layout exists and before drawing begins;
- drawing consumes prepared records and does not commit UI interaction or actions.

The second detail is a current limitation discussed below.

## Startup Assembly

The display thread opens the Raylib window before packaged assets, Julia content, and
normal UI resources are ready. During that interval, `loading.odin` pumps window events
and draws a dependency-free representation of the eventual interface. It does not enter
the normal frame lifecycle or access application-owned widget state.

`startup_outline.odin` builds one fixed-capacity sequence of line segments from the
same pure layout helpers used by the real baseline UI. The sequence traces the world,
presentation, accordion, accordion-header, and animation-control boundaries. It stores
no dynamic memory and requires no font cache, texture, Julia state, or initialized
presentation runtime.

The assembling outline is the normal startup progress indicator; there is no separate
spinner or progress bar. Its reveal target follows the coarse startup milestones:

| Target | Startup phase |
| ---: | --- |
| 15% | Packaged assets |
| 35% | Julia runtime initialization |
| 65% | Julia content initialization |
| 85% | Fonts and graphics |
| 100% | All runtime owners ready |

The outline advances at a stable rate but never beyond the current milestone. These
targets communicate phase progress rather than estimated remaining time. Once startup
is actually ready, a bounded 240-millisecond ease-out completes the remaining trace and
the normal frame loop replaces it with the real UI.

If a Julia startup request exceeds the unresponsive threshold, the default Raylib font
draws `Julia is not responding` over the partial outline. This warning remains available
before application fonts exist and is the only ordinary startup text.

## Window And Layout

### Fixed Window

The current window is initialized at `1280x720`. `open_window` enables high-DPI output
and optional multisampling and VSync, but it does not enable Raylib's resizable-window
flag. UI layout therefore targets one logical window size rather than querying a
changing client extent.

The baseline starts with:

| Constant | Value | Meaning |
| --- | ---: | --- |
| `WINDOW_WIDTH` | 1280 | Logical window width. |
| `WINDOW_HEIGHT` | 720 | Logical window height. |
| `VIEW_WIDTH` | 900 | Initial vertical split position. |
| `VIEW_HEIGHT` | 500 | Initial horizontal split position. |
| `WORLD_MIN_WIDTH` | 320 | Minimum world-side width. |
| `WORLD_MIN_HEIGHT` | 240 | Minimum world-side height. |
| `RIGHT_PANEL_MIN_WIDTH` | 240 | Minimum right-side width. |
| `BOTTOM_PANEL_MIN_HEIGHT` | 140 | Minimum presentation height. |

### Regions

`compute_ui_regions` clamps the vertical and horizontal split positions and fills one
`Ui_Regions` value:

```text
+------------------------------+-------------------+
|                              |                   |
|          world_rect          |  accordion_rect   |
|                              |                   |
+------------------------------+                   |
|          text_rect           |                   |
|   Dynview or Terminal view   |                   |
+------------------------------+-------------------+
```

`accordion_rect` is the complete right-side region. The accordion derives three
full-width headers and one flexible content rectangle inside it; only the active child
receives that content rectangle. `terminal_rect` is a clamped inset of the text region.
Panel drawing applies additional container borders and padding where required.

`validate_ui_regions` rejects negative dimensions. The frame falls back to baseline
split positions if validation fails.

### Splitters

The vertical splitter spans the window height. The horizontal splitter spans only the
left side up to the vertical split. Each has:

- a 3-pixel visible line;
- an 8-pixel centered hit rectangle;
- a 0.15-second hover fade;
- a stable press ID;
- clamped drag behavior preserving panel minimums.

At the splitter intersection, the nearest axis wins and an exact tie prefers the
vertical splitter. The active or hovered splitter selects the matching resize cursor.

GIF capture phases `Armed`, `Recording`, and `Finalizing` lock both splitters. Entering
one of those phases releases an existing splitter capture and removes hover feedback so
captured frames retain stable panel geometry.

Debug/test scenarios may request both splitter positions atomically with
`{"set_splitters":{"vertical":X,"horizontal":Y}}`. The display queues the request
after the current frame is prepared, then applies the same pane-minimum clamps before
the next frame computes `Ui_Regions`. A pending or active GIF capture rejects the
request, preserving capture geometry.

## Panel Composition

The top-level draw order is:

```mermaid
flowchart TD
    Clear[Clear window background]
    World[Draw geometry world]
    Presentation[Draw text or Terminal panel]
    Controls[Draw animation controls over world]
    Accordion[Draw accordion and active child]
    Splitters[Draw splitter feedback and cursor]
    Overlay[Draw optional FPS overlay]

    Clear --> World --> Presentation --> Controls --> Accordion --> Splitters --> Overlay
```

The UI owns panel composition, not the internal world rendering order. `draw_world`
invokes the drawing surface, prepared geometry, tools, shadows, and particle layers.
Their data models and detailed layering belong to the shape, tool, and animation
documentation.

### Standard Containers

`container_geometry` clamps dimensions and returns outer and inner rectangles without
drawing. `draw_container_with_border` uses the same geometry to issue fill and border
commands. The shared variants are:

| Variant | Use |
| --- | --- |
| `Dark_Red` | Major panel background matching the application background. |
| `Grey` | Inset component and content regions. |

This geometry/drawing split is useful where callers need a content rectangle before
they issue their own rendering.

## UI Runtime State

`Euclid_Ui_Runtime_State` is embedded in `Euclid_General_State` and persists for the
window session.

| State group | Representative fields |
| --- | --- |
| Layout | `current_layout_mode`, `ui_regions`, split positions and hover fades |
| Scroll | Tree and presentation offsets, drag flags, and drag offsets |
| Interaction | Shared `ui_press_owner`, Dynview selection |
| Accordion | `active_accordion_section` selects Library, Save GIF, or Settings |
| Settings | FPS, simulation pause, SIMD, GPU dust, and slider state |
| FPS reporting | Fixed rolling bucket arrays, cursor, elapsed time, and average |
| GIF capture | Request flag, phase, frame counters, options, status, and last path |

Runtime initialization sets the split positions to `VIEW_WIDTH` and `VIEW_HEIGHT` and
the GIF downsample factor to two. Other zero-valued fields use their enum or scalar
defaults unless startup settings override them.

The runtime stores interaction state that must survive frames, but it does not own
Terminal grids, Dynview documents, fonts, animation catalogue nodes, shapes, or
particles. Those remain in their subsystem owners.

## Input Model

`input.input_poll_frame` drains Raylib input once and returns one device-independent
`Input_Frame`. Its event slice borrows fixed storage in `Input_Runtime` until the next
frame begins.

The snapshot contains:

| Input class | Representation |
| --- | --- |
| Keyboard and text | Ordered `Input_Event` slice with modifier and correlation data. |
| Window activation | Current focus and one-frame transition flag. |
| Pointer position | Screen-space `x` and `y`, plus a real-movement flag. |
| Pointer buttons | Pressed and released edges plus current down levels. |
| Pointer modifiers | Control, Shift, Alt, and Super snapshot. |
| Wheel | Signed vertical delta. |
| Time | Monotonic sample time for UI transitions. |
| Terminal coordinates | UI-resolved cell and pixel positions added to a frame copy. |

UI modules receive the frame by value and commonly use helpers in `ui.odin` for the
left-button aliases and Raylib-compatible pointer position.

`input_frame_filter_pointer` creates routed value copies without copying the borrowed
event storage. Its fixed mask independently controls screen position, motion, press and
release edges, button levels, wheel, resolved Terminal positions, and Terminal
ownership. Callers can therefore suppress a new press while preserving the release and
coordinates required by an already-admitted capture.

The input package also owns concerns that are not UI focus:

- device-to-portable key mapping;
- physical/text event correlation;
- synthetic scenario events;
- registered semantic hotkeys;
- terminal byte encoding and retained byte ownership;
- terminal protocol mouse capture and release retry.

These remain input-layer responsibilities even when UI code supplies hit-test facts.

## Press Ownership

The UI has one shared `Ui_Press_Owner_State`:

```odin
Ui_Press_Owner_State :: struct {
    active: bool,
    kind: Ui_Press_Owner_Kind,
    id: int,
}
```

Supported owner kinds currently include list items, icon and text buttons, checkboxes,
sliders, scrollbars, splitters, Dynview selection, and copy icons.

The common lifecycle is:

1. hit test the widget and its interaction-space rectangle;
1. on a left press, capture only when no owner is active;
1. while captured, continue the widget's pressed or drag behavior;
1. on release, decide whether the action completes;
1. clear the shared owner.

The identity pairs a kind with a caller-supplied integer ID. Static controls use fixed
IDs. Tree rows derive a stable per-frame ID from the animation node pointer. The shared
state serializes ordinary UI press transactions so overlapping widgets do not both
capture the same press.

Press ownership is distinct from logical focus. Logical focus persists after release
and currently selects Terminal, Presentation, or Accordion as the ordinary keyboard
target.
The interaction router classifies the legacy owner into a typed frame-local capture
target. It snapshots that identity before interaction updates so release-frame routing
cannot fall through to a newly hovered panel. Terminal child mouse capture remains an
independent protocol mechanism.

## Interaction Routing

`ui_route_interaction_frame` is the bounded display-owned router. It consumes the raw
frame, current regions, visible presentation kind, persistent focus, and the singleton
capture snapshot. It publishes one `Ui_Interaction_Frame` containing:

- logical and effective keyboard focus;
- topmost hover, pointer capture, pointer target, and wheel target identities;
- narrow keyboard, pointer, and wheel eligibility for Terminal, Presentation, and
    Accordion;
- the effective Terminal focus transition used by rendering and child protocols.

Targets carry an interaction class, focus surface, and stable ID. Static resolution
places splitters above Terminal, Presentation, Accordion, and world content. Animation
controls are explicit `.Control` targets above the world, so their hit rectangles
consume pointer input without allowing the same edge to reach world interaction.
Existing capture outranks current hover. A wheel delta receives the hovered target only
when no pointer capture is active, so it cannot follow a drag into another panel.

Terminal preparation refines its coarse content target once scrollbar geometry exists.
The complete visible track then replaces content for hover, pointer, and eligible wheel
routing. Presentation preparation similarly resolves scrolling, copy targets, and
selection after Dynview layout completes. The router uses only value state, fixed enums,
and borrowed frame copies; it allocates no region or target lists.

## Widgets

### Buttons

Icon and text buttons use the shared capture pattern. They distinguish hover, active
press, enabled state, toggle state, and completed click. A click completes only after a
captured press reaches release according to the widget's hit policy.

Each basic widget exposes an update procedure and a prepared-result draw procedure.
Panel preparation commits actions and values; drawing only selects visual state from
the prepared result.

The world animation overlay uses icon buttons for:

| ID | Action |
| ---: | --- |
| 2101 | Request animation refresh. |
| 2102 | Toggle simulation pause and play. |

The controls are anchored to the lower-left edge of the current `world_rect`, so they
follow splitter changes. They are hidden while GIF capture is recording. Refresh also
resumes simulation, requests the normal animation-reset path, and cancels an in-flight
capture when refreshing from a paused capture.

Accordion headers are full-width text buttons with IDs 2201 through 2203. Clicking a
header assigns `active_accordion_section`; selecting the already expanded header leaves
it expanded because exactly one section is always active.

### Checkboxes

Checkboxes return a result containing the output checked state and whether a toggle
completed. The settings panel uses them for:

- FPS display;
- FPS limiting;
- drawing sound;
- SIMD projection when available;
- GPU dust instancing when the active OpenGL version supports it.

Unavailable optional features are forced false and shown with an unavailable label.

### Integer Sliders

Integer sliders support wheel steps, press capture, drag updates, clamping, and a
numeric value label. The settings panel controls maximum dust particles. The GIF panel
controls downsampling and frame step, each in the range one through four.

### List Items And Expanders

Animation rows use a list-item press transaction for selection. Expandable nodes also
draw and handle an expander icon. Selection clears the previous selected flag, updates
`selected_animation`, records a pending reveal identity, and requests the normal
animation transition path.

The tree update and draw walks are recursive but bounded by the registered animation
count. The update walk resolves one hovered row and expander identity without allocating
a row list. The draw walk skips offscreen rows while preserving content height.

## Scrolling

`scroll.odin` provides one vertical scroll-container implementation shared by:

| Container | ID | Persistent offset |
| --- | ---: | --- |
| Presentation panel | 1001 | `view_text_scroll_y` or Terminal-owned offset |
| Terminal panel | 1002 | Terminal scroll offset committed through its facade |
| Tree catalogue | 1003 | `tree_scroll_y` |

Presentation, Terminal, and Tree all use the pre-render update path:

```mermaid
flowchart LR
    Geometry[Build geometry]
    Wheel[Apply hovered wheel]
    Capture[Resolve capture and drag]
    Commit[Commit scroll offset]
    Route[Route content input]
    Service[Update Terminal content]
    Scissor[Begin draw-only scissor]
    Draw[Draw content and scrollbar]

    Geometry --> Wheel --> Capture --> Commit --> Route --> Service --> Scissor --> Draw
```

The view rectangle, interaction-space rectangle, and optional scroll offset keep hit
testing aligned with nested or translated content. Wheel movement applies only while
the pointer is inside the active view. Scroll positions clamp to:

$$
0 \leq y_{scroll} \leq \max(0, h_{content} - h_{view})
$$

The scrollbar is eight pixels wide and its thumb has a minimum height of 24 pixels.
Thumb capture uses the shared press owner and persists while the button remains down.

The complete visible track is reserved above Terminal content. Track wheel input always
scrolls locally. In content, negotiated SGR mouse mode receives wheel input unless Shift
selects local scrollback. Thumb capture persists outside the track until release.
Prepared draw helpers begin and end Raylib scissoring and draw the scrollbar without
mutating scroll state.

Debug/test scenarios may request non-Terminal presentation scrolling with
`{"set_view_scroll":{"y":Y}}`. The request clears presentation scrollbar capture,
clamps negative values to zero, and yields a frame. The next presentation preparation
computes the content-dependent maximum and clamps the effective offset before drawing;
Terminal scrollback and tree scrolling remain separately owned.

## Presentation Panel

The bottom-left panel shows either the selected animation presentation or the Terminal.
`draw_view_text_panel` decides which path is active.

### Dynview Or Plain Text

For an ordinary animation, the post-layout interaction stage:

1. obtains the current immutable presentation snapshot;
1. queries authoritative Dynview content height or the wrapped-text fallback height;
1. updates and commits the shared presentation scroll container;
1. refreshes bounded copy targets from authoritative layout;
1. updates copy capture, clipboard publication, and visual transitions;
1. reconciles and updates selection state;
1. publishes a fixed preparation record for drawing.

Drawing then clips with the prepared scroll result and renders selection, compiled or
fallback content, copy affordances, and the scrollbar without changing interaction.

Dynview remains responsible for semantic content, shaping, line breaking, math layout,
and copy-target generation. The UI supplies panel bounds, scroll offset, style metrics,
selection input, clipping, and final draw placement.

### Selection

Dynview selection supports semantic documents, atomic source, and wrapped plain text.
The selection stores mode, revision, anchor, head, active state, and drag state.

A left press inside selectable content captures `.Dynview_Selection` unless another
widget owns the press or a copy icon occupies the point. Dragging updates the head, and
release commits an active selection when anchor and head differ. `Ctrl+A` selects the
complete logical content and `Ctrl+C` writes selected source to the clipboard only while
Presentation has effective keyboard focus.

### Copy Affordances

Dynview compilation publishes bounded copy hit targets. The copy interaction runtime
tracks one hovered block, one pressed block, and short linger feedback. On a matching
release it publishes that block's canonical payload to the clipboard.

Copy visual state remains in `Dynview_System`, while `.Copy_Icon` in the shared press
owner retains the pointer transaction through release. Copy updates run before
selection, so an admitted icon press has priority over selectable content.

## Terminal Panel

When the selected animation node has kind `Terminal`, the presentation panel delegates
to the Terminal facade. The complete Terminal architecture is documented in
[TerminalArchitecture.md](TerminalArchitecture.md); this section describes only its UI
integration.

### Service Update

Before drawing, `terminal_service_update`:

1. confirms the committed Terminal animation is selected;
1. initializes generation-scoped Terminal state when needed;
1. requests and waits for the matching Julia session;
1. derives the same content panel used by later drawing;
1. resolves font, Terminal geometry, layout, and mouse coordinates;
1. resolves scrollbar capture and wheel ownership, then commits local scrolling;
1. routes a content frame that excludes scrollbar or foreign UI-owned input while
    retaining fields required by established local or child capture;
1. prepares hyperlink hover from the committed scroll position;
1. consumes the UI-prepared effective focus and transition;
1. updates local editor, selection, completion, and link behavior;
1. applies submissions and completion requests;
1. updates the active native shell session and terminal graphics;
1. publishes clipboard and hyperlink actions through display-owned adapters.

Terminal initialization and input routing are service work, not draw work. Julia never
receives a pointer to the visible Terminal state.

### Drawing

`ui.terminal_draw`:

1. resolves a font capability and draw theme;
1. consumes the prepared layout, scroll geometry, and hyperlink hover;
1. begins draw-only Terminal scissoring;
1. converts the prepared scroll offset into a content origin;
1. draws cells, prompt, cursor, selection, links, and raster attachments;
1. ends scissoring and draws the prepared scrollbar;
1. draws overlays outside content clipping.

Terminal prompt and output cursor styles consume effective Terminal focus. Focused
cursors are filled; unfocused cursors are outlined.

### Keyboard Focus

The display-owned `Ui_Interaction_State` retains logical focus independently of OS
window activation. Terminal entry focuses Terminal once. A primary press on Terminal,
Presentation, or Tree moves logical focus to that surface; world, background, and
splitter presses clear it. Leaving Terminal clears a Terminal focus target.

`ui_route_interaction_frame` derives effective focus during static interaction routing:

```text
terminal_focused = window_focused && terminal_present && logical_focus == Terminal
```

OS deactivation therefore emits an effective focus-out without discarding logical
focus. Reactivation restores effective Terminal focus when the Terminal remains the
logical target. Local editing, clipboard chords, child keyboard bytes, DECSET 1004
reports, and cursor presentation all consume this one result. The raw polled
`Input_Frame` remains unchanged.

### Input Boundaries

The Terminal UI distinguishes several existing facts:

- pointer inside accepted grid bounds;
- one-based cell and content-pixel coordinates;
- Shift-based local ownership for selection;
- interpreter-negotiated child mouse modes;
- owner-bound retained bytes for Julia evaluation or native sessions.

These facts are intentionally not all the same concept. Current orchestration has one
application-wide interaction result plus Terminal pointer filtering. One routed content
frame feeds both local Terminal policy and native child byte encoding. A scrollbar or
foreign UI capture removes fresh Terminal presses, levels, motion, and wheel. Existing
local selection or hyperlink capture retains its real release point, while existing child
protocol capture retains resolved motion and release data outside content.

## Accordion And Animation Controls

### Landscape Accordion

The current landscape layout assigns the complete right-side region to an
orientation-neutral accordion. Its ordered sections are Library, Save GIF, and
Settings. Every section keeps a header visible, and the active section receives all
remaining height between the headers. The enum-backed `active_accordion_section` is the
single source of truth, so contradictory combinations of visible utility panels cannot
occur.

The accordion component owns header geometry, header interaction, labels, disclosure
icons, and the one-expanded-section invariant. `tree_panel.odin` orchestrates the
active child because the Library was the original right-side owner; the Library, GIF,
and Settings implementations retain their existing domain behavior. The abstraction
does not encode right-side or landscape placement, allowing another layout mode to
place the same component elsewhere.

### Animation Controls

Refresh and pause/play are not accordion sections. They are a compact overlay inside
the lower-left corner of the current world viewport. Preparation resolves and commits
their actions before simulation, while drawing consumes the prepared button results.
Their explicit control targets outrank ordinary world interaction.

### Tree Catalogue

When Library is active, its accordion content counts visible rows, applies pending
reveal state, updates scrolling, and walks visible roots to resolve hover, selection,
and expansion. Expansion recounts topology and reclamps scrolling in the same update.
Rendering repeats the bounded walk only to issue draw calls.

The reveal mechanism stores a stable animation UUID rather than a pointer. On the next
eligible tree frame it resolves the current node and minimally adjusts scroll so the row
becomes visible. This survives catalogue replacement better than retaining row geometry.

### Settings Panel

When Settings is active, its controls occupy the accordion content region. It contains:

- a maximum-dust-particle slider;
- current low, middle, and high particle render counts;
- the number of Julia animation entries;
- FPS display and limit toggles;
- drawing sound;
- optional SIMD projection;
- optional GPU dust instancing.

The UI changes display-owned settings directly. Where a setting has an external effect,
such as target FPS, the control also calls the appropriate display-thread Raylib API.

### GIF Panel

When Save GIF is active, its controls occupy the accordion content region. The panel
contains downsample and frame step sliders, a Save/Cancel button, current phase, status
notes, and the final path after success.

The button sets `save_gif_requested`; the owning GIF update path interprets that request
and advances the phase. Controls are disabled where recording or finalization policy
requires stable state.

## Fonts And Text Drawing

The UI uses the display-owned font cache rather than loading fonts per widget. Font CPU
preparation may execute on workers, but the display thread publishes Raylib resources
and resolves the active face generation.

Common UI text uses JuliaMono through either:

- a borrowed regular Raylib font;
- a `Font_Resolver` for styled or fallback runs;
- `view_core.ui_text_shaped` for shaped labels;
- terminal-specific fixed-column shaping for grid content;
- NewCM and OpenType MATH data through Dynview for mathematical presentation.

`prepare_ui_frame` tracks panel dimensions, prose font metrics, and style revision with
Dynview. Font generation changes invalidate derived presentation layout so worker
preparation can rebuild it before drawing.

UI code should resolve fonts through the cache and should not retain Raylib font or
texture ownership in widget state.

## GIF Capture Coordination

The GIF panel is only the control surface. Capture itself is coordinated by the view and
GIF runtime:

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Armed: Save request
    Armed --> Recording: Capture begins
    Armed --> Idle: Cancel request
    Recording --> Finalizing: Stop condition
    Recording --> Error: Frame submission fails
    Finalizing --> Saved: Encoder completes
    Finalizing --> Error: Encoder fails
    Saved --> Idle: New request lifecycle
    Error --> Idle: New request lifecycle
```

While capture requires stable framing, splitter interaction is locked. Frame submission
occurs after the presented frame and is skipped while simulation is paused. Status and
path strings live in bounded arrays in UI runtime state.

## Allocation And Lifetime

The UI runtime itself is embedded in the display-owned application state and does not
allocate per widget. Most widget parameter and result structs are frame-local values.

| Data | Lifetime and storage |
| --- | --- |
| `Euclid_Ui_Runtime_State` | Window session, embedded in application state. |
| `Input_Runtime` event storage | Display lifetime; borrowed by one `Input_Frame`. |
| `Input_Frame` scalar fields | Frame-local values. |
| UI rectangles and widget results | Stack or frame-local values. |
| Tree nodes | Julia interface lifecycle, read and selected by display UI. |
| Dynview selection | Persistent UI runtime state, reconciled to content revision. |
| Terminal selection and scrolling | Terminal generation state. |
| Font resources | Font-cache lifetime, published and destroyed on display thread. |
| Temporary formatted labels | `context.temp_allocator`, reset after each frame. |

Hot UI paths should not introduce hidden dynamic growth. New persistent interaction
state belongs in a lifetime-matched owner; temporary formatting should use the explicit
temporary allocator already reset at frame completion.

## Verification

### Focused Tests

| Test area | Coverage |
| --- | --- |
| `src/view/startup_outline_test.odin` | Fixed-capacity silhouette geometry and bounded milestone reveal. |
| `src/view/ui/ui_test.odin` | Router priority, focus, capture, wheel ownership, regions, splitters, animation controls, accordion layout, tree layout, and scrolling. |
| `src/view/ui/dynview/selection_test.odin` | Selection modes, hit boundaries, capture, and source extraction. |
| `src/view/core/copy_interaction_test.odin` | Copy target identity, hover, press, release, and animation state. |
| `src/view/input/input_test.odin` | Device-independent events, correlation, hotkeys, Terminal encoding. |
| `src/view/terminal/terminal_test.odin` | Terminal geometry, input, selection, links, cursor, and rendering policy. |
| `src/view/terminal_service_test.odin` | Display service selection and Terminal lifecycle behavior. |
| `src/view/view_test.odin` | View-level state transitions and UI-facing Terminal behavior. |

Run the complete Odin unit suite after UI behavior changes:

```sh
julia tools/make.jl unit odin
```

Build after package or shared-state changes:

```sh
cmake --build --preset default
```

The final repository gate is:

```sh
cmake --build --preset default --target check
```

### Behavioral Evidence

Scenarios exercise UI-visible behavior through production ownership paths. Checked-in
Terminal scenarios select the Terminal animation, wait for correlated state or events,
submit input, capture a presented frame, assert allocation state, and request orderly
shutdown.

Use scenario evidence when correctness depends on frame ordering, Terminal publication,
capture completion, or shutdown. A screenshot alone does not prove scenario success;
the artifact manifest and semantic trace remain authoritative.

## Current Limitations

The current UI is coherent enough for the present application, but several constraints
are important when changing it:

1. Logical keyboard focus exists for Terminal, Presentation, and Accordion, but keyboard
    traversal, modal focus, and control-level focus are not implemented.
1. `Ui_Press_Owner_State` is pointer capture, not focus, and covers one press at a time.
1. Terminal child mouse capture and UI widget capture are independent mechanisms.
1. The window uses fixed logical dimensions and has only the baseline layout mode.
1. Accessibility navigation is not implemented.

The repository root document `staging_uifocus.md` records the completed interaction
migration and the deliberately deferred keyboard traversal and modal-focus work.

## Change Guide

### Adding A Widget

1. Choose an existing widget primitive when its press and visual behavior match.
1. Assign a stable ID within the owning panel.
1. Pass both the widget rectangle and its containing interaction-space rectangle.
1. Use the shared press owner unless the subsystem has a documented specialized capture.
1. Keep persistent state in the owning runtime, not in transient draw parameters.
1. Add focused press, release, disabled, and boundary tests.

### Adding A Panel

1. Add its rectangle to `Ui_Regions` only if it has independent geometry.
1. Derive the rectangle in `compute_ui_regions` and include it in validation.
1. Decide whether it coexists with or replaces existing right/presentation content.
1. For an accordion child, extend `Ui_Accordion_Section`, its label mapping, section
    count, child preparation, child drawing, and focused selection tests together.
1. Keep service work before drawing and Raylib calls on the display thread.
1. Define clipping, scroll, font, and press-ID policy explicitly.
1. Add region and minimum-size tests.

### Changing Layout

1. Update region calculation and splitter constraints together.
1. Preserve non-negative rectangle validation and fallback behavior.
1. Revisit Dynview panel tracking and world viewport fitting.
1. Check Terminal geometry and native session resize propagation.
1. Check GIF capture framing and splitter locking.

### Changing Input Behavior

1. Identify whether the concern is hover, UI capture, Terminal child capture, byte
   ownership, keyboard event claims, or OS window focus.
1. Change the subsystem that owns that concept rather than adding a cross-layer flag.
1. Preserve press/release pairing and correlated physical/text event semantics.
1. Test pointer exit, owner replacement, disabled state, and overlapping hit regions.

### Changing Text Or Fonts

1. Resolve faces through the font cache.
1. Keep shaping generation consistent with the prepared layout being drawn.
1. Invalidate Dynview through its tracking APIs rather than mutating derived caches.
1. Preserve Terminal fixed-column geometry and fallback behavior.

## Correctness Invariants

The current UI depends on these invariants:

1. Only the display thread mutates visible UI state or calls Raylib drawing APIs.
1. Device input is polled once per frame and its event slice is borrowed only until the
   next poll.
1. Splitter updates precede region computation, viewport fitting, and Dynview tracking.
1. Every stored UI rectangle has non-negative dimensions before use.
1. At most one shared UI press owner is active at a time.
1. Scroll offsets remain clamped to the current content and viewport extents.
1. Tree traversal is bounded by registered animation count.
1. Exactly one accordion section is expanded, and only that child receives content
    interaction.
1. Animation controls are anchored to `world_rect`, outrank world input, and are absent
    while GIF recording is active.
1. Presentation selection is reconciled when content mode or revision changes.
1. Every pointer edge and wheel delta reaches at most one routed top-level surface.
1. Control, accordion, presentation, copy, and Terminal interaction commits before
    drawing.
1. Repeating drawing for one prepared frame cannot duplicate a UI action.
1. Terminal state and messages are accepted only for the matching animation generation.
1. Worker-prepared state commits before the display consumes it.
1. Font and texture resources are published and destroyed by the display thread.
1. Splitters cannot change capture framing during armed, recording, or finalizing GIF
   phases.
1. Temporary frame allocations are released after presentation and evidence handling.
1. Startup drawing remains allocation-free and independent of resources that are still
    loading, and its reveal never exceeds the completed phase milestone.
