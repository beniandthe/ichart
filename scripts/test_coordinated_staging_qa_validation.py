"""Synthetic QA packaging guards; never invokes Xcode, native tests or services."""
import ast
import copy
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shlex
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/run_coordinated_staging_qa_validation.py"
PRODUCTION = ROOT / "scripts/run_production_paid_validation.py"
SPEC = importlib.util.spec_from_file_location("coordinated_qa_native_test_subject", RUNNER)
qa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qa)
recipe = qa.recipe
REVIEWED_KEY_HASH = recipe.QA_KEY_SHA256
SYNTHETIC_KEY = "sb_publishable_synthetic_qa_fixture_client_0123456789"
SYNTHETIC_HASH = hashlib.sha256(SYNTHETIC_KEY.encode()).hexdigest()
APP_FLAGS = {"ICHART_PAID_SUBSCRIPTION", "ICHART_STAGING_STOREKIT_PRODUCTS", "ICHART_COORDINATED_STAGING_QA"}
MARKER = "ICHART_PRODUCTION_PAID_VALIDATION"
DEVICE = "12345678-1234-1234-1234-123456789ABC"
SHARED_CLASSES = {
    "CoordinatedProductAccessStoreTests": 25,
    "CoordinatedPaidCheckoutAdmissionTests": 14,
    "CoordinatedLibraryPolicyPreservationTests": 5,
    "CoordinatedPlanPresentationTests": 9,
    "IChartSubscriptionDeadlineTests": 6,
    "IChartSubscriptionEntitlementExpiryTests": 9,
    "IChartKnownExpiryExportContextTests": 1,
}
EXTRA_CLASSES = {
    "CoordinatedQAConfigurationTests": 3,
    "CoordinatedQABackendRoutingTests": 4,
    "IChartAuthStorageIsolationTests": 5,
    "IChartStorageNamespaceTests": 5,
    "IChartStoreKitProductCatalogTests": 13,
}


def functions(path):
    return {node.name: node for node in ast.parse(path.read_text()).body if isinstance(node, ast.FunctionDef)}


def declared_tests(paths):
    """Associate ordinary four-space XCTest methods with their declared class.

    Include all class declarations as boundaries so helper classes cannot lend
    methods to a preceding test class. These reviewed files contain no nested
    XCTest classes; source and runtime inventories are independently checked.
    """
    result = {}
    for relative in paths:
        text = (ROOT / relative).read_text()
        declarations = list(re.finditer(r"^(?:@\w+\s+)?(?:\w+\s+)*class\s+(\w+)([^\n]*)", text, re.M))
        for index, declaration in enumerate(declarations):
            if not re.search(r":\s*XCTestCase\b", declaration.group(2)):
                continue
            end = declarations[index + 1].start() if index + 1 < len(declarations) else len(text)
            name = declaration.group(1)
            if name in result:
                raise AssertionError("Duplicate selected XCTest class: " + name)
            result[name] = [name + "/" + method for method in re.findall(
                r"^    func (test\w+)\(", text[declaration.end():end], re.M)]
    return result


class CoordinatedStagingQAValidationTests(unittest.TestCase):
    def original(self):
        return {
            "name": "iChart",
            "settings": {"base": {"MARKETING_VERSION": "1.9.4", "CURRENT_PROJECT_VERSION": "208"},
                         "configs": {"Debug": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}}},
            "packages": {"Supabase": {"url": "https://example.invalid/synthetic-package.git", "from": "2.0.0"}},
            "targets": {
                "iChart": {
                    "settings": {"base": {"SUPABASE_URL": "https://production.invalid",
                                            "SUPABASE_PUBLISHABLE_KEY": "synthetic-normal-client-key",
                                            "ICHART_RELEASE_ACCESS_CONDITIONS": ""},
                                 "configs": {"Release": {
                                     "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) $(ICHART_RELEASE_ACCESS_CONDITIONS)",
                                     "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "Apple Distribution",
                                     "PROVISIONING_PROFILE_SPECIFIER": "iChart App Store"}}},
                    "info": {"path": "iChart/App/Info.plist", "properties": {
                        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "SupabaseURL": "$(SUPABASE_URL)",
                        "SupabasePublishableKey": "$(SUPABASE_PUBLISHABLE_KEY)", "SupabaseAnonKey": "$(SUPABASE_ANON_KEY)"}},
                    "sources": [{"path": "iChart", "excludes": ["Resources"]}],
                    "dependencies": [{"package": "Supabase"}],
                },
                "iChartTests": {"settings": {"base": {"TEST_HOST": "synthetic-host"}}, "dependencies": [{"target": "iChart"}]},
                "RecognitionStudy": {"settings": {"base": {"SYNTHETIC_UNRELATED": "preserved"}}},
            },
            "schemes": {"iChart": {"archive": {"config": "Release"}}, "RecognitionStudy": {}},
        }

    @contextmanager
    def trusted_synthetic_key(self):
        with patch.object(recipe, "QA_KEY_SHA256", SYNTHETIC_HASH):
            yield SYNTHETIC_KEY

    def settings(self):
        return [{"target": name, "buildSettings": {
            "CONFIGURATION": "Release",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": " ".join(sorted(APP_FLAGS | ({MARKER} if name == "iChartTests" else set()))),
        }} for name in ("iChart", "iChartTests")]

    def results(self):
        identifiers = [name + "/testBaseline" for name in qa.selected_classes() if name not in qa.COORDINATED_TEST_CLASSES]
        identifiers += list(qa.REQUIRED_COORDINATED_TESTS)
        count = len(identifiers)
        summary = {"result": "Passed", "passedTests": count, "failedTests": 0, "skippedTests": 0,
                   "totalTestCount": count, "devicesAndConfigurations": [{"passedTests": count, "device": {"deviceId": DEVICE}}]}
        tree = {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"} for name in identifiers]}]}
        return summary, tree

    @contextmanager
    def compiler_fixture(self):
        with tempfile.TemporaryDirectory(prefix="ichart-qa-compiler-fixture-") as directory:
            root = Path(directory).resolve()
            source, derived = root / "source with spaces", root / "DerivedData"
            derived.mkdir()
            tokens = {}
            maps = {}
            for module, relatives in (("iChart", qa.REQUIRED_RUNTIME_APP_SOURCES), ("iChartTests", qa.selected_sources())):
                paths = [source / relative for relative in relatives]
                for path in paths:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("// synthetic compiled input: " + path.name)
                mapping = derived / (module + ".json")
                mapping.write_text(json.dumps({str(path): {} for path in paths}))
                maps[module] = mapping
                flags = APP_FLAGS | ({MARKER} if module == "iChartTests" else set())
                tokens[module] = ["builtin-SwiftDriver", "--", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
                                  "-module-name", module, "-target", "arm64-apple-ios17.0-simulator", "-O",
                                  "-output-file-map", str(mapping), *map(str, paths),
                                  *[item for flag in sorted(flags) for item in ("-D", flag)]]
            manifest = {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in source.rglob("*") if path.is_file()}
            yield root, source, derived, tokens, maps, manifest

    def compiler_log(self, tokens):
        return "\n".join(shlex.join(tokens[module]) for module in ("iChart", "iChartTests"))

    def testReviewedQALiteralsAndArtifactIdentityAreExplicit(self):
        self.assertEqual(recipe.APP_FLAGS, APP_FLAGS)
        self.assertEqual(recipe.QA_REF, "yiuxduqhhbucsmooevxz")
        self.assertEqual(recipe.QA_URL, "https://yiuxduqhhbucsmooevxz.supabase.co")
        self.assertEqual(REVIEWED_KEY_HASH, "bfdf9049a7237013fea1b1f18d137e4d58daa34078fec4290b78a9676e9038e2")
        self.assertEqual((recipe.QA_VERSION, recipe.QA_BUILD, recipe.SOURCE_BUILD), ("1.9.4", "207", "208"))
        self.assertEqual(recipe.QA_PRODUCTS, {"monthly": "com.ichart.app.staging.fix036.monthly", "annual": "com.ichart.app.staging.fix036.annual"})
        self.assertEqual(recipe.QA_NAMESPACE, {"mode": "coordinatedStagingQA", "directory": "iChart Coordinated QA yiuxduqhhbucsmooevxz",
                         "defaults_suite": "com.ichart.app.coordinated-qa.yiuxduqhhbucsmooevxz", "auth_prefix": "coordinated-qa.yiuxduqhhbucsmooevxz."})

    def testAppAndTestsRequireExactFlagsWithMarkerOnlyInTests(self):
        self.assertEqual(qa.expected_defines("iChart"), APP_FLAGS)
        self.assertEqual(qa.expected_defines("iChartTests"), APP_FLAGS | {MARKER})
        qa.validate_build_settings(self.settings())
        for function in (qa.selected_classes, qa.selected_sources):
            for lane in ("production-paid", "public-free", "internal-staging", "unknown"):
                with self.subTest(lane=lane), self.assertRaises(ValueError): function(lane)

    def testEveryMissingOrUnexpectedActualConditionFailsClosed(self):
        for index, name in enumerate(("iChart", "iChartTests")):
            expected = APP_FLAGS | ({MARKER} if index else set())
            variants = [expected - {flag} for flag in expected]
            variants += [expected | {flag} for flag in {"DEBUG", "ICHART_LOCAL_PLAN_QA", "ICHART_LOCAL_QA_PLAN_PREVIEW", "UNREVIEWED_FEATURE", "ICHART_COORDINATED_STAGING_QA=1"}]
            if index == 0: variants.append(expected | {MARKER})
            for flags in variants:
                rows = self.settings(); rows[index]["buildSettings"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = " ".join(sorted(flags))
                with self.subTest(target=name, flags=flags), self.assertRaises(ValueError): qa.validate_build_settings(rows)

    def testActualSettingsRequireBothReleaseTargetsAndNoHiddenDefines(self):
        with self.assertRaises(ValueError): qa.validate_build_settings(self.settings()[:1])
        for index in (0, 1):
            rows = self.settings(); rows[index]["buildSettings"]["CONFIGURATION"] = "Debug"
            with self.assertRaises(ValueError): qa.validate_build_settings(rows)
            for hidden in ("-DDEBUG", "-D ICHART_COORDINATED_STAGING_QA", "-Xfrontend -DICHART_PAID_SUBSCRIPTION"):
                rows = self.settings(); rows[index]["buildSettings"]["OTHER_SWIFT_FLAGS"] = hidden
                with self.subTest(hidden=hidden), self.assertRaises(ValueError): qa.validate_build_settings(rows)

    def testAllLaneFlagsAndTestMarkerAreForbiddenInDependencies(self):
        for flag in APP_FLAGS | {MARKER}:
            rows = self.settings() + [{"target": "Supabase", "buildSettings": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": flag}}]
            with self.subTest(flag=flag), self.assertRaises(ValueError): qa.validate_build_settings(rows)
        qa.validate_build_settings(self.settings() + [{"target": "Supabase", "buildSettings": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "SWIFT_PACKAGE"}}])

    def testAllLaneFlagsAndTestMarkerAreForbiddenInGlobalSettings(self):
        with self.trusted_synthetic_key() as key:
            for flag in APP_FLAGS | {MARKER}:
                original = self.original(); original["settings"]["base"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = flag
                for transform in (qa.make_spec, recipe.configure_app, recipe.make_archive_spec):
                    with self.subTest(flag=flag, transform=transform.__name__), self.assertRaises(ValueError):
                        transform(original, Path("/private/tmp/qa-unused-spec"), key=key)

    def testQAOverrideCannotHideWrongOrMissingNormalSourceIdentity(self):
        with self.trusted_synthetic_key() as key:
            for field, value in (("MARKETING_VERSION", "1.9.3"), ("MARKETING_VERSION", "$(VERSION)"),
                                 ("CURRENT_PROJECT_VERSION", "207"), ("CURRENT_PROJECT_VERSION", "209"),
                                 ("CURRENT_PROJECT_VERSION", "$(BUILD)"), ("CURRENT_PROJECT_VERSION", None)):
                original = self.original()
                if value is None: original["settings"]["base"].pop(field)
                else: original["settings"]["base"][field] = value
                for transform in (qa.make_spec, recipe.make_archive_spec):
                    with self.subTest(field=field, value=value, transform=transform.__name__), self.assertRaises(ValueError):
                        transform(original, Path("/private/tmp/qa-unused-spec"), key=key)

    def testIsolatedSpecBakesOnlyAppInputsWithoutMutatingNormalSource(self):
        original = self.original(); before = copy.deepcopy(original)
        with self.trusted_synthetic_key() as key:
            result = recipe.configure_app(original, Path("/private/tmp/qa-unused-spec"), key)
        self.assertEqual(original, before)
        self.assertEqual(result["settings"], before["settings"])
        self.assertEqual(result["packages"], before["packages"])
        for name in ("iChartTests", "RecognitionStudy"): self.assertEqual(result["targets"][name], before["targets"][name])
        app = result["targets"]["iChart"]
        self.assertEqual(app["settings"]["base"], before["targets"]["iChart"]["settings"]["base"])
        self.assertEqual(app["dependencies"], before["targets"]["iChart"]["dependencies"])
        self.assertEqual(app["info"]["properties"], {**before["targets"]["iChart"]["info"]["properties"],
                         "SupabaseURL": recipe.QA_URL, "SupabasePublishableKey": SYNTHETIC_KEY, "SupabaseAnonKey": "", "TFInternalTestingOnly": True})
        release = app["settings"]["configs"]["Release"]
        self.assertEqual((release["MARKETING_VERSION"], release["CURRENT_PROJECT_VERSION"]), ("1.9.4", "207"))
        self.assertEqual(before["settings"]["base"]["CURRENT_PROJECT_VERSION"], "208")
        self.assertEqual(set(release["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split()), APP_FLAGS | {"$(inherited)"})
        self.assertEqual(app["info"]["path"], "/private/tmp/qa-unused-spec/iChart-Info.plist")
        self.assertIn("App/Info.plist", app["sources"][0]["excludes"])

    def testArchiveSpecContainsOnlyAppAndKeepsManualSigningAndDependencies(self):
        original = self.original(); before = copy.deepcopy(original)
        with self.trusted_synthetic_key() as key: result = recipe.make_archive_spec(original, Path("/private/tmp/qa-unused-archive"), key)
        self.assertEqual(original, before)
        self.assertEqual(set(result["targets"]), {"iChart"})
        self.assertEqual(result["packages"], before["packages"])
        release = result["targets"]["iChart"]["settings"]["configs"]["Release"]
        self.assertEqual(release["ENABLE_TESTABILITY"], "NO")
        for key in ("CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER"):
            self.assertEqual(release[key], before["targets"]["iChart"]["settings"]["configs"]["Release"][key])
        self.assertEqual(result["schemes"], {"iChart": {"build": {"targets": {"iChart": "all"}}, "archive": {"config": "Release"}}})

    def testNativeSpecSelectsOnlyReviewedSourcesAndKeepsBothTargetsTestable(self):
        original = self.original(); before = copy.deepcopy(original)
        with self.trusted_synthetic_key() as key: result = qa.make_spec(original, Path("/private/tmp/qa-unused-native"), key=key)
        self.assertEqual(original, before)
        self.assertEqual(set(result["targets"]), {"iChart", "iChartTests"})
        self.assertEqual(result["settings"], before["settings"])
        self.assertEqual(result["packages"], before["packages"])
        for name in ("iChart", "iChartTests"):
            release = result["targets"][name]["settings"]["configs"]["Release"]
            self.assertEqual(release["ENABLE_TESTABILITY"], "YES")
            self.assertEqual(set(release["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split()), qa.expected_defines(name) | {"$(inherited)"})
        self.assertEqual([entry["path"] for entry in result["targets"]["iChartTests"]["sources"]], list(qa.selected_sources()))

    def testOnlyPinnedRegularPublishableKeyFileIsAcceptedWithoutEcho(self):
        with tempfile.TemporaryDirectory(prefix="ichart-qa-key-fixture-") as directory, self.trusted_synthetic_key():
            path = Path(directory) / "client-key.txt"; path.write_text(" \n" + SYNTHETIC_KEY + "\n"); path.chmod(0o600)
            self.assertEqual(recipe.read_public_key(path), SYNTHETIC_KEY)
            for value in ("sb_publishable_synthetic_wrong_project_0123456789", "_".join(('sb', 'secret', 'synthetic_secret_0123456789')), "synthetic.service.role.jwt", "", "$(SUPABASE_PUBLISHABLE_KEY)"):
                path.write_text(value); output, errors = io.StringIO(), io.StringIO()
                with redirect_stdout(output), redirect_stderr(errors), self.assertRaises(ValueError) as caught: recipe.read_public_key(path)
                self.assertEqual(output.getvalue() + errors.getvalue(), "")
                if value: self.assertNotIn(value, str(caught.exception))
            with self.assertRaises(ValueError): recipe.configure_app(self.original(), Path(directory), "sb_publishable_synthetic_wrong_project_0123456789")

    def testKeyInputRejectsMissingDirectoriesSymlinksAndOversizeFiles(self):
        with tempfile.TemporaryDirectory(prefix="ichart-qa-key-bounds-") as directory, self.trusted_synthetic_key():
            root = Path(directory); target = root / "key"; target.write_text(SYNTHETIC_KEY)
            link = root / "link"; link.symlink_to(target)
            for path in (root, root / "missing", link):
                with self.subTest(path=path.name), self.assertRaises(ValueError): recipe.read_public_key(path)
            target.write_text("x" * 4097)
            with self.assertRaises(ValueError): recipe.read_public_key(target)

    def testBuildEnvironmentDropsCompilerBackendAndInjectionInputs(self):
        environment = {"PATH": "/usr/bin", "HOME": "/Users/synthetic", "TMPDIR": "/private/tmp", "LANG": "en_US.UTF-8",
                       "SUPABASE_URL": "https://wrong.invalid", "SUPABASE_SERVICE_ROLE_KEY": "synthetic-secret",
                       "SUPABASE_PUBLISHABLE_KEY": SYNTHETIC_KEY, "XCODE_XCCONFIG_FILE": "synthetic.xcconfig",
                       "SWIFT_EXEC": "synthetic-compiler", "SDKROOT": "synthetic-sdk", "OTHER_SWIFT_FLAGS": "-DDEBUG",
                       "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "DYLD_INSERT_LIBRARIES": "synthetic.dylib",
                       "SIMCTL_CHILD_SUPABASE_URL": "https://wrong.invalid", "ICHART_LOCAL_PLAN_QA": "YES"}
        expected = {name: environment[name] for name in ("PATH", "HOME", "TMPDIR", "LANG")}
        self.assertEqual(qa.build_environment(environment), expected)
        with patch.dict(qa.os.environ, environment, clear=True), patch.object(qa.subprocess, "check_output", return_value="synthetic output") as run:
            self.assertEqual(qa.run(["synthetic-command"]), "synthetic output")
        self.assertEqual(run.call_args.kwargs["env"], expected)

    def testSharedAndQARoutingAuthStorageCatalogInventoryIsComplete(self):
        declared = declared_tests(qa.selected_sources())
        expected_classes = SHARED_CLASSES | EXTRA_CLASSES
        self.assertEqual(set(qa.COORDINATED_TEST_CLASSES), set(expected_classes))
        for name, count in expected_classes.items(): self.assertEqual(len(declared[name]), count, name)
        actual = [method for name in expected_classes for method in declared[name]]
        self.assertEqual(len(actual), 99)
        self.assertEqual(len(qa.REQUIRED_COORDINATED_TESTS), 99)
        self.assertEqual(len(set(qa.REQUIRED_COORDINATED_TESTS)), 99)
        self.assertEqual(set(actual), set(qa.REQUIRED_COORDINATED_TESTS))
        source_ast = ast.parse(PRODUCTION.read_text())
        assignments = {node.targets[0].id: node.value for node in source_ast.body if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)}
        shared = ast.literal_eval(assignments["REQUIRED_COORDINATED_TESTS"])
        self.assertEqual(len(shared), 69)
        self.assertTrue(set(shared) <= set(actual))
        self.assertTrue(qa.COORDINATION_CONTRACT_FINALIZED)
        self.assertIn("iChartTests/Support/NativeAccessibilityLookup.swift", qa.selected_sources())
        self.assertNotIn("ProductionPaidBuildScopeTests", qa.selected_classes())
        self.assertNotIn("ProductionPaidBackendConfigurationTests", qa.selected_classes())
        self.assertEqual(len(qa.selected_classes()), len(set(qa.selected_classes())))

    def testEverySelectedClassIsDeclaredAndOwnRuntimeSourcesAreRequired(self):
        declared = declared_tests(qa.selected_sources())
        self.assertTrue(set(qa.selected_classes()) <= set(declared))
        self.assertEqual(len(qa.selected_sources()), len(set(qa.selected_sources())))
        for path in ("iChart/Persistence/IChartStorageNamespace.swift", "iChart/App/Supabase/IChartSupabaseConfiguration.swift",
                     "iChart/Models/IChartStoreKitProductCatalog.swift", "iChart/Models/IChartProductAccessStatus.swift",
                     "iChart/Models/IChartSubscriptionEntitlement.swift", "iChart/Models/AppEntitlements.swift",
                     "iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift", "iChart/Services/ChartExporting.swift"):
            self.assertIn(path, qa.REQUIRED_RUNTIME_APP_SOURCES)

    def testCompletePassingNativeInventoryIsCountedOnConfiguredSimulator(self):
        summary, tree = self.results(); counts = qa.validate_results(summary, tree, DEVICE)
        self.assertEqual(sum(counts.values()), summary["passedTests"])
        for name, count in (SHARED_CLASSES | EXTRA_CLASSES).items(): self.assertEqual(counts[name], count)

    def testZeroSkippedFailedAndWrongSimulatorResultsFail(self):
        summary, tree = self.results()
        with self.assertRaises(ValueError): qa.validate_results(summary, tree, "00000000-0000-0000-0000-000000000000")
        for key, value in (("passedTests", 0), ("passedTests", True), ("failedTests", 1), ("skippedTests", 1), ("result", "Failed")):
            changed = copy.deepcopy(summary); changed[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): qa.validate_results(changed, tree, DEVICE)

    def testMissingRequiredMethodsCannotHideBehindConsistentCounts(self):
        summary, tree = self.results(); tree["testNodes"][0]["children"].pop()
        for key in ("passedTests", "totalTestCount"): summary[key] -= 1
        summary["devicesAndConfigurations"][0]["passedTests"] -= 1
        with self.assertRaisesRegex(ValueError, "Missing required"): qa.validate_results(summary, tree, DEVICE)

    def testEveryKnownExpiryMethodMustActuallyExecuteWithConsistentTotals(self):
        classes = {"IChartSubscriptionDeadlineTests", "IChartSubscriptionEntitlementExpiryTests",
                   "IChartKnownExpiryExportContextTests"}
        required = [method for method in qa.REQUIRED_COORDINATED_TESTS if method.split("/", 1)[0] in classes]
        self.assertEqual(len(required), 16)
        for method in required:
            summary, tree = self.results()
            tree["testNodes"][0]["children"] = [node for node in tree["testNodes"][0]["children"]
                                               if node["nodeIdentifier"] != method + "()"]
            for key in ("passedTests", "totalTestCount"): summary[key] -= 1
            summary["devicesAndConfigurations"][0]["passedTests"] -= 1
            with self.subTest(missing=method), self.assertRaises(ValueError):
                qa.validate_results(summary, tree, DEVICE)

    def testDuplicateUnexpectedAndNonpassingMethodsFail(self):
        summary, tree = self.results(); children = tree["testNodes"][0]["children"]
        children.append(copy.deepcopy(children[-1]))
        for key in ("passedTests", "totalTestCount"): summary[key] += 1
        summary["devicesAndConfigurations"][0]["passedTests"] += 1
        with self.assertRaisesRegex(ValueError, "Duplicate"): qa.validate_results(summary, tree, DEVICE)
        for identifier, result in (("Unselected/testUnexpected()", "Passed"), (qa.REQUIRED_COORDINATED_TESTS[0] + "()", "Skipped")):
            summary, tree = self.results(); tree["testNodes"][0]["children"][0].update(nodeIdentifier=identifier, result=result)
            with self.assertRaises(ValueError): qa.validate_results(summary, tree, DEVICE)

    def testInconsistentDeviceAndMethodTotalsFail(self):
        summary, tree = self.results(); summary["devicesAndConfigurations"][0]["passedTests"] -= 1
        with self.assertRaises(ValueError): qa.validate_results(summary, tree, DEVICE)
        summary, tree = self.results(); summary["totalTestCount"] += 1
        with self.assertRaises(ValueError): qa.validate_results(summary, tree, DEVICE)
        summary, tree = self.results(); summary["devicesAndConfigurations"].append({"passedTests": 1, "device": {"deviceId": "WRONG"}})
        with self.assertRaises(ValueError): qa.validate_results(summary, tree, DEVICE)

    def testActualCompilerEvidenceBindsBothOptimizedModulesAndTheirSources(self):
        with self.compiler_fixture() as (_, source, derived, tokens, maps, manifest):
            evidence = qa.validate_compiler_commands(self.compiler_log(tokens), derived, source=source, source_inputs=manifest)
            self.assertEqual(set(evidence), {"iChart", "iChartTests"})
            for module in evidence:
                self.assertEqual(set(evidence[module][0]["conditions"]), APP_FLAGS | ({MARKER} if module == "iChartTests" else set()))
                self.assertTrue(evidence[module][0]["sourceBinding"]["sourceInputHashes"])
            with self.assertRaises(ValueError): qa.validate_compiler_commands(shlex.join(tokens["iChart"]), derived, source=source, source_inputs=manifest)

    def testCompilerRejectsMissingUnknownDebugAndHiddenConditions(self):
        with self.compiler_fixture() as (_, source, derived, tokens, maps, manifest):
            for module in tokens:
                for flag in APP_FLAGS | ({MARKER} if module == "iChartTests" else set()):
                    changed = copy.deepcopy(tokens); index = changed[module].index(flag); del changed[module][index - 1:index + 1]
                    with self.subTest(module=module, missing=flag), self.assertRaises(ValueError): qa.validate_compiler_commands(self.compiler_log(changed), derived, source=source, source_inputs=manifest)
                for extra in (["-DDEBUG"], ["-DUNREVIEWED_FEATURE"], ["-Xfrontend", "-DICHART_COORDINATED_STAGING_QA"]):
                    changed = copy.deepcopy(tokens); changed[module] += extra
                    with self.subTest(module=module, extra=extra), self.assertRaises(ValueError): qa.validate_compiler_commands(self.compiler_log(changed), derived, source=source, source_inputs=manifest)

    def testCompilerRejectsEchoRequirementsWrongTargetAndDebugOptimization(self):
        with self.compiler_fixture() as (_, source, derived, tokens, maps, manifest):
            for before, after in (("builtin-SwiftDriver", "echo"), ("builtin-SwiftDriver", "builtin-Swift-Compilation-Requirements"),
                                  ("arm64-apple-ios17.0-simulator", "arm64-apple-ios17.0"), ("-O", "-Onone")):
                changed = copy.deepcopy(tokens); changed["iChart"][changed["iChart"].index(before)] = after
                with self.subTest(after=after), self.assertRaises(ValueError): qa.validate_compiler_commands(self.compiler_log(changed), derived, source=source, source_inputs=manifest)

    def testCompilerMapMustMatchWholeSourceListAndPinnedBytes(self):
        with self.compiler_fixture() as (_, source, derived, tokens, maps, manifest):
            mapping = json.loads(maps["iChart"].read_text()); missing = next(iter(mapping)); del mapping[missing]; maps["iChart"].write_text(json.dumps(mapping))
            with self.assertRaises(ValueError): qa.validate_compiler_commands(self.compiler_log(tokens), derived, source=source, source_inputs=manifest)
        with self.compiler_fixture() as (_, source, derived, tokens, maps, manifest):
            path = source / qa.REQUIRED_RUNTIME_APP_SOURCES[0]; path.write_text("// changed frozen source")
            with self.assertRaisesRegex(ValueError, "pinned bytes changed"): qa.validate_compiler_commands(self.compiler_log(tokens), derived, source=source, source_inputs=manifest)

    def testIgnoredAndExternalSwiftInputsFailButGeneratedBytesAreBound(self):
        with self.compiler_fixture() as (root, source, derived, tokens, maps, manifest):
            for extra in (source / "Ignored.swift", root / "External.swift"):
                extra.write_text("// unpinned synthetic input")
                with self.subTest(extra=extra.name), self.assertRaises(ValueError): qa.bind_swift_inputs([str(source / qa.REQUIRED_RUNTIME_APP_SOURCES[0]), str(extra)], source, derived, manifest)
            generated = derived / "GeneratedAssetSymbols.swift"; generated.write_text("// first")
            paths = [str(source / qa.REQUIRED_RUNTIME_APP_SOURCES[0]), str(generated)]
            before = qa.bind_swift_inputs(paths, source, derived, manifest)
            self.assertEqual(before["generatedInputHashes"], {"GeneratedAssetSymbols.swift": hashlib.sha256(generated.read_bytes()).hexdigest()})
            generated.write_text("// second")
            self.assertNotEqual(before, qa.bind_swift_inputs(paths, source, derived, manifest))
            link = derived / "linked.swift"; link.symlink_to(generated)
            with self.assertRaises(ValueError): qa.bind_swift_inputs([paths[0], str(link)], source, derived, manifest)

    def testResponseFilesExposeConditionsAndCannotEscapeOrRecurseUnbounded(self):
        with tempfile.TemporaryDirectory(prefix="ichart-qa-responses-") as directory:
            root = Path(directory); derived = root / "DerivedData"; derived.mkdir(); response = derived / "flags.rsp"
            response.write_text("-D ICHART_COORDINATED_STAGING_QA -DDEBUG"); receipts = {}
            self.assertEqual(qa.expand_responses(["@" + str(response)], derived, receipts), ["-D", "ICHART_COORDINATED_STAGING_QA", "-DDEBUG"])
            self.assertEqual(receipts[str(response.resolve())], hashlib.sha256(response.read_bytes()).hexdigest())
            outside = root / "outside.rsp"; outside.write_text("-DDEBUG")
            with self.assertRaises(ValueError): qa.expand_responses(["@" + str(outside)], derived, {})
            response.write_text("@" + str(response))
            with self.assertRaises(ValueError): qa.expand_responses(["@" + str(response)], derived, {})

    def testResultBundleInventoryDetectsMutationAndRejectsSymlinks(self):
        with tempfile.TemporaryDirectory(prefix="ichart-qa-result-fixture-") as directory:
            bundle = Path(directory) / "qa.xcresult"; bundle.mkdir(); data = bundle / "data"; data.write_bytes(b"first")
            first = qa.result_bundle_hashes(bundle); data.write_bytes(b"second")
            self.assertNotEqual(first, qa.result_bundle_hashes(bundle))
            (bundle / "link").symlink_to(data)
            with self.assertRaises(ValueError): qa.result_bundle_hashes(bundle)

    def testCopiedGenericFunctionsRemainASTIdenticalToStrictProductionGate(self):
        copied, strict = functions(RUNNER), functions(PRODUCTION)
        names = ("build_environment", "run", "file_hashes", "require_clean_head", "source_manifest",
                 "expand_responses", "bind_swift_inputs", "result_bundle_hashes")
        for name in names:
            with self.subTest(name=name): self.assertEqual(ast.dump(copied[name], include_attributes=False), ast.dump(strict[name], include_attributes=False))
        for name in ("validate_compiler_commands", "validate_results"):
            actual, reference = copy.deepcopy(copied[name]), copy.deepcopy(strict[name])
            for node, expected in ((actual, "coordinated-staging-qa"), (reference, "production-paid")):
                arguments = node.args.posonlyargs + node.args.args
                default_index = [arg.arg for arg in arguments].index("lane") - (len(arguments) - len(node.args.defaults))
                self.assertEqual(ast.literal_eval(node.args.defaults[default_index]), expected)
                node.args.defaults[default_index] = ast.Constant(value="reviewed-lane-policy")
            with self.subTest(name=name): self.assertEqual(ast.dump(actual, include_attributes=False), ast.dump(reference, include_attributes=False))

    def testCopiedFunctionDependenciesResolveToQAPolicyAndNoImportedModuleIsMutated(self):
        for function, dependencies in ((qa.validate_compiler_commands, ("expected_defines", "selected_sources", "source_manifest", "bind_swift_inputs", "expand_responses")),
                                       (qa.validate_results, ("selected_classes",)), (qa.expand_responses, ("file_hashes",)), (qa.run, ("build_environment",))):
            self.assertIs(function.__globals__, vars(qa))
            for name in dependencies: self.assertIs(function.__globals__[name], getattr(qa, name))
        self.assertIs(qa.expected_defines.__globals__["recipe"], recipe)
        self.assertIs(qa.make_spec.__globals__["recipe"], recipe)
        for path in (RUNNER, ROOT / "scripts/prepare_coordinated_staging_qa_project.py"):
            for node in ast.walk(ast.parse(path.read_text())):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                    self.assertNotIn(node.func.id, {"exec", "eval", "setattr"})
                if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                    self.assertFalse(any(isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name)
                                         and target.value.id in {"recipe", "native", "base", "production"} for target in targets))


if __name__ == "__main__":
    unittest.main()
