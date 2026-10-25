#!/usr/bin/env bash
set -euo pipefail

# Additional logging setup
LOG_FILE="/tmp/setup_machine.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Check if the script is running on Ubuntu 26.x
if ! grep -q "DISTRIB_RELEASE=26\." /etc/lsb-release; then
    echo "ERROR: This script is designed to run on Ubuntu 26.x. Exiting."
    exit 1
fi

print_header() {
    echo "---------------------------------------------------------------------"
    echo "$1"
    echo "---------------------------------------------------------------------"
}

# Welcome message
print_header "Automatic Xubuntu Setup Script by Gemini 2.5 Pro and ChatGPT 4.0"
echo "This script will install and configure essential packages for your Xubuntu system."
echo "Please ensure you have a stable internet connection and sufficient permissions to install packages."
echo ""

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
    masscan
    curl
    wget # For downloading files
    terminator # Terminal emulator
    tmux # Terminal multiplexer
    tcpdump
    net-tools # Contains netstat, ifconfig, etc.
    iftop
    traceroute
    moreutils # Contains 'ts' (timestamp)
    htop
    tiptop # Alternative to htop
    iotop # Disk I/O monitoring 
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
    libstrongswan-standard-plugins # Plugins for strongswan
    libstrongswan-extra-plugins # Plugins for strongswan
    libcharon-extra-plugins # Plugins for strongswan
    xl2tpd # L2TP VPN client
    nfs-common # For NFS support
    samba # SMB/CIFS server
    cifs-utils # For SMB/CIFS share support
    keyutils # For kernel key management
    pass # Password manager
    gnupg2 # Newer version of GnuPG
    software-properties-common # For PPA repository management
    openssl
    pax-utils # Contains dumpelf
    netcat-openbsd
    wireshark # Network protocol analyzer
    tcpflow # TCP flow analysis
    tcpick # TCP packet capture
    mtr # Network diagnostic tool

    # Developer tools
    git
    gitk
    git-gui
    git-lfs # Git Large File Storage
    vim
    mc # Midnight Commander, a file manager
    meld # File and directory comparison tool
    build-essential # Basic compilation tools (gcc, g++, make)
    clang # C/C++ compiler
    clang-format # Code formatter for C/C++
    clang-tidy # C++ code analysis tool
    clang-tools # Additional tools for Clang
    python3-dev
    python3-pip
    python3-venv # For creating Python 3 virtual environment
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
    unzip
    virtualenv # For creating Python virtual environments (general)
    imagemagick # For image processing
    exif # For reading EXIF metadata from images
    pylint # Linter for Python
    vlc # Multimedia player
    ffmpeg # Multimedia conversion and streaming tool
    baobab # Disk usage analyzer
    ntp # Network Time Protocol (replaced by systemd-timesyncd, but might be needed)
    chrony # NTP implementation, often used as a replacement for ntpd
    shutter # Screenshot tool
    gimp # Raster graphics editor
    xscreensaver # Screensaver
    minicom # Serial communication program
    putty # SSH, Telnet, Rlogin, Serial client
    zsh # Z shell, an alternative shell
    fonts-powerline # Powerline fonts for Zsh
)

# Loop to install all packages from the list
for pkg in "${packages_to_install[@]}"; do
    echo "---------------------------------------------------------------------"
    echo "Attempting to install/update $pkg..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
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

# --- SECTION: INSTALLATION OF GitHub CLI ---
print_header "Installing GitHub CLI..."
# Check if gh is already installed
if command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is already installed. Skipping installation."
else
    echo "GitHub CLI (gh) not found. Installing..."
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
            && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y
fi

CURRENT_USER="${USER:-$(id -un)}"

# --- SECTION: INSTALLATION OF DOCKER ---
print_header "Installing Docker..."
if command -v docker >/dev/null 2>&1; then
    echo "Docker is already installed. Skipping installation."
else
    echo "Docker not found. Installing from the official Docker repository..."
    sudo apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if getent group docker >/dev/null; then
    sudo usermod -aG docker "$CURRENT_USER"
fi
print_header "Docker installation finished."
echo ""

# --- SECTION: INSTALLATION OF VIRTUALBOX ---
print_header "Installing VirtualBox..."
# Pre-accept the Oracle extension pack license so apt does not prompt
echo "virtualbox-ext-pack virtualbox-ext-pack/license select true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    virtualbox virtualbox-ext-pack virtualbox-guest-additions-iso
if getent group vboxusers >/dev/null; then
    sudo usermod -aG vboxusers "$CURRENT_USER"
fi
print_header "VirtualBox installation finished."
echo ""

# --- SECTION: MANUAL DEBIAN PACKAGE INSTALLATION ---
print_header "Installing Visual Studio Code via .deb package..."

# Temporary directory for downloading .deb files
TEMP_DIR="/tmp/deb_packages"
mkdir -p "$TEMP_DIR"
# Cleaning up temporary files on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

VSCODE_DEB="$TEMP_DIR/code.deb"

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
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y "$output"; then
        echo "ERROR: Failed to install $name. Exiting."
        exit 1
    fi
}

download_and_install "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" "$VSCODE_DEB" "Visual Studio Code"
print_header "Manual installation of Visual Studio Code finished."
echo ""

# --- SECTION: COPYING DOTFILES ---
# This section has been removed. Use dump_config.bash to extract configurations
# and install_config.bash to install them on a new machine.

print_header Installing VIM plugins...
curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Final message
echo "---------------------------------------------------------------------"
echo "Script execution finished."
echo "Restart your terminal or computer to apply changes (e.g., default shell change)."
echo "If you encounter any issues, please check the log file at $LOG_FILE."
echo "Remember to manually:"
echo " - change the default shell to Zsh using: chsh -s /usr/bin/zsh"
echo " - do in vim :PlugInstall to install plugins."
echo " - log out and back in to apply 'docker' and 'vboxusers' group membership."
echo " - if Secure Boot is enabled, enroll the MOK key so the vboxdrv module can load."
echo "Please check git setup: "
echo "Name: $(git config --global user.name)"
echo "Email: $(git config --global user.email)"
echo "---------------------------------------------------------------------"

exit 0
