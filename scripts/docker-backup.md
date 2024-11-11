# Docker Backup Script

## Overview

This bash script is designed to create a backup of all Docker volumes and the Docker Compose configuration (if specified). The script stops all running containers, backs up the volumes, creates a compressed archive, and then restarts the previously running containers.

## Quick Start

To use the script, you can run it with the following command-line options:

```
./docker-backup.sh [-c <compose_path>] [-t <target_path>] [-e <excluded_volume>]...
```

- `-c <compose_path>`: Specify the path to the Docker Compose folder (optional)
- `-t <target_path>`: Specify the target path for the backup file (default: current directory)
- `-e <excluded_volume>`: Specify a volume to exclude from the backup (can be used multiple times)

Example usage:

```
./docker-backup.sh -c /path/to/compose -t /backup/directory -e volume1 -e volume2
```

## Functionality

The script performs the following main tasks:

1. **Usage Display**: The `usage()` function displays the usage information for the script.
2. **Command-line Options Parsing**: The script uses the `getopts` command to parse the command-line options.
3. **Volume Exclusion Check**: The `is_excluded()` function checks if a given volume should be excluded from the backup.
4. **Container Stopping**: The `stop_containers()` function stops all running containers and stores their IDs.
5. **Volume Backup and Compose Compression**: The `backup_volumes_and_compose()` function:
   - Creates a backup folder with the current date and time
   - Backs up each Docker volume (excluding the ones specified)
   - Compresses the backup folder and the Docker Compose folder (if specified)
   - Moves the compressed backup to the target path
   - Removes the original backup folder
6. **Container Restart**: The `restart_containers()` function restarts the previously running containers.

The script starts by displaying a message indicating the start of the execution, then performs the backup process, and finally restarts the previously running containers before completing the execution.