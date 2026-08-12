#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

source_pattern='NSAppleScript|NSUserAppleScriptTask|OSAKit|OSAScript|AEDeterminePermissionToAutomateTarget|AECreateDesc|AEDisposeDesc|AESend(Message)?|OSA(Compile|Execute|Load|Store|DoScript)|kOSAComponentType|NSAppleEventsUsageDescription|(^|[^[:alnum:]_])osascript([^[:alnum:]_]|$)'
source_scan_exit=0
source_matches="$(grep -REn "$source_pattern" Sources)" || source_scan_exit=$?
if ((source_scan_exit > 1)); then
    echo "Could not inspect production source for Apple Events surfaces" >&2
    exit 1
fi
if [[ -n "$source_matches" ]]; then
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

symbol_pattern='(^|[[:space:]])_(AE[A-Z][[:alnum:]_]*|OSA[A-Z][[:alnum:]_]*|kOSAComponentType|OBJC_(CLASS|METACLASS)_[^[:space:]]*(NSAppleScript|NSUserAppleScriptTask|OSAScript))'
if ! undefined_symbols="$(nm -u "$binary")"; then
    echo "Could not inspect axorc imports: $binary" >&2
    exit 1
fi

if [[ "$undefined_symbols" =~ $symbol_pattern ]]; then
    echo "axorc imports an Apple Events execution API:" >&2
    echo "${BASH_REMATCH[0]}" >&2
    exit 1
fi

if ! embedded_strings="$(strings -a "$binary")"; then
    echo "Could not inspect axorc embedded strings: $binary" >&2
    exit 1
fi

string_pattern='NSAppleScript|NSUserAppleScriptTask|OSAKit(\.framework)?|OSAScript|OSA(Compile|Execute|Load|Store|DoScript)|kOSAComponentType|NSAppleEventsUsageDescription|/usr/bin/osascript|(^|[^[:alnum:]_])osascript([^[:alnum:]_]|$)'
if [[ "$embedded_strings" =~ $string_pattern ]]; then
    echo "axorc embeds an Apple Events execution surface:" >&2
    echo "${BASH_REMATCH[0]}" >&2
    exit 1
fi

echo "test-native-ax-only: ok"
