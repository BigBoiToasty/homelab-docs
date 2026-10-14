# Management & monitoring stack (`management`)

> Compose project `~/docker/management` · network `server-net` · last verified 2026-10-13.
> **In one line:** Vaultwarden (password manager), Homepage (dashboard), Uptime-Kuma (up/down checks), Dozzle (container logs) and Prometheus + Grafana (metrics). Problems are posted to a Discord channel (`#homelab`) by Uptime-Kuma and by a server-health script.

## Containers

| Container | Image | Port | Data lives in | Notes |
|---|---|---|---|---|
| vaultwarden | `vaultwarden/server:latest` | 8222→80 | `/docker/media/config/vaultwarden` | Served at `https://vaultwarden.example.com` (tailnet-only). Sign-ups **off** since 2026-09-25. **No backup.** |
| homepage | `ghcr.io/gethomepage/homepage:latest` | 3000 | `/docker/media/config/homepage` | Mounts the Docker socket **read-write**; read-only is enough |
| uptime-kuma | `louislam/uptime-kuma:1` | 3001 | `/docker/media/uptime-kuma` | 22 monitors, alerts to Discord `#homelab` ([below](#monitoring-and-alerts)) |
| dozzle | `amir20/dozzle:latest` | 8888→8080 | Docker socket (read-only) | Live container logs |
| prometheus | `prom/prometheus:latest` | 9090 | volume `monitoring_prometheus_data`; config `~/docker/management/prometheus.yml` | One scrape job: `node-exporter` |
| node_exporter | `prom/node-exporter:latest` | internal 9100 | reads `/` read-only | VM CPU/RAM/disk metrics |
| grafana | `grafana/grafana:latest` | 3005→3000 | volume `monitoring_grafana_data` | Dashboards |

**Who can reach it:** LAN + tailnet by port; Vaultwarden also by name over Tailscale. None are on the internet.

## Vaultwarden

Served at `https://vaultwarden.example.com` (tailnet-only); sign-ups are off. The vault was restored on 2026-09-25 after the 2026-09-08 data-path reset ([incident log](../runbooks/incident-log.md)).

**Clients** (browser extension, phone app) must use `https://vaultwarden.example.com`. The older `https://<vm>.<tailnet>.ts.net` address came from Tailscale Serve, which is no longer configured; a client still pointing there fails with "failed to fetch" (fixed on the laptop 2026-10-13).

This is the highest-value data in the stack. `db.sqlite3` and `rsa_key.pem` are dumped nightly ([app dumps](../runbooks/maintenance.md#nightly-app-database-dumps)); without the RSA key every client must log in again.

## Monitoring and alerts

Two sources post to the Discord channel `#homelab`. Both reach Discord over the normal internet connection, so they still work when Tailscale is down.

**Uptime-Kuma** (`http://<tailscale-ip>:3001`): "does this service answer?" A service must fail 2 checks in a row before it alerts, and Kuma posts again when it recovers.

| Group | Monitors | Every |
|---|---|---|
| Public | portfolio (keyword check), Mush, Mush's Supabase API (401 counts as up) | 1 min |
| Private apps | Vaultwarden, Immich, n8n, Supabase Studio (401 = up), Stirling-PDF | 2 min |
| Games | Minecraft and Terraria (TCP port) | 2 min |
| Host | Proxmox web UI over Tailscale | 1 min |
| Media | Jellyfin, Sonarr, Radarr, Prowlarr, Kavita, LazyLibrarian; qBittorrent is paused while the VPN is down | 5 min |
| Infrastructure | Ollama, Homepage, Grafana, Dozzle | 5 min |

**Server-health script** (`/usr/local/bin/homelab-alerts.py`, `homelab-alerts.timer`, every 5 min): what Kuma can't see. It posts once when a problem starts, a daily reminder while it lasts, and once when it clears.

- Disk ≥ 85 % (🔴 at 90 %) on `/`, `/mnt/tank`, `/mnt/photo-copy`.
- Memory < 8 % available for 10 min; swap > 80 %.
- A container unhealthy, restarting, or stopped. Gluetun gets its own message ("Mullvad probably expired").
- Any failed systemd unit.
- Backups: no new Terraria tar or app dump in 26 h; the Immich photo copy log not reporting `OK`.
- Tailscale down on the VM, the watchdog having restarted it, the Proxmox host offline on the tailnet, or a key expiring within 14 days.
- **Silencing:** add the alert's key (e.g. `container:gluetun`) to `/etc/homelab-alerts/silence`. State lives in `/var/lib/homelab-alerts/state.json`. Test with `homelab-alerts.py --dry-run`.

The webhook URL is in Vaultwarden, copied to a root-only file under `~/docker/management/secrets/`.

**Gaps:**

- **The server going down entirely is not detected:** a power cut, an internet outage or a frozen VM takes Kuma and the script down with it. An outside "dead man's switch" (e.g. Healthchecks.io) would cover this; not set up.
- **Proxmox host:** its own 05:00 backup isn't checked; the VM can't see it.
- **Per-container metrics:** add cAdvisor, so you can see which container is eating RAM.
- A second `prometheus/prometheus.yml` in the stack folder is unused; delete it to avoid confusion.
