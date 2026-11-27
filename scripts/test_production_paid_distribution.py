"""Synthetic local guards for held production-paid artifacts; never builds/signs/uploads."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("held_production_paid_guard", Path(__file__).with_name("verify-production-paid-distribution.py"))
packaging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packaging)


class ProductionPaidDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ichart-held-paid-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.derived = self.root / "DerivedData"
        self.objects = self.derived / "Release-iphoneos/iChart.build/Objects-normal/arm64"
        self.objects.mkdir(parents=True)
        for name in packaging.REQUIRED_SOURCES:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// Synthetic source-path fixture, never compiled.\n")
        self.mapping = self.objects / "OutputFileMap.json"
        self.mapping.write_text(json.dumps({str(self.source / p): {"object": str(self.objects / "object.o")} for p in packaging.REQUIRED_SOURCES}))
        self.tokens = ["builtin-SwiftDriver", "--", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc", "-module-name", "iChart", "-O", "-target", "arm64-apple-ios17.0", "-output-file-map", str(self.mapping), "-D", packaging.PAID_FLAG]
        self.snapshot = {"head": "a" * 40, "tree": "b" * 40, "files": {"example": "c" * 64}, "release": {"version": "1.9.4", "build": "206"}}
        self.policy_path = self.root / "release-policy.json"
        self.policy = {"schema": 1, "package_mode": "production_paid", "source_head": self.snapshot["head"], "source_tree": self.snapshot["tree"], "version": "1.9.4", "build": "206", "distribution_held": True, "apple_delivery_held": True, "automatic_activation": False, "production_activation_approved": False, "preactivation_free_pro_supported": False, "public_beta_must_remain_on": True, "deploy_to_production_must_remain_off": True, "target_cutover_utc": "2026-12-01T17:00:00Z"}
        self.write_policy()

    def write_policy(self, value=None):
        self.policy_path.write_text(json.dumps(self.policy if value is None else value))

    def evidence(self, tokens=None):
        return packaging.compiler_evidence(shlex.join(self.tokens if tokens is None else tokens) + "\n", self.derived, self.source)

    def contract_sources(self):
        (self.source / packaging.REQUIRED_SOURCES[0]).write_text("#if ICHART_PAID_SUBSCRIPTION\nstatic let current: Self = .paidSubscription\n#else\nstatic let current: Self = .freeAllFeatures\n#endif\n")
        (self.source / packaging.REQUIRED_SOURCES[1]).write_text('''#if ICHART_STAGING_STOREKIT_PRODUCTS
static let proMonthlyProductID = "com.ichart.app.staging.fix036.monthly"
static let proAnnualProductID = "com.ichart.app.staging.fix036.annual"
static let targetMonthlyPriceCents = 699
static let targetAnnualPriceCents = 6_000
#else
static let proMonthlyProductID = "com.ichart.app.pro.monthly"
static let proAnnualProductID = "com.ichart.app.pro.annual"
static let targetMonthlyPriceCents = 699
static let targetAnnualPriceCents = 6_000
#endif
''')
        (self.source / packaging.REQUIRED_SOURCES[2]).write_text('''#if ICHART_STAGING_STOREKIT_PRODUCTS
static let mode: Mode = .internalStaging
#else
static let mode: Mode = .publicApp
#endif
case .publicApp:
return .standard
case .internalStaging:
case .publicApp:
return root
case .internalStaging:
mode == .internalStaging ? stagingAuthKeyPrefix + key : key
''')

    def test_actual_paid_compilation_requires_real_driver_and_all_current_runtime_files(self):
        self.assertEqual(self.evidence()[0]["conditions"], [packaging.PAID_FLAG])
        mapping = json.loads(self.mapping.read_text())
        mapping.pop(str(self.source / "iChart/App/Supabase/IChartSupabaseConfiguration.swift"))
        self.mapping.write_text(json.dumps(mapping))
        with self.assertRaises(packaging.GuardError): self.evidence()

    def test_free_debug_staging_qa_unknown_or_valued_conditions_fail(self):
        for flags in ([], ["-D", packaging.PAID_FLAG + "=1"], ["-Xcc", "-D" + packaging.PAID_FLAG]):
            with self.subTest(flags=flags), self.assertRaises(packaging.GuardError): self.evidence(self.tokens[:-2] + flags)
        for flag in packaging.FORBIDDEN_FLAGS | {"ICHART_UNREVIEWED_FEATURE"}:
            with self.subTest(flag=flag), self.assertRaises(packaging.GuardError): self.evidence(self.tokens + ["-D" + flag])

    def test_response_files_cannot_hide_forbidden_conditions_or_escape(self):
        response = self.objects / "flags.rsp"
        response.write_text("-D ICHART_PAID_SUBSCRIPTION")
        self.assertTrue(self.evidence(self.tokens[:-2] + ["@" + str(response)]))
        response.write_text("-D ICHART_PAID_SUBSCRIPTION -D ICHART_LOCAL_PLAN_QA")
        with self.assertRaises(packaging.GuardError): self.evidence(self.tokens[:-2] + ["@" + str(response)])
        outside = self.root / "outside.rsp";outside.write_text("-D ICHART_PAID_SUBSCRIPTION")
        with self.assertRaises(packaging.GuardError): self.evidence(self.tokens[:-2] + ["@" + str(outside)])

    def test_fake_requirements_only_wrong_module_simulator_and_debug_optimization_fail(self):
        variants = []
        for before, after in (("builtin-SwiftDriver", "echo"), ("builtin-SwiftDriver", "builtin-Swift-Compilation-Requirements"), ("iChart", "iChartTests"), ("arm64-apple-ios17.0", "arm64-apple-ios17.0-simulator"), ("-O", "-Onone")):
            tokens = list(self.tokens);tokens[tokens.index(before)] = after;variants.append(tokens)
        for tokens in variants:
            with self.subTest(tokens=tokens), self.assertRaises(packaging.GuardError): self.evidence(tokens)
        with self.assertRaises(packaging.GuardError): self.evidence(self.tokens + ["-Xfrontend", "-DDEBUG"])

    def test_public_verifier_policy_constants_are_not_mutated(self):
        before = set(packaging.base.FORBIDDEN_FLAGS)
        self.evidence()
        self.assertEqual(before, packaging.base.FORBIDDEN_FLAGS)
        self.assertIn(packaging.PAID_FLAG, packaging.base.FORBIDDEN_FLAGS)

    def test_production_catalog_public_namespace_and_agreed_prices_are_required(self):
        self.contract_sources()
        contract = packaging.source_contracts(self.source)
        self.assertEqual(contract["target_prices_usd_minor_units"], {"monthly": 699, "annual": 6000})
        self.assertEqual(contract["namespace"], "publicApp")
        self.assertFalse(contract["apple_prices_verified"])
        self.assertFalse(contract["preactivation_free_pro_supported"])
        path = self.source / packaging.REQUIRED_SOURCES[1]
        original = path.read_text()
        for old, new in (("699", "799"), ("6_000", "6_499"), ("com.ichart.app.pro.monthly", "com.ichart.app.staging.fix036.monthly"), ("= 699", "= 699 + 1")):
            path.write_text(original.replace(old, new))
            with self.subTest(change=new), self.assertRaises(packaging.GuardError): packaging.source_contracts(self.source)
        path.write_text(original)
        namespace = self.source / packaging.REQUIRED_SOURCES[2]
        namespace.write_text(namespace.read_text().replace("return .standard", "return .staging"))
        with self.assertRaises(packaging.GuardError): packaging.source_contracts(self.source)

    def test_project_identity_is_authoritative_and_literal(self):
        p = self.source / "project.yml"
        p.write_text('settings:\n  base:\n    MARKETING_VERSION: "1.9.4"\n    CURRENT_PROJECT_VERSION: "206"\n')
        self.assertEqual(packaging.project_identity(self.source), {"version": "1.9.4", "build": "206"})
        for value in ("0", "$(BUILD)", "206.1"):
            p.write_text('    MARKETING_VERSION: "1.9.4"\n    CURRENT_PROJECT_VERSION: "' + value + '"\n')
            with self.subTest(value=value), self.assertRaises(packaging.GuardError): packaging.project_identity(self.source)

    def test_policy_requires_source_bound_typed_hold_and_never_authorizes_by_time(self):
        self.assertEqual(packaging.release_policy(self.policy_path, self.snapshot), self.policy)
        for key, value in (("distribution_held", False), ("apple_delivery_held", False), ("automatic_activation", True), ("production_activation_approved", True), ("preactivation_free_pro_supported", True), ("public_beta_must_remain_on", False), ("schema", True), ("source_head", "d" * 40), ("build", "205")):
            altered = dict(self.policy);altered[key] = value;self.write_policy(altered)
            with self.subTest(key=key), self.assertRaises(packaging.GuardError): packaging.release_policy(self.policy_path, self.snapshot)
        past = dict(self.policy, target_cutover_utc="2020-01-01T00:00:00Z");self.write_policy(past)
        self.assertTrue(packaging.release_policy(self.policy_path, self.snapshot)["distribution_held"])
        for value in ("2026-12-01 09:00", "garbageZ"):
            self.write_policy(dict(self.policy, target_cutover_utc=value))
            with self.assertRaises(packaging.GuardError): packaging.release_policy(self.policy_path, self.snapshot)
        self.write_policy(dict(self.policy, delivery_override=True))
        with self.assertRaises(packaging.GuardError): packaging.release_policy(self.policy_path, self.snapshot)

    def test_paid_metadata_requires_current_config_and_all_runtime_sources(self):
        folder = self.derived / "Build/Intermediates.noindex/XCBuildData/example.xcbuilddata";folder.mkdir(parents=True)
        request = {"containerPath": str(self.source / "iChart.xcodeproj"), "useDryRun": False, "schemeCommand": "archive", "parameters": {"configurationName": "Release", "action": "install", "activeRunDestination": {"platform": "iphoneos"}}}
        (folder / "build-request.json").write_text(json.dumps(request))
        inputs = [str(self.source / p) for p in packaging.REQUIRED_SOURCES]
        command = {"tool": "swift-driver-compilation", "description": "SwiftDriver Compilation iChart normal arm64 com.apple.xcode.tools.swift.compiler", "inputs": inputs, "outputs": [str(self.objects / "object.o")]}
        manifest = {"commands": {"target:Release:SwiftDriver Compilation iChart normal arm64 compiler": command}}
        p = folder / "manifest.json";p.write_text(json.dumps(manifest))
        self.assertTrue(packaging.build_metadata(self.source, self.derived, 0))
        command["inputs"] = inputs[:-1];p.write_text(json.dumps(manifest))
        with self.assertRaises(packaging.GuardError): packaging.build_metadata(self.source, self.derived, 0)

    def verify_fixture(self):
        archive = self.root / "archive.xcarchive";app = archive / "Products/Applications/iChart.app";app.mkdir(parents=True)
        ipa = self.root / "iChart.ipa";ipa.write_bytes(b"Synthetic orchestrator fixture; not a real IPA")
        pin = self.root / "source-pin.json";pin.write_text(json.dumps({"schema": 1, "package_mode": "production_paid_held", "source": str(self.source.resolve()), "snapshot": self.snapshot, "release_policy_sha256": packaging.sha(self.policy_path.read_bytes()), "pinned_at_utc": "2026-01-01T00:00:00+00:00"}))
        options = self.root / "ExportOptions.plist";options.write_bytes(plistlib.dumps({"method": "app-store-connect", "destination": "export", "signingStyle": "manual", "signingCertificate": "Apple Distribution", "teamID": "N6G8X4K46U", "provisioningProfiles": {"com.ichart.app": "iChart App Store"}, "manageAppVersionAndBuildNumber": False, "testFlightInternalTestingOnly": False}))
        log = self.root / "archive.log";log.write_text("synthetic compiler orchestration")
        args = argparse.Namespace(source=self.source, release_policy=self.policy_path, source_pin=pin, archive=archive, derived_data=self.derived, build_log=log, export_options=options, ipa=ipa)
        return args, app

    def test_orchestration_reuses_strict_signatures_export_uuid_and_reports_held(self):
        args, app = self.verify_fixture()
        result = {"uuid": "SYNTHETIC-UUID", "files": {"iChart": "hash"}}
        with patch.object(packaging, "snapshot_source", return_value=self.snapshot), patch.object(packaging, "compiler_evidence", return_value=[{}]), patch.object(packaging, "build_metadata", return_value=[{}]), patch.object(packaging.base, "verify_app", return_value=result) as signatures, patch.object(packaging.base, "uuid", return_value="SYNTHETIC-UUID"), patch.object(packaging.base, "unpack_ipa", return_value=(app, set())), patch.object(packaging.base, "compare_export", return_value=[]) as comparison:
            receipt = packaging.verify(args)
        self.assertEqual(signatures.call_count, 2)
        signatures.assert_any_call(app, "1.9.4", "206")
        comparison.assert_called_once()
        self.assertTrue(receipt["artifact_verified"])
        self.assertFalse(receipt["delivery_ready"])
        self.assertFalse(receipt["preactivation_free_pro_supported"])
        self.assertFalse(receipt["apple_prices_verified"])
        self.assertNotIn("passed", receipt)

    def test_orchestration_rejects_policy_drift_before_archive_calls(self):
        args, app = self.verify_fixture();self.write_policy(dict(self.policy, target_cutover_utc="2027-01-01T00:00:00Z"))
        with patch.object(packaging, "snapshot_source", return_value=self.snapshot), patch.object(packaging.base, "verify_app") as verifier:
            with self.assertRaises(packaging.GuardError): packaging.verify(args)
        verifier.assert_not_called()

    def test_policy_drift_during_verification_is_rejected_and_fixture_restored(self):
        args, app = self.verify_fixture()
        original = self.policy_path.read_bytes()
        result = {"uuid": "SYNTHETIC-UUID", "files": {"iChart": "hash"}}
        def change_policy(*unused):
            self.write_policy(dict(self.policy, distribution_held=False))
            return []
        try:
            with patch.object(packaging, "snapshot_source", return_value=self.snapshot), patch.object(packaging, "compiler_evidence", return_value=[{}]), patch.object(packaging, "build_metadata", return_value=[{}]), patch.object(packaging.base, "verify_app", return_value=result), patch.object(packaging.base, "uuid", return_value="SYNTHETIC-UUID"), patch.object(packaging.base, "unpack_ipa", return_value=(app, set())), patch.object(packaging.base, "compare_export", side_effect=change_policy):
                with self.assertRaisesRegex(packaging.GuardError, "policy changed during"):
                    packaging.verify(args)
        finally:
            self.policy_path.write_bytes(original)
        self.assertEqual(self.policy_path.read_bytes(), original)

    def test_packaging_never_includes_staging_models_or_test_payloads(self):
        for name in ("Resources/model.mlmodel", "Resources/NeuralInk/data.json", "PlugIns/probe.xctest", "Resources/Test.storekit"):
            with self.subTest(name=name), self.assertRaises(packaging.GuardError): packaging.base.validate_inventory([name])


if __name__ == "__main__":
    unittest.main()
