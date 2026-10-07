# Accessibility

## Status and Product Claim

Last consolidated: 2026-09-30.

Euclid provides a bounded native accessibility projection for its application shell and
sidebar on Linux, macOS, and Windows through AccessKit C 0.23.1. The supported surface
is the ordinary controls, Library Search, Library Tree, and content-free context-menu
entry points described in this guide.
All three platforms consume the same semantic publication, identity, validation, and
display-thread action model. Their native adapters differ in some observable states and
operable actions, so this is a version-qualified cross-platform implementation, not a
claim of identical native API behavior.

Euclid does **not** currently claim whole-application accessibility. In particular:

- Dynview, including mathematical and document content, is excluded.
- Terminal content, input, history, and live output are excluded.
- The drawing surface and animation geometry are excluded.
- Exact screen-reader speech, announcement timing, and navigation parity are not
  guaranteed.

The current defensible product claim is:

> Euclid exposes its application shell and sidebar controls, Search, and Tree through
> native accessibility APIs on Linux, macOS, and Windows, subject to the platform and
> AccessKit limitations recorded here. Dynview, Terminal, and drawing content are not
> exposed.

In particular, AccessKit is simultaneously great and disappointing across the different
platforms here. A strong start is provided, but a lot of work is needed, some of it
with serious question to AccessKit, forking it, and so on. A defensible start was
initiated here, such that we can proceed. This is mostly exasperated details about that
simultaneous success and failure leading to the current state.

## Scope

### Included Surface

The shared projection supports:

- a synthetic application root and ordered visible hierarchy;
- buttons, including Restart and Pause/Resume;
- checkboxes, including Display FPS;
- numeric sliders and splitters;
- accordion headers and their currently expanded panels;
- Save GIF controls and bounded status text;
- Library Search as editable text with placeholder, caret, and selection facts;
- the Library Tree and TreeItems, including levels, set position, active descendant,
  selection, filtering, expansion facts, and identity retirement;
- Search-to-Tree and accordion-to-panel control relations;
- named Presentation and Terminal panes with Focus and Show Context Menu actions,
  plus their transient Menu and MenuItem children;
- logical focus, host-window focus, clipped bounds, display scale, enabled, checked,
  selected, expanded, and busy facts where the native adapter exposes them;
- activation, toggle, increment, decrement, range mutation, text replacement, text
  selection, Tree selection, expansion/collapse, and scrolling where the native adapter
  dispatches the corresponding operation; and
- clean provider startup, repeated sessions, stale-target rejection, and teardown.

Collapsed accordion content is intentionally absent from the native tree. Euclid starts
with Library active. Settings or Save GIF controls become discoverable only after their
accordion is expanded and a native client refreshes its view if necessary.

### Explicitly Excluded: Dynview

Dynview document roles are intentionally filtered from the current projection. A named,
content-free Presentation pane exposes Focus and Show Context Menu, and its popup
exposes Copy and Select All. The native tree does not contain document text, prose,
headings, mathematical expressions, selection, or animation geometry.
A plain or verbal rendering of mathematics is not
equivalent to mathematical accessibility and must not be advertised as such.

The pinned AccessKit schema can represent ordinary structure and mathematical roles,
but it has no complete portable MathML payload, speech-expression payload, or protocol
for navigating fractions, scripts, matrices, operators, and notation consistently
across AT-SPI, NSAccessibility, and UI Automation. Dynview also needs a larger retained
document model, character geometry, cross-node selection, viewport relations, and
immutable callback lifetime rules that are deliberately outside the current bounded
control tree.

Future Dynview work must begin as a new document-accessibility design. It must not widen
the current control projection incrementally or claim success from readable fallback
text alone.

### Explicitly Excluded: Terminal

Terminal content roles are also intentionally filtered from the current projection.
A named, content-free Terminal pane exposes Focus and Show Context Menu, and its popup
exposes Copy and Paste. These command entry points do not expose clipboard contents.
Euclid does
not expose Terminal input, output, scrollback, cursor, selection, links, alternate-screen
content, or command history through AccessKit.

AccessKit provides useful text primitives but no complete terminal protocol. Before
implementation, Euclid needs an explicit semantic and threat model covering prompt and
input boundaries, protected input and secrets, retained scrollback, live-output
batching, cursor speech, links, selection, alternate-screen behavior, virtualization,
and whether off-screen or historical data may be disclosed to native clients. Terminal
accessibility must not resume until those privacy and security decisions are recorded.

## Architecture and Ownership

Odin owns the semantic UI, publication, native adapters, actions, and lifecycle. Julia
is never entered from an accessibility callback.

The flow is:

1. The display thread commits one semantic UI snapshot.
2. Visible supported nodes are copied into one complete native-ready candidate.
3. The candidate is validated for identities, hierarchy, relations, UTF-8, ranges,
   bounds, and capacities.
4. Qualified semantic identities resolve to monotonic session-local native IDs.
5. One protected immutable tree generation is published to AccessKit.
6. Native callbacks may only read protected publication, copy bounded requests, update
   content-free diagnostics, and release transferred native values.
7. The display thread drains requests, revalidates target identity, generation, action,
   state, and payload, then routes an ordinary semantic UI command to the owner.
8. The next committed UI snapshot republishes the resulting state.

The shared substrate begins in `src/accessibility/publication.odin`.
Platform-independent AccessKit translation, validation, identity resolution, and action
admission begin in `src/view/native/accessibility/owner.odin`. Display-thread projection
and owner convergence are in `src/view/view.odin`.

### Identity and Lifecycle Contract

A native target is keyed by domain, owner domain, local ID, stable UUID, and generation.
Surviving semantic controls keep their native ID for the window session. Removed IDs
are retired and never reused, so a retained native element cannot retarget a later
control. Exhaustion rejects publication rather than wrapping IDs.

The display owner creates and destroys each platform adapter. Teardown closes protected
publication and action admission before AccessKit is freed and before the SDL window is
destroyed. New callbacks are rejected while already accepted bounded work remains safe
to drain. Native callbacks hold no display-owned pointers and cannot mutate UI state.

### Validation and Failure Policy

A candidate with an invalid ID, duplicate ID, missing parent, cycle, unreachable node,
invalid UTF-8, invalid bounds, invalid numeric range, invalid text boundary, or capacity
overflow is rejected as a whole. The implementation does not publish a truncated or
partially remapped tree. Unknown, stale, retired, unsupported, disabled, or invalid
native actions are rejected without owner mutation.

Diagnostics may retain generations, IDs, counts, capacities, statuses, failure stages,
and queue pressure. They must not log arbitrary Search, Dynview, or Terminal content.

## Published Model and Hard Limits

The current model is deliberately fixed-capacity and allocation-free in callback paths.

| Limit | Current value | Behavior at limit |
| --- | ---: | --- |
| Published control nodes | 320 | Reject the complete candidate. |
| Copied labels, values, and placeholders | 32 KiB total | Reject the complete candidate. |
| UTF-8 character and word-boundary entries | 1,024 | Reject the complete candidate. |
| Session-local native ID registry | 4,096 entries, including the root | Reject new identity allocation without ID reuse. |
| Queued native actions | 64 | Reject additional ingress and increment overflow diagnostics. |
| Text payload per action | 512 bytes | Reject the action. |
| Static bootstrap label | 64 bytes | Reject invalid bootstrap publication. |

Text offsets from the UI owner are UTF-8 byte offsets. Publication validates boundaries
and converts them to bounded native character positions. The current projection carries
one caret/selection pair and basic word starts, not a complete styled text document or
arbitrary text geometry.

Published roles are Label, TextRun, Button, Checkbox, Slider, AccordionHeader, Panel,
Status, SearchInput, Tree, TreeItem, Menu, and MenuItem. The current UI projection uses
all except the standalone Label role. Surface and Document UI roles are ignored;
Presentation and Terminal are projected only as content-free named panels.

### Context Menus

Right-click, Shift+F10, Menu, and the native Show Context Menu action open one
display-owned flat popup. Disabled commands remain visible and published but cannot
activate. Up/Down wrap over enabled commands, Home/End select an edge, and Enter/Space
activate once. Escape restores pane focus. Tab/Shift+Tab close and traverse from the
pane, including in Terminal. Outside presses dismiss and use normal click-through
routing; presses inside retain their release ownership even after dismissal.

Menu identities include an opening generation. Closed or replaced menu actions are
rejected, and native IDs are retired without reuse. Repeated openings consume the
existing bounded session registry; exhaustion rejects native publication explicitly.
Menu callbacks enqueue bounded owner requests and never read clipboard or pane text.
Menu-role/action translation and stale/disabled rejection have automated coverage;
complete screen-reader menu workflows remain unqualified on all three platforms.

## Cross-Platform Coverage

“Passed” below means the recorded Euclid native workflow operated that behavior on the
versioned platform. It does not mean exhaustive conformance or identical behavior among
inspectors and assistive technologies.

| Capability | Linux / AT-SPI | macOS / AX | Windows / UIA |
| --- | --- | --- | --- |
| Root, hierarchy, roles, names, bounds | Passed | Passed | Passed |
| Buttons and focus | Passed | Passed | Passed |
| Checkbox toggle | Passed | Passed | Passed |
| Ordinary numeric range mutation | Passed | Passed | Passed |
| Accordion and panel discovery | Passed through `click` | Panel discovery passed; native expanded selector absent | Passed |
| Search whole-value replacement | Passed through `setTextContents` | Passed through `AXValue` | Passed through Value pattern |
| Caret and text selection | Basic selection passed | Set and rejection passed | Caret and whole-document selection passed; partial range is a no-op |
| Selected-text replacement | Owner path tested; native dispatch unproven | Not dispatched by AccessKit macOS 0.27.1 | Not exposed by the qualified managed UIA client |
| Search-to-Tree relation | Passed | Passed as linked elements | Unavailable through the qualified managed UIA client |
| Tree filtering and selection | Passed | Passed | Passed |
| Tree expand/collapse | `click` compatibility toggle; no named Expand/Collapse | Not dispatched by AccessKit macOS 0.27.1 | Passed |
| Composite Tree scrolling | Value compatibility operation passed | Positive native range passed | RangeValue is exposed read-only |
| Identity continuity and retirement | Passed | Passed | Passed, including stale-item rejection and ID non-reuse |
| Repeated provider teardown | Passed | Passed | Passed |
| Busy-state projection | Not exhaustively qualified | Not exposed by AccessKit macOS 0.27.1 | Transient GIF state not yet automated |
| Primary screen-reader workflow | No archived complete Orca workflow | VoiceOver review completed | Complete Narrator workflow not recorded |
| Content-free context menus | Automated shared role/action tests; native workflow unqualified | Native workflow unqualified | Native workflow unqualified |
| Dynview and mathematics | Excluded | Excluded | Excluded |
| Terminal | Excluded | Excluded | Excluded |

The platforms therefore provide roughly equivalent access to the current sidebar, but
not native action-by-action parity. The Tree operation used for expansion or scrolling
is notably different on each adapter.

## Verification Model

Accessibility evidence has distinct layers. Do not substitute one for another:

| Evidence | What it proves | What it does not prove |
| --- | --- | --- |
| Deterministic Odin tests | Validation, copying, identity, queue, owner routing, adapter lifecycle, and failure behavior | Native adapter dispatch or assistive-technology usability |
| AccessKit ABI probe | Header layout, enums, symbols, linkage, and retained provider loading | Semantic correctness |
| Application scenarios | Owner mutation, republication, shutdown, and correlated application evidence | Native API exposure |
| Native platform probe | Discovery and operation through AT-SPI, AX, or UIA | Complete API conformance or screen-reader speech |
| Inspector review | Human-observable native structure and state | Full keyboard or screen-reader workflow |
| Assistive-technology review | User workflow on one named client and environment | Other clients, desktops, scales, or architectures |

Public API existence does not prove adapter behavior. Adapter source does not prove the
retained provider. A passing native probe does not prove a screen reader will navigate
or speak the surface usefully.

### Common Commands

Build the debug application before a native probe:

```sh
cmake --build --preset debug
```

Validate the retained C ABI on the active host:

```sh
julia tools/make.jl accesskit-abi
```

Run the platform command on a logged-in graphical session:

```sh
julia tools/make.jl accessibility-tree
julia tools/make.jl accessibility-macos
julia tools/make.jl accessibility-windows
```

Only the command for the active platform is valid. Native probes run two complete
application sessions and require provider removal after shutdown. After substantive
changes, also run the relevant language unit suite, debug/default builds when affected,
and the canonical gate:

```sh
cmake --build --preset default --target check
```

## Native Probes

### AccessKit C ABI Probe

`tools/accessibility/run_accesskit_abi_probe.jl`
compiles the C probe against the retained header and provider. It checks action and role
values, structure sizes and offsets, required platform symbols, Windows adjacent-DLL
loading, and exact host linkage assumptions. Output is generated under
`.build/accesskit-abi/`.

Run this whenever the AccessKit artifact, header, Odin binding, platform toolchain,
packaging, or runtime closure changes. It says nothing about native semantic behavior.

### Linux AT-SPI Probe

`tools/accessibility/accesskit_tree_probe.py`
uses `pyatspi` against the real desktop bus. `julia tools/make.jl accessibility-tree`
first runs its Python unit tests and then runs the native probe.

Prerequisites are Linux, Python 3 with `pyatspi`, a logged-in AT-SPI session, the debug
build, and the repository's current Hyprland/`hyprctl` close workflow. The last
requirement is a probe portability limitation, not an application requirement.

The probe records two sessions in `.build/accessibility-button/atspi.json` using report
schema 6. It records the desktop/session type, SDL video driver, roots and controls,
interfaces, roles, states, relations, object paths, bounds, actions, values, text,
Component observations, Search and Tree operations, Settings controls, host
transitions, scenario evidence, and provider removal. Unsupported Component or text
operations are recorded as outcomes instead of aborting unrelated observations.

The current workflow proves direct AT-SPI operation for ordinary controls, Search
whole-value replacement, basic text selection, filtering, Tree selection, branch
toggling through `click`, composite scrolling through Value, identity retirement, and
repeated teardown. It does not establish exhaustive AT-SPI conformance, desktop parity,
or a complete Orca workflow.

### macOS AX Probe

`tools/accessibility/accesskit_macos_tree_probe.swift`
uses the system Accessibility API. It requires Apple Silicon macOS, Swift, a logged-in
GUI session, the debug build, and Accessibility permission for the terminal or VS Code
process launching the command. Enable that process under **System Settings > Privacy &
Security > Accessibility**.

The command launches `.build/debug/Euclid.app`, validates its bundle identity and a
system-wide point hit, then operates Search, selection, relations, filtering, Tree
selection, identity continuity and retirement, composite scrolling, Settings,
checkbox, slider, Restart, native close, and provider removal. It writes two-session
schema-3 evidence to `.build/accessibility-macos/ax.json` and session logs beside it.

Launch the packaged default artifact with `open bin/Euclid.app` for manual inspection.
A bare Mach-O process has no application bundle identity and Accessibility Inspector's
point picker may ignore it.

### Windows UIA Probe

`tools/accessibility/accesskit_windows_tree_probe.cs`
is a .NET file-based UI Automation client. It requires Windows 11 x64, .NET SDK 10 or
newer, a logged-in interactive desktop, and the debug build. By default it targets
`.build/debug/euclid.exe`; `--binary=bin/euclid.exe` may target the default build.

The command runs two complete sessions covering the root, ordered controls, Restart,
Pause/Resume, splitters, Settings, Display FPS, Maximum Dust, GIF idle state, focus,
Search Value and Text patterns, multibyte text, caret, whole-document selection,
filtering, Tree selection and expansion, identity continuity, retirement, stale-item
rejection, ID non-reuse, process exit, and provider removal. It writes schema-3 evidence
to `.build/accessibility-windows/uia.json`, with session logs and scenario artifacts
beside it.

Accessibility Insights remains necessary for manual relation, dynamic event, transient
state, scale, resize, and client-behavior review. Expand Settings or Save GIF in Euclid,
then refresh or reselect the Euclid root if Live Inspect has not followed the update.

## Known AccessKit and Client Limits

### Attribution Rules

Classify every finding at the narrowest evidenced boundary:

| Boundary | Question |
| --- | --- |
| Native API | Can AT-SPI, NSAccessibility, or UIA represent the behavior? |
| AccessKit schema | Can a portable AccessKit node carry it? |
| AccessKit C | Is the schema feature exported across the C ABI? |
| Rust platform adapter | Does the adapter translate the fact or action? |
| Euclid binding and publication | Does Euclid declare, publish, and route it? |
| Native client and evidence | Does the qualified inspector or assistive technology expose and operate it? |

Do not label a behavior an AccessKit defect merely because one inspector cannot observe
it. Conversely, deterministic owner tests prove Euclid can handle a request but do not
prove an adapter can emit it.

### Portable Schema Limits

The pinned schema has no complete representation for:

- exact mathematical payloads and navigation;
- a complete terminal semantic protocol;
- arbitrary announcements with portable queueing, interruption, priority, and
  attribution guarantees;
- custom VoiceOver rotors or equivalent native navigation collections;
- AT-SPI Component alpha or MDI z-order; and
- every native-only property, action, notification, and text pattern.

Live-region and status facts can be published, but Euclid cannot promise identical
spoken timing. Structural roles should be preferred over custom navigation extensions.

### AccessKit C and Euclid Binding

No confirmed current failure has been attributed to AccessKit C 0.23.1 itself. Its API
exports the text, range, relation, focus, selection, expansion, scrolling, and state
features used by the current model. Euclid intentionally binds only the subset it owns.
The binding does not yet expose every description, invalid/read-only/required/modal/
hidden state, language, text direction, transform, role description, state description,
braille description, or detailed text-geometry setter available upstream.

Evaluate future features as **available and used**, **available but unused**, or
**unavailable**. Add binding symbols only with a semantic owner, deterministic tests,
and a native acceptance case.

### Linux / AccessKit Unix 0.24.0

- TreeItem exposes one `click` action rather than named Expand and Collapse actions.
  Euclid treats `click` on a branch as an expansion toggle.
- Expanded state was not visible through the qualified AT-SPI projection.
- Tree scrolling uses a finite Value range because useful named native scrolling
  actions were not exposed.
- Search requires a TextRun descendant to expose Text. Even an empty TextRun must carry
  a value; omitting it can reach an adapter unwrap and disconnect the client.
- `EditableText.setTextContents` works and maps to whole-value replacement.
  `insert_text`, `delete_text`, `copy_text`, `cut_text`, and `paste_text` return
  unsupported through AccessKit Unix.
- Accerciser's text editor uses granular `insert_text`, so typing there fails even
  though the direct probe's whole-value replacement succeeds.
- For unstyled Search text, an observed Accerciser path receives `None` for text
  attributes and crashes while assuming a dictionary. The producing AccessKit,
  libatspi/pyatspi, or client layer has not been isolated. Euclid must not invent style
  attributes to mask that client failure.
- Component alpha and MDI z-order have no portable node property. The probe records the
  native results, but these inspector methods should block only if they affect native
  conformance, stability, or real assistive-technology behavior.
- No complete Orca workflow or GNOME/KDE, X11/Wayland matrix is archived.

The Linux claim remains direct AT-SPI operation on the recorded session, not exhaustive
interface or screen-reader qualification.

### macOS / AccessKit macOS 0.27.1

- DisclosureTriangle maps to `AXButton` and controls relations map to
  `AXLinkedUIElements`.
- The adapter does not expose an expanded-state selector or operable native Tree
  Expand/Collapse dispatch. `AXPress` and `AXPick` did not change branch topology.
- `AXSelectedTextRange` maps to SetTextSelection, but there is no
  `setAccessibilitySelectedText:` implementation to dispatch ReplaceSelectedText.
- Busy state is not exposed by this adapter version.
- Positive composite Tree scrolling through `AXValue` passed and is not a limitation.

Tree expansion/collapse and selected-text replacement are native action blockers for a
strict parity claim, even though their shared Euclid owner paths are tested.

### Windows / AccessKit Windows 0.35.1

- Selecting a valid partial TextPattern range leaves the previous owner-published
  selection unchanged. Caret and whole-document selection pass.
- The Tree publishes a positive vertical range, but UIA exposes RangeValue as read-only,
  so the qualified client cannot perform composite scrolling.
- The inbox managed UIA client exposes no selected-text replacement operation.
- That client reports ControllerFor as unsupported even though Euclid publishes the
  Search-to-Tree and accordion-to-panel relations.
- Transient GIF busy/disabled events, complete dynamic-event review, resize,
  multi-monitor behavior, and 100/200 percent scale checks remain unqualified.

Partial selection and read-only Tree range are adapter projection differences.
Selected-text replacement and ControllerFor also require lower-level UIA or
Accessibility Insights evidence before assigning them solely to AccessKit.

## Qualification Records

These records preserve what was actually run on 2026-09-30. Generated `.build/`
artifacts are local evidence and are not source-controlled specifications.

### macOS Qualification

| Component | Qualified version |
| --- | --- |
| macOS | 26.6.2 (25G83) |
| Architecture | Apple Silicon arm64 |
| Euclid candidate | `8fee5a0b09434930928362ec640548f99e8d213a` plus the then-uncommitted qualification patch |
| AccessKit C / schema / macOS | 0.23.1 / 0.25.1 / 0.27.1 |
| SDL3 / SDL3_image | 3.4.16 / 3.4.6 |
| Accessibility Inspector / VoiceOver | 5.0 / 10 |
| Odin / Julia | dev-2026-09:a2fb372b7 / 1.13.0 |
| Apple clang / Xcode / CMake | 21.0.0 / 27.0 / 4.4.3 |

The focused Odin suite passed 1,470/1,470 and the Julia suite passed 2,363/2,363.
The canonical gate passed 3,833 application tests and 710 analyzer tests with 782 files
analyzed and no warnings or failures. ABI, debug/default builds, two AX sessions,
provider removal, native Tree scrolling from 0 to 616, Accessibility Inspector, and
VoiceOver review passed. Retina bounds were checked against the 30 by 30 Restart frame.

The checked runtime-closure hash was
`9980e96012c0982c9c952cab74d73bcfdbc801c6ed3205cce013adf2be66d7d5`; the generated
form was `ea331071f6cd2c607e65e77fc2e2ed250726da73a22dc9b5e864d5e33fe06bd6`.
The forms are intentionally not byte-identical. A future formal freeze must identify
one committed candidate and re-run all gates after adapter changes.

### Windows Qualification

| Component | Qualified version |
| --- | --- |
| Windows | Windows 11 Home 10.0.26200, build 26200 |
| Architecture / scale | AMD64 / 150 percent (`AppliedDPI=144`) |
| Euclid candidate | `9c86605dda3fe7c87cc59e692f6cd14ff78ff898` plus the then-uncommitted qualification patch |
| Analyzer candidate | `70b818f5f428bdf91234c63b7aedafb6853e6668` plus the path-normalization test fix |
| AccessKit C / schema / Windows | 0.23.1 / 0.25.1 / 0.35.1 |
| SDL3 / SDL3_image | 3.4.16 / 3.4.6 |
| Accessibility Insights | 1.1.2924.1 |
| Odin / Julia | dev-2026-09-nightly:a2fb372 / 1.13.0 |
| MSVC / CMake | 19.51.36260 for x64 / 3.29.2 |

The focused native suite passed 17/17. The canonical gate passed 3,829 application
tests and 710 analyzer tests; analyzer self-analysis covered 55 files and repository
analysis covered 787 files with no warnings or failures. ABI and adjacent-DLL loading,
debug/default builds and loader smokes, two UIA sessions, stale-item rejection, provider
removal, and ID non-reuse passed. The staged `accesskit.dll` hash was
`d9f9d834eb0a86c799044800065887749397e2343f37681d38f9725535beaa63`.

The qualification report hash was
`697e692d8770ac35ef256bbeedb1774678f71bef4a65f3c18fe3ce9f947361d3`.
Default and debug executable hashes were
`9d93b1a81b3eb87219ab43b81376d8caa5a35e077838c0db36f43b52388241f3` and
`cee7c0f9a55ff6a67154d1cf47083929a1a3e7211e6a93944d00470c83ea8427`.
Checked and generated runtime-closure hashes were
`3cd3ae3865af43a957f0ada53d782950634272c6bd62454689ff29160c5edc94` and
`89204020f4fd84487e0a1c68e1936389f0eb0a2cbded7fa4d6358db564befa81`.

Manual Accessibility Insights discovery passed for the root, Restart, Pause, and active
accordion subtree. It was not the complete transient GIF, relation, dynamic filtering,
composite scrolling, teardown, resize, or 100/200 percent scale matrix. A future formal
freeze must use one committed candidate and close or explicitly re-scope those gates.

## Resuming Accessibility Work

Use this order when accessibility work resumes:

1. Re-run `accesskit-abi` and the active platform probe on the current committed
   revision. Archive OS, desktop/compositor, display server, scale, locale,
   architecture, AccessKit versions and hashes, native client versions, report schema,
   and dirty state.
2. Expand Linux evidence first: complete Component, Text, EditableText, event,
   retained-object, resize/scale, GNOME/KDE, Wayland/X11, and Orca coverage. Record each
   operation as passed, unsupported, rejected, no-op, timeout, crash, or provider loss.
3. Extract one platform-neutral operation vocabulary from all three probes while
   retaining platform-native observations. Do not force false equality between APIs.
4. Reproduce each suspected adapter defect outside owner logic and add the smallest
   upstream Rust regression test before patching AccessKit.
5. Prefer a fork of the main AccessKit Rust repository with AccessKit C retained as the
   stable `extern "C"` boundary. Fork AccessKit C only when a required schema feature or
   adapter configuration cannot cross its current API.
6. Re-run ABI, deterministic tests, native probes, manual inspectors, representative
   assistive technologies, builds, runtime closure, and the canonical gate on every
   supported platform affected by a patch.
7. Treat Dynview as a separate document-and-math program and Terminal as a separate
   semantic, privacy, and security program. Neither belongs in a patch that merely
   improves the current sidebar.

Strong initial adapter candidates are Unix granular EditableText operations and named
Tree state/actions, macOS Tree expansion and selected-text replacement, Windows partial
TextPattern selection, and a writable Windows composite-scroll operation. Patch only
user-relevant behavior that is reproducible below Euclid's owner layer and representable
by the native platform.

## Source Map

- Shared publication and capacities: `src/accessibility/publication.odin`
- Native IDs and action ingress: `src/accessibility/native_storage.odin`
- Shared adapter ownership: `src/view/native/accessibility/owner.odin`
- Translation and action validation:
  `src/view/native/accessibility/accesskit_translation.odin` and
  `src/view/native/accessibility/action_adapter.odin`
- Platform adapters: `src/view/native/accessibility/unix_adapter.odin`,
  `src/view/native/accessibility/macos_adapter.odin`, and
  `src/view/native/accessibility/windows_adapter.odin`
- Display projection and owner convergence: `src/view/view.odin`
- Narrow Odin binding: `libs/accesskit/accesskit.odin`
- Retained C header: `libs/accesskit/include/accesskit.h`
- Linux native probe: `tools/accessibility/accesskit_tree_probe.py`
- Command driver: `tools/make.jl`

This guide is the accessibility source of truth. Update it whenever supported roles,
capacities, AccessKit versions, platform evidence, exclusions, or qualification claims
change.
