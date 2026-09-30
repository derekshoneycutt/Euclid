#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let bundle = root.appendingPathComponent(".build/debug/Euclid.app")
let binary = bundle.appendingPathComponent("Contents/MacOS/euclid")
let artifactDirectory = root.appendingPathComponent(".build/accessibility-macos")
let reportURL = artifactDirectory.appendingPathComponent("ax.json")
let searchLabel = "Search animations"
let searchQuery = "Elements"
let retirementQuery = "algebra"
let treeLabel = "Animation library"

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

func outlineRows(_ element: AXUIElement) -> [AXUIElement] {
    let rows = elementsAttribute(element, "AXRows")
    return rows.isEmpty ? children(element) : rows
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

func textRecord(_ element: AXUIElement) -> [String: Any] {
    var selection = CFRange(location: 0, length: 0)
    var selectedRange: [String: Int]?
    if let value = attribute(element, kAXSelectedTextRangeAttribute),
       CFGetTypeID(value) == AXValueGetTypeID(),
       AXValueGetValue(value as! AXValue, .cfRange, &selection) {
        selectedRange = ["location": selection.location, "length": selection.length]
    }
    return [
        "value": stringAttribute(element, kAXValueAttribute) ?? "",
        "selected_text": stringAttribute(element, kAXSelectedTextAttribute) ?? "",
        "selected_range": selectedRange as Any,
    ]
}

func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
    let result = AXUIElementSetAttributeValue(element, name as CFString, value)
    guard result == .success else {
        throw ProbeError(description:
            "setting AX attribute \(name) failed with \(result.rawValue)")
    }
}

func waitForText(
    _ root: AXUIElement, _ expected: String, process: Process,
    seconds: TimeInterval = 5
) throws -> (AXUIElement, [String: Any]) {
    let deadline = Date().addingTimeInterval(seconds)
    var last: [String: Any] = [:]
    while Date() < deadline {
        if let search = named(root, searchLabel) {
            last = textRecord(search)
            if last["value"] as? String == expected { return (search, last) }
        }
        if !process.isRunning {
            throw ProbeError(description: "Euclid exited during AX text update")
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ProbeError(description:
        "AX text did not reach \(expected.debugDescription); last=\(last)")
}

func setTextSelection(
    _ root: AXUIElement, location: Int, length: Int, process: Process
) throws -> [String: Any] {
    var range = CFRange(location: location, length: length)
    guard let rangeValue = AXValueCreate(.cfRange, &range) else {
        throw ProbeError(description: "could not create AX text range")
    }
    guard let search = named(root, searchLabel) else {
        throw ProbeError(description: "Search disappeared before AX selection")
    }
    try setAttribute(search, kAXSelectedTextRangeAttribute, rangeValue)
    let deadline = Date().addingTimeInterval(3)
    var last = textRecord(search)
    while Date() < deadline {
        guard let current = named(root, searchLabel) else { break }
        last = textRecord(current)
        if let selected = last["selected_range"] as? [String: Int],
           selected["location"] == location, selected["length"] == length {
            return last
        }
        if !process.isRunning { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ProbeError(description: "AX text selection did not update; last=\(last)")
}

func rejectInvalidTextSelection(
    _ root: AXUIElement, location: Int, length: Int, process: Process
) throws -> [String: Any] {
    guard let search = named(root, searchLabel) else {
        throw ProbeError(description: "Search disappeared before invalid AX selection")
    }
    let before = textRecord(search)
    var range = CFRange(location: location, length: length)
    guard let rangeValue = AXValueCreate(.cfRange, &range) else {
        throw ProbeError(description: "could not create invalid AX text range")
    }
    let result = AXUIElementSetAttributeValue(
        search, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    Thread.sleep(forTimeInterval: 0.2)
    guard process.isRunning, let current = named(root, searchLabel) else {
        throw ProbeError(description: "Search disappeared after invalid AX selection")
    }
    let after = textRecord(current)
    let beforeRange = before["selected_range"] as? [String: Int]
    let afterRange = after["selected_range"] as? [String: Int]
    guard beforeRange?["location"] == afterRange?["location"],
          beforeRange?["length"] == afterRange?["length"],
          before["value"] as? String == after["value"] as? String else {
        throw ProbeError(description:
            "invalid AX text selection mutated Search; before=\(before) after=\(after)")
    }
    return ["result": result.rawValue, "after": after]
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
        "selected": numberAttribute(element, kAXSelectedAttribute)?.boolValue as Any,
        "identifier": stringAttribute(element, kAXIdentifierAttribute) as Any,
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

func rangeRecord(_ element: AXUIElement) -> [String: Double]? {
    guard let current = doubleAttribute(element, kAXValueAttribute),
          let minimum = doubleAttribute(element, kAXMinValueAttribute),
          let maximum = doubleAttribute(element, kAXMaxValueAttribute) else {
        return nil
    }
    return ["current": current, "minimum": minimum, "maximum": maximum]
}

func waitForNamedState(
    _ root: AXUIElement, _ name: String, process: Process,
    seconds: TimeInterval = 5, predicate: (AXUIElement) -> Bool
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(seconds)
    var last: AXUIElement?
    while Date() < deadline {
        if let element = named(root, name) {
            last = element
            if predicate(element) { return element }
        }
        if !process.isRunning {
            throw ProbeError(description:
                "Euclid exited while waiting for AX node \(name.debugDescription)")
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    let detail: Any = last.map { element in
        ["node": elementRecord(element),
         "rows": outlineRows(element).map {
             stringAttribute($0, kAXTitleAttribute) ??
                 stringAttribute($0, kAXDescriptionAttribute) ?? ""
         }] as [String: Any]
    } as Any
    throw ProbeError(description:
        "AX node \(name.debugDescription) did not reach the required state; last=\(detail)")
}

func waitForFilteredTree(
    _ root: AXUIElement, required: String, absent: [String], process: Process
) throws -> AXUIElement {
    return try waitForNamedState(root, treeLabel, process: process) { tree in
        let names = outlineRows(tree).compactMap {
            stringAttribute($0, kAXTitleAttribute) ??
                stringAttribute($0, kAXDescriptionAttribute)
        }
        return names.contains(required) && !absent.contains(where: names.contains)
    }
}

func waitForTreeRowState(
    _ root: AXUIElement, _ name: String, process: Process,
    predicate: (AXUIElement) -> Bool
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let tree = named(root, treeLabel),
           let row = outlineRows(tree).first(where: {
               stringAttribute($0, kAXTitleAttribute) == name ||
                   stringAttribute($0, kAXDescriptionAttribute) == name
           }), predicate(row) { return row }
        if !process.isRunning { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ProbeError(description:
        "AX Tree row \(name.debugDescription) did not reach the required state")
}

func waitForElementRemoval(
    _ root: AXUIElement, target: AXUIElement, process: Process
) throws {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        let currentTrees = descendants(root).filter {
            (stringAttribute($0, kAXTitleAttribute) ??
                stringAttribute($0, kAXDescriptionAttribute)) == treeLabel
        }
        let retained = currentTrees.flatMap(outlineRows).contains {
            CFEqual($0, target)
        }
        if !retained { return }
        if !process.isRunning { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ProbeError(description:
        "retired AX Tree item remained discoverable")
}

func performFirst(_ element: AXUIElement, _ accepted: [String]) throws -> String {
    let available = actionNames(element)
    guard let action = accepted.first(where: { available.contains($0) }) else {
        throw ProbeError(description:
            "AX element exposes none of \(accepted); actions=\(available)")
    }
    try perform(element, action)
    return action
}

func exerciseTreeBranch(
    _ root: AXUIElement, process _: Process
) throws -> [String: Any] {
    guard let tree = named(root, treeLabel) else {
        throw ProbeError(description: "Animation Tree disappeared before branch test")
    }
    guard let branch = outlineRows(tree).first(where: {
              $0 !== tree && actionNames($0).contains("AXPick")
          }) else {
        let summary = outlineRows(tree).prefix(64).map {
            ["name": stringAttribute($0, kAXTitleAttribute) ??
                stringAttribute($0, kAXDescriptionAttribute) ?? "",
             "role": stringAttribute($0, kAXRoleAttribute) ?? "",
             "children": children($0).count,
             "actions": actionNames($0)] as [String: Any]
        }
        throw ProbeError(description:
            "Animation Tree has no operable branch; tree=\(summary)")
    }
    let name = stringAttribute(branch, kAXTitleAttribute) ??
        stringAttribute(branch, kAXDescriptionAttribute) ?? ""
    return ["node": elementRecord(branch), "name": name,
        "row_count": outlineRows(tree).count,
        "native_operation": "unavailable"]
}

func exerciseTreeScroll(
    _ root: AXUIElement, process: Process
) throws -> [String: Any] {
    guard let tree = named(root, treeLabel), let before = rangeRecord(tree) else {
        throw ProbeError(description: "Animation Tree has no finite AX range")
    }
    let current = before["current"] ?? 0
    let minimum = before["minimum"] ?? 0
    let maximum = before["maximum"] ?? 0
    guard maximum > minimum else {
        throw ProbeError(description: "Animation Tree has no positive AX scroll extent")
    }
    let target = abs(current - maximum) > 0.01 ? maximum : minimum
    try setAttribute(tree, kAXValueAttribute, NSNumber(value: target))
    let updated = try waitForNamedState(root, treeLabel, process: process) {
        guard let value = rangeRecord($0)?["current"] else { return false }
        return abs(value - target) < 0.01
    }
    return ["before": before, "after": rangeRecord(updated) as Any,
        "requested": target]
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

func waitForRuntime(_ process: Process, diagnosticsURL: URL) throws {
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

func runProbe(sessionIndex: Int) throws -> [String: Any] {
    guard AXIsProcessTrusted() else {
        throw ProbeError(description: "Accessibility permission is required for the terminal running this command (System Settings > Privacy & Security > Accessibility)")
    }
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
        throw ProbeError(description: "debug binary missing; run cmake --build --preset debug")
    }
    let diagnosticsURL = artifactDirectory.appendingPathComponent(
        "session-\(sessionIndex).log")

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

    try waitForRuntime(process, diagnosticsURL: diagnosticsURL)
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
    let search = try waitForNamed(application, searchLabel, process: process)
    let searchNode = elementRecord(search)
    let tree = try waitForNamed(application, treeLabel, process: process)
    let treeNode = elementRecord(tree)
    let survivingAlgebra = outlineRows(tree).first {
        stringAttribute($0, kAXTitleAttribute) == "Algebra"
    }
    let linkedNames = elementsAttribute(search, "AXLinkedUIElements").map {
        stringAttribute($0, kAXTitleAttribute) ??
            stringAttribute($0, kAXDescriptionAttribute) ?? ""
    }
    guard linkedNames.contains(treeLabel) else {
        throw ProbeError(description:
            "Search does not expose its controlled Tree; linked=\(linkedNames)")
    }
    let branch = try exerciseTreeBranch(application, process: process)
    let searchBefore = textRecord(search)
    try setAttribute(search, kAXValueAttribute, searchQuery as CFString)
    let (_, searchCommitted) = try waitForText(
        application, searchQuery, process: process)
    let searchSelected = try setTextSelection(
        application, location: 0, length: searchQuery.count, process: process)
    let invalidSelection = try rejectInvalidTextSelection(
        application, location: 100, length: 1, process: process)
    guard let selectedSearch = named(application, searchLabel) else {
        throw ProbeError(description: "Search disappeared before selected replacement")
    }
    var selectedTextSettable = DarwinBoolean(false)
    let selectedTextSettableResult = AXUIElementIsAttributeSettable(
        selectedSearch, kAXSelectedTextAttribute as CFString,
        &selectedTextSettable)
    let selectedReplacement: [String: Any] = [
        "settable": selectedTextSettableResult == .success &&
            selectedTextSettable.boolValue,
        "native_operation": "unavailable",
    ]
    let restoredSearch = textRecord(selectedSearch)
    let filteredTree = try waitForFilteredTree(
        application, required: "Euclid's Elements",
        absent: ["Terminal"],
        process: process)
    let treeScroll = try exerciseTreeScroll(application, process: process)
    let survivingIdentityContinuous = survivingAlgebra.map { prior in
        outlineRows(filteredTree).contains { current in CFEqual(prior, current) }
    } ?? false
    guard survivingIdentityContinuous else {
        throw ProbeError(description: "surviving Algebra AX row changed identity")
    }
    let filteredStatus = try waitForNamed(
        application, "Library search status", process: process)
    let filteredStatusRecord = elementRecord(filteredStatus)
    guard let selectedItem = outlineRows(filteredTree).first(where: {
        stringAttribute($0, kAXTitleAttribute) == "Euclid's Elements" &&
            actionNames($0).contains("AXPick")
    }) else {
        throw ProbeError(description: "filtered Animation Tree has no selectable item")
    }
    let itemBefore = elementRecord(selectedItem)
    let itemIdentityHash = CFHash(selectedItem)
    let itemAction = try performFirst(selectedItem, ["AXPick"])
    let itemName = stringAttribute(selectedItem, kAXTitleAttribute) ?? ""
    let selectedItemAfter = try waitForTreeRowState(
        application, itemName, process: process) {
            numberAttribute($0, kAXSelectedAttribute)?.boolValue == true
        }
    try setAttribute(search, kAXValueAttribute, retirementQuery as CFString)
    let (_, retirementText) = try waitForText(
        application, retirementQuery, process: process)
    _ = try waitForFilteredTree(
        application, required: "Algebra", absent: ["Euclid's Elements"],
        process: process)
    let retirementStatus = try waitForNamed(
        application, "Library search status", process: process)
    let retirementStatusRecord = elementRecord(retirementStatus)
    try waitForElementRemoval(
        application, target: selectedItem, process: process)
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
        "session_index": sessionIndex,
        "bundle_identifier": runningApplication.bundleIdentifier as Any,
        "application": applicationBefore,
        "restart": restartBefore,
        "system_wide_restart": systemWideRestartRecord,
        "search": ["node": searchNode, "before": searchBefore,
            "committed": searchCommitted, "selected": searchSelected,
            "invalid_selection": invalidSelection,
            "selected_replacement": selectedReplacement,
            "restored": restoredSearch, "linked": linkedNames,
            "filtered_status": filteredStatusRecord,
            "retirement_status": retirementStatusRecord,
            "retirement_text": retirementText],
        "tree": ["node": treeNode, "branch": branch, "scroll": treeScroll,
            "item_before": itemBefore,
            "item_after": elementRecord(selectedItemAfter),
            "item_action": itemAction, "retired_identity_hash": itemIdentityHash,
            "retired_after_filter": true,
            "surviving_identity_continuous": survivingIdentityContinuous],
        "settings": ["header": settingsAfter, "named_nodes": settingsNodes],
        "checkbox": ["before": checkboxBefore, "after": checkboxAfter],
        "slider": ["before": sliderBefore, "after": sliderAfter,
            "invoked_action": sliderAction],
        "adapter_limitations": [
            "accesskit_macos_0_27_1_does_not_implement_expanded",
            "accesskit_macos_0_27_1_does_not_implement_busy",
            "accesskit_macos_0_27_1_tree_expansion_actions_are_not_operable",
            "accesskit_macos_0_27_1_selected_text_replacement_is_not_operable",
        ],
        "removed_after_shutdown": children(application).isEmpty,
    ]
}

do {
    try? FileManager.default.removeItem(at: artifactDirectory)
    try FileManager.default.createDirectory(
        at: artifactDirectory, withIntermediateDirectories: true)
    let sessions = try (1...2).map { try runProbe(sessionIndex: $0) }
    guard sessions.allSatisfy({ $0["removed_after_shutdown"] as? Bool == true }) else {
        throw ProbeError(description: "one repeated AX session retained its provider")
    }
    let report: [String: Any] = [
        "schema_version": 3,
        "session_count": sessions.count,
        "repeated_teardown": true,
        "sessions": sessions,
    ]
    let data = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: reportURL)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("accessibility macOS probe failed: \(error)\n".utf8))
    exit(1)
}
