# Pi-hole + Unbound

[Pi-hole](https://pi-hole.net/) provides network-wide ad blocking via DNS.
[Unbound](https://nlnetlabs.nl/projects/unbound/about/) is a recursive DNS
resolver that eliminates reliance on third-party upstream DNS providers.

Together, Pi-hole handles client queries and ad filtering, then delegates
non-cached lookups to Unbound which recursively resolves from the root
servers — maximising privacy.

## At a glance

| Property            | Value                                                    |
| ------------------- | -------------------------------------------------------- |
| Pi-hole image       | `pihole/pihole:2025.07.0` (pinned by digest)             |
| Unbound image       | `klutchell/unbound:1.23.0` (pinned by digest, multi-arch)|
| Host ports          | `53/tcp+udp` (DNS), `17418` (web admin)                  |
| Volumes             | `pihole-config`, `pihole-dnsmasq` (fresh, not migrated)  |
| Healthchecks        | `dig pi.hole` (pihole), `drill cloudflare.com` (unbound) |
| Hardened with       | `cap_drop: [ALL]` + selective `cap_add`, `no-new-privileges` |

## Architecture

```
Clients ──► :53 ──► Pi-hole (filtering + caching)
                        │
                        ▼
                    Unbound :5335 (recursive resolution from root servers)
                        │
                        ▼
                    Root / TLD / Authoritative servers
```

Pi-hole is configured via `FTLCONF_dns_upstreams: "unbound#5335"` to use
the Unbound container (resolved via Docker DNS on the shared network) as
its sole upstream. DNSSEC validation is enabled at both layers.

## First-time setup

1. `cp .env.example .env` and set `PIHOLE_PASSWORD`.
2. Start:
   ```sh
   scripts/homelab.sh start pihole-unbound
   ```
3. Point your router's DNS to the host's IP on port 53, or configure
   individual clients.
4. Visit `http://<host>:17418/admin` and log in.
5. Verify Unbound is working:
   ```sh
   docker exec pihole-unbound-unbound-1 drill @127.0.0.1 -p 5335 pi-hole.net
   ```

## Port 53 conflicts

On macOS, the built-in `mDNSResponder` binds port 53. You may need to
disable it or change its listening port. On Linux, `systemd-resolved`
typically binds `127.0.0.53:53` — disable with:
```sh
sudo systemctl disable --now systemd-resolved
```

## Unbound configuration

The file `config/unbound.conf` is bind-mounted read-only into the Unbound
container. It follows the Pi-hole documentation recommendations:
- Listens on port 5335
- DNSSEC validation enabled
- Hardened against cache poisoning (harden-glue, harden-dnssec-stripped)
- EDNS buffer size 1232 (DNS Flag Day 2020)
- Prefetching enabled
- Private address ranges declared

Edit `config/unbound.conf` to customise, then restart:
```sh
scripts/homelab.sh restart pihole-unbound
```

## Security notes

- Pi-hole needs `NET_RAW` for DHCP (even if not used, the init fails
  without it). If you're certain you won't use Pi-hole's DHCP, you can try
  removing it.
- Port 53 is exposed on all interfaces. Ensure your firewall only allows
  LAN access.
- The web admin (port 17418) should **never** be exposed to the internet.

## Updating

```sh
docker buildx imagetools inspect pihole/pihole:<new-tag>
docker buildx imagetools inspect klutchell/unbound:<new-tag>
# Update tags + digests in compose.yaml, then:
scripts/homelab.sh restart pihole-unbound
```
