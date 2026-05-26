# Nextcloud

Self-hosted file sync and collaboration platform with MariaDB backend.

## Setup

```bash
# Create external resources
docker network create nextcloud
docker volume create nextcloud-config
docker volume create nextcloud-data
docker volume create nextcloud-db

# Create secrets
cp secrets/db_password.example secrets/db_password
cp secrets/db_root_password.example secrets/db_root_password
# Edit both files with generated passwords (openssl rand -base64 32)

# Configure
cp .env.example .env

# Start
docker compose up -d
```

## Access

- Web UI: `https://<host>:17411`

## Notes

- The app waits for MariaDB to be healthy before starting.
- Passwords are injected via Docker secrets (`*_FILE` env vars), not plaintext environment variables.
- Data is stored in the `nextcloud-data` volume; back this up regularly.
