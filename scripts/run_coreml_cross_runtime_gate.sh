#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python_bin=${ICHART_RECOGNITION_PYTHON:-python3}
gate_root=$(mktemp -d /tmp/ichart-coreml-cross-runtime.XXXXXX)

cleanup() {
  case "$gate_root" in
    /tmp/ichart-coreml-cross-runtime.*)
      rm -rf -- "$gate_root"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

cd "$repo_root"
xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -framework CoreML \
  -framework CoreVideo \
  -framework CryptoKit \
  iChart/Shared/ChordNotation/ChordNotation.swift \
  iChart/Shared/ChordNotation/ChordNotationGrammar.swift \
  iChart/Recognition/InkTrajectoryTypes.swift \
  iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift \
  iChart/Recognition/Learned/ChordInkFeatureSchema.swift \
  iChart/Recognition/Learned/ChordInkLearnedFactorOutput.swift \
  iChart/Recognition/Learned/ChordInkModelArtifactManifest.swift \
  iChart/Recognition/Learned/ChordInkCompositionalDecoder.swift \
  iChart/Recognition/Learned/ChordInkLearnedRuntime.swift \
  iChart/Recognition/Learned/ChordInkCoreMLAdapter.swift \
  recognition_ml/tests/ChordInkCoreMLCrossRuntimeGate.swift \
  -o "$gate_root/chord-ink-coreml-cross-runtime-gate"

for model_architecture in \
  dual-view-v2-layout-preserving \
  trajectory-only-v2-layout-preserving \
  raster-only-v2-layout-preserving
do
  fixture_root="$gate_root/$model_architecture"
  PYTHONPATH="recognition_ml:recognition_ml/tests" "$python_bin" \
    recognition_ml/tests/generate_coreml_cross_runtime_fixture.py \
    --output "$fixture_root" \
    --model-architecture "$model_architecture"

  "$gate_root/chord-ink-coreml-cross-runtime-gate" \
    "$fixture_root/ChordInk.manifest.json" \
    "$fixture_root/ChordInk.mlmodelc" \
    dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
done
