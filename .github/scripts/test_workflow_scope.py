"""Exercise the actual Bash change predicates, including inputs larger than a pipe."""
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


def predicates():
    result = []
    for name in ("ci", "codeql"):
        source = (ROOT / ".github" / "workflows" / f"{name}.yml").read_text()
        for line in source.splitlines():
            line = line.strip()
            if line.startswith("if ") and "changed_files" in line and "grep -E" in line:
                if not line.endswith("; then"):
                    raise AssertionError("Change predicate must remain independently testable")
                result.append((name, line[3:-6]))
    return result


def matches(predicate, paths):
    script = (
        "set -euo pipefail\n"
        "changed_files=$(cat)\n"
        f"if {predicate}; then printf matched; else printf unmatched; fi\n"
    )
    completed = subprocess.run(
        ["/bin/bash", "-c", script],
        input="\n".join(paths) + "\n", text=True, capture_output=True,
        check=True, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"}, timeout=15,
    )
    if completed.stdout not in ("matched", "unmatched"):
        raise AssertionError("Change predicate returned no classification")
    return completed.stdout == "matched"


class WorkflowScopeTests(unittest.TestCase):
    def setUp(self):
        self.filters = predicates()
        self.assertEqual([name for name, _ in self.filters].count("ci"), 2)
        self.assertEqual([name for name, _ in self.filters].count("codeql"), 1)

    def test_production_and_shared_build_inputs_trigger_all_filters(self):
        for name, predicate in self.filters:
            for path in ("iChart/App/AppRootView.swift", "project.yml", "Package.swift",
                         ".github/scripts/install-xcodegen.sh"):
                with self.subTest(workflow=name, path=path):
                    self.assertTrue(matches(predicate, [path]))

    def test_analyzer_changes_trigger_scan_and_test_changes_trigger_native_tests(self):
        for name, predicate in self.filters:
            if name == "codeql":
                self.assertTrue(matches(predicate, [".github/workflows/codeql.yml"]))
                self.assertFalse(matches(predicate, ["iChartTests/ExampleTests.swift"]))
            else:
                self.assertTrue(matches(predicate, ["iChartTests/ExampleTests.swift"]))
                self.assertTrue(matches(predicate, [".github/workflows/ci.yml"]))

    def test_documentation_and_empty_inputs_do_not_force_runtime_checks(self):
        for name, predicate in self.filters:
            for paths in ([], ["README.md", "docs/project-state.md", "public-site/useichart/index.html"]):
                with self.subTest(workflow=name, paths=paths):
                    self.assertFalse(matches(predicate, paths))

    def test_large_lists_match_at_start_middle_and_end(self):
        documents = [f"docs/archive/historical-file-{index:05d}.md" for index in range(20000)]
        for name, predicate in self.filters:
            for offset in (0, len(documents) // 2, len(documents)):
                paths = documents[:offset] + ["iChart/App/AppRootView.swift"] + documents[offset:]
                with self.subTest(workflow=name, offset=offset):
                    self.assertTrue(matches(predicate, paths))


if __name__ == "__main__":
    unittest.main()
