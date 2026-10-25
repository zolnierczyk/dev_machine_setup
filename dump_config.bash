#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER="$SCRIPT_DIR/zsh_history_sanitize.py"

SANITIZE=1
SECRET_WORDS_FILE="${ZSH_SANITIZE_WORDS:-$HOME/.config/zsh-sanitize/secret-words.txt}"
REPORT_FILE=""
DEST_FOLDER=""

usage() {
    cat <<USAGE
Usage: $0 [options] <destination_folder>

Options:
  --no-sanitize             Dump ~/.zsh_history verbatim, WITHOUT removing
                            secrets. The dump will contain passwords and
                            tokens - use only for a local, trusted copy.
  --secret-words-file FILE  Custom secret substrings passed to the sanitiser.
                            Default: \$HOME/.config/zsh-sanitize/secret-words.txt
                            (silently skipped when absent).
  --report FILE             Write the sanitiser's before/after report to FILE.
                            Must live OUTSIDE the destination folder, because
                            it contains the original, unredacted secrets.
  -h, --help                Show this help.

By default the Zsh history is sanitised with $(basename "$SANITIZER") before
being added to the dump.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-sanitize)
            SANITIZE=0
            shift
            ;;
        --secret-words-file)
            [ "$#" -ge 2 ] || { echo "ERROR: --secret-words-file needs an argument." >&2; exit 1; }
            SECRET_WORDS_FILE="$2"
            shift 2
            ;;
        --report)
            [ "$#" -ge 2 ] || { echo "ERROR: --report needs an argument." >&2; exit 1; }
            REPORT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            [ -z "$DEST_FOLDER" ] || { echo "ERROR: Only one destination folder may be given." >&2; exit 1; }
            DEST_FOLDER="$1"
            shift
            ;;
    esac
done

if [ -z "$DEST_FOLDER" ]; then
    usage >&2
    exit 1
fi

# Create the destination folder if it doesn't exist
mkdir -p "$DEST_FOLDER"

# The report contains the original, unredacted secrets. Writing it into the
# destination folder would archive it straight back into the dump.
if [ -n "$REPORT_FILE" ]; then
    dest_abs="$(cd "$DEST_FOLDER" && pwd)"
    report_dir_abs="$(cd "$(dirname "$REPORT_FILE")" 2>/dev/null && pwd || true)"
    if [ -z "$report_dir_abs" ]; then
        echo "ERROR: Directory for --report file $REPORT_FILE does not exist." >&2
        exit 1
    fi
    case "$report_dir_abs/" in
        "$dest_abs"/*)
            echo "ERROR: --report must not point inside the destination folder," >&2
            echo "ERROR: it contains unredacted secrets and would be archived." >&2
            exit 1
            ;;
    esac
fi

# Everything that belongs in $HOME is dumped under $DUMP_HOME, keeping its
# original relative path. RESTORE_MANIFEST lists those paths so install_config.bash
# restore each one to exactly where it came from, including dotfiles and nested
# paths such as .config/terminator.
DUMP_HOME="$DEST_FOLDER/home"
RESTORE_MANIFEST="$DEST_FOLDER/RESTORE_MANIFEST"
mkdir -p "$DUMP_HOME"
: > "$RESTORE_MANIFEST"

# Copy $HOME/<relative path> into the dump, preserving the relative path.
copy_home_path() {
    local rel="$1"
    local source_path="$HOME/$rel"
    local dest_path="$DUMP_HOME/$rel"

    if [ ! -e "$source_path" ]; then
        echo "WARNING: $source_path does not exist. Skipping."
        return 0
    fi

    mkdir -p "$(dirname "$dest_path")"
    # Remove any previous copy first: "cp -a dir dest" would nest the source
    # inside an existing destination directory on a repeated run.
    rm -rf "$dest_path"
    cp -a "$source_path" "$dest_path"
    register_manifest "$rel"
    echo "Copied $source_path to $dest_path"
}

# Record a path (relative to $HOME) as restorable.
register_manifest() {
    printf '%s\n' "$1" >> "$RESTORE_MANIFEST"
}

# Copy VIM configuration
copy_home_path ".vimrc"
copy_home_path ".vim"

# Copy XFCE panel configuration
copy_home_path ".config/xfce4/panel"

# Copy Visual Studio Code configuration
copy_home_path ".config/Code/User/settings.json"
copy_home_path ".config/Code/User/keybindings.json"
copy_home_path ".config/Code/User/snippets"

# Copy Zsh configuration
copy_home_path ".zshrc"

# Copy Powerlevel10k prompt configuration (.zshrc sources this file)
copy_home_path ".p10k.zsh"

# Copy Terminator configuration
copy_home_path ".config/terminator"

# Copy only the user-owned parts of Oh-My-Zsh. The framework itself is
# reinstalled by setup_machine.bash, so copying the whole checkout would just
# bloat the archive with a Git clone that is about to be replaced. Everything a
# user actually writes lives in custom/ (own themes, plugins, *.zsh files).
copy_home_path ".oh-my-zsh/custom"

# Copy Zsh history, sanitised unless explicitly disabled.
dump_zsh_history() {
    local source_path="$HOME/.zsh_history"
    local dest_path="$DUMP_HOME/.zsh_history"

    if [ ! -e "$source_path" ]; then
        echo "WARNING: $source_path does not exist. Skipping."
        return 0
    fi

    if [ "$SANITIZE" -eq 0 ]; then
        cp "$source_path" "$dest_path"
        chmod 600 "$dest_path"
        register_manifest ".zsh_history"
        echo "WARNING: Zsh history copied WITHOUT sanitisation (--no-sanitize)."
        echo "WARNING: $dest_path may contain passwords and tokens."
        return 0
    fi

    # Fail closed: never fall back to an unsanitised copy.
    if [ ! -f "$SANITIZER" ]; then
        echo "ERROR: Sanitiser not found at $SANITIZER." >&2
        echo "ERROR: Refusing to dump the history unsanitised. Use --no-sanitize to override." >&2
        exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is required to sanitise the Zsh history." >&2
        echo "ERROR: Refusing to dump the history unsanitised. Use --no-sanitize to override." >&2
        exit 1
    fi

    local args=("$source_path" -o "$dest_path")
    if [ -f "$SECRET_WORDS_FILE" ]; then
        args+=(--secret-words-file "$SECRET_WORDS_FILE")
        echo "Using custom secret substrings from $SECRET_WORDS_FILE"
    fi
    if [ -n "$REPORT_FILE" ]; then
        args+=(--report "$REPORT_FILE")
    fi

    echo "Sanitising Zsh history..."
    python3 "$SANITIZER" "${args[@]}"
    chmod 600 "$dest_path"

    if [ -n "$REPORT_FILE" ]; then
        chmod 600 "$REPORT_FILE"
        echo "Redaction report written to $REPORT_FILE (contains unredacted secrets, keep it local)."
    fi
    echo "Copied sanitised $source_path to $dest_path"
    register_manifest ".zsh_history"
}

dump_zsh_history

# Copy Midnight Commander (mc) configuration
copy_home_path ".config/mc"

# Copy install_config.bash script. It sits at the root of the dump, next to the
# RESTORE_MANIFEST, and is therefore not restored into $HOME.
if [ -f "$SCRIPT_DIR/install_config.bash" ]; then
    cp "$SCRIPT_DIR/install_config.bash" "$DEST_FOLDER/install_config.bash"
    echo "Copied $SCRIPT_DIR/install_config.bash to $DEST_FOLDER/install_config.bash"
else
    echo "WARNING: $SCRIPT_DIR/install_config.bash does not exist. Skipping."
fi

# Describe the machine this dump was taken from, so the target machine can be
# compared against it. Deliberately records only descriptive facts - the
# environment is never dumped, because it routinely holds tokens.
write_machine_manifest() {
    local out="$DEST_FOLDER/manifest.txt"
    local v

    {
        echo "# Machine manifest for this configuration dump"
        echo "# Generated by dump_config.bash"
        echo
        echo "[dump]"
        echo "created            : $(date -Is)"
        echo "sanitised_history  : $([ "$SANITIZE" -eq 1 ] && echo yes || echo no)"
        echo "entries            : $(wc -l < "$RESTORE_MANIFEST" | tr -d ' ')"
        echo
        echo "[machine]"
        echo "hostname           : $(hostname 2>/dev/null || echo unknown)"
        echo "user               : ${USER:-$(id -un)}"
        echo "kernel             : $(uname -s -r)"
        echo "architecture       : $(uname -m)"
        if [ -r /etc/os-release ]; then
            echo "os                 : $(. /etc/os-release && echo "${PRETTY_NAME:-$NAME $VERSION_ID}")"
        fi
        echo "cpu                : $(nproc 2>/dev/null || echo '?') cores"
        if [ -r /proc/meminfo ]; then
            echo "memory             : $(awk '/MemTotal/ {printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
        fi
        echo "locale             : ${LANG:-unset}"
        echo "timezone           : $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo unknown)"
        echo "desktop            : ${XDG_CURRENT_DESKTOP:-unknown}"
        echo "login_shell        : ${SHELL:-unknown}"
        # Only the local groups that matter for a dev machine. The full list is
        # dominated by corporate directory groups that say nothing about setup.
        echo "local_groups       : $(id -nG 2>/dev/null | tr ' ' '\n' \
            | grep -xE 'docker|vboxusers|sudo|adm|dialout|plugdev|wireshark|kvm|libvirt|video|audio|users' \
            | paste -sd' ' - || true)"
        echo
        echo "[tools]"
        for tool in zsh bash git python3 docker code gh tmux vim nvim node npm; do
            if command -v "$tool" >/dev/null 2>&1; then
                # "|| true" is required: head closes the pipe after the first
                # line, the tool dies with SIGPIPE and pipefail would abort.
                v="$("$tool" --version 2>/dev/null | head -n1 || true)"
                # tmux and a few others report their version via -V only.
                [ -n "$v" ] || v="$("$tool" -V 2>/dev/null | head -n1 || true)"
                printf '%-18s : %s\n' "$tool" "${v:-present}"
            else
                printf '%-18s : not installed\n' "$tool"
            fi
        done
        echo
        echo "# Reference lists live in info/ next to this file:"
        echo "#   info/vscode_extensions.txt    installed VS Code extensions"
        echo "#   info/apt_manual_packages.txt  manually installed APT packages"
    } > "$out"

    echo "Wrote machine manifest to $out"
}

# Reference lists for rebuilding the new machine. These are informational:
# install_config.bash never replays them automatically, except for the VS Code
# extensions, which can be requested explicitly.
write_info_lists() {
    local info_dir="$DEST_FOLDER/info"
    mkdir -p "$info_dir"

    if command -v code >/dev/null 2>&1; then
        if code --list-extensions > "$info_dir/vscode_extensions.txt" 2>/dev/null; then
            echo "Wrote $(wc -l < "$info_dir/vscode_extensions.txt" | tr -d ' ') VS Code extensions to $info_dir/vscode_extensions.txt"
        else
            rm -f "$info_dir/vscode_extensions.txt"
            echo "WARNING: 'code --list-extensions' failed. Skipping extension list."
        fi
    else
        echo "WARNING: VS Code CLI not found. Skipping extension list."
    fi

    # Manually installed APT packages: what was asked for, without the
    # dependencies that apt pulls in on its own.
    if command -v apt-mark >/dev/null 2>&1; then
        {
            echo "# Manually installed APT packages on $(hostname 2>/dev/null)."
            echo "# INFORMATIONAL ONLY - not installed by install_config.bash."
            echo "# Review first, then: grep -v '^#' this_file | xargs sudo apt install -y"
            apt-mark showmanual 2>/dev/null || true
        } > "$info_dir/apt_manual_packages.txt"
        echo "Wrote manually installed APT packages to $info_dir/apt_manual_packages.txt"
    fi

    if command -v snap >/dev/null 2>&1; then
        snap list > "$info_dir/snap_packages.txt" 2>/dev/null || rm -f "$info_dir/snap_packages.txt"
    fi

    if command -v pip3 >/dev/null 2>&1; then
        pip3 list --user --format=freeze > "$info_dir/pip_user_packages.txt" 2>/dev/null \
            || rm -f "$info_dir/pip_user_packages.txt"
    fi

    if command -v npm >/dev/null 2>&1; then
        npm ls -g --depth=0 > "$info_dir/npm_global_packages.txt" 2>/dev/null \
            || rm -f "$info_dir/npm_global_packages.txt"
    fi
}

write_machine_manifest
write_info_lists
# Create an archive of all extracted files and install_config.bash.
# The archive is built outside the destination folder so that tar never tries
# to read the file it is writing (which makes it fail with "file changed as we
# read it" and would grow the dump on every run).
ARCHIVE_FILE="$DEST_FOLDER/config_backup_$(date +%Y%m%d).tar.gz"
echo "Creating archive $ARCHIVE_FILE..."
TMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/config_backup_XXXXXX.tar.gz")"
trap 'rm -f "$TMP_ARCHIVE"' EXIT
tar -czf "$TMP_ARCHIVE" --exclude='./config_backup_*.tar.gz' --exclude='./config_backup_*.sha256' -C "$DEST_FOLDER" .
mv "$TMP_ARCHIVE" "$ARCHIVE_FILE"
chmod 600 "$ARCHIVE_FILE"
echo "Archive created successfully: $ARCHIVE_FILE"

# Checksum for transfer verification. Only the base name is stored so the file
# can be checked with "sha256sum -c" from inside the dump folder.
CHECKSUM_FILE="$ARCHIVE_FILE.sha256"
( cd "$DEST_FOLDER" && sha256sum "$(basename "$ARCHIVE_FILE")" > "$(basename "$CHECKSUM_FILE")" )
chmod 600 "$CHECKSUM_FILE"
echo "Checksum written to $CHECKSUM_FILE"
echo "Verify on the target machine with:"
echo "  cd $(basename "$DEST_FOLDER") && sha256sum -c $(basename "$CHECKSUM_FILE")"

# Final message
echo "Configuration files have been successfully copied to $DEST_FOLDER."
if [ "$SANITIZE" -eq 1 ]; then
    echo "Zsh history in the dump has been sanitised."
else
    echo "WARNING: Zsh history in the dump is NOT sanitised."
fi