#!/usr/bin/env python3
"""Capture and validate Euclid's Phase 2 AT-SPI button on Linux."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import pyatspi


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build" / "debug" / "euclid"
ARTIFACTS = Path(".build/accessibility-button")
REPORT = ROOT / ARTIFACTS / "atspi.json"
LABEL = "Restart animation"
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


def find_button():
    """Return the first Euclid restart button currently exposed on the desktop."""
    desktop = pyatspi.Registry.getDesktop(0)
    try:
        applications = list(desktop)
    except Exception:
        return None, None
    for application in applications:
        try:
            for node in descendants(application):
                if node.name == LABEL:
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
    }


def wait_for_tree(timeout_seconds: float = 25.0):
    """Wait for AccessKit activation and return the application and static child."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        application, child = find_button()
        if child is not None:
            return application, child
        time.sleep(0.1)
    raise RuntimeError(
        "Euclid accessibility button was not discovered; "
        f"desktop={json.dumps(desktop_summary(), sort_keys=True)}")


def wait_for_removal(timeout_seconds: float = 5.0) -> bool:
    """Return true once the button has disappeared after process shutdown."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        _, child = find_button()
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
    return wait_for_node_record(node, lambda record: record["focused"])


def activate_button(node) -> str:
    """Invoke the restart button's native click action."""
    action = node.queryAction()
    for index in range(action.nActions):
        name = action.getName(index)
        if name.lower() in ("click", "press", "activate"):
            if not action.doAction(index):
                raise RuntimeError(f"AT-SPI action was rejected: {name}")
            return name
    raise RuntimeError(f"restart button has no activation action: {action_names(node)}")


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
    focused = wait_for_node_record(root, lambda record: record["focused"])
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
        try:
            application, child = wait_for_tree()
        except RuntimeError as error:
            status = process.poll()
            stderr = ""
            if status is not None and process.stderr is not None:
                stderr = process.stderr.read()
            raise RuntimeError(f"{error}; process={status}; stderr={stderr}")
        wait_for_runtime_ready(process, diagnostics)
        parent = child.parent
        transitions = exercise_host_transitions(parent, child)
        focused = focus_button(child)
        actions = action_names(child)
        result = {
            "schema_version": 2,
            "session_type": os.environ.get("XDG_SESSION_TYPE", "unknown"),
            "video_driver": os.environ.get("SDL_VIDEODRIVER", "default"),
            "application": node_record(application),
            "root": node_record(parent),
            "child": node_record(child),
            "focused_child": focused,
            "actions": actions,
            "host_transitions": transitions,
        }
        if result["root"]["role"] not in ("application", "landmark"):
            raise RuntimeError("button parent is not an application root")
        if result["root"]["child_count"] != 1:
            raise RuntimeError("synthetic application root does not have one child")
        if result["child"]["role"] not in ("push button", "button"):
            raise RuntimeError("restart control is not exposed as a button")
        if result["child"]["parent_path"] != result["root"]["object_path"]:
            raise RuntimeError("button parent link is inconsistent")
        if result["root"]["parent_path"] != result["application"]["object_path"]:
            raise RuntimeError("synthetic root parent link is inconsistent")
        if result["child"]["bounds"]["width"] < 0 or \
                result["child"]["bounds"]["height"] < 0:
            raise RuntimeError("button bounds are inverted")
        result["invoked_action"] = activate_button(child)
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
        "schema_version": 2,
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
        print(
            "accessibility tree probe failed: "
            f"{type(error).__name__}: {error!r}", file=sys.stderr)
        raise SystemExit(1)