#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: scripts/render-homebrew-formula.sh <version> <sha256>" >&2
  exit 2
fi

version="$1"
sha256="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use x.y.z form." >&2
  exit 2
fi
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "SHA-256 must be 64 lowercase hexadecimal characters." >&2
  exit 2
fi

sed \
  -e "s/@VERSION@/$version/g" \
  -e "s/@SHA256@/$sha256/g" \
  "$repo_root/packaging/homebrew/axorc.rb.template"
