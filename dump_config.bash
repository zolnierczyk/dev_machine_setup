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

# Function to copy files/directories if they exist
copy_if_exists() {
    local source_path="$1"
    local dest_path="$2"

    if [ -e "$source_path" ]; then
        mkdir -p "$(dirname "$dest_path")" # Ensure destination directories exist
        cp -r "$source_path" "$dest_path"
        echo "Copied $source_path to $dest_path"
    else
        echo "WARNING: $source_path does not exist. Skipping."
    fi
}

# Copy VIM configuration
copy_if_exists "$HOME/.vimrc" "$DEST_FOLDER/.vimrc"
copy_if_exists "$HOME/.vim" "$DEST_FOLDER/.vim"

# Copy XFCE panel configuration
copy_if_exists "$HOME/.config/xfce4/panel" "$DEST_FOLDER/.config.xfce4_panel"

# Copy Visual Studio Code configuration
copy_if_exists "$HOME/.config/Code/User/settings.json" "$DEST_FOLDER/vscode_settings.json"
copy_if_exists "$HOME/.config/Code/User/keybindings.json" "$DEST_FOLDER/vscode_keybindings.json"
copy_if_exists "$HOME/.config/Code/User/snippets" "$DEST_FOLDER/vscode_snippets"

# Copy Zsh and Oh-My-Zsh configuration
copy_if_exists "$HOME/.zshrc" "$DEST_FOLDER/.zshrc"
copy_if_exists "$HOME/.oh-my-zsh" "$DEST_FOLDER/oh-my-zsh"

# Copy Zsh history, sanitised unless explicitly disabled.
dump_zsh_history() {
    local source_path="$HOME/.zsh_history"
    local dest_path="$DEST_FOLDER/zsh_history"

    if [ ! -e "$source_path" ]; then
        echo "WARNING: $source_path does not exist. Skipping."
        return 0
    fi

    if [ "$SANITIZE" -eq 0 ]; then
        cp "$source_path" "$dest_path"
        chmod 600 "$dest_path"
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
}

dump_zsh_history

# Copy Midnight Commander (mc) configuration
copy_if_exists "$HOME/.config/mc" "$DEST_FOLDER/.config/mc"

# Copy install_config.bash script
copy_if_exists "$PWD/install_config.bash" "$DEST_FOLDER/install_config.bash"

# Create an archive of all extracted files and install_config.bash.
# The archive is built outside the destination folder so that tar never tries
# to read the file it is writing (which makes it fail with "file changed as we
# read it" and would grow the dump on every run).
ARCHIVE_FILE="$DEST_FOLDER/config_backup_$(date +%Y%m%d).tar.gz"
echo "Creating archive $ARCHIVE_FILE..."
TMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/config_backup_XXXXXX.tar.gz")"
trap 'rm -f "$TMP_ARCHIVE"' EXIT
tar -czf "$TMP_ARCHIVE" --exclude='./config_backup_*.tar.gz' -C "$DEST_FOLDER" .
mv "$TMP_ARCHIVE" "$ARCHIVE_FILE"
chmod 600 "$ARCHIVE_FILE"
echo "Archive created successfully: $ARCHIVE_FILE"

# Final message
echo "Configuration files have been successfully copied to $DEST_FOLDER."
if [ "$SANITIZE" -eq 1 ]; then
    echo "Zsh history in the dump has been sanitised."
else
    echo "WARNING: Zsh history in the dump is NOT sanitised."
fi