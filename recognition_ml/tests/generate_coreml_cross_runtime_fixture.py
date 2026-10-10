import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path

from corpus_v2_fixture import record_mapping, valid_feature_payloads
from ichart_recognition_ml.cli import main as recognition_cli
from ichart_recognition_ml.models.factory import MODEL_ARCHITECTURE_IDS
from ichart_recognition_ml.schema import SPLITS


DETACHED_MANIFEST_SHA256 = "d" * 64


def run_cli(arguments):
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        code = recognition_cli(arguments)
    if code != 0:
        raise RuntimeError(stderr.getvalue() or stdout.getvalue() or f"CLI exited {code}")
    return json.loads(stdout.getvalue())


def write_fixture(output_root: Path, model_architecture: str):
    if model_architecture not in MODEL_ARCHITECTURE_IDS:
        raise RuntimeError(f"unsupported architecture: {model_architecture}")
    if output_root.exists():
        raise RuntimeError(f"output already exists: {output_root}")
    output_root.mkdir(parents=True)
    data_root = output_root / "data"
    records_path = output_root / "records.jsonl"
    corpus_manifest_path = output_root / "corpus.manifest.json"
    training_output = output_root / "training"
    compiled_model_path = output_root / "ChordInk.mlmodelc"
    model_manifest_path = output_root / "ChordInk.manifest.json"

    records = []
    for index, split in enumerate(SPLITS, start=1):
        trajectory, raster = valid_feature_payloads(index)
        trajectory_relative = f"trajectory/{index}.f32le"
        raster_relative = f"raster/{index}.u8"
        for relative, payload in (
            (trajectory_relative, trajectory),
            (raster_relative, raster),
        ):
            path = data_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
        records.append(
            record_mapping(
                index,
                split,
                "G7",
                trajectory={
                    "relative_path": trajectory_relative,
                    "sha256": hashlib.sha256(trajectory).hexdigest(),
                    "byte_count": len(trajectory),
                    "encoding": "float32-le",
                },
                raster={
                    "relative_path": raster_relative,
                    "sha256": hashlib.sha256(raster).hexdigest(),
                    "byte_count": len(raster),
                    "encoding": "uint8-gray",
                },
            )
        )

    records_path.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\n" for record in records),
        encoding="utf-8",
    )
    run_cli(
        [
            "build-manifest",
            "--records",
            str(records_path),
            "--data-root",
            str(data_root),
            "--dataset-version",
            "cross-runtime-fixture-v1",
            "--output",
            str(corpus_manifest_path),
        ]
    )
    training = run_cli(
        [
            "train",
            "--manifest",
            str(corpus_manifest_path),
            "--records",
            str(records_path),
            "--data-root",
            str(data_root),
            "--output-dir",
            str(training_output),
            "--model-identifier",
            f"cross-runtime-{model_architecture}",
            "--model-architecture",
            model_architecture,
            "--epochs",
            "1",
            "--batch-size",
            "1",
        ]
    )
    exported = run_cli(
        [
            "export",
            "--manifest",
            str(corpus_manifest_path),
            "--records",
            str(records_path),
            "--data-root",
            str(data_root),
            "--checkpoint",
            str(training["checkpoint"]),
            "--output",
            str(compiled_model_path),
            "--manifest-output",
            str(model_manifest_path),
            "--model-identifier",
            f"cross-runtime-{model_architecture}",
            "--detached-manifest-sha256",
            DETACHED_MANIFEST_SHA256,
        ]
    )
    receipt = {
        "compiled_model": str(compiled_model_path),
        "detached_manifest_sha256": DETACHED_MANIFEST_SHA256,
        "manifest": str(model_manifest_path),
        "model_architecture": model_architecture,
        "model_byte_count": exported["model_byte_count"],
        "model_sha256": exported["model_sha256"],
        "parity_maximum_absolute_error": exported[
            "coreml_parity_maximum_absolute_error"
        ],
        "schema_version": "chord-ink-coreml-cross-runtime-fixture-v2",
    }
    (output_root / "fixture_receipt.json").write_text(
        json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--model-architecture",
        required=True,
        choices=MODEL_ARCHITECTURE_IDS,
    )
    arguments = parser.parse_args()
    print(
        json.dumps(
            write_fixture(arguments.output, arguments.model_architecture),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
