# macOS Native Accessibility Parity for Euclid

## Proposal Status

This is the macOS implementation staging companion to
[`sev_access2.md`](sev_access2.md). It begins from the accessibility behavior already
implemented on Linux through the current Search, Tree, basic text, and composite
scrolling work. Its purpose is to bring that complete existing surface to Apple Silicon
macOS through AccessKit C 0.23.1, with intermediate native gates that isolate Cocoa
admission, lifecycle, controls, text, and dynamic hierarchy before declaring parity.

This is not a cross-platform development loop. The delivery order is intentionally
serial:

1. implement and qualify the current accessibility surface on macOS;
2. after macOS parity is complete, return to Linux once and run the full regression
   matrix;
3. implement and qualify the same parity surface on Windows;
4. after Windows parity is complete, run the full matrix on Linux, macOS, and Windows;
5. only then resume new accessibility development, beginning with Dynview and Terminal
   on Linux.

Linux is the behavioral reference for this document, not a second active development
platform during the macOS phases. Linux native evidence is not a gate for each macOS
increment. It is run once after macOS parity to detect regressions introduced while
extracting shared AccessKit translation and action behavior.

The recommendation is:

> Establish the Darwin ABI and Cocoa lifecycle first, prove one rooted tree and one
> real button, expand through ordinary controls and status, then qualify Search, Tree,
> text, filtering, identity retirement, and composite scrolling. Declare macOS parity
> only after deterministic tests, machine-readable AX evidence, Accessibility
> Inspector, and VoiceOver all agree. Then stop macOS development and perform one
> complete Linux regression pass.

## Scope

### Required Parity Surface

macOS parity means the application exposes and operates the complete accessibility
surface currently implemented on Linux:

- one synthetic application root;
- complete ordered control hierarchy;
- stable qualified semantic identities mapped to monotonic session-local native IDs;
- host focus and semantic focus;
- complete changed-node publication and identical-frame suppression;
- buttons and native activation;
- checkboxes and toggled state;
- sliders and splitters with finite range facts and actions;
- accordion headers, panels, expanded state, and relations;
- GIF controls, enabled, disabled, pending, busy, and status behavior already present;
- Library Search as editable text;
- committed text, placeholder, caret, selection, and bounded text actions;
- Tree and TreeItem hierarchy, active descendant, selection, expansion, levels, set
  position, filtering, and identity retirement;
- Search-to-Tree relation;
- composite scrolling without native custom scrollbar thumbs;
- copied bounded callback ingress;
- display-thread stale-target, generation, payload, and action validation;
- owner-side exactly-once mutation;
- clean partial-construction unwind and teardown.

### Qualified Target

The qualified target for this program is Apple Silicon macOS.

The repository may retain the AccessKit x86_64 macOS artifact and validate its manifest
and hash, but this document makes no Intel runtime, Accessibility Inspector, or
VoiceOver support claim. Intel qualification requires execution on an Intel macOS host
and is outside this staging program.

### Required Native Evidence

The required macOS evidence sources are:

- deterministic Odin and Julia tests;
- the native AccessKit C ABI and ownership probe;
- a machine-readable macOS Accessibility API evidence workflow;
- Accessibility Inspector;
- VoiceOver.

Voice Control and Switch Control remain part of the later full cross-platform
qualification program. They do not block this current-tree parity milestone.

### Non-Goals

This staging program does not implement or qualify:

- Dynview document accessibility;
- mathematical fallback semantics;
- Terminal accessibility;
- Voice Control workflows;
- Switch Control workflows;
- Intel macOS runtime support;
- custom AppKit accessibility objects authored by Euclid;
- Julia-owned native accessibility objects;
- native custom scrollbar thumbs;
- identical native object trees or spoken wording between AT-SPI and
  NSAccessibility.

## Decision Requested

Approve the following macOS staging decisions before implementation begins:

| Decision | Recommendation |
| --- | --- |
| Delivery order | Complete macOS parity first, regress Linux once afterward, then begin Windows parity. |
| Qualified architecture | Apple Silicon only. |
| Native adapter | Use the AccessKit macOS subclassing adapter around SDL's borrowed `NSWindow`. |
| Native pointer ownership | Borrow the SDL `NSWindow` only for the SDL window lifetime; never retain or release it as Euclid-owned storage. |
| Window class | Discover the actual Objective-C class at runtime; do not hard-code an SDL private class name. |
| Focus forwarding | Install AccessKit's window-class focus forwarder once for each encountered window class. |
| Library lifetime | Keep AccessKit loaded for the remainder of the process after focus-forwarder installation. |
| Thread ownership | Obtain SDL Cocoa properties and perform adapter/event operations on the display/AppKit main thread. |
| Scroll direction | Preserve SDL's delivered per-event wheel sign so natural trackpad and ordinary mouse scrolling follow system/device behavior without a Darwin-wide inversion. |
| Queued events | Raise every non-null AccessKit macOS queued-event object exactly once. |
| Shared policy | Keep tree translation, ID policy, request copying, and action validation platform-neutral. |
| macOS ownership | Limit Darwin code to Cocoa admission, adapter lifetime, focus forwarding, queued events, and documented native conversion. |
| Failure behavior | Diagnose macOS accessibility failure while allowing ordinary Euclid operation to continue. |
| Native automation | Add a logged-in-session AX evidence command with explicit Accessibility permission requirements. |
| Parity gate | Require deterministic tests, AX evidence, Accessibility Inspector, and VoiceOver. |
| Linux timing | Run Linux regression only after the complete macOS parity gate passes. |
| Expansion stop | Do not start Windows work while macOS has malformed trees, stale mutation, callback faults, event ownership faults, or teardown failures. |

## Existing Foundation

Euclid already has the portable and owner-side facilities needed for macOS parity:

- bounded protected accessibility publication;
- complete validation before publication becomes current;
- qualified identities and a monotonic native ID registry;
- explicit identity retirement without session reuse;
- bounded copied action ingress;
- display-thread generation, target, action, and payload validation;
- complete AccessKit node construction for current controls;
- retained publication generation and update suppression;
- owner-side convergence between pointer, keyboard, semantic, scenario, and native
  actions;
- prepared control geometry and values;
- editable text descriptors and UTF-8 character mapping;
- Tree hierarchy, filtering, active descendant, and composite scroll facts;
- repository-owned AccessKit C 0.23.1 arm64 and x86_64 macOS dylibs;
- schema-versioned artifact manifests, hashes, licenses, notices, linker paths, runtime
  paths, and closure generation;
- a host ABI probe covering common C layouts and basic ownership.

The central implementation problem is that the current AccessKit tree construction,
request copying, action validation, and adapter lifecycle are still combined in a
Linux-tagged file. The macOS work must separate reusable AccessKit behavior from native
Unix admission without creating a second translation policy.

## macOS Native Contracts

### SDL and Cocoa Ownership

SDL creates and owns the application window. On macOS,
`SDL_GetWindowProperties` provides
`SDL_PROP_WINDOW_COCOA_WINDOW_POINTER`, an unsafe-unretained pointer to the associated
`NSWindow`. The property query must occur on the main thread.

Euclid must:

- query the property only after SDL window creation succeeds;
- reject a missing property with a typed accessibility initialization diagnostic;
- treat the pointer as borrowed;
- never release it;
- never use it after `SDL_DestroyWindow`;
- free the AccessKit adapter before destroying the SDL window.

### Subclassing Adapter

Use `accesskit_macos_subclassing_adapter_for_window`. SDL owns the content view and
window class, so the subclassing adapter is a better ownership match than introducing a
Euclid AppKit view subclass or manually forwarding every accessibility method through
the lower-level adapter.

The adapter constructor requires a valid `NSWindow` with a current content view. Native
constructor failure must unwind accessibility resources without preventing Euclid from
continuing without a native accessibility tree.

### Focus Forwarder and Process Lifetime

SDL may place keyboard focus directly on the window. AccessKit provides a focus
forwarder that adds `accessibilityFocusedUIElement` behavior to an `NSWindow` subclass.
This mutates the Objective-C class and cannot be reversed.

Euclid must:

- discover the actual class name through the Objective-C runtime;
- install the forwarder once per encountered class;
- avoid hard-coding an SDL implementation class;
- ensure the AccessKit dylib is never unloaded after installation;
- retain process-level installation state separately from a window-session adapter;
- document the irreversible lifetime contract.

### Queued Native Events

The macOS update and view-focus functions return
`accesskit_macos_queued_events *`. A non-null return transfers work that must be raised
through `accesskit_macos_queued_events_raise`. Raising also frees the queued-event
storage.

Every call site must therefore satisfy exactly-once ownership:

1. call the AccessKit update or focus function on the AppKit/main thread;
2. if the returned pointer is non-null, raise it exactly once;
3. do not retain, inspect, duplicate, or free it through another path;
4. record content-free diagnostics for update and event raising;
5. never abandon a returned non-null pointer during an error path.

### System Scroll Direction

SDL marks naturally scrolling wheel events as `FLIPPED` and already delivers their
`x` and `y` values with the system-selected direction. Euclid currently negates those
values again at the SDL input boundary, converting natural trackpad behavior back to
traditional wheel direction.

Euclid must preserve `SDL_MouseWheelEvent.y` as delivered. It must not:

- invert every event on Darwin;
- query macOS scrolling preferences directly;
- infer trackpad versus mouse from device identity;
- normalize `FLIPPED` events back to `NORMAL` direction.

This is a cross-platform input correction discovered during macOS qualification, not a
macOS-only policy. SDL's per-event direction preserves ordinary `NORMAL` mouse-wheel
behavior while allowing natural trackpad events and platform/device settings to remain
effective. Scroll containers, sliders, and Terminal mouse reporting must consume one
consistent delivered-sign contract.

### Coordinates

The current publication carries authoritative logical control bounds. AccessKit's
macOS adapter projects view-relative geometry through AppKit. macOS must not reuse the
Linux X11 root-window bounds path.

Any demonstrated scale, origin, or text-geometry mismatch must be corrected at the
Darwin adapter boundary with explicit fixtures. It must not be hidden by changing
portable owner geometry solely for macOS.

### Callback Boundary

Native action callbacks may only:

- observe callback-admission state;
- copy the action, target, generation, and bounded payload;
- enqueue the copied request or record rejection;
- free the transferred AccessKit action request exactly once;
- return.

They must not enter Julia, call SDL, mutate UI owners, wait for the display thread, or
hold protected publication synchronization while doing unrelated work.

## Implementation Phases

## Phase 0: Darwin Boundary and Shared AccessKit Core

### Phase 0 Objective

Make the existing AccessKit translation and action contract reusable by macOS while
preserving one implementation of semantic policy.

### Phase 0 Work

1. Split `src/view/native/accessibility/unix_adapter.odin` into shared AccessKit behavior
   and Unix lifecycle behavior.
2. Move complete tree construction into an untagged shared file:
   - synthetic root creation;
   - role mapping;
   - label, value, placeholder, state, action, range, relation, hierarchy, text,
     selection, and bounds properties;
   - focus selection;
   - complete changed-node updates.
3. Move adapter-independent publication ownership into shared code:
   - staging validation;
   - qualified-identity lookup;
   - native ID resolution and retirement;
   - protected publication;
   - delivered-generation suppression.
4. Move adapter-independent action handling into shared code:
   - supported AccessKit action filtering;
   - copied text, numeric, and text-selection payloads;
   - UTF-8 validation;
   - target and generation validation;
   - enabled and supported-action validation;
   - range and selection validation;
   - display-thread action drain.
5. Leave in the Unix file only:
   - Unix adapter construction and destruction;
   - activation and deactivation registration;
   - Unix update calls;
   - Unix host-focus forwarding;
   - X11 root bounds;
   - Unix-specific callback wrappers where the C signature requires them.
6. Move deterministic translation and action fixtures out of Linux-only tests. Keep
   Unix lifecycle tests tagged for Linux.
7. Add Darwin declarations to `libs/accesskit/accesskit.odin` for:
   - `accesskit_macos_subclassing_adapter`;
   - `accesskit_macos_queued_events`;
   - subclassing adapter creation and free;
   - update-if-active;
   - view-focus updates;
   - queued-event raise;
   - window-class focus-forwarder installation.
8. Extend the ABI probe to verify the required macOS symbols and retained arm64 dylib.
9. Verify the active manifest, artifact hash, native dependencies, rpath, and generated
   closure on Apple Silicon.
10. Remove the SDL input-boundary inversion of `FLIPPED` wheel events and define
  `mouse_wheel_delta` as the signed value delivered by SDL after platform and device
  scrolling policy.
11. Add focused input tests proving that `NORMAL` and `FLIPPED` events both preserve
  their delivered magnitude and sign, multiple events accumulate without global
  platform inversion, and ordinary mouse behavior is unchanged.
12. Add typed failure stages for Cocoa property lookup, class discovery, focus-forwarder
    installation, adapter creation, update, focus update, queued-event raise, and
    teardown.

### Deterministic Tests

- exact static root and child update;
- exact mixed ordinary-control update;
- exact Search and Tree hierarchy;
- complete changed records;
- semantically identical publication suppression;
- monotonic ID allocation and retirement;
- stale, unknown, removed, disabled, and unsupported requests;
- finite and bounded numeric payloads;
- bounded valid UTF-8 text payloads;
- text-selection node and index validation;
- callback request freed exactly once;
- callback rejection after admission closes.
- delivered-sign wheel behavior for `NORMAL` mouse and `FLIPPED` natural-scroll
  events;
- accumulated fractional trackpad deltas without sign normalization.

### Phase 0 Falsifiable Claim

Apple Silicon can validate and link the exact retained AccessKit C 0.23.1 macOS ABI,
and macOS can consume one platform-neutral tree and action implementation without
copying Linux semantic policy.

### Phase 0 Exit Gate

- shared deterministic tests pass on macOS;
- Darwin-specific declarations compile and link;
- `julia tools/make.jl accesskit-abi` passes on Apple Silicon;
- the arm64 manifest, artifact, license, dependencies, and closure validate;
- trackpad scrolling follows the macOS system direction while `NORMAL` mouse-wheel
  fixtures retain their existing direction;
- no macOS adapter is admitted yet;
- no Linux regression run is required at this phase.

## Phase 1: Cocoa Admission, Root, Button, Focus, and Teardown

### Phase 1 Objective

Publish one valid rooted application tree and one real button through
NSAccessibility, proving Cocoa admission, focus forwarding, queued-event ownership,
action ingress, and teardown.

### Phase 1 Work

1. Add a Darwin-tagged macOS adapter owner under
   `src/view/native/accessibility/`.
2. Query SDL window properties on the display/AppKit main thread.
3. Borrow the `NSWindow` pointer and validate its lifetime preconditions.
4. Discover its Objective-C class name at runtime.
5. Install the AccessKit focus forwarder once for that class and retain process-level
   installation state.
6. Publish a validated protected tree before adapter construction can activate it.
7. Construct the subclassing adapter for the SDL window.
8. Reuse the shared activation tree factory and action callback ingress.
9. Forward host focus through the macOS view-focus API.
10. Raise each non-null queued-event result exactly once.
11. Route copied actions through the existing display-frame drain and owner result path.
12. Wire macOS into the current SDL platform publication, focus, drain, and destruction
    interfaces.
13. Preserve ordinary application operation after injected accessibility failure.
14. Destroy in this order:
    - stop action and publication admission;
    - prevent further native updates;
    - free the subclassing adapter;
    - clear borrowed Cocoa state;
    - continue ordinary native resource teardown;
    - destroy the SDL window.
15. Exercise a synthetic root plus one representative existing animation button inside
    the application tree.

### Phase 1 Required Cases

- missing Cocoa window property;
- invalid or absent content view at adapter admission;
- repeated focus-forwarder installation attempt;
- activation before a valid publication;
- root and button discovery;
- role, name, enabled state, actions, and bounds;
- host focus loss and restoration;
- semantic focus gain and loss;
- native activation exactly once;
- native plus keyboard or pointer activation in one frame;
- identical-frame update suppression;
- removal and reappearance with a fresh native ID;
- stale and retired target rejection;
- resize and display-scale change;
- queued events present and absent;
- partial-construction failure unwind;
- repeated launch and close;
- late callback after closing begins;
- adapter destruction before SDL window destruction.

### Native Evidence

Accessibility Inspector must report:

- one Euclid application root;
- one correctly named representative button;
- coherent parent and child links;
- finite bounds;
- enabled and focusable state;
- supported focus and press actions;
- current focus;
- clean disappearance after shutdown.

VoiceOver must:

- discover Euclid;
- move to the representative button;
- report a coherent name and role;
- activate it;
- observe the resulting application state change;
- survive application focus changes and repeated restart.

### Phase 1 Falsifiable Claim

A macOS accessibility client can repeatedly discover, focus, and activate one real
Euclid button without malformed native state, duplicate owner mutation, leaked queued
events, late callbacks, or teardown faults.

### Phase 1 Exit Gate

- deterministic Darwin lifecycle tests pass;
- Accessibility Inspector reports the required root and button facts;
- VoiceOver completes the button workflow;
- owner evidence records exactly one mutation per accepted native action;
- every queued-event result follows exactly-once ownership;
- repeated teardown remains clean;
- no Linux regression run is required at this phase.

## Phase 2: Ordinary Controls and Status

### Phase 2 Objective

Expand the proven macOS lifecycle and action path through every ordinary control family
currently exposed on Linux.

### Work Order

1. remaining push buttons;
2. checkboxes and toggled state;
3. integer sliders;
4. splitters as ranged controls;
5. accordion headers, panels, expanded state, and relations;
6. GIF timing and selected-state controls;
7. save, cancel, enabled, disabled, pending, and busy state;
8. bounded status and error nodes.

### Control Requirements

#### Buttons

- Accessible names agree with visible labels where practical.
- Changing state does not destroy stable identity without an owner generation change.
- Disabled controls reject native activation.
- Contextual duplicate actions expose enough name context for coherent navigation.

#### Checkboxes

- Publish CheckBox role, toggled state, enabled state, name, focus, bounds, and click
  action.
- Preserve unavailable-feature identity in the stable name and availability in state or
  description.

#### Sliders and Splitters

- Publish finite current, minimum, maximum, step, orientation, and formatted value.
- Reject NaN, infinity, and out-of-range values before owner mutation.
- Route increment, decrement, and set-value through existing typed range helpers.
- Preserve pane minimums, portrait behavior, overlap arbitration, and locking.

#### Accordion and Panels

- Preserve deterministic identity and hierarchy.
- Publish expanded state and controls relations.
- Omit inactive descendants.
- Preserve one-open-section policy and existing focus repair.

#### Status

- Publish only meaningful bounded milestones and errors.
- Do not make FPS, particles, animation frames, or other high-rate telemetry live.
- Treat VoiceOver wording and timing as empirical behavior rather than a portable schema
  guarantee.

### Native Evidence Tool

Add an Apple-Silicon accessibility evidence command under `tools/accessibility/` and
dispatch it through `tools/make.jl` on macOS. It must run in a logged-in GUI session
with documented Accessibility permission and emit bounded machine-readable facts for:

- AX role and subrole where relevant;
- name, value, state, actions, and hierarchy;
- focused element;
- bounds;
- range facts;
- expanded and toggled state;
- relations available through AX;
- action result and owner evidence;
- update and removal behavior.

The GUI evidence command is an explicit qualification workflow. It is not silently
added to headless `ctest`, where permissions or a WindowServer session may be absent.

### Phase 2 Required Cases

- exact native properties for each control family;
- system-directed trackpad scrolling and unchanged `NORMAL` mouse-wheel behavior over
  scroll containers and wheel-adjustable ranges;
- dynamic enabled and disabled transitions;
- toggled, selected, and expanded transitions;
- finite range changes and clamping;
- focus traversal and focus repair;
- dynamic panel insertion and removal;
- native action plus pointer or keyboard action in one frame;
- stale generation and retired native ID;
- unsupported action and malformed payload;
- status coalescing and update suppression;
- repeated native inspection during dynamic changes.

### Phase 2 Falsifiable Claim

Every ordinary visible Euclid control exposes coherent macOS role, name, state, value,
range, relationship, focus, bounds, and supported actions without duplicate owner
mutation or malformed dynamic updates.

### Phase 2 Exit Gate

- shared and Darwin adapter tests for ordinary controls pass on macOS;
- machine-readable AX evidence inspects and operates representative controls;
- Accessibility Inspector remains stable through dynamic panel and state changes;
- VoiceOver traverses and operates buttons, checkboxes, ranges, accordions, and status;
- high-rate visual telemetry does not produce live accessibility churn;
- custom scrollbar thumbs remain absent;
- no Linux regression run is required at this phase.

## Phase 3: Search, Text, Tree, Filtering, and Scrolling

### Phase 3 Objective

Complete parity with the current Linux accessibility tree by qualifying editable Search,
dynamic Tree hierarchy, filtering, identity retirement, focus repair, and composite
scrolling on macOS.

### Search Work

1. Publish SearchInput role, accessible name, placeholder, committed value, editable
   state, focus, and bounds.
2. Preserve the existing SearchInput plus TextRun structure used by the AccessKit text
   model.
3. Publish valid UTF-8 character lengths, caret, anchor, and selection.
4. Support bounded selected-text replacement, whole-text replacement, and set-selection
   actions.
5. Keep IME preedit outside committed accessible text.
6. Keep query storage, debounce, suggestions, filtering, and generation ownership in
   Library.
7. Relate Search to the controlled Tree.
8. Publish bounded result-count and no-results status.

### Text Cases

- empty and maximum-length values;
- ASCII and multibyte UTF-8;
- combining sequences;
- bidirectional text;
- cursor and anchor at every valid boundary;
- malformed byte or character boundaries;
- collapsed and extended selections;
- replacement at current and stale generations;
- whole-text replacement;
- read-only rejection;
- payload overflow;
- horizontal clipping and scale changes;
- malformed character-length arrays;
- demonstrated macOS text-unit conversion differences.

A real macOS text-index mismatch must be handled in the Darwin adapter conversion layer
with exact fixtures. It must not change Library's UTF-8 ownership or invent a second
portable text model.

### Tree Work

1. Publish one Tree composite and ordered visible TreeItem descendants.
2. Preserve stable UUID-backed semantic identity.
3. Publish parentage, active descendant, selected and expanded state, level, position,
   and set size.
4. Preserve the existing global Tab stop and roving active-descendant policy unless
   macOS qualification demonstrates a concrete native mapping defect.
5. Route select, expand, collapse, toggle, and scroll behavior through current owners.
6. Remove filtered nodes atomically.
7. Preserve surviving identities and retire removed identities without native ID reuse.
8. Reject actions against retired, removed, or stale results.
9. Repair focus predictably when the active item disappears.
10. Publish scroll current, minimum, maximum, and supported actions on the Tree
    composite.
11. Keep the visual scrollbar thumb pointer-only.

### Native AX Evidence

The macOS evidence workflow must:

- discover Search and Tree;
- inspect Search name, placeholder, value, focus, caret, and selection;
- replace selected text;
- replace the full query;
- set a valid selection;
- reject an invalid or stale selection;
- filter the Tree;
- confirm surviving identity continuity;
- confirm removed identity retirement;
- inspect TreeItem hierarchy, level, position, set size, selected, and expanded state;
- expand, collapse, and select representative items;
- inspect Search-to-Tree relation where exposed by AX;
- observe bounded result status;
- operate composite scrolling;
- verify that acted items become visible without unrelated focus theft;
- confirm provider removal after shutdown.

### Manual Workflows

Accessibility Inspector must remain stable while:

- Search changes rapidly;
- Tree nodes are inserted and removed;
- active descendant changes;
- branches expand and collapse;
- focus moves between ordinary controls, Search, and Tree;
- the window resizes or changes display scale;
- the application loses and regains focus;
- the accessibility service begins observing after application startup;
- the application closes.

VoiceOver must:

- locate and edit Search;
- report the committed query and selection coherently;
- receive bounded result feedback;
- navigate the Tree in deterministic order;
- identify selection and expansion state;
- expand, collapse, and select representative items;
- review filtered results without stale items;
- scroll the Tree composite using the configured macOS trackpad direction and a
  `NORMAL` mouse-wheel path;
- retain a coherent reading and focus position through updates.

### Phase 3 Falsifiable Claim

A macOS accessibility client can edit and inspect Library Search, receive bounded result
feedback, navigate and operate the filtered Tree, and scroll the composite without
stale targets, malformed text ranges, focus theft, duplicate owner mutation, or
teardown failure.

### Phase 3 Exit Gate

- deterministic text, hierarchy, filtering, identity, action, and scroll tests pass on
  Apple Silicon;
- machine-readable AX evidence passes the complete current-tree matrix;
- Accessibility Inspector remains stable through rapid filtering and removal;
- VoiceOver completes Search and Tree workflows;
- stale and retired actions never mutate current state;
- scrolling reveals acted items without moving unrelated focus;
- callback and queued-event ownership remain clean under stress;
- shutdown removes the provider cleanly;
- macOS now has full parity with the current Linux accessibility surface.

## Phase 4: macOS Qualification Freeze

### Phase 4 Objective

Freeze and document the macOS parity result before returning to Linux or beginning
Windows work.

### Phase 4 Work

1. Run the complete Apple-Silicon deterministic test suite.
2. Run Julia build-driver and provider tests.
3. Run `julia tools/make.jl accesskit-abi`.
4. Run validated debug and default builds.
5. Run the complete machine-readable macOS AX evidence workflow.
6. Complete the Accessibility Inspector workflow matrix.
7. Complete the VoiceOver workflow matrix.
8. Exercise partial initialization failure and ordinary application continuation.
9. Exercise focus changes, resize, scale, late service observation, repeated sessions,
   and teardown stress.
10. Run `cmake --build --preset default --target check` on macOS.
11. Record exact versions for:
    - macOS;
    - hardware architecture;
    - AccessKit C and underlying adapter;
    - SDL;
    - Accessibility Inspector;
    - VoiceOver;
    - Odin, Julia, and compiler toolchains;
    - Euclid revision.
12. Update architecture and UI documentation.
13. Add or update the accessibility verification guide with permissions, commands,
    expected artifacts, manual workflows, and known macOS differences.
14. Update checked and generated runtime closure evidence.
15. Preserve normalized evidence and manual qualification records.

### Phase 4 Exit Gate

- all macOS phase gates pass together on one qualified revision;
- documentation matches actual ownership and lifecycle;
- native evidence is complete and version-qualified;
- unresolved speech heuristics are documented without weakening structural or action
  requirements;
- no malformed tree, stale mutation, callback race, queued-event ownership error, or
  teardown fault remains open;
- the macOS implementation is frozen for the post-parity Linux regression.

## Post-Parity Linux Regression

The Linux regression begins only after the macOS qualification freeze. It is not part
of the macOS phase-by-phase development loop.

### Required Regression

On a qualified Linux desktop environment:

1. run Odin and Julia deterministic tests;
2. run the AccessKit ABI probe;
3. run validated debug and default builds;
4. run the complete AT-SPI machine-readable evidence workflow;
5. inspect dynamic controls, Search, Tree, text, filtering, scrolling, and removal;
6. complete the agreed Orca workflow;
7. exercise focus, service activation, repeated sessions, and teardown;
8. run the canonical repository check.

### Outcome Policy

- If Linux passes, freeze the shared current-tree foundation and begin Windows parity.
- If Linux exposes a regression caused by shared extraction, repair the shared defect,
  re-run the complete Linux regression, and re-run the affected macOS qualification
  slice before proceeding.
- Do not reopen broad feature development during this repair loop.
- Do not begin Windows parity while Linux regression or affected macOS evidence is
  incomplete.

## Windows Handoff

After macOS parity and the post-parity Linux regression both pass, Windows receives its
own staging companion and parity implementation. Windows work uses the frozen shared
current-tree semantics and proves its own native lifecycle, HWND admission, UIA event
ownership, focus, coordinates, text, controls, Search, Tree, scrolling, and teardown.

After Windows parity, the complete current-tree matrix runs once across Linux, macOS,
and Windows. Only after that three-platform foundation passes does accessibility
feature development resume with Dynview and Terminal on Linux.

## Failure and Degradation Policy

| Failure | Required behavior |
| --- | --- |
| Missing or modified arm64 AccessKit artifact | Fail provider validation with exact expected identity. |
| Darwin ABI probe mismatch | Block macOS adapter enablement. |
| Missing Cocoa window property | Record typed initialization failure and continue without native accessibility. |
| Objective-C class discovery failure | Do not install the forwarder or adapter; diagnose and continue Euclid. |
| Focus-forwarder installation failure | Reject adapter admission and preserve ordinary application operation. |
| Adapter construction failure | Close callback admission, unwind partial resources, diagnose, and continue Euclid. |
| Activation without valid publication | Return no malformed tree and record rejection. |
| Invalid current translation | Preserve the last good native publication. |
| Non-null queued events | Raise exactly once on the main thread. |
| Action queue overflow | Drop the new request, record bounded pressure, and do not mutate state. |
| Stale, retired, or removed action | Reject without retargeting. |
| Invalid numeric or text payload | Reject before owner mutation. |
| Window focus change | Forward through the macOS adapter and raise returned events. |
| Window close | Stop admission, free adapter state, then destroy the SDL window. |
| Inspector instability | Stop expansion and reduce to the last known-good native tree. |
| VoiceOver discrepancy | Preserve artifacts and distinguish semantic defects from version-qualified speech behavior. |

## Inspector Failure Protocol

When Accessibility Inspector crashes, hangs, or reports malformed data:

1. stop adding controls or properties;
2. preserve the tree snapshot, action/event evidence, Euclid diagnostics, OS version,
   AccessKit version, inspector version, and reproduction steps;
3. reduce to the last known-good macOS tree;
4. reintroduce only the smallest changed record or transition;
5. classify the defect as ABI, tree structure, value validation, update completeness,
   AppKit lifecycle, queued-event ownership, coordinate conversion, or inspector
   behavior;
6. add a deterministic regression fixture when Euclid controls the defect;
7. add a native reproduction when translation fixtures cannot expose it;
8. resume expansion only after the known-good tree is stable again.

An inspector failure is not waived because VoiceOver appears to work. A VoiceOver
workflow is not considered sufficient proof of a structurally valid tree.

## Verification Matrix

| Surface | Deterministic proof | Native AX evidence | Human proof |
| --- | --- | --- | --- |
| Artifact and ABI | Manifest, hash, layout, and symbol tests | Dylib load and closure inspection | None |
| Cocoa admission | Failure-stage and ownership tests | Window/adapter discovery and removal | Inspector discovery |
| Root and button | Exact tree, update, and action tests | Role, name, focus, bounds, press | VoiceOver discovery and activation |
| Checkboxes | Toggled, disabled, and owner tests | State and press action | VoiceOver state and operation |
| Sliders/splitters | Finite range and clamp tests | Range properties and actions | VoiceOver value and operation |
| Accordion | Relation and focus-repair tests | Expanded tree and controlled panel | VoiceOver section navigation |
| Status | Coalescing and severity tests | Bounded AX updates | VoiceOver pending/completion/error feedback |
| Search | UTF-8, selection, and replacement tests | Value, caret, selection, and actions | VoiceOver edit and review |
| Tree | Identity, filtering, and active-descendant tests | Hierarchy, state, actions, and scroll | VoiceOver navigation and filtering |
| Lifecycle | Failure unwind, late callback, and event tests | Focus, service observation, provider removal | Repeated application use |

## Relevant Files

- [`sev_access2.md`](sev_access2.md) — complete accessibility program and platform
  sequencing.
- `libs/accesskit/accesskit.odin` — narrow Darwin C declarations.
- `libs/accesskit/include/accesskit.h` — authoritative tagged API and ownership
  contract.
- `libs/accesskit/bin/macos/arm64/manifest.toml` — qualified provider identity.
- `src/accessibility/` — portable protected publication, validation, IDs, action queue,
  and diagnostics.
- `src/view/native/accessibility/owner.odin` — shared adapter-facing owner records and
  diagnostics.
- `src/view/native/accessibility/unix_adapter.odin` — Unix lifecycle remaining after
  shared extraction.
- `src/view/native/accessibility/accesskit_translation.odin` — proposed shared
  AccessKit tree construction.
- `src/view/native/accessibility/action_adapter.odin` — proposed shared request copy,
  validation, and drain behavior.
- `src/view/native/accessibility/macos_adapter.odin` — proposed Darwin lifecycle,
  focus, and queued-event owner.
- `src/view/native/sdl_platform.odin` — SDL window ownership and Cocoa adapter
  admission.
- `src/view/sdl_input.odin` — host focus events forwarded through the platform owner.
- `src/view/view.odin` — complete control publication and native action drain.
- `tools/accessibility/accesskit_abi_probe.c` — native C ABI probe.
- `tools/accessibility/run_accesskit_abi_probe.jl` — host ABI driver and provider
  environment.
- `tools/accessibility/accesskit_macos_tree_probe.swift` — proposed machine-readable
  AX evidence workflow.
- `tools/accessibility/accesskit_tree_probe.py` — Linux evidence workflow used only in
  the post-parity regression.
- `tools/make.jl` — host evidence command dispatch.
- `tools/test/runtests.jl` — provider and build-driver tests.
- `cmake/EuclidTests.cmake` — deterministic and ABI test registration.
- `docs/wiki/Guides/ArchitectureSummary.md` — native owner and lifecycle architecture.
- `docs/wiki/Guides/UiSystem.md` — semantic publication and owner convergence.
- `docs/wiki/Guides/AccessibilityVerification.md` — proposed platform evidence and
  permission guide.
- `runtime-closure.cdx.json` and generated closure artifacts — checked provider and
  native dependency evidence.

## Completion Criteria

The macOS current-tree parity program is complete when all of the following are true:

1. The retained Apple-Silicon AccessKit artifact, manifest, license, symbols, ABI, and
   runtime closure validate reproducibly.
2. Euclid obtains and borrows the SDL `NSWindow` only on the main thread and only for
   the window lifetime.
3. The AccessKit focus forwarder is installed against the discovered window class and
   its process-lifetime library contract is preserved.
4. The subclassing adapter is created from valid protected publication and destroyed
   before the SDL window.
5. Every non-null macOS queued-event object is raised exactly once.
6. macOS uses the same complete AccessKit translation, native ID policy, bounded
   request copy, and display-thread validation as the existing current-tree model.
7. Native callbacks never mutate UI, SDL, GPU, Terminal, or Julia state directly.
8. Invalid staging preserves the last good native publication.
9. Buttons, checkboxes, ranges, splitters, accordions, GIF controls, labels, and status
   expose coherent native properties and actions.
10. Search exposes committed text, placeholder, caret, selection, and bounded editing
    actions without publishing IME preedit.
11. Tree exposes coherent hierarchy, active descendant, selection, expansion, set
    facts, filtering, identity retirement, and composite scrolling.
12. Stale, retired, removed, disabled, unsupported, malformed, and out-of-range actions
    never mutate current state.
13. Pointer, keyboard, and native action convergence preserves owner-side exactly-once
  mutation, and pointer scrolling preserves SDL's per-event system/device direction.
14. Machine-readable AX evidence passes the complete current-tree matrix.
15. Accessibility Inspector remains stable through dynamic updates and teardown.
16. VoiceOver completes the representative ordinary-control, Search, Tree, and scroll
    workflows.
17. Partial accessibility failure does not prevent ordinary Euclid operation.
18. Documentation, permission instructions, provider closure, and evidence identify
    exact qualified versions.
19. The complete macOS repository gate passes on the qualified Apple-Silicon host.
20. The subsequent complete Linux regression passes before Windows parity begins.

## Final Recommendation

Approve the macOS parity program as four bounded native stages followed by one Linux
regression gate.

The governing sequencing rule is:

> Finish and freeze macOS parity first. Then test Linux once. Then implement Windows
> parity. Then test all three platforms. Only after that foundation passes should new
> accessibility surfaces resume.

Within macOS, maintain one known-good native tree and expand only after the current
Cocoa lifecycle, queued-event ownership, action path, and assistive-technology workflow
are proven. That gives Euclid useful intermediate checkpoints without turning platform
bring-up into permanent simultaneous development across operating systems.
