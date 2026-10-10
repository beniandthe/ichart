"""Bind the frozen residual comparison to a research-only Core ML/Swift packet."""

import argparse
import hashlib
import json
from pathlib import Path

from .personal_encoder_export import export
from .personal_residual import VERSION


def run(checkpoint: Path, source: Path, residual_report: Path, output: Path):
    result = json.loads(residual_report.read_text())
    checkpoint_report = json.loads((checkpoint / "report.json").read_text())
    if (result.get("version") != VERSION or result.get("productionEligible") is not False
            or result.get("reservedWritersEvaluated") is not False
            or result["weightsSHA256"] != checkpoint_report["weightsSHA256"]
            or result["trainingReportSHA256"] != hashlib.sha256((checkpoint / "report.json").read_bytes()).hexdigest()):
        raise ValueError("Residual experiment/checkpoint mismatch")
    export(checkpoint, source, output, include_generic=True, all_characters=True)
    packet_path = output / "swift-parity.json"
    packet = json.loads(packet_path.read_text())
    packet["encoderVersion"] = packet["version"]
    packet["version"] = "personal-residual-parity-v1"
    packet["residualVersion"] = VERSION
    packet["residualReportSHA256"] = hashlib.sha256(residual_report.read_bytes()).hexdigest()
    packet["queries"] = [{"identity": row["queryID"], "ranks": row["correctionRanks"]}
                         for row in result["characterTask"]["rows"]]
    if len(packet["queries"]) != 776 or len({r["identity"] for r in packet["queries"]}) != 776:
        raise ValueError("Incomplete residual parity queries")
    packet_path.write_text(json.dumps(packet, indent=2, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--residual-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.checkpoint.resolve(), args.source.resolve(), args.residual_report.resolve(), args.output.resolve())
