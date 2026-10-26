#!/usr/bin/env bash
set -euo pipefail

INSTALL_VSCODE_EXT=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<USAGE
Usage: $0 [options]

Restore configurations from the extracted dump beside this script.
RESTORE_MANIFEST and home/ must be in the same directory as this script.

Options:
  --install-vscode-extensions  Install the VS Code extensions listed in
                               info/vscode_extensions.txt after restoring.
  -h, --help                   Show this help.

Package lists under info/ are informational and are never installed
automatically.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --install-vscode-extensions)
            INSTALL_VSCODE_EXT=1
            shift
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
            echo "ERROR: Unexpected argument: $1. Run this script from an extracted dump without an archive argument." >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate the extracted layout before changing anything in HOME.
MANIFEST_FILE="$SCRIPT_DIR/RESTORE_MANIFEST"
DUMP_HOME="$SCRIPT_DIR/home"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: No RESTORE_MANIFEST found in $SCRIPT_DIR." >&2
    echo "ERROR: Extract a dump created by dump_config.bash and run its install_config.bash." >&2
    exit 1
fi
if [ ! -d "$DUMP_HOME" ]; then
    echo "ERROR: No home/ directory found in $SCRIPT_DIR. Extract the complete dump before restoring." >&2
    exit 1
fi

echo "Restoring configurations from $SCRIPT_DIR"

# Show which machine the dump came from.
if [ -f "$SCRIPT_DIR/manifest.txt" ]; then
    echo
    echo "--- Source machine ---"
    grep -E '^(created|hostname|user|os|kernel|architecture) ' "$SCRIPT_DIR/manifest.txt" || true
    echo "Full details: $SCRIPT_DIR/manifest.txt"
    echo "----------------------"
    echo
fi

# Function to copy files and create backups
copy_with_backup() {
    src_file="$1"
    dest_file="$2"

    if [ -e "$dest_file" ]; then
        backup_file="${dest_file}.bak.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing file: $dest_file to $backup_file"
        mv "$dest_file" "$backup_file"
    fi

    echo "Copying $src_file to $dest_file"
    mkdir -p "$(dirname "$dest_file")"
    # The destination was moved away above, so "cp -a" cannot nest the source
    # inside an existing directory carrying the same name.
    cp -a "$src_file" "$dest_file"
}

# Restore every path listed in RESTORE_MANIFEST to its original location.
restored=0
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src_file="$DUMP_HOME/$rel"
    if [ ! -e "$src_file" ]; then
        echo "WARNING: $rel is listed in RESTORE_MANIFEST but missing from the dump. Skipping."
        continue
    fi
    copy_with_backup "$src_file" "$HOME/$rel"
    restored=$((restored + 1))
done < "$MANIFEST_FILE"

echo "Restored $restored entries."

# Keep the shell history private.
if [ -e "$HOME/.zsh_history" ]; then
    chmod 600 "$HOME/.zsh_history"
fi

# Optionally reinstall the VS Code extensions recorded in the dump.
EXT_LIST="$SCRIPT_DIR/info/vscode_extensions.txt"
if [ "$INSTALL_VSCODE_EXT" -eq 1 ]; then
    if [ ! -f "$EXT_LIST" ]; then
        echo "WARNING: No info/vscode_extensions.txt in the dump. Nothing to install."
    elif ! command -v code >/dev/null 2>&1; then
        echo "ERROR: --install-vscode-extensions was requested but the 'code' CLI is missing." >&2
        exit 1
    else
        echo "Installing VS Code extensions..."
        ext_ok=0
        ext_failed=0
        while IFS= read -r ext; do
            [ -n "$ext" ] || continue
            case "$ext" in \#*) continue ;; esac
            if code --install-extension "$ext" --force >/dev/null 2>&1; then
                echo "  installed: $ext"
                ext_ok=$((ext_ok + 1))
            else
                echo "  FAILED:    $ext"
                ext_failed=$((ext_failed + 1))
            fi
        done < "$EXT_LIST"
        echo "VS Code extensions: $ext_ok installed, $ext_failed failed."
    fi
elif [ -f "$EXT_LIST" ]; then
    echo
    echo "VS Code extensions were recorded but not installed."
    echo "Re-run with --install-vscode-extensions to install them."
fi

if [ -d "$SCRIPT_DIR/info" ]; then
    saved_info="$HOME/config_dump_info"
    rm -rf "$saved_info"
    cp -a "$SCRIPT_DIR/info" "$saved_info"
    echo
    echo "Reference lists copied to $saved_info:"
    ls -1 "$saved_info" | sed 's/^/  /'
    echo "These are informational. Nothing from them is installed automatically."
fi

echo "Configuration files have been restored successfully."
