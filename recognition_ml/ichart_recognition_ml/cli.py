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
    require_bound_development_selection,
    require_negative_no_read_supervision,
    save_training_checkpoint,
    validate_checkpoint_corpus_binding,
)
from .calibrate import fit_writer_disjoint_model_temperature
from .contracts import (
    canonical_json_bytes,
    load_records_jsonl,
    validate_dataset,
    validate_feature_artifacts,
)
from .errors import ContractError, OperationRefusedError
from .development_selection import (
    DevelopmentComparisonConfig,
    build_development_model_comparison,
    load_bound_development_model_selection,
)
from .evaluate import run_sealed_model_assessment
from .export_coreml import CoreMLTrainingProvenance, export_uncalibrated_coreml
from .leakage_adjudication import (
    build_leakage_cluster_receipt,
    load_canonical_json,
)
from .leakage_scan import build_leakage_scan_report
from .manifest import build_manifest, load_manifest, validate_manifest, write_manifest
from .models.factory import (
    DUAL_VIEW_MODEL_ARCHITECTURE_ID,
    MODEL_ARCHITECTURE_IDS,
)
from .study_session import import_study_session
from .train_pipeline import (
    CATEGORICAL_CLASS_REWEIGHTING_MODES,
    CATEGORICAL_CLASS_REWEIGHTING_NONE,
    TrainingConfig,
    train_development_model,
)
from .selection_contract import UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY


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

    scan = commands.add_parser(
        "scan-leakage",
        help=(
            "Exhaustively generate label-blind near-neighbor candidates for "
            "protected adjudication without qualifying the corpus."
        ),
    )
    _add_corpus_arguments(scan)
    scan.add_argument("--output-dir", required=True, type=Path)

    adjudicate = commands.add_parser(
        "finalize-leakage-adjudication",
        help=(
            "Recompute an exact scan and resolve every candidate from a "
            "dual-independent-review file into unsigned registry preparation."
        ),
    )
    _add_corpus_arguments(adjudicate)
    adjudicate.add_argument("--scan-report", required=True, type=Path)
    adjudicate.add_argument("--adjudication", required=True, type=Path)
    adjudicate.add_argument("--output-dir", required=True, type=Path)

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
    train.add_argument(
        "--model-architecture",
        choices=MODEL_ARCHITECTURE_IDS,
        default=None,
        help="Use the architecture selected by development-writer comparison.",
    )
    train.add_argument(
        "--development-selection-report",
        type=Path,
        help=(
            "Canonical development_model_comparison.json to validate and "
            "bind; when supplied, its winner selects architecture and loss."
        ),
    )
    train.add_argument("--seed", type=int, default=None)
    train.add_argument("--epochs", type=int, default=None)
    train.add_argument("--batch-size", type=int, default=None)
    train.add_argument("--learning-rate", type=float, default=None)
    train.add_argument("--weight-decay", type=float, default=None)
    train.add_argument("--device", choices=("cpu", "cuda", "mps"), default=None)
    train.add_argument(
        "--categorical-class-reweighting",
        choices=CATEGORICAL_CLASS_REWEIGHTING_MODES,
        default=None,
        help=(
            "Use the loss treatment selected by development-writer "
            "comparison; never choose it from calibration or sealed data."
        ),
    )

    compare = commands.add_parser(
        "compare-development-models",
        help=(
            "Compare frozen model families by grouped development writer "
            "without loading calibration or sealed feature bytes."
        ),
    )
    _add_corpus_arguments(compare)
    compare.add_argument("--manifest", required=True, type=Path)
    compare.add_argument("--output-dir", required=True, type=Path)
    compare.add_argument("--fold-count", type=int, default=5)
    compare.add_argument("--seed", type=int, action="append")
    compare.add_argument("--epochs", type=int, default=40)
    compare.add_argument("--batch-size", type=int, default=64)
    compare.add_argument("--learning-rate", type=float, default=1e-3)
    compare.add_argument("--weight-decay", type=float, default=1e-4)
    compare.add_argument("--device", choices=("cpu", "cuda", "mps"), default="cpu")

    evaluate = commands.add_parser("evaluate")
    _add_checkpoint_operation_arguments(evaluate)
    evaluate.add_argument("--output-dir", required=True, type=Path)
    evaluate.add_argument("--batch-size", type=int, default=128)
    evaluate.add_argument(
        "--development-selection-report",
        type=Path,
        help=(
            "Canonical grouped development-writer comparison report. It is "
            "required and exactly rebound when --require-promotion-gate is set."
        ),
    )
    evaluate.add_argument(
        "--require-promotion-gate",
        action="store_true",
        help=(
            "Refuse unless true negative/no-read supervision and the frozen "
            "development-writer model selection are checkpoint-bound."
        ),
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

    study = commands.add_parser(
        "import-study-session",
        help=(
            "Mechanically validate one complete local Recognition Study pass "
            "and stage deterministic features without creating corpus data."
        ),
    )
    study.add_argument("--study-root", required=True, type=Path)
    study.add_argument("--output-dir", required=True, type=Path)
    study.add_argument("--local-session-id")
    return root


def _validated_records(arguments: argparse.Namespace):
    # Operations share the complete metadata boundary, not feature access.
    # Training/calibration/evaluation loaders validate only their own role;
    # export needs the checkpoint and corpus commitments, not raw handwriting.
    records = load_records_jsonl(arguments.records)
    validate_dataset(records, require_all_splits=True)
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
    selection = None
    if arguments.development_selection_report is not None:
        selection = load_bound_development_model_selection(
            arguments.development_selection_report,
            records,
        )
        if (
            arguments.model_architecture is not None
            and arguments.model_architecture
            != selection.selected_architecture_id
        ):
            raise OperationRefusedError(
                "development_selection_architecture_mismatch",
                "train.model_architecture",
                f"report selected {selection.selected_architecture_id}",
            )
        if (
            arguments.categorical_class_reweighting is not None
            and arguments.categorical_class_reweighting
            != selection.selected_categorical_class_reweighting
        ):
            raise OperationRefusedError(
                "development_selection_loss_mismatch",
                "train.categorical_class_reweighting",
                "report selected "
                + selection.selected_categorical_class_reweighting,
            )
        model_architecture = selection.selected_architecture_id
        categorical_class_reweighting = (
            selection.selected_categorical_class_reweighting
        )
        selection_authority = selection.authority
        selection_report_sha256 = selection.report_sha256
        comparison_config = selection.comparison_config
        frozen_final_training_seed = comparison_config.seeds[0]
        if (
            arguments.seed is not None
            and arguments.seed != frozen_final_training_seed
        ):
            raise OperationRefusedError(
                "development_selection_seed_mismatch",
                "train.seed",
                "seed must equal the comparison report's frozen first seed "
                f"({frozen_final_training_seed})",
            )
        resolved_seed = frozen_final_training_seed
        for argument_name in (
            "epochs",
            "batch_size",
            "learning_rate",
            "weight_decay",
            "device",
        ):
            supplied = getattr(arguments, argument_name)
            selected_value = getattr(comparison_config, argument_name)
            if supplied is not None and supplied != selected_value:
                raise OperationRefusedError(
                    "development_selection_training_config_mismatch",
                    f"train.{argument_name}",
                    f"report selected {selected_value}",
                )
        resolved_epochs = comparison_config.epochs
        resolved_batch_size = comparison_config.batch_size
        resolved_learning_rate = comparison_config.learning_rate
        resolved_weight_decay = comparison_config.weight_decay
        resolved_device = comparison_config.device
    else:
        model_architecture = (
            arguments.model_architecture
            or DUAL_VIEW_MODEL_ARCHITECTURE_ID
        )
        categorical_class_reweighting = (
            arguments.categorical_class_reweighting
            or CATEGORICAL_CLASS_REWEIGHTING_NONE
        )
        selection_authority = UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
        selection_report_sha256 = None
        defaults = TrainingConfig()
        resolved_seed = arguments.seed if arguments.seed is not None else defaults.seed
        resolved_epochs = (
            arguments.epochs if arguments.epochs is not None else defaults.epochs
        )
        resolved_batch_size = (
            arguments.batch_size
            if arguments.batch_size is not None
            else defaults.batch_size
        )
        resolved_learning_rate = (
            arguments.learning_rate
            if arguments.learning_rate is not None
            else defaults.learning_rate
        )
        resolved_weight_decay = (
            arguments.weight_decay
            if arguments.weight_decay is not None
            else defaults.weight_decay
        )
        resolved_device = (
            arguments.device if arguments.device is not None else defaults.device
        )
    training_config = TrainingConfig(
        seed=resolved_seed,
        epochs=resolved_epochs,
        batch_size=resolved_batch_size,
        learning_rate=resolved_learning_rate,
        weight_decay=resolved_weight_decay,
        device=resolved_device,
        deterministic=True,
        categorical_class_reweighting=(
            categorical_class_reweighting
        ),
    )
    result = train_development_model(
        records,
        arguments.data_root,
        config=training_config,
        model_architecture_id=model_architecture,
        development_selection_authority=selection_authority,
        development_selection_report_sha256=selection_report_sha256,
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
            "model_architecture_id": result.model_architecture_id,
            "development_selection_authority": (
                result.development_selection_authority
            ),
            "development_selection_report_sha256": (
                result.development_selection_report_sha256
            ),
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
        "model_architecture_id": result.model_architecture_id,
        "development_selection_authority": (
            result.development_selection_authority
        ),
        "development_selection_report_sha256": (
            result.development_selection_report_sha256
        ),
        "negative_no_read_supervision": result.has_negative_no_read_supervision,
        "ok": True,
        "promotion_eligible": False,
        "status": "development-training-complete",
    }


def _compare_development_models(
    arguments: argparse.Namespace,
    records,
) -> Dict[str, object]:
    seeds = tuple(arguments.seed) if arguments.seed else (17, 29, 43)
    report = build_development_model_comparison(
        records,
        arguments.data_root,
        DevelopmentComparisonConfig(
            fold_count=arguments.fold_count,
            seeds=seeds,
            epochs=arguments.epochs,
            batch_size=arguments.batch_size,
            learning_rate=arguments.learning_rate,
            weight_decay=arguments.weight_decay,
            device=arguments.device,
        ),
    )
    _publish_output_directory(
        arguments.output_dir,
        {"development_model_comparison.json": report},
    )
    return {
        "authority": report["authority"],
        "ok": True,
        "promotion_eligible": False,
        "report": str(
            arguments.output_dir / "development_model_comparison.json"
        ),
        "selected_candidate_id": report["selected_candidate_id"],
        "status": report["status"],
    }


def _load_bound_checkpoint(arguments: argparse.Namespace, records):
    checkpoint = load_training_checkpoint(arguments.checkpoint)
    validate_checkpoint_corpus_binding(checkpoint, records)
    return checkpoint


def _require_checkpoint_selection_report(checkpoint, records, report_path: Optional[Path]):
    require_bound_development_selection(
        checkpoint.metadata,
        "evaluate.promotion_gate",
    )
    if report_path is None:
        raise OperationRefusedError(
            "development_selection_report_required",
            "evaluate.development_selection_report",
            "promotion evaluation must revalidate the exact report bound to the checkpoint",
        )
    selection = load_bound_development_model_selection(report_path, records)
    metadata = checkpoint.metadata
    config = metadata.training_config
    comparison = selection.comparison_config
    mismatches = []
    if metadata.development_selection_report_sha256 != selection.report_sha256:
        mismatches.append("report_sha256")
    if metadata.model_architecture_id != selection.selected_architecture_id:
        mismatches.append("model_architecture_id")
    if (
        config.categorical_class_reweighting
        != selection.selected_categorical_class_reweighting
    ):
        mismatches.append("categorical_class_reweighting")
    if config.seed != comparison.seeds[0]:
        mismatches.append("seed")
    for field in (
        "epochs",
        "batch_size",
        "learning_rate",
        "weight_decay",
        "device",
    ):
        if getattr(config, field) != getattr(comparison, field):
            mismatches.append(field)
    if mismatches:
        raise OperationRefusedError(
            "checkpoint_development_selection_mismatch",
            "evaluate.development_selection_report",
            "checkpoint differs from its bound comparison report: "
            + ", ".join(mismatches),
        )


def _evaluate(arguments: argparse.Namespace, records) -> Dict[str, object]:
    _require_new_output_directory(arguments.output_dir)
    checkpoint = _load_bound_checkpoint(arguments, records)
    development_selection_revalidated = False
    if (
        arguments.require_promotion_gate
        or arguments.development_selection_report is not None
    ):
        _require_checkpoint_selection_report(
            checkpoint,
            records,
            arguments.development_selection_report,
        )
        development_selection_revalidated = True
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
        "development_selection_authority": (
            checkpoint.metadata.development_selection_authority
        ),
        "development_selection_report_sha256": (
            checkpoint.metadata.development_selection_report_sha256
        ),
        "development_selection_revalidated": (
            development_selection_revalidated
        ),
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
        CoreMLTrainingProvenance(
            checkpoint_contract_version=(
                checkpoint.metadata.checkpoint_contract_version
            ),
            checkpoint_artifact_sha256=checkpoint.artifact_sha256,
            checkpoint_artifact_byte_count=checkpoint.artifact_byte_count,
            model_architecture_id=checkpoint.metadata.model_architecture_id,
            development_records_sha256=(
                checkpoint.metadata.development_records_sha256
            ),
            development_sample_count=(
                checkpoint.metadata.development_sample_count
            ),
            development_writer_count=(
                checkpoint.metadata.development_writer_count
            ),
            development_selection_authority=(
                checkpoint.metadata.development_selection_authority
            ),
            development_selection_report_sha256=(
                checkpoint.metadata.development_selection_report_sha256
            ),
        ),
    )
    return {
        "authority": "learned-shadow-only",
        "manifest": str(receipt.manifest_path),
        "model": str(receipt.model_path),
        "model_byte_count": receipt.model_byte_count,
        "model_sha256": receipt.model_sha256,
        "training_checkpoint_sha256": checkpoint.artifact_sha256,
        "development_records_sha256": (
            checkpoint.metadata.development_records_sha256
        ),
        "model_architecture": checkpoint.metadata.model_architecture_id,
        "development_selection_authority": (
            checkpoint.metadata.development_selection_authority
        ),
        "development_selection_report_sha256": (
            checkpoint.metadata.development_selection_report_sha256
        ),
        "coreml_parity_maximum_absolute_error": (
            receipt.parity_evidence.maximum_absolute_error
        ),
        "inference_compute_units": receipt.parity_evidence.inference_compute_units,
        "no_read_trust_established": False,
        "ok": True,
        "status": "uncalibrated-shadow-model-exported",
    }


def run(arguments: argparse.Namespace) -> Dict[str, object]:
    if arguments.command == "import-study-session":
        receipt = import_study_session(
            arguments.study_root,
            arguments.output_dir,
            arguments.local_session_id,
        )
        return {
            "authority": "mechanical-validation-only",
            "capture_count": receipt.capture_count,
            "corpus_eligible": False,
            "ok": True,
            "receipt": str(receipt.receipt_path),
            "receipt_sha256": receipt.receipt_sha256,
            "status": "validated-local-engineering-session",
        }

    if arguments.command == "scan-leakage":
        records = load_records_jsonl(arguments.records)
        report = build_leakage_scan_report(records, arguments.data_root)
        _publish_output_directory(
            arguments.output_dir,
            {"leakage_scan.json": report},
        )
        return {
            "authority": report["authority"],
            "candidate_pair_count": report["candidate_pair_count"],
            "corpus_qualified": False,
            "ok": True,
            "report": str(arguments.output_dir / "leakage_scan.json"),
            "status": report["status"],
        }

    if arguments.command == "finalize-leakage-adjudication":
        records = load_records_jsonl(arguments.records)
        recomputed_report = build_leakage_scan_report(records, arguments.data_root)
        supplied_report = load_canonical_json(arguments.scan_report)
        if canonical_json_bytes(supplied_report) != canonical_json_bytes(recomputed_report):
            raise ContractError(
                "scan_report_mismatch",
                str(arguments.scan_report),
                "the supplied report does not match a fresh scan of the exact records and artifacts",
            )
        adjudication = load_canonical_json(arguments.adjudication)
        receipt = build_leakage_cluster_receipt(recomputed_report, adjudication)
        _publish_output_directory(
            arguments.output_dir,
            {"leakage_cluster_receipt.json": receipt},
        )
        return {
            "authority": receipt["authority"],
            "cluster_count": receipt["cluster_count"],
            "corpus_qualified": False,
            "ok": True,
            "receipt": str(arguments.output_dir / "leakage_cluster_receipt.json"),
            "registry_signed": False,
            "status": receipt["status"],
        }

    records = _validated_records(arguments)
    if arguments.command in (
        "validate-records", "build-manifest", "validate-manifest"
    ):
        validate_feature_artifacts(records, arguments.data_root)
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
    if arguments.command == "compare-development-models":
        return _compare_development_models(arguments, records)
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
