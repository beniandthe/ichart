import argparse
import json
import os
import shutil
import sys
import tempfile
from dataclasses import asdict
from pathlib import Path
from typing import Dict, Optional, Sequence

from .checkpoint import (
    load_training_checkpoint,
    require_negative_no_read_supervision,
    save_training_checkpoint,
    validate_checkpoint_corpus_binding,
)
from .calibrate import fit_writer_disjoint_model_temperature
from .contracts import load_records_jsonl, validate_dataset, validate_feature_artifacts
from .errors import ContractError, OperationRefusedError
from .evaluate import run_sealed_model_assessment
from .export_coreml import export_uncalibrated_coreml
from .manifest import build_manifest, load_manifest, validate_manifest, write_manifest
from .models.dual_view import DualViewModelConfig
from .train_pipeline import TrainingConfig, train_development_model


def _add_corpus_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--records", required=True, type=Path)
    parser.add_argument("--data-root", required=True, type=Path)


def _add_checkpoint_operation_arguments(parser: argparse.ArgumentParser) -> None:
    _add_corpus_arguments(parser)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--checkpoint", required=True, type=Path)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="ichart-recognition-ml")
    commands = root.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate-records")
    _add_corpus_arguments(validate)

    build = commands.add_parser("build-manifest")
    _add_corpus_arguments(build)
    build.add_argument("--dataset-version", required=True)
    build.add_argument("--output", required=True, type=Path)

    verify = commands.add_parser("validate-manifest")
    _add_corpus_arguments(verify)
    verify.add_argument("--manifest", required=True, type=Path)

    train = commands.add_parser("train")
    _add_corpus_arguments(train)
    train.add_argument("--manifest", required=True, type=Path)
    train.add_argument("--output-dir", required=True, type=Path)
    train.add_argument("--model-identifier", required=True)
    train.add_argument("--seed", type=int, default=17)
    train.add_argument("--epochs", type=int, default=40)
    train.add_argument("--batch-size", type=int, default=64)
    train.add_argument("--learning-rate", type=float, default=1e-3)
    train.add_argument("--weight-decay", type=float, default=1e-4)
    train.add_argument("--device", choices=("cpu", "cuda", "mps"), default="cpu")

    evaluate = commands.add_parser("evaluate")
    _add_checkpoint_operation_arguments(evaluate)
    evaluate.add_argument("--output-dir", required=True, type=Path)
    evaluate.add_argument("--batch-size", type=int, default=128)
    evaluate.add_argument(
        "--require-promotion-gate",
        action="store_true",
        help="Refuse unless true negative/no-read supervision is checkpoint-bound.",
    )

    calibrate = commands.add_parser("calibrate")
    _add_checkpoint_operation_arguments(calibrate)
    calibrate.add_argument("--output-dir", required=True, type=Path)
    calibrate.add_argument("--fit-dataset-identifier", required=True)
    calibrate.add_argument("--batch-size", type=int, default=128)

    export = commands.add_parser("export")
    _add_checkpoint_operation_arguments(export)
    export.add_argument("--output", required=True, type=Path)
    export.add_argument("--manifest-output", required=True, type=Path)
    export.add_argument("--model-identifier", required=True)
    export.add_argument("--detached-manifest-sha256", required=True)
    return root


def _validated_records(arguments: argparse.Namespace):
    records = load_records_jsonl(arguments.records)
    validate_dataset(records, require_all_splits=True)
    validate_feature_artifacts(records, arguments.data_root)
    return records


def _validated_manifest(arguments: argparse.Namespace, records):
    manifest = load_manifest(arguments.manifest)
    validate_manifest(manifest, records)
    return manifest


def _require_new_output_directory(path: Path) -> None:
    if path.exists():
        raise OperationRefusedError(
            "output_directory_exists", str(path), "operation outputs are immutable"
        )


def _publish_output_directory(path: Path, files: Dict[str, object]) -> None:
    _require_new_output_directory(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{path.name}.", dir=path.parent))
    try:
        for relative_path, value in files.items():
            target = staging / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                json.dumps(
                    value,
                    ensure_ascii=False,
                    allow_nan=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n",
                encoding="utf-8",
            )
        os.replace(staging, path)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def _train(arguments: argparse.Namespace, records, manifest) -> Dict[str, object]:
    _require_new_output_directory(arguments.output_dir)
    training_config = TrainingConfig(
        seed=arguments.seed,
        epochs=arguments.epochs,
        batch_size=arguments.batch_size,
        learning_rate=arguments.learning_rate,
        weight_decay=arguments.weight_decay,
        device=arguments.device,
        deterministic=True,
    )
    result = train_development_model(
        records,
        arguments.data_root,
        config=training_config,
        model_config=DualViewModelConfig(),
    )

    arguments.output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{arguments.output_dir.name}.", dir=arguments.output_dir.parent)
    )
    checkpoint_path = staging / "checkpoint.pt"
    try:
        metadata = save_training_checkpoint(result, checkpoint_path, arguments.model_identifier)
        receipt = {
            "status": "development-training-complete",
            "dataset_version": manifest["dataset_version"],
            "records_sha256": manifest["records_sha256"],
            "checkpoint": "checkpoint.pt",
            "checkpoint_metadata": metadata.as_dict(),
            "final_epoch_loss": result.epoch_losses[-1],
            "negative_no_read_supervision": result.has_negative_no_read_supervision,
            "promotion_eligible": False,
        }
        (staging / "training_receipt.json").write_text(
            json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        os.replace(staging, arguments.output_dir)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return {
        "checkpoint": str(arguments.output_dir / "checkpoint.pt"),
        "negative_no_read_supervision": result.has_negative_no_read_supervision,
        "ok": True,
        "promotion_eligible": False,
        "status": "development-training-complete",
    }


def _load_bound_checkpoint(arguments: argparse.Namespace, records):
    checkpoint = load_training_checkpoint(arguments.checkpoint)
    validate_checkpoint_corpus_binding(checkpoint, records)
    return checkpoint


def _evaluate(arguments: argparse.Namespace, records) -> Dict[str, object]:
    _require_new_output_directory(arguments.output_dir)
    checkpoint = _load_bound_checkpoint(arguments, records)
    if arguments.require_promotion_gate:
        require_negative_no_read_supervision(checkpoint.metadata, "evaluate.promotion_gate")
    assessment = run_sealed_model_assessment(
        records,
        arguments.data_root,
        checkpoint.model,
        batch_size=arguments.batch_size,
    )
    decoded_report = asdict(assessment.decoded_report)
    decoded_report["role"] = assessment.decoded_report.role.value
    decoded_report.update(
        {
            "top_one_accuracy": assessment.decoded_report.top_one_accuracy,
            "top_three_accuracy": assessment.decoded_report.top_three_accuracy,
            "trusted_coverage": assessment.decoded_report.trusted_coverage,
            "selective_risk": assessment.decoded_report.selective_risk,
            "review_rate": assessment.decoded_report.review_rate,
            "no_read_rate": assessment.decoded_report.no_read_rate,
            "no_read_recall": assessment.decoded_report.no_read_recall,
            "false_no_read_rate": assessment.decoded_report.false_no_read_rate,
        }
    )
    payload = {
        "checkpoint_sha256": checkpoint.artifact_sha256,
        "descriptive_factor_report": asdict(assessment.factor_report),
        "descriptive_decoded_report": decoded_report,
        "negative_no_read_supervision": checkpoint.metadata.has_negative_no_read_supervision,
        "no_read_trust_established": False,
        "promotion_eligible": False,
        "sealed_gate_receipt_produced": False,
        "status": "sealed-descriptive-evaluation-only",
    }
    _publish_output_directory(arguments.output_dir, {"evaluation.json": payload})
    return {"ok": True, "report": str(arguments.output_dir / "evaluation.json"), **payload}


def _calibrate(arguments: argparse.Namespace, records) -> Dict[str, object]:
    _require_new_output_directory(arguments.output_dir)
    checkpoint = _load_bound_checkpoint(arguments, records)
    require_negative_no_read_supervision(checkpoint.metadata, "calibrate")
    result = fit_writer_disjoint_model_temperature(
        records,
        arguments.data_root,
        checkpoint.model,
        batch_size=arguments.batch_size,
    )
    payload = {
        "checkpoint_sha256": checkpoint.artifact_sha256,
        "fit_dataset_identifier": arguments.fit_dataset_identifier,
        "temperature_fit": asdict(result),
        "negative_no_read_supervision": True,
        "promotion_eligible": False,
        "selective_thresholds_produced": False,
        "sealed_gate_receipt_produced": False,
        "status": "writer-disjoint-temperature-fit-only",
    }
    _publish_output_directory(arguments.output_dir, {"calibration_fit.json": payload})
    return {
        "ok": True,
        "report": str(arguments.output_dir / "calibration_fit.json"),
        **payload,
    }


def _export(arguments: argparse.Namespace, records) -> Dict[str, object]:
    checkpoint = _load_bound_checkpoint(arguments, records)
    if checkpoint.metadata.model_identifier != arguments.model_identifier:
        raise OperationRefusedError(
            "model_identifier_mismatch",
            "export.model_identifier",
            f"checkpoint contains {checkpoint.metadata.model_identifier}",
        )
    receipt = export_uncalibrated_coreml(
        checkpoint.model,
        arguments.output,
        arguments.manifest_output,
        arguments.model_identifier,
        arguments.detached_manifest_sha256,
    )
    return {
        "authority": "learned-shadow-only",
        "manifest": str(receipt.manifest_path),
        "model": str(receipt.model_path),
        "model_byte_count": receipt.model_byte_count,
        "model_sha256": receipt.model_sha256,
        "no_read_trust_established": False,
        "ok": True,
        "status": "uncalibrated-shadow-model-exported",
    }


def run(arguments: argparse.Namespace) -> Dict[str, object]:
    records = _validated_records(arguments)
    if arguments.command == "validate-records":
        return {"ok": True, "record_count": len(records), "status": "records-valid"}
    if arguments.command == "build-manifest":
        manifest = build_manifest(records, arguments.dataset_version)
        write_manifest(arguments.output, manifest)
        return {
            "manifest": str(arguments.output),
            "ok": True,
            "records_sha256": manifest["records_sha256"],
            "status": "manifest-written",
        }

    manifest = _validated_manifest(arguments, records)
    if arguments.command == "validate-manifest":
        return {
            "dataset_version": manifest["dataset_version"],
            "ok": True,
            "status": "manifest-valid",
        }
    if arguments.command == "train":
        return _train(arguments, records, manifest)
    if arguments.command == "evaluate":
        return _evaluate(arguments, records)
    if arguments.command == "calibrate":
        return _calibrate(arguments, records)
    if arguments.command == "export":
        return _export(arguments, records)
    raise ContractError("unknown_command", "command", str(arguments.command))


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        result = run(arguments)
    except ContractError as error:
        print(
            json.dumps(
                {
                    "error": {"code": error.code, "detail": error.detail, "path": error.path},
                    "ok": False,
                },
                sort_keys=True,
                separators=(",", ":"),
            ),
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


def entrypoint() -> None:
    raise SystemExit(main())
