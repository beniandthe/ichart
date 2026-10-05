"""Package the verified public research model for an opt-in Debug build only.

Copies no trajectories, parity queries, profiles or expected chord answers.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

PACKAGE_SHA = "c51029092ea80e6d2621db4606f7051139177169dc9d036b89c9e74b2f5988f5"
WEIGHTS_SHA = "5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0"
ANCHOR_SHA = "e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed"


def package(source: Path, destination: Path, anchor_path=None):
    if destination.exists():
        raise ValueError("Use a new output directory")
    parity = json.loads((source / "swift-parity.json").read_text())
    if (parity["version"] != "personal-residual-parity-v1" or parity["researchOnly"] is not True
            or parity["includesGenericLogits"] is not True or parity["modelPackageSHA256"] != PACKAGE_SHA
            or len(parity["vocabulary"]) != 97 or len(set(parity["vocabulary"])) != 97):
        raise ValueError("Only the verified frozen public research artifact can be packaged")
    artifact = source / "PersonalVisualEncoderResearch.mlpackage"
    digest = hashlib.sha256()
    for path in sorted(artifact.rglob("*")):
        if path.is_symlink():
            raise ValueError("No package symlinks")
        if path.is_file():
            digest.update(path.relative_to(artifact).as_posix().encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode() + b"\n")
    if digest.hexdigest() != PACKAGE_SHA:
        raise ValueError("Research package differs from verified artifact")
    manifest = {"version": "personal-visual-comparison-v1", "researchOnly": True,
                "packageSHA256": PACKAGE_SHA, "weightsSHA256": WEIGHTS_SHA,
                "vocabulary": parity["vocabulary"], "featureCount": 128,
                "source": "UJI Pen Characters v2; Prat et al.; CC BY 4.0",
                "sourceURL": "https://doi.org/10.24432/C5FG8S"}
    anchor_data = None
    if anchor_path is not None:
        if anchor_path.is_symlink():
            raise ValueError("No anchor symlinks")
        anchor_data = anchor_path.read_bytes()
        if hashlib.sha256(anchor_data).hexdigest() != ANCHOR_SHA:
            raise ValueError("Only the frozen public training anchor bank can be packaged")
        bank = json.loads(anchor_data)
        if bank["encoderSHA256"] != WEIGHTS_SHA or bank["vocabulary"] != parity["vocabulary"]:
            raise ValueError("Anchor bank does not match the visual encoder")
        manifest.update(version="personal-visual-comparison-v2", anchorSHA256=ANCHOR_SHA,
                        personalLearningVersion="personal-untaught-anchor-v1")
    data = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode()
    destination.mkdir(parents=True)
    shutil.copytree(artifact, destination / artifact.name)
    (destination / "manifest.json").write_bytes(data)
    if anchor_data is not None:
        (destination / "public-anchors.json").write_bytes(anchor_data)
    print(json.dumps({"manifestSHA256": hashlib.sha256(data).hexdigest(),
                      "modelPackageSHA256": PACKAGE_SHA, "debugOnly": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--anchors", type=Path)
    args = parser.parse_args()
    package(args.source, args.destination, args.anchors)
