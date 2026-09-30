#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let bundle = root.appendingPathComponent(".build/debug/Euclid.app")
let binary = bundle.appendingPathComponent("Contents/MacOS/euclid")
let artifactDirectory = root.appendingPathComponent(".build/accessibility-macos")
let reportURL = artifactDirectory.appendingPathComponent("ax.json")
let diagnosticsURL = artifactDirectory.appendingPathComponent("session.log")

struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    return attribute(element, name) as? String
}

func numberAttribute(_ element: AXUIElement, _ name: String) -> NSNumber? {
    return attribute(element, name) as? NSNumber
}

func doubleAttribute(_ element: AXUIElement, _ name: String) -> Double? {
    if let number = numberAttribute(element, name) { return number.doubleValue }
    if let text = stringAttribute(element, name) { return Double(text) }
    return nil
}

func elementsAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    return attribute(element, name) as? [AXUIElement] ?? []
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    return elementsAttribute(element, kAXChildrenAttribute)
}

func descendants(_ root: AXUIElement, depth: Int = 8) -> [AXUIElement] {
    var result: [AXUIElement] = [root]
    guard depth > 0 else { return result }
    for child in children(root).prefix(512) {
        result.append(contentsOf: descendants(child, depth: depth - 1))
        if result.count >= 1024 { break }
    }
    return Array(result.prefix(1024))
}

func named(_ root: AXUIElement, _ name: String) -> AXUIElement? {
    return descendants(root).first {
        stringAttribute($0, kAXTitleAttribute) == name ||
            stringAttribute($0, kAXDescriptionAttribute) == name
    }
}

func namedRole(_ root: AXUIElement, _ name: String, _ role: String) -> AXUIElement? {
    return descendants(root).first {
        (stringAttribute($0, kAXTitleAttribute) == name ||
            stringAttribute($0, kAXDescriptionAttribute) == name) &&
            stringAttribute($0, kAXRoleAttribute) == role
    }
}

func waitForNamed(
    _ root: AXUIElement, _ name: String, process: Process,
    seconds: TimeInterval = 20
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if let element = named(root, name) { return element }
        if !process.isRunning {
            throw ProbeError(description: "Euclid exited before AX node \(name.debugDescription) appeared")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let visible = descendants(root).prefix(64).map {
        ["role": stringAttribute($0, kAXRoleAttribute) ?? "",
         "name": stringAttribute($0, kAXTitleAttribute) ??
            stringAttribute($0, kAXDescriptionAttribute) ?? ""]
    }
    throw ProbeError(description: "AX node \(name.debugDescription) was not discovered; tree=\(visible)")
}

func waitForNamedRole(
    _ root: AXUIElement, _ name: String, _ role: String, process: Process,
    seconds: TimeInterval = 20
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if let element = namedRole(root, name, role) { return element }
        if !process.isRunning {
            throw ProbeError(description: "Euclid exited before AX \(role) \(name.debugDescription) appeared")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ProbeError(description: "AX \(role) \(name.debugDescription) was not discovered")
}

func frame(_ element: AXUIElement) -> [String: Double]? {
    guard let positionValue = attribute(element, kAXPositionAttribute),
        let sizeValue = attribute(element, kAXSizeAttribute),
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
    return ["x": position.x, "y": position.y,
        "width": size.width, "height": size.height]
}

func systemWideElement(atFrameOf element: AXUIElement) throws -> AXUIElement {
    guard let bounds = frame(element),
        let x = bounds["x"], let y = bounds["y"],
        let width = bounds["width"], let height = bounds["height"] else {
        throw ProbeError(description: "AX element has no screen frame")
    }
    var hit: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
        AXUIElementCreateSystemWide(), Float(x + width / 2),
        Float(y + height / 2), &hit)
    guard result == .success, let hit else {
        throw ProbeError(description:
            "system-wide AX hit test failed with \(result.rawValue)")
    }
    return hit
}

func actionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String] ?? []).sorted()
}

func attributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
    return (names as? [String] ?? []).sorted()
}

func elementRecord(_ element: AXUIElement) -> [String: Any] {
    let linked = elementsAttribute(element, "AXLinkedUIElements").map {
        stringAttribute($0, kAXTitleAttribute) ??
            stringAttribute($0, kAXDescriptionAttribute) ?? ""
    }
    return [
        "role": stringAttribute(element, kAXRoleAttribute) ?? "",
        "subrole": stringAttribute(element, kAXSubroleAttribute) ?? "",
        "name": stringAttribute(element, kAXTitleAttribute) ??
            stringAttribute(element, kAXDescriptionAttribute) ?? "",
        "enabled": numberAttribute(element, kAXEnabledAttribute)?.boolValue ?? false,
        "focused": numberAttribute(element, kAXFocusedAttribute)?.boolValue ?? false,
        "value": stringAttribute(element, kAXValueAttribute) ??
            numberAttribute(element, kAXValueAttribute)?.stringValue ?? "",
        "minimum": numberAttribute(element, kAXMinValueAttribute)?.doubleValue as Any,
        "maximum": numberAttribute(element, kAXMaxValueAttribute)?.doubleValue as Any,
        "expanded": numberAttribute(element, "AXExpanded")?.boolValue as Any,
        "busy": numberAttribute(element, "AXElementBusy")?.boolValue as Any,
        "actions": actionNames(element),
        "attributes": attributeNames(element),
        "children": children(element).count,
        "linked": linked,
        "frame": frame(element) as Any,
    ]
}

func perform(_ element: AXUIElement, _ action: String) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else {
        throw ProbeError(description: "AX action \(action) failed with \(result.rawValue)")
    }
}

func closeApplicationWindow(_ application: AXUIElement) throws {
    guard let window = descendants(application).first(where: {
        stringAttribute($0, kAXRoleAttribute) == kAXWindowRole
    }), let closeValue = attribute(window, kAXCloseButtonAttribute) else {
        throw ProbeError(description: "Euclid AX window has no close button")
    }
    let closeButton = unsafeBitCast(closeValue, to: AXUIElement.self)
    try perform(closeButton, kAXPressAction)
}

func waitForRuntime(_ process: Process) throws {
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if process.isRunning,
           let text = try? String(contentsOf: diagnosticsURL, encoding: .utf8),
           text.contains("display_runtime_ready") { return }
        if !process.isRunning {
            throw ProbeError(description: "Euclid exited before display runtime readiness")
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ProbeError(description: "timed out waiting for Euclid display runtime readiness")
}

func runProbe() throws -> [String: Any] {
    guard AXIsProcessTrusted() else {
        throw ProbeError(description: "Accessibility permission is required for the terminal running this command (System Settings > Privacy & Security > Accessibility)")
    }
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
        throw ProbeError(description: "debug binary missing; run cmake --build --preset debug")
    }
    try? FileManager.default.removeItem(at: artifactDirectory)
    try FileManager.default.createDirectory(
        at: artifactDirectory, withIntermediateDirectories: true)

    let visibleInspectors = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName == "Accessibility Inspector" && !$0.isHidden
    }
    visibleInspectors.forEach { $0.hide() }
    defer { visibleInspectors.forEach { $0.unhide() } }

    let process = Process()
    process.executableURL = binary
    process.currentDirectoryURL = root
    process.arguments = [
        "--window-mode=resizable",
        "--diagnostics=\(diagnosticsURL.path)",
    ]
    process.standardOutput = FileHandle.nullDevice
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    try waitForRuntime(process)
    guard let runningApplication = NSRunningApplication(
        processIdentifier: process.processIdentifier),
        runningApplication.bundleIdentifier == "app.euclid.Euclid" else {
        throw ProbeError(description: "Euclid is not running from its macOS application bundle")
    }
    runningApplication.activate(options: [.activateAllWindows])
    let application = AXUIElementCreateApplication(process.processIdentifier)
    let restart = try waitForNamed(
        application, "Restart animation", process: process)
    let hitDeadline = Date().addingTimeInterval(5)
    var systemWideRestart: AXUIElement?
    while Date() < hitDeadline {
        if let hit = try? systemWideElement(atFrameOf: restart) {
            var hitPID: pid_t = 0
            AXUIElementGetPid(hit, &hitPID)
            if hitPID == process.processIdentifier,
                stringAttribute(hit, kAXRoleAttribute) == kAXButtonRole,
                stringAttribute(hit, kAXTitleAttribute) == "Restart animation" {
                systemWideRestart = hit
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let systemWideRestart else {
        throw ProbeError(description:
            "system-wide AX hit test did not resolve Restart animation")
    }
    let systemWideRestartRecord = elementRecord(systemWideRestart)
    let settings = try waitForNamedRole(
        application, "Settings", kAXButtonRole, process: process)
    let applicationBefore = elementRecord(application)
    let restartBefore = elementRecord(restart)
    try perform(settings, kAXPressAction)
    Thread.sleep(forTimeInterval: 0.1)
    let updatedSettings = try waitForNamedRole(
        application, "Settings", kAXButtonRole, process: process)
    let settingsAfter = elementRecord(updatedSettings)
    let settingsNodes = descendants(application).filter {
        stringAttribute($0, kAXTitleAttribute) == "Settings" ||
            stringAttribute($0, kAXDescriptionAttribute) == "Settings"
    }.map(elementRecord)
    let checkbox = try waitForNamed(application, "Display FPS", process: process)
    let slider = try waitForNamed(
        application, "Maximum Dust particles", process: process)
    let checkboxBefore = elementRecord(checkbox)
    try perform(checkbox, kAXPressAction)
    Thread.sleep(forTimeInterval: 0.1)
    let updatedCheckbox = try waitForNamed(
        application, "Display FPS", process: process)
    let checkboxAfter = elementRecord(updatedCheckbox)
    let sliderBefore = elementRecord(slider)
    let sliderActions = actionNames(slider)
    let current = doubleAttribute(slider, kAXValueAttribute)
    let maximum = doubleAttribute(slider, kAXMaxValueAttribute)
    let sliderAction: String
    if current == maximum && sliderActions.contains(kAXDecrementAction) {
        sliderAction = kAXDecrementAction
    } else if sliderActions.contains(kAXIncrementAction) {
        sliderAction = kAXIncrementAction
    } else {
        throw ProbeError(description: "slider exposes no usable range action")
    }
    try perform(slider, sliderAction)
    Thread.sleep(forTimeInterval: 0.1)
    let updatedSlider = try waitForNamed(
        application, "Maximum Dust particles", process: process)
    let sliderAfter = elementRecord(updatedSlider)
    try perform(restart, kAXPressAction)

    guard restartBefore["role"] as? String == kAXButtonRole else {
        throw ProbeError(description: "restart control is not an AXButton")
    }
    guard checkboxBefore["role"] as? String == kAXCheckBoxRole else {
        throw ProbeError(description: "settings toggle is not an AXCheckBox")
    }
    guard sliderBefore["role"] as? String == kAXSliderRole else {
        throw ProbeError(description: "maximum dust is not an AXSlider")
    }
    guard let linked = settingsAfter["linked"] as? [String],
          linked.contains("Settings"), settingsNodes.count >= 2 else {
        throw ProbeError(description: "Settings header does not control its active panel; header=\(settingsAfter) nodes=\(settingsNodes)")
    }
    if let bounds = restartBefore["frame"] as? [String: Double],
       (bounds["width"] ?? -1) < 0 || (bounds["height"] ?? -1) < 0 {
        throw ProbeError(description: "restart bounds are inverted")
    }
    guard let restartFrame = restartBefore["frame"] as? [String: Double],
        abs((restartFrame["width"] ?? 0) - 30) < 0.01,
        abs((restartFrame["height"] ?? 0) - 30) < 0.01 else {
        throw ProbeError(description:
            "Restart accessibility frame does not match its 30-point visual bounds")
    }
    guard String(describing: checkboxBefore["value"] ?? "") !=
          String(describing: checkboxAfter["value"] ?? "") else {
        throw ProbeError(description: "checkbox value did not change after AXPress")
    }
    guard String(describing: sliderBefore["value"] ?? "") !=
          String(describing: sliderAfter["value"] ?? "") else {
                throw ProbeError(description:
                    "slider value did not change after \(sliderAction); before=\(sliderBefore) after=\(sliderAfter)")
    }

    try closeApplicationWindow(application)
    let shutdownDeadline = Date().addingTimeInterval(20)
    while process.isRunning && Date() < shutdownDeadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard !process.isRunning else {
        throw ProbeError(description: "Euclid did not exit after AX window close")
    }
    guard process.terminationStatus == 0 else {
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        throw ProbeError(description: "Euclid shutdown failed: \(String(decoding: data, as: UTF8.self))")
    }
    return [
        "schema_version": 1,
        "bundle_identifier": runningApplication.bundleIdentifier as Any,
        "application": applicationBefore,
        "restart": restartBefore,
        "system_wide_restart": systemWideRestartRecord,
        "settings": ["header": settingsAfter, "named_nodes": settingsNodes],
        "checkbox": ["before": checkboxBefore, "after": checkboxAfter],
        "slider": ["before": sliderBefore, "after": sliderAfter,
            "invoked_action": sliderAction],
        "adapter_limitations": [
            "accesskit_macos_0_27_1_does_not_implement_expanded",
            "accesskit_macos_0_27_1_does_not_implement_busy",
        ],
        "removed_after_shutdown": children(application).isEmpty,
    ]
}

do {
    let report = try runProbe()
    let data = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: reportURL)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("accessibility macOS probe failed: \(error)\n".utf8))
    exit(1)
}
