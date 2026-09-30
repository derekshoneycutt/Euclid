# macOS Accessibility Qualification

## Status

Qualification run: 2026-09-30.

The Phase 4 qualification workflow is complete, but the parity freeze is **blocked**.
AccessKit macOS 0.27.1 cannot dispatch two actions required by the Phase 3 exit gate:
Tree expand/collapse and selected-text replacement. These are native action blockers,
not Euclid owner-path failures, and are not waived by this record.

## Qualified Environment

| Component | Qualified version |
| --- | --- |
| macOS | 26.6.2 (25G83) |
| Architecture | Apple Silicon arm64 |
| Euclid base revision | `8fee5a0b09434930928362ec640548f99e8d213a` plus the uncommitted qualification patch |
| AccessKit C | 0.23.1 |
| AccessKit schema | 0.25.1 |
| AccessKit macOS | 0.27.1 |
| SDL3 | 3.4.16 |
| SDL3_image | 3.4.6 |
| Accessibility Inspector | 5.0 |
| VoiceOver | 10 |
| Odin | dev-2026-09:a2fb372b7 |
| Julia | 1.13.0 |
| Apple clang | 21.0.0 (clang-2100.3.34.2) |
| Xcode | 27.0 (27A266a) |
| CMake | 4.4.3 |

A commit identity must replace the base-revision-plus-patch description before a final
freeze can be declared.

## Automated Evidence

- Focused Odin suite: 1,470/1,470 passed.
- Julia suite: 2,363/2,363 passed.
- Canonical gate: 3,833 application tests and 710 analyzer tests passed; 782 files
  analyzed with zero warnings or failures.
- AccessKit ABI passed with `macos_symbols=1`.
- Debug and default builds passed.
- `julia tools/make.jl accessibility-macos` passed two complete native sessions.
- Both sessions closed the native window and removed the provider cleanly.
- Native Tree scrolling changed the filtered composite from 0 to 616 through `AXValue`
  in both sessions and was republished by the owner.

Normalized evidence is in `.build/accessibility-macos/ax.json` with schema version 3,
`session_count: 2`, and `repeated_teardown: true`. Session diagnostics are beside it as
`session-1.log` and `session-2.log`.

## Manual Evidence

Accessibility Inspector and VoiceOver review was completed by the operator. The app
bundle was targetable under `app.euclid.Euclid`; representative controls, Search, Tree,
relations, state, bounds, filtering, focus, and teardown were reviewed. Retina bounds
were confirmed against the 30 by 30 Restart button frame.

## Blocking Adapter Differences

AccessKit macOS 0.27.1 does not implement an expanded-state selector or native
Expand/Collapse selector mapping. `AXPress` and `AXPick` were exercised against an
advertised branch without changing the published row topology.

The adapter reads `AXSelectedText` and maps `AXSelectedTextRange` writes to
`SetTextSelection`, but it does not implement `setAccessibilitySelectedText:` and cannot
dispatch `ReplaceSelectedText`. Whole-value replacement through `AXValue` works.

Busy state is also not exposed by this adapter version. That is a state-observability
difference, not one of the two native action blockers above.

## Closure Evidence

The checked runtime closure hash observed during qualification was
`9980e96012c0982c9c952cab74d73bcfdbc801c6ed3205cce013adf2be66d7d5`.
The generated runtime closure hash was
`ea331071f6cd2c607e65e77fc2e2ed250726da73a22dc9b5e864d5e33fe06bd6`.
The checked and generated files are intentionally different forms and are not expected
to be byte-identical.

The freeze can close after the retained macOS adapter dispatches both blocking actions,
the native probe exercises them successfully, all gates are rerun, and the candidate is
identified by one committed Euclid revision.
