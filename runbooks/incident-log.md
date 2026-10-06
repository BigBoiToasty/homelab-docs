# Incident log

Everything that has gone wrong, newest first: what it looked like, why it happened, how it was fixed, and how to spot it if it comes back. Finished tasks are in the roadmap's [Done list](../roadmap/ROADMAP.md#-done).

**Status:** ✅ fixed · 🟡 open or being watched

---

### 2026-10-05 · VM stuck in Emergency Mode after reboot ✅
- **Symptom:** after the 09:01 reboot into kernel 6.1.0-53, the VM was off the tailnet all day; the noVNC console showed the emergency shell. Back up at 23:24 after a reboot from the console.
- **Cause:** the VM named its disks in a different order that boot (system disk `sdb`, photo disk `sda`). `/etc/fstab` mounted `/mnt/tank` by the name `/dev/sdb` with no `nofail`, so the mount failed (`already mounted or mount point busy`) and boot stopped in Emergency Mode before the network came up. No data was affected.
- **Fix (2026-10-06):** the `/mnt/tank` line in `/etc/fstab` now uses the disk's UUID and `nofail`, like the root and photo-copy disks. Old file kept at `/etc/fstab.bak-2026-10-05`.
- **If it comes back:** `journalctl -b -1 | grep -iE "emergency|Failed to mount"`; every fstab data-disk line should use `UUID=` and `nofail`.

### 2026-10-04 · Two Playit agents fighting ✅
- **Symptom:** random disconnects on the game servers; the agent logged `timeout waiting for register response`, `failed to authenticate`, `control session expired; reconnecting`.
- **Cause:** the host `playit.service` and the `playit` container used the same secret, so Playit saw one agent logging in from two places.
- **Fix:** host service disabled (`systemctl disable --now playit`); only the container runs.
- **If it comes back:** `systemctl is-active playit` must say `inactive`.

### 2026-10-04 · M.2 SSD connection errors 🟡
- **Symptom:** SMART on the host's 256 GB M.2 SATA SSD: 77 `UDMA_CRC_Error_Count`, and 2241 power cycles in 2031 power-on hours. No bad sectors; ZFS reports no errors.
- **Cause:** most likely a loose connection in the M.2 slot.
- **Fix:** reseat planned ([roadmap](../roadmap/ROADMAP.md)).
- **If it comes back:** `smartctl -a /dev/sda | grep -iE "crc|power_cycle"` on the host; rising numbers after reseating mean replace the drive.

### 2026-10-03 · VM ran out of memory, Tailscale down ✅
- **Symptom:** tailnet unreachable from ~19:30; the Proxmox console login hung; the VM had to be shut down from Proxmox at 22:50.
- **Cause:** RAM and all 8 GB of swap full. Ollama's `llama-server` prompt cache (~5.5 GB, default limit 8 GiB), 27 leftover Playwright Chrome processes (~2 GB) and 3 old Claude sessions. `tailscaled` hung (`panic: ipnlocal: watchdog timeout`), and the Tailscale watchdog restarted it 46 times without effect. Claude Code's npm auto-update ran during it, failed, and had to be reinstalled.
- **Fix:** Ollama cache capped (`LLAMA_ARG_CACHE_RAM=1024`, container 3 GiB); `tailscaled` and `sshd` got reserved memory and OOM protection; the watchdog skips restarts when memory is low.
- **If it comes back:** `tail /var/log/tailscale-watchdog.log` (shows free RAM/swap at each failure); `journalctl -b -1 -k | grep -i "killed process"` shows what the kernel killed before the last reboot.

### 2026-10-03 · `cloudflared` fails once at boot ✅ (harmless)
- **Symptom:** `Failed to start cloudflared.service` right after boot (`network is unreachable`).
- **Cause:** it starts before the network is up.
- **Fix:** none needed; systemd restarts it 5 s later and it stays up.

### 2026-09-30 · Kernel killed Ollama ✅
- **Symptom:** `Out of memory: Killed process ... (llama-server)`, ~3.3 GB RAM + 3.5 GB swap.
- **Cause:** the same prompt cache as 2026-10-03 (an early warning).
- **Fix:** see 2026-10-03.

### 2026-09-27 · First VM backup froze the VM ✅
- **Symptom:** during the first vzdump (~03:40), CPU steal up to 78 %, load ~84; the host had to be powered off.
- **Cause:** with the VM at 12 GB and the GPU passed through, the host had too little RAM left for ZFS and vzdump.
- **Fix:** VM RAM 12 → 11 GB; host ZFS write buffer and swappiness tuned; vzdump limited to 50 MiB/s and one compression thread. The retry the same day ran 2 h 51 min with the VM never pausing.
- **Notes:** progress is in `journalctl -fu <unit>`, not `/var/log/vzdump/qemu-100.log`; after an interrupted run check `zfs list -t all | grep fleece` for a leftover fleecing image; run `systemd-run ... vzdump` and `journalctl -fu` as separate commands.

### 2026-09-26 · GPU containers wouldn't start ✅
- **Symptom:** Ollama and Jellyfin `Exited (255)`: `could not select device driver "nvidia"`.
- **Cause:** `apt purge ... libnvidia-*` also matched `libnvidia-container1` and removed the NVIDIA Container Toolkit.
- **Fix:** `apt install nvidia-container-toolkit`, `nvidia-ctk runtime configure --runtime=docker`, `systemctl restart docker`.
- **If it comes back:** never purge NVIDIA packages with a wildcard.

### Until 2026-09-26 · Ollama ran on the CPU ✅
- **Symptom:** one request took ~5 minutes; `library=cpu` in `docker logs ollama`.
- **Cause:** NVIDIA driver 535 was too old for Ollama.
- **Fix:** driver 615 from NVIDIA's apt repo; ~63 tokens/s on the GPU.

### 2026-09-23 to 09-25 · VM out of memory and stalling ✅
- **Symptom:** swap 7.9 / 8 GB, the VM stalled under load; the 09-23 boot had OOM kills and CPU stall warnings.
- **Cause:** Immich uncapped, and Ollama doing inference on the CPU.
- **Fix:** Immich capped (server 4 GiB, ML 2 GiB), Ollama moved to the GPU.

### 2026-09-25 · VNC open without a password ✅
- **Symptom:** `x11vnc -nopw` and noVNC listened on all interfaces, including public IPv6.
- **Fix:** bound to the Tailscale IP only (`/usr/local/bin/vnc-tailscale.sh`).

### 2026-09-24 · Minecraft generated a new world ✅
- **Symptom:** players joined a different map.
- **Cause:** the server files were moved into `/srv/games/minecraft/data/`, but `world/` stayed one level up, so Minecraft made a new world. `mc-backup` still read the parent folder, so nothing looked broken.
- **Fix (2026-09-26):** the original world was copied into `data/world`; `mc-backup` now reads `data/`. Safety copies: `/mnt/tank/backups/minecraft-restore-2026-09-26/`.
- **If it comes back:** when moving a game server's folder, stop it, copy the whole folder, change the server's and the backup's paths together, and check the log says it loads the existing world.

### 2026-09-24 · Terraria backup stopped ✅
- **Symptom:** no new archives in `/mnt/tank/backups/terraria`.
- **Cause:** the cron still archived `/mnt/tank/terraria`, which no longer existed.
- **Fix:** cron `-C` changed to `/srv/games/terraria`.

### ~2026-09-19 · n8n stopped sending job-email notifications ✅
- **Symptom:** Gmail credential error `refresh token expired`.
- **Cause:** the Google OAuth app was in *Testing* mode, which expires tokens every 7 days.
- **Fix:** reconnected 2026-09-26; app published to production 2026-10-04.

### 2026-09-12 to 09-14 · Stirling-PDF kept running out of memory ✅
- **Symptom:** 33 Java heap dumps (~248 MB each, 7.6 GB) in `/mnt/tank/stirling-pdf/extraConfigs/heap_dumps`.
- **Cause:** the default ~256 MiB Java heap was too small for some jobs.
- **Fix:** dumps cleared; heap dumps turned off (`JAVA_CUSTOM_OPTS=-XX:-HeapDumpOnOutOfMemoryError`, 2026-10-04). If crashes return, raise the heap (`-Xmx512m`).

### 2026-09-08 · Vaultwarden and the media apps "reset" 🟡
- **Symptom:** Vaultwarden showed 0 accounts; clients kept working only from their offline cache and couldn't save. Sonarr, Radarr, Jellyfin, Prowlarr, Kavita and LazyLibrarian came up with fresh settings. Vaultwarden also had no working HTTPS name.
- **Cause:** the stacks were recreated with their data path changed from `/root/docker/media/config/<app>` to `/docker/media/config/<app>`, new empty folders.
- **Fix:** Vaultwarden's real vault copied back on 2026-09-25 (backups in `/root/vaultwarden-backup-20260925-1737/`), HTTPS site added, sign-ups turned off. The media apps' old settings are still in `/root/docker/media/config/` (open, see [media.md](../services/media.md#settings-probably-lost-on-2026-09-08)).
- **If it comes back:** before changing a container's data folder, follow [maintenance → Changing a container's data folder](maintenance.md#changing-a-containers-data-folder).
