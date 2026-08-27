#!/usr/bin/env bash
set -euo pipefail

version="${XCODEGEN_VERSION:-2.45.4}"
expected_sha256="${XCODEGEN_SHA256:-090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef}"
install_root="${RUNNER_TEMP:-/tmp}/xcodegen-${version}"
archive="${RUNNER_TEMP:-/tmp}/xcodegen-${version}.zip"
url="https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"

if [[ ! -x "${install_root}/xcodegen/bin/xcodegen" ]]; then
  rm -rf "${install_root}"
  mkdir -p "${install_root}"
  curl --fail --location --silent --show-error --retry 3 --output "${archive}" "${url}"
  printf '%s  %s\n' "${expected_sha256}" "${archive}" | shasum -a 256 -c -
  unzip -q "${archive}" -d "${install_root}"
fi

bin_dir="${install_root}/xcodegen/bin"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${bin_dir}" >> "${GITHUB_PATH}"
fi

"${bin_dir}/xcodegen" --version
