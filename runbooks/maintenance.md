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

## After a reboot

Most things come back on their own (Docker containers, cloudflared, Tailscale, cron). Two things don't:

1. **The Chrome/VNC desktop.** Start Xvfb and Chrome the way you normally do, then run `/usr/local/bin/vnc-tailscale.sh start`.
2. **Check the containers.** Run `docker ps --format '{{.Names}} {{.Status}}' | grep -v Up`; it should print nothing.

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
- [ ] Confirm the newest backup archives exist and open (`gzip -t file.tar.gz`)
- [ ] Refresh the docs with the audit script
- [ ] Glance at the [roadmap](../roadmap/ROADMAP.md) and tick off what's done
