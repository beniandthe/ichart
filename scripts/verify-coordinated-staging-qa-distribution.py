#!/usr/bin/env python3
"""Read-only coordinated-staging QA artifact guard. Apple delivery remains HELD."""
import argparse
import datetime
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import shlex
import sys
import uuid
import tempfile

_BASE_SPEC = importlib.util.spec_from_file_location(
    "ichart_public_guard_for_held_paid_artifacts",
    Path(__file__).with_name("verify_public_beta_archive.py"))
base = importlib.util.module_from_spec(_BASE_SPEC)
_BASE_SPEC.loader.exec_module(base)
_RUNTIME_SPEC = importlib.util.spec_from_file_location(
    "ichart_native_paid_semantics_for_held_artifacts",
    Path(__file__).with_name("run_coordinated_staging_qa_validation.py"))
native = importlib.util.module_from_spec(_RUNTIME_SPEC)
_RUNTIME_SPEC.loader.exec_module(native)
recipe = native.recipe
# Reuse the unchanged public verifier's byte/signature checks in an isolated module.
# Its policy constants are never modified.
GuardError, require, sha = base.GuardError, base.require, base.sha
XCODE_SWIFT_WRAPPERS = base.XCODE_SWIFT_WRAPPERS
expand_responses = base.expand_responses
PAID_FLAG = "ICHART_PAID_SUBSCRIPTION"
FORBIDDEN_FLAGS = {"DEBUG",
                   "ICHART_LOCAL_PLAN_QA", "ICHART_LOCAL_QA_PLAN_PREVIEW"}
REQUIRED_SOURCES = base.REQUIRED_SOURCES + (
    "iChart/App/Supabase/IChartSupabaseConfiguration.swift",
    "iChart/App/IChartApp.swift",
    "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift",
    "iChart/Models/AppEntitlements.swift",
) + tuple(p for p in native.REQUIRED_RUNTIME_APP_SOURCES if p not in base.REQUIRED_SOURCES and p not in {
    "iChart/App/Supabase/IChartSupabaseConfiguration.swift", "iChart/App/IChartApp.swift",
    "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift", "iChart/Models/AppEntitlements.swift"})
PRODUCTS = recipe.QA_PRODUCTS
REQUIRED_FLAGS = recipe.APP_FLAGS
PRICE_CENTS = {"monthly": 699, "annual": 6000}


def source_contracts(source):
    public = base.source_contracts(source)
    catalog = (source / "iChart/Models/IChartStoreKitProductCatalog.swift").read_text()
    branch = re.search(r"#if ICHART_STAGING_STOREKIT_PRODUCTS\s*\n(.*?)#else", catalog, re.S)
    require(branch is not None, "Explicit isolated StoreKit catalog branch missing.")
    for field, expected in (("proMonthlyProductID", PRODUCTS["monthly"]), ("proAnnualProductID", PRODUCTS["annual"])):
        require(re.findall(r'^\s*static let ' + field + r'\s*=\s*"([^"\n]+)"\s*$', branch.group(1), re.M) == [expected],
                "QA product catalog is not the reviewed isolated catalog.")
    for field, expected in (("targetMonthlyPriceCents", 699), ("targetAnnualPriceCents", 6000)):
        values = re.findall(r'^\s*static let ' + field + r'\s*=\s*([0-9][0-9_]*)\s*$', branch.group(1), re.M)
        require(len(values) == 1 and int(values[0].replace("_", "")) == expected, "QA target price changed.")
    catalog_path = source / "docs/coordinated-staging-qa-catalog.json"
    require(catalog_path.is_file() and not catalog_path.is_symlink(), "Separate reviewed QA catalog missing.")
    qa_catalog = checked_json(catalog_path.read_bytes())
    require(qa_catalog.get("qa_project_ref") == recipe.QA_REF and qa_catalog.get("qa_origin") == recipe.QA_URL
            and qa_catalog.get("publishable_key_sha256") == recipe.QA_KEY_SHA256
            and qa_catalog.get("namespace") == recipe.QA_NAMESPACE and qa_catalog.get("staging_product_ids") == PRODUCTS
            and qa_catalog.get("currency") == "USD" and qa_catalog.get("billing_environment") == "Sandbox"
            and qa_catalog.get("requested_prices") == {"monthly": {"period": "P1M", "amount": "6.99", "minor_units": 699},
                "annual": {"period": "P1Y", "amount": "60.00", "minor_units": 6000}}, "Exact QA catalog inputs differ.")
    namespace = (source / "iChart/Persistence/IChartStorageNamespace.swift").read_text()
    for expected in recipe.QA_NAMESPACE.values():
        require(expected in namespace, "Reviewed QA namespace source contract missing.")
    for name in REQUIRED_SOURCES:
        require((source / name).is_file() and not (source / name).is_symlink(), "Required coordinated QA source missing.")
    return {"normal_default_policy": public["policy"], "normal_namespace": public["namespace"],
            "qa_namespace": recipe.QA_NAMESPACE, "qa_origin": recipe.QA_URL, "qa_key_sha256": recipe.QA_KEY_SHA256,
            "storeKitProducts": PRODUCTS, "target_prices_usd_minor_units": PRICE_CENTS,
            "apple_prices_verified": False, "coordinated_runtime_proof_required": True,
            "production_activation_approved": False}


def project_identity(source):
    text = (source / "project.yml").read_text()
    result = {}
    for key, output in (("MARKETING_VERSION", "version"), ("CURRENT_PROJECT_VERSION", "build")):
        values = re.findall(r'^    ' + key + r':\s*"([^"\n]+)"\s*$', text, re.M)
        require(len(values) == 1, "One literal authoritative project " + key + " is required.")
        result[output] = values[0]
    require(re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", result["version"]), "Invalid marketing version.")
    require(re.fullmatch(r"[1-9][0-9]*", result["build"]), "Build must be a positive literal integer.")
    return result


def snapshot_source(source):
    current = base.snapshot_source(source)
    current["contracts"] = source_contracts(source)
    current["source_release"] = project_identity(source)
    require(current["source_release"] == {"version": recipe.QA_VERSION, "build": recipe.SOURCE_BUILD},
            "Normal authoritative source release differs from reviewed production208 inputs.")
    current["release"] = {"version": recipe.QA_VERSION, "build": recipe.QA_BUILD}
    current["runtime_inputs"] = native.source_manifest(source)
    current["files"]["docs/coordinated-staging-qa-catalog.json"] = sha((source / "docs/coordinated-staging-qa-catalog.json").read_bytes())
    return current


def checked_json(data):
    def object_pairs(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, "Duplicate keys in checked release evidence.")
            value[key] = item
        return value
    return json.loads(data, object_pairs_hook=object_pairs)


def checked_pin_bytes(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 32 * 1024 * 1024,
            "Use a bounded regular paid source pin.")
    data = path.read_bytes()
    require(len(data) <= 32 * 1024 * 1024, "Source pin grew beyond its bound.")
    return data


def checked_policy_bytes(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16384,
            "Use a bounded regular checked release-policy receipt.")
    data = path.read_bytes()
    require(len(data) <= 16384, "Release-policy receipt grew beyond its bound.")
    return data


def release_policy(path, snapshot, *, data=None):
    data = checked_policy_bytes(path) if data is None else data
    value = checked_json(data)
    expected = {"schema": 2, "package_mode": "coordinated_staging_qa",
                "source_head": snapshot["head"], "source_tree": snapshot["tree"],
                "version": recipe.QA_VERSION, "build": recipe.QA_BUILD,
                "source_version": recipe.QA_VERSION, "source_build": recipe.SOURCE_BUILD,
                "qa_origin": recipe.QA_URL, "qa_key_sha256": recipe.QA_KEY_SHA256,
                "internal_qa_only": True, "distribution_held": True, "apple_delivery_held": True,
                "automatic_activation": False, "production_activation_approved": False,
                "public_beta_must_remain_on": True, "deploy_to_production_must_remain_off": True,
                "production_resources_must_remain_unchanged": True}
    require(isinstance(value, dict) and set(value) == set(expected), "Exact coordinated-QA hold policy required.")
    for key, expected_value in expected.items():
        require(type(value.get(key)) is type(expected_value) and value[key] == expected_value,
                "Coordinated QA hold-policy mismatch: " + key)
    return value



def checked_runtime_bytes(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16 * 1024 * 1024,
            "Use a bounded regular native runtime receipt.")
    data = path.read_bytes()
    require(len(data) <= 16 * 1024 * 1024, "Native runtime receipt grew beyond its bound.")
    return data


def runtime_evidence(path, source, snapshot, lane):
    """Revalidate actual native evidence; a receipt success field is insufficient."""
    data = checked_runtime_bytes(path)
    value = checked_json(data)
    require(isinstance(value, dict) and value.get("schema") == 2 and value.get("lane") == lane,
            "A current lane-specific native runtime receipt is required.")
    require(value.get("nativeValidationPassed") is True and value.get("preparedOnly") is False
            and type(value.get("xcodebuildExitCode")) is int and value["xcodebuildExitCode"] == 0,
            "Preparation, skipped execution or failed native validation cannot certify semantics.")
    try:
        require(str(uuid.UUID(value.get("runID", ""))) == value["runID"], "Native run identity must be canonical.")
        started = datetime.datetime.fromisoformat(value["startedAtUTC"])
        completed = datetime.datetime.fromisoformat(value["completedAtUTC"])
        require(started.utcoffset() == completed.utcoffset() == datetime.timedelta(0) and completed >= started,
                "Native evidence must have ordered UTC run timestamps.")
    except (ValueError, KeyError, TypeError, AttributeError):
        raise GuardError("Native runtime receipt has no valid run chronology/identity.")
    require(value.get("sourceHead") == snapshot["head"] and value.get("sourceTree") == snapshot["tree"],
            "Native runtime receipt is not from this exact source HEAD/tree.")
    require(value.get("sourceInputs") == snapshot["runtime_inputs"] == native.source_manifest(source),
            "Native runtime inputs differ from the source-bound archive inputs.")
    require(native.COORDINATION_CONTRACT_FINALIZED and native.REQUIRED_COORDINATED_TESTS and native.COORDINATED_TEST_CLASSES,
            "Coordinated runtime scenario contract has not been finalized.")
    require(value.get("testClasses") == list(native.selected_classes(lane))
            and value.get("testSources") == list(native.selected_sources(lane))
            and value.get("requiredCoordinatedTests") == list(native.REQUIRED_COORDINATED_TESTS),
            "Runtime test scope differs from the required coordination contract.")
    require(value.get("qaInputs") == {"origin": recipe.QA_URL, "keySHA256": recipe.QA_KEY_SHA256,
            "namespace": recipe.QA_NAMESPACE, "artifactRelease": snapshot["release"]}, "Native receipt has foreign QA inputs.")
    destination = re.fullmatch(r"platform=iOS Simulator,id=([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})",
                               value.get("destination", ""))
    require(destination is not None, "Native runtime evidence must name its exact Simulator.")
    root = path.resolve().parent
    original_source = Path(value.get("source", ""))
    require(original_source.is_absolute(), "Native source location must be explicit.")
    project = root / "iChart.xcodeproj"
    require(value.get("project") == str(project), "Native project must belong to this evidence directory.")
    source_paths = (
        "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "scripts/run_coordinated_staging_qa_validation.py", "scripts/test_coordinated_staging_qa_validation.py", "scripts/prepare_coordinated_staging_qa_project.py",
    )
    proof = {str(original_source / p): sha((source / p).read_bytes()) for p in source_paths}
    proof_paths = [project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                   root / "qa-validation-project.json", project / "project.pbxproj", root / "iChart-Info.plist"]
    for proof_path in proof_paths:
        require(proof_path.is_file() and not proof_path.is_symlink()
                and proof_path.resolve().is_relative_to(root), "Native generated proof escaped its run directory.")
        proof[str(proof_path)] = sha(proof_path.read_bytes())
    require(value.get("proofFileHashes") == proof, "Native generated project, runner or package lock drifted.")
    log = root / "xcodebuild.log"
    require(log.is_file() and not log.is_symlink() and log.stat().st_size <= 512 * 1024 * 1024,
            "Native compiler log must be bounded regular evidence.")
    log_data = log.read_bytes()
    require(value.get("buildLogSHA256") == sha(log_data), "Native compiler log changed after execution.")
    compiler = native.validate_compiler_commands(log_data.decode(), root / "DerivedData", lane, original_source, snapshot["runtime_inputs"])
    require(value.get("actualCompilerCommands") == compiler, "Actual native compiler evidence changed.")
    conditions = value.get("targetConditions", {})
    other = value.get("otherSwiftFlags", {})
    require(isinstance(conditions, dict) and isinstance(other, dict), "Missing native scope evidence.")
    native.validate_build_settings([
        {"target": target, "buildSettings": {"CONFIGURATION": "Release",
         "SWIFT_ACTIVE_COMPILATION_CONDITIONS": flags, "OTHER_SWIFT_FLAGS": other.get(target, "")}}
        for target, flags in conditions.items()], lane)
    bundle = root / "qa-validation.xcresult"
    inventory = native.result_bundle_hashes(bundle)
    require(inventory and value.get("resultBundleFiles") == inventory, "Native result bundle changed.")
    summary = json.loads(base.run("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)).stdout)
    tree = json.loads(base.run("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)).stdout)
    counts = native.validate_results(summary, tree, destination.group(1), lane)
    require(type(summary.get("startTime")) in (int, float) and type(summary.get("finishTime")) in (int, float)
            and started.timestamp() <= summary["startTime"] <= summary["finishTime"] <= completed.timestamp(),
            "Actual xcresult execution is outside this receipt's run chronology.")
    require(value.get("summary") == summary and value.get("testTree") == tree
            and value.get("classExecutedCounts") == counts, "Native receipt differs from actual executed results.")
    # Preserve the validated bytes and evidence fingerprint for the ending check.
    fingerprint = {"receipt": sha(data), "proof": proof, "log": sha(log_data),
                   "result": inventory, "compiler": compiler}
    require(checked_runtime_bytes(path) == data and native.result_bundle_hashes(bundle) == inventory
            and sha(log.read_bytes()) == sha(log_data)
            and all(sha(proof_path.read_bytes()) == proof[str(proof_path)] for proof_path in proof_paths)
            and native.validate_compiler_commands(log_data.decode(), root / "DerivedData", lane, original_source, snapshot["runtime_inputs"]) == compiler,
            "Native evidence changed during revalidation.")
    return {"lane": lane, "source_head": snapshot["head"], "source_tree": snapshot["tree"],
            "receipt_sha256": sha(data), "executed_tests": summary["passedTests"],
            "class_executed_counts": counts, "required_coordinated_tests": list(native.REQUIRED_COORDINATED_TESTS),
            "hosted_backend_deployed": False, "fingerprint": fingerprint}


def compiler_evidence(log_text, derived_data, source=None, source_inputs=None):
    """Require real optimized native paid compilation, bound to the actual source."""
    derived = Path(derived_data).resolve()
    commands = []
    for line in log_text.splitlines():
        if 'swiftc' not in line or '-module-name' not in line:
            continue
        tokens = shlex.split(line)
        if '-module-name' not in tokens:
            continue
        index = tokens.index('-module-name')
        if index + 1 >= len(tokens) or tokens[index + 1] != 'iChart':
            continue
        wrapper = tokens[0] if len(tokens) > 2 and tokens[0] in XCODE_SWIFT_WRAPPERS and tokens[1] == '--' else None
        start = 2 if wrapper else 0
        require(len(tokens) > start and Path(tokens[start]).is_absolute() and Path(tokens[start]).name == 'swiftc'
                and '/Contents/Developer/Toolchains/' in tokens[start], 'App evidence must start with the actual Xcode Swift driver.')
        tokens = expand_responses(tokens, derived)
        require('-target' in tokens and tokens.index('-target') + 1 < len(tokens), 'App compiler target missing.')
        target = tokens[tokens.index('-target') + 1]
        require(re.fullmatch(r'arm64(?:e)?-apple-ios[0-9.]+', target), 'App compiler must target native arm64 iOS.')
        require('-Onone' not in tokens and any(p in tokens for p in ('-O', '-Osize', '-Ounchecked')), 'App compiler must be optimized Release.')
        conditions = set()
        i = 0
        while i < len(tokens):
            token = tokens[i]
            if token in {'-Xcc', '-Xllvm', '-Xlinker', '-Xfrontend'}:
                require(i + 1 < len(tokens), 'Incomplete forwarded compiler argument.')
                require(token != '-Xfrontend' or not tokens[i + 1].startswith('-D'), 'Forwarded Swift conditions are unsupported.')
                i += 2
                continue
            if token == '-D':
                require(i + 1 < len(tokens), 'Incomplete Swift condition.')
                conditions.add(tokens[i + 1])
                i += 2
                continue
            if token.startswith('-D') and len(token) > 2:
                conditions.add(token[2:])
            i += 1
        require(not {p.split('=', 1)[0] for p in conditions}.intersection(FORBIDDEN_FLAGS), 'App compiler contains a forbidden staging, Debug or local-QA condition.')
        require(conditions == REQUIRED_FLAGS, 'Actual app compilation must contain exactly paid, isolated catalog and coordinated-QA conditions.')
        map_receipt = None
        if source is not None:
            require('-output-file-map' in tokens and tokens.index('-output-file-map') + 1 < len(tokens), 'App compiler output map missing.')
            path = Path(tokens[tokens.index('-output-file-map') + 1]).resolve()
            require(path.is_relative_to(derived) and path.is_file(), 'App compiler output map outside this build.')
            mapping = json.loads(path.read_text())
            require({(source / p).resolve() for p in REQUIRED_SOURCES} <= {Path(p).resolve() for p in mapping if p}, 'App compiler not bound to current policy, catalog and namespace.')
            actual_paths = [p for p in tokens if p.endswith(".swift")]
            mapped_paths = [p for p in mapping if p.endswith(".swift")]
            require(all(Path(p).is_absolute() for p in actual_paths + mapped_paths), "Archive Swift input paths must be absolute.")
            actual = {str(Path(p).resolve()) for p in actual_paths}
            mapped = {str(Path(p).resolve()) for p in mapped_paths}
            require(actual == mapped, "Archive output map differs from its complete Swift file list.")
            closure = native.bind_swift_inputs(actual, source, derived,
                native.source_manifest(source) if source_inputs is None else source_inputs)
            map_receipt = {'path': str(path.relative_to(derived)), 'sha256': sha(path.read_bytes()), **closure}
        commands.append({'wrapper': wrapper or 'direct-swiftc', 'conditions': sorted(conditions),
                         'command_sha256': sha(line.encode()), 'output_file_map': map_receipt})
    require(commands and any(p['wrapper'] != 'builtin-Swift-Compilation-Requirements' for p in commands),
            'No actual iChart driver/compilation; requirements-only/build-setting evidence is insufficient.')
    return commands

def build_metadata(source, derived, pin_time, source_inputs=None):
    result = []
    for path in derived.rglob('build-request.json'):
        if not path.parent.name.endswith('.xcbuilddata'):
            continue
        request = json.loads(path.read_text())
        if Path(request.get('containerPath', '')).resolve() != (source / 'iChart.xcodeproj').resolve():
            continue
        require(path.stat().st_mtime >= pin_time, 'Archive request predates source pin.')
        params = request.get('parameters', {})
        require(request.get('useDryRun') is False and params.get('configurationName') == 'Release'
                and request.get('schemeCommand') == 'archive' and params.get('action') in {'install', 'archive'}
                and params.get('activeRunDestination', {}).get('platform') == 'iphoneos', 'Not a native Release archive request.')
        manifest_path = path.with_name('manifest.json')
        manifest = json.loads(manifest_path.read_text())
        matched = []
        for name, command in manifest.get('commands', {}).items():
            if command.get('tool') != 'swift-driver-compilation' or not re.fullmatch(
                    r'SwiftDriver Compilation iChart normal arm64(?:e)? com\.apple\.xcode\.tools\.swift\.compiler', command.get('description', '')):
                continue
            require(':Release:SwiftDriver Compilation iChart normal ' in name, 'App compiler manifest is not Release.')
            require({(source / p).resolve() for p in REQUIRED_SOURCES} <=
                    {Path(p).resolve() for p in command.get('inputs', []) if p.startswith('/')}, 'Build manifest not bound to current public source.')
            closure = native.bind_swift_inputs([p for p in command.get('inputs', []) if p.endswith('.swift')],
                source, derived, native.source_manifest(source) if source_inputs is None else source_inputs)
            outputs = command.get('outputs', [])
            require(outputs and all(Path(p).resolve().is_relative_to(derived.resolve()) for p in outputs)
                    and any('Release-iphoneos' in p and 'iChart.build' in p for p in outputs), 'App compiler outputs outside this native Release build.')
            matched.append({'command_sha256': sha(json.dumps(command, sort_keys=True).encode()), 'swift_inputs': closure})
        require(matched, 'No app compilation command in archive manifest.')
        result.append({'request_sha256': sha(path.read_bytes()), 'manifest_sha256': sha(manifest_path.read_bytes()),
                       'app_command_sha256': matched})
    require(result, 'No fresh native Release archive metadata.')
    return result


def archive_source_bindings_match(compiler, metadata):
    def fingerprint(value):
        require(isinstance(value, dict) and value.get("sourceInputHashes"), "Missing complete archive source closure.")
        return json.dumps({key: value[key] for key in ("sourceInputHashes", "generatedInputHashes")}, sort_keys=True)
    compiled = {fingerprint(row["output_file_map"]) for row in compiler}
    manifested = {fingerprint(command["swift_inputs"]) for row in metadata for command in row["app_command_sha256"]}
    require(compiled and compiled == manifested, "Actual compiler and archive manifest source closures differ.")



def qa_project_evidence(path, source, snapshot):
    data = checked_runtime_bytes(path)
    value = checked_json(data)
    require(value.get("schema") == 1 and value.get("preparedOnly") is True
            and value.get("buildExecuted") is False and value.get("deliveryReady") is False,
            "A preparation-only isolated QA project receipt is required.")
    require(value.get("sourceHead") == snapshot["head"] and value.get("sourceTree") == snapshot["tree"]
            and value.get("sourceInputs") == snapshot["runtime_inputs"], "QA prepared project is not source-bound.")
    require(value.get("qaOrigin") == recipe.QA_URL and value.get("qaKeySHA256") == recipe.QA_KEY_SHA256
            and value.get("artifactRelease") == snapshot["release"] and value.get("appConditions") == sorted(REQUIRED_FLAGS),
            "QA project receipt has foreign inputs.")
    root = path.resolve().parent
    spec_path = root / "coordinated-qa-archive-project.json"
    info_path = root / "iChart-Info.plist"
    for file in (spec_path, info_path):
        require(file.is_file() and not file.is_symlink(), "Prepared QA proof must be a regular file.")
    require(value.get("specPath") == str(spec_path) and value.get("infoPath") == str(info_path)
            and value.get("specSHA256") == sha(spec_path.read_bytes())
            and value.get("infoSHA256") == sha(info_path.read_bytes())
            and value.get("projectSHA256") == sha((source / "iChart.xcodeproj/project.pbxproj").read_bytes()),
            "Prepared QA specification/project/Info drifted.")
    spec = checked_json(spec_path.read_bytes())
    key = spec["targets"]["iChart"]["info"]["properties"]["SupabasePublishableKey"]
    require(isinstance(key, str) and sha(key.encode()) == recipe.QA_KEY_SHA256, "QA spec key hash mismatch.")
    original = json.loads(native.run(["xcodegen", "dump", "--no-env", "--type", "json", "--spec", str(source / "project.yml")], cwd=source))
    require(spec == recipe.make_archive_spec(original, root, key), "QA spec differs from the reviewed app-only transformation.")
    require(checked_runtime_bytes(path) == data
            and sha(spec_path.read_bytes()) == value["specSHA256"]
            and sha(info_path.read_bytes()) == value["infoSHA256"]
            and sha((source / "iChart.xcodeproj/project.pbxproj").read_bytes()) == value["projectSHA256"],
            "QA prepared project evidence changed during validation.")
    return {"receipt_sha256": sha(data), "spec_sha256": value["specSHA256"],
            "project_sha256": value["projectSHA256"], "info_sha256": value["infoSHA256"]}


def validate_info(info, version, build):
    expected = {"CFBundleIdentifier": base.BUNDLE_ID, "CFBundleExecutable": "iChart",
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
                "SupabaseURL": recipe.QA_URL, "SupabaseAnonKey": "", "UIDeviceFamily": [2],
                "CFBundleSupportedPlatforms": ["iPhoneOS"], "ITSAppUsesNonExemptEncryption": False,
                "TFInternalTestingOnly": True}
    for key, wanted in expected.items():
        require(type(info.get(key)) is type(wanted) and info[key] == wanted, "Baked QA app setting mismatch: " + key)
    key = info.get("SupabasePublishableKey")
    require(isinstance(key, str) and re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{16,}", key)
            and sha(key.encode()) == recipe.QA_KEY_SHA256, "Baked QA publishable-key hash mismatch.")
    return {"bundle_id": base.BUNDLE_ID, "version": version, "build": build, "host": recipe.QA_URL,
            "publishable_key_sha256": recipe.QA_KEY_SHA256, "legacy_anon_empty": True,
            "ipad_only": True, "actual_internal_only": True}


def validate_export_options(options):
    expected = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                "signingCertificate": "Apple Distribution", "teamID": base.TEAM,
                "provisioningProfiles": {base.BUNDLE_ID: "iChart App Store"},
                "manageAppVersionAndBuildNumber": False, "testFlightInternalTestingOnly": True}
    for key, wanted in expected.items():
        require(type(options.get(key)) is type(wanted) and options[key] == wanted, "QA export option mismatch: " + key)
    return {"internal_only": True, "method": "app-store-connect", "distribution": "manual App Store"}


def verify_app(app, version, build):
    base.run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    signer = base.run('/usr/bin/codesign', '-dv', '--verbose=4', str(app)).stderr.decode()
    require('Authority=Apple Distribution:' in signer and ('TeamIdentifier=' + base.TEAM + '\n') in signer,
            'App must have an Apple Distribution signature from the iChart team.')
    result = validate_info(plistlib.loads((app / 'Info.plist').read_bytes()), version, build)
    result['active_der_entitlements'] = base.active_entitlements(app)
    profile_path = app / 'embedded.mobileprovision'
    profile = plistlib.loads(base.run('/usr/bin/security', 'cms', '-D', '-i', str(profile_path)).stdout)
    expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
    require(expiry > datetime.datetime.now(datetime.timezone.utc), 'Distribution profile expired.')
    require(profile.get('Name') == 'iChart App Store' and profile.get('TeamIdentifier') == [base.TEAM]
            and 'ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices'),
            'Expected an App Store distribution profile without device scope.')
    grants = profile.get('Entitlements', {})
    require(all(type(grants.get(k)) is type(v) and grants[k] == v for k, v in base.ACTIVE_ENTITLEMENTS.items()),
            'Distribution profile entitlement mismatch.')
    paths = list(app.rglob('*'))
    require(not any(p.is_symlink() for p in paths), 'Unexpected app symlink.')
    files = {p.relative_to(app).as_posix(): sha(p.read_bytes()) for p in paths if p.is_file()}
    base.validate_inventory(files)
    executable = (app / 'iChart').read_bytes()
    require(all(item.encode() in executable for item in PRODUCTS.values()), 'Isolated QA products absent from executable.')
    require(not any(item in executable for item in (b'com.ichart.app.pro.monthly', b'com.ichart.app.pro.annual')),
            'Public production products present in coordinated QA executable.')
    result.update({'strict_signature': True, 'profile_uuid': profile['UUID'], 'profile_expiry_utc': expiry.isoformat(),
                   'profile_sha256': sha(profile_path.read_bytes()), 'executable_sha256': sha(executable),
                   'uuid': base.uuid(app / 'iChart'), 'files': files})
    return result


def verify(args):
    source = args.source.resolve()
    immutable_inputs = {}
    for path in (args.ipa, args.export_options, args.build_log):
        require(path.is_file() and not path.is_symlink(), "Artifact evidence must be regular files.")
        immutable_inputs[str(path)] = sha(path.read_bytes())
    current = snapshot_source(source)
    policy_data = checked_policy_bytes(args.release_policy)
    policy = release_policy(args.release_policy, current, data=policy_data)
    policy_hash = sha(policy_data)
    pin_data = checked_pin_bytes(args.source_pin)
    pin = checked_json(pin_data)
    require(pin.get("schema") == 1 and pin.get("package_mode") == "coordinated_staging_qa_held"
            and pin.get("source") == str(source) and pin.get("snapshot") == current,
            "Current source/build inputs differ from the paid source pin.")
    require(pin.get("release_policy_sha256") == policy_hash,
            "Checked hold policy changed after pinning.")
    runtime = runtime_evidence(args.runtime_receipt, source, current, "coordinated-staging-qa")
    project_proof = qa_project_evidence(args.qa_project_receipt, source, current)
    require(pin.get("qa_native_runtime") == runtime and pin.get("qa_project") == project_proof,
            "QA evidence differs from the pre-archive pin.")
    pin_time = datetime.datetime.fromisoformat(pin["pinned_at_utc"]).timestamp()
    compiler = compiler_evidence(args.build_log.read_text(), args.derived_data, source, current["runtime_inputs"])
    metadata = build_metadata(source, args.derived_data, pin_time, current["runtime_inputs"])
    archive_source_bindings_match(compiler, metadata)
    options = validate_export_options(plistlib.loads(args.export_options.read_bytes()))
    apps = list((args.archive / "Products/Applications").glob("*.app"))
    require(len(apps) == 1 and apps[0].name == "iChart.app", "Archive must contain exactly iChart.app.")
    version, build = current["release"]["version"], current["release"]["build"]
    archive = verify_app(apps[0], version, build)
    dsym_path = args.archive / "dSYMs/iChart.app.dSYM/Contents/Resources/DWARF/iChart"
    require(dsym_path.is_file() and not dsym_path.is_symlink(), "dSYM must be a regular immutable file.")
    dsym_hash = sha(dsym_path.read_bytes())
    dsym_uuid = base.uuid(dsym_path)
    with tempfile.TemporaryDirectory(prefix="ichart-coordinated-qa-ipa-") as directory:
        exported_app, names = base.unpack_ipa(args.ipa, Path(directory))
        exported = verify_app(exported_app, version, build)
        require(archive["uuid"] == exported["uuid"] == dsym_uuid, "Archive/IPA/dSYM UUID mismatch.")
        differences = base.compare_export(apps[0], exported_app, archive["files"], exported["files"])
    require(snapshot_source(source) == current, "Source changed during paid artifact verification.")
    final_policy_data = checked_policy_bytes(args.release_policy)
    require(final_policy_data == policy_data,
            "Checked hold policy changed during paid artifact verification.")
    require(release_policy(args.release_policy, current, data=final_policy_data) == policy,
            "Checked hold policy no longer matches the validated policy.")
    require(runtime_evidence(args.runtime_receipt, source, current, "coordinated-staging-qa") == runtime
            and qa_project_evidence(args.qa_project_receipt, source, current) == project_proof,
            "QA semantic/project evidence changed during artifact verification.")
    require(compiler_evidence(args.build_log.read_text(), args.derived_data, source, current["runtime_inputs"]) == compiler
            and build_metadata(source, args.derived_data, pin_time, current["runtime_inputs"]) == metadata,
            "Archive compiler/maps/generated sources or build manifests changed during verification.")
    require({str(path): sha(path.read_bytes()) for path in (args.ipa, args.export_options, args.build_log)} == immutable_inputs
            and sha(dsym_path.read_bytes()) == dsym_hash and verify_app(apps[0], version, build) == archive,
            "Signed artifact, dSYM, compiler log or export evidence changed during verification.")
    require(snapshot_source(source) == current and checked_policy_bytes(args.release_policy) == policy_data
            and checked_pin_bytes(args.source_pin) == pin_data,
            "Source or checked hold policy changed during final semantic evidence verification.")
    return {
        "schema": 2, "package_mode": "coordinated_staging_qa_held", "artifact_verified": True,
        "verified_at_utc": base.now(), "source": current,
        "source_pin_sha256": sha(pin_data),
        "release_policy": policy, "release_policy_sha256": policy_hash,
        "distribution_held": True, "apple_delivery_held": True, "delivery_ready": False,
        "automatic_activation": False, "production_activation_approved": False,
        "coordinated_qa_native_verified": True, "qa_native_runtime": runtime, "qa_project": project_proof,
        "production_artifact_verified": False, "production_native_verified": False, "apple_prices_verified": False,
        "live_backend_verified_by_packager": False,
        "compiler": compiler, "archive_build_metadata": metadata,
        "archive": archive, "exported_app": exported, "export_options": options,
        "export_options_sha256": immutable_inputs[str(args.export_options)],
        "ipa_sha256": immutable_inputs[str(args.ipa)], "ipa_bytes": args.ipa.stat().st_size,
        "dsym_uuid": dsym_uuid, "classified_export_changes": differences,
        "limits": [
            "This verifies a HELD artifact, not Apple upload or distribution readiness.",
            "Source-bound native fixtures verify coordinated phase behavior; no hosted RPC deployment or activation is certified.",
            "QA phase authority does not authorize production activation or delivery.",
            "Apple-loaded prices, review/billing/grace state and production server policy need separate live receipts.",
            "Runtime endpoint semantics require the reviewed source and its native tests; baked Info is not a runtime probe.",
            "Device preservation and TestFlight automatic-update gates remain separate.",
        ],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    pin = modes.add_parser("pin")
    verification = modes.add_parser("verify")
    for command in (pin, verification):
        command.add_argument("--source", type=Path, required=True)
        command.add_argument("--release-policy", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
        command.add_argument("--runtime-receipt", type=Path, required=True)
        command.add_argument("--qa-project-receipt", type=Path, required=True)
    verification.add_argument("--source-pin", type=Path, required=True)
    verification.add_argument("--archive", type=Path, required=True)
    verification.add_argument("--derived-data", type=Path, required=True)
    verification.add_argument("--build-log", type=Path, required=True)
    verification.add_argument("--export-options", type=Path, required=True)
    verification.add_argument("--ipa", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.mode == "pin":
        source = args.source.resolve()
        snapshot = snapshot_source(source)
        policy_data = checked_policy_bytes(args.release_policy)
        release_policy(args.release_policy, snapshot, data=policy_data)
        runtime = runtime_evidence(args.runtime_receipt, source, snapshot, "coordinated-staging-qa")
        project_proof = qa_project_evidence(args.qa_project_receipt, source, snapshot)
        value = {"schema": 1, "package_mode": "coordinated_staging_qa_held", "source": str(source),
                 "qa_native_runtime": runtime, "qa_project": project_proof,
                 "pinned_at_utc": base.now(), "snapshot": snapshot,
                 "release_policy_sha256": sha(policy_data)}
        require(checked_policy_bytes(args.release_policy) == policy_data and snapshot_source(source) == snapshot,
                "Source or checked hold policy changed while pinning.")
    else:
        value = verify(args)
    base.write_json(args.output, value)
    print("Held coordinated-QA source pin recorded." if args.mode == "pin" else
          "Coordinated QA artifact integrity verified. APPLE DELIVERY REMAINS HELD; no upload or activation is authorized.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (GuardError, KeyError, OSError, ValueError, TypeError) as error:
        print("Coordinated QA verification failed: " + (str(error) if isinstance(error, GuardError) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
