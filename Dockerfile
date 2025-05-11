# Use an official Ubuntu image as the base
FROM ubuntu:24.04

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install necessary dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    locales \
    && locale-gen en_US.UTF-8

# Set the locale
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Define a build argument for the local user name
ARG LOCAL_USER=localUser

# Create a non-root user for running the script
RUN useradd -ms /bin/bash $LOCAL_USER && echo "$LOCAL_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the non-root user
USER $LOCAL_USER
WORKDIR /home/$LOCAL_USER

# Copy the setup script into the container
COPY setup_machine.bash /home/$LOCAL_USER/setup_machine.bash

# Make the script executable
RUN sudo chmod +x /home/$LOCAL_USER/setup_machine.bash

# Entry point to run the script
CMD ["/bin/bash"]
