# Roadmap

> Planned work, tech debt and wishlist for the homelab. Last updated 2026-10-20.
> Each task says **why** it matters and links to where the details live. Tick the box when done and move the line to [Done](#-done). Problems and their fixes are in the [incident log](../runbooks/incident-log.md).

**Legend:** 🔴 in progress · 🟠 urgent (risk of losing data) · 🟡 soon · ⚪ someday · ✅ done

---

## 🔴 In progress

- [ ] **Test-restore the VM 100 backup once** (needs VM 100 off for 1–2 h). → [disaster-recovery §5.3](../runbooks/disaster-recovery.md#53-validation-procedures-run-quarterly-record-results)
- [ ] **Close old Claude sessions and leftover Chrome** now and then; they held ~2.7 GB on 2026-10-03.
- [ ] **Tune Immich background uploads/jobs.** Lower job concurrency in Admin → Jobs and run face detection / smart search overnight so they don't fight the game servers. → [services/immich.md](../services/immich.md#memory-and-cpu)

## 🟠 Short-term / immediate

Things that can lose data or are one-line fixes.


- [ ] **Long SMART test on HDD `sdj`** (2 pending sectors, 1 uncorrectable); replace it if the counts rise. hddpool is raidz1, so this disk is its only spare margin. → [incident-log](../runbooks/incident-log.md#2026-10-26--hdd-sdj-has-unreadable-sectors-)
- [ ] **Reseat the 256 GB M.2 SSD in the Proxmox host** (connection errors; flash healthy), then recheck its SMART counters. → [host-and-vm.md](../architecture/host-and-vm.md#proxmox-host)
- [ ] **Off-site copy** of the photos and database dumps (e.g. Backblaze B2).

## 🌐 Mush (public since 2026-10-11)

- [ ] Test a real sign-up on a phone off the tailnet (Turnstile in a real browser). Optional: Google sign-in (disabled on the server).
- [ ] **Delete the old Vercel project** (`pokemush.vercel.app`) once Google lists the own domain instead, around December 2026. Until then it only redirects (308) to the own domain.

## 🎮 Game streaming (next project)

Play Sekiro and Ghost of Tsushima from the server on the Retroid Pocket Flip 2 (Moonlight), at home and via Tailscale. Minecraft and Terraria keep running.

- [ ] **Phase A:** a games disk, a `game-mode` switch that pauses Ollama/n8n/Stirling/Immich ML, Wolf (Games on Whales), Moonlight on the Retroid.
- [ ] **Phase B:** RAM upgrade. Host has 32 GB since 2026-10-10 (4 × 8 GB DDR4). VM 22 GB / 8 vCPU since 2026-10-11. Still to do: Steam for the big games.

## 🟡 Mid-term infrastructure upgrades

- [ ] **Pi-hole as the tailnet's DNS** for ad blocking.
- [ ] **Renew Mullvad** (gluetun down since ~2026-09-27). Afterwards:
  - `docker restart gluetun qbittorrent`;
  - remove both from `/etc/homelab-alerts/silence` and un-pause Kuma's qBittorrent monitor;
  - note the paid-until date for a renewal reminder.

  → [services/media.md](../services/media.md)
- [ ] **Homelab monitor (prototype live 2026-10-25):** revise the design, then add `grafana.db` to the nightly dumps. Later: cAdvisor for per-container stats, a SMART exporter on the host. → [services/management.md](../services/management.md#homelab-monitor-httpsmonitorexamplecom)
- [ ] **Patching from now on:** `apt update && apt full-upgrade` monthly (or `unattended-upgrades`), and `docker compose pull` for the internet-facing containers (portfolio nginx, Mush nginx, Supabase Kong/auth/rest/storage/realtime, Minecraft, Playit).

## ⚪ Backlog / wishlist


- [ ] Web terminals (ttyd sidecars) and embedded game terminals. *(phases 3.4, 5.3)*
- [ ] Heavy local AI workstation (RX 9070 XT). *(phase 4.1)*
- [ ] **Local agent on the RX 9070 XT:**
  - **Working:** Qwen3.6 on the desktop scores job postings; Workday auto-fill stops before Submit; job emails update the tracker and sheet.
  - **Next:** Greenhouse/Lever/Ashby auto-fill, then a supervised nightly run. → [services/ai-tools.md](../services/ai-tools.md#job-application-automation)
- [ ] **Open-source the job-search toolkit** (career-ops + interview coach) as a public GitHub repo that others can run.
  - A localhost web app: browse and filter jobs, choose which companies get a full evaluation, and practise interviews.
  - Bring your own model (a local LLM through LM Studio/Ollama, or Claude for the harder steps).
  - Users add their own job sources (GitHub repos, careers pages) that are scanned and triaged automatically.
  - Low token use: scripts do the scraping, filtering and form filling; a model is only called for scoring and the short written answers. The upstream career-ops used up the Claude limit evaluating about 5 job postings.
  - Start after the 2026-10-20 interview. Remove personal data (profile, CV, tracker, secrets) from the repo first.
- [ ] Wake-on-LAN remote desktop power management. *(phase 4.2)*
- [ ] Custom React dashboard with live service integration (Mush + Supabase). *(phases 5.1–5.2)*

## ✅ Done

- ✅ Career site study guides: graded quiz mode with spaced review, spoken answers and Qwen-written questions (2026-10-26). → [ai-tools](../services/ai-tools.md)
- ✅ Career site: old `interview.` hostname retired (nginx redirect and DNS record removed); `career.` is the only name (2026-10-20).
- ✅ Monitoring alerts to Discord `#homelab`: a server-health script, plus Uptime-Kuma restored with 22 monitors; Kuma and Jellyfin added to the nightly dumps (2026-10-13).
- ✅ n8n job emails: full-email reading, cleaner Discord cards, tracker and sheet sync (2026-10-13).
- ✅ Media apps' pre-Sep-8 settings restored and fixed for the current setup; logins off except Kavita (2026-10-12).
- ✅ VM memory watch closed: 22 GB VM; swap 1.5 of 8 GB after a day of use, down from 5.7 GB before the RAM upgrade (2026-10-12).
- ✅ Mush's main address is its own domain: canonical, sitemap and share tags moved; the old Vercel copy redirects every path there (2026-10-12).
- ✅ Mush rebuilds itself from GitHub every 5 minutes (`mush-update.sh`: tests, build, then swap), with cache rules in its nginx (2026-10-12).
- ✅ Mush binder backgrounds fixed: storage policy for `binder-backgrounds` added by the owner (2026-10-12).
- ✅ Mush and its Supabase API public through the Cloudflare Tunnel; Studio not exposed; sign-ups need Cloudflare Turnstile (2026-10-11).
- ✅ VM on kernel 6.1.0-53, Ollama still 100 % on the GPU (2026-10-11).
- ✅ VM 100 resized to 22 GB / 8 vCPU after the host RAM upgrade (2026-10-11).
- ✅ Nightly VM backups confirmed succeeding (2026-10-04).
- ✅ n8n's Google OAuth app published to production (2026-10-04).
- ✅ Unknown device removed from the tailnet (2026-10-04).
- ✅ Cloudflare: one API token left (DNS-only); dead token removed from `~/docker/.env` (2026-10-04).
- ✅ Duplicate apt certbot removed; only the snap certbot runs (2026-10-04).
- ✅ All 51 OS updates installed (2026-10-04).
- ✅ 2FA: Tailscale and Cloudflare log in with Google, which has 2-Step Verification (2026-10-04).
- ✅ Duplicate Playit agent removed; only the container runs (2026-10-04).
- ✅ Stirling-PDF heap dumps turned off (2026-10-04).
- ✅ Docker log rotation (10 MB × 3) (2026-10-04).
- ✅ Immich photos copied nightly to a fastpool disk (2026-10-04). → [maintenance](../runbooks/maintenance.md#nightly-immich-photo-copy)
- ✅ Nightly database dumps of Vaultwarden, n8n, Immich and Supabase (2026-10-04). → [maintenance](../runbooks/maintenance.md#nightly-app-database-dumps)
- ✅ Ollama prompt cache capped at 1 GiB, container at 3 GiB (2026-10-03).
- ✅ Reserved memory for `tailscaled` and `sshd`; smarter Tailscale watchdog (2026-10-03).
- ✅ Portfolio rebuilds itself from GitHub every 5 minutes (`portfolio-update.sh`, 2026-09-29).
- ✅ Data disk no longer reserves its full 1.5 TB on hddpool (`refreservation=none`, checked 2026-09-28).
- ✅ First Proxmox backup of VM 100: storage `hddpool-backups` (600 GiB), 46 GB archive in 2 h 51 min, VM never paused. Nightly job at 05:00, keep-last 7 (2026-09-27/28).
- ✅ Daily `fstrim` at 04:30 instead of weekly, so the backup doesn't read deleted blocks (2026-09-27).
- ✅ VM RAM 12 → 11 GB so the host keeps enough RAM during backups (2026-09-27).
- ✅ Ollama runs on the GPU: NVIDIA driver 615, container toolkit reinstalled, `qwen3:8b` at ~63 tokens/s, model kept loaded (2026-09-26).
- ✅ VM CPU type `host` and QEMU guest agent on, in Proxmox and in the VM (2026-09-26).
- ✅ Minecraft: original world restored after the 2026-09-24 move had left it behind; `mc-backup` now backs up the live folder (2026-09-26). → [services/gaming.md](../runbooks/incident-log.md)
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
- ✅ Certificate renewal fully automatic, including the nginx reload (2026-10-04).
- ✅ Monitoring stack running (Prometheus, Grafana, Uptime-Kuma). *Alerts still missing; see mid-term.*
- ✅ Stirling-PDF, Gluetun VPN kill switch, Minecraft (tuned Paper) and Terraria servers, Playit tunnels.
- ✅ Remote development over SSH (VS Code Remote-SSH).
