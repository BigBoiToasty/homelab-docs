# Homelab

**Last updated:** 2026-10-04

**What changed:**
- Nightly database dumps (04:40) for Vaultwarden, n8n, Immich and Supabase. The 05:00 VM backup carries them to hddpool. [Details](runbooks/maintenance.md#nightly-app-database-dumps).
- The Immich photos (48 GB) are now the only important data without a second copy. Next step: a disk on the SSD pool for them ([roadmap](roadmap/ROADMAP.md)).
- 2026-10-03: the VM ran out of memory because of Ollama's prompt cache; it's now capped, and Tailscale/SSH have reserved memory. [What happened](services/README.md#2026-10-03-the-vm-ran-out-of-memory).

## Where to find what

| Folder | What's in it | Start here |
|---|---|---|
| [`architecture/`](architecture/README.md) | Hardware, the VM, disks, network maps, reverse-proxy flow, who can reach what, security | [host-and-vm.md](architecture/host-and-vm.md), [networking-and-security.md](architecture/networking-and-security.md) |
| [`services/`](services/README.md) | One page per app stack: what it does, ports, where its data lives, backups | [services/README.md](services/README.md) (overview table) |
| [`runbooks/`](runbooks/README.md) | Step-by-step guides: routine maintenance and disaster recovery | [maintenance.md](runbooks/maintenance.md) |
| [`scripts/`](scripts/README.md) | `audit-homelab.sh` (snapshot for the docs), `add-site.sh` (add a website) | [scripts/README.md](scripts/README.md) |
| [`roadmap/`](roadmap/ROADMAP.md) | To-do list by urgency, wishlist, tech debt | [ROADMAP.md](roadmap/ROADMAP.md) |

## What's running

| Area | Apps | Details |
|---|---|---|
| Photos | Immich | [services/immich.md](services/immich.md) |
| Media & books | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent (through a VPN), Kavita, LazyLibrarian | [services/media.md](services/media.md) |
| Games | Minecraft (Paper), Terraria, Playit tunnels | [services/gaming.md](services/gaming.md) |
| AI & automation | n8n, Ollama (LLM), Stirling-PDF | [services/ai-tools.md](services/ai-tools.md) |
| App backend | Supabase (Postgres, auth, API, storage) | [services/supabase.md](services/supabase.md) |
| Management | Vaultwarden, Homepage, Uptime-Kuma, Dozzle, Prometheus, Grafana | [services/management.md](services/management.md) |
| Websites | Portfolio (public), Mush front-end | [services/web-apps.md](services/web-apps.md) |

## How it fits together

```mermaid
flowchart TB
    subgraph NET["Who connects"]
        PUB["Anyone on the internet"]
        ME["Your devices<br/>(Tailscale on)"]
        LAN["Home network"]
    end

    subgraph EDGE["Ways in"]
        CF["Cloudflare Tunnel"]
        PLAY["Playit.gg"]
        TS["Tailscale"]
    end

    subgraph PVE["Proxmox server · ZFS fastpool (SSD) + hddpool (HDD) · RTX 2060 SUPER"]
        subgraph VM["VM 100 debian-docker · Debian 12 · 4 vCPU · 11 GB RAM"]
            NGINX["nginx-proxy<br/>immich · n8n · pdf · supabase · mush<br/>.example.com"]
            PORT["portfolio site"]
            GAMES["Minecraft · Terraria"]
            APPS["all apps by port<br/>(Jellyfin, Grafana, Vaultwarden, …)"]
        end
    end

    PUB --> CF --> PORT
    PUB --> PLAY --> GAMES
    ME --> TS --> NGINX
    TS --> APPS
    LAN -. "by IP:port" .-> APPS
```

- **Public (internet):** only the portfolio site and the two game servers.
- **Private (Tailscale):** every app. The `*.example.com` names resolve to the server's Tailscale IP, so they only work with Tailscale on.
- **Home network:** can reach apps by `IP:port` without Tailscale.

Details: [architecture/networking-and-security.md](architecture/networking-and-security.md).

## Health snapshot (2026-10-03, after the reboot)

| | Status | Notes |
|---|---|---|
| Containers | 🟢 40/40 running | 0 OOM kills this boot |
| Disk | 🟢 boot 15 %, data 3 % | 502 GB boot + 1.5 TB data disk |
| Memory | 🟡 swap 3.0 / 8 GB, ~2.8 GB RAM available | Ran out on 2026-10-03; Ollama now capped. Watch swap over the next days |
| Backups | 🟠 partial | Nightly VM boot-disk backup (05:00), app database dumps (04:40) and game worlds; **Immich photos have no second copy**; nothing off-site; no test restore yet |
| Public exposure | 🟡 small | Portfolio + game servers (game servers have no whitelist/password) |
| GPU | 🟢 in use | Ollama (5.4 of 8 GB VRAM) and Jellyfin; driver 615 |
| Updates | 🟡 50 OS updates pending | No automatic updates |
| Guest agent | 🟢 on | On in Proxmox and in the VM; CPU type `host` |

## 📌 Current Focus & Roadmap

- 🔴 **In Progress:** Test-restore the VM 100 backup once; watch VM memory after the 2026-10-03 incident.
- 🟠 **Urgent:** Second copy of the Immich photos on fastpool, then off-site; lock the public game servers (whitelist / password).
- 🟡 **Next Up:** Tune Immich background jobs, security quick wins (2FA, `.env` permissions), Stirling-PDF heap-dump cleanup.
- 📋 **Full List:** See [roadmap/ROADMAP.md](roadmap/ROADMAP.md) for detailed task tracking and future architecture plans.

## Keeping these docs current

Run the audit script, save the report **outside** the repo, and update the docs from it. Reports are never committed. How-to: [scripts/README.md](scripts/README.md) and [runbooks/maintenance.md](runbooks/maintenance.md#refresh-these-docs).
