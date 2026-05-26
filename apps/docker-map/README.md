# Docker Map

Interactive real-time visualization of Docker resources and their relationships. Built for homelab owners who want to understand and navigate their container infrastructure at a glance.

Connects to the Docker daemon via WebSocket for live updates — start a container, and it appears on the graph instantly.

## Quick Start

**Local:**
```bash
npm install
./docker-map.sh start
# → http://localhost:3009
```

**Docker:**
```bash
docker compose up -d --build
```

## Features

- **Live updates** — WebSocket connection streams Docker events; graph updates in real-time as containers start/stop
- **Health indicators** — container borders reflect state: green=healthy, red=unhealthy, yellow=update available, dimmed=exited
- **Project grouping** — containers are visually clustered by their Compose project
- **Search** — type to find and zoom to any node
- **Update detection** — compares local image digests to flag stale containers
- **Reverse proxy mapping** — integrates with Nginx Proxy Manager API to show domain→container routing
- **Compose enrichment** — overlays env vars, secrets, and file references from compose files
- **Filtering** — toggle visibility by resource type

## Configuration

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3009` | Server port |
| `DOCKER_SOCKET` | `/var/run/docker.sock` | Docker socket path |
| `COMPOSE_ROOT` | `../../docker-compose` | Path to compose files for enrichment |
| `NPM_API` | `http://localhost:17413` | Nginx Proxy Manager API URL |
| `NPM_EMAIL` | _(empty)_ | NPM admin email (enables domain mapping) |
| `NPM_PASSWORD` | _(empty)_ | NPM admin password |

## Architecture

```
Browser ←── WebSocket ──→ Node.js server ←── Docker Engine API
                                         ←── Docker Events stream
                                         ←── NPM REST API
                                         ←── Compose YAML files
```

The server queries Docker once on connection, then subscribes to the event stream. Any container/network/volume change triggers a debounced graph rebuild broadcast to all connected clients.

## Requirements

- Node.js 18+ (local) or Docker (containerized)
- Docker daemon accessible via socket
- _(Optional)_ Nginx Proxy Manager for domain mapping
