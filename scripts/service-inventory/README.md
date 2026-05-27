# Service Inventory

Generates a markdown report of all services in the homelab — Docker containers,
host-level services, nginx proxy routes, and Pi-hole DNS entries — in a single
consolidated view.

## Usage

```bash
# Full inventory
scripts/service-inventory/service-inventory.sh

# Containers + proxy only
scripts/service-inventory/service-inventory.sh --no-non-containers --no-pihole

# Custom service filter for host processes
scripts/service-inventory/service-inventory.sh --filter "(jellyfin|plex|ollama)"
```

## Options

| Flag | Description |
|---|---|
| `--no-containers` | Skip Docker containers |
| `--no-non-containers` | Skip host-level services |
| `--no-nginx` | Skip Nginx Proxy Manager config |
| `--no-pihole` | Skip Pi-hole DNS entries |
| `--nginx-container NAME` | NPM container name (default: `nginx-proxy-manager`) |
| `--pihole-container NAME` | Pi-hole container name (default: `pihole-unbound`) |
| `--filter REGEX` | Extended regex for host service names to detect |
| `--output FILE` | Output file path |

## Output

Reports are saved to `reports/service-inventory-YYYYMMDD-HHMMSS.md` with tables
showing port mappings, proxy domains, SSL status, and DNS entries for each service.

## Requirements

- bash 3.2+
- Docker (for container discovery and NPM/Pi-hole integration)
- sudo access (for `lsof` to detect host services)
