# Web apps: Mush and portfolio

> Last verified 2026-09-25.
> **In one line:** two static websites served by small nginx containers. Both are public through the Cloudflare Tunnel (Mush since 2026-10-11).

| Container | Compose project | Image | Port | Serves | Who can reach it |
|---|---|---|---|---|---|
| mush-frontend | `~/Mush` | `nginx:alpine` | 8085→80 | `~/Mush/dist` (React build) with `~/Mush/nginx.conf` | **Internet:** `https://mush.example.com` via Cloudflare Tunnel (Supabase API is its backend) |
| portfolio-web | `~/docker/portfolio` | `nginx:alpine` | 8090→80 | `~/docker/portfolio/repo/dist` | **Internet:** apex `https://example.com` via Cloudflare Tunnel |
| portfolio-build | `~/docker/portfolio` | `node:20-alpine` | — | one-shot build that produces `repo/dist` | — |

## Updating

**The portfolio updates itself** (since 2026-09-29). Every 5 minutes root's cron runs `/usr/local/bin/portfolio-update.sh`. When GitHub's `main` has a new commit, it resets `~/docker/portfolio/repo` to match GitHub exactly and runs the build container. nginx serves `repo/dist` directly, so no restart is needed. A push is live within ~5 minutes; the build takes seconds, and the site may show errors while it runs.

- **GitHub is the source of truth.** Edits made directly in `~/docker/portfolio/repo` are overwritten on the next update. Change the site on GitHub (or push from your PC).
- **A failed build rolls back** to the previous commit. The failed commit is saved in `~/docker/portfolio/.last-failed-commit` and skipped until the next push.
- **Log:** `tail /var/log/portfolio-update.log`. Update now instead of waiting: run `/usr/local/bin/portfolio-update.sh`.
- The repo is public, so fetching needs no login. The server can't push.
- `reference/` in the repo holds design references (including an old resume copy); only `public/` ends up on the site.

Manual commands:

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
