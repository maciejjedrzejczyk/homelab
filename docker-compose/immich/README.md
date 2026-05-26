# Immich

[Immich](https://immich.app/) is a self-hosted photo and video management
solution with machine learning features (face recognition, object
detection, CLIP search).

## At a glance

| Property         | Value                                                      |
| ---------------- | ---------------------------------------------------------- |
| Server image     | `ghcr.io/immich-app/immich-server:v1.138.0` (digest-pinned) |
| ML image         | `ghcr.io/immich-app/immich-machine-learning:v1.138.0`       |
| Database         | `ghcr.io/immich-app/postgres:14-vectorchord0.4.3` (digest) |
| Cache            | `valkey/valkey:9` (digest-pinned)                           |
| Host port        | `17426` → container `2283`                                  |
| Media storage    | Bind-mount `UPLOAD_LOCATION`                                |
| DB storage       | Bind-mount `DB_DATA_LOCATION`                               |
| Model cache      | Named volume `immich-model-cache`                           |

## First-time setup

1. `cp .env.example .env`
2. Edit `.env`:
   - Set `UPLOAD_LOCATION` to the host directory for photo/video storage.
   - Set `DB_DATA_LOCATION` to a **local** (not network) path for Postgres.
   - Generate a strong `DB_PASSWORD`.
3. Start:
   ```sh
   scripts/homelab.sh start immich
   ```
4. Visit `http://<host>:17426` and create your admin account.

## Important notes

- **UPLOAD_LOCATION**: This is where all your photos live. Back it up
  independently (Time Machine, restic, etc.). It can be large.
- **DB_DATA_LOCATION**: Must be on a local disk (SSD preferred). Network
  shares cause database corruption.
- **Machine learning**: The ML container downloads models on first start
  (~1-2 GB). Subsequent starts are fast thanks to the model cache volume.
- **Memory**: The ML container can use significant RAM during indexing.
  The 4 GB limit is generous; reduce if your host is constrained.

## Updating

Immich should be updated as a whole (all images at once):

```sh
# Check latest release at https://github.com/immich-app/immich/releases
docker buildx imagetools inspect ghcr.io/immich-app/immich-server:<new-tag>
docker buildx imagetools inspect ghcr.io/immich-app/immich-machine-learning:<new-tag>
# Update both tags + digests in compose.yaml, then:
scripts/homelab.sh delete immich
scripts/homelab.sh start immich
```

Always check the [release notes](https://github.com/immich-app/immich/releases)
for breaking changes before upgrading.

## Security notes

- The server and ML containers are hardened with `no-new-privileges`.
- Postgres and Valkey have `cap_drop: [ALL]` with selective `cap_add`.
- Database credentials are in `.env` (git-ignored).
- The web UI has no built-in rate limiting — put it behind NPM with
  auth if exposing externally.
