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

run_from() (
    cd "$1" || exit 1
    shift
    "$@"
)

for script in "$DUMP" "$INSTALL"; do
    name="$(basename "$script")"
    expect 0 ""                "$name: bash syntax"         -- bash -n "$script"
    expect 0 "^Usage:"         "$name: --help"              -- bash "$script" --help
    expect 0 "^Usage:"         "$name: -h"                  -- bash "$script" -h
    expect 1 "Unknown option"  "$name: unknown option"      -- bash "$script" --bogus
done

expect 1 "^Usage:" "dump_config.bash: no arguments" -- bash "$DUMP"
expect 1 "needs an argument" "dump_config.bash: --report without value" \
    -- bash "$DUMP" --report
expect 1 "Only one destination" "dump_config.bash: two destinations" \
    -- bash "$DUMP" "$WORK_DIR/a" "$WORK_DIR/b"
expect 1 "Unexpected argument" "install_config.bash: rejects archive argument" \
    -- bash "$INSTALL" "$WORK_DIR/no_such_archive.tar.gz"

# Dump a fake HOME, extract the archive, and run the bundled installer.
SRC_HOME="$WORK_DIR/src_home"
DST_HOME="$WORK_DIR/dst_home"
DUMP_DIR="$WORK_DIR/dump"
EXTRACT_DIR="$WORK_DIR/extracted dump"
INVALID_DIR="$WORK_DIR/invalid dump"
mkdir -p "$SRC_HOME/.config/terminator" "$DST_HOME/.config/terminator" \
    "$EXTRACT_DIR" "$INVALID_DIR"
echo '" dummy vimrc' > "$SRC_HOME/.vimrc"
echo "dummy terminal config" > "$SRC_HOME/.config/terminator/config"
echo "old vimrc" > "$DST_HOME/.vimrc"
echo "old terminal config" > "$DST_HOME/.config/terminator/old_config"
printf ': 1700000000:0;echo hello\n' > "$SRC_HOME/.zsh_history"

cp "$INSTALL" "$INVALID_DIR/install_config.bash"
expect 1 "No RESTORE_MANIFEST" "install_config.bash: rejects missing manifest" \
    -- env HOME="$DST_HOME" bash "$INVALID_DIR/install_config.bash"
: > "$INVALID_DIR/RESTORE_MANIFEST"
expect 1 "No home/ directory" "install_config.bash: rejects incomplete dump" \
    -- env HOME="$DST_HOME" bash "$INVALID_DIR/install_config.bash"
check "install_config.bash: invalid dump leaves HOME unchanged" \
    test "$(cat "$DST_HOME/.vimrc")" = "old vimrc"

expect 0 "Archive created successfully" "dump_config.bash: runs on fake HOME" \
    -- env HOME="$SRC_HOME" ZSH_SANITIZE_WORDS=/nonexistent bash "$DUMP" "$DUMP_DIR"

archive="$(find "$DUMP_DIR" -maxdepth 1 -name 'config_backup_*.tar.gz' | head -n1)"
check "dump_config.bash: archive created" test -n "$archive"
check "dump_config.bash: checksum created" test -f "${archive}.sha256"
expect 0 "OK" "dump_config.bash: checksum verifies" \
    -- run_from "$DUMP_DIR" sha256sum -c "$(basename "$archive").sha256"

expect 0 "" "dump_config.bash: archive extracts" \
    -- tar -xzf "$archive" -C "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR/info"
printf '# informational only\ndummy-package\n' > "$EXTRACT_DIR/info/apt_manual_packages.txt"
printf '# extension IDs\nexample.first\n\nexample.failing\nexample.last\n' \
    > "$EXTRACT_DIR/info/vscode_extensions.txt"

BIN_DIR="$WORK_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/code" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODE_CALLS"
[ "$2" != "example.failing" ]
MOCK
chmod +x "$BIN_DIR/code"
CODE_CALLS="$WORK_DIR/code_calls"
export CODE_CALLS

expect 0 "Restored [0-9]+ entries" "install_config.bash: restores extracted dump from unrelated working directory" \
    -- run_from "$WORK_DIR" env HOME="$DST_HOME" PATH="$BIN_DIR:$PATH" \
    bash "$EXTRACT_DIR/install_config.bash"
check "install_config.bash: .vimrc restored" cmp -s "$SRC_HOME/.vimrc" "$DST_HOME/.vimrc"
check "install_config.bash: nested directory restored" \
    cmp -s "$SRC_HOME/.config/terminator/config" "$DST_HOME/.config/terminator/config"
vim_backup=("$DST_HOME"/.vimrc.bak.*)
dir_backup=("$DST_HOME"/.config/terminator.bak.*)
check "install_config.bash: existing file backed up" \
    test "$(cat "${vim_backup[0]}")" = "old vimrc"
check "install_config.bash: existing directory backed up" \
    test -f "${dir_backup[0]}/old_config"
check "install_config.bash: directory not merged with previous contents" \
    test ! -e "$DST_HOME/.config/terminator/old_config"
check "install_config.bash: history restored" \
    cmp -s "$SRC_HOME/.zsh_history" "$DST_HOME/.zsh_history"
check "install_config.bash: history mode is 600" \
    test "$(stat -c %a "$DST_HOME/.zsh_history")" = 600
check "install_config.bash: reference lists copied" \
    cmp -s "$EXTRACT_DIR/info/apt_manual_packages.txt" "$DST_HOME/config_dump_info/apt_manual_packages.txt"
check "install_config.bash: source dump preserved" \
    cmp -s "$SRC_HOME/.vimrc" "$EXTRACT_DIR/home/.vimrc"
check "install_config.bash: source manifest preserved" test -f "$EXTRACT_DIR/RESTORE_MANIFEST"
check "install_config.bash: extensions not installed by default" test ! -e "$CODE_CALLS"

EXT_HOME="$WORK_DIR/ext_home"
mkdir -p "$EXT_HOME"
expect 0 "VS Code extensions: 2 installed, 1 failed" "install_config.bash: extension opt-in keeps going after failure" \
    -- env HOME="$EXT_HOME" PATH="$BIN_DIR:$PATH" \
    bash "$EXTRACT_DIR/install_config.bash" --install-vscode-extensions
printf '%s\n' '--install-extension example.first --force' \
    '--install-extension example.failing --force' \
    '--install-extension example.last --force' > "$WORK_DIR/expected_code_calls"
check "install_config.bash: extensions installed with expected arguments" \
    cmp -s "$WORK_DIR/expected_code_calls" "$CODE_CALLS"

echo "---------------------------------------------------------------------"
echo "Passed: $passed, Failed: $failed"
[ "$failed" -eq 0 ]
