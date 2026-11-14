"""Keep the system's indeterminate progress indicators out of the control panel, without Xcode.

A `ProgressView` without a `value:` (a spinner, or a linear bar of unknown length) and a
`ProgressView(timerInterval:)` animate on their own: they keep turning in a hidden or minimized
window and with Reduce Motion. The panel draws `ProgressRing(value: nil)` or `LoadingRing` for a
spinner and `ProgressBar(value: nil)` for a bar, which read `\\.panelIsVisible` and Reduce Motion
and stop when either says so. A `ProgressView(value:)` with a known amount is fine. This scans
`App/Views/` for the others. See docs/conventions.md#swiftui-control-panel.
"""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_localization_catalogs import ROOT  # noqa: E402
from test_panel_lazy_lists import blank_comments_and_strings, matching, skip_space  # noqa: E402

VIEWS = ROOT / "App" / "Views"
PROGRESS = re.compile(r"(?<![\w.])ProgressView\b")
AMOUNT = re.compile(r"(?<![\w.])value\s*:")


def indeterminate(text):
    """The line of every `ProgressView` in Swift source `text` that is not given an amount."""
    code = blank_comments_and_strings(text)
    found = []
    for match in PROGRESS.finditer(code):
        index = skip_space(code, match.end())
        arguments = code[index:matching(code, index)] if code[index:index + 1] == "(" else ""
        if not AMOUNT.search(arguments):
            found.append(code.count("\n", 0, match.start()) + 1)
    return found


class PanelProgressIndicatorTests(unittest.TestCase):
    def test_no_panel_view_draws_the_systems_indeterminate_indicator(self):
        problems = [
            f"{path.relative_to(ROOT)}:{line}"
            for path in sorted(VIEWS.rglob("*.swift"))
            for line in indeterminate(path.read_text(encoding="utf-8"))
        ]
        self.assertEqual(
            problems, [],
            "The system's indeterminate ProgressView keeps animating in a hidden window and with"
            " Reduce Motion; draw ProgressRing(value: nil) or LoadingRing for a spinner and"
            " ProgressBar(value: nil) for a bar (docs/conventions.md#swiftui-control-panel).")

    def test_the_scan_finds_indicators_without_an_amount_and_nothing_else(self):
        source = """
        ProgressView()
        ProgressView().progressViewStyle(.linear)
        ProgressView("Loading…")
        ProgressView { Text("Importing") }
        ProgressView(timerInterval: start...end)
        ProgressView(value: 0.4)
        ProgressView(value: Double(copied), total: Double(total)).progressViewStyle(.linear)
        ProgressView("Copying", value: done, total: all)
        """
        self.assertEqual(indeterminate(source), [2, 3, 4, 5, 6])
        quiet = """
        // ProgressView() keeps turning in a hidden window.
        Text("ProgressView()")
        .progressViewStyle(.linear)
        struct LinearProgressViewStyle {}
        ProgressBar(value: nil)
        """
        self.assertEqual(indeterminate(quiet), [], "comments, strings and other names are not calls")


if __name__ == "__main__":
    unittest.main()
