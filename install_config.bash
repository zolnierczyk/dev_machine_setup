#!/usr/bin/env bash
set -euo pipefail

INSTALL_VSCODE_EXT=0
ARCHIVE_FILE=""

usage() {
    cat <<USAGE
Usage: $0 [options] <config_archive.tar.gz>

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
            [ -z "$ARCHIVE_FILE" ] || { echo "ERROR: Only one archive may be given." >&2; exit 1; }
            ARCHIVE_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$ARCHIVE_FILE" ]; then
    usage >&2
    exit 1
fi

# Check if the archive file exists
if [ ! -f "$ARCHIVE_FILE" ]; then
    echo "ERROR: Archive file $ARCHIVE_FILE does not exist. Exiting."
    exit 1
fi

# Verify the archive against its checksum when dump_config.bash produced one.
CHECKSUM_FILE="$ARCHIVE_FILE.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    echo "Verifying archive against $CHECKSUM_FILE..."
    if ( cd "$(dirname "$ARCHIVE_FILE")" && sha256sum -c "$(basename "$CHECKSUM_FILE")" ); then
        echo "Checksum OK."
    else
        echo "ERROR: Checksum mismatch. The archive is corrupted or was modified." >&2
        exit 1
    fi
else
    echo "WARNING: No checksum file next to the archive; skipping integrity check."
fi

# Extract the archive to a temporary directory
temp_dir=$(mktemp -d)
echo "Extracting configuration archive to temporary directory: $temp_dir"
tar -xzf "$ARCHIVE_FILE" -C "$temp_dir"

# Show which machine the dump came from.
if [ -f "$temp_dir/manifest.txt" ]; then
    echo
    echo "--- Source machine ---"
    grep -E '^(created|hostname|user|os|kernel|architecture) ' "$temp_dir/manifest.txt" || true
    echo "Full details: manifest.txt inside the archive."
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
# The manifest stores paths relative to $HOME, which keeps dotfiles and nested
# paths such as .config/terminator working. The previous implementation globbed
# the extracted folder with "$temp_dir"/*, which silently skipped every entry
# whose name starts with a dot (.zshrc, .vimrc, .vim) and flattened the rest
# into $HOME under the wrong name.
MANIFEST_FILE="$temp_dir/RESTORE_MANIFEST"
DUMP_HOME="$temp_dir/home"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: No RESTORE_MANIFEST found in $ARCHIVE_FILE." >&2
    echo "ERROR: The archive predates the manifest format; recreate it with dump_config.bash." >&2
    rm -rf "$temp_dir"
    exit 1
fi

restored=0
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src_file="$DUMP_HOME/$rel"
    if [ ! -e "$src_file" ]; then
        echo "WARNING: $rel is listed in RESTORE_MANIFEST but missing from the archive. Skipping."
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
EXT_LIST="$temp_dir/info/vscode_extensions.txt"
if [ "$INSTALL_VSCODE_EXT" -eq 1 ]; then
    if [ ! -f "$EXT_LIST" ]; then
        echo "WARNING: No info/vscode_extensions.txt in the archive. Nothing to install."
    elif ! command -v code >/dev/null 2>&1; then
        echo "ERROR: --install-vscode-extensions was requested but the 'code' CLI is missing." >&2
        rm -rf "$temp_dir"
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

# Point at the informational lists before the temporary copy disappears.
if [ -d "$temp_dir/info" ]; then
    saved_info="$HOME/config_dump_info"
    rm -rf "$saved_info"
    cp -a "$temp_dir/info" "$saved_info"
    echo
    echo "Reference lists copied to $saved_info:"
    ls -1 "$saved_info" | sed 's/^/  /'
    echo "These are informational. Nothing from them is installed automatically."
fi

# Clean up temporary directory
echo "Cleaning up temporary directory: $temp_dir"
rm -rf "$temp_dir"

echo "Configuration files have been restored successfully."
