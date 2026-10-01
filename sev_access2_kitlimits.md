# AccessKit Capability Limits and Evaluation Plan for Euclid

## Document Status

Evaluation date: 2026-09-30. This document is a cross-platform assessment
companion to [`sev_access2_research.md`](sev_access2_research.md),
[`sev_access2_macos.md`](sev_access2_macos.md), and
[`sev_access2_windows.md`](sev_access2_windows.md). It records what Euclid
cannot currently represent, expose, operate, or prove through its pinned
AccessKit stack, and defines the evidence needed before changing or forking
that stack.

The evaluated dependency set is:

| Component | Version |
| --- | --- |
| AccessKit C | 0.23.1 |
| AccessKit schema crate | 0.25.1 |
| AccessKit Unix adapter | 0.24.0 |
| AccessKit macOS adapter | 0.27.1 |
| AccessKit Windows adapter | 0.35.1 |

The upstream AccessKit projects are dual-licensed MIT OR Apache-2.0. Euclid's
retained provider manifests select MIT and preserve the applicable
Chromium-derived notice. This permits a downstream fork or patch stack,
subject to preserving the selected license and required notices.

This document is deliberately not a defect ledger against AccessKit alone.
A failed native operation may originate in the portable schema, AccessKit C,
one Rust platform adapter, Euclid's binding or publication, the native client,
or the qualification workflow. Each finding below identifies the narrowest
layer currently supported by evidence. Unresolved findings remain hypotheses.

## Executive Assessment

Euclid is already exercising the practical edges of the pinned AccessKit
adapters. Ordinary buttons, checkboxes, numeric ranges, focus, hierarchy, and
basic values map successfully. Dynamic trees, editable text, relations,
composite scrolling, transient states, and platform-specific semantics expose
material differences on every qualified platform.

The most important conclusions are:

1. AccessKit's portable schema does not model every native accessibility fact.
   AT-SPI Component alpha and MDI z-order have no corresponding node property
   in the pinned C contract. Exact MathML or speech-expression payloads,
   arbitrary announcement strings, custom VoiceOver rotors, and a complete
   terminal protocol are also absent.
2. AccessKit C is not the source of the currently confirmed platform defects.
   It exposes the relevant portable text actions, text metadata, relations,
   state, ranges, geometry, transforms, and platform adapter entry points.
   Euclid's Odin declaration is intentionally narrower than that complete C
   surface and must be evaluated separately.
3. AccessKit Unix exposes only a compatibility subset of the portable Tree
   action and state model through AT-SPI. Euclid works around this with `click`
   for branch toggling and Value for composite scrolling.
4. Linux is currently the least trustworthy parity claim, not necessarily the
   least capable platform. Its archived native probe is narrower than the
   Component and EditableText surfaces visible in Accerciser, and no completed
   Orca workflow is recorded.
5. AccessKit macOS cannot currently dispatch two required Euclid operations:
   Tree expansion/collapse and selected-text replacement. The observed native
   projection also lacks expanded and busy state.
6. AccessKit Windows leaves valid partial TextPattern selection unchanged and
   exposes Euclid's Tree range as read-only. Selected-text replacement and the
   Search-to-Tree relation are not available through the qualified inbox
   managed UIA client.
7. A downstream fork is technically justified if Euclid accepts ongoing Rust
   adapter maintenance. It should begin only after a native conformance suite
   turns the current observations into reproducible, versioned failures.

## Attribution Model

Every capability claim must be classified at one of these boundaries:

| Layer | Question | Typical failure |
| --- | --- | --- |
| Native platform contract | Can AT-SPI, NSAccessibility, or UIA express it? | The platform has no equivalent semantic concept. |
| AccessKit schema | Can an `accesskit::Node` carry the fact or action? | No alpha, MDI z-order, exact math payload, or arbitrary announcement operation. |
| AccessKit C ABI | Can a C-family host publish or receive the schema feature? | A Rust feature exists but is not exported by AccessKit C. |
| Rust platform adapter | Does the adapter translate it to and from the native API? | Expand exists in the schema but Unix exposes only `click`. |
| Euclid binding/publication | Does Euclid declare and publish the available feature? | The C setter exists but `accesskit.odin` or translation omits it. |
| Native client and evidence | Does a real inspector or assistive technology observe and operate it? | A probe uses one method while Accerciser or a screen reader uses another. |

Deterministic Euclid tests prove callback copying, validation, owner routing,
and republication. They do not prove that a native adapter emits the request.
A successful inspector query proves native exposure but does not prove screen
reader navigation or speech. A complete claim requires evidence at every
relevant boundary.

## Portable Schema Limits

### Component alpha and MDI z-order

AT-SPI's Component interface includes `getAlpha()` and `getMDIZOrder()`.
AccessKit C 0.23.1 contains no node setter or property for component opacity,
alpha, MDI stacking order, or z-order. The only `alpha` field in the retained
header is the alpha channel of an sRGB color structure. Euclid therefore has
no portable AccessKit value it can publish for either AT-SPI query.

The reported Accerciser failures are consistent with a schema or Unix-adapter
default, not evidence that Euclid forgot to publish an available property.
The exact returned value, D-Bus error, and adapter implementation path still
need to be recorded before classifying either behavior as an upstream defect.

Potential resolutions are:

- document a deliberate AT-SPI default when the values are not meaningful;
- add portable opacity and stacking metadata to AccessKit;
- add Unix-only adapter configuration outside the portable node schema; or
- accept the missing methods if real assistive technologies do not consume
  them and conformance requirements permit the defaults.

### Mathematical content

AccessKit can mark mathematical roles and ordinary semantic structure, but the
pinned schema has no portable MathML payload, speech-expression payload, or
complete mathematical navigation protocol. Euclid cannot rely on AccessKit to
preserve exact fraction, script, matrix, operator, or notation semantics across
AT-SPI, NSAccessibility, and UIA.

Dynview mathematics will require one or more of:

- a structured approximation using existing roles and text;
- adapter-specific native math payloads;
- a new portable AccessKit math representation; or
- an alternate native accessibility path for document mathematics.

This is a future product limitation, not a blocker for the current ordinary
controls, Search, and Tree milestone.

### Announcements and live output

AccessKit models live-region policy and relevant state, but it has no portable
operation equivalent to an arbitrary native announcement string with complete
queueing, interruption, priority, and attribution policy. Platform adapters
and assistive technologies retain control over announcement timing and speech.

This limits exact cross-platform parity for search result feedback, async
errors, GIF operation status, and future Terminal output. Euclid can publish
status nodes and state transitions, but cannot guarantee identical spoken
behavior.

### Custom navigation and rotors

The portable schema has no API for custom VoiceOver rotors or equivalent
platform-specific navigation collections. Document headings, links, controls,
and landmarks should be represented structurally first. Product requirements
that demand custom rotors would need an AccessKit extension or a native macOS
side channel.

### Terminal semantics

AccessKit includes roles and text primitives useful for a terminal projection,
but no complete portable terminal protocol. It does not prescribe retained
scrollback, prompt and input boundaries, protected input, alternate-screen
behavior, live output batching, cursor speech, links, selection, or row
virtualization. Euclid must design those semantics and qualify each adapter and
screen reader empirically.

### Native-only properties and actions

The three native APIs contain properties, interfaces, patterns, notifications,
and actions with no exact portable peer. Absence from AccessKit is not
automatically a defect: some properties are toolkit implementation details,
some can be derived by an adapter, and some have no useful cross-platform
meaning. Evaluation must distinguish required user behavior from inspector
surface completeness.

## AccessKit C and Euclid Binding Limits

No confirmed current-platform failure has been traced to AccessKit C's FFI
design. The retained API exports actions for click, focus, blur,
expand/collapse, increment/decrement, replace selected text, set text
selection, set value, scrolling, and context menus. It also exports setters
for text metadata, relations, numeric ranges, scroll ranges, bounds,
transforms, language, text direction, descriptions, and substantial state.

Euclid's [`libs/accesskit/accesskit.odin`](libs/accesskit/accesskit.odin)
intentionally declares only the subset needed by the current projection. It
does not yet expose every available description, invalid/read-only/required/
modal/hidden state, language, text-direction, transform, role-description,
state-description, braille-description, or detailed text-geometry setter.

Consequently, future evaluations must use three outcomes rather than a binary
supported/unsupported result:

- **Available and used**: exported by AccessKit C and published by Euclid.
- **Available but unused**: exported by AccessKit C but absent from Euclid's
  binding, semantic model, or translation.
- **Unavailable**: absent from the portable schema or C ABI.

The Odin declaration should remain narrow. New symbols should be added only
with a semantic owner, deterministic tests, and a native acceptance case.

## Linux: AccessKit Unix and AT-SPI

### Confirmed behavior

The archived Linux two-session probe proved direct AT-SPI discovery and
operation for the following current surface:

- application and synthetic-root discovery;
- role, name, hierarchy, state, relation, bounds, and object-path inspection;
- Search Text and EditableText interfaces;
- Search-to-Tree controller relation;
- whole-value replacement through `EditableText.setTextContents`;
- text selection;
- committed filtered Tree topology;
- branch collapse and expansion through `click`;
- leaf selection through `click`;
- Tree scrolling through the Value interface;
- disjoint-filter TreeItem retirement;
- representative button, checkbox, and slider operation;
- provider removal and a second complete application session.

This evidence is useful but narrower than the complete AT-SPI interfaces.

### Confirmed adapter limitations and compatibility behavior

AccessKit Unix 0.24.0 does not expose every portable action as a named AT-SPI
Action entry. For the qualified TreeItem projection:

- Action is present only when the node is considered clickable;
- the adapter reports one action named `click`;
- invoking it emits AccessKit `Action::Click`;
- AccessKit Expand and Collapse are not separately exposed;
- the published expanded property was not visible as an AT-SPI expanded state.

Euclid therefore interprets `click` on a branch as an expansion toggle while
continuing to publish portable Expand and Collapse actions for adapters that
can use them. This is functional compatibility, not native action parity.

Tree scrolling also lacked useful named AT-SPI scrolling actions. Euclid
publishes a finite numeric current/minimum/maximum/step range on the Tree and
accepts numeric SetValue as absolute scrolling. The workaround passed the
native probe but exposes scrolling as Value rather than a native scrolling
contract.

A flat SearchInput value did not expose AT-SPI Text. A TextRun descendant was
required. Every TextRun, including an empty TextRun, also required a value;
omitting the empty value reached an adapter-side unwrap and disconnected the
client. This projection works, but it is a fragile adapter contract that must
remain covered by regression tests.

### Reported Component failures

Current manual Accerciser observations report broken Component MDI-Z-Order and
Alpha queries. The checked-in probe calls `getExtents()` and `grabFocus()` but
does not call or record `getAlpha()` or `getMDIZOrder()`. The archived pass
therefore says nothing about these methods.

The next Linux run must capture for every representative role:

- advertised interfaces;
- `getAlpha()` return value or exception;
- `getMDIZOrder()` return value or exception;
- layer;
- extents, position, and size in supported coordinate systems;
- `contains()` and accessible-at-point hit testing;
- focus acceptance;
- native scroll-to and scroll-to-point behavior where advertised;
- behavior before and after resize, scale, clipping, and removal.

Alpha and MDI z-order should not block Euclid merely because Accerciser lists
them. They should block only if the native contract requires a valid result,
an assistive technology consumes it, or the adapter fails in a way that harms
client stability. The evidence must make that policy decision explicit.

### Confirmed Accerciser text-editing limitation

Accerciser cannot edit Euclid's Search field through its Interface Viewer text
box. The exact failure resolves the apparent conflict with the archived Python
probe: the two clients invoke different AT-SPI methods.

Accerciser connects GTK text-buffer insertion to `_onITextInsert`, which calls
`EditableText.insert_text(position, text, length)`. AccessKit Unix implements
`set_text_contents`, but its EditableText interface explicitly returns an
unsupported-operation error for `insert_text`, `delete_text`, `copy_text`,
`cut_text`, and `paste_text`. The observed
`atspi_error: Editing operation is not supported (1)` is therefore an adapter
limitation, not a rejected Euclid callback. No AccessKit action reaches
Euclid for that insertion.

The checked-in probe succeeds because it directly calls
`EditableText.setTextContents`, which AccessKit Unix maps to AccessKit
SetValue. Euclid handles that request as whole-value replacement and
re-publishes the committed text. Accerciser's Interface Viewer provides no
alternative whole-value editor that calls `set_text_contents`, so there is no
working insertion path in that UI for the current adapter.

The same interaction produces a separate viewer failure. GTK mark movement
calls Accerciser's `_onTextMarkSet`, which calls `popTextAttr`. That function
expects `Text.get_text_attributes(offset)` to return a dictionary and invokes
`.keys()` unconditionally. In the observed stack it receives `None`, producing
`AttributeError: 'NoneType' object has no attribute 'keys'`.

AccessKit has portable font, size, weight, style, foreground/background color,
language, alignment, underline, and strikethrough properties, and its Unix
adapter implements text-attribute queries. Euclid currently publishes no
Search text styling, so an empty attribute result is legitimate. Whether the
`None` originates in AccessKit's D-Bus result, libatspi/pyatspi conversion, or
the exact Accerciser version remains to be captured. Accerciser should handle
an absent or empty map as `{}` rather than crashing; Euclid should not publish
invented styling to work around the viewer.

These two exceptions can appear together because typing both invokes
`insert_text` and moves GTK text marks. They represent independent failures:

- granular EditableText insertion is a confirmed AccessKit Unix limitation;
- text-attribute rendering is an Accerciser/AT-SPI interoperability issue
  whose producing layer remains unresolved; and
- whole-value `setTextContents` remains proven through the Python probe.

The existing probe still does not exercise:

- `insertText`, `deleteText`, `copyText`, `cutText`, or `pasteText` as expected
  unsupported operations;
- empty and styled text-attribute maps at valid and end-of-text offsets;
- replacement of only the selected text;
- replacement with no selection or a collapsed caret;
- invalid and stale ranges;
- forward and backward selections;
- multibyte UTF-8 text through every operation;
- editing through both the Search owner and its TextRun child; or
- emitted text, caret, selection, and attribute events.

Euclid also publishes ReplaceSelectedText and SetTextSelection and has
deterministic owner tests for them, but those tests construct AccessKit
requests directly. They do not prove native AccessKit Unix dispatch.

The next Linux evidence run should record the selected object path, invoked
D-Bus method and arguments, return value or exception, callback received by
Euclid, owner mutation, republication, and events. For `popTextAttr`, it should
also record the requested offset, character count, raw attribute result, and
attribute range so the `None` conversion can be assigned precisely.

### Missing Linux qualification

Linux has no archived completed Orca workflow. The probe also lacks exhaustive
Component, Text, EditableText, event, transient-state, retained-object, and
desktop-environment coverage. It has not established parity across GNOME,
KDE, X11, and Wayland sessions.

The current Linux claim must therefore remain:

> Basic direct AT-SPI operation passed for one versioned desktop session. Full
> interface conformance and screen-reader usability remain unqualified.

## macOS: AccessKit macOS and NSAccessibility

The qualified macOS workflow proves ordinary controls, Search whole-value
mutation, text selection, relations, Tree filtering, selection, retirement,
native Tree scrolling, provider removal, and repeated sessions. Inspector and
VoiceOver review were completed for that milestone.

The following current-surface requirements remain blocked by AccessKit macOS
0.27.1:

- no selector dispatch for Tree expansion or collapse;
- no selected-text replacement dispatch;
- no observed expanded-state selector for the Tree branch; and
- no observed native busy-state projection.

The first two are behavioral blockers because native clients cannot request
operations that Euclid publishes and can execute internally. The latter two
are state-projection blockers and may alter navigation or feedback. Composite
Tree scrolling is not a current limitation; it passed through a positive
native range.

Additional macOS areas remain under-qualified rather than confirmed broken:

- selected-text replacement through clients beyond the current probe;
- event ordering for rapid filtering and focus repair;
- retained AX element behavior after retirement;
- Voice Control and Switch Control;
- Intel macOS runtime behavior; and
- future document, mathematical, live-output, and Terminal surfaces.

## Windows: AccessKit Windows and UI Automation

The qualified Windows workflow proves ordinary controls, Search Value and Text
patterns, multibyte whole-value replacement, caret placement, whole-document
selection, dynamic Tree hierarchy, expansion/collapse, selection, filtering,
identity continuity, retirement, runtime-ID non-reuse, provider removal, and
repeated teardown.

The following behaviors are confirmed for AccessKit Windows 0.35.1 and the
qualified inbox managed UIA client:

- selecting a valid partial TextPattern range leaves the prior selection
  unchanged;
- the filtered Tree exposes RangeValue as read-only;
- selected-text replacement is unavailable through the inbox managed UIA
  surface used by the probe; and
- the published Search-to-Tree ControllerFor relation is unavailable through
  that managed client.

These findings do not all have the same ownership. Partial selection and the
read-only Tree range are adapter projection differences. Selected-text
replacement and ControllerFor may also be constrained by the qualified client
API. They require a lower-level UIA client or Accessibility Insights trace
before assigning an AccessKit-only defect.

The Windows record also lacks complete transient GIF state, resize,
multi-monitor, and 100/150/200-percent DPI evidence. Those are qualification
gaps, not confirmed AccessKit limitations.

## Cross-Platform Capability Matrix

| Capability | Portable schema/C ABI | Linux | macOS | Windows | Current classification |
| --- | --- | --- | --- | --- | --- |
| Button activation | Yes | Passed | Passed | Passed | Qualified current surface. |
| Checkbox toggle | Yes | Passed | Passed | Passed | Qualified current surface. |
| Numeric range mutation | Yes | Passed | Passed | Passed for ordinary ranges | Tree range diverges by adapter. |
| Focus | Yes | Passed | Passed | Passed | More event and retirement coverage needed. |
| Relations | Yes | Controller relation passed | Passed in probe | ControllerFor unavailable to managed client | Client/adapter parity gap. |
| Whole text replacement | SetValue | Python probe passed; Accerciser has no UI path to this method | Passed | Passed | Qualified through direct native probe. |
| Granular text insertion/deletion | No direct portable insert/delete actions | Unix methods return unsupported | Not qualified | Managed UIA path unavailable | Confirmed Unix adapter limitation. |
| Text attributes | Yes | Adapter supports queries; Accerciser receives `None` for Euclid's unstyled text and crashes | Not exhaustively qualified | Not exhaustively qualified | Linux producing layer unresolved. |
| Text selection | Yes | Whole-range probe passed | Set/rejection passed | Caret and whole range pass | Windows partial range fails. |
| Selected-text replacement | Yes | Owner path tested; native dispatch unproven | Not dispatched | Managed UIA path unavailable | Not qualified on any platform. |
| Tree expand/collapse | Yes | `click` workaround; no named actions/state | Not dispatched | Passed | Material adapter divergence. |
| Tree composite scrolling | Yes | Value workaround | Positive range passed | RangeValue read-only | No common native operation. |
| Busy state | Yes | Not exhaustively qualified | Not observed | Transient state unqualified | Projection/evidence gap. |
| Component alpha | No | Reported broken; untested by probe | Not applicable as AT-SPI method | Not applicable as AT-SPI method | Portable schema gap. |
| Component MDI z-order | No | Reported broken; untested by probe | Not applicable as AT-SPI method | Not applicable as AT-SPI method | Portable schema gap. |
| Exact math semantics | No complete payload | Not implemented | Not implemented | Not implemented | Portable schema/product gap. |
| Arbitrary announcements | No exact portable operation | Platform-dependent | Platform-dependent | Platform-dependent | Cannot promise speech parity. |
| Custom rotors | No | Not applicable | Unavailable portably | Not applicable | Native extension required. |
| Complete Terminal model | No prescribed protocol | Not implemented | Not implemented | Not implemented | Product and schema design required. |

“Passed” in this table means the versioned Euclid workflow passed its recorded
operation. It does not imply exhaustive native API conformance or parity among
assistive technologies.

## Required Linux Conformance Expansion

Linux should be evaluated first because it currently combines the broadest
AT-SPI inspector surface with the narrowest archived assertions. The expanded
probe should produce one structured record per object and operation rather
than only a scenario-level pass.

### Discovery and interfaces

For each representative root, ordinary control, Search owner, TextRun, Tree,
branch, leaf, status, and transient node, record:

- role, name, description, attributes, states, object path, process, parent,
  index in parent, and child count;
- every advertised AT-SPI interface;
- relations and target object paths;
- actions, names, descriptions, key bindings, and invocation results;
- Value facts and write behavior; and
- identity before, during, and after updates.

### Component

Exercise every applicable Component method, including alpha, MDI z-order,
layer, extents, position, size, containment, point hit testing, focus, and
scroll methods. Repeat after host movement, resize, desktop scaling, clipping,
filtering, and object retirement. Record unsupported methods as explicit
results rather than aborting the complete report.

### Text and EditableText

Exercise:

- full text, character count, caret, and selection count;
- text at/before/after offsets for character, word, line, sentence, and
  attribute boundaries where supported;
- character and range extents and offset-at-point;
- attributes, default attributes, and bounded ranges;
- whole-value replacement;
- insertion and deletion at the beginning, middle, and end;
- selected-text replacement;
- copy, cut, and paste where supported by the test environment;
- collapsed, forward, backward, invalid, and stale selections; and
- ASCII, multibyte BMP, supplementary-plane, combining-mark, and newline
  content.

Each mutating operation must correlate the native call with Euclid callback
ingress, accepted owner mutation, republication, and the native event stream.

### Events and dynamic state

Subscribe before discovery and record focus, state, property, text, caret,
selection, children, bounds, relation, and provider lifecycle events. Exercise
rapid updates, no-op updates, identical frames, transient busy/disabled/status
states, branch toggling, filtering, focus repair, retirement, and teardown.

### Assistive technologies and desktops

Archive one exact Orca workflow for Search and Tree, including spoken value,
selection, result status, branch operation, filtering, focus repair, and
retirement. Repeat the direct probe and user workflow under named GNOME and
KDE sessions and record whether each uses Wayland or X11. Accerciser remains
an inspector and method exerciser; it is not a substitute for Orca evidence.

## Cross-Platform Evaluation Program

The conformance work should proceed in this order:

1. Expand Linux evidence until the reported Component and text failures are
   reproducible and attributed.
2. Extract a platform-neutral operation vocabulary and expected semantic
   outcomes from the Linux, macOS, and Windows probes.
3. Preserve platform-specific native details in per-adapter evidence rather
   than forcing false equality.
4. Add failing adapter-level Rust tests for each confirmed upstream mapping
   defect before patching AccessKit.
5. Build AccessKit C against the patched Rust workspace and rerun Euclid's
   ABI, deterministic, native, assistive-technology, build, and closure gates.
6. Re-evaluate the patch on every supported platform before adding new
   Dynview or Terminal semantics.

The machine-readable evidence schema should include:

- Euclid revision and dirty state;
- AccessKit C and every Rust crate version or commit;
- provider binary hash;
- OS, desktop/compositor, display server, scale, locale, and architecture;
- native API, inspector, and assistive-technology versions;
- object identity and complete observed interfaces;
- requested operation and native result;
- AccessKit request received, if any;
- owner mutation and publication generation;
- resulting properties, topology, and events; and
- a classification of pass, unsupported, rejected, no-op, timeout, crash, or
  provider disappearance.

## Fork and Patch Decision

### Recommended repository boundary

If patches are required, fork the main AccessKit Rust repository and maintain
a disciplined patch series there. Continue using AccessKit C unchanged at
first, built against the forked crates through Cargo dependency overrides.
Odin cannot safely call Rust's unstable native ABI directly, so an
`extern "C"` and `#[repr(C)]` boundary remains necessary.

Fork or replace AccessKit C only if a required new schema field, action, or
adapter configuration cannot be exposed through its existing C API. Keeping
the current C ABI stable minimizes Euclid changes and lets the fork focus on
the adapter defects that evidence actually identifies.

### Patch eligibility

A downstream patch should require all of the following:

- a user-relevant behavior is blocked or materially degraded;
- the failure reproduces outside Euclid's owner logic;
- the native platform can represent the intended behavior;
- the AccessKit schema can represent it, or a deliberate schema extension is
  proposed;
- a minimal adapter-level regression test exists;
- the patch does not regress another platform's contract; and
- Euclid can package, license, update, and qualify the resulting binaries.

Inspector completeness alone is not sufficient. Alpha or MDI z-order, for
example, should not receive a schema extension without evidence that valid
values affect conformance, stability, or assistive-technology behavior.

### Initial candidate patches

The strongest initial candidates are:

1. AccessKit Unix EditableText insertion and deletion, which currently return
  unsupported while the interface is advertised. Copy, cut, paste, and
  selected-text replacement should be designed and tested with them.
2. AccessKit Unix expanded-state exposure and explicit Expand/Collapse action
   mapping, if AT-SPI can support them without compatibility regressions.
3. AccessKit macOS Tree expansion/collapse dispatch.
4. AccessKit macOS selected-text replacement dispatch.
5. AccessKit Windows partial TextPattern selection.
6. A writable Windows Tree scrolling operation that maps cleanly to Euclid's
   composite scroll range.

Busy-state projection, relations, Component defaults, notifications, and
event fidelity should follow once their failures are precisely attributed.

## Acceptance Criteria

AccessKit is sufficient for Euclid's current pre-Dynview/pre-Terminal surface
only when all of the following hold:

- every required semantic fact is either represented portably or has an
  explicitly accepted platform-specific approximation;
- every required action reaches Euclid exactly once with valid identity and
  payload;
- Search supports whole-value mutation, caret and range selection, and
  selected-text replacement through representative native clients;
- Tree supports discoverable expansion state, expansion/collapse, selection,
  filtering, focus repair, identity retirement, and scrolling;
- relations and transient busy/disabled/status states are observable through
  qualified clients;
- native events describe meaningful changes without duplicate storms or
  missing lifecycle transitions;
- retained removed objects cannot retarget new controls;
- provider startup, repeated sessions, and teardown remain stable; and
- direct API probes and at least one primary assistive technology agree on the
  user workflow for each platform.

Until then, Euclid should describe the implementation as a version-qualified
native accessibility projection, not cross-platform parity.

## Immediate Evaluation Backlog

1. Add native assertions that AccessKit Unix `insertText`, `deleteText`,
  `copyText`, `cutText`, and `pasteText` return unsupported and emit no Euclid
  callback, while `setTextContents` succeeds and republishes text.
2. Add non-fatal Alpha and MDI-Z-Order observations to the Linux Component
   record, then determine whether they affect clients or conformance.
3. Capture `get_text_attributes` at valid, empty-text, and end-of-text offsets
  and determine where an empty map becomes `None`; report or patch Accerciser
  to tolerate `{}`/`None` without inventing Euclid text styling.
4. Add the complete Linux EditableText operation matrix and multibyte cases.
5. Add Linux text geometry, boundary, hit-testing, event, and retained-object
  coverage.
6. Complete and archive one Orca Search/Tree workflow.
7. Re-run under named GNOME and KDE environments.
8. Convert every confirmed adapter limitation into the smallest upstream Rust
   regression test.
9. Decide per failure whether to report upstream, carry a temporary patch, or
   accept and document a platform approximation.

This backlog should precede a fork. Its purpose is not to delay one, but to
ensure that Euclid maintains patches for demonstrated user behavior rather
than for ambiguous inspector output.

## Source Ledger

The conclusions in this document derive from:

- the versioned AccessKit C header retained at
  [`libs/accesskit/include/accesskit.h`](libs/accesskit/include/accesskit.h);
- Euclid's narrow binding at
  [`libs/accesskit/accesskit.odin`](libs/accesskit/accesskit.odin);
- shared translation and action validation under
  [`src/view/native/accessibility`](src/view/native/accessibility);
- the Linux AT-SPI probe at
  [`tools/accessibility/accesskit_tree_probe.py`](tools/accessibility/accesskit_tree_probe.py);
- the macOS AX probe at
  [`tools/accessibility/accesskit_macos_tree_probe.swift`](tools/accessibility/accesskit_macos_tree_probe.swift);
- the Windows UIA probe at
  [`tools/accessibility/accesskit_windows_tree_probe.cs`](tools/accessibility/accesskit_windows_tree_probe.cs);
- the completed research record in
  [`sev_access2_research.md`](sev_access2_research.md);
- the macOS qualification record in
  [`docs/wiki/Guides/MacosAccessibilityQualification.md`](docs/wiki/Guides/MacosAccessibilityQualification.md);
  and
- the Windows qualification record in
  [`docs/wiki/Guides/WindowsAccessibilityQualification.md`](docs/wiki/Guides/WindowsAccessibilityQualification.md).

Public API existence does not prove adapter behavior. Adapter source does not
prove retained provider behavior. Machine probes do not prove screen-reader
usability. This document should be revised only when new evidence identifies
which boundary changed.