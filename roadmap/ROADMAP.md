# Roadmap

> Planned work, tech debt and wishlist for the homelab. Last updated 2026-10-04.
> Each task says **why** it matters and links to where the details live. Tick the box when done and move the line to [Done](#-done).

**Legend:** 🔴 in progress · 🟠 urgent (risk of losing data) · 🟡 soon · ⚪ someday · ✅ done

---

## 🔴 In progress

- [ ] **Finish the VM 100 backup setup.** The first manual backup worked on 2026-09-27 ([details](../architecture/host-and-vm.md#vm-100-backup-working-since-2026-09-27)). Left to do (on the Proxmox host):
  1. The nightly 05:00 job exists (seen under Datacenter → Backup, 2026-09-28). Check that its first scheduled run finished with `OK` (`ls -lh /hddpool/backups/dump/`, newest `.log` ends with "Finished Backup of VM 100").
  2. Once, do a real test restore (see [disaster-recovery §5.3](../runbooks/disaster-recovery.md#53-validation-procedures-run-quarterly-record-results)). `zstd -t` only proves the file decompresses, not that the VM boots from it. It needs VM 100 stopped, because the host can't run two VMs this size.
- [ ] **Back up the data disk's irreplaceable files (Immich photos first).** The VM backup skips the 1.5 TB `/mnt/tank` disk. Backing it up to hddpool wouldn't help anyway, since it already lives there. The photos need a copy on fastpool or off-site (see the Immich task below).
- [ ] **Keep an eye on VM memory.** The VM runs on 11 GB since 2026-09-27; 12 GB left the host too little RAM during backups. On 2026-10-03 it ran out of RAM and swap anyway, mainly because of Ollama's prompt cache; that is now capped ([incident](../services/README.md#2026-10-03-the-vm-ran-out-of-memory)). Check `free -h` over the next week: swap should stay well below 8 GB.
- [ ] **Close old Claude sessions and leftover Chrome.** On 2026-10-03, 3 forgotten Claude sessions and 27 Playwright Chrome processes held ~2.7 GB. `ps -eo pid,etime,rss,comm --sort=-rss | head -20` shows them. The host only has 16 GB, so the VM can't grow. Real fix: a RAM upgrade to 32 GB. Don't add more swap: it only hides the problem. → [services/README.md#memory-budget-11-gb-vm](../services/README.md#memory-budget-11-gb-vm)
- [ ] **Tune Immich background uploads/jobs.** Lower job concurrency in Admin → Jobs and run face detection / smart search overnight so they don't fight the game servers. → [services/immich.md](../services/immich.md#memory-and-cpu)

## 🟠 Short-term / immediate

Things that can lose data or are one-line fixes.

- [ ] **Media apps: decide whether to restore their pre-Sep-8 settings** from `/root/docker/media/config`. They were reset by the same path change as Vaultwarden. → [services/media.md](../services/media.md#settings-probably-lost-on-2026-09-08)
- [ ] **n8n: publish the Google OAuth app** to *In production* if the Gmail credential breaks again after a week (it was reconnected 2026-09-26). → [services/ai-tools.md](../services/ai-tools.md#n8n)

- [ ] **Copy the Immich photos (48 GB) to the SSD pool.** They exist only on hddpool. You: Proxmox → VM 100 → Hardware → Add → Hard Disk on **fastpool**, ~150 GB, **Backup unchecked** (so the nightly VM backup doesn't grow by 48 GB). Then Claude formats/mounts it and adds a nightly `rsync`. → [services/immich.md](../services/immich.md#backup-half-done)
- [ ] **Off-site copy** of the photos and `/root/backups/app-dumps` (Backblaze B2 ≈ $0.30/month for 48 GB with restic, or the Windows desktop over Tailscale). Protects against fire/theft/surge, which take out both pools.
- [ ] **Lock the public game servers.** Minecraft whitelist on (`ENABLE_WHITELIST`, `ENFORCE_WHITELIST`, `WHITELIST=`); Terraria server password; in the Playit dashboard, confirm only 25565 and 7777 are tunnelled. → [services/gaming.md](../services/gaming.md#who-can-reach-it)
- [ ] **2FA on the Tailscale and Cloudflare logins**; review the 5 tailnet devices. These accounts control everything. → [networking-and-security.md §6](../architecture/networking-and-security.md#6-security-posture)
- [ ] **`chmod 600` every `.env`** under `~/docker` and `~/Mush` (they're world-readable now). Scope the Cloudflare API token to DNS-edit on one zone.
- [ ] **Delete Stirling-PDF heap dumps** (frees 7.6 GB) and set `JAVA_CUSTOM_OPTS=-Xms64m -Xmx512m -XX:-HeapDumpOnOutOfMemoryError`. → [services/ai-tools.md](../services/ai-tools.md#stirling-pdf-what-the-76-gb-really-is)
- [ ] **Remove the duplicate Playit agent:** `systemctl disable --now playit` (keep the container).

## 🟡 Mid-term infrastructure upgrades

- [ ] **Certificates: finish the automation.** Renewal already runs automatically, but there are two certbot installs (apt + snap) and nothing reloads nginx afterwards, so the container would keep serving an old certificate. Keep the snap, `apt purge certbot`, add a deploy hook `docker exec nginx-proxy nginx -s reload`. → [networking-and-security.md §2.1](../architecture/networking-and-security.md#21-private-https-via-nginx-proxy-tailnet-only-by-dns)
- [ ] **Local DNS with Pi-hole or AdGuard Home** (optional). Today the public DNS records point at the Tailscale IP, which works but shows your tailnet address to anyone who looks it up. A local DNS server (or Tailscale split DNS) could answer `*.example.com` privately instead.
- [ ] **Finish monitoring.** Prometheus + Grafana + Uptime-Kuma already run, but only VM-level metrics exist and there are no alerts. Add cAdvisor (per-container RAM/CPU) and alerts for swap > 80 %, disk > 85 %, hddpool > 80 % (it's overcommitted once the backup job exists), unhealthy containers and backups older than 26 h. → [services/management.md](../services/management.md#monitoring-gaps)
- [ ] **Optional: Immich machine learning on the GPU** (`-cuda` image). It would have to share the 8 GB with Ollama; lower Ollama's keep-alive to `20m` first. → [services/ai-tools.md](../services/ai-tools.md#ollama-on-the-gpu)
- [ ] **Docker log rotation** in `/etc/docker/daemon.json` (`max-size 10m`, `max-file 3`). → [services/README.md](../services/README.md#docker-engine-settings)
- [ ] **Patching:** install `unattended-upgrades` (50 updates pending), enable `cloudflared-update.timer`, and `docker compose pull` monthly, starting with the internet-facing ones (portfolio nginx, Minecraft, Playit).
- [ ] **LAN hardening (optional, if you ever share your network):** bind admin ports (Ollama 11434, Postgres 5432/6543, RCON 25575, dashboards) to `127.0.0.1` or the Tailscale IP, like VNC. Also: n8n back to `127.0.0.1:5678`, Homepage's Docker socket to `:ro`, SSH keys instead of the root password.
- [ ] **Start VNC at boot:** turn `vnc-tailscale.sh` (and Xvfb) into systemd services.

## ⚪ Backlog / wishlist

- [ ] **Expand ZFS storage** with more drives (plan the vdev layout first: `zpool status`).
- [ ] **SSO / OIDC for self-hosted apps** (Authentik, Authelia or Pocket ID) so Immich, Grafana, n8n etc. share one login.
- [ ] Move the Immich library to `fastpool/photos`, and app state to `fastpool/appdata`.
- [ ] Containerise the Chrome/Playwright desktop (1.5 GiB cap, `shm_size: 1gb`).
- [ ] Containerized headless game host (Steam / Wolf). *(phase 3.1)* Needs the GPU that Ollama now keeps 5.4 GB of: lower Ollama's keep-alive or use a smaller model first.
- [ ] Moonlight streaming to the Retroid Pocket Flip 2. *(phase 3.3)*
- [ ] Web terminals (ttyd sidecars) and embedded game terminals. *(phases 3.4, 5.3)*
- [ ] Heavy local AI workstation (RX 9070 XT). *(phase 4.1)*
- [ ] Wake-on-LAN remote desktop power management. *(phase 4.2)*
- [ ] Custom React dashboard with live service integration (Mush + Supabase). *(phases 5.1–5.2)*

## ✅ Done

- ✅ Nightly database dumps of Vaultwarden, n8n, Immich and Supabase (`app-db-dumps.sh`, 04:40, 7 kept), carried to hddpool by the VM backup (2026-10-04). → [maintenance](../runbooks/maintenance.md#nightly-app-database-dumps)
- ✅ Ollama's prompt cache capped at 1 GiB (`LLAMA_ARG_CACHE_RAM=1024`) and the container at 3 GiB, after it grew to ~5.5 GB and filled the VM (2026-10-03).
- ✅ `tailscaled` and `sshd` have reserved memory and OOM protection; the Tailscale watchdog skips pointless restarts when memory is the problem (2026-10-03).
- ✅ Portfolio rebuilds itself from GitHub every 5 minutes (`portfolio-update.sh`, 2026-09-29).
- ✅ Data disk no longer reserves its full 1.5 TB on hddpool (`refreservation=none`, checked 2026-09-28).
- ✅ First Proxmox backup of VM 100: storage `hddpool-backups` (600 GiB), 46 GB archive in 2 h 51 min, VM never paused. Nightly job at 05:00, keep-last 7 (2026-09-27/28).
- ✅ Daily `fstrim` at 04:30 instead of weekly, so the backup doesn't read deleted blocks (2026-09-27).
- ✅ VM RAM 12 → 11 GB so the host keeps enough RAM during backups (2026-09-27).
- ✅ Ollama runs on the GPU: NVIDIA driver 615, container toolkit reinstalled, `qwen3:8b` at ~63 tokens/s, model kept loaded (2026-09-26).
- ✅ VM CPU type `host` and QEMU guest agent on, in Proxmox and in the VM (2026-09-26).
- ✅ Minecraft: original world restored after the 2026-09-24 move had left it behind; `mc-backup` now backs up the live folder (2026-09-26). → [services/gaming.md](../services/gaming.md#the-sep-2426-world-mix-up-what-happened-and-how-to-avoid-it)
- ✅ n8n Gmail credential reconnected (2026-09-26).
- ✅ Immich memory capped (server 4 GiB, ML 2 GiB).

- ✅ Media and backups on the HDD pool: 1.5 TB `hddpool` virtual disk at `/mnt/tank` (2026-09-24).
- ✅ Checked the host's ZFS RAM cache: capped at 1.5 GB, not competing with the VM (2026-09-26).
- ✅ Terraria backup cron points at `/srv/games/terraria` again.
- ✅ Vaultwarden reachable at its HTTPS name, **real vault restored** (it had silently been running on an empty database since 2026-09-08), sign-ups turned off (2026-09-25).
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

## Original phase blueprint (status as of 2026-09-26)

| Phase | Item | Status | Notes |
|---|---|---|---|
| 1.1 | Stirling-PDF | ✅ | Running, HTTPS. JVM tuning still pending |
| 1.2 | Remote development (VS Code SSH) | ✅ | Root + password login still allowed |
| 2.1 | Security & torrents (Gluetun) | ✅ | |
| 2.2 | Media & backup (Jellyfin / Immich) | 🟠 | Both deployed; Immich database dumped nightly, **photos have no second copy**; media library empty |
| 2.3 | Terraria server | ✅ | Running; nightly backup working |
| 2.4 | Minecraft server (Paper) | ✅ | World restored 2026-09-26; backups fixed |
| 2.5 | External gaming connectivity | ✅ | Duplicate Playit agent; no whitelist/password |
| 2.6 | System monitoring | 🟡 | Running; no container metrics or alerts |
| 3.1 | Headless game host (Steam/Wolf) | ⚪ | |
| 3.2 | VRAM balancing (Ollama) | 🟡 | Ollama on the GPU (5.4 of 8 GB); no balancing with other GPU users yet |
| 3.3 | Moonlight streaming | ⚪ | |
| 3.4 | Web terminals (ttyd) | ⚪ | |
| 3.5 | RAM caps & Ollama isolation | 🟡 | Immich capped, Ollama model in VRAM, Ollama capped at 3 GiB with a 1 GiB prompt cache (2026-10-03); Supabase and host programs still uncapped |
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
| Ollama limits | RAM/VRAM caps | no cap, CPU | 09-26: on the GPU, keep-alive -1, no RAM cap; 10-03: 3 GiB cap, prompt cache 1 GiB | ✅ |
| Chrome desktop | container, 1.5 GiB | native, VNC open | native, VNC tailnet-only | Backlog |
| Media library | `hddpool/media` | empty dir on root disk | empty dir on data disk | Mid-term |
| Backups | `hddpool/backups` + PBS | same disk as data | inside the VM; 09-27: vzdump of the boot disk to `hddpool-backups`, nightly 05:00; data disk not included; 10-04: nightly app DB dumps | In progress |
| Minecraft data path | one folder | `/srv/games/minecraft` | 09-24: server moved to `data/`, world left behind; 09-26: fixed | ✅ |
| Terraria backup | nightly | working | 09-26: working again | ✅ |
| Playit | one agent | two | two | Short-term |
| qBittorrent config | `/docker/media/config/qbittorrent` | under `/home/<user>` | unchanged | Backlog |
| n8n binding | loopback | `127.0.0.1` | `0.0.0.0` | Mid-term (LAN hardening) |
| Reverse proxy | host nginx | host nginx | `nginx-proxy` container | ✅ docs updated |
| Public ingress | — | assumed port-forward | tunnel (portfolio) + Playit only | ✅ verified |
| Photos | Immich on `fastpool/photos` | absent | on `/mnt/tank`, no backup | Short-term + backlog |
| Root disk | — | 102 GB, 88 % | 502 GB, 15 % | ✅ |
| Log rotation | bounded | none | none | Mid-term |
| Monitoring | full | 1 scrape job | unchanged | Mid-term |
| Guest RAM | 12 GB | swap 5.7 GiB | swap 7.9 GiB (full); 09-26: 5.1 GiB, not thrashing; 09-27: lowered to 11 GB, 4–5 GiB cold swap, no active swapping; 10-03: RAM + swap full, VM unreachable, Ollama capped afterwards | Watch |
| Guest agent | on | inactive | 09-26: on, both sides | ✅ |
