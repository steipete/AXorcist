#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-release-artifact.sh <version> [--adhoc]

Builds dist/axorc-<version>-macos-universal.zip and its SHA-256 file.

Release builds require AXORC_CODESIGN_IDENTITY to name a Developer ID
Application identity already available in the current keychain. Use --adhoc
only for local or CI verification; ad-hoc artifacts must not be published.
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

version="$1"
shift
adhoc=false

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use x.y.z form." >&2
  exit 2
fi

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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_version="$(sed -n 's/.*axorcVersion = "\([^"]*\)".*/\1/p' Sources/axorc/Models/AXORCModels.swift)"
if [[ "$source_version" != "$version" ]]; then
  echo "Version mismatch: source has $source_version, requested $version" >&2
  exit 1
fi

if [[ "$adhoc" == false && -z "${AXORC_CODESIGN_IDENTITY:-}" ]]; then
  echo "AXORC_CODESIGN_IDENTITY is required for publishable artifacts." >&2
  exit 1
fi

dist_dir="$repo_root/dist"
stage_dir="$dist_dir/stage"
binary_path="$stage_dir/axorc"
archive_path="$dist_dir/axorc-$version-macos-universal.zip"
checksum_path="$archive_path.sha256"

rm -rf "$stage_dir" "$archive_path" "$checksum_path"
mkdir -p "$stage_dir"

swift build -c release --arch arm64 --product axorc
swift build -c release --arch x86_64 --product axorc

lipo -create \
  .build/arm64-apple-macosx/release/axorc \
  .build/x86_64-apple-macosx/release/axorc \
  -output "$binary_path"
strip -x "$binary_path"

if [[ "$adhoc" == true ]]; then
  codesign --force --sign - "$binary_path"
else
  codesign --force --options runtime --timestamp --sign "$AXORC_CODESIGN_IDENTITY" "$binary_path"
fi

codesign --verify --strict --verbose=2 "$binary_path"
file "$binary_path" | grep -q 'universal binary'
"$binary_path" --version | grep -Fx "axorc $version"

(
  cd "$stage_dir"
  ditto --norsrc -c -k axorc "$archive_path"
)
(
  cd "$dist_dir"
  shasum -a 256 "$(basename "$archive_path")"
) | tee "$checksum_path"

rm -rf "$stage_dir"
echo "Created $archive_path"
