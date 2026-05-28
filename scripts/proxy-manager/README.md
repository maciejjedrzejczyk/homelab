# Proxy Manager

Maps running Docker containers to Nginx Proxy Manager proxy hosts, checks
certificate expiry, and offers renewal or creation of new proxy hosts with
Let's Encrypt SSL via DNS challenge.

## Setup

```bash
cp config.env.example config.env
# Edit config.env with your NPM credentials and DuckDNS token
```

## Usage

```bash
# Report only — show mapping and cert status
scripts/proxy-manager/proxy-manager.sh --check

# Interactive — offer renewal for expiring certs, creation for unmatched containers
scripts/proxy-manager/proxy-manager.sh
```

## What it does

1. Scans all running containers with exposed ports
2. Matches each to an existing NPM proxy host (by port, project name, or domain)
3. For matched hosts: checks SSL certificate expiry against the configured threshold
4. For expiring certs: offers to renew via the NPM API
5. For unmatched containers: offers to create a new proxy host + SSL certificate

## Configuration

| Variable | Description |
|---|---|
| `NPM_API_URL` | NPM admin API URL |
| `NPM_EMAIL` / `NPM_PASSWORD` | NPM admin credentials |
| `DNS_PROVIDER` | DNS provider for cert challenges (default: `duckdns`) |
| `DNS_CREDENTIALS` | Provider-specific credentials string |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |
| `DEFAULT_SCHEME` | Forward scheme for new hosts (`http`) |
| `SSL_FORCED` | Force HTTPS on new hosts (`true`) |
| `HTTP2_SUPPORT` | Enable HTTP/2 (`true`) |
| `BLOCK_EXPLOITS` | Enable exploit blocking (`true`) |
| `ALLOW_WEBSOCKET` | Enable WebSocket upgrade (`true`) |
| `CERT_WARN_DAYS` | Days before expiry to warn (`30`) |
