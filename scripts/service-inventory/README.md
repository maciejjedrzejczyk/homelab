# Service Inventory

Generates a report of all services in the homelab — Docker containers,
host-level services, Nginx Proxy Manager routes, and Pi-hole DNS entries.
Supports markdown and JSON output, and can diff against a previous report to
show what changed.

## Usage

```bash
# Full inventory (markdown)
scripts/service-inventory/service-inventory.sh

# JSON output
scripts/service-inventory/service-inventory.sh --format json

# Diff against previous report (auto-detects most recent)
scripts/service-inventory/service-inventory.sh --diff

# Diff against a specific report
scripts/service-inventory/service-inventory.sh --diff reports/service-inventory-20260101-030000.md

# Containers + proxy only, JSON format
scripts/service-inventory/service-inventory.sh --no-non-containers --no-pihole --format json
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
| `--format FORMAT` | Output format: `markdown` (default) or `json` |
| `--diff [FILE]` | Compare against previous report; shows added/removed services |
| `--output FILE` | Output file path |

## Output Formats

**Markdown** — human-readable tables with port mappings, proxy domains, SSL
status, and DNS entries.

**JSON** — machine-readable structure for integration with other tools:

```json
{
  "generated": "2026-05-27T10:00:00Z",
  "containers": [{"name": "...", "image": "...", "status": "...", "external_ports": "...", "internal_ports": "..."}],
  "proxy_hosts": [{"domain": "...", "target": "...", "ssl": "...", "port": "..."}],
  "dns_entries": [{"hostname": "...", "ip": "..."}]
}
```

## Diff Mode

When run with `--diff`, the script compares the current inventory against the
most recent previous report (or a specified file) and prints:

```
━━━ Changes since service-inventory-20260526-030000.md ━━━

  ✚ Added:
    + nextcloud-app
    + nextcloud-db

  ✖ Removed:
    - old-container
```

Useful for cron-based drift detection — pipe the diff output to a notification
system to alert on unexpected changes.

## Requirements

- bash 3.2+
- Docker (for container discovery and NPM/Pi-hole integration)
- sudo access (for `lsof` to detect host services)
