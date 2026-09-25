# Web apps: Mush and portfolio

> Last verified 2026-09-25.
> **In one line:** two static websites served by small nginx containers. The portfolio is the **only public website** (through the Cloudflare Tunnel); Mush is tailnet-only.

| Container | Compose project | Image | Port | Serves | Who can reach it |
|---|---|---|---|---|---|
| mush-frontend | `~/Mush` | `nginx:alpine` | 8085→80 | `~/Mush/dist` (React build) with `~/Mush/nginx.conf` | `https://mush.example.com` for the tailnet (Supabase is its backend) |
| portfolio-web | `~/docker/portfolio` | `nginx:alpine` | 8090→80 | `~/docker/portfolio/repo/dist` | **Internet:** apex `https://example.com` via Cloudflare Tunnel |
| portfolio-build | `~/docker/portfolio` | `node:20-alpine` | — | one-shot build that produces `repo/dist` | — |

## Updating

```bash
# Mush
cd ~/Mush && npm ci && npm run build && docker compose up -d
# Portfolio (the build container runs once, then the web container serves the result)
cd ~/docker/portfolio && docker compose up -d
```

## Backups

Nothing to back up here beyond the source code: both sites are built from their repos. Make sure those repos are pushed somewhere off the server. Mush's real data lives in [Supabase](supabase.md).

## Risk

The portfolio is static files behind Cloudflare, so there's little to attack. Keep the `nginx:alpine` image updated (`docker compose pull && docker compose up -d`) since it faces the internet.
