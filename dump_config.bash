#!/usr/bin/env bash
set -euo pipefail

# Check if the folder path argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <destination_folder>"
    exit 1
fi

DEST_FOLDER="$1"

# Create the destination folder if it doesn't exist
mkdir -p "$DEST_FOLDER"

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

# Copy Zsh history
copy_if_exists "$HOME/.zsh_history" "$DEST_FOLDER/zsh_history"

# Copy Midnight Commander (mc) configuration
copy_if_exists "$HOME/.config/mc" "$DEST_FOLDER/.config/mc"

# Copy install_config.bash script
copy_if_exists "$PWD/install_config.bash" "$DEST_FOLDER/install_config.bash"

# Create an archive of all extracted files and install_config.bash
ARCHIVE_FILE="$DEST_FOLDER/config_backup_$(date +%Y%m%d).tar.gz"
echo "Creating archive $ARCHIVE_FILE..."
tar -czf "$ARCHIVE_FILE" -C "$DEST_FOLDER" . 
echo "Archive created successfully: $ARCHIVE_FILE"

# Final message
echo "Configuration files have been successfully copied to $DEST_FOLDER."