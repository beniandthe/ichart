import copy
import importlib.util
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("paid_validation", Path(__file__).with_name("run_production_paid_validation.py"))
paid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paid)

EXPIRY_CLASSES = {
    "IChartSubscriptionDeadlineTests": 6,
    "IChartSubscriptionEntitlementExpiryTests": 9,
    "IChartKnownExpiryExportContextTests": 1,
}


class ProductionPaidValidationTests(unittest.TestCase):
    def original(self):
        return {
            "settings": {"configs": {"Debug": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}}},
            "targets": {
                "iChart": {"info": {"path": "iChart/App/Info.plist"}, "sources": [{"path": "iChart"}],
                           "dependencies": [{"package": "Supabase"}]},
                "iChartTests": {}, "RecognitionStudy": {},
            },
            "packages": {"Supabase": {"url": "https://github.com/supabase/supabase-swift.git"}},
            "schemes": {"iChart": {}, "RecognitionStudy": {}},
        }

    def settings(self):
        return [{"target": name, "buildSettings": {
            "CONFIGURATION": "Release",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": paid.PAID_FLAG +
                (" " + paid.VALIDATION_FLAG if name == "iChartTests" else ""),
        }} for name in ("iChart", "iChartTests")]

    def result(self, lane="production-paid"):
        identifiers = [name + "/testFixture" for name in paid.selected_classes(lane) if name not in paid.COORDINATED_TEST_CLASSES]
        identifiers += list(paid.REQUIRED_COORDINATED_TESTS)
        summary = {"result": "Passed", "passedTests": len(identifiers), "failedTests": 0, "skippedTests": 0,
                   "devicesAndConfigurations": [{"passedTests": len(identifiers), "device": {"deviceId": "ABC"}}]}
        tree = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"}
                              for name in identifiers]}
        return summary, tree

    def testProjectTransformationDoesNotMutateNormalSpecOrDependencies(self):
        original = self.original()
        before = copy.deepcopy(original)
        result = paid.make_spec(original, Path("/private/tmp/isolated-paid"))
        self.assertEqual(original, before)
        self.assertEqual(result["settings"], original["settings"])
        self.assertEqual(result["packages"], original["packages"])
        self.assertEqual(set(result["targets"]), {"iChart", "iChartTests"})
        self.assertEqual(result["targets"]["iChart"]["info"]["path"], "/private/tmp/isolated-paid/iChart-Info.plist")
        self.assertIn("App/Info.plist", result["targets"]["iChart"]["sources"][0]["excludes"])
        self.assertEqual([item["path"] for item in result["targets"]["iChartTests"]["sources"]], list(paid.selected_sources()))

    def testSelectedReleaseSourceFilesContainEveryRequiredClass(self):
        source = Path(__file__).resolve().parents[1]
        text = "\n".join((source / name).read_text() for name in paid.selected_sources())
        for name in paid.selected_classes():
            self.assertIn("final class " + name + ": XCTestCase", text)

    def testReviewedCoordinationMethodInventoryMatchesItsSourceExactly(self):
        source = Path(__file__).resolve().parents[1]
        methods = []
        for name in paid.COORDINATED_TEST_CLASSES:
            path = source / ("iChartTests/" + name + ".swift")
            methods += [name + "/" + method for method in re.findall(r"^    func (test\w+)\(", path.read_text(), re.M)]
        self.assertTrue(paid.COORDINATION_CONTRACT_FINALIZED)
        self.assertEqual(len(methods), len(set(methods)))
        self.assertEqual(set(methods), set(paid.REQUIRED_COORDINATED_TESTS))
        for lane in paid.LANES:
            self.assertTrue(set(paid.COORDINATED_TEST_CLASSES) <= set(paid.selected_classes(lane)))
            self.assertTrue(set(paid.COORDINATED_TEST_SOURCES) <= set(paid.selected_sources(lane)))

    def testKnownExpiryMethodsAndRuntimeSourcesAreRequiredInEveryLane(self):
        source = Path(__file__).resolve().parents[1]
        self.assertTrue(set(EXPIRY_CLASSES) <= set(paid.COORDINATED_TEST_CLASSES))
        methods = []
        for name, count in EXPIRY_CLASSES.items():
            path = "iChartTests/" + name + ".swift"
            declared = [name + "/" + method for method in re.findall(
                r"^    func (test\w+)\(", (source / path).read_text(), re.M)]
            self.assertEqual(len(declared), count, name)
            methods += declared
            self.assertIn(path, paid.COORDINATED_TEST_SOURCES)
            for lane in paid.LANES:
                self.assertIn(name, paid.selected_classes(lane))
                self.assertIn(path, paid.selected_sources(lane))
                transformed = paid.make_spec(self.original(), Path("/private/tmp/expiry-proof"), lane)
                self.assertIn({"path": path}, transformed["targets"]["iChartTests"]["sources"])
        self.assertEqual(len(methods), 16)
        self.assertTrue(set(methods) <= set(paid.REQUIRED_COORDINATED_TESTS))
        for path in ("iChart/Models/IChartSubscriptionEntitlement.swift", "iChart/Models/AppEntitlements.swift",
                     "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift", "iChart/Services/ChartExporting.swift"):
            self.assertIn(path, paid.REQUIRED_RUNTIME_APP_SOURCES)

    def testEveryKnownExpiryMethodMustActuallyExecuteInBothLanes(self):
        required = [method for method in paid.REQUIRED_COORDINATED_TESTS
                    if method.split("/", 1)[0] in EXPIRY_CLASSES]
        self.assertEqual(len(required), 16)
        for lane in paid.LANES:
            summary, tree = self.result(lane)
            self.assertEqual(sum(paid.validate_results(summary, tree, "ABC", lane).values()), summary["passedTests"])
            for method in required:
                changed_summary, changed_tree = copy.deepcopy(summary), copy.deepcopy(tree)
                changed_tree["testNodes"] = [node for node in changed_tree["testNodes"]
                                             if node["nodeIdentifier"] != method + "()"]
                changed_summary["passedTests"] -= 1
                changed_summary["devicesAndConfigurations"][0]["passedTests"] -= 1
                with self.subTest(lane=lane, missing=method), self.assertRaises(ValueError):
                    paid.validate_results(changed_summary, changed_tree, "ABC", lane)

    def testGlobalPaidConditionsAreRejected(self):
        original = self.original()
        original["settings"]["base"] = {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": paid.PAID_FLAG}
        with self.assertRaises(ValueError): paid.make_spec(original, Path("/private/tmp/isolated-paid"))

    @unittest.skipUnless(shutil.which("xcodegen"), "XcodeGen is required to inspect the authoritative project")
    def testAuthoritativeProjectKeepsReleaseInputEmptyAndAppScoped(self):
        source = Path(__file__).resolve().parents[1]
        original = json.loads(subprocess.check_output(
            ["xcodegen", "dump", "--no-env", "--type", "json", "--spec", str(source / "project.yml")], text=True))
        self.assertNotIn("ICHART_RELEASE_ACCESS_CONDITIONS", json.dumps(original.get("settings", {})))
        self.assertEqual(original["targets"]["iChart"]["settings"]["base"]["ICHART_RELEASE_ACCESS_CONDITIONS"], "")
        self.assertEqual(original["targets"]["iChart"]["settings"]["configs"]["Release"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
                         "$(inherited) $(ICHART_RELEASE_ACCESS_CONDITIONS)")
        for name, target in original["targets"].items():
            if name != "iChart":
                self.assertNotIn("ICHART_RELEASE_ACCESS_CONDITIONS", json.dumps(target.get("settings", {})))

    def testActualAppAndTestsMustBothBePaid(self):
        paid.validate_build_settings(self.settings())
        for index in (0, 1):
            rows = self.settings()
            rows[index]["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = ""
            with self.assertRaises(ValueError): paid.validate_build_settings(rows)

    def testActualSettingsRejectMissingTargetTestMarkerAndNonRelease(self):
        rows = self.settings()
        with self.assertRaises(ValueError): paid.validate_build_settings(rows[:1])
        rows[1]["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = paid.PAID_FLAG
        with self.assertRaises(ValueError): paid.validate_build_settings(rows)
        rows = self.settings()
        rows[0]["buildSettings"]["CONFIGURATION"] = "Debug"
        with self.assertRaises(ValueError): paid.validate_build_settings(rows)

    def testActualSettingsRejectEveryStagingDebugOrPreviewFlag(self):
        for flag in paid.FORBIDDEN_FLAGS:
            for index in (0, 1):
                rows = self.settings()
                rows[index]["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] += " " + flag
                with self.subTest(flag=flag, target=index), self.assertRaises(ValueError):
                    paid.validate_build_settings(rows)

    def testDependencyContaminationIsRejected(self):
        rows = self.settings() + [{"target": "Supabase", "buildSettings": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": paid.PAID_FLAG}}]
        with self.assertRaises(ValueError): paid.validate_build_settings(rows)

    def testOtherSwiftFlagsCannotSmuggleCompileTimeOverrides(self):
        for flags in ["-DDEBUG", "-D DEBUG", "-Xfrontend -DDEBUG", "-DICHART_LOCAL_PLAN_QA",
                      "-D ICHART_STAGING_STOREKIT_PRODUCTS", "-DICHART_PAID_SUBSCRIPTION"]:
            for index in (0, 1):
                rows = self.settings()
                rows[index]["buildSettings"]["OTHER_SWIFT_FLAGS"] = flags
                with self.subTest(flags=flags, target=index), self.assertRaises(ValueError):
                    paid.validate_build_settings(rows)

    def testBuildEnvironmentDoesNotInheritCompilerXcconfigBackendOrQAOverrides(self):
        environment = {"PATH": "/usr/bin", "HOME": "/Users/example", "TMPDIR": "/private/tmp",
                       "XCODE_XCCONFIG_FILE": "/private/tmp/injected.xcconfig",
                       "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "OTHER_SWIFT_FLAGS": "-DDEBUG",
                       "SUPABASE_URL": "https://staging.invalid", "ICHART_LOCAL_PLAN_QA": "YES",
                       "SWIFT_EXEC": "/private/tmp/custom-swift", "SDKROOT": "/private/tmp/sdk"}
        self.assertEqual(paid.build_environment(environment),
                         {"PATH": "/usr/bin", "HOME": "/Users/example", "TMPDIR": "/private/tmp"})

    def testActualCompilerEvidenceRequiresBothModulesAndExactProductionDefines(self):
        app = "builtin-SwiftDriver -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name iChart -target arm64-apple-ios17.0-simulator -O -D ICHART_PAID_SUBSCRIPTION"
        tests = app.replace("-module-name iChart", "-module-name iChartTests") + " -D ICHART_PRODUCTION_PAID_VALIDATION"
        derived = Path("/private/tmp/paid-derived-fixture")
        self.assertEqual(set(paid.validate_compiler_commands(app + "\n" + tests, derived)), {"iChart", "iChartTests"})
        self.assertTrue(paid.validate_compiler_commands(app + " -Xcc -D_LIBCPP_HARDENING_MODE=1\n" + tests, derived))
        for bad in [app, app + "\n" + tests + " -DDEBUG", app + " -Xfrontend -D -Xfrontend DEBUG\n" + tests,
                    app + "\n" + tests.replace("ICHART_PAID_SUBSCRIPTION", "ICHART_INTERNAL_STAGING"),
                    app.replace("-simulator", "") + "\n" + tests, app.replace("-O", "-Onone") + "\n" + tests,
                    "echo " + app + "\n" + tests]:
            with self.subTest(log=bad), self.assertRaises(ValueError): paid.validate_compiler_commands(bad, derived)

    def testCompilerResponsesAreBoundedWithinRunAndExposeHiddenDefines(self):
        with tempfile.TemporaryDirectory() as directory:
            derived = Path(directory)
            response = derived / "flags.rsp"
            response.write_text("-D ICHART_PAID_SUBSCRIPTION -DDEBUG")
            receipts = {}
            self.assertEqual(paid.expand_responses(["@" + str(response)], derived, receipts),
                             ["-D", "ICHART_PAID_SUBSCRIPTION", "-DDEBUG"])
            self.assertIn(str(response.resolve()), receipts)
            with self.assertRaises(ValueError): paid.expand_responses(["@/etc/passwd"], derived, {})

    def testCleanHeadRejectsDirtyUntrackedInputsAndChangedCommit(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=source, text=True, stderr=subprocess.DEVNULL).strip()
            git("init", "-q")
            (source / "project.yml").write_text("name: test\n")
            git("add", "project.yml")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Fixture")
            head = paid.require_clean_head(source)
            (source / "untracked.swift").write_text("// uncommitted input\n")
            with self.assertRaises(ValueError): paid.require_clean_head(source)
            (source / "untracked.swift").unlink()
            (source / "project.yml").write_text("name: changed\n")
            with self.assertRaises(ValueError): paid.require_clean_head(source)
            git("add", "project.yml")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Changed")
            with self.assertRaises(ValueError): paid.require_clean_head(source, head)
        rows = self.settings()
        rows[0]["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] += " " + paid.VALIDATION_FLAG
        with self.assertRaises(ValueError): paid.validate_build_settings(rows)

    def testEverySelectedClassMustActuallyExecute(self):
        summary, tree = self.result()
        self.assertEqual(sum(paid.validate_results(summary, tree, "ABC").values()), summary["passedTests"])
        tree["testNodes"].pop()
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "ABC")

    def testWrongSimulatorAndZeroOrSkippedResultsAreRejected(self):
        summary, tree = self.result()
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "WRONG")
        for key, value in [("passedTests", 0), ("failedTests", 1), ("skippedTests", 1), ("result", "Failed")]:
            changed = dict(summary, **{key: value})
            with self.subTest(key=key), self.assertRaises(ValueError): paid.validate_results(changed, tree, "ABC")

    def testUnexpectedAndNonPassingTestCasesAreRejected(self):
        summary, tree = self.result()
        tree["testNodes"][0]["result"] = "Skipped"
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "ABC")
        summary, tree = self.result()
        tree["testNodes"][0]["nodeIdentifier"] = "UnselectedSuite/testUnexpected()"
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "ABC")

    def testPublicFreeLaneHasNoPaidOrValidationDefinesInEitherTarget(self):
        original = self.original()
        result = paid.make_spec(original, Path("/private/tmp/free-proof"), "public-free")
        for name in ("iChart", "iChartTests"):
            flags = result["targets"][name]["settings"]["configs"]["Release"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
            self.assertEqual(flags.strip(), "$(inherited)")
        self.assertNotIn("ProductionPaidAccessPolicyTests", paid.selected_classes("public-free"))
        rows = self.settings()
        for row in rows:
            row["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = ""
        paid.validate_build_settings(rows, "public-free")
        for name in ("iChart", "iChartTests"):
            contaminated = copy.deepcopy(rows)
            next(row for row in contaminated if row["target"] == name)["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = paid.PAID_FLAG
            with self.assertRaises(ValueError): paid.validate_build_settings(contaminated, "public-free")

    def testUnknownAppAndTestDefinesFailClosedInBothLanes(self):
        for lane in paid.LANES:
            for name in ("iChart", "iChartTests"):
                rows = self.settings()
                for row in rows:
                    row["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = " ".join(paid.expected_defines(row["target"], lane))
                next(row for row in rows if row["target"] == name)["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] += " UNREVIEWED_FEATURE"
                with self.subTest(lane=lane, target=name), self.assertRaises(ValueError): paid.validate_build_settings(rows, lane)

    def testDuplicateMethodsAndInconsistentDeviceTotalsAreRejected(self):
        summary, tree = self.result()
        tree["testNodes"].append(copy.deepcopy(tree["testNodes"][0]))
        summary["passedTests"] += 1
        summary["devicesAndConfigurations"][0]["passedTests"] += 1
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "ABC")
        summary, tree = self.result()
        summary["devicesAndConfigurations"][0]["passedTests"] -= 1
        with self.assertRaises(ValueError): paid.validate_results(summary, tree, "ABC")

    def testResultBundleInventoryRejectsSymlinksAndObservesByteChanges(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "example.xcresult"
            bundle.mkdir()
            evidence = bundle / "data"
            evidence.write_bytes(b"first")
            first = paid.result_bundle_hashes(bundle)
            evidence.write_bytes(b"second")
            self.assertNotEqual(first, paid.result_bundle_hashes(bundle))
            (bundle / "escape").symlink_to("/etc/passwd")
            with self.assertRaises(ValueError): paid.result_bundle_hashes(bundle)

    def testActualCompilerRequiresRuntimeAndSelectedTestFileBindings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, derived = root / "source", root / "DerivedData"
            derived.mkdir()
            lines = []
            for module, paths in (("iChart", paid.REQUIRED_RUNTIME_APP_SOURCES), ("iChartTests", paid.selected_sources())):
                required = [str(source / p) for p in paths]
                for name in required:
                    path = Path(name)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("// synthetic compiled source")
                mapping = derived / (module + ".json")
                mapping.write_text(json.dumps({p: {} for p in required}))
                lines.append("builtin-SwiftDriver -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name " + module + " -target arm64-apple-ios17.0-simulator -O -output-file-map " + str(mapping) + " " + " ".join(required) + " " + " ".join("-D " + p for p in paid.expected_defines(module)))
            manifest = {str(p.relative_to(source)): paid.hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob("*") if p.is_file()}
            self.assertTrue(paid.validate_compiler_commands("\n".join(lines), derived, source=source, source_inputs=manifest))
            mapping.write_text("{}")
            with self.assertRaises(ValueError): paid.validate_compiler_commands("\n".join(lines), derived, source=source, source_inputs=manifest)

    def testUnmanifestedIgnoredExternalAndChangedSwiftInputsFailClosed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source, derived = root / "source", root / "DerivedData"
            source.mkdir(); derived.mkdir()
            tracked = source / "Tracked.swift"
            tracked.write_text("// frozen")
            manifest = {"Tracked.swift": paid.hashlib.sha256(tracked.read_bytes()).hexdigest()}
            self.assertEqual(paid.bind_swift_inputs([str(tracked)], source, derived, manifest)["sourceInputHashes"], manifest)
            ignored = source / "Ignored.swift"
            ignored.write_text("// ignored and absent from Git manifest")
            with self.assertRaises(ValueError): paid.bind_swift_inputs([str(tracked), str(ignored)], source, derived, manifest)
            external = root / "External.swift"
            external.write_text("// external")
            with self.assertRaises(ValueError): paid.bind_swift_inputs([str(tracked), str(external)], source, derived, manifest)
            tracked.write_text("// changed during compilation")
            with self.assertRaises(ValueError): paid.bind_swift_inputs([str(tracked)], source, derived, manifest)
            tracked.write_text("// frozen")
            generated = derived / "GeneratedAssetSymbols.swift"
            generated.write_text("// generated first")
            first = paid.bind_swift_inputs([str(tracked), str(generated)], source, derived, manifest)
            generated.write_text("// generated second")
            self.assertNotEqual(first, paid.bind_swift_inputs([str(tracked), str(generated)], source, derived, manifest))


if __name__ == "__main__": unittest.main()
