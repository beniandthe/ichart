"""Synthetic QA artifact guards only; no signing, build, hosted or device action."""
import argparse
import ast
from collections import Counter
import copy
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("qa_guard", Path(__file__).with_name("verify-coordinated-staging-qa-distribution.py"))
qa = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(qa)
KEY = "sb_publishable_synthetic_qa_key_0123456789"


class CoordinatedQADistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ichart-qa-guard-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source, self.derived = self.root / "source", self.root / "DerivedData"
        self.derived.mkdir()
        key_patch = patch.object(qa.recipe, "QA_KEY_SHA256", qa.sha(KEY.encode()))
        key_patch.start(); self.addCleanup(key_patch.stop)
        for name in qa.REQUIRED_SOURCES:
            path = self.source / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// Synthetic pinned Swift fixture, never compiled")
        self.inputs = {str(p.relative_to(self.source)): qa.sha(p.read_bytes()) for p in self.source.rglob("*") if p.is_file()}
        self.map = self.derived / "map.json"
        self.map.write_text(json.dumps({str(self.source / p): {} for p in qa.REQUIRED_SOURCES}))
        self.snapshot = {"head": "a" * 40, "tree": "b" * 40, "files": {}, "runtime_inputs": self.inputs,
                         "source_release": {"version": "1.9.4", "build": "210"}, "release": {"version": "1.9.4", "build": "209"}}
        self.policy = {"schema": 2, "package_mode": "coordinated_staging_qa", "source_head": self.snapshot["head"],
                       "source_tree": self.snapshot["tree"], "version": "1.9.4", "build": "209",
                       "source_version": "1.9.4", "source_build": "210", "qa_origin": qa.recipe.QA_URL,
                       "qa_key_sha256": qa.recipe.QA_KEY_SHA256, "internal_qa_only": True, "distribution_held": True,
                       "apple_delivery_held": True, "automatic_activation": False, "production_activation_approved": False,
                       "public_beta_must_remain_on": True, "deploy_to_production_must_remain_off": True,
                       "production_resources_must_remain_unchanged": True}
        self.policy_path = self.root / "policy.json"; self.policy_path.write_text(json.dumps(self.policy))
        catalog = self.source / "docs/coordinated-staging-qa-catalog.json"; catalog.parent.mkdir(parents=True)
        catalog.write_bytes((Path(__file__).resolve().parents[1] / "docs/coordinated-staging-qa-catalog.json").read_bytes())

    def compiler(self, flags=None):
        flags = qa.REQUIRED_FLAGS if flags is None else flags
        tokens = ["builtin-SwiftDriver", "--", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
                  "-module-name", "iChart", "-O", "-target", "arm64-apple-ios17.0", "-output-file-map", str(self.map),
                  *[str(self.source / p) for p in qa.REQUIRED_SOURCES], *[part for f in sorted(flags) for part in ("-D", f)]]
        return shlex.join(tokens)

    def info(self, **changes):
        value = {"CFBundleIdentifier": "com.ichart.app", "CFBundleExecutable": "iChart", "CFBundleShortVersionString": "1.9.4",
                 "CFBundleVersion": "209", "SupabaseURL": qa.recipe.QA_URL, "SupabasePublishableKey": KEY,
                 "SupabaseAnonKey": "", "UIDeviceFamily": [2], "CFBundleSupportedPlatforms": ["iPhoneOS"],
                 "ITSAppUsesNonExemptEncryption": False, "TFInternalTestingOnly": True}
        return dict(value, **changes)

    def options(self, **changes):
        value = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual", "signingCertificate": "Apple Distribution",
                 "teamID": "N6G8X4K46U", "provisioningProfiles": {"com.ichart.app": "iChart App Store"},
                 "manageAppVersionAndBuildNumber": False, "testFlightInternalTestingOnly": True}
        return dict(value, **changes)

    def testExactlyThreeNativeQAConditionsAreRequired(self):
        self.assertTrue(qa.compiler_evidence(self.compiler(), self.derived, self.source, self.inputs))
        for flag in qa.REQUIRED_FLAGS:
            with self.subTest(missing=flag), self.assertRaises(qa.GuardError):
                qa.compiler_evidence(self.compiler(qa.REQUIRED_FLAGS - {flag}), self.derived, self.source, self.inputs)
        for flag in ("DEBUG", "ICHART_LOCAL_PLAN_QA", "ICHART_LOCAL_QA_PLAN_PREVIEW", "ICHART_PRODUCTION_PAID_VALIDATION", "UNKNOWN_FEATURE"):
            with self.subTest(extra=flag), self.assertRaises(qa.GuardError):
                qa.compiler_evidence(self.compiler(qa.REQUIRED_FLAGS | {flag}), self.derived, self.source, self.inputs)

    def testFakeSimulatorDebugOrRequirementsOnlyCompilerProofIsRejected(self):
        for original, bad in (("builtin-SwiftDriver", "echo"), ("builtin-SwiftDriver", "builtin-Swift-Compilation-Requirements"),
                              ("arm64-apple-ios17.0", "arm64-apple-ios17.0-simulator"), ("-O", "-Onone")):
            with self.subTest(change=bad), self.assertRaises(qa.GuardError):
                qa.compiler_evidence(self.compiler().replace(original, bad), self.derived, self.source, self.inputs)

    def testIgnoredAndWrongSourceMapInputsCannotEnterQAArchive(self):
        extra = self.source / "Ignored.swift"; extra.write_text("// absent from pin")
        mapping = json.loads(self.map.read_text()); mapping[str(extra)] = {}; self.map.write_text(json.dumps(mapping))
        with self.assertRaises(ValueError):
            qa.compiler_evidence(self.compiler() + " " + str(extra), self.derived, self.source, self.inputs)

    def testOnlyExactQAOriginKey209AndInternalOnlyInfoCanPass(self):
        receipt = qa.validate_info(self.info(), "1.9.4", "209")
        self.assertTrue(receipt["actual_internal_only"])
        self.assertNotIn(KEY, json.dumps(receipt))
        for change in ({"SupabaseURL": "https://pausvvwoazbvmzyrebwl.supabase.co"}, {"SupabaseURL": "https://gfqpbikqvdgtjjgxrkgo.supabase.co"},
                       {"SupabaseURL": qa.recipe.QA_URL + "/"}, {"SupabasePublishableKey": "sb_publishable_wrong_project_0123456789"},
                       {"SupabasePublishableKey": "_".join(('sb', 'secret', 'not_a_client_0123456789'))}, {"SupabaseAnonKey": "legacy"},
                       {"CFBundleVersion": "207"}, {"CFBundleVersion": "208"}, {"CFBundleVersion": "210"},
                       {"TFInternalTestingOnly": False}, {"TFInternalTestingOnly": 1}, {"UIDeviceFamily": [1, 2]}):
            with self.subTest(change=change), self.assertRaises(qa.GuardError): qa.validate_info(self.info(**change), "1.9.4", "209")

    def testInternalOnlyManualExportCannotUploadOrRenumber(self):
        self.assertTrue(qa.validate_export_options(self.options())["internal_only"])
        for change in ({"testFlightInternalTestingOnly": False}, {"destination": "upload"}, {"manageAppVersionAndBuildNumber": True},
                       {"signingStyle": "automatic"}, {"teamID": "OTHER"}, {"provisioningProfiles": {"com.ichart.app": "Development"}}):
            with self.subTest(change=change), self.assertRaises(qa.GuardError): qa.validate_export_options(self.options(**change))

    def testTypedSourceBoundHoldCannotAuthorizeProductionOrDelivery(self):
        self.assertEqual(qa.release_policy(self.policy_path, self.snapshot), self.policy)
        for key, value in (("apple_delivery_held", False), ("production_activation_approved", True), ("distribution_held", False),
                           ("automatic_activation", True), ("internal_qa_only", False), ("source_build", "208"), ("source_build", "209"),
                           ("qa_origin", "https://gfqpbikqvdgtjjgxrkgo.supabase.co"), ("schema", True), ("source_head", "c" * 40)):
            self.policy_path.write_text(json.dumps(dict(self.policy, **{key: value})))
            with self.subTest(key=key), self.assertRaises(qa.GuardError): qa.release_policy(self.policy_path, self.snapshot)
        self.policy_path.write_text(json.dumps(dict(self.policy, deadline_activates=True)))
        with self.assertRaises(qa.GuardError): qa.release_policy(self.policy_path, self.snapshot)

    def testNormalSourceIdentityMustStay210AndQAOverrideIs209(self):
        with patch.object(qa.base, "snapshot_source", return_value=dict(self.snapshot)), patch.object(qa, "source_contracts", return_value={}), patch.object(qa.native, "source_manifest", return_value=self.inputs):
            for release in ({"version": "1.9.4", "build": "207"}, {"version": "1.9.4", "build": "208"},
                            {"version": "1.9.4", "build": "209"}, {"version": "1.9.4", "build": "211"},
                            {"version": "2.0.0", "build": "210"}):
                with patch.object(qa, "project_identity", return_value=release), self.assertRaises(qa.GuardError): qa.snapshot_source(self.source)
            with patch.object(qa, "project_identity", return_value={"version": "1.9.4", "build": "210"}):
                self.assertEqual(qa.snapshot_source(self.source)["release"], {"version": "1.9.4", "build": "209"})

    def testActualSourceCatalogAndNamespacesMatchReviewedQAContract(self):
        root = Path(__file__).resolve().parents[1]
        reviewed_key_hash = json.loads((root / "docs/coordinated-staging-qa-catalog.json").read_text())["publishable_key_sha256"]
        with patch.object(qa.recipe, "QA_KEY_SHA256", reviewed_key_hash):
            contract = qa.source_contracts(root)
        self.assertEqual(contract["qa_namespace"], qa.recipe.QA_NAMESPACE)
        self.assertEqual(contract["storeKitProducts"], qa.recipe.QA_PRODUCTS)
        self.assertEqual(contract["normal_default_policy"], "freeAllFeatures")

    def testQAContractsRejectForeignOriginNamespaceProductsAndTargetPrice(self):
        root = Path(__file__).resolve().parents[1]
        for name in ("iChart/Models/IChartStoreKitProductCatalog.swift", "iChart/Persistence/IChartStorageNamespace.swift"):
            (self.source / name).write_bytes((root / name).read_bytes())
        path = self.source / "docs/coordinated-staging-qa-catalog.json"
        original = json.loads(path.read_text()); original["publishable_key_sha256"] = qa.recipe.QA_KEY_SHA256
        with patch.object(qa.base, "source_contracts", return_value={"policy": "freeAllFeatures", "namespace": "publicApp"}):
            path.write_text(json.dumps(original)); self.assertTrue(qa.source_contracts(self.source))
            for key, changed in (("qa_origin", "https://pausvvwoazbvmzyrebwl.supabase.co"), ("qa_origin", "https://gfqpbikqvdgtjjgxrkgo.supabase.co"),
                                 ("namespace", {"mode": "publicApp"}), ("staging_product_ids", {"monthly": "com.ichart.app.pro.monthly"}),
                                 ("requested_prices", {"annual": {"minor_units": 5999}})):
                path.write_text(json.dumps(dict(original, **{key: changed})))
                with self.subTest(field=key), self.assertRaises(qa.GuardError): qa.source_contracts(self.source)

    def testStrictProductionAndPublicVerifierBytesAreUnchanged(self):
        root = Path(__file__).resolve().parent
        self.assertEqual(qa.sha((root / "verify_public_beta_archive.py").read_bytes()), "973a42bf7bfe965a9d9a0e4cfdc39b5695422336d49a1b6c4096a1ec12758ff8")
        self.assertEqual(qa.sha((root / "verify-production-paid-distribution.py").read_bytes()), "6fba9ed713dc6849a94bae4481afb7de208b1f16e228e3c4895325f6c14f6177")
        public = qa.base
        with self.assertRaises(public.GuardError): public.compiler_evidence(self.compiler(), self.derived, self.source)

    def testCopiedNeutralGuardFunctionsRemainIdenticalToProduction(self):
        root = Path(__file__).resolve().parent
        def bodies(path):
            return {n.name: ast.dump(n, include_attributes=False) for n in ast.parse(path.read_text()).body if isinstance(n, ast.FunctionDef)}
        original = bodies(root / "verify-production-paid-distribution.py"); actual = bodies(root / "verify-coordinated-staging-qa-distribution.py")
        for name in ("project_identity", "checked_json", "checked_pin_bytes", "checked_policy_bytes", "checked_runtime_bytes", "build_metadata", "archive_source_bindings_match"):
            with self.subTest(function=name): self.assertEqual(actual[name], original[name])

    def testStrictSigningWrapperRetainsProfileDERUUIDAndIsolatedCatalogChecks(self):
        app = self.root / "iChart.app"; app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps(self.info()))
        (app / "embedded.mobileprovision").write_bytes(b"synthetic profile fixture")
        (app / "iChart").write_bytes(b"synthetic binary " + b" ".join(p.encode() for p in qa.PRODUCTS.values()))
        profile = {"Name": "iChart App Store", "TeamIdentifier": [qa.base.TEAM], "UUID": "SYNTHETIC-PROFILE",
                   "ExpirationDate": datetime.datetime(2030, 1, 1), "Entitlements": qa.base.ACTIVE_ENTITLEMENTS}
        def command(*args):
            if args[0] == "/usr/bin/security": return argparse.Namespace(stdout=plistlib.dumps(profile), stderr=b"")
            return argparse.Namespace(stdout=b"", stderr=("Authority=Apple Distribution: Synthetic\nTeamIdentifier=" + qa.base.TEAM + "\n").encode())
        with patch.object(qa.base, "run", side_effect=command), patch.object(qa.base, "active_entitlements", return_value=qa.base.ACTIVE_ENTITLEMENTS), patch.object(qa.base, "uuid", return_value="SYNTHETIC-UUID"):
            self.assertTrue(qa.verify_app(app, "1.9.4", "209")["strict_signature"])
            profile["ProvisionedDevices"] = ["SYNTHETIC-DEVICE"]
            with self.assertRaises(qa.GuardError): qa.verify_app(app, "1.9.4", "209")
            profile.pop("ProvisionedDevices")
            (app / "iChart").write_bytes((app / "iChart").read_bytes() + b" com.ichart.app.pro.monthly")
            with self.assertRaises(qa.GuardError): qa.verify_app(app, "1.9.4", "209")

    def runtime_fixture(self):
        root = self.root / "native"; root.mkdir(); project = root / "iChart.xcodeproj"
        source_paths = ("iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", "scripts/run_coordinated_staging_qa_validation.py",
                        "scripts/test_coordinated_staging_qa_validation.py", "scripts/prepare_coordinated_staging_qa_project.py")
        outputs = [project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved", root / "qa-validation-project.json", project / "project.pbxproj", root / "iChart-Info.plist"]
        proof = {}
        for path in [self.source / p for p in source_paths] + outputs:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_text("synthetic pinned proof"); proof[str(path)] = qa.sha(path.read_bytes())
        derived = root / "DerivedData"; derived.mkdir(); lines = []
        for module, names in (("iChart", qa.native.REQUIRED_RUNTIME_APP_SOURCES), ("iChartTests", qa.native.selected_sources())):
            paths = [str(self.source / p) for p in names]
            for name in paths:
                p = Path(name); p.parent.mkdir(parents=True, exist_ok=True)
                if not p.exists(): p.write_text("// synthetic frozen source")
            mapping = derived / (module + ".json"); mapping.write_text(json.dumps({p: {} for p in paths}))
            lines.append("builtin-SwiftDriver -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name " + module + " -target arm64-apple-ios17.0-simulator -O -output-file-map " + str(mapping) + " " + " ".join(paths) + " " + " ".join("-D " + f for f in qa.native.expected_defines(module)))
        log = root / "xcodebuild.log"; log.write_text("\n".join(lines))
        bundle = root / "qa-validation.xcresult"; bundle.mkdir(); (bundle / "Data").write_text("synthetic result")
        identifiers = [c + "/testFixture" for c in qa.native.selected_classes() if c not in qa.native.COORDINATED_TEST_CLASSES] + list(qa.native.REQUIRED_COORDINATED_TESTS)
        device = "12345678-1234-1234-1234-123456789ABC"
        summary = {"result": "Passed", "startTime": 1795737660, "finishTime": 1795737720, "passedTests": len(identifiers), "failedTests": 0, "skippedTests": 0,
                   "devicesAndConfigurations": [{"passedTests": len(identifiers), "device": {"deviceId": device}}]}
        tree = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"} for name in identifiers]}
        self.snapshot["runtime_inputs"] = {str(p.relative_to(self.source)): qa.sha(p.read_bytes()) for p in self.source.rglob("*") if p.is_file()}
        value = {"schema": 2, "lane": "coordinated-staging-qa", "runID": "12345678-1234-1234-1234-123456789abc", "startedAtUTC": "2026-11-27T00:00:00+00:00", "completedAtUTC": "2026-11-27T00:10:00+00:00",
                 "nativeValidationPassed": True, "preparedOnly": False, "xcodebuildExitCode": 0, "source": str(self.source), "sourceHead": self.snapshot["head"], "sourceTree": self.snapshot["tree"],
                 "sourceInputs": self.snapshot["runtime_inputs"], "project": str(project), "destination": "platform=iOS Simulator,id=" + device,
                 "testClasses": list(qa.native.selected_classes()), "testSources": list(qa.native.selected_sources()), "requiredCoordinatedTests": list(qa.native.REQUIRED_COORDINATED_TESTS),
                 "qaInputs": {"origin": qa.recipe.QA_URL, "keySHA256": qa.recipe.QA_KEY_SHA256, "namespace": qa.recipe.QA_NAMESPACE, "artifactRelease": self.snapshot["release"]},
                 "proofFileHashes": proof, "targetConditions": {m: " ".join(qa.native.expected_defines(m)) for m in ("iChart", "iChartTests")}, "otherSwiftFlags": {},
                 "actualCompilerCommands": qa.native.validate_compiler_commands(log.read_text(), derived, source=self.source, source_inputs=self.snapshot["runtime_inputs"]), "buildLogSHA256": qa.sha(log.read_bytes()),
                 "resultBundleFiles": qa.native.result_bundle_hashes(bundle), "summary": summary, "testTree": tree, "classExecutedCounts": dict(Counter(x.split("/")[0] for x in identifiers))}
        path = root / "validation-receipt.json"; path.write_text(json.dumps(value))
        return path, value, summary, tree

    def runtime_context(self, summary, tree):
        def tool(*args): return argparse.Namespace(stdout=json.dumps(summary if args[4] == "summary" else tree).encode())
        return patch.multiple(qa.native, source_manifest=lambda source: self.snapshot["runtime_inputs"]), patch.object(qa.base, "run", side_effect=tool)

    def testQARuntimeEvidencePinsOwnProducersAndActual99MethodResults(self):
        path, value, summary, tree = self.runtime_fixture(); a, b = self.runtime_context(summary, tree)
        with a, b:
            proof = qa.runtime_evidence(path, self.source, self.snapshot, "coordinated-staging-qa")
        self.assertEqual(len(proof["required_coordinated_tests"]), 99)
        self.assertFalse(proof["hosted_backend_deployed"])

    def testProductionHistoricalPreparedOrForeignReceiptsCannotCertifyQA(self):
        path, value, summary, tree = self.runtime_fixture(); a, b = self.runtime_context(summary, tree)
        with a, b:
            for key, change in (("lane", "production-paid"), ("lane", "internal-staging"), ("preparedOnly", True), ("sourceHead", "e" * 40),
                                ("qaInputs", {}), ("proofFileHashes", {}), ("requiredCoordinatedTests", [])):
                path.write_text(json.dumps(dict(value, **{key: change})))
                with self.subTest(field=key, value=change), self.assertRaises((qa.GuardError, ValueError)):
                    qa.runtime_evidence(path, self.source, self.snapshot, "coordinated-staging-qa")

    def testRuntimeResultMutationAndMissingActualHostMethodFailClosed(self):
        path, value, summary, tree = self.runtime_fixture()
        missing = copy.deepcopy(tree); missing["testNodes"][-1]["nodeIdentifier"] = "IChartStoreKitProductCatalogTests/testUnreviewed()"
        a, b = self.runtime_context(summary, missing)
        with a, b, self.assertRaises(ValueError): qa.runtime_evidence(path, self.source, self.snapshot, "coordinated-staging-qa")
        (path.parent / "qa-validation.xcresult/Data").write_text("changed")
        a, b = self.runtime_context(summary, tree)
        with a, b, self.assertRaises(qa.GuardError): qa.runtime_evidence(path, self.source, self.snapshot, "coordinated-staging-qa")

    def project_fixture(self):
        root = self.root / "recipe"; root.mkdir()
        original = {"settings": {"base": {"MARKETING_VERSION": "1.9.4", "CURRENT_PROJECT_VERSION": "210"}},
                    "targets": {"iChart": {"sources": [{"path": "iChart"}], "info": {"path": "iChart/App/Info.plist", "properties": {}},
                                           "dependencies": [{"package": "Supabase"}]}}, "packages": {"Supabase": {"exactVersion": "synthetic"}}}
        spec = qa.recipe.make_archive_spec(original, root, KEY)
        spec_path = root / "coordinated-qa-archive-project.json"; spec_path.write_text(json.dumps(spec))
        info = root / "iChart-Info.plist"; info.write_bytes(plistlib.dumps(spec["targets"]["iChart"]["info"]["properties"]))
        project = self.source / "iChart.xcodeproj/project.pbxproj"; project.parent.mkdir(exist_ok=True); project.write_text("synthetic generated project")
        value = {"schema": 1, "preparedOnly": True, "buildExecuted": False, "deliveryReady": False,
                 "sourceHead": self.snapshot["head"], "sourceTree": self.snapshot["tree"], "sourceInputs": self.snapshot["runtime_inputs"],
                 "qaOrigin": qa.recipe.QA_URL, "qaKeySHA256": qa.recipe.QA_KEY_SHA256, "artifactRelease": self.snapshot["release"],
                 "appConditions": sorted(qa.REQUIRED_FLAGS), "specPath": str(spec_path), "infoPath": str(info),
                 "specSHA256": qa.sha(spec_path.read_bytes()), "infoSHA256": qa.sha(info.read_bytes()), "projectSHA256": qa.sha(project.read_bytes())}
        path = root / "qa-project-receipt.json"; path.write_text(json.dumps(value))
        return path, value, original, spec

    def testPreparedProjectMustMatchAuthoritativeAppOnlyTransformation(self):
        path, value, original, spec = self.project_fixture()
        with patch.object(qa.native, "run", return_value=json.dumps(original)):
            self.assertEqual(qa.qa_project_evidence(path, self.source, self.snapshot)["receipt_sha256"], qa.sha(path.read_bytes()))
            # Re-signing a receipt's hashes cannot authorize a different spec.
            spec["settings"]["base"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = qa.recipe.QA_FLAG
            spec_path = Path(value["specPath"]); spec_path.write_text(json.dumps(spec))
            value["specSHA256"] = qa.sha(spec_path.read_bytes()); path.write_text(json.dumps(value))
            with self.assertRaisesRegex(qa.GuardError, "app-only transformation"):
                qa.qa_project_evidence(path, self.source, self.snapshot)

    def testPreparedProjectCannotUseForeignOrUnboundReceipt(self):
        path, value, original, spec = self.project_fixture()
        for key, change in (("preparedOnly", False), ("sourceHead", "d" * 40), ("qaOrigin", "https://pausvvwoazbvmzyrebwl.supabase.co"),
                           ("appConditions", sorted(qa.REQUIRED_FLAGS - {qa.recipe.QA_FLAG})), ("projectSHA256", "f" * 64)):
            path.write_text(json.dumps(dict(value, **{key: change})))
            with self.subTest(field=key), self.assertRaises(qa.GuardError): qa.qa_project_evidence(path, self.source, self.snapshot)

    def testPreparedSpecMutationDuringReconstructionFailsClosed(self):
        path, value, original, spec = self.project_fixture()
        def mutate(*args, **kwargs):
            target = Path(value["specPath"]); target.write_bytes(target.read_bytes() + b" ")
            return json.dumps(original)
        with patch.object(qa.native, "run", side_effect=mutate), self.assertRaisesRegex(qa.GuardError, "changed during"):
            qa.qa_project_evidence(path, self.source, self.snapshot)

    def verify_fixture(self):
        archive = self.root / "archive.xcarchive"; app = archive / "Products/Applications/iChart.app"; app.mkdir(parents=True)
        dsym = archive / "dSYMs/iChart.app.dSYM/Contents/Resources/DWARF/iChart"; dsym.parent.mkdir(parents=True); dsym.write_bytes(b"synthetic dsym")
        ipa = self.root / "iChart.ipa"; ipa.write_bytes(b"synthetic orchestration fixture")
        log = self.root / "archive.log"; log.write_text("synthetic compiler log")
        options = self.root / "ExportOptions.plist"; options.write_bytes(plistlib.dumps(self.options()))
        pin = self.root / "pin.json"; pin.write_text(json.dumps({"schema": 1, "package_mode": "coordinated_staging_qa_held", "source": str(self.source),
            "snapshot": self.snapshot, "release_policy_sha256": qa.sha(self.policy_path.read_bytes()), "pinned_at_utc": "2026-11-27T00:00:00+00:00",
            "qa_native_runtime": {"syntheticRuntime": True}, "qa_project": {"syntheticProject": True}}))
        return argparse.Namespace(source=self.source, ipa=ipa, build_log=log, export_options=options, archive=archive, derived_data=self.derived,
             source_pin=pin, release_policy=self.policy_path, runtime_receipt=self.root / "native.json", qa_project_receipt=self.root / "project.json"), app

    def testQAArtifactOrchestrationNeverCertifiesProductionOrClearsHolds(self):
        args, app = self.verify_fixture(); closure = {"sourceInputHashes": {"example.swift": "a" * 64}, "generatedInputHashes": {}}
        signed = {"uuid": "SYNTHETIC", "files": {"iChart": "hash"}}
        with patch.object(qa, "snapshot_source", return_value=self.snapshot), patch.object(qa, "runtime_evidence", return_value={"syntheticRuntime": True}), patch.object(qa, "qa_project_evidence", return_value={"syntheticProject": True}), patch.object(qa, "compiler_evidence", return_value=[{"output_file_map": closure}]), patch.object(qa, "build_metadata", return_value=[{"app_command_sha256": [{"swift_inputs": closure}]}]), patch.object(qa, "verify_app", return_value=signed) as signatures, patch.object(qa.base, "uuid", return_value="SYNTHETIC"), patch.object(qa.base, "unpack_ipa", return_value=(app, set())), patch.object(qa.base, "compare_export", return_value=[]):
            receipt = qa.verify(args)
        self.assertEqual(signatures.call_count, 3)
        self.assertTrue(receipt["artifact_verified"])
        self.assertTrue(receipt["coordinated_qa_native_verified"])
        for key in ("delivery_ready", "production_activation_approved", "production_artifact_verified", "production_native_verified", "apple_prices_verified", "live_backend_verified_by_packager"):
            self.assertIs(receipt[key], False)
        self.assertIs(receipt["apple_delivery_held"], True)
        self.assertNotIn("passed", receipt)

    def testPolicyMutationDuringArtifactVerificationCannotBeReceipted(self):
        args, app = self.verify_fixture(); closure = {"sourceInputHashes": {"example.swift": "a" * 64}, "generatedInputHashes": {}}
        signed = {"uuid": "SYNTHETIC", "files": {"iChart": "hash"}}
        def mutate(*unused):
            self.policy_path.write_text(json.dumps(dict(self.policy, apple_delivery_held=False)))
            return []
        with patch.object(qa, "snapshot_source", return_value=self.snapshot), patch.object(qa, "runtime_evidence", return_value={"syntheticRuntime": True}), patch.object(qa, "qa_project_evidence", return_value={"syntheticProject": True}), patch.object(qa, "compiler_evidence", return_value=[{"output_file_map": closure}]), patch.object(qa, "build_metadata", return_value=[{"app_command_sha256": [{"swift_inputs": closure}]}]), patch.object(qa, "verify_app", return_value=signed), patch.object(qa.base, "uuid", return_value="SYNTHETIC"), patch.object(qa.base, "unpack_ipa", return_value=(app, set())), patch.object(qa.base, "compare_export", side_effect=mutate):
            with self.assertRaisesRegex(qa.GuardError, "policy changed"):
                qa.verify(args)


if __name__ == "__main__": unittest.main()
