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

- [ ] **Reseat the 256 GB M.2 SSD in the Proxmox host.** It shows 77 connection (CRC) errors and 2241 power cycles in 2031 hours, a sign of a loose connection; the flash itself is healthy. Shut down, unplug, reseat, tighten the screw. Then recheck `smartctl -a /dev/sda | grep -iE "crc|power_cycle"` every few days: if the numbers still climb, plan a replacement. → [host-and-vm.md](../architecture/host-and-vm.md#proxmox-host)
- [ ] **Off-site copy** of the photos and `/root/backups/app-dumps` (Backblaze B2 ≈ $0.30/month for 48 GB with restic, or the Windows desktop over Tailscale). Protects against fire/theft/surge, which take out both pools.
- [ ] **Lock the public game servers.** Minecraft whitelist on (`ENABLE_WHITELIST`, `ENFORCE_WHITELIST`, `WHITELIST=`); Terraria server password; in the Playit dashboard, confirm only 25565 and 7777 are tunnelled. → [services/gaming.md](../services/gaming.md#who-can-reach-it)
- [ ] **Review the tailnet devices** in the Tailscale admin console (Machines): remove any you don't recognize, such as a phone from another account that was offline for 8+ days on 2026-10-03.
- [ ] **Scope the Cloudflare API token** to DNS-edit on one zone.

## 🟡 Mid-term infrastructure upgrades

- [ ] **Optional:** `apt purge certbot` so only the snap certbot runs (both work; it's just duplication). → [networking-and-security.md §2.1](../architecture/networking-and-security.md#21-private-https-via-nginx-proxy-tailnet-only-by-dns)
- [ ] **Local DNS with Pi-hole or AdGuard Home** (optional). Today the public DNS records point at the Tailscale IP, which works but shows your tailnet address to anyone who looks it up. A local DNS server (or Tailscale split DNS) could answer `*.example.com` privately instead.
- [ ] **Finish monitoring.** Prometheus + Grafana + Uptime-Kuma already run, but only VM-level metrics exist and there are no alerts. Add cAdvisor (per-container RAM/CPU) and alerts for swap > 80 %, disk > 85 %, hddpool > 80 % (it's overcommitted once the backup job exists), unhealthy containers and backups older than 26 h. → [services/management.md](../services/management.md#monitoring-gaps)
- [ ] **Optional: Immich machine learning on the GPU** (`-cuda` image). It would have to share the 8 GB with Ollama; lower Ollama's keep-alive to `20m` first. → [services/ai-tools.md](../services/ai-tools.md#ollama-on-the-gpu)
- [ ] **Reboot the VM once** to start the new kernel 6.1.0-53 (installed 2026-10-04; the NVIDIA driver is already built for it). Afterwards check `docker exec ollama ollama ps` shows `100% GPU` after the first request.
- [ ] **Patching from now on:** `apt update && apt full-upgrade` monthly (or `unattended-upgrades`), and `docker compose pull` for the internet-facing containers (portfolio nginx, Minecraft, Playit).
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

- ✅ All 51 OS updates installed: Docker 29.8.2, Tailscale 1.102.4, cloudflared 2026.9.3, kernel 6.1.0-53 (needs a reboot). Every container came back healthy (2026-10-04).
- ✅ 2FA: Tailscale and Cloudflare are both logged into with Google, and the Google account has 2-Step Verification (confirmed by the owner 2026-10-04). If Cloudflare ever gets its own password, turn on Cloudflare's 2FA too.
- ✅ Duplicate Playit agent removed: the host `playit.service` and the container shared one secret and kept knocking each other off; only the container runs now (2026-10-04).
- ✅ Stirling-PDF heap dumps gone and turned off (`JAVA_CUSTOM_OPTS=-XX:-HeapDumpOnOutOfMemoryError`, 2026-10-04).
- ✅ Docker log rotation set in `daemon.json` (10 MB × 3), active from the next Docker start / container recreate (2026-10-04).
- ⚪ Decided **not** to `chmod 600` the `.env` files: only root and the owner log in (2026-10-04).
- ✅ Immich photos copied nightly to their own 150 GB disk on fastpool, deleted files kept 30 days (2026-10-04). → [maintenance](../runbooks/maintenance.md#nightly-immich-photo-copy)
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
- ✅ Automatic certificate renewal (certbot timers) and nginx reload hook; one wildcard certificate for all sites, three unused old ones deleted, renewal dry-run passed (2026-10-04).
- ✅ Monitoring stack running (Prometheus, Grafana, Uptime-Kuma). *Alerts still missing; see mid-term.*
- ✅ Stirling-PDF, Gluetun VPN kill switch, Minecraft (tuned Paper) and Terraria servers, Playit tunnels.

---

## Original phase blueprint (status as of 2026-09-26)

| Phase | Item | Status | Notes |
|---|---|---|---|
| 1.1 | Stirling-PDF | ✅ | Running, HTTPS. JVM tuning still pending |
| 1.2 | Remote development (VS Code SSH) | ✅ | Root + password login still allowed |
| 2.1 | Security & torrents (Gluetun) | ✅ | |
| 2.2 | Media & backup (Jellyfin / Immich) | 🟡 | Both deployed; Immich database and photos backed up nightly on the server, not off-site; media library empty |
| 2.3 | Terraria server | ✅ | Running; nightly backup working |
| 2.4 | Minecraft server (Paper) | ✅ | World restored 2026-09-26; backups fixed |
| 2.5 | External gaming connectivity | ✅ | One Playit agent since 2026-10-04; no whitelist/password |
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
| Stirling-PDF memory | 512 MiB, `-Xmx256m` | 1 GiB, defaults, stopped | 1 GiB, defaults, running; 33 heap dumps show repeated OOMs; 10-04: dumps gone and turned off | Optional |
| Ollama limits | RAM/VRAM caps | no cap, CPU | 09-26: on the GPU, keep-alive -1, no RAM cap; 10-03: 3 GiB cap, prompt cache 1 GiB | ✅ |
| Chrome desktop | container, 1.5 GiB | native, VNC open | native, VNC tailnet-only | Backlog |
| Media library | `hddpool/media` | empty dir on root disk | empty dir on data disk | Mid-term |
| Backups | `hddpool/backups` + PBS | same disk as data | inside the VM; 09-27: vzdump of the boot disk to `hddpool-backups`, nightly 05:00; data disk not included; 10-04: nightly app DB dumps | In progress |
| Minecraft data path | one folder | `/srv/games/minecraft` | 09-24: server moved to `data/`, world left behind; 09-26: fixed | ✅ |
| Terraria backup | nightly | working | 09-26: working again | ✅ |
| Playit | one agent | two | two; 10-04: one (container) | ✅ |
| qBittorrent config | `/docker/media/config/qbittorrent` | under `/home/<user>` | unchanged | Backlog |
| n8n binding | loopback | `127.0.0.1` | `0.0.0.0` | Mid-term (LAN hardening) |
| Reverse proxy | host nginx | host nginx | `nginx-proxy` container | ✅ docs updated |
| Public ingress | — | assumed port-forward | tunnel (portfolio) + Playit only | ✅ verified |
| Photos | Immich on `fastpool/photos` | absent | on `/mnt/tank`, no backup; 10-04: nightly copy on a fastpool disk | Backlog (move) + off-site |
| Root disk | — | 102 GB, 88 % | 502 GB, 15 % | ✅ |
| Log rotation | bounded | none | none; 10-04: set in `daemon.json` (from next Docker start) | ✅ |
| Monitoring | full | 1 scrape job | unchanged | Mid-term |
| Guest RAM | 12 GB | swap 5.7 GiB | swap 7.9 GiB (full); 09-26: 5.1 GiB, not thrashing; 09-27: lowered to 11 GB, 4–5 GiB cold swap, no active swapping; 10-03: RAM + swap full, VM unreachable, Ollama capped afterwards | Watch |
| Guest agent | on | inactive | 09-26: on, both sides | ✅ |
