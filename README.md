# dev_machine_setup

This is repository with setup script and configuration for may mostly embedded C++ development machines.

## Disclaimer

 Written using AI tools as I always forget this strange bash language constructs.

# Running `setup_machine.bash` in a Docker Container

This guide explains how to run the `setup_machine.bash` script in a safe and isolated Docker environment.

## Prerequisites

- Docker installed on your system.

## Steps to Run

1. **Build the Docker Image**

   Open a terminal in the directory containing the `Dockerfile` and `setup_machine.bash` script, then run:

   ```bash
   docker build --build-arg LOCAL_USER=yourUserName -t setup-machine .
   ```

   Replace `yourUserName` with the desired username for the non-root user inside the container. This will create a Docker image named `setup-machine`.

2. **Run the Docker Container**

   Start a container from the image:

   ```bash
   docker run -it --rm setup-machine
   ```

   This will launch an interactive terminal session inside the container.

3. **Run the Script**

   Inside the container, execute the `setup_machine.bash` script:

   ```bash
   ./setup_machine.bash
   ```

   The script will run in the isolated environment of the container.

4. **Verify the Script**

   Check the output of the script to ensure it runs without errors. Since the container is isolated, any changes made by the script will not affect your host system.

5. **Exit the Container**

   To exit the container, type:

   ```bash
   exit
   ```

   The container will be automatically removed because of the `--rm` flag used in the `docker run` command.

## Notes

- The Docker container uses an Ubuntu 24.04 base image.
- The script is run as a non-root user for safety.
- The container is ephemeral; any changes made inside it will be lost when it is stopped.

## Proof of Concept: `tmux_monitoring_setup.sh`

The `tmux_monitoring_setup.sh` script is a Proof of Concept (PoC) designed to set up a `tmux` session for system monitoring. It creates multiple panes within a `tmux` session, each running a different monitoring tool.

### Features

- **System Monitoring**: Includes tools like `htop`, `iotop`, and `iftop` for monitoring system performance, disk I/O, and network traffic, respectively.
- **Passwordless `sudo`**: To ensure smooth execution of commands requiring elevated privileges, the script includes instructions for setting up passwordless `sudo` for specific commands.

### Usage

1. **Run the Script**:

   ```bash
   ./tmux_monitoring_setup.sh
   ```

   This will launch a `tmux` session with pre-configured panes for monitoring.

2. **Exit the Session**:

   To exit the `tmux` session, type:

   ```bash
   exit
   ```

   or press `Ctrl-b` followed by `d` to detach the session.

### Notes

- This script is a PoC and may require additional customization for specific use cases.
- Ensure that the required monitoring tools (`htop`, `iotop`, `iftop`) are installed on your system before running the script.

## Configuration Management Scripts

### `dump_config.bash`

The `dump_config.bash` script is used to extract user configurations from the system and create a compressed archive for backup purposes. This script ensures that important configuration files are preserved and can be restored later.

#### Features

- Copies configurations for tools like VIM, XFCE, Visual Studio Code, Zsh, and Midnight Commander.
- Creates destination directories as needed.
- Generates a compressed archive containing the extracted configurations and the `install_config.bash` script.

#### Usage

1. **Run the Script**:

   ```bash
   ./dump_config.bash
   ```

   This will create a compressed archive in the `configs/` directory.

2. **Verify the Archive**:

   Ensure that the archive file (e.g., `config_backup_<date>.tar.gz`) is created successfully in the `configs/` directory.

### `install_config.bash`

The `install_config.bash` script is used to restore configurations from the archive created by `dump_config.bash`. It ensures that existing files are backed up before being replaced.

#### Features

- Extracts the archive into a temporary directory.
- Copies configuration files to their original locations.
- Creates backups of existing files before overwriting them.

#### Usage

1. **Run the Script**:

   ```bash
   ./install_config.bash <config_archive.tar.gz>
   ```

   Replace `<config_archive.tar.gz>` with the path to the archive file.

2. **Verify Restoration**:

   Check that the configuration files have been restored to their original locations and that backups of existing files have been created.

### Notes

- Ensure that the `dump_config.bash` script is run before using `install_config.bash` to create a valid archive.
- Both scripts are designed to work seamlessly together for configuration management.