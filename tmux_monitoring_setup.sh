#!/usr/bin/env bash
# This script sets up a tmux session with multiple panes for system monitoring.
# It is a Proof of Concept (POC) and may require passwordless sudo for some commands.
# To configure passwordless sudo, edit the sudoers file using 'sudo visudo' and add:
# your_username ALL=(ALL) NOPASSWD: /usr/sbin/iotop, /usr/sbin/iftop

set -euo pipefail

SESSION_NAME="monitoring"

# Check if tmux session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Tmux session '$SESSION_NAME' already exists. Attaching to it."
    tmux attach-session -t "$SESSION_NAME"
    exit 0
fi

# Create a new tmux session
echo "Creating new tmux session: $SESSION_NAME"
tmux new-session -d -s "$SESSION_NAME" -n "System Monitoring"

# Split the window into panes and run commands
# Pane 1: htop (process monitoring)
tmux send-keys -t "$SESSION_NAME":0.0 "htop" C-m

# Pane 2: iotop (I/O usage)
tmux split-window -h -t "$SESSION_NAME":0.0
sleep 1
tmux send-keys -t "$SESSION_NAME":0.1 "sudo -S iotop <<< 'your_password_here'" C-m

# Pane 3: iftop (network usage)
tmux split-window -v -t "$SESSION_NAME":0.0
sleep 1
tmux send-keys -t "$SESSION_NAME":0.2 "sudo -S iftop <<< 'your_password_here'" C-m

# # Pane 4: nicstat (network statistics)
# tmux split-window -v -t "$SESSION_NAME":0.1
# sleep 1
# tmux send-keys -t "$SESSION_NAME":0.3 "nicstat" C-m

# # Pane 5: Disk usage
# tmux split-window -v -t "$SESSION_NAME":0.2
# sleep 1
# tmux send-keys -t "$SESSION_NAME":0.4 "df -h" C-m

# # Pane 6: Memory usage
# tmux split-window -v -t "$SESSION_NAME":0.3
# sleep 1
# tmux send-keys -t "$SESSION_NAME":0.5 "watch -n 1 free -h" C-m

# Select the first pane
sleep 1
tmux select-pane -t "$SESSION_NAME":0.0

# Attach to the session
echo "Attaching to tmux session: $SESSION_NAME"
tmux attach-session -t "$SESSION_NAME"
