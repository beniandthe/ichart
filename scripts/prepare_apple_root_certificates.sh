#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-/tmp/ichart-apple-root-certificates.pem}"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/ichart-apple-root-certificates.XXXXXX")"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

download_and_convert() {
  local url="$1"
  local name
  name="$(basename "$url" .cer)"

  curl -fsSL "$url" -o "$workdir/$name.cer"
  openssl x509 -inform DER -in "$workdir/$name.cer" -out "$workdir/$name.pem"
}

download_and_convert "https://www.apple.com/appleca/AppleIncRootCertificate.cer"
download_and_convert "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer"
download_and_convert "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"

cat "$workdir"/*.pem > "$output_path"

echo "Wrote Apple root certificate PEM bundle:"
echo "$output_path"
echo
echo "Included certificates:"
openssl crl2pkcs7 -nocrl -certfile "$output_path" \
  | openssl pkcs7 -print_certs -noout \
  | rg '^subject='
