# Roadmap

> Planned work, tech debt and wishlist for the homelab. Last updated 2026-09-25.
> Each task says **why** it matters and links to where the details live. Tick the box when done and move the line to [Done](#-done).

**Legend:** 🔴 in progress · 🟠 urgent (risk of losing data) · 🟡 soon · ⚪ someday · ✅ done

---

## 🔴 In progress

- [ ] **Optimize Debian VM memory usage.** Swap was 7.9/8 GB and the VM is stalling for CPU. Plan:
  1. Raise VM 100 from 12 GB to 16–20 GB RAM in Proxmox (if the host has room).
  2. Cap Immich: `immich_machine_learning` → `mem_limit: 1536m` + `MACHINE_LEARNING_WORKERS=1`; `immich_server` → `mem_limit: 3g`.
  3. Set the VM CPU type to `host`.
  4. The host only has **16 GB total** (Proxmox ~4 + VM 12), so the VM can't grow much. On the host, check ZFS's cache isn't competing: `grep -E '^(size|c_max) ' /proc/spl/kstat/zfs/arcstats` (cap it at ~1–2 GB if it's larger).
  5. Real long-term fix: a RAM upgrade to 32 GB. The GPU driver upgrade also helps a lot: it moves Ollama's 5 GB model from RAM into the GPU's 8 GB of VRAM.

  Diagnosis 2026-09-25: `immich_server` alone used 6.8 GB (3.9 RAM + 2.9 swap) while processing the first import (4,258 videos transcoded on CPU, face detection, OCR). Failing ML requests were being retried, adding more load. Tonight: let it run; lower Immich job concurrency to 1 and turn off OCR until the backlog clears.

  Adding *more swap* would only hide the problem; swap is what's making the VM crawl. → [services/README.md#memory-budget-12-gb-vm](../services/README.md#memory-budget-12-gb-vm)
- [ ] **Tune Immich background uploads/jobs.** Lower job concurrency in Admin → Jobs and run face detection / smart search overnight so they don't fight the game servers. → [services/immich.md](../services/immich.md#memory-and-cpu)

## 🟠 Short-term / immediate

Things that can lose data or are one-line fixes.

- [ ] **Vaultwarden: add the DNS record.** Cloudflare DNS → A record `vaultwarden` → the server's Tailscale IP, DNS only. The nginx site already exists (2026-09-25). → [services/management.md](../services/management.md#vaultwarden)
- [ ] **n8n: reconnect the Gmail credential** and publish the Google OAuth app to *In production* so the token stops expiring weekly. This is why the Discord notifications stopped. → [services/ai-tools.md](../services/ai-tools.md#n8n)

- [ ] **Fix the Terraria backup.** The cron still archives `/mnt/tank/terraria`, which has been gone since the move to `/srv/games` on 2026-09-24. `crontab -e` → change `-C /mnt/tank/terraria` to `-C /srv/games/terraria`. → [services/gaming.md](../services/gaming.md#backups)
- [ ] **Back up Immich (photos + database) off-site** with restic or Borg. Nightly `pg_dumpall` + the `library/` and `upload/` folders, first to `hddpool/backups`, then to an off-site repo (Backblaze B2, a friend's server…). → [services/immich.md](../services/immich.md#backup-not-set-up-yet)
- [ ] **Back up Supabase, Vaultwarden and n8n** in the same job (DB dump + folders). → [supabase.md](../services/supabase.md#backup-not-set-up-yet), [management.md](../services/management.md#vaultwarden), [ai-tools.md](../services/ai-tools.md#n8n)
- [ ] **Turn on the QEMU guest agent (both sides)** and **create a Proxmox backup job for VM 100** to `hddpool/backups` (nightly, snapshot mode, keep 7 daily / 4 weekly). → [runbooks/disaster-recovery.md §5](../runbooks/disaster-recovery.md#5-backup-validation-and-hardening-plan)
- [ ] **Lock the public game servers.** Minecraft whitelist on (`ENABLE_WHITELIST`, `ENFORCE_WHITELIST`, `WHITELIST=`); Terraria server password; in the Playit dashboard, confirm only 25565 and 7777 are tunnelled. → [services/gaming.md](../services/gaming.md#who-can-reach-it)
- [ ] **2FA on the Tailscale and Cloudflare logins**; review the 5 tailnet devices. These accounts control everything. → [networking-and-security.md §6](../architecture/networking-and-security.md#6-security-posture)
- [ ] **`chmod 600` every `.env`** under `~/docker` and `~/Mush` (they're world-readable now). Scope the Cloudflare API token to DNS-edit on one zone.
- [ ] **Delete Stirling-PDF heap dumps** (frees 7.6 GB) and set `JAVA_CUSTOM_OPTS=-Xms64m -Xmx512m -XX:-HeapDumpOnOutOfMemoryError`. → [services/ai-tools.md](../services/ai-tools.md#stirling-pdf-what-the-76-gb-really-is)
- [ ] **Remove the duplicate Playit agent:** `systemctl disable --now playit` (keep the container).

## 🟡 Mid-term infrastructure upgrades

- [ ] **Certificates: finish the automation.** Renewal already runs automatically, but there are two certbot installs (apt + snap) and nothing reloads nginx afterwards, so the container would keep serving an old certificate. Keep the snap, `apt purge certbot`, add a deploy hook `docker exec nginx-proxy nginx -s reload`. → [networking-and-security.md §2.1](../architecture/networking-and-security.md#21-private-https-via-nginx-proxy-tailnet-only-by-dns)
- [ ] **Local DNS with Pi-hole or AdGuard Home** (optional). Today the public DNS records point at the Tailscale IP, which works but shows your tailnet address to anyone who looks it up. A local DNS server (or Tailscale split DNS) could answer `*.example.com` privately instead.
- [ ] **Finish monitoring.** Prometheus + Grafana + Uptime-Kuma already run, but only VM-level metrics exist and there are no alerts. Add cAdvisor (per-container RAM/CPU) and alerts for swap > 80 %, disk > 85 %, unhealthy containers and backups older than 26 h. → [services/management.md](../services/management.md#monitoring-gaps)
- [ ] **Upgrade the NVIDIA driver to 550+** in the VM so Ollama (and Immich ML) use the GPU instead of CPU and RAM. → [services/ai-tools.md](../services/ai-tools.md#ollama-why-its-slow-right-now)
- [ ] **Docker log rotation** in `/etc/docker/daemon.json` (`max-size 10m`, `max-file 3`). → [services/README.md](../services/README.md#docker-engine-settings)
- [ ] **Patching:** install `unattended-upgrades` (40 updates pending), enable `cloudflared-update.timer`, and `docker compose pull` monthly, starting with the internet-facing ones (portfolio nginx, Minecraft, Playit).
- [ ] **Move backups and media onto the ZFS pools:** mount `hddpool/backups` and `hddpool/media` into the VM (NFS or a virtual disk). → [architecture/host-and-vm.md](../architecture/host-and-vm.md#recommended-storage-alignment)
- [ ] **LAN hardening (optional, if you ever share your network):** bind admin ports (Ollama 11434, Postgres 5432/6543, RCON 25575, dashboards) to `127.0.0.1` or the Tailscale IP, like VNC. Also: n8n back to `127.0.0.1:5678`, Homepage's Docker socket to `:ro`, Vaultwarden `SIGNUPS_ALLOWED=false`, SSH keys instead of the root password.
- [ ] **Start VNC at boot:** turn `vnc-tailscale.sh` (and Xvfb) into systemd services.

## ⚪ Backlog / wishlist

- [ ] **Expand ZFS storage** with more drives (plan the vdev layout first: `zpool status`).
- [ ] **SSO / OIDC for self-hosted apps** (Authentik, Authelia or Pocket ID) so Immich, Grafana, n8n etc. share one login.
- [ ] Move the Immich library to `fastpool/photos`, and app state to `fastpool/appdata`.
- [ ] Containerise the Chrome/Playwright desktop (1.5 GiB cap, `shm_size: 1gb`).
- [ ] Containerized headless game host (Steam / Wolf). *(phase 3.1)*
- [ ] Moonlight streaming to the Retroid Pocket Flip 2. *(phase 3.3)*
- [ ] Web terminals (ttyd sidecars) and embedded game terminals. *(phases 3.4, 5.3)*
- [ ] Heavy local AI workstation (RX 9070 XT). *(phase 4.1)*
- [ ] Wake-on-LAN remote desktop power management. *(phase 4.2)*
- [ ] Custom React dashboard with live service integration (Mush + Supabase). *(phases 5.1–5.2)*

## ✅ Done

- ✅ VNC / noVNC restricted to Tailscale only (2026-09-25).
- ✅ Audit script + docs workflow (`scripts/audit-homelab.sh`, 2026-09-25).
- ✅ Only the portfolio (via Cloudflare Tunnel) and the game ports are public; the app sites are tailnet-only (verified 2026-09-25).
- ✅ Root disk grown 102 → 502 GB, plus a 1.5 TB data disk (was 88 % full).
- ✅ `pdf.example.com` has HTTPS.
- ✅ Immich deployed.
- ✅ Automatic certificate renewal (certbot timers). *Reload hook still missing; see mid-term.*
- ✅ Monitoring stack running (Prometheus, Grafana, Uptime-Kuma). *Alerts still missing; see mid-term.*
- ✅ Stirling-PDF, Gluetun VPN kill switch, Minecraft (tuned Paper) and Terraria servers, Playit tunnels.

---

## Original phase blueprint (status as of 2026-09-25)

| Phase | Item | Status | Notes |
|---|---|---|---|
| 1.1 | Stirling-PDF | ✅ | Running, HTTPS. JVM tuning still pending |
| 1.2 | Remote development (VS Code SSH) | ✅ | Root + password login still allowed |
| 2.1 | Security & torrents (Gluetun) | ✅ | |
| 2.2 | Media & backup (Jellyfin / Immich) | 🟠 | Both deployed; **no backups**; media library empty |
| 2.3 | Terraria server | ✅ / 🟠 | Running; backup broken |
| 2.4 | Minecraft server (Paper) | ✅ | |
| 2.5 | External gaming connectivity | ✅ | Duplicate Playit agent; no whitelist/password |
| 2.6 | System monitoring | 🟡 | Running; no container metrics or alerts |
| 3.1 | Headless game host (Steam/Wolf) | ⚪ | |
| 3.2 | VRAM balancing (Ollama) | 🟡 | Not effective: driver 535 → CPU only |
| 3.3 | Moonlight streaming | ⚪ | |
| 3.4 | Web terminals (ttyd) | ⚪ | |
| 3.5 | RAM caps & Ollama isolation | 🔴 | Ollama and Immich uncapped; swap full |
| 4.1 | AI workstation (RX 9070 XT) | ⚪ | |
| 4.2 | Wake-on-LAN | ⚪ | |
| 5.1 | Custom React dashboard | ⚪ | Mush front-end exists |
| 5.2 | Live service integration | ⚪ | Supabase backend exists |
| 5.3 | Embedded game terminals | ⚪ | |

## Tech debt: design vs. reality (drift register)

Things that were planned one way and are actually another. Re-check with the audit script.

| Item | Design | 2026-09-16 | 2026-09-25 | Action |
|---|---|---|---|---|
| Stirling-PDF memory | 512 MiB, `-Xmx256m` | 1 GiB, defaults, stopped | 1 GiB, defaults, running; 33 heap dumps show repeated OOMs | Short-term |
| Ollama limits | RAM/VRAM caps | no cap, CPU | unchanged | Mid-term (driver) |
| Chrome desktop | container, 1.5 GiB | native, VNC open | native, VNC tailnet-only | Backlog |
| Media library | `hddpool/media` | empty dir on root disk | empty dir on data disk | Mid-term |
| Backups | `hddpool/backups` + PBS | same disk as data | inside the VM; no VM backup | Short-term |
| Terraria backup | nightly | working | broken since 2026-09-24 | Short-term |
| Playit | one agent | two | two | Short-term |
| qBittorrent config | `/docker/media/config/qbittorrent` | under `/home/<user>` | unchanged | Backlog |
| n8n binding | loopback | `127.0.0.1` | `0.0.0.0` | Mid-term (LAN hardening) |
| Reverse proxy | host nginx | host nginx | `nginx-proxy` container | ✅ docs updated |
| Public ingress | — | assumed port-forward | tunnel (portfolio) + Playit only | ✅ verified |
| Photos | Immich on `fastpool/photos` | absent | on `/mnt/tank`, no backup | Short-term + backlog |
| Root disk | — | 102 GB, 88 % | 502 GB, 15 % | ✅ |
| Log rotation | bounded | none | none | Mid-term |
| Monitoring | full | 1 scrape job | unchanged | Mid-term |
| Guest RAM | 12 GB | swap 5.7 GiB | swap 7.9 GiB (full) | In progress |
| Guest agent | on | inactive | off in Proxmox *and* guest | Short-term |
