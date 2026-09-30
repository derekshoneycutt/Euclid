# Accessibility Verification

## Windows Phase 2 ordinary controls

The Windows workflow requires Windows 11 x64, .NET SDK 10 or newer, a logged-in
interactive desktop session, and the debug build. Run `cmake --build --preset debug`, then
`julia tools/make.jl accessibility-windows`.

The command compiles and runs the file-based C# UI Automation probe, then runs two
complete application sessions. Each session verifies the application root; Restart
and Pause/Resume Invoke behavior; ordered top-level controls; both splitter ranges and
orientations; Settings ExpandCollapse behavior and panel presence; Display FPS Toggle
in both directions; Maximum Dust range stepping, direct set, invalid-value rejection,
and restoration; idle GIF controls and status; runtime identity continuity; focus
movement; owner-observed reset; clean process exit; and provider removal. Normalized
schema-versioned evidence is written to `.build/accessibility-windows/uia.json`;
session logs and scenario artifacts are stored beside it.

The inbox managed UIA client reports the Settings `ControllerFor` property as
unsupported even though the shared tree publishes the relation and Accessibility
Insights can inspect the native tree. Transient GIF recording busy/disabled states and
multi-DPI/resize bounds remain separate Phase 2 gates and are listed in the artifact's
`limitations` field rather than claimed by this stable-control probe.

Euclid starts with the Library accordion active. Controls belonging to Settings or
Save GIF are intentionally absent while those panels are collapsed. For manual review,
activate Settings in Euclid or invoke its ExpandCollapse pattern, then refresh or
reselect the Euclid root in Accessibility Insights if Live Inspect is not tracking tree
updates. Display FPS and the remaining Settings controls should then appear beneath the
Settings pane. Repeat with Save GIF to inspect its buttons, ranges, and status node.
Use a freshly built `bin/euclid.exe`; the automated command targets the debug executable
unless `--binary=bin/euclid.exe` is supplied.

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
