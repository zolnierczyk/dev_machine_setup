#!/usr/bin/env bash
set -euo pipefail

# Check if the archive file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <config_archive.tar.gz>"
    exit 1
fi

ARCHIVE_FILE="$1"

# Check if the archive file exists
if [ ! -f "$ARCHIVE_FILE" ]; then
    echo "ERROR: Archive file $ARCHIVE_FILE does not exist. Exiting."
    exit 1
fi

# Extract the archive to a temporary directory
temp_dir=$(mktemp -d)
echo "Extracting configuration archive to temporary directory: $temp_dir"
tar -xzf "$ARCHIVE_FILE" -C "$temp_dir"

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
    cp -r "$src_file" "$dest_file"
}

# Iterate over extracted files and copy them to their original locations
for file in "$temp_dir"/*; do
    dest_file="$HOME/$(basename "$file")"
    copy_with_backup "$file" "$dest_file"
done

# Clean up temporary directory
echo "Cleaning up temporary directory: $temp_dir"
rm -rf "$temp_dir"

echo "Configuration files have been restored successfully."
