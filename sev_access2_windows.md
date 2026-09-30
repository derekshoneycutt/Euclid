# Windows Native Accessibility Parity for Euclid

## Proposal Status

This is the Windows implementation staging companion to
[`sev_access2.md`](sev_access2.md) and [`sev_access2_macos.md`](sev_access2_macos.md).
It begins from the accessibility behavior already implemented through the current
ordinary controls, Search, Tree, basic text, and composite scrolling work. Its purpose
is to bring that complete pre-Dynview and pre-Terminal surface to Windows 11 x64 through
AccessKit C 0.23.1 and UI Automation, with intermediate gates that isolate provider
integrity, hidden-window admission, adapter lifetime, controls, text, dynamic hierarchy,
and teardown before declaring parity.

Phase 0 was implemented and validated on 2026-09-30. The repository now verifies the
retained provider bytes on Windows, declares the narrow subclassing ABI, links every
required Windows export in the host probe, stages the validated DLL beside release and
debug executables, and proves adjacent loading with the source provider directory
removed from `PATH`.

Phase 1 implementation and automated qualification completed on 2026-09-30. Windows
now creates SDL's HWND hidden, commits a complete rooted publication before attaching
the AccessKit subclassing adapter, shows the window once after admission succeeds or
fails, routes changed generations and bounded actions, raises transferred queued events
exactly once, and frees the adapter before SDL destroys the HWND. The
`accessibility-windows` command passed two complete UIA sessions with one Restart
Invoke, owner-observed reset, focus gain and loss, provider removal, and clean repeated
teardown. Accessibility Insights remains a later manual Windows parity gate; this
Phase 1 record does not claim full Windows parity.

The macOS implementation is complete through its current qualification workflow, with
version-qualified native action limitations recorded separately. Windows now becomes
the active accessibility development platform. Linux and macOS remain behavioral
references, not simultaneous implementation targets. Their complete native regression
work runs once after the Windows parity gate rather than after every Windows increment.

The recommendation is:

> First prove the retained Windows AccessKit payload, ABI, exports, and runtime loading.
> Then create SDL's HWND hidden, publish one complete rooted tree, attach AccessKit's
> subclassing adapter before the first show or focus, and prove one real button through
> UI Automation. Expand through ordinary controls and status, then qualify Search,
> text, Tree, filtering, identity retirement, and composite scrolling. Declare Windows
> parity only after deterministic tests, repeated machine-readable UIA sessions,
> Accessibility Insights review, clean teardown, and the complete repository gates pass.

## Scope

### Required Parity Surface

Windows parity means the application exposes and operates the complete accessibility
surface already projected through the shared AccessKit translation:

- one synthetic application root;
- complete ordered control hierarchy;
- stable qualified semantic identities mapped to monotonic session-local native IDs;
- host focus and semantic focus;
- complete changed-node publication and identical-frame suppression;
- buttons and native activation;
- checkboxes and toggled state;
- sliders and splitters with finite range facts, orientation, and actions;
- accordion headers, panels, expanded state, and controls relations;
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
- clean partial-construction unwind and teardown;
- provider removal after native window destruction;
- developer and direct executable loading without a manually prepared AccessKit path.

Parity does not require identical UIA, AT-SPI, and NSAccessibility object trees. It
requires the same authored meaning, owner behavior, identity policy, validation, and
lifetime guarantees, expressed through the native conventions and capabilities of the
qualified adapter version.

### Qualified Target

The qualified target for this program is Windows 11 x64 on an x86-64 host.

The repository retains only an x86-64 MSVC Windows payload for AccessKit C 0.23.1.
Windows 10 and Windows on ARM require independent native execution and are outside this
staging program. The qualification record must name the exact Windows 11 build rather
than making an unversioned Windows claim.

### Required Native Evidence

The required Windows evidence sources are:

- deterministic Odin and Julia tests;
- the native AccessKit C ABI, export, and ownership probe;
- release and debug build/runtime-loading checks;
- a machine-readable UI Automation evidence workflow in a logged-in desktop session;
- Accessibility Insights for Windows.

Narrator and Voice Access remain part of later full assistive-technology qualification.
They do not block this current-tree engineering parity milestone. Windows Inspect is a
useful diagnostic fallback but is not a second required manual gate.

### Non-Goals

This staging program does not implement or qualify:

- Dynview document accessibility;
- mathematical fallback semantics;
- Terminal accessibility;
- Narrator workflows;
- Voice Access workflows;
- Windows 10 support claims;
- Windows on ARM support claims;
- custom UI Automation providers authored by Euclid;
- a manual `WM_GETOBJECT` forwarding path while the subclassing adapter remains viable;
- Julia-owned native accessibility objects;
- native custom scrollbar thumbs;
- a complete portable Julia distribution or launcher;
- identical native object trees, pattern sets, events, or spoken wording across
  AT-SPI, NSAccessibility, and UI Automation.

## Decision Requested

Approve the following Windows staging decisions before implementation begins:

| Decision | Recommendation |
| --- | --- |
| Delivery order | Complete Windows parity now, then run one full Linux, macOS, and Windows regression matrix before Dynview or Terminal work. |
| Qualified target | Windows 11 x64 only. |
| AccessKit release | Retain AccessKit C 0.23.1, schema 0.25.1, and `accesskit_windows` 0.35.1 until evidence requires a version change. |
| Native adapter | Use the AccessKit Windows subclassing adapter around SDL's borrowed HWND. |
| Window admission | Create the Windows SDL window hidden and attach the adapter before the first show or focus. |
| Initial publication | Commit one complete validated publication before adapter construction and before showing the window. |
| Failure behavior | Show the ordinary window even if accessibility publication, HWND lookup, or adapter creation fails. |
| Retry policy | Do not retry subclass installation after the HWND has become visible or focused. |
| HWND ownership | Borrow SDL's HWND only for the SDL window lifetime; never destroy or retain it as Euclid-owned storage. |
| Message handling | Let the subclassing adapter own `WM_GETOBJECT`; do not add a second WndProc or bare-adapter route without evidence. |
| Focus | Let the subclass observe HWND focus and continue publishing semantic focus in complete tree updates. |
| Queued events | Raise every non-null AccessKit Windows queued-event object exactly once. |
| Callback boundary | Copy bounded requests, free AccessKit ownership exactly once, and return without entering SDL, Julia, or UI owners. |
| Shared policy | Keep tree translation, identity, request copying, and action validation platform-neutral. |
| Coordinates | Begin with the shared logical-to-physical scale contract and change only the Windows boundary after measured UIA evidence. |
| DLL deployment | Stage the manifest-validated `accesskit.dll` beside release and debug executables. |
| Portable packaging | Leave the full Julia/runtime portable layout to `staging_windowsportable_discussion.md`. |
| Native automation | Add a logged-in-session UIA evidence command with repeated-session teardown checks. |
| Manual gate | Require Accessibility Insights; defer Narrator and Voice Access. |
| Expansion stop | Do not expand beyond one button while root validity, action ingress, event ownership, focus, bounds, or teardown remain unproven. |

## Existing Foundation

Euclid already has the portable and owner-side facilities needed for Windows parity:

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
- prepared control geometry and finite numeric values;
- editable-text descriptors and UTF-8 character mapping;
- Tree hierarchy, filtering, active descendant, set position, and composite scroll
  facts;
- Linux AT-SPI native evidence through the current surface;
- macOS AX native evidence through the current surface, with adapter limitations
  recorded separately;
- repository-owned AccessKit C 0.23.1 Windows x86-64 DLL and import library;
- a schema-versioned Windows manifest with hashes, licenses, notices, target ABI, and
  declared native dependencies;
- Windows linker and runtime-directory resolution in the build configuration;
- a host ABI probe covering common C layouts and basic node ownership.

The shared implementation is already separated from platform admission:

- `src/accessibility/` owns publication, validation, IDs, retirement, and the action
  queue;
- `src/view/native/accessibility/accesskit_translation.odin` owns common AccessKit node
  and tree construction;
- `src/view/native/accessibility/action_adapter.odin` owns common publication and
  display-thread action validation;
- `src/view/native/accessibility/owner.odin` owns callback-visible adapter state and
  content-free diagnostics;
- `src/view/view.odin` drains validated actions and converges them through existing UI
  owner commands;
- `src/view/native/sdl_platform.odin` owns the SDL window session and platform adapter
  lifetime.

The Windows implementation must preserve those boundaries. It must not copy the shared
translator into a Windows file or introduce UIA-specific semantics into UI owners.

## Current Windows Gaps

Phase 1 supplies native admission diagnostics, hidden HWND creation, pre-show adapter
attachment, publication and action dispatch, deterministic teardown, and automated UIA
root and Restart-button evidence. The remaining work begins with Phase 2:

- ordinary controls, status, and relation evidence;
- Search value and text-selection operations;
- Tree hierarchy, filtering, identity retirement, and scrolling;
- DPI and resize qualification;
- Accessibility Insights review and the final Windows qualification record.

## Windows Native Contracts

### Retained Provider and ABI

The retained payload is AccessKit C 0.23.1 with AccessKit schema 0.25.1 and
`accesskit_windows` 0.35.1. The Windows manifest identifies an x86-64 MSVC DLL and import
library and records their SHA-256 hashes.

Before enabling the Windows adapter, Euclid must prove on the Windows host that:

- the manifest identity and every retained file hash are valid;
- the C header and import library agree on the required Windows exports;
- the common enum and structure layouts match the Odin declarations;
- one node can be created, queried, and freed through the retained DLL;
- the subclassing constructor, update, queued-event raise, and free symbols link;
- the probe executable loads the exact retained DLL rather than another `accesskit.dll`
  found earlier on `PATH`.

The Windows binding should declare only the subclassing surface used by Euclid. The
bare adapter and optional `LRESULT` structures should remain undeclared until an
empirical failure forces a manual `WM_GETOBJECT` design.

### Runtime DLL Deployment

The application links against `accesskit.lib`, so the Windows loader must resolve
`accesskit.dll` before Odin startup. Application code cannot repair that search path
after process entry.

Repository-driven commands currently prepend the provider directory to `PATH`. That is
useful for tests but insufficient for direct developer launch. A successful Windows
build must therefore copy the manifest-validated DLL beside the built executable:

- `bin/accesskit.dll` beside `bin/euclid.exe`;
- `.build/debug/accesskit.dll` beside `.build/debug/euclid.exe`.

The staged bytes must match the manifest hash. A stale adjacent DLL is a build failure,
not a fallback provider. This staging decision concerns AccessKit discovery in the
normal developer environment; it does not claim that every Julia, JLL, SDL, or Visual
C++ dependency needed for a portable ZIP is now self-contained.

### SDL Window and HWND Ownership

SDL creates and owns the application window. On Windows,
`SDL_GetWindowProperties` exposes `SDL_PROP_WINDOW_WIN32_HWND_POINTER`, a borrowed HWND
associated with the SDL window.

Euclid must:

- query the property only after `SDL_CreateWindow` succeeds;
- query it on the display thread that owns the window;
- reject a missing property with a typed accessibility diagnostic;
- treat the HWND as borrowed;
- never call `DestroyWindow` on it;
- never use it after `SDL_DestroyWindow`;
- free the AccessKit adapter before destroying the SDL window.

The exact SDL Odin constant name must be verified against the active SDL binding during
implementation. The C property contract, not an assumed binding spelling, is
authoritative.

### Hidden-Window Admission

`accesskit_windows_subclassing_adapter_new` must be called on the HWND-owning thread
before the window has been shown or focused. The constructor may panic if the window is
already visible.

Windows window creation must therefore use SDL's hidden-window flag. The initial
sequence is:

1. initialize SDL video and events;
2. create the Windows SDL window hidden;
3. obtain the borrowed HWND;
4. build and commit one complete validated accessibility publication;
5. construct the AccessKit subclassing adapter;
6. show the SDL window exactly once;
7. continue GPU, input, publication, and action service under the normal display owner.

If GPU swapchain admission requires a visible window in the qualified SDL/Direct3D 12
combination, the implementation must preserve steps 3 through 6 and move only the
smallest necessary GPU operation. It must not show the window before AccessKit
attachment merely to preserve the current function order.

Accessibility failure must not leave the application permanently hidden. Missing HWND,
invalid initial publication, constructor failure, or injected test failure must record
the stage, close callback admission as appropriate, and show the ordinary window once.
Subclass installation must not be retried after that show because the precondition no
longer holds.

### Subclassing Adapter

The subclassing adapter is preferred because it matches SDL's HWND ownership and owns
the Win32 message integration required to expose UI Automation. Euclid should not
replace SDL's WndProc or manually forward `WM_GETOBJECT` while this path works.

The native adapter receives:

- the borrowed HWND;
- the shared activation callback and adapter owner;
- the shared action callback and adapter owner.

The first complete publication must already be current when the constructor is called.
An activation caused during or immediately after window display must never observe an
empty or partially staged tree.

### Queued Native Events

The Windows subclassing update function returns
`accesskit_windows_queued_events *`. A non-null return transfers work that must be
raised through `accesskit_windows_queued_events_raise`. Raising also frees the event
storage.

Every update call site must satisfy exactly-once ownership:

1. request an update only for a newly committed publication generation;
2. retain the returned pointer only in a local variable;
3. if non-null, raise it exactly once;
4. never separately free, duplicate, inspect, or cache it;
5. never abandon it during an error path;
6. record only content-free update and event diagnostics.

The operation-injected lifecycle tests must prove zero raises for a null return and one
raise for every non-null return.

### Focus

The Windows subclassing API does not expose the separate host-focus update function
available on the bare Windows adapter. The subclass observes HWND focus messages.

Euclid must continue to:

- retain SDL's current window-focus state;
- publish that state in each complete portable tree;
- choose the synthetic root as AccessKit focus when the host window is unfocused;
- choose the focused control only when both host and semantic focus are current;
- avoid adding a fictitious subclassing focus API;
- verify UIA keyboard focus during focus gain, focus loss, filtering, and removal.

If native evidence demonstrates a focus defect, investigate the subclassing adapter and
SDL message flow before changing the portable focus model.

### Coordinates and DPI

The shared publication carries logical SDL control bounds and an explicit scale. The
shared AccessKit translator currently converts those bounds to physical coordinates.
Windows UIA reports screen-space bounding rectangles, while AccessKit's Windows adapter
owns the HWND-relative native conversion.

The initial Windows implementation must reuse the shared scale contract. It must then
measure representative controls at:

- 100 percent scale;
- 150 percent scale;
- 200 percent scale;
- initial placement;
- after resize;
- after moving to a monitor with a different scale, when available.

Any demonstrated origin, client-area, non-client-area, or scale mismatch must be fixed
at the Windows adapter or SDL input boundary with deterministic fixtures. Portable owner
geometry must not change solely to compensate for one platform adapter.

### Callback and Thread Boundary

The Windows action handler may run away from the display thread. Native callbacks may
only:

- observe callback-admission state;
- copy the action, target, publication generation, and bounded payload;
- enqueue the copied request or record rejection;
- free the transferred AccessKit action request exactly once;
- return without waiting for display mutation.

Callbacks must not:

- enter Julia;
- call SDL or Win32 window APIs;
- mutate UI owners;
- retain AccessKit pointers;
- borrow frame-owned semantic storage;
- log editable user text;
- wait synchronously for the display thread.

The existing protected publication and action queue are the callback boundary. Windows
must reuse them unchanged unless a deterministic shared defect is demonstrated.

### COM and UI Automation Lifetime

UI Automation clients may retain elements after a tree update, node removal, or window
closure. Euclid must treat those retained client references as expected external
behavior.

The adapter lifetime must guarantee:

- retired native IDs are never reused in one window session;
- a removed target cannot mutate a replacement node;
- an action carrying an old publication generation is rejected;
- callback admission closes before native adapter release;
- accepted queued actions remain bounded and drainable according to current shutdown
  policy;
- the adapter is freed before the HWND;
- retained UIA elements become unavailable without crashing the application or client;
- repeated create/show/update/close sessions do not leak subclass state into the next
  HWND.

### Failure and Degradation

Accessibility is an important subsystem but must not corrupt or prevent ordinary
application operation. Every Windows-specific failure must be typed and content-free.

Required stages include:

- provider validation;
- DLL staging;
- HWND property lookup;
- pre-show contract validation;
- adapter construction;
- native update;
- queued-event raising;
- callback rejection;
- teardown.

After a failed current publication, the last good native publication remains current.
After initial admission failure, the window is shown without a native provider and no
unsafe retry occurs.

## Implementation Phases

## Phase 0: Windows Provider, ABI, and Runtime Loading

### Phase 0 Objective

Prove that the retained Windows AccessKit artifacts, C header, Odin declarations,
linker path, runtime DLL, and executable deployment all describe one coherent provider
before any HWND adapter is enabled.

**Implementation status:** complete on the qualified Windows 11 x64 development host.
The ABI probe reports `windows_symbols=1` and `windows_module_adjacent=1`; release and
debug outputs contain the manifest-matching DLL, and both executable `--help` loader
smokes pass with the source provider directory removed from `PATH`.

### Phase 0 Work

1. Add opaque `Windows_Subclassing_Adapter` and `Windows_Queued_Events` types to the
   Odin AccessKit binding.
2. Add declarations for:
   - `accesskit_windows_subclassing_adapter_new`;
   - `accesskit_windows_subclassing_adapter_update_if_active`;
   - `accesskit_windows_subclassing_adapter_free`;
   - `accesskit_windows_queued_events_raise`.
3. Preserve the common callback signatures already used by Linux and macOS.
4. Do not add the unused bare adapter and `WM_GETOBJECT` declarations.
5. Extend the C ABI probe with a `windows_symbols=1` record covering every required
   Windows function.
6. Make the Julia probe driver resolve the import library from the validated manifest
   and the runtime DLL from provider identity.
7. Make Windows probe compilation deterministic with the selected clang/MSVC-compatible
   toolchain and Windows SDK headers.
8. Add Julia tests for Windows target identity, import-library resolution, runtime
   environment, and probe command construction.
9. Add a post-build helper that copies the validated DLL beside release and debug
   executables.
10. Verify the staged file hash and reject a stale or foreign adjacent DLL.
11. Include the staged provider in cleanup and generated runtime evidence without
    duplicating its logical SBOM identity.

### Deterministic Tests

Phase 0 tests must prove:

- the Windows manifest accepts exactly x86-64 MSVC identity;
- missing, modified, or ambiguously duplicated artifacts fail validation;
- the import-library path comes from the `import-library` manifest role;
- the runtime path comes from the `runtime` manifest role;
- the probe links every required Windows symbol;
- common C and Odin structure sizes still agree;
- node creation/query/free succeeds;
- release and debug staging use the corresponding executable directory;
- a staged DLL hash equals the retained manifest hash;
- a second build replaces a stale staged DLL deterministically;
- direct launch does not require the AccessKit source directory on `PATH`.

### Phase 0 Native Evidence

Run the ABI probe in an environment where no unrelated `accesskit.dll` is present on
`PATH`. Record the loaded module path or otherwise prove that the probe consumed the
retained runtime. Run release and debug executable loader smoke checks with the source
provider directory removed from `PATH` while preserving the rest of the supported
developer runtime environment.

### Phase 0 Falsifiable Claim

> On Windows 11 x64, the tagged C header, Odin declarations, import library, retained
> DLL, staged DLL, and required subclassing symbols form one verified AccessKit C
> 0.23.1 provider, and AccessKit discovery does not depend on a manually added source
> directory.

### Phase 0 Exit Gate

Phase 0 is complete only when:

- manifest and hash tests pass;
- the Windows ABI/export/ownership probe passes with `windows_symbols=1`;
- release and debug builds link;
- both executable directories contain the exact validated DLL;
- the loader smoke test proves the adjacent DLL is used;
- no Windows adapter code is enabled against an unproven provider.

## Phase 1: Hidden HWND Admission, Root, Button, and Teardown

Automated implementation and qualification completed on 2026-09-30. The retained
evidence is `.build/accessibility-windows/uia.json`; manual Accessibility Insights
review remains part of the final Windows parity gate.

### Phase 1 Objective

Prove the complete native lifetime with the smallest useful UIA tree: create one hidden
SDL window, commit one rooted publication, attach the subclassing adapter, show the
window, discover one real button, execute one action round trip, and remove the provider
cleanly.

### Phase 1 Work

1. Add typed Windows failure stages and synchronized diagnostics to the adapter owner.
2. Add an operation-injected Windows adapter core for deterministic lifecycle tests.
3. Add the build-tagged real Windows adapter implementation.
4. Change Windows SDL creation to include the hidden flag without changing Linux or
   macOS flags.
5. Retain explicit one-session state for whether accessibility admission was attempted
   and whether the window was shown.
6. Obtain the borrowed HWND from SDL window properties.
7. Commit the first complete control publication before constructing the adapter.
8. Construct the adapter on the display/HWND-owning thread.
9. Show the window exactly once after success or failure.
10. Publish later generations only when semantic facts change.
11. Raise each returned queued-event object exactly once.
12. Route native actions through the existing bounded callback queue.
13. Drain and validate actions on the display thread.
14. Close callback admission and free the adapter before GPU and window teardown.

### Deterministic Lifecycle Tests

The operation-injected tests must cover:

- nil owner and nil HWND rejection;
- invalid or absent initial publication;
- constructor failure;
- typed failure stage and count;
- callback closure after failed admission;
- initial activation from a complete current publication;
- one adapter per window session;
- generation-based update suppression;
- one update for a changed publication;
- zero event raises for a null update result;
- exactly one event raise for a non-null update result;
- action queue availability through the public Windows drain API;
- close-before-free ordering;
- one native free;
- repeated destroy safety;
- activation rejection after close.

SDL/platform tests must cover:

- Windows-only hidden flag selection;
- HWND lookup after window creation;
- publication-before-admission ordering;
- admission-before-show ordering;
- one-shot show behavior;
- show after accessibility failure;
- no post-show admission retry;
- adapter destruction before `SDL_DestroyWindow`.

### Phase 1 Native Evidence

The first native evidence workflow must prove:

- the process starts without manual AccessKit path setup;
- the window becomes visible after admission;
- UIA discovers one Application root;
- the root contains one real Restart button;
- role/control type, name, enabled state, focusability, and bounds are coherent;
- UIA Invoke reaches the existing Restart owner exactly once;
- the resulting semantic update is observable;
- focus gain and loss do not expose a stale focused element;
- closing the window removes the provider;
- a second complete session succeeds in the same environment.

### Phase 1 Falsifiable Claim

> A Windows UIA client can discover and invoke one real Euclid button through a rooted
> AccessKit tree attached before the HWND is shown, while callbacks remain bounded and
> teardown removes the provider without stale mutation or faults.

### Phase 1 Exit Gate

Phase 1 is complete only when:

- all deterministic lifecycle and SDL ordering tests pass;
- the hidden-window constructor contract is demonstrated on the qualified host;
- root and button UIA evidence passes twice;
- action mutation occurs exactly once through the existing owner;
- provider removal and repeated teardown pass;
- accessibility failure still produces an ordinary visible application window;
- no inspector or application crash remains unexplained.

## Phase 2: Ordinary Controls, Relations, Ranges, and Status

### Phase 2 Objective

Expose every current ordinary control through the shared translator and prove its UIA
properties, patterns, state updates, actions, bounds, and owner convergence before
introducing editable text and dynamic Tree topology.

### Work Order

Implement and verify in this order:

1. remaining buttons;
2. accordion headers and controlled panels;
3. checkboxes;
4. sliders and splitters;
5. enabled and disabled GIF controls;
6. pending, busy, and status behavior;
7. ordinary focus transitions and removals.

### Control Requirements

Buttons must expose a coherent UIA Button control type and Invoke behavior. Native
invocation must route through the same owner command as pointer and keyboard activation.

Checkboxes must expose Toggle behavior, current checked state, enabled state, focus,
and complete state updates after mutation.

Sliders and splitters must expose finite minimum, maximum, current, step, orientation,
and supported range actions. NaN, infinity, and out-of-range requests must be rejected
before owner mutation.

Accordion headers must expose activation, expanded state where supported by the adapter,
and their relationship to controlled panels. Panels remain structural and do not become
extra tab stops.

Status nodes must expose authored status text and the current live/busy facts without
turning frame-rate or rapidly changing statistics into high-frequency announcements.

Disabled controls must retain stable names and roles while rejecting unsupported native
mutation. Availability explanations must not be encoded by continually changing the
control identity.

### Phase 2 Native Evidence

The UIA probe must record, for representative controls:

- runtime identity within the session;
- parent and ordered children;
- control type and name;
- enabled, keyboard-focusable, focused, toggled, expanded, and busy facts where
  natively observable;
- supported control patterns;
- bounding rectangle;
- relation targets where UIA exposes them;
- action result and resulting updated state;
- disappearance after owner removal or window closure.

Accessibility Insights must inspect the same representative controls and event stream.
Any difference between shared AccessKit facts and the Windows adapter's UIA mapping must
be recorded against `accesskit_windows` 0.35.1.

### Phase 2 Required Cases

- button Invoke;
- checkbox Toggle in both directions;
- slider increment, decrement, and direct finite value set;
- rejected out-of-range value;
- accordion activation and panel relation;
- disabled control rejection;
- pending/busy transition;
- semantic focus movement;
- bounds after resize and at 100, 150, and 200 percent scale;
- retained UIA element after control removal;
- repeated window teardown.

### Phase 2 Falsifiable Claim

> Windows UIA exposes the current ordinary Euclid controls with coherent roles,
> patterns, state, relations, ranges, focus, and bounds, and every accepted action
> converges through the same display-owned mutation path used by pointer and keyboard
> input.

### Phase 2 Exit Gate

Phase 2 is complete only when:

- deterministic shared and Windows lifecycle tests pass;
- the automated UIA ordinary-control matrix passes twice;
- DPI and resize bounds are empirically correct or corrected at the Windows boundary;
- invalid values and disabled actions cannot mutate owners;
- Accessibility Insights finds no malformed hierarchy, invalid property, event storm,
  or teardown fault;
- every adapter limitation is explicitly version-qualified.

## Phase 3: Search, Text, Tree, Filtering, and Scrolling

### Phase 3 Objective

Qualify the complete dynamic pre-Dynview/Terminal surface: editable Search, text value
and selection, Search-to-Tree relation, Tree hierarchy and actions, filtering, stable
identity, retirement, and composite scrolling.

### Search Work

Search must expose:

- Search control type;
- stable accessible name;
- placeholder;
- committed UTF-8 value;
- focusability and native focus;
- caret and selection;
- whole-value replacement;
- selected-text replacement when the adapter dispatches it;
- explicit text-selection requests;
- the relation to the controlled Tree;
- no IME preedit or secret text.

Native text requests must copy payloads into bounded queue storage before freeing the
AccessKit request. Invalid UTF-8, oversized payloads, stale generations, removed
targets, and invalid character boundaries must be rejected without changing Search.

### Text Cases

The evidence workflow must cover:

- empty Search with placeholder;
- ASCII replacement;
- multibyte UTF-8 replacement;
- collapsed caret selection;
- forward and backward selection;
- selected-text replacement;
- invalid range rejection;
- payload-capacity rejection through deterministic tests;
- focus loss and restoration;
- filtering after committed text mutation.

UIA uses UTF-16 text units at its public boundary while Euclid stores validated UTF-8
and AccessKit carries character indices. The adapter owns native conversion. Tests must
use non-ASCII text to detect unit mismatches instead of assuming byte, scalar, UTF-16,
or grapheme equivalence.

### Tree Work

Tree and TreeItem publication must expose:

- one labelled Tree root;
- ordered nested TreeItem children;
- active descendant;
- selected state distinct from focus;
- expanded state for branch items;
- level, position in set, and set size;
- selection action;
- expand and collapse actions;
- stable identity for surviving items;
- retirement for removed filtered items;
- composite vertical range and scrolling actions;
- no native custom scrollbar-thumb nodes.

Filtering must preserve current surviving identities, remove excluded IDs from the live
registry, prevent retained stale UIA elements from mutating replacements, repair focus
through the existing semantic policy, and publish one coherent resulting generation.

### Native UIA Evidence

Extend `tools/accessibility/accesskit_windows_tree_probe.cs`, the .NET 10 file-based C#
probe compiled against inbox UI Automation managed assemblies.

The probe must:

- build or require the debug executable explicitly;
- launch the established accessibility acceptance scenario;
- identify Euclid by process and HWND rather than a global label alone;
- wait for activation without unbounded sleeps;
- traverse a bounded UIA subtree;
- normalize control types, names, states, patterns, relations, and rectangles;
- invoke representative ordinary actions;
- replace Search text and manipulate selection;
- filter the Tree;
- preserve and compare surviving runtime identity;
- retain a removed element and prove it becomes unavailable;
- select and expand or collapse representative items;
- operate composite scrolling and observe owner republish;
- close the native window;
- require provider disappearance;
- run two complete sessions;
- emit bounded schema-versioned JSON.

The evidence artifact belongs at `.build/accessibility-windows/uia.json`. It must record:

- schema version;
- exact Windows build and architecture;
- AccessKit C, schema, and Windows adapter versions;
- SDL version;
- display scale used by each session;
- session count;
- repeated teardown result;
- normalized control and action outcomes;
- content-free diagnostics;
- explicit adapter limitations;
- final pass or failure status.

### Manual Workflow

Accessibility Insights must verify:

- Euclid Application root;
- ordered representative hierarchy;
- Restart button;
- Settings accordion and panel relation;
- Display FPS checkbox;
- Maximum Dust particles slider;
- Search value, placeholder, focus, and selection;
- Search-to-Tree relation;
- Tree hierarchy, selected and expanded states, and structural positions;
- dynamic filtering and events;
- composite scrolling;
- representative bounds at multiple scales;
- clean disappearance after closing the native window.

Narrator and Voice Access observations may be recorded opportunistically but cannot
replace the required automated UIA evidence or Accessibility Insights gate.

### Phase 3 Falsifiable Claim

> On the qualified Windows 11 x64 host, UI Automation can inspect and operate Search,
> text selection, Tree hierarchy, filtering, selection, expansion, identity retirement,
> and composite scrolling through the existing Euclid owners without malformed data,
> stale mutation, callback faults, or teardown faults.

### Phase 3 Exit Gate

Phase 3 is complete only when:

- every deterministic text, action, identity, and lifecycle test passes;
- two complete UIA evidence sessions pass;
- Search and Tree native actions reach owners exactly once;
- multibyte text and selection units are correct;
- surviving and retired identities behave correctly;
- composite scrolling produces a positive owner update;
- retained stale elements cannot mutate current controls;
- Accessibility Insights review passes;
- provider disappearance and repeated teardown pass;
- unsupported adapter behavior is recorded rather than silently waived.

## Phase 4: Windows 11 x64 Qualification Freeze

### Phase 4 Objective

Freeze one reproducible Windows parity candidate, run every deterministic and native
gate, record the exact environment and known adapter differences, and stop Windows
implementation before beginning new Dynview or Terminal accessibility work.

### Phase 4 Work

1. Run the focused native accessibility package tests.
2. Run the complete Odin and Julia suites.
3. Run the analyzer regression suite and canonical repository check.
4. Run the Windows AccessKit ABI/export/ownership probe.
5. Build debug and default artifacts.
6. Verify adjacent AccessKit DLL hashes and loader behavior.
7. Run two complete automated UIA sessions.
8. Complete Accessibility Insights review.
9. Record the exact Windows build, architecture, AccessKit versions, SDL version, Odin
   version, Julia version, compiler, CMake, Accessibility Insights version, and Euclid
   commit.
10. Record generated evidence paths and hashes.
11. Classify every discrepancy as a Euclid defect, AccessKit adapter limitation, UIA
   client limitation, or unresolved blocker.
12. Regenerate the wiki and runtime closure artifacts through repository commands.

### Phase 4 Exit Gate

The Windows parity freeze is complete only when:

- the candidate is identified by one committed Euclid revision;
- all deterministic tests and analyzers pass;
- the ABI probe reports `windows_symbols=1`;
- release and debug builds pass;
- direct developer launch resolves the staged AccessKit DLL;
- two native UIA sessions pass with repeated teardown;
- Accessibility Insights review is complete;
- no malformed tree, stale mutation, callback race, event ownership fault, DPI defect,
  or teardown crash remains open;
- every version-specific limitation is documented without overstating parity;
- generated documentation and runtime closure evidence are current.

## Post-Parity Cross-Platform Regression

### Required Regression

After the Windows freeze, run one complete regression pass on each qualified host:

**Linux**

- complete deterministic suites and analyzer gates;
- debug and default builds;
- AccessKit ABI probe;
- `accessibility-tree` AT-SPI evidence;
- representative inspector and screen-reader checks required by the current Linux
  qualification policy.

**macOS**

- complete deterministic suites and analyzer gates;
- debug and default builds;
- AccessKit ABI probe;
- `accessibility-macos` AX evidence;
- existing Accessibility Inspector and VoiceOver qualification checks;
- confirmation that Windows work did not alter recorded macOS adapter limitations.

**Windows**

- complete deterministic suites and analyzer gates;
- debug and default builds;
- AccessKit ABI/export probe;
- adjacent DLL loader smoke;
- `accessibility-windows` UIA evidence;
- Accessibility Insights review.

### Outcome Policy

A shared regression reopens the owning shared phase. A platform-only regression reopens
that platform's adapter or evidence phase. No new Dynview or Terminal accessibility
work begins while any platform has a malformed tree, stale action path, callback race,
event ownership failure, or teardown fault.

Version-qualified limitations may remain documented only when:

- Euclid publishes valid shared facts;
- the owner path is deterministically proven;
- the native adapter demonstrably cannot expose or dispatch the behavior;
- the limitation does not corrupt the tree or create unsafe mutation;
- the qualification record does not claim the unsupported native behavior passed.

## Failure and Degradation Policy

Windows accessibility failures must be diagnosable without publishing user content or
preventing ordinary Euclid use.

Required behavior:

- invalid provider identity aborts the build or probe before adapter enablement;
- failed DLL staging aborts the build artifact rather than selecting another DLL;
- missing HWND records one typed failure and still shows the ordinary window;
- invalid first publication prevents native admission and still shows the window;
- constructor failure closes callback admission and still shows the window;
- invalid later publication preserves the last good native tree;
- update failure does not transfer or abandon a queued-event pointer;
- queue overflow rejects the request without mutation;
- stale, unknown, removed, disabled, unsupported, or invalid actions do not mutate
  owners;
- teardown closes ingress before native free;
- native free precedes HWND destruction;
- repeated destroy remains harmless;
- diagnostics contain counts, stages, statuses, and identities only where non-sensitive.

Accessibility initialization is not retried automatically after the window is visible.
A future explicit window recreation may create a fresh adapter session with a new HWND
and native ID registry.

## UIA Failure Protocol

If Accessibility Insights or the automated probe hangs, crashes, reports invalid data,
or retains an apparently live element after teardown:

1. stop expansion to the next control family;
2. preserve the smallest failing tree and exact Windows/AccessKit/UIA versions;
3. rerun with the static root and one button;
4. determine whether failure begins at admission, activation, translation, update,
   action callback, queued-event raising, or teardown;
5. inspect publication validation and lifecycle diagnostics without logging text;
6. reproduce with two sessions to distinguish per-HWND state from process state;
7. test retained UIA references across update, removal, and close;
8. compare the same shared publication in deterministic AccessKit translation tests;
9. classify the defect before adding a workaround;
10. fix the smallest owning boundary and rerun the same native case.

Do not broaden role mappings, remove properties, reuse native IDs, disable validation,
or bypass the action queue merely to make one client stop failing.

## Verification Matrix

| Layer | Required verification | Blocking failure |
| --- | --- | --- |
| Provider identity | Windows manifest, target, artifact roles, licenses, notices, SHA-256 | Any mismatch or unverified fallback |
| C/Odin ABI | Common layouts, ownership, node smoke, Windows subclassing exports | Any mismatch, missing export, or wrong DLL |
| Runtime loading | Adjacent release/debug DLL, hash equality, source path absent from `PATH` | Loader failure or foreign DLL |
| Publication | Rooted hierarchy, UTF-8, finite bounds/ranges, capacity, last-good preservation | Invalid or partial current tree |
| Native IDs | Monotonic allocation, continuity, retirement, no session reuse | Duplicate, dangling, or reused ID |
| Admission | Hidden HWND, publication before adapter, adapter before show/focus | Visible/focused precondition violation |
| Updates | Complete changed records, identical-generation suppression | Partial record or event storm |
| Queued events | Exactly one raise for each non-null pointer | Leak, double raise, or abandoned event |
| Actions | Bounded copy, free once, display-thread validation, owner convergence | Callback mutation, stale mutation, or ownership fault |
| Ordinary controls | UIA types, names, states, patterns, ranges, relations, bounds | Missing required behavior or malformed properties |
| Search/text | Value, placeholder, UTF-8, selection, replacement, invalid rejection | Unit mismatch, leak, or wrong mutation |
| Tree | Hierarchy, active descendant, selection, expansion, set facts, filtering | Stale identity or incoherent topology |
| Scrolling | Composite range/action and positive owner republish | Native thumb invention or ineffective action |
| DPI | 100/150/200 percent, resize, monitor movement when available | Material bounds mismatch |
| Teardown | Close ingress, free adapter, destroy HWND, provider removal, second session | Crash, stale provider, or retained mutation |
| Manual review | Accessibility Insights properties, patterns, events, and teardown | Unexplained warning, malformed tree, or fault |
| Repository | Unit suites, analyzer, builds, wiki, closure, canonical check | Any unexplained regression |

## Repository Commands

The intended Windows commands are:

```powershell
julia tools/make.jl unit odin --package=view/native/accessibility
julia tools/make.jl accesskit-abi
cmake --build --preset debug
cmake --build --preset default
julia tools/make.jl unit
julia tools/make.jl accessibility-windows
cmake --build --preset default --target check
```

`accessibility-windows` is an interactive-desktop evidence command. It should have a
CMake convenience target but must not become an unconditional headless CTest because
UI Automation discovery and window interaction require a logged-in session.

## Relevant Files

- [`sev_access2.md`](sev_access2.md) - controlling cross-platform accessibility
  architecture and delivery gates.
- [`sev_access2_research.md`](sev_access2_research.md) - evidence ledger for AccessKit,
  UI Automation, platform contracts, and unresolved empirical questions.
- [`sev_access2_macos.md`](sev_access2_macos.md) - prior platform parity staging model
  and shared extraction history.
- `libs/accesskit/accesskit.odin` - narrow Odin AccessKit declarations to extend with
  the Windows subclassing surface.
- `libs/accesskit/include/accesskit.h` - tagged controlling Windows C contract.
- `libs/accesskit/bin/windows/x86_64/manifest.toml` - retained provider identity,
  versions, artifact roles, and hashes.
- `tools/build_config.jl` - provider validation, import-library flags, runtime paths,
  and target-sensitive build facts.
- `tools/accessibility/accesskit_abi_probe.c` - common and Windows ABI/export probe.
- `tools/accessibility/run_accesskit_abi_probe.jl` - host probe compilation, loading,
  and result validation.
- `tools/make.jl` - DLL staging, evidence command, cleanup, wiki, and runtime closure.
- `tools/test/runtests.jl` - build configuration, command parsing, and staging tests.
- `src/accessibility/publication.odin` - validated complete portable publications.
- `src/accessibility/native_storage.odin` - native IDs, retirement, and bounded action
  queue.
- `src/view/native/accessibility/owner.odin` - adapter state and diagnostics.
- `src/view/native/accessibility/accesskit_translation.odin` - shared AccessKit tree
  construction and scale conversion.
- `src/view/native/accessibility/action_adapter.odin` - shared publication and action
  validation.
- `src/view/native/accessibility/windows_adapter_core.odin` - deterministic
  Windows lifecycle owner.
- `src/view/native/accessibility/windows_adapter.odin` - real Windows
  subclassing adapter calls.
- `src/view/native/accessibility/windows_adapter_test.odin` - admission,
  ownership, update, and teardown tests.
- `src/view/native/sdl_platform.odin` - hidden-window creation, HWND lookup, adapter
  dispatch, show sequencing, and teardown.
- `src/view/view.odin` - complete publication and display-thread action convergence.
- `tools/accessibility/accesskit_windows_tree_probe.cs` - automated UIA evidence
  workflow.
- `cmake/EuclidTargets.cmake` - proposed `accessibility-windows` convenience target.
- `docs/wiki/Guides/AccessibilityVerification.md` - cross-platform operator workflow.
- `docs/wiki/Guides/WindowsAccessibilityQualification.md` - proposed final Windows
  qualification record.
- [`staging_windowsportable_discussion.md`](staging_windowsportable_discussion.md) -
  separate future portable Julia/runtime packaging discussion.

## Completion Criteria

Windows current-tree parity is complete only when all of the following are true:

1. The retained Windows AccessKit provider, header, import library, DLL, symbols, and
   common ABI are verified on the qualified host.
2. Release and debug outputs stage the exact validated AccessKit DLL beside the
   executable.
3. The Windows SDL window is hidden until one complete publication is current and the
   subclassing adapter admission attempt is complete.
4. Accessibility failure never prevents the ordinary window from being shown.
5. UI Automation exposes one rooted, ordered, bounded control tree.
6. Native IDs remain stable, retire safely, and are never reused in one session.
7. Native callbacks copy bounded requests, free transferred ownership once, and never
   mutate owners directly.
8. Display-thread validation rejects stale, removed, unsupported, disabled, malformed,
   and out-of-range requests.
9. Buttons, accordion relations, panels, checkboxes, ranges, disabled controls, status,
   Search, text selection, Tree hierarchy, filtering, and scrolling expose coherent
   native behavior.
10. Every accepted native action mutates the existing owner exactly once.
11. Every non-null queued-event pointer is raised exactly once.
12. DPI and resize bounds are empirically correct on the qualified host.
13. Two automated UIA sessions pass with clean provider removal and repeated teardown.
14. Accessibility Insights review passes without malformed data or unexplained faults.
15. Version-specific adapter limitations are explicit and do not become false parity
   claims.
16. Documentation, generated wiki, runtime closure, and qualification evidence identify
   one committed candidate.
17. The complete Linux, macOS, and Windows regression matrix passes before Dynview or
   Terminal accessibility resumes.

## Final Recommendation

Approve the Windows program with the pre-show adapter contract as its first invariant:

> A complete validated publication must exist before AccessKit is attached, AccessKit
> must be attached before SDL shows or focuses the HWND, every native transfer must have
> exactly one owner, and failure must degrade to an ordinary visible application rather
> than an unsafe retry or blocked startup.

That sequence gives Windows one small falsifiable starting point and keeps the mature
shared accessibility model authoritative. Once the rooted button round trip and
teardown are proven, ordinary controls, Search, Tree, text, filtering, and scrolling can
advance through the same owner paths already exercised on Linux and macOS. Dynview and
Terminal remain stopped until that current surface is demonstrably stable on all three
desktop platforms.