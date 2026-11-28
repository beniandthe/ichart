#!/usr/bin/env python3
"""Prepare an isolated coordinated-QA project only; never build, sign or upload."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

QA_REF = "yiuxduqhhbucsmooevxz"
QA_URL = "https://" + QA_REF + ".supabase.co"
QA_KEY_SHA256 = "bfdf9049a7237013fea1b1f18d137e4d58daa34078fec4290b78a9676e9038e2"
QA_FLAG = "ICHART_COORDINATED_STAGING_QA"
PAID_FLAG = "ICHART_PAID_SUBSCRIPTION"
STAGING_FLAG = "ICHART_STAGING_STOREKIT_PRODUCTS"
APP_FLAGS = {QA_FLAG, PAID_FLAG, STAGING_FLAG}
QA_VERSION, QA_BUILD, SOURCE_BUILD = "1.9.4", "209", "210"
QA_PRODUCTS = {"monthly": "com.ichart.app.staging.fix036.monthly", "annual": "com.ichart.app.staging.fix036.annual"}
QA_NAMESPACE = {"mode": "coordinatedStagingQA",
                "directory": "iChart Coordinated QA " + QA_REF,
                "defaults_suite": "com.ichart.app.coordinated-qa." + QA_REF,
                "auth_prefix": "coordinated-qa." + QA_REF + "."}


def read_public_key(path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 4096:
        raise ValueError("Use a bounded regular QA publishable-key file")
    key = path.read_text().strip()
    if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{16,}", key) or hashlib.sha256(key.encode()).hexdigest() != QA_KEY_SHA256:
        raise ValueError("QA client key does not match the reviewed project publishable-key hash")
    return key


def configure_app(original, output, key):
    """Literal app-only inputs; normal project/dependency defaults are unchanged."""
    if hashlib.sha256(key.encode()).hexdigest() != QA_KEY_SHA256:
        raise ValueError("Unreviewed QA client key")
    identity = original.get("settings", {}).get("base", {})
    if identity.get("MARKETING_VERSION") != QA_VERSION or str(identity.get("CURRENT_PROJECT_VERSION", "")) != SOURCE_BUILD:
        raise ValueError("Authoritative normal source identity must be1.9.4(210); QA override is209 only")
    if any(flag in json.dumps(original.get("settings", {})) for flag in APP_FLAGS | {"ICHART_PRODUCTION_PAID_VALIDATION"}):
        raise ValueError("QA/validation conditions cannot be global")
    spec = copy.deepcopy(original)
    app = spec["targets"]["iChart"]
    release = app.setdefault("settings", {}).setdefault("configs", {}).setdefault("Release", {})
    release.update(MARKETING_VERSION=QA_VERSION, CURRENT_PROJECT_VERSION=QA_BUILD,
                   SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(inherited) " + " ".join(sorted(APP_FLAGS)))
    info = app["info"]
    original_info = PurePosixPath(info["path"])
    for entry in app.get("sources", []):
        if isinstance(entry, dict):
            try:
                relative = original_info.relative_to(PurePosixPath(entry["path"]))
            except ValueError:
                continue
            if str(relative) not in entry.setdefault("excludes", []):
                entry["excludes"].append(str(relative))
    info["path"] = str(output / "iChart-Info.plist")
    info.setdefault("properties", {}).update(SupabaseURL=QA_URL, SupabasePublishableKey=key, SupabaseAnonKey="", TFInternalTestingOnly=True)
    return spec


def make_archive_spec(original, output, key):
    spec = configure_app(original, output, key)
    spec["targets"] = {"iChart": spec["targets"]["iChart"]}
    spec["targets"]["iChart"]["settings"]["configs"]["Release"]["ENABLE_TESTABILITY"] = "NO"
    spec["schemes"] = {"iChart": {"build": {"targets": {"iChart": "all"}}, "archive": {"config": "Release"}}}
    return spec


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Fresh committed isolated QA source clone")
    parser.add_argument("--output", type=Path, required=True, help="New private recipe/evidence directory outside source")
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--qa-public-key-file", type=Path, required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.exists() or output == source or source in output.parents:
        parser.error("Use a fresh evidence directory outside source")
    # The strict native helper supplies the same allowlist and clean-head checks.
    import importlib.util
    definition = importlib.util.spec_from_file_location("qa_recipe_native", Path(__file__).with_name("run_production_paid_validation.py"))
    native = importlib.util.module_from_spec(definition); definition.loader.exec_module(native)
    head = native.require_clean_head(source, args.expected_head)
    key = read_public_key(args.qa_public_key_file)
    before = native.source_manifest(source)
    original = json.loads(native.run(["xcodegen", "dump", "--no-env", "--type", "json", "--spec", str(source / "project.yml")], cwd=source))
    output.mkdir(parents=True, mode=0o700)
    spec = make_archive_spec(original, output, key)
    spec_path = output / "coordinated-qa-archive-project.json"
    spec_path.write_text(json.dumps(spec, indent=2) + "\n"); spec_path.chmod(0o600)
    native.run(["xcodegen", "generate", "--no-env", "--spec", str(spec_path),
                "--project-root", str(source), "--project", str(source)], cwd=source)
    native.require_clean_head(source, head)
    if native.source_manifest(source) != before:
        raise ValueError("QA project preparation changed source inputs")
    project = source / "iChart.xcodeproj/project.pbxproj"
    receipt = {"schema": 1, "preparedOnly": True, "sourceHead": head,
               "sourceTree": native.run(["git", "rev-parse", "HEAD^{tree}"], cwd=source).strip(),
               "sourceInputs": before, "qaOrigin": QA_URL, "qaKeySHA256": QA_KEY_SHA256,
               "artifactRelease": {"version": QA_VERSION, "build": QA_BUILD},
               "specPath": str(spec_path), "specSHA256": hashlib.sha256(spec_path.read_bytes()).hexdigest(),
               "projectSHA256": hashlib.sha256(project.read_bytes()).hexdigest(),
               "infoPath": str(output / "iChart-Info.plist"),
               "infoSHA256": hashlib.sha256((output / "iChart-Info.plist").read_bytes()).hexdigest(),
               "appConditions": sorted(APP_FLAGS), "buildExecuted": False, "deliveryReady": False}
    target = output / "qa-project-receipt.json"
    target.write_text(json.dumps(receipt, indent=2) + "\n"); target.chmod(0o600)
    print(json.dumps({"preparedOnly": True, "receipt": str(target), "qaKeySHA256": QA_KEY_SHA256}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("QA project preparation failed: " + type(error).__name__)
