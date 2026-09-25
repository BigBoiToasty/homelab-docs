# Management & monitoring stack (`management`)

> Compose project `~/docker/management` · network `server-net` · last verified 2026-09-25.
> **In one line:** Vaultwarden (password manager), Homepage (dashboard), Uptime-Kuma (up/down checks), Dozzle (container logs) and Prometheus + Grafana (metrics). Monitoring exists but only watches the VM itself; there are no alerts.

## Containers

| Container | Image | Port | Data lives in | Notes |
|---|---|---|---|---|
| vaultwarden | `vaultwarden/server:latest` | 8222→80 | `/docker/media/config/vaultwarden` | Served at `https://vaultwarden.example.com` since 2026-09-25 (needs its DNS record). **Sign-ups are open**. **No backup.** |
| homepage | `ghcr.io/gethomepage/homepage:latest` | 3000 | `/docker/media/config/homepage` | Mounts the Docker socket **read-write**; read-only is enough |
| uptime-kuma | `louislam/uptime-kuma:1` | 3001 | `/docker/media/uptime-kuma` | healthy |
| dozzle | `amir20/dozzle:latest` | 8888→8080 | Docker socket (read-only) | Live container logs |
| prometheus | `prom/prometheus:latest` | 9090 | volume `monitoring_prometheus_data`; config `~/docker/management/prometheus.yml` | One scrape job: `node-exporter` |
| node_exporter | `prom/node-exporter:latest` | internal 9100 | reads `/` read-only | VM CPU/RAM/disk metrics |
| grafana | `grafana/grafana:latest` | 3005→3000 | volume `monitoring_grafana_data` | Dashboards |

**Who can reach it:** LAN + tailnet by port; Vaultwarden also by name over Tailscale. None are on the internet.

## Vaultwarden

**Why it "didn't work" (fixed 2026-09-25):** `DOMAIN` was set to `https://vaultwarden.example.com`, but that name had no DNS record and no nginx site. Bitwarden apps and the web vault require HTTPS, so `http://<ip>:8222` can't be used either. There was no working way in. Fix: `add-site.sh vaultwarden 8222 --max-body 525M` (done), plus a Cloudflare DNS **A** record `vaultwarden` → Tailscale IP, DNS only (**to do**). Then point the Bitwarden apps at `https://vaultwarden.example.com` (Settings → self-hosted → Server URL).

This is the highest-value data in the stack, and it has no backup.

- Set `SIGNUPS_ALLOWED=false` once your account exists.
- Back up the `/docker/media/config/vaultwarden` folder: `db.sqlite3`, `attachments/`, and the `rsa_key*` files. Without the RSA keys, every client must log in again. For a safe live copy: `sqlite3 db.sqlite3 ".backup out.db"`.

## Monitoring gaps

What exists: Prometheus scrapes node-exporter every 15 s, Grafana shows it, and Uptime-Kuma pings services. What's missing:

- **Per-container metrics:** add cAdvisor, so you can see which container is eating RAM.
- **Alerts:** swap > 80 %, disk > 85 %, a container unhealthy, a backup older than 26 h. Use Grafana alerting or Uptime-Kuma notifications (Discord/Telegram/email).
- A second `prometheus/prometheus.yml` in the stack folder is unused; delete it to avoid confusion.
