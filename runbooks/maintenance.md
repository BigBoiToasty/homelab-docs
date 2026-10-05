# Maintenance runbook

> Routine, step-by-step tasks. Run them on VM 100 as root unless noted. For "everything is broken" scenarios see [disaster-recovery.md](disaster-recovery.md).

## Quick health check (2 minutes)

```bash
docker ps --filter health=unhealthy --format '{{.Names}}'      # should print nothing
docker ps -a --filter status=exited --format '{{.Names}} {{.Status}}'   # portfolio-build is expected
free -h                                                          # watch the Swap "used" column
df -h / /mnt/tank                                                # keep both under ~80 %
systemctl --failed --no-pager                                    # should list 0 units
ls -lt /mnt/tank/backups/minecraft /mnt/tank/backups/terraria | head   # newest files < 24 h old
```

On the Proxmox host, check the nightly VM backup:

```bash
ls -lh /hddpool/backups/dump/ | tail -4                          # newest vzdump-qemu-100-*.vma.zst from today, ~40–50 GB
grep -h 'Finished Backup\|ERROR' /hddpool/backups/dump/vzdump-qemu-100-*.log | tail -2   # "Finished Backup of VM 100", no ERROR
```

## Nightly schedule

| Time | Where | Job |
|---|---|---|
| 04:00 | VM (root cron) | Terraria world → `/mnt/tank/backups/terraria` |
| 04:10 | VM (root cron) | `immich-photo-copy.sh`: `/mnt/tank/immich` (hddpool) → `/mnt/photo-copy/immich` (fastpool disk) ([below](#nightly-immich-photo-copy)) |
| 04:30 | VM (`fstrim.timer`, override in `/etc/systemd/system/fstrim.timer.d/override.conf`) | Trim deleted blocks on `/` and `/mnt/tank`, so the backup skips them |
| 04:40 | VM (root cron) | `app-db-dumps.sh`: Vaultwarden, n8n, Immich and Supabase databases → `/root/backups/app-dumps/<date>/` ([below](#nightly-app-database-dumps)) |
| 05:00 | Proxmox host (Datacenter → Backup) | vzdump of VM 100's boot disk to `hddpool-backups`, keep 7; ~1–3 h |
| ~06:00–07:00 | VM (`apt-daily-upgrade.timer`, randomized) | Package list refresh / upgrades |
| every 24 h from container start | VM (`mc-backup`) | Minecraft world → `/mnt/tank/backups/minecraft` |
| every 5 min | VM (root cron) | Portfolio: pull from GitHub and rebuild if `main` changed ([web-apps](../services/web-apps.md#updating)) |

### Nightly app database dumps

`/usr/local/bin/app-db-dumps.sh` (root cron, 04:40, since 2026-10-04) writes clean copies of the irreplaceable databases to the **boot disk**. The 05:00 VM backup then carries them to hddpool, a different physical pool. The VM backup alone copies the databases as live files, which usually restores fine but isn't guaranteed; these dumps are.

| File in `/root/backups/app-dumps/<date>/` | Made with | Checked by the script |
|---|---|---|
| `vaultwarden.sqlite3`, `vaultwarden-rsa_key.pem` | `sqlite3 .backup` (safe while running) | `pragma integrity_check` |
| `n8n.sqlite`, `n8n-config` (encryption key) | `sqlite3 .backup` | `pragma integrity_check` |
| `immich.sql.gz` | `pg_dumpall -U postgres --clean --if-exists` in `immich_postgres` | ends with "cluster dump complete" |
| `supabase.sql.gz` | `pg_dumpall -U supabase_admin --clean --if-exists` in `supabase-db` (`postgres` isn't a superuser in Supabase) | same |

- ~62 MB per night, ~10 s. Folders older than 7 days are deleted. Everything is mode `600`/`700` (root only), because it contains the vault and the n8n key.
- Result log: `tail /var/log/app-db-dumps.log` should show `OK <size> in ...` for each night; `FAILED: <app>` names what broke.
- **Not included:** the Immich photos (data disk, see the [roadmap](../roadmap/ROADMAP.md)) and Supabase's file storage `volumes/storage` (on the boot disk, so the VM backup covers it; empty so far).
- Restoring from a dump: [disaster-recovery §3](disaster-recovery.md#3-per-service-data-recovery).

### Nightly Immich photo copy

`/usr/local/bin/immich-photo-copy.sh` (root cron, 04:10, since 2026-10-04) mirrors `/mnt/tank/immich` (data disk on **hddpool**) to `/mnt/photo-copy/immich` (its own 150 GB disk on **fastpool**). If either pool dies, the other still has the photos.

- `rsync -a --delete` at low priority. Files deleted or changed in Immich aren't lost straight away: the old version moves to `/mnt/photo-copy/deleted/<date>/` and is removed after 30 days.
- **Safety checks:** it refuses to run if `/mnt/photo-copy` isn't mounted (rsync would otherwise fill the boot disk) or if `/mnt/tank/immich/library` is missing or empty (`--delete` would otherwise wipe the copy). Both were tested.
- First full copy 2026-10-04: 48 GB, 24,764 files, ~11 min, verified file-by-file. A normal night takes seconds.
- Result log: `tail /var/log/immich-photo-copy.log` shows `OK <size> copied, <free> free` each night.
- Space: 48 of 147 GB used. Grow the disk in Proxmox (VM 100 → Hardware → Disk Action → Resize), then `resize2fs /dev/sdc` in the VM.
- Restore: stop Immich, `rsync -a /mnt/photo-copy/immich/ /mnt/tank/immich/`, restore the matching database dump ([disaster-recovery §3](disaster-recovery.md#3-per-service-data-recovery)), start Immich.
- **Not off-site:** fire, theft or a surge would take both pools. That's the next step on the [roadmap](../roadmap/ROADMAP.md).

Don't reboot the host or the VM between 05:00 and ~08:00 without checking whether the backup is still running (`pgrep -a vzdump` on the host). A running backup can be followed with `journalctl -fu <unit>` or in the web UI under the node's Tasks.

## After a reboot

Most things come back on their own (Docker containers, cloudflared, Tailscale, cron). Check these:

1. **The Chrome/VNC desktop.** Start Xvfb and Chrome the way you normally do, then run `/usr/local/bin/vnc-tailscale.sh start`.
2. **Check the containers.** Run `docker ps --format '{{.Names}} {{.Status}}' | grep -v Up`; it should print nothing.
3. **Check the GPU.** `docker exec ollama ollama ps` should show the model on `100% GPU` after its first request. If Ollama or Jellyfin exited with `could not select device driver "nvidia"`, see [ai-tools → Ollama on the GPU](../services/ai-tools.md#ollama-on-the-gpu).

## Update containers

Monthly is a good rhythm. Do the internet-facing stacks first (`gaming`, `portfolio`).

```bash
cd ~/docker/<stack>            # gaming, portfolio, media, management, ai-tools, immich, reverse-proxy
docker compose pull
docker compose up -d
docker image prune -f          # delete the old image layers
```

- **Immich:** read the release notes first; major versions sometimes need a manual step. The compose file pins `v3`.
- **Supabase:** versions are pinned in its compose file; upgrade deliberately, following upstream's notes.
- **Mush / portfolio:** see [services/web-apps.md](../services/web-apps.md#updating).

## Update the OS

```bash
apt update && apt list --upgradable
apt upgrade
# If the kernel or NVIDIA driver was upgraded, reboot, then follow "After a reboot".
```

**NVIDIA packages:** never remove them with a wildcard like `apt purge libnvidia-*`. That also matches `libnvidia-container1`, which takes the NVIDIA Container Toolkit with it, and the GPU containers stop starting (this happened on 2026-09-26). Check what apt will remove before confirming. The driver comes from NVIDIA's apt repo (`nvidia-official.list`), so `apt upgrade` can move it to a newer major version. Reboot afterwards and do the GPU check above.

## Changing a container's data folder

For example, when moving a service to another disk:

1. Stop the container.
2. Copy the **whole** folder and check that the important part came along (Minecraft: `world/`; databases: their data directory).
3. Change the path in the service **and** in anything that backs it up (like `mc-backup`, or cron jobs).
4. Start it and read the log. It must load the existing data, not create new data. Minecraft silently generates a new world if it can't find one (this happened on 2026-09-24).
5. Keep the old folder until you've checked the service in normal use.

## Add a new website (tailnet-only)

1. Make sure the app's port is published on the host (e.g. `8096` for Jellyfin).
2. Preview, then create the site:
   ```bash
   bash ~/homelab-docs/scripts/add-site.sh jellyfin 8096 --dry-run
   bash ~/homelab-docs/scripts/add-site.sh jellyfin 8096
   ```
   The wildcard certificate already covers any `*.example.com` name, so no new certificate is needed.
3. In Cloudflare DNS, add an **A** record `jellyfin` → the server's Tailscale IP, set to **DNS only** (grey cloud). The site then works from any device with Tailscale on.
4. **To make a site public** instead: don't open router ports. Add it as a public hostname on the Cloudflare Tunnel (Zero Trust → Networks → Tunnels), optionally behind Cloudflare Access.

To remove a site: delete `~/docker/reverse-proxy/conf.d/<name>.conf`, run `docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload`, then delete the DNS record.

## Certificates

```bash
certbot certificates                 # expiry dates
certbot renew --dry-run              # proves renewal will work
docker exec nginx-proxy nginx -s reload   # after any renewal, until the deploy hook exists
```

## VNC desktop (Tailscale-only)

```bash
/usr/local/bin/vnc-tailscale.sh status   # what's listening
/usr/local/bin/vnc-tailscale.sh start    # (re)start bound to the Tailscale IP
/usr/local/bin/vnc-tailscale.sh stop
```

Connect with a VNC client to `<tailscale-ip>:5900`, or in a browser to `http://<tailscale-ip>:3010/vnc.html`.

## Refresh these docs

```bash
bash ~/homelab-docs/scripts/audit-homelab.sh > ~/audit.md    # outside the repo; the file is chmod 600
```

Then ask Claude (or read it yourself) to compare `~/audit.md` with the docs and update what changed. Never commit the report. Details: [scripts/README.md](../scripts/README.md).

## Monthly checklist

- [ ] Quick health check (above)
- [ ] Update containers and OS
- [ ] Look at swap and disk trends in Grafana
- [ ] Confirm the newest backup archives exist and open (`gzip -t file.tar.gz`; for the VM backup on the host, `zstd -t /hddpool/backups/dump/<newest>.vma.zst`)
- [ ] Refresh the docs with the audit script
- [ ] Glance at the [roadmap](../roadmap/ROADMAP.md) and tick off what's done
