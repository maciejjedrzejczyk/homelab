# <Service Name>

<One-line description>.

## Setup

```bash
# Create external resources
docker network create <service-name>
docker volume create <service-name>-data

# Configure
cp .env.example .env
# Edit .env with your values

# Start
docker compose up -d
```

## Access

- Web UI: `http://<host>:<port>`
