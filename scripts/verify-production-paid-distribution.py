#!/usr/bin/env python3
"""Read-only production-paid artifact guard. Success keeps Apple delivery HELD."""
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
    Path(__file__).with_name("run_production_paid_validation.py"))
native = importlib.util.module_from_spec(_RUNTIME_SPEC)
_RUNTIME_SPEC.loader.exec_module(native)
# Reuse the unchanged public verifier's byte/signature checks in an isolated module.
# Its policy constants are never modified.
GuardError, require, sha = base.GuardError, base.require, base.sha
XCODE_SWIFT_WRAPPERS = base.XCODE_SWIFT_WRAPPERS
expand_responses = base.expand_responses
PAID_FLAG = "ICHART_PAID_SUBSCRIPTION"
FORBIDDEN_FLAGS = {"DEBUG", "ICHART_STAGING_STOREKIT_PRODUCTS",
                   "ICHART_LOCAL_PLAN_QA", "ICHART_LOCAL_QA_PLAN_PREVIEW"}
REQUIRED_SOURCES = base.REQUIRED_SOURCES + (
    "iChart/App/Supabase/IChartSupabaseConfiguration.swift",
    "iChart/App/IChartApp.swift",
    "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift",
    "iChart/Models/AppEntitlements.swift",
) + tuple(p for p in native.REQUIRED_RUNTIME_APP_SOURCES if p not in base.REQUIRED_SOURCES and p not in {
    "iChart/App/Supabase/IChartSupabaseConfiguration.swift", "iChart/App/IChartApp.swift",
    "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift", "iChart/Models/AppEntitlements.swift"})
PRODUCTS = {"monthly": "com.ichart.app.pro.monthly", "annual": "com.ichart.app.pro.annual"}
PRICE_CENTS = {"monthly": 699, "annual": 6000}


def source_contracts(source):
    public = base.source_contracts(source)
    catalog = (source / "iChart/Models/IChartStoreKitProductCatalog.swift").read_text()
    match = re.search(r"#if ICHART_STAGING_STOREKIT_PRODUCTS\s*\n.*?#else\s*\n(.*?)#endif", catalog, re.S)
    require(match is not None, "Explicit production StoreKit catalog branch missing.")
    production = match.group(1)
    for name, value in (("proMonthlyProductID", PRODUCTS["monthly"]),
                        ("proAnnualProductID", PRODUCTS["annual"])):
        found = re.findall(r'^\s*static let ' + name + r'\s*=\s*"([^"\n]+)"\s*$', production, re.M)
        require(found == [value], "Production StoreKit ID contract changed: " + name)
    for name, value in (("targetMonthlyPriceCents", PRICE_CENTS["monthly"]),
                        ("targetAnnualPriceCents", PRICE_CENTS["annual"])):
        found = re.findall(r'^\s*static let ' + name + r'\s*=\s*([0-9][0-9_]*)\s*$', production, re.M)
        require(len(found) == 1 and int(found[0].replace("_", "")) == value,
                "Production catalog target must be USD6.99/month and exactlyUSD60.00/year.")
    for name in REQUIRED_SOURCES:
        require((source / name).is_file() and not (source / name).is_symlink(),
                "Required paid runtime source missing or symlinked.")
    return {"compile_time_policy": "paidSubscription", "normal_default_policy": public["policy"],
            "namespace": public["namespace"], "authKeys": public["authKeys"],
            "production_url": base.PRODUCTION_URL,
            "production_key_sha256": base.PRODUCTION_KEY_SHA256,
            "storeKitProducts": PRODUCTS, "target_prices_usd_minor_units": PRICE_CENTS,
            "apple_prices_verified": False,
            "preactivation_runtime_proof_required": True,
            "activation_strategy": "server_coordinated_runtime_phase"}


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
    current["release"] = project_identity(source)
    # Bind client tests and backend/RPC fixtures as well as compiled app inputs.
    current["runtime_inputs"] = native.source_manifest(source)
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
    require(isinstance(data, bytes) and len(data) <= 16384, "Invalid checked release-policy bytes.")
    value = checked_json(data)
    require(isinstance(value, dict), "Release-policy receipt must be an object.")
    expected = {
        "schema": 2, "package_mode": "production_paid",
        "source_head": snapshot["head"], "source_tree": snapshot["tree"],
        "version": snapshot["release"]["version"], "build": snapshot["release"]["build"],
        "distribution_held": True, "apple_delivery_held": True,
        "automatic_activation": False, "production_activation_approved": False,
        "activation_strategy": "server_coordinated_runtime_phase",
        "public_beta_must_remain_on": True, "deploy_to_production_must_remain_off": True,
    }
    require(set(value) <= set(expected) | {"target_cutover_utc"}, "Unknown release-policy fields.")
    for key, expected_value in expected.items():
        require(type(value.get(key)) is type(expected_value) and value[key] == expected_value,
                "Held production-paid release-policy mismatch: " + key)
    if "target_cutover_utc" in value:
        target = value["target_cutover_utc"]
        require(isinstance(target, str) and target.endswith("Z"), "Target must be an explicit UTC timestamp.")
        try:
            datetime.datetime.fromisoformat(target[:-1] + "+00:00")
        except ValueError:
            raise GuardError("Invalid target UTC timestamp.")
    # A target date is descriptive. No clock comparison can clear either hold.
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
        "scripts/run_production_paid_validation.py", "scripts/test_production_paid_validation.py",
    )
    proof = {str(original_source / p): sha((source / p).read_bytes()) for p in source_paths}
    proof_paths = [project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                   root / "paid-validation-project.json", project / "project.pbxproj", root / "iChart-Info.plist"]
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
    bundle = root / "paid-validation.xcresult"
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
        require(conditions == {PAID_FLAG}, 'Actual app compilation must contain only the explicit production-paid Swift condition.')
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
    require(pin.get("schema") == 1 and pin.get("package_mode") == "production_paid_held"
            and pin.get("source") == str(source) and pin.get("snapshot") == current,
            "Current source/build inputs differ from the paid source pin.")
    require(pin.get("release_policy_sha256") == policy_hash,
            "Checked hold policy changed after pinning.")
    runtime = {lane: runtime_evidence(path, source, current, lane) for lane, path in (
        ("production-paid", args.runtime_receipt), ("public-free", args.normal_free_runtime_receipt))}
    require(pin.get("paired_native_runtime") == runtime, "Native semantic evidence differs from the pre-archive source pin.")
    pin_time = datetime.datetime.fromisoformat(pin["pinned_at_utc"]).timestamp()
    compiler = compiler_evidence(args.build_log.read_text(), args.derived_data, source, current["runtime_inputs"])
    metadata = build_metadata(source, args.derived_data, pin_time, current["runtime_inputs"])
    archive_source_bindings_match(compiler, metadata)
    options = base.validate_export_options(plistlib.loads(args.export_options.read_bytes()))
    apps = list((args.archive / "Products/Applications").glob("*.app"))
    require(len(apps) == 1 and apps[0].name == "iChart.app", "Archive must contain exactly iChart.app.")
    version, build = current["release"]["version"], current["release"]["build"]
    archive = base.verify_app(apps[0], version, build)
    dsym_path = args.archive / "dSYMs/iChart.app.dSYM/Contents/Resources/DWARF/iChart"
    require(dsym_path.is_file() and not dsym_path.is_symlink(), "dSYM must be a regular immutable file.")
    dsym_hash = sha(dsym_path.read_bytes())
    dsym_uuid = base.uuid(dsym_path)
    with tempfile.TemporaryDirectory(prefix="ichart-production-paid-ipa-") as directory:
        exported_app, names = base.unpack_ipa(args.ipa, Path(directory))
        exported = base.verify_app(exported_app, version, build)
        require(archive["uuid"] == exported["uuid"] == dsym_uuid, "Archive/IPA/dSYM UUID mismatch.")
        differences = base.compare_export(apps[0], exported_app, archive["files"], exported["files"])
    require(snapshot_source(source) == current, "Source changed during paid artifact verification.")
    final_policy_data = checked_policy_bytes(args.release_policy)
    require(final_policy_data == policy_data,
            "Checked hold policy changed during paid artifact verification.")
    require(release_policy(args.release_policy, current, data=final_policy_data) == policy,
            "Checked hold policy no longer matches the validated policy.")
    require({lane: runtime_evidence(path, source, current, lane) for lane, path in (
        ("production-paid", args.runtime_receipt), ("public-free", args.normal_free_runtime_receipt))} == runtime,
        "Native semantic evidence changed during artifact verification.")
    require(compiler_evidence(args.build_log.read_text(), args.derived_data, source, current["runtime_inputs"]) == compiler
            and build_metadata(source, args.derived_data, pin_time, current["runtime_inputs"]) == metadata,
            "Archive compiler/maps/generated sources or build manifests changed during verification.")
    require({str(path): sha(path.read_bytes()) for path in (args.ipa, args.export_options, args.build_log)} == immutable_inputs
            and sha(dsym_path.read_bytes()) == dsym_hash and base.verify_app(apps[0], version, build) == archive,
            "Signed artifact, dSYM, compiler log or export evidence changed during verification.")
    require(snapshot_source(source) == current and checked_policy_bytes(args.release_policy) == policy_data
            and checked_pin_bytes(args.source_pin) == pin_data,
            "Source or checked hold policy changed during final semantic evidence verification.")
    return {
        "schema": 2, "package_mode": "production_paid_held", "artifact_verified": True,
        "verified_at_utc": base.now(), "source": current,
        "source_pin_sha256": sha(pin_data),
        "release_policy": policy, "release_policy_sha256": policy_hash,
        "distribution_held": True, "apple_delivery_held": True, "delivery_ready": False,
        "automatic_activation": False, "production_activation_approved": False,
        "preactivation_free_pro_supported": True, "paired_native_runtime": runtime,
        "normal_free_native_verified": True, "apple_prices_verified": False,
        "live_backend_verified_by_packager": False,
        "compiler": compiler, "archive_build_metadata": metadata,
        "archive": archive, "exported_app": exported, "export_options": options,
        "export_options_sha256": immutable_inputs[str(args.export_options)],
        "ipa_sha256": immutable_inputs[str(args.ipa)], "ipa_bytes": args.ipa.stat().st_size,
        "dsym_uuid": dsym_uuid, "classified_export_changes": differences,
        "limits": [
            "This verifies a HELD artifact, not Apple upload or distribution readiness.",
            "Source-bound native fixtures verify coordinated phase behavior; no hosted RPC deployment or activation is certified.",
            "Target time does not activate the app or clear the delivery hold.",
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
        command.add_argument("--normal-free-runtime-receipt", type=Path, required=True)
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
        runtime = {lane: runtime_evidence(path, source, snapshot, lane) for lane, path in (
            ("production-paid", args.runtime_receipt), ("public-free", args.normal_free_runtime_receipt))}
        value = {"schema": 1, "package_mode": "production_paid_held", "source": str(source),
                 "paired_native_runtime": runtime,
                 "pinned_at_utc": base.now(), "snapshot": snapshot,
                 "release_policy_sha256": sha(policy_data)}
        require(checked_policy_bytes(args.release_policy) == policy_data and snapshot_source(source) == snapshot,
                "Source or checked hold policy changed while pinning.")
    else:
        value = verify(args)
    base.write_json(args.output, value)
    print("Held production-paid source pin recorded." if args.mode == "pin" else
          "Paid artifact integrity verified. APPLE DELIVERY REMAINS HELD; no upload or activation is authorized.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (GuardError, KeyError, OSError, ValueError, TypeError) as error:
        print("Production-paid verification failed: " + (str(error) if isinstance(error, GuardError) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
