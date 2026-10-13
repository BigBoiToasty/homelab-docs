# Web apps: Mush and portfolio

> Last verified 2026-09-25.
> **In one line:** two static websites served by small nginx containers. Both are public through the Cloudflare Tunnel (Mush since 2026-10-11).

| Container | Compose project | Image | Port | Serves | Who can reach it |
|---|---|---|---|---|---|
| mush-frontend | `~/Mush` | `nginx:alpine` | 8085→80 | `~/Mush/dist` (React build) with `~/Mush/nginx.conf` | **Internet:** `https://mush.example.com` via Cloudflare Tunnel (Supabase API is its backend) |
| portfolio-web | `~/docker/portfolio` | `nginx:alpine` | 8090→80 | `~/docker/portfolio/repo/dist` | **Internet:** apex `https://example.com` via Cloudflare Tunnel |
| portfolio-build | `~/docker/portfolio` | `node:20-alpine` | — | one-shot build that produces `repo/dist` | — |

Mush is a PWA that caches itself. After a DNS or backend change, a phone can keep the old copy and old DNS answer (empty card slots, no Turnstile box): toggle airplane mode and clear the site's data, or test in a private tab (2026-10-11).

## Updating

**The portfolio updates itself** (since 2026-09-29). Every 5 minutes root's cron runs `/usr/local/bin/portfolio-update.sh`. When GitHub's `main` has a new commit, it resets `~/docker/portfolio/repo` to match GitHub exactly and runs the build container. nginx serves `repo/dist` directly, so no restart is needed. A push is live within ~5 minutes; the build takes seconds, and the site may show errors while it runs.

- **GitHub is the source of truth.** Edits made directly in `~/docker/portfolio/repo` are overwritten on the next update. Change the site on GitHub (or push from your PC).
- **A failed build rolls back** to the previous commit. The failed commit is saved in `~/docker/portfolio/.last-failed-commit` and skipped until the next push.
- **Log:** `tail /var/log/portfolio-update.log`. Update now instead of waiting: run `/usr/local/bin/portfolio-update.sh`.
- The repo is public, so fetching needs no login. The server can't push.
- `reference/` in the repo holds design references (including an old resume copy); only `public/` ends up on the site.

**Mush updates itself too** (since 2026-10-12). Every 5 minutes root's cron runs `/usr/local/bin/mush-update.sh`. When GitHub's `main` has a new commit, it builds it in its own checkout (`~/docker/mush-deploy/repo`), runs the tests, builds into a separate folder, and only then updates `~/Mush/dist` (new code files first, then the page). Merging into `main` is the deploy; work in progress belongs on a branch.

- **A failed test or build leaves the live site untouched.** The commit is saved in `~/docker/mush-deploy/.last-failed-commit` and skipped until the next push.
- **The previous build's code files are kept**, so tabs open during a deploy keep working. The outgoing build is copied to `~/docker/mush-deploy/previous/`.
- **Rollback:** revert the commit on GitHub (the next run deploys it), or right away: `rsync -a --delete ~/docker/mush-deploy/previous/ ~/Mush/dist/`.
- **Site settings** (Supabase address, public anon key, Turnstile site key) are in `~/docker/mush-deploy/.env.production`, not in GitHub. A laptop needs its own copy to run Mush locally. `VITE_GOOGLE_SIGNIN=true` shows the Google button once Google sign-in is set up.
- **Log:** `tail /var/log/mush-update.log`. Update now: run `/usr/local/bin/mush-update.sh`.
- **`~/Mush`** is a working copy for branches (the server pushes with a Mush-only deploy key). `docker-compose.yml` and `nginx.conf` there are server files, not in GitHub.
- **Old Vercel copy:** the Vercel project still builds from GitHub, but `vercel.json` makes it serve only a self-removing `sw.js` (clears the old offline app from browsers that used the Vercel copy) and redirect (308) every other path to the own domain. Delete it once search results show the own domain.
- **Caching** (`~/Mush/nginx.conf`): build files in `/assets/` are kept a year (their names change every build), the page and the app's update files are always re-checked, textures and the icon a week.

Manual commands:

```bash
# Mush (normally not needed: see above)
/usr/local/bin/mush-update.sh
# Portfolio (the build container runs once, then the web container serves the result)
cd ~/docker/portfolio && docker compose up -d
```

## Backups

Nothing to back up here beyond the source code: both sites are built from their repos. Make sure those repos are pushed somewhere off the server. Mush's real data lives in [Supabase](supabase.md).

## Risk

The portfolio is static files behind Cloudflare, so there's little to attack. Keep the `nginx:alpine` image updated (`docker compose pull && docker compose up -d`) since it faces the internet.
