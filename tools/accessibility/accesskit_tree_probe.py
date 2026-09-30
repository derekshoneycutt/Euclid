#!/usr/bin/env python3
"""Capture and validate Euclid's Phase 3 and 4 AT-SPI controls on Linux."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback

import pyatspi


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build" / "debug" / "euclid"
ARTIFACTS = Path(".build/accessibility-button")
REPORT = ROOT / ARTIFACTS / "atspi.json"
RESTART_LABEL = "Restart animation"
SETTINGS_LABEL = "Settings"
LIBRARY_LABEL = "Library"
CHECKBOX_LABEL = "Display FPS"
SLIDER_LABEL = "Maximum Dust particles"
SEARCH_LABEL = "Search animations"
TREE_LABEL = "Animation library"
SEARCH_QUERY = "Elements"
RETIREMENT_QUERY = "algebra"
SCENARIO = Path("tools/accessibility/accessibility-button-acceptance.jsonl")
WINDOW_SELECTOR = "class:^euclid$"


def descendants(node, depth: int = 4):
    """Yield one bounded preorder traversal from an AT-SPI accessible."""
    yield node
    if depth == 0:
        return
    try:
        children = list(node)
    except Exception:
        return
    for child in children:
        yield from descendants(child, depth - 1)


def find_named(label: str):
    """Return the first Euclid node with one exact accessible name."""
    desktop = pyatspi.Registry.getDesktop(0)
    try:
        applications = list(desktop)
    except Exception:
        return None, None
    for application in applications:
        try:
            for node in descendants(application):
                if node.name == label:
                    return application, node
        except Exception:
            continue
    return None, None


def desktop_summary() -> list[dict]:
    """Return bounded names and roles for diagnosing failed native discovery."""
    records = []
    desktop = pyatspi.Registry.getDesktop(0)
    try:
        applications = list(desktop)
    except Exception:
        return records
    for application in applications:
        try:
            nodes = list(descendants(application, 3))[:32]
            records.append({
                "application": application.name,
                "nodes": [
                    {"name": node.name, "role": node.getRoleName()}
                    for node in nodes
                ],
            })
        except Exception as error:
            records.append({"error": str(error)})
    return records


def node_record(node) -> dict:
    """Normalize stable machine-readable role, state, relation, and bounds facts."""
    try:
        extents = node.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
        bounds = {
            "x": extents.x,
            "y": extents.y,
            "width": extents.width,
            "height": extents.height,
        }
    except NotImplementedError:
        bounds = None
    states = sorted(
        pyatspi.stateToString(state) for state in node.getState().getStates())
    try:
        accessible_id = node.get_accessible_id()
    except (AttributeError, NotImplementedError):
        accessible_id = None
    try:
        parent_path = str(node.parent.path)
    except (AttributeError, NotImplementedError):
        parent_path = None
    return {
        "accessible_id": accessible_id,
        "object_path": str(node.path),
        "parent_path": parent_path,
        "name": node.name,
        "role": node.getRoleName(),
        "child_count": node.childCount,
        "index_in_parent": node.getIndexInParent(),
        "states": states,
        "focused": "focused" in states,
        "bounds": bounds,
        "attributes": dict(node.get_attributes() or {}),
    }


def relation_records(node) -> list[dict]:
    """Normalize one node's bounded AT-SPI relation targets."""
    records = []
    for relation in node.getRelationSet():
        targets = []
        for index in range(relation.getNTargets()):
            target = relation.getTarget(index)
            targets.append({
                "name": target.name,
                "object_path": str(target.path),
            })
        records.append({
            "type": pyatspi.relationToString(relation.getRelationType()),
            "targets": targets,
        })
    return records


def wait_for_named(label: str, timeout_seconds: float = 25.0):
    """Wait for AccessKit activation and return one exact named node."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        application, child = find_named(label)
        if child is not None:
            return application, child
        time.sleep(0.1)
    raise RuntimeError(
        f"Euclid accessibility node {label!r} was not discovered; "
        f"desktop={json.dumps(desktop_summary(), sort_keys=True)}")


def wait_for_removal(timeout_seconds: float = 5.0) -> bool:
    """Return true once the button has disappeared after process shutdown."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        _, child = find_named(RESTART_LABEL)
        if child is None:
            return True
        time.sleep(0.1)
    return False


def wait_for_node_record(node, predicate, timeout_seconds: float = 3.0) -> dict:
    """Wait until one live AT-SPI record satisfies a host-transition predicate."""
    deadline = time.monotonic() + timeout_seconds
    last_record = node_record(node)
    while time.monotonic() < deadline:
        last_record = node_record(node)
        if predicate(last_record):
            return last_record
        time.sleep(0.05)
    raise RuntimeError(f"AT-SPI host transition timed out; last={last_record}")


def action_names(node) -> list[str]:
    """Return normalized actions exposed by one AT-SPI accessible."""
    action = node.queryAction()
    return [action.getName(index) for index in range(action.nActions)]


def focus_button(node) -> dict:
    """Request native focus and return the resulting focused record."""
    if not node.queryComponent().grabFocus():
        raise RuntimeError("AT-SPI rejected restart-button focus")
    time.sleep(0.1)
    return node_record(node)


def invoke_action(node, accepted_names: tuple[str, ...]) -> str:
    """Invoke the first native action whose normalized name is accepted."""
    action = node.queryAction()
    for index in range(action.nActions):
        name = action.getName(index)
        if name.lower() in accepted_names:
            if not action.doAction(index):
                raise RuntimeError(f"AT-SPI action was rejected: {name}")
            return name
    raise RuntimeError(
        f"{node.name!r} has no accepted action: {action_names(node)}")


def value_record(node) -> dict:
    """Normalize one AT-SPI ranged-value record."""
    value = node.queryValue()
    return {
        "current": value.currentValue,
        "minimum": value.minimumValue,
        "maximum": value.maximumValue,
        "step": value.minimumIncrement,
    }


def increment_value(node, before: dict) -> float:
    """Request one bounded increment through the AT-SPI Value interface."""
    target = min(before["maximum"], before["current"] + before["step"])
    if target <= before["current"]:
        target = max(before["minimum"], before["current"] - before["step"])
    node.queryValue().currentValue = target
    return target


def text_record(node) -> dict:
    """Normalize committed text, caret, and the first selection."""
    try:
        text = node.queryText()
    except NotImplementedError as error:
        raise RuntimeError(
            f"{node.name!r} has no AT-SPI Text interface; "
            f"node={node_record(node)} "
            f"interfaces={node.get_interfaces()}") from error
    record = {
        "text": text.getText(0, -1),
        "character_count": text.characterCount,
        "caret": text.caretOffset,
        "selection_count": text.getNSelections(),
        "selection": None,
    }
    if record["selection_count"] > 0:
        start, end = text.getSelection(0)
        record["selection"] = {"start": start, "end": end}
    return record


def wait_for_text(node, expected: str, timeout_seconds: float = 5.0) -> dict:
    """Wait for one committed native text value."""
    deadline = time.monotonic() + timeout_seconds
    last = text_record(node)
    while time.monotonic() < deadline:
        last = text_record(node)
        if last["text"] == expected:
            return last
        time.sleep(0.05)
    raise RuntimeError(f"AT-SPI text transition timed out; last={last}")


def replace_text(node, value: str) -> dict:
    """Replace one editable value and wait for owner publication."""
    node.queryEditableText().setTextContents(value)
    return wait_for_text(node, value)


def set_text_selection(node, start: int, end: int) -> dict:
    """Set one text selection and wait for its owner-published range."""
    text = node.queryText()
    if text.getNSelections() == 0:
        accepted = text.addSelection(start, end)
    else:
        accepted = text.setSelection(0, start, end)
    if not accepted:
        raise RuntimeError("AT-SPI rejected Search text selection")
    deadline = time.monotonic() + 3.0
    last = text_record(node)
    while time.monotonic() < deadline:
        last = text_record(node)
        if last["selection"] == {"start": start, "end": end}:
            return last
        time.sleep(0.05)
    raise RuntimeError(f"AT-SPI selection transition timed out; last={last}")


def find_descendant_by_role(node, role: str):
    """Return the first bounded descendant with one normalized role."""
    for candidate in descendants(node, 6):
        if candidate is not node and candidate.getRoleName() == role:
            return candidate
    return None


def find_expanded_tree_branch(tree):
    """Return one visible TreeItem branch with published children."""
    for candidate in descendants(tree, 8):
        if candidate.getRoleName() == "tree item" and candidate.childCount > 0:
            return candidate
    return None


def wait_for_child_count(node, predicate, timeout_seconds: float = 3.0) -> dict:
    """Wait until one live node's child count satisfies a topology predicate."""
    deadline = time.monotonic() + timeout_seconds
    last = node_record(node)
    while time.monotonic() < deadline:
        last = node_record(node)
        if predicate(last["child_count"]):
            return last
        time.sleep(0.05)
    raise RuntimeError(f"AT-SPI child topology transition timed out; last={last}")


def exercise_tree_branch_toggle(tree) -> dict:
    """Collapse and restore one branch through AccessKit Unix's click action."""
    branch = find_expanded_tree_branch(tree)
    if branch is None:
        raise RuntimeError("Tree has no expanded branch for native toggle testing")
    before = node_record(branch)
    actions = action_names(branch)
    collapse_action = invoke_action(branch, ("click",))
    collapsed = wait_for_child_count(branch, lambda count: count == 0)
    expand_action = invoke_action(branch, ("click",))
    expanded = wait_for_child_count(branch, lambda count: count > 0)
    return {
        "before": before,
        "collapsed": collapsed,
        "expanded": expanded,
        "actions": actions,
        "collapse_action": collapse_action,
        "expand_action": expand_action,
    }


def wait_for_filtered_tree(
        required_name: str, absent_name: str,
        timeout_seconds: float = 5.0):
    """Wait until one query replaces the prior Tree topology."""
    deadline = time.monotonic() + timeout_seconds
    last_names = []
    while time.monotonic() < deadline:
        _, tree = find_named(TREE_LABEL)
        if tree is not None:
            last_names = [candidate.name for candidate in descendants(tree, 8)]
            if required_name in last_names and absent_name not in last_names:
                return tree
        time.sleep(0.05)
    raise RuntimeError(
        f"filtered topology timed out; names={last_names}")


def wait_for_path_removal(object_path: str, timeout_seconds: float = 5.0) -> bool:
    """Return true once an object path leaves Euclid's accessible tree."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        _, tree = find_named(TREE_LABEL)
        if tree is None:
            time.sleep(0.05)
            continue
        paths = {str(node.path) for node in descendants(tree, 8)}
        if object_path not in paths:
            return True
        time.sleep(0.05)
    return False


def node_at_path(node, object_path: str):
    """Describe the current descendant occupying one AT-SPI object path."""
    for candidate in descendants(node, 8):
        if str(candidate.path) == object_path:
            return node_record(candidate)
    return None


def descendant_summary(node) -> list[dict]:
    """Describe the bounded current subtree for retirement diagnostics."""
    return [{
        "name": candidate.name,
        "description": candidate.description,
        "role": candidate.getRoleName(),
        "path": str(candidate.path),
    } for candidate in descendants(node, 8)]


def exercise_search_and_tree() -> dict:
    """Operate Phase 4 editable Search and its controlled Tree."""
    _, search = wait_for_named(SEARCH_LABEL)
    _, tree = wait_for_named(TREE_LABEL)
    branch_toggle = exercise_tree_branch_toggle(tree)
    initial_text = text_record(search)
    relations = relation_records(search)
    controlled_paths = {
        target["object_path"] for relation in relations
        if relation["type"] in ("controller for", "controller-for")
        for target in relation["targets"]
    }
    if str(tree.path) not in controlled_paths:
        raise RuntimeError(f"Search does not control Tree: {relations}")
    committed = replace_text(search, SEARCH_QUERY)
    selected = set_text_selection(search, 0, len(SEARCH_QUERY))
    tree = wait_for_filtered_tree("Euclid's Elements", "Terminal")
    items = [candidate for candidate in descendants(tree, 8)
             if candidate.getRoleName() == "tree item"]
    item = next((candidate for candidate in reversed(items)
                 if candidate.childCount == 0), None)
    if item is None:
        raise RuntimeError("filtered Tree has no TreeItem descendant")
    item_before = node_record(item)
    item_actions = action_names(item)
    tree_value_before = value_record(tree)
    scroll_target = increment_value(tree, tree_value_before)
    deadline = time.monotonic() + 3.0
    tree_value_after = value_record(tree)
    while tree_value_after["current"] != scroll_target and \
            time.monotonic() < deadline:
        time.sleep(0.05)
        tree_value_after = value_record(tree)
    if tree_value_after["current"] != scroll_target:
        raise RuntimeError("native Tree scroll value did not reach its target")
    item_action = invoke_action(item, ("click", "select", "activate"))
    item_after = wait_for_node_record(
        item, lambda record: "selected" in record["states"])
    retired_path = str(item.path)
    replacement = replace_text(search, RETIREMENT_QUERY)
    _ = wait_for_filtered_tree("Algebra", "Euclid's Elements")
    if not wait_for_path_removal(retired_path):
        _, current_tree = wait_for_named(TREE_LABEL)
        _, current_status = find_named("Library search status")
        raise RuntimeError(
            "filtered TreeItem object path remained discoverable: "
            f"occupant={node_at_path(current_tree, retired_path)} "
            f"status={node_record(current_status) if current_status else None} "
            f"tree={descendant_summary(current_tree)}")
    return {
        "search": {
            "node": node_record(search),
            "initial_text": initial_text,
            "committed_text": committed,
            "selected_text": selected,
            "relations": relations,
            "retirement_query_text": replacement,
        },
        "tree": {
            "node": node_record(tree),
            "branch_toggle": branch_toggle,
            "item_before": item_before,
            "item_after": item_after,
            "item_actions": item_actions,
            "invoked_item_action": item_action,
            "value_before": tree_value_before,
            "value_after": tree_value_after,
            "requested_scroll_value": scroll_target,
            "retired_item_path": retired_path,
            "retired_after_filter": True,
        },
    }


def dispatch_hyprland(hyprctl: str, expression: str) -> None:
    """Retry one bounded compositor dispatch until Euclid's window is mapped."""
    deadline = time.monotonic() + 3.0
    while True:
        result = subprocess.run(
            [hyprctl, "dispatch", expression],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
        if result.returncode == 0:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Hyprland rejected {expression}")
        time.sleep(0.05)


def exercise_host_transitions(root, child) -> dict | None:
    """Exercise Euclid focus and resize through Hyprland when that host is available."""
    hyprctl = shutil.which("hyprctl")
    if hyprctl is None or "hyprland" not in \
            os.environ.get("XDG_CURRENT_DESKTOP", "").lower():
        return None
    initial = node_record(child)
    dispatch_hyprland(
        hyprctl, 'hl.dsp.focus({ window = "class:^euclid$" })')
    focused = node_record(root)
    dispatch_hyprland(
        hyprctl, 'hl.dsp.window.float({ action = "toggle" })')
    dispatch_hyprland(
        hyprctl,
        "hl.dsp.window.resize({ x = -160, y = -80, relative = true })")
    resized = wait_for_node_record(
        child, lambda record: record["bounds"] != initial["bounds"])
    return {"initial": initial, "focused": focused, "resized": resized}


def close_host_window() -> None:
    """Request orderly Euclid shutdown through its ordinary SDL window-close path."""
    hyprctl = shutil.which("hyprctl")
    if hyprctl is None:
        raise RuntimeError("orderly native probe shutdown requires hyprctl")
    dispatch_hyprland(
        hyprctl, 'hl.dsp.focus({ window = "class:^euclid$" })')
    dispatch_hyprland(hyprctl, "hl.dsp.window.close()")


def wait_for_runtime_ready(process, diagnostics: Path) -> None:
    """Wait for the display owner to enter its initialized frame loop."""
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if diagnostics.is_file() and \
                "display_runtime_ready" in diagnostics.read_text(
                    encoding="utf-8", errors="replace"):
            return
        status = process.poll()
        if status is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise RuntimeError(
                f"Euclid exited before runtime readiness ({status}): {stderr}")
        time.sleep(0.05)
    raise RuntimeError("timed out waiting for Euclid display runtime readiness")


def run_session(session_index: int) -> dict:
    """Launch and validate one orderly Euclid accessibility session."""
    diagnostics = ROOT / ARTIFACTS / f"session-{session_index}.log"
    scenario_artifacts = ARTIFACTS / f"session-{session_index}-evidence"
    diagnostics.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(BINARY),
        "--window-mode=resizable",
        f"--diagnostics={diagnostics}",
        f"--scenario={SCENARIO}",
        f"--scenario-artifacts={scenario_artifacts}",
    ]
    process = subprocess.Popen(
        command, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, env=os.environ.copy())
    try:
        wait_for_runtime_ready(process, diagnostics)
        time.sleep(3.0)
        try:
            application, child = wait_for_named(RESTART_LABEL)
        except RuntimeError as error:
            status = process.poll()
            stderr = ""
            if status is not None and process.stderr is not None:
                stderr = process.stderr.read()
            raise RuntimeError(f"{error}; process={status}; stderr={stderr}")
        parent = child.parent
        search_tree = exercise_search_and_tree()
        transitions = exercise_host_transitions(parent, child)
        focused = focus_button(child)
        actions = action_names(child)
        _, settings = wait_for_named(SETTINGS_LABEL)
        settings_action = invoke_action(
            settings, ("click", "press", "activate"))
        _, checkbox = wait_for_named(CHECKBOX_LABEL)
        _, slider = wait_for_named(SLIDER_LABEL)
        checkbox_before = node_record(checkbox)
        checkbox_action = invoke_action(
            checkbox, ("click", "press", "activate"))
        checkbox_after = wait_for_node_record(
            checkbox, lambda record: record["states"] != checkbox_before["states"])
        slider_before = value_record(slider)
        slider_target = increment_value(slider, slider_before)
        deadline = time.monotonic() + 3.0
        slider_after = value_record(slider)
        while slider_after["current"] != slider_target and time.monotonic() < deadline:
            time.sleep(0.05)
            slider_after = value_record(slider)
        result = {
            "schema_version": 4,
            "session_type": os.environ.get("XDG_SESSION_TYPE", "unknown"),
            "video_driver": os.environ.get("SDL_VIDEODRIVER", "default"),
            "application": node_record(application),
            "root": node_record(parent),
            "child": node_record(child),
            "focused_child": focused,
            "actions": actions,
            "search_tree": search_tree,
            "settings": {
                "node": node_record(settings),
                "invoked_action": settings_action,
            },
            "checkbox": {
                "before": checkbox_before,
                "after": checkbox_after,
                "actions": action_names(checkbox),
                "invoked_action": checkbox_action,
            },
            "slider": {
                "node": node_record(slider),
                "before": slider_before,
                "after": slider_after,
                "requested_value": slider_target,
            },
            "host_transitions": transitions,
        }
        if result["root"]["role"] not in ("application", "landmark"):
            raise RuntimeError("button parent is not an application root")
        if result["root"]["child_count"] < 4:
            raise RuntimeError("synthetic application root lacks ordinary controls")
        if result["child"]["role"] not in ("push button", "button"):
            raise RuntimeError("restart control is not exposed as a button")
        if result["child"]["parent_path"] != result["root"]["object_path"]:
            raise RuntimeError("button parent link is inconsistent")
        if result["root"]["parent_path"] != result["application"]["object_path"]:
            raise RuntimeError("synthetic root parent link is inconsistent")
        if result["child"]["bounds"]["width"] < 0 or \
                result["child"]["bounds"]["height"] < 0:
            raise RuntimeError("button bounds are inverted")
        if result["checkbox"]["before"]["role"] not in ("check box", "checkbox"):
            raise RuntimeError("settings toggle is not exposed as a checkbox")
        if result["slider"]["node"]["role"] != "slider":
            raise RuntimeError("maximum dust is not exposed as a slider")
        if slider_after["current"] != slider_target:
            raise RuntimeError("native slider value did not reach the requested value")
        result["invoked_action"] = invoke_action(
            child, ("click", "press", "activate"))
        return_code = process.wait(timeout=20)
        if return_code != 0:
            stderr = process.stderr.read() if process.stderr else ""
            raise RuntimeError(f"Euclid orderly shutdown failed ({return_code}): {stderr}")
        manifest_path = ROOT / scenario_artifacts / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        result["scenario_manifest"] = manifest
        if manifest.get("result") != "passed":
            raise RuntimeError(f"accessibility owner evidence failed: {manifest}")
        result["removed_after_shutdown"] = wait_for_removal()
        if not result["removed_after_shutdown"]:
            raise RuntimeError("accessibility provider remained after shutdown")
        return result
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def run_probe() -> dict:
    """Validate repeated Euclid sessions on the desktop accessibility bus."""
    if not BINARY.is_file():
        raise RuntimeError("debug binary missing; run cmake --build --preset debug")
    shutil.rmtree(ROOT / ARTIFACTS, ignore_errors=True)
    return {
        "schema_version": 4,
        "sessions": [run_session(1), run_session(2)],
    }


if __name__ == "__main__":
    try:
        report = run_probe()
        encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(encoded, encoding="ascii")
        sys.stdout.write(encoded)
    except Exception as error:
        traceback.print_exc()
        print(
            "accessibility tree probe failed: "
            f"{type(error).__name__}: {error!r}", file=sys.stderr)
        raise SystemExit(1)