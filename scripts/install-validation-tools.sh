#!/usr/bin/env bash

set -euo pipefail

swiftformat_version="0.63.0"
swiftformat_sha256="28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f"
swiftlint_version="0.65.1"
swiftlint_sha256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

if [[ $# -gt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: scripts/install-validation-tools.sh [destination]"
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$repo_root/.build/validation-tools}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/axorcist-validation-tools.XXXXXX")"

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

mkdir -p "$destination"

install_tool() {
  local name="$1"
  local version="$2"
  local sha256="$3"
  local owner="$4"
  local repository="$5"
  local archive_name="$6"
  local archive_path="$temporary_directory/$name.zip"
  local extract_path="$temporary_directory/$name"

  curl --fail --location --retry 3 --silent --show-error \
    "https://github.com/$owner/$repository/releases/download/$version/$archive_name" \
    --output "$archive_path"
  printf '%s  %s\n' "$sha256" "$archive_path" | shasum -a 256 --check
  mkdir -p "$extract_path"
  unzip -q "$archive_path" -d "$extract_path"
  install -m 0755 "$extract_path/$name" "$destination/$name"
}

install_tool \
  swiftformat \
  "$swiftformat_version" \
  "$swiftformat_sha256" \
  nicklockwood \
  SwiftFormat \
  swiftformat.zip
install_tool \
  swiftlint \
  "$swiftlint_version" \
  "$swiftlint_sha256" \
  realm \
  SwiftLint \
  portable_swiftlint.zip

"$destination/swiftformat" --version | grep -Fx "$swiftformat_version"
"$destination/swiftlint" version | grep -Fx "$swiftlint_version"
echo "Installed validation tools in $destination"
