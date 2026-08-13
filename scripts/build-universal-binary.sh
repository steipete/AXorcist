#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-universal-binary.sh <output-path> [--adhoc]

Builds a universal release axorc binary at the requested path. Publishable
builds require AXORC_CODESIGN_IDENTITY to name a Developer ID Application
identity. Use --adhoc only for local or CI verification.
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

output_path="$1"
shift
adhoc=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc)
      adhoc=true
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$adhoc" == false && -z "${AXORC_CODESIGN_IDENTITY:-}" ]]; then
  echo "AXORC_CODESIGN_IDENTITY is required for publishable artifacts." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

build_arguments=(-c release --arch arm64 --arch x86_64 --product axorc)
swift build "${build_arguments[@]}"
bin_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
built_binary="$bin_dir/axorc"
if [[ ! -x "$built_binary" ]]; then
  echo "Built universal axorc binary is missing: $built_binary" >&2
  exit 1
fi

for architecture in arm64 x86_64; do
  if ! lipo "$built_binary" -verify_arch "$architecture"; then
    echo "Built axorc binary is missing the $architecture architecture: $built_binary" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$output_path")"
install -m 0755 "$built_binary" "$output_path"
strip -x "$output_path"

if [[ "$adhoc" == true ]]; then
  codesign --force --sign - "$output_path"
else
  codesign --force --options runtime --timestamp --sign "$AXORC_CODESIGN_IDENTITY" "$output_path"
fi

codesign --verify --strict --verbose=2 "$output_path"
file "$output_path" | grep -q 'universal binary'
echo "Created universal binary $output_path"
