#!/usr/bin/env python3
"""Generate/run an isolated Simulator project for production paid defaults.

This is an additional policy/preservation gate, not the normal free CI suite or
an Apple archive verifier. No device, production backend, or Apple write occurs.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


PAID_FLAG = "ICHART_PAID_SUBSCRIPTION"
VALIDATION_FLAG = "ICHART_PRODUCTION_PAID_VALIDATION"
FORBIDDEN_FLAGS = {
    "DEBUG", "ICHART_STAGING_STOREKIT_PRODUCTS", "ICHART_INTERNAL_STAGING",
    "ICHART_LOCAL_PLAN_QA", "ICHART_LOCAL_QA_PLAN_PREVIEW",
}
TEST_CLASSES = (
    "ProductionPaidBuildScopeTests", "ProductionPaidAccessPolicyTests",
    "ProductionPaidBackendConfigurationTests", "LocalChartDowngradeAccessTests",
    "ChartFontSelectionPolicyTests", "IChartStoreKitProductCatalogTests",
    "IChartSubscriptionAccessRecoveryTests", "IChartSubscriptionAccessRecoveryIntegrationTests",
    "IChartRemoteSubscriptionRecordTests", "PDFLibraryCloudRestoreTests", "PDFSetlistStoreTests",
)


def run(command: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True)


def source_manifest(source: Path) -> dict[str, str]:
    paths = run(["git", "ls-files", "-co", "--exclude-standard", "--",
                 "iChart", "iChartTests", "ThirdParty", "StoreKit", "project.yml",
                 "Package.swift", "Package.resolved",
                 "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"], cwd=source).splitlines()
    return {p: hashlib.sha256((source / p).read_bytes()).hexdigest()
            for p in sorted(set(paths)) if (source / p).is_file()}


def make_spec(original: dict, output: Path) -> dict:
    spec = copy.deepcopy(original)
    spec["targets"] = {name: spec["targets"][name] for name in ("iChart", "iChartTests")}
    for name, target in spec["targets"].items():
        release = target.setdefault("settings", {}).setdefault("configs", {}).setdefault("Release", {})
        existing = str(release.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", ""))
        if any(flag in existing for flag in FORBIDDEN_FLAGS):
            raise ValueError(f"Unexpected Release override in {name}")
        release["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = (
            "$(inherited) " + PAID_FLAG + (" " + VALIDATION_FLAG if name == "iChartTests" else "")
        )
        release["ENABLE_TESTABILITY"] = "YES"
        if "info" in target:
            target["info"]["path"] = str(output / f"{name}-Info.plist")
    # Do not propagate paid flags through project/global settings or dependencies.
    if PAID_FLAG in json.dumps(spec.get("settings", {})):
        raise ValueError("Paid conditions must be target-scoped, never global")
    spec["schemes"] = {
        "iChart": {
            "build": {"targets": {"iChart": "all"}},
            "test": {"config": "Release", "targets": ["iChartTests"]},
        }
    }
    return spec


def validate_build_settings(rows: list[dict]) -> None:
    indexed = {row["target"]: row["buildSettings"] for row in rows}
    for target in ("iChart", "iChartTests"):
        settings = indexed.get(target)
        if settings is None:
            raise ValueError(f"Missing actual build settings for {target}")
        flags = set(str(settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")).split())
        if PAID_FLAG not in flags or flags & FORBIDDEN_FLAGS:
            raise ValueError(f"Wrong actual production paid conditions for {target}: {sorted(flags)}")
        if target == "iChartTests" and VALIDATION_FLAG not in flags:
            raise ValueError("Dedicated paid test cases were not enabled")
        if target == "iChart" and VALIDATION_FLAG in flags:
            raise ValueError("Test-only validation flag leaked into application")
        if settings.get("CONFIGURATION") != "Release":
            raise ValueError("Paid policy gate requires Release compilation")
    for target, settings in indexed.items():
        if target not in ("iChart", "iChartTests"):
            flags = set(str(settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")).split())
            if flags & {PAID_FLAG, VALIDATION_FLAG}:
                raise ValueError(f"Paid conditions leaked into dependency {target}")


def validate_results(summary: dict, tree: dict, device_id: str) -> dict[str, int]:
    if summary.get("result") != "Passed" or summary.get("passedTests", 0) < 1:
        raise ValueError("A successful, nonempty native result is required")
    if summary.get("failedTests", 0) or summary.get("skippedTests", 0):
        raise ValueError("All selected paid gates must execute without failures or skips")
    executed = [r for r in summary.get("devicesAndConfigurations", [])
                if r.get("passedTests", 0) + r.get("failedTests", 0) > 0]
    if not executed or any(r.get("device", {}).get("deviceId", "").upper() != device_id.upper()
                           for r in executed):
        raise ValueError("Results did not execute exclusively on the configured Simulator")
    counts = {name: 0 for name in TEST_CLASSES}

    def visit(node: dict) -> None:
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier", "")
            name = identifier.split("/", 1)[0]
            if name not in counts or node.get("result") != "Passed":
                raise ValueError(f"Unexpected or nonpassing selected test: {identifier}")
            counts[name] += 1
        for child in node.get("children", []):
            visit(child)

    for node in tree.get("testNodes", []):
        visit(node)
    if not all(counts.values()) or sum(counts.values()) != summary["passedTests"]:
        raise ValueError(f"Missing selected test class or inconsistent execution counts: {counts}")
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True, help="New local directory outside checkout")
    parser.add_argument("--destination", required=True, help="platform=iOS Simulator,id=UUID")
    parser.add_argument("--run-tests", action="store_true", help="Otherwise prepare only; no heavy build/test")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    destination = re.fullmatch(r"platform=iOS Simulator,id=([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})", args.destination)
    if not destination:
        parser.error("An exact iOS Simulator UUID is required; physical devices are not supported")
    if output == source or source in output.parents or output.exists():
        parser.error("Output must be a new directory outside the source checkout")
    output.mkdir(parents=True)
    before = source_manifest(source)
    original = json.loads(run(["xcodegen", "dump", "--no-env", "--type", "json",
                               "--spec", str(source / "project.yml")], cwd=source))
    spec = make_spec(original, output)
    spec_path = output / "paid-validation-project.json"
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")
    run(["xcodegen", "generate", "--no-env", "--spec", str(spec_path),
         "--project-root", str(source), "--project", str(output)], cwd=source)
    if source_manifest(source) != before:
        raise ValueError("Generating the paid validation project changed source inputs")
    project = output / "iChart.xcodeproj"
    resolved = source / "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    if not resolved.is_file():
        raise ValueError("The committed Xcode package resolution is required")
    generated_resolution = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    generated_resolution.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(resolved, generated_resolution)
    command = ["xcodebuild", "test", "-project", str(project), "-scheme", "iChart",
               "-configuration", "Release", "-destination", args.destination,
               "-onlyUsePackageVersionsFromResolvedFile", "-parallel-testing-enabled", "NO",
               "-derivedDataPath", str(output / "DerivedData"),
               "-clonedSourcePackagesDirPath", str(output / "SourcePackages"),
               "-resultBundlePath", str(output / "paid-validation.xcresult"),
               *[f"-only-testing:iChartTests/{name}" for name in TEST_CLASSES], "CODE_SIGNING_ALLOWED=NO"]
    receipt = {"source": str(source), "sourceHead": run(["git", "rev-parse", "HEAD"], cwd=source).strip(),
               "sourceInputs": before, "project": str(project), "destination": args.destination,
               "testClasses": TEST_CLASSES, "command": command, "preparedOnly": not args.run_tests,
               "nativeValidationPassed": False}
    (output / "validation-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if not args.run_tests:
        print(json.dumps({"preparedOnly": True, "project": str(project), "runCommand": shlex.join(command)}))
        return
    settings_command = ["xcodebuild", "-project", str(project), "-alltargets", "-configuration", "Release",
                        "-destination", args.destination, "-showBuildSettings", "-json", "CODE_SIGNING_ALLOWED=NO"]
    settings = json.loads(run(settings_command, cwd=source))
    validate_build_settings(settings)
    # Retain only build-scope evidence; unrestricted settings may include local environment values.
    receipt["targetConditions"] = {r["target"]: r["buildSettings"].get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
                                   for r in settings}
    with (output / "xcodebuild.log").open("w") as log:
        status = subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT).returncode
    receipt["xcodebuildExitCode"] = status
    if status:
        (output / "validation-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        raise ValueError(f"Native paid validation failed; see {output / 'xcodebuild.log'}")
    result = output / "paid-validation.xcresult"
    summary = json.loads(run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)]))
    tree = json.loads(run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result)]))
    receipt["classExecutedCounts"] = validate_results(summary, tree, destination.group(1))
    if source_manifest(source) != before:
        raise ValueError("Source inputs changed during paid validation; rerun the final frozen head")
    receipt["summary"] = summary
    receipt["nativeValidationPassed"] = True
    (output / "validation-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"passed": True, "passedTests": summary["passedTests"],
                      "receipt": str(output / "validation-receipt.json")}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
