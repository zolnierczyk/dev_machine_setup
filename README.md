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