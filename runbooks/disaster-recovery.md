# Disaster Recovery Runbook

> Covers: Proxmox host loss, ZFS pool re-import, VM 100 loss, Docker stack and per-service data recovery, backup validation.
> Based on the 2026-09-16 inspection. Placeholders: `<PVE_LAN_IP>` = `192.168.x.x`, secrets = `<YOUR_SECRET>`, domains = `*.example.com`.

## 0. Recovery objectives and current reality

| Asset | Where it lives today | Protection in place | Effective RPO | Effective RTO |
|---|---|---|---|---|
| Proxmox host OS | PVE boot device | none observed from the guest | rebuild from ISO | ~1 h |
| ZFS pools `fastpool` (8.72 TB), `hddpool` (2.72 TB) | NVMe/SSD + HDD | pool redundancy (unknown vdev layout — verify with `zpool status`) | n/a | `zpool import` minutes |
| VM 100 disk (`fastpool/vm-100-disk-0`, 102 GB) | fastpool | **no PBS/vzdump job detected**; QEMU guest agent inactive | undefined | reinstall 2–4 h |
| Minecraft world | `/mnt/tank/minecraft` on the VM disk | mc-backup daily, 7 kept, **same disk** | ≤ 24 h | 10 min |
| Terraria world | `/mnt/tank/terraria` | root cron daily 04:00, 7 kept, **same disk** | ≤ 24 h | 10 min |
| Supabase Postgres | `~/docker/supabase-service/volumes/db/data` | **none** | total loss | n/a |
| Vaultwarden vault | `/docker/media/config/vaultwarden` | **none** | total loss | n/a |
| n8n workflows/credentials | `/docker/appdata/n8n` | **none** | total loss | n/a |
| *arr / Jellyfin / Kavita configs | `/docker/media/config/*` | none | rebuild | 1–2 h |
| Ollama models, Stirling OCR data, Docker images | root disk | none needed (re-downloadable) | — | bandwidth-bound (~60 GB) |
| TLS certs, nginx vhosts, Tailscale identity | `/etc/letsencrypt`, `/etc/nginx/sites-enabled`, `/var/lib/tailscale` | none | re-issue / re-auth | 30 min |

**Bottom line:** today a failure of the single zvol loses the Supabase database, the password vault, the automation credentials and both game backups at once. Section 5 fixes that; sections 1–4 tell you how to get back when it happens.

## 1. Bare-metal Proxmox rebuild

Use when the hypervisor boot device or the whole node is lost but the ZFS disks survive.

### 1.1 Prerequisites to have stored off-box (checklist)

- [ ] Proxmox ISO matching `pve-manager 9.2.x` (or newer 9.x) on USB.
- [ ] `/etc/pve` backup (`tar czf pve-config.tgz /etc/pve /etc/network/interfaces /etc/hosts /etc/modprobe.d /etc/default/grub` taken on the host) — contains `qemu-server/100.conf`, `storage.cfg`, user/ACL config.
- [ ] Output of `zpool status`, `zpool list -v`, `zfs list -o name,mountpoint,used`, `zfs get all fastpool/vm-100-disk-0 | grep volsize` saved as text.
- [ ] IOMMU/passthrough notes: PCI ID of the RTX 2060 SUPER (`lspci -nn | grep -i nvidia` on the host), the `vfio-pci` ids line, and the VM's `hostpci0:` entry.
- [ ] Tailscale auth key or admin console access; Cloudflare API token (`<YOUR_SECRET>`); Playit agent secret; Mullvad WireGuard key.

### 1.2 Install and re-import pools

1. Install Proxmox from ISO onto the **boot device only**. Do not let the installer touch the NVMe or HDD members of `fastpool` / `hddpool`. If the installer offers ZFS on the boot device, that is fine; it creates `rpool`, which is separate.
2. First boot: set the management IP to the old `<PVE_LAN_IP>` so the VM's DHCP lease and any NFS exports keep working.
3. Re-import the data pools. `-f` is needed because the pools were last imported by a different host id:

   ```bash
   zpool import                       # lists importable pools; confirm fastpool and hddpool are visible
   zpool import -f fastpool
   zpool import -f hddpool
   zpool status -v                    # all vdevs ONLINE, no errors
   zfs list -r fastpool hddpool       # expect fastpool/appdata, fastpool/photos, fastpool/vms,
                                      # fastpool/vm-100-disk-0 (zvol), hddpool/backups, hddpool/media
   zpool set cachefile=/etc/zfs/zpool.cache fastpool
   zpool set cachefile=/etc/zfs/zpool.cache hddpool
   update-initramfs -u -k all         # so pools import at boot
   ```

   If a pool shows `DEGRADED`, do **not** start VMs; replace the failed member first (`zpool replace <pool> <old> <new>`), let the resilver finish, then continue.
4. Re-register storage in Proxmox so the zvol is usable (Datacenter → Storage, or restore `storage.cfg`):
   - `zfspool: fastpool` with `pool fastpool`, content `images,rootdir`.
   - `zfspool: hddpool` or a `dir` storage on `/hddpool/backups` with content `backup` for vzdump targets.
5. Restore `/etc/pve/qemu-server/100.conf` from the config backup. If it is lost, recreate VM 100 with these known parameters:

   | Setting | Value |
   |---|---|
   | VMID / name | 100 / `debian` (guest hostname `debian-docker`) |
   | Machine | `q35` (guest reports `pc-q35-11.0`), OVMF/UEFI recommended for GPU passthrough |
   | CPU | 4 cores (guest sees `QEMU Virtual CPU version 2.5+` — consider `host` type for AVX in Ollama) |
   | Memory | 12288 MB, ballooning off (fixed) |
   | Disk | `scsi0: fastpool:vm-100-disk-0` (existing zvol, 102 GB), SCSI controller VirtIO SCSI, `discard=on`, `ssd=1` |
   | NIC | `virtio`, bridge `vmbr0` (guest interface `enp6s18`) |
   | Display | default (Virtio GPU) plus `hostpci0: <nvidia-pci-id>,pcie=1` for the RTX 2060 SUPER |
   | Agent | `agent: 1` (and start `qemu-guest-agent` in the guest) |
   | Boot | `order=scsi0` |

6. Re-enable passthrough on the host: IOMMU in `/etc/default/grub` (`intel_iommu=on` or `amd_iommu=on iommu=pt`), `vfio vfio_iommu_type1 vfio_pci` in `/etc/modules`, blacklist `nouveau`/`nvidia` on the host, `update-grub && update-initramfs -u`, reboot, confirm the card is bound to `vfio-pci` (`lspci -k`).
7. Start VM 100. Verify from the guest: `lspci | grep -i nvidia`, `nvidia-smi`, `df -h /`, `docker ps`.

### 1.3 If the zvol itself is intact but the VM won't boot

Boot the VM from a Debian live ISO, `fsck.ext4 -f /dev/sda1`, mount it, chroot, `update-grub`. The most likely causes after a hypervisor rebuild are a changed disk bus (SCSI → SATA) or a missing UEFI boot entry.

## 2. VM 100 restoration

### 2.1 Preferred path: restore from PBS / vzdump (once §5.1 is implemented)

```bash
# On PVE
pvesm list <backup-storage>                       # find the newest vzdump-qemu-100-*.vma.zst or PBS snapshot
qmrestore <archive-or-pbs-path> 100 --storage fastpool --unique 0
qm set 100 --hostpci0 <nvidia-pci-id>,pcie=1      # passthrough is not always preserved
qm start 100
```

Then inside the guest: `systemctl status docker tailscaled nginx`, `docker compose ls`, and continue with §2.3 verification.

### 2.2 Fallback path: rebuild the guest from scratch

Only when no VM backup exists. Order matters; each step depends on the previous.

1. **Base OS:** Debian 12 netinst, hostname `debian-docker`, ext4 root ≥ 102 GB on `fastpool`, 8 GB swapfile (`fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`, add to fstab). Install `qemu-guest-agent nfs-common curl gnupg ca-certificates`. Enable `qemu-guest-agent`.
2. **NVIDIA driver:** for Ollama CUDA support install **≥ 550** (bookworm-backports `nvidia-driver` or NVIDIA's CUDA repo), not the 535 currently installed. Then `nvidia-container-toolkit` from NVIDIA's apt repo, `nvidia-ctk runtime configure --runtime=docker`, which writes the `nvidia` runtime into `/etc/docker/daemon.json`. Reboot, check `nvidia-smi`.
3. **Docker:** Docker CE from `download.docker.com` (engine 29.x, compose plugin 5.x). Create the shared bridge before any stack: `docker network create server-net`.
4. **Tailscale:** install from `pkgs.tailscale.com`, `tailscale up` (or `--auth-key=<YOUR_SECRET>`), confirm MagicDNS name resolves. Reinstate the watchdog: copy `tailscale-watchdog.sh` to `/usr/local/bin/`, `chmod +x`, add the `*/5` root cron line.
5. **Reverse proxy:** `apt install nginx`; `snap install certbot certbot-dns-cloudflare` (snap core is already used here); write `/root/.secrets/cloudflare.ini` with `dns_cloudflare_api_token = <YOUR_SECRET>` (`chmod 600`); issue certs: `certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d n8n.example.com` (repeat for `mush`, `supabase`; add `pdf`). Recreate the five vhosts (§2 of the networking doc lists every upstream). `nginx -t && systemctl reload nginx`.
6. **Directories:** recreate the bind-mount tree with the ownership the containers expect:

   ```bash
   mkdir -p /mnt/tank/{minecraft,terraria/{Worlds,configs},stirling-pdf/{trainingData,extraConfigs},media/{downloads,books,movies,tv},backups/{minecraft,terraria}}
   mkdir -p /docker/appdata/{ollama,n8n} /docker/media/{cache/jellyfin,uptime-kuma,config/{jellyfin,sonarr,radarr,prowlarr,kavita,lazylibrarian,vaultwarden,homepage,qbittorrent}}
   chown -R 1000:1000 /mnt/tank/minecraft /docker/media/config /mnt/tank/media   # PUID/PGID 1000 = user "chris"
   ```

   Prefer to mount `/docker` and `/mnt/tank` from dedicated disks/exports at this point (see storage recommendations in the workloads doc) instead of recreating them on the root disk.
7. **Stacks:** clone or copy `~/docker` (compose files + `.env` files restored from the secrets store), `~/Mush`, and `~/docker/supabase-service`. Restore data into the directories from §3. Bring up in dependency order:

   ```bash
   cd ~/docker/management && docker compose up -d        # dashboards first: homepage, uptime-kuma, dozzle, prometheus, grafana
   cd ~/docker/supabase-service && docker compose up -d  # db must be healthy before kong/rest/auth start (compose handles it)
   cd ~/docker/media && docker compose up -d             # gluetun becomes healthy, then qbittorrent joins its netns
   cd ~/docker/ai-tools && docker compose up -d
   cd ~/docker/gaming && docker compose up -d
   cd ~/Mush && npm ci && npm run build && docker compose up -d
   ```

8. **Playit:** restore `/etc/playit/playit.toml` **or** the container `SECRET_KEY`, not both. Confirm tunnels in the Playit dashboard.

### 2.3 Post-restore verification

| Check | Command | Expect |
|---|---|---|
| All containers up | `docker ps --format '{{.Names}} {{.Status}}' \| grep -v Up` | empty (stirling-pdf optional) |
| Healthchecks | `docker ps --filter health=unhealthy` | empty |
| Minecraft accepting RCON | `docker exec minecraft rcon-cli list` | player list |
| Terraria world loaded | `docker logs terraria --tail 20` | "Server started" |
| Gluetun tunnel | `docker exec gluetun wget -qO- https://ipinfo.io/ip` | a Mullvad address, not your ISP |
| qBittorrent inside VPN | `docker exec qbittorrent wget -qO- https://ipinfo.io/ip` | identical to the previous line |
| Supabase API | `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/rest/v1/ -H "apikey: <YOUR_SECRET>"` | 200 |
| Postgres | `docker exec supabase-db pg_isready -U postgres` | accepting connections |
| nginx + TLS | `curl -sI https://n8n.example.com \| head -1`; `certbot certificates` | 200/302; 3+ valid certs |
| Tailscale | `tailscale status --self` | online, MagicDNS name present |
| GPU in containers | `docker exec ollama nvidia-smi -L`; `docker logs ollama 2>&1 \| grep 'inference compute'` | GPU listed; `library=cuda` |
| Backups running | `ls -lt /mnt/tank/backups/minecraft \| head -2` | file newer than 24 h after first cycle |

## 3. Per-service data recovery

| Service | Restore procedure | Consistency notes |
|---|---|---|
| **Minecraft** | `docker compose stop minecraft` → `tar xzf /mnt/tank/backups/minecraft/world-<date>.tar.gz -C /mnt/tank/minecraft` → `chown -R 1000:1000` → `docker compose start minecraft` | mc-backup tars are RCON-quiesced (`save-off`), so they are safe to restore as-is. Keep `server.properties`/plugins from the live dir if only the world is corrupt. |
| **Terraria** | Stop container → `tar xzf /mnt/tank/backups/terraria/terraria_<date>.tar.gz -C /mnt/tank/terraria` → start | Cron tar runs while the server is live; Terraria writes `.wld` atomically, but a backup taken mid-save can hold the `.wld.bak`. Prefer the second-newest archive if the newest fails to load. |
| **Supabase Postgres** | Logical: `docker exec supabase-db pg_dumpall -U postgres > supabase.sql` (backup) / `cat supabase.sql \| docker exec -i supabase-db psql -U postgres` (restore into a fresh `db` with the same `POSTGRES_PASSWORD` and `JWT_SECRET`). Physical: stop the stack, replace `volumes/db/data`, start `db` alone, then the rest. | Roles, JWT secret and the `supabase_admin` password must match `.env`; otherwise auth/rest fail with 401/500. Storage objects live in `volumes/storage` and must be restored together with the DB (`storage.objects` rows reference them). |
| **Vaultwarden** | Stop container → restore `/docker/media/config/vaultwarden` (`db.sqlite3`, `attachments/`, `rsa_key*`) → start | Restore the RSA key pair too, or every client must re-login. Use `sqlite3 db.sqlite3 ".backup out.db"` for live backups. |
| **n8n** | Stop → restore `/docker/appdata/n8n` (`database.sqlite`, `config`) → start | `config` holds `encryptionKey`; without it stored credentials are unreadable. Also export workflows: `docker exec n8n n8n export:workflow --all --output=/home/node/.n8n/wf.json`. |
| **Jellyfin / *arr / Kavita / LazyLibrarian / Uptime-Kuma / Homepage** | Stop → restore the respective `/docker/media/config/<app>` dir → start | SQLite databases; stop the container first. Media files themselves are re-acquirable. |
| **qBittorrent** | Restore `/home/christopherle/docker/media/config/qbittorrent` (or the new canonical path) | Contains `.torrent` fastresume files; downloads resume from `/mnt/tank/media/downloads`. |
| **Grafana / Prometheus** | `docker run --rm -v monitoring_grafana_data:/v -v $PWD:/b alpine tar czf /b/grafana.tgz -C /v .` (and reverse) | Prometheus TSDB is disposable; Grafana dashboards are worth backing up or provisioning as code. |
| **Ollama / Stirling data** | `docker exec ollama ollama pull qwen3:8b`; Stirling re-downloads tessdata on first start if the dir is empty | No restore needed. |
| **Certificates** | `certbot certonly --dns-cloudflare …` re-issues in ~1 min; rate limit is 50/week per domain | Back up `/etc/letsencrypt` only for convenience. |
| **Tailscale node identity** | `/var/lib/tailscale/tailscaled.state` | Restoring it keeps the same node/IP; otherwise re-auth and update any peer ACLs. |

## 4. Failure troubleshooting matrix

| Symptom | Likely cause | Diagnose | Fix |
|---|---|---|---|
| VM won't start after PVE rebuild: "no such logical volume / zvol" | Pool not imported or storage not defined | `zpool list`; `pvesm status` | §1.2 steps 3–4 |
| VM boots but `nvidia-smi` fails | Passthrough not restored, host grabbed the GPU, or driver mismatch | host: `lspci -k -s <id>` shows `vfio-pci`?; guest: `dmesg \| grep -i nvidia` | Re-add `hostpci0`; blacklist on host; reinstall guest driver |
| Ollama slow, `library=cpu` in logs | Guest driver < 550 | `docker logs ollama \| grep -i driver` | Upgrade driver (current known issue) |
| Container `Exited (137)`, `OOMKilled=false` | SIGKILL after `docker stop` grace period | `docker inspect -f '{{.State}}'`; `journalctl -k \| grep -i oom` | Raise `stop_grace_period`; investigate why the process ignores SIGTERM (Stirling: JVM + unoserver) |
| Container `Exited (137)`, `OOMKilled=true` | Hit cgroup memory cap | `docker stats`, `dmesg` | Raise `memory` or lower JVM `-Xmx` |
| Whole guest sluggish, `si/so` in `vmstat 1` non-zero | Swap thrash: Ollama CPU inference + Minecraft heap | `free -h`, `cat /proc/pressure/memory` | Cap Ollama, fix GPU, or reduce `MAX_MEMORY` |
| Root disk 100 %, containers fail to write | Docker images/logs or Stirling/Ollama data growth | `df -h /`, `docker system df`, `du -shx /var/lib/docker/containers/*/*.log` | `docker system prune`, add log rotation in `daemon.json`, move data to dedicated disks |
| qBittorrent WebUI unreachable after Gluetun restart | qbittorrent still attached to the old netns | `docker inspect qbittorrent -f '{{.HostConfig.NetworkMode}}'` vs current gluetun id | `docker compose up -d` in `media` (recreates qbittorrent) |
| Torrents stall, Gluetun `unhealthy` | Mullvad endpoint/key issue | `docker logs gluetun --tail 50` | Rotate WireGuard key in Mullvad account, update `.env` |
| Public site 502 | Upstream container down or port moved | `docker ps`, `ss -tlnp \| grep 127.0.0.1` | Start container; align `proxy_pass` port |
| Public site cert expired | `certbot.timer` failed (Cloudflare token revoked) | `systemctl status certbot.timer`; `certbot renew --dry-run` | Renew token in `.env` + credentials file |
| Tailscale offline, watchdog log growing | `tailscaled` hung or key expired | `tail /var/log/tailscale-watchdog.log`; `tailscale status` | Watchdog restarts automatically; if key expired, `tailscale up` interactively or disable key expiry in the admin console |
| Minecraft/Terraria unreachable from internet, LAN fine | Playit agent(s) down or fighting | `systemctl status playit`; `docker logs playit` | Run exactly one agent; check dashboard tunnel status |
| Supabase `auth`/`rest` return 401 after restore | `JWT_SECRET`/`ANON_KEY` mismatch with restored DB | compare `.env` with the values the DB roles were created with | Restore the matching `.env`, or re-run `roles.sql`/`jwt.sql` with the new secret |
| `supabase-db` restart loop | Data dir permissions or PG major mismatch (17 ↔ 15 overlay) | `docker logs supabase-db` | Use the `pg17` compose overlay only with a 17 data dir; fix ownership to the container's postgres uid |
| PBS backup of VM 100 reports "guest agent not running" | `qemu-guest-agent` inactive in guest / `agent: 0` in VM config | `qm agent 100 ping` | `qm set 100 --agent 1`; `systemctl enable --now qemu-guest-agent` |

## 5. Backup validation and hardening plan

### 5.1 Target backup architecture

```mermaid
flowchart LR
    subgraph GUEST["VM 100"]
        MC["mc-backup (24 h)"]
        TC["terraria cron (04:00)"]
        PG["pg_dumpall nightly (to add)"]
        CFG["config tar nightly (to add):<br/>/docker, /mnt/tank/*/configs,<br/>supabase volumes, /etc/nginx, /etc/letsencrypt, ~/docker/*.env"]
    end
    subgraph PVE["Proxmox"]
        VZ["vzdump / PBS job for VM 100<br/>nightly, agent-quiesced, keep 7d/4w/6m"]
        SNAP["zfs auto-snapshots<br/>fastpool/vm-100-disk-0 hourly×24, daily×7"]
    end
    HDD["hddpool/backups"]
    OFF["Offsite: PBS remote sync or<br/>restic/rclone → object storage"]

    MC & TC & PG & CFG -->|"NFS mount /mnt/backups → hddpool/backups"| HDD
    VZ --> HDD
    SNAP -. "zfs send" .-> HDD
    HDD --> OFF
```

### 5.2 Implementation checklist

- [ ] **Hypervisor:** create a vzdump or PBS backup job for VM 100 to `hddpool/backups` (mode `snapshot`, compression `zstd`, schedule nightly, retention 7 daily / 4 weekly / 6 monthly). Enable the guest agent (`qm set 100 --agent 1`, `systemctl enable --now qemu-guest-agent` in the guest) so the filesystem is frozen during the snapshot.
- [ ] **Hypervisor:** enable `zfs-auto-snapshot` or sanoid on `fastpool/vm-100-disk-0` and, after the storage realignment, on `fastpool/appdata`.
- [ ] **Guest:** export `hddpool/backups` via NFS from PVE (or attach a second disk) and mount it at `/mnt/backups`; re-point `mc-backup` `/backups` and the Terraria cron there.
- [ ] **Guest:** add a nightly `pg_dumpall` for Supabase and a config tar (list in the diagram) to the same mount; prune with `find -mtime +14 -delete`.
- [ ] **Guest:** run `docker system prune` weekly and add json-file log rotation to `daemon.json` to keep the root disk under 75 %.
- [ ] **Offsite:** PBS remote sync to a second PBS, or `restic`/`rclone` from `hddpool/backups` to object storage with a `<YOUR_SECRET>` repository key stored in the password manager (not on the VM).
- [ ] **Secrets escrow:** copy every `.env`, `cloudflare.ini`, Playit secret, Mullvad key and the Vaultwarden RSA keys to the offsite store; without them a restored DB is unusable.

### 5.3 Validation procedures (run quarterly, record results)

| Test | Steps | Pass criteria |
|---|---|---|
| Minecraft archive integrity | `for f in /mnt/tank/backups/minecraft/*.tar.gz; do gzip -t "$f" && echo OK $f; done`; extract the newest to `/tmp/mc-test`, check `level.dat` and `region/` exist | All archives OK; extracted world loads in a scratch container (`docker run --rm -e EULA=TRUE -e TYPE=PAPER -v /tmp/mc-test:/data itzg/minecraft-server` reaches "Done") |
| Terraria archive | Same `gzip -t`; confirm a `.wld` is present and non-zero | Server starts from extracted world |
| Supabase dump | `pg_dumpall` → restore into `docker run --rm -e POSTGRES_PASSWORD=x supabase/postgres:17.6.1.136` on a scratch port; `psql -c '\dt auth.*'` | Tables present, row counts match production |
| VM-level restore | `qmrestore` the latest vzdump into VMID 900 on an isolated bridge, boot, `docker ps` | All stacks come up without manual edits |
| ZFS snapshot rollback | On PVE: `zfs clone fastpool/vm-100-disk-0@<snap> fastpool/test-clone`, attach to VMID 900 | Boots and mounts cleanly |
| Cert renewal | `certbot renew --dry-run` | "Congratulations, all simulated renewals succeeded" |
| Tailscale watchdog | `systemctl stop tailscaled`; wait ≤ 5 min | `tailscale status` back online, log line appended |
| Restore-time drill | Time a full §2.2 rebuild in a scratch VM | ≤ 4 h, and the drill notes update this runbook |

### 5.4 Known gaps as of 2026-09-16

1. No hypervisor-level backup job and guest agent inactive → VM 100 has no restorable image.
2. All guest backups are on the same 102 GB zvol as the data, on a disk at 88 % capacity.
3. Supabase Postgres, Vaultwarden and n8n have no backups at all.
4. No offsite copy of anything, including the secrets needed to make a restore useful.
5. `hddpool/backups` and `hddpool/media` are provisioned but unused by the guest.
