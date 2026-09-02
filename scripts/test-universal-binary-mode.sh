#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
builder="$script_dir/build-universal-binary.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/axorcist-binary-mode.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mock_bin="$fixture_root/bin"
mkdir -p "$mock_bin" "$fixture_root/build output"
# Inert data only: the real builder installs this fixture but never executes it.
printf '%s\n' 'Not a Mach-O executable; permission fixture only.' >"$fixture_root/build output/axorc"
chmod 0700 "$fixture_root/build output/axorc"

cat >"$mock_bin/mock-tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$(umask)" != 0077 ]]; then
    echo 'Builder widened the caller umask' >&2
    exit 1
fi

narrow_mode() {
    if [[ "$AXORCIST_TEST_NARROW_TOOL" == "$1" ]]; then
        chmod 0700 "$2"
        touch "$AXORCIST_TEST_STATE/narrowed"
    fi
}

case "${0##*/}" in
    swift)
        if [[ " $* " == *' --show-bin-path '* ]]; then
            printf '%s\n' "$AXORCIST_TEST_BUILD_DIR"
        fi
        ;;
    lipo) ;;
    strip) narrow_mode strip "${!#}" ;;
    codesign)
        case "$1" in
            --force) narrow_mode codesign "${!#}" ;;
            --verify) ;;
            *) exit 2 ;;
        esac
        ;;
    file) printf '%s: universal binary (mock)\n' "$1" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$mock_bin/mock-tool"
for tool in swift lipo strip codesign file; do
    ln -s mock-tool "$mock_bin/$tool"
done

failed=0
for narrow_tool in strip codesign; do
    for signing_mode in adhoc developer-id; do
        case_dir="$fixture_root/$narrow_tool-$signing_mode"
        binary="$case_dir/output directory/axorc"
        mkdir -p "$case_dir"
        args=("$binary")
        if [[ "$signing_mode" == adhoc ]]; then
            args+=(--adhoc)
        fi
        if ! output="$(
            umask 077
            env -i \
                PATH="$mock_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
                AXORC_CODESIGN_IDENTITY='Fixture identity (mock only)' \
                AXORCIST_TEST_BUILD_DIR="$fixture_root/build output" \
                AXORCIST_TEST_STATE="$case_dir" \
                AXORCIST_TEST_NARROW_TOOL="$narrow_tool" \
                bash "$builder" "${args[@]}" 2>&1
        )"; then
            printf 'FAIL: %s/%s builder failed\n%s\n' "$narrow_tool" "$signing_mode" "$output" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$case_dir/narrowed" ]]; then
            printf 'FAIL: %s/%s did not exercise the rewrite\n' "$narrow_tool" "$signing_mode" >&2
            failed=1
            continue
        fi
        mode="$(stat -f '%Lp' "$binary")"
        if [[ "$mode" != 755 ]]; then
            printf 'FAIL: %s/%s builder succeeded but output mode is %s; expected 755\n' \
                "$narrow_tool" "$signing_mode" "$mode" >&2
            failed=1
            continue
        fi
        printf 'PASS: %s/%s output mode 755 with umask 077\n' "$narrow_tool" "$signing_mode"
    done
done
exit "$failed"
