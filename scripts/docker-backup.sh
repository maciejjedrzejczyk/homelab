#!/bin/bash

# Default values
compose_path=""
target_path="."
declare -a excluded_volumes

# Function to display usage information
usage() {
    echo "Usage: $0 [-c <compose_path>] [-t <target_path>] [-e <excluded_volume>]..."
    echo "  -c <compose_path>    Path to the compose folder (optional)"
    echo "  -t <target_path>     Target path for the backup file (default: current directory)"
    echo "  -e <excluded_volume> Volume to exclude from backup (can be used multiple times)"
    exit 1
}

# Parse command-line options
while getopts ":c:t:e:" opt; do
    case ${opt} in
        c )
            compose_path=$OPTARG
            ;;
        t )
            target_path=$OPTARG
            ;;
        e )
            excluded_volumes+=("$OPTARG")
            ;;
        \? )
            usage
            ;;
    esac
done

# Function to check if a volume should be excluded
is_excluded() {
    local volume=$1
    for excluded in "${excluded_volumes[@]}"; do
        if [[ "$volume" == "$excluded" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to stop all running containers and store their IDs
stop_containers() {
    echo "Stopping all running containers..."
    running_containers=$(docker ps -q)
    if [ -n "$running_containers" ]; then
        docker stop $running_containers
        echo "All containers stopped."
    else
        echo "No running containers found."
    fi
}

# Function to backup all Docker volumes and create the final compressed backup
backup_volumes_and_compose() {
    echo "Starting backup process..."
    
    # Get current date and time
    current_date=$(date +"%Y-%m-%d")
    current_time=$(date +"%H-%M-%S")
    
    # Create backup subfolder
    backup_folder="${current_date}-${current_time}-backup"
    mkdir -p "$backup_folder"
    echo "Created backup folder: $backup_folder"
    
    # Get list of all Docker volumes
    volumes=$(docker volume ls -q)
    
    for volume in $volumes
    do
        if is_excluded "$volume"; then
            echo "Skipping excluded volume: $volume"
            continue
        fi

        backup_name="${volume}-${current_date}-${current_time}.tar.gz"
        echo "Backing up volume: $volume to $backup_name"
        
        # Create a temporary container to mount the volume and create a tar archive
        docker run --rm -v $volume:/source:ro -v $(pwd)/$backup_folder:/backup alpine tar czf /backup/$backup_name -C /source .
        
        echo "Backup completed for $volume"
    done
    
    echo "All volume backups completed."
    
    # Compress the backup folder and compose folder (if specified)
    compressed_backup="${current_date}-${current_time}-backup.tar.gz"
    if [ -n "$compose_path" ] && [ -d "$compose_path" ]; then
        tar czf "$compressed_backup" "$backup_folder" -C "$(dirname "$compose_path")" "$(basename "$compose_path")"
        echo "Created compressed backup including compose folder: $compressed_backup"
    else
        tar czf "$compressed_backup" "$backup_folder"
        echo "Created compressed backup: $compressed_backup"
    fi
    
    # Move the compressed backup to the target path
    mv "$compressed_backup" "$target_path"
    echo "Moved compressed backup to: $target_path"
    
    # Remove the original backup folder
    rm -rf "$backup_folder"
    echo "Removed original backup folder"
}

# Function to restart previously stopped containers
restart_containers() {
    echo "Restarting previously stopped containers..."
    if [ -n "$running_containers" ]; then
        docker start $running_containers
        echo "All previously running containers have been restarted."
    else
        echo "No containers to restart."
    fi
}

# Main execution
echo "Starting Docker management script..."

# Store the list of running containers
running_containers=$(docker ps -q)

# Stop all running containers
stop_containers

# Backup all volumes and create compressed backup with compose folder (if specified)
backup_volumes_and_compose

# Restart previously running containers
restart_containers

echo "Script execution completed."