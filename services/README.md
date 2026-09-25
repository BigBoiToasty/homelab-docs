# Services

> Everything that runs in Docker on VM 100, grouped by Compose project. Last verified 2026-09-25: **40 containers, 9 projects**, Docker Engine 29.6.2, Compose 5.3.1.
> Each project has its own page. This page is the overview: what exists, who can reach it, how memory is shared, and where data lives.

## At a glance

| Page | Compose project (folder) | What it's for | Reachable from | Backed up? |
|---|---|---|---|---|
| [immich.md](immich.md) | `immich` (`~/docker/immich`) | Photo library | tailnet (`immich.example.com`), LAN | ❌ **no** (23 GB + DB) |
| [supabase.md](supabase.md) | `supabase` (`~/docker/supabase-service`) | Database/auth backend for Mush | tailnet (`supabase.example.com`), LAN | ❌ no |
| [ai-tools.md](ai-tools.md) | `ai-tools` (`~/docker/ai-tools`) | n8n automations, Ollama LLM, Stirling-PDF | tailnet (`n8n.`, `pdf.example.com`), LAN | ❌ no (n8n matters) |
| [management.md](management.md) | `management` (`~/docker/management`) | Vaultwarden, dashboards, monitoring | LAN + tailnet by port | ❌ no (Vaultwarden matters) |
| [gaming.md](gaming.md) | `gaming` (`~/docker/gaming`) | Minecraft, Terraria, Playit | **internet** (games via Playit), LAN, tailnet | ✅ Minecraft · ⚠️ Terraria broken |
| [media.md](media.md) | `media` (`~/docker/media`) | Jellyfin, *arr apps, VPN'd torrents, books | LAN + tailnet by port | not needed yet (empty library) |
| [web-apps.md](web-apps.md) | `mush` (`~/Mush`), `portfolio` (`~/docker/portfolio`) | Mush front-end, portfolio site | portfolio: **internet** (tunnel); Mush: tailnet | source code only |
| [../architecture/networking-and-security.md](../architecture/networking-and-security.md#21-private-https-via-nginx-proxy-tailnet-only-by-dns) | `reverse-proxy` (`~/docker/reverse-proxy`) | nginx in front of the tailnet sites | — | config is tiny; include in config backup |

"Reachable from" in plain terms:
- **internet**: anyone in the world.
- **tailnet**: your devices with Tailscale on; the `*.example.com` names point at the server's Tailscale IP.
- **LAN**: devices on your home network, using the server's IP and port.

## Memory budget (12 GB VM)

The VM is out of memory: 7.9 of 8 GB swap was in use on 2026-09-25. This is where it goes.

| Consumer | Limit | Uses (2026-09-25) | Page |
|---|---|---|---|
| immich_server | **none** | 2.0–2.4 GiB | [immich](immich.md) |
| immich_machine_learning | **none** | ~1 GiB (+200 % CPU while indexing) | [immich](immich.md) |
| minecraft | 5 GiB | ~920 MiB idle | [gaming](gaming.md) |
| supabase (11 containers) | none | ~0.9 GiB total | [supabase](supabase.md) |
| stirling-pdf | 1 GiB | ~370 MiB | [ai-tools](ai-tools.md) |
| n8n | 1 GiB | ~240 MiB | [ai-tools](ai-tools.md) |
| ollama | **none** | ~20 MiB idle, **~5–6 GiB per request** on CPU | [ai-tools](ai-tools.md) |
| everything else in Docker | mostly none | ~1.2 GiB | — |
| host programs (Chrome/Xvfb, Claude tooling, dockerd, tailscaled) | none | ~1.5–2 GiB | [host-and-vm](../architecture/host-and-vm.md#host-native-programs) |

The caps that do exist (Minecraft 5 G, Terraria 2 G, n8n 1 G, Stirling 1 G, mc-backup 512 M) already add up to 9.5 GiB, and Immich came on top of that. The fix is two-sided: give the VM more RAM (16–20 GB) **and** cap Immich. Both are in the [roadmap](../roadmap/ROADMAP.md).

## Where data lives

The VM has two disks ([details](../architecture/host-and-vm.md#disks-and-storage)). **Bold** = irreplaceable, with no backup yet.

| Data | Path | Disk |
|---|---|---|
| **Immich photos** | `/mnt/tank/immich` | data disk (`sdb`, 1.5 TB) |
| **Immich database** | `~/docker/immich/postgres` | boot disk (`sda`) |
| **Supabase database + files** | `~/docker/supabase-service/volumes/{db/data,storage}` | boot disk |
| **Vaultwarden vault** | `/docker/media/config/vaultwarden` | boot disk |
| **n8n workflows + key** | `/docker/appdata/n8n` | boot disk |
| Game worlds | `/srv/games/{minecraft,terraria}` | boot disk |
| Game backups | `/mnt/tank/backups/{minecraft,terraria}` | data disk |
| Media app configs | `/docker/media/config/*` | boot disk |
| Media library (empty) | `/mnt/tank/media` | data disk |
| Stirling settings + 7.6 GB of heap dumps | `/mnt/tank/stirling-pdf/extraConfigs` | data disk |
| Ollama models (re-downloadable) | `/docker/appdata/ollama` | boot disk |
| Named volumes (Grafana, Prometheus, Immich ML cache, Supabase config, Deno cache) | `/var/lib/docker/volumes` | boot disk |
| Docker socket | `/var/run/docker.sock` | mounted by dozzle (ro) and homepage (**rw**) |

To regenerate this table from the live system: the audit script's "Where container data lives" section ([scripts/](../scripts/README.md)).

## Docker engine settings

- `/etc/docker/daemon.json` only registers the `nvidia` runtime. **Logs are not rotated**: every container logs with `max-size: none`. Add `"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}`, then recreate the containers.
- NVIDIA container toolkit 1.20.0, driver 535 (too old for Ollama; fine for Jellyfin).
- 38 images (38.1 GB, nothing to prune). Named volumes use 1.05 GB.
- Only Supabase and Immich pin image versions; everything else uses `:latest`, so updates happen whenever you `docker compose pull`.

## Leftovers on disk (safe to delete after a look)

`/docker/appdata/caddy` (from the retired Caddy proxy), empty `/docker/appdata/{grafana,mush}`, stray `~/docker/appdata/{n8n,ollama}` (36 KB, not mounted by anything), `~/docker/management/prometheus/prometheus.yml` (unused duplicate).
