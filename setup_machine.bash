#!/usr/bin/env bash
set -euo pipefail

# Additional logging setup
LOG_FILE="/var/log/setup_machine.log"
exec > >(tee -a "$LOG_FILE") 2>&1

print_header() {
    echo "---------------------------------------------------------------------"
    echo "$1"
    echo "---------------------------------------------------------------------"
}

# Welcome message
print_header "Automatic Xubuntu Setup Script by Gemini 2.5 Pro"

echo "Starting package list update..."
sudo apt update
echo "Package list updated."
echo ""

# --- SECTION: INSTALLATION OF BASIC PACKAGES ---
print_header "Installing basic and identified packages..."

# List of packages identified from history and commonly used
packages_to_install=(
    # System and network tools
    nmap
    curl
    wget # For downloading files
    tcpdump
    net-tools # Contains netstat, ifconfig, etc.
    iftop
    traceroute
    moreutils # Contains 'ts' (timestamp)
    htop
    tiptop # Alternative to htop
    iotop # Disk I/O monitoring
    dstat # Versatile resource statistics
    sysstat # Contains mpstat, iostat, sar, pidstat
    nicstat # Network interface statistics
    smem # Memory usage reporting tool
    tree # Display directory tree
    gnupg # For GPG key management
    lsb-release # For distribution information
    apt-transport-https
    ca-certificates
    isc-dhcp-server # DHCP server, if you use it locally
    strongswan # VPN client
    strongswan-plugin-eap-mschapv2 # Plugin for strongswan
    libcharon-extra-plugins # Plugins for strongswan
    libstrongswan-extra-plugins # Plugins for strongswan
    libstrongswan-standard-plugins # Plugins for strongswan
    libcharon-standard-plugins # Plugins for strongswan
    xl2tpd # L2TP VPN client
    nfs-common # For NFS support
    cifs-utils # For SMB/CIFS share support
    keyutils # For kernel key management
    pass # Password manager
    gnupg2 # Newer version of GnuPG
    software-properties-common # For PPA repository management
    openssl
    pax-utils # Contains dumpelf

    # Developer tools
    git
    vim
    meld # File and directory comparison tool
    build-essential # Basic compilation tools (gcc, g++, make)
    python3-dev
    python3-pip
    python3-venv # For creating Python 3 virtual environments
    cmake
    ninja-build # Ninja build system
    ccache # Compiler cache
    valgrind # Memory debugging tool
    gdb # GNU debugger
    doxygen # Documentation generator
    graphviz # For graph generation (used by doxygen)
    shellcheck # For shell script linting
    libssl-dev
    libopus-dev
    pkg-config
    libjsoncpp-dev
    libjpeg-turbo8-dev
    libavutil-dev
    libavformat-dev
    libcpprest-dev # Microsoft C++ REST SDK
    libboost-atomic-dev
    libboost-thread-dev
    libboost-system-dev
    libboost-regex-dev
    libboost-random-dev
    libboost-chrono-dev
    libboost-locale-dev
    libboost-program-options-dev
    libcurl4-openssl-dev # Dependency for libcpprest-dev and others
    libopencv-dev # OpenCV for image processing

    # Other tools
    tldr # Simplified man pages
    unzip
    virtualenv # For creating Python virtual environments (general)
    imagemagick # For image processing
    exif # For reading EXIF metadata from images
    pylint # Linter for Python
    ipython # Interactive Python shell
    vlc # Multimedia player
    ffplay # Multimedia player from FFmpeg
    ffprobe # Stream analysis tool from FFmpeg
    ffmpeg # Multimedia conversion and streaming tool
    baobab # Disk usage analyzer
    blender # 3D graphics software
    ntp # Network Time Protocol (replaced by systemd-timesyncd, but might be needed)
    chrony # NTP implementation, often used as a replacement for ntpd
    shutter # Screenshot tool
    gimp # Raster graphics editor
    inkscape # Vector graphics editor
    xscreensaver # Screensaver
    minicom # Serial communication program
    putty # SSH, Telnet, Rlogin, Serial client
    zsh # Z shell, an alternative shell
    oh-my-zsh # Framework for managing Zsh configuration
    fonts-powerline # Powerline fonts for Zsh
)

# Loop to install all packages from the list
for pkg in "${packages_to_install[@]}"; do
    echo "Attempting to install/update $pkg..."
    sudo apt install -y "$pkg"
    if [ $? -eq 0 ]; then
        echo "Package $pkg processed successfully (installed/updated or already present)."
    else
        echo "ERROR: Failed to process package $pkg."
    fi
done
print_header "Package installation process finished."
echo ""

# --- SECTION: INSTALLATION OF OH MY ZSH ---
print_header "Installing Oh My Zsh environment..."

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Oh My Zsh not found. Installing..."
    sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "Oh My Zsh installed successfully."
else
    echo "Oh My Zsh is already installed. Skipping installation."
fi

# Set Zsh as the default shell
echo "Please manually change the default shell to Zsh using: chsh -s /usr/bin/zsh"

print_header "Oh My Zsh installation and configuration completed."
echo ""

# --- SECTION: MANUAL DEBIAN PACKAGE INSTALLATION ---
print_header "Installing Visual Studio Code and Slack via .deb packages..."

# Temporary directory for downloading .deb files
TEMP_DIR="/tmp/deb_packages"
mkdir -p "$TEMP_DIR"
# Cleaning up temporary files on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

VSCODE_DEB="$TEMP_DIR/code.deb"
SLACK_DEB="$TEMP_DIR/slack.deb"

download_and_install() {
    local url=$1
    local output=$2
    local name=$3

    echo "Downloading $name..."
    if ! wget -qO "$output" "$url"; then
        echo "ERROR: Failed to download $name. Exiting."
        exit 1
    fi

    echo "Installing $name..."
    if ! sudo apt install -y "$output"; then
        echo "ERROR: Failed to install $name. Exiting."
        exit 1
    fi
}

download_and_install "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" "$VSCODE_DEB" "Visual Studio Code"
download_and_install "https://downloads.slack-edge.com/linux_releases/slack-desktop-latest-amd64.deb" "$SLACK_DEB" "Slack"

print_header "Manual installation of Visual Studio Code and Slack finished."
echo ""

# --- SECTION: COPYING DOTFILES ---
# Place your dotfile copying logic here
# Example:
# echo "---------------------------------------------------------------------"
# echo "Copying configuration files (dotfiles)..."
# echo "---------------------------------------------------------------------"
# DOTFILES_REPO_URL="https://github.com/YOUR_USER/YOUR_DOTFILES_REPO.git" # Change to your repository URL
# DOTFILES_DIR="$HOME/.dotfiles" # Directory where you'll clone the repository
#
# if [ -d "$DOTFILES_DIR" ]; then
#   echo "Directory $DOTFILES_DIR already exists. Updating..."
#   cd "$DOTFILES_DIR"
#   git pull
#   cd "$HOME"
# else
#   echo "Cloning dotfiles repository..."
#   git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
# fi
#
# # Example using 'stow' to link files (if you use stow)
# # sudo apt install -y stow # Make sure stow is installed
# # cd "$DOTFILES_DIR"
# # stow CONFIG_DIRECTORY_NAME # e.g., stow zsh, stow vim
# # cd "$HOME"
#
# # Alternatively, manual creation of symlinks:
# # ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
# # ln -sf "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"
# # ...and so on for other files
#
# echo "Dotfiles copying finished."
# echo "---------------------------------------------------------------------"
# echo ""

# Final message
echo "---------------------------------------------------------------------"
echo "Script execution finished."
echo "Restart your terminal or computer to apply changes (e.g., default shell change)."
echo "If you encounter any issues, please check the log file at $LOG_FILE."
echo "Please check git setup: "
echo "Name: $(git config --global user.name)"
echo "Email: $(git config --global user.email)"
echo "---------------------------------------------------------------------"

exit 0
