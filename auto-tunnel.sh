#!/bin/bash

# Parameter passed by systemd
PARAMS=$1

# Default configuration file
CONFIG_FILE="/etc/default/auto-tunnel"

# Validate parameter
if [[ -z "$PARAMS" ]]; then
    echo "No parameter passed to the script."
    exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install it."
    exit 1
fi

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file $CONFIG_FILE not found."
    exit 1
fi

SSH_USER=$(jq -r '.ssh_user' "$CONFIG_FILE")
SSH_SERVER=$(jq -r '.ssh_server' "$CONFIG_FILE")
SSH_PORT=$(jq -r '.ssh_port' "$CONFIG_FILE")
SERVER_ALIVE_INTERVAL=$(jq -r '.server_alive_interval' "$CONFIG_FILE")
SERVER_ALIVE_COUNT_MAX=$(jq -r '.server_alive_count_max' "$CONFIG_FILE")

# Extract the monitoring port and mappings from the parameter
MONITORING_PORT=$(echo "$PARAMS" | cut -d'_' -f1)
MAPPING_IDS=$(echo "$PARAMS" | cut -d'_' -f2-)

# Validate the monitoring port
if ! [[ "$MONITORING_PORT" =~ ^[0-9]+$ ]]; then
    echo "Invalid monitoring port specified: $MONITORING_PORT"
    exit 1
fi

# Construct the autossh command with the extracted monitoring port
AUTOSSH_CMD="/usr/bin/autossh -N -M $MONITORING_PORT \
    -o \"ServerAliveInterval=$SERVER_ALIVE_INTERVAL\" \
    -o \"ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX\" \
    -o \"ExitOnForwardFailure=yes\" \
    -p $SSH_PORT $SSH_USER@$SSH_SERVER"

# Split the mappings
IFS="_" read -ra MAPPING_IDS <<< "$MAPPING_IDS"

# Add tunnels for each mapping
for ID in "${MAPPING_IDS[@]}"; do
    # Fetch mapping details from JSON
    MAPPING=$(jq -r ".mappings[\"$ID\"]" "$CONFIG_FILE")
    if [[ "$MAPPING" == "null" ]]; then
        echo "Mapping $ID not found in configuration."
        continue
    fi

    TYPE=$(jq -r '.type' <<< "$MAPPING")
    BIND_HOST=$(jq -r '.bind_host' <<< "$MAPPING")
    LOCAL_HOST=$(jq -r '.local_host' <<< "$MAPPING")
    LOCAL_PORT=$(jq -r '.local_port' <<< "$MAPPING")
    REMOTE_PORT=$(jq -r '.remote_port' <<< "$MAPPING")

    # Add the appropriate forwarding rule
    if [[ "$TYPE" == "R" ]]; then
        AUTOSSH_CMD+=" -R ${BIND_HOST}:${REMOTE_PORT}:${LOCAL_HOST}:${LOCAL_PORT}"
    elif [[ "$TYPE" == "L" ]]; then
        AUTOSSH_CMD+=" -L ${BIND_HOST}:${LOCAL_PORT}:${LOCAL_HOST}:${REMOTE_PORT}"
    else
        echo "Invalid mapping type $TYPE for $ID."
        continue
    fi
done

# Run the autossh command
echo "Executing: $AUTOSSH_CMD"
eval "$AUTOSSH_CMD"

