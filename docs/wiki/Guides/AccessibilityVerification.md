# Accessibility Verification

## Windows Phase 1 root and button

The Windows workflow requires Windows 11 x64, .NET SDK 10 or newer, a logged-in
interactive desktop session, and the debug build. Run `cmake --build --preset debug`, then
`julia tools/make.jl accessibility-windows`.

The command compiles and runs the file-based C# UI Automation probe, then runs two
complete application sessions. In each session it discovers the root and Restart
button through UI Automation, checks the button's role, name, enabled
state, focusability, bounds, focus gain and loss, and Invoke pattern, invokes it exactly
once, and requires the passive scenario to observe the existing reset-owner event. It
then requires clean process exit and provider removal. Normalized evidence is written
to `.build/accessibility-windows/uia.json`; session logs and scenario artifacts are
stored beside it.

## macOS Phase 3 controls

The qualified macOS workflow requires an Apple Silicon host, a logged-in GUI session,
the debug build, and Accessibility permission for the terminal or VS Code process that
runs the command.

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Enable the process that launches the repository command.
3. Build with `cmake --build --preset debug`.
4. Run `julia tools/make.jl accessibility-macos`.

The command launches `.build/debug/Euclid.app`, verifies its bundle identity and a
system-wide point hit, and discovers controls through the macOS Accessibility API. It
replaces the Library Search value, sets and rejects text selections, verifies the
Search-to-Tree relation, filters the Tree, selects a result, proves surviving native
identity continuity and removed identity retirement, operates composite scrolling, and
records bounded result status.
It then operates the Settings accordion, checkbox, slider, and restart button, closes
the native window, and requires orderly provider removal. Normalized schema-versioned
evidence is written to `.build/accessibility-macos/ax.json`.

The retained AccessKit C 0.23.1 artifact uses `accesskit_macos` 0.27.1. That adapter maps
`DisclosureTriangle` to `AXButton` and `controls` to `AXLinkedUIElements`, but its native
node implementation has no expanded-state or busy-state selector. Its `AXOutline` also
does not dispatch Tree expansion, and the adapter has no selected-text setter that could
dispatch `ReplaceSelectedText`. Euclid still publishes these
facts and actions into the shared AccessKit tree and verifies their owner paths
deterministically. The macOS artifact records each version-qualified adapter limitation
and does not claim unsupported native operation.

Accessibility Inspector and VoiceOver remain manual qualification gates. Launch the
default macOS artifact with `open bin/Euclid.app`; a bare Mach-O process has no bundle
identity and Accessibility Inspector's point picker will ignore it. Verify the
Euclid application root, representative button, Settings relation, checkbox state,
slider range and actions, Search value and selection, filtered Tree rows and selection,
focus behavior, dynamic updates, and clean disappearance after window closure. Confirm
composite scrolling manually as an empirical check. Tree expansion and selected-text
replacement remain blocking AccessKit 0.27.1 differences for the parity freeze even
though their shared owner paths have deterministic coverage.
