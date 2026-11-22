"""Pure local regression checks for the public-beta packaging guards."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("verify_public_beta_archive.py")
SPEC = importlib.util.spec_from_file_location("public_beta_packaging", MODULE_PATH)
packaging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packaging)


class PublicBetaPackagingTests(unittest.TestCase):
    synthetic_key = "sb_publishable_invented_public_fixture_0123456789"
    swiftc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ichart-public-packaging-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.derived = self.root / "DerivedData"
        self.objects = self.derived / "Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64"
        self.objects.mkdir(parents=True)
        self.sources = [self.source / name for name in packaging.REQUIRED_SOURCES]
        for source in self.sources:
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("// Original synthetic compiler-path fixture; never compiled.\n")
        self.file_list = self.objects / "iChart.SwiftFileList"
        self.file_list.write_text("\n".join(shlex.quote(str(p)) for p in self.sources) + "\n")
        self.output_map = self.objects / "iChart-OutputFileMap.json"
        self.mapping = {str(p): {"object": str(self.objects / (p.stem + ".o"))} for p in self.sources}
        self.output_map.write_text(json.dumps(self.mapping))
        key_hash = hashlib.sha256(self.synthetic_key.encode()).hexdigest()
        self.key_patch = patch.object(packaging, "PRODUCTION_KEY_SHA256", key_hash)
        self.key_patch.start()
        self.addCleanup(self.key_patch.stop)

    def info(self, **changes):
        value = {
            "CFBundleIdentifier": "com.ichart.app",
            "CFBundleExecutable": "iChart",
            "CFBundleShortVersionString": "1.9.4",
            "CFBundleVersion": "174",
            "SupabaseURL": "https://pausvvwoazbvmzyrebwl.supabase.co",
            "SupabasePublishableKey": self.synthetic_key,
            "SupabaseAnonKey": "",
            "UIDeviceFamily": [2],
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "ITSAppUsesNonExemptEncryption": False,
        }
        value.update(changes)
        return value

    def export_options(self):
        return {
            "method": "app-store-connect", "destination": "export",
            "signingStyle": "manual", "signingCertificate": "Apple Distribution",
            "teamID": "N6G8X4K46U",
            "provisioningProfiles": {"com.ichart.app": "iChart App Store"},
            "manageAppVersionAndBuildNumber": False,
            "testFlightInternalTestingOnly": False,
            "stripSwiftSymbols": True, "uploadSymbols": True,
        }

    def compiler_tokens(self, wrapper="builtin-SwiftDriver"):
        # Redacted Xcode 27 archive argv format: paths are synthetic and paid/
        # staging definitions are absent for this public-beta fixture.
        command = [self.swiftc, "-module-name", "iChart", "-O", "@" + str(self.file_list),
                   "-enable-bare-slash-regex", "-enable-experimental-feature", "DebugDescriptionMacro",
                   "-sdk", "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.2.sdk",
                   "-target", "arm64-apple-ios17.0", "-g", "-swift-version", "5",
                   "-I", str(self.derived / "Build/Intermediates.noindex/ArchiveIntermediates/iChart/BuildProductsPath/Release-iphoneos"),
                   "-c", "-j10", "-enable-batch-mode", "-incremental",
                   "-Xfrontend", "-serialize-debugging-options",
                   "-output-file-map", str(self.output_map), "-emit-dependencies",
                   "-emit-module", "-emit-module-path", str(self.objects / "iChart.swiftmodule"),
                   "-working-directory", str(self.source), "-experimental-emit-module-separately", "-disable-cmo"]
        return ([wrapper, "--"] if wrapper else []) + command

    def evidence(self, tokens=None, source=True):
        line = shlex.join(tokens if tokens is not None else self.compiler_tokens())
        return packaging.compiler_evidence(line + "\n", self.derived, self.source if source else None)

    def test_valid_info_uses_pinned_hash_without_exposing_client_key(self):
        result = packaging.validate_info(self.info())
        self.assertEqual(result["publishable_key_sha256"], hashlib.sha256(self.synthetic_key.encode()).hexdigest())
        self.assertEqual(result["host"], packaging.PRODUCTION_URL)
        self.assertNotIn(self.synthetic_key, json.dumps(result))
        self.assertEqual(packaging.validate_info(self.info(TFInternalTestingOnly=False))["build"], "174")

    def test_info_rejects_wrong_backend_key_and_legacy_fallback(self):
        changes = [
            {"SupabaseURL": "https://gfqpbikqvdgtjjgxrkgo.supabase.co"},
            {"SupabaseURL": packaging.PRODUCTION_URL + "/"},
            {"SupabaseURL": ""}, {"SupabasePublishableKey": ""},
            {"SupabasePublishableKey": "sb_publishable_different_invented_key_123456789"},
            {"SupabasePublishableKey": "sb_" + "secret_" + "invented_fixture_only_" + ("x" * 24)},
            {"SupabasePublishableKey": "eyJhbGciOiJIUzI1NiJ9.invented.fixture"},
            {"SupabaseAnonKey": "legacy-fixture"},
        ]
        for change in changes:
            with self.subTest(fields=list(change)), self.assertRaises(packaging.GuardError) as caught:
                packaging.validate_info(self.info(**change))
            self.assertNotIn(self.synthetic_key, str(caught.exception))

    def test_info_rejects_wrong_identity_platform_family_and_boolean_types(self):
        for change in [
            {"CFBundleIdentifier": "com.ichart.test"}, {"CFBundleExecutable": "Other"},
            {"CFBundleVersion": "173"}, {"CFBundleVersion": 174},
            {"CFBundleShortVersionString": "1.9.3"},
            {"CFBundleSupportedPlatforms": ["iPhoneSimulator"]},
            {"UIDeviceFamily": [1, 2]}, {"UIDeviceFamily": (2,)},
            {"ITSAppUsesNonExemptEncryption": True}, {"ITSAppUsesNonExemptEncryption": 0},
            {"TFInternalTestingOnly": True}, {"TFInternalTestingOnly": "false"},
        ]:
            with self.subTest(change=change), self.assertRaises(packaging.GuardError):
                packaging.validate_info(self.info(**change))

    def test_public_export_disables_the_internal_only_restriction(self):
        result = packaging.validate_export_options(self.export_options())
        self.assertIs(result["internal_only"], False)
        self.assertEqual(result["method"], "app-store-connect")

    def test_export_rejects_missing_internal_flag_wrong_route_and_signing(self):
        for key, value in [
            ("testFlightInternalTestingOnly", True), ("testFlightInternalTestingOnly", 0),
            ("method", "development"), ("destination", "upload"), ("teamID", "OTHERTEAM"),
            ("signingStyle", "automatic"), ("signingCertificate", "Apple Development"),
            ("provisioningProfiles", {"com.ichart.app": "iChart Development"}),
            ("manageAppVersionAndBuildNumber", True),
        ]:
            options = self.export_options()
            options[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(packaging.GuardError):
                packaging.validate_export_options(options)
        options = self.export_options()
        del options["testFlightInternalTestingOnly"]
        with self.assertRaises(packaging.GuardError):
            packaging.validate_export_options(options)

    def test_real_xcode27_wrappers_and_direct_driver_bind_required_source_map(self):
        wrappers = ["builtin-SwiftDriver", "builtin-Swift-Compilation-Requirements", "builtin-Swift-Compilation"]
        log = "\n".join("    " + shlex.join(self.compiler_tokens(w)) for w in wrappers)
        result = packaging.compiler_evidence(log, self.derived, self.source)
        self.assertEqual([item["wrapper"] for item in result], wrappers)
        self.assertEqual(len({item["output_file_map"]["sha256"] for item in result}), 1)
        self.assertEqual(self.evidence(self.compiler_tokens(None))[0]["wrapper"], "direct-swiftc")
        self.assertEqual(result[0]["conditions"], [])

    def test_compiler_rejects_echo_fake_malformed_and_requirements_only(self):
        real = self.compiler_tokens()
        missing_separator = real[:1] + real[2:]
        fake_wrapper = ["builtin-Fake-SwiftDriver"] + real[1:]
        fake_executable = list(real)
        fake_executable[2] = "/private/tmp/fake/swiftc"
        for tokens in [["echo"] + real, ["printf"] + real, missing_separator, fake_wrapper,
                       fake_executable, self.compiler_tokens("builtin-Swift-Compilation-Requirements")]:
            with self.subTest(prefix=tokens[:3]), self.assertRaises(packaging.GuardError):
                self.evidence(tokens)
        with self.assertRaises(packaging.GuardError):
            packaging.compiler_evidence("SWIFT_ACTIVE_COMPILATION_CONDITIONS = PUBLIC\n", self.derived)

    def test_compiler_rejects_wrong_module_nonphysical_target_and_debug_optimization(self):
        for flag, value in [("-module-name", "iChartTests"), ("-target", "arm64-apple-ios17.0-simulator"),
                            ("-target", "x86_64-apple-ios17.0"), ("-target", "arm64-apple-ios17.0-macabi"),
                            ("-O", "-Onone")]:
            tokens = self.compiler_tokens()
            index = tokens.index(flag)
            tokens[index if flag == "-O" else index + 1] = value
            with self.subTest(flag=flag, value=value), self.assertRaises(packaging.GuardError):
                self.evidence(tokens)

    def test_every_paid_staging_debug_and_preview_define_is_rejected(self):
        for condition in sorted(packaging.FORBIDDEN_FLAGS):
            for extra in [["-D", condition], ["-D" + condition]]:
                with self.subTest(condition=condition, syntax=extra), self.assertRaises(packaging.GuardError):
                    self.evidence(self.compiler_tokens() + extra)

    def test_forwarded_frontend_defines_cannot_hide_forbidden_flags(self):
        for condition in sorted(packaging.FORBIDDEN_FLAGS):
            for extra in [["-Xfrontend", "-D" + condition],
                          ["-Xfrontend", "-D", "-Xfrontend", condition]]:
                with self.subTest(condition=condition, syntax=extra), self.assertRaises(packaging.GuardError):
                    self.evidence(self.compiler_tokens() + extra)
        # A C compiler definition does not masquerade as a Swift condition.
        self.assertEqual(self.evidence(self.compiler_tokens() + ["-Xcc", "-DDEBUG"])[0]["conditions"], [])

    def test_response_files_expand_and_hidden_conditions_escape_or_depth_fail(self):
        nested = self.derived / "nested.resp"
        outer = self.derived / "outer.resp"
        nested.write_text("-D PUBLIC_BETA_FIXTURE")
        outer.write_text(shlex.quote("@" + str(nested)))
        result = self.evidence(self.compiler_tokens() + ["@" + str(outer)])
        self.assertEqual(result[0]["conditions"], ["PUBLIC_BETA_FIXTURE"])
        nested.write_text("-D ICHART_STAGING_STOREKIT_PRODUCTS")
        with self.assertRaises(packaging.GuardError):
            self.evidence(self.compiler_tokens() + ["@" + str(outer)])
        external = self.root / "outside.resp"
        external.write_text("-D PUBLIC_BETA_FIXTURE")
        link = self.derived / "escape.resp"
        link.symlink_to(external)
        for path in [external, link]:
            with self.subTest(path=path.name), self.assertRaises(packaging.GuardError):
                self.evidence(self.compiler_tokens() + ["@" + str(path)])
        nested.write_text(shlex.quote("@" + str(outer)))
        with self.assertRaises(packaging.GuardError):
            self.evidence(self.compiler_tokens() + ["@" + str(outer)])

    def test_compiler_requires_all_current_sources_in_bounded_output_map(self):
        changed = copy.deepcopy(self.mapping)
        changed.pop(str(self.source / "iChart/Persistence/IChartStorageNamespace.swift"))
        self.output_map.write_text(json.dumps(changed))
        with self.assertRaises(packaging.GuardError):
            self.evidence()
        self.output_map.write_text(json.dumps(self.mapping))
        tokens = self.compiler_tokens()
        at = tokens.index("-output-file-map")
        outside = self.root / "outside-map.json"
        outside.write_text(json.dumps(self.mapping))
        tokens[at + 1] = str(outside)
        with self.assertRaises(packaging.GuardError):
            self.evidence(tokens)
        tokens = self.compiler_tokens()
        at = tokens.index("-output-file-map")
        del tokens[at:at + 2]
        with self.assertRaises(packaging.GuardError):
            self.evidence(tokens)

    def test_inventory_rejects_parked_models_private_research_and_qa_bundles(self):
        self.assertTrue(packaging.validate_inventory([
            "Info.plist", "iChart", "Bravura.otf", "PrivacyInfo.xcprivacy",
            "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy",
        ]))
        for name in ["PersonalMLComparison/model.bin", "PersonalVisualEncoderResearch/weights.bin",
                     "private-profile.json", "MyScript/engine", "NeuralInk/model.bin",
                     "RecognizerGraph/graph.bin", "weights.mlmodelc/data", "model.mlpackage/Manifest.json",
                     "model.onnx", "model.tflite", "PlugIns/Fixture.appex/Info.plist",
                     "Tests.xctest/Info.plist", "Nested/Fixture.appex/Info.plist",
                     "UIFixture/sample.json", "iChart.storekit"]:
            with self.subTest(name=name), self.assertRaises(packaging.GuardError):
                packaging.validate_inventory(["Info.plist", name])

    def test_source_contracts_preserve_public_defaults_and_reject_namespace_catalog_drift(self):
        actual = MODULE_PATH.parent.parent
        for name in packaging.REQUIRED_SOURCES:
            (self.source / name).write_bytes((actual / name).read_bytes())
        result = packaging.source_contracts(self.source)
        self.assertEqual(result["policy"], "freeAllFeatures")
        self.assertEqual(result["namespace"], "publicApp")
        changes = [
            (packaging.REQUIRED_SOURCES[0], "static let current: Self = .freeAllFeatures", "static let current: Self = .paidSubscription"),
            (packaging.REQUIRED_SOURCES[2], "case .publicApp:\n            return root", "case .publicApp:\n            return root.appendingPathComponent(\"wrong\")"),
            (packaging.REQUIRED_SOURCES[1], '"com.ichart.app.pro.annual"', '"com.ichart.app.staging.fixture.annual"'),
        ]
        for name, before, after in changes:
            path = self.source / name
            original = path.read_text()
            self.assertIn(before, original)
            path.write_text(original.replace(before, after))
            with self.subTest(source=name), self.assertRaises(packaging.GuardError):
                packaging.source_contracts(self.source)
            path.write_text(original)

    def test_archive_metadata_rejects_stale_debug_phony_or_escaped_app_commands(self):
        folder = self.derived / "Build/Intermediates.noindex/XCBuildData/synthetic.xcbuilddata"
        folder.mkdir(parents=True)
        request = {"containerPath": str(self.source / "iChart.xcodeproj"), "useDryRun": False,
                   "schemeCommand": "archive", "parameters": {"configurationName": "Release",
                   "action": "install", "activeRunDestination": {"platform": "iphoneos"}}}
        command = {"tool": "swift-driver-compilation",
                   "description": "SwiftDriver Compilation iChart normal arm64 com.apple.xcode.tools.swift.compiler",
                   "inputs": [str(p) for p in self.sources],
                   "outputs": [str(self.objects / "policy.o")]}
        name = "P0:target-iChart:Release:SwiftDriver Compilation iChart normal arm64 compiler"
        request_path = folder / "build-request.json"
        manifest_path = folder / "manifest.json"
        request_path.write_text(json.dumps(request))
        manifest_path.write_text(json.dumps({"commands": {name: command}}))
        self.assertEqual(len(packaging.build_metadata(self.source, self.derived, 0)), 1)
        for change in [{"tool": "phony"}, {"inputs": []},
                       {"description": "SwiftDriver Compilation iChartTests normal arm64 com.apple.xcode.tools.swift.compiler"},
                       {"outputs": [str(self.root / "outside.o")]}]:
            manifest_path.write_text(json.dumps({"commands": {name: dict(command, **change)}}))
            with self.subTest(change=change), self.assertRaises(packaging.GuardError):
                packaging.build_metadata(self.source, self.derived, 0)
        manifest_path.write_text(json.dumps({"commands": {name: command}}))
        bad = copy.deepcopy(request)
        bad["parameters"]["configurationName"] = "Debug"
        request_path.write_text(json.dumps(bad))
        with self.assertRaises(packaging.GuardError):
            packaging.build_metadata(self.source, self.derived, 0)
        request_path.write_text(json.dumps(request))
        with self.assertRaises(packaging.GuardError):
            packaging.build_metadata(self.source, self.derived, request_path.stat().st_mtime + 1)


if __name__ == "__main__":
    unittest.main()
