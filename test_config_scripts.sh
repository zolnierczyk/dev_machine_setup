#!/usr/bin/env bash
# Sanity tests for dump_config.bash and install_config.bash.
# Uses a throw-away HOME with dummy files only, so no real user data is touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUMP="$SCRIPT_DIR/dump_config.bash"
INSTALL="$SCRIPT_DIR/install_config.bash"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
OUT="$WORK_DIR/out.txt"

passed=0
failed=0

pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() {
    echo "FAIL: $1"
    sed 's/^/    | /' "$OUT"
    failed=$((failed + 1))
}

# expect <exit_code> <grep_pattern|""> <description> -- <command...>
expect() {
    local want_code="$1" pattern="$2" desc="$3"
    shift 4
    "$@" > "$OUT" 2>&1
    local code=$?
    if [ "$code" -ne "$want_code" ]; then
        fail "$desc (exit $code, expected $want_code)"
    elif [ -n "$pattern" ] && ! grep -qE "$pattern" "$OUT"; then
        fail "$desc (output does not match '$pattern')"
    else
        pass "$desc"
    fi
}

check() {
    local desc="$1"
    shift
    if "$@"; then pass "$desc"; else : > "$OUT"; fail "$desc"; fi
}

for script in "$DUMP" "$INSTALL"; do
    name="$(basename "$script")"
    expect 0 ""                "$name: bash syntax"         -- bash -n "$script"
    expect 0 "^Usage:"         "$name: --help"              -- bash "$script" --help
    expect 0 "^Usage:"         "$name: -h"                  -- bash "$script" -h
    expect 1 "^Usage:"         "$name: no arguments"        -- bash "$script"
    expect 1 "Unknown option"  "$name: unknown option"      -- bash "$script" --bogus
done

expect 1 "needs an argument" "dump_config.bash: --report without value" \
    -- bash "$DUMP" --report
expect 1 "Only one destination" "dump_config.bash: two destinations" \
    -- bash "$DUMP" "$WORK_DIR/a" "$WORK_DIR/b"
expect 1 "does not exist" "install_config.bash: missing archive" \
    -- bash "$INSTALL" "$WORK_DIR/no_such_archive.tar.gz"

# Smoke run: dump a fake HOME and restore it into another fake HOME.
SRC_HOME="$WORK_DIR/src_home"
DST_HOME="$WORK_DIR/dst_home"
DUMP_DIR="$WORK_DIR/dump"
mkdir -p "$SRC_HOME" "$DST_HOME"
echo '" dummy vimrc' > "$SRC_HOME/.vimrc"
printf ': 1700000000:0;echo hello\n' > "$SRC_HOME/.zsh_history"

expect 0 "Archive created successfully" "dump_config.bash: runs on fake HOME" \
    -- env HOME="$SRC_HOME" ZSH_SANITIZE_WORDS=/nonexistent bash "$DUMP" "$DUMP_DIR"

archive="$(find "$DUMP_DIR" -maxdepth 1 -name 'config_backup_*.tar.gz' | head -n1)"
check "dump_config.bash: archive created" test -n "$archive"
check "dump_config.bash: checksum created" test -f "${archive}.sha256"

expect 0 "Restored [0-9]+ entries" "install_config.bash: restores archive" \
    -- env HOME="$DST_HOME" bash "$INSTALL" "$archive"
check "install_config.bash: .vimrc restored" cmp -s "$SRC_HOME/.vimrc" "$DST_HOME/.vimrc"

echo "---------------------------------------------------------------------"
echo "Passed: $passed, Failed: $failed"
[ "$failed" -eq 0 ]
