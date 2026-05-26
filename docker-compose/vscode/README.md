# code-server

VS Code in the browser with Docker CLI access for managing the homelab.

## Setup

```bash
# Create external resources
docker network create vscode
docker volume create vscode

# Create secrets
cp secrets/password.example secrets/password
cp secrets/sudo_password.example secrets/sudo_password
# Edit both files with your passwords

# Configure
cp .env.example .env
# Edit .env — set DOCKER_GID to match: stat -f '%g' /var/run/docker.sock

# Start
docker compose up -d
```

## Docker access

The container mounts `/var/run/docker.sock` and is added to the host's Docker GID, giving the terminal full `docker` and `docker compose` access.

## Access

- Web UI: `http://<host>:17425`
