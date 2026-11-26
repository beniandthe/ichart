"""Verify CI entry points, required contexts and the actual Bash scope predicates."""
from fnmatch import fnmatchcase
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


def mapping_block(source, key, indent=0):
    """Read this repository's block-style workflow mappings without dependencies."""
    lines = source.splitlines()
    header = " " * indent + key + ":"
    starts = [index for index, line in enumerate(lines) if line.rstrip() == header]
    if len(starts) != 1:
        raise AssertionError(f"Expected one workflow mapping: {key}")
    contents = []
    for line in lines[starts[0] + 1:]:
        if line.strip() and not line.lstrip().startswith("#"):
            if len(line) - len(line.lstrip()) <= indent:
                break
        contents.append(line)
    return "\n".join(contents)


def mapping_keys(source, indent):
    return re.findall(rf"^{' ' * indent}([A-Za-z0-9_-]+):(?:\s|$)", source, re.MULTILINE)


def literal(value):
    value = value.strip()
    if value[:1] in ("'", '"') and value[-1:] == value[:1]:
        return value[1:-1]
    return {"true": True, "false": False}.get(value, value)


def scalar(source, key, indent):
    prefix = " " * indent + key + ": "
    values = [literal(line[len(prefix):]) for line in source.splitlines() if line.startswith(prefix)]
    if len(values) != 1:
        raise AssertionError(f"Expected one workflow scalar: {key}")
    return values[0]


def branches(source, event):
    event_block = mapping_block(mapping_block(source, "on"), event, 2)
    branch_block = mapping_block(event_block, "branches", 4)
    result = []
    for line in branch_block.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith("      - "):
            raise AssertionError("Expected explicit workflow branch patterns")
        result.append(literal(line[8:]))
    return result


def accepts_event(source, event, branch):
    events = mapping_block(source, "on")
    if event not in mapping_keys(events, 2):
        return False
    if event == "workflow_dispatch":
        return True
    return any(fnmatchcase(branch, pattern) for pattern in branches(source, event))


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


class WorkflowEntryPointTests(unittest.TestCase):
    def setUp(self):
        self.ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text()

    def test_pr_main_and_manual_entry_points_without_feature_push_duplicates(self):
        events = mapping_block(self.ci, "on")
        self.assertEqual(set(mapping_keys(events, 2)), {"pull_request", "push", "workflow_dispatch"})
        for event in ("pull_request", "push"):
            event_block = mapping_block(events, event, 2)
            self.assertEqual(mapping_keys(event_block, 4), ["branches"],
                "Workflow-level path or activity filters can leave required contexts pending")
            self.assertEqual(branches(self.ci, event), ["main"])
        for event, branch, expected in (
            ("pull_request", "main", True),
            ("pull_request", "release", False),
            ("push", "main", True),
            ("push", "codex/ci-repair", False),
            ("push", "agy/editor-fix", False),
            ("push", "dependabot/github_actions/update", False),
            ("workflow_dispatch", "main", True),
            ("workflow_dispatch", "codex/ci-repair", True),
            ("delete", "main", False),
        ):
            with self.subTest(event=event, branch=branch):
                self.assertEqual(accepts_event(self.ci, event, branch), expected)

    def test_required_jobs_keep_their_context_names_without_job_level_skips(self):
        for workflow, job, context in (
            ("ci", "swift-package", "SwiftPM tests"),
            ("ci", "ios-simulator", "iOS simulator tests"),
            ("codeql", "analyze", "Analyze Swift"),
            ("dependency-review", "dependency-review", "Review dependency changes"),
        ):
            with self.subTest(workflow=workflow, job=job):
                source = (ROOT / ".github" / "workflows" / f"{workflow}.yml").read_text()
                job_block = mapping_block(mapping_block(source, "jobs"), job, 2)
                self.assertEqual(scalar(job_block, "name", 4), context)
                self.assertNotIn("if", mapping_keys(job_block, 4),
                    "Required contexts must be emitted even when expensive steps are scoped out")
                self.assertNotIn("continue-on-error", mapping_keys(job_block, 4))

    def test_documentation_and_analyzer_action_only_skips_do_not_skip_runtime_dependencies(self):
        for name, predicate in predicates():
            if name != "ci":
                continue
            for paths in (["README.md", "docs/project-state.md"], [".github/workflows/codeql.yml"]):
                with self.subTest(predicate=predicate, paths=paths):
                    self.assertFalse(matches(predicate, paths))
            for path in ("Package.swift", "Package.resolved",
                         "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
                with self.subTest(predicate=predicate, path=path):
                    self.assertTrue(matches(predicate, ["README.md", path]))

    def test_parked_research_remains_an_explicit_manual_opt_in(self):
        dispatch = mapping_block(mapping_block(self.ci, "on"), "workflow_dispatch", 2)
        research_input = mapping_block(mapping_block(dispatch, "inputs", 4), "run_recognition_research", 6)
        self.assertEqual(scalar(research_input, "type", 8), "boolean")
        self.assertIs(scalar(research_input, "required", 8), False)
        self.assertIs(scalar(research_input, "default", 8), False)
        research_job = mapping_block(mapping_block(self.ci, "jobs"), "recognition-research", 2)
        self.assertEqual(scalar(research_job, "if", 4),
            "github.event_name == 'workflow_dispatch' && inputs.run_recognition_research")


if __name__ == "__main__":
    unittest.main()
