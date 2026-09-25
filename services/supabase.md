# Supabase (`supabase`): backend platform

> Compose project `~/docker/supabase-service` (the official self-host repo) · network `supabase_default` · last verified 2026-09-25.
> **In one line:** a self-hosted Firebase alternative (Postgres database, auth, REST API, storage, realtime) used as the backend for the Mush app. The database has **no backup**.

## Containers

| Container | Image | Ports | Data lives in |
|---|---|---|---|
| supabase-db | `supabase/postgres:17.6.1.136` | internal 5432 | `volumes/db/data` (**the database**), init SQL files, volume `supabase_db-config` |
| supabase-pooler | `supabase/supavisor:2.9.5` | **5432, 6543 on all interfaces** | `volumes/pooler/pooler.exs` |
| supabase-kong | `kong/kong:3.9.1` | 8000, 8443 | `volumes/api/kong.yml` (API gateway) |
| supabase-auth | `supabase/gotrue:v2.189.0` | internal | — |
| supabase-rest | `postgrest/postgrest:v14.12` | internal 3000 | — |
| realtime-dev.supabase-realtime | `supabase/realtime:v2.102.3` | internal | — |
| supabase-storage | `supabase/storage-api:v1.60.4` | internal 5000 | `volumes/storage` (uploaded files) |
| supabase-imgproxy | `darthsim/imgproxy:v3.30.1` | internal 8080 | `volumes/storage` (shared) |
| supabase-meta | `supabase/postgres-meta:v0.96.6` | internal 8080 | — |
| supabase-edge-functions | `supabase/edge-runtime:v1.74.0` | internal | `volumes/functions`, volume `supabase_deno-cache` |
| supabase-studio | `supabase/studio:latest` | `127.0.0.1:3002` only | `volumes/functions` (ro), `volumes/snippets` |

All paths are relative to `~/docker/supabase-service/` (68 MB, on the boot disk). Versions are pinned (good for repeatable rebuilds). No memory limits are set; the whole stack uses ~0.9 GiB.

## Who can reach it

| Part | Reachable from |
|---|---|
| API (Kong) at `https://supabase.example.com` | Tailnet (DNS points at the Tailscale IP). Returns 401 without an API key, as expected |
| Kong direct on 8000/8443, Postgres pooler on 5432/6543 | LAN + tailnet |
| Studio (admin UI) | Only from the server itself (`127.0.0.1:3002`). Use an SSH tunnel: `ssh -L 3002:127.0.0.1:3002 root@<server>` |

## Secrets

`~/docker/supabase-service/.env` holds ~20 secret values (JWT secret, anon/service keys, Postgres password, dashboard password). It is mode `644` (readable by every user on the server); `chmod 600` it. The restored database only works with the **same** `.env`, so escrow it with the backups.

## Backup (not set up yet)

```bash
docker exec supabase-db pg_dumpall -U postgres | gzip > /mnt/backups/supabase/supabase-$(date +%F).sql.gz
tar czf /mnt/backups/supabase/storage-$(date +%F).tgz -C ~/docker/supabase-service/volumes storage
```

Database rows reference files in `volumes/storage`, so back up both together. Restore steps and gotchas (JWT/role mismatches): [runbooks/disaster-recovery.md §3](../runbooks/disaster-recovery.md#3-per-service-data-recovery).
