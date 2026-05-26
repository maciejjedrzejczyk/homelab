# iCloudPD

[iCloudPD](https://github.com/icloud-photos-downloader/icloud_photos_downloader)
downloads photos and videos from iCloud to a local directory.

## At a glance

| Property            | Value                                                    |
| ------------------- | -------------------------------------------------------- |
| Image               | `icloudpd/icloudpd:1.32.2` (pinned by digest)           |
| Host port           | None (no web UI)                                         |
| Data                | Bind-mount `ICLOUDPD_DOWNLOAD_PATH`, cookies in volume   |
| Hardened with       | `cap_drop: [ALL]`, `no-new-privileges`, `init: true`     |

## First-time setup

1. Generate an **app-specific password** at https://appleid.apple.com/account/manage
2. `cp .env.example .env` and fill in your credentials + download path.
3. Start:
   ```sh
   scripts/homelab.sh start icloudpd
   ```
4. On first run, iCloudPD will prompt for 2FA. Check logs:
   ```sh
   scripts/homelab.sh logs icloudpd
   ```
   Enter the code via `docker exec`:
   ```sh
   docker exec -it <container> icloudpd --username <email> --cookie-directory /cookies --auth-only
   ```
   Once authenticated, the cookie is stored in the volume and reused.

## Security notes

- Credentials are in `.env` (git-ignored), **not** on the `command:` line
  where they'd be visible via `docker inspect`.
- The app-specific password has limited scope — it cannot change your Apple
  ID settings. Rotate it periodically.
- Downloaded photos land on a bind-mounted host path. Back that up
  separately (Time Machine, restic, etc.).

## Updating

```sh
docker buildx imagetools inspect icloudpd/icloudpd:<new-tag>
# Update tag + digest in compose.yaml, then:
scripts/homelab.sh restart icloudpd
```
