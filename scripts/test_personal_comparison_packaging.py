import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PersonalComparisonPackagingTests(unittest.TestCase):
    def run_script(self, root, *, configuration="Debug", enabled="NO", source=True, anchors=False):
        package = root / "source"
        if source:
            package.mkdir(exist_ok=True)
            (package / "manifest.json").write_text("unit fixture")
            model = package / "PersonalVisualEncoderResearch.mlpackage"
            model.mkdir(exist_ok=True)
            (model / "model").write_text("unit fixture")
            (package / "private-profile.json").write_text("must not be embedded")
            if anchors:
                (package / "public-anchors.json").write_text("public anchor fixture")
        env = dict(os.environ, TARGET_BUILD_DIR=str(root / "build"),
                   UNLOCALIZED_RESOURCES_FOLDER_PATH="iChart.app", CONFIGURATION=configuration,
                   ICHART_INCLUDE_PERSONAL_ML_COMPARISON=enabled, ICHART_PERSONAL_ML_ARTIFACT_DIR=str(package))
        script = Path(__file__).with_name("embed_personal_comparison.sh")
        result = subprocess.run(["/bin/sh", str(script)], env=env, capture_output=True, text=True)
        return result, root / "build/iChart.app/PersonalMLComparison"

    def test_default_debug_and_release_do_not_embed(self):
        for config in ("Debug", "Release"):
            with self.subTest(config=config), tempfile.TemporaryDirectory() as directory:
                result, target = self.run_script(Path(directory), configuration=config)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(target.exists())

    def test_release_rejects_explicit_opt_in(self):
        with tempfile.TemporaryDirectory() as directory:
            result, target = self.run_script(Path(directory), configuration="Release", enabled="YES")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Debug-only", result.stderr)
            self.assertFalse(target.exists())

    def test_debug_copies_only_manifest_and_model_not_private_data(self):
        with tempfile.TemporaryDirectory() as directory:
            result, target = self.run_script(Path(directory), enabled="YES")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({p.name for p in target.iterdir()}, {"manifest.json", "PersonalVisualEncoderResearch.mlpackage"})

    def test_missing_opted_in_model_fails_build(self):
        with tempfile.TemporaryDirectory() as directory:
            result, _ = self.run_script(Path(directory), enabled="YES", source=False)
            self.assertNotEqual(result.returncode, 0)

    def test_opted_in_public_anchors_are_copied_without_other_source_files(self):
        with tempfile.TemporaryDirectory() as directory:
            result, target = self.run_script(Path(directory), enabled="YES", anchors=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({p.name for p in target.iterdir()},
                             {"manifest.json", "PersonalVisualEncoderResearch.mlpackage", "public-anchors.json"})

    def test_legacy_package_cannot_silently_reuse_old_anchors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result, target = self.run_script(root, enabled="YES")
            self.assertEqual(result.returncode, 0)
            (target / "public-anchors.json").write_text("old public anchors")
            result, _ = self.run_script(root, enabled="YES")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Stale public anchors", result.stderr)
            self.assertTrue((target / "public-anchors.json").exists())

    def test_stale_artifact_requires_fresh_build_without_deleting_anything(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result, target = self.run_script(root, enabled="YES")
            self.assertEqual(result.returncode, 0)
            result, _ = self.run_script(root, enabled="NO")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Stale", result.stderr)
            self.assertTrue((target / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
