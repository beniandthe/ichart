import contextlib
import importlib.util
import io
import json
import os
import sys
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

# The existing CI entry point verifies both isolated packaging lanes.
from test_public_beta_packaging import PublicBetaPackagingTests
import zipfile

MODULE_PATH = Path(__file__).with_name("archive_internal_paid_staging.py")
SPEC = importlib.util.spec_from_file_location("internal_staging", MODULE_PATH)
packaging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packaging)


class InternalPaidStagingPackagingTests(unittest.TestCase):
    key = "sb_publishable_synthetic_client_key_0123456789"
    monthly = "com.ichart.app.staging.fix036.monthly"
    annual = "com.ichart.app.staging.fix036.annual"

    def info(self, **changes):
        result = {"CFBundleIdentifier": "com.ichart.app", "CFBundleShortVersionString": "2.0.0",
                  "CFBundleVersion": "999", "CFBundleExecutable": "iChart", "UIDeviceFamily": [2],
                  "SupabaseURL": packaging.STAGING_URL, "SupabasePublishableKey": self.key, "SupabaseAnonKey": ""}
        result.update(changes)
        return result

    def compiler(self, root, flags="-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS", target="arm64-apple-ios17.0"):
        log = root / "archive.log"
        log.write_text("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name iChart -O -target " + target + " " + flags + "\n")
        return log

    def test_key_reader_rejects_privileged_or_legacy_keys_without_echoing_value(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "key"
            for value in ("sb_secret_invented_secret_123456789", "service_role", "eyJhbGciOiJIUzI1NiJ9.invented.jwt", "sb_publishable_short"):
                path.write_text(value)
                with self.assertRaises(packaging.GuardError) as caught:
                    packaging.read_public_key(path)
                self.assertNotIn(value, str(caught.exception))
            path.write_text(self.key + "\n")
            self.assertEqual(packaging.read_public_key(path), self.key)

    def test_metadata_binds_native_release_archive_to_current_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, derived = root / "source", root / "DerivedData"
            bundle = derived / "Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/XCBuildData/fake.xcbuilddata"
            bundle.mkdir(parents=True)
            request = {"containerPath": str(source / "iChart.xcodeproj"), "schemeCommand": "archive", "useDryRun": False,
                       "parameters": {"configurationName": "Release", "action": "install",
                                      "activeRunDestination": {"platform": "iphoneos"}}}
            manifest = {"commands": {"P0:target-iChart:Release:SwiftDriver Compilation iChart normal arm64 compiler":
                                     {"tool": "swift-driver-compilation", "description": "SwiftDriver Compilation iChart normal arm64 com.apple.xcode.tools.swift.compiler", "inputs": [str(source / "iChart/Models/IChartProductAccessPolicy.swift"), str(source / "iChart/Models/IChartStoreKitProductCatalog.swift")], "outputs": [str(derived / "Release-iphoneos/iChart.build/object.o")]}}}
            request_path = bundle / "build-request.json"
            request_path.write_text(json.dumps(request))
            (bundle / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(len(packaging.build_metadata_evidence(source, derived)), 1)
            for field, value in (("configurationName", "Debug"), ("action", "build")):
                changed = json.loads(json.dumps(request))
                changed["parameters"][field] = value
                request_path.write_text(json.dumps(changed))
                with self.assertRaises(packaging.GuardError):
                    packaging.build_metadata_evidence(source, derived)
            request_path.write_text(json.dumps(dict(request, useDryRun=True)))
            with self.assertRaises(packaging.GuardError):
                packaging.build_metadata_evidence(source, derived)
            request_path.write_text(json.dumps(request))
            original = next(iter(manifest["commands"].values()))
            for changes in ({"tool": "phony"}, {"description": "SwiftDriver Compilation iChartTests normal arm64 com.apple.xcode.tools.swift.compiler"},
                            {"inputs": []}, {"outputs": []}, {"outputs": [str(derived / "../outside.o")]}):
                bad = {"commands": {next(iter(manifest["commands"])): dict(original, **changes)}}
                (bundle / "manifest.json").write_text(json.dumps(bad))
                with self.subTest(changes=changes), self.assertRaises(packaging.GuardError):
                    packaging.build_metadata_evidence(source, derived)
            (bundle / "manifest.json").write_text(json.dumps({"commands": {}}))
            with self.assertRaises(packaging.GuardError):
                packaging.build_metadata_evidence(source, derived)

    def test_exact_info_rejects_production_blank_key_or_legacy_fallback(self):
        for changes in ({"SupabaseURL": "https://pausvvwoazbvmzyrebwl.supabase.co"},
                        {"SupabaseURL": ""}, {"SupabasePublishableKey": ""},
                        {"SupabaseAnonKey": "legacy"}, {"CFBundleVersion": "172"},
                        {"UIDeviceFamily": [1, 2]}):
            with self.subTest(changes=changes), self.assertRaises(packaging.GuardError):
                packaging.check_info(self.info(**changes), "2.0.0", "999", self.key)
        result = packaging.check_info(self.info(), "2.0.0", "999", self.key)
        self.assertEqual(result["publishable_key_sha256"], packaging.sha(self.key.encode()))
        self.assertNotIn(self.key, json.dumps(result))

    def test_compiler_guard_requires_real_native_paid_invocation_and_excludes_preview(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for flags in ("", "-D ICHART_PAID_SUBSCRIPTION", "-Xcc -DICHART_PAID_SUBSCRIPTION -Xcc -DICHART_STAGING_STOREKIT_PRODUCTS", "-D DEBUG", "-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -D DEBUG",
                          "-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -Xfrontend -DDEBUG",
                          "-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -Xfrontend -D -Xfrontend DEBUG",
                          "-DICHART_PAID_SUBSCRIPTION -DICHART_STAGING_STOREKIT_PRODUCTS -DICHART_LOCAL_PLAN_QA",
                          "-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -D ICHART_LOCAL_QA_PLAN_PREVIEW"):
                with self.subTest(flags=flags), self.assertRaises(packaging.GuardError):
                    packaging.compilation_evidence(self.compiler(root, flags), root)
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(self.compiler(root, target="arm64-apple-ios17.0-simulator"), root)
            self.assertEqual(len(packaging.compilation_evidence(self.compiler(root), root)), 1)
            self.assertEqual(len(packaging.compilation_evidence(self.compiler(root, "-DICHART_PAID_SUBSCRIPTION -DICHART_STAGING_STOREKIT_PRODUCTS"), root)), 1)
            log = root / "archive.log"
            real = self.compiler(root).read_text()
            log.write_text("echo " + real)
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(log, root)
            log.write_text("SWIFT_ACTIVE_COMPILATION_CONDITIONS = ICHART_PAID_SUBSCRIPTION\n")
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(log, root)

    def test_real_xcode27_archive_wrappers_keep_flag_and_source_binding(self):
        # Redacted from archive173-locked-dependencies/archive.log line2099.
        # This tests the logged argv format only; that archive is superseded.
        template = '    builtin-SwiftDriver -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name iChart -O @{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart.SwiftFileList -DICHART_PAID_SUBSCRIPTION -DICHART_STAGING_STOREKIT_PRODUCTS -enable-bare-slash-regex -enable-experimental-feature DebugDescriptionMacro -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.2.sdk -target arm64-apple-ios17.0 -g -module-cache-path {derived}/ModuleCache.noindex -Xfrontend -serialize-debugging-options -swift-version 5 -I {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/BuildProductsPath/Release-iphoneos -F {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/BuildProductsPath/Release-iphoneos/PackageFrameworks -F {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/BuildProductsPath/Release-iphoneos -c -j10 -enable-batch-mode -incremental -Xcc -ivfsstatcache -Xcc {derived}/SDKStatCaches.noindex/iphoneos27.2-24B8118-9aa026f88bf9ed31cff8761912ac5bd16890c9e4970e00494a266ff652f095d9.sdkstatcache -output-file-map {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart-OutputFileMap.json -save-temps -no-color-diagnostics -explicit-module-build -module-cache-path {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/SwiftExplicitPrecompiledModules -clang-scanner-module-cache-path {derived}/ModuleCache.noindex -sdk-module-cache-path {derived}/SDKExplicitPrecompiledModules -emit-dependencies -emit-module -emit-module-path {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart.swiftmodule -serialize-diagnostics -dependency-scan-serialize-diagnostics-path {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart-dependency-scan.dia -validate-clang-modules-once -clang-build-session-file {derived}/ModuleCache.noindex/Session.modulevalidation -Xcc -fmodules-prune-interval\\=86400 -Xcc -fmodules-prune-after\\=345600 -emit-const-values -const-gather-protocols-list {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart_const_extract_protocols.json -Xcc -iquote -Xcc {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/iChart-generated-files.hmap -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/iChart-own-target-headers.hmap -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/iChart-all-non-framework-target-headers.hmap -Xcc -ivfsoverlay -Xcc {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart-e59c10da2ff0fefb0b15a108dd2996f3-VFS-iphoneos/all-product-headers.yaml -Xcc -iquote -Xcc {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/iChart-project-headers.hmap -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/BuildProductsPath/Release-iphoneos/include -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/DerivedSources-normal/arm64 -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/DerivedSources/arm64 -Xcc -I{derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/DerivedSources -emit-objc-header -emit-objc-header-path {derived}/Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64/iChart-Swift.h -working-directory {source} -experimental-emit-module-separately -disable-cmo'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, derived = root / "source", root / "DerivedData"
            objects = derived / "Build/Intermediates.noindex/ArchiveIntermediates/iChart/IntermediateBuildFilesPath/iChart.build/Release-iphoneos/iChart.build/Objects-normal/arm64"
            objects.mkdir(parents=True)
            inputs = [source / "iChart/Models/IChartProductAccessPolicy.swift",
                      source / "iChart/Models/IChartStoreKitProductCatalog.swift"]
            (objects / "iChart.SwiftFileList").write_text("\n".join(str(p) for p in inputs) + "\n")
            (objects / "iChart-OutputFileMap.json").write_text(json.dumps({str(p): {"object": str(objects / (p.stem + ".o"))} for p in inputs}))
            driver = template.format(source=source, derived=derived)
            wrappers = ["builtin-SwiftDriver", "builtin-Swift-Compilation-Requirements", "builtin-Swift-Compilation"]
            lines = [driver.replace("builtin-SwiftDriver", wrapper, 1) for wrapper in wrappers]
            log = root / "archive.log"
            log.write_text("\n".join(lines) + "\n")
            evidence = packaging.compilation_evidence(log, derived, source)
            self.assertEqual([item["wrapper"] for item in evidence], wrappers)
            self.assertTrue(all(packaging.REQUIRED_FLAGS <= set(item["conditions"]) for item in evidence))
            self.assertEqual(len({item["output_file_map"]["sha256"] for item in evidence}), 1)
            # Requirements are a planning record, and cannot stand alone.
            log.write_text(lines[1] + "\n")
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(log, derived, source)
            # Whitelisting real wrappers must not accept echoed or malformed argv.
            for bad in ["echo " + lines[0], "echo " + lines[1], "printf " + lines[2],
                        lines[0].replace(" -- ", " ", 1),
                        lines[0].replace("builtin-SwiftDriver", "builtin-Fake-SwiftDriver", 1),
                        lines[2].replace("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc", "/tmp/fake/swiftc", 1)]:
                log.write_text(bad + "\n")
                with self.subTest(bad=bad[:90]), self.assertRaises(packaging.GuardError):
                    packaging.compilation_evidence(log, derived, source)

    def test_compiler_expands_response_flags_and_rejects_external_or_hidden_preview(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            response = root / "common.resp"
            response.write_text("-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS")
            self.assertEqual(len(packaging.compilation_evidence(self.compiler(root, "@" + str(response)), root)), 1)
            response.write_text("-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -D DEBUG")
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(self.compiler(root, "@" + str(response)), root)
            with self.assertRaises(packaging.GuardError):
                packaging.expand_responses(["@/outside/untrusted.resp"], root)

    def test_compile_output_map_must_include_current_policy_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            policy = source / "iChart/Models/IChartProductAccessPolicy.swift"
            mapping = root / "iChart-OutputFileMap.json"
            mapping.write_text(json.dumps({str(policy): {"object": str(root / "policy.o")}, str(source / "iChart/Models/IChartStoreKitProductCatalog.swift"): {"object": str(root / "catalog.o")}}))
            log = self.compiler(root, "-D ICHART_PAID_SUBSCRIPTION -D ICHART_STAGING_STOREKIT_PRODUCTS -output-file-map " + str(mapping))
            evidence = packaging.compilation_evidence(log, root, source)
            self.assertEqual(evidence[0]["output_file_map"]["sha256"], packaging.sha(mapping.read_bytes()))
            mapping.write_text(json.dumps({str(source / "unrelated.swift"): {}}))
            with self.assertRaises(packaging.GuardError):
                packaging.compilation_evidence(log, root, source)

    def test_archive_and_ipa_guards_reject_wrong_backends_and_personal_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "fixture.xcarchive"
            app = archive / "Products/Applications/iChart.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps(self.info()))
            (app / "iChart").write_bytes(b"synthetic executable")
            self.assertEqual(packaging.verify_archive(archive, "2.0.0", "999", self.key)["build"], "999")
            (app / "PersonalMLComparison").mkdir()
            with self.assertRaises(packaging.GuardError):
                packaging.verify_archive(archive, "2.0.0", "999", self.key)
            ipa = root / "fixture.ipa"
            with zipfile.ZipFile(ipa, "w") as package:
                package.writestr("Payload/iChart.app/Info.plist", plistlib.dumps(self.info()))
                package.writestr("Payload/iChart.app/iChart", b"synthetic executable")
            self.assertEqual(packaging.verify_ipa(ipa, "2.0.0", "999", self.key)["url"], packaging.STAGING_URL)
            with zipfile.ZipFile(ipa, "w") as package:
                package.writestr("Payload/iChart.app/Info.plist", plistlib.dumps(self.info(SupabaseURL="https://wrong.example")))
            with self.assertRaises(packaging.GuardError):
                packaging.verify_ipa(ipa, "2.0.0", "999", self.key)

    def test_runtime_catalog_requires_exact_explicit_product_order(self):
        source = MODULE_PATH.resolve().parent.parent
        catalog = packaging.check_source(source, self.monthly, self.annual)
        self.assertEqual(catalog["requested_prices"]["annual"]["amount"], "60.00")
        for monthly, annual in ((self.annual, self.monthly), ("unreviewed.monthly", self.annual)):
            with self.assertRaises(packaging.GuardError):
                packaging.check_source(source, monthly, annual)

    def test_public_beta_inputs_remain_unchanged_and_paid_is_opt_in(self):
        source = MODULE_PATH.resolve().parent.parent
        project = (source / "project.yml").read_text()
        policy = (source / "iChart/Models/IChartProductAccessPolicy.swift").read_text()
        self.assertIn("SUPABASE_URL: https://pausvvwoazbvmzyrebwl.supabase.co", project)
        self.assertNotIn(packaging.STAGING_REF, project)
        self.assertNotIn(packaging.PAID_FLAG, project)
        self.assertIn("#if ICHART_PAID_SUBSCRIPTION", policy)
        self.assertIn("static let current: Self = .freeAllFeatures", policy)

    def test_environment_removes_backend_and_injected_build_overrides(self):
        invented = {"SUPABASE_URL": "https://wrong.invalid", "SUPABASE_SERVICE_ROLE_KEY": "invented-secret",
                    "SUPABASE_PUBLISHABLE_KEY": self.key, "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                    "OTHER_SWIFT_FLAGS": "-DDEBUG", "XCODE_XCCONFIG_FILE": "/wrong/config",
                    "SIMCTL_CHILD_SUPABASE_URL": "https://wrong.invalid", "ICHART_PERSONAL_ML_ARTIFACT_DIR": "/private/fixture"}
        with patch.dict(os.environ, invented):
            environment = packaging.safe_environment()
        self.assertFalse(set(invented).intersection(environment))

    def test_subprocess_failure_redacts_public_key_and_keeps_failure_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "synthetic.log"
            with self.assertRaises(packaging.GuardError):
                packaging.run_logged([sys.executable, "-c", "import sys; print(sys.argv[1]); sys.exit(1)", self.key], log, root, self.key)
            self.assertNotIn(self.key, log.read_text())
            self.assertIn("<staging-publishable-key>", log.read_text())

    def test_plan_is_redacted_and_does_not_build_or_create_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "key"
            key.write_text(self.key)
            output = root / "output"
            args = ["plan", "--project-ref", packaging.STAGING_REF, "--publishable-key-file", str(key),
                    "--version", "2.0.0", "--build", "999", "--monthly-product-id", self.monthly,
                    "--annual-product-id", self.annual, "--output-dir", str(output)]
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                packaging.main(args)
            text = stream.getvalue()
            self.assertNotIn(self.key, text)
            self.assertFalse(output.exists())
            self.assertFalse(json.loads(text)["apple_price_verified_by_packaging"])
            for flag, value in (("--project-ref", "pausvvwoazbvmzyrebwl"), ("--build", "172"), ("--version", "unset")):
                changed = list(args)
                changed[changed.index(flag) + 1] = value
                with self.assertRaises(packaging.GuardError):
                    packaging.main(changed)


if __name__ == "__main__":
    unittest.main()
