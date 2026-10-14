# AI & automation stack (`ai-tools`): n8n, Ollama, Stirling-PDF

> Compose project `~/docker/ai-tools` · network `server-net` · last verified 2026-10-13.
> **In one line:** n8n runs automations, Ollama runs a local LLM on the GPU, and Stirling-PDF is a web PDF toolbox.

## Containers

| Container | Image | Ports | Memory cap | Data lives in | Notes |
|---|---|---|---|---|---|
| n8n | `docker.n8n.io/n8nio/n8n:latest` | **`0.0.0.0:5678`** | 1 GiB | `/docker/appdata/n8n → /home/node/.n8n` (9 MB) | Owner account set up (login required). Served at `https://n8n.example.com` (tailnet-only). |
| ollama | `ollama/ollama:latest` | 11434 | 3 GiB (since 2026-10-03) | `/docker/appdata/ollama` (4.9 GB) | Model `qwen3:8b` (5.2 GB), 100 % on the GPU. `OLLAMA_KEEP_ALIVE=-1` (model stays loaded), `LLAMA_ARG_CACHE_RAM=1024` (prompt cache capped at 1 GiB). **No authentication** on its API. |
| stirling-pdf | `frooodle/s-pdf:latest` | 8081→8080 | 1 GiB | `/mnt/tank/stirling-pdf/extraConfigs → /configs` | **No login** (`DOCKER_ENABLE_SECURITY=false`). Served at `https://pdf.example.com` (tailnet-only). |

**Who can reach it:** tailnet (by domain name) and LAN (by port). Not the internet.

## n8n

**The workflow ("My workflow"):**

1. *Gmail Trigger* polls every 15 min, with Simplify off, so the full message is available.
2. *Ollama* (`qwen3:8b`, temperature 0, JSON output, `num_ctx` 8192) reads the **full email body** (first 6,000 characters). It decides whether the email is a real update on a job application (confirmation, assessment, interview, rejection) or noise (job alerts, newsletters), and extracts company, job title and dates.
   - The rules are in the system message and the email in the user message.
   - A consistency rule says any confirmation, assessment, interview or rejection is "useful".
3. *Filter* passes anything marked useful or carrying one of those four categories.
4. *Discord* posts a card to `#jobs`. It shows the company and role, the email's own date, a deadline if there is one, a one-line summary, and an "Open email" link. The link is `https://mail.google.com/mail/?authuser=<account>#all/<thread id>`, wrapped in `<>` so Discord shows no preview.
5. *Run email sync* calls the email-sync listener ([below](#job-application-automation)), which updates the job tracker and the applied-jobs sheet. It runs once per poll and on error continues, so a failure never blocks the Discord post.

- **Before 2026-10-13** the model only saw Gmail's ~200-character preview, so it often called rejections "confirmations".
- **Editing it:** an n8n API key (Settings → n8n API) is in Vaultwarden, copied to a root-only file under `~/docker/management/secrets/`.
- **Backups:** older workflow versions are saved as JSON in `config-backups/`.
- **Testing:** the Gmail trigger can't be fired through the API. Test with a temporary copy whose first node is a webhook (same nodes and credentials), then delete it.

**Gmail credential:** it broke around 2026-09-19 ("refresh token expired"), which is why notifications stopped. Reconnected 2026-09-26; n8n's calls to Ollama show up in its log again. If it breaks again after about a week, the Google Cloud OAuth app is still in *Testing* mode, which expires tokens every 7 days. Fix: OAuth consent screen → *Publish app*.

- Backups: dumped nightly ([app dumps](../runbooks/maintenance.md#nightly-app-database-dumps)). Everything is in `/docker/appdata/n8n`: `database.sqlite` holds the workflows and `config` holds the encryption key. Without that key, saved credentials can't be decrypted after a restore.
- The port binding regressed from loopback (`127.0.0.1:5678`) to all interfaces. nginx reaches it through the host either way, so set it back to `"127.0.0.1:5678:5678"`.
- Memory: the 1 GiB cap keeps a runaway workflow from starving the game servers. Add `NODE_OPTIONS=--max-old-space-size=768` so Node cleans up memory before the cap kills it.

## Ollama on the GPU

| | Now |
|---|---|
| Driver | NVIDIA 615 from NVIDIA's own apt repo (`cuda-drivers-580` pulls in the newest `nvidia-driver`) |
| Speed | ~63 tokens/s with `qwen3:8b` |
| GPU memory | ~5.4 of 8 GB, held permanently |
| System RAM | ~0.5–1 GB for the `llama-server` process right after a load; its prompt cache can add up to 1 GiB more (see below). Container capped at 3 GiB |
| Keep-alive | `OLLAMA_KEEP_ALIVE=-1` in `~/docker/ai-tools/docker-compose.yml` |
| Prompt cache | `LLAMA_ARG_CACHE_RAM=1024` in the same file |

**Why keep-alive is `-1`:** n8n polls Gmail every 15 minutes. Any keep-alive shorter than that unloads the model between polls, and every run then pays a 10–60 s reload. With the model always loaded, a request is answered almost instantly. The idle GPU still drops to ~15 W.

After editing the compose file, run `docker compose up -d` in `~/docker/ai-tools`. A plain restart keeps the old settings.

**If Ollama or Jellyfin won't start** with `could not select device driver "nvidia"`: the NVIDIA Container Toolkit is missing; see the 2026-09-26 entry in the [incident log](../runbooks/incident-log.md).

**Harmless kernel messages when the model loads.** Each time the model loads (for example after a VM reboot), `journalctl -k` shows a burst of `NVRM: ... Out of memory [NV_ERR_NO_MEMORY]` and `Allocation failed with big page size, retrying with default page size`. The driver couldn't get one large block of system RAM, retried with small pages and succeeded; `ollama ps` still shows `100% GPU`. Seen 2026-09-27 13:15, together with ~1 GB of cold pages moving to swap while the 5.4 GB model file was read. They are not OOM kills (`grep oom_kill /proc/vmstat` stays 0).

### Ollama prompt cache

Ollama's `llama-server` keeps a prompt cache in **system RAM** (default up to 8 GiB) even though the model is on the GPU. With keep-alive `-1` it only grows; on 2026-10-03 it reached ~5.5 GB and filled the VM. Since then `LLAMA_ARG_CACHE_RAM=1024` caps the cache at 1 GiB and the container has a 3 GiB limit. A plain `docker restart` doesn't apply compose changes; use `docker compose up -d ollama`.

Still open: `OLLAMA_MAX_LOADED_MODELS=1`.

## Job-application automation

The tools themselves live in career-ops, which is private and not in this repo; its `local-automation.md` is the guide. This section covers only what runs on the homelab.

| Piece | Where | What |
|---|---|---|
| Qwen3.6-35B-A3B (Q4_K_M) | the desktop (LM Studio, RX 9070 XT), over Tailscale | Reads and scores job postings, ~10–30 s each. The desktop's Windows sleep is set to Never when plugged in, so long runs aren't cut off; `desktop-llm sleep` puts it to sleep afterwards. |
| `email-sync-listener.service` | VM, `/usr/local/bin/email-sync-listener.py` | Listens only on the `server-net` gateway (`172.22.0.1:8765`), with a token (stored in n8n as a Header Auth credential). On a ping it waits 30 s, then runs career-ops' `email-sync.mjs`. |
| `email-sync.mjs` | career-ops | Rejection → tracker *Rejected* and sheet *Rejected*; online assessment → *Responded* and *Online Assessment*; interview → *Interview*; confirmation → *Applied*, or a new sheet row if the company is missing. It changes only exact single matches and lists the rest. It reports to Discord `#job-agent`. |
| Applied-jobs Google Sheet | Google | A service account (key in Vaultwarden) with Editor on that one sheet. To allow creating its key, the Google Cloud organization policies `iam.disableServiceAccountKeyCreation` and `iam.managed.disableServiceAccountKeyCreation` were turned off. Turning them back on keeps the existing key working. |
| Agent Chrome | VM, Xvfb `:98`, noVNC screen 2 (`:3011`) | Auto-fills Workday forms (it never submits), and reads jobright.ai and pages that block headless browsers. Signed in to Jobright. |

**Discord channels:** `#jobs` (n8n email cards), `#job-agent` (the agent's messages: summaries, what's ready to submit), `#homelab` (server alerts; see [management](management.md#monitoring-and-alerts)).

**Ollama callers:** `qwen3:8b` "thinks" before answering unless the request sets `think: false`, which roughly doubles the time. career-ops' batch classifier sets it.

## Stirling-PDF memory

1 GiB container limit, default Java heap (~256 MiB), heap dumps turned off (`JAVA_CUSTOM_OPTS=-XX:-HeapDumpOnOutOfMemoryError`). History: [incident log](../runbooks/incident-log.md).

## Backups

Only n8n matters here (see above). Ollama models and Stirling data can be downloaded again.
