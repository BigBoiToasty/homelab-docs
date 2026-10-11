# Services

> Everything that runs in Docker on VM 100, grouped by Compose project. Last verified 2026-09-26: **40 containers, 9 projects**, Docker Engine 29.6.2, Compose 5.3.1.
> Each project has its own page. This page is the overview: what exists, who can reach it, how memory is shared, and where data lives.

## At a glance

| Page | Compose project (folder) | What it's for | Reachable from | Backed up? |
|---|---|---|---|---|
| [immich.md](immich.md) | `immich` (`~/docker/immich`) | Photo library | tailnet (`immich.example.com`), LAN | ❌ **no** (47 GB + DB) |
| [supabase.md](supabase.md) | `supabase` (`~/docker/supabase-service`) | Database/auth backend for Mush | tailnet (`supabase.example.com`), LAN | ❌ no |
| [ai-tools.md](ai-tools.md) | `ai-tools` (`~/docker/ai-tools`) | n8n automations, Ollama LLM, Stirling-PDF | tailnet (`n8n.`, `pdf.example.com`), LAN | ❌ no (n8n matters) |
| [management.md](management.md) | `management` (`~/docker/management`) | Vaultwarden, dashboards, monitoring | LAN + tailnet by port | ❌ no (Vaultwarden matters) |
| [gaming.md](gaming.md) | `gaming` (`~/docker/gaming`) | Minecraft, Terraria, Playit | **internet** (games via Playit), LAN, tailnet | ✅ Minecraft, Terraria (inside the VM only; verified 2026-09-26) |
| [media.md](media.md) | `media` (`~/docker/media`) | Jellyfin, *arr apps, VPN'd torrents, books | LAN + tailnet by port | not needed yet (empty library) |
| [web-apps.md](web-apps.md) | `mush` (`~/Mush`), `portfolio` (`~/docker/portfolio`) | Mush front-end, portfolio site | portfolio: **internet** (tunnel); Mush: tailnet | source code only |
| [../architecture/networking-and-security.md](../architecture/networking-and-security.md#21-private-https-via-nginx-proxy-tailnet-only-by-dns) | `reverse-proxy` (`~/docker/reverse-proxy`) | nginx in front of the tailnet sites | — | config is tiny; include in config backup |

"Reachable from" in plain terms:
- **internet**: anyone in the world.
- **tailnet**: your devices with Tailscale on; the `*.example.com` names point at the server's Tailscale IP.
- **LAN**: devices on your home network, using the server's IP and port.

## Memory budget (22 GB VM)

The VM has 22 GB since 2026-10-11 (was 11; host RAM upgraded to 32 GB). With the GPU passed through, all of it is locked on the host, so the host keeps the other ~10 GB for itself and the nightly backup. Just after boot on 2026-10-11: ~10 GiB used, ~11 GiB available, swap empty.

**How the RAM is shared:** no fixed split. Linux uses whatever is free as file cache and gives it back on demand, so most containers have no limit. The caps below are guard rails on the few apps that have run away before (or could), not reservations: they don't hold memory back from anyone else. Keep them, because nothing kills processes automatically on this VM. Keep ~8 GB free in normal use as headroom for game streaming and the job agent's Chrome. Worry only if `vmstat 1` shows non-zero `si`/`so` for minutes, or `/proc/pressure/memory` stays above a few percent.

| Consumer | Limit | Uses (2026-09-27/28) | Page |
|---|---|---|---|
| immich_server | 4 GiB | ~0.6 GiB idle, 2+ GiB while importing | [immich](immich.md) |
| immich_machine_learning | 2 GiB | ~50 MiB idle, ~1 GiB (+200 % CPU) while indexing | [immich](immich.md) |
| minecraft | 5 GiB | ~1.1 GiB | [gaming](gaming.md) |
| supabase (11 containers) | none | ~0.9 GiB total | [supabase](supabase.md) |
| stirling-pdf | 1 GiB | ~490 MiB | [ai-tools](ai-tools.md) |
| terraria | 2 GiB | ~0.4–1 GiB | [gaming](gaming.md) |
| n8n | 1 GiB | ~290 MiB | [ai-tools](ai-tools.md) |
| ollama | 3 GiB | ~1 GiB RAM (prompt cache capped at 1 GiB); the model itself is in GPU memory | [ai-tools](ai-tools.md#ollama-prompt-cache) |
| everything else in Docker | mostly none | ~1.2 GiB | — |
| host programs (Chrome/Xvfb, Claude tooling, dockerd, tailscaled) | none (`tailscaled` and `sshd` have reserved memory, see below) | ~1.5–2.5 GiB normally. On 2026-10-03: 27 leftover Playwright Chrome processes (~2 GiB) and 3 forgotten Claude sessions | [host-and-vm](../architecture/host-and-vm.md#host-native-programs) |

The caps (Minecraft 5 G, Immich 4 G + 2 G, Terraria 2 G, Ollama 3 G, n8n 1 G, Stirling 1 G, mc-backup 512 M) add up to 18.5 GiB, which now fits inside the VM even if everything peaks at once.

Past memory problems (2026-09-25, 2026-10-03) and their fixes: [incident log](../runbooks/incident-log.md).

## Where data lives

The VM has two disks ([details](../architecture/host-and-vm.md#disks-and-storage)). **Bold** = irreplaceable. Everything on the boot disk is in the nightly VM backup, and the bold databases are also dumped nightly ([app dumps](../runbooks/maintenance.md#nightly-app-database-dumps)). The Immich photos still have no second copy.

| Data | Path | Disk |
|---|---|---|
| **Immich photos** | `/mnt/tank/immich` | data disk (`sdb`, 1.5 TB) |
| **Immich database** | `~/docker/immich/postgres` | boot disk (`sda`) |
| **Supabase database + files** | `~/docker/supabase-service/volumes/{db/data,storage}` | boot disk |
| **Vaultwarden vault** | `/docker/media/config/vaultwarden` | boot disk |
| **n8n workflows + key** | `/docker/appdata/n8n` | boot disk |
| Game worlds | `/srv/games/minecraft/data/world`, `/srv/games/terraria/Worlds` | boot disk |
| Game backups | `/mnt/tank/backups/{minecraft,terraria}` | data disk |
| Media app configs | `/docker/media/config/*` | boot disk |
| Media library (empty) | `/mnt/tank/media` | data disk |
| Stirling settings (< 1 MB) | `/mnt/tank/stirling-pdf/extraConfigs` | data disk |
| Ollama models (re-downloadable) | `/docker/appdata/ollama` | boot disk |
| Named volumes (Grafana, Prometheus, Immich ML cache, Supabase config, Deno cache) | `/var/lib/docker/volumes` | boot disk |
| Docker socket | `/var/run/docker.sock` | mounted by dozzle (ro) and homepage (**rw**) |

To regenerate this table from the live system: the audit script's "Where container data lives" section ([scripts/](../scripts/README.md)).

## Docker engine settings

- `/etc/docker/daemon.json` registers the `nvidia` runtime and rotates container logs (`max-size 10m`, `max-file 3`). Containers pick up the log setting when they're recreated.
- NVIDIA container toolkit 1.20.1, driver 615. Containers get the GPU through the toolkit. If it's missing, GPU containers fail to start with `could not select device driver "nvidia"` ([ai-tools](ai-tools.md#ollama-on-the-gpu)).
- 38 images (38.1 GB, nothing to prune). Named volumes use 1.05 GB.
- Only Supabase and Immich pin image versions; everything else uses `:latest`, so updates happen whenever you `docker compose pull`.

## Leftovers on disk (safe to delete after a look)

`/docker/appdata/caddy` (from the retired Caddy proxy), empty `/docker/appdata/{grafana,mush}`, stray `~/docker/appdata/{n8n,ollama}` (36 KB, not mounted by anything), `~/docker/management/prometheus/prometheus.yml` (unused duplicate).
