#!/usr/bin/env python3
"""Audit Smart Chart chord-entry diagnostics against rendered chart chords."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_BUNDLE_ID = "com.smartchart.app"
DEFAULT_CHART_TITLE = "Chord Writing Test Chart"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare rendered ChordEvent IDs in the simulator state with chord-entry diagnostics."
    )
    parser.add_argument(
        "--bundle-id",
        default=DEFAULT_BUNDLE_ID,
        help=f"App bundle id. Defaults to {DEFAULT_BUNDLE_ID}.",
    )
    parser.add_argument(
        "--simulator",
        metavar="DEVICE",
        help="Simulator UDID. Defaults to booted.",
    )
    parser.add_argument(
        "--app-data",
        type=Path,
        help="Explicit simulator app data container path.",
    )
    parser.add_argument(
        "--chart-title",
        default=DEFAULT_CHART_TITLE,
        help=f"Chart title to audit. Defaults to {DEFAULT_CHART_TITLE!r}.",
    )
    parser.add_argument(
        "--chart-id",
        help="Exact chart id to audit. When omitted, selected matching chart is preferred.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero when rendered chord events are missing diagnostics.",
    )
    parser.add_argument(
        "--reconcile-missing",
        action="store_true",
        help="Append fallback diagnostics for rendered chord events missing live diagnostic rows.",
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="Print one concise row per diagnostic event for the audited chart.",
    )
    parser.add_argument(
        "--scores",
        type=int,
        default=0,
        metavar="N",
        help="With --details, include the top N candidate scores for each diagnostic row.",
    )
    return parser.parse_args()


def app_data_container(bundle_id: str, simulator: str | None) -> Path:
    command = ["xcrun", "simctl", "get_app_container"]
    if simulator:
        command.append(simulator)
    else:
        command.append("booted")
    command.extend([bundle_id, "data"])
    output = subprocess.check_output(command, text=True).strip()
    return Path(output)


def load_json(path: Path) -> dict[str, Any]:
    with path.open() as file:
        return json.load(file)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []

    events = []
    with path.open() as file:
        for line in file:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def chart_matches(snapshot: dict[str, Any], title: str) -> list[dict[str, Any]]:
    charts = snapshot.get("charts", [])
    return [chart for chart in charts if chart.get("title") == title]


def chart_updated_sort_key(chart: dict[str, Any]) -> str:
    return chart.get("updatedAt") or chart.get("createdAt") or ""


def chart_for_audit(
    snapshot: dict[str, Any],
    title: str,
    chart_id: str | None,
) -> tuple[dict[str, Any] | None, int]:
    charts = snapshot.get("charts", [])
    if chart_id:
        matches = [chart for chart in charts if chart.get("id") == chart_id]
        return (matches[0], 1) if matches else (None, 0)

    matches = chart_matches(snapshot, title)
    if not matches:
        return None, 0

    selected_chart_id = snapshot.get("selectedChartID")
    for chart in matches:
        if chart.get("id") == selected_chart_id:
            return chart, len(matches)

    return max(matches, key=chart_updated_sort_key), len(matches)


def chord_events(chart: dict[str, Any]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for system in chart.get("systems", []):
        for measure in system.get("measures", []):
            for event in measure.get("chordEvents", []):
                event = dict(event)
                event["_measureID"] = measure.get("id")
                event["_measureIndex"] = measure.get("index")
                events.append(event)
    return events


def event_label(event: dict[str, Any]) -> str:
    raw_input = event.get("rawInput") or "?"
    measure_index = event.get("_measureIndex")
    beat = event.get("startPosition", {}).get("beat")
    return f"{event.get('id')} measure={measure_index} beat={beat} raw={raw_input}"


def diagnostic_sort_key(event: dict[str, Any]) -> tuple[int, str, str]:
    measure_index = event.get("measureIndex")
    timestamp = event.get("timestamp") or ""
    chord_event_id = event.get("chordEventID") or ""
    return (
        measure_index if isinstance(measure_index, int) else 0,
        timestamp,
        chord_event_id,
    )


def latest_diagnostics_by_chord_event(
    events: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], int]:
    latest_by_id: dict[str, dict[str, Any]] = {}
    superseded_count = 0

    for event in sorted(events, key=diagnostic_sort_key):
        chord_event_id = event.get("chordEventID")
        if not chord_event_id:
            continue

        if chord_event_id in latest_by_id:
            superseded_count += 1
        latest_by_id[chord_event_id] = event

    return list(latest_by_id.values()), superseded_count


def short_text(text: Any, fallback: str = "?") -> str:
    if not isinstance(text, str) or not text:
        return fallback
    return text


def format_confidence(value: Any) -> str:
    return f"{value:.2f}" if isinstance(value, (float, int)) else "?"


def format_gap(value: Any) -> str:
    return f"{value:.2f}" if isinstance(value, (float, int)) else "-"


def format_scores(candidate_scores: list[dict[str, Any]], limit: int) -> str:
    if limit <= 0 or not candidate_scores:
        return ""

    pairs = []
    for score in candidate_scores[:limit]:
        text = score.get("displayText") or score.get("text") or "?"
        confidence = format_confidence(score.get("confidence"))
        pairs.append(f"{text}:{confidence}")
    return " scores=[" + ", ".join(pairs) + "]"


def format_metrics(metrics: dict[str, Any] | None) -> str:
    if not metrics:
        return ""

    composition = metrics.get("compositionMetrics") or {}

    def ms(key: str) -> str:
        value = metrics.get(key)
        return "?" if value is None else f"{value:.0f}ms"

    generated = composition.get("generatedSequenceCount")
    max_generated = composition.get("maxGeneratedSequences")
    if generated is None or max_generated is None:
        sequence_summary = "seq=?"
    else:
        limit = " limit" if composition.get("hitGeneratedSequenceLimit") else ""
        sequence_summary = f"seq={generated}/{max_generated}{limit}"

    return (
        " metrics=["
        f"cluster={ms('clusterMilliseconds')}, "
        f"glyph={ms('glyphMilliseconds')}, "
        f"context={ms('contextualGlyphMilliseconds')}, "
        f"compose={ms('composeMilliseconds')}, "
        f"semantic={ms('semanticMilliseconds')}, "
        f"match={ms('matchMilliseconds')}, "
        f"ocr={ms('ocrMilliseconds')}, "
        f"{sequence_summary}"
        "]"
    )


def format_symbol_ledger(ledger: dict[str, Any] | None) -> str:
    if not ledger:
        return ""

    stable_symbols = ledger.get("stableSymbols") or []
    running_prefixes = ledger.get("runningPrefixes") or []
    final_candidate = ledger.get("finalCandidateDisplayText") or ledger.get("finalCandidateText") or "-"

    stable_text_parts = []
    reason_counts = Counter()
    for symbol in stable_symbols:
        candidates = symbol.get("candidates") or []
        best = candidates[0].get("text") if candidates else "?"
        stable_text_parts.append(best or "?")
        reason = symbol.get("stabilityReason") or "?"
        reason_counts[reason] += 1

    supported_prefixes = [
        prefix for prefix in running_prefixes
        if prefix.get("supportedDisplayTexts")
    ]
    if supported_prefixes:
        prefix_summary = "|".join(supported_prefixes[-1].get("supportedDisplayTexts")[:3])
    elif running_prefixes:
        final_prefix = running_prefixes[-1]
        prefix_summary = final_prefix.get("displayText") or final_prefix.get("text")
    else:
        prefix_summary = "-"

    reason_summary = ",".join(
        f"{reason}:{count}" for reason, count in sorted(reason_counts.items())
    ) or "-"

    return (
        " ledger=["
        f"stable={len(stable_symbols)}, "
        f"text={''.join(stable_text_parts) or '-'}, "
        f"prefix={prefix_summary or '-'}, "
        f"final={final_candidate}, "
        f"reasons={reason_summary}"
        "]"
    )


def format_symbol_ledger_assessment(assessment: dict[str, Any] | None) -> str:
    if not assessment:
        return ""

    agreement = assessment.get("agreement") or "?"
    support_count = assessment.get("supportCount")
    support = support_count if isinstance(support_count, int) else "?"
    signals = assessment.get("supportingSignals") or []
    conflicts = assessment.get("competingDisplayTexts") or []
    unresolved = assessment.get("unresolvedOverlapCount")
    signal_summary = "|".join(signals[:4]) or "-"
    conflict_summary = "|".join(conflicts[:3]) or "-"
    unresolved_summary = unresolved if isinstance(unresolved, int) else "?"

    return (
        " ledgerAssessment=["
        f"agreement={agreement}, "
        f"support={support}, "
        f"signals={signal_summary}, "
        f"conflicts={conflict_summary}, "
        f"unresolved={unresolved_summary}"
        "]"
    )


def format_primary_symbol_ledger_assessment(assessment: dict[str, Any] | None) -> str:
    if not assessment:
        return ""

    agreement = assessment.get("agreement") or "?"
    primary = assessment.get("primaryDisplayText") or "-"
    support_count = assessment.get("supportCount")
    support = support_count if isinstance(support_count, int) else "?"
    conflicts = assessment.get("competingDisplayTexts") or []
    conflict_summary = "|".join(conflicts[:3]) or "-"
    return (
        " primaryLedgerAssessment=["
        f"primary={primary}, "
        f"agreement={agreement}, "
        f"support={support}, "
        f"conflicts={conflict_summary}"
        "]"
    )


def print_diagnostic_details(chart_diagnostics: list[dict[str, Any]], score_limit: int) -> None:
    if not chart_diagnostics:
        print("\nDiagnostic detail: none")
        return

    print("\nDiagnostic detail:")
    for index, event in enumerate(sorted(chart_diagnostics, key=diagnostic_sort_key), start=1):
        resolution = short_text(event.get("resolution"))
        accepted = short_text(event.get("acceptedText"))
        rendered = short_text(event.get("renderedDisplayText"))
        best = short_text(event.get("bestCandidateText"), fallback="-")
        confidence = format_confidence(event.get("confidence"))
        gap = format_gap(event.get("confidenceGap"))
        measure = event.get("measureIndex")
        measure_label = measure + 1 if isinstance(measure, int) else "?"
        close_marker = " close" if event.get("wasCloseRace") else ""
        trust = short_text(event.get("recognitionTrustSource"), fallback="-")
        agreement = short_text(event.get("recognitionAgreementLevel"), fallback="-")
        ocr = short_text(event.get("ocrBestCandidateText"), fallback="-")
        primary_action = short_text(event.get("primaryRecognitionAction"), fallback="-")
        primary_accepted = short_text(event.get("primaryAcceptedText"), fallback="-")
        score_suffix = format_scores(event.get("candidateScores") or [], score_limit)
        metrics_suffix = format_metrics(event.get("recognitionMetrics"))
        ledger_suffix = format_symbol_ledger(event.get("symbolLedger"))
        ledger_assessment_suffix = format_symbol_ledger_assessment(
            event.get("symbolLedgerAssessment")
        )
        primary_ledger_assessment_suffix = format_primary_symbol_ledger_assessment(
            event.get("primarySymbolLedgerAssessment")
        )
        print(
            f"  {index:02d}. m{measure_label} {resolution}{close_marker}: "
            f"accepted={accepted} rendered={rendered} best={best} "
            f"confidence={confidence} gap={gap} trust={trust} "
            f"agreement={agreement} ocr={ocr} "
            f"primary={primary_action}:{primary_accepted}{score_suffix}{metrics_suffix}"
            f"{ledger_suffix}{ledger_assessment_suffix}{primary_ledger_assessment_suffix}"
        )


def append_jsonl(path: Path, events: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as file:
        for event in events:
            file.write(json.dumps(event, sort_keys=True, separators=(",", ":")))
            file.write("\n")


def fallback_diagnostic_event(
    chart: dict[str, Any],
    chord_event: dict[str, Any],
) -> dict[str, Any]:
    display_text = chord_event.get("rawInput") or "?"
    return {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "chartID": chart.get("id"),
        "chartTitle": chart.get("title") or "",
        "measureID": chord_event.get("_measureID"),
        "measureIndex": chord_event.get("_measureIndex") or 0,
        "chordEventID": chord_event.get("id"),
        "resolution": "reconciledRenderedChord",
        "acceptedText": display_text,
        "previousRenderedDisplayText": None,
        "renderedDisplayText": display_text,
        "bestCandidateText": display_text,
        "suggestedCandidateTexts": [display_text],
        "rawCandidates": [display_text],
        "candidateScores": [],
        "confidence": 0,
        "recognitionReason": "Reconciled rendered chord event missing live diagnostic.",
        "wasCloseRace": False,
        "confidenceGap": None,
        "targetFraction": None,
        "ocrCandidates": None,
        "ocrBestCandidateText": None,
        "ocrRawTexts": None,
        "recognitionTrustSource": None,
        "recognitionAgreementLevel": None,
        "primaryRecognitionAction": None,
        "primaryAcceptedText": None,
        "primaryRecognitionReason": None,
        "primaryWasCloseRace": None,
        "primaryConfidenceGap": None,
        "recognitionMetrics": None,
        "symbolLedger": None,
        "symbolLedgerAssessment": None,
        "primarySymbolLedgerAssessment": None,
    }


def main() -> int:
    args = parse_args()
    try:
        app_data = args.app_data or app_data_container(args.bundle_id, args.simulator)
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        print(f"Could not locate app container: {error}", file=sys.stderr)
        return 2

    smart_chart_dir = app_data / "Library" / "Application Support" / "SmartChart"
    state_path = smart_chart_dir / "library-state.json"
    diagnostics_path = smart_chart_dir / "chord-entry-diagnostics.jsonl"

    if not state_path.exists():
        print(f"Missing library state: {state_path}", file=sys.stderr)
        return 2

    snapshot = load_json(state_path)
    chart, matching_chart_count = chart_for_audit(snapshot, args.chart_title, args.chart_id)
    diagnostics = load_jsonl(diagnostics_path)
    if chart is None:
        if args.chart_id:
            print(f"No chart with id {args.chart_id!r} in {state_path}")
        else:
            print(f"No chart titled {args.chart_title!r} in {state_path}")
        print(f"Diagnostics events on disk: {len(diagnostics)}")
        return 0

    rendered_events = chord_events(chart)
    rendered_ids = [event.get("id") for event in rendered_events if event.get("id")]
    rendered_id_set = set(rendered_ids)
    chart_id = chart.get("id")
    chart_title = chart.get("title")
    chart_diagnostics = [
        event for event in diagnostics
        if event.get("chartID") == chart_id
    ]
    active_chart_diagnostics = [
        event for event in chart_diagnostics
        if event.get("chordEventID") in rendered_id_set
    ]
    latest_active_chart_diagnostics, superseded_active_count = latest_diagnostics_by_chord_event(
        active_chart_diagnostics
    )
    stale_title_diagnostics = [
        event for event in diagnostics
        if event.get("chartTitle") == chart_title and event.get("chartID") != chart_id
    ]
    logged_ids = []
    for event in latest_active_chart_diagnostics:
        chord_event_id = event.get("chordEventID")
        if chord_event_id and chord_event_id not in logged_ids:
            logged_ids.append(chord_event_id)
    logged_id_set = set(logged_ids)
    missing_ids = [event_id for event_id in rendered_ids if event_id not in logged_id_set]
    stale_ids = [
        event.get("chordEventID") for event in chart_diagnostics
        if event.get("chordEventID") and event.get("chordEventID") not in rendered_id_set
    ]
    stale_ids = list(dict.fromkeys(stale_ids))
    resolutions = Counter(event.get("resolution", "unknown") for event in latest_active_chart_diagnostics)

    print(f"App data: {app_data}")
    print(f"Chart: {chart_title} ({chart_id})")
    if not args.chart_id and matching_chart_count > 1:
        print(f"Matching charts with title: {matching_chart_count} (selected/newest chart audited)")
    print(f"Rendered chord events: {len(rendered_ids)}")
    print(f"Diagnostic events for active chords: {len(latest_active_chart_diagnostics)}")
    if superseded_active_count:
        print(f"Superseded active diagnostic events: {superseded_active_count}")
    if len(active_chart_diagnostics) != len(chart_diagnostics):
        print(f"Superseded diagnostic events for chart: {len(chart_diagnostics) - len(active_chart_diagnostics)}")
    if stale_title_diagnostics:
        print(f"Stale diagnostics with same chart title: {len(stale_title_diagnostics)}")
    print("Resolution counts: " + (", ".join(f"{key}={value}" for key, value in sorted(resolutions.items())) or "none"))

    if args.details:
        print_diagnostic_details(latest_active_chart_diagnostics, args.scores)

    if missing_ids:
        print("\nMissing diagnostics:")
        rendered_by_id = {event.get("id"): event for event in rendered_events}
        for event_id in missing_ids:
            print(f"  - {event_label(rendered_by_id[event_id])}")
    else:
        print("\nMissing diagnostics: none")

    if args.reconcile_missing and missing_ids:
        rendered_by_id = {event.get("id"): event for event in rendered_events}
        fallback_events = [
            fallback_diagnostic_event(chart, rendered_by_id[event_id])
            for event_id in missing_ids
        ]
        append_jsonl(diagnostics_path, fallback_events)
        print(f"\nReconciled missing diagnostics: {len(fallback_events)}")
        print(f"Diagnostic events after reconcile: {len(chart_diagnostics) + len(fallback_events)}")
        missing_ids = []

    if stale_ids:
        print("\nStale diagnostics not present in current chart:")
        for event_id in stale_ids:
            print(f"  - {event_id}")
    else:
        print("Stale diagnostics: none")

    if args.strict and missing_ids:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
