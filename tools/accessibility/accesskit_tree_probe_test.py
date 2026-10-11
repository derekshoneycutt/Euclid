#!/usr/bin/env python3
"""Focused tests for Linux AT-SPI evidence helpers."""

from __future__ import annotations

import unittest

import accesskit_tree_probe as probe


class UnsupportedOperationError(RuntimeError):
    """Represent one adapter operation rejected as unsupported."""


class FakeText:
    """Expose the text facts consumed by the mutation guard."""

    def __init__(self, value: str) -> None:
        self.value = value
        self.characterCount = len(value)
        self.caretOffset = 0

    def getText(self, start: int, end: int) -> str:
        return self.value[start:] if end == -1 else self.value[start:end]

    def getNSelections(self) -> int:
        return 0


class FakeTextNode:
    """Provide a stable queryText result for helper tests."""

    def __init__(self, value: str) -> None:
        self.text = FakeText(value)

    def queryText(self) -> FakeText:
        return self.text

    def __iter__(self):
        return iter(())


class FakeTreeNode:
    """Provide bounded children for capability-based descendant discovery."""

    def __init__(self, children=()) -> None:
        self.children = children

    def __iter__(self):
        return iter(self.children)


class Rect:
    """Provide the pyatspi rectangle shape normalized by the probe."""

    x = 1
    y = 2
    width = 3
    height = 4


class ProbeHelperTests(unittest.TestCase):
    """Verify evidence normalization and unsupported-operation enforcement."""

    def test_normalized_value_recurses_and_normalizes_rectangles(self) -> None:
        value = probe.normalized_value({"bounds": Rect(), "values": (1, None)})
        self.assertEqual(value, {
            "bounds": {"x": 1, "y": 2, "width": 3, "height": 4},
            "values": [1, None],
        })

    def test_observe_operation_preserves_success(self) -> None:
        self.assertEqual(probe.observe_operation(lambda: (1, "two")), {
            "status": "passed",
            "value": [1, "two"],
        })

    def test_rectangle_center_accepts_object_and_tuple_results(self) -> None:
        self.assertEqual(probe.rectangle_center(Rect()), (2, 4))
        self.assertEqual(probe.rectangle_center((10, 20, 8, 6)), (14, 23))

    def test_exception_record_distinguishes_unsupported_and_error(self) -> None:
        unsupported = probe.exception_record(
            UnsupportedOperationError("Editing operation is not supported (1)"))
        failure = probe.exception_record(RuntimeError("provider disappeared"))
        self.assertEqual(unsupported["status"], "unsupported")
        self.assertEqual(failure["status"], "error")
        self.assertIn("UnsupportedOperationError", unsupported["exception_type"])

    def test_unsupported_edit_requires_unchanged_text(self) -> None:
        node = FakeTextNode("Elements")

        def reject() -> None:
            raise UnsupportedOperationError("operation unsupported")

        outcome = probe.expect_unsupported_edit(node, "insertText", reject)
        self.assertEqual(outcome["status"], "unsupported")
        self.assertTrue(outcome["text_unchanged"])

    def test_unsupported_edit_rejects_mutation_before_error(self) -> None:
        node = FakeTextNode("Elements")

        def mutate_then_reject() -> None:
            node.text.value = "changed"
            raise UnsupportedOperationError("operation unsupported")

        with self.assertRaisesRegex(RuntimeError, "mutated text"):
            probe.expect_unsupported_edit(node, "deleteText", mutate_then_reject)

    def test_unsupported_edit_rejects_unexpected_success(self) -> None:
        node = FakeTextNode("Elements")
        with self.assertRaisesRegex(RuntimeError, "unexpectedly succeeded"):
            probe.expect_unsupported_edit(node, "copyText", lambda: True)

    def test_text_descendant_uses_interface_capability(self) -> None:
        text = FakeTextNode("Elements")
        root = FakeTreeNode((FakeTreeNode(), text))
        self.assertIs(probe.find_text_descendant(root), text)


if __name__ == "__main__":
    unittest.main()
