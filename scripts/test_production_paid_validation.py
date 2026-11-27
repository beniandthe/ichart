import copy
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("paid_validation", Path(__file__).with_name("run_production_paid_validation.py"))
paid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paid)


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

    def result(self):
        summary = {"result": "Passed", "passedTests": len(paid.TEST_CLASSES), "failedTests": 0, "skippedTests": 0,
                   "devicesAndConfigurations": [{"passedTests": len(paid.TEST_CLASSES), "device": {"deviceId": "ABC"}}]}
        tree = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": name + "/testFixture()", "result": "Passed"}
                              for name in paid.TEST_CLASSES]}
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
        self.assertEqual(sum(paid.validate_results(summary, tree, "ABC").values()), len(paid.TEST_CLASSES))
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


if __name__ == "__main__": unittest.main()
