#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

source_pattern='NSAppleScript|AEDeterminePermissionToAutomateTarget|AECreateDesc|AEDisposeDesc|AESend(Message)?|OSA(Compile|Execute|Load|Store|DoScript)|NSAppleEventsUsageDescription|(^|[^[:alnum:]_])osascript([^[:alnum:]_]|$)'
if source_matches="$(grep -REn "$source_pattern" Sources 2>/dev/null)" && [[ -n "$source_matches" ]]; then
    echo "Production source retains an Apple Events execution surface:" >&2
    echo "$source_matches" >&2
    exit 1
fi

resource_matches="$(find Sources -type f \( -name '*.scpt' -o -name '*.applescript' -o -name '*.osa' \) -print)"
if [[ -n "$resource_matches" ]]; then
    echo "Production source contains an Apple Events script resource:" >&2
    echo "$resource_matches" >&2
    exit 1
fi

if [[ $# -gt 1 ]]; then
    echo "Usage: scripts/test-native-ax-only.sh [axorc-binary]" >&2
    exit 2
fi

binary="${1:-}"
if [[ -z "$binary" ]]; then
    swift build --product axorc >/dev/null
    binary="$(swift build --show-bin-path)/axorc"
elif [[ "$binary" != /* ]]; then
    binary="$repo_root/$binary"
fi

if [[ ! -x "$binary" ]]; then
    echo "axorc binary is missing or not executable: $binary" >&2
    exit 1
fi

symbol_pattern='(^|[[:space:]])_(AE[A-Z][[:alnum:]_]*|OSA[A-Z][[:alnum:]_]*|OBJC_(CLASS|METACLASS)_[^[:space:]]*NSAppleScript)'
if symbol_matches="$(nm -u "$binary" | grep -E "$symbol_pattern")" && [[ -n "$symbol_matches" ]]; then
    echo "axorc imports an Apple Events execution API:" >&2
    echo "$symbol_matches" >&2
    exit 1
fi

if string_matches="$(strings -a "$binary" | grep -E 'NSAppleEventsUsageDescription|(^|[^[:alnum:]_])osascript([^[:alnum:]_]|$)')" &&
    [[ -n "$string_matches" ]]
then
    echo "axorc embeds an Apple Events execution surface:" >&2
    echo "$string_matches" >&2
    exit 1
fi

echo "test-native-ax-only: ok"
