#!/usr/bin/env bash
set -euo pipefail

# Define variables
DOCKER_IMAGE="setup-machine-test"

# Build the Docker image
function build_docker_image() {
    echo "Building Docker image..."
    docker build -t "$DOCKER_IMAGE" .
    echo "Docker image built successfully."
}

# Run the script inside the Docker container
function run_script_in_docker() {
    echo "Running setup_machine.bash inside Docker container..."
    docker run --rm "$DOCKER_IMAGE" /bin/bash -c "./setup_machine.bash"
    echo "Script executed successfully inside Docker container."
}

# Main function
function main() {
    build_docker_image
    run_script_in_docker
    echo "All tests passed successfully."
}

main
