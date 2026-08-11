#!/usr/bin/env bash

set -euo pipefail

swiftformat_version="0.62.1"
swiftformat_sha256="7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"
swiftlint_version="0.65.0"
swiftlint_sha256="d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6"

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
