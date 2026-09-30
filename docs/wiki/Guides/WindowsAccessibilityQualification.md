# Windows Accessibility Qualification

## Status

Qualification run: 2026-09-30.

The Phase 4 qualification workflow was executed, but the parity freeze is **blocked**.
AccessKit Windows 0.35.1 ignores partial TextPattern selection and exposes the Tree
RangeValue pattern as read-only. The complete Accessibility Insights, transient GIF,
resize, and 100/200 percent scale gates also remain open. These gaps are not waived by
this record.

## Qualified Environment

| Component | Qualified version |
| --- | --- |
| Windows | Windows 11 Home 10.0.26200 (build 26200) |
| Architecture | x86-64 / AMD64 |
| Desktop scale | 150 percent (`AppliedDPI=144`) |
| Euclid base revision | `9c86605dda3fe7c87cc59e692f6cd14ff78ff898` plus the uncommitted qualification patch |
| Analyzer submodule | `70b818f5f428bdf91234c63b7aedafb6853e6668` plus the Windows path-normalization test fix |
| AccessKit C | 0.23.1 |
| AccessKit schema | 0.25.1 |
| AccessKit Windows | 0.35.1 |
| SDL3 | 3.4.16 |
| SDL3_image | 3.4.6 |
| Accessibility Insights for Windows | 1.1.2924.1 |
| Odin | dev-2026-09-nightly:a2fb372 |
| Julia | 1.13.0 |
| MSVC | 19.51.36260 for x64 |
| CMake | 3.29.2 |

A commit identity must replace the base-revision-plus-patch description before a final
freeze can be declared. The Windows build reports itself through the underlying version
API as `Microsoft Windows 10.0.26200`; the qualified product caption is Windows 11 Home.

## Automated Evidence

- Focused native accessibility suite: 17/17 passed.
- Canonical gate: 3,829 application tests and 710 analyzer tests passed.
- Analyzer self-analysis covered 55 files with zero warnings or failures.
- Repository analysis covered 787 files with zero warnings or failures.
- AccessKit ABI passed with `windows_symbols=1` and
  `windows_module_adjacent=1`.
- Debug and default builds passed.
- Both staged `accesskit.dll` files matched the retained provider SHA-256
  `d9f9d834eb0a86c799044800065887749397e2343f37681d38f9725535beaa63`.
- Debug and default direct `--help` loader smokes passed.
- `julia tools/make.jl accessibility-windows` passed two complete native sessions.
- Both sessions closed the native window, removed the provider, and rejected retained
  stale Tree elements without mutating current controls.
- Search whole-value replacement, multibyte value publication, collapsed caret,
  whole-document selection, filtering, Tree selection, expansion, collapse, identity
  continuity, retirement, and native ID non-reuse passed.

Normalized evidence is in `.build/accessibility-windows/uia.json` with schema version 3,
`result: pass`, `session_count: 2`, and `repeated_teardown: true`. Its qualification
SHA-256 is `697e692d8770ac35ef256bbeedb1774678f71bef4a65f3c18fe3ce9f947361d3`.

The default executable SHA-256 is
`9d93b1a81b3eb87219ab43b81376d8caa5a35e077838c0db36f43b52388241f3`.
The debug executable SHA-256 is
`cee7c0f9a55ff6a67154d1cf47083929a1a3e7211e6a93944d00470c83ea8427`.

The analyzer suite initially exposed one Windows-only test expectation that compared a
normalized exclusion path with a hard-coded forward-slash path. The qualification patch
uses `normpath` in that assertion; the focused analyzer suite and complete canonical
gate then passed.

## Manual Evidence

The operator used Accessibility Insights to discover the Euclid root, Restart and
Pause controls, and the active accordion subtree. Settings and other panel controls
became inspectable after activating the corresponding accordion and refreshing or
reselecting the root.

This is useful partial evidence, but it is not the complete Phase 4 manual matrix.
Transient GIF busy/disabled events, relation inspection, dynamic filtering events,
composite scrolling, teardown, resize, and representative 100/200 percent scale checks
remain unrecorded. The current automated run covered the 150 percent desktop scale.

## Blocking Differences

AccessKit Windows 0.35.1 leaves a valid partial TextPattern range selection unchanged.
The probe constructs and verifies the requested beta range before invoking `Select`,
then records the unchanged owner-published caret as `provider_noop`. Whole-document
selection works. Inbox managed UIA exposes no selected-text replacement operation, so
that owner action cannot be qualified through this client.

The filtered Tree publishes a positive composite vertical range, but AccessKit Windows
0.35.1 exposes its RangeValue pattern as read-only. Native SetValue is rejected and no
positive owner scroll update occurs. Shared publication and owner scrolling remain
covered deterministically.

Inbox managed UIA reports the `ControllerFor` property as unsupported even though the
shared tree publishes the Search-to-Tree and accordion-to-panel relations. This is
classified as a client observability limitation pending complete Accessibility Insights
relation review.

No malformed tree, stale mutation, callback fault, queued-event ownership fault,
provider-removal fault, or teardown crash was observed.

## Closure Evidence

The checked runtime closure SHA-256 is
`3cd3ae3865af43a957f0ada53d782950634272c6bd62454689ff29160c5edc94`.
The generated runtime closure SHA-256 is
`89204020f4fd84487e0a1c68e1936389f0eb0a2cbded7fa4d6358db564befa81`.
The checked and generated files are different forms and are not expected to be
byte-identical.

The freeze can close after the retained Windows adapter or qualified client can operate
partial text selection, selected-text replacement, and composite Tree scrolling; the
complete Accessibility Insights, transient GIF, resize, and multi-scale matrix passes;
all gates are rerun; and the candidate is identified by one committed Euclid revision.
The post-parity Linux, macOS, and Windows regression matrix begins only after that
Windows freeze closes.
