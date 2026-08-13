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

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/axorc-universal.XXXXXX")"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

build_architecture() {
  local architecture="$1"
  local destination="$2"
  local bin_dir

  swift build -c release --arch "$architecture" --product axorc
  bin_dir="$(swift build -c release --arch "$architecture" --show-bin-path)"
  if [[ ! -x "$bin_dir/axorc" ]]; then
    echo "Built axorc binary is missing for $architecture: $bin_dir/axorc" >&2
    exit 1
  fi
  install -m 0755 "$bin_dir/axorc" "$destination"
}

arm64_binary="$stage_dir/axorc-arm64"
x86_64_binary="$stage_dir/axorc-x86_64"
build_architecture arm64 "$arm64_binary"
build_architecture x86_64 "$x86_64_binary"

mkdir -p "$(dirname "$output_path")"
lipo -create "$arm64_binary" "$x86_64_binary" -output "$output_path"
strip -x "$output_path"

if [[ "$adhoc" == true ]]; then
  codesign --force --sign - "$output_path"
else
  codesign --force --options runtime --timestamp --sign "$AXORC_CODESIGN_IDENTITY" "$output_path"
fi

codesign --verify --strict --verbose=2 "$output_path"
file "$output_path" | grep -q 'universal binary'
echo "Created universal binary $output_path"
