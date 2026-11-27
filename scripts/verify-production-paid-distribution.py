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
import tempfile

_BASE_SPEC = importlib.util.spec_from_file_location(
    "ichart_public_guard_for_held_paid_artifacts",
    Path(__file__).with_name("verify_public_beta_archive.py"))
base = importlib.util.module_from_spec(_BASE_SPEC)
_BASE_SPEC.loader.exec_module(base)
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
)
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
            "preactivation_free_pro_supported": False,
            "activation_strategy": "hold_apple_delivery_until_separate_approval"}


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
    return current


def checked_policy_bytes(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16384,
            "Use a bounded regular checked release-policy receipt.")
    data = path.read_bytes()
    require(len(data) <= 16384, "Release-policy receipt grew beyond its bound.")
    return data


def release_policy(path, snapshot, *, data=None):
    data = checked_policy_bytes(path) if data is None else data
    require(isinstance(data, bytes) and len(data) <= 16384, "Invalid checked release-policy bytes.")
    value = json.loads(data)
    require(isinstance(value, dict), "Release-policy receipt must be an object.")
    expected = {
        "schema": 1, "package_mode": "production_paid",
        "source_head": snapshot["head"], "source_tree": snapshot["tree"],
        "version": snapshot["release"]["version"], "build": snapshot["release"]["build"],
        "distribution_held": True, "apple_delivery_held": True,
        "automatic_activation": False, "production_activation_approved": False,
        "preactivation_free_pro_supported": False,
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


def compiler_evidence(log_text, derived_data, source=None):
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
            map_receipt = {'path': str(path.relative_to(derived)), 'sha256': sha(path.read_bytes())}
        commands.append({'wrapper': wrapper or 'direct-swiftc', 'conditions': sorted(conditions),
                         'command_sha256': sha(line.encode()), 'output_file_map': map_receipt})
    require(commands and any(p['wrapper'] != 'builtin-Swift-Compilation-Requirements' for p in commands),
            'No actual iChart driver/compilation; requirements-only/build-setting evidence is insufficient.')
    return commands

def build_metadata(source, derived, pin_time):
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
            outputs = command.get('outputs', [])
            require(outputs and all(Path(p).resolve().is_relative_to(derived.resolve()) for p in outputs)
                    and any('Release-iphoneos' in p and 'iChart.build' in p for p in outputs), 'App compiler outputs outside this native Release build.')
            matched.append(sha(json.dumps(command, sort_keys=True).encode()))
        require(matched, 'No app compilation command in archive manifest.')
        result.append({'request_sha256': sha(path.read_bytes()), 'manifest_sha256': sha(manifest_path.read_bytes()),
                       'app_command_sha256': matched})
    require(result, 'No fresh native Release archive metadata.')
    return result

def verify(args):
    source = args.source.resolve()
    current = snapshot_source(source)
    policy_data = checked_policy_bytes(args.release_policy)
    policy = release_policy(args.release_policy, current, data=policy_data)
    policy_hash = sha(policy_data)
    pin = json.loads(args.source_pin.read_text())
    require(pin.get("schema") == 1 and pin.get("package_mode") == "production_paid_held"
            and pin.get("source") == str(source) and pin.get("snapshot") == current,
            "Current source/build inputs differ from the paid source pin.")
    require(pin.get("release_policy_sha256") == policy_hash,
            "Checked hold policy changed after pinning.")
    pin_time = datetime.datetime.fromisoformat(pin["pinned_at_utc"]).timestamp()
    compiler = compiler_evidence(args.build_log.read_text(), args.derived_data, source)
    metadata = build_metadata(source, args.derived_data, pin_time)
    options = base.validate_export_options(plistlib.loads(args.export_options.read_bytes()))
    apps = list((args.archive / "Products/Applications").glob("*.app"))
    require(len(apps) == 1 and apps[0].name == "iChart.app", "Archive must contain exactly iChart.app.")
    version, build = current["release"]["version"], current["release"]["build"]
    archive = base.verify_app(apps[0], version, build)
    dsym_uuid = base.uuid(args.archive / "dSYMs/iChart.app.dSYM/Contents/Resources/DWARF/iChart")
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
    return {
        "schema": 1, "package_mode": "production_paid_held", "artifact_verified": True,
        "verified_at_utc": base.now(), "source": current,
        "source_pin_sha256": sha(args.source_pin.read_bytes()),
        "release_policy": policy, "release_policy_sha256": policy_hash,
        "distribution_held": True, "apple_delivery_held": True, "delivery_ready": False,
        "automatic_activation": False, "production_activation_approved": False,
        "preactivation_free_pro_supported": False, "apple_prices_verified": False,
        "live_backend_verified_by_packager": False,
        "compiler": compiler, "archive_build_metadata": metadata,
        "archive": archive, "exported_app": exported, "export_options": options,
        "export_options_sha256": sha(args.export_options.read_bytes()),
        "ipa_sha256": sha(args.ipa.read_bytes()), "ipa_bytes": args.ipa.stat().st_size,
        "dsym_uuid": dsym_uuid, "classified_export_changes": differences,
        "limits": [
            "This verifies a HELD artifact, not Apple upload or distribution readiness.",
            "Paid capability immediately gates the client; do not distribute before separate cutover approval.",
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
        value = {"schema": 1, "package_mode": "production_paid_held", "source": str(source),
                 "pinned_at_utc": base.now(), "snapshot": snapshot,
                 "release_policy_sha256": sha(policy_data)}
        require(checked_policy_bytes(args.release_policy) == policy_data,
                "Checked hold policy changed while pinning.")
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
