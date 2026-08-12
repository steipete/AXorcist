#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/test-native-ax-only.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/axorcist-native-policy.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mock_bin="$fixture_root/bin"
binary="$fixture_root/axorc"
mkdir -p "$mock_bin"
touch "$binary"
chmod +x "$binary"

cat >"$mock_bin/nm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${AXORCIST_TEST_NM_MODE:-clean}" in
    clean) ;;
    fail) exit 86 ;;
    apple-event) printf '%s\n' '                 U _AEGetParamPtr' ;;
    osa) printf '%s\n' '                 U _OSAGetScriptInfo' ;;
    user-script-task) printf '%s\n' '                 U _OBJC_CLASS_$_NSUserAppleScriptTask' ;;
    *) exit 2 ;;
esac
EOF

cat >"$mock_bin/strings" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${AXORCIST_TEST_STRINGS_MODE:-clean}" in
    clean) printf '%s\n' 'native accessibility only' ;;
    fail) exit 87 ;;
    osakit) printf '%s\n' 'OSAKit.framework' ;;
    osascript) printf '%s\n' '/usr/bin/osascript' ;;
    *) exit 2 ;;
esac
EOF

cat >"$mock_bin/grep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${AXORCIST_TEST_GREP_MODE:-clean}" in
    clean) exec /usr/bin/grep "$@" ;;
    fail) exit 88 ;;
    *) exit 2 ;;
esac
EOF

chmod +x "$mock_bin/nm" "$mock_bin/strings" "$mock_bin/grep"

run_gate() {
    env \
        PATH="$mock_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        AXORCIST_TEST_NM_MODE="${1:-clean}" \
        AXORCIST_TEST_STRINGS_MODE="${2:-clean}" \
        AXORCIST_TEST_GREP_MODE="${3:-clean}" \
        bash "$gate" "$binary" 2>&1
}

expect_success() {
    local label="$1"
    local nm_mode="$2"
    local strings_mode="$3"
    local grep_mode="${4:-clean}"
    local output

    if ! output="$(run_gate "$nm_mode" "$strings_mode" "$grep_mode")"; then
        printf 'FAIL: %s unexpectedly failed\n%s\n' "$label" "$output" >&2
        exit 1
    fi
    [[ "$output" == *'test-native-ax-only: ok'* ]] || {
        printf 'FAIL: %s did not report success\n%s\n' "$label" "$output" >&2
        exit 1
    }
}

expect_failure() {
    local label="$1"
    local nm_mode="$2"
    local strings_mode="$3"
    local expected="$4"
    local grep_mode="${5:-clean}"
    local output

    if output="$(run_gate "$nm_mode" "$strings_mode" "$grep_mode")"; then
        printf 'FAIL: %s unexpectedly passed\n%s\n' "$label" "$output" >&2
        exit 1
    fi
    [[ "$output" == *"$expected"* ]] || {
        printf 'FAIL: %s did not report %q\n%s\n' "$label" "$expected" "$output" >&2
        exit 1
    }
}

expect_success 'clean executable' clean clean
expect_failure 'source inspection failure' clean clean 'Could not inspect production source' fail
expect_failure 'nm inspection failure' fail clean 'Could not inspect axorc imports'
expect_failure 'strings inspection failure' clean fail 'Could not inspect axorc embedded strings'
expect_failure 'generic Apple Events import' apple-event clean 'imports an Apple Events execution API'
expect_failure 'generic OSA import' osa clean 'imports an Apple Events execution API'
expect_failure 'NSUserAppleScriptTask import' user-script-task clean 'imports an Apple Events execution API'
expect_failure 'OSAKit framework string' clean osakit 'embeds an Apple Events execution surface'
expect_failure 'osascript path string' clean osascript 'embeds an Apple Events execution surface'

echo 'test-native-ax-only-policy: ok'
