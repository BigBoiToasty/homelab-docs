# AI & automation stack (`ai-tools`): n8n, Ollama, Stirling-PDF

> Compose project `~/docker/ai-tools` · network `server-net` · last verified 2026-10-03.
> **In one line:** n8n runs automations, Ollama runs a local LLM on the GPU, and Stirling-PDF is a web PDF toolbox.

## Containers

| Container | Image | Ports | Memory cap | Data lives in | Notes |
|---|---|---|---|---|---|
| n8n | `docker.n8n.io/n8nio/n8n:latest` | **`0.0.0.0:5678`** | 1 GiB | `/docker/appdata/n8n → /home/node/.n8n` (9 MB) | Owner account set up (login required). Served at `https://n8n.example.com` (tailnet-only). |
| ollama | `ollama/ollama:latest` | 11434 | 3 GiB (since 2026-10-03) | `/docker/appdata/ollama` (4.9 GB) | Model `qwen3:8b` (5.2 GB), 100 % on the GPU. `OLLAMA_KEEP_ALIVE=-1` (model stays loaded), `LLAMA_ARG_CACHE_RAM=1024` (prompt cache capped at 1 GiB). **No authentication** on its API. |
| stirling-pdf | `frooodle/s-pdf:latest` | 8081→8080 | 1 GiB | `/mnt/tank/stirling-pdf/extraConfigs → /configs` | **No login** (`DOCKER_ENABLE_SECURITY=false`). Served at `https://pdf.example.com` (tailnet-only). |

**Who can reach it:** tailnet (by domain name) and LAN (by port). Not the internet.

## n8n

**The workflow:** *Gmail Trigger* (polls every 15 min) → *Ollama* (`qwen3:8b`, temperature 0, JSON output) sorts each email: is it a real update on a job application (confirmation, assessment, interview, rejection) or noise (job alerts, newsletters)? It extracts company, job title and dates, then the result goes to Discord.

**Gmail credential:** it broke around 2026-09-19 ("refresh token expired"), which is why notifications stopped. Reconnected 2026-09-26; n8n's calls to Ollama show up in its log again. If it breaks again after about a week, the Google Cloud OAuth app is still in *Testing* mode, which expires tokens every 7 days. Fix: OAuth consent screen → *Publish app*.

- Backups: nightly since 2026-10-04 ([nightly app dumps](../runbooks/maintenance.md#nightly-app-database-dumps)): `database.sqlite` and `config` are copied to `/root/backups/app-dumps/<date>/`. Everything is in `/docker/appdata/n8n`: `database.sqlite` holds the workflows and `config` holds the encryption key. Without that key, saved credentials can't be decrypted after a restore.
- The port binding regressed from loopback (`127.0.0.1:5678`) to all interfaces. nginx reaches it through the host either way, so set it back to `"127.0.0.1:5678:5678"`.
- Memory: the 1 GiB cap keeps a runaway workflow from starving the game servers. Add `NODE_OPTIONS=--max-old-space-size=768` so Node cleans up memory before the cap kills it.

## Ollama on the GPU

Fixed 2026-09-26. Before that, Ollama ran on the CPU (the old driver 535 was too old for it), and one request took about 5 minutes.

| | Now |
|---|---|
| Driver | NVIDIA 615 from NVIDIA's own apt repo (`cuda-drivers-580` pulls in the newest `nvidia-driver`) |
| Speed | ~63 tokens/s with `qwen3:8b` |
| GPU memory | ~5.4 of 8 GB, held permanently |
| System RAM | ~0.5–1 GB for the `llama-server` process right after a load; its prompt cache can add up to 1 GiB more (see below). Container capped at 3 GiB |
| Keep-alive | `OLLAMA_KEEP_ALIVE=-1` in `~/docker/ai-tools/docker-compose.yml` |
| Prompt cache | `LLAMA_ARG_CACHE_RAM=1024` in the same file |

**Why keep-alive is `-1`:** n8n polls Gmail every 15 minutes. Any keep-alive shorter than that unloads the model between polls, and every run then pays a 10–60 s reload. With the model always loaded, a request is answered almost instantly. The idle GPU still drops to ~15 W.

**When to lower it:** if Immich's machine learning moves to the GPU, a bigger model is added, or the game-streaming plans (phases 3.1/3.3) start using the GPU, set it to about `20m` (just longer than the poll interval) so the 5.4 GB is freed when idle.

After editing the compose file, run `docker compose up -d` in `~/docker/ai-tools`. A plain restart keeps the old settings.

**If Ollama or Jellyfin won't start** with `could not select device driver "nvidia"`: the NVIDIA Container Toolkit is missing. That happened on 2026-09-26: `apt-get purge ... libnvidia-*` also matched `libnvidia-container1` and removed the toolkit with the old driver. Fix: `apt install nvidia-container-toolkit`, `nvidia-ctk runtime configure --runtime=docker`, `systemctl restart docker`.

**Harmless kernel messages when the model loads.** Each time the model loads (for example after a VM reboot), `journalctl -k` shows a burst of `NVRM: ... Out of memory [NV_ERR_NO_MEMORY]` and `Allocation failed with big page size, retrying with default page size`. The driver couldn't get one large block of system RAM, retried with small pages and succeeded; `ollama ps` still shows `100% GPU`. Seen 2026-09-27 13:15, together with ~1 GB of cold pages moving to swap while the 5.4 GB model file was read. They are not OOM kills (`grep oom_kill /proc/vmstat` stays 0).

### Why Ollama used system RAM although the model is on the GPU (fixed 2026-10-03)

Ollama runs the model through a bundled `llama-server` (llama.cpp). That server keeps a **prompt cache in system RAM** so repeated prompts are answered faster. Its default size is 8192 MiB (`llama-server --help`, option `--cache-ram`), and Ollama doesn't change it. On an 11 GB VM that is most of the memory.

With keep-alive `-1` the process never restarts, so the cache only grows. Each n8n run adds to it. Measured in the kernel's OOM reports:

| Date | `llama-server` in RAM | in swap | What happened |
|---|---|---|---|
| 2026-09-30 11:04 | 3.3 GB | 3.5 GB | Kernel killed `llama-server` |
| 2026-10-03 19:38 | 2.8 GB | 2.7 GB | VM ran out of RAM and swap; see [the incident](README.md#2026-10-03-the-vm-ran-out-of-memory) |
| After the reboot | 0.24 GB | 0 | Cache empty again |

**Fix (2026-10-03),** in the `ollama` service of `~/docker/ai-tools/docker-compose.yml`:

```yaml
    environment:
      - OLLAMA_KEEP_ALIVE=-1
      - LLAMA_ARG_CACHE_RAM=1024   # prompt cache max 1 GiB (0 = off)
    deploy:
      resources:
        limits:
          memory: 3G               # backstop: only Ollama restarts if it ever grows anyway
```

`LLAMA_ARG_CACHE_RAM` is the environment form of `--cache-ram`. Ollama passes its environment on to `llama-server`; check with `tr '\0' '\n' < /proc/<llama-server pid>/environ | grep LLAMA_ARG`. After the change: model still `100% GPU`, container at ~1 GiB of its 3 GiB.

Remember: `docker restart ollama` does **not** apply compose changes. Use `docker compose up -d ollama`.

Still open: `OLLAMA_MAX_LOADED_MODELS=1`.

## Stirling-PDF heap dumps (cleared)

The earlier docs called the 7.6 GB under `/mnt/tank/stirling-pdf` OCR training data. It isn't: `trainingData` is empty. The space is **33 Java heap dumps (~248 MB each)** written 2026-09-12 → 09-14. Each dump means Stirling ran out of heap memory, crashed and restarted. The default heap is ~256 MiB (a quarter of the 1 GiB cap), and that proved too small. No new dumps have appeared since 2026-09-14. **By 2026-10-04 the folder was empty** (all of `/mnt/tank/stirling-pdf` is under 1 MB), most likely cleared when the container was updated or recreated.

| | Intended | Actual |
|---|---|---|
| Container limit | 512 MiB | 1 GiB |
| Java heap | `-Xms64m -Xmx256m` | image default (~256 MiB); heap dumps **off** since 2026-10-04 |
| State | running | running, healthy, ~370 MiB |

Done 2026-10-04: `JAVA_CUSTOM_OPTS=-XX:-HeapDumpOnOutOfMemoryError` in the compose file. The image turns dumps on in `_JVM_OPTS`; its start script appends `JAVA_CUSTOM_OPTS` afterwards, and Java uses the last value, so dumps are off (checked in the running process). Stirling still exits and restarts on an out-of-memory error (`ExitOnOutOfMemoryError`), it just no longer leaves a 250 MB file each time.

Optional, not done: raise the heap with `-Xmx512m` in the same variable if crashes come back (the 1 GiB cap leaves room), and add `stop_grace_period: 30s`.

Because Stirling has no login, anyone on the tailnet or LAN can use it. That's fine while you're the only user.

## Backups

Only n8n matters here (see above). Ollama models and Stirling data can be downloaded again.
