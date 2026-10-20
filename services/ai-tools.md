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

1. *Gmail Trigger*: polls every 15 min (Simplify off, so the full message is available).
2. *Ollama*: `qwen3:8b`, temperature 0, JSON, `num_ctx` 8192. Reads the first 6,000 characters of the body. It classifies the email as confirmation, assessment, interview, rejection or noise, and extracts company, role and dates.
3. *Filter*: passes useful emails and anything in those four categories.
4. *Discord*: a card in `#jobs` with company, role, date, deadline, a summary and an "Open email" link (`https://mail.google.com/mail/?authuser=<account>#all/<thread id>`, wrapped in `<>` so Discord shows no preview).
5. *Run email sync*: pings the [email-sync listener](#job-application-automation) once per poll; a failure doesn't block the Discord post.

- API key for edits: in Vaultwarden, copied under `~/docker/management/secrets/`. Old versions of the workflow are in `config-backups/`.
- The Gmail trigger can't be fired through the API. To test, use a temporary copy that starts with a webhook node, then delete it.

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

The tools live in career-ops (private; guide: `local-automation.md`). What runs on the homelab:

| Piece | Where | What |
|---|---|---|
| Qwen3.6-35B-A3B | desktop (LM Studio, RX 9070 XT), via Tailscale | Scores job postings. Windows sleep is set to Never when plugged in; `desktop-llm sleep` after runs. |
| `email-sync-listener.service` | VM, `/usr/local/bin/email-sync-listener.py` | Listens on `172.22.0.1:8765` (the `server-net` gateway) and needs a token (an n8n Header Auth credential). On a ping it runs career-ops' `email-sync.mjs`. |
| `email-sync.mjs` | career-ops | Applies email verdicts to the job tracker and the applied-jobs sheet (rejection, online assessment, interview, confirmation). It changes only unambiguous matches and reports to `#job-agent`. |
| Applied-jobs sheet | Google | A service account with Editor access on that one sheet; its key is in Vaultwarden. Creating the key needed the org policies `iam.disableServiceAccountKeyCreation` and `iam.managed.disableServiceAccountKeyCreation` turned off. |
| `oa-reminder.timer` | VM, daily 12:00 | Posts open online assessments to `#job-agent`. |
| Agent Chrome | VM, Xvfb `:98`, noVNC screen 2 (`:3011`) | Auto-fills Workday (never submits) and reads jobright.ai. |

Discord channels: `#jobs` (n8n cards), `#job-agent` (the agent's messages), `#homelab` ([server alerts](management.md#monitoring-and-alerts)).

`qwen3:8b` thinks before answering unless a request sets `think: false`, which takes about twice as long.

## Stirling-PDF memory

1 GiB container limit, default Java heap (~256 MiB), heap dumps turned off (`JAVA_CUSTOM_OPTS=-XX:-HeapDumpOnOutOfMemoryError`). History: [incident log](../runbooks/incident-log.md).

## Interview coach

Compose project `~/docker/interview-coach` (added 2026-10-18). A tailnet-only site at `https://career.example.com` (the old `interview.` name redirects) with three pages that share one stylesheet and top bar: `/interview` (pick a company, then practice its questions on camera and get graded on how you speak), `/coding` (coding problems per company you're interviewing with) and `/pipeline` (the career-ops unapplied-pipeline page; the file is mounted live). systemd `career-pipeline.path` reruns `gen-unapplied.mjs` a minute after the tracker (`data/applications.md`) changes, and `career-pipeline.timer` reruns it daily at 06:30 for edits made directly in the Google Sheet. Logs: `journalctl -u career-pipeline.service`.

| Container | Does | Memory cap | Notes |
|---|---|---|---|
| interview-whisper | Speech-to-text (faster-whisper `large-v3-turbo`, int8 on the GPU) with word timestamps | 3 GiB | Loads on first use (~1.2 GB GPU memory, ~2.7 GB RAM) and, after 5 idle minutes, **exits** so Docker restarts a ~45 MB idle process (unloading alone kept ~4 GB in RAM and swap; seen 2026-10-19 with swap at 81%). First answer after a break takes 10–20 s longer. Falls back to CPU `small.en` if the GPU is full. Model cache: `/docker/appdata/interview-coach/models` |
| interview-coach | Page + grading API (`node:22-alpine`, no dependencies) | 256 MiB | Listens on `172.17.0.1:8790` only. Saves attempts to `/docker/appdata/interview-coach/data/sessions.jsonl` |

- **How grading works:** the browser measures pitch variation, loudness and sentence-end fade. Video never leaves the browser; only the audio is uploaded. Whisper returns words with timings, the coach computes pace, pauses and fillers, and Qwen on the desktop (LM Studio, `qwen/qwen3.6-35b-a3b`) grades story, structure, cadence and tone, then writes a stronger answer using only facts from `cv.md`.
- **Playback:** each graded answer's audio is kept in `/docker/appdata/interview-coach/data/audio/<id>.webm`. The result shows a waveform with Qwen's timestamped "did well"/"to fix" moments, ticks for fillers and long pauses, and a transcript that highlights as it plays (click a word or marker to jump). History rows expand into a replay viewer. A low-res replay video (426×320, 12 fps, VP9 ~200 kbps, about 2–3 MB per 90 s answer) is saved to `data/video/`; the coach keeps at most 500 MB of videos and deletes the oldest past that.
- **Needs the desktop on:** with LM Studio down, the page shows "Qwen offline" and grading fails; `desktop-llm up` loads the model.
- **Questions:** one file per company in `/docker/appdata/interview-coach/data/questions/` (seeded once from `app/questions/`). Add, edit or delete questions from the page, or use "Suggest questions for me" (Qwen writes them from what you want to practise, tailored to the company and `cv.md`); or drop in a new company file. No restart needed. The company list also marks companies whose tracker row is at Interview or Offer stage.
- **Rounds:** each question can carry `round: behavioral|technical`; the page has a Behavioral/Technical toggle above the list (questions without one fall back by type: Technical → technical, the rest → behavioral). The add/edit form sets it.
- **Coding practice:** one file per company in `/docker/appdata/interview-coach/data/coding/` (seeded once per file from `app/coding/`), listing problems candidates reported from that company's technical rounds plus core patterns, each with a LeetCode link, difficulty, source and a short approach. Ticking a problem saves the date in that file. Companies at Interview stage without a file are listed so one can be researched. **Talk-through practice** (`/coding/<company>/<problem>`): a plain code editor (Tab indents, a 15-minute timer) and the mic. The page saves code snapshots every 3 s while recording; Whisper transcribes the audio, and Qwen grades it like a live technical round: clarifying, brute force → optimal, complexity, talking while coding (silences of 15 s+ are flagged), correctness, code quality, testing, time. It also reviews the code (not run) and writes how a strong walkthrough would sound. The replay plays the audio with the code and transcript following along. Attempts: `data/coding-sessions.jsonl` + `data/audio/<id>.webm`. If the desktop is off, the attempt is still saved and can be re-graded later. A pasted problem statement is saved in the company's coding file.
- **Grading structure** depends on the question type: STAR for behavioral, present→past→future for the intro, and so on (`SHAPE` in `app/server.mjs`).

## Backups

Only n8n matters here (see above). Ollama models and Stirling data can be downloaded again.
