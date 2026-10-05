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

## Memory budget (11 GB VM)

On 2026-09-25 the VM ran out of memory (7.9 of 8 GB swap). Immich is now capped and Ollama's model moved to the GPU. On 2026-09-27 the VM went from 12 to 11 GB so the host keeps enough RAM during the nightly backup (with the GPU passed through, the host can't reclaim any of the VM's RAM). On 2026-09-27/28: 1.6–3.6 GB available, 4–5 GB of cold pages in swap, no active swapping, no OOM kills.

**Why 11 GB is the right size for now:** more would starve the host during backups (the 12 GB setup froze the VM on 2026-09-27); less would leave no room for Immich imports (+2 GB) and indexing (+1 GB) on top of the normal load. Worry only if `vmstat 1` shows non-zero `si`/`so` for minutes, or `/proc/pressure/memory` stays above a few percent.

| Consumer | Limit | Uses (2026-09-27/28) | Page |
|---|---|---|---|
| immich_server | 4 GiB | ~0.6 GiB idle, 2+ GiB while importing | [immich](immich.md) |
| immich_machine_learning | 2 GiB | ~50 MiB idle, ~1 GiB (+200 % CPU) while indexing | [immich](immich.md) |
| minecraft | 5 GiB | ~1.1 GiB | [gaming](gaming.md) |
| supabase (11 containers) | none | ~0.9 GiB total | [supabase](supabase.md) |
| stirling-pdf | 1 GiB | ~490 MiB | [ai-tools](ai-tools.md) |
| terraria | 2 GiB | ~0.4–1 GiB | [gaming](gaming.md) |
| n8n | 1 GiB | ~290 MiB | [ai-tools](ai-tools.md) |
| ollama | 3 GiB (since 2026-10-03) | ~1 GiB RAM (`llama-server`) with the model loaded, plus a prompt cache now capped at 1 GiB (it was allowed 8 GiB and reached 5.5 GiB). The model itself (5.4 GB) is in GPU memory | [ai-tools](ai-tools.md#why-ollama-used-system-ram-although-the-model-is-on-the-gpu-fixed-2026-10-03) |
| everything else in Docker | mostly none | ~1.2 GiB | — |
| host programs (Chrome/Xvfb, Claude tooling, dockerd, tailscaled) | none (`tailscaled` and `sshd` have reserved memory, see below) | ~1.5–2.5 GiB normally. On 2026-10-03: 27 leftover Playwright Chrome processes (~2 GiB) and 3 forgotten Claude sessions | [host-and-vm](../architecture/host-and-vm.md#host-native-programs) |

The caps (Minecraft 5 G, Immich 4 G + 2 G, Terraria 2 G, Ollama 3 G, n8n 1 G, Stirling 1 G, mc-backup 512 M) add up to 18.5 GiB, more than the VM has. That works only because they rarely peak together. Cheapest way to get headroom: lower Minecraft's cap to ~3 GiB. The host has only 16 GB, so the real long-term fix is a RAM upgrade ([roadmap](../roadmap/ROADMAP.md)).

### 2026-10-03: the VM ran out of memory

**What you saw:** Tailscale went offline around 19:30 and the VM couldn't be reached, not even through the Proxmox console. A shutdown from Proxmox at 22:50 brought it back.

**What happened (from the logs of that boot):**

1. Around 19:30, RAM **and** all 8 GB of swap were full. The biggest users were Ollama's `llama-server` (~5.5 GB, its prompt cache, see [ai-tools](ai-tools.md#why-ollama-used-system-ram-although-the-model-is-on-the-gpu-fixed-2026-10-03)), 27 leftover Chrome processes from Playwright (~2 GB) and 3 old Claude sessions. At 19:38 the kernel killed a Chrome process.
2. `tailscaled` didn't crash on its own. With no memory left, DNS lookups timed out and its internal watchdog stopped it (`panic: ipnlocal: watchdog timeout`, 20:29).
3. The Tailscale watchdog script restarted `tailscaled` every 5 minutes (46 starts/stops between 20:30 and 22:46). Each restart timed out, because the problem was memory, not Tailscale.
4. The Proxmox console login hung for the same reason.
5. Claude Code's automatic update (2.1.288 → 2.1.289, npm) ran at 20:17 and failed, which is why it had to be reinstalled. The current install is in `/usr/lib/node_modules/@anthropic-ai/claude-code`; `~/.claude` (settings, memory) survived.

**What changed afterwards:**

- Ollama's prompt cache capped at 1 GiB and the container at 3 GiB ([ai-tools](ai-tools.md#why-ollama-used-system-ram-although-the-model-is-on-the-gpu-fixed-2026-10-03)).
- `tailscaled` and `sshd` have **reserved memory** and are protected from the OOM killer, so remote access survives memory pressure for longer ([networking](../architecture/networking-and-security.md#23-tailscale-mesh)).
- The watchdog no longer restarts Tailscale when the real problem is memory ([networking](../architecture/networking-and-security.md#23-tailscale-mesh)).
- Decided **not** to install `earlyoom`: it would kill the biggest process (possibly Minecraft or something else important) without asking. The caps above are the safer fix.

**If it happens again:** `tail /var/log/tailscale-watchdog.log` now records free RAM and swap at each failure. `journalctl -b -1 -k | grep -i "killed process"` shows what the kernel killed in the previous boot.

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

- `/etc/docker/daemon.json` registers the `nvidia` runtime and, since 2026-10-04, rotates logs: `json-file` with `max-size 10m`, `max-file 3` (backup: `daemon.json.bak-20261004`). Docker reads the file only when it starts, and the setting applies only to containers created after that. Docker was restarted by the 2026-10-04 update, so the daemon uses it now, and each container gets it the next time it's recreated (`docker compose up -d` after a change or `pull`). The largest container log was 118 MB when this was set.
- NVIDIA container toolkit 1.20.1, driver 615. Containers get the GPU through the toolkit. If it's missing, GPU containers fail to start with `could not select device driver "nvidia"` ([ai-tools](ai-tools.md#ollama-on-the-gpu)).
- 38 images (38.1 GB, nothing to prune). Named volumes use 1.05 GB.
- Only Supabase and Immich pin image versions; everything else uses `:latest`, so updates happen whenever you `docker compose pull`.

## Leftovers on disk (safe to delete after a look)

`/docker/appdata/caddy` (from the retired Caddy proxy), empty `/docker/appdata/{grafana,mush}`, stray `~/docker/appdata/{n8n,ollama}` (36 KB, not mounted by anything), `~/docker/management/prometheus/prometheus.yml` (unused duplicate).
