# Management & monitoring stack (`management`)

> Compose project `~/docker/management` · network `server-net` · last verified 2026-09-25.
> **In one line:** Vaultwarden (password manager), Homepage (dashboard), Uptime-Kuma (up/down checks), Dozzle (container logs) and Prometheus + Grafana (metrics). Monitoring exists but only watches the VM itself; there are no alerts.

## Containers

| Container | Image | Port | Data lives in | Notes |
|---|---|---|---|---|
| vaultwarden | `vaultwarden/server:latest` | 8222→80 | `/docker/media/config/vaultwarden` | Served at `https://vaultwarden.example.com` (tailnet-only). Sign-ups **off** since 2026-09-25. **No backup.** |
| homepage | `ghcr.io/gethomepage/homepage:latest` | 3000 | `/docker/media/config/homepage` | Mounts the Docker socket **read-write**; read-only is enough |
| uptime-kuma | `louislam/uptime-kuma:1` | 3001 | `/docker/media/uptime-kuma` | healthy |
| dozzle | `amir20/dozzle:latest` | 8888→8080 | Docker socket (read-only) | Live container logs |
| prometheus | `prom/prometheus:latest` | 9090 | volume `monitoring_prometheus_data`; config `~/docker/management/prometheus.yml` | One scrape job: `node-exporter` |
| node_exporter | `prom/node-exporter:latest` | internal 9100 | reads `/` read-only | VM CPU/RAM/disk metrics |
| grafana | `grafana/grafana:latest` | 3005→3000 | volume `monitoring_grafana_data` | Dashboards |

**Who can reach it:** LAN + tailnet by port; Vaultwarden also by name over Tailscale. None are on the internet.

## Vaultwarden

**Why it "didn't work" (fixed 2026-09-25).** Two separate problems:

1. **No way in.** `DOMAIN` was `https://vaultwarden.example.com`, but that name had no DNS record and no nginx site, and Bitwarden clients require HTTPS. Fixed with `add-site.sh vaultwarden 8222 --max-body 525M` plus a Cloudflare **A** record → Tailscale IP (DNS only).
2. **The vault "reset" on 2026-09-08.** The `management` stack was recreated with its data path changed from `/root/docker/media/config/vaultwarden` to `/docker/media/config/vaultwarden`, a new empty folder. The server started as a fresh install (0 accounts). The real vault (1 account, 4 items, last change 2026-08-26) stayed in the old folder, and clients kept working only from their offline cache, unable to save. Fixed by copying the old data into the live path. Backups of both versions: `/root/vaultwarden-backup-20260925-1737/`. The empty folder was kept as `/docker/media/config/vaultwarden.empty-20260925`, and the old folder is still in place (delete both only once real backups exist).

Afterwards `SIGNUPS_ALLOWED` was set to `false` (compose backup: `docker-compose.yml.bak-20260925`).

This is the highest-value data in the stack. **Backed up nightly since 2026-10-04:** `db.sqlite3` (via `sqlite3 .backup`) and `rsa_key.pem` go to `/root/backups/app-dumps/<date>/` at 04:40, and the 05:00 VM backup copies them to hddpool ([nightly app dumps](../runbooks/maintenance.md#nightly-app-database-dumps)). Without the RSA key, every client must log in again. There is no `attachments/` folder yet; if you start using attachments, add it to the script.

- Still open: an off-site copy.

## Monitoring gaps

What exists: Prometheus scrapes node-exporter every 15 s, Grafana shows it, and Uptime-Kuma pings services. What's missing:

- **Per-container metrics:** add cAdvisor, so you can see which container is eating RAM.
- **Alerts:** swap > 80 %, disk > 85 %, a container unhealthy, a backup older than 26 h. Use Grafana alerting or Uptime-Kuma notifications (Discord/Telegram/email).
- A second `prometheus/prometheus.yml` in the stack folder is unused; delete it to avoid confusion.
