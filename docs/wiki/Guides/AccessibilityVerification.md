# Accessibility Verification

## macOS ordinary controls

The qualified macOS workflow requires an Apple Silicon host, a logged-in GUI session,
the debug build, and Accessibility permission for the terminal or VS Code process that
runs the command.

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Enable the process that launches the repository command.
3. Build with `cmake --build --preset debug`.
4. Run `julia tools/make.jl accessibility-macos`.

The command launches `.build/debug/Euclid.app`, verifies its bundle identity and a
system-wide point hit, discovers controls through the macOS Accessibility API, operates
the Settings accordion, toggles a checkbox, adjusts a finite slider, presses the restart
button, closes the native window, and requires orderly provider removal. It writes
normalized evidence to `.build/accessibility-macos/ax.json`.

The retained AccessKit C 0.23.1 artifact uses `accesskit_macos` 0.27.1. That adapter maps
`DisclosureTriangle` to `AXButton` and `controls` to `AXLinkedUIElements`, but its native
node implementation has no expanded-state or busy-state selector. Euclid still publishes
both facts into the shared AccessKit tree and verifies them deterministically. The macOS
artifact records these two version-qualified adapter limitations and does not claim
native `AXExpanded` or `AXElementBusy` support.

Accessibility Inspector and VoiceOver remain manual qualification gates. Launch the
default macOS artifact with `open bin/Euclid.app`; a bare Mach-O process has no bundle
identity and Accessibility Inspector's point picker will ignore it. Verify the
Euclid application root, representative button, Settings relation, checkbox state,
slider range and actions, focus behavior, dynamic updates, and clean disappearance after
window closure.
